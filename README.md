# Roblox UI Libraries

Two standalone interface libraries for Roblox, each with its own visual
identity. Every file is self-contained — no dependencies, no external assets,
no image IDs. Execute one and you get a welcome screen; click **LOAD** and the
main interface builds itself.

| File | Identity | Accent | Layout | Typeface |
|---|---|---|---|---|
| `obsidian.lua` | Dense, technical, hairline borders | Ice cyan | Left sidebar, inset group titles | Gotham + Code |
| `amethyst.lua` | Soft, modern, rounded cards | Violet → magenta gradient | Left sidebar, sliding gradient rail | Nunito + RobotoMono |

Both put navigation on the left. Obsidian marks the active tab with a flat 2px
cyan tick; Amethyst uses a rounded pill with a gradient wash and a rail that
slides between tabs.

> `ember.lua` (amber / terminal styling) is still in the repo but is not part of
> the current set — its palette was rejected.

## Running one

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/chris360-ai/cursor.ai/claude/aa-hub-folder-visibility-1jnuce/obsidian.lua"))()
```

Or paste the file contents straight into your executor.

Default toggle keys: `RightShift` (Obsidian), `RightControl` (Amethyst). Both
configurable via `ToggleKey`.

## Changing Amethyst's typeface

One line near the top of `amethyst.lua`:

```lua
local FAMILY = "Nunito"
```

Other families that suit the design, all shipped with Roblox: `JosefinSans`,
`Ubuntu`, `Montserrat`, `TitilliumWeb`, `GothamSSm`. Numeric values use `MONO`
(default `RobotoMono`) so digits stay aligned in columns.

Weights resolve through `FontFace` on modern clients and fall back to the
classic `Enum.Font` values on older ones, so a missing family degrades rather
than erroring.

## Using one as a library

Each file ends with a clearly marked **DEMO BUILD** block. Delete everything
below that line and you have a bare library — then build your own menu:

```lua
local Obsidian = loadstring(game:HttpGet("<raw url>"))()

local Window = Obsidian:CreateWindow({
    Title     = "my menu",
    Tag       = ".lua",
    Size      = UDim2.new(0, 700, 0, 470),
    ToggleKey = Enum.KeyCode.RightShift,
    OnLoad    = function() print("loaded") end,
})

local Tab     = Window:AddTab("Main")
local Section = Tab:AddSection("General", "left")   -- "left" or "right"

Section:AddToggle({
    Text     = "Enabled",
    Default  = false,
    Flag     = "enabled",
    Callback = function(value)
        -- your function here
    end,
})
```

The container method differs per library, everything else is identical:

- Obsidian → `Tab:AddSection(title, side)`
- Amethyst → `Tab:AddCard(title, side)`

## Elements

Both implement the same set. Every element takes an optional `Callback` and an
optional `Flag`.

```lua
Section:AddLabel("Some text")
Section:AddDivider()

Section:AddToggle({ Text, Default, Flag, Callback })
Section:AddSlider({ Text, Min, Max, Default, Decimals, Suffix, Flag, Callback })
Section:AddButton({ Text, Callback })
Section:AddTextbox({ Text, Default, Placeholder, Flag, Callback })
Section:AddDropdown({ Text, Options, Default, Flag, Callback })
Section:AddKeybind({ Text, Default, Flag, Callback, OnBind })
Section:AddColorpicker({ Text, Default, Flag, Callback })
```

Amethyst's dropdown also supports `Multi = true` for multi-select.

Every element returns a handle:

```lua
local t = Section:AddToggle({ Text = "Enabled" })
t:Set(true)        -- fires the callback
t:Set(true, true)  -- silent, no callback
print(t:Get())
```

## Flags

Anything given a `Flag` writes its current value into the library's flag table,
which is handy for config saving:

```lua
Obsidian.Flags["enabled"]   --> true
Amethyst.Flags["fov"]       --> 90
```

## Notifications

```lua
Obsidian:Notify("text", 3)                  -- message, duration
Amethyst:Notify("Title", "Body text", 3.5)  -- title, body, duration
```

## Live theming

Each library keeps a registry of themed instances, so changing a colour
retints the whole interface at runtime — no rebuild. The **Theme** tab in each
demo shows this: drag the colourpicker and everything updates instantly.
Amethyst's accent is a two-stop gradient, so both ends are separately settable.

## Notes

- These are UI shells only. They draw the interface and route callbacks —
  they contain no game logic. Attach your own functions via `Callback`.
- Mounting is executor-aware: it tries `gethui()`, then `syn.protect_gui`,
  then `CoreGui`, and finally falls back to `PlayerGui` so the files also run
  in Roblox Studio for previewing.
- Sliders, colourpickers and dragging all handle touch input as well as mouse.
