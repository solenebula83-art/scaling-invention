--[[
═══════════════════════════════════════════════════════════════════════
                    HS HUB · ActionSpy
        Label-driven action→remote capture (spawn / restart /
        invisible / hide-scent / eat / drink) + death detection
                    discord.gg/5rpP6faZSJ

    WHY (the 50-100-try lesson):
        Automating by SIMULATING UI CLICKS is fragile (button position,
        render timing, UI state) — that's why auto-store-fruit took 100
        tries. The robust way is to capture the REMOTE each action fires,
        then replay it with FireServer/InvokeServer. This tool captures it.

    HOW IT WORKS:
        Hooks EVERY FireServer + InvokeServer (the shared C-closure, so it
        catches CoS's dot-call fires too — same proven method as DamageSpy).
        You set a LABEL, do ONE action manually, and every remote that fires
        is tagged with that label. Read the JSON → which remote = which action.

    WORKFLOW (one session captures everything):
        1. Open the spawn/play menu, paste this, click ▶ Start.
        2. Type a label in the box, e.g.  SPAWN-newcreature  → tap "Set Label".
        3. Do the action ONCE (create creature → category → creature → slot →
           Play). Watch the live log — the spawn remotes appear.
        4. Set label  SPAWN-existing-slot  → select an ALIVE slot → Play.
        5. Set label  RESTART-dead         → select a DEAD slot → Restart.
        6. Set label  INVIS  → activate the invisible skill.
        7. Set label  SCENT  → hide scent.   Then  EAT , then  DRINK .
        8. ■ Stop  →  💾 Save  → send the JSON.

    Do each action SLOWLY and ALONE so its remotes aren't mixed with others.
    DEATH events (Character removed / health→0) are auto-logged so we know
    how to detect death for the auto-restart.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_ActionSpy then
    pcall(function() shared.__HSHub_ActionSpy:Destroy() end)
end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

-- ═════════════ STATE ═════════════════════════════════════════════
local ACTIVE     = false
local START      = 0
local curLabel   = '(none)'
local summary    = {}     -- name -> {count, method, label->count, sample}
local timeline   = {}     -- {t, name, method, args, label}
local labels     = {}     -- {t, label}
local deaths     = {}     -- {t, how, label}
local MAX_TL     = 1800
local hookStatus = 'init'

local function now() return tick() - START end

-- ═════════════ CHARACTER ═════════════════════════════════════════
local function getChar()
    local c = LP.Character
    if c and c:FindFirstChild('Data') then return c end
    local chars = Workspace:FindFirstChild('Characters')
    if chars then
        local byName = chars:FindFirstChild(LP.Name)
        if byName then return byName end
    end
    return c
end

-- ═════════════ ARG DUMP (full, typed, paths) ═════════════════════
local function dumpVal(v, depth)
    depth = depth or 0
    local t = typeof and typeof(v) or type(v)
    if t == 'string' then
        if #v > 160 then return 'str['..#v..'B]:'..v:sub(1,160) end
        return '"'..v..'"'
    elseif t == 'number' or t == 'boolean' then
        return tostring(v)
    elseif t == 'nil' then
        return 'nil'
    elseif t == 'Instance' then
        local ok, nm = pcall(function() return v:GetFullName() end)
        return ('<%s %s>'):format(v.ClassName, ok and nm or v.Name)
    elseif t == 'Vector3' then
        return ('Vec3(%.1f,%.1f,%.1f)'):format(v.X, v.Y, v.Z)
    elseif t == 'CFrame' then
        local p = v.Position; return ('CFrame@(%.1f,%.1f,%.1f)'):format(p.X, p.Y, p.Z)
    elseif t == 'table' then
        if depth > 2 then return '{..}' end
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 12 then parts[#parts+1] = '...'; break end
            parts[#parts+1] = tostring(k)..'='..dumpVal(val, depth+1)
        end
        return '{'..table.concat(parts, ', ')..'}'
    end
    return '<'..t..'>'
end

local function dumpArgs(a, n)
    local p = {}
    local lim = math.min(n or 0, 8)
    for i = 1, lim do p[i] = dumpVal(a[i]) end
    return table.concat(p, ', ')
end

-- ═════════════ RECORD ════════════════════════════════════════════
local liveQueue = {}     -- {t,name,method,args,label} for the live log
local function recordCall(name, method, argstr)
    local s = summary[name]
    if not s then
        s = { count = 0, method = method, labels = {}, sample = argstr }
        summary[name] = s
    end
    s.count = s.count + 1
    s.labels[curLabel] = (s.labels[curLabel] or 0) + 1
    if #timeline < MAX_TL then
        timeline[#timeline+1] = { t = now(), name = name, method = method, args = argstr, label = curLabel }
    end
    liveQueue[#liveQueue+1] = { t = now(), name = name, method = method, args = argstr, label = curLabel }
end

-- ═════════════ UNIVERSAL HOOKS (no filter) ═══════════════════════
local function findSample(className)
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA(className) then return d end
    end
    return nil
end

pcall(function()
    if not hookfunction then hookStatus = 'NO hookfunction — executor incompatible'; return end
    local cc = checkcaller
    local sampleEvent = findSample('RemoteEvent')
    local sampleFn    = findSample('RemoteFunction')
    local okE, okF = false, false

    if sampleEvent then
        local of
        okE = pcall(function()
            of = hookfunction(sampleEvent.FireServer, function(self, ...)
                if ACTIVE and not (cc and cc()) then
                    local a = table.pack(...)
                    pcall(recordCall, self.Name, 'FireServer', dumpArgs(a, a.n))
                end
                return of(self, ...)
            end)
        end)
    end
    if sampleFn then
        local oi
        okF = pcall(function()
            oi = hookfunction(sampleFn.InvokeServer, function(self, ...)
                if ACTIVE and not (cc and cc()) then
                    local a = table.pack(...)
                    pcall(recordCall, self.Name, 'InvokeServer', dumpArgs(a, a.n))
                end
                return oi(self, ...)
            end)
        end)
    end
    hookStatus = ('FireServer:%s  InvokeServer:%s'):format(
        okE and 'OK' or (sampleEvent and 'FAIL' or 'no-sample'),
        okF and 'OK' or (sampleFn and 'FAIL' or 'no-sample'))
end)

-- ═════════════ DEATH DETECTION ═══════════════════════════════════
local watched, lastH = nil, nil
local function attachWatch()
    local c = getChar()
    if not c or watched == c then return end
    local data = c:FindFirstChild('Data')
    if not data then return end
    watched = c
    lastH = tonumber(data:GetAttribute('h'))
    pcall(function()
        data:GetAttributeChangedSignal('h'):Connect(function()
            local h = tonumber(data:GetAttribute('h'))
            if ACTIVE and h and h <= 0 and (lastH == nil or lastH > 0) then
                deaths[#deaths+1] = { t = now(), how = 'health<=0', label = curLabel }
            end
            lastH = h
        end)
    end)
end
task.spawn(function() while true do task.wait(0.5); pcall(attachWatch) end end)
LP.CharacterRemoving:Connect(function()
    if ACTIVE then deaths[#deaths+1] = { t = now(), how = 'CharacterRemoving', label = curLabel } end
end)
LP.CharacterAdded:Connect(function() watched = nil; task.wait(1); pcall(attachWatch) end)

-- ═════════════ JSON ══════════════════════════════════════════════
local function toJSON(v, indent)
    indent = indent or 0
    local pad1 = string.rep('  ', indent + 1)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' or t == 'number' then return tostring(v) end
    if t == 'string' then
        return '"' .. v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t') .. '"'
    end
    if t == 'table' then
        local isArr, maxK = true, 0
        for k in pairs(v) do
            if type(k) ~= 'number' then isArr = false; break end
            if k > maxK then maxK = k end
        end
        if isArr and maxK > 0 then
            local p = {}
            for i = 1, maxK do p[i] = toJSON(v[i], indent + 1) end
            return '[\n'..pad1..table.concat(p, ',\n'..pad1)..'\n'..string.rep('  ', indent)..']'
        else
            local p = {}
            for k, val in pairs(v) do p[#p+1] = '"'..tostring(k)..'": '..toJSON(val, indent + 1) end
            if #p == 0 then return '{}' end
            return '{\n'..pad1..table.concat(p, ',\n'..pad1)..'\n'..string.rep('  ', indent)..'}'
        end
    end
    return '"<'..t..'>"'
end

local function saveJSON()
    local report = {
        time         = os.date('%Y-%m-%d %H:%M:%S'),
        place_id     = game.PlaceId,
        hook_status  = hookStatus,
        labels       = labels,
        deaths       = deaths,
        summary      = summary,
        timeline     = timeline,
    }
    local json = toJSON(report)
    local path = ('HSHub_ActionSpy_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    return saved, path
end

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_ActionSpy_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_ActionSpy = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 440, 0, 470)
frame.Position = UDim2.new(0, 20, 0.4, -235)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame); stroke.Color = Color3.fromRGB(90, 200, 150); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 46); header.BackgroundColor3 = Color3.fromRGB(60, 170, 130); header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · ActionSpy'
local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 3)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() gui:Destroy(); shared.__HSHub_ActionSpy = nil end)

-- label textbox
local box = Instance.new('TextBox', frame)
box.Size = UDim2.new(1, -150, 0, 30); box.Position = UDim2.new(0, 12, 0, 54)
box.BackgroundColor3 = Color3.fromRGB(30, 34, 44); box.BorderSizePixel = 0
box.Font = Enum.Font.Code; box.TextSize = 13; box.TextColor3 = Color3.fromRGB(230, 240, 230)
box.PlaceholderText = 'label e.g. SPAWN / RESTART / INVIS / SCENT'; box.Text = ''
box.ClearTextOnFocus = false
Instance.new('UICorner', box).CornerRadius = UDim.new(0, 6)

local setBtn = Instance.new('TextButton', frame)
setBtn.Size = UDim2.new(0, 124, 0, 30); setBtn.Position = UDim2.new(1, -134, 0, 54)
setBtn.BackgroundColor3 = Color3.fromRGB(70, 120, 200); setBtn.BorderSizePixel = 0
setBtn.Font = Enum.Font.GothamBold; setBtn.TextSize = 12; setBtn.TextColor3 = Color3.fromRGB(245, 245, 250); setBtn.Text = '🏷 Set Label'
Instance.new('UICorner', setBtn).CornerRadius = UDim.new(0, 6)

local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1; stat.Size = UDim2.new(1, -24, 0, 18); stat.Position = UDim2.new(0, 14, 0, 90)
stat.Font = Enum.Font.Code; stat.TextSize = 11; stat.TextColor3 = Color3.fromRGB(150, 230, 180)
stat.TextXAlignment = Enum.TextXAlignment.Left; stat.Text = 'label: (none)   hooks: ' .. hookStatus

local function btn(label, color, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 30); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local startBtn = btn('▶ Start', Color3.fromRGB(60, 150, 100), 12, 100, 114)
local stopBtn  = btn('■ Stop',  Color3.fromRGB(160, 80, 80), 120, 100, 114)
local clrBtn   = btn('🧹 Clear', Color3.fromRGB(110, 90, 60), 228, 95, 114)
local saveBtn  = btn('💾 Save',  Color3.fromRGB(80, 120, 180), 331, 97, 114)

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 290); scroll.Position = UDim2.new(0, 10, 0, 152)
scroll.BackgroundColor3 = Color3.fromRGB(12, 14, 20); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4; scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 200, 150)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local layout = Instance.new('UIListLayout', scroll); layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll); pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6)

local function logRow(text, color)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -12, 0, 15); lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 10; lbl.TextColor3 = color or Color3.fromRGB(180, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 17)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end

logRow('Hooks: ' .. hookStatus, Color3.fromRGB(150, 230, 180))
if not hookfunction then logRow('hookfunction NOT AVAILABLE — cannot capture.', Color3.fromRGB(255, 130, 130)) end
logRow('1) Start  2) type label + Set  3) do action ONCE  4) repeat  5) Save', Color3.fromRGB(200, 210, 150))

-- live forwarder + death log
local liveIdx, deathIdx = 0, 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.2)
        while liveIdx < #liveQueue do
            liveIdx = liveIdx + 1
            local e = liveQueue[liveIdx]
            logRow(('[%6.2fs][%s] %s.%s(%s)'):format(e.t, e.label, e.name, e.method, e.args:sub(1, 60)),
                Color3.fromRGB(170, 220, 235))
        end
        while deathIdx < #deaths do
            deathIdx = deathIdx + 1
            local d = deaths[deathIdx]
            logRow(('[%6.2fs][%s] ☠ DEATH (%s)'):format(d.t, d.label, d.how), Color3.fromRGB(255, 150, 150))
        end
    end
end)

setBtn.MouseButton1Click:Connect(function()
    local txt = box.Text
    if txt == '' then txt = 'lbl' .. tostring(#labels + 1) end
    curLabel = txt
    labels[#labels + 1] = { t = now(), label = txt }
    stat.Text = 'label: ' .. curLabel .. '   hooks: ' .. hookStatus
    logRow(('───── label set: %s ─────'):format(curLabel), Color3.fromRGB(230, 210, 130))
end)

startBtn.MouseButton1Click:Connect(function()
    ACTIVE = true; START = tick()
    summary = {}; timeline = {}; labels = {}; deaths = {}; liveQueue = {}; liveIdx = 0; deathIdx = 0
    curLabel = box.Text ~= '' and box.Text or '(none)'
    watched = nil; pcall(attachWatch)
    for _, c in ipairs(scroll:GetChildren()) do if c:IsA('TextLabel') then c:Destroy() end end
    logRow('Recording STARTED. Set a label, then do an action.', Color3.fromRGB(170, 230, 180))
    stat.Text = 'label: ' .. curLabel .. '   hooks: ' .. hookStatus
end)

stopBtn.MouseButton1Click:Connect(function()
    if not ACTIVE then return end
    ACTIVE = false
    local n = 0; for _ in pairs(summary) do n = n + 1 end
    logRow(('STOPPED. distinct remotes=%d  events=%d  deaths=%d'):format(n, #timeline, #deaths),
        Color3.fromRGB(230, 180, 130))
end)

clrBtn.MouseButton1Click:Connect(function()
    summary = {}; timeline = {}; deaths = {}; liveQueue = {}; liveIdx = 0; deathIdx = 0
    for _, c in ipairs(scroll:GetChildren()) do if c:IsA('TextLabel') then c:Destroy() end end
    logRow('cleared.', Color3.fromRGB(200, 200, 200))
end)

saveBtn.MouseButton1Click:Connect(function()
    local saved, path = saveJSON()
    logRow(saved and ('Saved: workspace/' .. path) or 'Save FAILED (no writefile)', Color3.fromRGB(170, 230, 180))
    logRow('JSON also in clipboard.', Color3.fromRGB(180, 220, 255))
end)
