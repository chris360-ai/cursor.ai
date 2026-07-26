"""Closure-compiling execution engine for the Lua interpreter.

Compiles each AST node into a Python closure once, then runs the closures.
Semantics match luavm's tree-walker exactly (same Table/metatable/call runtime);
this only removes per-step dispatch overhead.  Same-block local shadowing is
resolved at compile time by splitting the block into nested scopes.
"""
from luavm import (Table, Userdata, LuaFunction, Builtin, Scope, LuaError,
                   Coroutine, type_name, tonum, BREAK, MAXEXACT)

RET = '#ret'
_MISS = object()


class Compiler:
    def __init__(self, I):
        self.I = I
        self.cache = {}
        # bind hot runtime ops as locals
        self.index = I.index
        self.setindex = I.setindex
        self.call = I.call
        self.arith = I.arith
        self.concat = I.concat
        self.length = I.length
        self.eq = I.eq
        self.lt = I.lt
        self.le = I.le
        self.unm = I.unm
        self.metaop = I.metaop

    # ---- entry: compile a function body (list of stmts) ----------------
    def get_runner(self, body):
        r = self.cache.get(id(body))
        if r is None:
            r = self.compile_block(body)
            self.cache[id(body)] = r
        return r

    # ---- blocks --------------------------------------------------------
    def compile_block(self, stmts):
        declared = set()
        compiled = []
        n = len(stmts)
        i = 0
        while i < n:
            st = stmts[i]
            k = st[0]
            shadow = False
            if k == 'local':
                if any(nm in declared for nm in st[1]):
                    shadow = True
                else:
                    declared.update(st[1])
            elif k == 'localfunc':
                if st[1] in declared:
                    shadow = True
                else:
                    declared.add(st[1])
            if shadow:
                prefix = compiled
                rest = self.compile_block(stmts[i:])

                def runner(sc, env, prefix=prefix, rest=rest):
                    for c in prefix:
                        sig = c(sc, env)
                        if sig is not None:
                            return sig
                    return rest(Scope(sc), env)
                return runner
            compiled.append(self.compile_stmt(st))
            i += 1
        if len(compiled) == 1:
            return compiled[0]

        def runner(sc, env, compiled=tuple(compiled)):
            for c in compiled:
                sig = c(sc, env)
                if sig is not None:
                    return sig
            return None
        return runner

    @staticmethod
    def declares(stmts):
        """True if the block binds any name in its own scope."""
        for st in stmts:
            if st[0] == 'local' or st[0] == 'localfunc':
                return True
        return False

    def compile_block_scoped(self, stmts):
        """A block executed in a fresh child scope (elided when it binds nothing)."""
        inner = self.compile_block(stmts)
        if not self.declares(stmts):
            return inner

        def runner(sc, env, inner=inner):
            return inner(Scope(sc), env)
        return runner

    # ---- statements ----------------------------------------------------
    def compile_stmt(self, st):
        k = st[0]
        m = getattr(self, 'st_' + k)
        return m(st)

    def st_local(self, st):
        names = st[1]
        cargs = self.compile_args(st[2])
        nn = len(names)
        if nn == 1:
            name = names[0]
            if len(st[2]) == 1 and st[2][0][0] not in ('call', 'method', 'vararg'):
                ce = self.compile_expr(st[2][0])

                def run(sc, env, name=name, ce=ce):
                    sc.v[name] = ce(sc, env)
                    return None
                return run

            def run(sc, env, name=name, cargs=cargs):
                vals = cargs(sc, env)
                sc.v[name] = vals[0] if vals else None
                return None
            return run

        def run(sc, env, names=names, nn=nn, cargs=cargs):
            vals = cargs(sc, env)
            v = sc.v
            lv = len(vals)
            for i in range(nn):
                v[names[i]] = vals[i] if i < lv else None
            return None
        return run

    def st_localfunc(self, st):
        name = st[1]
        fexpr = st[2]
        params, vararg, body = fexpr[1], fexpr[2], fexpr[3]

        def run(sc, env, name=name, params=params, vararg=vararg, body=body):
            sc.v[name] = None
            sc.v[name] = LuaFunction(params, vararg, body, sc, env, name)
            return None
        return run

    def st_callstat(self, st):
        cm = self.compile_multi(st[1])

        def run(sc, env, cm=cm):
            cm(sc, env)
            return None
        return run

    def st_assign(self, st):
        targets = st[1]
        cargs = self.compile_args(st[2])
        setters = [self.compile_setter(t) for t in targets]
        if len(setters) == 1 and len(st[2]) == 1 and \
                st[2][0][0] not in ('call', 'method', 'vararg'):
            setter = setters[0]
            ce = self.compile_expr(st[2][0])

            def run(sc, env, setter=setter, ce=ce):
                setter(sc, env, ce(sc, env))
                return None
            return run

        def run(sc, env, setters=tuple(setters), cargs=cargs):
            vals = cargs(sc, env)
            lv = len(vals)
            for i, setr in enumerate(setters):
                setr(sc, env, vals[i] if i < lv else None)
            return None
        return run

    def compile_setter(self, tg):
        if tg[0] == 'name':
            n = tg[1]
            setindex = self.setindex

            def setr(sc, env, val, n=n, setindex=setindex, MISS=_MISS):
                s = sc
                while s is not None:
                    v = s.v
                    if v.get(n, MISS) is not MISS:
                        v[n] = val
                        return
                    s = s.parent
                setindex(env, n, val)
            return setr
        # index target
        cobj = self.compile_expr(tg[1])
        ckey = self.compile_expr(tg[2])
        setindex = self.setindex

        def setr(sc, env, val, cobj=cobj, ckey=ckey, setindex=setindex):
            setindex(cobj(sc, env), ckey(sc, env), val)
        return setr

    def st_if(self, st):
        clauses = [(self.compile_expr(c), self.compile_block_scoped(b))
                   for c, b in st[1]]
        els = self.compile_block_scoped(st[2]) if st[2] is not None else None

        def run(sc, env, clauses=tuple(clauses), els=els):
            for cond, body in clauses:
                c = cond(sc, env)
                if not (c is None or c is False):
                    return body(sc, env)
            if els is not None:
                return els(sc, env)
            return None
        return run

    def st_while(self, st):
        ccond = self.compile_expr(st[1])
        cbody = self.compile_block(st[2])
        fresh = self.declares(st[2])
        if not fresh:
            def run(sc, env, ccond=ccond, cbody=cbody):
                while True:
                    c = ccond(sc, env)
                    if c is None or c is False:
                        return None
                    sig = cbody(sc, env)
                    if sig is not None:
                        if sig is BREAK:
                            return None
                        return sig
            return run

        def run(sc, env, ccond=ccond, cbody=cbody):
            while True:
                c = ccond(sc, env)
                if c is None or c is False:
                    return None
                sig = cbody(Scope(sc), env)
                if sig is not None:
                    if sig is BREAK:
                        return None
                    return sig
        return run

    def st_repeat(self, st):
        cbody = self.compile_block(st[1])
        ccond = self.compile_expr(st[2])

        def run(sc, env, cbody=cbody, ccond=ccond):
            while True:
                s2 = Scope(sc)
                sig = cbody(s2, env)
                if sig is not None:
                    if sig is BREAK:
                        return None
                    return sig
                c = ccond(s2, env)
                if not (c is None or c is False):
                    return None
        return run

    def st_numfor(self, st):
        var = st[1]
        ca = self.compile_expr(st[2])
        cb = self.compile_expr(st[3])
        cstep = self.compile_expr(st[4]) if st[4] is not None else None
        cbody = self.compile_block(st[5])

        def run(sc, env, var=var, ca=ca, cb=cb, cstep=cstep, cbody=cbody):
            a = tonum(ca(sc, env))
            b = tonum(cb(sc, env))
            step = tonum(cstep(sc, env)) if cstep is not None else 1
            if a is None or b is None or step is None:
                raise LuaError("'for' initial value must be a number")
            i = a
            if step > 0:
                while i <= b:
                    s2 = Scope(sc)
                    s2.v[var] = i
                    sig = cbody(s2, env)
                    if sig is not None:
                        if sig is BREAK:
                            return None
                        return sig
                    i += step
            elif step < 0:
                while i >= b:
                    s2 = Scope(sc)
                    s2.v[var] = i
                    sig = cbody(s2, env)
                    if sig is not None:
                        if sig is BREAK:
                            return None
                        return sig
                    i += step
            else:
                raise LuaError("'for' step is zero")
            return None
        return run

    def st_genfor(self, st):
        names = tuple(st[1])
        cargs = self.compile_args(st[2])
        cbody = self.compile_block(st[3])
        call = self.call
        nn = len(names)

        def run(sc, env, names=names, nn=nn, cargs=cargs, cbody=cbody, call=call):
            vals = cargs(sc, env)
            f = vals[0] if len(vals) > 0 else None
            state = vals[1] if len(vals) > 1 else None
            ctl = vals[2] if len(vals) > 2 else None
            while True:
                rs = call(f, [state, ctl])
                first = rs[0] if rs else None
                if first is None:
                    return None
                ctl = first
                s2 = Scope(sc)
                v2 = s2.v
                lr = len(rs)
                for i in range(nn):
                    v2[names[i]] = rs[i] if i < lr else None
                sig = cbody(s2, env)
                if sig is not None:
                    if sig is BREAK:
                        return None
                    return sig
        return run

    def st_do(self, st):
        return self.compile_block_scoped(st[1])

    def st_return(self, st):
        exprs = st[1]
        if not exprs:
            def run(sc, env):
                return (RET, [])
            return run
        cargs = self.compile_args(exprs)

        def run(sc, env, cargs=cargs):
            return (RET, cargs(sc, env))
        return run

    def st_break(self, st):
        def run(sc, env):
            return BREAK
        return run

    # ---- argument lists ------------------------------------------------
    def compile_args(self, exprs):
        n = len(exprs)
        if n == 0:
            def f(sc, env):
                return []
            return f
        heads = [self.compile_expr(e) for e in exprs[:-1]]
        last = exprs[-1]
        if last[0] in ('call', 'method', 'vararg'):
            clast = self.compile_multi(last)
            if n == 1:
                return clast

            def f(sc, env, heads=tuple(heads), clast=clast):
                out = [h(sc, env) for h in heads]
                out.extend(clast(sc, env))
                return out
            return f
        clast = self.compile_expr(last)
        if n == 1:
            def f(sc, env, clast=clast):
                return [clast(sc, env)]
            return f

        def f(sc, env, heads=tuple(heads), clast=clast):
            out = [h(sc, env) for h in heads]
            out.append(clast(sc, env))
            return out
        return f

    # ---- multi-value expressions --------------------------------------
    def compile_multi(self, e):
        k = e[0]
        call = self.call
        if k == 'call':
            cf = self.compile_expr(e[1])
            cargs = self.compile_args(e[2])

            def f(sc, env, cf=cf, cargs=cargs, call=call):
                return call(cf(sc, env), cargs(sc, env))
            return f
        if k == 'method':
            cobj = self.compile_expr(e[1])
            name = e[2]
            cargs = self.compile_args(e[3])
            index = self.index

            def f(sc, env, cobj=cobj, name=name, cargs=cargs, call=call, index=index):
                obj = cobj(sc, env)
                fn = index(obj, name)
                return call(fn, [obj] + cargs(sc, env))
            return f
        if k == 'vararg':
            def f(sc, env):
                s = sc
                while s is not None:
                    if '...' in s.v:
                        return list(s.v['...'])
                    s = s.parent
                return []
            return f
        ce = self.compile_expr(e)

        def f(sc, env, ce=ce):
            return [ce(sc, env)]
        return f

    # ---- single-value expressions -------------------------------------
    def compile_expr(self, e):
        k = e[0]
        return getattr(self, 'ex_' + k)(e)

    def ex_num(self, e):
        v = e[1]
        return lambda sc, env: v

    def ex_str(self, e):
        v = e[1]
        return lambda sc, env: v

    def ex_nil(self, e):
        return lambda sc, env: None

    def ex_true(self, e):
        return lambda sc, env: True

    def ex_false(self, e):
        return lambda sc, env: False

    def ex_name(self, e):
        n = e[1]
        index = self.index

        def f(sc, env, n=n, index=index, MISS=_MISS):
            s = sc
            while s is not None:
                r = s.v.get(n, MISS)
                if r is not MISS:
                    return r
                s = s.parent
            return index(env, n)
        return f

    def ex_vararg(self, e):
        def f(sc, env):
            s = sc
            while s is not None:
                if '...' in s.v:
                    va = s.v['...']
                    return va[0] if va else None
                s = s.parent
            return None
        return f

    def ex_index(self, e):
        cobj = self.compile_expr(e[1])
        ckey = self.compile_expr(e[2])
        index = self.index

        def f(sc, env, cobj=cobj, ckey=ckey, index=index):
            return index(cobj(sc, env), ckey(sc, env))
        return f

    def ex_paren(self, e):
        return self.compile_expr(e[1])

    def ex_call(self, e):
        cm = self.compile_multi(e)

        def f(sc, env, cm=cm):
            r = cm(sc, env)
            return r[0] if r else None
        return f

    def ex_method(self, e):
        cm = self.compile_multi(e)

        def f(sc, env, cm=cm):
            r = cm(sc, env)
            return r[0] if r else None
        return f

    def ex_func(self, e):
        params, vararg, body = e[1], e[2], e[3]

        def f(sc, env, params=params, vararg=vararg, body=body):
            return LuaFunction(params, vararg, body, sc, env)
        return f

    def ex_and(self, e):
        ca = self.compile_expr(e[1])
        cb = self.compile_expr(e[2])

        def f(sc, env, ca=ca, cb=cb):
            a = ca(sc, env)
            if a is None or a is False:
                return a
            return cb(sc, env)
        return f

    def ex_or(self, e):
        ca = self.compile_expr(e[1])
        cb = self.compile_expr(e[2])

        def f(sc, env, ca=ca, cb=cb):
            a = ca(sc, env)
            if not (a is None or a is False):
                return a
            return cb(sc, env)
        return f

    def ex_unop(self, e):
        op = e[1]
        cv = self.compile_expr(e[2])
        if op == 'not':
            def f(sc, env, cv=cv):
                v = cv(sc, env)
                return v is None or v is False
            return f
        if op == '-':
            unm = self.unm

            def f(sc, env, cv=cv, unm=unm):
                v = cv(sc, env)
                if type(v) is int or type(v) is float:
                    return -v
                return unm(v)
            return f
        length = self.length

        def f(sc, env, cv=cv, length=length):
            return length(cv(sc, env))
        return f

    def ex_binop(self, e):
        op = e[1]
        ca = self.compile_expr(e[2])
        cb = self.compile_expr(e[3])
        arith = self.arith
        if op == '+':
            def f(sc, env, ca=ca, cb=cb, arith=arith):
                a = ca(sc, env); b = cb(sc, env)
                ta = type(a); tb = type(b)
                if (ta is int or ta is float) and (tb is int or tb is float):
                    r = a + b
                    if type(r) is int and (r > MAXEXACT or r < -MAXEXACT):
                        return float(r)
                    return r
                return arith('+', a, b)
            return f
        if op == '-':
            def f(sc, env, ca=ca, cb=cb, arith=arith):
                a = ca(sc, env); b = cb(sc, env)
                ta = type(a); tb = type(b)
                if (ta is int or ta is float) and (tb is int or tb is float):
                    r = a - b
                    if type(r) is int and (r > MAXEXACT or r < -MAXEXACT):
                        return float(r)
                    return r
                return arith('-', a, b)
            return f
        if op == '*':
            def f(sc, env, ca=ca, cb=cb, arith=arith):
                a = ca(sc, env); b = cb(sc, env)
                ta = type(a); tb = type(b)
                if (ta is int or ta is float) and (tb is int or tb is float):
                    r = a * b
                    if type(r) is int and (r > MAXEXACT or r < -MAXEXACT):
                        return float(r)
                    return r
                return arith('*', a, b)
            return f
        if op == '%':
            def f(sc, env, ca=ca, cb=cb, arith=arith):
                a = ca(sc, env); b = cb(sc, env)
                if type(a) is int and type(b) is int and b > 0:
                    return a % b
                return arith('%', a, b)
            return f
        if op in ('/', '^'):
            def f(sc, env, op=op, ca=ca, cb=cb, arith=arith):
                return arith(op, ca(sc, env), cb(sc, env))
            return f
        if op == '..':
            concat = self.concat

            def f(sc, env, ca=ca, cb=cb, concat=concat):
                return concat(ca(sc, env), cb(sc, env))
            return f
        if op == '==':
            eq = self.eq

            def f(sc, env, ca=ca, cb=cb, eq=eq):
                return eq(ca(sc, env), cb(sc, env))
            return f
        if op == '~=':
            eq = self.eq

            def f(sc, env, ca=ca, cb=cb, eq=eq):
                return not eq(ca(sc, env), cb(sc, env))
            return f
        if op == '<':
            lt = self.lt

            def f(sc, env, ca=ca, cb=cb, lt=lt):
                a = ca(sc, env); b = cb(sc, env)
                if type(a) in (int, float) and type(b) in (int, float):
                    return a < b
                return lt(a, b)
            return f
        if op == '>':
            lt = self.lt

            def f(sc, env, ca=ca, cb=cb, lt=lt):
                a = ca(sc, env); b = cb(sc, env)
                if type(a) in (int, float) and type(b) in (int, float):
                    return b < a
                return lt(b, a)
            return f
        if op == '<=':
            le = self.le

            def f(sc, env, ca=ca, cb=cb, le=le):
                a = ca(sc, env); b = cb(sc, env)
                if type(a) in (int, float) and type(b) in (int, float):
                    return a <= b
                return le(a, b)
            return f
        if op == '>=':
            le = self.le

            def f(sc, env, ca=ca, cb=cb, le=le):
                a = ca(sc, env); b = cb(sc, env)
                if type(a) in (int, float) and type(b) in (int, float):
                    return a >= b
                return le(b, a)
            return f
        raise LuaError('bad binop ' + op)

    def ex_table(self, e):
        arr = e[1]
        hashpairs = e[2]
        na = len(arr)
        arr_heads = [self.compile_expr(x) for x in arr[:-1]] if na else []
        if na:
            lastnode = arr[-1]
            last_multi = lastnode[0] in ('call', 'method', 'vararg')
            clast = (self.compile_multi(lastnode) if last_multi
                     else self.compile_expr(lastnode))
        else:
            last_multi = False
            clast = None
        chash = [(self.compile_expr(kk), self.compile_expr(vv))
                 for kk, vv in hashpairs]

        def f(sc, env, arr_heads=tuple(arr_heads), clast=clast,
              last_multi=last_multi, chash=tuple(chash), na=na):
            t = Table()
            idx = 1
            for h in arr_heads:
                t.set(idx, h(sc, env))
                idx += 1
            if na:
                if last_multi:
                    for v in clast(sc, env):
                        t.set(idx, v)
                        idx += 1
                else:
                    t.set(idx, clast(sc, env))
            for ck, cv in chash:
                t.set(ck(sc, env), cv(sc, env))
            return t
        return f
