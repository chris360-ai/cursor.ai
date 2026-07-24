--[[
    EMBER UI  —  v1.0
    An industrial, terminal-flavoured Roblox interface library.

    Identity : warm charcoal surfaces, amber accent, monospace throughout,
               segmented pill navigation, bracketed values, live status bar.

    Usage:
        local Ember  = loadstring(game:HttpGet("<raw url>"))()
        local Window = Ember:CreateWindow({ Title = "EMBER" })
        local Tab    = Window:AddTab("MAIN")
        local Group  = Tab:AddGroup("GENERAL", "left")
        Group:AddToggle({ Text = "Enabled", Callback = function(v) end })

    Every element accepts a Callback. Attach your own functions there.
    Toggle the interface with Insert (configurable).
]]

--=========================================================================--
--  SERVICES
--=========================================================================--

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players          = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

--=========================================================================--
--  THEME
--=========================================================================--

local Theme = {
    Background   = Color3.fromRGB( 11,  10,   9),
    Panel        = Color3.fromRGB( 19,  17,  16),
    Group        = Color3.fromRGB( 24,  21,  20),
    Element      = Color3.fromRGB( 33,  29,  27),
    ElementHover = Color3.fromRGB( 44,  39,  36),
    Border       = Color3.fromRGB( 46,  41,  38),
    BorderLight  = Color3.fromRGB( 64,  57,  52),
    Accent       = Color3.fromRGB(255, 154,  60),  -- amber
    AccentSoft   = Color3.fromRGB(255, 207, 107),  -- pale amber
    Text         = Color3.fromRGB(228, 222, 214),
    TextDim      = Color3.fromRGB(146, 137, 128),
    TextFaint    = Color3.fromRGB( 97,  90,  84),
    OnAccent     = Color3.fromRGB( 20,  14,   8),  -- text sitting on amber
    Risk         = Color3.fromRGB(235,  96,  76),
}

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
--  FONTS  —  monospace-first, this is the whole look
--=========================================================================--

local function font(name, fallback)
    local ok, f = pcall(function() return Enum.Font[name] end)
    if ok and f then return f end
    return Enum.Font[fallback or "SourceSans"]
end

local F = {
    Mono  = font("RobotoMono", "Code"),
    Code  = font("Code", "SourceSans"),
    Head  = font("Oswald", "GothamMedium"),
    Label = font("RobotoMono", "Code"),
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

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 4) }) end

local function stroke(key, thickness, transparency)
    local s = new("UIStroke", {
        Thickness       = thickness or 1,
        Transparency    = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
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
        Padding       = UDim.new(0, padding or 0),
        SortOrder     = Enum.SortOrder.LayoutOrder,
        FillDirection = dir or Enum.FillDirection.Vertical,
    })
end

local TW_FAST = TweenInfo.new(0.10, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TW_MED  = TweenInfo.new(0.20, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TW_SLOW = TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local function tween(inst, info, props)
    local t = TweenService:Create(inst, info, props); t:Play(); return t
end

local function round(n, places)
    local m = 10 ^ (places or 0)
    return math.floor(n * m + 0.5) / m
end

--=========================================================================--
--  MOUNT
--=========================================================================--

local function mount(gui)
    if typeof(gethui) == "function" then
        local ok = pcall(function() gui.Parent = gethui() end)
        if ok and gui.Parent then return end
    end
    if syn and typeof(syn.protect_gui) == "function" then
        local ok = pcall(function()
            syn.protect_gui(gui); gui.Parent = game:GetService("CoreGui")
        end)
        if ok and gui.Parent then return end
    end
    local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if ok and gui.Parent then return end
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

--=========================================================================--
--  ROOT
--=========================================================================--

local Ember = {}
Ember.Flags = {}
Ember.Theme = Theme

local Screen = new("ScreenGui", {
    Name           = "EmberUI",
    ResetOnSpawn   = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder   = 999,
})
mount(Screen)

--=========================================================================--
--  NOTIFICATIONS  —  terminal log style, bottom-left
--=========================================================================--

local NotifyHolder = new("Frame", {
    AnchorPoint            = Vector2.new(0, 1),
    Position               = UDim2.new(0, 18, 1, -18),
    Size                   = UDim2.new(0, 300, 1, -36),
    BackgroundTransparency = 1,
    Parent                 = Screen,
}, {
    new("UIListLayout", {
        Padding           = UDim.new(0, 5),
        SortOrder         = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
    }),
})

function Ember:Notify(text, duration)
    duration = duration or 3

    local card = new("Frame", {
        Size                   = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        ClipsDescendants       = true,
        Parent                 = NotifyHolder,
    })

    local inner = new("Frame", {
        Size   = UDim2.new(1, 0, 0, 30),
        Parent = card,
    }, { corner(4), stroke("Border") })
    reg(inner, "BackgroundColor3", "Panel")

    local mark = new("TextLabel", {
        Position               = UDim2.new(0, 10, 0, 0),
        Size                   = UDim2.new(0, 14, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = ">",
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = inner,
    })
    reg(mark, "TextColor3", "Accent")

    local l = new("TextLabel", {
        Position               = UDim2.new(0, 24, 0, 0),
        Size                   = UDim2.new(1, -34, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = tostring(text),
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = inner,
    })
    reg(l, "TextColor3", "Text")

    tween(card, TW_MED, { Size = UDim2.new(1, 0, 0, 30) })

    task.delay(duration, function()
        tween(card,  TW_MED, { Size = UDim2.new(1, 0, 0, 0) })
        tween(inner, TW_MED, { BackgroundTransparency = 1 })
        tween(l,     TW_MED, { TextTransparency = 1 })
        tween(mark,  TW_MED, { TextTransparency = 1 })
        task.wait(0.24)
        card:Destroy()
    end)
end

--=========================================================================--
--  WINDOW
--=========================================================================--

function Ember:CreateWindow(cfg)
    cfg = cfg or {}
    local title     = cfg.Title     or "EMBER"
    local size      = cfg.Size      or UDim2.new(0, 690, 0, 500)
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.Insert

    local Main = new("Frame", {
        Name             = "Window",
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0.5, 0, 0.5, 0),
        Size             = UDim2.new(0, 0, 0, 0),
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        Visible          = false,
        Parent           = Screen,
    }, { corner(6), stroke("BorderLight") })
    reg(Main, "BackgroundColor3", "Background")

    ------------------------------------------------------------------
    -- Header
    ------------------------------------------------------------------
    local Header = new("Frame", {
        Size                   = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        Parent                 = Main,
    })

    local block = new("Frame", {
        AnchorPoint     = Vector2.new(0, 0.5),
        Position        = UDim2.new(0, 16, 0.5, 0),
        Size            = UDim2.new(0, 4, 0, 16),
        BorderSizePixel = 0,
        Parent          = Header,
    }, { corner(1) })
    reg(block, "BackgroundColor3", "Accent")

    local brand = new("TextLabel", {
        Position               = UDim2.new(0, 28, 0, 0),
        Size                   = UDim2.new(0, 240, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Head,
        Text                   = title,
        TextSize               = 18,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = Header,
    })
    reg(brand, "TextColor3", "Text")

    local function headBtn(char, offset, hoverKey, cb)
        local b = new("TextButton", {
            AnchorPoint            = Vector2.new(1, 0.5),
            Position               = UDim2.new(1, -offset, 0.5, 0),
            Size                   = UDim2.new(0, 22, 0, 22),
            BackgroundTransparency = 1,
            AutoButtonColor        = false,
            Font                   = F.Mono,
            Text                   = char,
            TextSize               = 13,
            Parent                 = Header,
        }, { corner(3) })
        reg(b, "TextColor3", "TextDim")
        b.MouseEnter:Connect(function()
            b.TextColor3 = Theme[hoverKey]
            tween(b, TW_FAST, { BackgroundTransparency = 0, BackgroundColor3 = Theme.Element })
        end)
        b.MouseLeave:Connect(function()
            b.TextColor3 = Theme.TextDim
            tween(b, TW_FAST, { BackgroundTransparency = 1 })
        end)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    local minimized, fullSize = false, size

    headBtn("X", 14, "Risk", function()
        tween(Main, TW_MED, { Size = UDim2.new(0, fullSize.X.Offset, 0, 0) })
        task.wait(0.24); Screen:Destroy()
    end)
    headBtn("_", 42, "Accent", function()
        minimized = not minimized
        tween(Main, TW_MED, {
            Size = minimized and UDim2.new(0, fullSize.X.Offset, 0, 44) or fullSize
        })
    end)

    ------------------------------------------------------------------
    -- Segmented pill navigation
    ------------------------------------------------------------------
    local NavShell = new("Frame", {
        Position        = UDim2.new(0, 16, 0, 48),
        Size            = UDim2.new(1, -32, 0, 30),
        BorderSizePixel = 0,
        Parent          = Main,
    }, { corner(5), stroke("Border"), pad(3, 3, 3, 3), list(3, Enum.FillDirection.Horizontal) })
    reg(NavShell, "BackgroundColor3", "Panel")

    local Content = new("Frame", {
        Position               = UDim2.new(0, 0, 0, 86),
        Size                   = UDim2.new(1, 0, 1, -114),
        BackgroundTransparency = 1,
        ClipsDescendants       = true,
        Parent                 = Main,
    })

    ------------------------------------------------------------------
    -- Status footer
    ------------------------------------------------------------------
    local footLine = new("Frame", {
        Position        = UDim2.new(0, 0, 1, -28),
        Size            = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent          = Main,
    })
    reg(footLine, "BackgroundColor3", "Border")

    local Footer = new("Frame", {
        Position               = UDim2.new(0, 0, 1, -27),
        Size                   = UDim2.new(1, 0, 0, 27),
        BackgroundTransparency = 1,
        Parent                 = Main,
    })

    local statusDot = new("Frame", {
        AnchorPoint     = Vector2.new(0, 0.5),
        Position        = UDim2.new(0, 16, 0.5, 0),
        Size            = UDim2.new(0, 6, 0, 6),
        BorderSizePixel = 0,
        Parent          = Footer,
    }, { corner(3) })
    reg(statusDot, "BackgroundColor3", "Accent")

    local statusText = new("TextLabel", {
        Position               = UDim2.new(0, 28, 0, 0),
        Size                   = UDim2.new(0, 320, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "ready",
        TextSize               = 10,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = Footer,
    })
    reg(statusText, "TextColor3", "TextFaint")

    local clock = new("TextLabel", {
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, -16, 0, 0),
        Size                   = UDim2.new(0, 160, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "",
        TextSize               = 10,
        TextXAlignment         = Enum.TextXAlignment.Right,
        Parent                 = Footer,
    })
    reg(clock, "TextColor3", "TextFaint")

    task.spawn(function()
        while Screen.Parent do
            local ok, t = pcall(function() return os.date("%H:%M:%S") end)
            clock.Text = (ok and t or "") .. "   |   " .. (LocalPlayer and LocalPlayer.Name or "guest")
            task.wait(1)
        end
    end)

    -- pulse the status dot
    task.spawn(function()
        while Screen.Parent do
            tween(statusDot, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.6 })
            task.wait(0.95)
            tween(statusDot, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
            task.wait(0.95)
        end
    end)

    function Ember:SetStatus(t) statusText.Text = tostring(t) end

    ------------------------------------------------------------------
    -- Drag
    ------------------------------------------------------------------
    do
        local dragging, dragStart, startPos
        Header.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, i.Position, Main.Position
                i.Changed:Connect(function()
                    if i.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if not dragging then return end
            if i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch then
                local d = i.Position - dragStart
                Main.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    UserInputService.InputBegan:Connect(function(i, gpe)
        if not gpe and i.KeyCode == toggleKey then Main.Visible = not Main.Visible end
    end)

    ------------------------------------------------------------------
    local Window = { Tabs = {}, Main = Main }
    local activeTab

    function Window:AddTab(name)
        local Tab = {}

        local btn = new("TextButton", {
            Size                   = UDim2.new(0, 0, 1, 0),
            AutomaticSize          = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            AutoButtonColor        = false,
            Text                   = "",
            Parent                 = NavShell,
        }, { corner(4) })
        reg(btn, "BackgroundColor3", "Accent")

        local lbl = new("TextLabel", {
            Size                   = UDim2.new(0, 0, 1, 0),
            AutomaticSize          = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Font                   = F.Mono,
            Text                   = name,
            TextSize               = 11,
            Parent                 = btn,
        }, { pad(0, 0, 16, 16) })
        reg(lbl, "TextColor3", "TextDim")

        local page = new("Frame", {
            Size                   = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Visible                = false,
            Parent                 = Content,
        }, { pad(10, 6, 16, 16) })

        local function column(xScale, xOff)
            return new("ScrollingFrame", {
                Position               = UDim2.new(xScale, xOff, 0, 0),
                Size                   = UDim2.new(0.5, -6, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel        = 0,
                ScrollBarThickness     = 2,
                ScrollBarImageColor3   = Theme.BorderLight,
                CanvasSize             = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize    = Enum.AutomaticSize.Y,
                Parent                 = page,
            }, { list(12), pad(0, 14, 0, 4) })
        end

        local left  = column(0, 0)
        local right = column(0.5, 6)

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
            lbl.TextColor3 = Theme.OnAccent
            tween(btn, TW_FAST, { BackgroundTransparency = 0 })
        end

        function Tab._deselect()
            page.Visible   = false
            lbl.TextColor3 = Theme.TextDim
            tween(btn, TW_FAST, { BackgroundTransparency = 1 })
        end

        btn.MouseButton1Click:Connect(function() Tab:Select() end)

        --==========================================================--
        --  GROUP
        --==========================================================--
        function Tab:AddGroup(groupTitle, side)
            local parentCol = (side == "right") and right or left

            local wrap = new("Frame", {
                Size                   = UDim2.new(1, 0, 0, 0),
                AutomaticSize          = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Parent                 = parentCol,
            }, { list(7) })

            -- header: amber square + uppercase label + rule
            local head = new("Frame", {
                Size                   = UDim2.new(1, 0, 0, 14),
                BackgroundTransparency = 1,
                LayoutOrder            = 1,
                Parent                 = wrap,
            })

            local sq = new("Frame", {
                AnchorPoint     = Vector2.new(0, 0.5),
                Position        = UDim2.new(0, 0, 0.5, 0),
                Size            = UDim2.new(0, 6, 0, 6),
                BorderSizePixel = 0,
                Parent          = head,
            }, { corner(1) })
            reg(sq, "BackgroundColor3", "Accent")

            local ht = new("TextLabel", {
                Position               = UDim2.new(0, 13, 0, 0),
                Size                   = UDim2.new(0, 0, 1, 0),
                AutomaticSize          = Enum.AutomaticSize.X,
                BackgroundTransparency = 1,
                Font                   = F.Mono,
                Text                   = string.upper(groupTitle),
                TextSize               = 10,
                TextXAlignment         = Enum.TextXAlignment.Left,
                Parent                 = head,
            })
            reg(ht, "TextColor3", "TextDim")

            local rule = new("Frame", {
                AnchorPoint     = Vector2.new(1, 0.5),
                Position        = UDim2.new(1, 0, 0.5, 0),
                Size            = UDim2.new(1, -(20 + ht.TextBounds.X), 0, 1),
                BorderSizePixel = 0,
                Parent          = head,
            })
            reg(rule, "BackgroundColor3", "Border")
            task.defer(function()
                rule.Size = UDim2.new(1, -(22 + ht.TextBounds.X), 0, 1)
            end)

            local body = new("Frame", {
                Size            = UDim2.new(1, 0, 0, 0),
                AutomaticSize   = Enum.AutomaticSize.Y,
                BorderSizePixel = 0,
                LayoutOrder     = 2,
                Parent          = wrap,
            }, { corner(5), stroke("Border"), list(5), pad(11, 11, 11, 11) })
            reg(body, "BackgroundColor3", "Group")

            local Group = {}

            local function row(h)
                return new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, h),
                    BackgroundTransparency = 1,
                    Parent                 = body,
                })
            end

            ----------------------------------------------------------
            function Group:AddLabel(text)
                local r = row(15)
                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = text,
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextWrapped            = true,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextFaint")
                return { Set = function(_, t) l.Text = t end }
            end

            function Group:AddDivider()
                local r = row(8)
                local d = new("Frame", {
                    Position        = UDim2.new(0, 0, 0.5, 0),
                    Size            = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    Parent          = r,
                })
                reg(d, "BackgroundColor3", "Border")
            end

            ----------------------------------------------------------
            --  TOGGLE  (square, amber fill)
            ----------------------------------------------------------
            function Group:AddToggle(o)
                o = o or {}
                local state = o.Default or false

                local r = row(19)
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
                    Size            = UDim2.new(0, 14, 0, 14),
                    BorderSizePixel = 0,
                    Parent          = btn2,
                }, { corner(3), stroke("BorderLight") })
                reg(boxOuter, "BackgroundColor3", "Element")

                local fill = new("Frame", {
                    AnchorPoint            = Vector2.new(0.5, 0.5),
                    Position               = UDim2.new(0.5, 0, 0.5, 0),
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    BorderSizePixel        = 0,
                    Parent                 = boxOuter,
                }, { corner(3) })
                reg(fill, "BackgroundColor3", "Accent")

                local check = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = "x",
                    TextSize               = 11,
                    TextTransparency       = 1,
                    ZIndex                 = 3,
                    Parent                 = boxOuter,
                })
                reg(check, "TextColor3", "OnAccent")

                local lbl2 = new("TextLabel", {
                    Position               = UDim2.new(0, 23, 0, 0),
                    Size                   = UDim2.new(1, -23, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Text or "Toggle",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = btn2,
                })
                reg(lbl2, "TextColor3", "TextDim")

                local api = {}

                function api:Set(v, silent)
                    state = v and true or false
                    if o.Flag then Ember.Flags[o.Flag] = state end
                    tween(fill,  TW_FAST, { BackgroundTransparency = state and 0 or 1 })
                    tween(check, TW_FAST, { TextTransparency = state and 0 or 1 })
                    lbl2.TextColor3 = state and Theme.Text or Theme.TextDim
                    if not silent and o.Callback then task.spawn(o.Callback, state) end
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

            ----------------------------------------------------------
            --  SLIDER  (bracketed value, square knob)
            ----------------------------------------------------------
            function Group:AddSlider(o)
                o = o or {}
                local min, max = o.Min or 0, o.Max or 100
                local decimals = o.Decimals or 0
                local value    = math.clamp(o.Default or min, min, max)
                local suffix   = o.Suffix or ""

                local r = row(32)

                local lbl3 = new("TextLabel", {
                    Size                   = UDim2.new(1, -80, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Text or "Slider",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(lbl3, "TextColor3", "TextDim")

                local valLbl = new("TextLabel", {
                    AnchorPoint            = Vector2.new(1, 0),
                    Position               = UDim2.new(1, 0, 0, 0),
                    Size                   = UDim2.new(0, 80, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = "",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Right,
                    Parent                 = r,
                })
                reg(valLbl, "TextColor3", "AccentSoft")

                local track = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 22),
                    Size            = UDim2.new(1, 0, 0, 5),
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

                local knob = new("Frame", {
                    AnchorPoint     = Vector2.new(0.5, 0.5),
                    Position        = UDim2.new(0, 0, 0.5, 0),
                    Size            = UDim2.new(0, 3, 0, 11),
                    BorderSizePixel = 0,
                    ZIndex          = 3,
                    Parent          = track,
                }, { corner(1) })
                reg(knob, "BackgroundColor3", "AccentSoft")

                local api = {}

                function api:Set(v, silent)
                    value = math.clamp(round(v, decimals), min, max)
                    if o.Flag then Ember.Flags[o.Flag] = value end
                    local a = (max == min) and 0 or (value - min) / (max - min)
                    tween(fill2, TW_FAST, { Size = UDim2.new(a, 0, 1, 0) })
                    tween(knob,  TW_FAST, { Position = UDim2.new(a, 0, 0.5, 0) })
                    valLbl.Text = "[" .. tostring(value) .. suffix .. "]"
                    if not silent and o.Callback then task.spawn(o.Callback, value) end
                end

                function api:Get() return value end

                local sliding = false
                local function fromX(px)
                    local w = track.AbsoluteSize.X
                    if w <= 0 then return end
                    local a = math.clamp((px - track.AbsolutePosition.X) / w, 0, 1)
                    api:Set(min + (max - min) * a)
                end

                track.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                        sliding = true; fromX(i.Position.X)
                    end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then sliding = false end
                end)
                UserInputService.InputChanged:Connect(function(i)
                    if not sliding then return end
                    if i.UserInputType == Enum.UserInputType.MouseMovement
                    or i.UserInputType == Enum.UserInputType.Touch then fromX(i.Position.X) end
                end)

                api:Set(value, true)
                return api
            end

            ----------------------------------------------------------
            --  BUTTON  (amber wipe on hover)
            ----------------------------------------------------------
            function Group:AddButton(o)
                o = o or {}
                local r = row(26)
                local b = new("TextButton", {
                    Size             = UDim2.new(1, 0, 1, 0),
                    AutoButtonColor  = false,
                    BorderSizePixel  = 0,
                    ClipsDescendants = true,
                    Text             = "",
                    Parent           = r,
                }, { corner(4), stroke("Border") })
                reg(b, "BackgroundColor3", "Element")

                local wipe = new("Frame", {
                    Size            = UDim2.new(0, 0, 1, 0),
                    BorderSizePixel = 0,
                    Parent          = b,
                })
                reg(wipe, "BackgroundColor3", "Accent")

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Text or "Button",
                    TextSize               = 11,
                    ZIndex                 = 3,
                    Parent                 = b,
                })
                reg(l, "TextColor3", "TextDim")

                b.MouseEnter:Connect(function()
                    tween(wipe, TW_MED, { Size = UDim2.new(1, 0, 1, 0) })
                    l.TextColor3 = Theme.OnAccent
                end)
                b.MouseLeave:Connect(function()
                    tween(wipe, TW_MED, { Size = UDim2.new(0, 0, 1, 0) })
                    l.TextColor3 = Theme.TextDim
                end)
                b.MouseButton1Click:Connect(function()
                    if o.Callback then task.spawn(o.Callback) end
                end)
                return b
            end

            ----------------------------------------------------------
            function Group:AddTextbox(o)
                o = o or {}
                local r = row(40)

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Text or "Input",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local holder = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 18),
                    Size            = UDim2.new(1, 0, 0, 22),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(4), stroke("Border") })
                reg(holder, "BackgroundColor3", "Element")

                local caret = new("TextLabel", {
                    Position               = UDim2.new(0, 8, 0, 0),
                    Size                   = UDim2.new(0, 10, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = ">",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = holder,
                })
                reg(caret, "TextColor3", "TextFaint")

                local tb = new("TextBox", {
                    Position               = UDim2.new(0, 20, 0, 0),
                    Size                   = UDim2.new(1, -28, 1, 0),
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

                tb.Focused:Connect(function() caret.TextColor3 = Theme.Accent end)
                tb.FocusLost:Connect(function(enter)
                    caret.TextColor3 = Theme.TextFaint
                    if o.Flag then Ember.Flags[o.Flag] = tb.Text end
                    if o.Callback then task.spawn(o.Callback, tb.Text, enter) end
                end)
                return tb
            end

            ----------------------------------------------------------
            function Group:AddDropdown(o)
                o = o or {}
                local options  = o.Options or {}
                local selected = o.Default or options[1] or "None"
                local open     = false

                local r = new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, 40),
                    BackgroundTransparency = 1,
                    ClipsDescendants       = true,
                    Parent                 = body,
                })

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 0, 14),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Text or "Dropdown",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local head2 = new("TextButton", {
                    Position        = UDim2.new(0, 0, 0, 18),
                    Size            = UDim2.new(1, 0, 0, 22),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Text            = "",
                    Parent          = r,
                }, { corner(4), stroke("Border") })
                reg(head2, "BackgroundColor3", "Element")

                local sel = new("TextLabel", {
                    Position               = UDim2.new(0, 9, 0, 0),
                    Size                   = UDim2.new(1, -28, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = tostring(selected),
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextTruncate           = Enum.TextTruncate.AtEnd,
                    Parent                 = head2,
                })
                reg(sel, "TextColor3", "Text")

                local arrow = new("TextLabel", {
                    AnchorPoint            = Vector2.new(1, 0.5),
                    Position               = UDim2.new(1, -9, 0.5, 0),
                    Size                   = UDim2.new(0, 10, 0, 10),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = "+",
                    TextSize               = 12,
                    Parent                 = head2,
                })
                reg(arrow, "TextColor3", "TextDim")

                local listHolder = new("Frame", {
                    Position               = UDim2.new(0, 0, 0, 43),
                    Size                   = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Parent                 = r,
                }, { list(2) })

                local api = { Selected = selected }

                local function rebuild()
                    for _, c in ipairs(listHolder:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for _, opt in ipairs(options) do
                        local ob = new("TextButton", {
                            Size            = UDim2.new(1, 0, 0, 20),
                            AutoButtonColor = false,
                            BorderSizePixel = 0,
                            Font            = F.Mono,
                            Text            = "  " .. tostring(opt),
                            TextSize        = 11,
                            TextXAlignment  = Enum.TextXAlignment.Left,
                            Parent          = listHolder,
                        }, { corner(3) })
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
                            tween(r, TW_MED, { Size = UDim2.new(1, 0, 0, 40) })
                            arrow.Text = "+"
                        end)
                    end
                end

                function api:Set(v, silent)
                    api.Selected = v
                    sel.Text = tostring(v)
                    if o.Flag then Ember.Flags[o.Flag] = v end
                    rebuild()
                    if not silent and o.Callback then task.spawn(o.Callback, v) end
                end
                function api:Get() return api.Selected end
                function api:SetOptions(t) options = t; rebuild() end

                head2.MouseButton1Click:Connect(function()
                    open = not open
                    local h = open and (43 + #options * 22) or 40
                    tween(r, TW_MED, { Size = UDim2.new(1, 0, 0, h) })
                    arrow.Text = open and "-" or "+"
                end)

                rebuild()
                if o.Flag then Ember.Flags[o.Flag] = selected end
                return api
            end

            ----------------------------------------------------------
            function Group:AddKeybind(o)
                o = o or {}
                local bound, binding = o.Default, false

                local r = row(20)
                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, -74, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Text or "Keybind",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local kb = new("TextButton", {
                    AnchorPoint     = Vector2.new(1, 0.5),
                    Position        = UDim2.new(1, 0, 0.5, 0),
                    Size            = UDim2.new(0, 68, 0, 18),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Font            = F.Mono,
                    Text            = bound and ("[" .. bound.Name .. "]") or "[none]",
                    TextSize        = 10,
                    Parent          = r,
                }, { corner(3), stroke("Border") })
                reg(kb, "BackgroundColor3", "Element")
                reg(kb, "TextColor3", "TextDim")

                kb.MouseButton1Click:Connect(function()
                    binding = true
                    kb.Text = "[...]"
                    kb.TextColor3 = Theme.Accent
                end)

                UserInputService.InputBegan:Connect(function(i, gpe)
                    if binding and i.UserInputType == Enum.UserInputType.Keyboard then
                        binding = false
                        if i.KeyCode == Enum.KeyCode.Backspace then
                            bound, kb.Text = nil, "[none]"
                        else
                            bound, kb.Text = i.KeyCode, "[" .. i.KeyCode.Name .. "]"
                        end
                        kb.TextColor3 = Theme.TextDim
                        if o.Flag then Ember.Flags[o.Flag] = bound end
                        if o.OnBind then task.spawn(o.OnBind, bound) end
                        return
                    end
                    if gpe then return end
                    if bound and i.KeyCode == bound and o.Callback then task.spawn(o.Callback) end
                end)

                return {
                    Get = function() return bound end,
                    Set = function(_, k)
                        bound = k
                        kb.Text = k and ("[" .. k.Name .. "]") or "[none]"
                    end,
                }
            end

            ----------------------------------------------------------
            function Group:AddColorpicker(o)
                o = o or {}
                local col = o.Default or Theme.Accent
                local h, s, v = Color3.toHSV(col)
                local open = false

                local r = new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, 20),
                    BackgroundTransparency = 1,
                    ClipsDescendants       = true,
                    Parent                 = body,
                })

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, -46, 0, 20),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = o.Text or "Colour",
                    TextSize               = 11,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local swatch = new("TextButton", {
                    AnchorPoint      = Vector2.new(1, 0),
                    Position         = UDim2.new(1, 0, 0, 3),
                    Size             = UDim2.new(0, 36, 0, 14),
                    BackgroundColor3 = col,
                    AutoButtonColor  = false,
                    BorderSizePixel  = 0,
                    Text             = "",
                    Parent           = r,
                }, { corner(3), stroke("BorderLight") })

                local body2 = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 25),
                    Size            = UDim2.new(1, 0, 0, 100),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(5), stroke("Border") })
                reg(body2, "BackgroundColor3", "Element")

                local field = new("Frame", {
                    Position         = UDim2.new(0, 9, 0, 9),
                    Size             = UDim2.new(1, -18, 0, 64),
                    BackgroundColor3 = Color3.fromHSV(h, 1, 1),
                    BorderSizePixel  = 0,
                    Parent           = body2,
                }, { corner(3) })

                new("Frame", {
                    Size             = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel  = 0,
                    Parent           = field,
                }, {
                    corner(3),
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
                    corner(3),
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
                    Size                   = UDim2.new(0, 8, 0, 8),
                    BackgroundTransparency = 1,
                    ZIndex                 = 5,
                    Parent                 = field,
                }, { corner(1), new("UIStroke", { Color = Color3.new(1,1,1), Thickness = 1.5 }) })

                local hueBar = new("Frame", {
                    Position        = UDim2.new(0, 9, 0, 80),
                    Size            = UDim2.new(1, -18, 0, 11),
                    BorderSizePixel = 0,
                    Parent          = body2,
                }, {
                    corner(3),
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
                    if o.Flag then Ember.Flags[o.Flag] = col end
                    if not silent and o.Callback then task.spawn(o.Callback, col) end
                end

                function api:Set(c, silent) h, s, v = Color3.toHSV(c); push(silent) end
                function api:Get() return col end

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
                    tween(r, TW_MED, { Size = UDim2.new(1, 0, 0, open and 130 or 20) })
                end)

                push(true)
                return api
            end

            return Group
        end

        table.insert(Window.Tabs, Tab)
        if #Window.Tabs == 1 then Tab:Select() end
        return Tab
    end

    --==============================================================--
    --  WELCOME / LOADER  —  boot-sequence styling
    --==============================================================--
    local Welcome = new("Frame", {
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0.5, 0, 0.5, 0),
        Size             = UDim2.new(0, 0, 0, 0),
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        Parent           = Screen,
    }, { corner(6), stroke("BorderLight") })
    reg(Welcome, "BackgroundColor3", "Background")

    local wStripe = new("Frame", {
        Size                   = UDim2.new(0, 3, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Parent                 = Welcome,
    })
    reg(wStripe, "BackgroundColor3", "Accent")

    local wTitle = new("TextLabel", {
        Position               = UDim2.new(0, 30, 0, 34),
        Size                   = UDim2.new(1, -60, 0, 30),
        BackgroundTransparency = 1,
        Font                   = F.Head,
        Text                   = title,
        TextSize               = 30,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wTitle, "TextColor3", "Text")

    local wSub = new("TextLabel", {
        Position               = UDim2.new(0, 30, 0, 66),
        Size                   = UDim2.new(1, -60, 0, 16),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "> welcome back, " .. (LocalPlayer and LocalPlayer.DisplayName or "guest"),
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wSub, "TextColor3", "TextDim")

    -- boot log lines
    local logHolder = new("Frame", {
        Position               = UDim2.new(0, 30, 0, 96),
        Size                   = UDim2.new(1, -60, 0, 62),
        BackgroundTransparency = 1,
        Parent                 = Welcome,
    }, { list(3) })

    local wBarBg = new("Frame", {
        Position               = UDim2.new(0, 30, 0, 166),
        Size                   = UDim2.new(1, -60, 0, 4),
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
        AnchorPoint            = Vector2.new(0.5, 0),
        Position               = UDim2.new(0.5, 0, 0, 158),
        Size                   = UDim2.new(0, 150, 0, 32),
        AutoButtonColor        = false,
        BorderSizePixel        = 0,
        ClipsDescendants       = true,
        Text                   = "",
        BackgroundTransparency = 1,
        Parent                 = Welcome,
    }, { corner(4), stroke("BorderLight") })
    reg(wBtn, "BackgroundColor3", "Element")

    local wWipe = new("Frame", {
        Size            = UDim2.new(0, 0, 1, 0),
        BorderSizePixel = 0,
        Parent          = wBtn,
    })
    reg(wWipe, "BackgroundColor3", "Accent")

    local wBtnLbl = new("TextLabel", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "[ LOAD ]",
        TextSize               = 12,
        TextTransparency       = 1,
        ZIndex                 = 3,
        Parent                 = wBtn,
    })
    reg(wBtnLbl, "TextColor3", "Text")

    wBtn.MouseEnter:Connect(function()
        tween(wWipe, TW_MED, { Size = UDim2.new(1, 0, 1, 0) })
        wBtnLbl.TextColor3 = Theme.OnAccent
    end)
    wBtn.MouseLeave:Connect(function()
        tween(wWipe, TW_MED, { Size = UDim2.new(0, 0, 1, 0) })
        wBtnLbl.TextColor3 = Theme.Text
    end)

    task.spawn(function()
        tween(Welcome, TW_SLOW, { Size = UDim2.new(0, 360, 0, 224) })
        task.wait(0.30)
        tween(wStripe, TW_MED, { BackgroundTransparency = 0 })
        tween(wTitle,  TW_MED, { TextTransparency = 0 })
        task.wait(0.08)
        tween(wSub,    TW_MED, { TextTransparency = 0 })
        task.wait(0.10)
        tween(wBtn,    TW_MED, { BackgroundTransparency = 0 })
        tween(wBtnLbl, TW_MED, { TextTransparency = 0 })
    end)

    local loaded = false
    wBtn.MouseButton1Click:Connect(function()
        if loaded then return end
        loaded = true
        wBtn.Active = false

        tween(wBtn,    TW_FAST, { BackgroundTransparency = 1 })
        tween(wWipe,   TW_FAST, { BackgroundTransparency = 1 })
        tween(wBtnLbl, TW_FAST, { TextTransparency = 1 })
        tween(wBarBg,  TW_FAST, { BackgroundTransparency = 0 })
        tween(wBar,    TW_FAST, { BackgroundTransparency = 0 })

        local steps = {
            { "initialising interface", 0.25 },
            { "building components",    0.55 },
            { "applying theme",         0.82 },
            { "ready",                  1.00 },
        }

        task.spawn(function()
            for idx, step in ipairs(steps) do
                local line = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 0, 13),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = "  " .. step[1],
                    TextSize               = 10,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextTransparency       = 1,
                    LayoutOrder            = idx,
                    Parent                 = logHolder,
                })
                reg(line, "TextColor3", (idx == #steps) and "Accent" or "TextFaint")
                tween(line, TW_FAST, { TextTransparency = 0 })

                tween(wBar, TweenInfo.new(0.30, Enum.EasingStyle.Sine), {
                    Size = UDim2.new(step[2], 0, 1, 0)
                })
                task.wait(0.34)
            end
            task.wait(0.22)

            tween(Welcome, TW_MED, { Size = UDim2.new(0, 360, 0, 0) })
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
--  Delete everything below this line to use EMBER as a pure library.
--=========================================================================--

local Window = Ember:CreateWindow({
    Title     = "EMBER",
    Size      = UDim2.new(0, 690, 0, 500),
    ToggleKey = Enum.KeyCode.Insert,
    OnLoad    = function()
        Ember:Notify("interface loaded — Insert to toggle", 4)
    end,
})

-------------------------------------------------- MAIN
do
    local Tab = Window:AddTab("MAIN")

    local a = Tab:AddGroup("Overview", "left")
    a:AddLabel("Industrial interface library for Roblox.")
    a:AddLabel("Monospace, amber, bracketed values.")
    a:AddDivider()
    a:AddButton({ Text = "Send test notification", Callback = function()
        Ember:Notify("this is a log line", 3)
    end })

    local b = Tab:AddGroup("Session", "left")
    b:AddLabel("user   " .. (LocalPlayer and LocalPlayer.Name or "unknown"))
    b:AddLabel("place  " .. tostring(game.PlaceId))

    local c = Tab:AddGroup("Elements", "right")
    c:AddToggle({ Text = "Example toggle", Default = true, Flag = "demo_toggle",
        Callback = function(v) print("[ember] toggle:", v) end })
    c:AddToggle({ Text = "Second toggle", Flag = "demo_toggle2" })
    c:AddSlider({ Text = "Example slider", Min = 0, Max = 100, Default = 74, Suffix = "",
        Flag = "demo_slider", Callback = function(v) print("[ember] slider:", v) end })
    c:AddSlider({ Text = "Decimal slider", Min = 0, Max = 30, Default = 14.2, Decimals = 1,
        Flag = "demo_slider2" })
    c:AddKeybind({ Text = "Example keybind", Default = Enum.KeyCode.H,
        Callback = function() Ember:Notify("keybind fired", 2) end })
end

-------------------------------------------------- COMPONENTS
do
    local Tab = Window:AddTab("COMPONENTS")

    local a = Tab:AddGroup("Selection", "left")
    a:AddDropdown({ Text = "Example dropdown", Options = { "Alpha", "Bravo", "Charlie", "Delta" },
        Default = "Alpha", Flag = "demo_drop",
        Callback = function(v) print("[ember] dropdown:", v) end })
    a:AddTextbox({ Text = "Example textbox", Placeholder = "type here...", Flag = "demo_text" })

    local b = Tab:AddGroup("Actions", "left")
    b:AddButton({ Text = "Primary action",   Callback = function() Ember:Notify("primary fired", 3) end })
    b:AddButton({ Text = "Secondary action", Callback = function() Ember:Notify("secondary fired", 3) end })

    local c = Tab:AddGroup("Status", "right")
    c:AddLabel("The footer status line is scriptable.")
    c:AddDivider()
    c:AddTextbox({ Text = "Set status text", Placeholder = "ready",
        Callback = function(t) Ember:SetStatus(t ~= "" and t or "ready") end })
    c:AddButton({ Text = "Dump flags to console", Callback = function()
        for k, v in pairs(Ember.Flags) do print("[flag]", k, v) end
        Ember:Notify("flags printed to console", 3)
    end })
end

-------------------------------------------------- THEME
do
    local Tab = Window:AddTab("THEME")

    local a = Tab:AddGroup("Palette", "left")
    a:AddLabel("Pick a colour — the interface retints live.")
    a:AddDivider()
    a:AddColorpicker({ Text = "Accent", Default = Theme.Accent,
        Callback = function(c) retint("Accent", c) end })
    a:AddColorpicker({ Text = "Accent soft", Default = Theme.AccentSoft,
        Callback = function(c) retint("AccentSoft", c) end })
    a:AddColorpicker({ Text = "Text", Default = Theme.Text,
        Callback = function(c) retint("Text", c) end })

    local b = Tab:AddGroup("Presets", "right")
    local presets = {
        { "Ember",   Color3.fromRGB(255, 154,  60), Color3.fromRGB(255, 207, 107) },
        { "Toxic",   Color3.fromRGB(163, 230,  53), Color3.fromRGB(212, 245, 140) },
        { "Signal",  Color3.fromRGB( 56, 189, 248), Color3.fromRGB(147, 220, 252) },
        { "Blood",   Color3.fromRGB(239,  68,  68), Color3.fromRGB(252, 140, 140) },
        { "Bone",    Color3.fromRGB(226, 220, 208), Color3.fromRGB(245, 242, 236) },
    }
    for _, p in ipairs(presets) do
        b:AddButton({ Text = p[1], Callback = function()
            retint("Accent", p[2]); retint("AccentSoft", p[3])
            Ember:Notify("accent -> " .. string.lower(p[1]), 2)
        end })
    end
end

-------------------------------------------------- SETTINGS
do
    local Tab = Window:AddTab("SETTINGS")

    local a = Tab:AddGroup("Interface", "left")
    a:AddSlider({ Text = "Background opacity", Min = 0, Max = 100, Default = 100, Suffix = "%",
        Callback = function(v) Window.Main.BackgroundTransparency = 1 - (v / 100) end })
    a:AddKeybind({ Text = "Toggle interface", Default = Enum.KeyCode.Insert })
    a:AddToggle({ Text = "Notifications", Default = true, Flag = "ui_notify" })

    local b = Tab:AddGroup("Configuration", "left")
    b:AddTextbox({ Text = "Config name", Placeholder = "default", Flag = "cfg_name" })
    b:AddButton({ Text = "Save", Callback = function() Ember:Notify("save hook not attached", 3) end })
    b:AddButton({ Text = "Load", Callback = function() Ember:Notify("load hook not attached", 3) end })

    local c = Tab:AddGroup("Danger", "right")
    c:AddLabel("Unloading destroys the interface entirely.")
    c:AddDivider()
    c:AddButton({ Text = "Unload", Callback = function()
        Ember:Notify("unloading...", 1)
        task.wait(1); Screen:Destroy()
    end })
end

return Ember
