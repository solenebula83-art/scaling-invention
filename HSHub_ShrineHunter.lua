--[[
═══════════════════════════════════════════════════════════════════════
                HS HUB · ShrineHunter
   Background collector — leave it running, jalan-jalan di game, tiap
   shrine tablet ke-stream otomatis ke-save (posisi + nama folder + timer
   status). Live list di UI. Hasil persist ke file + export ke clipboard.
                    discord.gg/5rpP6faZSJ

   USE:
     1. Paste script  →  UI ungu muncul, langsung "HUNTING"
     2. Tinggal jalan / terbang di game seperti biasa
     3. Tiap masuk region baru, shrine tablet di-detect otomatis → ✅ saved
     4. Klik nama di list = TP balik ke shrine itu  (verify)
     5. Klik EXPORT = copy JSON semua shrine ke clipboard, kirim ke aku.
   File: hshub_shrines_hunted.json  (awet walau re-exec)
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_ShrineHunter then
    pcall(function() shared.__HSHub_ShrineHunter:Destroy() end)
end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')
local FILE      = 'hshub_shrines_hunted.json'

-- ═════════════ STATE / PERSIST ══════════════════════════════════════
local saved = {}   -- name -> {x,y,z, timer, place}
local order = {}

local function persist()
    pcall(function()
        if not writefile then return end
        local lines = { '{' }
        for i, name in ipairs(order) do
            local r = saved[name]
            if r then
                local c = (i < #order) and ',' or ''
                lines[#lines + 1] = ('  "%s": { "pos": [%.2f, %.2f, %.2f], "timer": "%s", "place_id": %s }%s'):format(
                    name:gsub('"', '\\"'), r[1], r[2], r[3],
                    tostring(r.timer or ''):gsub('"', '\\"'),
                    tostring(r.place or 0), c)
            end
        end
        lines[#lines + 1] = '}'
        writefile(FILE, table.concat(lines, '\n'))
    end)
end

local function load()
    pcall(function()
        if not (readfile and isfile and isfile(FILE)) then return end
        local raw = tostring(readfile(FILE))
        for name, x, y, z, timer, pid in raw:gmatch(
            '"([^"]+)"%s*:%s*{%s*"pos"%s*:%s*%[%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%]%s*,%s*"timer"%s*:%s*"([^"]*)"%s*,%s*"place_id"%s*:%s*([%-%d]+)') do
            saved[name] = { tonumber(x), tonumber(y), tonumber(z), timer = timer, place = tonumber(pid) }
            order[#order + 1] = name
        end
    end)
end
load()

local function getRoot()
    local c = LP.Character
    if c then local r = c:FindFirstChild('HumanoidRootPart'); if r then return r end end
    local chars = Workspace:FindFirstChild('Characters')
    if chars then
        local me = chars:FindFirstChild(LP.Name)
        if me then return me:FindFirstChild('HumanoidRootPart') or me.PrimaryPart end
    end
end

-- ═════════════ UI ═══════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_ShrineHunter_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_ShrineHunter = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 460, 0, 470)
frame.Position = UDim2.new(0, 20, 0.35, -235)
frame.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame); stroke.Color = Color3.fromRGB(170, 110, 220); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 46); header.BorderSizePixel = 0
header.BackgroundColor3 = Color3.fromRGB(170, 110, 220)
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = Color3.fromRGB(28, 22, 36); title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · ShrineHunter (auto)'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 3)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(28, 22, 36); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_ShrineHunter = nil
end)

local status = Instance.new('TextLabel', frame)
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -28, 0, 38); status.Position = UDim2.new(0, 14, 0, 54)
status.Font = Enum.Font.Code; status.TextSize = 12
status.TextColor3 = Color3.fromRGB(220, 200, 250)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = ('● HUNTING (jalan-jalan aja, shrine ke-detect otomatis)\nLoaded: %d shrine tersimpan.'):format(#order)

local function mkBtn(label, col, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 30); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(28, 22, 36); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local exportBtn = mkBtn('📋 EXPORT JSON', Color3.fromRGB(180, 200, 240),  14, 210, 100)
local clearBtn  = mkBtn('🗑 CLEAR ALL',  Color3.fromRGB(220, 130, 130), 236, 210, 100)

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -28, 0, 326); scroll.Position = UDim2.new(0, 14, 0, 138)
scroll.BackgroundColor3 = Color3.fromRGB(14, 12, 20); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(170, 110, 220)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 4); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll)
pad.PaddingTop = UDim.new(0, 6); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)

local function refreshList()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA('Frame') then c:Destroy() end
    end
    for i, name in ipairs(order) do
        local r = saved[name]
        if r then
            local row = Instance.new('Frame', scroll)
            row.Size = UDim2.new(1, -12, 0, 36); row.BackgroundColor3 = Color3.fromRGB(28, 24, 36)
            row.BorderSizePixel = 0; row.LayoutOrder = i
            Instance.new('UICorner', row).CornerRadius = UDim.new(0, 4)

            local tpBtn = Instance.new('TextButton', row)
            tpBtn.Size = UDim2.new(1, -40, 1, 0); tpBtn.Position = UDim2.new(0, 0, 0, 0)
            tpBtn.BackgroundTransparency = 1
            tpBtn.Font = Enum.Font.Code; tpBtn.TextSize = 11
            tpBtn.TextColor3 = Color3.fromRGB(230, 220, 245)
            tpBtn.TextXAlignment = Enum.TextXAlignment.Left
            tpBtn.TextYAlignment = Enum.TextYAlignment.Top
            tpBtn.Text = ('  %s\n    %.0f, %.0f, %.0f  ·  %s  ·  pid:%s'):format(
                name, r[1], r[2], r[3],
                tostring(r.timer or '—'), tostring(r.place or '?'))
            tpBtn.MouseButton1Click:Connect(function()
                local root = getRoot()
                if root then
                    root.CFrame = CFrame.new(r[1], r[2] + 6, r[3])
                    status.Text = ('TP -> %s'):format(name)
                end
            end)

            local del = Instance.new('TextButton', row)
            del.Size = UDim2.new(0, 32, 1, 0); del.Position = UDim2.new(1, -36, 0, 0)
            del.BackgroundColor3 = Color3.fromRGB(180, 80, 90); del.BorderSizePixel = 0
            del.Font = Enum.Font.GothamBold; del.TextSize = 14
            del.TextColor3 = Color3.fromRGB(245, 235, 235); del.Text = '×'
            Instance.new('UICorner', del).CornerRadius = UDim.new(0, 4)
            del.MouseButton1Click:Connect(function()
                saved[name] = nil
                for k = #order, 1, -1 do if order[k] == name then table.remove(order, k); break end end
                persist(); refreshList()
                status.Text = ('Deleted: %s'):format(name)
            end)
        end
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, #order * 40 + 12)
end
refreshList()

exportBtn.MouseButton1Click:Connect(function()
    local lines = { '{' }
    for i, name in ipairs(order) do
        local r = saved[name]
        if r then
            local c = (i < #order) and ',' or ''
            lines[#lines + 1] = ('  "%s": { "pos": [%.2f, %.2f, %.2f], "timer": "%s", "place_id": %s }%s'):format(
                name, r[1], r[2], r[3],
                tostring(r.timer or ''), tostring(r.place or 0), c)
        end
    end
    lines[#lines + 1] = '}'
    local json = table.concat(lines, '\n')
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    status.Text = ('Exported %d shrines to clipboard.'):format(#order)
end)

clearBtn.MouseButton1Click:Connect(function()
    saved, order = {}, {}; persist(); refreshList()
    status.Text = 'Cleared. (file ke-empty-in juga)'
end)

-- ═════════════ HUNTER LOOP ══════════════════════════════════════════
-- sweeps Workspace every 1.5s for any BasePart whose name has "Tablet";
-- pulls parent folder name as the shrine name + the TimerGui text if any.
-- Re-finds known shrines too (updates timer text + place_id), but only logs
-- "new shrine detected" the FIRST time we see a name.

local function readTimer(tabletPart)
    local ok, t = pcall(function()
        local g = tabletPart:FindFirstChild('TimerGui')
        if not g then return nil end
        local l = g:FindFirstChild('TimerLabel')
        return l and l.Text
    end)
    return ok and t or nil
end

local hits = 0
task.spawn(function()
    while gui.Parent do
        task.wait(1.5)
        pcall(function()
            local found = 0
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA('BasePart') and d.Name:lower():find('tablet') then
                    found = found + 1
                    local p = d.Position
                    -- name from parent folder; fall back to tablet name stripped of "Tablet"
                    local shrineName = d.Parent and d.Parent.Name
                    if (not shrineName) or shrineName == '' then
                        shrineName = d.Name:gsub('Tablet', ''):gsub('%s+$', '')
                    end
                    local timer = readTimer(d)
                    local isNew = saved[shrineName] == nil
                    saved[shrineName] = {
                        p.X, p.Y, p.Z, timer = timer, place = game.PlaceId,
                    }
                    if isNew then
                        order[#order + 1] = shrineName
                        persist(); refreshList()
                        status.Text = ('● HUNTING  ·  NEW: %s  (%.0f,%.0f,%.0f)  [%s]')
                            :format(shrineName, p.X, p.Y, p.Z, tostring(timer or '—'))
                    end
                end
            end
            hits = found
        end)
    end
end)

-- light heartbeat refresh so timer text in the list stays current
task.spawn(function()
    while gui.Parent do
        task.wait(8)
        pcall(refreshList)
        pcall(persist)
    end
end)
