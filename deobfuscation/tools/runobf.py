"""Run the obfuscated chunk under the Python Lua VM with a Roblox-shaped env."""
import sys, traceback
sys.setrecursionlimit(300000)
import luavm
from luavm import Table, Builtin, Userdata, LuaError, type_name, tostr
from lualib import mk, arg


def make_roblox_env(I):
    G = I.G

    # typeof(): like type() but Roblox instances report their class
    def _typeof(I, a):
        v = arg(a, 0)
        if isinstance(v, Userdata):
            return [v.name]
        return [type_name(v)]
    mk(G, 'typeof', _typeof)

    # Instance.new(class) -> opaque userdata
    Instance = Table()
    G.set('Instance', Instance)

    def _inew(I, a):
        u = Userdata(arg(a, 0, 'Instance'))
        u.mt = Table()
        return [u]
    mk(Instance, 'new', _inew)

    def _vec_new(I, a, _n, comps):
        u = Userdata(_n)
        u.mt = Table()
        fields = Table()
        for i, c in enumerate(comps):
            val = arg(a, i, 0) or 0
            if _n == 'Vector3int16':
                val = int(val) & 0xFFFF
                if val >= 0x8000:
                    val -= 0x10000
            fields.set(c, val)
        # expose components through the userdata's metatable __index
        u.mt.set('__index', fields)
        return [u]

    for name, comps in (('Vector3int16', 'XYZ'), ('Vector3', 'XYZ'),
                        ('Vector2', 'XY'), ('Color3', ('R', 'G', 'B')),
                        ('CFrame', 'XYZ'), ('UDim2', ('X', 'Y'))):
        t = Table()
        mk(t, 'new', lambda I, a, _n=name, _c=comps: _vec_new(I, a, _n, _c))
        G.set(name, t)

    game = Userdata('DataModel')
    gmt = Table()

    def _gindex(I, a):
        return [None]
    gmt.set('__index', Builtin(_gindex, 'game.__index'))
    game.mt = gmt
    G.set('game', game)
    G.set('workspace', Userdata('Workspace'))

    task = Table()
    for n in ('wait', 'spawn', 'delay', 'defer'):
        mk(task, n, lambda I, a: [])
    G.set('task', task)
    mk(G, 'wait', lambda I, a: [0])
    mk(G, 'spawn', lambda I, a: [])
    mk(G, 'delay', lambda I, a: [])
    mk(G, 'tick', lambda I, a: [1750000000])
    mk(G, 'require', lambda I, a: [None])
    G.set('script', Userdata('LocalScript'))
    G.set('shared', Table())

    Enum = Table()
    emt = Table()
    emt.set('__index', Builtin(lambda I, a: [Userdata('EnumItem')], 'Enum.__index'))
    Enum.mt = emt
    G.set('Enum', Enum)


def main(path, keep_going=True):
    I = luavm.Interp()
    I.maxdepth = 3000
    make_roblox_env(I)
    src = open(path, encoding='utf8', errors='surrogateescape').read()
    I.G.set('script_key', None)
    try:
        r = I.run(src, [], '=obf')
        print('CHUNK RETURNED:', [type_name(v) for v in r])
        return I, r
    except LuaError as e:
        print('LUA ERROR:', tostr(I, e.value))
    except Exception:
        traceback.print_exc()
    return I, None


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'obf.lua')
