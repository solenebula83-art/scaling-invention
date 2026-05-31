--[[
═══════════════════════════════════════════════════════════════════════
                    HS HUB · TPDetectSpy
   Answer ONE question: is CoS teleport detection SERVER-SIDE (rubber-band)
   or CLIENT-REPORTED (a remote carries your position / a flag)?
                    discord.gg/5rpP6faZSJ

   It captures, around your teleports:
     1. EVERY FireServer/InvokeServer + whether its args carry a POSITION
        (Vector3 / CFrame / a number triple near your HRP). A remote fired
        right after a TP carrying your position = the client report path =
        the thing you'd hook/spoof to bypass.
     2. A DENSE position+velocity timeline (20 Hz). If the server SNAPS you
        BACK after a TP (a big jump out, then a big jump back you didn't do)
        = rubber-band = SERVER-SIDE detection (no client bypass; must move
        within the speed cap).
     3. Marks (press when you SEE detection: teleport-back / warning / freeze).

   WORKFLOW: Start → do a TP that normally gets flagged (use the hub's TP, or
   set HRP.CFrame manually) → watch → press ⚑ Mark the instant anything happens
   → Stop → Save. Send the JSON.

   READ THE OUTPUT:
     - remotes_carrying_position non-empty  → CLIENT-REPORTED → bypassable
       (hook/block/spoof that remote).
     - position_jumps shows TP-out THEN snap-back you didn't cause → SERVER-SIDE
       rubber-band → no instant-TP bypass (use gradual speed-capped move).
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_TPDetectSpy then
    pcall(function() shared.__HSHub_TPDetectSpy:Destroy() end)
end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local RunService= game:GetService('RunService')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

-- ═════════════ STATE ═════════════════════════════════════════════
local ACTIVE   = false
local START    = 0
local summary  = {}     -- name -> {count, method, carriesPos, sample, firstT, lastT}
local fires    = {}     -- chronological remote fires (capped)
local posTL    = {}     -- {t, x,y,z, vx,vy,vz}  (dense)
local jumps    = {}     -- detected big position deltas (TP out / snap back)
local marks    = {}     -- user marks {t, posAtMark}
local hookStatus = 'init'
local MAXFIRE  = 3000
local MAXPOS   = 6000
local JUMP_STUDS = 80   -- frame-to-frame delta above this = a "jump"

local function now() return tick() - START end

-- ═════════════ CHAR ══════════════════════════════════════════════
local function getRoot()
    local c = LP.Character
    if c then local r = c:FindFirstChild('HumanoidRootPart'); if r then return r end end
    local chars = Workspace:FindFirstChild('Characters')
    if chars then local m = chars:FindFirstChild(LP.Name)
        if m then return m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart end end
end

local function hrpPos()
    local r = getRoot()
    if r then local p = r.Position; return p.X, p.Y, p.Z end
    return nil
end

-- ═════════════ ARG / POSITION DETECTION ══════════════════════════
local function looksLikePos(v)
    local t = typeof(v)
    if t == 'Vector3' or t == 'CFrame' then return true end
    return false
end

local function dumpVal(v)
    local t = typeof(v)
    if t == 'Vector3' then return ('V3(%.1f,%.1f,%.1f)'):format(v.X, v.Y, v.Z) end
    if t == 'CFrame'  then local p = v.Position; return ('CF(%.1f,%.1f,%.1f)'):format(p.X, p.Y, p.Z) end
    if t == 'Instance' then local ok,n = pcall(function() return v:GetFullName() end); return ok and ('<'..n..'>') or '<inst>' end
    if t == 'string'  then return (#v > 40) and ('str('..#v..'B)') or ('"'..v:sub(1,40)..'"') end
    if t == 'number' or t == 'boolean' then return tostring(v) end
    if t == 'table'   then return '{table}' end
    return '<'..t..'>'
end

-- scan args: build readable string + detect if any arg carries a position
local function scanArgs(a, n)
    local parts = {}
    local hasPos = false
    local px, py, pz = hrpPos()
    local nums = {}
    for i = 1, math.min(n, 8) do
        local v = a[i]
        parts[i] = dumpVal(v)
        if looksLikePos(v) then hasPos = true end
        if type(v) == 'number' then nums[#nums + 1] = v end
    end
    -- heuristic: 3+ numeric args that match the current HRP position (±60) = a
    -- position triple sent as separate numbers.
    if px and #nums >= 3 then
        for i = 1, #nums - 2 do
            if math.abs(nums[i] - px) < 60 and math.abs(nums[i+1] - py) < 60 and math.abs(nums[i+2] - pz) < 60 then
                hasPos = true; break
            end
        end
    end
    return table.concat(parts, ', '), hasPos
end

local function recordFire(name, method, a, n)
    local argstr, hasPos = scanArgs(a, n)
    local s = summary[name]
    if not s then
        s = { count = 0, method = method, carriesPos = false, sample = argstr, firstT = now() }
        summary[name] = s
    end
    s.count = s.count + 1
    s.lastT = now()
    if hasPos then s.carriesPos = true; s.posSample = argstr end
    if #fires < MAXFIRE then
        local px, py, pz = hrpPos()
        fires[#fires + 1] = { t = now(), name = name, method = method, args = argstr,
            hasPos = hasPos, at = px and ('%.0f,%.0f,%.0f'):format(px, py, pz) or nil }
    end
end

-- ═════════════ HOOK FireServer / InvokeServer (proven pattern) ════
pcall(function()
    if not hookfunction then hookStatus = 'no hookfunction'; return end
    local sampleE, sampleF
    for _, d in ipairs(RS:GetDescendants()) do
        if not sampleE and d:IsA('RemoteEvent') then sampleE = d end
        if not sampleF and d:IsA('RemoteFunction') then sampleF = d end
        if sampleE and sampleF then break end
    end
    local okE, okF = false, false
    if sampleE then
        local of; local ok = pcall(function()
            of = hookfunction(sampleE.FireServer, function(self, ...)
                if ACTIVE then local a = table.pack(...); pcall(recordFire, self.Name, 'FireServer', a, a.n) end
                return of(self, ...)
            end)
        end); okE = ok
    end
    if sampleF then
        local oi; local ok = pcall(function()
            oi = hookfunction(sampleF.InvokeServer, function(self, ...)
                if ACTIVE then local a = table.pack(...); pcall(recordFire, self.Name, 'InvokeServer', a, a.n) end
                return oi(self, ...)
            end)
        end); okF = ok
    end
    hookStatus = ('FireServer:%s InvokeServer:%s'):format(okE and 'OK' or 'x', okF and 'OK' or 'x')
end)

-- ═════════════ POSITION + VELOCITY SAMPLER (detect rubber-band) ═══
task.spawn(function()
    local lx, ly, lz
    while true do
        RunService.Heartbeat:Wait()
        if ACTIVE then
            local r = getRoot()
            if r then
                local p = r.Position
                local vx, vy, vz = 0, 0, 0
                pcall(function() local v = r.AssemblyLinearVelocity; vx, vy, vz = v.X, v.Y, v.Z end)
                if #posTL < MAXPOS then
                    posTL[#posTL + 1] = { t = now(), x = p.X, y = p.Y, z = p.Z, vx = vx, vy = vy, vz = vz }
                end
                if lx then
                    local d = math.sqrt((p.X-lx)^2 + (p.Y-ly)^2 + (p.Z-lz)^2)
                    if d > JUMP_STUDS then
                        jumps[#jumps + 1] = { t = now(), dist = d,
                            from = ('%.0f,%.0f,%.0f'):format(lx, ly, lz),
                            to   = ('%.0f,%.0f,%.0f'):format(p.X, p.Y, p.Z) }
                    end
                end
                lx, ly, lz = p.X, p.Y, p.Z
            end
        end
    end
end)

-- ═════════════ JSON ══════════════════════════════════════════════
local function toJSON(v, indent)
    indent = indent or 0
    local pad = string.rep('  ', indent + 1)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' or t == 'number' then return tostring(v) end
    if t == 'string' then return '"' .. v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r') .. '"' end
    if t == 'table' then
        local arr, mx = true, 0
        for k in pairs(v) do if type(k) ~= 'number' then arr = false break end if k > mx then mx = k end end
        if arr and mx > 0 then
            local p = {}; for i = 1, mx do p[i] = toJSON(v[i], indent+1) end
            return '[\n'..pad..table.concat(p, ',\n'..pad)..'\n'..string.rep('  ',indent)..']'
        else
            local p = {}; for k,val in pairs(v) do p[#p+1] = '"'..tostring(k)..'": '..toJSON(val, indent+1) end
            if #p == 0 then return '{}' end
            return '{\n'..pad..table.concat(p, ',\n'..pad)..'\n'..string.rep('  ',indent)..'}'
        end
    end
    return '"<'..t..'>"'
end

local function save()
    -- build remotes_carrying_position list (the bypass candidates)
    local carriers = {}
    for name, s in pairs(summary) do
        if s.carriesPos then carriers[#carriers + 1] = { name = name, method = s.method, count = s.count, sample = s.posSample } end
    end
    local report = {
        time = os.date('%Y-%m-%d %H:%M:%S'), place_id = game.PlaceId, hook_status = hookStatus,
        duration = now(),
        remotes_carrying_position = carriers,   -- <- if non-empty: CLIENT-REPORTED (bypassable)
        position_jumps = jumps,                  -- <- TP-out then snap-back = SERVER-SIDE rubber-band
        marks = marks,
        remote_summary = summary,
        position_timeline = posTL,
        fires = fires,
    }
    local json = toJSON(report)
    local path = ('HSHub_TPDetectSpy_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    return saved, path, #carriers, #jumps
end

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_TPDetectSpy_'..tostring(math.random(100000,999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_TPDetectSpy = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 430, 0, 250); frame.Position = UDim2.new(0, 20, 0.4, -125)
frame.BackgroundColor3 = Color3.fromRGB(22, 18, 26); frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame); stroke.Color = Color3.fromRGB(230, 160, 90); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame); header.Size = UDim2.new(1,0,0,46); header.BorderSizePixel = 0
header.BackgroundColor3 = Color3.fromRGB(230, 160, 90)
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local title = Instance.new('TextLabel', header); title.BackgroundTransparency = 1
title.Size = UDim2.new(1,-60,1,0); title.Position = UDim2.new(0,14,0,0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.TextColor3 = Color3.fromRGB(30,22,18)
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = 'HS HUB · TPDetectSpy'
local closeBtn = Instance.new('TextButton', header); closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-45,0,3)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22; closeBtn.TextColor3 = Color3.fromRGB(30,22,18); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() gui:Destroy(); shared.__HSHub_TPDetectSpy = nil end)

local stat = Instance.new('TextLabel', frame); stat.BackgroundTransparency = 1
stat.Size = UDim2.new(1,-28,0,46); stat.Position = UDim2.new(0,14,0,52)
stat.Font = Enum.Font.Code; stat.TextSize = 11; stat.TextColor3 = Color3.fromRGB(235,210,180)
stat.TextXAlignment = Enum.TextXAlignment.Left; stat.TextYAlignment = Enum.TextYAlignment.Top; stat.TextWrapped = true
stat.Text = 'Hooks: '..hookStatus..'\nStart, lalu TP yang biasanya ke-detect. Tekan Mark pas keliatan ke-flag.'

local function mk(label, col, x, w)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0,w,0,32); b.Position = UDim2.new(0,x,0,108)
    b.BackgroundColor3 = col; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(30,22,18); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local startBtn = mk('▶ Start', Color3.fromRGB(110,200,130), 14, 95)
local stopBtn  = mk('■ Stop',  Color3.fromRGB(210,120,110), 113, 95)
local markBtn  = mk('⚑ Mark',  Color3.fromRGB(235,200,110), 212, 95)
local saveBtn  = mk('💾 Save',  Color3.fromRGB(120,170,225), 311, 95)

local res = Instance.new('TextLabel', frame); res.BackgroundTransparency = 1
res.Size = UDim2.new(1,-28,0,86); res.Position = UDim2.new(0,14,0,148)
res.Font = Enum.Font.Code; res.TextSize = 11; res.TextColor3 = Color3.fromRGB(180,220,200)
res.TextXAlignment = Enum.TextXAlignment.Left; res.TextYAlignment = Enum.TextYAlignment.Top; res.TextWrapped = true
res.Text = 'Ready.'

startBtn.MouseButton1Click:Connect(function()
    ACTIVE = true; START = tick()
    summary = {}; fires = {}; posTL = {}; jumps = {}; marks = {}
    res.TextColor3 = Color3.fromRGB(170,230,180); res.Text = 'RECORDING. TP sekarang.'
end)
stopBtn.MouseButton1Click:Connect(function()
    ACTIVE = false
    local nc = 0; for _,s in pairs(summary) do if s.carriesPos then nc = nc + 1 end end
    res.Text = ('STOP. remotes=%d  pos-carrying=%d  jumps=%d  marks=%d'):format(
        (function() local n=0 for _ in pairs(summary) do n=n+1 end return n end)(), nc, #jumps, #marks)
end)
markBtn.MouseButton1Click:Connect(function()
    if not ACTIVE then return end
    local px,py,pz = hrpPos()
    marks[#marks+1] = { t = now(), pos = px and ('%.0f,%.0f,%.0f'):format(px,py,pz) or '?' }
    res.Text = ('⚑ MARK @ %.2fs (jumps so far=%d)'):format(now(), #jumps)
end)
saveBtn.MouseButton1Click:Connect(function()
    local ok, path, carriers, njumps = save()
    res.TextColor3 = Color3.fromRGB(170,230,180)
    res.Text = ('Saved: %s\npos-carrying remotes=%d  jumps=%d\n(non-empty carriers = CLIENT-REPORTED = bypassable)')
        :format(ok and ('workspace/'..path) or 'clipboard only', carriers, njumps)
end)
