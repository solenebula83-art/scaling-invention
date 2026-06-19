--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · CoS · Trade Realm — Unlock + Bypass
    discord.gg/5rpP6faZSJ

    From the ripped code (PlaceService.GetRealmData("Trade").CanAccess):
      CanAccess(player) == true if ANY of:
        • PlayerData.Monetization.TradesCompleted.Value > 0     <- SHORTCUT (skips age/species/verify)
        • PlayerData.MarketStalls.ShoomsRaised.Value   > 0       <- SHORTCUT (skips age/species/verify)
        • HasSpeciesRequirement & HasAccountAgeRequirement & IsTradeVerified
      The shortcuts bypass age + verify entirely (matches the "excluded age verify" unlock).
      Those flags live in REPLICATED PlayerData Value objects -> reachable client-side via
      PlayerWrapper.getWrapperFromPlayer(LocalPlayer).

    Buttons:
      UNLOCK  = set the shortcut flags (TradesCompleted/ShoomsRaised = 1) + pass the client req
                checks. If the writes stick / are read client-side -> CanAccess returns true.
      ENTER   = the entry bypass (TeleportToPlace remote ignores the requirements on teleport).

    TEST after: enter the realm and try to LIST a trade / open a stall / bid.
      • works  -> unlocked.
      • "not allowed" -> the server re-reads its own data; next step = run game_ripper INSIDE the
        Trade Realm place (we get there via ENTER) so we can read the realm's own gate / remotes.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_CoS_TR then pcall(function() shared.__HSHub_CoS_TR:Destroy() end) end

local Players = game:GetService('Players')
local RS      = game:GetService('ReplicatedStorage')
local LP      = Players.LocalPlayer

local Sonar, TradeService, RemoteUtils, Constants, PlayerWrapper, teleport
pcall(function() Sonar = require(RS:WaitForChild('Sonar', 10)) end)
if Sonar then
    pcall(function() TradeService  = Sonar('TradeService') end)
    pcall(function() RemoteUtils   = Sonar('RemoteUtils') end)
    pcall(function() Constants     = Sonar('Constants') end)
    pcall(function() PlayerWrapper = Sonar('PlayerWrapper') end)
    pcall(function() teleport      = RemoteUtils and RemoteUtils.GetRemoteEvent('TeleportToPlace') end)
end

-- make the CLIENT requirement checks pass (species + age; verify left alone)
local function hookReqs()
    if not TradeService then return end
    pcall(function() TradeService.HasAccountAgeRequirement = function(_) return true, 9999 end end)
    pcall(function() TradeService.HasSpeciesRequirement   = function(_) return true, 9999 end end)
end

-- set the auto-pass shortcut flags in PlayerData (the real unlock attempt)
local function getPData()
    local w; pcall(function() w = PlayerWrapper and PlayerWrapper.getWrapperFromPlayer(LP) end)
    return w and w.PlayerData
end
local function setFlag(pdata, folder, name, val)
    local f = pdata:FindFirstChild(folder); local o = f and f:FindFirstChild(name)
    if o then local ok = pcall(function() o.Value = val end); return ok and tostring(o.Value) or 'err' end
    return 'missing'
end
local reapply = false
local function unlock()
    hookReqs()
    local pd = getPData(); if not pd then return false, 'PlayerData not found (tell me)' end
    local a = setFlag(pd, 'Monetization', 'TradesCompleted', 1)
    local b = setFlag(pd, 'MarketStalls', 'ShoomsRaised', 1)
    reapply = true                                       -- keep flags set if the server re-syncs the folder
    return true, ('trades=%s shrooms=%s (reqs hooked)'):format(a, b)
end
task.spawn(function()
    while true do
        if reapply then local pd = getPData(); if pd then setFlag(pd, 'Monetization', 'TradesCompleted', 1); setFlag(pd, 'MarketStalls', 'ShoomsRaised', 1) end end
        task.wait(1)
    end
end)

local function enter()
    if not (teleport and Constants and Constants.TradeRealmId) then return false, 'remote/id missing' end
    local ok = pcall(function() teleport:FireServer(Constants.TradeRealmId) end)
    return ok, ok and ('teleporting -> ' .. tostring(Constants.TradeRealmId)) or 'fire failed'
end

-- TEST: block client-initiated teleports BACK to the main realm. Survives the on-arrival kick ONLY
-- if that kick is client-side. If the realm boots you server-side, this can't stop it (that's the test).
local blockReturn = false
pcall(function()
    if not hookmetamethod then return end
    local TS = game:GetService('TeleportService')
    local old
    old = hookmetamethod(game, '__namecall', function(self, ...)
        if blockReturn and Constants then
            local m = getnamecallmethod and getnamecallmethod()
            local a = { ... }
            if self == teleport and m == 'FireServer' and a[1] == Constants.MainGameId then return end
            if self == TS and (m == 'Teleport' or m == 'TeleportAsync' or m == 'TeleportToPlaceInstance') and a[1] == Constants.MainGameId then return end
        end
        return old(self, ...)
    end)
end)

-- ═══════════ UI ═══════════
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_CoS_TR'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or LP:WaitForChild('PlayerGui')
shared.__HSHub_CoS_TR = gui

local f = Instance.new('Frame', gui); f.Size = UDim2.new(0, 256, 0, 192); f.Position = UDim2.new(0, 24, 0.38, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local stk = Instance.new('UIStroke', f); stk.Color = Color3.fromRGB(120, 200, 120); stk.Thickness = 1.5

local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 28); hdr.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
hdr.BorderSizePixel = 0; hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 13; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Trade Realm Unlock'; Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)

local stat = Instance.new('TextLabel', f); stat.Position = UDim2.new(0, 10, 0, 32); stat.Size = UDim2.new(1, -20, 0, 36)
stat.BackgroundTransparency = 1; stat.Font = Enum.Font.Code; stat.TextSize = 10; stat.TextColor3 = Color3.fromRGB(150, 210, 150)
stat.TextWrapped = true; stat.TextXAlignment = Enum.TextXAlignment.Left; stat.TextYAlignment = Enum.TextYAlignment.Top
stat.Text = (teleport and PlayerWrapper) and 'ready' or 'ERROR: Sonar modules not found — tell me'

local function mkBtn(yy, txt, col, cb)
    local b = Instance.new('TextButton', f); b.Position = UDim2.new(0, 10, 0, yy); b.Size = UDim2.new(1, -20, 0, 32)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = txt; Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(cb)
end
mkBtn(72, 'UNLOCK (set flags + reqs)', Color3.fromRGB(50, 110, 70), function()
    local ok, msg = unlock(); stat.Text = msg
end)
local brBtn = Instance.new('TextButton', f); brBtn.Position = UDim2.new(0, 10, 0, 108); brBtn.Size = UDim2.new(1, -20, 0, 32)
brBtn.BorderSizePixel = 0; brBtn.Font = Enum.Font.GothamBold; brBtn.TextSize = 13; brBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
Instance.new('UICorner', brBtn).CornerRadius = UDim.new(0, 6)
local function refBR() brBtn.Text = 'Block Return: ' .. (blockReturn and 'ON' or 'OFF'); brBtn.BackgroundColor3 = blockReturn and Color3.fromRGB(150, 90, 40) or Color3.fromRGB(34, 38, 50) end
brBtn.MouseButton1Click:Connect(function() blockReturn = not blockReturn; refBR() end); refBR()
mkBtn(146, 'ENTER Trade Realm', Color3.fromRGB(55, 90, 140), function()
    local ok, msg = enter(); stat.Text = msg
end)
