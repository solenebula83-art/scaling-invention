--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · Hollowed Era · Combat Capture  (dead simple)
    NO Start button, NO labels. It records the MOMENT it's injected.
    WORKFLOW:
        1. Join Hollowed Era (FRESH — rejoin if you ran a capture before)
        2. Paste this
        3. Walk to a Hollow and land ~5 M1 hits (the counter goes up live)
        4. Click  SAVE  → send the JSON file
    Only YOUR client's remote fires are caught, so nearby players don't matter.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_CombatCap then pcall(function() shared.__HSHub_CombatCap:Destroy() end) end

local Players = game:GetService('Players')
local RS      = game:GetService('ReplicatedStorage')
local WS      = game:GetService('Workspace')
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild('PlayerGui')
local HttpSvc = game:GetService('HttpService')

local cc      = checkcaller
local summary = {}     -- path -> { count, name, method, samples = {argstr,...} }
local total   = 0
local liveLog = {}

-- ── value/arg dumper (full args, so we see the hit-list + damage values) ──
local function dumpVal(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == 'string' then return (#v > 100 and ('str[' .. #v .. ']' .. v:sub(1, 100)) or ('"' .. v .. '"'))
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
            n = n + 1; if n > 15 then parts[#parts + 1] = '...+'; break end
            parts[#parts + 1] = tostring(k) .. '=' .. dumpVal(val, depth + 1)
        end
        return '{' .. table.concat(parts, ', ') .. '}'
    end
    return '<' .. t .. '>'
end
local function dumpArgs(a, n)
    local p = {}
    for i = 1, math.min(n or 0, 12) do p[i] = dumpVal(a[i]) end
    return table.concat(p, ', ')
end

local function record(self, method, ...)
    if cc and cc() then return end                 -- skip our own (executor) fires
    local ok, path = pcall(function() return self:GetFullName() end)
    if not ok then return end
    local s = summary[path]
    if not s then s = { count = 0, name = self.Name, method = method, samples = {} }; summary[path] = s end
    s.count = s.count + 1; total = total + 1
    local a = table.pack(...)
    local argstr = dumpArgs(a, a.n)
    local dup = false
    for _, sm in ipairs(s.samples) do if sm == argstr then dup = true; break end end
    if not dup and #s.samples < 6 then s.samples[#s.samples + 1] = argstr end
    if #liveLog < 400 then liveLog[#liveLog + 1] = self.Name .. '.' .. method .. '(' .. argstr:sub(1, 70) .. ')' end
end

-- ── install hooks (hookfunction on the shared C-closures + __namecall) ──
local function findSample(cls)
    for _, root in ipairs({ RS, WS, LP, PG }) do
        local found
        pcall(function()
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA(cls) then found = d; break end
            end
        end)
        if found then return found end
    end
end
pcall(function()
    if not hookfunction then return end
    local re = findSample('RemoteEvent')
    if re then local o; o = hookfunction(re.FireServer, function(self, ...) record(self, 'FireServer', ...); return o(self, ...) end) end
    local rf = findSample('RemoteFunction')
    if rf then local o; o = hookfunction(rf.InvokeServer, function(self, ...) record(self, 'InvokeServer', ...); return o(self, ...) end) end
    local ur = findSample('UnreliableRemoteEvent')
    if ur then local o; o = hookfunction(ur.FireServer, function(self, ...) record(self, 'FireServer(Unrel)', ...); return o(self, ...) end) end
end)
pcall(function()
    local mt = getrawmetatable(game); if not mt or not mt.__namecall then return end
    local sr = setreadonly or make_writeable; if sr then pcall(sr, mt, false) end
    local old = mt.__namecall
    local FIRE = { FireServer = true, InvokeServer = true }
    local newfn = function(self, ...)
        local m = getnamecallmethod and getnamecallmethod() or ''
        if FIRE[m] then
            local ok, cls = pcall(function() return self.ClassName end)
            if ok and (cls == 'RemoteEvent' or cls == 'RemoteFunction' or cls == 'UnreliableRemoteEvent') then
                record(self, m, ...)
            end
        end
        return old(self, ...)
    end
    mt.__namecall = (newcclosure and newcclosure(newfn)) or newfn
end)

-- ── save ──
local function save()
    local report = { tool = 'HSHub_CombatCapture', time = os.date('%Y-%m-%d %H:%M:%S'),
        place = game.PlaceId, total_fires = total, summary = summary }
    local json
    pcall(function() json = HttpSvc:JSONEncode(report) end)
    json = json or '{}'
    local path = ('HSHub_combatcap_%d.json'):format(os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) end end)
    return saved, path
end

-- ── UI ──
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_CombatCap'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_CombatCap = gui

local f = Instance.new('Frame', gui)
f.Size = UDim2.new(0, 300, 0, 250); f.Position = UDim2.new(0, 24, 0.3, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local strk = Instance.new('UIStroke', f); strk.Color = Color3.fromRGB(200, 120, 60); strk.Thickness = 1.5

local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 28)
hdr.BackgroundColor3 = Color3.fromRGB(180, 100, 40); hdr.BorderSizePixel = 0
hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 12; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Combat Capture (fight then Save)'
Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)

local cnt = Instance.new('TextLabel', f); cnt.Position = UDim2.new(0, 10, 0, 32); cnt.Size = UDim2.new(1, -20, 0, 18)
cnt.BackgroundTransparency = 1; cnt.Font = Enum.Font.Code; cnt.TextSize = 12
cnt.TextColor3 = Color3.fromRGB(150, 230, 150); cnt.TextXAlignment = Enum.TextXAlignment.Left
cnt.Text = 'fires: 0   (now hit a Hollow)'

local scroll = Instance.new('ScrollingFrame', f); scroll.Position = UDim2.new(0, 8, 0, 54); scroll.Size = UDim2.new(1, -16, 0, 150)
scroll.BackgroundColor3 = Color3.fromRGB(10, 12, 18); scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 4
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local lay = Instance.new('UIListLayout', scroll); lay.Padding = UDim.new(0, 1)

local saveBtn = Instance.new('TextButton', f); saveBtn.Position = UDim2.new(0, 8, 1, -38); saveBtn.Size = UDim2.new(1, -16, 0, 30)
saveBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 90); saveBtn.BorderSizePixel = 0
saveBtn.Font = Enum.Font.GothamBold; saveBtn.TextSize = 13; saveBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
saveBtn.Text = 'SAVE  (send the file)'
Instance.new('UICorner', saveBtn).CornerRadius = UDim.new(0, 6)
saveBtn.MouseButton1Click:Connect(function()
    local ok, path = save()
    cnt.Text = (ok and ('SAVED: ' .. path) or 'saved to clipboard') .. ' | fires: ' .. total
end)

local shown = 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.2)
        cnt.Text = ('fires: %d   (hit a Hollow, then SAVE)'):format(total)
        while shown < #liveLog do
            shown = shown + 1
            local l = Instance.new('TextLabel', scroll)
            l.BackgroundTransparency = 1; l.Size = UDim2.new(1, -8, 0, 13); l.LayoutOrder = shown
            l.Font = Enum.Font.Code; l.TextSize = 9; l.TextColor3 = Color3.fromRGB(120, 210, 255)
            l.TextXAlignment = Enum.TextXAlignment.Left; l.TextTruncate = Enum.TextTruncate.AtEnd
            l.Text = liveLog[shown]
            scroll.CanvasSize = UDim2.new(0, 0, 0, shown * 14)
            scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
        end
    end
end)
