"""Standard library for the Python Lua interpreter, plus Roblox-shaped stubs."""
import math, os, time, random as _random
import luapat
from luavm import (Table, Userdata, LuaFunction, Builtin, LuaError, Coroutine,
                   type_name, tostr, tonum, fmtnum, truthy, Scope)


def mk(t, name, fn):
    t.set(name, Builtin(fn, name))


def arg(a, i, default=None):
    return a[i] if i < len(a) and a[i] is not None else default


def checkint(v, what='number'):
    n = tonum(v)
    if n is None:
        raise LuaError('bad argument (%s expected, got %s)' % (what, type_name(v)))
    return int(n)


def strarg(I, a, i):
    v = arg(a, i)
    if isinstance(v, str):
        return v
    if isinstance(v, (int, float)):
        return fmtnum(v)
    raise LuaError('bad argument #%d (string expected, got %s)' % (i + 1, type_name(v)))


# --------------------------------------------------------------- base lib

def install(I):
    G = I.G
    G.set('_G', G)
    G.set('_VERSION', 'Lua 5.1')

    def _print(I, a):
        print(' '.join(tostr(I, v) for v in a))
        return []
    mk(G, 'print', _print)

    mk(G, 'type', lambda I, a: [type_name(arg(a, 0))])
    mk(G, 'tostring', lambda I, a: [tostr(I, arg(a, 0))])
    mk(G, 'tonumber', lambda I, a: [tonum(arg(a, 0), arg(a, 1))])

    def _rawget(I, a):
        t = arg(a, 0)
        if not isinstance(t, Table):
            raise LuaError('bad argument #1 to rawget (table expected)')
        return [t.get(arg(a, 1))]
    mk(G, 'rawget', _rawget)

    def _rawset(I, a):
        t = arg(a, 0)
        if not isinstance(t, Table):
            raise LuaError('bad argument #1 to rawset (table expected)')
        t.set(arg(a, 1), arg(a, 2))
        return [t]
    mk(G, 'rawset', _rawset)

    mk(G, 'rawequal', lambda I, a: [arg(a, 0) is arg(a, 1) or
                                    (type(arg(a, 0)) in (int, float, str, bool) and
                                     type(arg(a, 1)) is type(arg(a, 0)) and
                                     arg(a, 0) == arg(a, 1))])

    def _rawlen(I, a):
        v = arg(a, 0)
        if isinstance(v, str):
            return [len(v)]
        if isinstance(v, Table):
            return [v.length()]
        raise LuaError('table or string expected')
    mk(G, 'rawlen', _rawlen)

    def _setmetatable(I, a):
        t = arg(a, 0)
        m = arg(a, 1)
        if not isinstance(t, (Table, Userdata)):
            raise LuaError('bad argument #1 to setmetatable (table expected, got %s)'
                           % type_name(t))
        if t.mt is not None and t.mt.get('__metatable') is not None:
            raise LuaError('cannot change a protected metatable')
        t.mt = m
        return [t]
    mk(G, 'setmetatable', _setmetatable)

    def _getmetatable(I, a):
        mt = I.getmeta(arg(a, 0))
        if mt is None:
            return [None]
        p = mt.get('__metatable')
        return [p if p is not None else mt]
    mk(G, 'getmetatable', _getmetatable)

    def _assert(I, a):
        v = arg(a, 0)
        if v is None or v is False:
            m = arg(a, 1, 'assertion failed!')
            raise LuaError(m)
        return list(a)
    mk(G, 'assert', _assert)

    def _error(I, a):
        v = arg(a, 0)
        lvl = arg(a, 1, 1)
        if isinstance(v, str) and lvl and lvl != 0:
            v = 'chunk:0: ' + v
        raise LuaError(v)
    mk(G, 'error', _error)

    def _pcall(I, a):
        if not a:
            raise LuaError('bad argument #1 to pcall (value expected)')
        f = a[0]
        d = I.depth
        try:
            r = I.call(f, list(a[1:]))
            return [True] + r
        except LuaError as e:
            I.depth = d
            return [False, e.value]
        except RecursionError:
            I.depth = d
            return [False, 'stack overflow']
        except ZeroDivisionError:
            I.depth = d
            return [False, 'attempt to perform division by zero']
    mk(G, 'pcall', _pcall)

    def _xpcall(I, a):
        f = arg(a, 0)
        h = arg(a, 1)
        d = I.depth
        try:
            r = I.call(f, list(a[2:]))
            return [True] + r
        except LuaError as e:
            I.depth = d
            hr = I.call(h, [e.value])
            return [False] + hr
        except RecursionError:
            I.depth = d
            return [False] + I.call(h, ['stack overflow'])
    mk(G, 'xpcall', _xpcall)

    def _select(I, a):
        n = arg(a, 0)
        rest = list(a[1:])
        if n == '#':
            return [len(rest)]
        n = checkint(n)
        if n < 0:
            n = len(rest) + n
            if n < 0:
                raise LuaError('bad argument #1 to select (index out of range)')
            return rest[n:]
        return rest[n - 1:]
    mk(G, 'select', _select)

    def _next(I, a):
        t = arg(a, 0)
        if not isinstance(t, Table):
            raise LuaError('bad argument #1 to next (table expected, got %s)'
                           % type_name(t))
        r = t.nextkey(arg(a, 1))
        if r is None:
            return [None]
        return [r[0], r[1]]
    nextb = Builtin(_next, 'next')
    G.set('next', nextb)

    def _pairs(I, a):
        t = arg(a, 0)
        mt = I.getmeta(t)
        if mt is not None:
            h = mt.get('__pairs')
            if h is not None:
                return I.call(h, [t])
        return [nextb, t, None]
    mk(G, 'pairs', _pairs)

    def _inext(I, a):
        t = arg(a, 0)
        i = checkint(arg(a, 1, 0)) + 1
        v = I.index(t, i)
        if v is None:
            return [None]
        return [i, v]
    inextb = Builtin(_inext, 'inext')

    mk(G, 'ipairs', lambda I, a: [inextb, arg(a, 0), 0])

    def _unpack(I, a):
        t = arg(a, 0)
        i = checkint(arg(a, 1, 1))
        j = arg(a, 2)
        j = t.length() if j is None else checkint(j)
        return [t.get(k) for k in range(i, j + 1)]
    mk(G, 'unpack', _unpack)

    def _newproxy(I, a):
        u = Userdata()
        if truthy(arg(a, 0)):
            u.mt = Table()
        return [u]
    mk(G, 'newproxy', _newproxy)

    mk(G, 'collectgarbage', lambda I, a: [0])
    mk(G, 'gcinfo', lambda I, a: [0])

    # -- environments ----------------------------------------------------
    def _getfenv(I, a):
        v = arg(a, 0, 1)
        if isinstance(v, LuaFunction):
            return [v.env]
        if isinstance(v, Builtin):
            return [I.G]
        n = checkint(v)
        if n == 0:
            return [I.G]
        fr = I.envstack[-min(n, len(I.envstack))] if I.envstack else I.G
        return [fr]
    mk(G, 'getfenv', _getfenv)

    def _setfenv(I, a):
        v = arg(a, 0)
        e = arg(a, 1)
        if isinstance(v, LuaFunction):
            v.env = e
            return [v]
        return [None]
    mk(G, 'setfenv', _setfenv)

    def _loadstring(I, a):
        src = arg(a, 0)
        name = arg(a, 1, '=(load)')
        if not isinstance(src, str):
            return [None, 'bad argument']
        try:
            f = I.load(src, name, I.G)
            return [f]
        except Exception as e:
            return [None, str(e)]
    mk(G, 'loadstring', _loadstring)
    mk(G, 'load', _loadstring)

    # ------------------------------------------------------------- string
    S = Table()
    G.set('string', S)
    smeta = Table()
    smeta.set('__index', S)
    I.stringmeta = smeta

    def _byte(I, a):
        s = strarg(I, a, 0)
        i = checkint(arg(a, 1, 1))
        j = checkint(arg(a, 2, i))
        n = len(s)
        if i < 0:
            i = n + i + 1
        if j < 0:
            j = n + j + 1
        i = max(i, 1)
        j = min(j, n)
        return [ord(c) for c in s[i - 1:j]]
    mk(S, 'byte', _byte)

    def _char(I, a):
        return [''.join(chr(checkint(x) & 0xFF) for x in a)]
    mk(S, 'char', _char)

    def _sub(I, a):
        s = strarg(I, a, 0)
        n = len(s)
        i = checkint(arg(a, 1, 1))
        j = checkint(arg(a, 2, -1))
        if i < 0:
            i = max(n + i + 1, 1)
        elif i == 0:
            i = 1
        if j < 0:
            j = n + j + 1
        elif j > n:
            j = n
        if i > j:
            return ['']
        return [s[i - 1:j]]
    mk(S, 'sub', _sub)

    mk(S, 'len', lambda I, a: [len(strarg(I, a, 0))])
    mk(S, 'upper', lambda I, a: [strarg(I, a, 0).upper()])
    mk(S, 'lower', lambda I, a: [strarg(I, a, 0).lower()])
    mk(S, 'reverse', lambda I, a: [strarg(I, a, 0)[::-1]])
    mk(S, 'rep', lambda I, a: [strarg(I, a, 0) * max(checkint(arg(a, 1, 0)), 0)])

    def _format(I, a):
        fmt = strarg(I, a, 0)
        out = []
        ai = 1
        i = 0
        while i < len(fmt):
            c = fmt[i]
            if c != '%':
                out.append(c)
                i += 1
                continue
            i += 1
            if i < len(fmt) and fmt[i] == '%':
                out.append('%')
                i += 1
                continue
            spec = '%'
            while i < len(fmt) and fmt[i] in '-+ #0':
                spec += fmt[i]; i += 1
            while i < len(fmt) and fmt[i].isdigit():
                spec += fmt[i]; i += 1
            if i < len(fmt) and fmt[i] == '.':
                spec += '.'; i += 1
                while i < len(fmt) and fmt[i].isdigit():
                    spec += fmt[i]; i += 1
            conv = fmt[i]; i += 1
            v = arg(a, ai); ai += 1
            if conv in 'di':
                out.append((spec + 'd') % int(tonum(v)))
            elif conv == 'u':
                out.append((spec + 'd') % (int(tonum(v)) & 0xFFFFFFFF))
            elif conv in 'fgGeE':
                out.append((spec + conv) % float(tonum(v)))
            elif conv in 'xX':
                out.append((spec + conv) % (int(tonum(v)) & 0xFFFFFFFF))
            elif conv == 'o':
                out.append((spec + 'o') % int(tonum(v)))
            elif conv == 'c':
                out.append(chr(int(tonum(v)) & 0xFF))
            elif conv == 's':
                out.append((spec + 's') % tostr(I, v))
            elif conv == 'q':
                out.append('"%s"' % tostr(I, v).replace('\\', '\\\\').replace('"', '\\"'))
            else:
                raise LuaError("invalid option '%%%s' to 'format'" % conv)
        return [''.join(out)]
    mk(S, 'format', _format)

    def _find(I, a):
        s = strarg(I, a, 0)
        p = strarg(I, a, 1)
        init = checkint(arg(a, 2, 1))
        plain = truthy(arg(a, 3))
        r = luapat.str_find_aux(s, p, init, plain, True)
        return r if r is not None else [None]
    mk(S, 'find', _find)

    def _match(I, a):
        s = strarg(I, a, 0)
        p = strarg(I, a, 1)
        init = checkint(arg(a, 2, 1))
        r = luapat.str_find_aux(s, p, init, False, False)
        return r if r is not None else [None]
    mk(S, 'match', _match)

    def _gmatch(I, a):
        s = strarg(I, a, 0)
        p = strarg(I, a, 1)
        it = luapat.gmatch_iter(s, p)

        def step(I2, args):
            try:
                return next(it)
            except StopIteration:
                return [None]
        return [Builtin(step, 'gmatch_iter')]
    mk(S, 'gmatch', _gmatch)

    def _gsub(I, a):
        s = strarg(I, a, 0)
        p = strarg(I, a, 1)
        repl = arg(a, 2)
        maxn = arg(a, 3)
        maxn = float('inf') if maxn is None else checkint(maxn)
        anchor = p.startswith('^')
        pstart = 1 if anchor else 0
        ms = luapat.MatchState(s, p)
        out = []
        pos = 0
        count = 0
        while count < maxn:
            ms.level = 0
            e = luapat.do_match(ms, pos, pstart)
            if e is not None:
                count += 1
                caps = luapat.get_captures(ms, pos, e)
                whole = s[pos:e]
                if isinstance(repl, str):
                    buf = []
                    k = 0
                    while k < len(repl):
                        ch = repl[k]
                        if ch == '%':
                            k += 1
                            d = repl[k]
                            if d == '0':
                                buf.append(whole)
                            elif d.isdigit():
                                cv = caps[int(d) - 1]
                                buf.append(cv if isinstance(cv, str) else fmtnum(cv))
                            else:
                                buf.append(d)
                        else:
                            buf.append(ch)
                        k += 1
                    out.append(''.join(buf))
                elif isinstance(repl, Table):
                    v = repl.get(caps[0])
                    out.append(whole if v is None or v is False else
                               (v if isinstance(v, str) else fmtnum(v)))
                else:
                    r = I.call(repl, caps)
                    v = r[0] if r else None
                    out.append(whole if v is None or v is False else
                               (v if isinstance(v, str) else fmtnum(v)))
            if e is not None and e > pos:
                pos = e
            elif pos < len(s):
                out.append(s[pos])
                pos += 1
            else:
                break
            if anchor:
                break
        out.append(s[pos:])
        return [''.join(out), count]
    mk(S, 'gsub', _gsub)

    # -------------------------------------------------------------- table
    T = Table()
    G.set('table', T)

    def _concat(I, a):
        t = arg(a, 0)
        sep = arg(a, 1, '')
        if not isinstance(sep, str):
            sep = fmtnum(sep)
        i = checkint(arg(a, 2, 1))
        j = arg(a, 3)
        j = t.length() if j is None else checkint(j)
        parts = []
        for k in range(i, j + 1):
            v = t.get(k)
            if isinstance(v, str):
                parts.append(v)
            elif isinstance(v, (int, float)):
                parts.append(fmtnum(v))
            else:
                raise LuaError('invalid value (at index %d) in table for concat' % k)
        return [sep.join(parts)]
    mk(T, 'concat', _concat)

    def _insert(I, a):
        t = arg(a, 0)
        if len(a) >= 3:
            pos = checkint(a[1])
            v = a[2]
            n = t.length()
            for k in range(n, pos - 1, -1):
                t.set(k + 1, t.get(k))
            t.set(pos, v)
        else:
            t.set(t.length() + 1, arg(a, 1))
        return []
    mk(T, 'insert', _insert)

    def _remove(I, a):
        t = arg(a, 0)
        n = t.length()
        pos = checkint(arg(a, 1, n)) if len(a) > 1 else n
        if n == 0:
            return [None]
        v = t.get(pos)
        for k in range(pos, n):
            t.set(k, t.get(k + 1))
        t.set(n, None)
        return [v]
    mk(T, 'remove', _remove)

    def _sort(I, a):
        t = arg(a, 0)
        cmp = arg(a, 1)
        items = [t.get(k) for k in range(1, t.length() + 1)]
        import functools
        if cmp is None:
            key = functools.cmp_to_key(lambda x, y: -1 if I.lt(x, y) else (1 if I.lt(y, x) else 0))
        else:
            def c(x, y):
                if truthy(I.call(cmp, [x, y])[0] if I.call(cmp, [x, y]) else None):
                    return -1
                r = I.call(cmp, [y, x])
                return 1 if truthy(r[0] if r else None) else 0
            key = functools.cmp_to_key(c)
        items.sort(key=key)
        for idx, v in enumerate(items):
            t.set(idx + 1, v)
        return []
    mk(T, 'sort', _sort)

    mk(T, 'getn', lambda I, a: [arg(a, 0).length()])
    mk(T, 'unpack', _unpack)

    # --------------------------------------------------------------- math
    M = Table()
    G.set('math', M)
    M.set('pi', math.pi)
    M.set('huge', math.inf)
    mk(M, 'floor', lambda I, a: [int(math.floor(tonum(arg(a, 0))))])
    mk(M, 'ceil', lambda I, a: [int(math.ceil(tonum(arg(a, 0))))])
    mk(M, 'abs', lambda I, a: [abs(tonum(arg(a, 0)))])
    mk(M, 'sqrt', lambda I, a: [math.sqrt(tonum(arg(a, 0)))])
    mk(M, 'max', lambda I, a: [max(tonum(x) for x in a)])
    mk(M, 'min', lambda I, a: [min(tonum(x) for x in a)])
    mk(M, 'pow', lambda I, a: [float(tonum(arg(a, 0))) ** float(tonum(arg(a, 1)))])
    mk(M, 'exp', lambda I, a: [math.exp(tonum(arg(a, 0)))])
    mk(M, 'sin', lambda I, a: [math.sin(tonum(arg(a, 0)))])
    mk(M, 'cos', lambda I, a: [math.cos(tonum(arg(a, 0)))])
    mk(M, 'tan', lambda I, a: [math.tan(tonum(arg(a, 0)))])

    def _log(I, a):
        x = tonum(arg(a, 0))
        b = arg(a, 1)
        return [math.log(x) if b is None else math.log(x, tonum(b))]
    mk(M, 'log', _log)

    def _fmod(I, a):
        x, y = tonum(arg(a, 0)), tonum(arg(a, 1))
        if y == 0:
            return [float('nan')]
        return [math.fmod(x, y)]
    mk(M, 'fmod', _fmod)

    def _modf(I, a):
        x = tonum(arg(a, 0))
        f, i = math.modf(float(x))
        return [int(i) if abs(i) < 2**53 else i, f]
    mk(M, 'modf', _modf)

    mk(M, 'ldexp', lambda I, a: [math.ldexp(float(tonum(arg(a, 0))),
                                            int(tonum(arg(a, 1))))])

    def _frexp(I, a):
        m, e = math.frexp(float(tonum(arg(a, 0))))
        return [m, e]
    mk(M, 'frexp', _frexp)

    _rng = _random.Random(0x5eed)

    def _mrandom(I, a):
        if not a:
            return [_rng.random()]
        if len(a) == 1:
            return [_rng.randint(1, checkint(a[0]))]
        return [_rng.randint(checkint(a[0]), checkint(a[1]))]
    mk(M, 'random', _mrandom)
    mk(M, 'randomseed', lambda I, a: [])

    # ----------------------------------------------------------------- os
    O = Table()
    G.set('os', O)
    mk(O, 'time', lambda I, a: [int(1750000000)])
    mk(O, 'clock', lambda I, a: [time.process_time()])
    mk(O, 'date', lambda I, a: ['Mon Jan  1 00:00:00 2024'])
    mk(O, 'getenv', lambda I, a: [None])

    # -------------------------------------------------------------- bit32
    def _mask(x):
        return int(x) & 0xFFFFFFFF

    B = Table()
    G.set('bit32', B)
    mk(B, 'band', lambda I, a: [_mask(_fold(a, lambda x, y: x & y, 0xFFFFFFFF))])
    mk(B, 'bor', lambda I, a: [_mask(_fold(a, lambda x, y: x | y, 0))])
    mk(B, 'bxor', lambda I, a: [_mask(_fold(a, lambda x, y: x ^ y, 0))])
    mk(B, 'bnot', lambda I, a: [_mask(~int(tonum(arg(a, 0))))])
    mk(B, 'lshift', lambda I, a: [_mask(int(tonum(arg(a, 0))) << (int(tonum(arg(a, 1))) & 31))])
    mk(B, 'rshift', lambda I, a: [_mask(_mask(int(tonum(arg(a, 0)))) >> (int(tonum(arg(a, 1))) & 31))])

    def _arshift(I, a):
        x = _mask(int(tonum(arg(a, 0))))
        n = int(tonum(arg(a, 1))) & 31
        if x & 0x80000000:
            x -= 0x100000000
        return [_mask(x >> n)]
    mk(B, 'arshift', _arshift)

    def _extract(I, a):
        x = _mask(int(tonum(arg(a, 0))))
        f = int(tonum(arg(a, 1)))
        w = int(tonum(arg(a, 2, 1)))
        return [(x >> f) & ((1 << w) - 1)]
    mk(B, 'extract', _extract)

    def _fold(a, op, init):
        r = init
        for v in a:
            r = op(r, _mask(int(tonum(v))))
        return r

    # ---------------------------------------------------------- coroutine
    C = Table()
    G.set('coroutine', C)
    mk(C, 'create', lambda I, a: [Coroutine(arg(a, 0))])
    mk(C, 'status', lambda I, a: ['suspended'])
    mk(C, 'running', lambda I, a: [None])

    def _resume(I, a):
        co = arg(a, 0)
        try:
            return [True] + I.call(co.fn, list(a[1:]))
        except LuaError as e:
            return [False, e.value]
    mk(C, 'resume', _resume)

    def _wrap(I, a):
        f = arg(a, 0)
        return [Builtin(lambda I2, args: I2.call(f, args), 'wrapped')]
    mk(C, 'wrap', _wrap)
    mk(C, 'yield', lambda I, a: list(a))

    # -------------------------------------------------------------- debug
    D = Table()
    G.set('debug', D)

    # The obfuscated payload is a single physical line (line 3 of the file that
    # ships it, but the chunk it loadstring's starts at line 1); every function
    # lives on that one line, so `currentline` is a small constant.  Roblox
    # executors return this line number from debug.info/getinfo, and the loader
    # only requires it to be a positive number <= 49157.
    I.debug_line = 3

    def _getinfo(I, a):
        # debug.getinfo(level, opts) -> table
        t = Table()
        t.set('currentline', I.debug_line)
        t.set('source', '=[C]')
        t.set('short_src', '[C]')
        t.set('what', 'Lua')
        t.set('func', arg(a, 0))
        t.set('name', '')
        t.set('linedefined', I.debug_line)
        t.set('nups', 0)
        t.set('numparams', 0)
        return [t]
    mk(D, 'getinfo', _getinfo)
    mk(D, 'traceback', lambda I, a: [arg(a, 0, '') or ''])

    def _info(I, a):
        # Roblox debug.info(level_or_func, options) -> one value per option char
        opts = None
        for v in a:
            if isinstance(v, str):
                opts = v
                break
        if opts is None:
            return [None]
        out = []
        for ch in opts:
            if ch == 'l':
                out.append(I.debug_line)      # current line (number!)
            elif ch == 's':
                out.append('[C]')             # short source
            elif ch == 'n':
                out.append('')                # name
            elif ch == 'f':
                out.append(arg(a, 0))         # function
            elif ch == 'a':
                out.append(0)                 # numparams
                out.append(False)             # is vararg
            elif ch == 'u':
                out.append(0)                 # nups
            else:
                out.append(None)
        return out
    mk(D, 'info', _info)

    I.envstack = [G]
