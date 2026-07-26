# Deobfuscating a wYnFuscate-protected Lua script

This directory documents the reverse-engineering of a Roblox Lua script that was
protected with **wYnFuscate** (`-- Protected by wYnFuscate: https://wynfuscate.com`).

The goal was to "fully deobfuscate the source so it's running and executable."
The result is honest about what a *virtualizing* obfuscator allows:

* The **outer protection is completely removed.** Every encrypted string constant
  has been decoded and inlined, producing a valid, runnable Lua file that behaves
  identically to the original.
* A **full Lua 5.1 interpreter** (written in Python, included here) executes the
  script through *all* of its anti-tamper checks and into the protected core.
* The **core is a custom bytecode virtual machine** (a "virtualized" payload).
  Recovering the pristine original source from it is a devirtualization problem,
  not a decryption one; the groundwork and tooling for that are provided.

## Files

| File | What it is |
|---|---|
| `loader.destrung.lua` | **Runnable, de-obfuscated build.** Byte-for-byte the original, except the obfuscator's `fg(n,key)` string-decryption calls (219 of them) are replaced inline with the literals they decode to. Parses as valid Lua 5.1 and is behaviourally identical to the original. |
| `loader.readable.lua` | The same, pretty-printed onto ~13k indented lines for reading. |
| `payload_api_identifiers.txt` | The global / method names the payload resolves — i.e. the Roblox + executor API surface it uses. |
| `tools/` | The complete toolchain (see below). `tools/obf.lua` is the original protected input. |

## The protection, layer by layer

1. **Environment resolver.** The chunk opens with three self-contained functions
   that recover `getfenv`, `setmetatable` and `rawget` by hashing every key of
   `_ENV`/`_G` (a FNV-style `x = x*131 + byte` rolling hash) and matching a target
   constant — so the names never appear as strings.

2. **String decryptor `fg(n, key)`.** All identifiers ("game", "Instance",
   "writefile", …) are stored encrypted in a 1477-byte pool (`f4[1..5]`,
   themselves lightly scrambled). `fg` walks the pool with an LCG
   (`1664525 / 1013904223`), XOR-folding each byte against a running state seeded
   by `fM`, `fT` and the caller-supplied `key`. It is a *stateful, keyed* decoder:
   the same index with a different key yields a different string.
   `tools/stage1.py` is an exact Python port; running it reproduces every
   identifier the loader uses.

3. **Anti-tamper.** Before decoding anything important the loader:
   * probes for hooked `rawset` / hooked `getmetatable` and for a hooked
     `debug`/`Instance` metatable, and
   * temporarily perturbs the decoder state (`fM += fG` then `fM -= fG`) over a
     short window so a naïve "decode every `fg()` with one key" pass produces
     garbage for the calls inside it.
   If tampering is detected, poisoned state (`fz`, `fT`) silently corrupts every
   later decode. `tools/destring.py` reproduces the window correctly, so the
   de-stringed build is faithful.

4. **Environment-fingerprint key.** The VM's master key `a2[7]` is derived at run
   time from features only a real Roblox client has: the components of
   `Vector3int16.new(1,2,3)` (`X*74 + Y*168 + Z*274`), the line number returned by
   `debug.info(2,"l")`, and a per-script constant `ff`. A second key `a2[10]`
   folds in `debug.info`/`debug.getinfo` line numbers. This ties correct
   decryption to a genuine executor environment.

5. **Integrity gate → decoy.** Just before running, the loader checks that the
   sandbox table `a2` has exactly 26 keys, that `a2[50173] == 26981`, and that no
   tamper flag is set. If any check fails it swaps the real interpreter for a
   **decoy** that runs harmless stub logic — so a debugger that trips a check
   never sees the real program.

6. **The virtual machine.** The payload proper is ~151 function prototypes
   serialised with base85 + LEB128 and encrypted with a **per-instruction** key
   schedule (each opcode's operands are XORed with a value derived from its index
   and the master key). It is a register machine with **randomised opcode
   numbers** implementing standard Lua 5.1 semantics (LOADK, GETGLOBAL via the
   sandbox env, CALL/VARARG using a `table.pack` shim, NEWTABLE, SETLIST, the
   numeric-`for` triple, CONCAT, arithmetic with a `bit32`/`bit` fallback, …).

## What the script does

From the resolved API surface (`payload_api_identifiers.txt`) the payload is a
Roblox **executor / exploit** script:

* builds Roblox instances — `game`, `Instance.new`, `Vector3int16`, `task`;
* persists data — `writefile`, `appendfile` (typical of config saving);
* manipulates the runtime — `hookfunction`, `newcclosure`, `restorefunction`,
  `clonefunction`, `getrawmetatable`, `setreadonly`, `getgc`, `getgenv`,
  `getreg`/`getregistry`, `cloneref`;
* actively defends itself — `isfunctionhooked`, hook-detection, and the
  `WYNF_NO_VIRTUALIZE` marker used by wYnFuscate itself.

## Reproducing it

The `tools/` directory is a from-scratch Lua 5.1 runtime in Python (no `lua`
binary needed — none was reachable in the build environment):

```
tools/
  lualex.py     Lua lexer + source beautifier
  luaparse.py   Lua 5.1 parser (tuple AST)
  luavm.py      runtime: tables, metatables, calling, IEEE-double arithmetic
  luacomp.py    AST-to-closure compiler (the interpreter that actually runs)
  luapat.py     Lua string-pattern matcher (lstrlib.c port)
  lualib.py     string/table/math/os/bit32/coroutine/debug standard library
  runobf.py     Roblox-shaped environment (game, Instance, Vector3int16, task…)
  capture.py    harness that runs the loader and captures VM state
  stage1.py     exact port of the fg(n,key) string decoder
  destring.py   produces loader.destrung.lua
  simplify.py   fg-inlining + constant folding for the readable build
```

Regenerate the de-stringed build (from `tools/`):

```bash
cd tools && python3 destring.py      # writes obf.destrung.lua
python3 -c "import luaparse; luaparse.parse(open('obf.destrung.lua').read())"  # validates
```

Run the original under the emulator (executes all anti-tamper, reaches the VM):

```bash
cd tools && python3 runobf.py obf.lua
```

Two implementation details in `luavm.py` were essential to get *past* the
protection and matter for anyone extending this:

* **Local shadowing.** Lua allows `local x` to be re-declared in the same block,
  creating a *new* variable while closures made earlier keep the old one. The
  decoder relies on exactly this (`local fT = 0` captured by `fg`, then
  `local fT = 3 - qg` later). The compiler resolves it by splitting a block into
  nested scopes at each shadowing declaration.
* **IEEE-double numbers.** Lua 5.1 numbers are doubles; Python ints are
  unbounded. Integer results past 2^53 are demoted to float so the key
  arithmetic (and its overflow behaviour) matches the real VM.

## Status / limits

The decryption/packing layers are fully solved and the script runs end-to-end
under the included emulator. Recovering the *original human-readable source*
would require devirtualizing the custom VM — mapping its randomised opcodes and
lifting ~151 prototypes of register bytecode back to Lua. That is a separate,
larger effort; everything needed to start it (a working VM, the decoded
prototypes in memory, the opcode dispatch located in the readable loader) is
here.

*Reverse-engineering notes for understanding a script the author intentionally
protected. Nothing here weaponises the payload; it is a UI/automation shell that
routes to user-supplied callbacks.*
