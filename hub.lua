--[[ AOTR_HUB / hub.lua  --  Attack on Titan Revolution (place 13379349730)  v1.2
     Built from live RE (Xeno). Client UNOBFUSCATED. Actions: Host:Send(cat,act,...)->POST:FireServer,
     Host:Invoke->GET:InvokeServer. Nape kill = Zones.Bounds scans hitbox -> Send("Hitboxes","Register",Nape,nil,nil,p3).
     We wrap Zones.Bounds (indexed fresh each frame) => enlarge hitbox + capture live host ctx p1/p2/p3.

     TRUST BOUNDARY (honest):
       ESP / Hitbox-visual .... pure client -> UNDETECTED.
       Nape-extender .......... game's OWN Register with a bigger client hitbox. Server range-validates
                                -> CEILING; a modest factor is undetected, too big -> rejected/flagged.
       Autofarm ............... drives the game's OWN Bounds with captured ctx. Same range ceiling.
       Auto-reload ............ calls the game's OWN ODMG.Reload(self) -> game-native.
       Gas .................... reads p1.Loadout (dumped on capture) -> wired after we see the fields.
     ARMING: NapeExtend/Autofarm/Reload need the live host ctx `p1`, captured on the FIRST manual swing
             (Zones.Bounds fires). Swing once -> everything arms. Status printed to console.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local LP = Players.LocalPlayer

--=========================== CONFIG ===========================
local CFG = {
    ESP            = true,
    HitboxVisual   = true,
    NapeExtend     = true,
    NapeLevels     = {1.5, 2.0, 3.0, 4.0, 5.0}, -- cycle with V; find the undetected sweet-spot on mobile
    NapeLevelIdx   = 2,                          -- start at 2.0x
    AutoFarm       = false,
    AutoFarm_Range = 70,     -- studs; keep within legit ODM strike reach so server accepts
    AutoReload     = false,
    ReloadEvery    = 1.0,    -- s; only fires when blades actually need it (Blade_Check gate)
    Keybinds       = true,
}
-- keys: G=NapeExtend  H=AutoFarm  J=ESP  V=cycle nape level  B=AutoReload
local BINDS = {
    [Enum.KeyCode.G] = "NapeExtend", [Enum.KeyCode.H] = "AutoFarm",
    [Enum.KeyCode.J] = "ESP",        [Enum.KeyCode.B] = "AutoReload",
}
--==============================================================

if _G.__AOTR_HUB then pcall(_G.__AOTR_HUB) end
local _bin = {}
local function bin(x) _bin[#_bin+1] = x; return x end
_G.__AOTR_HUB = function()
    for _, c in ipairs(_bin) do pcall(function()
        if typeof(c) == "RBXScriptConnection" then c:Disconnect()
        elseif typeof(c) == "Instance" then c:Destroy()
        elseif type(c) == "function" then c() end end) end
    _bin = {}; _G.__AOTR_HUB = nil
end

local function charModel()
    local cc = Workspace:FindFirstChild("Characters")
    return cc and cc:FindFirstChild(LP.Name)
end
-- Nape = titan.Hitboxes.Hit.Nape (BasePart); a Weld is also named "Nape" -> verify class.
local function napeOf(titan)
    local hb = titan:FindFirstChild("Hitboxes")
    local hit = hb and hb:FindFirstChild("Hit")
    local nape = hit and hit:FindFirstChild("Nape")
    if nape and nape:IsA("BasePart") then return nape end
    for _, d in ipairs(titan:GetDescendants()) do
        if d.Name == "Nape" and d:IsA("BasePart") then return d end
    end
end
local function napeFactor() return CFG.NapeLevels[CFG.NapeLevelIdx] or 2.0 end

-- captured live context
local CTX = { p1 = nil, p2 = nil, p3 = nil, hitboxTemplate = nil }
local ODMG = nil
local function getODMG()
    if ODMG then return ODMG end
    local cm = charModel(); local m = cm and cm:FindFirstChild("ODMG", true)
    if m then local ok, M = pcall(require, m); if ok and type(M) == "table" then ODMG = M end end
    return ODMG
end
local _dumpedLoadout = false
local function onCapture(p1)
    if _dumpedLoadout or not p1 then return end
    _dumpedLoadout = true
    local lo = p1.Loadout
    if type(lo) == "table" then
        local k = {}; for key, v in pairs(lo) do k[#k+1] = tostring(key) .. ":" .. typeof(v) end
        print("[AOTR] ctx captured. Loadout keys: " .. table.concat(k, ", "))
        if type(lo.Stats) == "table" then
            local sk = {}; for key, v in pairs(lo.Stats) do sk[#sk+1] = tostring(key) .. "=" .. tostring(v) end
            print("[AOTR] Loadout.Stats: " .. table.concat(sk, ", "))
        end
    else
        print("[AOTR] ctx captured (p1.Loadout type=" .. typeof(lo) .. ")")
    end
end

--============================ ESP ============================
local espCache = {}
local function clearEsp(t) local e = espCache[t]; if e then if e.hl then e.hl:Destroy() end if e.box then e.box:Destroy() end espCache[t] = nil end end
local function updateEsp()
    local titans = Workspace:FindFirstChild("Titans"); if not titans then return end
    local live = {}
    for _, titan in ipairs(titans:GetChildren()) do
        live[titan] = true
        if not espCache[titan] then
            local hl = Instance.new("Highlight")
            hl.FillColor = Color3.fromRGB(255, 60, 60); hl.FillTransparency = 0.7
            hl.OutlineColor = Color3.fromRGB(255, 255, 255); hl.Adornee = titan; hl.Parent = titan
            local box; local nape = napeOf(titan)
            if nape then
                box = Instance.new("SelectionBox"); box.Color3 = Color3.fromRGB(60, 255, 90)
                box.LineThickness = 0.06; box.SurfaceTransparency = 0.5; box.Adornee = nape; box.Parent = nape
            end
            espCache[titan] = { hl = hl, box = box }
        end
    end
    for titan in pairs(espCache) do if not live[titan] or not CFG.ESP then clearEsp(titan) end end
end

--==================== NAPE-EXTENDER + HITBOX ====================
local hookedZones = nil
local function installNapeHook()
    local cm = charModel(); if not cm then return false, "no char" end
    local zmod = cm:FindFirstChild("Zones", true); if not zmod then return false, "no Zones" end
    local ok, Zones = pcall(require, zmod)
    if not ok or type(Zones) ~= "table" or typeof(Zones.Bounds) ~= "function" then return false, "require/Bounds fail" end
    if hookedZones == Zones then return true, "already" end
    local original = Zones.Bounds
    Zones.Bounds = function(p1, p2, p3, hitbox)
        CTX.p1, CTX.p2, CTX.p3 = p1, p2, p3
        onCapture(p1)
        if typeof(hitbox) == "Instance" and hitbox:IsA("BasePart") then
            CTX.hitboxTemplate = CTX.hitboxTemplate or hitbox
            local restore
            if CFG.NapeExtend then local s = hitbox.Size; hitbox.Size = s * math.clamp(napeFactor(), 1, 6); restore = s end
            if CFG.HitboxVisual then hitbox.Transparency = 0.6; hitbox.Color = Color3.fromRGB(80, 160, 255); hitbox.Material = Enum.Material.ForceField end
            local r = table.pack(original(p1, p2, p3, hitbox))
            if restore then pcall(function() hitbox.Size = restore end) end
            return table.unpack(r, 1, r.n)
        end
        return original(p1, p2, p3, hitbox)
    end
    hookedZones = Zones
    bin(function() if hookedZones then hookedZones.Bounds = original end end)
    return true, "hooked"
end

--=========================== AUTOFARM ===========================
-- Reuses the VERIFIED register path: game's own Zones.Bounds with captured ctx + a hitbox at the nape.
local function nearestNape()
    local titans = Workspace:FindFirstChild("Titans"); if not titans then return end
    local cm = charModel(); local root = cm and cm:FindFirstChild("HumanoidRootPart", true)
    if not root then return end
    local best, bestD
    for _, titan in ipairs(titans:GetChildren()) do
        local nape = napeOf(titan)
        if nape then
            local d = (nape.Position - root.Position).Magnitude
            if d <= CFG.AutoFarm_Range and (not bestD or d < bestD) then best, bestD = nape, d end
        end
    end
    return best
end
local _lastFarm = 0
local function autofarmStep()
    if not CFG.AutoFarm then return end
    if not (CTX.p1 and CTX.p3 and CTX.hitboxTemplate and hookedZones) then return end
    if os.clock() - _lastFarm < 0.15 then return end
    local nape = nearestNape(); if not nape then return end
    _lastFarm = os.clock()
    local titan = nape:FindFirstAncestorWhichIsA("Model")
    pcall(function() ReplicatedStorage.Assets.Remotes.POST:FireServer("Attacks", "Slash", true) end)
    local hb = CTX.hitboxTemplate:Clone()
    hb.CFrame = nape.CFrame; hb.Size = nape.Size * 2.5; hb.CanTouch = true; hb.CanCollide = false
    hb.Transparency = 1; hb.Parent = Workspace
    task.wait()
    pcall(function() hookedZones.Bounds(CTX.p1, titan or CTX.p2, CTX.p3, hb) end)
    hb:Destroy()
end

--========================= AUTO-RELOAD =========================
local _lastReload = 0
local function autoreloadStep()
    if not CFG.AutoReload or not CTX.p1 then return end
    if os.clock() - _lastReload < CFG.ReloadEvery then return end
    local M = getODMG(); if not M then return end
    -- only reload if the game says blades need it (Blade_Check), else no-op (undetected: game-native call)
    local need = true
    if typeof(M.Blade_Check) == "function" then local ok, r = pcall(M.Blade_Check, CTX.p1); if ok and r ~= nil then need = (r == false or r == 0 or r == nil) end end
    if need and typeof(M.Reload) == "function" then
        _lastReload = os.clock()
        pcall(M.Reload, CTX.p1)
    end
end

--=========================== DRIVER ===========================
local function toggle(n)
    CFG[n] = not CFG[n]; print("[AOTR] " .. n .. " = " .. tostring(CFG[n]))
    if n == "NapeExtend" and CFG[n] then installNapeHook() end
end
local function cycleNape()
    CFG.NapeLevelIdx = (CFG.NapeLevelIdx % #CFG.NapeLevels) + 1
    print("[AOTR] NapeFactor = " .. tostring(napeFactor()) .. "x")
end
if CFG.Keybinds then
    bin(UserInputService.InputBegan:Connect(function(i, gp)
        if gp then return end
        if i.KeyCode == Enum.KeyCode.V then cycleNape(); return end
        local n = BINDS[i.KeyCode]; if n then toggle(n) end
    end))
end
bin(LP.CharacterAdded:Connect(function() task.wait(2); hookedZones = nil; ODMG = nil; _dumpedLoadout = false; installNapeHook() end))
bin(RunService.Heartbeat:Connect(function()
    if CFG.ESP then updateEsp() end
    if CFG.AutoFarm then pcall(autofarmStep) end
    if CFG.AutoReload then pcall(autoreloadStep) end
end))

local ok, msg = installNapeHook()
print(("[AOTR] hub v1.2 loaded. hook=%s(%s). Keys: G=NapeExt H=Autofarm J=ESP B=Reload V=cycle(%.1fx)")
    :format(tostring(ok), tostring(msg), napeFactor()))
print("[AOTR] Swing once to ARM NapeExtend/Autofarm/Reload (captures attack context).")
_G.__AOTR_STATE = function()
    return { napehook = hookedZones ~= nil, esp = (next(espCache) ~= nil), armed = CTX.p1 ~= nil,
             napeFactor = napeFactor(), autofarm = CFG.AutoFarm, autoreload = CFG.AutoReload }
end
