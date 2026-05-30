--[[
═══════════════════════════════════════════════════════════════════════
                HS HUB · PosSaver
   Save creature's current position under a custom name. Use this to mark
   safe TP spots per region (so we stop teleporting underground or into the
   sky). Persists across re-exec via writefile.
                    discord.gg/5rpP6faZSJ

   USE:
     1. Walk creature to a safe spot in a region (on the ground, in air, etc.)
     2. Type a name (e.g. "Desert", "Hellion shrine") in the textbox
     3. Click  ▣ SAVE HERE  → adds to list + persists to file
     4. Click any saved entry to TP back, or × to delete
     5. Click  📋 EXPORT  → copies all entries as JSON to clipboard
        → send to me, ku-hardcode jadi tabel Teleports tab.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_PosSaver then
    pcall(function() shared.__HSHub_PosSaver:Destroy() end)
end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')
local FILE      = 'hshub_cos_positions.json'

-- ═════════════ STATE / PERSIST ══════════════════════════════════════
local saved = {}   -- name -> {x,y,z}
local order = {}   -- insertion order so UI is stable

local function persist()
    pcall(function()
        if not writefile then return end
        local lines = { '{' }
        for i, name in ipairs(order) do
            local p = saved[name]
            if p then
                local comma = (i < #order) and ',' or ''
                lines[#lines + 1] = ('  "%s": [%.2f, %.2f, %.2f]%s'):format(
                    name:gsub('"', '\\"'), p[1], p[2], p[3], comma)
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
        -- tiny parser: "name": [x, y, z]
        for name, x, y, z in raw:gmatch('"([^"]+)"%s*:%s*%[%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%]') do
            saved[name] = { tonumber(x), tonumber(y), tonumber(z) }
            order[#order + 1] = name
        end
    end)
end
load()

-- ═════════════ CHARACTER ════════════════════════════════════════════
local function getRoot()
    local c = LP.Character
    if c then
        local r = c:FindFirstChild('HumanoidRootPart')
        if r then return r end
    end
    -- CoS streams the character under Workspace.Characters.<playerName>
    local chars = Workspace:FindFirstChild('Characters')
    if chars then
        local me = chars:FindFirstChild(LP.Name)
        if me then return me:FindFirstChild('HumanoidRootPart') or me.PrimaryPart end
    end
end

-- ═════════════ UI ═══════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_PosSaver_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_PosSaver = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 420, 0, 460)
frame.Position = UDim2.new(0, 20, 0.35, -230)
frame.BackgroundColor3 = Color3.fromRGB(20, 24, 22)
frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(120, 200, 240); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 46); header.BorderSizePixel = 0
header.BackgroundColor3 = Color3.fromRGB(120, 200, 240)
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)

local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = Color3.fromRGB(20, 28, 32)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · PosSaver'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 3)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(20, 28, 32); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_PosSaver = nil
end)

-- name textbox
local box = Instance.new('TextBox', frame)
box.Size = UDim2.new(1, -28, 0, 32); box.Position = UDim2.new(0, 14, 0, 58)
box.BackgroundColor3 = Color3.fromRGB(14, 18, 22); box.BorderSizePixel = 0
box.Font = Enum.Font.Code; box.TextSize = 13
box.TextColor3 = Color3.fromRGB(230, 245, 245)
box.PlaceholderText = 'Nama posisi (mis: Desert, Hellion shrine)'
box.PlaceholderColor3 = Color3.fromRGB(110, 130, 140)
box.TextXAlignment = Enum.TextXAlignment.Left
box.ClearTextOnFocus = false
box.Text = ''
Instance.new('UICorner', box).CornerRadius = UDim.new(0, 6)
local boxPad = Instance.new('UIPadding', box); boxPad.PaddingLeft = UDim.new(0, 10); boxPad.PaddingRight = UDim.new(0, 10)

-- buttons row
local function mkBtn(label, col, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 32); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(20, 28, 32); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end

local saveBtn   = mkBtn('▣ SAVE HERE', Color3.fromRGB(120, 220, 150), 14,  192, 100)
local exportBtn = mkBtn('📋 EXPORT JSON', Color3.fromRGB(180, 200, 240), 214, 192, 100)

local status = Instance.new('TextLabel', frame)
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -28, 0, 22); status.Position = UDim2.new(0, 14, 0, 138)
status.Font = Enum.Font.Code; status.TextSize = 11
status.TextColor3 = Color3.fromRGB(170, 230, 210)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ('Loaded %d saved positions.'):format(#order)

-- scrollable list
local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -28, 0, 286); scroll.Position = UDim2.new(0, 14, 0, 164)
scroll.BackgroundColor3 = Color3.fromRGB(14, 18, 22); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 200, 240)
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
        local p = saved[name]
        if p then
            local row = Instance.new('Frame', scroll)
            row.Size = UDim2.new(1, -12, 0, 28); row.BackgroundColor3 = Color3.fromRGB(24, 28, 32)
            row.BorderSizePixel = 0; row.LayoutOrder = i
            Instance.new('UICorner', row).CornerRadius = UDim.new(0, 4)

            local tpBtn = Instance.new('TextButton', row)
            tpBtn.Size = UDim2.new(1, -40, 1, 0); tpBtn.Position = UDim2.new(0, 0, 0, 0)
            tpBtn.BackgroundTransparency = 1
            tpBtn.Font = Enum.Font.Code; tpBtn.TextSize = 12
            tpBtn.TextColor3 = Color3.fromRGB(220, 235, 240)
            tpBtn.TextXAlignment = Enum.TextXAlignment.Left
            tpBtn.Text = ('  %s  ·  %.0f, %.0f, %.0f'):format(name, p[1], p[2], p[3])
            tpBtn.MouseButton1Click:Connect(function()
                local r = getRoot()
                if r then r.CFrame = CFrame.new(p[1], p[2], p[3])
                    status.Text = ('TP -> %s'):format(name) end
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
    scroll.CanvasSize = UDim2.new(0, 0, 0, #order * 32 + 12)
end
refreshList()

-- save button
saveBtn.MouseButton1Click:Connect(function()
    local name = (box.Text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then status.Text = 'Nama kosong — isi dulu.'; status.TextColor3 = Color3.fromRGB(255, 180, 180); return end
    local r = getRoot()
    if not r then status.Text = 'Creature ga ke-load (root ga ada).'; status.TextColor3 = Color3.fromRGB(255, 180, 180); return end
    local p = r.Position
    if not saved[name] then order[#order + 1] = name end
    saved[name] = { p.X, p.Y, p.Z }
    persist(); refreshList()
    status.TextColor3 = Color3.fromRGB(170, 230, 180)
    status.Text = ('Saved: %s = (%.1f, %.1f, %.1f)'):format(name, p.X, p.Y, p.Z)
    box.Text = ''
end)

-- export to clipboard
exportBtn.MouseButton1Click:Connect(function()
    local lines = { '{' }
    for i, name in ipairs(order) do
        local p = saved[name]
        if p then
            local comma = (i < #order) and ',' or ''
            lines[#lines + 1] = ('  "%s": [%.2f, %.2f, %.2f]%s'):format(name, p[1], p[2], p[3], comma)
        end
    end
    lines[#lines + 1] = '}'
    local json = table.concat(lines, '\n')
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    status.TextColor3 = Color3.fromRGB(170, 230, 180)
    status.Text = ('Exported %d positions to clipboard.'):format(#order)
end)
