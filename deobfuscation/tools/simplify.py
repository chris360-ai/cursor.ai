"""Fold constant arithmetic and inline fg() string constants in the loader."""
import re, sys, os
sys.argv = ['x']
import stage1
from lualex import tokenize, qstr, beautify

FH = 4294967296

body = stage1.body

# ---------------------------------------------------------------- fg inlining
FG = re.compile(r'fg\((\d+),\(\((\d+)\*8877\+(\d+)\*6352([-+]\d+)\)%fh\)\)')

# During load the loader temporarily perturbs the decoder state fM by +fG over a
# short window (see the anti-tamper block); every fg() call inside that window
# decodes to "" at run time.  Substitute those faithfully instead of using FM0.
FG_ADJ = (126 * 8877 + 86 * 6352 - 1618614) % FH          # fG
WIN_START = body.index('fM=(fM+fG)%fI')
WIN_END = body.index('fM=(fM-fG)%fI')


def _fg_sub(m):
    n = int(m.group(1))
    key = (int(m.group(2)) * 8877 + int(m.group(3)) * 6352 + int(m.group(4))) % FH
    if WIN_START < m.start() < WIN_END:
        return qstr(stage1.fg(n, key, fM=(stage1.FM0 + FG_ADJ) % FH))
    return qstr(stage1.fg(n, key))


# ------------------------------------------------------- constant folding pass
NUMTOK = re.compile(r'^(0[xX][0-9a-fA-F]+|\d+\.?\d*([eE][-+]?\d+)?)$')


def luanum(t):
    if t.lower().startswith('0x'):
        return int(t, 16)
    if '.' in t or 'e' in t.lower():
        return float(t)
    return int(t)


def fold(src, names):
    """Fold parenthesised expressions made only of numbers, ops and known names."""
    toks = tokenize(src)
    out = []
    i = 0
    n = len(toks)
    while i < n:
        t = toks[i]
        if t.kind == 'op' and t.val == '(':
            # try to find matching ) with only numeric content
            depth = 0
            j = i
            ok = True
            while j < n:
                tv = toks[j]
                if tv.kind == 'op' and tv.val == '(':
                    depth += 1
                elif tv.kind == 'op' and tv.val == ')':
                    depth -= 1
                    if depth == 0:
                        break
                elif tv.kind == 'num':
                    pass
                elif tv.kind == 'name' and tv.val in names:
                    pass
                elif tv.kind == 'op' and tv.val in '+-*/%^':
                    pass
                else:
                    ok = False
                    break
                j += 1
            if ok and j < n and depth == 0 and j > i + 1:
                expr = []
                for k in range(i, j + 1):
                    tv = toks[k]
                    if tv.kind == 'num':
                        expr.append(repr(luanum(tv.val)))
                    elif tv.kind == 'name':
                        expr.append(repr(names[tv.val]))
                    elif tv.val == '^':
                        expr.append('**')
                    elif tv.val == '/':
                        expr.append('/')
                    else:
                        expr.append(tv.val)
                try:
                    val = eval(''.join(expr), {'__builtins__': {}}, {})
                    if isinstance(val, float) and val.is_integer():
                        val = int(val)
                    out.append(str(val))
                    i = j + 1
                    continue
                except Exception:
                    pass
        # default emit
        if t.kind == 'str':
            out.append(qstr(t.val))
        elif t.kind == 'eof':
            pass
        else:
            out.append(t.val)
        # spacing: keep names/keywords separated
        if t.kind in ('name', 'kw', 'num') and i + 1 < n and \
           toks[i+1].kind in ('name', 'kw', 'num'):
            out.append(' ')
        i += 1
    return ''.join(out)


if __name__ == '__main__':
    NAMES = {'fh': 4294967296, 'fI': 2147483647}
    s = FG.sub(_fg_sub, body)
    for _ in range(4):
        s2 = fold(s, NAMES)
        if s2 == s:
            break
        s = s2
    open('loader.folded.lua', 'w', encoding='utf8', errors='surrogateescape').write(s)
    open('loader.pretty.lua', 'w', encoding='utf8', errors='surrogateescape').write(
        beautify(s, max_str=70))
    print('wrote loader.folded.lua / loader.pretty.lua', file=sys.stderr)
