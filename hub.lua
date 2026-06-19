--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · Hollowed Era  —  ALL-IN-ONE  (built from the ripped game code)
    discord.gg/5rpP6faZSJ

    COMBAT   Killaura (drives the game's real M1) · No-Cooldown · Teleport reach ·
             Extra Reach (1-50) · Auto Face
    DEFENSE  Always Parry (overrides IsClientBlocking -> server thinks you perfect-block
             every hit) · Auto Block (reactive, Swing-triggered)
    MOVEMENT Walk Speed · Infinite Jump · Fly+Noclip · Dash (Shunpo)
    VISUAL   Enemy/Boss ESP (highlight + name + HP + distance)

    Notes: damage is server-authoritative (no one-shot). Movement has anti-cheat — start
    moderate. Reach via M1Range is server-capped, so Teleport is the true reach.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_HE_Hub then pcall(function() shared.__HSHub_HE_Hub:Destroy() end) end

local Players    = game:GetService('Players')
local RS         = game:GetService('ReplicatedStorage')
local UIS        = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local LP         = Players.LocalPlayer
local cam        = workspace.CurrentCamera

local RsPackage = RS:WaitForChild('RsPackage', 10)
local function rget(p) local o = RsPackage; for _, n in ipairs(p) do o = o and o:FindFirstChild(n) end; return o end
local Block   = rget({ 'Block' })
local Swing   = rget({ 'Swing' })
local Shunpo  = rget({ 'Shunpo' })
local Hitbox  = rget({ 'ClientVFX', 'Hitbox' })
local ICB     = rget({ 'IsClientBlocking' })
local RacesInfo; pcall(function() RacesInfo = require(RsPackage.Modules.RacesInfo) end)

local S = {
    Killaura = false, NoCd = false, TP = false, AutoFace = true, Range = 130, ExtraReach = 12, NoCdRate = 0.14,
    AlwaysParry = false, AutoBlock = false, BlockRange = 22, BlockHold = 0.6,
    SpeedOn = false, Speed = 16, InfJump = false, Fly = false, FlySpeed = 70,
    ESP = false, ESPRange = 700,
}

-- ═══════════ shared helpers ═══════════
local function hum()  local c = LP.Character; return c and c:FindFirstChildOfClass('Humanoid') end
local function root() local c = LP.Character; return c and (c:FindFirstChild('HumanoidRootPart') or c.PrimaryPart) end
local function isEnemy(m)
    -- only ever called on Workspace.Humanoids children, so any living non-player humanoid = NPC/boss
    if not m:IsA('Model') or Players:GetPlayerFromCharacter(m) then return false end
    local h = m:FindFirstChildOfClass('Humanoid')
    return h ~= nil and h.Health > 0
end
local function nearestEnemy(rng)
    local h = workspace:FindFirstChild('Humanoids'); local r = root()
    if not h or not r then return nil end
    local best, bd
    for _, m in ipairs(h:GetChildren()) do
        if isEnemy(m) then
            local hrp = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
            if hrp then local d = (hrp.Position - r.Position).Magnitude
                if d <= rng and (not bd or d < bd) then best, bd = hrp, d end end
        end
    end
    return best
end

-- ═══════════ COMBAT: drive the game's own M1 ═══════════
local m1tbl
local function loadM1()
    m1tbl = nil; local c = LP.Character; if not c then return end
    local mod = c:FindFirstChild('M1Types', true)
    if mod and mod:IsA('ModuleScript') then local ok, m = pcall(require, mod); if ok and type(m) == 'table' then m1tbl = m end end
end
loadM1(); LP.CharacterAdded:Connect(function() task.wait(1.5); loadM1() end)

-- reach (M1Range bonus) + no-cd (shrink M1Cooldown) via the cached RacesInfo table
local function raceEntries()
    local list = {}; if type(RacesInfo) ~= 'table' then return list end
    for _, v in pairs(RacesInfo) do if type(v) == 'table' and type(rawget(v, 'M1Range')) == 'number' then list[#list + 1] = v end end
    local sw = rawget(RacesInfo, 'SwordTypes')
    if type(sw) == 'table' then for _, v in pairs(sw) do if type(v) == 'table' and type(rawget(v, 'M1Range')) == 'number' then list[#list + 1] = v end end end
    return list
end
local rangeOrig, cdOrig = {}, {}
local function applyReach() for _, e in ipairs(raceEntries()) do if rangeOrig[e] == nil then rangeOrig[e] = e.M1Range end; e.M1Range = rangeOrig[e] + S.ExtraReach end end
local function applyNoCd(on)
    for _, e in ipairs(raceEntries()) do
        local cd = rawget(e, 'M1Cooldown')
        if type(cd) == 'table' and #cd > 0 then
            if on then if not cdOrig[e] then local c = {}; for i = 1, #cd do c[i] = cd[i] end; cdOrig[e] = c end; for i = 1, #cd do cd[i] = 0.08 end
            elseif cdOrig[e] then for i = 1, #cdOrig[e] do cd[i] = cdOrig[e][i] end; cdOrig[e] = nil end
        end
    end
end
local function canAct()
    local c = LP.Character; if not c then return false end
    local h = c:FindFirstChildOfClass('Humanoid'); if not h or h.Health <= 0 then return false end
    if h:GetState() == Enum.HumanoidStateType.Physics then return false end
    if c:FindFirstChild('Stun', true) then return false end
    if c:GetAttribute('Blocking') or c:GetAttribute('MiscActing') or c:GetAttribute('Carrying')
        or c:GetAttribute('Dominated') or c:GetAttribute('Downed') or c:GetAttribute('InCutscene') then return false end
    return true
end
local function face(pos) local r = root(); if r then pcall(function() r.CFrame = CFrame.lookAt(r.Position, Vector3.new(pos.X, r.Position.Y, pos.Z)) end) end end
applyReach()
task.spawn(function()
    while true do
        local dt = 0.2
        if S.Killaura and m1tbl then
            local hrp = nearestEnemy(S.Range)
            if hrp then
                local r = root()
                if S.TP and r then local dir = r.Position - hrp.Position
                    if dir.Magnitude > 10 then pcall(function() r.CFrame = CFrame.lookAt(hrp.Position + dir.Unit * 6, hrp.Position) end) end end
                if S.AutoFace then face(hrp.Position) end
                local class = LP:GetAttribute('Class')
                if S.NoCd then if canAct() then pcall(function() m1tbl.standard(class) end) end; dt = S.NoCdRate
                else if (not m1tbl.CanAttack) and canAct() then pcall(function() m1tbl.standard(class) end) end; dt = 0.05 end
            else dt = 0.15 end
        end
        task.wait(dt)
    end
end)

-- ═══════════ DEFENSE ═══════════
-- Always Parry: override the server's "are you blocking?" query to always say yes+parry
local function setAlwaysParry(on)
    if not ICB then return end
    if on then ICB.OnClientInvoke = function() return true, true end
    else ICB.OnClientInvoke = function() local c = LP.Character; if c then return c:GetAttribute('Blocking'), c:GetAttribute('PerfectBlocking') end; return false end end
end
-- Auto Block: reactive, raise block when a nearby enemy starts a Swing
local blocking, blockUntil = false, 0
local function startBlock() local c = LP.Character; if not c then return end
    pcall(function() Block:FireServer(true) end); pcall(function() c:SetAttribute('Blocking', true); c:SetAttribute('PerfectBlocking', true); c:SetAttribute('Running', false) end); blocking = true end
local function stopBlock() local c = LP.Character; pcall(function() Block:FireServer(false) end)
    if c then pcall(function() c:SetAttribute('Blocking', false); c:SetAttribute('PerfectBlocking', false) end) end; blocking = false end
local function guard() blockUntil = tick() + S.BlockHold; if not blocking then startBlock() end end
RunService.Heartbeat:Connect(function() if blocking and tick() > blockUntil then stopBlock() end; if not S.AutoBlock and blocking then stopBlock() end end)
if Swing then Swing.OnClientEvent:Connect(function(attacker)
    if not S.AutoBlock then return end
    if typeof(attacker) ~= 'Instance' or attacker == LP.Character then return end
    local r = root(); if not r then return end
    local ap = attacker:IsA('Model') and (attacker.PrimaryPart or attacker:FindFirstChild('HumanoidRootPart'))
    if ap and (ap.Position - r.Position).Magnitude <= S.BlockRange then guard() end
end) end

-- ═══════════ MOVEMENT ═══════════
RunService.Heartbeat:Connect(function() if S.SpeedOn then local h = hum(); if h then h.WalkSpeed = S.Speed end end end)
UIS.JumpRequest:Connect(function() if S.InfJump then local h = hum(); if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end end end)
local bv, noclip
local function startFly() local r = root(); if not r then return end
    if bv then bv:Destroy() end
    bv = Instance.new('BodyVelocity'); bv.MaxForce = Vector3.new(1, 1, 1) * 1e5; bv.P = 1e4; bv.Velocity = Vector3.zero; bv.Parent = r
    noclip = RunService.Stepped:Connect(function() local c = LP.Character; if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA('BasePart') and p.CanCollide then p.CanCollide = false end end end end) end
local function stopFly() if bv then bv:Destroy(); bv = nil end; if noclip then noclip:Disconnect(); noclip = nil end end
RunService.Heartbeat:Connect(function() if S.Fly and bv then local h = hum(); if h then bv.Velocity = (h.MoveDirection.Magnitude > 0) and (cam.CFrame.LookVector * S.FlySpeed) or Vector3.zero end end end)
LP.CharacterAdded:Connect(function() if S.Fly then task.wait(1.5); startFly() end end)
local function dash() local h = hum(); local r = root(); if not (h and r and Shunpo) then return end
    local dir = h.MoveDirection; if dir.Magnitude < 0.1 then dir = cam.CFrame.LookVector end
    dir = Vector3.new(dir.X, 0, dir.Z); if dir.Magnitude < 0.1 then return end
    pcall(function() Shunpo:FireServer(r.Position + dir.Unit * 45) end) end

-- ═══════════ VISUAL: ESP ═══════════
local espCache = {}
local function destroyESP(e) pcall(function() e.hl:Destroy() end); pcall(function() e.bb:Destroy() end) end
local function makeESP(m, hrp)
    local hl = Instance.new('Highlight'); hl.FillColor = Color3.fromRGB(255, 70, 70); hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.6; hl.OutlineTransparency = 0; hl.Adornee = m; hl.Parent = m
    local bb = Instance.new('BillboardGui'); bb.Size = UDim2.new(0, 130, 0, 26); bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true; bb.Adornee = hrp; bb.Parent = hrp
    local lbl = Instance.new('TextLabel', bb); lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 12; lbl.TextColor3 = Color3.fromRGB(255, 235, 235)
    lbl.TextStrokeTransparency = 0.3
    return { hl = hl, bb = bb, lbl = lbl }
end
task.spawn(function()
    while true do
        task.wait(0.4)
        local h = workspace:FindFirstChild('Humanoids'); local r = root(); local seen = {}
        if S.ESP and h and r then
            for _, m in ipairs(h:GetChildren()) do
                if isEnemy(m) then
                    local hrp = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
                    local hh = m:FindFirstChildOfClass('Humanoid')
                    if hrp and hh and (hrp.Position - r.Position).Magnitude <= S.ESPRange then
                        seen[m] = true
                        local e = espCache[m]; if not e then e = makeESP(m, hrp); espCache[m] = e end
                        e.lbl.Text = ('%s  %d%%  [%dm]'):format(m.Name, math.floor(hh.Health / math.max(hh.MaxHealth, 1) * 100), math.floor((hrp.Position - r.Position).Magnitude))
                    end
                end
            end
        end
        for m, e in pairs(espCache) do if not seen[m] then destroyESP(e); espCache[m] = nil end end
    end
end)

-- ═══════════════════════════ UI (tabbed) ═══════════════════════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_HE_Hub'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or LP:WaitForChild('PlayerGui')
shared.__HSHub_HE_Hub = gui

local f = Instance.new('Frame', gui); f.Size = UDim2.new(0, 258, 0, 330); f.Position = UDim2.new(0, 24, 0.22, 0)
f.BackgroundColor3 = Color3.fromRGB(15, 17, 24); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 10)
local stk = Instance.new('UIStroke', f); stk.Color = Color3.fromRGB(180, 100, 50); stk.Thickness = 1.5

local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 30); hdr.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
hdr.BorderSizePixel = 0; hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 14; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Hollowed Era'; Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 10)
local minBtn = Instance.new('TextButton', hdr); minBtn.Size = UDim2.new(0, 28, 0, 24); minBtn.Position = UDim2.new(1, -30, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 20); minBtn.BorderSizePixel = 0; minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14; minBtn.TextColor3 = Color3.fromRGB(245, 245, 250); minBtn.Text = '_'; Instance.new('UICorner', minBtn).CornerRadius = UDim.new(0, 6)

local tabBar = Instance.new('Frame', f); tabBar.Position = UDim2.new(0, 6, 0, 36); tabBar.Size = UDim2.new(1, -12, 0, 26); tabBar.BackgroundTransparency = 1
local tlay = Instance.new('UIListLayout', tabBar); tlay.FillDirection = Enum.FillDirection.Horizontal; tlay.Padding = UDim.new(0, 4)
local body = Instance.new('Frame', f); body.Position = UDim2.new(0, 6, 0, 66); body.Size = UDim2.new(1, -12, 1, -72); body.BackgroundTransparency = 1

local pages, tabBtns = {}, {}
local function showTab(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and Color3.fromRGB(180, 100, 40) or Color3.fromRGB(34, 38, 50) end
end
local function makeTab(name)
    local tb = Instance.new('TextButton', tabBar); tb.Size = UDim2.new(0, 58, 1, 0); tb.BackgroundColor3 = Color3.fromRGB(34, 38, 50)
    tb.BorderSizePixel = 0; tb.Font = Enum.Font.GothamBold; tb.TextSize = 11; tb.TextColor3 = Color3.fromRGB(235, 240, 245); tb.Text = name
    Instance.new('UICorner', tb).CornerRadius = UDim.new(0, 6); tb.MouseButton1Click:Connect(function() showTab(name) end); tabBtns[name] = tb
    local p = Instance.new('ScrollingFrame', body); p.Size = UDim2.new(1, 0, 1, 0); p.BackgroundTransparency = 1; p.BorderSizePixel = 0
    p.ScrollBarThickness = 4; p.Visible = false; p.CanvasSize = UDim2.new(0, 0, 0, 0); p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local lay = Instance.new('UIListLayout', p); lay.Padding = UDim.new(0, 5); pages[name] = p
    return p
end
local function addToggle(page, label, get, set)
    local b = Instance.new('TextButton', page); b.Size = UDim2.new(1, -6, 0, 28); b.BackgroundColor3 = Color3.fromRGB(34, 38, 50)
    b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(235, 240, 245)
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    local function r() b.Text = label .. ': ' .. (get() and 'ON' or 'OFF'); b.BackgroundColor3 = get() and Color3.fromRGB(50, 110, 60) or Color3.fromRGB(34, 38, 50) end
    b.MouseButton1Click:Connect(function() set(); r() end); r()
end
local function addButton(page, label, cb)
    local b = Instance.new('TextButton', page); b.Size = UDim2.new(1, -6, 0, 28); b.BackgroundColor3 = Color3.fromRGB(55, 75, 120)
    b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(235, 240, 245); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); b.MouseButton1Click:Connect(cb)
end
local function addSlider(page, getTxt, dec, inc)
    local h = Instance.new('Frame', page); h.Size = UDim2.new(1, -6, 0, 28); h.BackgroundTransparency = 1
    local rl = Instance.new('TextLabel', h); rl.Size = UDim2.new(1, -64, 1, 0); rl.BackgroundTransparency = 1; rl.Font = Enum.Font.Code
    rl.TextSize = 12; rl.TextColor3 = Color3.fromRGB(200, 220, 240); rl.TextXAlignment = Enum.TextXAlignment.Left
    local function rt() rl.Text = getTxt() end
    local function mk(xoff, txt, cb) local b = Instance.new('TextButton', h); b.Position = UDim2.new(1, xoff, 0, 1); b.Size = UDim2.new(0, 26, 0, 26)
        b.BackgroundColor3 = Color3.fromRGB(34, 38, 50); b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 16
        b.TextColor3 = Color3.fromRGB(235, 240, 245); b.Text = txt; Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(function() cb(); rt() end) end
    mk(-58, '-', dec); mk(-28, '+', inc); rt()
end

-- COMBAT tab
local cT = makeTab('Combat')
addToggle(cT, 'Killaura', function() return S.Killaura end, function() S.Killaura = not S.Killaura end)
addToggle(cT, 'No Cooldown', function() return S.NoCd end, function() S.NoCd = not S.NoCd; applyNoCd(S.NoCd) end)
addToggle(cT, 'Teleport (reach)', function() return S.TP end, function() S.TP = not S.TP end)
addToggle(cT, 'Auto Face', function() return S.AutoFace end, function() S.AutoFace = not S.AutoFace end)
addSlider(cT, function() return 'Range: ' .. S.Range end, function() S.Range = math.max(20, S.Range - 20) end, function() S.Range = math.min(500, S.Range + 20) end)
addSlider(cT, function() return 'Extra Reach: +' .. S.ExtraReach end, function() S.ExtraReach = math.max(1, S.ExtraReach - 1); applyReach() end, function() S.ExtraReach = math.min(50, S.ExtraReach + 1); applyReach() end)

-- DEFENSE tab
local dT = makeTab('Defense')
addToggle(dT, 'Always Parry', function() return S.AlwaysParry end, function() S.AlwaysParry = not S.AlwaysParry; setAlwaysParry(S.AlwaysParry) end)
addToggle(dT, 'Auto Block (reactive)', function() return S.AutoBlock end, function() S.AutoBlock = not S.AutoBlock end)
addSlider(dT, function() return 'Block Range: ' .. S.BlockRange end, function() S.BlockRange = math.max(8, S.BlockRange - 2) end, function() S.BlockRange = math.min(60, S.BlockRange + 2) end)

-- MOVEMENT tab
local mT = makeTab('Move')
addToggle(mT, 'Walk Speed', function() return S.SpeedOn end, function() S.SpeedOn = not S.SpeedOn
    if not S.SpeedOn then local h = hum(); if h then pcall(function() h.WalkSpeed = game.StarterPlayer.CharacterWalkSpeed end) end end end)
addSlider(mT, function() return 'Speed: ' .. S.Speed end, function() S.Speed = math.max(8, S.Speed - 4) end, function() S.Speed = math.min(250, S.Speed + 4) end)
addToggle(mT, 'Infinite Jump', function() return S.InfJump end, function() S.InfJump = not S.InfJump end)
addToggle(mT, 'Fly (push stick)', function() return S.Fly end, function() S.Fly = not S.Fly; if S.Fly then startFly() else stopFly() end end)
addSlider(mT, function() return 'Fly Speed: ' .. S.FlySpeed end, function() S.FlySpeed = math.max(20, S.FlySpeed - 10) end, function() S.FlySpeed = math.min(400, S.FlySpeed + 10) end)
addButton(mT, 'Dash (Shunpo) >>', dash)

-- VISUAL tab
local vT = makeTab('Visual')
addToggle(vT, 'Enemy/Boss ESP', function() return S.ESP end, function() S.ESP = not S.ESP end)
addSlider(vT, function() return 'ESP Range: ' .. S.ESPRange end, function() S.ESPRange = math.max(100, S.ESPRange - 100) end, function() S.ESPRange = math.min(2000, S.ESPRange + 100) end)

showTab('Combat')
local mini = false
minBtn.MouseButton1Click:Connect(function() mini = not mini; tabBar.Visible = not mini; body.Visible = not mini
    f.Size = mini and UDim2.new(0, 258, 0, 36) or UDim2.new(0, 258, 0, 330) end)
