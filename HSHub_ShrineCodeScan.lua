--[[
═══════════════════════════════════════════════════════════════════════
            HS HUB · ShrineCodeScan  (v5 — dump the new util modules)
   LUNAR's old `workspace.WardenShrines` is GONE in the updated game.
   The new equivalents live in RS._replicationFolder as modules. We require
   (cached -> safe, no hang) and dump the ones likely to hold shrine/region
   POSITIONS + data:  ArtifactUtils, RegionUtils, WardenShrine, PositionUtils
   (+ Constants.WardenTexts).  discord.gg/5rpP6faZSJ

   USE: run ONCE, anywhere. Writes + copies HSHub_ShrineCodeScan.json.
═══════════════════════════════════════════════════════════════════════
]]

local RS  = game:GetService('ReplicatedStorage')
local out = { modules = {} }

local function ser(v, d, seen)
    d = d or 0; seen = seen or {}
    local t = typeof(v)
    if t == 'Vector3'  then return ('V3(%.2f,%.2f,%.2f)'):format(v.X, v.Y, v.Z) end
    if t == 'CFrame'   then local p = v.Position; return ('CF(%.2f,%.2f,%.2f)'):format(p.X, p.Y, p.Z) end
    if t == 'Instance' then return '<' .. v:GetFullName() .. '>' end
    if t == 'number' or t == 'boolean' then return v end
    if t == 'string'   then return (#v > 160) and ('str[' .. #v .. ']') or v end
    if t == 'function' then return '<fn>' end
    if t == 'table' then
        if seen[v] then return '<cycle>' end
        if d > 7 then return '{...}' end
        seen[v] = true
        local r, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1; if n > 300 then r['_more'] = true; break end
            local ok, sv = pcall(ser, val, d + 1, seen)
            r[tostring(k)] = ok and sv or '<err>'
        end
        return r
    end
    return '<' .. t .. '>'
end

-- require ONE module with a timeout (game already required it -> cached, instant)
local function dumpModule(mod)
    if not mod then return nil, 'not found' end
    local res, done, e
    task.spawn(function()
        local ok, r = pcall(require, mod); done = true
        if ok then res = r else e = tostring(r) end
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 5 do task.wait(0.05) end
    if not done then return nil, 'timed out (yields)' end
    if e then return nil, 'require error: ' .. e end
    local okS, dumped = pcall(ser, res, 0, {})
    return okS and dumped or nil, okS and nil or 'serialize error'
end

local rf = RS:FindFirstChild('_replicationFolder')
local constants = rf and rf:FindFirstChild('Constants')

local function grab(name, parent)
    parent = parent or rf
    local m = parent and parent:FindFirstChild(name)
    local data, err = dumpModule(m)
    out.modules[name] = { data = data, err = err }
end

grab('ArtifactUtils')
grab('RegionUtils')
grab('WardenShrine')
grab('PositionUtils')
grab('HUDGui')          -- LUNAR runs the artifact farm THROUGH this module (Sample 11 finding)
grab('WardenTexts', constants)

local json
local ok = pcall(function() json = game:GetService('HttpService'):JSONEncode(out) end)
if not ok or not json then json = '{"error":"JSONEncode failed"}' end
pcall(function() if writefile then writefile('HSHub_ShrineCodeScan.json', json) end end)
pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)

pcall(function()
    local g = Instance.new('ScreenGui'); g.Name = 'HSHub_ShrineCodeScan'
    g.Parent = (gethui and gethui()) or game:GetService('CoreGui')
    local l = Instance.new('TextLabel', g)
    l.Size = UDim2.new(0, 520, 0, 92); l.Position = UDim2.new(0.5, -260, 0, 80)
    l.BackgroundColor3 = Color3.fromRGB(20, 20, 28); l.TextColor3 = Color3.fromRGB(150, 230, 170)
    l.Font = Enum.Font.Code; l.TextSize = 12; l.TextWrapped = true
    local lines = { 'ShrineCodeScan v5:' }
    for name, r in pairs(out.modules) do
        lines[#lines + 1] = ('  %s = %s'):format(name, r.data and 'OK' or ('FAIL:' .. tostring(r.err)))
    end
    lines[#lines + 1] = 'Saved HSHub_ShrineCodeScan.json (+ clipboard).'
    l.Text = table.concat(lines, '\n')
    Instance.new('UICorner', l)
    task.delay(16, function() g:Destroy() end)
end)
