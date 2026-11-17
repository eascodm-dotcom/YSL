--[[
    YSL FINAL SHOWDOWN
    discord.gg/yslrolling

    UI: Obsidian.
    v31:
      - auto-weave back to your original: awFire(false); awFire(true), wait hold,
        wait gap, Heartbeat forcing CanAttack/OpenFrame. No bucket, no hold floor,
        hold default 0.22, slider min 0.10.
      - grey box kill from v30 stays.
    v30:
      - grey box identified: the game clones Assets.VFX.WeaveHighlight into a
        character, renames it WeaveHIGHLIGHT and destroys it after 0.4s. The old
        sweep only killed real Highlights and parts under Attachments, so a part
        named WeaveHIGHLIGHT survived. Now killed by name, every 0.1s, on every
        character.
      - weave cadence limited by the game's own contract: CombatService.Weave is
        10/s burst 10, so a 2-call cycle at 0.22s hold sat right on the ceiling.
        Hold floor is now 0.25s plus a dedicated 8/s bucket.
    v29:
      - hits now use the exact wire shape RobloxSpy logged from the game:
        HitReport:FireServer(seq, <hit part>, <world position of that part>).
        Previously the script sent HumanoidRootPart + its position.
      - scripted path (no HitWindow hook) fires Swing:FireServer(seq, "Attack",
        <limb>) first, matching the server's swing-then-hit order.
    v28:
      - autoload no longer leaves the Auto-Weave toggle showing ON while the
        feature is stopped (it now flips the toggle back to OFF).
      - auto-weave says on screen when Combat.Weave is nil instead of idling silently.
    v27:
      - headless: replaced with ScriptBlox logic.
        applyHeadless uses ch:WaitForChild("Head", math.random(6,11)) then
        sets Head.Transparency = 1 and face.Transparency = 1.
        restoreHead sets both back to 0 on toggle off.
        CharacterAdded reapplies 0.33s after spawn when headless is on.
      - everything else from v26 kept.
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

-- =========================== FORWARD DECLS =================================
local RebuildCrosshair
local ApplyTransparency
local HeadlessToggle
local PhillyToggle
local LowGraphicsToggle
local StretchToggle
local SetStretchAspect
local autoWeaveStart
local autoWeaveStop
local ApplyAllConfig
local RunDoctor

-- =========================== SHOW ERROR (BEFORE OBSIDIAN) ==================
showError = function(msg)
    local text = tostring(msg)
    if #text > 400 then text = string.sub(text, 1, 400) end
    warn("[YSL] " .. text)
    pcall(function()
        local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local old = pg:FindFirstChild("YSL_ERR")
        if old then old:Destroy() end
        local g = Instance.new("ScreenGui")
        g.Name = "YSL_ERR"
        g.ResetOnSpawn = false
        g.DisplayOrder = 99999
        g.Parent = pg
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(0.96, 0, 0.3, 0)
        l.Position = UDim2.new(0.02, 0, 0.02, 0)
        l.BackgroundColor3 = Color3.fromRGB(110, 0, 0)
        l.BackgroundTransparency = 0.15
        l.BorderSizePixel = 0
        l.TextWrapped = true
        l.Font = Enum.Font.Code
        l.TextSize = 14
        l.TextColor3 = Color3.fromRGB(255, 255, 255)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Top
        l.Text = "YSL ERROR\n" .. text
        l.Parent = g
    end)
end

-- =========================== LOAD OBSIDIAN =================================
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
        showError("Obsidian failed to load: " .. tostring(res))
        return
    end
    Library = res
end

local function keepGuiAlive()
    local targets = {}
    pcall(function()
        targets[#targets + 1] = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end)
    pcall(function()
        if gethui then targets[#targets + 1] = gethui() end
    end)
    for _, holder in ipairs(targets) do
        if holder then
            local ok, kids = pcall(function() return holder:GetChildren() end)
            if ok and type(kids) == "table" then
                for _, gui in ipairs(kids) do
                    if gui:IsA("ScreenGui") then
                        pcall(function() gui.ResetOnSpawn = false end)
                    end
                end
            end
        end
    end
end

-- =========================== CONFIG ========================================
local Config = {
    autoWeave = { enabled = false, manualOnly = false, hold = 0.22, gap = 0.0 },
    hitbox = { enabled = false, radius = 7, airOnly = false, groundOnly = false },
    damage = {
        autoConnect = false, connectRange = 15,
        hitMultiplier = { enabled = false, value = 1, delay = 0.10 },
        noAttackDelay = false,
    },
    movement = {
        glide = { enabled = false, speed = 16 },
        walkSpeed = { enabled = false, value = 16 },
    },
    dodge = { noStun = true, hitThrough = true },
    longRange = { enabled = false, mode = "position", maxRadius = 15 },
    damageNumbers = true, damageSwingWindow = 1.10,
    noDelay = false,
    headless = false, philly = false, lowGraphics = false,
    stretchResolution = false, stretchAspect = 0.65,
    transparency = { enabled = false, level = 0.85 },
    crosshair = { enabled = false, size = 14, thickness = 2, gap = 5, dot = true },
    budgetRate = 5, budgetCap = 6,
}

local ENABLE_FEATURES = true
local ENABLE_SWEEP = true

local VERSION = "v31"
local CHANGELOG = {
    { "v31", "auto-weave restored to the original that worked: two wrapper calls per cycle, hold, gap, Heartbeat flags. Removed the 8/s weave bucket and the 0.25s hold floor, hold default back to 0.22, slider min back to 0.10. Grey box name kill from v30 unchanged." },
    { "v30", "grey box: Assets.VFX.WeaveHighlight is cloned into the character as 'WeaveHIGHLIGHT' and lives 0.4s; killed by name now, 0.1s scan on the local character plus every player's character in the 3s sweep. weave: hold floor 0.25s and an 8/s bucket, because Shared/Net/Remotes declares CombatService.Weave at perSecond 10 burst 10 (Swing 8/12, HitReport 10/14)." },
    { "v29", "hit reports match the wire format captured by RobloxSpy: seq, the actual hit part (UpperTorso/LowerTorso/Torso, root as last resort) and that part's world position. Hooked attacks already send Swing themselves; the fallback path now sends Swing(seq, 'Attack', limb) before reporting. Weave confirmed as true/false bool, unchanged." },
    { "v28", "autoload: after forcing remote features off, the Auto-Weave toggle is set back to OFF so the UI stops lying. auto-weave: if Combat.Weave is nil for 3s it notifies on screen instead of idling silently. No change to hits, weave call, or sweep." },
    { "v27", "headless: replaced with ScriptBlox logic. applyHeadless uses ch:WaitForChild('Head', math.random(6,11)) then sets Head.Transparency = 1 and face.Transparency = 1. restoreHead sets both back to 0 on toggle off. CharacterAdded reapplies 0.33s after spawn when headless is on. Everything else from v26 kept." },
    { "v26", "removed Killaura, Counter Stun, 4th Punch Reset, Phone Switch, Reset Delay, Custom Sensitivity, Heavy Booster. Renamed Timing -> Attack Speed. Removed dead notePunch, equipPhone, combo state, punchSpeed, counter wiring, sensitivity wiring." },
    { "v25", "headless: minimal, only Head + face transparency toggled" },
    { "v24", "headless grey box attempt via accessory handle hiding (reverted in v25)" },
    { "v23", "auto-weave reverted to working baseline awFire (Fire + FireServer); manualOnly default false" },
    { "v22", "auto-weave wrapper-only; per-frame WalkSpeed restore; expanded grey-box sweep; instant DescendantAdded kill; showError hoisted; _tick counter moved off the function" },
    { "v16", "swing remote removed entirely; wrapper-only hit reporting" },
    { "v15", "reverted to service wrapper (remotes.Client) as only transport" },
    { "v14", "prune: removed Double Hit, Stomp Speed, Auto Stomp, Style Changer, Anti Debounce, Remote Spy" },
    { "v13", "weave remote retired: auto-weave presses game's own key instead" },
    { "v12", "kick bisect: feature and sweep switches, stall watchdog" },
    { "v11", "load safety: autoload no longer starts remote features" },
    { "v10", "kick safety: send governor at 5/s, hit multiplier capped at 4" },
    { "v9", "swing-first: every hit and weave opens a swing" },
    { "v8", "gui death: ResetOnSpawn guard + on-screen error panel" },
    { "v7", "nine fixes: weave-hit, grey box, respawn cosmetics, potato graphics, ground targets, range merge, 4th punch, phone switch, tab moves" },
    { "v6", "exact RE paths: Hitreport, weave, swing + Hitrejected listener" },
    { "v5", "remote spy + full replicated-tree scan" },
    { "v4", "crash fix, module discovery, Run Doctor" },
    { "v3", "weave combat, killaura, configs, real damage numbers" },
}
local STATS = { hits = 0, silentHits = 0, greySwept = 0, blocked = 0 }

do
    local ok, rs = pcall(function() return game:GetService("RunService") end)
    if ok and rs then
        local last = os.clock()
        pcall(function()
            rs.Heartbeat:Connect(function()
                local now = os.clock()
                local dt = now - last
                last = now
                if dt > 1.2 and showError then
                    showError(string.format("stall %.2fs - client froze, not a server kick", dt))
                end
            end)
        end)
    end
end

-- =========================== CONFIG FILES ==================================
local Options = {}
local SelectedConfig = nil

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

local function deepApply(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            deepApply(dst[k], v)
        elseif dst[k] ~= nil and type(v) ~= "table" then
            dst[k] = v
        end
    end
end

local SyncList = {
    { "aw_enabled", { "autoWeave", "enabled" } }, { "aw_manual", { "autoWeave", "manualOnly" } },
    { "aw_hold", { "autoWeave", "hold" } },     { "aw_gap", { "autoWeave", "gap" } },
    { "hb_enabled", { "hitbox", "enabled" } }, { "hb_radius", { "hitbox", "radius" } },
    { "hb_air", { "hitbox", "airOnly" } }, { "hb_ground", { "hitbox", "groundOnly" } },
    { "noDelay", { "noDelay" } },
    { "autoConnect", { "damage", "autoConnect" } }, { "connectRange", { "damage", "connectRange" } },
    { "hitMult", { "damage", "hitMultiplier", "enabled" } }, { "hitCount", { "damage", "hitMultiplier", "value" } },
    { "hitDelay", { "damage", "hitMultiplier", "delay" } },
    { "glide_enabled", { "movement", "glide", "enabled" } }, { "glide_speed", { "movement", "glide", "speed" } },
    { "walk_enabled", { "movement", "walkSpeed", "enabled" } }, { "walk_speed", { "movement", "walkSpeed", "value" } },
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

local function notify(msg)
    if not (Library and Library.Notify) then return end
    pcall(function()
        Library:Notify({ Title = "YSL", Description = tostring(msg), Time = 3 })
    end)
end

-- =========================== WINDOW ========================================
local Window = Library:CreateWindow({
    Title = "YSL FINAL SHOWDOWN (UPDATE SOON)" .. VERSION,
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
    Callback = function(v)
        Config.autoWeave.enabled = v
        if v then autoWeaveStart() else autoWeaveStop() end
    end })
Options.aw_manual = AW:AddToggle("aw_manual", { Text = "Manual Mode (weave-gated)", Default = Config.autoWeave.manualOnly,
    Callback = function(v) Config.autoWeave.manualOnly = v end })
Options.aw_hold = AW:AddSlider("aw_hold", { Text = "Hold", Default = Config.autoWeave.hold,
    Min = 0.10, Max = 0.50, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.autoWeave.hold = v end })
Options.aw_gap = AW:AddSlider("aw_gap", { Text = "Cycle Gap", Default = Config.autoWeave.gap,
    Min = 0.00, Max = 0.30, Rounding = 2, Suffix = "s",
    Callback = function(v) Config.autoWeave.gap = v end })

local HB = Tabs.Combat:AddRightGroupbox("Hitbox")
Options.hb_enabled = HB:AddToggle("hb_enabled", { Text = "Hitbox", Default = Config.hitbox.enabled,
    Callback = function(v) Config.hitbox.enabled = v end })
Options.hb_radius = HB:AddSlider("hb_radius", { Text = "Radius", Default = Config.hitbox.radius,
    Min = 1, Max = 8, Rounding = 1, Suffix = " studs",
    Callback = function(v) Config.hitbox.radius = v end })
Options.hb_air = HB:AddToggle("hb_air", { Text = "Airborne Targets Only", Default = Config.hitbox.airOnly,
    Callback = function(v) Config.hitbox.airOnly = v end })
Options.hb_ground = HB:AddToggle("hb_ground", { Text = "Grounded Targets Only", Default = Config.hitbox.groundOnly,
    Callback = function(v) Config.hitbox.groundOnly = v end })

local AS = Tabs.Combat:AddRightGroupbox("Attack Speed")
Options.noDelay = AS:AddToggle("noDelay", { Text = "No Punch Delay", Default = Config.noDelay,
    Callback = function(v) Config.noDelay = v end })

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

local LR = Tabs.Combat:AddRightGroupbox("Long Range")
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

local CS = Tabs.Visuals:AddLeftGroupbox("Cosmetics")
Options.headless = CS:AddToggle("headless", { Text = "Headless", Default = Config.headless,
    Callback = function(v) Config.headless = v; if HeadlessToggle then HeadlessToggle(v) end end })
Options.philly = CS:AddToggle("philly", { Text = "Philly Style", Default = Config.philly,
    Callback = function(v) Config.philly = v; if PhillyToggle then PhillyToggle(v) end end })
Options.lowGraphics = CS:AddToggle("lowGraphics", { Text = "Potato Graphics", Default = Config.lowGraphics,
    Callback = function(v) Config.lowGraphics = v; if LowGraphicsToggle then LowGraphicsToggle(v) end end })
Options.stretchRes = CS:AddToggle("stretchRes", { Text = "Stretch Resolution", Default = Config.stretchResolution,
    Callback = function(v) Config.stretchResolution = v; if StretchToggle then StretchToggle(v) end end })
Options.stretchAspect = CS:AddSlider("stretchAspect", { Text = "Stretch Aspect", Default = Config.stretchAspect,
    Min = 0.35, Max = 1.00, Rounding = 2,
    Callback = function(v) Config.stretchAspect = v; if SetStretchAspect then SetStretchAspect(v) end end })

-- =========================== MISC TAB ======================================
local DG = Tabs.Misc:AddLeftGroupbox("Dodge")
Options.noStun = DG:AddToggle("noStun", { Text = "Anti Weave Stun (VISUALLY WORKS)", Default = Config.dodge.noStun,
    Callback = function(v) Config.dodge.noStun = v end })
Options.hitThrough = DG:AddToggle("hitThrough", { Text = "Hit Through Weave (MIGHT NOT WORK)", Default = Config.dodge.hitThrough,
    Callback = function(v) Config.dodge.hitThrough = v end })

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

-- =========================== FEATURE CODE ==================================
local featureOk, featureErr = pcall(function()

if not ENABLE_FEATURES then
    print("[YSL] features disabled by ENABLE_FEATURES - UI only")
    return
end

local Remotes, Combat, AttackState, HitWindow, Hitboxes, CharacterController, DataController, Classes
local Active = { Weaving = false, OpenFrame = false, CanAttack = false, Seq = 0, CurrentM1 = nil }
local HITBOX_MAX = 15.2
local watchedChar, lastStun = nil, false
local lastStunClearAt = 0
local suppressHookReport = false
local origHWStart, origHBStart, origHitReportFire
local learnedHitArgs = nil
local lastRejectAt = 0
local budget = { tokens = 6, rate = 5, cap = 6, last = os.clock() }

local function syncBudgets()
    budget.rate = Config.budgetRate or 5
    budget.cap = Config.budgetCap or 6
    if budget.tokens > budget.cap then budget.tokens = budget.cap end
end

local function takeToken()
    local now = os.clock()
    budget.tokens = math.min(budget.cap, budget.tokens + (now - budget.last) * budget.rate)
    budget.last = now
    if budget.tokens < 1 then
        STATS.blocked = (STATS.blocked or 0) + 1
        return false
    end
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

local function isAirborne(hum)
    if not hum then return false end
    local ok, mat = pcall(function() return hum.FloorMaterial end)
    if not ok then return false end
    return mat == Enum.Material.Air
end

local function effectiveRange()
    local r = Config.hitbox.radius or 7
    if Config.damage.autoConnect then r = math.max(r, Config.damage.connectRange or r) end
    if Config.longRange.enabled then r = math.max(r, Config.longRange.maxRadius or r) end
    return math.min(r, HITBOX_MAX)
end

local function spoofPos(t)
    local r = myRoot(); if not r then return t.root.Position end
    if Config.longRange.mode == "position" then return r.Position + r.CFrame.LookVector * 2 end
    if Config.longRange.mode == "midpoint" then return (r.Position + t.root.Position) / 2 end
    return t.root.Position
end

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

local function brief(v)
    local t = typeof(v)
    if t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        return "table(" .. n .. ")"
    end
    if t == "string" then return string.sub(v, 1, 80) end
    return tostring(v)
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

local aw = { cycleActive = false, cycleTask = nil, cycles = 0, lastAnimAt = 0, lastStateTrueAt = 0, gateOpenUntil = 0, weaveSentAt = 0 }

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

local function weaveActiveNow()
    if aw.weaveSentAt > 0 then return true end
    if Active and Active.Weaving == true then return true end
    if CharacterController then
        local ok, w = pcall(function() return CharacterController:Is("Weaving") end)
        if ok and w == true then return true end
    end
    return animPlayingNow()
end

-- =========================== DAMAGE NUMBERS ================================

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

local function currentSeq()
    if AttackState and AttackState.Active then return Active.Seq end
    Active.Seq = (Active.Seq or 0) + 1
    return Active.Seq
end

-- Wire format confirmed from the game's own traffic: the third argument is the
-- part that was hit and the fourth is that part's world position, not the root.
local TORSO_ORDER = { "UpperTorso", "LowerTorso", "Torso" }
local function hitPartOf(t)
    local ch = t and t.char
    if ch then
        for _, nm in ipairs(TORSO_ORDER) do
            local p = ch:FindFirstChild(nm)
            if p and p:IsA("BasePart") then return p end
        end
    end
    return t and t.root
end

local swingLimbFlip = false
local function swingFor(seq)
    if not Combat or not Combat.Swing then return false end
    swingLimbFlip = not swingLimbFlip
    local limb = swingLimbFlip and "LeftHand" or "RightHand"
    return fireRemote(Combat.Swing, seq, "Attack", limb)
end

local function reportOnce(seq, target)
    if not Combat or not Combat.HitReport then return false end
    if not target or not target.root or not target.root:IsA("BasePart") then return false end
    if Config.hitbox.airOnly and not isAirborne(target.hum) then return false end
    if Config.hitbox.groundOnly and isAirborne(target.hum) then return false end
    if target.dist and target.dist > HITBOX_MAX then return false end
    if not takeToken() then return false end

    local hum = target.hum
    local before = (hum and hum.Health) or nil
    local part = hitPartOf(target) or target.root
    local pos = part.Position
    if Config.longRange.enabled then pos = spoofPos(target) end

    local ok
    if typeof(Combat.HitReport) == "Instance" and learnedHitArgs then
        local out, n = {}, 0
        for i = 1, learnedHitArgs.n do
            local v = learnedHitArgs[i]
            local t = typeof(v)
            if t == "Instance" then
                local okp, isPart = pcall(function() return v:IsA("BasePart") end)
                out[i] = (okp and isPart) and part or v
            elseif t == "Vector3" then
                out[i] = pos
            else
                out[i] = v
            end
            n = i
        end
        ok = fireRemote(Combat.HitReport, table.unpack(out, 1, n))
    else
        ok = fireRemote(Combat.HitReport, seq, part, pos)
    end
    if not ok then return false end

    STATS.hits = STATS.hits + 1
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
    local hits = math.min(4, math.floor(Config.damage.hitMultiplier.value or 1))
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

local function attackTrigger()
    if not (Config.hitbox.enabled or Config.damage.autoConnect) then return end
    if not Combat or not Combat.HitReport then return end
    local seq = currentSeq()
    if not origHWStart then swingFor(seq) end
    local targets = collect(effectiveRange())
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
        if Config.damage.noAttackDelay or Config.noDelay then
            Active.OpenFrame = true; Active.CanAttack = true
        end
        if not suppressHookReport and (Config.hitbox.enabled or Config.damage.autoConnect) then
            local seq = currentSeq()
            local targets = collect(effectiveRange())
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

-- =========================== AUTO-WEAVE ====================================

local function gateOpen()
    if not Config.autoWeave.enabled then return false end
    if not Config.autoWeave.manualOnly then return true end
    return weavingNow()
end

local function awFire(state)
    if not Combat or not Combat.Weave then return end
    pcall(function() Combat.Weave:Fire(state) end)
    pcall(function() Combat.Weave:FireServer(state) end)
    if state then
        aw.weaveSentAt = os.clock()
    else
        aw.weaveSentAt = 0
    end
end

autoWeaveStart = function()
    if aw.cycleActive then return end
    aw.cycleActive = true
    aw.cycleTask = task.spawn(function()
        local waited, told = 0, false
        while aw.cycleActive and (not Combat or not Combat.Weave) do
            task.wait(0.1)
            waited = waited + 0.1
            if not told and waited >= 3 then
                told = true
                notify("Auto-Weave idle: Combat.Weave = nil (Run Doctor)")
            end
        end
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
    aw.weaveSentAt = 0
    if aw.cycleTask then pcall(function() task.cancel(aw.cycleTask) end) aw.cycleTask = nil end
    if Combat and Combat.Weave then
        pcall(function() Combat.Weave:Fire(false) end)
        pcall(function() Combat.Weave:FireServer(false) end)
    end
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

local function updateGlide(rp, hum)
    if not Config.movement.glide.enabled or not rp or not hum or hum.Health <= 0 then stopGlide(); return end
    if not weaveActiveNow() then stopGlide(); return end
    local mv = hum.MoveDirection
    if mv.Magnitude < 0.05 then stopGlide(); return end
    local horiz = Vector3.new(mv.X, 0, mv.Z)
    if horiz.Magnitude < 0.05 then stopGlide(); return end
    if glideBody.Parent ~= rp then glideBody.Parent = rp end
    glideBody.Velocity = horiz.Unit * Config.movement.glide.speed
    glideOn = true
end

-- =========================== COSMETICS =====================================

local lightingBackup

-- v27: headless uses the ScriptBlox logic.
-- applyHeadless waits for Head with a random 6-11s timeout (returns
-- immediately when Head is present), then sets Head and face transparency
-- to 1. restoreHead sets both back to 0 on toggle off.
local function applyHeadless(ch)
    if not ch then return end
    local ok, h = pcall(function() return ch:WaitForChild("Head", math.random(6, 11)) end)
    if ok and h then
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
                OutdoorAmbient = Lighting.OutdoorAmbient,
                EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
                EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
                ClockTime = Lighting.ClockTime,
                effects = {},
            }
            for _, e in ipairs(Lighting:GetChildren()) do
                if e:IsA("PostEffect") then
                    table.insert(lightingBackup.effects, { inst = e, enabled = e.Enabled })
                end
            end
        end
        for _, rec in ipairs(lightingBackup.effects) do
            pcall(function() rec.inst.Enabled = false end)
        end
        pcall(function()
            Lighting.GlobalShadows = false
            Lighting.Brightness = 3
            Lighting.FogStart = 0
            Lighting.FogEnd = 100000
            Lighting.Ambient = Color3.fromRGB(160, 160, 160)
            Lighting.OutdoorAmbient = Color3.fromRGB(160, 160, 160)
            Lighting.EnvironmentDiffuseScale = 0
            Lighting.EnvironmentSpecularScale = 0
            Lighting.ClockTime = 13.5
        end)
        pcall(function()
            local t = workspace:FindFirstChildOfClass("Terrain")
            if t then
                t.WaterWaveSize = 0
                t.WaterWaveSpeed = 0
                t.WaterReflectance = 0
                t.WaterTransparency = 1
            end
        end)
        pcall(function()
            for _, inst in ipairs(workspace:GetChildren()) do
                if inst:IsA("ParticleEmitter") or inst:IsA("Fire")
                    or inst:IsA("Smoke") or inst:IsA("Sparkles") then
                    inst.Enabled = false
                end
            end
        end)
        pcall(function() settings().Rendering.QualityLevel = 1 end)
        pcall(function()
            UserSettings():GetService("UserGameSettings").SavedQualityLevel =
                Enum.SavedQualitySetting.QualityLevel1
        end)
    elseif lightingBackup then
        local b = lightingBackup
        lightingBackup = nil
        for _, rec in ipairs(b.effects or {}) do
            pcall(function() rec.inst.Enabled = rec.enabled end)
        end
        pcall(function()
            Lighting.GlobalShadows = b.GlobalShadows
            Lighting.Brightness = b.Brightness
            Lighting.FogStart = b.FogStart
            Lighting.FogEnd = b.FogEnd
            Lighting.Ambient = b.Ambient
            Lighting.OutdoorAmbient = b.OutdoorAmbient
            Lighting.EnvironmentDiffuseScale = b.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale = b.EnvironmentSpecularScale
            Lighting.ClockTime = b.ClockTime
        end)
        pcall(function() settings().Rendering.QualityLevel = 21 end)
    end
end

-- =========================== VISUAL CLEANUP ================================

local sweepTickCounter = 0

local function visualizerName(nm)
    nm = string.lower(tostring(nm or ""))
    return nm:find("visual", 1, true) or nm:find("hitbox", 1, true)
        or nm:find("point", 1, true) or nm:find("debug", 1, true)
end

-- The game clones Assets.VFX.WeaveHighlight into a character, renames it
-- "WeaveHIGHLIGHT" and destroys it 0.4s later. It is parented straight to the
-- character, not to an Attachment, and it is not always a Highlight instance.
local function killWeaveHighlight(inst)
    if not inst or not inst.Parent then return false end
    local nm = string.lower(tostring(inst.Name or ""))
    if string.find(nm, "weavehigh", 1, true) then
        pcall(function() inst:Destroy() end)
        STATS.greySwept = (STATS.greySwept or 0) + 1
        return true
    end
    return false
end

local function sweepDebugVisuals(alsoVisualizer)
    if alsoVisualizer and Hitboxes and type(Hitboxes.SetVisualizer) == "function" then
        pcall(function() Hitboxes:SetVisualizer(false) end)
    end
    local destroyed = 0
    local function nuke(root)
        if not root then return end
        local ok, kids = pcall(function() return root:GetDescendants() end)
        if not ok or type(kids) ~= "table" then return end
        for _, inst in ipairs(kids) do
            if killWeaveHighlight(inst) then
                destroyed = destroyed + 1
            else
                local cn = inst.ClassName
                if cn == "BoxHandleAdornment" or cn == "SelectionBox" or cn == "SurfaceSelection"
                    or cn == "SelectionSphere" or cn == "Highlight" then
                    pcall(function() inst:Destroy() end)
                    destroyed = destroyed + 1
                elseif inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Attachment")
                    and visualizerName(inst.Name) then
                    pcall(function() inst:Destroy() end)
                    destroyed = destroyed + 1
                end
            end
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        nuke(p.Character)
    end
    nuke(workspace.CurrentCamera)
    sweepTickCounter = sweepTickCounter + 1
    if sweepTickCounter % 3 == 0 then
        local ch = LP.Character
        if ch then
            local origin = ch:GetPivot().Position
            local rad = 60
            local ok, all = pcall(function() return workspace:GetDescendants() end)
            if ok and type(all) == "table" then
                for _, inst in ipairs(all) do
                    if inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Attachment")
                        and visualizerName(inst.Name) then
                        local okp, p = pcall(function() return inst.Position end)
                        if okp and p and (p - origin).Magnitude <= rad then
                            pcall(function() inst:Destroy() end)
                            destroyed = destroyed + 1
                        end
                    end
                end
            end
        end
    end
    STATS.greySwept = (STATS.greySwept or 0) + destroyed
    return destroyed
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
local lastKillScanAt = 0

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

    if ch then
        local killNow = os.clock()
        if killNow - lastKillScanAt > 0.1 then
            lastKillScanAt = killNow
            local okKids, kids = pcall(function() return ch:GetChildren() end)
            if okKids and type(kids) == "table" then
                for _, inst in ipairs(kids) do
                    killWeaveHighlight(inst)
                end
            end
        end
    end

    if hum then
        if Config.movement.walkSpeed.enabled then
            hum.WalkSpeed = Config.movement.walkSpeed.value
        elseif Config.autoWeave.enabled and aw.cycleActive and Active and Active.Weaving == true then
            local okc, ws = pcall(function() return CharacterController:Get("WalkSpeed") end)
            hum.WalkSpeed = (okc and tonumber(ws)) or 16
        end
    end
end)

-- =========================== APPLY ALL =====================================

ApplyAllConfig = function()
    for _, entry in ipairs(SyncList) do
        local el = Options[entry[1]]
        local v = pathGet(Config, entry[2])
        if el and v ~= nil and el.SetValue then
            pcall(function() el:SetValue(v) end)
        end
    end

    if Config.autoWeave.enabled then autoWeaveStart() else autoWeaveStop() end
    ApplyTransparency(LP.Character)
    RebuildCrosshair()
    HeadlessToggle(Config.headless)
    PhillyToggle(Config.philly)
    LowGraphicsToggle(Config.lowGraphics)
    StretchToggle(Config.stretchResolution)
    notify("Config applied")
end

-- =========================== DISCOVERY ====================================

local Discovered = { modules = {}, remotes = {}, re = {} }

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
    L[#L + 1] = "YSL " .. VERSION
    L[#L + 1] = string.format("hits=%d blocked_by_rate=%d grey=%d", STATS.hits or 0, STATS.blocked or 0, STATS.greySwept or 0)
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
    L[#L + 1] = "PlaceId: " .. tostring(game.PlaceId)
    L[#L + 1] = "CombatService.RE: " .. (#Discovered.re > 0 and table.concat(Discovered.re, ", ") or "(not found)")
    return L
end

RunDoctor = function()
    local L = doctorLines()
    for _, line in ipairs(L) do print("[YSL] " .. line) end
    if hasFS() then
        ensureFolder("YSL")
        pcall(writefile, "YSL/doctor.txt", table.concat(L, "\n"))
    end
    notify("Doctor " .. VERSION .. ": " .. L[2] .. " | " .. L[3])
end

-- =========================== INIT ==========================================

task.spawn(function()
    task.wait(1.5)
    local ok, err = pcall(function()
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
                if inst.Name == "YSL_Cross" or inst.Name == "YSL_DIAG" then
                    pcall(function() inst:Destroy() end)
                end
            end
        end

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

        Remotes = resolveModule("Remotes", { "Shared", "Net", "Remotes" }, 2)
        local wrapperResolved = false
        if Remotes and Remotes.Client then
            local okc, c = pcall(function() return Remotes.Client("CombatService") end)
            if okc and type(c) == "table" then
                Combat = c
                wrapperResolved = true
            end
        end

        local RE = nil
        do
            local ok, v = pcall(function()
                local r = ReplicatedStorage:FindFirstChild("Remotes")
                local cs = r and r:FindFirstChild("CombatService")
                return cs and cs:FindFirstChild("RE")
            end)
            if ok and v then RE = v end
        end
        if RE then
            for _, ch in ipairs(RE:GetChildren()) do
                Discovered.re[#Discovered.re + 1] = ch.Name
                if ch:IsA("RemoteEvent") or ch:IsA("RemoteFunction") then
                    Discovered.remotes[ch.Name] = ch
                end
            end
            table.sort(Discovered.re)
        end
        AttackState         = resolveModule("AttackState", { "Client", "Combat", "AttackState" }, 2)
        HitWindow           = resolveModule("HitWindow", { "Client", "Combat", "HitWindow" }, 2)
        Hitboxes            = resolveModule("Hitboxes", { "Client", "Combat", "Hitboxes" }, 2)
        CharacterController = resolveModule("CharacterController", { "Client", "Controllers", "CharacterController" }, 2)
        DataController      = resolveModule("DataController", { "Client", "Controllers", "DataController" }, 2)
        Classes             = resolveModule("Classes", { "Shared", "Config", "Classes" }, 1.5)

        if not Combat then Combat = {} end

        local function reChild(want)
            if not RE then return nil end
            local w = string.lower(want)
            for _, ch in ipairs(RE:GetChildren()) do
                if string.lower(ch.Name) == w then return ch end
            end
            return nil
        end

        if wrapperResolved then
            Combat.HitReport   = Combat.HitReport or Combat.Hitreport or Combat.hitreport
                or Combat.Hit or Combat.hit or Combat.Attack or Combat.attack
                or Combat.Damage or Combat.damage or Combat.HitBox or Combat.Hitbox
            Combat.Weave       = Combat.Weave or Combat.weave
            Combat.Swing       = Combat.Swing or Combat.swing
            Combat.HitRejected = Combat.HitRejected or Combat.Hitrejected
            Combat.Cooldown    = Combat.Cooldown or Combat.cooldown
        else
            Combat.HitReport = reChild("hitreport")
            Combat.Weave     = nil
        end

        if not Combat.HitReport then
            local r = remoteLike({ "hitreport", "hit", "damage", "strike" })
            if r then Combat.HitReport = r end
        end

        if Combat.HitRejected and Combat.HitRejected.OnClientEvent then
            pcall(function()
                Combat.HitRejected.OnClientEvent:Connect(function(...)
                    local a = table.pack(...)
                    local bits = {}
                    for i = 1, math.min(a.n, 5) do bits[i] = brief(a[i]) end
                    local msg = table.concat(bits, " | ")
                    print("[YSL] HIT REJECTED: " .. msg)
                    if os.clock() - lastRejectAt > 2 then
                        lastRejectAt = os.clock()
                        notify("Rejected: " .. string.sub(msg, 1, 70))
                    end
                end)
            end)
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
        end

        if LP.Character then
            ApplyTransparency(LP.Character)
            if Config.headless then applyHeadless(LP.Character) end
        end

        if ENABLE_SWEEP then
            sweepDebugVisuals(true)
            task.spawn(function()
                while true do
                    sweepDebugVisuals()
                    task.wait(3)
                end
            end)
        end

        local function attachKill(inst)
            if killWeaveHighlight(inst) then return end
            if inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Attachment")
                and visualizerName(inst.Name) then
                pcall(function() inst:Destroy() end)
                STATS.greySwept = (STATS.greySwept or 0) + 1
            end
        end
        if LP.Character then
            pcall(function() LP.Character.DescendantAdded:Connect(attachKill) end)
        end

        LP.CharacterAdded:Connect(function(ch)
            task.wait(0.5)
            stopGlide()
            transOriginal = setmetatable({}, { __mode = "k" })
            watchedChar = nil
            ApplyTransparency(ch)
            if Config.crosshair.enabled then RebuildCrosshair() end
            if Config.headless then
                task.delay(0.33, function()
                    if LP.Character == ch then applyHeadless(ch) end
                end)
            end
            if Config.philly then PhillyToggle(true) end
            if Config.lowGraphics then LowGraphicsToggle(true) end
            if Config.stretchResolution then StretchToggle(true) end
            if ENABLE_SWEEP then sweepDebugVisuals(true) end
            pcall(function() ch.DescendantAdded:Connect(attachKill) end)
            keepGuiAlive()
        end)

        keepGuiAlive()
        print("[YSL] " .. VERSION .. " Combat ready")

        task.wait(1)
        local autoName = nil
        if hasFS() and typeof(isfile) == "function" and isfile(AUTOLOAD_FILE) then
            local rok, body = pcall(readfile, AUTOLOAD_FILE)
            if rok then autoName = sanitizeName(body) end
        end
        if autoName then
            local data = readConfig(autoName)
            if data then
                deepApply(Config, data)
                ApplyAllConfig()
                Config.autoWeave.enabled = false
                if autoWeaveStop then autoWeaveStop() end
                if Options.aw_enabled and Options.aw_enabled.SetValue then
                    pcall(function() Options.aw_enabled:SetValue(false) end)
                end
                notify("Loaded " .. autoName .. " - features start on toggle")
            end
        end
    end)
    if not ok then showError("init: " .. tostring(err)) end
end)

syncBudgets()

end) -- feature pcall

if not featureOk then showError("FEATURE ERROR: " .. tostring(featureErr)) end
print("[YSL] ready")
