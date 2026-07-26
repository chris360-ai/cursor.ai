"""Lua 5.1 pattern matching (a direct port of lstrlib.c's matcher)."""

SPECIALS = '^$*+?.([%-'
MAXCAPTURES = 32
CAP_UNF = -1
CAP_POS = -2


class MatchState:
    __slots__ = ('src', 'pat', 'level', 'capstart', 'caplen')

    def __init__(self, src, pat):
        self.src = src
        self.pat = pat
        self.level = 0
        self.capstart = [0] * MAXCAPTURES
        self.caplen = [0] * MAXCAPTURES


def class_match(c, cl):
    lower = cl.lower()
    if lower == 'a':
        res = c.isalpha()
    elif lower == 'c':
        res = ord(c) < 32 or ord(c) == 127
    elif lower == 'd':
        res = c.isdigit()
    elif lower == 'l':
        res = 'a' <= c <= 'z'
    elif lower == 'p':
        o = ord(c)
        res = (33 <= o <= 47) or (58 <= o <= 64) or (91 <= o <= 96) or (123 <= o <= 126)
    elif lower == 's':
        res = c in ' \t\n\r\f\v'
    elif lower == 'u':
        res = 'A' <= c <= 'Z'
    elif lower == 'w':
        res = c.isalnum() and ord(c) < 128
    elif lower == 'x':
        res = c in '0123456789abcdefABCDEF'
    elif lower == 'z':
        res = c == '\0'
    else:
        return cl == c
    if cl.isupper():
        return not res
    return res


def class_end(ms, p):
    pat = ms.pat
    c = pat[p]
    p += 1
    if c == '%':
        if p >= len(pat):
            raise ValueError("malformed pattern (ends with '%')")
        return p + 1
    if c == '[':
        if p < len(pat) and pat[p] == '^':
            p += 1
        while True:
            if p >= len(pat):
                raise ValueError("malformed pattern (missing ']')")
            c = pat[p]
            p += 1
            if c == '%':
                if p >= len(pat):
                    raise ValueError("malformed pattern")
                p += 1
            elif c == ']':
                return p
    return p


def match_bracket(ms, c, p, ec):
    """p points at '[', ec at the closing ']'."""
    pat = ms.pat
    sig = True
    p += 1
    if pat[p] == '^':
        sig = False
        p += 1
    while p < ec:
        if pat[p] == '%':
            p += 1
            if class_match(c, pat[p]):
                return sig
            p += 1
        elif p + 2 < ec and pat[p + 1] == '-':
            if pat[p] <= c <= pat[p + 2]:
                return sig
            p += 3
        else:
            if pat[p] == c:
                return sig
            p += 1
    return not sig


def single_match(ms, s, p, ep):
    if s >= len(ms.src):
        return False
    c = ms.src[s]
    pc = ms.pat[p]
    if pc == '.':
        return True
    if pc == '%':
        return class_match(c, ms.pat[p + 1])
    if pc == '[':
        return match_bracket(ms, c, p, ep - 1)
    return pc == c


def do_match(ms, s, p):
    pat = ms.pat
    src = ms.src
    while True:
        if p >= len(pat):
            return s
        pc = pat[p]
        if pc == '(':
            if p + 1 < len(pat) and pat[p + 1] == ')':
                ms.capstart[ms.level] = s
                ms.caplen[ms.level] = CAP_POS
                ms.level += 1
                r = do_match(ms, s, p + 2)
                if r is None:
                    ms.level -= 1
                return r
            ms.capstart[ms.level] = s
            ms.caplen[ms.level] = CAP_UNF
            ms.level += 1
            r = do_match(ms, s, p + 1)
            if r is None:
                ms.level -= 1
            return r
        if pc == ')':
            l = -1
            for i in range(ms.level - 1, -1, -1):
                if ms.caplen[i] == CAP_UNF:
                    l = i
                    break
            if l < 0:
                raise ValueError('invalid pattern capture')
            ms.caplen[l] = s - ms.capstart[l]
            r = do_match(ms, s, p + 1)
            if r is None:
                ms.caplen[l] = CAP_UNF
            return r
        if pc == '$' and p + 1 == len(pat):
            return s if s == len(src) else None
        if pc == '%':
            nx = pat[p + 1] if p + 1 < len(pat) else ''
            if nx == 'b':
                if s >= len(src) or src[s] != pat[p + 2]:
                    return None
                o, c = pat[p + 2], pat[p + 3]
                cont = 1
                i = s + 1
                while i < len(src):
                    ch = src[i]
                    if ch == c:
                        cont -= 1
                        if cont == 0:
                            return do_match(ms, i + 1, p + 4)
                    elif ch == o:
                        cont += 1
                    i += 1
                return None
            if nx == 'f':
                p += 2
                if p >= len(pat) or pat[p] != '[':
                    raise ValueError("missing '[' after '%f' in pattern")
                ep = class_end(ms, p)
                prev = '\0' if s == 0 else src[s - 1]
                cur = '\0' if s >= len(src) else src[s]
                if (not match_bracket(ms, prev, p, ep - 1)) and \
                        match_bracket(ms, cur, p, ep - 1):
                    p = ep
                    continue
                return None
            if nx.isdigit():
                l = int(nx) - 1
                if l < 0 or l >= ms.level or ms.caplen[l] == CAP_UNF:
                    raise ValueError('invalid capture index')
                ln = ms.caplen[l]
                if len(src) - s >= ln and \
                        src[ms.capstart[l]:ms.capstart[l] + ln] == src[s:s + ln]:
                    s += ln
                    p += 2
                    continue
                return None
        ep = class_end(ms, p)
        nxt = pat[ep] if ep < len(pat) else ''
        if nxt == '?':
            if single_match(ms, s, p, ep):
                r = do_match(ms, s + 1, ep + 1)
                if r is not None:
                    return r
            p = ep + 1
            continue
        if nxt == '+':
            if not single_match(ms, s, p, ep):
                return None
            s += 1
            # max expand
            i = 0
            while single_match(ms, s + i, p, ep):
                i += 1
            while i >= 0:
                r = do_match(ms, s + i, ep + 1)
                if r is not None:
                    return r
                i -= 1
            return None
        if nxt == '*':
            i = 0
            while single_match(ms, s + i, p, ep):
                i += 1
            while i >= 0:
                r = do_match(ms, s + i, ep + 1)
                if r is not None:
                    return r
                i -= 1
            return None
        if nxt == '-':
            while True:
                r = do_match(ms, s, ep + 1)
                if r is not None:
                    return r
                if single_match(ms, s, p, ep):
                    s += 1
                else:
                    return None
        if not single_match(ms, s, p, ep):
            return None
        s += 1
        p = ep


def get_captures(ms, s, e, wholeif0=True):
    n = ms.level
    if n == 0:
        return [ms.src[s:e]] if wholeif0 else []
    out = []
    for i in range(n):
        if ms.caplen[i] == CAP_POS:
            out.append(ms.capstart[i] + 1)
        else:
            st = ms.capstart[i]
            out.append(ms.src[st:st + ms.caplen[i]])
    return out


def str_find_aux(src, pat, init, plain, find):
    ls = len(src)
    if init < 0:
        init = ls + init
        if init < 0:
            init = 0
    elif init > 0:
        init -= 1
    if init > ls:
        return None
    if find and (plain or not any(ch in pat for ch in SPECIALS)):
        idx = src.find(pat, init)
        if idx < 0:
            return None
        return [idx + 1, idx + len(pat)]
    anchor = pat.startswith('^')
    p = 1 if anchor else 0
    s = init
    ms = MatchState(src, pat)
    while True:
        ms.level = 0
        e = do_match(ms, s, p)
        if e is not None:
            if find:
                return [s + 1, e] + get_captures(ms, s, e, False)
            return get_captures(ms, s, e)
        s += 1
        if s > ls or anchor:
            return None


def gmatch_iter(src, pat):
    ms = MatchState(src, pat)
    s = 0
    ls = len(src)
    while s <= ls:
        ms.level = 0
        e = do_match(ms, s, 0)
        if e is not None:
            caps = get_captures(ms, s, e)
            s = e + 1 if e == s else e
            yield caps
        else:
            s += 1
