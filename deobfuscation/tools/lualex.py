"""Minimal Lua 5.1 lexer + source beautifier used for unpacking the payload."""
import re, sys

KEYWORDS = {
    'and','break','do','else','elseif','end','false','for','function','if','in',
    'local','nil','not','or','repeat','return','then','true','until','while'
}

class Tok:
    __slots__ = ('kind','val','pos','raw')
    def __init__(self, kind, val, pos, raw=None):
        self.kind = kind; self.val = val; self.pos = pos
        self.raw = raw if raw is not None else val
    def __repr__(self):
        return '<%s %r>' % (self.kind, self.val[:40] if isinstance(self.val,str) else self.val)


ESCAPES = {'a':'\a','b':'\b','f':'\f','n':'\n','r':'\r','t':'\t','v':'\v',
           '\\':'\\','"':'"',"'":"'",'\n':'\n'}


def _long_bracket(s, i):
    """If s[i] starts a long bracket [=*[, return (level, content_start) else None."""
    if s[i] != '[':
        return None
    j = i + 1
    lvl = 0
    while j < len(s) and s[j] == '=':
        lvl += 1; j += 1
    if j < len(s) and s[j] == '[':
        return lvl, j + 1
    return None


def tokenize(s):
    toks = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c in ' \t\r\n':
            i += 1
            continue
        # comments
        if c == '-' and i + 1 < n and s[i+1] == '-':
            i += 2
            lb = _long_bracket(s, i) if i < n else None
            if lb:
                lvl, st = lb
                close = ']' + '=' * lvl + ']'
                e = s.find(close, st)
                e = n if e < 0 else e + len(close)
                i = e
            else:
                e = s.find('\n', i)
                i = n if e < 0 else e + 1
            continue
        # long string
        lb = _long_bracket(s, i)
        if lb:
            lvl, st = lb
            close = ']' + '=' * lvl + ']'
            e = s.find(close, st)
            if e < 0:
                e = n
                content = s[st:]
                i = n
            else:
                content = s[st:e]
                i = e + len(close)
            if content.startswith('\n'):
                content = content[1:]
            toks.append(Tok('str', content, i, s[:0]))
            toks[-1].raw = None  # long strings re-emitted as quoted
            continue
        # short string
        if c in '"\'':
            q = c
            j = i + 1
            buf = []
            while j < n:
                ch = s[j]
                if ch == '\\':
                    nx = s[j+1] if j + 1 < n else ''
                    if nx.isdigit():
                        k = j + 1
                        num = ''
                        while k < n and s[k].isdigit() and len(num) < 3:
                            num += s[k]; k += 1
                        buf.append(chr(int(num) & 0xFF)); j = k; continue
                    buf.append(ESCAPES.get(nx, nx)); j += 2; continue
                if ch == q:
                    j += 1
                    break
                buf.append(ch); j += 1
            toks.append(Tok('str', ''.join(buf), i))
            toks[-1].raw = None
            i = j
            continue
        # number
        if c.isdigit() or (c == '.' and i + 1 < n and s[i+1].isdigit()):
            m = re.match(r'0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?', s[i:])
            txt = m.group(0)
            toks.append(Tok('num', txt, i))
            i += len(txt)
            continue
        # name
        if c.isalpha() or c == '_':
            m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', s[i:])
            txt = m.group(0)
            toks.append(Tok('kw' if txt in KEYWORDS else 'name', txt, i))
            i += len(txt)
            continue
        # operators
        for op in ('...', '==', '~=', '<=', '>=', '..', '::'):
            if s.startswith(op, i):
                toks.append(Tok('op', op, i)); i += len(op); break
        else:
            toks.append(Tok('op', c, i)); i += 1
    toks.append(Tok('eof', '', n))
    return toks


def qstr(v):
    out = ['"']
    for ch in v:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\r':
            out.append('\\r')
        elif ch == '\t':
            out.append('\\t')
        elif 32 <= o < 127:
            out.append(ch)
        else:
            out.append('\\%d' % (o & 0xFF))
    out.append('"')
    return ''.join(out)


OPEN = {'do', 'then', 'repeat'}
NOSPACE_BEFORE = set(')]},;:.')
NOSPACE_AFTER = set('([{.#')


def beautify(src, max_str=90):
    toks = tokenize(src)
    lines = []
    cur = []
    ind = 0

    def flush():
        nonlocal cur
        if cur:
            lines.append('  ' * max(ind, 0) + ''.join(cur).strip())
            cur = []

    i = 0
    n = len(toks)
    fn_depth = 0
    while i < n:
        t = toks[i]
        if t.kind == 'eof':
            break
        v = t.val
        if t.kind == 'kw':
            if v in ('end', 'until', 'elseif', 'else'):
                flush()
                ind = max(ind - 1, 0)
                cur.append(v)
                if v in ('elseif', 'else'):
                    ind += 1
                else:
                    flush()
                    i += 1
                    continue
                i += 1
                continue
            if v in ('local', 'if', 'for', 'while', 'return', 'break'):
                flush()
                cur.append(v)
                i += 1
                continue
            if v in ('do', 'then', 'repeat'):
                cur.append(' ' + v)
                flush()
                ind += 1
                i += 1
                continue
            if v == 'function':
                cur.append(('' if not cur else ' ') + v)
                # consume the parameter list, then open a block
                j = i + 1
                depth = 0
                while j < n:
                    tv = toks[j]
                    cur.append(('' if tv.val in ')' else '') + tv.val)
                    if tv.val == '(':
                        depth += 1
                    elif tv.val == ')':
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                flush()
                ind = min(ind + 1, 60)
                i = j + 1
                continue
        if t.kind == 'op' and v == ';':
            flush()
            i += 1
            continue
        if t.kind == 'str':
            s = t.val
            disp = qstr(s if len(s) <= max_str else s[:max_str])
            if len(s) > max_str:
                disp = disp[:-1] + '"--[[+%d bytes]]' % (len(s) - max_str)
            cur.append(disp)
            i += 1
            continue
        prev = cur[-1][-1] if cur and cur[-1] else ''
        need = True
        if not cur:
            need = False
        elif v and v[0] in NOSPACE_BEFORE:
            need = False
        elif prev in NOSPACE_AFTER:
            need = False
        elif prev in '=+-*/%^<>~,' and t.kind == 'op':
            need = False
        elif t.kind == 'op' and v in '=+-*/%^<>,)]}(':
            need = False
        cur.append((' ' if need else '') + v)
        i += 1
    flush()
    return '\n'.join(lines)


if __name__ == '__main__':
    src = open(sys.argv[1], encoding='utf8', errors='surrogateescape').read()
    print(beautify(src))
