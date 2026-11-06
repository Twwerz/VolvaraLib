--[[
    LibraryUI
    Interface library for Roblox executors.

    Built-in tabs : Settings / Config / About
    Config files : .lua and .json only (anything else is rejected)
    Settings : UI size, interface color, animations, effects, toggle key

    Usage (after hosting this file at a RAW URL):
        local LibraryUI = loadstring(game:HttpGet("LINK"))()
        local Window = LibraryUI:CreateWindow({ Title = "LibraryUI" })

        local Main = Window:AddTab("Main")
        Main:Toggle({ Name = "Example", Flag = "example", Callback = function(v) print(v) end })
]]

if getgenv and getgenv().LibraryUI then
    pcall(function() getgenv().LibraryUI:Destroy() end)
end

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

----------------------------------------------------------------------
-- Library state
----------------------------------------------------------------------
local DEFAULT_ACCENT = Color3.fromRGB(0, 72, 140)

local LibraryUI = {
    Version = "1.0.0",
    Flags = {},
    Setters = {},
    Accent = DEFAULT_ACCENT,
    Animations = true,
    AnimSpeed = 1,
    ToggleKey = Enum.KeyCode.RightShift,
    Folder = "LibraryUI",
}
LibraryUI.ConfigFolder = LibraryUI.Folder .. "/configs"

local SIZES = {
    Default = Vector2.new(560, 500),
    Small = Vector2.new(440, 400),
    Medium = Vector2.new(620, 540),
    Large = Vector2.new(720, 600),
    Big = Vector2.new(860, 680),
}
local SIZE_ORDER = { "Default", "Small", "Medium", "Large", "Big" }

local TITLE_H = 36
local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

local connections = {}
local themed = {}
local gradients = {}
local startClock = os.clock()

local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

local function safe(cb, ...)
    if type(cb) ~= "function" then return end
    task.spawn(function(...)
        local ok, err = pcall(cb, ...)
        if not ok then warn("[LibraryUI] " .. tostring(err)) end
    end, ...)
end

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local Shade = {
    Top = function(a) return a:Lerp(BLACK, 0.90) end,
    Base = function(a) return a:Lerp(BLACK, 0.80) end,
    Side = function(a) return a:Lerp(BLACK, 0.74) end,
    Panel = function(a) return a:Lerp(BLACK, 0.66) end,
    Row = function(a) return a:Lerp(BLACK, 0.52) end,
    RowHover = function(a) return a:Lerp(BLACK, 0.42) end,
    Accent = function(a) return a end,
    Hover = function(a) return a:Lerp(WHITE, 0.14) end,
    Press = function(a) return a:Lerp(BLACK, 0.25) end,
    Light = function(a) return a:Lerp(WHITE, 0.18) end,
    Line = function(a) return a:Lerp(WHITE, 0.25) end,
    Muted = function(a) return a:Lerp(WHITE, 0.62) end,
    Off = function(a) return a:Lerp(BLACK, 0.68) end,
}

local function windowGradient(a)
    return ColorSequence.new(Shade.Top(a), a:Lerp(BLACK, 0.60))
end

local function bind(inst, prop, fn)
    themed[#themed + 1] = { inst = inst, prop = prop, fn = fn }
    inst[prop] = fn(LibraryUI.Accent)
end

local function dur(t)
    return (t or 0.2) / LibraryUI.AnimSpeed
end

local function tween(inst, props, t, style, dir)
    if not LibraryUI.Animations then
        for k, v in pairs(props) do inst[k] = v end
        return nil
    end
    local tw = TweenService:Create(
        inst,
        TweenInfo.new(dur(t), style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

function LibraryUI:SetAccent(color)
    local h, s, v = color:ToHSV()
    color = Color3.fromHSV(h, s, math.clamp(v, 0.35, 0.9))
    self.Accent = color
    for i = #themed, 1, -1 do
        local e = themed[i]
        if e.inst.Parent == nil then
            table.remove(themed, i)
        else
            tween(e.inst, { [e.prop] = e.fn(color) }, 0.15)
        end
    end
    for _, g in ipairs(gradients) do
        g.inst.Color = g.fn(color)
    end
end

----------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------
local function new(class, props)
    local o = Instance.new(class)
    local parent = props.Parent
    for k, v in pairs(props) do
        if k ~= "Parent" then o[k] = v end
    end
    if parent then o.Parent = parent end
    return o
end

local function corner(parent, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

local function stroke(parent, fn, transparency)
    local s = new("UIStroke", {
        Thickness = 1,
        Transparency = transparency or 0.6,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
    bind(s, "Color", fn or Shade.Line)
    return s
end

local function padding(parent, l, t, r, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t),
        PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b),
        Parent = parent,
    })
end

local function label(props)
    props.BackgroundTransparency = 1
    props.Font = props.Font or FONT
    props.TextSize = props.TextSize or 13
    props.TextColor3 = props.TextColor3 or WHITE
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.BorderSizePixel = 0
    return new("TextLabel", props)
end

local function hoverable(btn, normal, hover, press, prop)
    prop = prop or "BackgroundColor3"
    local over = false
    btn.MouseEnter:Connect(function()
        over = true
        tween(btn, { [prop] = hover(LibraryUI.Accent) }, 0.15)
    end)
    btn.MouseLeave:Connect(function()
        over = false
        tween(btn, { [prop] = normal(LibraryUI.Accent) }, 0.2)
    end)
    if press then
        btn.MouseButton1Down:Connect(function()
            tween(btn, { [prop] = press(LibraryUI.Accent) }, 0.08)
        end)
        btn.MouseButton1Up:Connect(function()
            tween(btn, { [prop] = (over and hover or normal)(LibraryUI.Accent) }, 0.15)
        end)
    end
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function dragArea(hit, onMove)
    local dragging = false
    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            onMove(input.Position)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and isMove(input) then onMove(input.Position) end
    end)
    connect(UserInputService.InputEnded, function(input)
        if isPress(input) then dragging = false end
    end)
end

local function toHex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

----------------------------------------------------------------------
-- GUI root + notifications
----------------------------------------------------------------------
-- Mounts the GUI in PlayerGui.
local function mountGui(gui)
    -- PlayerGui only (no CoreGui / gethui)
    local candidates = {
        function() return LocalPlayer:WaitForChild("PlayerGui", 10) end,
    }

    for _, getParent in ipairs(candidates) do
        local okGet, parent = pcall(getParent)
        if okGet and parent then
            local okSet, errSet = pcall(function() gui.Parent = parent end)
            if okSet and gui.Parent == parent then
                LibraryUI.MountedIn = parent:GetFullName()
                return true
            end
            warn("[LibraryUI] parent failed (" .. tostring(parent) .. "): " .. tostring(errSet))
        else
            warn("[LibraryUI] could not get a parent: " .. tostring(parent))
        end
    end
    return false
end

local toastHolder

local function ensureGui()
    if LibraryUI.Gui and LibraryUI.Gui.Parent then return LibraryUI.Gui end
    local gui = new("ScreenGui", {
        Name = HttpService:GenerateGUID(false),
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999,
    })
    if not mountGui(gui) then
        error("[LibraryUI] Could not parent the GUI (gethui, CoreGui and PlayerGui all failed)")
    end
    LibraryUI.Gui = gui

    toastHolder = new("Frame", {
        Name = "Toasts",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -16),
        Size = UDim2.new(0, 260, 1, -32),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Parent = toastHolder,
    })
    return gui
end

local KIND_COLOR = {
    Success = Color3.fromRGB(70, 200, 120),
    Error = Color3.fromRGB(230, 80, 80),
    Warn = Color3.fromRGB(240, 180, 60),
}

function LibraryUI:Notify(opts)
    opts = opts or {}
    ensureGui()
    local wrap = new("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = toastHolder,
    })
    local inner = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.new(1, 30, 0, 0),
        BorderSizePixel = 0,
        Parent = wrap,
    })
    bind(inner, "BackgroundColor3", Shade.Panel)
    corner(inner, 6)
    stroke(inner, Shade.Line, 0.7)

    local bar = new("Frame", {
        Size = UDim2.new(0, 3, 1, -14),
        Position = UDim2.new(0, 7, 0, 7),
        BorderSizePixel = 0,
        Parent = inner,
    })
    corner(bar, 2)
    if KIND_COLOR[opts.Type] then
        bar.BackgroundColor3 = KIND_COLOR[opts.Type]
    else
        bind(bar, "BackgroundColor3", Shade.Hover)
    end

    label({
        Text = opts.Title or "LibraryUI", Font = FONT_BOLD, TextSize = 13,
        Position = UDim2.new(0, 20, 0, 7), Size = UDim2.new(1, -28, 0, 16), Parent = inner,
    })
    local msg = label({
        Text = opts.Text or "", TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
        Position = UDim2.new(0, 20, 0, 24), Size = UDim2.new(1, -28, 0, 16), Parent = inner,
    })
    bind(msg, "TextColor3", Shade.Muted)

    tween(inner, { Position = UDim2.new(0, 0, 0, 0) }, 0.35)
    task.delay(opts.Duration or 3.2, function()
        if not wrap.Parent then return end
        tween(inner, { Position = UDim2.new(1, 30, 0, 0) }, 0.3)
        task.wait(dur(0.3))
        if not wrap.Parent then return end
        tween(wrap, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
        task.wait(dur(0.2))
        if wrap.Parent then wrap:Destroy() end
    end)
end

----------------------------------------------------------------------
-- Config serialization / file system
----------------------------------------------------------------------
local FS = {}
function FS.available()
    return type(writefile) == "function" and type(readfile) == "function"
        and type(isfolder) == "function" and type(makefolder) == "function"
        and type(listfiles) == "function" and type(isfile) == "function"
end

local function ensureFolders()
    if not isfolder(LibraryUI.Folder) then makefolder(LibraryUI.Folder) end
    if not isfolder(LibraryUI.ConfigFolder) then makefolder(LibraryUI.ConfigFolder) end
end

local function encode(v)
    local t = typeof(v)
    if t == "Color3" then
        return { __type = "Color3", r = v.R, g = v.G, b = v.B }
    elseif t == "EnumItem" then
        return { __type = "KeyCode", name = v.Name }
    end
    return v
end

local function decode(v)
    if type(v) == "table" then
        if v.__type == "Color3" then
            return Color3.new(v.r, v.g, v.b)
        elseif v.__type == "KeyCode" then
            return Enum.KeyCode[v.name]
        end
    end
    return v
end

local function serialize(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local pad = string.rep("\t", depth + 1)
        local out = {}
        for _, k in ipairs(keys) do
            local key = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
            out[#out + 1] = pad .. key .. " = " .. serialize(v[k], depth + 1) .. ","
        end
        if #out == 0 then return "{}" end
        return "{\n" .. table.concat(out, "\n") .. "\n" .. string.rep("\t", depth) .. "}"
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    end
    return "nil"
end

local function snapshot()
    local data = { version = 1, flags = {} }
    for flag, value in pairs(LibraryUI.Flags) do
        data.flags[flag] = encode(value)
    end
    return data
end

local function extOf(filename)
    local e = filename:match("%.(%w+)$")
    return e and e:lower() or nil
end

local function validFile(filename)
    if type(filename) ~= "string" then return false end
    if not filename:match("^[%w_%- ]+%.%a+$") then return false end
    local e = extOf(filename)
    return e == "lua" or e == "json"
end

function LibraryUI:ConfigPath(filename)
    return self.ConfigFolder .. "/" .. filename
end

function LibraryUI:ConfigExists(filename)
    return FS.available() and isfile(self:ConfigPath(filename))
end

function LibraryUI:ListConfigs()
    local names = {}
    if not FS.available() then return names end
    ensureFolders()
    local ok, files = pcall(listfiles, self.ConfigFolder)
    if not ok then return names end
    for _, p in ipairs(files) do
        local name = p:match("([^/\\]+)$")
        if name and validFile(name) then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function LibraryUI:SaveConfig(filename)
    if not FS.available() then return false, "File functions not supported by this executor" end
    if not validFile(filename) then return false, "Only .lua and .json configs are allowed" end
    local ok, err = pcall(function()
        ensureFolders()
        local data = snapshot()
        local out
        if extOf(filename) == "json" then
            out = HttpService:JSONEncode(data)
        else
            out = "-- LibraryUI config\nreturn " .. serialize(data) .. "\n"
        end
        writefile(self:ConfigPath(filename), out)
    end)
    if not ok then return false, tostring(err) end
    return true
end

function LibraryUI:LoadConfig(filename)
    if not FS.available() then return false, "File functions not supported by this executor" end
    if not validFile(filename) then return false, "Only .lua and .json configs are allowed" end
    if not isfile(self:ConfigPath(filename)) then return false, "Config not found" end

    local okRead, src = pcall(readfile, self:ConfigPath(filename))
    if not okRead then return false, tostring(src) end

    local data
    if extOf(filename) == "json" then
        local ok, res = pcall(HttpService.JSONDecode, HttpService, src)
        if not ok then return false, "Invalid JSON" end
        data = res
    else
        if type(loadstring) ~= "function" then return false, "loadstring is not available" end
        local fn, err = loadstring(src, "=config")
        if not fn then return false, tostring(err) end
        if type(setfenv) == "function" then pcall(setfenv, fn, {}) end
        local ok, res = pcall(fn)
        if not ok then return false, tostring(res) end
        data = res
    end

    if type(data) ~= "table" or type(data.flags) ~= "table" then
        return false, "Invalid config structure"
    end
    for flag, raw in pairs(data.flags) do
        local setter = self.Setters[flag]
        if setter then pcall(setter, decode(raw)) end
    end
    return true
end

function LibraryUI:DeleteConfig(filename)
    if not FS.available() or type(delfile) ~= "function" then
        return false, "delfile is not supported by this executor"
    end
    if not validFile(filename) then return false, "Invalid config name" end
    local ok, err = pcall(delfile, self:ConfigPath(filename))
    if not ok then return false, tostring(err) end
    return true
end

function LibraryUI:CreateConfig(raw, defaultExt)
    raw = (raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then return nil, "Enter a config name" end

    local base, ext = raw:match("^(.+)%.(%w+)$")
    if base then
        ext = ext:lower()
        if ext ~= "lua" and ext ~= "json" then
            return nil, "Only .lua and .json files are allowed"
        end
    else
        base, ext = raw, defaultExt or "lua"
    end
    if #base > 32 or not base:match("^[%w_%- ]+$") then
        return nil, "Use letters, numbers, spaces, - and _ (max 32)"
    end

    local filename = base .. "." .. ext
    if self:ConfigExists(filename) then return nil, "That config already exists" end
    local ok, err = self:SaveConfig(filename)
    if not ok then return nil, err end
    return filename
end

----------------------------------------------------------------------
-- Tab (element builders)
----------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

function Tab:_next()
    self._n = self._n + 1
    return self._n
end

local function makeRow(tab, height)
    local r = new("Frame", {
        Size = UDim2.new(1, 0, 0, height or 34),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = tab:_next(),
        Parent = tab.Scroll,
    })
    bind(r, "BackgroundColor3", Shade.Row)
    corner(r, 5)
    stroke(r, Shade.Line, 0.88)
    return r
end

local function register(flag, value, setter)
    if not flag then return end
    LibraryUI.Flags[flag] = value
    LibraryUI.Setters[flag] = setter
end

function Tab:Section(text)
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        LayoutOrder = self:_next(),
        Parent = self.Scroll,
    })
    local l = label({
        Text = string.upper(text), Font = FONT_BOLD, TextSize = 11,
        Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -4, 1, -3),
        TextYAlignment = Enum.TextYAlignment.Bottom, Parent = f,
    })
    bind(l, "TextColor3", Shade.Muted)
    local line = new("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0,
        BackgroundTransparency = 0.8, Parent = f,
    })
    bind(line, "BackgroundColor3", Shade.Line)
end

function Tab:Label(text)
    local l = label({
        Text = text, TextSize = 12, TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = self:_next(), Parent = self.Scroll,
    })
    bind(l, "TextColor3", Shade.Muted)
    return { Set = function(_, t) l.Text = t end }
end

function Tab:Info(name, value)
    local r = makeRow(self, 30)
    local n = label({ Text = name, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, -12, 1, 0), Parent = r })
    bind(n, "TextColor3", Shade.Muted)
    local v = label({
        Text = tostring(value), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -12, 1, 0), Parent = r,
    })
    return { Set = function(_, t) v.Text = tostring(t) end }
end

function Tab:Button(text, callback)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), Text = text, Font = FONT_BOLD, TextSize = 13,
        TextColor3 = WHITE, AutoButtonColor = false, BorderSizePixel = 0,
        LayoutOrder = self:_next(), Parent = self.Scroll,
    })
    bind(b, "BackgroundColor3", Shade.Accent)
    corner(b, 5)
    hoverable(b, Shade.Accent, Shade.Hover, Shade.Press)
    b.MouseButton1Click:Connect(function() safe(callback) end)
    return { Set = function(_, t) b.Text = t end, Instance = b }
end

function Tab:ButtonRow(buttons)
    local n = #buttons
    local gap = 6
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1,
        LayoutOrder = self:_next(), Parent = self.Scroll,
    })
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap),
        SortOrder = Enum.SortOrder.LayoutOrder, Parent = f,
    })
    for i, def in ipairs(buttons) do
        local b = new("TextButton", {
            Size = UDim2.new(1 / n, -math.ceil(gap * (n - 1) / n), 1, 0),
            Text = def[1], Font = FONT_BOLD, TextSize = 13, TextColor3 = WHITE,
            AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i, Parent = f,
        })
        bind(b, "BackgroundColor3", Shade.Accent)
        corner(b, 5)
        hoverable(b, Shade.Accent, Shade.Hover, Shade.Press)
        b.MouseButton1Click:Connect(function() safe(def[2]) end)
    end
end

function Tab:Toggle(opts)
    local state = opts.Default and true or false
    local r = makeRow(self, 34)
    local click = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = r })
    label({ Text = opts.Name, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -64, 1, 0), Parent = r })

    local pill = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(36, 18), BorderSizePixel = 0, Parent = r,
    })
    corner(pill, 9)
    local pillColor = function(a) return state and Shade.Light(a) or Shade.Off(a) end
    bind(pill, "BackgroundColor3", pillColor)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(12, 12),
        Position = state and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = pill,
    })
    corner(knob, 6)

    local function set(v, silent)
        state = v and true or false
        tween(pill, { BackgroundColor3 = pillColor(LibraryUI.Accent) }, 0.2)
        tween(knob, { Position = state and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.22, Enum.EasingStyle.Back)
        if opts.Flag then LibraryUI.Flags[opts.Flag] = state end
        if not silent then safe(opts.Callback, state) end
    end

    click.MouseEnter:Connect(function() tween(r, { BackgroundColor3 = Shade.RowHover(LibraryUI.Accent) }, 0.15) end)
    click.MouseLeave:Connect(function() tween(r, { BackgroundColor3 = Shade.Row(LibraryUI.Accent) }, 0.2) end)
    click.MouseButton1Click:Connect(function() set(not state) end)

    register(opts.Flag, state, function(v) set(v) end)
    return { Set = function(_, v) set(v) end, Get = function() return state end }
end

function Tab:Slider(opts)
    local min, max, inc = opts.Min or 0, opts.Max or 100, opts.Increment or 1
    local suffix = opts.Suffix or ""
    local value = opts.Default or min
    local r = makeRow(self, 48)

    label({ Text = opts.Name, Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -90, 0, 16), Parent = r })
    local valLabel = label({
        Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7),
        Size = UDim2.fromOffset(70, 16), Parent = r,
    })

    local track = new("Frame", {
        Position = UDim2.new(0, 12, 0, 31), Size = UDim2.new(1, -24, 0, 6),
        BorderSizePixel = 0, Parent = r,
    })
    bind(track, "BackgroundColor3", Shade.Off)
    corner(track, 3)
    local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = track })
    bind(fill, "BackgroundColor3", Shade.Hover)
    corner(fill, 3)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(12, 12), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = track,
    })
    corner(knob, 6)
    local hit = new("TextButton", {
        Position = UDim2.new(0, 12, 0, 22), Size = UDim2.new(1, -24, 0, 24),
        BackgroundTransparency = 1, Text = "", Parent = r,
    })

    local function set(v, silent)
        v = math.clamp(v, min, max)
        v = math.floor((v - min) / inc + 0.5) * inc + min
        v = tonumber(string.format("%.4f", v))
        value = v
        local a = (max == min) and 0 or (v - min) / (max - min)
        tween(fill, { Size = UDim2.fromScale(a, 1) }, 0.08, Enum.EasingStyle.Sine)
        tween(knob, { Position = UDim2.fromScale(a, 0.5) }, 0.08, Enum.EasingStyle.Sine)
        valLabel.Text = tostring(v) .. suffix
        if opts.Flag then LibraryUI.Flags[opts.Flag] = v end
        if not silent then safe(opts.Callback, v) end
    end

    dragArea(hit, function(pos)
        local a = math.clamp((pos.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        set(min + (max - min) * a)
    end)

    set(value, true)
    register(opts.Flag, value, function(v) set(v) end)
    return { Set = function(_, v) set(v) end, Get = function() return value end }
end

function Tab:Dropdown(opts)
    local options = opts.Options or {}
    local selected = opts.Default or options[1]
    local open = false
    local HEAD = 34

    local r = makeRow(self, HEAD)
    local head = new("TextButton", { Size = UDim2.new(1, 0, 0, HEAD), BackgroundTransparency = 1, Text = "", Parent = r })
    label({ Text = opts.Name, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, -12, 0, HEAD), Parent = r })
    local valLabel = label({
        Text = tostring(selected), Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -36, 0, HEAD), Parent = r,
    })

    local chev = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, HEAD / 2),
        Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Parent = r,
    })
    for i, rot in ipairs({ 45, -45 }) do
        local arm = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(i == 1 and 4.5 or 9.5, 6.5),
            Size = UDim2.fromOffset(7, 2), Rotation = rot, BorderSizePixel = 0, Parent = chev,
        })
        bind(arm, "BackgroundColor3", Shade.Muted)
    end

    local list = new("ScrollingFrame", {
        Position = UDim2.new(0, 8, 0, HEAD + 4), Size = UDim2.new(1, -16, 0, 0),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = r,
    })
    bind(list, "ScrollBarImageColor3", Shade.Hover)
    new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

    local function listHeight() return math.min(#options, 5) * 26 - 2 end
    local function openHeight() return HEAD + 4 + listHeight() + 8 end

    local set
    local function build()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        list.Size = UDim2.new(1, -16, 0, listHeight())
        for i, opt in ipairs(options) do
            local b = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 24), Text = "", AutoButtonColor = false,
                BorderSizePixel = 0, LayoutOrder = i, Parent = list,
                BackgroundTransparency = (opt == selected) and 0 or 1,
            })
            bind(b, "BackgroundColor3", Shade.Accent)
            corner(b, 4)
            label({ Text = tostring(opt), TextSize = 12, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), Parent = b })
            b.MouseEnter:Connect(function()
                if opt ~= selected then tween(b, { BackgroundTransparency = 0.7 }, 0.12) end
            end)
            b.MouseLeave:Connect(function()
                if opt ~= selected then tween(b, { BackgroundTransparency = 1 }, 0.15) end
            end)
            b.MouseButton1Click:Connect(function()
                set(opt)
                open = false
                tween(r, { Size = UDim2.new(1, 0, 0, HEAD) }, 0.25)
                tween(chev, { Rotation = 0 }, 0.25)
            end)
        end
    end

    set = function(v, silent)
        if v == nil or not table.find(options, v) then return end
        selected = v
        valLabel.Text = tostring(v)
        if opts.Flag then LibraryUI.Flags[opts.Flag] = v end
        build()
        if not silent then safe(opts.Callback, v) end
    end

    head.MouseEnter:Connect(function() tween(r, { BackgroundColor3 = Shade.RowHover(LibraryUI.Accent) }, 0.15) end)
    head.MouseLeave:Connect(function() tween(r, { BackgroundColor3 = Shade.Row(LibraryUI.Accent) }, 0.2) end)
    head.MouseButton1Click:Connect(function()
        open = not open
        tween(r, { Size = UDim2.new(1, 0, 0, open and openHeight() or HEAD) }, 0.28)
        tween(chev, { Rotation = open and 180 or 0 }, 0.28)
    end)

    build()
    if opts.Flag then LibraryUI.Flags[opts.Flag] = selected end
    register(opts.Flag, selected, function(v) set(v) end)
    return {
        Set = function(_, v) set(v) end,
        Get = function() return selected end,
        Refresh = function(_, newOptions)
            options = newOptions
            if not table.find(options, selected) then selected = options[1] end
            valLabel.Text = tostring(selected)
            build()
        end,
    }
end

function Tab:Input(opts)
    local r = makeRow(self, 34)
    label({ Text = opts.Name, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.4, -12, 1, 0), Parent = r })
    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0.6, -8, 0, 24), Text = opts.Default or "",
        PlaceholderText = opts.Placeholder or "", ClearTextOnFocus = false,
        Font = FONT, TextSize = 12, TextColor3 = WHITE, BorderSizePixel = 0,
        TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true, Parent = r,
    })
    bind(box, "BackgroundColor3", Shade.Base)
    bind(box, "PlaceholderColor3", Shade.Muted)
    corner(box, 4)
    padding(box, 8, 0, 8, 0)
    local s = stroke(box, Shade.Line, 0.8)

    box.Focused:Connect(function() tween(s, { Color = Shade.Hover(LibraryUI.Accent), Transparency = 0.2 }, 0.15) end)
    box.FocusLost:Connect(function(enter)
        tween(s, { Color = Shade.Line(LibraryUI.Accent), Transparency = 0.8 }, 0.2)
        if opts.Flag then LibraryUI.Flags[opts.Flag] = box.Text end
        safe(opts.Callback, box.Text, enter)
    end)

    register(opts.Flag, box.Text, function(v) box.Text = tostring(v) end)
    return {
        Get = function() return box.Text end,
        Set = function(_, v) box.Text = tostring(v) end,
        Clear = function() box.Text = "" end,
    }
end

function Tab:Keybind(opts)
    local key = opts.Default or Enum.KeyCode.RightShift
    local listening = false
    local r = makeRow(self, 34)
    label({ Text = opts.Name, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -110, 1, 0), Parent = r })
    local btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(92, 24), Text = key.Name, Font = FONT_BOLD, TextSize = 12,
        TextColor3 = WHITE, AutoButtonColor = false, BorderSizePixel = 0, Parent = r,
    })
    bind(btn, "BackgroundColor3", Shade.Accent)
    corner(btn, 4)
    hoverable(btn, Shade.Accent, Shade.Hover, Shade.Press)

    local function set(k, silent)
        if typeof(k) ~= "EnumItem" then return end
        key = k
        btn.Text = k.Name
        if opts.Flag then LibraryUI.Flags[opts.Flag] = k end
        if not silent then safe(opts.Callback, k) end
    end

    btn.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true
        LibraryUI._binding = true
        btn.Text = "..."
        local conn
        conn = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                conn:Disconnect()
                listening = false
                task.defer(function() LibraryUI._binding = false end)
                if input.KeyCode ~= Enum.KeyCode.Escape then
                    set(input.KeyCode)
                else
                    btn.Text = key.Name
                end
            end
        end)
    end)

    register(opts.Flag, key, function(v) set(v) end)
    return { Set = function(_, v) set(v) end, Get = function() return key end }
end

function Tab:ColorPicker(opts)
    local h, s, v = (opts.Default or DEFAULT_ACCENT):ToHSV()
    local r = makeRow(self, 152)

    label({ Text = opts.Name, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(0.5, -12, 0, 18), Parent = r })
    local hex = label({
        Font = FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8),
        Size = UDim2.fromOffset(90, 18), Parent = r,
    })

    local box = new("Frame", {
        Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -52, 0, 108),
        BorderSizePixel = 0, BackgroundColor3 = Color3.fromHSV(h, 1, 1), Parent = r,
    })
    corner(box, 4)
    local white = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = box })
    corner(white, 4)
    new("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
    local dark = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0, Parent = box })
    corner(dark, 4)
    new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = dark })

    local svKnob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1, ZIndex = 3, Parent = box,
    })
    corner(svKnob, 5)
    new("UIStroke", { Thickness = 2, Color = WHITE, Parent = svKnob })
    local svHit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 4, Parent = box })

    local hue = new("Frame", {
        Position = UDim2.new(1, -34, 0, 34), Size = UDim2.fromOffset(22, 108),
        BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = r,
    })
    corner(hue, 4)
    new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0.00, 1, 1)),
            ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
            ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
            ColorSequenceKeypoint.new(0.50, Color3.fromHSV(0.50, 1, 1)),
            ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
            ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
            ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1.00, 1, 1)),
        }),
        Parent = hue,
    })
    local hueKnob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 6, 0, 5),
        BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = hue,
    })
    corner(hueKnob, 2)
    new("UIStroke", { Thickness = 1, Color = BLACK, Transparency = 0.5, Parent = hueKnob })
    local hueHit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 4, Parent = hue })

    local function apply(silent)
        local c = Color3.fromHSV(h, s, v)
        box.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        svKnob.Position = UDim2.fromScale(s, 1 - v)
        hueKnob.Position = UDim2.fromScale(0.5, h)
        hex.Text = toHex(c)
        if opts.Flag then LibraryUI.Flags[opts.Flag] = c end
        if not silent then safe(opts.Callback, c) end
    end

    dragArea(svHit, function(pos)
        s = math.clamp((pos.X - box.AbsolutePosition.X) / math.max(box.AbsoluteSize.X, 1), 0, 1)
        v = 1 - math.clamp((pos.Y - box.AbsolutePosition.Y) / math.max(box.AbsoluteSize.Y, 1), 0, 1)
        apply()
    end)
    dragArea(hueHit, function(pos)
        h = math.clamp((pos.Y - hue.AbsolutePosition.Y) / math.max(hue.AbsoluteSize.Y, 1), 0, 1)
        apply()
    end)

    apply(true)
    local function setColor(c, silent)
        if typeof(c) ~= "Color3" then return end
        h, s, v = c:ToHSV()
        apply(silent)
    end
    register(opts.Flag, Color3.fromHSV(h, s, v), function(c) setColor(c) end)
    return {
        Set = function(_, c) setColor(c) end,
        Get = function() return Color3.fromHSV(h, s, v) end,
    }
end

function Tab:Swatches(opts)
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1,
        LayoutOrder = self:_next(), Parent = self.Scroll,
    })
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = f,
    })
    for i, def in ipairs(opts.Colors) do
        local b = new("TextButton", {
            Size = UDim2.fromOffset(24, 24), Text = "", AutoButtonColor = false,
            BackgroundColor3 = def[2], BorderSizePixel = 0, LayoutOrder = i, Parent = f,
        })
        corner(b, 12)
        local ring = new("UIStroke", { Thickness = 2, Color = WHITE, Transparency = 1, Parent = b })
        b.MouseEnter:Connect(function()
            tween(ring, { Transparency = 0 }, 0.12)
            tween(b, { Size = UDim2.fromOffset(27, 27) }, 0.15, Enum.EasingStyle.Back)
        end)
        b.MouseLeave:Connect(function()
            tween(ring, { Transparency = 1 }, 0.15)
            tween(b, { Size = UDim2.fromOffset(24, 24) }, 0.15)
        end)
        b.MouseButton1Click:Connect(function() safe(opts.Callback, def[2], def[1]) end)
    end
end

function Tab:ListBox(opts)
    local H = opts.Height or 140
    local selected
    local r = makeRow(self, H)
    local scroll = new("ScrollingFrame", {
        Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = r,
    })
    bind(scroll, "ScrollBarImageColor3", Shade.Hover)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

    local empty = label({
        Text = "No configs found", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1), Visible = false, Parent = r,
    })
    bind(empty, "TextColor3", Shade.Muted)

    local buttons = {}
    local function paint(name, b)
        tween(b, { BackgroundTransparency = (name == selected) and 0 or 1 }, 0.15)
    end

    local function select(name, silent)
        selected = name
        for n, b in pairs(buttons) do paint(n, b) end
        if not silent then safe(opts.Callback, name) end
    end

    local function setItems(items)
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        buttons = {}
        empty.Visible = #items == 0
        if selected and not table.find(items, selected) then selected = nil end
        for i, name in ipairs(items) do
            local b = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 26), Text = "", AutoButtonColor = false,
                BorderSizePixel = 0, LayoutOrder = i, Parent = scroll,
                BackgroundTransparency = (name == selected) and 0 or 1,
            })
            bind(b, "BackgroundColor3", Shade.Accent)
            corner(b, 4)
            label({ Text = name, TextSize = 12, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Parent = b })
            b.MouseEnter:Connect(function()
                if name ~= selected then tween(b, { BackgroundTransparency = 0.75 }, 0.12) end
            end)
            b.MouseLeave:Connect(function()
                if name ~= selected then tween(b, { BackgroundTransparency = 1 }, 0.15) end
            end)
            b.MouseButton1Click:Connect(function() select(name) end)
            buttons[name] = b
        end
    end

    return {
        SetItems = function(_, items) setItems(items) end,
        Get = function() return selected end,
        Select = function(_, name) select(name, true) end,
    }
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local Window = {}
Window.__index = Window

function Window:SetSize(name)
    local sz = SIZES[name]
    if not sz then return end
    self.SizeName = name
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    self.Width = math.floor(math.min(sz.X, vp.X - 40))
    self.Height = math.floor(math.min(sz.Y, vp.Y - 40))
    tween(self.Holder, {
        Size = UDim2.fromOffset(self.Width, self.Minimized and TITLE_H or self.Height),
    }, 0.4)
end

function Window:SetMinimized(v)
    self.Minimized = v
    tween(self.Holder, {
        Size = UDim2.fromOffset(self.Width, v and TITLE_H or self.Height),
    }, 0.32)
end

function Window:SetShadow(v)
    self.ShadowOn = v
    if self.Visible then
        tween(self.Shadow, { ImageTransparency = v and 0.45 or 1 }, 0.25)
    end
end

function Window:SetVisible(v)
    if self.Visible == v then return end
    self.Visible = v
    if v then
        self.Holder.Visible = true
        self.Scale.Scale = 0.94
        tween(self.Scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
        tween(self.Main, { GroupTransparency = 0 }, 0.25)
        tween(self.Shadow, { ImageTransparency = self.ShadowOn and 0.45 or 1 }, 0.3)
    else
        tween(self.Scale, { Scale = 0.94 }, 0.2)
        tween(self.Main, { GroupTransparency = 1 }, 0.2)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
        task.delay(dur(0.2), function()
            if not self.Visible then self.Holder.Visible = false end
        end)
    end
end

function Window:Close()
    self:SetVisible(false)
    task.delay(dur(0.25), function() LibraryUI:Destroy() end)
end

function Window:Select(tab)
    if self.Active == tab then return end
    local prev = self.Active
    self.Active = tab
    local acc = LibraryUI.Accent

    if prev then
        tween(prev.Button, { BackgroundColor3 = acc }, 0.2)
        tween(prev.Indicator, { BackgroundTransparency = 1 }, 0.2)
        tween(prev.Page, { GroupTransparency = 1 }, 0.15)
        task.delay(dur(0.15), function()
            if self.Active ~= prev then prev.Page.Visible = false end
        end)
    end

    tab.Page.Visible = true
    tab.Page.Position = UDim2.fromOffset(0, 12)
    tab.Page.GroupTransparency = 1
    tween(tab.Page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.3)
    tween(tab.Button, { BackgroundColor3 = Shade.Light(acc) }, 0.2)
    tween(tab.Indicator, { BackgroundTransparency = 0 }, 0.2)
end

function Window:AddTab(name, order)
    local tab = setmetatable({ Window = self, Name = name, _n = 0 }, Tab)
    if not order then
        self._userOrder = self._userOrder + 1
        order = self._userOrder
    end
    tab.Order = order

    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), Text = name, Font = FONT_BOLD, TextSize = 13,
        TextColor3 = WHITE, AutoButtonColor = false, BorderSizePixel = 0,
        LayoutOrder = order, Parent = self.Sidebar,
    })
    bind(btn, "BackgroundColor3", function(a)
        return (self.Active == tab) and Shade.Light(a) or a
    end)
    corner(btn, 5)
    local ind = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0),
        Size = UDim2.fromOffset(3, 14), BackgroundColor3 = WHITE,
        BackgroundTransparency = 1, BorderSizePixel = 0, Parent = btn,
    })
    corner(ind, 2)
    tab.Button, tab.Indicator = btn, ind

    btn.MouseEnter:Connect(function()
        if self.Active ~= tab then tween(btn, { BackgroundColor3 = LibraryUI.Accent:Lerp(WHITE, 0.08) }, 0.15) end
    end)
    btn.MouseLeave:Connect(function()
        if self.Active ~= tab then tween(btn, { BackgroundColor3 = LibraryUI.Accent }, 0.2) end
    end)
    btn.MouseButton1Down:Connect(function()
        tween(btn, { BackgroundColor3 = Shade.Press(LibraryUI.Accent) }, 0.08)
    end)
    btn.MouseButton1Click:Connect(function() self:Select(tab) end)

    local page = new("CanvasGroup", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        GroupTransparency = 1, Visible = false, Parent = self.Content,
    })
    local scroll = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, Parent = page,
    })
    bind(scroll, "ScrollBarImageColor3", Shade.Hover)
    padding(scroll, 10, 8, 12, 10)
    new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
    tab.Page, tab.Scroll = page, scroll

    self.Tabs[#self.Tabs + 1] = tab
    return tab
end

----------------------------------------------------------------------
-- Built-in tabs
----------------------------------------------------------------------
local PRESETS = {
    { "Blue", Color3.fromRGB(0, 72, 140) },
    { "Violet", Color3.fromRGB(96, 52, 170) },
    { "Crimson", Color3.fromRGB(160, 32, 60) },
    { "Emerald", Color3.fromRGB(0, 128, 96) },
    { "Amber", Color3.fromRGB(176, 112, 0) },
    { "Rose", Color3.fromRGB(176, 48, 120) },
    { "Cyan", Color3.fromRGB(0, 128, 150) },
    { "Slate", Color3.fromRGB(60, 72, 92) },
}

local function buildSettings(win)
    local t = win:AddTab("Settings", 1001)

    t:Section("Interface")
    t:Dropdown({
        Name = "UI Size", Options = SIZE_ORDER, Default = win.SizeName, Flag = "ui.size",
        Callback = function(v) win:SetSize(v) end,
    })
    t:Keybind({
        Name = "Toggle Key", Default = LibraryUI.ToggleKey, Flag = "ui.togglekey",
        Callback = function(k) LibraryUI.ToggleKey = k end,
    })

    t:Section("Appearance")
    local picker = t:ColorPicker({
        Name = "Interface Color", Default = LibraryUI.Accent, Flag = "ui.accent",
        Callback = function(c) LibraryUI:SetAccent(c) end,
    })
    t:Swatches({
        Colors = PRESETS,
        Callback = function(c) picker:Set(c) end,
    })

    t:Section("Effects")
    t:Toggle({
        Name = "Animations", Default = true, Flag = "ui.animations",
        Callback = function(v) LibraryUI.Animations = v end,
    })
    t:Slider({
        Name = "Animation Speed", Min = 0.5, Max = 2, Default = 1, Increment = 0.1,
        Suffix = "x", Flag = "ui.animspeed",
        Callback = function(v) LibraryUI.AnimSpeed = v end,
    })
    t:Toggle({
        Name = "Animated Background", Default = true, Flag = "ui.bgfx",
        Callback = function(v)
            win.BgFx = v
            if not v then win.Gradient.Rotation = 90 end
        end,
    })
    t:Toggle({
        Name = "Window Shadow", Default = true, Flag = "ui.shadow",
        Callback = function(v) win:SetShadow(v) end,
    })

    t:Section("Window")
    t:ButtonRow({
        { "Reset Interface", function()
            local defaults = {
                ["ui.size"] = "Default", ["ui.accent"] = DEFAULT_ACCENT,
                ["ui.animations"] = true, ["ui.animspeed"] = 1,
                ["ui.bgfx"] = true, ["ui.shadow"] = true,
                ["ui.togglekey"] = Enum.KeyCode.RightShift,
            }
            for flag, value in pairs(defaults) do
                if LibraryUI.Setters[flag] then LibraryUI.Setters[flag](value) end
            end
            LibraryUI:Notify({ Title = "Settings", Text = "Interface reset to defaults", Type = "Success" })
        end },
        { "Unload UI", function() win:Close() end },
    })
    return t
end

local function buildConfig(win)
    local t = win:AddTab("Config", 1002)
    local selected
    local format = "lua"
    local pendingDelete

    local list
    local function refresh()
        list:SetItems(LibraryUI:ListConfigs())
    end

    if not FS.available() then
        t:Label("This executor does not expose the file functions needed to store configs (writefile, readfile, listfiles, isfile, makefolder).")
    end

    t:Section("Create")
    local nameBox = t:Input({ Name = "Config Name", Placeholder = "name  or  name.json" })
    t:Dropdown({
        Name = "Format", Options = { "lua", "json" }, Default = "lua",
        Callback = function(v) format = v end,
    })
    t:Button("Create Config", function()
        local filename, err = LibraryUI:CreateConfig(nameBox:Get(), format)
        if not filename then
            LibraryUI:Notify({ Title = "Config", Text = err, Type = "Error" })
            return
        end
        nameBox:Clear()
        refresh()
        list:Select(filename)
        selected = filename
        LibraryUI:Notify({ Title = "Config", Text = "Created " .. filename, Type = "Success" })
    end)

    t:Section("Saved Configs")
    list = t:ListBox({
        Height = 150,
        Callback = function(name)
            selected = name
            pendingDelete = nil
        end,
    })

    t:ButtonRow({
        { "Save", function()
            if not selected then
                LibraryUI:Notify({ Title = "Config", Text = "Select a config first", Type = "Warn" })
                return
            end
            local ok, err = LibraryUI:SaveConfig(selected)
            LibraryUI:Notify({
                Title = "Config", Type = ok and "Success" or "Error",
                Text = ok and ("Saved " .. selected) or err,
            })
        end },
        { "Load", function()
            if not selected then
                LibraryUI:Notify({ Title = "Config", Text = "Select a config first", Type = "Warn" })
                return
            end
            local ok, err = LibraryUI:LoadConfig(selected)
            LibraryUI:Notify({
                Title = "Config", Type = ok and "Success" or "Error",
                Text = ok and ("Loaded " .. selected) or err,
            })
        end },
        { "Delete", function()
            if not selected then
                LibraryUI:Notify({ Title = "Config", Text = "Select a config first", Type = "Warn" })
                return
            end
            if pendingDelete ~= selected then
                pendingDelete = selected
                LibraryUI:Notify({ Title = "Config", Text = "Press Delete again to remove " .. selected, Type = "Warn" })
                task.delay(3, function()
                    if pendingDelete == selected then pendingDelete = nil end
                end)
                return
            end
            pendingDelete = nil
            local ok, err = LibraryUI:DeleteConfig(selected)
            if ok then
                LibraryUI:Notify({ Title = "Config", Text = "Deleted " .. selected, Type = "Success" })
                selected = nil
                refresh()
            else
                LibraryUI:Notify({ Title = "Config", Text = err, Type = "Error" })
            end
        end },
    })
    t:Button("Refresh List", refresh)

    task.defer(refresh)
    return t
end

local function buildAbout(win)
    local t = win:AddTab("About", 1003)

    t:Section("LibraryUI")
    t:Label("Interface library with tabs, config profiles and a fully themeable window.")

    t:Section("Session")
    local executor = "Unknown"
    if type(identifyexecutor) == "function" then
        local ok, name = pcall(identifyexecutor)
        if ok and name then executor = tostring(name) end
    end
    t:Info("Version", LibraryUI.Version)
    t:Info("Executor", executor)
    local keyInfo = t:Info("Toggle Key", LibraryUI.ToggleKey.Name)
    t:Info("Config Folder", LibraryUI.ConfigFolder)
    local upInfo = t:Info("Uptime", "0:00")
    local fpsInfo = t:Info("FPS", "--")

    local acc = 0
    connect(RunService.RenderStepped, function(dt)
        acc = acc + dt
        if acc < 0.5 then return end
        acc = 0
        if win.Active and win.Active.Name == "About" and win.Visible then
            local s = math.floor(os.clock() - startClock)
            upInfo:Set(string.format("%d:%02d", math.floor(s / 60), s % 60))
            fpsInfo:Set(tostring(win.FPS))
            keyInfo:Set(LibraryUI.ToggleKey.Name)
        end
    end)
    return t
end

----------------------------------------------------------------------
-- CreateWindow
----------------------------------------------------------------------
function LibraryUI:_CreateWindow(opts)
    opts = opts or {}
    local gui = ensureGui()
    print("[LibraryUI] 1/6 ScreenGui ok -> " .. tostring(self.MountedIn))

    if opts.Accent then self:SetAccent(opts.Accent) end
    if opts.ToggleKey then self.ToggleKey = opts.ToggleKey end

    local self_ = setmetatable({
        Tabs = {}, Active = nil, Visible = false, Minimized = false,
        BgFx = true, ShadowOn = true, FPS = 0, _userOrder = 0,
    }, Window)
    local win = self_

    local sizeName = SIZES[opts.Size] and opts.Size or "Default"
    win.SizeName = sizeName

    -- frame structure
    local holder = new("Frame", {
        Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(SIZES[sizeName].X, SIZES[sizeName].Y),
        BackgroundTransparency = 1, Visible = false, Parent = gui,
    })
    local scale = new("UIScale", { Scale = 1, Parent = holder })
    local shadow = new("ImageLabel", {
        BackgroundTransparency = 1, Image = "rbxassetid://6014261993",
        ImageColor3 = BLACK, ImageTransparency = 1, ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 44, 1, 44), ZIndex = 0, Parent = holder,
    })
    local main = new("CanvasGroup", {
        Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, GroupTransparency = 1, Parent = holder,
    })
    corner(main, 7)
    stroke(main, Shade.Line, 0.75)
    -- gradient lives on its own frame: a UIGradient directly on a CanvasGroup
    -- would tint every child (text, buttons...) and make the UI look dark/broken
    local bg = new("Frame", {
        Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE,
        BorderSizePixel = 0, ZIndex = 0, Parent = main,
    })
    local grad = new("UIGradient", { Rotation = 90, Color = windowGradient(self.Accent), Parent = bg })
    gradients[#gradients + 1] = { inst = grad, fn = windowGradient }

    win.Holder, win.Scale, win.Shadow, win.Main, win.Gradient = holder, scale, shadow, main, grad

    print("[LibraryUI] 2/6 frames ok")
    -- title bar
    local titlebar = new("Frame", {
        Size = UDim2.new(1, 0, 0, TITLE_H), BorderSizePixel = 0,
        BackgroundTransparency = 0.35, Parent = main,
    })
    bind(titlebar, "BackgroundColor3", Shade.Top)
    label({
        Text = opts.Title or "LibraryUI", Font = FONT_BOLD, TextSize = 15,
        Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -90, 1, 0), Parent = titlebar,
    })

    local function iconButton(xOffset)
        return new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, xOffset, 0.5, 0),
            Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1, Text = "",
            AutoButtonColor = false, Parent = titlebar,
        })
    end

    local closeBtn = iconButton(-8)
    local closeArms = {}
    for _, rot in ipairs({ 45, -45 }) do
        closeArms[#closeArms + 1] = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(15, 2), Rotation = rot, BackgroundColor3 = WHITE,
            BorderSizePixel = 0, Parent = closeBtn,
        })
    end
    closeBtn.MouseEnter:Connect(function()
        for _, a in ipairs(closeArms) do tween(a, { BackgroundColor3 = Color3.fromRGB(255, 95, 95) }, 0.15) end
    end)
    closeBtn.MouseLeave:Connect(function()
        for _, a in ipairs(closeArms) do tween(a, { BackgroundColor3 = WHITE }, 0.2) end
    end)
    closeBtn.MouseButton1Click:Connect(function() win:Close() end)

    local minBtn = iconButton(-38)
    local minLine = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 2), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = minBtn,
    })
    minBtn.MouseEnter:Connect(function()
        tween(minLine, { BackgroundColor3 = Shade.Muted(LibraryUI.Accent), Size = UDim2.fromOffset(16, 2) }, 0.15)
    end)
    minBtn.MouseLeave:Connect(function()
        tween(minLine, { BackgroundColor3 = WHITE, Size = UDim2.fromOffset(14, 2) }, 0.2)
    end)
    minBtn.MouseButton1Click:Connect(function() win:SetMinimized(not win.Minimized) end)

    -- dragging
    local dragging, dragStart, startPos = false, nil, nil
    titlebar.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            dragStart = input.Position
            startPos = holder.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and isMove(input) then
            local d = input.Position - dragStart
            tween(holder, {
                Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y),
            }, 0.06, Enum.EasingStyle.Sine)
        end
    end)

    print("[LibraryUI] 3/6 titlebar ok")
    -- body
    local body = new("Frame", {
        Name = "Body", Position = UDim2.fromOffset(0, TITLE_H),
        Size = UDim2.new(1, 0, 1, -TITLE_H), BackgroundTransparency = 1, Parent = main,
    })
    local sidebar = new("Frame", {
        Name = "Sidebar", Position = UDim2.fromOffset(10, 6),
        Size = UDim2.new(0, 132, 1, -16), BackgroundTransparency = 0.15,
        BorderSizePixel = 0, Parent = body,
    })
    bind(sidebar, "BackgroundColor3", Shade.Side)
    corner(sidebar, 6)
    padding(sidebar, 10, 12, 10, 10)
    new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })

    local content = new("Frame", {
        Name = "Content", Position = UDim2.fromOffset(150, 6),
        Size = UDim2.new(1, -160, 1, -16), BackgroundTransparency = 0.15,
        BorderSizePixel = 0, ClipsDescendants = true, Parent = body,
    })
    bind(content, "BackgroundColor3", Shade.Panel)
    corner(content, 6)

    win.Body, win.Sidebar, win.Content = body, sidebar, content

    -- size
    win:SetSize(sizeName)
    holder.Size = UDim2.fromOffset(win.Width, win.Height)

    print("[LibraryUI] 4/6 body ok")
    -- built-in tabs
    local okS, eS = pcall(buildSettings, win)
    if not okS then warn("[LibraryUI] Settings tab failed: " .. tostring(eS)) end
    local okC, eC = pcall(buildConfig, win)
    if not okC then warn("[LibraryUI] Config tab failed: " .. tostring(eC)) end
    local okA, eA = pcall(buildAbout, win)
    if not okA then warn("[LibraryUI] About tab failed: " .. tostring(eA)) end
    print("[LibraryUI] 5/6 built-in tabs done")

    -- per-frame work: background effect + fps
    local t, frames, fpsAcc = 0, 0, 0
    connect(RunService.RenderStepped, function(dt)
        t = t + dt
        frames = frames + 1
        fpsAcc = fpsAcc + dt
        if fpsAcc >= 0.5 then
            win.FPS = math.floor(frames / fpsAcc + 0.5)
            frames, fpsAcc = 0, 0
        end
        if win.BgFx and win.Visible and LibraryUI.Animations then
            grad.Rotation = 90 + math.sin(t * 0.5 * LibraryUI.AnimSpeed) * 22
        end
    end)

    -- toggle key
    connect(UserInputService.InputBegan, function(input, processed)
        if processed or LibraryUI._binding then return end
        if input.KeyCode == LibraryUI.ToggleKey then
            win:SetVisible(not win.Visible)
        end
    end)

    -- select the first tab once the caller has added theirs
    task.defer(function()
        if win.Active or #win.Tabs == 0 then return end
        table.sort(win.Tabs, function(a, b) return a.Order < b.Order end)
        win:Select(win.Tabs[1])
    end)

    win:SetVisible(true)
    print("[LibraryUI] 6/6 window visible")
    LibraryUI.Window = win
    return win
end

function LibraryUI:CreateWindow(opts)
    local ok, res = xpcall(function() return self:_CreateWindow(opts) end, function(e)
        return tostring(e) .. "\n" .. debug.traceback()
    end)
    if not ok then
        warn("[LibraryUI] CreateWindow failed:\n" .. tostring(res))
        error(res, 0)
    end
    print("[LibraryUI] window created, mounted in: " .. tostring(self.MountedIn))
    return res
end

function LibraryUI:Destroy()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(connections)
    table.clear(themed)
    table.clear(gradients)
    if self.Gui then
        self.Gui:Destroy()
        self.Gui = nil
    end
    self.Window = nil
    if getgenv and getgenv().LibraryUI == self then getgenv().LibraryUI = nil end
end

if getgenv then getgenv().LibraryUI = LibraryUI end

return LibraryUI
