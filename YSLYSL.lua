--[[
    YSL FINAL SHOWDOWN
    discord.gg/yslrolling

    UI: Obsidian. Forward decls FIXED - all toggles functional.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local LP = Players.LocalPlayer

-- =========================== FORWARD DECLS (must be before UI) ==============
local CounterEnabled  = false
local CounterReturn   = true
local CounterClear    = true
local CounterAssert   = true
local RebuildCrosshair
local ApplyTransparency
local HeadlessToggle
local PhillyToggle
local LowGraphicsToggle
local StretchToggle
local SetStretchAspect
local autoWeaveStart
local autoWeaveStop

-- =========================== LOAD OBSIDIAN ==================================
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()

-- =========================== CONFIG ========================================
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
    transparency = { enabled = false, level = 0.85 },
    crosshair = { enabled = false, size = 14, thickness = 2, gap = 5, dot = true },
}

local STATS = { hits=0, silentHits=0, counterHits=0, dodgeRetries=0 }

-- =========================== WINDOW ========================================
local Window = Library:CreateWindow({
    Title = "YSL FINAL SHOWDOWN",
    Footer = "discord.gg/yslrolling",
    Center = true,
    AutoShow = true,
    NotifySide = "Right",
})

local Tabs = {
    Combat   = Window:AddTab("Combat", "swords"),
    Movement = Window:AddTab("Movement", "move"),
    Visuals  = Window:AddTab("Visuals", "eye"),
    Misc     = Window:AddTab("Misc", "settings"),
}

-- =========================== COMBAT TAB ====================================
local AW = Tabs.Combat:AddLeftGroupbox("Auto-Weave")
AW:AddToggle("aw_enabled", { Text = "Auto-Weave", Default = Config.autoWeave.enabled,
    Callback = function(v) Config.autoWeave.enabled = v; if v then autoWeaveStart() else autoWeaveStop() end end })
AW:AddToggle("aw_manual", { Text = "Manual Mode", Default = Config.autoWeave.manualOnly,
    Callback = function(v) Config.autoWeave.manualOnly = v end })
AW:AddSlider("aw_hold", { Text = "Hold", Default = Config.autoWeave.hold,
    Min = 0.10, Max = 0.50, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.autoWeave.hold = v end })

local HB = Tabs.Combat:AddRightGroupbox("Hitbox")
HB:AddToggle("hb_enabled", { Text = "Hitbox", Default = Config.hitbox.enabled,
    Callback = function(v) Config.hitbox.enabled = v end })
HB:AddSlider("hb_radius", { Text = "Radius", Default = Config.hitbox.radius,
    Min = 1, Max = 8, Rounding = 1, Suffix = " studs",
    Callback = function(v) Config.hitbox.radius = v end })

local TM = Tabs.Combat:AddLeftGroupbox("Timing")
TM:AddToggle("noDelay",   { Text = "No Punch Delay", Default = Config.noDelay, Callback = function(v) Config.noDelay = v end })
TM:AddToggle("doubleHit", { Text = "Double Hit",     Default = Config.doubleHit, Callback = function(v) Config.doubleHit = v end })
TM:AddSlider("doubleDelay", { Text = "Double Delay", Default = Config.doubleDelay, Min = 0.00, Max = 0.20, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.doubleDelay = v end })
TM:AddToggle("comboReset", { Text = "4th Punch Reset", Default = Config.comboReset, Callback = function(v) Config.comboReset = v end })
TM:AddToggle("phoneSwitch",{ Text = "Phone Switch",   Default = Config.phoneSwitch, Callback = function(v) Config.phoneSwitch = v end })
TM:AddSlider("resetDelay", { Text = "Reset Delay", Default = Config.comboResetDelay, Min = 0.00, Max = 1.00, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.comboResetDelay = v end })

local DMG = Tabs.Combat:AddRightGroupbox("Damage")
DMG:AddToggle("autoConnect", { Text = "Auto Connect", Default = Config.damage.autoConnect,
    Callback = function(v) Config.damage.autoConnect = v end })
DMG:AddSlider("connectRange", { Text = "Connect Range", Default = Config.damage.connectRange,
    Min = 5, Max = 15, Rounding = 1, Suffix = " studs",
    Callback = function(v) Config.damage.connectRange = v end })
DMG:AddToggle("hitMult", { Text = "Hit Multiplier (Silent)", Default = Config.damage.hitMultiplier.enabled,
    Callback = function(v) Config.damage.hitMultiplier.enabled = v end })
DMG:AddSlider("hitCount", { Text = "Hit Count", Default = Config.damage.hitMultiplier.value,
    Min = 1, Max = 4, Rounding = 0,
    Callback = function(v) Config.damage.hitMultiplier.value = v end })
DMG:AddSlider("hitDelay", { Text = "Hit Delay", Default = Config.damage.hitMultiplier.delay,
    Min = 0.02, Max = 0.20, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.damage.hitMultiplier.delay = v end })

local CT = Tabs.Combat:AddLeftGroupbox("Counter Stun")
CT:AddToggle("counter_enabled", { Text = "Enable Counter Stun", Default = false,
    Callback = function(v) CounterEnabled = v end })
CT:AddToggle("counter_return",  { Text = "Return Fire",          Default = true,
    Callback = function(v) CounterReturn = v end })
CT:AddToggle("counter_clear",   { Text = "Clear Stun",           Default = true,
    Callback = function(v) CounterClear = v end })
CT:AddToggle("counter_assert",  { Text = "Assert Weave",         Default = true,
    Callback = function(v) CounterAssert = v end })

-- =========================== MOVEMENT TAB ==================================
local GL = Tabs.Movement:AddLeftGroupbox("Weave Glide")
GL:AddToggle("glide_enabled", { Text = "Weave Glide", Default = Config.movement.glide.enabled,
    Callback = function(v) Config.movement.glide.enabled = v end })
GL:AddSlider("glide_speed", { Text = "Glide Speed", Default = Config.movement.glide.speed,
    Min = 12, Max = 20, Rounding = 0,
    Callback = function(v) Config.movement.glide.speed = v end })

local WK = Tabs.Movement:AddRightGroupbox("Movement")
WK:AddToggle("walk_enabled", { Text = "Walkspeed", Default = Config.movement.walkSpeed.enabled,
    Callback = function(v) Config.movement.walkSpeed.enabled = v end })
WK:AddSlider("walk_speed", { Text = "Walkspeed Value", Default = Config.movement.walkSpeed.value,
    Min = 16, Max = 100, Rounding = 0,
    Callback = function(v) Config.movement.walkSpeed.value = v end })
WK:AddToggle("heavyBoost", { Text = "Heavy Booster", Default = Config.movement.heavyBoost,
    Callback = function(v) Config.movement.heavyBoost = v end })

-- =========================== VISUALS TAB ===================================
local CR = Tabs.Visuals:AddLeftGroupbox("Crosshair")
CR:AddToggle("cross_enabled", { Text = "Crosshair", Default = Config.crosshair.enabled,
    Callback = function(v) Config.crosshair.enabled = v; if RebuildCrosshair then RebuildCrosshair() end end })
CR:AddSlider("cross_size", { Text = "Size", Default = Config.crosshair.size, Min = 4, Max = 30, Rounding = 0,
    Callback = function(v) Config.crosshair.size = v; if RebuildCrosshair then RebuildCrosshair() end end })
CR:AddSlider("cross_thick", { Text = "Thickness", Default = Config.crosshair.thickness, Min = 1, Max = 6, Rounding = 0,
    Callback = function(v) Config.crosshair.thickness = v; if RebuildCrosshair then RebuildCrosshair() end end })
CR:AddSlider("cross_gap", { Text = "Gap", Default = Config.crosshair.gap, Min = 0, Max = 20, Rounding = 0,
    Callback = function(v) Config.crosshair.gap = v; if RebuildCrosshair then RebuildCrosshair() end end })
CR:AddToggle("cross_dot", { Text = "Center Dot", Default = Config.crosshair.dot,
    Callback = function(v) Config.crosshair.dot = v; if RebuildCrosshair then RebuildCrosshair() end end })

local TR = Tabs.Visuals:AddRightGroupbox("Character Transparency")
TR:AddToggle("trans_enabled", { Text = "Transparent Character", Default = Config.transparency.enabled,
    Callback = function(v) Config.transparency.enabled = v; if ApplyTransparency then ApplyTransparency(LP.Character) end end })
TR:AddSlider("trans_level", { Text = "Transparency Level", Default = Config.transparency.level,
    Min = 0.5, Max = 1.0, Rounding = 2,
    Callback = function(v) Config.transparency.level = v
        if Config.transparency.enabled and ApplyTransparency then ApplyTransparency(LP.Character) end
    end })

-- =========================== MISC TAB ======================================
local DG = Tabs.Misc:AddLeftGroupbox("Dodge")
DG:AddToggle("noStun",     { Text = "Anti Weave Stun",    Default = Config.dodge.noStun,     Callback = function(v) Config.dodge.noStun = v end })
DG:AddToggle("hitThrough", { Text = "Hit Through Weave",  Default = Config.dodge.hitThrough, Callback = function(v) Config.dodge.hitThrough = v end })

local LR = Tabs.Misc:AddRightGroupbox("Long Range")
LR:AddToggle("lr_enabled", { Text = "Long Range", Default = Config.longRange.enabled,
    Callback = function(v) Config.longRange.enabled = v end })
LR:AddButton({ Text = "Cycle Mode", Func = function()
    Config.longRange.mode = Config.longRange.mode == "position" and "midpoint" or "position"
end })
LR:AddSlider("lr_radius", { Text = "Max Radius", Default = Config.longRange.maxRadius,
    Min = 10, Max = 15.2, Rounding = 1,
    Callback = function(v) Config.longRange.maxRadius = math.min(v, 15.2) end })

local CS = Tabs.Misc:AddLeftGroupbox("Cosmetics")
CS:AddToggle("headless",    { Text = "Headless",           Default = Config.headless,
    Callback = function(v) Config.headless = v; if HeadlessToggle then HeadlessToggle(v) end end })
CS:AddToggle("philly",      { Text = "Philly Style",       Default = Config.philly,
    Callback = function(v) Config.philly = v; if PhillyToggle then PhillyToggle(v) end end })
CS:AddToggle("lowGraphics", { Text = "Low Graphics",       Default = Config.lowGraphics,
    Callback = function(v) Config.lowGraphics = v; if LowGraphicsToggle then LowGraphicsToggle(v) end end })
CS:AddToggle("stretchRes",  { Text = "Stretch Resolution", Default = Config.stretchResolution,
    Callback = function(v) Config.stretchResolution = v; if StretchToggle then StretchToggle(v) end end })
CS:AddSlider("stretchAspect", { Text = "Stretch Aspect", Default = Config.stretchAspect,
    Min = 0.35, Max = 1.00, Rounding = 2,
    Callback = function(v) Config.stretchAspect = v; if SetStretchAspect then SetStretchAspect(v) end end })

local DN = Tabs.Misc:AddRightGroupbox("Damage Numbers")
DN:AddToggle("dmgNums", { Text = "Damage Numbers", Default = Config.damageNumbers,
    Callback = function(v) Config.damageNumbers = v end })
DN:AddSlider("swingWindow", { Text = "Swing Window", Default = Config.damageSwingWindow,
    Min = 0.10, Max = 1.50, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.damageSwingWindow = v end })

-- =========================== FEATURE CODE ==================================
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

local function syncBudgets() budget.rate = Config.budgetRate or 10; budget.cap = Config.budgetCap or 12 end
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
local function dealing(t) return t and t.root and t.root.Parent and t.hum and t.hum.Health > 0 end
local function myRoot() local ch = LP.Character; return ch and ch:FindFirstChild("HumanoidRootPart") end
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
    hum.HealthChanged:Connect(function(newHP)
        if not CounterEnabled then return end
        if newHP >= hum.Health then return end
        if os.clock() - lastServerStunAt < 0.1 then return end
        lastServerStunAt = os.clock()
        if CounterClear then
            pcall(function() ch:SetAttribute("WeaveStun", false) end)
            stopStunAnims()
        end
        if CounterAssert and Combat and Combat.Weave then
            pcall(function() Combat.Weave:Fire(true) end)
            pcall(function() Combat.Weave:FireServer(true) end)
        end
        if CounterReturn and Combat and Combat.HitReport then
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
ApplyTransparency = function(ch)
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
RebuildCrosshair = function()
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
local function stopGlide()
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
HeadlessToggle = function(on) Config.headless = on; if on then applyHeadless(LP.Character) else restoreHead(LP.Character) end end
PhillyToggle = function(on)
    Config.philly = on
    local ch = LP.Character; if not ch then return end
    if on then pcall(function() ch:SetAttribute("Style", "Philly") end)
    else
        local ok, real = pcall(function() return DataController and DataController:Get("Class") end)
        if ok and type(real) == "string" then pcall(function() ch:SetAttribute("Style", real) end) end
    end
end
LowGraphicsToggle = function(on)
    Config.lowGraphics = on
    if on then
        pcall(function()
            Lighting.GlobalShadows = false; Lighting.FogStart = 0; Lighting.FogEnd = 100000; Lighting.Brightness = 2
        end)
    else
        pcall(function() Lighting.GlobalShadows = true; Lighting.Brightness = 2 end)
    end
end
local stretchConn
SetStretchAspect = function(v) Config.stretchAspect = v end
StretchToggle = function(on)
    Config.stretchResolution = on
    if stretchConn then stretchConn:Disconnect() stretchConn = nil end
    if not on then return end
    local cam = workspace.CurrentCamera; if not cam then return end
    local res = CFrame.new(0,0,0, 1,0,0, 0,Config.stretchAspect,0, 0,0,1)
    stretchConn = RunService.RenderStepped:Connect(function()
        if Config.stretchResolution then cam.CFrame = cam.CFrame * res end
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

-- Init
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
        if LP.Character then setupCounterStun(LP.Character); ApplyTransparency(LP.Character) end
        LP.CharacterAdded:Connect(function(ch) task.wait(0.5); setupCounterStun(ch); ApplyTransparency(ch) end)
        print("[YSL] Combat ready")
    end)
    if not ok then warn("[YSL] init:", tostring(err)) end
end)

syncBudgets()

end) -- feature pcall

if not featureOk then warn("[YSL] FEATURE ERROR: " .. tostring(featureErr)) end
print("[YSL] ready")
