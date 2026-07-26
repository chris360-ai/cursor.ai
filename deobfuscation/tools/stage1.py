"""Port of the wYnFuscate outer-layer string decoder (fg) to Python."""
import re, sys
from lualex import tokenize

FH = 4294967296
FI = 2147483647

src = open('obf.lua', encoding='utf8', errors='surrogateescape').read()
body = src.split('\n')[2]

# ---- extract f4 = {[1]=..,[5]=..,[3]=..,[2]=..,[4]=..} -------------------
start = body.index('local f4={')
toks = tokenize(body[start:start + 20000])
# walk tokens: f4 = { [n] = "str" , ... }
parts = {}
i = 0
while i < len(toks):
    t = toks[i]
    if t.kind == 'op' and t.val == '[' and toks[i+1].kind == 'num' and \
       toks[i+2].val == ']' and toks[i+3].val == '=' and toks[i+4].kind == 'str':
        parts[int(toks[i+1].val)] = toks[i+4].val
        i += 5
        continue
    if t.kind == 'op' and t.val == '}':
        break
    i += 1

FW = ''.join(parts[k] for k in sorted(parts))
FW_B = bytes(ord(c) & 0xFF for c in FW)
print('f4 chunks: %s  total pool bytes: %d' % (sorted(parts), len(FW_B)), file=sys.stderr)


def sbyte(s, idx):
    """string.byte(s, idx) with 1-based index, None when out of range."""
    if idx < 1 or idx > len(s):
        return None
    return s[idx - 1]


def bxor8(a, b):
    return (a ^ b) & 0xFF


SC = 1664525
SE = 1013904223
SR = 256
SQ = (64 * 8877 + 139 * 6352 - 1425348) % FH
SW_ = (86 * 8877 + 118 * 6352 - 1512776) % FH
SG_ = (105 * 8877 + 54 * 6352 - 1274886) % FH      # 'Sg'
SM_ = (107 * 8877 + 146 * 6352 - 1877202) % FH
SGG = (116 * 8877 + 149 * 6352 + 1879745096) % FH  # 'SG'
ST_ = (73 * 8877 + 111 * 6352 - 1322398) % FH
SR_ = (136 * 8877 + 142 * 6352 - 2086524) % FH     # 'Sr'

FM0 = (93 * 8877 + 89 * 6352 - 1326082) % FH


def _step(Si, fT, SF, Sa):
    """One header decode: returns (Sf, Sz, Sq) for the record starting at Sa."""
    b0 = sbyte(FW_B, Sa) or 0
    b1 = sbyte(FW_B, Sa + 1) or 0
    Sq = b0 + b1 * SR
    Sz = (Si + fT + (SF * SG_) + (Sq % 65536) + SQ) % FH
    Sz = ((Sz * SC) + SE + (SF * ST_) + ((Si % 65536) * SR_)) % FH
    if Sz == 0:
        Sz = (Si + 1) % FH
    Sz = ((Sz * SC) + SE + (SF * SG_) + SGG + (Sq % 65536)) % FH
    Su = Sz % SR
    Sd = ((Sz - Su) // SR) % SR
    SA = ((Sz - (Sz % 65536)) // 65536) % SR
    SD = ((Sz - (Sz % 16777216)) // 16777216) % SR
    SS = sbyte(FW_B, Sa + 2)
    if SS is None:
        return None
    Sf = bxor8(SS, bxor8(bxor8(Su, Sd), bxor8(SA, (SD + SF) % SR)))
    return Sf, Sz, Sq


def fg(f0, f9, fM=FM0, fT=0):
    Sa = 1
    Si = fM
    SF = 0
    for _ in range(1, f0 + 1):
        r = _step(Si, fT, SF, Sa)
        if r is None:
            return ''
        Sf = r[0]
        Sa = Sa + 3 + Sf
        SF += 1
    r = _step(Si, fT, SF, Sa)
    if r is None:
        return ''
    Sf, Sz, Sq = r
    out = []
    for Sk in range(1, Sf + 1):
        Sz = ((Sz * SC) + SE + (SF * SG_) + (Sk * SW_) + (Sf * SM_) +
              (Sq % 65536) + SGG) % FH
        Su = Sz % SR
        Sd = ((Sz - Su) // SR) % SR
        SA = ((Sz - (Sz % 65536)) // 65536) % SR
        SD = ((Sz - (Sz % 16777216)) // 16777216) % SR
        SS = sbyte(FW_B, Sa + 2 + Sk)
        if SS is None:
            return ''
        f6 = (f9 + (Sk * 37) + (Sf * 13) + (SF * 17) +
              (((f9 - (f9 % 257)) // 257) % SR)) % SR
        out.append(bxor8(SS, bxor8(bxor8(bxor8(Su, (Sd + Sk) % SR),
                                          bxor8(SA, (SD + SF + Sf) % SR)), f6)))
    return bytes(out).decode('latin1')


if __name__ == '__main__':
    for n in range(0, 130):
        s = fg(n, 0)
        print(n, repr(s))
