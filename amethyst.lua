--[[
    AMETHYST UI  —  v1.0
    A soft, modern Roblox interface library.

    Identity : deep violet-black surfaces, rounded cards, gradient accents,
               horizontal tab bar with a sliding underline, pill switches.

    Usage:
        local Amethyst = loadstring(game:HttpGet("<raw url>"))()
        local Window = Amethyst:CreateWindow({ Title = "Amethyst", SubTitle = "v1.0" })
        local Tab    = Window:AddTab("Main")
        local Card   = Tab:AddCard("General", "left")
        Card:AddToggle({ Text = "Enabled", Callback = function(v) end })

    Every element accepts a Callback. Attach your own functions there.
    Toggle the interface with RightControl (configurable).
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
    Background   = Color3.fromRGB( 12,  10,  18),
    Panel        = Color3.fromRGB( 20,  17,  28),
    Card         = Color3.fromRGB( 25,  21,  35),
    Element      = Color3.fromRGB( 33,  28,  46),
    ElementHover = Color3.fromRGB( 42,  36,  58),
    Border       = Color3.fromRGB( 40,  34,  55),
    Accent       = Color3.fromRGB(139,  92, 246),  -- violet
    AccentTo     = Color3.fromRGB(217,  70, 239),  -- magenta (gradient end)
    Text         = Color3.fromRGB(232, 228, 240),
    TextDim      = Color3.fromRGB(150, 142, 170),
    TextFaint    = Color3.fromRGB(103,  96, 122),
    Risk         = Color3.fromRGB(244,  93, 118),
}

local Registry = {}

local function reg(inst, prop, key)
    table.insert(Registry, { inst = inst, prop = prop, key = key })
    inst[prop] = Theme[key]
    return inst
end

-- Gradient instances re-tint through their own list
local Gradients = {}

local function regGradient(g)
    table.insert(Gradients, g)
    g.Color = ColorSequence.new(Theme.Accent, Theme.AccentTo)
    return g
end

local function retint(key, color)
    Theme[key] = color
    for _, e in ipairs(Registry) do
        if e.key == key and e.inst and e.inst.Parent ~= nil then
            pcall(function() e.inst[e.prop] = color end)
        end
    end
    if key == "Accent" or key == "AccentTo" then
        for _, g in ipairs(Gradients) do
            if g.Parent ~= nil then
                pcall(function()
                    g.Color = ColorSequence.new(Theme.Accent, Theme.AccentTo)
                end)
            end
        end
    end
end

--=========================================================================--
--  FONTS
--=========================================================================--

local function font(name, fallback)
    local ok, f = pcall(function() return Enum.Font[name] end)
    if ok and f then return f end
    return Enum.Font[fallback or "SourceSans"]
end

local F = {
    Label = font("Gotham", "SourceSans"),
    Head  = font("GothamMedium", "SourceSansSemibold"),
    Bold  = font("GothamBold", "SourceSansBold"),
    Mono  = font("RobotoMono", "Code"),
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

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end

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

local TW_FAST = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_MED  = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TW_SOFT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_SLOW = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

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

local Amethyst = {}
Amethyst.Flags = {}
Amethyst.Theme = Theme

local Screen = new("ScreenGui", {
    Name           = "AmethystUI",
    ResetOnSpawn   = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder   = 999,
})
mount(Screen)

--=========================================================================--
--  NOTIFICATIONS
--=========================================================================--

local NotifyHolder = new("Frame", {
    AnchorPoint            = Vector2.new(1, 0),
    Position               = UDim2.new(1, -18, 0, 18),
    Size                   = UDim2.new(0, 280, 1, -36),
    BackgroundTransparency = 1,
    Parent                 = Screen,
}, {
    new("UIListLayout", {
        Padding             = UDim.new(0, 8),
        SortOrder           = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    }),
})

function Amethyst:Notify(title, body, duration)
    duration = duration or 3.5

    local card = new("Frame", {
        Size                   = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        ClipsDescendants       = true,
        Parent                 = NotifyHolder,
    })

    local h = body and 52 or 38

    local inner = new("Frame", {
        Size   = UDim2.new(1, 0, 0, h),
        Parent = card,
    }, { corner(8), stroke("Border") })
    reg(inner, "BackgroundColor3", "Panel")

    local bar = new("Frame", {
        Position        = UDim2.new(0, 0, 0, 0),
        Size            = UDim2.new(0, 3, 1, 0),
        BorderSizePixel = 0,
        Parent          = inner,
    }, { corner(2), regGradient(new("UIGradient", { Rotation = 90 })) })
    bar.BackgroundColor3 = Color3.new(1, 1, 1)

    local t = new("TextLabel", {
        Position               = UDim2.new(0, 14, 0, body and 8 or 0),
        Size                   = UDim2.new(1, -24, 0, body and 16 or h),
        BackgroundTransparency = 1,
        Font                   = F.Head,
        Text                   = tostring(title),
        TextSize               = 13,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Parent                 = inner,
    })
    reg(t, "TextColor3", "Text")

    local bl
    if body then
        bl = new("TextLabel", {
            Position               = UDim2.new(0, 14, 0, 26),
            Size                   = UDim2.new(1, -24, 0, 18),
            BackgroundTransparency = 1,
            Font                   = F.Label,
            Text                   = tostring(body),
            TextSize               = 12,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextTruncate           = Enum.TextTruncate.AtEnd,
            Parent                 = inner,
        })
        reg(bl, "TextColor3", "TextDim")
    end

    tween(card, TW_MED, { Size = UDim2.new(1, 0, 0, h) })

    task.delay(duration, function()
        tween(card,  TW_SOFT, { Size = UDim2.new(1, 0, 0, 0) })
        tween(inner, TW_SOFT, { BackgroundTransparency = 1 })
        tween(t,     TW_SOFT, { TextTransparency = 1 })
        if bl then tween(bl, TW_SOFT, { TextTransparency = 1 }) end
        task.wait(0.3)
        card:Destroy()
    end)
end

--=========================================================================--
--  WINDOW
--=========================================================================--

function Amethyst:CreateWindow(cfg)
    cfg = cfg or {}
    local title     = cfg.Title     or "Amethyst"
    local subTitle  = cfg.SubTitle  or "v1.0"
    local size      = cfg.Size      or UDim2.new(0, 720, 0, 490)
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightControl

    local Main = new("Frame", {
        Name             = "Window",
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0.5, 0, 0.5, 0),
        Size             = UDim2.new(0, 0, 0, 0),
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        Visible          = false,
        Parent           = Screen,
    }, { corner(12), stroke("Border") })
    reg(Main, "BackgroundColor3", "Background")

    ------------------------------------------------------------------
    -- Header
    ------------------------------------------------------------------
    local Header = new("Frame", {
        Size                   = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        Parent                 = Main,
    })

    local dot = new("Frame", {
        AnchorPoint      = Vector2.new(0, 0.5),
        Position         = UDim2.new(0, 18, 0.5, 0),
        Size             = UDim2.new(0, 10, 0, 10),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel  = 0,
        Parent           = Header,
    }, { corner(5), regGradient(new("UIGradient", { Rotation = 45 })) })

    local brand = new("TextLabel", {
        Position               = UDim2.new(0, 36, 0, 12),
        Size                   = UDim2.new(0, 200, 0, 16),
        BackgroundTransparency = 1,
        Font                   = F.Bold,
        Text                   = title,
        TextSize               = 15,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = Header,
    })
    reg(brand, "TextColor3", "Text")

    local sub = new("TextLabel", {
        Position               = UDim2.new(0, 36, 0, 28),
        Size                   = UDim2.new(0, 240, 0, 14),
        BackgroundTransparency = 1,
        Font                   = F.Label,
        Text                   = subTitle,
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Parent                 = Header,
    })
    reg(sub, "TextColor3", "TextFaint")

    local function headBtn(char, offset, hoverKey, cb)
        local b = new("TextButton", {
            AnchorPoint            = Vector2.new(1, 0.5),
            Position               = UDim2.new(1, -offset, 0.5, 0),
            Size                   = UDim2.new(0, 26, 0, 26),
            BackgroundTransparency = 1,
            AutoButtonColor        = false,
            Font                   = F.Head,
            Text                   = char,
            TextSize               = 15,
            Parent                 = Header,
        }, { corner(6) })
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

    headBtn("×", 14, "Risk", function()
        tween(Main, TW_SOFT, { Size = UDim2.new(0, fullSize.X.Offset, 0, 0) })
        task.wait(0.28); Screen:Destroy()
    end)
    headBtn("–", 46, "Accent", function()
        minimized = not minimized
        tween(Main, TW_SOFT, {
            Size = minimized and UDim2.new(0, fullSize.X.Offset, 0, 88) or fullSize
        })
    end)

    ------------------------------------------------------------------
    -- Tab bar with sliding gradient underline
    ------------------------------------------------------------------
    local TabBar = new("Frame", {
        Position               = UDim2.new(0, 18, 0, 52),
        Size                   = UDim2.new(1, -36, 0, 34),
        BackgroundTransparency = 1,
        Parent                 = Main,
    }, { list(4, Enum.FillDirection.Horizontal) })

    local underline = new("Frame", {
        Position         = UDim2.new(0, 18, 0, 85),
        Size             = UDim2.new(0, 0, 0, 2),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel  = 0,
        Parent           = Main,
    }, { corner(1), regGradient(new("UIGradient", {})) })

    local barLine = new("Frame", {
        Position        = UDim2.new(0, 0, 0, 86),
        Size            = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        Parent          = Main,
    })
    reg(barLine, "BackgroundColor3", "Border")

    local Content = new("Frame", {
        Position               = UDim2.new(0, 0, 0, 87),
        Size                   = UDim2.new(1, 0, 1, -87),
        BackgroundTransparency = 1,
        ClipsDescendants       = true,
        Parent                 = Main,
    })

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
            Font                   = F.Head,
            Text                   = name,
            TextSize               = 13,
            Parent                 = TabBar,
        }, { pad(0, 0, 14, 14) })
        reg(btn, "TextColor3", "TextDim")

        local page = new("ScrollingFrame", {
            Size                   = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel        = 0,
            ScrollBarThickness     = 3,
            ScrollBarImageColor3   = Theme.Border,
            CanvasSize             = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize    = Enum.AutomaticSize.Y,
            Visible                = false,
            Parent                 = Content,
        }, { pad(16, 16, 18, 18) })

        local colHolder = new("Frame", {
            Size                   = UDim2.new(1, 0, 0, 0),
            AutomaticSize          = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent                 = page,
        })

        local left = new("Frame", {
            Size                   = UDim2.new(0.5, -7, 0, 0),
            AutomaticSize          = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent                 = colHolder,
        }, { list(12) })

        local right = new("Frame", {
            Position               = UDim2.new(0.5, 7, 0, 0),
            Size                   = UDim2.new(0.5, -7, 0, 0),
            AutomaticSize          = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent                 = colHolder,
        }, { list(12) })

        btn.MouseEnter:Connect(function()
            if activeTab ~= Tab then btn.TextColor3 = Theme.Text end
        end)
        btn.MouseLeave:Connect(function()
            if activeTab ~= Tab then btn.TextColor3 = Theme.TextDim end
        end)

        function Tab:Select()
            for _, t in ipairs(Window.Tabs) do t._deselect() end
            activeTab      = Tab
            page.Visible   = true
            btn.TextColor3 = Theme.Text
            task.defer(function()
                local x = btn.AbsolutePosition.X - TabBar.AbsolutePosition.X + 18
                tween(underline, TW_SOFT, {
                    Position = UDim2.new(0, x, 0, 85),
                    Size     = UDim2.new(0, btn.AbsoluteSize.X, 0, 2),
                })
            end)
        end

        function Tab._deselect()
            page.Visible   = false
            btn.TextColor3 = Theme.TextDim
        end

        btn.MouseButton1Click:Connect(function() Tab:Select() end)

        --==========================================================--
        --  CARD
        --==========================================================--
        function Tab:AddCard(cardTitle, side)
            local parentCol = (side == "right") and right or left

            local wrap = new("Frame", {
                Size                   = UDim2.new(1, 0, 0, 0),
                AutomaticSize          = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Parent                 = parentCol,
            }, { list(8) })

            -- header row: gradient tick + title
            local head = new("Frame", {
                Size                   = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                LayoutOrder            = 1,
                Parent                 = wrap,
            })

            local tick = new("Frame", {
                AnchorPoint      = Vector2.new(0, 0.5),
                Position         = UDim2.new(0, 0, 0.5, 0),
                Size             = UDim2.new(0, 3, 0, 12),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BorderSizePixel  = 0,
                Parent           = head,
            }, { corner(2), regGradient(new("UIGradient", { Rotation = 90 })) })

            local ht = new("TextLabel", {
                Position               = UDim2.new(0, 11, 0, 0),
                Size                   = UDim2.new(1, -11, 1, 0),
                BackgroundTransparency = 1,
                Font                   = F.Head,
                Text                   = cardTitle,
                TextSize               = 12,
                TextXAlignment         = Enum.TextXAlignment.Left,
                Parent                 = head,
            })
            reg(ht, "TextColor3", "TextDim")

            local body = new("Frame", {
                Size            = UDim2.new(1, 0, 0, 0),
                AutomaticSize   = Enum.AutomaticSize.Y,
                BorderSizePixel = 0,
                LayoutOrder     = 2,
                Parent          = wrap,
            }, { corner(8), stroke("Border"), list(6), pad(12, 12, 12, 12) })
            reg(body, "BackgroundColor3", "Card")

            local Card = {}

            local function row(h)
                return new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, h),
                    BackgroundTransparency = 1,
                    Parent                 = body,
                })
            end

            ----------------------------------------------------------
            function Card:AddLabel(text)
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
                return { Set = function(_, t2) l.Text = t2 end }
            end

            function Card:AddDivider()
                local r = row(9)
                local d = new("Frame", {
                    Position        = UDim2.new(0, 0, 0.5, 0),
                    Size            = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    Parent          = r,
                })
                reg(d, "BackgroundColor3", "Border")
            end

            ----------------------------------------------------------
            --  TOGGLE  (pill switch)
            ----------------------------------------------------------
            function Card:AddToggle(o)
                o = o or {}
                local state = o.Default or false

                local r = row(24)
                local btn2 = new("TextButton", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    AutoButtonColor        = false,
                    Text                   = "",
                    Parent                 = r,
                })

                local lbl = new("TextLabel", {
                    Size                   = UDim2.new(1, -46, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Toggle",
                    TextSize               = 13,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = btn2,
                })
                reg(lbl, "TextColor3", "TextDim")

                local track = new("Frame", {
                    AnchorPoint     = Vector2.new(1, 0.5),
                    Position        = UDim2.new(1, 0, 0.5, 0),
                    Size            = UDim2.new(0, 34, 0, 18),
                    BorderSizePixel = 0,
                    Parent          = btn2,
                }, { corner(9) })
                reg(track, "BackgroundColor3", "Element")

                local trackFill = new("Frame", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3       = Color3.new(1, 1, 1),
                    BackgroundTransparency = 1,
                    BorderSizePixel        = 0,
                    Parent                 = track,
                }, { corner(9), regGradient(new("UIGradient", {})) })

                local knob = new("Frame", {
                    AnchorPoint      = Vector2.new(0, 0.5),
                    Position         = UDim2.new(0, 3, 0.5, 0),
                    Size             = UDim2.new(0, 12, 0, 12),
                    BackgroundColor3 = Color3.fromRGB(180, 172, 200),
                    BorderSizePixel  = 0,
                    ZIndex           = 3,
                    Parent           = track,
                }, { corner(6) })

                local api = {}

                function api:Set(v, silent)
                    state = v and true or false
                    if o.Flag then Amethyst.Flags[o.Flag] = state end
                    tween(knob, TW_MED, {
                        Position         = state and UDim2.new(1, -15, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                        BackgroundColor3 = state and Color3.new(1, 1, 1) or Color3.fromRGB(180, 172, 200),
                    })
                    tween(trackFill, TW_FAST, { BackgroundTransparency = state and 0 or 1 })
                    lbl.TextColor3 = state and Theme.Text or Theme.TextDim
                    if not silent and o.Callback then task.spawn(o.Callback, state) end
                end

                function api:Get() return state end

                btn2.MouseButton1Click:Connect(function() api:Set(not state) end)
                btn2.MouseEnter:Connect(function()
                    if not state then lbl.TextColor3 = Theme.Text end
                end)
                btn2.MouseLeave:Connect(function()
                    if not state then lbl.TextColor3 = Theme.TextDim end
                end)

                api:Set(state, true)
                return api
            end

            ----------------------------------------------------------
            --  SLIDER  (rounded track, gradient fill, circular knob)
            ----------------------------------------------------------
            function Card:AddSlider(o)
                o = o or {}
                local min, max = o.Min or 0, o.Max or 100
                local decimals = o.Decimals or 0
                local value    = math.clamp(o.Default or min, min, max)
                local suffix   = o.Suffix or ""

                local r = row(38)

                local lbl = new("TextLabel", {
                    Size                   = UDim2.new(1, -80, 0, 16),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Slider",
                    TextSize               = 13,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(lbl, "TextColor3", "TextDim")

                local valBox = new("Frame", {
                    AnchorPoint     = Vector2.new(1, 0),
                    Position        = UDim2.new(1, 0, 0, 0),
                    Size            = UDim2.new(0, 58, 0, 17),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(5) })
                reg(valBox, "BackgroundColor3", "Element")

                local valLbl = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Mono,
                    Text                   = "",
                    TextSize               = 11,
                    Parent                 = valBox,
                })
                reg(valLbl, "TextColor3", "Text")

                local track = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 26),
                    Size            = UDim2.new(1, 0, 0, 6),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(3) })
                reg(track, "BackgroundColor3", "Element")

                local fill = new("Frame", {
                    Size             = UDim2.new(0, 0, 1, 0),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel  = 0,
                    Parent           = track,
                }, { corner(3), regGradient(new("UIGradient", {})) })

                local knob = new("Frame", {
                    AnchorPoint      = Vector2.new(0.5, 0.5),
                    Position         = UDim2.new(0, 0, 0.5, 0),
                    Size             = UDim2.new(0, 12, 0, 12),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel  = 0,
                    ZIndex           = 3,
                    Parent           = track,
                }, { corner(6) })

                local api = {}

                function api:Set(v, silent)
                    value = math.clamp(round(v, decimals), min, max)
                    if o.Flag then Amethyst.Flags[o.Flag] = value end
                    local a = (max == min) and 0 or (value - min) / (max - min)
                    tween(fill, TW_FAST, { Size = UDim2.new(a, 0, 1, 0) })
                    tween(knob, TW_FAST, { Position = UDim2.new(a, 0, 0.5, 0) })
                    valLbl.Text = tostring(value) .. suffix
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
                        tween(knob, TW_FAST, { Size = UDim2.new(0, 15, 0, 15) })
                    end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                        if sliding then tween(knob, TW_FAST, { Size = UDim2.new(0, 12, 0, 12) }) end
                        sliding = false
                    end
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
            --  BUTTON  (gradient fill on hover)
            ----------------------------------------------------------
            function Card:AddButton(o)
                o = o or {}
                local r = row(30)
                local b = new("TextButton", {
                    Size            = UDim2.new(1, 0, 1, 0),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Text            = "",
                    Parent          = r,
                }, { corner(6), stroke("Border") })
                reg(b, "BackgroundColor3", "Element")

                local grad = new("Frame", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3       = Color3.new(1, 1, 1),
                    BackgroundTransparency = 1,
                    BorderSizePixel        = 0,
                    Parent                 = b,
                }, { corner(6), regGradient(new("UIGradient", {})) })

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Head,
                    Text                   = o.Text or "Button",
                    TextSize               = 12,
                    ZIndex                 = 3,
                    Parent                 = b,
                })
                reg(l, "TextColor3", "TextDim")

                b.MouseEnter:Connect(function()
                    tween(grad, TW_FAST, { BackgroundTransparency = 0.82 })
                    l.TextColor3 = Theme.Text
                end)
                b.MouseLeave:Connect(function()
                    tween(grad, TW_FAST, { BackgroundTransparency = 1 })
                    l.TextColor3 = Theme.TextDim
                end)
                b.MouseButton1Click:Connect(function()
                    tween(grad, TW_FAST, { BackgroundTransparency = 0.6 })
                    task.delay(0.1, function()
                        tween(grad, TW_FAST, { BackgroundTransparency = 0.82 })
                    end)
                    if o.Callback then task.spawn(o.Callback) end
                end)
                return b
            end

            ----------------------------------------------------------
            function Card:AddTextbox(o)
                o = o or {}
                local r = row(44)

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Input",
                    TextSize               = 13,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local holder = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 20),
                    Size            = UDim2.new(1, 0, 0, 24),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(6), stroke("Border") })
                reg(holder, "BackgroundColor3", "Element")

                local tb = new("TextBox", {
                    Position               = UDim2.new(0, 10, 0, 0),
                    Size                   = UDim2.new(1, -20, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Default or "",
                    PlaceholderText        = o.Placeholder or "...",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    ClearTextOnFocus       = false,
                    Parent                 = holder,
                })
                reg(tb, "TextColor3", "Text")
                reg(tb, "PlaceholderColor3", "TextFaint")

                local hs = holder:FindFirstChildOfClass("UIStroke")
                tb.Focused:Connect(function()
                    if hs then tween(hs, TW_FAST, { Color = Theme.Accent }) end
                end)
                tb.FocusLost:Connect(function(enter)
                    if hs then tween(hs, TW_FAST, { Color = Theme.Border }) end
                    if o.Flag then Amethyst.Flags[o.Flag] = tb.Text end
                    if o.Callback then task.spawn(o.Callback, tb.Text, enter) end
                end)
                return tb
            end

            ----------------------------------------------------------
            --  DROPDOWN  (single or multi select)
            ----------------------------------------------------------
            function Card:AddDropdown(o)
                o = o or {}
                local options = o.Options or {}
                local multi   = o.Multi or false
                local chosen  = multi and (o.Default or {}) or (o.Default or options[1] or "None")
                local open    = false

                local r = new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, 44),
                    BackgroundTransparency = 1,
                    ClipsDescendants       = true,
                    Parent                 = body,
                })

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Dropdown",
                    TextSize               = 13,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local head2 = new("TextButton", {
                    Position        = UDim2.new(0, 0, 0, 20),
                    Size            = UDim2.new(1, 0, 0, 24),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Text            = "",
                    Parent          = r,
                }, { corner(6), stroke("Border") })
                reg(head2, "BackgroundColor3", "Element")

                local sel = new("TextLabel", {
                    Position               = UDim2.new(0, 10, 0, 0),
                    Size                   = UDim2.new(1, -32, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = "",
                    TextSize               = 12,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    TextTruncate           = Enum.TextTruncate.AtEnd,
                    Parent                 = head2,
                })
                reg(sel, "TextColor3", "Text")

                local arrow = new("TextLabel", {
                    AnchorPoint            = Vector2.new(1, 0.5),
                    Position               = UDim2.new(1, -10, 0.5, 0),
                    Size                   = UDim2.new(0, 12, 0, 12),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = "v",
                    TextSize               = 11,
                    Parent                 = head2,
                })
                reg(arrow, "TextColor3", "TextDim")

                local listHolder = new("Frame", {
                    Position               = UDim2.new(0, 0, 0, 48),
                    Size                   = UDim2.new(1, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Parent                 = r,
                }, { list(3) })

                local api = {}

                local function display()
                    if multi then
                        if #chosen == 0 then return "None" end
                        return table.concat(chosen, ", ")
                    end
                    return tostring(chosen)
                end

                local function isChosen(opt)
                    if not multi then return chosen == opt end
                    for _, v in ipairs(chosen) do if v == opt then return true end end
                    return false
                end

                local function rebuild()
                    for _, c in ipairs(listHolder:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for _, opt in ipairs(options) do
                        local ob = new("TextButton", {
                            Size            = UDim2.new(1, 0, 0, 22),
                            AutoButtonColor = false,
                            BorderSizePixel = 0,
                            Font            = F.Label,
                            Text            = "   " .. tostring(opt),
                            TextSize         = 12,
                            TextXAlignment  = Enum.TextXAlignment.Left,
                            Parent          = listHolder,
                        }, { corner(5) })
                        reg(ob, "BackgroundColor3", "Element")
                        ob.TextColor3 = isChosen(opt) and Theme.Accent or Theme.TextDim

                        ob.MouseEnter:Connect(function()
                            tween(ob, TW_FAST, { BackgroundColor3 = Theme.ElementHover })
                        end)
                        ob.MouseLeave:Connect(function()
                            tween(ob, TW_FAST, { BackgroundColor3 = Theme.Element })
                        end)
                        ob.MouseButton1Click:Connect(function()
                            if multi then
                                local found
                                for idx, v in ipairs(chosen) do
                                    if v == opt then found = idx break end
                                end
                                if found then table.remove(chosen, found)
                                else table.insert(chosen, opt) end
                                api:Set(chosen)
                            else
                                api:Set(opt)
                                open = false
                                tween(r, TW_SOFT, { Size = UDim2.new(1, 0, 0, 44) })
                                arrow.Text = "v"
                            end
                        end)
                    end
                end

                function api:Set(v, silent)
                    chosen   = v
                    sel.Text = display()
                    if o.Flag then Amethyst.Flags[o.Flag] = v end
                    rebuild()
                    if not silent and o.Callback then task.spawn(o.Callback, v) end
                end

                function api:Get() return chosen end
                function api:SetOptions(t) options = t; rebuild() end

                head2.MouseButton1Click:Connect(function()
                    open = not open
                    local h = open and (48 + #options * 25) or 44
                    tween(r, TW_SOFT, { Size = UDim2.new(1, 0, 0, h) })
                    arrow.Text = open and "^" or "v"
                end)

                api:Set(chosen, true)
                return api
            end

            ----------------------------------------------------------
            function Card:AddKeybind(o)
                o = o or {}
                local bound, binding = o.Default, false

                local r = row(24)
                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, -76, 1, 0),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Keybind",
                    TextSize               = 13,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local kb = new("TextButton", {
                    AnchorPoint     = Vector2.new(1, 0.5),
                    Position        = UDim2.new(1, 0, 0.5, 0),
                    Size            = UDim2.new(0, 70, 0, 20),
                    AutoButtonColor = false,
                    BorderSizePixel = 0,
                    Font            = F.Mono,
                    Text            = bound and bound.Name or "None",
                    TextSize        = 11,
                    Parent          = r,
                }, { corner(5), stroke("Border") })
                reg(kb, "BackgroundColor3", "Element")
                reg(kb, "TextColor3", "TextDim")

                kb.MouseButton1Click:Connect(function()
                    binding = true
                    kb.Text = "..."
                    kb.TextColor3 = Theme.Accent
                end)

                UserInputService.InputBegan:Connect(function(i, gpe)
                    if binding and i.UserInputType == Enum.UserInputType.Keyboard then
                        binding = false
                        if i.KeyCode == Enum.KeyCode.Backspace then
                            bound, kb.Text = nil, "None"
                        else
                            bound, kb.Text = i.KeyCode, i.KeyCode.Name
                        end
                        kb.TextColor3 = Theme.TextDim
                        if o.Flag then Amethyst.Flags[o.Flag] = bound end
                        if o.OnBind then task.spawn(o.OnBind, bound) end
                        return
                    end
                    if gpe then return end
                    if bound and i.KeyCode == bound and o.Callback then task.spawn(o.Callback) end
                end)

                return {
                    Get = function() return bound end,
                    Set = function(_, k) bound = k; kb.Text = k and k.Name or "None" end,
                }
            end

            ----------------------------------------------------------
            --  COLORPICKER
            ----------------------------------------------------------
            function Card:AddColorpicker(o)
                o = o or {}
                local col = o.Default or Theme.Accent
                local h, s, v = Color3.toHSV(col)
                local open = false

                local r = new("Frame", {
                    Size                   = UDim2.new(1, 0, 0, 24),
                    BackgroundTransparency = 1,
                    ClipsDescendants       = true,
                    Parent                 = body,
                })

                local l = new("TextLabel", {
                    Size                   = UDim2.new(1, -50, 0, 24),
                    BackgroundTransparency = 1,
                    Font                   = F.Label,
                    Text                   = o.Text or "Colour",
                    TextSize               = 13,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    Parent                 = r,
                })
                reg(l, "TextColor3", "TextDim")

                local swatch = new("TextButton", {
                    AnchorPoint      = Vector2.new(1, 0),
                    Position         = UDim2.new(1, 0, 0, 4),
                    Size             = UDim2.new(0, 40, 0, 17),
                    BackgroundColor3 = col,
                    AutoButtonColor  = false,
                    BorderSizePixel  = 0,
                    Text             = "",
                    Parent           = r,
                }, { corner(5), stroke("Border") })

                local body2 = new("Frame", {
                    Position        = UDim2.new(0, 0, 0, 30),
                    Size            = UDim2.new(1, 0, 0, 108),
                    BorderSizePixel = 0,
                    Parent          = r,
                }, { corner(8), stroke("Border") })
                reg(body2, "BackgroundColor3", "Element")

                local field = new("Frame", {
                    Position         = UDim2.new(0, 10, 0, 10),
                    Size             = UDim2.new(1, -20, 0, 68),
                    BackgroundColor3 = Color3.fromHSV(h, 1, 1),
                    BorderSizePixel  = 0,
                    Parent           = body2,
                }, { corner(6) })

                new("Frame", {
                    Size             = UDim2.new(1, 0, 1, 0),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel  = 0,
                    Parent           = field,
                }, {
                    corner(6),
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
                    corner(6),
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
                    Size                   = UDim2.new(0, 9, 0, 9),
                    BackgroundTransparency = 1,
                    ZIndex                 = 5,
                    Parent                 = field,
                }, { corner(5), new("UIStroke", { Color = Color3.new(1,1,1), Thickness = 2 }) })

                local hueBar = new("Frame", {
                    Position        = UDim2.new(0, 10, 0, 86),
                    Size            = UDim2.new(1, -20, 0, 12),
                    BorderSizePixel = 0,
                    Parent          = body2,
                }, {
                    corner(6),
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
                    Size             = UDim2.new(0, 4, 1, 4),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BorderSizePixel  = 0,
                    ZIndex           = 5,
                    Parent           = hueBar,
                }, { corner(2) })

                local api = {}

                local function push(silent)
                    col = Color3.fromHSV(h, s, v)
                    swatch.BackgroundColor3 = col
                    field.BackgroundColor3  = Color3.fromHSV(h, 1, 1)
                    cursor.Position         = UDim2.new(s, 0, 1 - v, 0)
                    hueCursor.Position      = UDim2.new(h, 0, 0.5, 0)
                    if o.Flag then Amethyst.Flags[o.Flag] = col end
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
                    tween(r, TW_SOFT, { Size = UDim2.new(1, 0, 0, open and 142 or 24) })
                end)

                push(true)
                return api
            end

            return Card
        end

        table.insert(Window.Tabs, Tab)
        if #Window.Tabs == 1 then task.defer(function() Tab:Select() end) end
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
    }, { corner(14), stroke("Border") })
    reg(Welcome, "BackgroundColor3", "Background")

    -- gradient banner strip
    local banner = new("Frame", {
        Size                   = UDim2.new(1, 0, 0, 3),
        BackgroundColor3       = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Parent                 = Welcome,
    }, { regGradient(new("UIGradient", {})) })

    local wTitle = new("TextLabel", {
        Position               = UDim2.new(0, 0, 0, 46),
        Size                   = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Font                   = F.Bold,
        Text                   = title,
        TextSize               = 26,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wTitle, "TextColor3", "Text")

    local wSub = new("TextLabel", {
        Position               = UDim2.new(0, 0, 0, 76),
        Size                   = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Font                   = F.Label,
        Text                   = "Welcome back, " .. (LocalPlayer and LocalPlayer.DisplayName or "guest"),
        TextSize               = 13,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wSub, "TextColor3", "TextDim")

    local wStatus = new("TextLabel", {
        Position               = UDim2.new(0, 0, 0, 118),
        Size                   = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "",
        TextSize               = 11,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wStatus, "TextColor3", "TextFaint")

    local wPct = new("TextLabel", {
        AnchorPoint            = Vector2.new(1, 0),
        Position               = UDim2.new(1, -50, 0, 118),
        Size                   = UDim2.new(0, 40, 0, 14),
        BackgroundTransparency = 1,
        Font                   = F.Mono,
        Text                   = "0%",
        TextSize               = 11,
        TextXAlignment         = Enum.TextXAlignment.Right,
        TextTransparency       = 1,
        Parent                 = Welcome,
    })
    reg(wPct, "TextColor3", "Text")

    local wBarBg = new("Frame", {
        AnchorPoint            = Vector2.new(0.5, 0),
        Position               = UDim2.new(0.5, 0, 0, 138),
        Size                   = UDim2.new(0, 280, 0, 5),
        BorderSizePixel        = 0,
        BackgroundTransparency = 1,
        Parent                 = Welcome,
    }, { corner(3) })
    reg(wBarBg, "BackgroundColor3", "Element")

    local wBar = new("Frame", {
        Size                   = UDim2.new(0, 0, 1, 0),
        BackgroundColor3       = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Parent                 = wBarBg,
    }, { corner(3), regGradient(new("UIGradient", {})) })

    local wBtn = new("TextButton", {
        AnchorPoint            = Vector2.new(0.5, 0),
        Position               = UDim2.new(0.5, 0, 0, 164),
        Size                   = UDim2.new(0, 160, 0, 36),
        AutoButtonColor        = false,
        BorderSizePixel        = 0,
        Text                   = "",
        BackgroundTransparency = 1,
        Parent                 = Welcome,
    }, { corner(8) })
    reg(wBtn, "BackgroundColor3", "Element")

    local wBtnGrad = new("Frame", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundColor3       = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel        = 0,
        Parent                 = wBtn,
    }, { corner(8), regGradient(new("UIGradient", {})) })

    local wBtnLbl = new("TextLabel", {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Font                   = F.Bold,
        Text                   = "LOAD",
        TextSize               = 13,
        TextTransparency       = 1,
        ZIndex                 = 3,
        Parent                 = wBtn,
    })
    reg(wBtnLbl, "TextColor3", "Text")

    wBtn.MouseEnter:Connect(function()
        tween(wBtnGrad, TW_FAST, { BackgroundTransparency = 0.7 })
    end)
    wBtn.MouseLeave:Connect(function()
        tween(wBtnGrad, TW_FAST, { BackgroundTransparency = 1 })
    end)

    task.spawn(function()
        tween(Welcome, TW_SLOW, { Size = UDim2.new(0, 380, 0, 232) })
        task.wait(0.32)
        tween(banner, TW_SOFT, { BackgroundTransparency = 0 })
        tween(wTitle, TW_SOFT, { TextTransparency = 0 })
        task.wait(0.08)
        tween(wSub,   TW_SOFT, { TextTransparency = 0 })
        task.wait(0.08)
        tween(wBtn,    TW_SOFT, { BackgroundTransparency = 0 })
        tween(wBtnLbl, TW_SOFT, { TextTransparency = 0 })
    end)

    local loaded = false
    wBtn.MouseButton1Click:Connect(function()
        if loaded then return end
        loaded = true
        wBtn.Active = false

        tween(wBtn,    TW_FAST, { BackgroundTransparency = 1 })
        tween(wBtnGrad,TW_FAST, { BackgroundTransparency = 1 })
        tween(wBtnLbl, TW_FAST, { TextTransparency = 1 })
        tween(wBarBg,  TW_FAST, { BackgroundTransparency = 0 })
        tween(wBar,    TW_FAST, { BackgroundTransparency = 0 })
        tween(wStatus, TW_FAST, { TextTransparency = 0 })
        tween(wPct,    TW_FAST, { TextTransparency = 0 })

        local steps = {
            { "Initialising interface", 0.25 },
            { "Building components",    0.55 },
            { "Applying theme",         0.82 },
            { "Ready",                  1.00 },
        }

        task.spawn(function()
            for _, step in ipairs(steps) do
                wStatus.Text = step[1]
                wPct.Text    = math.floor(step[2] * 100) .. "%"
                tween(wBar, TweenInfo.new(0.32, Enum.EasingStyle.Quad), {
                    Size = UDim2.new(step[2], 0, 1, 0)
                })
                task.wait(0.36)
            end
            task.wait(0.22)

            tween(Welcome, TW_SOFT, { Size = UDim2.new(0, 380, 0, 0) })
            task.wait(0.28)
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
--  Delete everything below this line to use AMETHYST as a pure library.
--=========================================================================--

local Window = Amethyst:CreateWindow({
    Title     = "Amethyst",
    SubTitle  = "interface library  •  v1.0",
    Size      = UDim2.new(0, 720, 0, 490),
    ToggleKey = Enum.KeyCode.RightControl,
    OnLoad    = function()
        Amethyst:Notify("Loaded", "Press RightControl to toggle the interface.", 4)
    end,
})

-------------------------------------------------- HOME
do
    local Tab = Window:AddTab("Home")

    local a = Tab:AddCard("Overview", "left")
    a:AddLabel("A soft, modern interface library for Roblox.")
    a:AddLabel("Rounded cards, gradient accents, pill switches.")
    a:AddDivider()
    a:AddButton({ Text = "Send test notification", Callback = function()
        Amethyst:Notify("Notification", "This is what a toast looks like.", 3.5)
    end })

    local b = Tab:AddCard("Session", "left")
    b:AddLabel("User    " .. (LocalPlayer and LocalPlayer.Name or "unknown"))
    b:AddLabel("Place   " .. tostring(game.PlaceId))

    local c = Tab:AddCard("Elements", "right")
    c:AddToggle({ Text = "Example toggle", Default = true, Flag = "demo_toggle",
        Callback = function(v) print("[amethyst] toggle:", v) end })
    c:AddToggle({ Text = "Second toggle", Flag = "demo_toggle2" })
    c:AddSlider({ Text = "Example slider", Min = 0, Max = 100, Default = 65, Suffix = "%",
        Flag = "demo_slider", Callback = function(v) print("[amethyst] slider:", v) end })
    c:AddSlider({ Text = "Decimal slider", Min = 0, Max = 5, Default = 2.5, Decimals = 2,
        Suffix = "x", Flag = "demo_slider2" })
    c:AddKeybind({ Text = "Example keybind", Default = Enum.KeyCode.G,
        Callback = function() Amethyst:Notify("Keybind", "G was pressed.", 2) end })
end

-------------------------------------------------- COMPONENTS
do
    local Tab = Window:AddTab("Components")

    local a = Tab:AddCard("Selection", "left")
    a:AddDropdown({ Text = "Single select", Options = { "Alpha", "Bravo", "Charlie", "Delta" },
        Default = "Alpha", Flag = "demo_drop",
        Callback = function(v) print("[amethyst] dropdown:", v) end })
    a:AddDropdown({ Text = "Multi select", Multi = true,
        Options = { "One", "Two", "Three", "Four" }, Default = { "One" }, Flag = "demo_multi" })

    local b = Tab:AddCard("Text", "left")
    b:AddTextbox({ Text = "Example textbox", Placeholder = "Type something...", Flag = "demo_text",
        Callback = function(t) print("[amethyst] textbox:", t) end })

    local c = Tab:AddCard("Actions", "right")
    c:AddButton({ Text = "Primary action", Callback = function()
        Amethyst:Notify("Action", "Primary action fired.", 3) end })
    c:AddButton({ Text = "Secondary action", Callback = function()
        Amethyst:Notify("Action", "Secondary action fired.", 3) end })
    c:AddDivider()
    c:AddButton({ Text = "Dump flags to console", Callback = function()
        for k, v in pairs(Amethyst.Flags) do print("[flag]", k, v) end
        Amethyst:Notify("Flags", "Printed to console.", 3)
    end })
end

-------------------------------------------------- THEME
do
    local Tab = Window:AddTab("Theme")

    local a = Tab:AddCard("Gradient", "left")
    a:AddLabel("The accent is a two-stop gradient. Change either end.")
    a:AddDivider()
    a:AddColorpicker({ Text = "Accent start", Default = Theme.Accent,
        Callback = function(c) retint("Accent", c) end })
    a:AddColorpicker({ Text = "Accent end", Default = Theme.AccentTo,
        Callback = function(c) retint("AccentTo", c) end })

    local b = Tab:AddCard("Presets", "right")
    local presets = {
        { "Amethyst", Color3.fromRGB(139,  92, 246), Color3.fromRGB(217,  70, 239) },
        { "Ocean",    Color3.fromRGB( 56, 189, 248), Color3.fromRGB( 45, 212, 191) },
        { "Sunset",   Color3.fromRGB(251, 146,  60), Color3.fromRGB(244,  63,  94) },
        { "Forest",   Color3.fromRGB( 74, 222, 128), Color3.fromRGB( 34, 197,  94) },
        { "Mono",     Color3.fromRGB(200, 200, 210), Color3.fromRGB(140, 140, 155) },
    }
    for _, p in ipairs(presets) do
        b:AddButton({ Text = p[1], Callback = function()
            retint("Accent", p[2]); retint("AccentTo", p[3])
            Amethyst:Notify("Theme", p[1] .. " applied.", 2)
        end })
    end
end

-------------------------------------------------- SETTINGS
do
    local Tab = Window:AddTab("Settings")

    local a = Tab:AddCard("Interface", "left")
    a:AddSlider({ Text = "Background opacity", Min = 0, Max = 100, Default = 100, Suffix = "%",
        Callback = function(v) Window.Main.BackgroundTransparency = 1 - (v / 100) end })
    a:AddKeybind({ Text = "Toggle interface", Default = Enum.KeyCode.RightControl })
    a:AddToggle({ Text = "Notifications", Default = true, Flag = "ui_notify" })

    local b = Tab:AddCard("Configuration", "left")
    b:AddTextbox({ Text = "Config name", Placeholder = "default", Flag = "cfg_name" })
    b:AddButton({ Text = "Save",   Callback = function() Amethyst:Notify("Config", "Save hook not attached.", 3) end })
    b:AddButton({ Text = "Load",   Callback = function() Amethyst:Notify("Config", "Load hook not attached.", 3) end })

    local c = Tab:AddCard("Danger", "right")
    c:AddLabel("Unloading destroys the interface entirely.")
    c:AddDivider()
    c:AddButton({ Text = "Unload", Callback = function()
        Amethyst:Notify("Unloading", "Goodbye.", 1)
        task.wait(1); Screen:Destroy()
    end })
end

return Amethyst
