"""Lua 5.1 parser producing a tuple-based AST."""
from lualex import tokenize, Tok


class ParseError(Exception):
    pass


BINPRI = {
    'or': (1, 1), 'and': (2, 2),
    '<': (3, 3), '>': (3, 3), '<=': (3, 3), '>=': (3, 3), '~=': (3, 3), '==': (3, 3),
    '..': (9, 8),                      # right associative
    '+': (10, 10), '-': (10, 10),
    '*': (11, 11), '/': (11, 11), '%': (11, 11),
    '^': (14, 13),                     # right associative
}
UNARY_PRI = 12


def luanumber(txt):
    if txt[:2].lower() == '0x':
        return int(txt, 16)
    if '.' in txt or 'e' in txt.lower():
        return float(txt)
    return int(txt)


class Parser:
    def __init__(self, src, chunkname='?'):
        self.toks = tokenize(src)
        self.p = 0
        self.chunk = chunkname

    # ---- token helpers -------------------------------------------------
    def peek(self, k=0):
        return self.toks[min(self.p + k, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.p]
        self.p += 1
        return t

    def check(self, kind, val=None):
        t = self.peek()
        return t.kind == kind and (val is None or t.val == val)

    def accept(self, kind, val=None):
        if self.check(kind, val):
            return self.next()
        return None

    def expect(self, kind, val=None):
        t = self.next()
        if t.kind != kind or (val is not None and t.val != val):
            raise ParseError('%s: expected %r got %r near pos %d' %
                             (self.chunk, val or kind, t.val, t.pos))
        return t

    # ---- entry ---------------------------------------------------------
    def parse_chunk(self):
        b = self.block()
        if not self.check('eof'):
            t = self.peek()
            raise ParseError('%s: unexpected %r at %d' % (self.chunk, t.val, t.pos))
        return b

    BLOCK_END = {'end', 'else', 'elseif', 'until'}

    def block(self):
        stmts = []
        while True:
            t = self.peek()
            if t.kind == 'eof':
                break
            if t.kind == 'kw' and t.val in self.BLOCK_END:
                break
            if t.kind == 'kw' and t.val == 'return':
                self.next()
                exprs = []
                if not (self.check('eof') or
                        (self.peek().kind == 'kw' and self.peek().val in self.BLOCK_END) or
                        self.check('op', ';')):
                    exprs = self.exprlist()
                self.accept('op', ';')
                stmts.append(('return', exprs))
                break
            if t.kind == 'kw' and t.val == 'break':
                self.next()
                self.accept('op', ';')
                stmts.append(('break',))
                break
            s = self.statement()
            if s is not None:
                stmts.append(s)
        return stmts

    def statement(self):
        t = self.peek()
        if t.kind == 'op' and t.val == ';':
            self.next()
            return None
        if t.kind == 'kw':
            v = t.val
            if v == 'if':
                return self.if_stat()
            if v == 'while':
                self.next()
                cond = self.expr()
                self.expect('kw', 'do')
                body = self.block()
                self.expect('kw', 'end')
                return ('while', cond, body)
            if v == 'do':
                self.next()
                body = self.block()
                self.expect('kw', 'end')
                return ('do', body)
            if v == 'for':
                return self.for_stat()
            if v == 'repeat':
                self.next()
                body = self.block()
                self.expect('kw', 'until')
                cond = self.expr()
                return ('repeat', body, cond)
            if v == 'function':
                self.next()
                # funcname: Name {'.' Name} [':' Name]
                name = self.expect('name').val
                target = ('name', name)
                ismethod = False
                while True:
                    if self.accept('op', '.'):
                        k = self.expect('name').val
                        target = ('index', target, ('str', k))
                    elif self.accept('op', ':'):
                        k = self.expect('name').val
                        target = ('index', target, ('str', k))
                        ismethod = True
                        break
                    else:
                        break
                f = self.funcbody(ismethod)
                return ('assign', [target], [f])
            if v == 'local':
                self.next()
                if self.accept('kw', 'function'):
                    name = self.expect('name').val
                    f = self.funcbody(False)
                    return ('localfunc', name, f)
                names = [self.expect('name').val]
                while self.accept('op', ','):
                    names.append(self.expect('name').val)
                exprs = []
                if self.accept('op', '='):
                    exprs = self.exprlist()
                return ('local', names, exprs)
        # exprstat: either a call or an assignment
        e = self.suffixedexp()
        if self.check('op', '=') or self.check('op', ','):
            targets = [e]
            while self.accept('op', ','):
                targets.append(self.suffixedexp())
            self.expect('op', '=')
            exprs = self.exprlist()
            for tg in targets:
                if tg[0] not in ('name', 'index'):
                    raise ParseError('cannot assign to %r' % (tg[0],))
            return ('assign', targets, exprs)
        if e[0] not in ('call', 'method'):
            raise ParseError('%s: syntax error, expression statement %r at %d'
                             % (self.chunk, e[0], self.peek().pos))
        return ('callstat', e)

    def if_stat(self):
        self.expect('kw', 'if')
        clauses = []
        cond = self.expr()
        self.expect('kw', 'then')
        clauses.append((cond, self.block()))
        while self.check('kw', 'elseif'):
            self.next()
            c = self.expr()
            self.expect('kw', 'then')
            clauses.append((c, self.block()))
        els = None
        if self.accept('kw', 'else'):
            els = self.block()
        self.expect('kw', 'end')
        return ('if', clauses, els)

    def for_stat(self):
        self.expect('kw', 'for')
        n1 = self.expect('name').val
        if self.accept('op', '='):
            e1 = self.expr()
            self.expect('op', ',')
            e2 = self.expr()
            e3 = None
            if self.accept('op', ','):
                e3 = self.expr()
            self.expect('kw', 'do')
            body = self.block()
            self.expect('kw', 'end')
            return ('numfor', n1, e1, e2, e3, body)
        names = [n1]
        while self.accept('op', ','):
            names.append(self.expect('name').val)
        self.expect('kw', 'in')
        exprs = self.exprlist()
        self.expect('kw', 'do')
        body = self.block()
        self.expect('kw', 'end')
        return ('genfor', names, exprs, body)

    def funcbody(self, ismethod):
        self.expect('op', '(')
        params = ['self'] if ismethod else []
        vararg = False
        if not self.check('op', ')'):
            while True:
                if self.accept('op', '...'):
                    vararg = True
                    break
                params.append(self.expect('name').val)
                if not self.accept('op', ','):
                    break
        self.expect('op', ')')
        body = self.block()
        self.expect('kw', 'end')
        return ('func', params, vararg, body)

    def exprlist(self):
        out = [self.expr()]
        while self.accept('op', ','):
            out.append(self.expr())
        return out

    def expr(self, limit=0):
        t = self.peek()
        if (t.kind == 'kw' and t.val == 'not') or \
           (t.kind == 'op' and t.val in ('-', '#')):
            self.next()
            operand = self.expr(UNARY_PRI)
            left = ('unop', t.val, operand)
        else:
            left = self.simpleexp()
        while True:
            t = self.peek()
            op = t.val
            if t.kind == 'kw' and op in ('and', 'or'):
                pass
            elif t.kind == 'op' and op in BINPRI:
                pass
            else:
                break
            lp, rp = BINPRI[op]
            if lp <= limit:
                break
            optok = self.next()
            right = self.expr(rp)
            if op == 'and':
                left = ('and', left, right)
            elif op == 'or':
                left = ('or', left, right)
            else:
                left = ('binop', op, left, right, optok.pos)
        return left

    def simpleexp(self):
        t = self.peek()
        if t.kind == 'num':
            self.next()
            return ('num', luanumber(t.val))
        if t.kind == 'str':
            self.next()
            return ('str', t.val)
        if t.kind == 'kw':
            if t.val == 'nil':
                self.next(); return ('nil',)
            if t.val == 'true':
                self.next(); return ('true',)
            if t.val == 'false':
                self.next(); return ('false',)
            if t.val == 'function':
                self.next(); return self.funcbody(False)
        if t.kind == 'op':
            if t.val == '...':
                self.next(); return ('vararg',)
            if t.val == '{':
                return self.tablector()
        return self.suffixedexp()

    def primaryexp(self):
        t = self.peek()
        if t.kind == 'name':
            self.next()
            return ('name', t.val)
        if t.kind == 'op' and t.val == '(':
            self.next()
            e = self.expr()
            self.expect('op', ')')
            return ('paren', e)
        raise ParseError('%s: unexpected symbol %r at %d' % (self.chunk, t.val, t.pos))

    def suffixedexp(self):
        e = self.primaryexp()
        while True:
            t = self.peek()
            if t.kind == 'op':
                if t.val == '.':
                    self.next()
                    k = self.expect('name').val
                    e = ('index', e, ('str', k))
                    continue
                if t.val == '[':
                    self.next()
                    k = self.expr()
                    self.expect('op', ']')
                    e = ('index', e, k)
                    continue
                if t.val == ':':
                    self.next()
                    m = self.expect('name').val
                    args = self.callargs()
                    e = ('method', e, m, args, t.pos)
                    continue
                if t.val in ('(', '{'):
                    e = ('call', e, self.callargs(), t.pos)
                    continue
            if t.kind == 'str':
                e = ('call', e, self.callargs(), t.pos)
                continue
            break
        return e

    def callargs(self):
        t = self.peek()
        if t.kind == 'str':
            self.next()
            return [('str', t.val)]
        if t.kind == 'op' and t.val == '{':
            return [self.tablector()]
        self.expect('op', '(')
        if self.accept('op', ')'):
            return []
        args = self.exprlist()
        self.expect('op', ')')
        return args

    def tablector(self):
        self.expect('op', '{')
        array = []
        hash_ = []
        while not self.check('op', '}'):
            t = self.peek()
            if t.kind == 'op' and t.val == '[':
                self.next()
                k = self.expr()
                self.expect('op', ']')
                self.expect('op', '=')
                hash_.append((k, self.expr()))
            elif t.kind == 'name' and self.peek(1).kind == 'op' and self.peek(1).val == '=':
                self.next(); self.next()
                hash_.append((('str', t.val), self.expr()))
            else:
                array.append(self.expr())
            if not (self.accept('op', ',') or self.accept('op', ';')):
                break
        self.expect('op', '}')
        return ('table', array, hash_)


def parse(src, chunkname='?'):
    return Parser(src, chunkname).parse_chunk()
