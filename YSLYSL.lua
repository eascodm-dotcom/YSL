--[[
    YSL FINAL SHOWDOWN
    discord.gg/yslrolling

    Custom UI (no Rayfield). UI built FIRST so feature errors can't kill it.
    Everything else runs in a pcall so any single failure doesn't take the window down.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local LP = Players.LocalPlayer

local Config = {
    autoWeave = { enabled = false, manualOnly = true, hold = 0.22, gap = 0.0 },
    hitbox = { enabled = false, radius = 7, airOnly = false },
    punchSpeed = { enabled = false, value = 1.7 },
    stompSpeed = { enabled = false, value = 1.4 },
    autoStomp = false,
    styleChanger = { enabled = false, style = "Philly" },
    damage = {
        autoConnect = false, connectRange = 15,
        hitMultiplier = { enabled = false, value = 1, delay = 0.08 },
        stompMultiplier = { enabled = false, value = 1 },
        noAttackDelay = false,
    },
    movement = {
        glide = { enabled = false, speed = 16 },
        antiDebounce = { enabled = false, value = 0.2 },
        walkSpeed = { enabled = false, value = 16 },
        heavyBoost = false,
    },
    dodge = { noStun = true, hitThrough = true },
    longRange = { enabled = false, mode = "position", maxRadius = 15 },
    damageNumbers = true, damageSwingWindow = 0.55,
    comboReset = false, phoneSwitch = false, comboResetDelay = 0.03, comboDebounce = 0.35, comboIdleReset = 0.85,
    headless = false, philly = false, lowGraphics = false,
    stretchResolution = false, stretchAspect = 0.65,
    noDelay = false, doubleHit = false, doubleDelay = 0.04,
    budgetRate = 10, budgetCap = 12, swingRate = 6, swingCap = 8,
    transparency = { enabled = false, level = 0.85 },
    crosshair = { enabled = false, size = 14, thickness = 2, gap = 5, dot = true },
}

local STATS = { hits=0, silentHits=0, counterHits=0, dodgeRetries=0 }

-- =========================== UI (built first) ==============================
local parent = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
if not parent then warn("[YSL] PlayerGui missing"); return end

local gui = Instance.new("ScreenGui")
gui.Name = "YSL_UI_" .. math.random(1, 99999)
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Parent = parent
print("[YSL] UI parented: " .. parent:GetFullName())

local main = Instance.new("Frame")
main.Size = UDim2.new(0.9, 0, 0.8, 0)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
title.BorderSizePixel = 0
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(240, 240, 250)
title.Text = "YSL FINAL SHOWDOWN"
title.Parent = main
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(28, 28)
close.Position = UDim2.new(1, -33, 0.5, -14)
close.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
close.Text = "X"
close.TextColor3 = Color3.fromRGB(240, 240, 250)
close.Font = Enum.Font.GothamBold
close.TextSize = 12
close.Parent = main
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)
close.MouseButton1Click:Connect(function() gui:Destroy() end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -10, 1, -40)
scroll.Position = UDim2.fromOffset(5, 35)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 5)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local y = 0
local function safeCb(fn) return function(...) pcall(fn, ...) end end
local function addSection(text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 24)
    lbl.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    lbl.BorderSizePixel = 0
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(180, 180, 200)
    lbl.Text = "  " .. string.upper(text)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = y
    y = y + 1
    lbl.Parent = scroll
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)
end
local function addToggle(name, get, set)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = get() and Color3.fromRGB(50, 100, 70) or Color3.fromRGB(40, 40, 55)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(220, 220, 230)
    btn.Text = name .. ": " .. (get() and "ON" or "OFF")
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.LayoutOrder = y
    y = y + 1
    btn.Parent = scroll
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(safeCb(function()
        local new = not get()
        set(new)
        btn.Text = name .. ": " .. (new and "ON" or "OFF")
        btn.BackgroundColor3 = new and Color3.fromRGB(50, 100, 70) or Color3.fromRGB(40, 40, 55)
    end))
end
local function addSlider(name, min, max, step, get, set, fmt)
    fmt = fmt or "%.2f"
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 40)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    frame.BorderSizePixel = 0
    frame.LayoutOrder = y
    y = y + 1
    frame.Parent = scroll
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 16)
    lbl.Position = UDim2.fromOffset(5, 2)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextColor3 = Color3.fromRGB(220, 220, 230)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = string.format("%s: " .. fmt, name, get())
    lbl.Parent = frame
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -10, 0, 8)
    bar.Position = UDim2.fromOffset(5, 24)
    bar.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    bar.BorderSizePixel = 0
    bar.Active = true
    bar.Parent = frame
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((get() - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(80, 140, 220)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
    local dragging = false
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local val = min + rel * (max - min)
            val = math.floor(val / step + 0.5) * step
            val = math.clamp(val, min, max)
            safeCb(function()
                set(val)
                fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
                lbl.Text = string.format("%s: " .. fmt, name, val)
            end)()
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end
local function addButton(name, cb)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = Color3.fromRGB(240, 240, 250)
    btn.Text = name
    btn.LayoutOrder = y
    y = y + 1
    btn.Parent = scroll
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(safeCb(cb))
end

-- Forward decls so UI can reference before feature block runs
local autoWeaveStart, autoWeaveStop, autoStompStart, autoConnectStart
local applyTransparency, rebuildCrosshair, stopGlide
local headlessToggle, phillyToggle, lowGraphicsToggle, stretchToggle, setStretchAspect
local applyStyle
local counter = { enabled = false, returnFire = true, clearStun = true, assertWeave = true }

-- Populate UI
addSection("Auto-Weave")
addToggle("Auto-Weave", function() return Config.autoWeave.enabled end, function(v) Config.autoWeave.enabled = v; if v then autoWeaveStart() else autoWeaveStop() end end)
addToggle("Manual Mode", function() return Config.autoWeave.manualOnly end, function(v) Config.autoWeave.manualOnly = v end)
addSlider("Hold", 0.10, 0.50, 0.01, function() return Config.autoWeave.hold end, function(v) Config.autoWeave.hold = v end)

addSection("Classic")
addToggle("Hitbox", function() return Config.hitbox.enabled end, function(v) Config.hitbox.enabled = v end)
addSlider("Hitbox Size", 1, 8, 0.1, function() return Config.hitbox.radius end, function(v) Config.hitbox.radius = v end, "%.1f")
addToggle("Punch Speed", function() return Config.punchSpeed.enabled end, function(v) Config.punchSpeed.enabled = v end)
addSlider("Punch Speed Val", 1.7, 3, 0.05, function() return Config.punchSpeed.value end, function(v) Config.punchSpeed.value = v end)
addToggle("Stomp Speed", function() return Config.stompSpeed.enabled end, function(v) Config.stompSpeed.enabled = v end)
addSlider("Stomp Speed Val", 1.4, 3, 0.05, function() return Config.stompSpeed.value end, function(v) Config.stompSpeed.value = v end)
addToggle("Auto Stomp", function() return Config.autoStomp end, function(v) Config.autoStomp = v; if v then autoStompStart() end end)
addToggle("Style Changer", function() return Config.styleChanger.enabled end, function(v) Config.styleChanger.enabled = v; if v then applyStyle(LP.Character, Config.styleChanger.style) end end)
addButton("Cycle Style: " .. Config.styleChanger.style, function()
    if Config.styleChanger.style == "Philly" then Config.styleChanger.style = "Classic"
    elseif Config.styleChanger.style == "Classic" then Config.styleChanger.style = "Kicks"
    elseif Config.styleChanger.style == "Kicks" then Config.styleChanger.style = "Boxing"
    else Config.styleChanger.style = "Philly" end
    if Config.styleChanger.enabled then applyStyle(LP.Character, Config.styleChanger.style) end
end)

addSection("Damage")
addToggle("Auto Connect", function() return Config.damage.autoConnect end, function(v) Config.damage.autoConnect = v; if v then autoConnectStart() end end)
addSlider("Connect Range", 5, 15, 0.5, function() return Config.damage.connectRange end, function(v) Config.damage.connectRange = v end, "%.1f")
addToggle("Hit Multiplier", function() return Config.damage.hitMultiplier.enabled end, function(v) Config.damage.hitMultiplier.enabled = v end)
addSlider("Hit Count", 1, 4, 1, function() return Config.damage.hitMultiplier.value end, function(v) Config.damage.hitMultiplier.value = v end, "%.0f")
addSlider("Hit Delay", 0.02, 0.20, 0.01, function() return Config.damage.hitMultiplier.delay end, function(v) Config.damage.hitMultiplier.delay = v end)
addToggle("No Attack Delay", function() return Config.damage.noAttackDelay end, function(v) Config.damage.noAttackDelay = v end)

addSection("Timing")
addToggle("No Punch Delay", function() return Config.noDelay end, function(v) Config.noDelay = v end)
addToggle("Double Hit", function() return Config.doubleHit end, function(v) Config.doubleHit = v end)
addSlider("Double Delay", 0.00, 0.20, 0.01, function() return Config.doubleDelay end, function(v) Config.doubleDelay = v end)
addToggle("4th Punch Reset", function() return Config.comboReset end, function(v) Config.comboReset = v end)
addToggle("Phone Switch", function() return Config.phoneSwitch end, function(v) Config.phoneSwitch = v end)
addSlider("Reset Delay", 0.00, 1.00, 0.01, function() return Config.comboResetDelay end, function(v) Config.comboResetDelay = v end)

addSection("Counter Stun")
addToggle("Enable Counter Stun", function() return counter.enabled end, function(v) counter.enabled = v end)
addToggle("Return Fire", function() return counter.returnFire end, function(v) counter.returnFire = v end)
addToggle("Clear Stun", function() return counter.clearStun end, function(v) counter.clearStun = v end)
addToggle("Assert Weave", function() return counter.assertWeave end, function(v) counter.assertWeave = v end)

addSection("Movement")
addToggle("Weave Glide", function() return Config.movement.glide.enabled end, function(v) Config.movement.glide.enabled = v; if not v then stopGlide() end end)
addSlider("Glide Speed", 12, 20, 1, function() return Config.movement.glide.speed end, function(v) Config.movement.glide.speed = v end, "%.0f")
addToggle("Anti Debounce", function() return Config.movement.antiDebounce.enabled end, function(v) Config.movement.antiDebounce.enabled = v end)
addSlider("Debounce", 0.05, 0.30, 0.01, function() return Config.movement.antiDebounce.value end, function(v) Config.movement.antiDebounce.value = v end)
addToggle("Walkspeed", function() return Config.movement.walkSpeed.enabled end, function(v)
    Config.movement.walkSpeed.enabled = v
    if not v then local ch = LP.Character; local hum = ch and ch:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed = 16 end end
end)
addSlider("Walkspeed Val", 16, 100, 1, function() return Config.movement.walkSpeed.value end, function(v) Config.movement.walkSpeed.value = v end, "%.0f")
addToggle("Heavy Booster", function() return Config.movement.heavyBoost end, function(v) Config.movement.heavyBoost = v; local ch = LP.Character; if ch then pcall(function() ch:SetAttribute("Heavy", v or nil) end) end end)

addSection("Dodge")
addToggle("Anti Weave Stun", function() return Config.dodge.noStun end, function(v) Config.dodge.noStun = v end)
addToggle("Hit Through Weave", function() return Config.dodge.hitThrough end, function(v) Config.dodge.hitThrough = v end)

addSection("Long Range")
addToggle("Long Range", function() return Config.longRange.enabled end, function(v) Config.longRange.enabled = v end)
addButton("Mode: " .. string.upper(Config.longRange.mode) .. " (cycle)", function()
    Config.longRange.mode = Config.longRange.mode == "position" and "midpoint" or "position"
end)
addSlider("Max Radius", 10, 15.2, 0.1, function() return Config.longRange.maxRadius end, function(v) Config.longRange.maxRadius = math.min(v, 15.2) end, "%.1f")

addSection("Transparency")
addToggle("Transparent Character", function() return Config.transparency.enabled end, function(v) Config.transparency.enabled = v; applyTransparency(LP.Character) end)
addSlider("Transparency Level", 0.5, 1.0, 0.05, function() return Config.transparency.level end, function(v) Config.transparency.level = v; if Config.transparency.enabled then applyTransparency(LP.Character) end end, "%.2f")

addSection("Crosshair")
addToggle("Crosshair", function() return Config.crosshair.enabled end, function(v) Config.crosshair.enabled = v; rebuildCrosshair() end)
addSlider("Size", 4, 30, 1, function() return Config.crosshair.size end, function(v) Config.crosshair.size = v; rebuildCrosshair() end, "%.0f")
addSlider("Thickness", 1, 6, 1, function() return Config.crosshair.thickness end, function(v) Config.crosshair.thickness = v; rebuildCrosshair() end, "%.0f")
addSlider("Gap", 0, 20, 1, function() return Config.crosshair.gap end, function(v) Config.crosshair.gap = v; rebuildCrosshair() end, "%.0f")
addToggle("Center Dot", function() return Config.crosshair.dot end, function(v) Config.crosshair.dot = v; rebuildCrosshair() end)

addSection("Cosmetics")
addToggle("Headless", function() return Config.headless end, function(v) headlessToggle(v) end)
addToggle("Philly Style", function() return Config.philly end, function(v) phillyToggle(v) end)
addToggle("Low Graphics", function() return Config.lowGraphics end, function(v) lowGraphicsToggle(v) end)
addToggle("Stretch Resolution", function() return Config.stretchResolution end, function(v) stretchToggle(v) end)
addSlider("Stretch Aspect", 0.35, 1.00, 0.01, function() return Config.stretchAspect end, function(v) setStretchAspect(v) end)

addSection("Damage Numbers")
addToggle("Damage Numbers", function() return Config.damageNumbers end, function(v) Config.damageNumbers = v end)
addSlider("Swing Window", 0.10, 1.50, 0.05, function() return Config.damageSwingWindow end, function(v) Config.damageSwingWindow = v end)

print("[YSL] UI built: " .. tostring(y) .. " rows")

-- =========================== FEATURES (pcall) ==============================
local featureOk, featureErr = pcall(function()

local Remotes, Combat, AttackState, HitWindow, Hitboxes, CharacterController, DataController, Classes
local Active = { Weaving = false, OpenFrame = false, CanAttack = false, Seq = 0, CurrentM1 = nil }
local HITBOX_MAX = 15.2
local SERVER_REACH = 5.8
local watchedChar, lastStun, stunWindowUntil = nil, false, 0
local lastServerStunAt = 0
local suppressHookReport = false
local dodgePending = setmetatable({}, { __mode = "k" })
local origHWStart, origHBStart, origHitReportFire
local counterSetupChar

local budget = { tokens = 12, rate = 10, cap = 12, last = os.clock() }
local function syncBudgets() budget.rate = Config.budgetRate; budget.cap = Config.budgetCap end
local function takeToken()
    local now = os.clock()
    budget.tokens = math.min(budget.cap, budget.tokens + (now - budget.last) * budget.rate)
    budget.last = now
    if budget.tokens < 1 then return false end
    budget.tokens -= 1
    return true
end

local function safeWait(p, n, t)
    t = t or 5
    local t0 = os.clock()
    local o = p:FindFirstChild(n)
    while not o and os.clock() - t0 < t do o = p:FindFirstChild(n); task.wait(0.05) end
    return o
end
local function safeRequire(path, t)
    local n = ReplicatedStorage
    for _, name in ipairs(path) do
        n = safeWait(n, name, t or 5)
        if not n then return nil end
    end
    local ok, mod = pcall(require, n)
    if ok then return mod end
    return nil
end

local function characterOf(p)
    local ch = p.Character; if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then return nil end
    return ch, hum, hrp
end
local function friendly(p)
    if p == LP then return true end
    return LP.Team ~= nil and p.Team == LP.Team
end
local function dealing(t)
    return t and t.root and t.root.Parent and t.hum and t.hum.Health > 0
end
local function myRoot() local ch = LP.Character; return ch and ch:FindFirstChild("HumanoidRootPart") end
local function distTo(t)
    local r = myRoot(); if not r or not t or not t.root then return math.huge end
    return (t.root.Position - r.Position).Magnitude
end
local function collect(radius)
    local ch = characterOf(LP); if not ch then return {} end
    local origin = ch:GetPivot().Position
    local cap = math.min(radius, HITBOX_MAX)
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if not friendly(p) then
            local tch, hum, hrp = characterOf(p)
            if tch then
                local d = (hrp.Position - origin).Magnitude
                if d <= cap then out[#out + 1] = { player=p, char=tch, hum=hum, root=hrp, dist=d } end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end
local function spoofPos(t)
    local r = myRoot(); if not r then return t.root.Position end
    if Config.longRange.mode == "position" then return r.Position + r.CFrame.LookVector * 2 end
    if Config.longRange.mode == "midpoint" then return (r.Position + t.root.Position) / 2 end
    return t.root.Position
end
local function stopStunAnims()
    local ch = watchedChar or LP.Character; if not ch then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator"); if not animator then return end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return end
    for _, t in ipairs(tracks) do
        local anim = t.Animation
        if anim then
            local nm = string.lower(tostring(anim.Name or ""))
            if nm:find("stun") or nm:find("hit") or nm:find("flinch") or nm:find("stagger")
                or nm:find("hurt") or nm:find("block") or nm:find("guard") or nm:find("shove") then
                pcall(function() t:Stop(0) end)
            end
        end
    end
end

-- Auto-weave
local aw = { cycleActive=false, cycleTask=nil, cycles=0, lastAnimAt=0, lastStateTrueAt=0, gateOpenUntil=0 }
local WEAVE_IDS = { ["17819683172"]=true, ["17819688197"]=true, ["17819691229"]=true, ["17819695187"]=true }
local function animPlayingNow()
    local ch = LP.Character; if not ch then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator"); if not animator then return false end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return false end
    for _, t in ipairs(tracks) do
        local anim = t.Animation
        if anim then
            local id = (anim.AnimationId or ""):match("(%d+)")
            if id and WEAVE_IDS[id] then return true end
        end
    end
    return false
end
local function weavingNow()
    local now = os.clock(); local open = false
    if CharacterController then
        local ok, w = pcall(function() return CharacterController:Is("Weaving") end)
        if ok and w == true then aw.lastStateTrueAt = now; aw.lastAnimAt = now; open = true end
    end
    if not open and Active and Active.Weaving == true then aw.lastStateTrueAt = now; aw.lastAnimAt = now; open = true end
    if not open and animPlayingNow() then aw.lastAnimAt = now; open = true end
    if not open then
        if (now - aw.lastStateTrueAt) < 0.28 then open = true end
        if (now - aw.lastAnimAt) < 0.28 then open = true end
    end
    if open then aw.gateOpenUntil = now + 0.20 return true end
    if now < aw.gateOpenUntil then return true end
    return false
end
local function gateOpen()
    if not Config.autoWeave.enabled then return false end
    if not Config.autoWeave.manualOnly then return true end
    return weavingNow()
end
local function awFire(state)
    if not Combat or not Combat.Weave then return end
    pcall(function() Combat.Weave:Fire(state) end)
    pcall(function() Combat.Weave:FireServer(state) end)
end
autoWeaveStart = function()
    if aw.cycleActive then return end
    aw.cycleActive = true
    aw.cycleTask = task.spawn(function()
        while aw.cycleActive and (not Combat or not Combat.Weave) do task.wait(0.1) end
        while aw.cycleActive do
            if not Config.autoWeave.enabled then task.wait(0.1)
            elseif gateOpen() then
                awFire(false); awFire(true)
                task.wait(Config.autoWeave.hold)
                if Config.autoWeave.gap > 0 then task.wait(Config.autoWeave.gap) end
                aw.cycles += 1
            else task.wait(0.02) end
        end
    end)
end
autoWeaveStop = function()
    aw.cycleActive = false
    if aw.cycleTask then pcall(function() task.cancel(aw.cycleTask) end) aw.cycleTask = nil end
    awFire(false)
end

-- Counter stun
local function setupCounterStun(ch)
    if counterSetupChar == ch then return end
    counterSetupChar = ch
    local hum = ch and ch:FindFirstChildOfClass("Humanoid"); if not hum then return end
    counter.lastHP = hum.Health
    hum.HealthChanged:Connect(function(newHP)
        if not counter.enabled then counter.lastHP = newHP; return end
        if newHP >= counter.lastHP then counter.lastHP = newHP; return end
        counter.lastHP = newHP
        if os.clock() - counter.lastHitAt < 0.1 then return end
        counter.lastHitAt = os.clock()
        if counter.clearStun then
            pcall(function() ch:SetAttribute("WeaveStun", false) end)
            stopStunAnims()
        end
        if counter.assertWeave and Combat and Combat.Weave then
            pcall(function() Combat.Weave:Fire(true) end)
            pcall(function() Combat.Weave:FireServer(true) end)
        end
        if counter.returnFire and Combat and Combat.HitReport then
            local r = Config.hitbox.radius > 0 and Config.hitbox.radius or 7
            for _, t in ipairs(collect(r)) do
                if dealing(t) and takeToken() then
                    pcall(function() Combat.HitReport:Fire(Active.Seq, t.root, t.root.Position) end)
                    STATS.counterHits += 1
                end
            end
        end
    end)
end

-- Transparency
applyTransparency = function(ch)
    if not ch then return end
    for _, part in ipairs(ch:GetDescendants()) do
        if part:IsA("BasePart") then
            if Config.transparency.enabled then
                pcall(function() part.LocalTransparencyModifier = Config.transparency.level end)
                pcall(function() part.Transparency = Config.transparency.level end)
            else
                pcall(function() part.LocalTransparencyModifier = 0 end)
            end
        elseif part:IsA("Decal") or part:IsA("Texture") then
            if Config.transparency.enabled then
                pcall(function() part.Transparency = Config.transparency.level end)
            else
                pcall(function() part.Transparency = 0 end)
            end
        end
    end
end

-- Crosshair
local crosshairGui
rebuildCrosshair = function()
    if crosshairGui then pcall(function() crosshairGui:Destroy() end) crosshairGui = nil end
    if not Config.crosshair.enabled then return end
    local pg = LP:FindFirstChild("PlayerGui"); if not pg then return end
    local g = Instance.new("ScreenGui"); g.Name = "YSL_Cross"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 50; g.Parent = pg
    crosshairGui = g
    local c = Instance.new("Frame"); c.Size = UDim2.fromOffset(0,0); c.Position = UDim2.new(0.5,0,0.5,0); c.BackgroundTransparency = 1; c.Parent = g
    local gp, s, t = Config.crosshair.gap, Config.crosshair.size, Config.crosshair.thickness
    local function arm(x, yy, w, h)
        local f = Instance.new("Frame"); f.Size = UDim2.fromOffset(w,h); f.Position = UDim2.fromOffset(x,yy)
        f.AnchorPoint = Vector2.new(0.5,0.5); f.BackgroundColor3 = Color3.fromRGB(255,255,255); f.BorderSizePixel = 0; f.Parent = c
    end
    arm(0, -(gp+s/2), t, s); arm(0, gp+s/2, t, s); arm(-(gp+s/2), 0, s, t); arm(gp+s/2, 0, s, t)
    if Config.crosshair.dot then
        local d = Instance.new("Frame"); d.Size = UDim2.fromOffset(t,t); d.AnchorPoint = Vector2.new(0.5,0.5)
        d.BackgroundColor3 = Color3.fromRGB(255,255,255); d.BorderSizePixel = 0; d.Parent = c
        Instance.new("UICorner", d).CornerRadius = UDim.new(1,0)
    end
end

-- Combat
local function reportOnce(seq, target)
    if not Combat or not Combat.HitReport then return false end
    if not takeToken() then return false end
    if not target.root or not target.root:IsA("BasePart") then return false end
    if Config.hitbox.airOnly then return false end
    if target.dist and target.dist > HITBOX_MAX then return false end
    local pos = target.root.Position
    if Config.longRange.enabled then pos = spoofPos(target) end
    local ok = pcall(function() Combat.HitReport:Fire(seq, target.root, pos) end)
    if ok then STATS.hits += 1 end
    return ok
end
local function silentHitMulti(seq, targets)
    if not Config.damage.hitMultiplier.enabled then return end
    local hits = math.floor(Config.damage.hitMultiplier.value or 1)
    if hits <= 1 then return end
    local delay = Config.damage.hitMultiplier.delay or 0.08
    for i = 2, hits do
        task.delay(delay * (i - 1), function()
            Active.OpenFrame = true; Active.CanAttack = true
            if origHWStart then
                suppressHookReport = true
                pcall(function() origHWStart("Attack", "RightHand") end)
                suppressHookReport = false
            end
            for _, t in ipairs(targets) do
                if dealing(t) and reportOnce(seq, t) then STATS.silentHits += 1 end
            end
        end)
    end
end
local function hookCombat()
    if not HitWindow or not origHWStart then return end
    HitWindow.Start = function(kind, limb, track, group)
        local r = origHWStart(kind, limb, track, group)
        if kind == "Attack" and not suppressHookReport then
            if Config.punchSpeed.enabled and Active.CurrentM1 then
                pcall(function() Active.CurrentM1:AdjustSpeed(Config.punchSpeed.value) end)
            end
        end
        if Config.damage.noAttackDelay or Config.noDelay then
            Active.OpenFrame = true; Active.CanAttack = true
        end
        if not suppressHookReport and (Config.hitbox.enabled or Config.damage.autoConnect) then
            local seq = Active.Seq
            local targets = collect(Config.damage.autoConnect and Config.damage.connectRange or Config.hitbox.radius)
            if #targets > 0 then
                task.delay(0.02, function()
                    local hitT = {}
                    for _, t in ipairs(targets) do
                        if t.dist <= HITBOX_MAX and reportOnce(seq, t) then
                            table.insert(hitT, t)
                        end
                    end
                    if #hitT > 0 then silentHitMulti(seq, hitT) end
                end)
            end
        end
        return r
    end
end

-- Glide
local glideBody = Instance.new("BodyVelocity")
glideBody.Name = "YSLGlide"; glideBody.MaxForce = Vector3.new(100000,0,100000); glideBody.P = 8000; glideBody.Velocity = Vector3.zero
local glideOn = false
stopGlide = function()
    if not glideOn then return end
    glideOn = false; glideBody.Velocity = Vector3.zero; glideBody.Parent = nil
end
local function updateGlide(rp, hum)
    if not Config.movement.glide.enabled or not rp or not hum or hum.Health <= 0 then stopGlide(); return end
    local mv = hum.MoveDirection
    if mv.Magnitude < 0.05 then
        local lk = rp.CFrame.LookVector; mv = Vector3.new(lk.X,0,lk.Z)
    end
    if mv.Magnitude < 0.05 then stopGlide(); return end
    if glideBody.Parent ~= rp then glideBody.Parent = rp end
    glideBody.Velocity = mv.Unit * Config.movement.glide.speed
    glideOn = true
end

-- Cosmetics
local function applyHeadless(ch)
    if not ch then return end
    local h = ch:FindFirstChild("Head")
    if h then h.Transparency = 1; local f = h:FindFirstChild("face"); if f then f.Transparency = 1 end end
end
local function restoreHead(ch)
    if not ch then return end
    local h = ch:FindFirstChild("Head")
    if h then h.Transparency = 0; local f = h:FindFirstChild("face"); if f then f.Transparency = 0 end end
end
headlessToggle = function(on) Config.headless = on; if on then applyHeadless(LP.Character) else restoreHead(LP.Character) end end
applyStyle = function(ch, s) if not ch then return end; pcall(function() ch:SetAttribute("Style", s) end) end
local lastRealClass
phillyToggle = function(on)
    Config.philly = on
    local ch = LP.Character; if not ch then return end
    if on then pcall(function() ch:SetAttribute("Style", "Philly") end)
    else
        local ok, real = pcall(function() return DataController and DataController:Get("Class") end)
        if ok and type(real) == "string" then pcall(function() ch:SetAttribute("Style", real) end) end
    end
end
lowGraphicsToggle = function(on)
    Config.lowGraphics = on
    if on then
        pcall(function()
            Lighting.GlobalShadows = false; Lighting.FogStart = 0; Lighting.FogEnd = 100000; Lighting.Brightness = 2
        end)
    else
        pcall(function()
            Lighting.GlobalShadows = true; Lighting.Brightness = 2
        end)
    end
end
local stretchConn
local function applyStretch(aspect)
    if stretchConn then stretchConn:Disconnect() stretchConn = nil end
    local cam = workspace.CurrentCamera; if not cam then return end
    local res = CFrame.new(0,0,0, 1,0,0, 0,aspect,0, 0,0,1)
    stretchConn = RunService.RenderStepped:Connect(function()
        if Config.stretchResolution then cam.CFrame = cam.CFrame * res end
    end)
end
stretchToggle = function(on)
    Config.stretchResolution = on
    if on then applyStretch(Config.stretchAspect)
    else if stretchConn then stretchConn:Disconnect() stretchConn = nil end end
end
setStretchAspect = function(v) Config.stretchAspect = v; if Config.stretchResolution then applyStretch(v) end end

-- Auto stomp / connect
autoStompStart = function()
    task.spawn(function()
        while true do
            task.wait(0.5)
            if Config.autoStomp and Combat then
                for k, v in pairs(Combat) do
                    if type(v) == "table" and v.Fire and string.lower(tostring(k)):find("stomp") then
                        local t = collect(8)
                        if #t > 0 then pcall(function() v:FireServer(t[1].root) end) end
                    end
                end
            end
        end
    end)
end
autoConnectStart = function()
    task.spawn(function()
        while true do
            task.wait(0.2)
            if Config.damage.autoConnect and Combat and Combat.HitReport then
                for _, tg in ipairs(collect(Config.damage.connectRange)) do
                    if takeToken() then
                        pcall(function() Combat.HitReport:Fire(Active.Seq, tg.root, tg.root.Position) end)
                    end
                end
            end
        end
    end)
end

-- Watched char / stun / heartbeat
local function applyStunBypass()
    if not Config.dodge.noStun then return end
    local ch = watchedChar; if not ch or not ch.Parent then return end
    local now = os.clock()
    if ch:GetAttribute("WeaveStun") == true then
        lastServerStunAt = now; stunWindowUntil = now + 0.5
        pcall(function() ch:SetAttribute("WeaveStun", false) end)
        stopStunAnims()
    end
end
local function watchChar()
    local ch = LP.Character
    if ch == watchedChar then return end
    watchedChar = ch; lastStun = false
    if not ch then return end
    ch:GetAttributeChangedSignal("WeaveStun"):Connect(function()
        local s = ch:GetAttribute("WeaveStun") == true
        lastStun = s
        if s then applyStunBypass() end
    end)
end

RunService.Heartbeat:Connect(function()
    watchChar(); applyStunBypass()
    local ch = LP.Character
    updateGlide(ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid"))
    if Config.autoWeave.enabled and aw.cycleActive then
        pcall(function() Active.CanAttack = true end)
        pcall(function() Active.OpenFrame = true end)
    end
    if ch and Config.dodge.noStun then
        if ch:GetAttribute("WeaveStun") == true then
            pcall(function() ch:SetAttribute("WeaveStun", false) end)
            stopStunAnims()
            lastServerStunAt = os.clock()
        end
        if ch:GetAttribute("Shoved") == true then
            pcall(function() ch:SetAttribute("Shoved", false) end)
        end
    end
    if ch and Config.transparency.enabled then
        for _, part in ipairs(ch:GetDescendants()) do
            if part:IsA("BasePart") then
                pcall(function() part.LocalTransparencyModifier = Config.transparency.level end)
                pcall(function() part.Transparency = Config.transparency.level end)
            end
        end
    end
    if ch then
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if hum then
            if Config.movement.walkSpeed.enabled then hum.WalkSpeed = Config.movement.walkSpeed.value end
            if Config.movement.heavyBoost then pcall(function() ch:SetAttribute("Heavy", true) end) end
        end
    end
end)

-- Init (require + hooks)
task.spawn(function()
    task.wait(3)
    local ok, err = pcall(function()
        Remotes = safeRequire({ "Shared","Net","Remotes" }, 8)
        if Remotes and Remotes.Client then
            local okc, c = pcall(function() return Remotes.Client("CombatService") end)
            if okc then Combat = c end
        end
        AttackState         = safeRequire({ "Client","Combat","AttackState" }, 8)
        HitWindow           = safeRequire({ "Client","Combat","HitWindow" }, 8)
        Hitboxes            = safeRequire({ "Client","Combat","Hitboxes" }, 8)
        CharacterController = safeRequire({ "Client","Controllers","CharacterController" }, 8)
        DataController      = safeRequire({ "Client","Controllers","DataController" }, 8)
        Classes             = safeRequire({ "Shared","Config","Classes" }, 5)
        if AttackState and AttackState.Active then Active = AttackState.Active end
        origHWStart = HitWindow and HitWindow.Start
        origHBStart = Hitboxes and Hitboxes.Start
        if Combat and Combat.HitReport and type(Combat.HitReport.Fire) == "function"
            and hookfunction and newcclosure then
            origHitReportFire = Combat.HitReport.Fire
            Combat.HitReport.Fire = newcclosure(function(self, seq, root, pos, ...)
                if Config.dodge.hitThrough and root and typeof(root) == "Instance" and root:IsA("BasePart") then
                    pos = root.Position
                end
                return origHitReportFire(self, seq, root, pos, ...)
            end)
            print("[YSL] HitReport hooked")
        end
        hookCombat()
        if LP.Character then setupCounterStun(LP.Character); applyTransparency(LP.Character) end
        LP.CharacterAdded:Connect(function(ch) task.wait(0.5); setupCounterStun(ch); applyTransparency(ch) end)
        print("[YSL] Combat ready")
    end)
    if not ok then warn("[YSL] init:", tostring(err)) end
end)

syncBudgets()

end) -- closes feature pcall

if not featureOk then warn("[YSL] FEATURE ERROR (UI still works): " .. tostring(featureErr)) end
print("[YSL] ready")
