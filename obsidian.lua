--[[
    OBSIDIAN UI  —  v1.0
    A dense, technical Roblox interface library.

    Identity : near-black surfaces, hairline borders, ice-cyan accent,
               vertical sidebar navigation, inset group titles.

    Usage:
        local Obsidian = loadstring(game:HttpGet("<raw url>"))()
        local Window = Obsidian:CreateWindow({ Title = "obsidian", Tag = ".ui" })
        local Tab    = Window:AddTab("Main")
        local Box    = Tab:AddSection("General", "left")
        Box:AddToggle({ Text = "Enabled", Default = false, Callback = function(v) end })

    Every element accepts a Callback. Attach your own functions there.
    Toggle the interface with RightShift (configurable).
]]

--=========================================================================--
--  SERVICES
--=========================================================================--

local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

--=========================================================================--
--  THEME
--=========================================================================--

local Theme = {
    Background  = Color3.fromRGB(  8,   9,  11),  -- window shell
    Panel       = Color3.fromRGB( 13,  15,  18),  -- content surface
    Element     = Color3.fromRGB( 18,  21,  25),  -- inputs, group fills
    ElementHover= Color3.fromRGB( 24,  28,  33),
    Border      = Color3.fromRGB( 30,  34,  40),
    BorderLight = Color3.fromRGB( 42,  48,  56),
    Accent      = Color3.fromRGB( 53, 214, 232),  -- ice cyan
    AccentDim   = Color3.fromRGB( 30, 120, 132),
    Text        = Color3.fromRGB(214, 220, 228),
    TextDim     = Color3.fromRGB(124, 133, 145),
    TextFaint   = Color3.fromRGB( 78,  86,  96),
    Risk        = Color3.fromRGB(232,  86,  86),
}

-- Instances registered here re-tint live when Theme values change.
local Registry = {}

local function reg(inst, prop, key)
    table.insert(Registry, { inst = inst, prop = prop, key = key })
    inst[prop] = Theme[key]
    return inst
end

local function retint(key, color)
    Theme[key] = color
    for _, e in ipairs(Registry) do
        if e.key == key and e.inst and e.inst.Parent ~= nil then
            pcall(function() e.inst[e.prop] = color end)
        end
    end
end

--=========================================================================--
--  FONTS  (with graceful fallback across client versions)
--=========================================================================--

local function font(name, fallback)
    local ok, f = pcall(function() return Enum.Font[name] end)
    if ok and f then return f end
    return Enum.Font[fallback or "SourceSans"]
end

local F = {
    Label = font("Gotham", "SourceSans"),        -- element labels
    Head  = font("GothamMedium", "SourceSansBold"),-- section / tab titles
    Bold  = font("GothamBold", "SourceSansBold"), -- brand
    Mono  = font("Code", "SourceSans"),           -- values, keybinds
}

--=========================================================================--
--  HELPERS
--=========================================================================--

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 3) })
end

local function stroke(key, thickness, transparency)
    local s = new("UIStroke", {
        Thickness        = thickness or 1,
        Transparency     = transparency or 0,
        ApplyStrokeMode  = Enum.ApplyStrokeMode.Border,
    })
    reg(s, "Color", key or "Border")
    return s
end

local function pad(t, b, l, r)
    return new("UIPadding", {
        PaddingTop    = UDim.new(0, t or 0),
        PaddingBottom = UDim.new(0, b or t or 0),
        PaddingLeft   = UDim.new(0, l or 0),
        PaddingRight  = UDim.new(0, r or l or 0),
    })
end

local function list(padding, dir)
    return new("UIListLayout", {
        Padding   = UDim.new(0, padding or 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = dir or Enum.FillDirection.Vertical,
    })
end

local TW_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_MED  = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_SLOW = TweenInfo.new(0.40, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tween(inst, info, props)
    local t = TweenService:Create(inst, info, props)
    t:Play()
    return t
end

local function round(n, places)
    local m = 10 ^ (places or 0)
    return math.floor(n * m + 0.5) / m
end

--=========================================================================--
--  MOUNT  (executor-aware parenting)
--=========================================================================--

local function mount(gui)
    -- Newer executors
    if typeof(gethui) == "function" then
        local ok = pcall(function() gui.Parent = gethui() end)
        if ok and gui.Parent then return end
    end
    -- Synapse-style protection
    if syn and typeof(syn.protect_gui) == "function" then
        local ok = pcall(function()
            syn.protect_gui(gui)
            gui.Parent = game:GetService("CoreGui")
        end)
        if ok and gui.Parent then return end
    end
    -- CoreGui direct
    local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if ok and gui.Parent then return end
    -- Fallback: PlayerGui (works in Studio / normal play)
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

--=========================================================================--
--  LIBRARY ROOT
--=========================================================================--

local Obsidian = {}
Obsidian.Flags = {}   -- Flags["myflag"] = current value
Obsidian.Theme = Theme

local Screen = new("ScreenGui", {
    Name             = "ObsidianUI",
    ResetOnSpawn     = false,
    ZIndexBehavior   = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset   = true,
    DisplayOrder     = 999,
})
mount(Screen)

--=========================================================================--
--  NOTIFICATIONS
--=========================================================================--

local NotifyHolder = new("Frame", {
    Name                   = "Notifications",
    AnchorPoint            = Vector2.new(1, 1),
    Position               = UDim2.new(1, -16, 1, -16),
    Size                   = UDim2.new(0, 260, 1, -32),
    BackgroundTransparency = 1,
    Parent                 = Screen,
}, {
    new("UIListLayout", {
        Padding             = UDim.new(0, 6),
        SortOrder           = Enum.SortOrder.LayoutOrder,
        VerticalAlignment   = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    }),
})

function Obsidian:Notify(text, duration)
    duration = duration or 3

    local card = new("Frame", {
        Size                   = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        ClipsDescendants       = true,
        Parent                 = NotifyHolder,
    })
    local body = new("Frame", {
        Size     = UDim2.new(1, 0, 0, 36),
        Parent   = card,
    }, { corner(3), stroke("Border") })
    reg(body, "BackgroundColor3", "Panel")

    local rail = new("Frame", {
        Size         = UDim2.new(0, 2, 1, -10),
        Position     = UDim2.new(0, 8, 0, 5),
        BorderSizePixel = 0,
        Parent       = body,
    })
    reg(rail, "BackgroundColor3", "Accent")

    local label = new("TextLabel", {
        Position               = UDim2.new(0, 18, 0, 0),
        Size                   = UDim2.new(1, -26, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Label,
        Text                   = tostring(text),
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = body,
    })
    reg(label, "TextColor3", "Text")

    tween(card, TW_MED, { Size = UDim2.new(1, 0, 0, 36) })

    task.delay(duration, function()
        tween(card, TW_MED, { Size = UDim2.new(1, 0, 0, 0) })
        tween(body, TW_MED, { BackgroundTransparency = 1 })
        tween(label, TW_MED, { TextTransparency = 1 })
        task.wait(0.28)
        card:Destroy()
    end)
end

--=========================================================================--
--  WINDOW
--=========================================================================--

function Obsidian:CreateWindow(cfg)
    cfg = cfg or {}
    local title     = cfg.Title     or "obsidian"
    local tag       = cfg.Tag       or ".ui"
    local size      = cfg.Size      or UDim2.new(0, 700, 0, 470)
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift

    ------------------------------------------------------------------
    -- Shell
    ------------------------------------------------------------------
    local Main = new("Frame", {
        Name             = "Window",
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0.5, 0, 0.5, 0),
        Size             = UDim2.new(0, 0, 0, 0),
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        Visible          = false,
        Parent           = Screen,
    }, { corner(4), stroke("BorderLight") })
    reg(Main, "BackgroundColor3", "Background")

    ------------------------------------------------------------------
    -- Title bar
    ------------------------------------------------------------------
    local TitleBar = new("Frame", {
        Size            = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        Parent          = Main,
    })

    local brand = new("TextLabel", {
        Position               = UDim2.new(0, 14, 0, 0),
        Size                   = UDim2.new(0, 200, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Bold,
        Text                   = title,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = TitleBar,
    })
    reg(brand, "TextColor3", "Text")

    local brandTag = new("TextLabel", {
        Position               = UDim2.new(0, 14 + brand.TextBounds.X, 0, 0),
        Size                   = UDim2.new(0, 120, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Bold,
        Text                   = tag,
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = TitleBar,
    })
    reg(brandTag, "TextColor3", "Accent")
    -- reposition once bounds settle
    task.defer(function()
        brandTag.Position = UDim2.new(0, 14 + brand.TextBounds.X + 1, 0, 0)
    end)

    -- window buttons
    local function winButton(char, offset, hoverKey, onClick)
        local b = new("TextButton", {
            AnchorPoint            = Vector2.new(1, 0.5),
            Position               = UDim2.new(1, -offset, 0.5, 0),
            Size                   = UDim2.new(0, 20, 0, 20),
            BackgroundTransparency = 1,
            AutoButtonColor        = false,
            Font                   = F.Mono,
            Text                   = char,
            TextSize               = 13,
            Parent                 = TitleBar,
        })
        reg(b, "TextColor3", "TextDim")
        b.MouseEnter:Connect(function() b.TextColor3 = Theme[hoverKey] end)
        b.MouseLeave:Connect(function() b.TextColor3 = Theme.TextDim end)
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    local minimized = false
    local fullSize  = size

    winButton("x", 12, "Risk", function()
        tween(Main, TW_MED, { Size = UDim2.new(0, fullSize.X.Offset, 0, 0) })
        task.wait(0.25)
        Screen:Destroy()
    end)

    winButton("-", 38, "Accent", function()
        minimized = not minimized
        tween(Main, TW_MED, {
            Size = minimized and UDim2.new(0, fullSize.X.Offset, 0, 34) or fullSize
        })
    end)

    local sep = new("Frame", {
        Position        = UDim2.new(0, 0, 0, 34),
        Size            = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent          = Main,
    })
    reg(sep, "BackgroundColor3", "Border")

    ------------------------------------------------------------------
    -- Dragging
    ------------------------------------------------------------------
    do
        local dragging, dragStart, startPos
        TitleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging  = true
                dragStart = input.Position
                startPos  = Main.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                local d = input.Position - dragStart
                Main.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end)
    end

    ------------------------------------------------------------------
    -- Sidebar + content
    ------------------------------------------------------------------
    local Sidebar = new("Frame", {
        Position        = UDim2.new(0, 0, 0, 35),
        Size            = UDim2.new(0, 132, 1, -35),
        BackgroundTransparency = 1,
        Parent          = Main,
    }, { pad(10, 10, 8, 8), list(2) })

    local sideLine = new("Frame", {
        Position        = UDim2.new(0, 132, 0, 35),
        Size            = UDim2.new(0, 1, 1, -35),
        BorderSizePixel = 0,
        Parent          = Main,
    })
    reg(sideLine, "BackgroundColor3", "Border")

    local Content = new("Frame", {
        Position               = UDim2.new(0, 133, 0, 35),
        Size                   = UDim2.new(1, -133, 1, -35),
        BackgroundTransparency = 1,
        ClipsDescendants       = true,
        Parent                 = Main,
    })

    ------------------------------------------------------------------
    -- Toggle visibility
    ------------------------------------------------------------------
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == toggleKey then
            Main.Visible = not Main.Visible
        end
    end)

    ------------------------------------------------------------------
    local Window = { Tabs = {}, Main = Main }
    local activeTab

    --==============================================================--
    --  TAB
    --==============================================================--
    function Window:AddTab(name)
        local Tab = {}

        local btn = new("TextButton", {
            Size                   = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            AutoButtonColor        = false,
            Text                   = "",
            Parent                 = Sidebar,
        }, { corner(3) })
        reg(btn, "BackgroundColor3", "Element")

        local indicator = new("Frame", {
            Position        = UDim2.new(0, 0, 0.5, 0),
            AnchorPoint     = Vector2.new(0, 0.5),
            Size            = UDim2.new(0, 2, 0, 0),
            BorderSizePixel = 0,
            Parent          = btn,
        })
        reg(indicator, "BackgroundColor3", "Accent")

        local lbl = new("TextLabel", {
            Position               = UDim2.new(0, 12, 0, 0),
            Size                   = UDim2.new(1, -16, 1, 0),
            BackgroundTransparency = 1,
            Font                   = F.Label,
            Text                   = name,
            TextSize               = 12,
            TextXAlignment         = Enum.TextXAlignment.Left,
            Parent                 = btn,
        })
        reg(lbl, "TextColor3", "TextDim")

        local page = new("Frame", {
            Size                   = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Visible                = false,
            Parent                 = Content,
        }, { pad(12, 12, 12, 12) })

        -- two independent scroll columns, matching the reference layout
        local function column(xScale, xOff)
            local col = new("ScrollingFrame", {
                Position               = UDim2.new(xScale, xOff, 0, 0),
                Size                   = UDim2.new(0.5, -5, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel        = 0,
                ScrollBarThickness     = 2,
                ScrollBarImageColor3   = Theme.BorderLight,
                CanvasSize             = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize    = Enum.AutomaticSize.Y,
                Parent                 = page,
            }, { list(10), pad(0, 12, 0, 4) })
            return col
        end

        local left  = column(0, 0)
        local right = column(0.5, 5)

        btn.MouseEnter:Connect(function()
            if activeTab ~= Tab then lbl.TextColor3 = Theme.Text end
        end)
        btn.MouseLeave:Connect(function()
            if activeTab ~= Tab then lbl.TextColor3 = Theme.TextDim end
        end)

        function Tab:Select()
            for _, t in ipairs(Window.Tabs) do t._deselect() end
            activeTab      = Tab
            page.Visible   = true
            lbl.TextColor3 = Theme.Text
            tween(btn, TW_FAST, { BackgroundTransparency = 0 })
            tween(indicator, TW_FAST, { Size = UDim2.new(0, 2, 0, 16) })
        end

        function Tab._deselect()
            page.Visible   = false
            lbl.TextColor3 = Theme.TextDim
            tween(btn, TW_FAST, { BackgroundTransparency = 1 })
            tween(indicator, TW_FAST, { Size = UDim2.new(0, 2, 0, 0) })
        end

        btn.MouseButton1Click:Connect(function() Tab:Select() end)

        --==========================================================--
        --  SECTION  (group box with inset title, as in the refs)
        --==========================================================--
        function Tab:AddSection(sectionTitle, side)
            local parentCol = (side == "right") and right or left

            local box = new("Frame", {
                Size            = UDim2.new(1, 0, 0, 0),
                AutomaticSize   = Enum.AutomaticSize.Y,
                BorderSizePixel = 0,
                Parent          = parentCol,
            }, { corner(3), stroke("Border") })
            reg(box, "BackgroundColor3", "Panel")

            local inner = new("Frame", {
                Size                   = UDim2.new(1, 0, 0, 0),
                AutomaticSize          = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Parent                 = box,
            }, { list(4), pad(14, 10, 10, 10) })

            -- title sits ON the border line, masking it
            local titleLbl = new("TextLabel", {
                Position       = UDim2.new(0, 9, 0, -6),
                Size           = UDim2.new(0, 0, 0, 12),
                AutomaticSize  = Enum.AutomaticSize.X,
                Font           = F.Head,
                Text           = sectionTitle,
                TextSize       = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                BorderSizePixel= 0,
                ZIndex         = 3,
                Parent         = box,
            }, { pad(0, 0, 4, 4) })
            reg(titleLbl, "TextColor3", "TextDim")
            reg(titleLbl, "BackgroundColor3", "Panel")

            local Section = {}

            --------------------------------------------------------
            local function row(height)
                return new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, height),
                    BackgroundTransparency = 1,
                    Parent                 = inner,
                })
            end

            --------------------------------------------------------
            --  LABEL
            --------------------------------------------------------
            function Section:AddLabel(text)
                local r = row(16)
                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = text,
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextWrapped            = true,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextFaint")
                return {
                    Set = function(_, t) l.Text = t end
                }
            end

            --------------------------------------------------------
            --  DIVIDER
            --------------------------------------------------------
            function Section:AddDivider()
                local r = row(7)
                local d = new("Frame", {
                    Position        = UDim2.new(0, 0, 0.5, 0),
                    Size            = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    Parent          = r,
                })
                reg(d, "BackgroundColor3", "Border")
            end

            --------------------------------------------------------
            --  TOGGLE
            --------------------------------------------------------
            function Section:AddToggle(o)
                o = o or {}
                local state = o.Default or false

                local r = row(18)
                local btn2 = new("TextButton", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    AutoButtonColor        = false,
                    Text                   = "",
                    Parent                 = r,
                })

                local boxOuter = new("Frame", {
                    AnchorPoint     = Vector2.new(0, 0.5),
                    Position        = UDim2.new(0, 0, 0.5, 0),
                    Size            = UDim2.new(0, 13, 0, 13),
                    BorderSizePixel = 0,
                    Parent          = btn2,
                }, { corner(2), stroke("BorderLight") })
                reg(boxOuter, "BackgroundColor3", "Element")

                local fill = new("Frame", {
                    AnchorPoint            = Vector2.new(0.5, 0.5),
                    Position               = UDim2.new(0.5, 0, 0.5, 0),
                    Size                   = UDim2.new(0, 0, 0, 0),
                    BorderSizePixel        = 0,
                    Parent                 = boxOuter,
                }, { corner(1) })
                reg(fill, "BackgroundColor3", "Accent")

                local lbl2 = new("TextLabel", {
                    Position               = UDim2.new(0, 21, 0, 0),
                    Size                   = UDim2.new(1, -21, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Toggle",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = btn2,
                })
                reg(lbl2, "TextColor3", "TextDim")

                local api = {}

                function api:Set(v, silent)
                    state = v and true or false
                    if o.Flag then Obsidian.Flags[o.Flag] = state end
                    tween(fill, TW_FAST, {
                        Size = state and UDim2.new(0, 7, 0, 7) or UDim2.new(0, 0, 0, 0)
                    })
                    lbl2.TextColor3 = state and Theme.Text or Theme.TextDim
                    if not silent and o.Callback then
                        task.spawn(o.Callback, state)
                    end
                end

                function api:Get() return state end

                btn2.MouseButton1Click:Connect(function() api:Set(not state) end)
                btn2.MouseEnter:Connect(function()
                    if not state then lbl2.TextColor3 = Theme.Text end
                end)
                btn2.MouseLeave:Connect(function()
                    if not state then lbl2.TextColor3 = Theme.TextDim end
                end)

                api:Set(state, true)
                return api
            end

            --------------------------------------------------------
            --  SLIDER
            --------------------------------------------------------
            function Section:AddSlider(o)
                o = o or {}
                local min      = o.Min or 0
                local max      = o.Max or 100
                local decimals = o.Decimals or 0
                local value    = math.clamp(o.Default or min, min, max)
                local suffix   = o.Suffix or ""

                local r = row(30)

                local lbl3 = new("TextLabel", {
                    Size                   = UDim2.new(1, -70, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Slider",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(lbl3, "TextColor3", "TextDim")

                local valLbl = new("TextLabel", {
                    AnchorPoint            = Vector2.new(1, 0),
                    Position               = UDim2.new(1, 0, 0, 0),
                    Size                   = UDim2.new(0, 70, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = "",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Right,
                    Parent                 = r,
                })
                reg(valLbl, "TextColor3", "Text")

                local track = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 21),
                    Size            = UDim2.new(1, 0, 0, 4),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(2) })
                reg(track, "BackgroundColor3", "Element")

                local fill2 = new("Frame", {
                    Size            = UDim2.new(0, 0, 1, 0),
                    BorderSizePixel = 0,
                    Parent          = track,
                }, { corner(2) })
                reg(fill2, "BackgroundColor3", "Accent")

                local api = {}

                function api:Set(v, silent)
                    value = math.clamp(round(v, decimals), min, max)
                    if o.Flag then Obsidian.Flags[o.Flag] = value end
                    local alpha = (max == min) and 0 or (value - min) / (max - min)
                    tween(fill2, TW_FAST, { Size = UDim2.new(alpha, 0, 1, 0) })
                    valLbl.Text = tostring(value) .. suffix
                    if not silent and o.Callback then
                        task.spawn(o.Callback, value)
                    end
                end

                function api:Get() return value end

                local sliding = false
                local function fromX(px)
                    local w = track.AbsoluteSize.X
                    if w <= 0 then return end
                    local a = math.clamp((px - track.AbsolutePosition.X) / w, 0, 1)
                    api:Set(min + (max - min) * a)
                end

                track.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                        sliding = true
                        fromX(input.Position.X)
                    end
                end)
                UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                        sliding = false
                    end
                end)
                UserInputService.InputChanged:Connect(function(input)
                    if not sliding then return end
                    if input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch then
                        fromX(input.Position.X)
                    end
                end)

                api:Set(value, true)
                return api
            end

            --------------------------------------------------------
            --  BUTTON
            --------------------------------------------------------
            function Section:AddButton(o)
                o = o or {}
                local r = row(24)
                local b = new("TextButton", {
                    Size            = UDim2.new(1, 0, 1, 0),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Font            = F.Label,
                    Text            = o.Text or "Button",
                    TextSize        = 12,
                    Parent          = r,
                }, { corner(3), stroke("Border") })
                reg(b, "BackgroundColor3", "Element")
                reg(b, "TextColor3", "TextDim")

                b.MouseEnter:Connect(function()
                    tween(b, TW_FAST, { BackgroundColor3 = Theme.ElementHover })
                    b.TextColor3 = Theme.Text
                end)
                b.MouseLeave:Connect(function()
                    tween(b, TW_FAST, { BackgroundColor3 = Theme.Element })
                    b.TextColor3 = Theme.TextDim
                end)
                b.MouseButton1Click:Connect(function()
                    if o.Callback then task.spawn(o.Callback) end
                end)
                return b
            end

            --------------------------------------------------------
            --  TEXTBOX
            --------------------------------------------------------
            function Section:AddTextbox(o)
                o = o or {}
                local r = row(38)

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Input",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local holder = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 17),
                    Size            = UDim2.new(1, 0, 0, 20),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(3), stroke("Border") })
                reg(holder, "BackgroundColor3", "Element")

                local tb = new("TextBox", {
                    Size                   = UDim2.new(1, -14, 1, 0),
                    Position               = UDim2.new(0, 7, 0, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Default or "",
                    PlaceholderText        = o.Placeholder or "...",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    ClearTextOnFocus       = false,
                    Parent                 = holder,
                })
                reg(tb, "TextColor3", "Text")
                reg(tb, "PlaceholderColor3", "TextFaint")

                tb.FocusLost:Connect(function(enter)
                    if o.Flag then Obsidian.Flags[o.Flag] = tb.Text end
                    if o.Callback then task.spawn(o.Callback, tb.Text, enter) end
                end)
                return tb
            end

            --------------------------------------------------------
            --  DROPDOWN
            --------------------------------------------------------
            function Section:AddDropdown(o)
                o = o or {}
                local options  = o.Options or {}
                local selected = o.Default or (options[1] or "None")
                local open     = false

                local r = new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, 38),
                    BackgroundTransparency = 1,
                    ClipsDescendants       = true,
                    Parent                 = inner,
                })

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Dropdown",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local head = new("TextButton", {
                    Position        = UDim2.new(0, 0, 0, 17),
                    Size            = UDim2.new(1, 0, 0, 20),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Text            = "",
                    Parent          = r,
                }, { corner(3), stroke("Border") })
                reg(head, "BackgroundColor3", "Element")

                local sel = new("TextLabel", {
                    Position               = UDim2.new(0, 7, 0, 0),
                    Size                   = UDim2.new(1, -26, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = tostring(selected),
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextTruncate           = Enum.TextTruncate.AtEnd,
                    Parent                 = head,
                })
                reg(sel, "TextColor3", "Text")

                local arrow = new("TextLabel", {
                    AnchorPoint            = Vector2.new(1, 0.5),
                    Position               = UDim2.new(1, -7, 0.5, 0),
                    Size                   = UDim2.new(0, 10, 0, 10),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = "+",
                    TextSize               = 12,
                    Parent                 = head,
                })
                reg(arrow, "TextColor3", "TextDim")

                local listHolder = new("Frame", {
                    Position               = UDim2.new(0, 0, 0, 39),
                    Size                   = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Parent                 = r,
                }, { list(1) })

                local api = { Selected = selected }

                local function rebuild()
                    for _, c in ipairs(listHolder:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for _, opt in ipairs(options) do
                        local ob = new("TextButton", {
                            Size            = UDim2.new(1, 0, 0, 18),
                            AutoButtonColor = false,
                            BorderSizePixel = 0,
                            Font            = F.Mono,
                            Text            = "  " .. tostring(opt),
                            TextSize        = 11,
                            TextXAlignment  = Enum.TextXAlignment.Left,
                            Parent          = listHolder,
                        }, { corner(2) })
                        reg(ob, "BackgroundColor3", "Element")
                        ob.TextColor3 = (opt == api.Selected) and Theme.Accent or Theme.TextDim

                        ob.MouseEnter:Connect(function()
                            tween(ob, TW_FAST, { BackgroundColor3 = Theme.ElementHover })
                        end)
                        ob.MouseLeave:Connect(function()
                            tween(ob, TW_FAST, { BackgroundColor3 = Theme.Element })
                        end)
                        ob.MouseButton1Click:Connect(function()
                            api:Set(opt)
                            open = false
                            tween(r, TW_FAST, { Size = UDim2.new(1, 0, 0, 38) })
                            arrow.Text = "+"
                        end)
                    end
                end

                function api:Set(v, silent)
                    api.Selected = v
                    sel.Text = tostring(v)
                    if o.Flag then Obsidian.Flags[o.Flag] = v end
                    rebuild()
                    if not silent and o.Callback then task.spawn(o.Callback, v) end
                end

                function api:SetOptions(t)
                    options = t
                    rebuild()
                end

                head.MouseButton1Click:Connect(function()
                    open = not open
                    local h = open and (39 + #options * 19) or 38
                    tween(r, TW_FAST, { Size = UDim2.new(1, 0, 0, h) })
                    arrow.Text = open and "-" or "+"
                end)

                rebuild()
                if o.Flag then Obsidian.Flags[o.Flag] = selected end
                return api
            end

            --------------------------------------------------------
            --  KEYBIND
            --------------------------------------------------------
            function Section:AddKeybind(o)
                o = o or {}
                local bound   = o.Default
                local binding = false

                local r = row(20)

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, -70, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Keybind",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local kb = new("TextButton", {
                    AnchorPoint     = Vector2.new(1, 0.5),
                    Position        = UDim2.new(1, 0, 0.5, 0),
                    Size            = UDim2.new(0, 62, 0, 17),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Font            = F.Mono,
                    Text            = bound and bound.Name or "[ none ]",
                    TextSize        = 10,
                    Parent          = r,
                }, { corner(2), stroke("Border") })
                reg(kb, "BackgroundColor3", "Element")
                reg(kb, "TextColor3", "TextDim")

                kb.MouseButton1Click:Connect(function()
                    binding  = true
                    kb.Text  = "[ ... ]"
                    kb.TextColor3 = Theme.Accent
                end)

                UserInputService.InputBegan:Connect(function(input, gpe)
                    if binding and input.UserInputType == Enum.UserInputType.Keyboard then
                        binding = false
                        if input.KeyCode == Enum.KeyCode.Backspace then
                            bound   = nil
                            kb.Text = "[ none ]"
                        else
                            bound   = input.KeyCode
                            kb.Text = bound.Name
                        end
                        kb.TextColor3 = Theme.TextDim
                        if o.Flag then Obsidian.Flags[o.Flag] = bound end
                        if o.OnBind then task.spawn(o.OnBind, bound) end
                        return
                    end
                    if gpe then return end
                    if bound and input.KeyCode == bound and o.Callback then
                        task.spawn(o.Callback)
                    end
                end)

                return {
                    Get = function() return bound end,
                    Set = function(_, k)
                        bound   = k
                        kb.Text = k and k.Name or "[ none ]"
                    end,
                }
            end

            --------------------------------------------------------
            --  COLORPICKER
            --------------------------------------------------------
            function Section:AddColorpicker(o)
                o = o or {}
                local col   = o.Default or Theme.Accent
                local h, s, v = Color3.toHSV(col)
                local open  = false

                local r = new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, 20),
                    BackgroundTransparency = 1,
                    ClipsDescendants       = true,
                    Parent                 = inner,
                })

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, -40, 0, 20),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Color",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local swatch = new("TextButton", {
                    AnchorPoint     = Vector2.new(1, 0),
                    Position        = UDim2.new(1, 0, 0, 3),
                    Size            = UDim2.new(0, 32, 0, 14),
                    BackgroundColor3= col,
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Text            = "",
                    Parent          = r,
                }, { corner(2), stroke("BorderLight") })

                -- picker body
                local body2 = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 24),
                    Size            = UDim2.new(1, 0, 0, 96),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(3), stroke("Border") })
                reg(body2, "BackgroundColor3", "Element")

                local field = new("Frame", {
                    Position         = UDim2.new(0, 8, 0, 8),
                    Size             = UDim2.new(1, -16, 0, 62),
                    BackgroundColor3 = Color3.fromHSV(h, 1, 1),
                    BorderSizePixel  = 0,
                    Parent           = body2,
                }, { corner(2) })

                new("Frame", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3       = Color3.new(1, 1, 1),
                    BorderSizePixel        = 0,
                    Parent                 = field,
                }, {
                    corner(2),
                    new("UIGradient", {
                        Transparency = NumberSequence.new({
                            NumberSequenceKeypoint.new(0, 0),
                            NumberSequenceKeypoint.new(1, 1),
                        }),
                    }),
                })

                new("Frame", {
                    Size             = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3 = Color3.new(0, 0, 0),
                    BorderSizePixel  = 0,
                    Parent           = field,
                }, {
                    corner(2),
                    new("UIGradient", {
                        Rotation     = 90,
                        Transparency = NumberSequence.new({
                            NumberSequenceKeypoint.new(0, 1),
                            NumberSequenceKeypoint.new(1, 0),
                        }),
                    }),
                })

                local cursor = new("Frame", {
                    AnchorPoint            = Vector2.new(0.5, 0.5),
                    Size                   = UDim2.new(0, 7, 0, 7),
                    BackgroundTransparency = 1,
                    ZIndex                 = 5,
                    Parent                 = field,
                }, {
                    corner(4),
                    new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5 }),
                })

                local hueBar = new("Frame", {
                    Position        = UDim2.new(0, 8, 0, 76),
                    Size            = UDim2.new(1, -16, 0, 10),
                    BorderSizePixel = 0,
                    Parent          = body2,
                }, {
                    corner(2),
                    new("UIGradient", {
                        Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,   0,   0)),
                            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255,   0)),
                            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(  0, 255,   0)),
                            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(  0, 255, 255)),
                            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(  0,   0, 255)),
                            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255,   0, 255)),
                            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255,   0,   0)),
                        }),
                    }),
                })

                local hueCursor = new("Frame", {
                    AnchorPoint      = Vector2.new(0.5, 0.5),
                    Position         = UDim2.new(0, 0, 0.5, 0),
                    Size             = UDim2.new(0, 3, 1, 4),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel  = 0,
                    ZIndex           = 5,
                    Parent           = hueBar,
                }, { corner(1) })

                local api = {}

                local function push(silent)
                    col = Color3.fromHSV(h, s, v)
                    swatch.BackgroundColor3 = col
                    field.BackgroundColor3  = Color3.fromHSV(h, 1, 1)
                    cursor.Position         = UDim2.new(s, 0, 1 - v, 0)
                    hueCursor.Position      = UDim2.new(h, 0, 0.5, 0)
                    if o.Flag then Obsidian.Flags[o.Flag] = col end
                    if not silent and o.Callback then task.spawn(o.Callback, col) end
                end

                function api:Set(c, silent)
                    h, s, v = Color3.toHSV(c)
                    push(silent)
                end
                function api:Get() return col end

                -- field dragging
                local fieldDrag, hueDrag = false, false
                local function fieldFrom(p)
                    local sz = field.AbsoluteSize
                    if sz.X <= 0 then return end
                    s = math.clamp((p.X - field.AbsolutePosition.X) / sz.X, 0, 1)
                    v = 1 - math.clamp((p.Y - field.AbsolutePosition.Y) / sz.Y, 0, 1)
                    push()
                end
                local function hueFrom(p)
                    local sz = hueBar.AbsoluteSize
                    if sz.X <= 0 then return end
                    h = math.clamp((p.X - hueBar.AbsolutePosition.X) / sz.X, 0, 1)
                    push()
                end

                field.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                        fieldDrag = true; fieldFrom(i.Position)
                    end
                end)
                hueBar.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                        hueDrag = true; hueFrom(i.Position)
                    end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                        fieldDrag, hueDrag = false, false
                    end
                end)
                UserInputService.InputChanged:Connect(function(i)
                    if i.UserInputType ~= Enum.UserInputType.MouseMovement
                    and i.UserInputType ~= Enum.UserInputType.Touch then return end
                    if fieldDrag then fieldFrom(i.Position) end
                    if hueDrag   then hueFrom(i.Position)   end
                end)

                swatch.MouseButton1Click:Connect(function()
                    open = not open
                    tween(r, TW_FAST, { Size = UDim2.new(1, 0, 0, open and 124 or 20) })
                end)

                push(true)
                return api
            end

            return Section
        end

        table.insert(Window.Tabs, Tab)
        if #Window.Tabs == 1 then Tab:Select() end
        return Tab
    end

    --==============================================================--
    --  WELCOME / LOADER
    --==============================================================--
    local Welcome = new("Frame", {
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0.5, 0, 0.5, 0),
        Size             = UDim2.new(0, 0, 0, 0),
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        Parent           = Screen,
    }, { corner(4), stroke("BorderLight") })
    reg(Welcome, "BackgroundColor3", "Background")

    local wTitle = new("TextLabel", {
        Position               = UDim2.new(0, 0, 0, 42),
        Size                   = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Font                   = F.Bold,
        Text                   = title .. tag,
        TextSize               = 22,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wTitle, "TextColor3", "Text")

    local wSub = new("TextLabel", {
        Position               = UDim2.new(0, 0, 0, 70),
        Size                   = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "welcome back, " .. (LocalPlayer and LocalPlayer.DisplayName or "guest"),
        TextSize               = 12,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wSub, "TextColor3", "TextDim")

    local wLine = new("Frame", {
        AnchorPoint     = Vector2.new(0.5, 0),
        Position        = UDim2.new(0.5, 0, 0, 100),
        Size            = UDim2.new(0, 0, 0, 1),
        BorderSizePixel = 0,
        Parent          = Welcome,
    })
    reg(wLine, "BackgroundColor3", "Border")

    local wStatus = new("TextLabel", {
        Position               = UDim2.new(0, 0, 0, 116),
        Size                   = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "",
        TextSize               = 11,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wStatus, "TextColor3", "TextFaint")

    local wBarBg = new("Frame", {
        AnchorPoint            = Vector2.new(0.5, 0),
        Position               = UDim2.new(0.5, 0, 0, 136),
        Size                   = UDim2.new(0, 240, 0, 3),
        BorderSizePixel        = 0,
        BackgroundTransparency = 1,
        Parent                 = Welcome,
    }, { corner(2) })
    reg(wBarBg, "BackgroundColor3", "Element")

    local wBar = new("Frame", {
        Size                   = UDim2.new(0, 0, 1, 0),
        BorderSizePixel        = 0,
        BackgroundTransparency = 1,
        Parent                 = wBarBg,
    }, { corner(2) })
    reg(wBar, "BackgroundColor3", "Accent")

    local wBtn = new("TextButton", {
        AnchorPoint     = Vector2.new(0.5, 0),
        Position        = UDim2.new(0.5, 0, 0, 162),
        Size            = UDim2.new(0, 120, 0, 30),
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Font            = F.Head,
        Text            = "L O A D",
        TextSize        = 12,
        BackgroundTransparency = 1,
        TextTransparency       = 1,
        Parent          = Welcome,
    }, { corner(3), stroke("BorderLight") })
    reg(wBtn, "BackgroundColor3", "Element")
    reg(wBtn, "TextColor3", "Text")

    wBtn.MouseEnter:Connect(function()
        tween(wBtn, TW_FAST, { BackgroundColor3 = Theme.ElementHover })
    end)
    wBtn.MouseLeave:Connect(function()
        tween(wBtn, TW_FAST, { BackgroundColor3 = Theme.Element })
    end)

    -- intro animation
    task.spawn(function()
        tween(Welcome, TW_SLOW, { Size = UDim2.new(0, 340, 0, 218) })
        task.wait(0.30)
        tween(wTitle,  TW_MED, { TextTransparency = 0 })
        task.wait(0.08)
        tween(wSub,    TW_MED, { TextTransparency = 0 })
        tween(wLine,   TW_MED, { Size = UDim2.new(0, 280, 0, 1) })
        task.wait(0.08)
        tween(wBtn,    TW_MED, { TextTransparency = 0, BackgroundTransparency = 0 })
    end)

    local loaded = false
    wBtn.MouseButton1Click:Connect(function()
        if loaded then return end
        loaded = true

        tween(wBtn, TW_FAST, { TextTransparency = 1, BackgroundTransparency = 1 })
        wBtn.Active = false
        tween(wBarBg,  TW_FAST, { BackgroundTransparency = 0 })
        tween(wBar,    TW_FAST, { BackgroundTransparency = 0 })
        tween(wStatus, TW_FAST, { TextTransparency = 0 })

        local steps = {
            { "initialising interface", 0.25 },
            { "building components",    0.55 },
            { "applying theme",         0.80 },
            { "ready",                  1.00 },
        }

        task.spawn(function()
            for _, step in ipairs(steps) do
                wStatus.Text = step[1]
                tween(wBar, TweenInfo.new(0.30, Enum.EasingStyle.Quad), {
                    Size = UDim2.new(step[2], 0, 1, 0)
                })
                task.wait(0.34)
            end
            task.wait(0.20)

            -- collapse welcome, expand window
            tween(Welcome, TW_MED, { Size = UDim2.new(0, 340, 0, 0) })
            task.wait(0.24)
            Welcome:Destroy()

            Main.Visible = true
            fullSize = size
            tween(Main, TW_SLOW, { Size = size })

            if cfg.OnLoad then task.spawn(cfg.OnLoad) end
        end)
    end)

    return Window
end

--=========================================================================--
--  DEMO BUILD
--  Delete everything below this line to use OBSIDIAN as a pure library.
--=========================================================================--

local Window = Obsidian:CreateWindow({
    Title     = "obsidian",
    Tag       = ".ui",
    Size      = UDim2.new(0, 700, 0, 470),
    ToggleKey = Enum.KeyCode.RightShift,
    OnLoad    = function()
        Obsidian:Notify("interface loaded  •  RightShift to toggle", 4)
    end,
})

-------------------------------------------------- HOME
do
    local Tab = Window:AddTab("Home")

    local a = Tab:AddSection("Overview", "left")
    a:AddLabel("A dense, technical interface library for Roblox.")
    a:AddLabel("Hairline borders, inset group titles, one accent.")
    a:AddDivider()
    a:AddButton({
        Text = "Send test notification",
        Callback = function() Obsidian:Notify("this is a notification", 3) end,
    })

    local b = Tab:AddSection("Session", "left")
    b:AddLabel("user   " .. (LocalPlayer and LocalPlayer.Name or "unknown"))
    b:AddLabel("place  " .. tostring(game.PlaceId))

    local c = Tab:AddSection("Elements", "right")
    c:AddToggle({ Text = "Example toggle", Flag = "demo_toggle", Default = true,
        Callback = function(v) print("[obsidian] toggle:", v) end })
    c:AddToggle({ Text = "Second toggle", Flag = "demo_toggle2" })
    c:AddSlider({ Text = "Example slider", Min = 0, Max = 100, Default = 42, Suffix = "%",
        Flag = "demo_slider", Callback = function(v) print("[obsidian] slider:", v) end })
    c:AddSlider({ Text = "Decimal slider", Min = 0, Max = 5, Default = 1.25, Decimals = 2,
        Suffix = " x", Flag = "demo_slider2" })
    c:AddKeybind({ Text = "Example keybind", Default = Enum.KeyCode.F,
        Callback = function() Obsidian:Notify("keybind fired", 2) end })

    local d = Tab:AddSection("Inputs", "right")
    d:AddDropdown({ Text = "Example dropdown", Options = { "Alpha", "Bravo", "Charlie", "Delta" },
        Default = "Alpha", Flag = "demo_drop",
        Callback = function(v) print("[obsidian] dropdown:", v) end })
    d:AddTextbox({ Text = "Example textbox", Placeholder = "type here...", Flag = "demo_text" })
end

-------------------------------------------------- INTERFACE
do
    local Tab = Window:AddTab("Interface")

    local a = Tab:AddSection("Window", "left")
    a:AddToggle({ Text = "Lock position", Flag = "ui_lock" })
    a:AddSlider({ Text = "Background opacity", Min = 0, Max = 100, Default = 100,
        Suffix = "%", Flag = "ui_opacity",
        Callback = function(v) Window.Main.BackgroundTransparency = 1 - (v / 100) end })
    a:AddKeybind({ Text = "Toggle interface", Default = Enum.KeyCode.RightShift })

    local b = Tab:AddSection("Notifications", "left")
    b:AddToggle({ Text = "Enabled", Default = true, Flag = "ui_notify" })
    b:AddSlider({ Text = "Duration", Min = 1, Max = 10, Default = 3, Suffix = "s",
        Flag = "ui_notify_time" })

    local c = Tab:AddSection("Preview", "right")
    c:AddLabel("Every element supports a Callback and an optional Flag.")
    c:AddLabel("Flags land in Obsidian.Flags[\"name\"].")
    c:AddDivider()
    c:AddButton({ Text = "Dump flags to console", Callback = function()
        for k, v in pairs(Obsidian.Flags) do print("[flag]", k, v) end
        Obsidian:Notify("flags printed to console", 3)
    end })
end

-------------------------------------------------- THEME
do
    local Tab = Window:AddTab("Theme")

    local a = Tab:AddSection("Palette", "left")
    a:AddLabel("Pick a colour — the whole interface retints live.")
    a:AddDivider()
    a:AddColorpicker({ Text = "Accent", Default = Theme.Accent,
        Callback = function(c) retint("Accent", c) end })
    a:AddColorpicker({ Text = "Text", Default = Theme.Text,
        Callback = function(c) retint("Text", c) end })
    a:AddColorpicker({ Text = "Border", Default = Theme.Border,
        Callback = function(c) retint("Border", c) end })

    local b = Tab:AddSection("Presets", "right")
    local presets = {
        { "Ice",     Color3.fromRGB( 53, 214, 232) },
        { "Violet",  Color3.fromRGB(150, 110, 255) },
        { "Ember",   Color3.fromRGB(255, 154,  60) },
        { "Lime",    Color3.fromRGB(150, 235,  90) },
        { "Rose",    Color3.fromRGB(255, 100, 150) },
    }
    for _, p in ipairs(presets) do
        b:AddButton({ Text = p[1], Callback = function()
            retint("Accent", p[2])
            Obsidian:Notify("accent -> " .. p[1], 2)
        end })
    end
end

-------------------------------------------------- SETTINGS
do
    local Tab = Window:AddTab("Settings")

    local a = Tab:AddSection("Configuration", "left")
    a:AddTextbox({ Text = "Config name", Placeholder = "default", Flag = "cfg_name" })
    a:AddButton({ Text = "Save",   Callback = function() Obsidian:Notify("save hook not attached", 3) end })
    a:AddButton({ Text = "Load",   Callback = function() Obsidian:Notify("load hook not attached", 3) end })
    a:AddButton({ Text = "Delete", Callback = function() Obsidian:Notify("delete hook not attached", 3) end })

    local b = Tab:AddSection("Danger", "right")
    b:AddLabel("Unloading destroys the interface entirely.")
    b:AddDivider()
    b:AddButton({ Text = "Unload", Callback = function()
        Obsidian:Notify("unloading...", 1)
        task.wait(1)
        Screen:Destroy()
    end })
end

return Obsidian
