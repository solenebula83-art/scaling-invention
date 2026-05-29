--[[
═══════════════════════════════════════════════════════════════════════
                HS HUB · HardcoreEnvScan
   Single-shot dump of everything the artifact autofarm depends on, so we
   can compare hardcore realm vs normal realm and figure out what changed.
                    discord.gg/5rpP6faZSJ

   USE: run ONCE in HARDCORE realm. (Run again in normal realm if you want
   a baseline to diff.) Saves + clipboards HSHub_HardcoreEnvScan.json.

   What it dumps:
     - place/job id, game name (Marketplace), creator
     - all remotes named like farm/offer/anti-cheat targets, with parent path
     - Interactions tree (depth 3) -> see if "Warden Shrines"/"Food" still exist
     - Workspace TOP-LEVEL children + Terrain.WardenShrines if any
     - Every shrine tablet currently loaded (folder, name, position, TimerGui text)
     - ALL Food entries: FoodDataName, Value, T (tier), Held, position
     - Character.Data attributes (Tier, h, st, etc) + Character attrs (HeldCount,…)
     - _replicationFolder children (so we can spot new/renamed modules)
     - PlayerGui top-level (any new realm banner/warning UI)
═══════════════════════════════════════════════════════════════════════
]]

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

local out = {
    time = os.date('%Y-%m-%d %H:%M:%S'),
    place_id = game.PlaceId,
    job_id   = game.JobId,
    realm_hint = '',         -- caller fills in via game name / UI
}

-- ── helpers ─────────────────────────────────────────────────────────
local function attrs(inst)
    local t = {}
    pcall(function() for k, v in pairs(inst:GetAttributes()) do t[tostring(k)] = tostring(v) end end)
    return t
end
local function pos(inst)
    local ok, p = pcall(function()
        if inst:IsA('BasePart') then return inst.Position end
        if inst:IsA('Model') then return (inst.PrimaryPart and inst.PrimaryPart.Position) or inst:GetPivot().Position end
    end)
    if ok and p then return ('%.1f,%.1f,%.1f'):format(p.X, p.Y, p.Z) end
end
local function tree(inst, d, maxd)
    local node = { n = inst.Name, c = inst.ClassName }
    local a = attrs(inst); if next(a) then node.attr = a end
    local p = pos(inst); if p then node.pos = p end
    pcall(function()
        if inst:IsA('ValueBase') then node.value = tostring(inst.Value) end
        if inst:IsA('TextLabel') or inst:IsA('TextButton') then node.text = inst.Text end
    end)
    if d < maxd then
        local kids, n = {}, 0
        for _, ch in ipairs(inst:GetChildren()) do
            n = n + 1; if n > 120 then node.more = true; break end
            kids[#kids + 1] = tree(ch, d + 1, maxd)
        end
        if #kids > 0 then node.k = kids end
    else
        local cc = 0; pcall(function() cc = #inst:GetChildren() end)
        if cc > 0 then node.cc = cc end
    end
    return node
end

-- ── game identity ───────────────────────────────────────────────────
pcall(function()
    local info = game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId)
    if info then
        out.game_name    = info.Name
        out.game_desc    = (info.Description or ''):sub(1, 200)
        out.creator      = info.Creator and info.Creator.Name
    end
end)

-- ── interactions tree ───────────────────────────────────────────────
local inter = Workspace:FindFirstChild('Interactions')
out.has_interactions = inter ~= nil
if inter then
    -- skip the giant Food list here; dump separately below
    local node = { n = inter.Name, c = inter.ClassName, k = {} }
    for _, ch in ipairs(inter:GetChildren()) do
        if ch.Name == 'Food' then
            node.k[#node.k + 1] = { n = 'Food', c = ch.ClassName, child_count = #ch:GetChildren() }
        else
            node.k[#node.k + 1] = tree(ch, 0, 3)
        end
    end
    out.interactions = node
end

-- ── loaded shrine tablets + status text ─────────────────────────────
out.shrines = {}
local wsh = inter and inter:FindFirstChild('Warden Shrines')
if wsh then
    for _, sf in ipairs(wsh:GetChildren()) do
        local rec = { name = sf.Name, class = sf.ClassName, has_tablet = false }
        for _, d in ipairs(sf:GetDescendants()) do
            if d:IsA('BasePart') and d.Name:find('Tablet') then
                rec.has_tablet = true
                rec.tablet_name = d.Name
                rec.tablet_pos  = pos(d)
                local g = d:FindFirstChild('TimerGui')
                if g then
                    rec.timer_label  = g:FindFirstChild('TimerLabel')  and g.TimerLabel.Text
                    rec.header_label = g:FindFirstChild('HeaderLabel') and g.HeaderLabel.Text
                    rec.gui_enabled  = g:IsA('LayerCollector') and g.Enabled or nil
                end
                local pp = d:FindFirstChild('ProximityPrompt')
                if pp then
                    rec.prompt = { ActionText = pp.ActionText, ObjectText = pp.ObjectText,
                                   MaxActivationDistance = pp.MaxActivationDistance,
                                   HoldDuration = pp.HoldDuration, Enabled = pp.Enabled }
                end
                break
            end
        end
        out.shrines[#out.shrines + 1] = rec
    end
end

-- ── food dump (full attrs of every entry) ───────────────────────────
out.food = {}
local food = inter and inter:FindFirstChild('Food')
if food then
    for _, m in ipairs(food:GetChildren()) do
        out.food[#out.food + 1] = {
            name = m.Name, class = m.ClassName, pos = pos(m), attr = attrs(m),
        }
    end
end

-- ── farm/anti-cheat related remotes (paths + class) ─────────────────
out.remotes = {}
local function findAll(name, root, maxd)
    local list = {}
    local function rec(r, d)
        if d > maxd then return end
        for _, ch in ipairs(r:GetChildren()) do
            if ch.Name == name then list[#list + 1] = ch end
            rec(ch, d + 1)
        end
    end
    pcall(rec, root, 0)
    return list
end
local NAMES = {
    'WardenOffering','FoodPickup','FoodChunk','FoodDrop','Mud','Sheltered','DrinkRemote',
    'LavaSelfDamage','OxygenRemote','DrownRemote','StoreActiveCreatureRemote','CreateSlotRemote',
    'HideScent','PickupResource','DepositResource','ChunkResource','ResourceDamageRemote',
    'WardenShrine','AntiCheat','AntiExploit','Report','SecurityRemote','ValidationRemote',
    'TeleportCheck','MoveValidate',
}
for _, n in ipairs(NAMES) do
    for _, inst in ipairs(findAll(n, RS, 6)) do
        out.remotes[#out.remotes + 1] = { name = n, path = inst:GetFullName(), class = inst.ClassName }
    end
end

-- ── character: Data attrs + carry state ─────────────────────────────
local function getChar()
    local c = LP.Character
    if c and c:FindFirstChild('Data') then return c end
    local chars = Workspace:FindFirstChild('Characters')
    if chars then local b = chars:FindFirstChild(LP.Name) if b then return b end end
    return c
end
local c = getChar()
if c then
    out.character = { name = c.Name, class = c.ClassName, attr = attrs(c) }
    local d = c:FindFirstChild('Data')
    if d then out.character.data_attr = attrs(d) end
    local ail = c:FindFirstChild('Ailments')
    if ail then out.character.ailments = attrs(ail) end
end

-- ── _replicationFolder children (look for new module names) ─────────
local rf = RS:FindFirstChild('_replicationFolder')
if rf then
    out.repFolder = {}
    for _, ch in ipairs(rf:GetChildren()) do
        out.repFolder[#out.repFolder + 1] = ch.Name .. '(' .. ch.ClassName .. ')'
    end
end

-- ── Workspace top-level + PlayerGui top-level (catch realm banners) ─
out.workspace_top = {}
for _, ch in ipairs(Workspace:GetChildren()) do
    out.workspace_top[#out.workspace_top + 1] = ch.Name .. '(' .. ch.ClassName .. ')'
end
out.playergui_top = {}
for _, ch in ipairs(PG:GetChildren()) do
    out.playergui_top[#out.playergui_top + 1] = ch.Name .. '(' .. ch.ClassName .. ')'
end
-- Terrain.WardenShrines is where statues/doors live — list its shrines too
local terrain = Workspace:FindFirstChild('Terrain')
local twsh = terrain and terrain:FindFirstChild('Warden Shrines')
if twsh then
    out.terrain_shrines = {}
    for _, ch in ipairs(twsh:GetChildren()) do out.terrain_shrines[#out.terrain_shrines + 1] = ch.Name end
end

-- realm hint from name
if out.game_name then
    local n = out.game_name:lower()
    if n:find('hard') or n:find('hc') then out.realm_hint = 'looks like hardcore' end
end

-- ── save ────────────────────────────────────────────────────────────
local json
local ok = pcall(function() json = game:GetService('HttpService'):JSONEncode(out) end)
if not ok or not json then json = '{"error":"JSONEncode failed"}' end
pcall(function() if writefile then writefile('HSHub_HardcoreEnvScan.json', json) end end)
pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)

pcall(function()
    local g = Instance.new('ScreenGui'); g.Name = 'HSHub_HardcoreEnvScan'
    g.Parent = (gethui and gethui()) or game:GetService('CoreGui')
    local l = Instance.new('TextLabel', g)
    l.Size = UDim2.new(0, 540, 0, 100); l.Position = UDim2.new(0.5, -270, 0, 80)
    l.BackgroundColor3 = Color3.fromRGB(20, 20, 28); l.TextColor3 = Color3.fromRGB(150, 230, 170)
    l.Font = Enum.Font.Code; l.TextSize = 12; l.TextWrapped = true
    local nFood = #out.food; local nShr = #out.shrines; local nRem = #out.remotes
    l.Text = ('HardcoreEnvScan DONE.\nplace=%s  game=%s\nshrines=%d  food=%d  remotes=%d\nSaved HSHub_HardcoreEnvScan.json (+ clipboard).')
        :format(tostring(out.place_id), tostring(out.game_name), nShr, nFood, nRem)
    Instance.new('UICorner', l)
    task.delay(16, function() g:Destroy() end)
end)
