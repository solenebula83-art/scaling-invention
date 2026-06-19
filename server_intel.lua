--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · Server Intel   (the realistic "server-side dump")
    discord.gg/5rpP6faZSJ

    ⚠️ HONEST LIMIT: server SCRIPTS (ServerScriptService / ServerStorage) can NOT be dumped
    from a client. They never leave the server — that's a hard Roblox security boundary, no
    executor can read them. (We already ripped every CLIENT + SHARED module with game_ripper,
    and the server runs the SAME ReplicatedStorage modules, so we already have most logic.)

    WHAT WE CAN STILL GET (this tool):
      1. SPY — capture everything the SERVER sends YOU: every RemoteEvent OnClientEvent
         (damage dealt, drops, boss alerts, state pushes...) = live server behavior.
      2. DATA — snapshot all runtime replicated data: Value objects + attributes in
         ReplicatedStorage, your character/stats. (the "data the server gave the client")
    Run it -> play/fight a bit -> SAVE -> send the json.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_SrvIntel then pcall(function() shared.__HSHub_SrvIntel:Destroy() end) end

local Players = game:GetService('Players')
local RS      = game:GetService('ReplicatedStorage')
local WS      = game:GetService('Workspace')
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild('PlayerGui')
local HttpSvc = game:GetService('HttpService')

local incoming = {}   -- path -> { count, samples = {argstr,...} }
local total = 0
local liveLog = {}

-- ── value dumper ──
local function dumpVal(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == 'string' then return (#v > 80 and ('str[' .. #v .. ']' .. v:sub(1, 80)) or ('"' .. v .. '"'))
    elseif t == 'number' or t == 'boolean' then return tostring(v)
    elseif t == 'nil' then return 'nil'
    elseif t == 'Instance' then
        local ok, fn = pcall(function() return v:GetFullName() end)
        return '<' .. v.ClassName .. ':' .. (ok and fn or v.Name) .. '>'
    elseif t == 'Vector3' then return ('V3(%.1f,%.1f,%.1f)'):format(v.X, v.Y, v.Z)
    elseif t == 'CFrame' then local p = v.Position; return ('CF(%.1f,%.1f,%.1f)'):format(p.X, p.Y, p.Z)
    elseif t == 'EnumItem' then return tostring(v)
    elseif t == 'table' then
        if depth > 3 then return '{..}' end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1; if n > 12 then parts[#parts + 1] = '...'; break end
            parts[#parts + 1] = tostring(k) .. '=' .. dumpVal(val, depth + 1)
        end
        return '{' .. table.concat(parts, ', ') .. '}'
    end
    return '<' .. t .. '>'
end
local function dumpArgs(...)
    local a = table.pack(...); local p = {}
    for i = 1, math.min(a.n, 10) do p[i] = dumpVal(a[i]) end
    return table.concat(p, ', ')
end

-- ── spy: listen to what the SERVER fires to us ──
local function record(remote, ...)
    local ok, path = pcall(function() return remote:GetFullName() end)
    if not ok then return end
    local s = incoming[path]
    if not s then s = { count = 0, samples = {} }; incoming[path] = s end
    s.count = s.count + 1; total = total + 1
    local argstr = dumpArgs(...)
    local dup = false
    for _, sm in ipairs(s.samples) do if sm == argstr then dup = true; break end end
    if not dup and #s.samples < 6 then s.samples[#s.samples + 1] = argstr end
    if #liveLog < 400 then liveLog[#liveLog + 1] = remote.Name .. '  <=  ' .. argstr:sub(1, 64) end
end
local hooked = setmetatable({}, { __mode = 'k' })
local function listen(d)
    if hooked[d] then return end
    if d:IsA('RemoteEvent') or d:IsA('UnreliableRemoteEvent') then
        hooked[d] = true
        pcall(function() d.OnClientEvent:Connect(function(...) record(d, ...) end) end)
    end
end
for _, root in ipairs({ RS, WS, game:GetService('ReplicatedFirst') }) do
    pcall(function() for _, d in ipairs(root:GetDescendants()) do listen(d) end end)
    pcall(function() root.DescendantAdded:Connect(listen) end)
end

-- ── data: snapshot replicated runtime values + attributes ──
local function snapshot()
    local data = { values = {}, attributes = {}, player = {} }
    pcall(function()
        for _, d in ipairs(RS:GetDescendants()) do
            if d:IsA('ValueBase') then
                local ok, fn = pcall(function() return d:GetFullName() end)
                data.values[ok and fn or d.Name] = dumpVal(d.Value)
            end
            if #(data.attributes) < 300 then
                local at = d:GetAttributes()
                if next(at) then
                    local ok, fn = pcall(function() return d:GetFullName() end)
                    local m = {}; for k, v in pairs(at) do m[k] = dumpVal(v) end
                    data.attributes[ok and fn or d.Name] = m
                end
            end
        end
    end)
    pcall(function()
        for k, v in pairs(LP:GetAttributes()) do data.player['LP:' .. k] = dumpVal(v) end
        local c = LP.Character
        if c then for k, v in pairs(c:GetAttributes()) do data.player['Char:' .. k] = dumpVal(v) end end
        local ls = LP:FindFirstChild('leaderstats')
        if ls then for _, s in ipairs(ls:GetChildren()) do if s:IsA('ValueBase') then data.player['stat:' .. s.Name] = dumpVal(s.Value) end end end
    end)
    return data
end

local function save()
    local report = { tool = 'HSHub_ServerIntel', time = os.date('%Y-%m-%d %H:%M:%S'), place = game.PlaceId,
        note = 'server scripts are NOT client-readable; this = server->client traffic + replicated data',
        incoming_total = total, incoming = incoming, data = snapshot() }
    local json; pcall(function() json = HttpSvc:JSONEncode(report) end); json = json or '{}'
    local path = ('HSHub_serverintel_%d.json'):format(os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) end end)
    return saved, path
end

-- ── UI ──
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_SrvIntel'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_SrvIntel = gui
local f = Instance.new('Frame', gui); f.Size = UDim2.new(0, 310, 0, 250); f.Position = UDim2.new(0, 24, 0.28, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local stk = Instance.new('UIStroke', f); stk.Color = Color3.fromRGB(150, 120, 220); stk.Thickness = 1.5
local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 28); hdr.BackgroundColor3 = Color3.fromRGB(110, 80, 180)
hdr.BorderSizePixel = 0; hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 12; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Server Intel (spy + data)'; Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)
local cnt = Instance.new('TextLabel', f); cnt.Position = UDim2.new(0, 10, 0, 32); cnt.Size = UDim2.new(1, -20, 0, 18)
cnt.BackgroundTransparency = 1; cnt.Font = Enum.Font.Code; cnt.TextSize = 12; cnt.TextColor3 = Color3.fromRGB(200, 180, 240)
cnt.TextXAlignment = Enum.TextXAlignment.Left; cnt.Text = 'server msgs: 0  (play/fight to populate)'
local scroll = Instance.new('ScrollingFrame', f); scroll.Position = UDim2.new(0, 8, 0, 54); scroll.Size = UDim2.new(1, -16, 0, 150)
scroll.BackgroundColor3 = Color3.fromRGB(10, 12, 18); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lay = Instance.new('UIListLayout', scroll); lay.Padding = UDim.new(0, 1)
local saveBtn = Instance.new('TextButton', f); saveBtn.Position = UDim2.new(0, 8, 1, -38); saveBtn.Size = UDim2.new(1, -16, 0, 30)
saveBtn.BackgroundColor3 = Color3.fromRGB(90, 70, 150); saveBtn.BorderSizePixel = 0
saveBtn.Font = Enum.Font.GothamBold; saveBtn.TextSize = 13; saveBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
saveBtn.Text = 'SAVE  (spy + data dump)'; Instance.new('UICorner', saveBtn).CornerRadius = UDim.new(0, 6)
saveBtn.MouseButton1Click:Connect(function()
    local ok, path = save(); cnt.Text = (ok and ('SAVED: ' .. path) or 'saved to clipboard') .. ' | msgs: ' .. total
end)
local shown = 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.2)
        cnt.Text = ('server msgs: %d  (uniq remotes: %d)'):format(total, (function() local n = 0; for _ in pairs(incoming) do n = n + 1 end; return n end)())
        while shown < #liveLog do
            shown = shown + 1
            local l = Instance.new('TextLabel', scroll); l.BackgroundTransparency = 1; l.Size = UDim2.new(1, -8, 0, 13); l.LayoutOrder = shown
            l.Font = Enum.Font.Code; l.TextSize = 9; l.TextColor3 = Color3.fromRGB(190, 170, 255)
            l.TextXAlignment = Enum.TextXAlignment.Left; l.TextTruncate = Enum.TextTruncate.AtEnd; l.Text = liveLog[shown]
            scroll.CanvasSize = UDim2.new(0, 0, 0, shown * 14); scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
        end
    end
end)
