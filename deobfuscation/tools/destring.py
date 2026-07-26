"""Produce a faithful, runnable de-stringed copy of the payload.

Only the obfuscator's string-decoder calls -- fg(n, key) -- are replaced by the
plain string literals they evaluate to.  Every other byte is preserved, so the
result is guaranteed to parse and to behave identically to the original; it is
simply readable where the interesting identifiers used to be fg() calls.
"""
import re, sys
sys.argv = ['x']
import stage1
from lualex import qstr

FH = 4294967296

header = ("-- De-stringed build: the wYnFuscate string-decoder calls fg(n,key)\n"
          "-- have been replaced inline with the literals they decode to.\n"
          "-- Behaviour is identical to the original protected script.\n")

L = open('obf.lua', encoding='utf8', errors='surrogateescape').read().split('\n')
body = L[2]

FG = re.compile(r'fg\((\d+),\(\((\d+)\*8877\+(\d+)\*6352([-+]\d+)\)%fh\)\)')
FG_ADJ = (126 * 8877 + 86 * 6352 - 1618614) % FH
WIN_START = body.index('fM=(fM+fG)%fI')
WIN_END = body.index('fM=(fM-fG)%fI')


def sub(m):
    n = int(m.group(1))
    key = (int(m.group(2)) * 8877 + int(m.group(3)) * 6352 + int(m.group(4))) % FH
    if WIN_START < m.start() < WIN_END:
        s = stage1.fg(n, key, fM=(stage1.FM0 + FG_ADJ) % FH)
    else:
        s = stage1.fg(n, key)
    return qstr(s)


new_body, count = FG.subn(sub, body)
out = L[0] + '\n' + L[1] + '\n' + new_body + '\n'
open('obf.destrung.lua', 'w', encoding='utf8', errors='surrogateescape').write(header + out)
print('replaced %d fg() calls; wrote obf.destrung.lua (%d bytes)'
      % (count, len(out)), file=sys.stderr)
