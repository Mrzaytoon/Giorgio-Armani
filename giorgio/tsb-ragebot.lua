-- TSB_RAGEBOT_BEGIN
-- The Strongest Battlegrounds only (place 10449761463). integrate.py splices this
-- into the Giorgio build; the Lumen Rep Root build never sees it. Every number in
-- here was measured on game version 17455 against the user's own alt.
do
-- integrate.py splices this into the Rep Root addon chunk, so L, R (L.RepRoot),
-- C, K, Players and LP are already in scope as that chunk's locals. Only the two
-- services the addon does not itself name are pulled in here.
local RS = L.RunService
local UIS = L.UserInputService or game:GetService("UserInputService")

local TSB = { PLACE = 10449761463, running = false, state = "Idle", kills = 0, cfg = {} }
R.TSB = TSB
function TSB.supported() return game.PlaceId == TSB.PLACE end

-- ---------------------------------------------------------------- void immunity
-- Falling below Y -500 is not an engine or server kill in TSB. The character's own
-- CharacterHandler.Client runs, every Heartbeat (source line 6308):
--   if root.Y < -500 and gate and Health > 0 then Health = 0 end
-- `gate` is upvalue 40: false at spawn, set true by a task.delay(2). Nothing else
-- reads it. Closing it (plus a NaN FallenPartsDestroyHeight) held the main account
-- alive at Y -600, -2000 and -10000, and for 25 s at -2000 as seen from the alt.
local Void = { wanted = false, fn = nil, char = nil, born = setmetatable({}, { __mode = "k" }),
  method = "off", hookInstalled = false, hookArmed = false, fpdhOwned = false }
TSB.Void = Void
local KILL_LINE, GATE_INDEX = 6308, 40

function Void.locate(char)
  if not char or type(getconnections) ~= "function" or type(debug.getupvalue) ~= "function"
    or type(debug.setupvalue) ~= "function" or type(debug.info) ~= "function" then return nil end
  local ok, list = pcall(getconnections, RS.Heartbeat)
  if not ok or type(list) ~= "table" then return nil end
  for _, connection in ipairs(list) do
    local fn = connection.Function
    if type(fn) == "function" and (type(islclosure) ~= "function" or islclosure(fn)) then
      local okSource, source = pcall(debug.info, fn, "s")
      local okLine, line = pcall(debug.info, fn, "l")
      if okSource and okLine and line == KILL_LINE and string.find(tostring(source), "CharacterHandler.Client", 1, true) then
        local okChar, first = pcall(debug.getupvalue, fn, 1)
        local okHum, hum = pcall(debug.getupvalue, fn, 2)
        local okGate, gate = pcall(debug.getupvalue, fn, GATE_INDEX)
        if okChar and first == char and okHum and typeof(hum) == "Instance" and hum:IsA("Humanoid")
          and okGate and type(gate) == "boolean" then
          return fn
        end
      end
    end
  end
  return nil
end

-- Fallback when the script layout changes: refuse the kill-plane's Health write
-- while we are below the plane. Measured: blocked every write, no death. The hook
-- is never removed (restorefunction would also strip other scripts' hooks); it is
-- disarmed instead, which makes it a plain pass-through.
function Void.installHook()
  if Void.hookInstalled then Void.hookArmed = true; return true end
  if type(hookmetamethod) ~= "function" or type(checkcaller) ~= "function" then return false end
  local wrap = type(newcclosure) == "function" and newcclosure or function(f) return f end
  local original
  local ok = pcall(function()
    original = hookmetamethod(game, "__newindex", wrap(function(self, key, value)
      if Void.hookArmed and key == "Health" and type(value) == "number" and value <= 0 and not checkcaller() then
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = hum and hum.RootPart
        if self == hum and root and root.Position.Y < -490 then return end
      end
      return original(self, key, value)
    end))
  end)
  Void.hookInstalled = ok and original ~= nil
  Void.hookArmed = Void.hookInstalled
  return Void.hookInstalled
end

function Void.fpdhSafe()
  local floor = workspace.FallenPartsDestroyHeight
  return floor ~= floor
end

function Void.tick()
  if not Void.wanted then return end
  if not Void.fpdhSafe() then
    Void.fpdhOwned = pcall(function() workspace.FallenPartsDestroyHeight = 0 / 0 end) or Void.fpdhOwned
  end
  local char = LP.Character
  if not char then Void.method = "off"; return end
  if Void.char ~= char then Void.char, Void.fn, Void.method = char, nil, "pending" end
  local born = Void.born[char]
  -- The game opens the gate 2 s after spawn; closing it earlier gets overwritten.
  if born and os.clock() - born < 2.3 then return end
  if not Void.fn then Void.fn = Void.locate(char) end
  if Void.fn then
    local ok, gate = pcall(debug.getupvalue, Void.fn, GATE_INDEX)
    if ok and gate ~= false then pcall(debug.setupvalue, Void.fn, GATE_INDEX, false) end
    ok, gate = pcall(debug.getupvalue, Void.fn, GATE_INDEX)
    if ok and gate == false then Void.method = "gate"; Void.hookArmed = false; return end
  end
  if TSB.cfg.healthGuard ~= false and Void.installHook() then Void.method = "hook" else Void.method = "unprotected" end
end

-- True only when a verified mechanism will keep us alive below Y -500. The gate is
-- re-read live: a cached "closed" could be stale if the game reopened it since.
function Void.safe()
  if not Void.wanted or not Void.fpdhSafe() or Void.char ~= LP.Character then return false end
  if Void.method == "hook" then return Void.hookInstalled and Void.hookArmed end
  if Void.method ~= "gate" or not Void.fn then return false end
  local ok, gate = pcall(debug.getupvalue, Void.fn, GATE_INDEX)
  return ok and gate == false
end

-- The lowest Y we may write our own root to right now.
function Void.floor()
  return Void.safe() and -1e4 or -480
end

function Void.set(on)
  Void.wanted = on == true
  if Void.wanted then Void.tick(); return true end
  Void.hookArmed = false
  if Void.fn and Void.char and Void.char.Parent then pcall(debug.setupvalue, Void.fn, GATE_INDEX, true) end
  Void.fn, Void.char, Void.method = nil, nil, "off"
  if Void.fpdhOwned and not R.voidGuard then
    pcall(function() workspace.FallenPartsDestroyHeight = R.voidOriginal end)
  end
  Void.fpdhOwned = false
  return true
end

-- A character that existed before load has an unknown spawn time; tick() closes its
-- gate at once and re-closes it if the game's 2 s delay reopens it afterwards.
L.hold(LP.CharacterAdded:Connect(function(char) Void.born[char] = os.clock() end))

-- ---------------------------------------------------------------- game reads
local Game = {}
TSB.Game = Game
Game.BLOCKERS = { "Counter", "HunterCounter", "AtomicCounter" }
-- A grab in progress. Measured 2026-09-24: when a Hunter grab connects the
-- victim's model gains BeingGrabbed, RootAnchor, NoRotate, Freeze and a
-- ForceField together, and loses them together when it lets go. It is NOT a
-- counter: BeingGrabbed used to sit in BLOCKERS, which made the stand back off
-- from its own grab -- exactly the window it wants to act in.
Game.GRABS = { "BeingGrabbed", "RootAnchor" }

function Game.body(player)
  local live = workspace:FindFirstChild("Live")
  local model = (live and live:FindFirstChild(player.Name)) or player.Character
  local hum = model and model:FindFirstChildOfClass("Humanoid")
  local root = hum and hum.RootPart or (model and model:FindFirstChild("HumanoidRootPart"))
  return model, hum, root
end

local function finiteVector(v)
  return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z
    and math.abs(v.X) < 1e7 and math.abs(v.Y) < 1e7 and math.abs(v.Z) < 1e7
end
Game.finite = finiteVector

-- One read of everything the brain cares about for one player.
function Game.read(player)
  local model, hum, root = Game.body(player)
  local s = { player = player, model = model, hum = hum, root = root }
  if not model or not hum or not root or not root.Parent then s.gone = true; return s end
  s.health, s.maxHealth = hum.Health, math.max(hum.MaxHealth, 1)
  s.alive = s.health > 0 and not hum:GetAttribute("Dead")
  s.position = root.Position
  s.valid = finiteVector(s.position)
  s.forceField = model:FindFirstChildWhichIsA("ForceField") ~= nil
  s.immortal = model:FindFirstChild("AbsoluteImmortal") ~= nil
  s.ragdoll = model:FindFirstChild("Ragdoll") ~= nil or model:FindFirstChild("RagdollSim") ~= nil
  s.frozen = model:FindFirstChild("Freeze") ~= nil
  s.blocking = model:GetAttribute("Blocking") == true
  s.ulted = model:GetAttribute("Ulted") ~= nil and model:GetAttribute("Ulted") ~= false
  s.npc = model:GetAttribute("NPC") == true
  s.kit = model:GetAttribute("Character")
  s.lastHit = model:GetAttribute("LastHit")
  for _, name in ipairs(Game.BLOCKERS) do
    if model:FindFirstChild(name) then s.countering = true; break end
  end
  for _, name in ipairs(Game.GRABS) do
    if model:FindFirstChild(name) then s.grabbed = true; break end
  end
  s.seated = hum.Sit
  s.anchored = root.Anchored
  return s
end

-- Hotbar slots as the player sees them: tool name and whether it is cooling down.
function Game.hotbar()
  local slots = {}
  local gui = LP:FindFirstChildOfClass("PlayerGui")
  local bar = gui and gui:FindFirstChild("Hotbar")
  bar = bar and bar:FindFirstChild("Backpack")
  bar = bar and bar:FindFirstChild("Hotbar")
  for index = 1, 4 do
    local slot = bar and bar:FindFirstChild(tostring(index))
    local base = slot and slot:FindFirstChild("Base")
    local label = base and base:FindFirstChild("ToolName")
    local name = label and label:IsA("TextLabel") and label.Text or nil
    local cooldown = base and base:FindFirstChild("Cooldown")
    slots[index] = { index = index, name = (name and name ~= "") and name or nil, cooling = cooldown ~= nil,
      remaining = cooldown and cooldown:IsA("GuiObject") and math.clamp(-cooldown.Size.Y.Scale, 0, 1) or 0 }
  end
  return slots
end

function Game.tool(name)
  if not name then return nil end
  for _, holder in ipairs({ LP:FindFirstChildOfClass("Backpack"), LP.Character }) do
    if holder then
      for _, tool in ipairs(holder:GetChildren()) do
        if tool:IsA("Tool") and (tool:GetAttribute("Name") == name or tool.Name == name) then return tool end
      end
    end
  end
  return nil
end

function Game.ultimateReady()
  local value = LP:GetAttribute("Ultimate")
  return type(value) == "number" and value >= 100
end

function Game.killCount()
  local value = LP:GetAttribute("Kills")
  if type(value) == "number" then return value end
  local stats = LP:FindFirstChild("leaderstats")
  local stat = stats and (stats:FindFirstChild("Kills") or stats:FindFirstChild("Total Kills"))
  return stat and tonumber(stat.Value) or 0
end

-- ---------------------------------------------------------------- the wire
-- Everything the game's own input handler sends, with MousePos always filled in.
local Wire = { budget = 0, stamp = 0 }
TSB.Wire = Wire
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
Wire.KEYS = KEYS

function Wire.fire(payload)
  local now = os.clock()
  if now - Wire.stamp >= 1 then Wire.stamp, Wire.budget = now, 0 end
  if Wire.budget >= 45 then return false end -- hard ceiling; the game never needs more
  local model = Game.body(LP)
  local remote = model and model:FindFirstChild("Communicate")
  if not remote then return false end
  Wire.budget += 1
  return (pcall(remote.FireServer, remote, payload))
end

function Wire.aim(part)
  return part and CFrame.new(part.Position) or CFrame.new()
end

function Wire.press(key, aim, extra)
  local payload = { Goal = "KeyPress", Key = key, MousePos = aim }
  if extra then for k, v in pairs(extra) do payload[k] = v end end
  return Wire.fire(payload)
end

function Wire.release(key)
  return Wire.fire({ Goal = "KeyRelease", Key = key })
end

-- A hotbar move. On keyboard the game's number key only EQUIPS the tool (the
-- hotbar LocalScript calls Humanoid:EquipTool); a KeyPress alone never runs a
-- move. The gamepad path sends the tool itself, auto-activated, and that is what
-- this sends. Measured 2026-09-23: KeyPress One..Four played no move animation
-- and set no cooldown; this played Shove's animation and put slot 3 on cooldown.
-- CrushingPull is omitted for the same reason as in Wire.m1.
function Wire.skill(index)
  local slot = Game.hotbar()[index]
  local tool = slot and Game.tool(slot.name)
  if not tool then return false end
  pcall(function() tool:SetAttribute("Name", slot.name) end)
  return Wire.fire({ Goal = "Console Move", Tool = tool, IsAutoActivate = true })
end

-- A dash, as the game's own Q handler sends it (captured 2026-09-23): the
-- direction rides in `Dash` as the movement key -- W forward, A/D sideways, S back.
function Wire.dash(direction, aim)
  local ok = Wire.fire({ Goal = "KeyPress", Key = Enum.KeyCode.Q, Dash = direction or Enum.KeyCode.W, MousePos = aim })
  task.delay(0.05, function() if L.live() then Wire.fire({ Goal = "KeyRelease", Key = Enum.KeyCode.Q }) end end)
  return ok
end

function Wire.m1(aim)
  -- A normal M1 the way the game's own input path sends it. ToolName is filled
  -- from the equipped kit so the server runs that kit's swing, not a fist M1.
  -- CrushingPull is deliberately omitted: computing it means calling the game's
  -- shared.GetCrushingPullHit, and running game code from here is what kicked us
  -- in other titles. An empty pull just reads as a plain swing, which is fine for
  -- every kit except Esper's slot-1 special (still lands as a normal M1).
  local char = LP.Character
  local tool = char and char:FindFirstChildOfClass("Tool")
  local payload = { Goal = "LeftClick", MousePos = aim }
  if tool then payload.ToolName = tool:GetAttribute("Name") or tool.Name end
  Wire.fire(payload)
  task.delay(0.08, function() if L.live() then Wire.fire({ Goal = "LeftClickRelease" }) end end)
end

-- The awakening (every kit, key G) takes MoveDirection, never MousePos.
function Wire.ult()
  local _, hum = Game.body(LP)
  local move = (hum and hum.MoveDirection) or Vector3.zero
  return Wire.fire({ Goal = "KeyPress", Key = Enum.KeyCode.G, MoveDirection = move })
end

-- ---------------------------------------------------------------- the brain
-- Everything above is measured plumbing. This is the autonomy the manual Rep
-- Root hub does not have: acquire a target and either fight it with the kit
-- (Communicate M1/skill/ult -- works on any character, trips no anti-cheat) or
-- hand it to the existing void-aim fling queue.

TSB.cfg = {
  enabled = false,
  mode = "Combat",            -- "Combat" | "Void fling"
  voidImmunity = true,        -- keep our own kill-plane disarmed while running
  healthGuard = true,         -- __newindex Health fallback (Void.installHook)
  -- targeting
  priority = "Lowest HP",     -- "Lowest HP" | "Nearest" | "Lowest HP nearby"
  range = 150,                -- max engage distance in studs (0 = unlimited)
  respectFF = true,           -- skip spawn ForceField / VisibleFF
  skipImmortal = true,        -- skip AbsoluteImmortal
  skipCountering = true,      -- back off while a target's counter window is open
  whitelist = true,           -- never hit K.whitelist names (player-panel excludes)
  -- combat
  useUltimate = true,
  useSkills = true,
  useM1 = true,
  m1Interval = 0.34,          -- min gap between M1s; the game paces combos ~0.3s
  skillGap = 0.20,            -- min gap between skill presses
  -- fling
  flingVoidAim = true,        -- drive R.voidAim (down / nearest edge)
  flingMode = "All players",  -- queue mode the fling driver arms
  -- pacing / stealth
  publicCaution = true,       -- extra care outside the private server
  maxKillsPerMin = 0,         -- 0 = unlimited; else throttle in public servers
}

TSB.state = "Idle"
TSB.kills = 0
TSB.current = nil
local lastM1, lastSkill, lastUlt = 0, 0, 0
local toggleKey = Enum.KeyCode.Semicolon
local killSamples, lastKnownKills = {}, nil

function TSB.isVIP()
  local v = workspace:GetAttribute("VIPServer")
  return v ~= nil and v ~= false
end

-- Is our own body free to act? Mirror ActionCheck's gate from what Game.read
-- already sees, rather than requiring the game's ActionCheck module (calling
-- game code from here is the thing that gets us kicked elsewhere).
function TSB.selfReady(me)
  if not me or me.gone or not me.alive then return false end
  if me.frozen or me.ragdoll or me.seated or me.anchored then return false end
  return true
end

local function whitelisted(name)
  return TSB.cfg.whitelist and K ~= nil
    and K.whitelist and K.whitelist[name:lower()] == true
end

-- Everyone worth hitting right now, plus our own state (one scan).
function TSB.candidates()
  local me = Game.read(LP)
  local list = {}
  if not me.root or not me.valid then return list, me end
  for _, pl in ipairs(Players:GetPlayers()) do
    if pl ~= LP and not whitelisted(pl.Name) then
      local s = Game.read(pl)
      if not s.gone and s.alive and s.valid and not s.npc
        and not (TSB.cfg.respectFF and s.forceField)
        and not (TSB.cfg.skipImmortal and s.immortal) then
        s.dist = (s.position - me.position).Magnitude
        if TSB.cfg.range <= 0 or s.dist <= TSB.cfg.range then
          list[#list + 1] = s
        end
      end
    end
  end
  return list, me
end

-- Lower score wins. Countering targets are pushed to the bottom, not dropped,
-- so a lone countering enemy is still eventually engaged once its window closes.
function TSB.pick(list)
  local best, bestScore
  for _, s in ipairs(list) do
    local score
    if TSB.cfg.priority == "Nearest" then score = s.dist
    elseif TSB.cfg.priority == "Lowest HP nearby" then score = s.health + s.dist * 0.25
    else score = s.health end
    if s.ragdoll then score = score - 20 end        -- finish the ones already down
    if s.countering then score = score + 1e6 end
    if best == nil or score < bestScore then best, bestScore = s, score end
  end
  return best
end

function TSB.combat(me, target)
  local now = os.clock()
  local aim = Wire.aim(target.root)
  if TSB.cfg.useUltimate and Game.ultimateReady() and now - lastUlt > 1 then
    Wire.ult(); lastUlt = now; return
  end
  if TSB.cfg.useSkills and now - lastSkill > TSB.cfg.skillGap then
    local slots = Game.hotbar()
    for i = 1, 4 do
      local slot = slots[i]
      if slot and slot.name and not slot.cooling then
        Wire.skill(i); lastSkill = now; return
      end
    end
  end
  if TSB.cfg.useM1 and now - lastM1 > TSB.cfg.m1Interval then
    Wire.m1(aim); lastM1 = now
  end
end

-- Fling mode delegates to the proven Rep Root queue: arm it, aim for the void,
-- start it once. The queue owns rotation, respawn reacquire and recovery.
function TSB.flingDrive()
  if R == nil or not R.start then TSB.state = "Fling unavailable"; return end
  if R.setRepRoot and not R.repRoot then R.setRepRoot(true) end
  if TSB.cfg.flingVoidAim and R.voidAim ~= true then R.voidAim = true; R.voidRoute = nil end
  if R.loopMode ~= TSB.cfg.flingMode then R.loopMode = TSB.cfg.flingMode end
  if not R.queue then pcall(R.start) end
  TSB.state = R.queue and "Fling (queue active)" or "Fling (starting)"
end

-- Add the local-only rescue exclusion so a public server's 30k pull cannot yank
-- us mid-fling. VIP has that rescue off already, so skip it there.
function TSB.exclusionGuard()
  if TSB.isVIP() or TSB.cfg.mode ~= "Void fling" then return end
  local char = LP.Character
  if char and not char:FindFirstChild("MovingExclusion") then
    pcall(function()
      local f = Instance.new("Folder"); f.Name = "MovingExclusion"; f.Parent = char
    end)
  end
end

function TSB.trackKills()
  local k = Game.killCount()
  if lastKnownKills == nil then lastKnownKills = k; return end
  if k > lastKnownKills then
    for _ = 1, (k - lastKnownKills) do killSamples[#killSamples + 1] = os.clock() end
    TSB.kills += (k - lastKnownKills)
  end
  lastKnownKills = k
end

function TSB.paced()
  if TSB.cfg.maxKillsPerMin <= 0 then return false end
  if TSB.isVIP() then return false end            -- private server: no reason to slow down
  local now, n = os.clock(), 0
  for i = #killSamples, 1, -1 do
    if now - killSamples[i] <= 60 then n += 1 else break end
  end
  return n >= TSB.cfg.maxKillsPerMin
end

function TSB.step()
  if not TSB.cfg.enabled or not TSB.supported() then return end
  if TSB.cfg.voidImmunity then Void.set(true) elseif Void.wanted then Void.set(false) end
  TSB.trackKills()

  local list, me = TSB.candidates()
  if not TSB.selfReady(me) then TSB.state = "Idle (self)"; return end
  if TSB.paced() then TSB.state = "Paused (pace)"; return end

  if TSB.cfg.mode == "Void fling" then
    TSB.exclusionGuard()
    TSB.flingDrive()
    return
  end

  -- Combat mode. If the fling queue is somehow still running, let it go.
  local target = TSB.pick(list)
  if not target then TSB.state = "No target"; return end
  if target.countering and TSB.cfg.skipCountering then
    TSB.state = "Wait (counter) @" .. target.player.Name; return
  end
  TSB.current = target.player
  TSB.combat(me, target)
  TSB.state = "Engaging @" .. target.player.Name
end

function TSB.setMode(v)
  if TSB.cfg.mode == v then return end
  if TSB.cfg.mode == "Void fling" and R and R.stop then pcall(R.stop, "tsb mode change") end
  TSB.cfg.mode = v
  TSB.current = nil
end

function TSB.start()
  if not TSB.supported() then return false, "The Strongest Battlegrounds only" end
  TSB.cfg.enabled = true; TSB.running = true
  if TSB.cfg.voidImmunity then Void.set(true) end
  return true
end

function TSB.stop()
  TSB.cfg.enabled = false; TSB.running = false; TSB.state = "Idle"
  Void.set(false)
  if TSB.cfg.mode == "Void fling" and R and R.stop then pcall(R.stop, "tsb stopped") end
  TSB.current = nil
end

function TSB.bindToggle(k) if k then toggleKey = k end end

L.hold(UIS.InputBegan:Connect(function(input, gpe)
  if gpe or not TSB.supported() then return end
  if input.KeyCode == toggleKey then
    if TSB.cfg.enabled then TSB.stop() else TSB.start() end
  end
end))

-- 20 Hz decision tick. Wire.fire has its own 45/s ceiling, so the loop cannot
-- outrun the game's input path. A gap every frame also keeps us clear of the
-- root-CFrame watchdog (which only cares about gapless CFrame writes anyway --
-- we never write our own root in combat mode).
local acc = 0
L.hold(RS.Heartbeat:Connect(function(dt)
  if not L.live() then return end
  acc += dt
  if acc < 0.05 then return end
  acc = 0
  local ok, err = pcall(TSB.step)
  if not ok then TSB.state = "error"; if L.fault then L.fault("tsb.step", err) end end
end))

-- ---------------------------------------------------------------- the panel
-- One tab. Built only in TSB; elsewhere it explains itself and no-ops.
function TSB.buildUI(win)
  if C == nil then return end
  local page = win:tab({ name = "Combat", chrome = "hero",
    desc = "Automatic targeting for The Strongest Battlegrounds" }).body
  if C.ctx then C.ctx("tsb") end

  if not TSB.supported() then
    C.section(page, "the strongest battlegrounds")
    C.paragraph(page, "This tab drives combat only in The Strongest Battlegrounds (place 10449761463). Join that game and reopen the menu to use it.")
    return
  end

  C.section(page, "engage")
  C.toggle(page, { id = "tsb.enabled", text = "Enable combat",
    desc = "Auto-acquire a target and attack. Toggle key and Backspace both stop it.",
    default = false, callback = function(v) if v then TSB.start() else TSB.stop() end end })
  C.dropdown(page, { id = "tsb.mode", text = "Mode", items = { "Combat", "Void fling" },
    default = TSB.cfg.mode, callback = function(v) TSB.setMode(v) end })
  C.keybind(page, { id = "tsb.toggleKey", text = "Toggle key", default = toggleKey,
    callback = function(k) TSB.bindToggle(k) end })
  C.paragraph(page, "Combat fights with the equipped kit -- M1s, skills 1-4 and the [G] awakening at 100%. Void fling hands your target to the Rep Root queue with void aim on, so their own client's kill-plane finishes them.")

  C.section(page, "targeting")
  C.dropdown(page, { id = "tsb.priority", text = "Priority",
    items = { "Lowest HP", "Nearest", "Lowest HP nearby" }, default = TSB.cfg.priority,
    callback = function(v) TSB.cfg.priority = v end })
  C.slider(page, { id = "tsb.range", text = "Max range (0 = unlimited)", min = 0, max = 400, step = 5,
    default = TSB.cfg.range, callback = function(v) TSB.cfg.range = v end })
  C.toggle(page, { id = "tsb.respectFF", text = "Skip spawn protection", default = true,
    callback = function(v) TSB.cfg.respectFF = v end })
  C.toggle(page, { id = "tsb.skipImmortal", text = "Skip immortal targets", default = true,
    callback = function(v) TSB.cfg.skipImmortal = v end })
  C.toggle(page, { id = "tsb.skipCountering", text = "Avoid counter windows",
    desc = "Hold off while a target's counter (Split Second, Foul Ball, Prey's Peril, Death Counter) is open",
    default = true, callback = function(v) TSB.cfg.skipCountering = v end })
  C.toggle(page, { id = "tsb.whitelist", text = "Honor whitelist",
    desc = "Never hit players you marked excluded in the player panel", default = true,
    callback = function(v) TSB.cfg.whitelist = v end })

  C.section(page, "combat")
  C.toggle(page, { id = "tsb.useUltimate", text = "Awaken at 100%", default = true,
    callback = function(v) TSB.cfg.useUltimate = v end })
  C.toggle(page, { id = "tsb.useSkills", text = "Use skills 1-4", default = true,
    callback = function(v) TSB.cfg.useSkills = v end })
  C.toggle(page, { id = "tsb.useM1", text = "Use M1", default = true,
    callback = function(v) TSB.cfg.useM1 = v end })
  C.slider(page, { id = "tsb.m1Interval", text = "M1 pacing (seconds)", min = 0.2, max = 0.8, step = 0.02,
    default = TSB.cfg.m1Interval, callback = function(v) TSB.cfg.m1Interval = v end })

  C.section(page, "void fling")
  C.dropdown(page, { id = "tsb.flingMode", text = "Queue mode",
    items = { "All players", "Selected players" }, default = TSB.cfg.flingMode,
    callback = function(v) TSB.cfg.flingMode = v end })
  C.toggle(page, { id = "tsb.flingVoidAim", text = "Aim for the void", default = true,
    callback = function(v) TSB.cfg.flingVoidAim = v end })
  C.toggle(page, { id = "tsb.voidImmunity", text = "Void immunity",
    desc = "Disarm your own kill-plane and NaN the fall height so a knock below the map cannot kill you",
    default = true, callback = function(v) TSB.cfg.voidImmunity = v; if not v then Void.set(false) end end })
  C.paragraph(page, "Void fling requires Rep Root, which this build already carries. It cannot kill anyone who is also running void immunity.")

  C.section(page, "stealth")
  C.toggle(page, { id = "tsb.publicCaution", text = "Public-server caution",
    desc = "Slower, exclusion guard on, outside your own private server", default = true,
    callback = function(v) TSB.cfg.publicCaution = v end })
  C.slider(page, { id = "tsb.maxKPM", text = "Max kills / min in public (0 = off)", min = 0, max = 60, step = 1,
    default = TSB.cfg.maxKillsPerMin, callback = function(v) TSB.cfg.maxKillsPerMin = v end })

  C.section(page, "status")
  local status = C.paragraph(page, "Idle.")
  local lbl = status:FindFirstChildWhichIsA("TextLabel", true)
  local tick = 0
  local conn
  conn = RS.Heartbeat:Connect(function(dt)
    if not status.Parent or not L.live() then conn:Disconnect(); return end
    tick += dt; if tick < 0.2 then return end; tick = 0
    if lbl then
      lbl.Text = string.format("%s  |  %s  |  kills %d  |  void %s%s",
        TSB.cfg.enabled and "ON" or "off", TSB.state or "Idle", TSB.kills or 0,
        Void.method or "off", TSB.isVIP() and "  |  VIP" or "")
    end
  end)
  L.hold(conn)
end

end
-- TSB_RAGEBOT_END
