--[[
═══════════════════════════════════════════════════════════════════════
                    HS HUB · PROBE
              Comprehensive game data gatherer (the one tool)
                    discord.gg/5rpP6faZSJ

    PURPOSE
        Single-tool replacement for Inspector + Sentinel.
        Captures EVERYTHING needed for HS Hub fix/update/maintenance:
          • Full static structure (remotes, workspace, RS modules, PlayerGui)
          • Live RemoteEvent/RemoteFunction/BindableEvent calls
          • Module API introspection (require + dump return structure)
          • Anti-cheat / kick / GUI-creation detection
          • Baseline + diff (track game changes over time)
          • Per-feature labeled captures (multi-trace per session)

    WORKFLOW
        1. Paste this Probe in executor FIRST (before any hub)
        2. UI panel auto-opens. Static scan + module inspection runs
        3. Click "Start Capture" with label like "Hellion shrine ON"
        4. Load working hub (e.g. catnex LUNAR loader)
        5. Toggle the feature you want to trace
        6. After 30-60s click "Stop" → "Save Report"
        7. Run again later → auto-diff vs baseline detects game changes

    REUSABLE per-game via PLACE_SPECS at top of file.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_Probe_Running then
    pcall(function() shared.__HSHub_Probe_Running:Destroy() end)
end

-- ═════════════ PER-GAME SPECS ══════════════════════════════════════
local PLACE_SPECS = {
    [5233782396] = {
        name = 'Creatures of Sonaria',
        remotes_root = 'ReplicatedStorage.Remotes',
        notable_workspace = { 'Interactions', 'Warden Shrines' },
        modules_to_inspect = {
            'ArtifactUtils', 'WardenShrine', 'PlayerWrapper', 'HUDGui',
            'Nest', 'NestingService', 'TokenService', 'GachaService',
            'CharacterWrapper', 'AilmentsService', 'StatsService',
        },
        expected_remotes_RS = {
            'DrinkRemote', 'Food', 'Mud', 'Lay', 'Nest',
            'LavaSelfDamage', 'Sheltered', 'StateAilment',
            'RestartSlotRemote', 'GetSpawnedTokenRemote',
            'StoreActiveCreatureRemote', 'CreateSlotRemote',
            'PickupResource', 'DepositResource', 'ChunkResource',
            'ResourceDamageRemote', 'UpgradeNest', 'WardenOffering',
        },
        expected_remotes_LP = {
            'NestRequestRemote', 'NestJoinRequestRemote',
            'PartyRequestRemote', 'PartyJoinRequestRemote',
            'NestSlotPickRequestRemote',
        },
    },
    [3431407618] = { name='Isle 10', remotes_root='?', notable_workspace={}, modules_to_inspect={}, expected_remotes_RS={}, expected_remotes_LP={} },
}

local SPEC = PLACE_SPECS[game.PlaceId] or {
    name='Unknown', remotes_root='?', notable_workspace={},
    modules_to_inspect={}, expected_remotes_RS={}, expected_remotes_LP={},
}

-- ═════════════ NOISE FILTER (skip telemetry spam) ══════════════════
local IGNORE_PATHS = {
    'EventExportClientMetrics',
    'StaminaAnalytics',
    'SHImpressionsAnalytics',
    'EventRsvpAnalytics',
    'SendHomePurchaseAnalytics',
    'GameAnalytics',
}
local function isNoise(path)
    for _, p in ipairs(IGNORE_PATHS) do
        if path:find(p, 1, true) then return true end
    end
    return false
end

-- ═════════════ STATE ═══════════════════════════════════════════════
local Players = game:GetService('Players')
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild('PlayerGui')
local RS      = game:GetService('ReplicatedStorage')
local WS      = game:GetService('Workspace')
local UIS     = game:GetService('UserInputService')

local CAPTURE = {
    active = false, start_time = 0, label = 'unlabeled',
    events = {}, gui_events = {}, kick_events = {},
}
local STATIC = {}
local MODULES = {}
local DIFF = nil

-- ═════════════ STATIC DUMP ═════════════════════════════════════════
local function classifyRemote(inst)
    return inst.ClassName  -- RemoteEvent / RemoteFunction / BindableEvent / etc
end

local function dumpStatic()
    local s = { remotes_RS={}, remotes_LP={}, workspace_tree={}, replicated_modules={}, playergui_tree={} }

    -- ReplicatedStorage.Remotes
    local rsR = RS:FindFirstChild('Remotes')
    if rsR then
        for _, c in ipairs(rsR:GetChildren()) do
            table.insert(s.remotes_RS, { name=c.Name, class=c.ClassName })
        end
    end

    -- LocalPlayer.Remotes
    local lpR = LP:FindFirstChild('Remotes')
    if lpR then
        for _, c in ipairs(lpR:GetChildren()) do
            table.insert(s.remotes_LP, { name=c.Name, class=c.ClassName })
        end
    end

    -- Workspace.Interactions (depth-1)
    local inter = WS:FindFirstChild('Interactions')
    if inter then
        s.workspace_tree['Interactions'] = {}
        for _, c in ipairs(inter:GetChildren()) do
            local n = 0
            pcall(function() n = #c:GetChildren() end)
            local entry = { name=c.Name, class=c.ClassName, children=n }
            if c.Name == 'Warden Shrines' then
                entry.shrines = {}
                pcall(function()
                    for _, sh in ipairs(c:GetChildren()) do
                        table.insert(entry.shrines, sh.Name)
                    end
                end)
            end
            table.insert(s.workspace_tree['Interactions'], entry)
        end
    end

    -- ReplicatedStorage._replicationFolder (top-level only — too deep otherwise)
    local rf = RS:FindFirstChild('_replicationFolder')
    if rf then
        for _, c in ipairs(rf:GetChildren()) do
            if c:IsA('ModuleScript') then
                table.insert(s.replicated_modules, { name=c.Name, class=c.ClassName })
            end
        end
    end

    -- PlayerGui top-level
    for _, c in ipairs(PG:GetChildren()) do
        table.insert(s.playergui_tree, { name=c.Name, class=c.ClassName, enabled=c.Enabled ~= false })
    end

    return s
end

-- ═════════════ MODULE INTROSPECTION ════════════════════════════════
local function describeValue(v, depth, max_depth)
    depth = depth or 0
    max_depth = max_depth or 2
    if depth > max_depth then return ('<%s>'):format(type(v)) end
    local t = type(v)
    if t == 'function' then return 'function' end
    if t == 'string' then return ('%q'):format(v:sub(1, 60)) end
    if t == 'number' or t == 'boolean' or t == 'nil' then return tostring(v) end
    if t == 'table' then
        local keys = {}
        local count = 0
        for k in pairs(v) do
            count = count + 1
            if count <= 30 then table.insert(keys, tostring(k)) end
        end
        return ('table{n=%d, keys=%s}'):format(count, table.concat(keys, ','):sub(1, 200))
    end
    if t == 'userdata' then
        local ok, n = pcall(function() return v.ClassName or '?' end)
        return ok and ('<userdata:%s>'):format(n) or '<userdata>'
    end
    return ('<%s>'):format(t)
end

local function inspectModule(mod)
    if not mod or not mod:IsA('ModuleScript') then return nil end
    local ok, result = pcall(function() return require(mod) end)
    if not ok then return { error=tostring(result):sub(1, 200) } end
    return {
        type = type(result),
        summary = describeValue(result, 0, 2),
        keys = (function()
            if type(result) ~= 'table' then return {} end
            local k = {}
            for key, v in pairs(result) do
                table.insert(k, { key=tostring(key), value_type=type(v),
                    value=describeValue(v, 0, 1) })
            end
            return k
        end)(),
    }
end

local function dumpModules()
    local out = {}
    local rf = RS:FindFirstChild('_replicationFolder')
    if not rf then return out end
    for _, name in ipairs(SPEC.modules_to_inspect or {}) do
        local mod = rf:FindFirstChild(name)
        if mod then
            out[name] = inspectModule(mod)
        else
            out[name] = { error='NOT FOUND in _replicationFolder' }
        end
    end
    return out
end

-- ═════════════ RUNTIME HOOK ═══════════════════════════════════════
local function argDump(args, n)
    local parts = {}
    for i = 1, n do
        local v = args[i]
        local t = type(v)
        if t == 'string' then
            parts[i] = ('%q'):format(v:sub(1, 60)) .. (#v > 60 and '...' or '')
        elseif t == 'number' or t == 'boolean' then
            parts[i] = tostring(v)
        elseif t == 'table' then
            parts[i] = describeValue(v, 0, 1)
        elseif t == 'userdata' then
            local ok, name = pcall(function() return v:GetFullName() end)
            parts[i] = ok and ('<'..name..'>') or '<userdata>'
        else
            parts[i] = ('<%s>'):format(t)
        end
    end
    return table.concat(parts, ', ')
end

local function recordCall(remote, method, args, n)
    if not CAPTURE.active then return end
    local path = 'unknown'
    pcall(function() path = remote:GetFullName() end)
    if isNoise(path) then return end  -- skip telemetry
    table.insert(CAPTURE.events, {
        t = tick() - CAPTURE.start_time,
        kind = method, path = path,
        args = argDump(args, n),
    })
end

local hookInstalled = false
local function installHook()
    if hookInstalled then return true end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt then return false, 'getrawmetatable unavailable' end
    pcall(setreadonly, mt, false)
    local old = mt.__namecall
    local hooked = function(self, ...)
        local m = getnamecallmethod and getnamecallmethod() or '?'
        if m == 'FireServer' or m == 'InvokeServer' or m == 'Fire' or m == 'Invoke' then
            local args = table.pack(...)
            recordCall(self, m, args, args.n)
        end
        return old(self, ...)
    end
    if newcclosure then hooked = newcclosure(hooked) end
    mt.__namecall = hooked
    pcall(setreadonly, mt, true)
    hookInstalled = true
    return true
end

-- ═════════════ ANTI-CHEAT / KICK WATCH ═════════════════════════════
local function watchProtection()
    -- Listen for own kick (= PlayerRemoving fires for us)
    Players.PlayerRemoving:Connect(function(p)
        if p == LP then
            table.insert(CAPTURE.kick_events, {
                t = tick() - CAPTURE.start_time,
                reason = 'PlayerRemoving fired for LocalPlayer (likely kick)',
            })
        end
    end)
    -- Watch for new ScreenGuis added to CoreGui or PlayerGui (anti-cheat UIs)
    local function isAcHint(name)
        if not name then return false end
        local n = name:lower()
        return n:find('ban') or n:find('warning') or n:find('exploit')
            or n:find('cheat') or n:find('detect') or n:find('kick')
    end
    PG.ChildAdded:Connect(function(c)
        if CAPTURE.active and (c:IsA('ScreenGui') or c:IsA('Folder')) and isAcHint(c.Name) then
            table.insert(CAPTURE.gui_events, {
                t = tick() - CAPTURE.start_time,
                event = 'PlayerGui:' .. c.Name .. ' [' .. c.ClassName .. ']',
            })
        end
    end)
end

-- ═════════════ DIFF (baseline compare) ═════════════════════════════
local BASELINE_PATH = ('HSHub_Probe_baseline_%s.txt'):format(tostring(game.PlaceId))

local function staticToString(s)
    local lines = {}
    table.insert(lines, ('RS.Remotes (%d):'):format(#s.remotes_RS))
    for _, r in ipairs(s.remotes_RS) do table.insert(lines, ('  %s [%s]'):format(r.name, r.class)) end
    table.insert(lines, ('LP.Remotes (%d):'):format(#s.remotes_LP))
    for _, r in ipairs(s.remotes_LP) do table.insert(lines, ('  %s [%s]'):format(r.name, r.class)) end
    table.insert(lines, ('Workspace tree:'))
    for k, list in pairs(s.workspace_tree) do
        table.insert(lines, ('  %s (%d):'):format(k, #list))
        for _, e in ipairs(list) do
            table.insert(lines, ('    %s [%s] (%d children)'):format(e.name, e.class, e.children))
        end
    end
    return table.concat(lines, '\n')
end

local function diffStatic(curr, base_text)
    -- Quick diff: convert current to lines and check missing/added
    local curr_text = staticToString(curr)
    local curr_lines, base_lines = {}, {}
    for line in curr_text:gmatch('[^\n]+') do curr_lines[line] = true end
    for line in base_text:gmatch('[^\n]+') do base_lines[line] = true end
    local added, removed = {}, {}
    for line in pairs(curr_lines) do if not base_lines[line] then table.insert(added, line) end end
    for line in pairs(base_lines) do if not curr_lines[line] then table.insert(removed, line) end end
    return { added=added, removed=removed,
        unchanged=(#added == 0 and #removed == 0) }
end

local function loadBaseline()
    if not readfile then return nil end
    if not isfile or not isfile(BASELINE_PATH) then return nil end
    local ok, txt = pcall(readfile, BASELINE_PATH)
    return ok and txt or nil
end

-- ═════════════ INIT — run static + modules immediately ════════════
STATIC = dumpStatic()
MODULES = dumpModules()
local baseline = loadBaseline()
if baseline then
    DIFF = diffStatic(STATIC, baseline)
end
watchProtection()

-- Validate spec
local function specValidate()
    local missing = { remotes={}, lp_remotes={} }
    local rs_set = {}
    for _, r in ipairs(STATIC.remotes_RS) do rs_set[r.name] = true end
    for _, name in ipairs(SPEC.expected_remotes_RS or {}) do
        if not rs_set[name] then table.insert(missing.remotes, name) end
    end
    local lp_set = {}
    for _, r in ipairs(STATIC.remotes_LP) do lp_set[r.name] = true end
    for _, name in ipairs(SPEC.expected_remotes_LP or {}) do
        if not lp_set[name] then table.insert(missing.lp_remotes, name) end
    end
    return missing
end
local SPEC_MISSING = specValidate()

-- ═════════════ REPORT BUILDER ══════════════════════════════════════
local function buildReport()
    local L = {}
    table.insert(L, '═══════════════════════════════════════════════════════════════════════')
    table.insert(L, 'HS HUB · PROBE REPORT')
    table.insert(L, ('Generated: %s'):format(os.date('%Y-%m-%d %H:%M:%S')))
    table.insert(L, ('Place    : %d  (%s)'):format(game.PlaceId, SPEC.name))
    table.insert(L, '═══════════════════════════════════════════════════════════════════════')

    -- 1. SPEC VALIDATION
    table.insert(L, '\n## SPEC VALIDATION')
    if SPEC.name == 'Unknown' then
        table.insert(L, '  [WARN] No spec for this PlaceId — baseline mode (full dump only)')
    else
        if #SPEC_MISSING.remotes == 0 and #SPEC_MISSING.lp_remotes == 0 then
            table.insert(L, '  [OK] All expected remotes present')
        else
            for _, n in ipairs(SPEC_MISSING.remotes) do
                table.insert(L, ('  [FAIL] RS missing: %s'):format(n))
            end
            for _, n in ipairs(SPEC_MISSING.lp_remotes) do
                table.insert(L, ('  [FAIL] LP missing: %s'):format(n))
            end
        end
    end

    -- 2. STATIC STRUCTURE
    table.insert(L, '\n## STATIC: REMOTES')
    table.insert(L, staticToString(STATIC))

    -- 3. MODULE INTROSPECTION
    table.insert(L, '\n## MODULE INTROSPECTION (require + dump return)')
    for name, info in pairs(MODULES) do
        if info.error then
            table.insert(L, ('  %s: ERROR %s'):format(name, info.error))
        else
            table.insert(L, ('  %s: %s'):format(name, info.summary))
            for _, k in ipairs(info.keys or {}) do
                table.insert(L, ('    .%s [%s] = %s'):format(k.key, k.value_type, k.value))
            end
        end
    end

    -- 4. DIFF (vs baseline)
    table.insert(L, '\n## DIFF (vs baseline if exists)')
    if not DIFF then
        table.insert(L, '  No baseline found. This run will be saved as baseline.')
    elseif DIFF.unchanged then
        table.insert(L, '  No changes detected vs baseline.')
    else
        for _, line in ipairs(DIFF.added) do table.insert(L, '  [+] ' .. line) end
        for _, line in ipairs(DIFF.removed) do table.insert(L, '  [-] ' .. line) end
    end

    -- 5. RUNTIME CAPTURE
    table.insert(L, '\n## RUNTIME CAPTURE')
    table.insert(L, ('  Label   : %s'):format(CAPTURE.label))
    table.insert(L, ('  Events  : %d (noise-filtered)'):format(#CAPTURE.events))
    table.insert(L, ('  GUI evts: %d'):format(#CAPTURE.gui_events))
    table.insert(L, ('  Kick    : %d'):format(#CAPTURE.kick_events))
    for i, e in ipairs(CAPTURE.events) do
        table.insert(L, ('  [%4d] +%6.2fs  %-13s  %s  (%s)')
            :format(i, e.t, e.kind, e.path, e.args))
    end
    for _, e in ipairs(CAPTURE.gui_events) do
        table.insert(L, ('  [GUI ] +%6.2fs  %s'):format(e.t, e.event))
    end
    for _, e in ipairs(CAPTURE.kick_events) do
        table.insert(L, ('  [KICK] +%6.2fs  %s'):format(e.t, e.reason))
    end

    return table.concat(L, '\n')
end

local function saveReport()
    local text = buildReport()
    local path = ('HSHub_Probe_%s_%d.txt'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, text); saved = true end end)
    -- Also save current static as baseline (overwrite previous)
    pcall(function() if writefile then writefile(BASELINE_PATH, staticToString(STATIC)) end end)
    pcall(function() if setclipboard then setclipboard(text) elseif toclipboard then toclipboard(text) end end)
    return saved, path
end

-- ═════════════ UI PANEL ════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_Probe_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_Probe_Running = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 420, 0, 460)
frame.Position = UDim2.new(0, 20, 0.4, -230)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(140, 90, 220); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 50)
header.BackgroundColor3 = Color3.fromRGB(140, 90, 220)
header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local hGrad = Instance.new('UIGradient', header)
hGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 90, 220)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 200, 230)),
})

local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · PROBE  (kelangsungan hub tool)'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 5)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_Probe_Running = nil
end)

-- Status (game + spec validation + diff)
local status = Instance.new('TextLabel', frame)
status.BackgroundTransparency = 1
status.Size = UDim2.new(1, -28, 0, 36); status.Position = UDim2.new(0, 14, 0, 56)
status.Font = Enum.Font.Gotham; status.TextSize = 12
status.TextColor3 = Color3.fromRGB(200, 220, 255)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
local specStatus = (SPEC.name == 'Unknown') and 'no spec (baseline mode)'
    or ((#SPEC_MISSING.remotes + #SPEC_MISSING.lp_remotes == 0)
        and 'spec OK' or ('SPEC: %d missing'):format(#SPEC_MISSING.remotes + #SPEC_MISSING.lp_remotes))
local diffStatus = (not DIFF) and 'no prev baseline'
    or (DIFF.unchanged and 'unchanged' or ('DIFF: +%d / -%d'):format(#DIFF.added, #DIFF.removed))
status.Text = ('Game: %s\nRemotes: RS=%d LP=%d · %s · %s'):format(
    SPEC.name, #STATIC.remotes_RS, #STATIC.remotes_LP, specStatus, diffStatus)

-- Label box
local lblBox = Instance.new('TextBox', frame)
lblBox.Size = UDim2.new(1, -28, 0, 30); lblBox.Position = UDim2.new(0, 14, 0, 100)
lblBox.BackgroundColor3 = Color3.fromRGB(28, 28, 36); lblBox.BorderSizePixel = 0
lblBox.Font = Enum.Font.Gotham; lblBox.TextSize = 12
lblBox.TextColor3 = Color3.fromRGB(220, 220, 240)
lblBox.PlaceholderText = 'Capture label (e.g. "Hellion Artifact ON 60s")'
lblBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 150)
lblBox.Text = ''; lblBox.ClearTextOnFocus = false
Instance.new('UICorner', lblBox).CornerRadius = UDim.new(0, 6)

-- Buttons row 1
local function btn(label, color, x, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, 130, 0, 30); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end

local startBtn = btn('▶  Start',  Color3.fromRGB(60, 140, 100), 14,  140)
local stopBtn  = btn('■  Stop',   Color3.fromRGB(160, 80, 80),  148, 140)
local saveBtn  = btn('💾 Save',   Color3.fromRGB(80, 120, 180), 282, 140)

-- Log view
local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 232); scroll.Position = UDim2.new(0, 10, 0, 180)
scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 22); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 90, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)

local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll)
pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6)

local function logRow(text, color)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -12, 0, 18)
    lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 10
    lbl.TextColor3 = color or Color3.fromRGB(180, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 20)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end

logRow('Static scan + module introspection done.',
    Color3.fromRGB(170, 230, 180))
logRow(('RS.Remotes: %d, LP.Remotes: %d, Modules: %d'):format(
    #STATIC.remotes_RS, #STATIC.remotes_LP, (function()
        local n = 0; for _ in pairs(MODULES) do n = n + 1 end; return n end)()),
    Color3.fromRGB(180, 220, 255))
if SPEC.name ~= 'Unknown' then
    if #SPEC_MISSING.remotes > 0 then
        logRow(('Missing %d expected remotes: %s'):format(#SPEC_MISSING.remotes,
            table.concat(SPEC_MISSING.remotes, ', ')), Color3.fromRGB(255, 150, 150))
    end
end
if DIFF and not DIFF.unchanged then
    logRow(('Diff vs baseline: +%d -%d'):format(#DIFF.added, #DIFF.removed),
        Color3.fromRGB(255, 200, 120))
end

-- Footer
local footer = Instance.new('TextLabel', frame)
footer.BackgroundTransparency = 1
footer.Size = UDim2.new(1, -28, 0, 30); footer.Position = UDim2.new(0, 14, 1, -36)
footer.Font = Enum.Font.Gotham; footer.TextSize = 10
footer.TextColor3 = Color3.fromRGB(160, 150, 200)
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextYAlignment = Enum.TextYAlignment.Top; footer.TextWrapped = true
footer.Text = 'After Start: load working hub → toggle feature → Stop → Save.\nReport saved to workspace + clipboard.'

-- Live capture log forwarder
local lastShown = 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.3)
        while lastShown < #CAPTURE.events do
            lastShown = lastShown + 1
            local e = CAPTURE.events[lastShown]
            local short = e.path:gsub('^game%.', ''):sub(1, 60)
            logRow(('[%6.2fs] %s  %s'):format(e.t, e.kind:sub(1,4), short),
                e.kind:find('Invoke') and Color3.fromRGB(230, 200, 130) or Color3.fromRGB(170, 200, 240))
        end
    end
end)

-- Button handlers
startBtn.MouseButton1Click:Connect(function()
    local ok, err = installHook()
    if not ok then
        logRow('Hook FAILED: ' .. tostring(err), Color3.fromRGB(255, 130, 130))
        return
    end
    CAPTURE.active = true
    CAPTURE.start_time = tick()
    CAPTURE.label = lblBox.Text ~= '' and lblBox.Text or 'unlabeled'
    CAPTURE.events, CAPTURE.gui_events, CAPTURE.kick_events = {}, {}, {}
    lastShown = 0
    for _, c in ipairs(scroll:GetChildren()) do if c:IsA('TextLabel') then c:Destroy() end end
    logRow(('Started capture: %q'):format(CAPTURE.label), Color3.fromRGB(170, 230, 180))
    logRow('Now load the hub to inspect.', Color3.fromRGB(220, 200, 130))
end)

stopBtn.MouseButton1Click:Connect(function()
    if not CAPTURE.active then return end
    CAPTURE.active = false
    local elapsed = tick() - CAPTURE.start_time
    logRow(('Stopped. %d events / %d gui / %d kick over %.1fs'):format(
        #CAPTURE.events, #CAPTURE.gui_events, #CAPTURE.kick_events, elapsed),
        Color3.fromRGB(230, 180, 130))
end)

saveBtn.MouseButton1Click:Connect(function()
    local saved, path = saveReport()
    logRow(saved and ('Saved: workspace/' .. path) or 'Save failed (no writefile)',
        Color3.fromRGB(170, 230, 180))
    logRow('Baseline updated. Report copied to clipboard.',
        Color3.fromRGB(160, 150, 200))
end)
