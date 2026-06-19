--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · Hollowed Era · Auto Block / Parry
    discord.gg/5rpP6faZSJ

    Built from server_intel: the server broadcasts EVERY attack hitbox via
    ClientVFX.Hitbox (CFrame/pos + size). So instead of guessing animations,
    we KNOW when an attack lands on us → block exactly then.

    Block (from the ripped Block script):
        RsPackage.Block:FireServer(true)   + attribute Blocking=true, PerfectBlocking=true
        RsPackage.Block:FireServer(false)  + Blocking=false
    PerfectBlocking = the PARRY skill — if it's set when the hit lands, you parry.
    (If your account hasn't unlocked PerfectBlocking, it falls back to a normal block.)
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_HE_Block then pcall(function() shared.__HSHub_HE_Block:Destroy() end) end

local Players = game:GetService('Players')
local RS      = game:GetService('ReplicatedStorage')
local LP      = Players.LocalPlayer

local RsPackage = RS:WaitForChild('RsPackage', 10)
local Block     = RsPackage and RsPackage:FindFirstChild('Block')
local ClientVFX = RsPackage and RsPackage:FindFirstChild('ClientVFX')
local Hitbox    = ClientVFX and ClientVFX:FindFirstChild('Hitbox')

local S = { On = false, Radius = 11, Hold = 0.45 }
local blocking, lastTrig, blocks = false, 0, 0

local function root() local c = LP.Character; return c and c:FindFirstChild('HumanoidRootPart') end

local function startBlock()
    local c = LP.Character; if not c then return end
    pcall(function() Block:FireServer(true) end)
    pcall(function() c:SetAttribute('Blocking', true); c:SetAttribute('PerfectBlocking', true); c:SetAttribute('Running', false) end)
    blocking = true
end
local function stopBlock()
    local c = LP.Character
    pcall(function() Block:FireServer(false) end)
    if c then pcall(function() c:SetAttribute('Blocking', false); c:SetAttribute('PerfectBlocking', false) end) end
    blocking = false
end

-- Hitbox args are either (CFrame, sizeV3int16) [BoxAoe] or (V3int16 pos, radius) [RoundAoe]
local function posOf(a)
    local t = typeof(a)
    if t == 'CFrame' then return a.Position
    elseif t == 'Vector3int16' then return Vector3.new(a.X, a.Y, a.Z)
    elseif t == 'Vector3' then return a end
    return nil
end

if Hitbox then
    Hitbox.OnClientEvent:Connect(function(a, _)
        if not S.On then return end
        local r = root(); if not r then return end
        local c = LP.Character
        if c:GetAttribute('M1ning') or c:GetAttribute('Attacking') then return end  -- ignore our OWN swing boxes
        local p = posOf(a); if not p then return end
        if (p - r.Position).Magnitude <= S.Radius and tick() - lastTrig > 0.12 then
            lastTrig = tick(); blocks = blocks + 1
            startBlock()
            task.delay(S.Hold, function() if tick() - lastTrig >= S.Hold - 0.01 then stopBlock() end end)
        end
    end)
end

-- ═══════════ UI ═══════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_HE_Block'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or LP:WaitForChild('PlayerGui')
shared.__HSHub_HE_Block = gui

local f = Instance.new('Frame', gui); f.Size = UDim2.new(0, 224, 0, 150); f.Position = UDim2.new(0, 270, 0.55, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local stk = Instance.new('UIStroke', f); stk.Color = Color3.fromRGB(80, 160, 220); stk.Thickness = 1.5

local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 28); hdr.BackgroundColor3 = Color3.fromRGB(45, 110, 175)
hdr.BorderSizePixel = 0; hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 13; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Auto Block / Parry'; Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)

local stat = Instance.new('TextLabel', f); stat.Position = UDim2.new(0, 10, 0, 30); stat.Size = UDim2.new(1, -20, 0, 14)
stat.BackgroundTransparency = 1; stat.Font = Enum.Font.Code; stat.TextSize = 10; stat.TextColor3 = Color3.fromRGB(150, 190, 230)
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.Text = Hitbox and 'Hitbox feed OK' or 'Hitbox remote NOT found'

local y = 48
local b = Instance.new('TextButton', f); b.Position = UDim2.new(0, 10, 0, y); b.Size = UDim2.new(1, -20, 0, 28)
b.BackgroundColor3 = Color3.fromRGB(34, 38, 50); b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 12
b.TextColor3 = Color3.fromRGB(235, 240, 245); Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
local function refB() b.Text = 'Auto Block: ' .. (S.On and 'ON' or 'OFF') end
b.MouseButton1Click:Connect(function() S.On = not S.On; if not S.On and blocking then stopBlock() end; refB() end); refB(); y = y + 32

local function slider(getTxt, dec, inc)
    local rl = Instance.new('TextLabel', f); rl.Position = UDim2.new(0, 10, 0, y); rl.Size = UDim2.new(1, -80, 0, 26)
    rl.BackgroundTransparency = 1; rl.Font = Enum.Font.Code; rl.TextSize = 12; rl.TextColor3 = Color3.fromRGB(200, 220, 240)
    rl.TextXAlignment = Enum.TextXAlignment.Left
    local function rt() rl.Text = getTxt() end
    local function mk(xoff, txt, cb) local bb = Instance.new('TextButton', f); bb.Position = UDim2.new(1, xoff, 0, y); bb.Size = UDim2.new(0, 26, 0, 26)
        bb.BackgroundColor3 = Color3.fromRGB(34, 38, 50); bb.BorderSizePixel = 0; bb.Font = Enum.Font.GothamBold; bb.TextSize = 16
        bb.TextColor3 = Color3.fromRGB(235, 240, 245); bb.Text = txt; Instance.new('UICorner', bb).CornerRadius = UDim.new(0, 6)
        bb.MouseButton1Click:Connect(function() cb(); rt() end) end
    mk(-70, '-', dec); mk(-38, '+', inc); rt(); y = y + 30
end
slider(function() return 'Detect Radius: ' .. S.Radius end,
    function() S.Radius = math.max(5, S.Radius - 1) end, function() S.Radius = math.min(30, S.Radius + 1) end)
slider(function() return 'Block Hold: ' .. S.Hold end,
    function() S.Hold = math.max(0.2, math.floor((S.Hold - 0.05) * 100 + 0.5) / 100) end,
    function() S.Hold = math.min(1.2, math.floor((S.Hold + 0.05) * 100 + 0.5) / 100) end)

task.spawn(function()
    while gui.Parent do task.wait(0.3); stat.Text = ('blocks: %d  %s'):format(blocks, blocking and '[BLOCKING]' or '') end
end)
