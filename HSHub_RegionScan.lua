--[[
═══════════════════════════════════════════════════════════════════════
                HS HUB · RegionScan  (UI)
   Dump REAL region positions so Teleports tab + autofarm cross-region TP
   stop landing underground. LUNAR uses RS._replicationFolder.RegionUtils
   (.getRegionModel(name) -> Instance with a real CFrame). We mirror that.

   USE: paste & execute. UI appears (green theme):
     - TYPE a filename in the textbox (default: HSHub_RegionScan)
     - Click ⟳ SCAN to run + save as <filename>.json (workspace + clipboard)
     You can re-scan from different regions with different names to compare.
                    discord.gg/5rpP6faZSJ
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_RegionScan then
    pcall(function() shared.__HSHub_RegionScan:Destroy() end)
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local WS = game:GetService('Workspace')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

-- Known region names (captured from ChangeRegionRemote in DamageSpy/RemoteHook
-- plus realm transition banners). Add any missing ones here; scanner dumps every
-- one it can resolve via RegionUtils.getRegionModel.
local KNOWN = {
    'Desert','Volcano Island','Seaweed Depths','Rocky Drop','Jungle','Algae Sandbar',
    'Central Rockfaces','Swamp Hill','Coral Reef','Grassy Shoal','Redwoods','Mountains',
    'Tundra','Flower Cave','Mesa','Tropical Islands','The Forest','Mushroom Forest',
    'Mangrove','Plains','Steppe','Frozen Wastes','Northern Mountains','Cliffs',
    'Tar Pits','Plateau','Goose Glacier','Frostbite Spire','Ice Caves',
}

-- ═════════════ SCAN CORE ════════════════════════════════════════════
local function ser(v, d, seen)
    d = d or 0; seen = seen or {}
    local t = typeof(v)
    if t == 'Vector3'  then return ('V3(%.2f,%.2f,%.2f)'):format(v.X, v.Y, v.Z) end
    if t == 'CFrame'   then local p = v.Position; return ('CF(%.2f,%.2f,%.2f)'):format(p.X, p.Y, p.Z) end
    if t == 'Instance' then return '<' .. v:GetFullName() .. '>' end
    if t == 'number' or t == 'boolean' then return v end
    if t == 'string'   then return (#v > 120) and ('str[' .. #v .. ']') or v end
    if t == 'function' then return '<fn>' end
    if t == 'table' then
        if seen[v] then return '<cycle>' end
        if d > 5 then return '{...}' end
        seen[v] = true
        local r, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1; if n > 200 then r['_more'] = true; break end
            r[tostring(k)] = ser(val, d + 1, seen)
        end
        return r
    end
    return '<' .. t .. '>'
end

local function safeRequire(mod)
    if not mod then return nil end
    local res, done
    task.spawn(function() local ok, r = pcall(require, mod); done = true; if ok then res = r end end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 5 do task.wait(0.05) end
    return res
end

local function runScan()
    local out = {
        time = os.date('%Y-%m-%d %H:%M:%S'),
        place_id = game.PlaceId,
        regions = {}, regionutils_funcs = {}, workspace_region_hits = {}, current_region = nil,
    }
    local rf = RS:FindFirstChild('_replicationFolder')
    local regionUtils = safeRequire(rf and rf:FindFirstChild('RegionUtils'))

    if type(regionUtils) == 'table' then
        for k, v in pairs(regionUtils) do
            out.regionutils_funcs[#out.regionutils_funcs + 1] = ('%s = %s'):format(tostring(k), type(v))
        end
        pcall(function()
            if regionUtils.getRegion then out.current_region = ser(regionUtils.getRegion()) end
        end)
        if regionUtils.getRegionModel then
            for _, name in ipairs(KNOWN) do
                local ok, model = pcall(regionUtils.getRegionModel, name)
                if ok and model then
                    local rec = { name = name, class = typeof(model) }
                    pcall(function()
                        if typeof(model) == 'Instance' then
                            rec.full = model:GetFullName()
                            if model:IsA('Model') then
                                local p = model:GetPivot().Position
                                rec.pivot = ('%.2f,%.2f,%.2f'):format(p.X, p.Y, p.Z)
                                local cf, sz = model:GetBoundingBox()
                                rec.bb_center = ('%.2f,%.2f,%.2f'):format(cf.Position.X, cf.Position.Y, cf.Position.Z)
                                rec.bb_size   = ('%.2f,%.2f,%.2f'):format(sz.X, sz.Y, sz.Z)
                            elseif model:IsA('BasePart') then
                                local p = model.Position
                                rec.pos = ('%.2f,%.2f,%.2f'):format(p.X, p.Y, p.Z)
                            end
                        elseif typeof(model) == 'CFrame' then
                            rec.cframe = ser(model)
                        elseif typeof(model) == 'Vector3' then
                            rec.vector = ser(model)
                        else
                            rec.value = ser(model)
                        end
                    end)
                    out.regions[#out.regions + 1] = rec
                end
            end
        end
    end

    pcall(function()
        local count = 0
        for _, dd in ipairs(WS:GetDescendants()) do
            count = count + 1; if count > 80000 then break end
            local nm = dd.Name
            if nm:find('Region') and not nm:find('RegionUtil') then
                local rec = { path = dd:GetFullName(), class = dd.ClassName }
                pcall(function()
                    if dd:IsA('BasePart') then local p=dd.Position; rec.pos=('%.2f,%.2f,%.2f'):format(p.X,p.Y,p.Z) end
                    if dd:IsA('Model') then local p=dd:GetPivot().Position; rec.pivot=('%.2f,%.2f,%.2f'):format(p.X,p.Y,p.Z) end
                end)
                out.workspace_region_hits[#out.workspace_region_hits + 1] = rec
                if #out.workspace_region_hits >= 50 then break end
            end
        end
    end)
    return out
end

local function toJSON(out)
    local json
    local ok = pcall(function() json = game:GetService('HttpService'):JSONEncode(out) end)
    if not ok or not json then json = '{"error":"JSONEncode failed"}' end
    return json
end

-- sanitize a user-typed filename (strip path / extension / bad chars)
local function cleanName(s)
    s = tostring(s or ''):gsub('[\\/]', ''):gsub('%.json$', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then s = 'HSHub_RegionScan' end
    return s
end

-- ═════════════ UI ═══════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_RegionScan_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_RegionScan = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 440, 0, 250)
frame.Position = UDim2.new(0, 20, 0.4, -125)
frame.BackgroundColor3 = Color3.fromRGB(20, 24, 22)
frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(90, 200, 130); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 46); header.BorderSizePixel = 0
header.BackgroundColor3 = Color3.fromRGB(90, 200, 130)
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)

local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = Color3.fromRGB(20, 28, 22)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · RegionScan'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 3)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(20, 28, 22); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_RegionScan = nil
end)

local lbl = Instance.new('TextLabel', frame)
lbl.BackgroundTransparency = 1
lbl.Size = UDim2.new(1, -28, 0, 18); lbl.Position = UDim2.new(0, 14, 0, 54)
lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
lbl.TextColor3 = Color3.fromRGB(200, 230, 210)
lbl.TextXAlignment = Enum.TextXAlignment.Left
lbl.Text = 'Filename (no extension):'

local box = Instance.new('TextBox', frame)
box.Size = UDim2.new(1, -28, 0, 32); box.Position = UDim2.new(0, 14, 0, 74)
box.BackgroundColor3 = Color3.fromRGB(14, 18, 16); box.BorderSizePixel = 0
box.Font = Enum.Font.Code; box.TextSize = 13
box.TextColor3 = Color3.fromRGB(230, 245, 235)
box.PlaceholderText = 'HSHub_RegionScan'
box.PlaceholderColor3 = Color3.fromRGB(110, 130, 118)
box.TextXAlignment = Enum.TextXAlignment.Left
box.ClearTextOnFocus = false
box.Text = 'HSHub_RegionScan'
Instance.new('UICorner', box).CornerRadius = UDim.new(0, 6)
local boxPad = Instance.new('UIPadding', box); boxPad.PaddingLeft = UDim.new(0, 10); boxPad.PaddingRight = UDim.new(0, 10)

local hint = Instance.new('TextLabel', frame)
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, -28, 0, 32); hint.Position = UDim2.new(0, 14, 0, 112)
hint.Font = Enum.Font.Gotham; hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(150, 180, 160)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextYAlignment = Enum.TextYAlignment.Top
hint.TextWrapped = true
hint.Text = 'Run di region apa aja (yang masuk akal aja, kadang RegionUtils butuh region aktif).\n.json bakal ke-append otomatis.'

local scanBtn = Instance.new('TextButton', frame)
scanBtn.Size = UDim2.new(1, -28, 0, 38); scanBtn.Position = UDim2.new(0, 14, 0, 152)
scanBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 130); scanBtn.BorderSizePixel = 0
scanBtn.Font = Enum.Font.GothamBold; scanBtn.TextSize = 14
scanBtn.TextColor3 = Color3.fromRGB(20, 28, 22); scanBtn.Text = '⟳ SCAN & SAVE'
Instance.new('UICorner', scanBtn).CornerRadius = UDim.new(0, 6)

local result = Instance.new('TextLabel', frame)
result.BackgroundTransparency = 1
result.Size = UDim2.new(1, -28, 0, 44); result.Position = UDim2.new(0, 14, 0, 198)
result.Font = Enum.Font.Code; result.TextSize = 11
result.TextColor3 = Color3.fromRGB(170, 230, 180)
result.TextXAlignment = Enum.TextXAlignment.Left
result.TextYAlignment = Enum.TextYAlignment.Top
result.TextWrapped = true
result.Text = 'Ready.'

scanBtn.MouseButton1Click:Connect(function()
    scanBtn.Text = '... scanning'
    scanBtn.AutoButtonColor = false
    task.wait()  -- yield so the button label paints
    local ok, out = pcall(runScan)
    if not ok then
        result.TextColor3 = Color3.fromRGB(255, 140, 140)
        result.Text = 'ERROR: ' .. tostring(out)
        scanBtn.Text = '⟳ SCAN & SAVE'; scanBtn.AutoButtonColor = true
        return
    end
    local json = toJSON(out)
    local fname = cleanName(box.Text) .. '.json'
    local saved = false
    pcall(function() if writefile then writefile(fname, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    result.TextColor3 = Color3.fromRGB(170, 230, 180)
    result.Text = ('Saved: %s\nregions=%d  utils_funcs=%d  ws_hits=%d  (+ clipboard)')
        :format(saved and ('workspace/' .. fname) or '(no writefile)',
                #out.regions, #out.regionutils_funcs, #out.workspace_region_hits)
    scanBtn.Text = '⟳ SCAN & SAVE'; scanBtn.AutoButtonColor = true
end)
