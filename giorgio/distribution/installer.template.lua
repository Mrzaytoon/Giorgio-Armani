-- Giorgio first-install screen. The release builder fills both pins later.
-- No external URL is configured in this development template.
local MANIFEST_URL = "" -- SET_AT_RELEASE
local MANIFEST_SHA256 = "" -- SET_AT_RELEASE

-- CORE BEGIN: tested without a Roblox client using injected capabilities.
local Installer = {}
local CHUNK_LIMIT = 20 * 1024 * 1024
local HEADER_LIMIT = 1024 * 1024
local MAGIC = "GIORGIO1\n"

local function integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function validHash(value)
    return type(value) == "string" and #value == 64 and not value:find("[^0-9a-f]")
end

function Installer.validPath(value)
    if value == "Giorgio.lua" then return true end
    if type(value) ~= "string" or #value > 240 or value:sub(1, 15) ~= "Giorgio/assets/" then return false end
    if value:find("//", 1, true) or value:sub(-1) == "/" then return false end
    for part in value:gmatch("[^/]+") do
        if part == "." or part == ".." or part:find("[^%w_. %-]") or part:find("[. ]$") then return false end
        local stem = (part:match("^[^.]+") or ""):upper()
        if stem == "CON" or stem == "PRN" or stem == "AUX" or stem == "NUL"
            or stem:match("^COM[1-9]$") or stem:match("^LPT[1-9]$") then return false end
    end
    return true
end

function Installer.validateManifest(manifest)
    assert(type(manifest) == "table" and manifest.schema == 1 and manifest.entrypoint == "Giorgio.lua", "Unsupported Giorgio release manifest")
    assert(type(manifest.files) == "table" and #manifest.files > 0 and #manifest.files <= 100000, "Invalid release file list")
    assert(type(manifest.chunks) == "table" and #manifest.chunks > 0 and #manifest.chunks <= 998, "Invalid release part list")
    assert(integer(manifest.chunk_limit) and manifest.chunk_limit <= CHUNK_LIMIT, "Invalid release part limit")
    local files, folded, total = {}, {}, 0
    for _, file in ipairs(manifest.files) do
        assert(type(file) == "table" and Installer.validPath(file.path), "Unsafe Giorgio install path")
        assert(not folded[file.path:lower()], "Duplicate or case-colliding install path")
        assert(integer(file.bytes) and file.bytes <= CHUNK_LIMIT and validHash(file.sha256), "Invalid release file metadata")
        folded[file.path:lower()] = true
        files[file.path] = file
        total += file.bytes
    end
    assert(files["Giorgio.lua"] and total == manifest.total_bytes and total > 0 and total <= 8 * 1024 * 1024 * 1024, "Invalid release payload total")
    local assigned, chunkNames = {}, {}
    for _, chunk in ipairs(manifest.chunks) do
        assert(type(chunk) == "table" and type(chunk.file) == "string" and chunk.file:match("^chunk%-%d%d%d%d%.gpk$"), "Unsafe release part name")
        assert(not chunkNames[chunk.file], "Duplicate release part name")
        chunkNames[chunk.file] = true
        assert(integer(chunk.bytes) and chunk.bytes > #MAGIC + 9 and chunk.bytes <= manifest.chunk_limit and validHash(chunk.sha256), "Invalid release part metadata")
        assert(type(chunk.files) == "table" and #chunk.files > 0, "Empty release part")
        for _, path in ipairs(chunk.files) do
            assert(type(path) == "string" and files[path] and not assigned[path], "Unknown or duplicated release part file")
            assigned[path] = true
        end
    end
    for path in pairs(files) do assert(assigned[path], "File omitted from release parts") end
    return files
end

function Installer.decodeChunk(env, chunk, blob, files)
    assert(type(blob) == "string" and #blob == chunk.bytes and env.hash(blob) == chunk.sha256, "Downloaded part failed SHA-256 verification; run the installer again to retry")
    assert(blob:sub(1, #MAGIC) == MAGIC, "Invalid Giorgio part signature")
    local lengthText = blob:sub(#MAGIC + 1, #MAGIC + 8)
    assert(#lengthText == 8 and not lengthText:find("[^0-9a-f]") and blob:sub(#MAGIC + 9, #MAGIC + 9) == "\n", "Invalid Giorgio part header")
    local headerLength = tonumber(lengthText, 16)
    assert(headerLength and headerLength > 0 and headerLength <= HEADER_LIMIT, "Giorgio part header exceeds its limit")
    local payloadStart = #MAGIC + 10 + headerLength
    assert(payloadStart <= #blob + 1, "Truncated Giorgio part header")
    local header = env.decode(blob:sub(#MAGIC + 10, payloadStart - 1))
    assert(type(header) == "table" and header.schema == 1 and type(header.files) == "table" and #header.files == #chunk.files, "Invalid Giorgio part file table")
    local rows, offset = {}, 0
    -- Validate the complete part before writing even the first file.
    for index, row in ipairs(header.files) do
        assert(type(row) == "table" and row.path == chunk.files[index], "Release part file order differs from manifest")
        local file = files[row.path]
        assert(file and row.bytes == file.bytes and row.sha256 == file.sha256 and row.offset == offset, "Release part metadata differs from manifest")
        local data = blob:sub(payloadStart + offset, payloadStart + offset + file.bytes - 1)
        assert(#data == file.bytes and env.hash(data) == file.sha256, "Release asset failed SHA-256 verification")
        rows[index] = {path = file.path, data = data}
        offset += file.bytes
    end
    assert(payloadStart + offset - 1 == #blob, "Unexpected trailing data in Giorgio part")
    return rows
end

function Installer.install(env, url, manifestHash)
    assert(type(url) == "string" and url:match("^https://[^%s]+/manifest%.json$") and validHash(manifestHash), "Giorgio release is not configured; connect the release URL and SHA-256 first")
    env.progress("manifest", 0, 0, 0, 0)
    local manifestBody = env.fetch(url)
    assert(type(manifestBody) == "string" and #manifestBody <= 32 * 1024 * 1024 and env.hash(manifestBody) == manifestHash, "Giorgio manifest failed SHA-256 verification")
    local manifest = env.decode(manifestBody)
    local files = Installer.validateManifest(manifest)
    local valid, complete, transferred, installed = {}, 0, 0, 0
    env.progress("checking", complete, manifest.total_bytes, transferred, installed)
    for index, file in ipairs(manifest.files) do
        if env.isfile(file.path) then
            local ok, data = pcall(env.readfile, file.path)
            if ok and type(data) == "string" and #data == file.bytes and env.hash(data) == file.sha256 then
                valid[file.path] = true
                complete += file.bytes
                installed += 1
            end
        end
        if index % 32 == 0 then
            env.progress("checking", complete, manifest.total_bytes, transferred, installed)
            env.yield()
        end
    end
    local base = url:match("^(.*)/manifest%.json$")
    local madeFolders = {}
    local function createParents(path)
        local parent = ""
        for part in path:gmatch("([^/]+)/") do
            parent = parent == "" and part or (parent .. "/" .. part)
            if not madeFolders[parent] then
                env.makefolder(parent)
                madeFolders[parent] = true
            end
        end
    end
    for index, chunk in ipairs(manifest.chunks) do
        local needed = false
        for _, path in ipairs(chunk.files) do if not valid[path] then needed = true break end end
        if needed then
            env.progress("downloading", complete, manifest.total_bytes, transferred, installed, index, #manifest.chunks)
            local blob = env.fetch(base .. "/" .. chunk.file)
            local rows = Installer.decodeChunk(env, chunk, blob, files)
            transferred += #blob
            for rowIndex, row in ipairs(rows) do
                if not valid[row.path] then
                    createParents(row.path)
                    env.writefile(row.path, row.data)
                    local written = env.readfile(row.path)
                    assert(type(written) == "string" and #written == files[row.path].bytes and env.hash(written) == files[row.path].sha256, "Written asset failed verification; run the installer again")
                    valid[row.path] = true
                    complete += files[row.path].bytes
                    installed += 1
                end
                if rowIndex % 16 == 0 then
                    env.progress("installing", complete, manifest.total_bytes, transferred, installed, index, #manifest.chunks)
                    env.yield()
                end
            end
            env.progress("installing", complete, manifest.total_bytes, transferred, installed, index, #manifest.chunks)
            env.yield()
        end
    end
    assert(complete == manifest.total_bytes and installed == #manifest.files, "Giorgio installation is incomplete")
    local runtime = env.readfile("Giorgio.lua")
    assert(type(runtime) == "string" and #runtime == files["Giorgio.lua"].bytes and env.hash(runtime) == files["Giorgio.lua"].sha256, "Installed runtime failed final verification")
    env.progress("ready", complete, manifest.total_bytes, transferred, installed)
    env.execute(runtime)
    return {bytes = complete, transferred = transferred, files = installed, version = manifest.version}
end

function Installer.formatBytes(value)
    local digits = string.format("%.0f", math.max(0, value))
    return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Presentation state never starts, pauses or cancels the download worker.
function Installer.newProgressView(render)
    local view = {alive = true, state = {phase = "manifest", complete = 0, total = 0,
        transferred = 0, fileCount = 0, ratio = 0, remaining = nil, minimized = false}}
    function view:publish()
        if not self.alive then return false end
        render(self.state)
        return true
    end
    function view:update(phase, complete, total, transferred, fileCount, chunkIndex, chunkCount)
        if not self.alive then return false end
        assert(integer(complete) and integer(total) and complete <= total, "Invalid installer progress")
        assert(phase ~= "ready" or (total > 0 and complete == total), "Installer cannot finish before verification")
        local state = self.state
        state.phase, state.complete, state.total = phase, complete, total
        state.transferred, state.fileCount = transferred, fileCount
        state.chunkIndex, state.chunkCount = chunkIndex, chunkCount
        state.ratio = total > 0 and complete / total or 0
        state.remaining = total > 0 and (total - complete) or nil
        return self:publish()
    end
    function view:minimize(value)
        if not self.alive or self.state.phase == "failed" then return false end
        self.state.minimized = value == true
        return self:publish()
    end
    function view:fail(message)
        if not self.alive then return false end
        self.state.phase, self.state.error, self.state.minimized = "failed", tostring(message), false
        return self:publish()
    end
    function view:destroy()
        self.alive = false
    end
    return view
end
-- CORE END

assert(MANIFEST_URL ~= "" and MANIFEST_SHA256 ~= "", "Giorgio installer is prepared but no release is connected yet. Configure its manifest URL and SHA-256 after the GitHub release is ready.")
local environment = getgenv()
assert(not environment.GIORGIO_INSTALL_RUNNING, "Giorgio installation is already running")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local knownDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
local hashFunction
local candidates = {}
for _, provider in ipairs({environment.crypt or {}, (environment.syn or {}).crypt or {}}) do
    if type(provider.hash) == "function" then
        table.insert(candidates, function(data) return provider.hash(data, "sha256") end)
        table.insert(candidates, function(data) return provider.hash(data, "sha-256") end)
        table.insert(candidates, function(data) return provider.hash(data) end)
    end
end
local function normalizedHash(value)
    if type(value) ~= "string" then return "" end
    if #value == 32 then return (value:gsub(".", function(character) return string.format("%02x", string.byte(character)) end)) end
    return value:lower()
end
for _, candidate in ipairs(candidates) do
    local ok, result = pcall(candidate, "abc")
    if ok and normalizedHash(result) == knownDigest then
        hashFunction = function(data) return normalizedHash(candidate(data)) end
        break
    end
end
assert(hashFunction, "Giorgio installation needs a working crypt.hash SHA-256 capability; this executor did not pass its hash self-test")
for _, name in ipairs({"isfile", "readfile", "writefile", "makefolder", "isfolder", "loadstring"}) do
    assert(type(environment[name]) == "function", "Giorgio installation needs executor capability: " .. name)
end
if type(environment.GIORGIO_INSTALL_UI_CLEANUP) == "function" then
    environment.GIORGIO_INSTALL_UI_CLEANUP()
end

local gui = Instance.new("ScreenGui")
gui.Name = "GiorgioFirstInstall"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local parented = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not parented then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
local background = Instance.new("Frame")
background.BackgroundColor3 = Color3.fromRGB(10, 10, 11)
background.BorderSizePixel = 0
background.Size = UDim2.fromScale(1, 1)
background.Parent = gui
local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.AnchorPoint = Vector2.new(0.5, 0.5)
content.Position = UDim2.fromScale(0.5, 0.49)
content.Size = UDim2.new(0.82, 0, 0, 300)
content.Parent = background
local constraint = Instance.new("UISizeConstraint")
constraint.MaxSize = Vector2.new(680, 320)
constraint.Parent = content
local ivory = Color3.fromRGB(234, 231, 222)
local muted = Color3.fromRGB(155, 153, 147)
local function label(name, text, size, y, font, color)
    local object = Instance.new("TextLabel")
    object.Name = name
    object.BackgroundTransparency = 1
    object.Size = UDim2.new(1, 0, 0, size + 14)
    object.Position = UDim2.fromOffset(0, y)
    object.Font = font
    object.TextSize = size
    object.TextColor3 = color
    object.Text = text
    object.Parent = content
    return object
end
label("Edition", "P R I V A T E   E D I T I O N", 11, 0, Enum.Font.GothamMedium, muted)
local title = label("Title", "GIORGIO ARMANI", 43, 33, Enum.Font.Garamond, ivory)
local subtitle = label("Subtitle", "Preparing your collection", 16, 101, Enum.Font.Garamond, ivory)
local status = label("Status", "Connecting to the release", 12, 197, Enum.Font.Gotham, muted)
status.TextWrapped = true
status.Size = UDim2.new(1, 0, 0, 52)
local detail = label("Bytes", "", 11, 251, Enum.Font.Gotham, muted)
detail.Position = UDim2.fromOffset(0, 244)
detail.Size = UDim2.new(1, 0, 0, 42)
detail.TextWrapped = true
local track = Instance.new("Frame")
track.BackgroundColor3 = Color3.fromRGB(40, 39, 37)
track.BorderSizePixel = 0
track.Position = UDim2.new(0, 0, 0, 179)
track.Size = UDim2.new(1, 0, 0, 2)
track.Parent = content
local bar = Instance.new("Frame")
bar.BackgroundColor3 = ivory
bar.BorderSizePixel = 0
bar.Size = UDim2.fromScale(0, 1)
bar.Parent = track
local minimize = Instance.new("TextButton")
minimize.Name = "MinimizeInstaller"
minimize.AnchorPoint = Vector2.new(1, 0)
minimize.Position = UDim2.new(1, -24, 0, 24)
minimize.Size = UDim2.fromOffset(110, 32)
minimize.BackgroundTransparency = 1
minimize.Font = Enum.Font.GothamMedium
minimize.TextSize = 11
minimize.TextColor3 = ivory
minimize.Text = "MINIMIZE"
minimize.Parent = background
local compact = Instance.new("Frame")
compact.Name = "CompactProgress"
compact.AnchorPoint = Vector2.new(1, 1)
compact.Position = UDim2.new(1, -16, 1, -16)
compact.Size = UDim2.new(1, -32, 0, 100)
compact.BackgroundColor3 = Color3.fromRGB(10, 10, 11)
compact.BorderSizePixel = 0
compact.Visible = false
compact.Parent = gui
local compactSize = Instance.new("UISizeConstraint")
compactSize.MaxSize = Vector2.new(400, 100)
compactSize.Parent = compact
local compactStroke = Instance.new("UIStroke")
compactStroke.Color = Color3.fromRGB(66, 64, 59)
compactStroke.Thickness = 1
compactStroke.Parent = compact
local expand = Instance.new("TextButton")
expand.Name = "ExpandInstaller"
expand.Position = UDim2.fromOffset(16, 10)
expand.Size = UDim2.new(1, -32, 0, 28)
expand.BackgroundTransparency = 1
expand.Font = Enum.Font.Garamond
expand.TextSize = 20
expand.TextXAlignment = Enum.TextXAlignment.Left
expand.TextColor3 = ivory
expand.Text = "GIORGIO ARMANI  ·  OPEN"
expand.Parent = compact
local remaining = Instance.new("TextLabel")
remaining.Name = "RemainingBytes"
remaining.Position = UDim2.fromOffset(16, 42)
remaining.Size = UDim2.new(1, -32, 0, 32)
remaining.BackgroundTransparency = 1
remaining.Font = Enum.Font.Gotham
remaining.TextSize = 11
remaining.TextColor3 = ivory
remaining.TextWrapped = true
remaining.TextXAlignment = Enum.TextXAlignment.Left
remaining.Text = "Calculating remaining size"
remaining.Parent = compact
local compactTrack = Instance.new("Frame")
compactTrack.Position = UDim2.new(0, 16, 1, -14)
compactTrack.Size = UDim2.new(1, -32, 0, 2)
compactTrack.BorderSizePixel = 0
compactTrack.BackgroundColor3 = Color3.fromRGB(40, 39, 37)
compactTrack.Parent = compact
local compactBar = Instance.new("Frame")
compactBar.Size = UDim2.fromScale(0, 1)
compactBar.BorderSizePixel = 0
compactBar.BackgroundColor3 = ivory
compactBar.Parent = compactTrack
local headingLayout = content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    title.TextSize = math.clamp(math.floor(content.AbsoluteSize.X / 14), 18, 43)
end)
title.TextSize = math.clamp(math.floor(content.AbsoluteSize.X / 14), 18, 43)
local alive, progressTween, compactTween, executing = true, nil, nil, false
local closeButton, closeConnection, minimizeConnection, expandConnection, progressView
local spin = 0
local busy, baseStatus = false, ""
local animation = RunService.RenderStepped:Connect(function(dt)
    if not alive or not busy then return end
    spin += dt
    status.Text = baseStatus .. string.rep(".", math.floor(spin * 2) % 4)
end)
local function cleanup()
    if not alive then return end
    alive = false
    animation:Disconnect()
    headingLayout:Disconnect()
    if closeConnection then closeConnection:Disconnect() end
    if minimizeConnection then minimizeConnection:Disconnect() end
    if expandConnection then expandConnection:Disconnect() end
    if progressView then progressView:destroy() end
    if progressTween then progressTween:Cancel() end
    if compactTween then compactTween:Cancel() end
    gui:Destroy()
    environment.GIORGIO_INSTALL_UI_CLEANUP = nil
end
environment.GIORGIO_INSTALL_UI_CLEANUP = cleanup
local function renderProgress(state)
    if not alive then return end
    local phase, ratio = state.phase, state.ratio
    background.Visible = not state.minimized
    compact.Visible = state.minimized
    minimize.Visible = phase ~= "failed"
    if progressTween then progressTween:Cancel() end
    if compactTween then compactTween:Cancel() end
    progressTween = TweenService:Create(bar, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(ratio, 1)})
    compactTween = TweenService:Create(compactBar, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(ratio, 1)})
    progressTween:Play()
    compactTween:Play()
    busy = phase == "downloading" or phase == "manifest" or phase == "checking"
    local descriptions = {manifest = "Connecting to the release", checking = "Checking your collection", installing = "Verifying and saving your collection", ready = "Your collection is ready"}
    baseStatus = phase == "downloading" and string.format("Downloading part %d of %d", state.chunkIndex, state.chunkCount) or descriptions[phase] or phase
    status.Text = baseStatus
    subtitle.Text = phase == "ready" and "Welcome to your private edition" or "Preparing your collection"
    local remainingText = state.remaining and (Installer.formatBytes(state.remaining) .. " bytes left to verify") or "Calculating remaining size"
    remaining.Text = state.total > 0 and (string.format("%d%%  ·  ", math.floor(ratio * 100)) .. remainingText) or remainingText
    detail.Text = remainingText
    if state.total > 0 then
        detail.Text ..= string.format("\n%d files verified  ·  %.1f MiB received", state.fileCount, state.transferred / 1048576)
    end
    if phase == "failed" then
        subtitle.Text = "Your saved progress is kept"
        status.Text = state.error
        detail.Text = "Run this installer again to resume verified downloads."
    end
end
progressView = Installer.newProgressView(renderProgress)
minimizeConnection = minimize.Activated:Connect(function() progressView:minimize(true) end)
expandConnection = expand.Activated:Connect(function() progressView:minimize(false) end)
progressView:publish()
local function update(...)
    progressView:update(...)
end
local function fetch(url)
    local requestFunction = environment.request or environment.http_request or (environment.syn or {}).request
    if type(requestFunction) == "function" then
        local response = requestFunction({Url = url, Method = "GET", Headers = {["Accept"] = "application/octet-stream"}})
        assert(type(response) == "table" and tonumber(response.StatusCode) == 200 and type(response.Body) == "string", "Release download failed; check the connection and run the installer again")
        return response.Body
    end
    return game:HttpGet(url)
end
environment.GIORGIO_INSTALL_RUNNING = true
local ok, result = pcall(Installer.install, {
    hash = hashFunction,
    decode = function(value) return HttpService:JSONDecode(value) end,
    fetch = fetch,
    isfile = environment.isfile,
    readfile = environment.readfile,
    writefile = environment.writefile,
    makefolder = function(path) if not environment.isfolder(path) then environment.makefolder(path) end end,
    progress = update,
    yield = function() task.wait() end,
    execute = function(source)
        assert(not executing, "Giorgio runtime already started")
        executing = true
        local chunk, compileError = environment.loadstring(source, "=Giorgio.lua")
        assert(chunk, "Installed Giorgio runtime could not compile: " .. tostring(compileError))
        task.wait(0.35)
        cleanup()
        chunk()
    end,
}, MANIFEST_URL, MANIFEST_SHA256)
environment.GIORGIO_INSTALL_RUNNING = nil
if not ok then
    busy = false
    if alive then
        progressView:fail(tostring(result):gsub("^.-:%d+: ", ""))
        animation:Disconnect()
        closeButton = Instance.new("TextButton")
        closeButton.Name = "CloseInstaller"
        closeButton.AnchorPoint = Vector2.new(0.5, 0)
        closeButton.Position = UDim2.new(0.5, 0, 0, 284)
        closeButton.Size = UDim2.fromOffset(116, 34)
        closeButton.BackgroundTransparency = 1
        closeButton.Font = Enum.Font.GothamMedium
        closeButton.TextSize = 12
        closeButton.TextColor3 = ivory
        closeButton.Text = "CLOSE"
        closeButton.Parent = content
        closeConnection = closeButton.Activated:Connect(cleanup)
    end
    error("Giorgio installation: " .. tostring(result), 0)
end
