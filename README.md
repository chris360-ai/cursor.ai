# Roblox UI Libraries

Three standalone interface libraries for Roblox, each with its own visual
identity. Every file is self-contained — no dependencies, no external assets,
no image IDs. Execute one and you get a welcome screen; click **LOAD** and the
main interface builds itself.

| File | Identity | Accent | Layout | Fonts |
|---|---|---|---|---|
| `obsidian.lua` | Dense, technical, hairline borders | Ice cyan | Vertical sidebar, inset group titles | Gotham + Code |
| `amethyst.lua` | Soft, modern, rounded cards | Violet → magenta gradient | Top tab bar, sliding underline | Gotham + RobotoMono |
| `ember.lua` | Industrial, terminal-flavoured | Amber | Segmented pill nav, live status footer | RobotoMono + Oswald |

## Running one

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/chris360-ai/cursor.ai/claude/aa-hub-folder-visibility-1jnuce/obsidian.lua"))()
```

Or paste the file contents straight into your executor.

Default toggle keys: `RightShift` (Obsidian), `RightControl` (Amethyst),
`Insert` (Ember). All configurable.

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
- Ember → `Tab:AddGroup(title, side)`

## Elements

All three implement the same set. Every element takes an optional `Callback`
and an optional `Flag`.

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
Ember.Flags["accent"]       --> Color3
```

## Notifications

```lua
Obsidian:Notify("text", 3)                  -- message, duration
Amethyst:Notify("Title", "Body text", 3.5)  -- title, body, duration
Ember:Notify("text", 3)                     -- message, duration
```

Ember additionally has a scriptable footer: `Ember:SetStatus("text")`.

## Live theming

Each library keeps a registry of themed instances, so changing a colour
retints the whole interface at runtime — no rebuild. The **Theme** tab in each
demo shows this: drag the colourpicker and everything updates instantly.

## Notes

- These are UI shells only. They draw the interface and route callbacks —
  they contain no game logic. Attach your own functions via `Callback`.
- Mounting is executor-aware: it tries `gethui()`, then `syn.protect_gui`,
  then `CoreGui`, and finally falls back to `PlayerGui` so the files also run
  in Roblox Studio for previewing.
- Fonts resolve through a fallback helper, so a client missing `RobotoMono` or
  `Oswald` degrades to `Code` / `GothamMedium` rather than erroring.
- Sliders, colourpickers and dragging all handle touch input as well as mouse.
