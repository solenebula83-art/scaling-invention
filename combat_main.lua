--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · Hollowed Era · Combat Main   (Killaura + No-Cooldown + Reach)
    discord.gg/5rpP6faZSJ

    Built from the RIPPED game code (game_ripper.lua → 829 decompiled scripts).
    Instead of faking the Swing remote (which desynced the combo = flaky), this
    drives the game's OWN M1 function so the combo number + hit-list are always
    correct. Reliable by construction.

    MECHANISM (verified in ScsPackage.CombatSystem.Combat.M1Types):
      M1Types.standard(class)  -> builds a forward box sized by M1Range,
                                  hitList = AoeModule.BoxAoe(...) (enemy Models),
                                  fires RsPackage.Swing:FireServer(combo, hitList).
      Reach     = RacesInfo[class]/SwordTypes[type].M1Range   (cached module = we mutate it)
      Cooldown  = RacesInfo...M1Cooldown  +  M1Types.CanAttack flag
    Killaura  = call standard() when ready, facing the nearest enemy.
    No-Cd     = ignore the CanAttack gate + shrink M1Cooldown (client-side; server may cap).
    Reach     = raise M1Range so the box reaches far (test: do FAR hits land?).
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_HE_Combat then pcall(function() shared.__HSHub_HE_Combat:Destroy() end) end

local Players = game:GetService('Players')
local RS      = game:GetService('ReplicatedStorage')
local LP      = Players.LocalPlayer

local RacesInfo
pcall(function() RacesInfo = require(RS.RsPackage.Modules.RacesInfo) end)

local S = {
    On       = false,   -- killaura
    NoCd     = false,   -- ignore cooldown + shrink M1Cooldown
    AutoFace = true,    -- rotate to face the nearest enemy (so the forward box hits it)
    Reach    = 60,      -- M1Range to force (default Medium sword = 9)
    Range    = 60,      -- enemy detection range
    NoCdRate = 0.14,    -- seconds between hits when No-Cd is on
}

-- ═══════════ live M1Types (the game's own attack function) ═══════════
local m1tbl
local function loadM1()
    m1tbl = nil
    local char = LP.Character
    if not char then return end
    local mod = char:FindFirstChild('M1Types', true)
    if mod and mod:IsA('ModuleScript') then
        local ok, m = pcall(require, mod)
        if ok and type(m) == 'table' then m1tbl = m end
    end
end
loadM1()
LP.CharacterAdded:Connect(function() task.wait(1.5); loadM1() end)

-- ═══════════ RacesInfo mutation (reach + cooldown), with restore ═══════════
local function raceEntries()
    local list = {}
    if type(RacesInfo) ~= 'table' then return list end
    for _, v in pairs(RacesInfo) do
        if type(v) == 'table' and type(rawget(v, 'M1Range')) == 'number' then list[#list + 1] = v end
    end
    local sw = rawget(RacesInfo, 'SwordTypes')
    if type(sw) == 'table' then
        for _, v in pairs(sw) do
            if type(v) == 'table' and type(rawget(v, 'M1Range')) == 'number' then list[#list + 1] = v end
        end
    end
    return list
end
local rangeOrig, cdOrig = {}, {}
local function applyReach(on)
    for _, e in ipairs(raceEntries()) do
        if on then
            if rangeOrig[e] == nil then rangeOrig[e] = e.M1Range end
            e.M1Range = S.Reach
        elseif rangeOrig[e] ~= nil then
            pcall(function() e.M1Range = rangeOrig[e] end); rangeOrig[e] = nil
        end
    end
end
local function applyNoCdValues(on)
    for _, e in ipairs(raceEntries()) do
        local cd = rawget(e, 'M1Cooldown')
        if type(cd) == 'table' and #cd > 0 then
            if on then
                if not cdOrig[e] then local c = {}; for i = 1, #cd do c[i] = cd[i] end; cdOrig[e] = c end
                for i = 1, #cd do cd[i] = 0.08 end
            elseif cdOrig[e] then
                for i = 1, #cdOrig[e] do cd[i] = cdOrig[e][i] end; cdOrig[e] = nil
            end
        end
    end
end

-- ═══════════ enemies ═══════════
local function getRoot()
    local c = LP.Character
    return c and (c:FindFirstChild('HumanoidRootPart') or c.PrimaryPart)
end
local function nearestEnemy()
    local hum = workspace:FindFirstChild('Humanoids'); local root = getRoot()
    if not hum or not root then return nil end
    local best, bestD
    for _, m in ipairs(hum:GetChildren()) do
        if m:IsA('Model') and not Players:GetPlayerFromCharacter(m) then
            local h = m:FindFirstChildOfClass('Humanoid')
            local hrp = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
            if h and h.Health > 0 and hrp then
                local d = (hrp.Position - root.Position).Magnitude
                if d <= S.Range and (not bestD or d < bestD) then best, bestD = hrp, d end
            end
        end
    end
    return best
end
local function face(pos)
    local root = getRoot(); if not root then return end
    local p = root.Position
    pcall(function() root.CFrame = CFrame.lookAt(p, Vector3.new(pos.X, p.Y, pos.Z)) end)
end
-- SAFE local copy of UsefulModule.CanAttackIgnoringAttacking — WITHOUT the anti-exploit Kick
-- tripwire (the real CanAttack kicks you if ReplicatedFirst.AnimationHandler is missing, and we
-- call this very often). We never touch the game's CanAttack; calling standard() directly also
-- bypasses onM1Attempt's kick-gate.
local function canAct()
    local char = LP.Character
    if not char then return false end
    local h = char:FindFirstChildOfClass('Humanoid')
    if not h or h.Health <= 0 then return false end
    if h:GetState() == Enum.HumanoidStateType.Physics then return false end
    if char:FindFirstChild('Stun', true) then return false end
    if char:GetAttribute('Blocking') or char:GetAttribute('MiscActing') or char:GetAttribute('Carrying')
        or char:GetAttribute('Dominated') or char:GetAttribute('Downed') or char:GetAttribute('InCutscene') then
        return false
    end
    return true
end

-- ═══════════ killaura loop ═══════════
local enemyCount = 0
task.spawn(function()
    while true do
        local dt = 0.2
        if S.On and m1tbl then
            local hrp = nearestEnemy()
            if hrp then
                if S.AutoFace then face(hrp.Position) end
                local class = LP:GetAttribute('Class')
                if S.NoCd then
                    if canAct() then pcall(function() m1tbl.standard(class) end) end
                    dt = S.NoCdRate
                else
                    if (not m1tbl.CanAttack) and canAct() then pcall(function() m1tbl.standard(class) end) end
                    dt = 0.05
                end
            else
                dt = 0.15
            end
        end
        task.wait(dt)
    end
end)

-- ═══════════ UI ═══════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_HE_Combat'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or LP:WaitForChild('PlayerGui')
shared.__HSHub_HE_Combat = gui

local f = Instance.new('Frame', gui); f.Size = UDim2.new(0, 236, 0, 232); f.Position = UDim2.new(0, 24, 0.38, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local stk = Instance.new('UIStroke', f); stk.Color = Color3.fromRGB(200, 120, 60); stk.Thickness = 1.5

local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 28); hdr.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
hdr.BorderSizePixel = 0; hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 13; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Combat (Hollowed Era)'; Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)

local status = Instance.new('TextLabel', f); status.Position = UDim2.new(0, 10, 0, 30); status.Size = UDim2.new(1, -20, 0, 14)
status.BackgroundTransparency = 1; status.Font = Enum.Font.Code; status.TextSize = 10; status.TextColor3 = Color3.fromRGB(150, 200, 150)
status.TextXAlignment = Enum.TextXAlignment.Left; status.Text = '...'

local y = 48
local function toggleRow(label, get, set)
    local b = Instance.new('TextButton', f); b.Position = UDim2.new(0, 10, 0, y); b.Size = UDim2.new(1, -20, 0, 28)
    b.BackgroundColor3 = Color3.fromRGB(34, 38, 50); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(235, 240, 245)
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    local function r() b.Text = label .. ': ' .. (get() and 'ON' or 'OFF') end
    b.MouseButton1Click:Connect(function() set(); r() end); r(); y = y + 32
end
toggleRow('Killaura',   function() return S.On end,       function() S.On = not S.On end)
toggleRow('No Cooldown',function() return S.NoCd end,     function() S.NoCd = not S.NoCd; applyNoCdValues(S.NoCd) end)
toggleRow('Auto Face',  function() return S.AutoFace end, function() S.AutoFace = not S.AutoFace end)

-- reach slider row (M1Range)
local rl = Instance.new('TextLabel', f); rl.Position = UDim2.new(0, 10, 0, y); rl.Size = UDim2.new(1, -80, 0, 26)
rl.BackgroundTransparency = 1; rl.Font = Enum.Font.Code; rl.TextSize = 12; rl.TextColor3 = Color3.fromRGB(200, 220, 240)
rl.TextXAlignment = Enum.TextXAlignment.Left
local function rtxt() rl.Text = 'Reach(M1Range): ' .. S.Reach end
local function mkBtn(xoff, txt) local b = Instance.new('TextButton', f); b.Position = UDim2.new(1, xoff, 0, y); b.Size = UDim2.new(0, 26, 0, 26)
    b.BackgroundColor3 = Color3.fromRGB(34, 38, 50); b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 16
    b.TextColor3 = Color3.fromRGB(235, 240, 245); b.Text = txt; Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6); return b end
local minus, plus = mkBtn(-70, '-'), mkBtn(-38, '+')
minus.MouseButton1Click:Connect(function() S.Reach = math.max(8, S.Reach - 10); S.Range = S.Reach; applyReach(true); rtxt() end)
plus.MouseButton1Click:Connect(function() S.Reach = math.min(400, S.Reach + 10); S.Range = S.Reach; applyReach(true); rtxt() end)
rtxt(); y = y + 30

-- keep reach applied (so far hits work whenever killaura/reach is desired)
applyReach(true)

task.spawn(function()
    while gui.Parent do
        task.wait(0.4)
        local n = 0
        local hum = workspace:FindFirstChild('Humanoids'); local root = getRoot()
        if hum and root then for _, m in ipairs(hum:GetChildren()) do
            if m:IsA('Model') and not Players:GetPlayerFromCharacter(m) then
                local h = m:FindFirstChildOfClass('Humanoid'); local hrp = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
                if h and h.Health > 0 and hrp and (hrp.Position - root.Position).Magnitude <= S.Range then n = n + 1 end
            end
        end end
        enemyCount = n
        status.Text = (m1tbl and ('M1 ready · %d enemies'):format(n) or 'M1Types NOT loaded (respawn?)')
    end
end)
