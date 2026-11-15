--[[
    YSL FINAL SHOWDOWN
    discord.gg/yslrolling

    UI: Obsidian.
    v3: config persistence, weave-gated glide, cross-platform sensitivity,
        Weave Combat (hit while weaving), Killaura, real damage numbers,
        no stray part in the character, silent-hit count up to 10.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local OBSIDIAN_URL = "https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"
local SAVE_ROOT    = "YSL/configs"
local AUTOLOAD_FILE = "YSL/autoload.txt"

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
local WeaveHitSet
local KillAuraSet
local ApplySensitivity
local ApplyAllConfig
local RunDoctor
local StartSpy
local DumpSpy

-- =========================== LOAD OBSIDIAN ==================================
local Library
do
    local compile = loadstring or load
    local ok, res = pcall(function()
        local src = game:HttpGet(OBSIDIAN_URL)
        local chunk = compile(src)
        if not chunk then error("Obsidian source failed to compile") end
        return chunk()
    end)
    if not ok or type(res) ~= "table" then
        warn("[YSL] failed to load Obsidian: " .. tostring(res))
        return
    end
    Library = res
end

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
    sensitivity = { enabled = false, value = 1.0 },
    weaveHit = { enabled = false, window = 0.12, restoreDelay = 0.06, reassert = true },
    killaura = { enabled = false, radius = 12, interval = 0.12, maxTargets = 1, weaveSync = true },
    dodge = { noStun = true, hitThrough = true },
    counter = { enabled = false, returnFire = true, clearStun = true, assert = true },
    longRange = { enabled = false, mode = "position", maxRadius = 15 },
    damageNumbers = true, damageSwingWindow = 1.10,
    comboReset = false, phoneSwitch = false, comboResetDelay = 0.03, comboDebounce = 0.35, comboIdleReset = 0.85,
    headless = false, philly = false, lowGraphics = false,
    stretchResolution = false, stretchAspect = 0.65,
    noDelay = false, doubleHit = false, doubleDelay = 0.04,
    transparency = { enabled = false, level = 0.85 },
    crosshair = { enabled = false, size = 14, thickness = 2, gap = 5, dot = true },
    budgetRate = 10, budgetCap = 12,
}

local STATS = { hits = 0, silentHits = 0, counterHits = 0, dodgeRetries = 0 }

-- =========================== CONFIG FILES ==================================
local Options = {}      -- UI key -> element, for post-load visual sync
local SelectedConfig = nil
local spyLog = {}       -- captured FireServer calls, written to YSL/spy.txt

local function hasFS()
    return typeof(writefile) == "function" and typeof(readfile) == "function"
        and typeof(isfolder) == "function" and typeof(makefolder) == "function"
end

local function ensureFolder(path)
    if not hasFS() then return false end
    local cur = ""
    for seg in string.gmatch(path, "[^/]+") do
        cur = (cur == "") and seg or (cur .. "/" .. seg)
        if not isfolder(cur) then pcall(makefolder, cur) end
    end
    return true
end

local function sanitizeName(name)
    local s = tostring(name or ""):gsub("[^%w_%-%. ]", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if #s == 0 then return nil end
    return s:sub(1, 32)
end

local function configPath(name) return SAVE_ROOT .. "/" .. name .. ".json" end

local function listConfigs()
    local out = {}
    if typeof(listfiles) == "function" and typeof(isfolder) == "function" and isfolder(SAVE_ROOT) then
        local ok, files = pcall(listfiles, SAVE_ROOT)
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                local name = tostring(f):match("([^/\\]+)%.json$")
                if name then out[#out + 1] = name end
            end
        end
    end
    table.sort(out)
    return out
end

local function writeConfig(name)
    if not hasFS() then return false, "executor has no file API" end
    ensureFolder(SAVE_ROOT)
    local ok, body = pcall(function() return HttpService:JSONEncode(Config) end)
    if not ok then return false, "encode failed" end
    local wrote = pcall(writefile, configPath(name), body)
    return wrote, wrote and nil or "write failed"
end

local function readConfig(name)
    if not hasFS() then return nil, "executor has no file API" end
    local p = configPath(name)
    if typeof(isfile) == "function" and not isfile(p) then return nil, "not found" end
    local ok, body = pcall(readfile, p)
    if not ok or type(body) ~= "string" then return nil, "read failed" end
    local decoded, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not decoded or type(data) ~= "table" then return nil, "decode failed" end
    return data
end

-- Schema-safe apply: only keys that already exist in Config are written.
local function deepApply(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            deepApply(dst[k], v)
        elseif dst[k] ~= nil and type(v) ~= "table" then
            dst[k] = v
        end
    end
end

-- UI key -> path inside Config, so a load can push values back into the widgets.
local SyncList = {
    { "aw_enabled", { "autoWeave", "enabled" } }, { "aw_manual", { "autoWeave", "manualOnly" } },
    { "aw_hold", { "autoWeave", "hold" } }, { "aw_gap", { "autoWeave", "gap" } },
    { "hb_enabled", { "hitbox", "enabled" } }, { "hb_radius", { "hitbox", "radius" } },
    { "hb_air", { "hitbox", "airOnly" } },
    { "noDelay", { "noDelay" } }, { "doubleHit", { "doubleHit" } }, { "doubleDelay", { "doubleDelay" } },
    { "comboReset", { "comboReset" } }, { "phoneSwitch", { "phoneSwitch" } },
    { "resetDelay", { "comboResetDelay" } },
    { "autoConnect", { "damage", "autoConnect" } }, { "connectRange", { "damage", "connectRange" } },
    { "hitMult", { "damage", "hitMultiplier", "enabled" } }, { "hitCount", { "damage", "hitMultiplier", "value" } },
    { "hitDelay", { "damage", "hitMultiplier", "delay" } },
    { "counter_enabled", { "counter", "enabled" } }, { "counter_return", { "counter", "returnFire" } },
    { "counter_clear", { "counter", "clearStun" } }, { "counter_assert", { "counter", "assert" } },
    { "glide_enabled", { "movement", "glide", "enabled" } }, { "glide_speed", { "movement", "glide", "speed" } },
    { "walk_enabled", { "movement", "walkSpeed", "enabled" } }, { "walk_speed", { "movement", "walkSpeed", "value" } },
    { "heavyBoost", { "movement", "heavyBoost" } },
    { "sens_enabled", { "sensitivity", "enabled" } }, { "sens_value", { "sensitivity", "value" } },
    { "wh_enabled", { "weaveHit", "enabled" } }, { "wh_window", { "weaveHit", "window" } },
    { "wh_reassert", { "weaveHit", "reassert" } },
    { "ka_enabled", { "killaura", "enabled" } }, { "ka_radius", { "killaura", "radius" } },
    { "ka_interval", { "killaura", "interval" } }, { "ka_targets", { "killaura", "maxTargets" } },
    { "ka_weave", { "killaura", "weaveSync" } },
    { "cross_enabled", { "crosshair", "enabled" } }, { "cross_size", { "crosshair", "size" } },
    { "cross_thick", { "crosshair", "thickness" } }, { "cross_gap", { "crosshair", "gap" } },
    { "cross_dot", { "crosshair", "dot" } },
    { "trans_enabled", { "transparency", "enabled" } }, { "trans_level", { "transparency", "level" } },
    { "noStun", { "dodge", "noStun" } }, { "hitThrough", { "dodge", "hitThrough" } },
    { "lr_enabled", { "longRange", "enabled" } }, { "lr_radius", { "longRange", "maxRadius" } },
    { "headless", { "headless" } }, { "philly", { "philly" } }, { "lowGraphics", { "lowGraphics" } },
    { "stretchRes", { "stretchResolution" } }, { "stretchAspect", { "stretchAspect" } },
    { "dmgNums", { "damageNumbers" } }, { "swingWindow", { "damageSwingWindow" } },
}

local function pathGet(t, path)
    local cur = t
    for _, k in ipairs(path) do
        if type(cur) ~= "table" then return nil end
        cur = cur[k]
        if cur == nil then return nil end
    end
    return cur
end

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
Options.aw_enabled = AW:AddToggle("aw_enabled", { Text = "Auto-Weave", Default = Config.autoWeave.enabled,
    Callback = function(v) Config.autoWeave.enabled = v; if v then autoWeaveStart() else autoWeaveStop() end end })
Options.aw_manual = AW:AddToggle("aw_manual", { Text = "Manual Mode", Default = Config.autoWeave.manualOnly,
    Callback = function(v) Config.autoWeave.manualOnly = v end })
Options.aw_hold = AW:AddSlider("aw_hold", { Text = "Hold", Default = Config.autoWeave.hold,
    Min = 0.10, Max = 0.50, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.autoWeave.hold = v end })
Options.aw_gap = AW:AddSlider("aw_gap", { Text = "Cycle Gap", Default = Config.autoWeave.gap,
    Min = 0.00, Max = 0.30, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.autoWeave.gap = v end })

local WH = Tabs.Combat:AddLeftGroupbox("Weave Combat")
Options.wh_enabled = WH:AddToggle("wh_enabled", { Text = "Hit While Weaving", Default = Config.weaveHit.enabled,
    Callback = function(v) Config.weaveHit.enabled = v; if WeaveHitSet then WeaveHitSet(v) end end })
Options.wh_window = WH:AddSlider("wh_window", { Text = "Window", Default = Config.weaveHit.window,
    Min = 0.04, Max = 0.30, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.weaveHit.window = v end })
Options.wh_reassert = WH:AddToggle("wh_reassert", { Text = "Resume Weave After Hit", Default = Config.weaveHit.reassert,
    Callback = function(v) Config.weaveHit.reassert = v end })

local KA = Tabs.Combat:AddLeftGroupbox("Killaura")
Options.ka_enabled = KA:AddToggle("ka_enabled", { Text = "Killaura", Default = Config.killaura.enabled,
    Callback = function(v) Config.killaura.enabled = v; if KillAuraSet then KillAuraSet(v) end end })
Options.ka_radius = KA:AddSlider("ka_radius", { Text = "Radius", Default = Config.killaura.radius,
    Min = 3, Max = 15, Rounding = 1, Suffix = " studs",
    Callback = function(v) Config.killaura.radius = v end })
Options.ka_interval = KA:AddSlider("ka_interval", { Text = "Interval", Default = Config.killaura.interval,
    Min = 0.03, Max = 0.50, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.killaura.interval = v end })
Options.ka_targets = KA:AddSlider("ka_targets", { Text = "Targets Per Cycle", Default = Config.killaura.maxTargets,
    Min = 1, Max = 5, Rounding = 0,
    Callback = function(v) Config.killaura.maxTargets = v end })
Options.ka_weave = KA:AddToggle("ka_weave", { Text = "Sync With Weave", Default = Config.killaura.weaveSync,
    Callback = function(v) Config.killaura.weaveSync = v end })

local HB = Tabs.Combat:AddRightGroupbox("Hitbox")
Options.hb_enabled = HB:AddToggle("hb_enabled", { Text = "Hitbox", Default = Config.hitbox.enabled,
    Callback = function(v) Config.hitbox.enabled = v end })
Options.hb_radius = HB:AddSlider("hb_radius", { Text = "Radius", Default = Config.hitbox.radius,
    Min = 1, Max = 8, Rounding = 1, Suffix = " studs",
    Callback = function(v) Config.hitbox.radius = v end })
Options.hb_air = HB:AddToggle("hb_air", { Text = "Airborne Targets Only", Default = Config.hitbox.airOnly,
    Callback = function(v) Config.hitbox.airOnly = v end })

local TM = Tabs.Combat:AddRightGroupbox("Timing")
Options.noDelay = TM:AddToggle("noDelay", { Text = "No Punch Delay", Default = Config.noDelay,
    Callback = function(v) Config.noDelay = v end })
Options.doubleHit = TM:AddToggle("doubleHit", { Text = "Double Hit", Default = Config.doubleHit,
    Callback = function(v) Config.doubleHit = v end })
Options.doubleDelay = TM:AddSlider("doubleDelay", { Text = "Double Delay", Default = Config.doubleDelay,
    Min = 0.00, Max = 0.20, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.doubleDelay = v end })
Options.comboReset = TM:AddToggle("comboReset", { Text = "4th Punch Reset", Default = Config.comboReset,
    Callback = function(v) Config.comboReset = v end })
Options.phoneSwitch = TM:AddToggle("phoneSwitch", { Text = "Phone Switch", Default = Config.phoneSwitch,
    Callback = function(v) Config.phoneSwitch = v end })
Options.resetDelay = TM:AddSlider("resetDelay", { Text = "Reset Delay", Default = Config.comboResetDelay,
    Min = 0.00, Max = 1.00, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.comboResetDelay = v end })

local DMG = Tabs.Combat:AddRightGroupbox("Damage")
Options.autoConnect = DMG:AddToggle("autoConnect", { Text = "Auto Connect", Default = Config.damage.autoConnect,
    Callback = function(v) Config.damage.autoConnect = v end })
Options.connectRange = DMG:AddSlider("connectRange", { Text = "Connect Range", Default = Config.damage.connectRange,
    Min = 5, Max = 15, Rounding = 1, Suffix = " studs",
    Callback = function(v) Config.damage.connectRange = v end })
Options.hitMult = DMG:AddToggle("hitMult", { Text = "Silent Hit Multiplier", Default = Config.damage.hitMultiplier.enabled,
    Callback = function(v) Config.damage.hitMultiplier.enabled = v end })
Options.hitCount = DMG:AddSlider("hitCount", { Text = "Hit Count", Default = Config.damage.hitMultiplier.value,
    Min = 1, Max = 10, Rounding = 0,
    Callback = function(v) Config.damage.hitMultiplier.value = v end })
Options.hitDelay = DMG:AddSlider("hitDelay", { Text = "Hit Spacing", Default = Config.damage.hitMultiplier.delay,
    Min = 0.02, Max = 0.30, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.damage.hitMultiplier.delay = v end })

local CT = Tabs.Combat:AddRightGroupbox("Counter Stun")
Options.counter_enabled = CT:AddToggle("counter_enabled", { Text = "Enable Counter Stun", Default = false,
    Callback = function(v) CounterEnabled = v; Config.counter.enabled = v end })
Options.counter_return = CT:AddToggle("counter_return", { Text = "Return Fire", Default = true,
    Callback = function(v) CounterReturn = v; Config.counter.returnFire = v end })
Options.counter_clear = CT:AddToggle("counter_clear", { Text = "Clear Stun", Default = true,
    Callback = function(v) CounterClear = v; Config.counter.clearStun = v end })
Options.counter_assert = CT:AddToggle("counter_assert", { Text = "Assert Weave", Default = true,
    Callback = function(v) CounterAssert = v; Config.counter.assert = v end })

-- =========================== MOVEMENT TAB ==================================
local GL = Tabs.Movement:AddLeftGroupbox("Weave Glide")
Options.glide_enabled = GL:AddToggle("glide_enabled", { Text = "Weave Glide", Default = Config.movement.glide.enabled,
    Callback = function(v) Config.movement.glide.enabled = v end })
Options.glide_speed = GL:AddSlider("glide_speed", { Text = "Glide Speed", Default = Config.movement.glide.speed,
    Min = 12, Max = 20, Rounding = 0,
    Callback = function(v) Config.movement.glide.speed = v end })

local WK = Tabs.Movement:AddRightGroupbox("Movement")
Options.walk_enabled = WK:AddToggle("walk_enabled", { Text = "Walkspeed", Default = Config.movement.walkSpeed.enabled,
    Callback = function(v) Config.movement.walkSpeed.enabled = v end })
Options.walk_speed = WK:AddSlider("walk_speed", { Text = "Walkspeed Value", Default = Config.movement.walkSpeed.value,
    Min = 16, Max = 100, Rounding = 0,
    Callback = function(v) Config.movement.walkSpeed.value = v end })
Options.heavyBoost = WK:AddToggle("heavyBoost", { Text = "Heavy Booster", Default = Config.movement.heavyBoost,
    Callback = function(v) Config.movement.heavyBoost = v end })

local SE = Tabs.Movement:AddRightGroupbox("Sensitivity")
Options.sens_enabled = SE:AddToggle("sens_enabled", { Text = "Custom Sensitivity", Default = Config.sensitivity.enabled,
    Callback = function(v) Config.sensitivity.enabled = v; if ApplySensitivity then ApplySensitivity() end end })
Options.sens_value = SE:AddSlider("sens_value", { Text = "Multiplier", Default = Config.sensitivity.value,
    Min = 0.20, Max = 3.00, Rounding = 2,
    Callback = function(v) Config.sensitivity.value = v; if ApplySensitivity then ApplySensitivity() end end })

-- =========================== VISUALS TAB ===================================
local CR = Tabs.Visuals:AddLeftGroupbox("Crosshair")
Options.cross_enabled = CR:AddToggle("cross_enabled", { Text = "Crosshair", Default = Config.crosshair.enabled,
    Callback = function(v) Config.crosshair.enabled = v; if RebuildCrosshair then RebuildCrosshair() end end })
Options.cross_size = CR:AddSlider("cross_size", { Text = "Size", Default = Config.crosshair.size, Min = 4, Max = 30, Rounding = 0,
    Callback = function(v) Config.crosshair.size = v; if RebuildCrosshair then RebuildCrosshair() end end })
Options.cross_thick = CR:AddSlider("cross_thick", { Text = "Thickness", Default = Config.crosshair.thickness, Min = 1, Max = 6, Rounding = 0,
    Callback = function(v) Config.crosshair.thickness = v; if RebuildCrosshair then RebuildCrosshair() end end })
Options.cross_gap = CR:AddSlider("cross_gap", { Text = "Gap", Default = Config.crosshair.gap, Min = 0, Max = 20, Rounding = 0,
    Callback = function(v) Config.crosshair.gap = v; if RebuildCrosshair then RebuildCrosshair() end end })
Options.cross_dot = CR:AddToggle("cross_dot", { Text = "Center Dot", Default = Config.crosshair.dot,
    Callback = function(v) Config.crosshair.dot = v; if RebuildCrosshair then RebuildCrosshair() end end })

local TR = Tabs.Visuals:AddRightGroupbox("Character Transparency")
Options.trans_enabled = TR:AddToggle("trans_enabled", { Text = "Transparent Character", Default = Config.transparency.enabled,
    Callback = function(v) Config.transparency.enabled = v; if ApplyTransparency then ApplyTransparency(LP.Character) end end })
Options.trans_level = TR:AddSlider("trans_level", { Text = "Transparency Level", Default = Config.transparency.level,
    Min = 0.5, Max = 1.0, Rounding = 2,
    Callback = function(v) Config.transparency.level = v
        if Config.transparency.enabled and ApplyTransparency then ApplyTransparency(LP.Character) end
    end })

-- =========================== MISC TAB ======================================
local DG = Tabs.Misc:AddLeftGroupbox("Dodge")
Options.noStun = DG:AddToggle("noStun", { Text = "Anti Weave Stun", Default = Config.dodge.noStun,
    Callback = function(v) Config.dodge.noStun = v end })
Options.hitThrough = DG:AddToggle("hitThrough", { Text = "Hit Through Weave", Default = Config.dodge.hitThrough,
    Callback = function(v) Config.dodge.hitThrough = v end })

local LR = Tabs.Misc:AddRightGroupbox("Long Range")
Options.lr_enabled = LR:AddToggle("lr_enabled", { Text = "Long Range", Default = Config.longRange.enabled,
    Callback = function(v) Config.longRange.enabled = v end })

local modeButton
modeButton = LR:AddButton({
    Text = "Mode: " .. Config.longRange.mode,
    Func = function()
        Config.longRange.mode = (Config.longRange.mode == "position") and "midpoint" or "position"
        if modeButton and modeButton.SetText then
            pcall(function() modeButton:SetText("Mode: " .. Config.longRange.mode) end)
        end
    end,
})

Options.lr_radius = LR:AddSlider("lr_radius", { Text = "Max Radius", Default = Config.longRange.maxRadius,
    Min = 10, Max = 15.2, Rounding = 1,
    Callback = function(v) Config.longRange.maxRadius = math.min(v, 15.2) end })

local CS = Tabs.Misc:AddLeftGroupbox("Cosmetics")
Options.headless = CS:AddToggle("headless", { Text = "Headless", Default = Config.headless,
    Callback = function(v) Config.headless = v; if HeadlessToggle then HeadlessToggle(v) end end })
Options.philly = CS:AddToggle("philly", { Text = "Philly Style", Default = Config.philly,
    Callback = function(v) Config.philly = v; if PhillyToggle then PhillyToggle(v) end end })
Options.lowGraphics = CS:AddToggle("lowGraphics", { Text = "Low Graphics", Default = Config.lowGraphics,
    Callback = function(v) Config.lowGraphics = v; if LowGraphicsToggle then LowGraphicsToggle(v) end end })
Options.stretchRes = CS:AddToggle("stretchRes", { Text = "Stretch Resolution", Default = Config.stretchResolution,
    Callback = function(v) Config.stretchResolution = v; if StretchToggle then StretchToggle(v) end end })
Options.stretchAspect = CS:AddSlider("stretchAspect", { Text = "Stretch Aspect", Default = Config.stretchAspect,
    Min = 0.35, Max = 1.00, Rounding = 2,
    Callback = function(v) Config.stretchAspect = v; if SetStretchAspect then SetStretchAspect(v) end end })

local DN = Tabs.Misc:AddRightGroupbox("Damage Numbers")
Options.dmgNums = DN:AddToggle("dmgNums", { Text = "Damage Numbers", Default = Config.damageNumbers,
    Callback = function(v) Config.damageNumbers = v end })
Options.swingWindow = DN:AddSlider("swingWindow", { Text = "Number Lifetime", Default = Config.damageSwingWindow,
    Min = 0.30, Max = 2.00, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.damageSwingWindow = v end })

-- =========================== CONFIG TAB ====================================
local CFG = Tabs.Misc:AddLeftGroupbox("Configs")
local cfgNames = listConfigs()
local cfgValues = (#cfgNames > 0) and cfgNames or { "(none)" }
local typedName = ""
SelectedConfig = cfgNames[1]

local cfgDropdown
cfgDropdown = CFG:AddDropdown("cfg_list", {
    Text = "Saved Config",
    Values = cfgValues,
    Callback = function(v)
        if v and v ~= "(none)" then SelectedConfig = v end
    end,
})
if cfgDropdown and cfgDropdown.SetValue then
    pcall(function() cfgDropdown:SetValue(cfgValues[1]) end)
end

-- Obsidian has no AddTextbox; the text input is AddInput.
Options.cfg_name = CFG:AddInput("cfg_name", {
    Text = "Config Name",
    Placeholder = "type a name",
    Default = "",
    Callback = function(v) typedName = tostring(v or "") end,
})

local function refreshDropdown()
    local names = listConfigs()
    if #names == 0 then names = { "(none)" } end
    if cfgDropdown and cfgDropdown.SetValues then
        pcall(function() cfgDropdown:SetValues(names) end)
    elseif cfgDropdown and cfgDropdown.RefreshPool then
        pcall(function() cfgDropdown:RefreshPool() end)
    end
end

local function notify(msg)
    if not (Library and Library.Notify) then return end
    pcall(function()
        Library:Notify({ Title = "YSL", Description = tostring(msg), Time = 3 })
    end)
end

CFG:AddButton({ Text = "Save", Func = function()
    local name = sanitizeName(typedName ~= "" and typedName or SelectedConfig)
    if not name then notify("Enter a config name"); return end
    local ok, err = writeConfig(name)
    if ok then
        SelectedConfig = name
        refreshDropdown()
        notify("Saved: " .. name)
    else
        notify("Save failed: " .. tostring(err))
    end
end })

CFG:AddButton({ Text = "Load", Func = function()
    local name = sanitizeName(SelectedConfig or typedName)
    if not name then notify("Pick a config first"); return end
    local data, err = readConfig(name)
    if not data then notify("Load failed: " .. tostring(err)); return end
    deepApply(Config, data)
    if ApplyAllConfig then ApplyAllConfig() end
    notify("Loaded: " .. name)
end })

CFG:AddButton({ Text = "Delete", Func = function()
    local name = sanitizeName(SelectedConfig or typedName)
    if not name then notify("Pick a config first"); return end
    if typeof(delfile) == "function" then pcall(delfile, configPath(name)) end
    notify("Deleted: " .. name)
    refreshDropdown()
end })

CFG:AddButton({ Text = "Refresh", Func = function() refreshDropdown() end })

local CFG2 = Tabs.Misc:AddRightGroupbox("Autoload")
CFG2:AddButton({ Text = "Set Autoload", Func = function()
    local name = sanitizeName(SelectedConfig or typedName)
    if not name then notify("Pick a config first"); return end
    if not hasFS() then notify("No file API"); return end
    ensureFolder("YSL")
    pcall(writefile, AUTOLOAD_FILE, name)
    notify("Autoload set: " .. name)
end })

CFG2:AddButton({ Text = "Clear Autoload", Func = function()
    if typeof(delfile) == "function" then pcall(delfile, AUTOLOAD_FILE) end
    notify("Autoload cleared")
end })

CFG2:AddButton({ Text = "Run Doctor", Func = function()
    if RunDoctor then RunDoctor() else notify("Features never loaded - check console") end
end })

local SPY = Tabs.Misc:AddLeftGroupbox("Remote Spy")
SPY:AddButton({ Text = "Capture 10s (punch once)", Func = function()
    if StartSpy then StartSpy(10) else notify("Features never loaded") end
end })
SPY:AddButton({ Text = "Capture 30s", Func = function()
    if StartSpy then StartSpy(30) else notify("Features never loaded") end
end })
SPY:AddButton({ Text = "Dump Spy Log", Func = function()
    if DumpSpy then DumpSpy() else notify("Features never loaded") end
end })

-- =========================== FEATURE CODE ==================================
local featureOk, featureErr = pcall(function()

local Remotes, Combat, AttackState, HitWindow, Hitboxes, CharacterController, DataController, Classes
local Active = { Weaving = false, OpenFrame = false, CanAttack = false, Seq = 0, CurrentM1 = nil }
local HITBOX_MAX = 15.2
local SERVER_REACH = 5.8
local watchedChar, lastStun = nil, false
local lastStunClearAt = 0
local lastCounterAt = 0
local suppressHookReport = false
local dodgePending = setmetatable({}, { __mode = "k" })
local origHWStart, origHBStart, origHitReportFire
local learnedHitArgs = nil  -- argument shape captured from the real hit remote
local counterSetupChar, counterConn
local budget = { tokens = 12, rate = 10, cap = 12, last = os.clock() }

local function syncBudgets()
    budget.rate = Config.budgetRate or 10
    budget.cap = Config.budgetCap or 12
    if budget.tokens > budget.cap then budget.tokens = budget.cap end
end

local function takeToken()
    local now = os.clock()
    budget.tokens = math.min(budget.cap, budget.tokens + (now - budget.last) * budget.rate)
    budget.last = now
    if budget.tokens < 1 then return false end
    budget.tokens = budget.tokens - 1
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
                if d <= cap then out[#out + 1] = { player = p, char = tch, hum = hum, root = hrp, dist = d } end
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

-- Dispatch a remote whether it is a real Instance or a wrapper table.
local function fireRemote(remote, ...)
    if not remote then return false end
    local args = table.pack(...)
    if typeof(remote) == "Instance" then
        local method = nil
        if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then method = "FireServer"
        elseif remote:IsA("RemoteFunction") then method = "InvokeServer" end
        if not method then return false end
        return pcall(function() remote[method](remote, table.unpack(args, 1, args.n)) end)
    end
    if type(remote.Fire) == "function" then
        return pcall(function() remote:Fire(table.unpack(args, 1, args.n)) end)
    end
    if type(remote.FireServer) == "function" then
        return pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
    end
    return false
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

-- =========================== WEAVE DETECTION ===============================

local WEAVE_IDS = { ["17819683172"] = true, ["17819688197"] = true, ["17819691229"] = true, ["17819695187"] = true }

local function animPlayingNow()
    local ch = LP.Character; if not ch then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator"); if not animator then return false end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or not tracks then return false end
    for _, t in ipairs(tracks) do
        local anim = t.Animation
        if anim then
            local id = tostring(anim.AnimationId or ""):match("(%d+)")
            if id and WEAVE_IDS[id] then return true end
        end
    end
    return false
end

-- Pure read: does NOT touch the auto-weave gate timers.
local function weaveActiveNow()
    if Active and Active.Weaving == true then return true end
    if CharacterController then
        local ok, w = pcall(function() return CharacterController:Is("Weaving") end)
        if ok and w == true then return true end
    end
    return animPlayingNow()
end

local aw = { cycleActive = false, cycleTask = nil, cycles = 0, lastAnimAt = 0, lastStateTrueAt = 0, gateOpenUntil = 0 }

local function weavingNow()
    local now = os.clock()
    local open = false
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
    if open then
        aw.gateOpenUntil = now + 0.20
        return true
    end
    return now < aw.gateOpenUntil
end

-- =========================== DAMAGE NUMBERS ================================
-- No Part is created: the BillboardGui hangs off the target part, so nothing
-- can be left behind in the world (or inside your own character).

local function floatDamage(rootPart, amount)
    if not Config.damageNumbers then return end
    if not rootPart or not rootPart.Parent then return end
    local gui = Instance.new("BillboardGui")
    gui.Name = "YSL_Dmg"
    gui.Size = UDim2.fromOffset(90, 34)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.ExtentsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
    gui.Parent = rootPart

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Text = tostring(amount)
    label.TextColor3 = Color3.fromRGB(255, 92, 92)
    label.TextStrokeTransparency = 0.4
    label.Parent = gui

    local life = Config.damageSwingWindow
    pcall(function()
        TweenService:Create(gui, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            ExtentsOffsetWorldSpace = Vector3.new(0, 3.9, 0),
        }):Play()
    end)
    task.delay(life, function() pcall(function() gui:Destroy() end) end)
end

-- =========================== COMBAT ========================================

-- Attack sequence: the real one when AttackState resolved, otherwise a local
-- counter. Sending a constant 0 gets rejected by servers that track sequence.
local function currentSeq()
    if AttackState and AttackState.Active then return Active.Seq end
    Active.Seq = (Active.Seq or 0) + 1
    return Active.Seq
end

local function reportOnce(seq, target)
    if not Combat or not Combat.HitReport then return false end
    if not target or not target.root or not target.root:IsA("BasePart") then return false end
    if Config.hitbox.airOnly then
        local hum = target.hum
        if hum and hum:GetState() ~= Enum.HumanoidStateType.Freefall then return false end
    end
    local limit = HITBOX_MAX
    if Config.longRange.enabled then
        limit = math.min(HITBOX_MAX, Config.longRange.maxRadius or HITBOX_MAX)
    end
    if target.dist and target.dist > limit then return false end
    if not takeToken() then return false end

    local hum = target.hum
    local before = (hum and hum.Health) or nil
    local pos = target.root.Position
    if Config.longRange.enabled then pos = spoofPos(target) end

    local ok
    if typeof(Combat.HitReport) == "Instance" and learnedHitArgs then
        -- Replay the real call shape, swapping in this target's part and position.
        local out, n = {}, 0
        for i = 1, learnedHitArgs.n do
            local v = learnedHitArgs[i]
            local t = typeof(v)
            if t == "Instance" then
                local okp, isPart = pcall(function() return v:IsA("BasePart") end)
                out[i] = (okp and isPart) and target.root or v
            elseif t == "Vector3" then
                out[i] = pos
            else
                out[i] = v
            end
            n = i
        end
        ok = fireRemote(Combat.HitReport, table.unpack(out, 1, n))
    else
        ok = fireRemote(Combat.HitReport, seq, target.root, pos)
    end
    if not ok then return false end

    STATS.hits = STATS.hits + 1
    -- Real damage: difference in the target's own health, not a fake counter.
    if before then
        task.delay(0.18, function()
            if hum and hum.Parent then
                local dmg = math.floor(before - hum.Health + 0.5)
                if dmg > 0 then floatDamage(target.root, dmg) end
            end
        end)
    end
    return true
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
                if dealing(t) and reportOnce(seq, t) then
                    STATS.silentHits = STATS.silentHits + 1
                end
            end
        end)
    end
end

-- Fallback attack trigger: if the game's HitWindow never resolves, M1/touch
-- still drives hitbox and silent hits.
local function attackTrigger()
    if not (Config.hitbox.enabled or Config.damage.autoConnect) then return end
    if not Combat or not Combat.HitReport then return end
                        local seq = currentSeq()
    local targets = collect(Config.damage.autoConnect and Config.damage.connectRange or Config.hitbox.radius)
    if #targets == 0 then return end
    task.delay(0.02, function()
        local hitT = {}
        for _, t in ipairs(targets) do
            if t.dist <= HITBOX_MAX and reportOnce(seq, t) then table.insert(hitT, t) end
        end
        if #hitT > 0 then silentHitMulti(seq, hitT) end
    end)
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
                                local seq = currentSeq()
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

-- =========================== WEAVE BYPASS (hit while weaving) ==============
-- Shared by Weave Combat and Killaura. Never touches the auto-weave loop.

local pendingRestores = 0

local function weaveBypass(fn)
    local wasWeaving = (Active and Active.Weaving == true) or weaveActiveNow()
    pcall(function() Active.Weaving = false end)
    pcall(function() Active.CanAttack = true end)
    pcall(function() Active.OpenFrame = true end)
    pendingRestores = pendingRestores + 1
    local ok = pcall(fn)
    task.delay(Config.weaveHit.restoreDelay or 0.06, function()
        pendingRestores = pendingRestores - 1
        if pendingRestores > 0 then return end
        pcall(function() Active.Weaving = wasWeaving end)
        if wasWeaving and Config.weaveHit.reassert and Combat and Combat.Weave then
            fireRemote(Combat.Weave, true)
        end
        aw.lastAnimAt = os.clock()
    end)
    return ok
end

local wh = { running = false, task = nil }
WeaveHitSet = function(on)
    wh.running = on
    if not on then
        if wh.task then pcall(function() task.cancel(wh.task) end) wh.task = nil end
        return
    end
    if wh.task then return end
    wh.task = task.spawn(function()
        while wh.running do
            if Config.weaveHit.enabled and weaveActiveNow() and Combat and Combat.HitReport then
                local targets = collect(Config.hitbox.radius)
                if #targets > 0 then
                    local seq = currentSeq()
                    weaveBypass(function()
                        for _, t in ipairs(targets) do
                            if dealing(t) then reportOnce(seq, t) break end
                        end
                    end)
                end
                task.wait(math.max(0.03, Config.weaveHit.window))
            else
                task.wait(0.05)
            end
        end
        wh.task = nil
    end)
end

local ka = { running = false, task = nil }
KillAuraSet = function(on)
    ka.running = on
    if not on then
        if ka.task then pcall(function() task.cancel(ka.task) end) ka.task = nil end
        return
    end
    if ka.task then return end
    ka.task = task.spawn(function()
        while ka.running do
            if Config.killaura.enabled and Combat and Combat.HitReport then
                local targets = collect(Config.killaura.radius)
                local n = math.min(#targets, math.floor(Config.killaura.maxTargets or 1))
                if n > 0 then
                    local seq = currentSeq()
                    local function hitAll()
                        for i = 1, n do
                            local t = targets[i]
                            if dealing(t) then reportOnce(seq, t) end
                        end
                    end
                    if Config.killaura.weaveSync and weaveActiveNow() then
                        weaveBypass(hitAll)
                    else
                        hitAll()
                    end
                end
                task.wait(math.max(0.03, Config.killaura.interval))
            else
                task.wait(0.1)
            end
        end
        ka.task = nil
    end)
end

-- =========================== COUNTER STUN ==================================

local function setupCounterStun(ch)
    if counterSetupChar == ch then return end
    if counterConn then pcall(function() counterConn:Disconnect() end); counterConn = nil end
    counterSetupChar = ch
    local hum = ch and ch:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local lastHP = hum.Health
    counterConn = hum.HealthChanged:Connect(function(newHP)
        local previous = lastHP
        lastHP = newHP
        if not CounterEnabled then return end
        if newHP >= previous then return end
        if os.clock() - lastCounterAt < 0.1 then return end
        lastCounterAt = os.clock()
        if CounterClear then
            pcall(function() ch:SetAttribute("WeaveStun", false) end)
            stopStunAnims()
        end
        if CounterAssert and Combat and Combat.Weave then
            fireRemote(Combat.Weave, true)
        end
        if CounterReturn and Combat and Combat.HitReport then
            local r = Config.hitbox.radius > 0 and Config.hitbox.radius or 7
            for _, t in ipairs(collect(r)) do
                if dealing(t) and reportOnce(currentSeq(), t) then
                    STATS.counterHits = STATS.counterHits + 1
                end
            end
        end
    end)
end

-- =========================== AUTO-WEAVE ====================================

local function gateOpen()
    if not Config.autoWeave.enabled then return false end
    if not Config.autoWeave.manualOnly then return true end
    return weavingNow()
end

local function awFire(state)
    if not Combat or not Combat.Weave then return end
    fireRemote(Combat.Weave, state)
end

autoWeaveStart = function()
    if aw.cycleActive then return end
    aw.cycleActive = true
    aw.cycleTask = task.spawn(function()
        while aw.cycleActive and (not Combat or not Combat.Weave) do task.wait(0.1) end
        while aw.cycleActive do
            if not Config.autoWeave.enabled then
                task.wait(0.1)
            elseif gateOpen() then
                awFire(false); awFire(true)
                task.wait(Config.autoWeave.hold)
                if Config.autoWeave.gap > 0 then task.wait(Config.autoWeave.gap) end
                aw.cycles = aw.cycles + 1
            else
                task.wait(0.02)
            end
        end
    end)
end

autoWeaveStop = function()
    aw.cycleActive = false
    if aw.cycleTask then pcall(function() task.cancel(aw.cycleTask) end) aw.cycleTask = nil end
    awFire(false)
end

-- =========================== TRANSPARENCY ==================================

local transOriginal = setmetatable({}, { __mode = "k" })

local function setPartAlpha(part, alpha)
    if alpha == nil then
        local orig = transOriginal[part]
        if orig == nil then orig = 0 end
        pcall(function() part.LocalTransparencyModifier = 0 end)
        pcall(function() part.Transparency = orig end)
    else
        if transOriginal[part] == nil then
            pcall(function() transOriginal[part] = part.Transparency end)
        end
        pcall(function() part.LocalTransparencyModifier = alpha end)
        pcall(function() part.Transparency = alpha end)
    end
end

ApplyTransparency = function(ch)
    if not ch then return end
    local alpha = nil
    if Config.transparency.enabled then alpha = Config.transparency.level end
    for _, part in ipairs(ch:GetDescendants()) do
        if part:IsA("BasePart") or part:IsA("Decal") or part:IsA("Texture") then
            setPartAlpha(part, alpha)
        end
    end
end

-- =========================== CROSSHAIR =====================================

local crosshairGui
RebuildCrosshair = function()
    if crosshairGui then pcall(function() crosshairGui:Destroy() end) crosshairGui = nil end
    if not Config.crosshair.enabled then return end
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    local g = Instance.new("ScreenGui")
    g.Name = "YSL_Cross"
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.DisplayOrder = 50
    g.Parent = pg
    crosshairGui = g

    local size = Config.crosshair.size
    local thick = Config.crosshair.thickness
    local gap = Config.crosshair.gap
    local cx = size + gap * 2

    local c = Instance.new("Frame")
    c.Size = UDim2.fromOffset(cx, cx)
    c.Position = UDim2.new(0.5, 0, 0.5, 0)
    c.AnchorPoint = Vector2.new(0.5, 0.5)
    c.BackgroundTransparency = 1
    c.BorderSizePixel = 0
    c.Parent = g

    local function arm(x, y, w, h)
        local f = Instance.new("Frame")
        f.Size = UDim2.fromOffset(w, h)
        f.Position = UDim2.fromOffset(x, y)
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        f.BorderSizePixel = 0
        f.Parent = c
    end
    local half = cx / 2
    arm(half, half - (gap + size / 2), thick, size)
    arm(half, half + (gap + size / 2), thick, size)
    arm(half - (gap + size / 2), half, size, thick)
    arm(half + (gap + size / 2), half, size, thick)
    if Config.crosshair.dot then
        local d = Instance.new("Frame")
        d.Size = UDim2.fromOffset(thick, thick)
        d.Position = UDim2.fromOffset(half, half)
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        d.BorderSizePixel = 0
        d.Parent = c
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = d
    end
end

-- =========================== SENSITIVITY ===================================
-- Mouse: native, exact. Touch: poke the PlayerModule camera controller if it
-- exposes a sensitivity field (Delta has the hooks needed for this path).

ApplySensitivity = function()
    local v = Config.sensitivity.enabled and Config.sensitivity.value or 1
    local applied = false
    pcall(function()
        if UserInputService.MouseDeltaSensitivity ~= nil then
            UserInputService.MouseDeltaSensitivity = v
            applied = true
        end
    end)
    if UserInputService.TouchEnabled then
        pcall(function()
            local ps = LP:FindFirstChild("PlayerScripts")
            local pm = ps and ps:FindFirstChild("PlayerModule")
            if not pm then return end
            local mod = require(pm)
            local ctrl = mod.activeCameraController
            local input = ctrl and ctrl.cameraInput
            if not input then return end
            for _, field in ipairs({ "mouseSensitivity", "touchSensitivity", "gamepadSensitivity" }) do
                if input[field] ~= nil then input[field] = v; applied = true end
            end
        end)
    end
    return applied
end

-- =========================== GLIDE =========================================

local glideBody = Instance.new("BodyVelocity")
glideBody.Name = "YSLGlide"
glideBody.MaxForce = Vector3.new(100000, 0, 100000)
glideBody.P = 8000
glideBody.Velocity = Vector3.zero
local glideOn = false

local function stopGlide()
    if not glideOn and not glideBody.Parent then return end
    glideOn = false
    glideBody.Velocity = Vector3.zero
    glideBody.Parent = nil
end

-- Only moves while you are actually weaving, and stops the frame the weave ends.
local function updateGlide(rp, hum)
    if not Config.movement.glide.enabled or not rp or not hum or hum.Health <= 0 then stopGlide(); return end
    if not weaveActiveNow() then stopGlide(); return end
    local mv = hum.MoveDirection
    if mv.Magnitude < 0.05 then
        local lk = rp.CFrame.LookVector; mv = Vector3.new(lk.X, 0, lk.Z)
    end
    if mv.Magnitude < 0.05 then stopGlide(); return end
    if glideBody.Parent ~= rp then glideBody.Parent = rp end
    glideBody.Velocity = mv.Unit * Config.movement.glide.speed
    glideOn = true
end

-- =========================== COSMETICS =====================================

local lightingBackup

local function applyHeadless(ch)
    if not ch then return end
    local h = ch:FindFirstChild("Head")
    if h then
        h.Transparency = 1
        local f = h:FindFirstChild("face")
        if f then f.Transparency = 1 end
    end
end

local function restoreHead(ch)
    if not ch then return end
    local h = ch:FindFirstChild("Head")
    if h then
        h.Transparency = 0
        local f = h:FindFirstChild("face")
        if f then f.Transparency = 0 end
    end
end

HeadlessToggle = function(on)
    Config.headless = on
    if on then applyHeadless(LP.Character) else restoreHead(LP.Character) end
end

PhillyToggle = function(on)
    Config.philly = on
    local ch = LP.Character; if not ch then return end
    if on then
        pcall(function() ch:SetAttribute("Style", "Philly") end)
    else
        local ok, real = pcall(function() return DataController and DataController:Get("Class") end)
        if ok and type(real) == "string" then pcall(function() ch:SetAttribute("Style", real) end) end
    end
end

LowGraphicsToggle = function(on)
    Config.lowGraphics = on
    if on then
        if not lightingBackup then
            lightingBackup = {
                GlobalShadows = Lighting.GlobalShadows,
                Brightness = Lighting.Brightness,
                FogStart = Lighting.FogStart,
                FogEnd = Lighting.FogEnd,
                Ambient = Lighting.Ambient,
            }
        end
        pcall(function()
            Lighting.GlobalShadows = false
            Lighting.Brightness = 2
            Lighting.FogStart = 0
            Lighting.FogEnd = 100000
            Lighting.Ambient = Color3.fromRGB(120, 120, 120)
        end)
    elseif lightingBackup then
        local b = lightingBackup
        lightingBackup = nil
        pcall(function()
            Lighting.GlobalShadows = b.GlobalShadows
            Lighting.Brightness = b.Brightness
            Lighting.FogStart = b.FogStart
            Lighting.FogEnd = b.FogEnd
            Lighting.Ambient = b.Ambient
        end)
    end
end

local stretchConn
SetStretchAspect = function(v) Config.stretchAspect = v end

StretchToggle = function(on)
    Config.stretchResolution = on
    if stretchConn then stretchConn:Disconnect(); stretchConn = nil end
    if not on then return end
    local cam = workspace.CurrentCamera; if not cam then return end
    stretchConn = RunService.RenderStepped:Connect(function()
        if not Config.stretchResolution then return end
        local a = Config.stretchAspect
        local res = CFrame.new(0, 0, 0, 1, 0, 0, 0, a, 0, 0, 0, 1)
        cam.CFrame = cam.CFrame * res
    end)
end

-- =========================== STUN / WATCH ==================================

local function applyStunBypass()
    if not Config.dodge.noStun then return end
    local ch = watchedChar; if not ch or not ch.Parent then return end
    if ch:GetAttribute("WeaveStun") == true then
        lastStunClearAt = os.clock()
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

-- =========================== HEARTBEAT =====================================

local lastTransAt = 0

RunService.Heartbeat:Connect(function()
    local ch = LP.Character
    watchChar()
    applyStunBypass()

    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local rp = ch and ch:FindFirstChild("HumanoidRootPart")
    updateGlide(rp, hum)

    if Config.autoWeave.enabled and aw.cycleActive then
        pcall(function() Active.CanAttack = true end)
        pcall(function() Active.OpenFrame = true end)
    end

    if ch and Config.dodge.noStun then
        if ch:GetAttribute("WeaveStun") == true then
            pcall(function() ch:SetAttribute("WeaveStun", false) end)
            stopStunAnims()
            lastStunClearAt = os.clock()
        end
        if ch:GetAttribute("Shoved") == true then
            pcall(function() ch:SetAttribute("Shoved", false) end)
        end
    end

    if ch and Config.transparency.enabled then
        local now = os.clock()
        if now - lastTransAt > 0.2 then
            lastTransAt = now
            ApplyTransparency(ch)
        end
    end

    if hum then
        if Config.movement.walkSpeed.enabled then hum.WalkSpeed = Config.movement.walkSpeed.value end
        if Config.movement.heavyBoost and ch then pcall(function() ch:SetAttribute("Heavy", true) end) end
    end
end)

-- =========================== APPLY ALL =====================================
-- Single entry point used by Load Config, so a load lands everywhere the
-- widget callbacks would have put it.

ApplyAllConfig = function()
    CounterEnabled = Config.counter.enabled
    CounterReturn = Config.counter.returnFire
    CounterClear = Config.counter.clearStun
    CounterAssert = Config.counter.assert

    for _, entry in ipairs(SyncList) do
        local el = Options[entry[1]]
        local v = pathGet(Config, entry[2])
        if el and v ~= nil and el.SetValue then
            pcall(function() el:SetValue(v) end)
        end
    end

    if Config.autoWeave.enabled then autoWeaveStart() else autoWeaveStop() end
    if WeaveHitSet then WeaveHitSet(Config.weaveHit.enabled) end
    if KillAuraSet then KillAuraSet(Config.killaura.enabled) end
    ApplyTransparency(LP.Character)
    RebuildCrosshair()
    ApplySensitivity()
    HeadlessToggle(Config.headless)
    PhillyToggle(Config.philly)
    LowGraphicsToggle(Config.lowGraphics)
    StretchToggle(Config.stretchResolution)
    if LP.Character then setupCounterStun(LP.Character) end
    notify("Config applied")
end

-- =========================== DISCOVERY ====================================
-- The hardcoded module paths were guesses. Scan what the game actually ships,
-- resolve by name, and fall back to the old paths only if the scan misses.

local Discovered = { modules = {}, remotes = {} }

local function scanTree(root, depth)
    if depth <= 0 then return end
    local ok, kids = pcall(function() return root:GetChildren() end)
    if not ok or type(kids) ~= "table" then return end
    for _, inst in ipairs(kids) do
        if inst:IsA("ModuleScript") then
            if not Discovered.modules[inst.Name] then Discovered.modules[inst.Name] = inst end
        elseif inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
            Discovered.remotes[inst.Name] = inst
        elseif not inst:IsA("BasePart") and not inst:IsA("LuaSourceContainer") and not inst:IsA("Camera") then
            scanTree(inst, depth - 1)
        end
    end
end

local function moduleLike(name)
    local exact = Discovered.modules[name]
    if exact then return exact end
    local want = string.lower(name)
    for n, m in pairs(Discovered.modules) do
        if string.lower(n) == want then return m end
    end
    return nil
end

local function remoteLike(keys)
    for _, k in ipairs(keys) do
        for name, r in pairs(Discovered.remotes) do
            if string.lower(name) == string.lower(k) then return r, name end
        end
    end
    for _, k in ipairs(keys) do
        for name, r in pairs(Discovered.remotes) do
            if string.find(string.lower(name), string.lower(k), 1, true) then return r, name end
        end
    end
    return nil
end

local function resolveModule(name, path, timeout)
    local m = moduleLike(name)
    if m then
        local ok, mod = pcall(require, m)
        if ok and mod ~= nil then return mod end
    end
    if path then return safeRequire(path, timeout or 1.5) end
    return nil
end

local function doctorLines()
    local modCount, remCount = 0, 0
    local remNames, modNames = {}, {}
    for n in pairs(Discovered.modules) do modCount = modCount + 1; modNames[#modNames + 1] = n end
    for n in pairs(Discovered.remotes) do remCount = remCount + 1; remNames[#remNames + 1] = n end
    table.sort(modNames)
    table.sort(remNames)

    local L = {}
    L[#L + 1] = string.format("modules=%d remotes=%d", modCount, remCount)
    L[#L + 1] = string.format("Combat=%s Weave=%s HitReport=%s",
        tostring(Combat ~= nil),
        tostring(Combat ~= nil and Combat.Weave ~= nil),
        tostring(Combat ~= nil and Combat.HitReport ~= nil))
    L[#L + 1] = string.format("AttackState=%s HitWindow=%s Hitboxes=%s CharCtrl=%s DataCtrl=%s",
        tostring(AttackState ~= nil), tostring(HitWindow ~= nil), tostring(Hitboxes ~= nil),
        tostring(CharacterController ~= nil), tostring(DataController ~= nil))
    L[#L + 1] = "remotes: " .. (#remNames > 0 and table.concat(remNames, ", ") or "(none)")
    L[#L + 1] = "modules: " .. (#modNames > 0 and table.concat(modNames, ", ") or "(none)")
    return L
end

RunDoctor = function()
    local L = doctorLines()
    for _, line in ipairs(L) do print("[YSL] " .. line) end
    if hasFS() then
        ensureFolder("YSL")
        pcall(writefile, "YSL/doctor.txt", table.concat(L, "\n"))
        print("[YSL] wrote YSL/doctor.txt")
    end
    notify("Doctor: " .. L[1] .. " | " .. L[2])
end

-- =========================== REMOTE SPY ====================================
-- You cannot enumerate what the server hides, but you can watch the client fire
-- it. Hooking __namecall captures the real instance and its arguments, then
-- binds the two combat remotes by their argument shape.

local spy = { capturing = false, installed = false, seen = {}, hit = nil, weave = nil }

local function spyRecord(inst, ...)
    local okn, full = pcall(function() return inst:GetFullName() end)
    if not okn or type(full) ~= "string" then full = tostring(inst.Name) end
    local args = table.pack(...)
    local sig, hasPart, hasVec, onlyBool = {}, false, false, (args.n == 1)
    for i = 1, args.n do
        local t = typeof(args[i])
        sig[i] = t
        if t == "Instance" then
            local okp, is = pcall(function() return args[i]:IsA("BasePart") end)
            if okp and is then hasPart = true end
        elseif t == "Vector3" then
            hasVec = true
        elseif t ~= "boolean" then
            onlyBool = false
        end
    end
    local key = full .. "|n" .. args.n
    if not spy.seen[key] then
        spy.seen[key] = true
        local line = string.format("%s [%s] n=%d (%s)", full, inst.ClassName, args.n, table.concat(sig, ","))
        spyLog[#spyLog + 1] = line
        print("[YSL spy] " .. line)
    end
    if inst:IsA("RemoteEvent") then
        if hasPart and hasVec and not spy.hit then
            spy.hit = inst
            learnedHitArgs = args
        end
        if onlyBool and not spy.weave then spy.weave = inst end
    end
end

StartSpy = function(seconds)
    seconds = tonumber(seconds) or 10
    if not spy.installed then
        if hookmetamethod and getnamecallmethod and newcclosure then
            local okh, err = pcall(function()
                local old
                old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                    if spy.capturing then
                        local m = getnamecallmethod()
                        if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
                            pcall(spyRecord, self, ...)
                        end
                    end
                    return old(self, ...)
                end))
            end)
            if okh then
                spy.installed = true
                print("[YSL] spy hook installed")
            else
                warn("[YSL] spy hook failed: " .. tostring(err))
            end
        else
            warn("[YSL] hookmetamethod unavailable - using keyword match only")
        end
    end
    spy.capturing = true
    notify(string.format("Capturing %ds - punch someone now", seconds))
    task.delay(seconds, function()
        spy.capturing = false
        if spy.hit then
            Combat = Combat or {}
            Combat.HitReport = spy.hit
            print("[YSL] learned HitReport -> " .. spy.hit:GetFullName())
        end
        if spy.weave then
            Combat = Combat or {}
            Combat.Weave = spy.weave
            print("[YSL] learned Weave -> " .. spy.weave:GetFullName())
        end
        notify(string.format("Capture done: %d unique calls", #spyLog))
    end)
end

DumpSpy = function()
    if #spyLog == 0 then
        notify("Spy log empty - run a capture first")
        return
    end
    for _, l in ipairs(spyLog) do print("[YSL spy] " .. l) end
    if hasFS() then
        ensureFolder("YSL")
        local ok = pcall(writefile, "YSL/spy.txt", table.concat(spyLog, "\n"))
        notify(ok and "Wrote YSL/spy.txt" or "Write failed")
    else
        notify(#spyLog .. " calls - see console")
    end
end

-- =========================== INIT ==========================================

task.spawn(function()
    task.wait(1.5)
    local ok, err = pcall(function()
        -- Sweep anything an earlier version of this script left behind: stray
        -- marker parts (the grey box), stale glide bodies, duplicate crosshairs.
        local function sweep(parent)
            for _, inst in ipairs(parent:GetChildren()) do
                local n = inst.Name
                if n == "YSL_Marker" or (n == "YSLGlide" and not inst:IsA("BodyVelocity"))
                    or n == "YSL_Dmg" or n == "YSL_MarkerGui" then
                    pcall(function() inst:Destroy() end)
                end
            end
        end
        sweep(workspace)
        if LP.Character then sweep(LP.Character) end
        local pg = LP:FindFirstChild("PlayerGui")
        if pg then
            for _, inst in ipairs(pg:GetChildren()) do
                if inst.Name == "YSL_Cross" then pcall(function() inst:Destroy() end) end
            end
        end

        -- Every remote the client can fire must exist in the replicated tree,
        -- so getDescendants on game sees all of them. No guessing by folder.
        local okAll, all = pcall(function() return game:GetDescendants() end)
        if okAll and type(all) == "table" then
            for _, inst in ipairs(all) do
                if inst:IsA("ModuleScript") then
                    if not Discovered.modules[inst.Name] then Discovered.modules[inst.Name] = inst end
                elseif inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
                    Discovered.remotes[inst.Name] = inst
                end
            end
        else
            scanTree(ReplicatedStorage, 8)
        end
        print(string.format("[YSL] discovered %d modules, %d remotes",
            (function() local n = 0 for _ in pairs(Discovered.modules) do n = n + 1 end return n end)(),
            (function() local n = 0 for _ in pairs(Discovered.remotes) do n = n + 1 end return n end)()))

        Remotes = resolveModule("Remotes", { "Shared", "Net", "Remotes" }, 2)
        if Remotes and Remotes.Client then
            local okc, c = pcall(function() return Remotes.Client("CombatService") end)
            if okc then Combat = c end
        end
        AttackState         = resolveModule("AttackState", { "Client", "Combat", "AttackState" }, 2)
        HitWindow           = resolveModule("HitWindow", { "Client", "Combat", "HitWindow" }, 2)
        Hitboxes            = resolveModule("Hitboxes", { "Client", "Combat", "Hitboxes" }, 2)
        CharacterController = resolveModule("CharacterController", { "Client", "Controllers", "CharacterController" }, 2)
        DataController      = resolveModule("DataController", { "Client", "Controllers", "DataController" }, 2)
        Classes             = resolveModule("Classes", { "Shared", "Config", "Classes" }, 1.5)

        -- If the service table never resolved, wire straight to the real remotes.
        if not Combat then Combat = {} end
        if not Combat.Weave then
            local r = remoteLike({ "weave", "weaving" })
            if r then Combat.Weave = r; print("[YSL] Weave -> " .. r.Name) end
        end
        if not Combat.HitReport then
            local r = remoteLike({ "hitreport", "hit", "damage", "strike", "swing", "punch", "attack", "combat" })
            if r then Combat.HitReport = r; print("[YSL] HitReport -> " .. r.Name) end
        end

        if AttackState and AttackState.Active then Active = AttackState.Active end
        origHWStart = HitWindow and HitWindow.Start
        origHBStart = Hitboxes and Hitboxes.Start

        if Combat and Combat.HitReport and type(Combat.HitReport.Fire) == "function"
            and hookfunction and newcclosure then
            origHitReportFire = Combat.HitReport.Fire
            Combat.HitReport.Fire = newcclosure(function(self, seq, root, pos, ...)
                if Config.dodge.hitThrough and not Config.longRange.enabled
                    and root and typeof(root) == "Instance" and root:IsA("BasePart") then
                    pos = root.Position
                end
                return origHitReportFire(self, seq, root, pos, ...)
            end)
            print("[YSL] HitReport hooked")
        end

        hookCombat()

        if not origHWStart then
            UserInputService.InputBegan:Connect(function(input, processed)
                if processed then return end
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    attackTrigger()
                end
            end)
            print("[YSL] no HitWindow path - input fallback active for hits")
        end

        if LP.Character then
            setupCounterStun(LP.Character)
            ApplyTransparency(LP.Character)
            if Config.headless then applyHeadless(LP.Character) end
        end

        LP.CharacterAdded:Connect(function(ch)
            task.wait(0.5)
            stopGlide()
            transOriginal = setmetatable({}, { __mode = "k" })
            watchedChar = nil
            counterSetupChar = nil
            if counterConn then pcall(function() counterConn:Disconnect() end); counterConn = nil end
            setupCounterStun(ch)
            if Config.headless then applyHeadless(ch) end
            if Config.philly then PhillyToggle(true) end
            ApplyTransparency(ch)
            if Config.crosshair.enabled then RebuildCrosshair() end
            ApplySensitivity()
        end)

        print("[YSL] Combat ready")
        RunDoctor()

        task.wait(1)
        local autoName = nil
        if hasFS() and typeof(isfile) == "function" and isfile(AUTOLOAD_FILE) then
            local rok, body = pcall(readfile, AUTOLOAD_FILE)
            if rok then autoName = sanitizeName(body) end
        end
        if autoName then
            local data, lerr = readConfig(autoName)
            if data then
                deepApply(Config, data)
                ApplyAllConfig()
                print("[YSL] autoloaded: " .. autoName)
            else
                warn("[YSL] autoload failed: " .. tostring(lerr))
            end
        end
    end)
    if not ok then warn("[YSL] init: " .. tostring(err)) end
end)

syncBudgets()

end) -- feature pcall

if not featureOk then warn("[YSL] FEATURE ERROR: " .. tostring(featureErr)) end
print("[YSL] ready")
