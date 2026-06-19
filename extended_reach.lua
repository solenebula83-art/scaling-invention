--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · Hollowed Era · Extended Reach  (simple main script)
    Makes your melee reach further by ENLARGING nearby enemy hitboxes
    (their HumanoidRootPart / Hitbox part) so your normal M1 (tap) connects
    from a distance. 100% client-side, restores every size when OFF.

    This is a DIFFERENT mechanism than firing the Swing remote (which kept
    failing) — it changes geometry, not packets. It WORKS IF the game's hit
    detection reads hitbox size/bounds. If the server checks range on its own,
    this won't extend reach — then run game_ripper.lua and I'll switch to the
    exact method from the real combat code (no more guessing).
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_HE_Reach then pcall(function() shared.__HSHub_HE_Reach:Destroy() end) end

local Players   = game:GetService('Players')
local LP        = Players.LocalPlayer
local Humanoids = workspace:WaitForChild('Humanoids', 10)

local S = {
    On    = false,
    Reach = 16,    -- studs ADDED to each side of the hitbox (bigger = more reach, more obvious)
    Range = 120,   -- only enlarge enemies within this distance (keeps it light)
}
local orig = {}    -- part -> { size, canc } original values

-- ── helpers ──
local function getRoot()
    local c = LP.Character
    return c and (c:FindFirstChild('HumanoidRootPart') or c.PrimaryPart)
end
local function isEnemy(m)
    if not m:IsA('Model') then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    local h = m:FindFirstChildOfClass('Humanoid')
    if not h or h.Health <= 0 then return false end
    return m:FindFirstChild('CombatSystem') ~= nil or m.Name:lower():find('hollow') ~= nil
end
local function hitboxOf(m)
    return m:FindFirstChild('HumanoidRootPart') or m:FindFirstChild('Hitbox')
        or m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')
end
local function enlarge(p)
    if not orig[p] then orig[p] = { size = p.Size, canc = p.CanCollide } end
    pcall(function()
        p.Size = orig[p].size + Vector3.new(S.Reach, S.Reach, S.Reach)
        p.CanCollide = false                 -- avoid launching the enemy/you with the bigger box
    end)
end
local function restore(p)
    if orig[p] then pcall(function() p.Size = orig[p].size; p.CanCollide = orig[p].canc end); orig[p] = nil end
end
local function restoreAll() for p in pairs(orig) do restore(p) end end

-- ── main loop ──
task.spawn(function()
    while true do
        if S.On and Humanoids then
            local root = getRoot()
            local active = {}
            if root then
                for _, m in ipairs(Humanoids:GetChildren()) do
                    if isEnemy(m) then
                        local hb = hitboxOf(m)
                        if hb then
                            local d = (hb.Position - root.Position).Magnitude
                            if d <= S.Range then enlarge(hb); active[hb] = true end
                        end
                    end
                end
            end
            for p in pairs(orig) do if not active[p] then restore(p) end end   -- shrink ones that left range/died
            task.wait(0.3)
        else
            if next(orig) then restoreAll() end
            task.wait(0.3)
        end
    end
end)

-- ── minimal UI ──
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_HE_Reach'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or LP:WaitForChild('PlayerGui')
shared.__HSHub_HE_Reach = gui

local f = Instance.new('Frame', gui); f.Size = UDim2.new(0, 220, 0, 120); f.Position = UDim2.new(0, 24, 0.45, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local st = Instance.new('UIStroke', f); st.Color = Color3.fromRGB(90, 150, 220); st.Thickness = 1.5

local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 28); hdr.BackgroundColor3 = Color3.fromRGB(55, 100, 170)
hdr.BorderSizePixel = 0; hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 13; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Extended Reach'; Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)

local toggle = Instance.new('TextButton', f); toggle.Position = UDim2.new(0, 10, 0, 36); toggle.Size = UDim2.new(1, -20, 0, 30)
toggle.BackgroundColor3 = Color3.fromRGB(34, 38, 50); toggle.BorderSizePixel = 0
toggle.Font = Enum.Font.GothamBold; toggle.TextSize = 13; toggle.TextColor3 = Color3.fromRGB(235, 240, 245)
Instance.new('UICorner', toggle).CornerRadius = UDim.new(0, 6)
local function refT() toggle.Text = 'Extended Reach: ' .. (S.On and 'ON' or 'OFF') end
toggle.MouseButton1Click:Connect(function() S.On = not S.On; refT() end); refT()

local rl = Instance.new('TextLabel', f); rl.Position = UDim2.new(0, 10, 0, 74); rl.Size = UDim2.new(1, -80, 0, 26)
rl.BackgroundTransparency = 1; rl.Font = Enum.Font.Code; rl.TextSize = 12; rl.TextColor3 = Color3.fromRGB(200, 220, 240)
rl.TextXAlignment = Enum.TextXAlignment.Left
local function rtxt() rl.Text = 'Reach +' .. S.Reach end
local minus = Instance.new('TextButton', f); minus.Position = UDim2.new(1, -70, 0, 74); minus.Size = UDim2.new(0, 26, 0, 26)
minus.BackgroundColor3 = Color3.fromRGB(34, 38, 50); minus.BorderSizePixel = 0; minus.Font = Enum.Font.GothamBold
minus.TextSize = 16; minus.TextColor3 = Color3.fromRGB(235, 240, 245); minus.Text = '-'
Instance.new('UICorner', minus).CornerRadius = UDim.new(0, 6)
local plus = Instance.new('TextButton', f); plus.Position = UDim2.new(1, -38, 0, 74); plus.Size = UDim2.new(0, 26, 0, 26)
plus.BackgroundColor3 = Color3.fromRGB(34, 38, 50); plus.BorderSizePixel = 0; plus.Font = Enum.Font.GothamBold
plus.TextSize = 16; plus.TextColor3 = Color3.fromRGB(235, 240, 245); plus.Text = '+'
Instance.new('UICorner', plus).CornerRadius = UDim.new(0, 6)
minus.MouseButton1Click:Connect(function() S.Reach = math.max(2, S.Reach - 2); rtxt() end)
plus.MouseButton1Click:Connect(function() S.Reach = math.min(60, S.Reach + 2); rtxt() end)
rtxt()
