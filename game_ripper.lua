--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB · Game Ripper  (universal — works on any game)
    Goal: stop capturing remote-by-remote. This DECOMPILES the game's
    client + shared code and dumps the full tree, so we can READ how
    everything works (combat, hitreg, remotes) and design features fast.

    WHAT IT DOES:
      1. Decompiles every LocalScript / ModuleScript / Script we can reach
         (ReplicatedStorage, ReplicatedFirst, StarterPlayer/Gui, Lighting,
          PlayerScripts/PlayerGui, + nil-parented scripts) -> saves source.
      2. Dumps the full instance tree of those services -> tree.json
      3. Lists every remote (path + class) -> remotes.txt
    Output folder:  HSHub_GameRip_<placeid>/  (in your executor's workspace)
    Run it, watch the progress bar, then SEND THE FOLDER (or zip it).
    If your executor has no decompiler it still dumps the tree + remotes.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_Ripper then pcall(function() shared.__HSHub_Ripper:Destroy() end) end

local Players = game:GetService('Players')
local HttpSvc = game:GetService('HttpService')
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild('PlayerGui')

local DEC = decompile or (getgenv and getgenv().decompile)        -- executor decompiler (if any)
local OUT = ('HSHub_GameRip_%d'):format(game.PlaceId)
pcall(function() if makefolder and not (isfolder and isfolder(OUT)) then makefolder(OUT) end end)

-- ── gather every script we can reach ──
local function gather()
    local seen, list = {}, {}
    local roots = {}
    for _, n in ipairs({ 'ReplicatedStorage', 'ReplicatedFirst', 'StarterPlayer', 'StarterGui',
                         'Lighting', 'StarterPack', 'Chat', 'MaterialService' }) do
        local ok, sv = pcall(function() return game:GetService(n) end)
        if ok and sv then roots[#roots + 1] = sv end
    end
    roots[#roots + 1] = LP
    for _, r in ipairs(roots) do
        pcall(function()
            for _, d in ipairs(r:GetDescendants()) do
                if (d:IsA('LocalScript') or d:IsA('ModuleScript') or d:IsA('Script')) and not seen[d] then
                    seen[d] = true; list[#list + 1] = d
                end
            end
        end)
    end
    -- nil-parented scripts (loaded modules detached from the tree)
    pcall(function()
        if getnilinstances then
            for _, d in ipairs(getnilinstances()) do
                if (d:IsA('LocalScript') or d:IsA('ModuleScript') or d:IsA('Script')) and not seen[d] then
                    seen[d] = true; list[#list + 1] = d
                end
            end
        end
    end)
    return list
end

local function safePath(inst)
    local ok, fn = pcall(function() return inst:GetFullName() end)
    local p = ok and fn or inst.Name
    return (p:gsub('[^%w%._%- ]', '_'))
end

-- ── full tree dump (class + attributes, depth-limited) ──
local function treeDump(inst, depth)
    depth = depth or 0
    local node = { name = inst.Name, class = inst.ClassName }
    pcall(function()
        local a = inst:GetAttributes()
        if next(a) then node.attrs = {}; for k, v in pairs(a) do node.attrs[k] = tostring(v):sub(1, 60) end end
    end)
    if depth < 6 then
        local kids
        pcall(function() kids = inst:GetChildren() end)
        if kids and #kids > 0 then
            node.children = {}
            for _, c in ipairs(kids) do
                if #node.children < 200 then node.children[#node.children + 1] = treeDump(c, depth + 1) end
            end
        end
    end
    return node
end

-- ── remotes list ──
local function remotesDump()
    local out, seen = {}, {}
    for _, n in ipairs({ 'ReplicatedStorage', 'ReplicatedFirst', 'Workspace', 'Lighting' }) do
        local ok, sv = pcall(function() return game:GetService(n) end)
        if ok and sv then pcall(function()
            for _, d in ipairs(sv:GetDescendants()) do
                local c = d.ClassName
                if (c == 'RemoteEvent' or c == 'RemoteFunction' or c == 'UnreliableRemoteEvent'
                    or c == 'BindableEvent' or c == 'BindableFunction') and not seen[d] then
                    seen[d] = true
                    out[#out + 1] = ('[%s] %s'):format(c, (pcall(function() return d:GetFullName() end) and d:GetFullName() or d.Name))
                end
            end
        end) end
    end
    return out
end

-- ── UI ──
local gui = Instance.new('ScreenGui'); gui.Name = 'HSHub_Ripper'; gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_Ripper = gui
local f = Instance.new('Frame', gui); f.Size = UDim2.new(0, 330, 0, 120); f.Position = UDim2.new(0, 24, 0.35, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26); f.BorderSizePixel = 0; f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local strk = Instance.new('UIStroke', f); strk.Color = Color3.fromRGB(120, 180, 90); strk.Thickness = 1.5
local hdr = Instance.new('TextLabel', f); hdr.Size = UDim2.new(1, 0, 0, 28); hdr.BackgroundColor3 = Color3.fromRGB(70, 130, 70)
hdr.BorderSizePixel = 0; hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 13; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Game Ripper'; Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)
local stat = Instance.new('TextLabel', f); stat.Position = UDim2.new(0, 12, 0, 40); stat.Size = UDim2.new(1, -24, 0, 60)
stat.BackgroundTransparency = 1; stat.Font = Enum.Font.Code; stat.TextSize = 11; stat.TextColor3 = Color3.fromRGB(180, 230, 180)
stat.TextXAlignment = Enum.TextXAlignment.Left; stat.TextYAlignment = Enum.TextYAlignment.Top
stat.TextWrapped = true; stat.Text = 'starting...'

task.spawn(function()
    -- 1) tree + remotes (always works)
    pcall(function()
        local tree = {}
        for _, n in ipairs({ 'ReplicatedStorage', 'Workspace', 'ReplicatedFirst', 'Lighting' }) do
            local ok, sv = pcall(function() return game:GetService(n) end)
            if ok and sv then tree[n] = treeDump(sv) end
        end
        if writefile then pcall(function() writefile(OUT .. '/tree.json', HttpSvc:JSONEncode(tree)) end) end
    end)
    pcall(function()
        if writefile then writefile(OUT .. '/remotes.txt', table.concat(remotesDump(), '\n')) end
    end)

    -- 2) decompile every script
    local scripts = gather()
    stat.Text = ('found %d scripts | decompiler: %s'):format(#scripts, DEC and 'YES' or 'NONE')
    task.wait(0.5)
    if not DEC then
        stat.Text = ('no decompiler in this executor.\nSaved tree.json + remotes.txt to %s\nSEND THAT FOLDER.'):format(OUT)
        return
    end
    local ok_n, fail_n, manifest = 0, 0, {}
    for i, s in ipairs(scripts) do
        local src
        local good = pcall(function() src = DEC(s) end)
        if good and type(src) == 'string' and #src > 0 then
            local fname = ('%04d_%s.lua'):format(i, s.Name:gsub('[^%w%._%- ]', '_'):sub(1, 40))
            pcall(function() if writefile then writefile(OUT .. '/' .. fname, '-- ' .. safePath(s) .. '\n\n' .. src) end end)
            manifest[#manifest + 1] = fname .. '  <-  ' .. safePath(s)
            ok_n = ok_n + 1
        else
            fail_n = fail_n + 1
        end
        if i % 5 == 0 then
            stat.Text = ('decompiling %d/%d  (ok=%d fail=%d)\n-> %s'):format(i, #scripts, ok_n, fail_n, OUT)
            task.wait()
        end
    end
    pcall(function() if writefile then writefile(OUT .. '/_manifest.txt', table.concat(manifest, '\n')) end end)
    stat.Text = ('DONE. decompiled %d scripts (fail %d)\nfolder: %s\nSEND THE FOLDER (zip it).'):format(ok_n, fail_n, OUT)
end)
