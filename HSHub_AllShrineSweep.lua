--[[
═══════════════════════════════════════════════════════════════════════
                HS HUB · AllShrineSweep
   Sweep entire game state (Workspace + ReplicatedStorage) for anything
   that looks like a shrine tablet or shrine container. Hardcore realm
   only streams the region you're in — but folder STUBS, tablet meshes
   at alternate paths, and config modules can still be visible. We dump
   every lead in one run.  discord.gg/5rpP6faZSJ

   Catches:
     - Any BasePart whose name contains 'Tablet'
     - Any container whose name contains 'Shrine' / 'Warden' / 'Shadow'
     - ModuleScript names matching hardcore/shrine/shadow/realm
     - Calls RegionUtils.getRegionModel(name) for likely hardcore region names

   USE: run ONCE, anywhere (preferably in the realm you want to map).
   Saves HSHub_AllShrineSweep.json (+ clipboard).
═══════════════════════════════════════════════════════════════════════
]]

local RS = game:GetService('ReplicatedStorage')
local WS = game:GetService('Workspace')
local out = {
    time = os.date('%Y-%m-%d %H:%M:%S'),
    place_id = game.PlaceId,
    tablets = {},
    shrine_containers = {},
    shrine_modules = {},
    hardcore_regions = {},
    notes = {},
}

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

-- ── timeout-guarded require (for ModuleScripts) ─────────────────────
local function safeRequire(mod)
    if not mod then return nil end
    local res, done
    task.spawn(function() local ok, r = pcall(require, mod); done = true; if ok then res = r end end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 3 do task.wait(0.05) end
    return res
end

-- ── 1) Sweep Workspace + RS for tablets / shrine containers ─────────
local function sweep(root, label)
    local count = 0
    pcall(function()
        for _, d in ipairs(root:GetDescendants()) do
            count = count + 1; if count > 120000 then
                out.notes[#out.notes + 1] = label .. ': scan capped at 120k'; break end
            local nm = d.Name
            local lower = nm:lower()
            if d:IsA('BasePart') and lower:find('tablet') then
                local rec = {
                    name = nm, path = d:GetFullName(), pos = pos(d),
                    parent = d.Parent and d.Parent:GetFullName(),
                }
                -- pull TimerGui text (shrine status) if present
                pcall(function()
                    local g = d:FindFirstChild('TimerGui')
                    if g then
                        local tl = g:FindFirstChild('TimerLabel')
                        local hl = g:FindFirstChild('HeaderLabel')
                        if tl then rec.timer  = tl.Text end
                        if hl then rec.header = hl.Text end
                    end
                end)
                local a = attrs(d); if next(a) then rec.attr = a end
                out.tablets[#out.tablets + 1] = rec
            elseif (lower:find('shrine') or lower:find('warden') or lower:find('shadow'))
                and (d:IsA('Folder') or d:IsA('Model') or d:IsA('Configuration')) then
                -- list children of shrine containers (so we can SEE all sub-shrines)
                local kids = {}
                pcall(function()
                    for _, ch in ipairs(d:GetChildren()) do
                        kids[#kids + 1] = ch.Name .. '(' .. ch.ClassName .. ')'
                    end
                end)
                out.shrine_containers[#out.shrine_containers + 1] = {
                    name = nm, path = d:GetFullName(), class = d.ClassName,
                    child_count = #d:GetChildren(), children = kids,
                }
            end
        end
    end)
end
sweep(WS, 'Workspace')
sweep(RS, 'ReplicatedStorage')

-- ── 2) Shrine / hardcore / realm related modules in _replicationFolder ──
local rf = RS:FindFirstChild('_replicationFolder')
if rf then
    for _, ch in ipairs(rf:GetDescendants()) do
        if ch:IsA('ModuleScript') then
            local lower = ch.Name:lower()
            if lower:find('shrine') or lower:find('hardcore') or lower:find('shadow')
                or lower:find('warden') or lower:find('realm') then
                out.shrine_modules[#out.shrine_modules + 1] = ch:GetFullName()
            end
        end
    end
end

-- ── 3) Try RegionUtils.getRegionModel on hardcore-likely region names ──
local regionUtils = safeRequire(rf and rf:FindFirstChild('RegionUtils'))
if type(regionUtils) == 'table' and regionUtils.getRegionModel then
    local NAMES = {
        'Shadow Isle','Shadow','Hardcore','Shadow Realm','Shadowlands','Tox Spewer',
        'Hellfire','Necropolis','Ash','Ashlands','Void','Inferno','Wraith Mire',
        'Boreal Tundra','Hardcore Tundra','Hard Tundra','Hardcore Lake',
    }
    for _, n in ipairs(NAMES) do
        local ok, m = pcall(regionUtils.getRegionModel, n)
        if ok and m then
            local rec = { name = n, class = typeof(m) }
            pcall(function()
                if typeof(m) == 'Instance' then
                    rec.full = m:GetFullName()
                    if m:IsA('Model') then
                        local p = m:GetPivot().Position
                        rec.pivot = ('%.1f,%.1f,%.1f'):format(p.X, p.Y, p.Z)
                    elseif m:IsA('BasePart') then
                        local p = m.Position; rec.pos = ('%.1f,%.1f,%.1f'):format(p.X, p.Y, p.Z)
                    end
                end
            end)
            out.hardcore_regions[#out.hardcore_regions + 1] = rec
        end
    end
end

-- ── save ────────────────────────────────────────────────────────────
local json
local ok = pcall(function() json = game:GetService('HttpService'):JSONEncode(out) end)
if not ok or not json then json = '{"error":"JSONEncode failed"}' end
pcall(function() if writefile then writefile('HSHub_AllShrineSweep.json', json) end end)
pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)

pcall(function()
    local g = Instance.new('ScreenGui'); g.Name = 'HSHub_AllShrineSweep'
    g.Parent = (gethui and gethui()) or game:GetService('CoreGui')
    local l = Instance.new('TextLabel', g)
    l.Size = UDim2.new(0, 540, 0, 100); l.Position = UDim2.new(0.5, -270, 0, 80)
    l.BackgroundColor3 = Color3.fromRGB(20, 24, 22); l.TextColor3 = Color3.fromRGB(150, 230, 170)
    l.Font = Enum.Font.Code; l.TextSize = 12; l.TextWrapped = true
    l.Text = ('AllShrineSweep DONE.\ntablets=%d  shrine_containers=%d  modules=%d  hc_regions=%d\nSaved HSHub_AllShrineSweep.json (+ clipboard).')
        :format(#out.tablets, #out.shrine_containers, #out.shrine_modules, #out.hardcore_regions)
    Instance.new('UICorner', l)
    task.delay(16, function() g:Destroy() end)
end)
