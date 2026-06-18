--[[
═══════════════════════════════════════════════════════════════════════
                HS HUB · DeepRecon  (Universal Edition)
    Deep reconnaissance for UNKNOWN games — finds what Probe missed
                    discord.gg/5rpP6faZSJ

    WHY THIS EXISTS:
        Standard Probe + ActionSpy assume remotes live in
        RS.Remotes or LP.Remotes (Creatures of Sonaria layout).
        Hollowed Era returned 0 remotes + 0 captured events because
        its networking is structured differently.

        This tool walks THE ENTIRE GAME TREE to find every remote,
        uses DUAL hook methods (hookfunction + __namecall), and
        scans workspace deeply for enemy/NPC structures.

    WHAT IT CAPTURES:
        ① ALL RemoteEvent / RemoteFunction / UnreliableRemoteEvent
           across ALL services (not just RS)
        ② Full Workspace tree (enemies, NPCs, quest objects)
        ③ PlayerGui tree (quest dialogs, HUD buttons)
        ④ DUAL-METHOD remote fire interception:
           - hookfunction (patches C-closure, catches everything)
           - __namecall fallback (catches :Method() style calls)
        ⑤ Module enumeration in RS (for require-based inspection)

    WORKFLOW:
        1. Join Hollowed Era
        2. Paste this FIRST (before doing anything)
        3. Wait for "STATIC SCAN DONE" in the log panel
        4. Click ▶ Start Capture
        5. Set label → do ONE action → repeat:
             TALK-NPC      → walk up to NPC, interact
             ACCEPT-QUEST  → accept a quest
             ATTACK-M1     → basic melee attack
             ATTACK-SKILL  → use a skill
             DODGE          → dodge
        6. Click ■ Stop → 💾 Save
        7. Send the JSON file
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_DeepRecon then
    pcall(function() shared.__HSHub_DeepRecon:Destroy() end)
end

local Players    = game:GetService('Players')
local RS         = game:GetService('ReplicatedStorage')
local SS         = game:GetService('ServerStorage')  -- client can't read, but enumerate
local WS         = game:GetService('Workspace')
local LP         = Players.LocalPlayer
local PG         = LP:WaitForChild('PlayerGui')
local Lighting   = game:GetService('Lighting')
local StarterGui = game:GetService('StarterGui')

-- ═════════════ STATE ═════════════════════════════════════════════
local ACTIVE     = false
local START      = 0
local curLabel   = '(none)'
local timeline   = {}     -- {t, name, path, method, args, label, source}
local summary    = {}     -- path -> {count, method, labels, sample, source}
local labels     = {}     -- {t, label}
local MAX_TL     = 3000
local hookStatus = { hookfn = 'init', namecall = 'init' }

-- Static scan results
local STATIC = {
    all_remotes = {},       -- every remote found across all services
    workspace_tree = {},    -- workspace structure (enemies, NPCs, etc)
    playergui_tree = {},    -- PlayerGui structure (quest dialogs)
    rs_modules = {},        -- ModuleScripts in RS
    character_info = {},    -- player character structure
}

local function now() return ACTIVE and (tick() - START) or 0 end

-- ═════════════ HELPERS ═════════════════════════════════════════════
local function safeName(inst)
    local ok, n = pcall(function() return inst:GetFullName() end)
    return ok and n or (pcall(function() return inst.Name end) and inst.Name or '?')
end

local function dumpVal(v, depth)
    depth = depth or 0
    local t = typeof and typeof(v) or type(v)
    if t == 'string' then
        if #v > 120 then return 'str['..#v..'B]:'..v:sub(1,120) end
        return '"'..v..'"'
    elseif t == 'number' or t == 'boolean' then return tostring(v)
    elseif t == 'nil' then return 'nil'
    elseif t == 'Instance' then
        return ('<I:%s %s>'):format(v.ClassName, safeName(v))
    elseif t == 'Vector3' then
        return ('V3(%.1f,%.1f,%.1f)'):format(v.X, v.Y, v.Z)
    elseif t == 'CFrame' then
        local p = v.Position
        return ('CF(%.1f,%.1f,%.1f)'):format(p.X, p.Y, p.Z)
    elseif t == 'table' then
        if depth > 2 then return '{..}' end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 10 then parts[#parts+1] = '...+'..tostring(n); break end
            parts[#parts+1] = tostring(k)..'='..dumpVal(val, depth+1)
        end
        return '{'..table.concat(parts, ', ')..'}'
    elseif t == 'EnumItem' then return tostring(v)
    end
    return '<'..t..'>'
end

local function dumpArgs(a, n)
    local p = {}
    for i = 1, math.min(n or 0, 10) do p[i] = dumpVal(a[i]) end
    return table.concat(p, ', ')
end

-- ═════════════ PHASE 1: DEEP REMOTE SCAN ═══════════════════════════
-- Walk EVERY accessible service for RemoteEvent/RemoteFunction/
-- UnreliableRemoteEvent/BindableEvent — no assumptions about location.

local REMOTE_CLASSES = {
    'RemoteEvent', 'RemoteFunction',
    'UnreliableRemoteEvent',
    'BindableEvent', 'BindableFunction',
}
local REMOTE_SET = {}
for _, c in ipairs(REMOTE_CLASSES) do REMOTE_SET[c] = true end

local function scanServiceForRemotes(service, serviceName)
    local found = {}
    local ok, err = pcall(function()
        for _, d in ipairs(service:GetDescendants()) do
            if REMOTE_SET[d.ClassName] then
                found[#found+1] = {
                    name = d.Name,
                    class = d.ClassName,
                    path = safeName(d),
                    parent = d.Parent and d.Parent.Name or '?',
                    parent_class = d.Parent and d.Parent.ClassName or '?',
                    service = serviceName,
                }
            end
        end
    end)
    return found, err
end

local function deepRemoteScan()
    local all = {}
    local services = {
        { RS, 'ReplicatedStorage' },
        { WS, 'Workspace' },
        { Lighting, 'Lighting' },
        { StarterGui, 'StarterGui' },
    }
    -- Also scan LP's descendants
    pcall(function()
        local lpFound, _ = scanServiceForRemotes(LP, 'LocalPlayer')
        for _, r in ipairs(lpFound) do all[#all+1] = r end
    end)
    -- Scan PlayerGui separately
    pcall(function()
        local pgFound, _ = scanServiceForRemotes(PG, 'PlayerGui')
        for _, r in ipairs(pgFound) do all[#all+1] = r end
    end)
    -- Scan main services
    for _, sv in ipairs(services) do
        local found, _ = scanServiceForRemotes(sv[1], sv[2])
        for _, r in ipairs(found) do all[#all+1] = r end
    end
    -- Try ReplicatedFirst
    pcall(function()
        local rf = game:GetService('ReplicatedFirst')
        local found, _ = scanServiceForRemotes(rf, 'ReplicatedFirst')
        for _, r in ipairs(found) do all[#all+1] = r end
    end)
    -- Try SoundService (some games hide remotes here)
    pcall(function()
        local ss = game:GetService('SoundService')
        local found, _ = scanServiceForRemotes(ss, 'SoundService')
        for _, r in ipairs(found) do all[#all+1] = r end
    end)
    return all
end

-- ═════════════ PHASE 2: WORKSPACE DEEP TREE ══════════════════════════
-- Walk workspace 3 levels deep to find enemies, NPCs, quest objects, etc.

local WS_KEYWORDS = {
    'enemy', 'enemies', 'mob', 'mobs', 'npc', 'npcs', 'quest',
    'monster', 'boss', 'spawn', 'character', 'combat', 'weapon',
    'attack', 'damage', 'health', 'hitbox', 'hurtbox',
    'interact', 'dialog', 'dialogue', 'shop', 'vendor',
    'dungeon', 'zone', 'region', 'area', 'portal', 'teleport',
    'loot', 'drop', 'item', 'chest', 'reward', 'hollowed',
}

local function matchesKeyword(name)
    local lower = name:lower()
    for _, kw in ipairs(WS_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

local function scanWorkspace()
    local tree = {}
    local interesting = {}
    pcall(function()
        -- Top-level children
        for _, child in ipairs(WS:GetChildren()) do
            local entry = {
                name = child.Name,
                class = child.ClassName,
                children_count = 0,
                children = {},
                is_interesting = matchesKeyword(child.Name),
                has_humanoid = child:FindFirstChildOfClass('Humanoid') ~= nil,
                attrs = {},
            }
            -- Get attributes
            pcall(function()
                for k, v in pairs(child:GetAttributes()) do
                    entry.attrs[k] = { type = type(v), value = tostring(v):sub(1, 80) }
                end
            end)
            -- Depth-2 children
            pcall(function()
                local kids = child:GetChildren()
                entry.children_count = #kids
                for _, sub in ipairs(kids) do
                    local sub_entry = {
                        name = sub.Name,
                        class = sub.ClassName,
                        children_count = 0,
                        is_interesting = matchesKeyword(sub.Name),
                        has_humanoid = sub:FindFirstChildOfClass('Humanoid') ~= nil,
                    }
                    pcall(function() sub_entry.children_count = #sub:GetChildren() end)
                    entry.children[#entry.children+1] = sub_entry

                    -- If interesting, go depth-3
                    if sub_entry.is_interesting or sub_entry.has_humanoid then
                        sub_entry.depth3 = {}
                        pcall(function()
                            for _, d3 in ipairs(sub:GetChildren()) do
                                sub_entry.depth3[#sub_entry.depth3+1] = {
                                    name = d3.Name,
                                    class = d3.ClassName,
                                    has_humanoid = d3:FindFirstChildOfClass('Humanoid') ~= nil,
                                }
                            end
                        end)
                    end
                end
            end)
            tree[#tree+1] = entry
            if entry.is_interesting or entry.has_humanoid then
                interesting[#interesting+1] = entry.name
            end
        end
    end)
    return tree, interesting
end

-- ═════════════ PHASE 3: PLAYERGUI DEEP SCAN ═══════════════════════
-- Walk PlayerGui 3 levels deep, especially look for quest/dialog/button elements.

local function scanPlayerGui()
    local tree = {}
    pcall(function()
        for _, sg in ipairs(PG:GetChildren()) do
            if sg:IsA('ScreenGui') then
                local entry = {
                    name = sg.Name,
                    enabled = sg.Enabled ~= false,
                    children = {},
                }
                pcall(function()
                    for _, c in ipairs(sg:GetChildren()) do
                        local ce = {
                            name = c.Name,
                            class = c.ClassName,
                            visible = true,
                            children = {},
                        }
                        pcall(function() ce.visible = c.Visible end)
                        -- Depth-3 for buttons / text
                        pcall(function()
                            for _, d in ipairs(c:GetChildren()) do
                                local de = {
                                    name = d.Name,
                                    class = d.ClassName,
                                }
                                if d:IsA('TextLabel') or d:IsA('TextButton') then
                                    pcall(function() de.text = d.Text:sub(1, 60) end)
                                end
                                ce.children[#ce.children+1] = de
                            end
                        end)
                        entry.children[#entry.children+1] = ce
                    end
                end)
                tree[#tree+1] = entry
            end
        end
    end)
    return tree
end

-- ═════════════ PHASE 4: MODULE ENUMERATION ════════════════════════
local function scanModules()
    local mods = {}
    pcall(function()
        for _, d in ipairs(RS:GetDescendants()) do
            if d:IsA('ModuleScript') then
                mods[#mods+1] = {
                    name = d.Name,
                    path = safeName(d),
                    parent = d.Parent and d.Parent.Name or '?',
                }
            end
        end
    end)
    return mods
end

-- ═════════════ PHASE 5: CHARACTER INFO ═══════════════════════════
local function scanCharacter()
    local info = { found = false }
    pcall(function()
        local char = LP.Character
        if not char then return end
        info.found = true
        info.name = char.Name
        info.children = {}
        info.attrs = {}
        for _, c in ipairs(char:GetChildren()) do
            local ce = { name = c.Name, class = c.ClassName }
            if c:IsA('Humanoid') then
                pcall(function()
                    ce.health = c.Health
                    ce.maxHealth = c.MaxHealth
                    ce.walkSpeed = c.WalkSpeed
                    ce.jumpPower = c.JumpPower
                end)
            end
            -- Get attributes on child
            pcall(function()
                local a = c:GetAttributes()
                if next(a) then
                    ce.attrs = {}
                    for k, v in pairs(a) do
                        ce.attrs[k] = tostring(v):sub(1, 60)
                    end
                end
            end)
            info.children[#info.children+1] = ce
        end
        -- Character-level attributes
        pcall(function()
            for k, v in pairs(char:GetAttributes()) do
                info.attrs[k] = tostring(v):sub(1, 60)
            end
        end)
    end)
    -- Also look in Workspace for alternative character containers
    pcall(function()
        for _, name in ipairs({'Characters', 'Alive', 'Entities', 'Players_'..LP.Name}) do
            local folder = WS:FindFirstChild(name)
            if folder then
                info.alt_container = { name = name, children = {} }
                for _, c in ipairs(folder:GetChildren()) do
                    info.alt_container.children[#info.alt_container.children+1] = {
                        name = c.Name, class = c.ClassName,
                    }
                end
            end
        end
    end)
    return info
end

-- ═════════════ RECORD (shared by both hook methods) ═══════════════
local liveQueue = {}
local function recordCall(name, path, method, argstr, source)
    if not ACTIVE then return end
    local s = summary[path]
    if not s then
        s = { count = 0, name = name, method = method, labels = {}, sample = argstr, source = source }
        summary[path] = s
    end
    s.count = s.count + 1
    s.labels[curLabel] = (s.labels[curLabel] or 0) + 1
    if #timeline < MAX_TL then
        timeline[#timeline+1] = {
            t = now(), name = name, path = path,
            method = method, args = argstr,
            label = curLabel, source = source,
        }
    end
    liveQueue[#liveQueue+1] = {
        t = now(), name = name, method = method,
        args = argstr, label = curLabel, source = source,
    }
end

-- ═════════════ DUAL HOOKS ══════════════════════════════════════════
-- METHOD A: hookfunction (patches C-closure — catches all including cached refs)
-- METHOD B: __namecall (catches :Method() calls — backup for edge cases)

local function installHooks()
    local cc = checkcaller

    -- ─── METHOD A: hookfunction ────────────────────────────────────
    -- Search ALL services for a sample (not just RS like ActionSpy does)
    local function findAnySample(className)
        -- Try RS first
        for _, d in ipairs(RS:GetDescendants()) do
            if d:IsA(className) then return d end
        end
        -- Try Workspace
        pcall(function()
            for _, d in ipairs(WS:GetDescendants()) do
                if d:IsA(className) then return d end
            end
        end)
        -- Try LP
        pcall(function()
            for _, d in ipairs(LP:GetDescendants()) do
                if d:IsA(className) then return d end
            end
        end)
        -- Try PG
        pcall(function()
            for _, d in ipairs(PG:GetDescendants()) do
                if d:IsA(className) then return d end
            end
        end)
        return nil
    end

    pcall(function()
        if not hookfunction then
            hookStatus.hookfn = 'NO hookfunction'
            return
        end

        -- FireServer hook
        local sampleE = findAnySample('RemoteEvent')
        if sampleE then
            local of
            local ok = pcall(function()
                of = hookfunction(sampleE.FireServer, function(self, ...)
                    if ACTIVE and not (cc and cc()) then
                        local a = table.pack(...)
                        pcall(recordCall, self.Name, safeName(self), 'FireServer',
                            dumpArgs(a, a.n), 'hookfn')
                    end
                    return of(self, ...)
                end)
            end)
            hookStatus.hookfn_fire = ok and 'OK' or 'FAIL'
        else
            hookStatus.hookfn_fire = 'no-sample-RE'
        end

        -- InvokeServer hook
        local sampleF = findAnySample('RemoteFunction')
        if sampleF then
            local oi
            local ok = pcall(function()
                oi = hookfunction(sampleF.InvokeServer, function(self, ...)
                    if ACTIVE and not (cc and cc()) then
                        local a = table.pack(...)
                        pcall(recordCall, self.Name, safeName(self), 'InvokeServer',
                            dumpArgs(a, a.n), 'hookfn')
                    end
                    return oi(self, ...)
                end)
            end)
            hookStatus.hookfn_invoke = ok and 'OK' or 'FAIL'
        else
            hookStatus.hookfn_invoke = 'no-sample-RF'
        end

        -- UnreliableRemoteEvent hook (newer Roblox networking)
        local sampleU = findAnySample('UnreliableRemoteEvent')
        if sampleU then
            local ou
            local ok = pcall(function()
                ou = hookfunction(sampleU.FireServer, function(self, ...)
                    if ACTIVE and not (cc and cc()) then
                        local a = table.pack(...)
                        pcall(recordCall, self.Name, safeName(self), 'FireServer(Unreliable)',
                            dumpArgs(a, a.n), 'hookfn-unreliable')
                    end
                    return ou(self, ...)
                end)
            end)
            hookStatus.hookfn_unreliable = ok and 'OK' or 'FAIL'
        else
            hookStatus.hookfn_unreliable = 'no-sample-URE'
        end

        hookStatus.hookfn = 'installed'
    end)

    -- ─── METHOD B: __namecall hook ─────────────────────────────────
    pcall(function()
        local mt = getrawmetatable(game)
        if not mt then hookStatus.namecall = 'NO metatable'; return end

        local old_nc = mt.__namecall
        if not old_nc then hookStatus.namecall = 'NO __namecall'; return end

        local setreadonly = setreadonly or make_writeable
        if setreadonly then pcall(setreadonly, mt, false) end

        local FIRE_METHODS = {
            FireServer = true, InvokeServer = true,
            Fire = true, Invoke = true,
        }

        mt.__namecall = newcclosure and newcclosure(function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or ''
            if ACTIVE and FIRE_METHODS[method] and not (cc and cc()) then
                local ok, cls = pcall(function() return self.ClassName end)
                if ok and (cls == 'RemoteEvent' or cls == 'RemoteFunction'
                    or cls == 'UnreliableRemoteEvent'
                    or cls == 'BindableEvent' or cls == 'BindableFunction') then
                    local a = table.pack(...)
                    pcall(recordCall, self.Name, safeName(self),
                        method, dumpArgs(a, a.n), 'namecall')
                end
            end
            return old_nc(self, ...)
        end) or function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or ''
            if ACTIVE and FIRE_METHODS[method] and not (cc and cc()) then
                local ok, cls = pcall(function() return self.ClassName end)
                if ok and (cls == 'RemoteEvent' or cls == 'RemoteFunction'
                    or cls == 'UnreliableRemoteEvent'
                    or cls == 'BindableEvent' or cls == 'BindableFunction') then
                    local a = table.pack(...)
                    pcall(recordCall, self.Name, safeName(self),
                        method, dumpArgs(a, a.n), 'namecall')
                end
            end
            return old_nc(self, ...)
        end

        hookStatus.namecall = 'installed'
    end)
end

-- ═════════════ JSON SERIALIZER ═══════════════════════════════════
local function toJSON(v, indent)
    indent = indent or 0
    local pad1 = string.rep('  ', indent + 1)
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r',''):gsub('\t','\\t') .. '"'
    end
    if t == 'number' then
        if v ~= v then return '"NaN"' end
        if v == math.huge then return '"Inf"' end
        if v == -math.huge then return '"-Inf"' end
        return tostring(v)
    end
    if t == 'boolean' then return tostring(v) end
    if t == 'nil' then return 'null' end
    if t == 'table' then
        -- Detect array-like
        local isArr, maxK = true, 0
        for k in pairs(v) do
            if type(k) ~= 'number' then isArr = false; break end
            if k > maxK then maxK = k end
        end
        if isArr and maxK > 0 then
            local p = {}
            for i = 1, maxK do p[i] = toJSON(v[i], indent + 1) end
            if #p == 0 then return '[]' end
            return '[\n'..pad1..table.concat(p, ',\n'..pad1)..'\n'..string.rep('  ', indent)..']'
        else
            local p = {}
            for k, val in pairs(v) do
                p[#p+1] = '"'..tostring(k)..'": '..toJSON(val, indent + 1)
            end
            if #p == 0 then return '{}' end
            return '{\n'..pad1..table.concat(p, ',\n'..pad1)..'\n'..string.rep('  ', indent)..'}'
        end
    end
    return '"<'..t..'>"'
end

-- ═════════════ SAVE ═══════════════════════════════════════════════
local function saveReport()
    local report = {
        tool       = 'HSHub_DeepRecon v1.0',
        time       = os.date('%Y-%m-%d %H:%M:%S'),
        place_id   = game.PlaceId,
        place_name = game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId).Name or 'Unknown',
        hook_status = hookStatus,

        -- Static scan
        remotes_found   = STATIC.all_remotes,
        workspace_tree  = STATIC.workspace_tree,
        playergui_tree  = STATIC.playergui_tree,
        rs_modules      = STATIC.rs_modules,
        character_info  = STATIC.character_info,
        ws_interesting  = STATIC.ws_interesting,

        -- Capture data
        labels   = labels,
        summary  = summary,
        timeline = timeline,
    }
    -- Safe place name fetch
    pcall(function()
        report.place_name = game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId).Name
    end)

    local json = toJSON(report)
    local path = ('HSHub_DeepRecon_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function()
        if setclipboard then setclipboard(json)
        elseif toclipboard then toclipboard(json) end
    end)
    return saved, path
end

-- ═════════════ UI ═══════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_DeepRecon_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_DeepRecon = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 460, 0, 520)
frame.Position = UDim2.new(0, 20, 0.3, -260)
frame.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(200, 120, 60)
stroke.Thickness = 1.5

-- Header
local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundColor3 = Color3.fromRGB(180, 100, 40)
header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)

local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = '🔍 HS HUB · DeepRecon (Hollowed Era)'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40)
closeBtn.Position = UDim2.new(1, -45, 0, 3)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
    shared.__HSHub_DeepRecon = nil
end)

-- Label textbox
local box = Instance.new('TextBox', frame)
box.Size = UDim2.new(1, -150, 0, 28)
box.Position = UDim2.new(0, 12, 0, 54)
box.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
box.BorderSizePixel = 0
box.Font = Enum.Font.Code
box.TextSize = 12
box.TextColor3 = Color3.fromRGB(230, 240, 230)
box.PlaceholderText = 'label: TALK-NPC / ATTACK-M1 / DODGE ...'
box.Text = ''
box.ClearTextOnFocus = false
Instance.new('UICorner', box).CornerRadius = UDim.new(0, 6)

local setBtn = Instance.new('TextButton', frame)
setBtn.Size = UDim2.new(0, 124, 0, 28)
setBtn.Position = UDim2.new(1, -134, 0, 54)
setBtn.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
setBtn.BorderSizePixel = 0
setBtn.Font = Enum.Font.GothamBold
setBtn.TextSize = 11
setBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
setBtn.Text = '🏷 Set Label'
Instance.new('UICorner', setBtn).CornerRadius = UDim.new(0, 6)

-- Status bar
local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1
stat.Size = UDim2.new(1, -24, 0, 16)
stat.Position = UDim2.new(0, 14, 0, 88)
stat.Font = Enum.Font.Code
stat.TextSize = 10
stat.TextColor3 = Color3.fromRGB(200, 160, 100)
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.Text = 'scanning...'

-- Buttons row
local function btn(label, color, x, w, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 28)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.fromRGB(245, 245, 250)
    b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end
local startBtn  = btn('▶ Start',  Color3.fromRGB(60, 150, 100),  12,  90, 110)
local stopBtn   = btn('■ Stop',   Color3.fromRGB(160, 80, 80),  110,  90, 110)
local rescanBtn = btn('⟳ Rescan', Color3.fromRGB(140, 120, 60), 208,  90, 110)
local saveBtn   = btn('💾 Save',  Color3.fromRGB(80, 120, 180), 306, 100, 110)

-- Log area
local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 360)
scroll.Position = UDim2.new(0, 10, 0, 146)
scroll.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(200, 120, 60)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 1)
layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll)
pad.PaddingTop = UDim.new(0, 4)
pad.PaddingLeft = UDim.new(0, 6)

local function logRow(text, color)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -12, 0, 14)
    lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 9
    lbl.TextColor3 = color or Color3.fromRGB(180, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 16)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end

-- ═════════════ RUN STATIC SCAN ════════════════════════════════════
local function runStaticScan()
    logRow('═══ PHASE 1: Deep Remote Scan (all services) ═══', Color3.fromRGB(200, 160, 100))
    STATIC.all_remotes = deepRemoteScan()
    logRow(('  Found %d remotes total'):format(#STATIC.all_remotes), Color3.fromRGB(150, 230, 180))
    for _, r in ipairs(STATIC.all_remotes) do
        logRow(('  [%s] %s  ← %s.%s'):format(r.class, r.name, r.service, r.parent),
            Color3.fromRGB(170, 200, 240))
    end
    if #STATIC.all_remotes == 0 then
        logRow('  ⚠ ZERO remotes found! Game may create them dynamically.', Color3.fromRGB(255, 160, 100))
        logRow('  → Try: wait longer for game to load, then click ⟳ Rescan', Color3.fromRGB(255, 200, 130))
    end

    logRow('', Color3.fromRGB(100, 100, 100))
    logRow('═══ PHASE 2: Workspace Structure ═══', Color3.fromRGB(200, 160, 100))
    STATIC.workspace_tree, STATIC.ws_interesting = scanWorkspace()
    logRow(('  Top-level children: %d'):format(#STATIC.workspace_tree), Color3.fromRGB(150, 230, 180))
    for _, e in ipairs(STATIC.workspace_tree) do
        local tag = ''
        if e.is_interesting then tag = tag .. ' ★' end
        if e.has_humanoid then tag = tag .. ' 👤' end
        logRow(('  %s [%s] (%d kids)%s'):format(e.name, e.class, e.children_count, tag),
            e.is_interesting and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(160, 180, 200))
    end
    if STATIC.ws_interesting and #STATIC.ws_interesting > 0 then
        logRow(('  ★ Interesting folders: %s'):format(table.concat(STATIC.ws_interesting, ', ')),
            Color3.fromRGB(255, 200, 100))
    end

    logRow('', Color3.fromRGB(100, 100, 100))
    logRow('═══ PHASE 3: PlayerGui Scan ═══', Color3.fromRGB(200, 160, 100))
    STATIC.playergui_tree = scanPlayerGui()
    logRow(('  ScreenGuis: %d'):format(#STATIC.playergui_tree), Color3.fromRGB(150, 230, 180))
    for _, sg in ipairs(STATIC.playergui_tree) do
        logRow(('  %s %s (%d children)'):format(sg.enabled and '✓' or '✗', sg.name, #sg.children),
            Color3.fromRGB(160, 180, 200))
    end

    logRow('', Color3.fromRGB(100, 100, 100))
    logRow('═══ PHASE 4: RS Modules ═══', Color3.fromRGB(200, 160, 100))
    STATIC.rs_modules = scanModules()
    logRow(('  ModuleScripts: %d'):format(#STATIC.rs_modules), Color3.fromRGB(150, 230, 180))
    for _, m in ipairs(STATIC.rs_modules) do
        logRow(('  📦 %s  ← %s'):format(m.name, m.parent), Color3.fromRGB(160, 180, 200))
    end

    logRow('', Color3.fromRGB(100, 100, 100))
    logRow('═══ PHASE 5: Character Info ═══', Color3.fromRGB(200, 160, 100))
    STATIC.character_info = scanCharacter()
    if STATIC.character_info.found then
        logRow(('  Character: %s'):format(STATIC.character_info.name), Color3.fromRGB(150, 230, 180))
        for _, c in ipairs(STATIC.character_info.children or {}) do
            logRow(('  %s [%s]'):format(c.name, c.class), Color3.fromRGB(160, 180, 200))
        end
    else
        logRow('  No character found (not spawned yet?)', Color3.fromRGB(255, 160, 100))
    end

    logRow('', Color3.fromRGB(100, 100, 100))
    logRow('═══ STATIC SCAN DONE ═══', Color3.fromRGB(100, 255, 130))

    stat.Text = ('remotes=%d  ws=%d  gui=%d  mods=%d | label: %s'):format(
        #STATIC.all_remotes, #STATIC.workspace_tree,
        #STATIC.playergui_tree, #STATIC.rs_modules, curLabel)
end

-- ═════════════ INSTALL HOOKS ═══════════════════════════════════════
logRow('Installing dual hooks...', Color3.fromRGB(200, 200, 150))
installHooks()
logRow(('  hookfunction: fire=%s invoke=%s unreliable=%s'):format(
    hookStatus.hookfn_fire or '?',
    hookStatus.hookfn_invoke or '?',
    hookStatus.hookfn_unreliable or '?'),
    Color3.fromRGB(150, 230, 180))
logRow(('  __namecall: %s'):format(hookStatus.namecall),
    hookStatus.namecall == 'installed' and Color3.fromRGB(150, 230, 180) or Color3.fromRGB(255, 160, 100))
logRow('', Color3.fromRGB(100, 100, 100))

-- Run initial static scan
runStaticScan()

-- ═════════════ LIVE FORWARDER ════════════════════════════════════
local liveIdx = 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.15)
        while liveIdx < #liveQueue do
            liveIdx = liveIdx + 1
            local e = liveQueue[liveIdx]
            logRow(('[%5.1fs][%s][%s] %s.%s(%s)'):format(
                e.t, e.label, e.source, e.name, e.method, (e.args or ''):sub(1, 70)),
                Color3.fromRGB(100, 220, 255))
        end
    end
end)

-- ═════════════ BUTTON HANDLERS ═══════════════════════════════════
setBtn.MouseButton1Click:Connect(function()
    local txt = box.Text
    if txt == '' then txt = 'lbl'..tostring(#labels+1) end
    curLabel = txt
    labels[#labels+1] = { t = now(), label = txt }
    stat.Text = stat.Text:gsub('label: .+', 'label: '..curLabel)
    logRow(('───── label: %s ─────'):format(curLabel), Color3.fromRGB(230, 200, 100))
end)

startBtn.MouseButton1Click:Connect(function()
    ACTIVE = true
    START = tick()
    summary = {}
    timeline = {}
    labels = {}
    liveQueue = {}
    liveIdx = 0
    curLabel = box.Text ~= '' and box.Text or '(none)'
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA('TextLabel') then c:Destroy() end
    end
    logRow('▶ CAPTURE STARTED. Set label → do action → repeat.', Color3.fromRGB(130, 255, 150))
    logRow(('  Hooks: hookfn=%s namecall=%s'):format(
        hookStatus.hookfn or '?', hookStatus.namecall or '?'),
        Color3.fromRGB(150, 200, 180))
end)

stopBtn.MouseButton1Click:Connect(function()
    if not ACTIVE then return end
    ACTIVE = false
    local n = 0; for _ in pairs(summary) do n = n + 1 end
    logRow(('■ STOPPED. remotes=%d events=%d'):format(n, #timeline), Color3.fromRGB(230, 180, 100))
    if #timeline == 0 then
        logRow('  ⚠ ZERO events captured! Possible reasons:', Color3.fromRGB(255, 160, 100))
        logRow('  1. Game uses custom networking (not standard RemoteEvent)', Color3.fromRGB(255, 200, 130))
        logRow('  2. Game loads remotes dynamically → try ⟳ Rescan', Color3.fromRGB(255, 200, 130))
        logRow('  3. Actions are client-side only (no server call)', Color3.fromRGB(255, 200, 130))
        logRow('  → Still SAVE — static scan data is valuable!', Color3.fromRGB(200, 255, 200))
    end
end)

rescanBtn.MouseButton1Click:Connect(function()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA('TextLabel') then c:Destroy() end
    end
    logRow('⟳ Rescanning (game may have loaded more objects)...', Color3.fromRGB(200, 200, 150))
    -- Re-scan and re-hook
    installHooks()
    runStaticScan()
end)

saveBtn.MouseButton1Click:Connect(function()
    local saved, path = saveReport()
    logRow(saved and ('💾 Saved: workspace/'..path) or '💾 Save FAILED (no writefile)',
        Color3.fromRGB(150, 230, 180))
    logRow('JSON also in clipboard. SEND THIS FILE!', Color3.fromRGB(180, 220, 255))
end)
