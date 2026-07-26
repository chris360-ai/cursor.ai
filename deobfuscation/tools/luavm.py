"""A Lua 5.1 interpreter in Python, good enough to run obfuscator bootstraps.

Strings are Python `str` objects whose characters are all in U+0000..U+00FF
(i.e. latin-1 byte semantics).  Numbers are Python ints when exact and floats
otherwise; Lua 5.1 uses doubles throughout but every value this code sees stays
well inside 2**53, so int arithmetic is both exact and faster.
"""
import math, sys, time
from luaparse import parse

# ---------------------------------------------------------------- values


class LuaError(Exception):
    def __init__(self, value, traceback_=None):
        Exception.__init__(self, value)
        self.value = value
        self.lua_tb = traceback_


class Table:
    __slots__ = ('arr', 'hash', 'mt', '_keys', '_keypos')

    def __init__(self, arr=None, hash=None):
        self.arr = arr if arr is not None else []
        self.hash = hash if hash is not None else {}
        self.mt = None
        self._keys = None
        self._keypos = None

    # -- key normalisation: 2.0 and 2 are the same key in Lua
    @staticmethod
    def norm(k):
        if type(k) is float and k.is_integer() and abs(k) < 2**63:
            return int(k)
        return k

    def get(self, k):
        k = Table.norm(k)
        if type(k) is int:
            a = self.arr
            if 1 <= k <= len(a):
                return a[k - 1]
        return self.hash.get(k)

    def set(self, k, v):
        k = Table.norm(k)
        if type(k) is int:
            a = self.arr
            n = len(a)
            if 1 <= k <= n:
                a[k - 1] = v
                if v is None and k == n:
                    while a and a[-1] is None:
                        a.pop()
                    self._keys = None
                return
            if k == n + 1:
                if v is None:
                    if k in self.hash:
                        del self.hash[k]
                        self._keys = None
                    return
                a.append(v)
                h = self.hash
                j = n + 2
                while j in h:
                    a.append(h.pop(j))
                    j += 1
                self._keys = None
                return
        if v is None:
            if k in self.hash:
                del self.hash[k]
                self._keys = None
        else:
            if k not in self.hash:
                self._keys = None
            self.hash[k] = v

    def length(self):
        return len(self.arr)

    def keylist(self):
        if self._keys is None:
            ks = [i + 1 for i, v in enumerate(self.arr) if v is not None]
            ks.extend(self.hash.keys())
            self._keys = ks
            self._keypos = {k: i for i, k in enumerate(ks)}
        return self._keys

    def nextkey(self, k):
        ks = self.keylist()
        if k is None:
            i = 0
        else:
            k = Table.norm(k)
            p = self._keypos.get(k)
            if p is None:
                raise LuaError("invalid key to 'next'")
            i = p + 1
        while i < len(ks):
            key = ks[i]
            v = self.get(key)
            if v is not None:
                return key, v
            i += 1
        return None


class Userdata:
    __slots__ = ('mt', 'name')

    def __init__(self, name='userdata'):
        self.mt = None
        self.name = name


class LuaFunction:
    __slots__ = ('params', 'vararg', 'body', 'scope', 'env', 'name')

    def __init__(self, params, vararg, body, scope, env, name='?'):
        self.params = params
        self.vararg = vararg
        self.body = body
        self.scope = scope
        self.env = env
        self.name = name


class Builtin:
    __slots__ = ('fn', 'name')

    def __init__(self, fn, name):
        self.fn = fn
        self.name = name


class Scope:
    __slots__ = ('v', 'parent')

    def __init__(self, parent=None):
        self.v = {}
        self.parent = parent


# ---------------------------------------------------------------- helpers

def fmtnum(v):
    if type(v) is int:
        return str(v)
    if v != v:
        return 'nan'
    if v == math.inf:
        return 'inf'
    if v == -math.inf:
        return '-inf'
    if float(v).is_integer() and abs(v) < 1e15:
        return str(int(v))
    s = '%.14g' % v
    return s


def type_name(v):
    if v is None:
        return 'nil'
    t = type(v)
    if t is bool:
        return 'boolean'
    if t is int or t is float:
        return 'number'
    if t is str:
        return 'string'
    if t is Table:
        return 'table'
    if t is LuaFunction or t is Builtin:
        return 'function'
    if t is Userdata:
        return 'userdata'
    if t is Coroutine:
        return 'thread'
    return 'userdata'


def tostr(I, v):
    t = type(v)
    if v is None:
        return 'nil'
    if t is bool:
        return 'true' if v else 'false'
    if t is int or t is float:
        return fmtnum(v)
    if t is str:
        return v
    mt = I.getmeta(v)
    if mt is not None:
        h = mt.get('__tostring')
        if h is not None:
            return I.call(h, [v])[0]
        nm = mt.get('__name')
        if isinstance(nm, str):
            return '%s: 0x%08x' % (nm, id(v) & 0xffffffff)
    return '%s: 0x%08x' % (type_name(v), id(v) & 0xffffffff)


def tonum(v, base=None):
    if base is not None:
        base = int(base)
        if not isinstance(v, str):
            return None
        try:
            return int(v.strip(), base)
        except ValueError:
            return None
    t = type(v)
    if t is int or t is float:
        return v
    if t is str:
        s = v.strip()
        try:
            if s[:2].lower() in ('0x', '-0') and 'x' in s.lower():
                return int(s, 16)
            if '.' in s or 'e' in s.lower() or 'inf' in s.lower() or 'nan' in s.lower():
                return float(s)
            return int(s)
        except (ValueError, IndexError):
            try:
                return float(s)
            except ValueError:
                return None
    return None


def truthy(v):
    return not (v is None or v is False)


# Lua 5.1 numbers are IEEE doubles.  Python ints are unbounded, so an exact
# integer result that a real Lua would have rounded must be demoted to float,
# otherwise both the arithmetic results and the runtime cost diverge from Lua.
MAXEXACT = 9007199254740992          # 2**53


def norm(x):
    if type(x) is int and (x > MAXEXACT or x < -MAXEXACT):
        return float(x)
    return x


class Coroutine:
    __slots__ = ('fn', 'status', 'gen')

    def __init__(self, fn):
        self.fn = fn
        self.status = 'suspended'
        self.gen = None


def describe(e):
    k = e[0]
    if k == 'name':
        return e[1]
    if k == 'index':
        return '%s[%s]' % (describe(e[1]), describe(e[2]))
    if k == 'str':
        return repr(e[1][:30])
    if k == 'num':
        return str(e[1])
    if k == 'call':
        return describe(e[1]) + '(...)'
    if k == 'paren':
        return '(' + describe(e[1]) + ')'
    return '<%s>' % k


BREAK = ('#break',)


# ---------------------------------------------------------------- interp

class Interp:
    def __init__(self):
        self.G = Table()
        self.stringmeta = None
        self.depth = 0
        self.maxdepth = 190
        self.hooks = {}
        self.steps = 0
        self.envstack = []
        self.callsites = []
        self.binpos = -1
        self.capture_depths = ()
        self.captured = {}
        import lualib
        lualib.install(self)
        import luacomp
        self.compiler = luacomp.Compiler(self)

    # ---- metatable access ---------------------------------------------
    def getmeta(self, v):
        t = type(v)
        if t is Table or t is Userdata:
            return v.mt
        if t is str:
            return self.stringmeta
        return None

    def metaop(self, v, ev):
        mt = self.getmeta(v)
        if mt is None:
            return None
        return mt.get(ev)

    # ---- index / newindex ----------------------------------------------
    def index(self, obj, key):
        for _ in range(100):
            t = type(obj)
            if t is Table:
                v = obj.get(key)
                if v is not None:
                    return v
                mt = obj.mt
                if mt is None:
                    return None
                h = mt.get('__index')
                if h is None:
                    return None
            else:
                h = self.metaop(obj, '__index')
                if h is None:
                    raise LuaError('attempt to index a %s value (key %r)'
                                   % (type_name(obj), key))
            if type(h) is LuaFunction or type(h) is Builtin:
                r = self.call(h, [obj, key])
                return r[0] if r else None
            obj = h
        raise LuaError("'__index' chain too long; possible loop")

    def setindex(self, obj, key, val):
        for _ in range(100):
            t = type(obj)
            if t is Table:
                if obj.get(key) is not None or obj.mt is None:
                    if key is None:
                        raise LuaError('table index is nil')
                    obj.set(key, val)
                    return
                h = obj.mt.get('__newindex')
                if h is None:
                    if key is None:
                        raise LuaError('table index is nil')
                    obj.set(key, val)
                    return
            else:
                h = self.metaop(obj, '__newindex')
                if h is None:
                    raise LuaError('attempt to index a %s value' % type_name(obj))
            if type(h) is LuaFunction or type(h) is Builtin:
                self.call(h, [obj, key, val])
                return
            obj = h
        raise LuaError("'__newindex' chain too long; possible loop")

    # ---- calling --------------------------------------------------------
    def call(self, f, args):
        t = type(f)
        if t is Builtin:
            r = f.fn(self, args)
            return r if r is not None else []
        if t is LuaFunction:
            d = self.depth + 1
            if d > self.maxdepth:
                raise LuaError('stack overflow')
            self.depth = d
            self.envstack.append(f.env)
            try:
                sc = Scope(f.scope)
                if self.capture_depths and d in self.capture_depths:
                    self.captured.setdefault(d, []).append(sc)
                v = sc.v
                ps = f.params
                np = len(ps)
                la = len(args)
                for i in range(np):
                    v[ps[i]] = args[i] if i < la else None
                if f.vararg:
                    v['...'] = args[np:]
                runner = self.compiler.get_runner(f.body)
                sig = runner(sc, f.env)
                if sig is not None and sig is not BREAK:
                    return sig[1]
                return []
            finally:
                self.depth = d - 1
                self.envstack.pop()
        h = self.metaop(f, '__call')
        if h is not None:
            return self.call(h, [f] + args)
        raise LuaError('attempt to call a %s value' % type_name(f))

    # ---- arithmetic -----------------------------------------------------
    ARITH_EV = {'+': '__add', '-': '__sub', '*': '__mul', '/': '__div',
                '%': '__mod', '^': '__pow'}

    def arith(self, op, a, b):
        na = a if type(a) in (int, float) else tonum(a) if type(a) is str else None
        nb = b if type(b) in (int, float) else tonum(b) if type(b) is str else None
        if na is None or nb is None:
            ev = self.ARITH_EV[op]
            h = self.metaop(a, ev) or self.metaop(b, ev)
            if h is not None:
                r = self.call(h, [a, b])
                return r[0] if r else None
            bad = a if na is None else b
            raise LuaError('attempt to perform arithmetic on a %s value'
                           % type_name(bad))
        if op == '+':
            return norm(na + nb)
        if op == '-':
            return norm(na - nb)
        if op == '*':
            return norm(na * nb)
        if op == '/':
            if nb == 0:
                if na == 0:
                    return float('nan')
                return math.inf if na > 0 else -math.inf
            # keep exact integer quotients integral: in Lua 6/2 is 3.0, which
            # compares and formats identically to the int 3, and staying in
            # ints keeps the rest of the pipeline on the fast path
            if type(na) is int and type(nb) is int and na % nb == 0:
                return norm(na // nb)
            return na / nb
        if op == '%':
            if nb == 0:
                return float('nan')
            if type(na) is int and type(nb) is int:
                return na % nb
            r = math.fmod(na, nb)
            if r != 0 and (r < 0) != (nb < 0):
                r += nb
            return r
        if op == '^':
            try:
                r = float(na) ** float(nb)
            except (OverflowError, ZeroDivisionError):
                r = math.inf
            return r
        raise LuaError('bad arith op ' + op)

    def unm(self, a):
        na = a if type(a) in (int, float) else tonum(a) if type(a) is str else None
        if na is None:
            h = self.metaop(a, '__unm')
            if h is not None:
                r = self.call(h, [a, a])
                return r[0] if r else None
            raise LuaError('attempt to perform arithmetic on a %s value' % type_name(a))
        return -na

    def concat(self, a, b):
        ta, tb = type(a), type(b)
        if (ta is str or ta is int or ta is float) and \
           (tb is str or tb is int or tb is float):
            sa = a if ta is str else fmtnum(a)
            sb = b if tb is str else fmtnum(b)
            return sa + sb
        h = self.metaop(a, '__concat') or self.metaop(b, '__concat')
        if h is not None:
            r = self.call(h, [a, b])
            return r[0] if r else None
        bad = a if not (ta is str or ta is int or ta is float) else b
        raise LuaError('attempt to concatenate a %s value' % type_name(bad))

    def length(self, a):
        t = type(a)
        if t is str:
            return len(a)
        if t is Table:
            if a.mt is not None:
                h = a.mt.get('__len')
                if h is not None:
                    r = self.call(h, [a])
                    return r[0] if r else None
            return a.length()
        h = self.metaop(a, '__len')
        if h is not None:
            r = self.call(h, [a])
            return r[0] if r else None
        raise LuaError('attempt to get length of a %s value' % type_name(a))

    def eq(self, a, b):
        if a is b:
            return True
        ta, tb = type(a), type(b)
        if ta is bool or tb is bool:
            return a is b
        if (ta in (int, float)) and (tb in (int, float)):
            return a == b
        if ta is not tb:
            return False
        if ta is str:
            return a == b
        if a == b:
            return True
        if ta is Table or ta is Userdata:
            h = self.metaop(a, '__eq') or self.metaop(b, '__eq')
            if h is not None:
                r = self.call(h, [a, b])
                return truthy(r[0] if r else None)
        return False

    def lt(self, a, b):
        ta, tb = type(a), type(b)
        if ta in (int, float) and tb in (int, float):
            return a < b
        if ta is str and tb is str:
            return a < b
        h = self.metaop(a, '__lt') or self.metaop(b, '__lt')
        if h is not None:
            r = self.call(h, [a, b])
            return truthy(r[0] if r else None)
        raise LuaError('attempt to compare %s with %s' % (type_name(a), type_name(b)))

    def le(self, a, b):
        ta, tb = type(a), type(b)
        if ta in (int, float) and tb in (int, float):
            return a <= b
        if ta is str and tb is str:
            return a <= b
        h = self.metaop(a, '__le') or self.metaop(b, '__le')
        if h is not None:
            r = self.call(h, [a, b])
            return truthy(r[0] if r else None)
        h = self.metaop(a, '__lt') or self.metaop(b, '__lt')
        if h is not None:
            r = self.call(h, [b, a])
            return not truthy(r[0] if r else None)
        raise LuaError('attempt to compare %s with %s' % (type_name(a), type_name(b)))

    # ---- variable access ------------------------------------------------
    @staticmethod
    def lookup(scope, name):
        s = scope
        while s is not None:
            v = s.v
            if name in v:
                return s
            s = s.parent
        return None

    # ---- expression evaluation ------------------------------------------
    def eval(self, e, sc, env):
        k = e[0]
        if k == 'num' or k == 'str':
            return e[1]
        if k == 'name':
            n = e[1]
            s = sc
            while s is not None:
                v = s.v
                if n in v:
                    return v[n]
                s = s.parent
            return self.index(env, n)
        if k == 'index':
            return self.index(self.eval(e[1], sc, env), self.eval(e[2], sc, env))
        if k == 'binop':
            op = e[1]
            if op == '+' or op == '-' or op == '*' or op == '/' or op == '%' or op == '^':
                a = self.eval(e[2], sc, env)
                b = self.eval(e[3], sc, env)
                ta, tb = type(a), type(b)
                if (ta is int or ta is float) and (tb is int or tb is float):
                    if op == '+':
                        return a + b
                    if op == '-':
                        return a - b
                    if op == '*':
                        return a * b
                return self.arith(op, a, b)
            if op == '..':
                return self.concat(self.eval(e[2], sc, env), self.eval(e[3], sc, env))
            a = self.eval(e[2], sc, env)
            b = self.eval(e[3], sc, env)
            if op == '==':
                return self.eq(a, b)
            if op == '~=':
                return not self.eq(a, b)
            self.binpos = e[4]
            if op == '<':
                return self.lt(a, b)
            if op == '>':
                return self.lt(b, a)
            if op == '<=':
                return self.le(a, b)
            if op == '>=':
                return self.le(b, a)
            raise LuaError('bad binop ' + op)
        if k == 'call' or k == 'method':
            r = self.eval_multi(e, sc, env)
            return r[0] if r else None
        if k == 'and':
            a = self.eval(e[1], sc, env)
            if a is None or a is False:
                return a
            return self.eval(e[2], sc, env)
        if k == 'or':
            a = self.eval(e[1], sc, env)
            if not (a is None or a is False):
                return a
            return self.eval(e[2], sc, env)
        if k == 'nil':
            return None
        if k == 'true':
            return True
        if k == 'false':
            return False
        if k == 'unop':
            op = e[1]
            if op == '-':
                v = self.eval(e[2], sc, env)
                if type(v) is int or type(v) is float:
                    return -v
                return self.unm(v)
            if op == 'not':
                v = self.eval(e[2], sc, env)
                return v is None or v is False
            return self.length(self.eval(e[2], sc, env))
        if k == 'func':
            return LuaFunction(e[1], e[2], e[3], sc, env)
        if k == 'table':
            t = Table()
            arr = e[1]
            na = len(arr)
            for i in range(na):
                if i == na - 1 and arr[i][0] in ('call', 'method', 'vararg'):
                    vals = self.eval_multi(arr[i], sc, env)
                    for j, v in enumerate(vals):
                        t.set(i + 1 + j, v)
                else:
                    t.set(i + 1, self.eval(arr[i], sc, env))
            for kk, vv in e[2]:
                t.set(self.eval(kk, sc, env), self.eval(vv, sc, env))
            return t
        if k == 'paren':
            return self.eval(e[1], sc, env)
        if k == 'vararg':
            s = self.lookup(sc, '...')
            va = s.v['...'] if s else []
            return va[0] if va else None
        raise LuaError('bad expr node ' + k)

    def eval_multi(self, e, sc, env):
        k = e[0]
        if k == 'call':
            f = self.eval(e[1], sc, env)
            args = self.evalargs(e[2], sc, env)
            if type(f) is not LuaFunction and type(f) is not Builtin \
                    and self.metaop(f, '__call') is None:
                raise LuaError('attempt to call a %s value @%d [%s]'
                               % (type_name(f), e[3], describe(e[1])))
            self.callsites.append(e[3])
            try:
                return self.call(f, args)
            finally:
                self.callsites.pop()
        if k == 'method':
            obj = self.eval(e[1], sc, env)
            f = self.index(obj, e[2])
            args = self.evalargs(e[3], sc, env)
            if type(f) is not LuaFunction and type(f) is not Builtin \
                    and self.metaop(f, '__call') is None:
                raise LuaError('attempt to call method %r (a %s value) @%d'
                               % (e[2], type_name(f), e[4]))
            self.callsites.append(e[4])
            try:
                return self.call(f, [obj] + args)
            finally:
                self.callsites.pop()
        if k == 'vararg':
            s = self.lookup(sc, '...')
            return list(s.v['...']) if s else []
        v = self.eval(e, sc, env)
        return [v]

    def evalargs(self, exprs, sc, env):
        n = len(exprs)
        if n == 0:
            return []
        out = []
        for i in range(n - 1):
            out.append(self.eval(exprs[i], sc, env))
        last = exprs[n - 1]
        if last[0] in ('call', 'method', 'vararg'):
            out.extend(self.eval_multi(last, sc, env))
        else:
            out.append(self.eval(last, sc, env))
        return out

    # ---- statements ------------------------------------------------------
    def exec_block(self, stmts, sc, env):
        for st in stmts:
            k = st[0]
            if k == 'local':
                vals = self.evalargs(st[2], sc, env)
                names = st[1]
                # Lua: re-declaring a name already bound in *this* block makes a
                # NEW variable.  Closures created earlier captured the old one,
                # so we must not clobber it -- open a fresh child scope instead.
                v = sc.v
                if any(nm in v for nm in names):
                    sc = Scope(sc)
                    v = sc.v
                for i, nm in enumerate(names):
                    v[nm] = vals[i] if i < len(vals) else None
            elif k == 'callstat':
                self.eval_multi(st[1], sc, env)
            elif k == 'assign':
                targets = st[1]
                vals = self.evalargs(st[2], sc, env)
                for i, tg in enumerate(targets):
                    val = vals[i] if i < len(vals) else None
                    if tg[0] == 'name':
                        n = tg[1]
                        s = self.lookup(sc, n)
                        if s is not None:
                            s.v[n] = val
                        else:
                            self.setindex(env, n, val)
                    else:
                        self.setindex(self.eval(tg[1], sc, env),
                                      self.eval(tg[2], sc, env), val)
            elif k == 'if':
                done = False
                for cond, body in st[1]:
                    c = self.eval(cond, sc, env)
                    if not (c is None or c is False):
                        sig = self.exec_block(body, Scope(sc), env)
                        if sig is not None:
                            return sig
                        done = True
                        break
                if not done and st[2] is not None:
                    sig = self.exec_block(st[2], Scope(sc), env)
                    if sig is not None:
                        return sig
            elif k == 'return':
                return ('#ret', self.evalargs(st[1], sc, env))
            elif k == 'while':
                cond = st[1]
                body = st[2]
                while True:
                    c = self.eval(cond, sc, env)
                    if c is None or c is False:
                        break
                    sig = self.exec_block(body, Scope(sc), env)
                    if sig is not None:
                        if sig is BREAK:
                            break
                        return sig
            elif k == 'numfor':
                var = st[1]
                a = tonum(self.eval(st[2], sc, env))
                b = tonum(self.eval(st[3], sc, env))
                step = tonum(self.eval(st[4], sc, env)) if st[4] is not None else 1
                if a is None or b is None or step is None:
                    raise LuaError("'for' initial value must be a number")
                body = st[5]
                i = a
                if step > 0:
                    while i <= b:
                        s2 = Scope(sc)
                        s2.v[var] = i
                        sig = self.exec_block(body, s2, env)
                        if sig is not None:
                            if sig is BREAK:
                                break
                            return sig
                        i += step
                elif step < 0:
                    while i >= b:
                        s2 = Scope(sc)
                        s2.v[var] = i
                        sig = self.exec_block(body, s2, env)
                        if sig is not None:
                            if sig is BREAK:
                                break
                            return sig
                        i += step
                else:
                    raise LuaError("'for' step is zero")
            elif k == 'genfor':
                names = st[1]
                vals = self.evalargs(st[2], sc, env)
                f = vals[0] if len(vals) > 0 else None
                state = vals[1] if len(vals) > 1 else None
                ctl = vals[2] if len(vals) > 2 else None
                body = st[3]
                while True:
                    rs = self.call(f, [state, ctl])
                    first = rs[0] if rs else None
                    if first is None:
                        break
                    ctl = first
                    s2 = Scope(sc)
                    v2 = s2.v
                    for i, nm in enumerate(names):
                        v2[nm] = rs[i] if i < len(rs) else None
                    sig = self.exec_block(body, s2, env)
                    if sig is not None:
                        if sig is BREAK:
                            break
                        return sig
            elif k == 'repeat':
                body = st[1]
                cond = st[2]
                while True:
                    s2 = Scope(sc)
                    sig = self.exec_block(body, s2, env)
                    if sig is not None:
                        if sig is BREAK:
                            break
                        return sig
                    c = self.eval(cond, s2, env)
                    if not (c is None or c is False):
                        break
            elif k == 'do':
                sig = self.exec_block(st[1], Scope(sc), env)
                if sig is not None:
                    return sig
            elif k == 'localfunc':
                if st[1] in sc.v:
                    sc = Scope(sc)
                # bind the name first (in a fresh child if shadowing) so the
                # body's scope sees it and recursion works
                sc.v[st[1]] = None
                fn = LuaFunction(st[2][1], st[2][2], st[2][3], sc, env, st[1])
                sc.v[st[1]] = fn
            elif k == 'break':
                return BREAK
            else:
                raise LuaError('bad statement ' + k)
        return None

    # ---- top level -------------------------------------------------------
    def load(self, src, chunkname='=chunk', env=None):
        ast = parse(src, chunkname)
        return LuaFunction([], True, ast, Scope(None), env or self.G, chunkname)

    def run(self, src, args=None, chunkname='=chunk', env=None):
        f = self.load(src, chunkname, env)
        return self.call(f, args or [])
