"""Run the loader and capture the virtual machine's entry closure + its scope chain."""
import sys
sys.setrecursionlimit(300000)
import luavm, runobf
from luavm import Table, LuaFunction, Builtin, Userdata, type_name, tostr

SRC = open('obf.lua', encoding='utf8', errors='surrogateescape').read()
LINES = SRC.split('\n')
OFF = len(LINES[0]) + len(LINES[1]) + 2
BODY = LINES[2]
FINAL = BODY.index('(CR,a2,') + OFF


def run(capture_depths=()):
    I = luavm.Interp()
    I.maxdepth = 3000
    runobf.make_roblox_env(I)
    I.capture_depths = capture_depths
    I.vm_entry = None
    I.vm_args = None

    orig_call = luavm.Interp.call

    def call(self, f, args):
        if self.callsites and self.callsites[-1] == FINAL and self.vm_entry is None:
            self.vm_entry = f
            self.vm_args = list(args)
        return orig_call(self, f, args)

    luavm.Interp.call = call
    try:
        I.G.set('script_key', None)
        r = I.run(SRC, [], '=obf')
    finally:
        luavm.Interp.call = orig_call
    return I, r


def scope_chain(fn):
    out = []
    s = fn.scope
    while s is not None:
        out.append(s)
        s = s.parent
    return out


def desc(v, deep=False):
    t = type(v)
    if t is Table:
        return 'Table(arr=%d,hash=%d)' % (len(v.arr), len(v.hash))
    if t is LuaFunction:
        return 'LuaFunction(params=%r,vararg=%s)' % (v.params, v.vararg)
    if t is Builtin:
        return 'Builtin:' + v.name
    if t is str:
        return 'str[%d] %r' % (len(v), v[:50])
    if t is Userdata:
        return 'Userdata:' + v.name
    return repr(v)[:70]


if __name__ == '__main__':
    I, r = run()
    print('vm_entry:', desc(I.vm_entry))
    print('vm_args :', [desc(a) for a in (I.vm_args or [])])
    print('returned:', [desc(x) for x in r])
    ch = scope_chain(I.vm_entry)
    print('\nscope chain depth:', len(ch))
    for i, s in enumerate(ch):
        names = sorted(s.v.keys())
        print('--- scope %d: %d locals ---' % (i, len(names)))
        tabs = [(k, v) for k, v in s.v.items()
                if type(v) is Table and (len(v.arr) + len(v.hash)) > 8]
        tabs.sort(key=lambda kv: -(len(kv[1].arr) + len(kv[1].hash)))
        for k, v in tabs[:14]:
            print('    %-8s %s' % (k, desc(v)))
        strs = [(k, v) for k, v in s.v.items() if type(v) is str and len(v) > 200]
        for k, v in strs[:8]:
            print('    %-8s %s' % (k, desc(v)))
