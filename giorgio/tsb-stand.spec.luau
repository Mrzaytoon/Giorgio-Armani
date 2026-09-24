-- luau; run through verify_stand.py. The shipped module is spliced in at MODULE.
local checks = 0
local clock = 1000
local os = { clock = function() return clock end }
local function check(value, message) checks += 1; assert(value, message) end

-- ---------------------------------------------------------------- math
local V = {}
V.__index = function(self, key)
  if key == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) end
  if key == "Unit" then return self / self.Magnitude end
  return V[key]
end
local Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
Vector3.zero = Vector3.new(0, 0, 0)
function V.__add(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
function V.__sub(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
function V.__unm(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
function V.__mul(a, b) return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
function V.__div(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
function V.__eq(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
function V:Dot(b) return self.X * b.X + self.Y * b.Y + self.Z * b.Z end
function V:Cross(b) return Vector3.new(self.Y * b.Z - self.Z * b.Y, self.Z * b.X - self.X * b.Z, self.X * b.Y - self.Y * b.X) end

-- Row-major 3x3 rotation plus position; the same conventions as Roblox.
local CF = {}
local CFrame = {}
local function make(p, m) return setmetatable({ p = p, m = m }, CF) end
local function mm(a, b)
  local r = {}
  for i = 0, 2 do for j = 0, 2 do
    local s = 0
    for k = 0, 2 do s += a[i * 3 + k + 1] * b[k * 3 + j + 1] end
    r[i * 3 + j + 1] = s
  end end
  return r
end
local function mv(m, v)
  return Vector3.new(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
function CFrame.new(x, y, z)
  if type(x) == "table" then return make(x, table.clone(I3)) end
  return make(Vector3.new(x or 0, y or 0, z or 0), table.clone(I3))
end
function CFrame.Angles(rx, ry, rz)
  local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
  local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
  local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
  local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
  return make(Vector3.zero, mm(mm(X, Y), Z))
end
function CFrame.lookAt(pos, target)
  local look = (target - pos).Unit
  local right = look:Cross(Vector3.new(0, 1, 0)).Unit
  local up = right:Cross(look)
  return make(pos, { right.X, up.X, -look.X, right.Y, up.Y, -look.Y, right.Z, up.Z, -look.Z })
end
CF.__index = function(self, key)
  local m = rawget(self, "m")
  if key == "Position" then return rawget(self, "p") end
  if key == "X" then return self.p.X elseif key == "Y" then return self.p.Y elseif key == "Z" then return self.p.Z end
  if key == "Rotation" then return make(Vector3.zero, m) end
  if key == "LookVector" then return Vector3.new(-m[3], -m[6], -m[9]) end
  if key == "RightVector" then return Vector3.new(m[1], m[4], m[7]) end
  if key == "UpVector" then return Vector3.new(m[2], m[5], m[8]) end
  return CF[key]
end
CF.__mul = function(a, b)
  if getmetatable(b) == CF then return make(a.p + mv(a.m, b.p), mm(a.m, b.m)) end
  return a.p + mv(a.m, b)
end
CF.__add = function(a, v) return make(a.p + v, a.m) end
function CF:Inverse()
  local m = self.m
  local t = { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
  return make(-mv(t, self.p), t)
end
local function near(a, b, eps)
  eps = eps or 1e-6
  if (a.p - b.p).Magnitude > eps then return false end
  for i = 1, 9 do if math.abs(a.m[i] - b.m[i]) > eps then return false end end
  return true
end

-- ---------------------------------------------------------------- engine
local function signal()
  local s = { fns = {} }
  function s:Connect(fn)
    local entry = { fn = fn }
    table.insert(self.fns, entry)
    return { Disconnect = function() entry.dead = true end }
  end
  function s:Fire(...)
    for _, entry in ipairs(table.clone(self.fns)) do if not entry.dead then entry.fn(...) end end
  end
  return s
end
local timers = {}
local task
task = {
  spawn = function(fn, ...)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co, ...)
    assert(ok, err)
  end,
  defer = function(fn, ...) fn(...) end,
  delay = function(t, fn, ...) table.insert(timers, { at = clock + t, fn = fn, args = { ... } }) end,
  -- Yields the calling coroutine until the fixture clock passes t.
  wait = function(t)
    local co = coroutine.running()
    table.insert(timers, { at = clock + (t or 0), fn = function() local ok, err = coroutine.resume(co); assert(ok, err) end, args = {} })
    coroutine.yield()
  end,
}
local Enum = {
  TextChatMessageStatus = { Success = "Success", Sending = "Sending" },
  KeyCode = { Backspace = "Backspace", One = "One", Two = "Two", Three = "Three", Four = "Four",
    A = "A", D = "D", W = "W", Q = "Q" },
  Material = { Neon = "Neon" },
  AnimationPriority = { Movement = "Movement", Action = "Action", Core = "Core" },
  RenderPriority = { Camera = { Value = 200 } },
  HumanoidStateType = { Freefall = "Freefall", FallingDown = "FallingDown", Running = "Running",
    GettingUp = "GettingUp", Ragdoll = "Ragdoll", Landed = "Landed" },
}
local Instance = { new = function(class) return { ClassName = class } end }
local RS = { Heartbeat = signal(), RenderStepped = signal() }
local UIS = { InputBegan = signal(), GetFocusedTextBox = function() return nil end }
local binds = {}
local shpCalls = 0
local shpFails = false
local genv = {
  sethiddenproperty = function(part, prop, value)
    assert(prop == "PhysicsRepRootPart", "only PhysicsRepRootPart is ever written")
    if shpFails then error("write refused") end
    shpCalls += 1
    binds[part] = value
  end,
}
local function getgenv() return genv end
local said = {}
local channel = { SendAsync = function(_, message) table.insert(said, message) end }
local TCS = { MessageReceived = signal(), ChatInputBarConfiguration = { TargetTextChannel = channel },
  FindFirstChild = function() return nil end }
local game = { GetService = function(_, name) if name == "TextChatService" then return TCS end end }
local camera = { CameraSubject = nil }
local workspace = { CurrentCamera = camera }

local tracks = {}
local function part(name)
  local p = { Name = name, Parent = true, CanCollide = true, AssemblyLinearVelocity = Vector3.new(1, 1, 1),
    AssemblyAngularVelocity = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 0, 0), Size = Vector3.new(2, 2, 1) }
  function p:IsA(class) return class == "BasePart" end
  return setmetatable(p, { __index = function(t, k) if k == "Position" then return rawget(t, "CFrame").Position end end })
end
local function character(name, at)
  local root = part("HumanoidRootPart")
  root.CFrame = at
  local torso = part("Torso")
  local animator = {}
  function animator:LoadAnimation(animation)
    local track = { id = animation.AnimationId, IsPlaying = false, plays = 0 }
    function track:Play() self.IsPlaying = true; self.plays += 1 end
    function track:Stop() self.IsPlaying = false end
    function track:AdjustWeight() end
    table.insert(tracks, track)
    return track
  end
  local hum = { Health = 100, MaxHealth = 100, RootPart = root, PlatformStand = false, attrs = {},
    enabled = { Freefall = true, FallingDown = true, GettingUp = true, Ragdoll = true }, state = "Freefall" }
  function hum:GetAttribute(k) return self.attrs[k] end
  function hum:GetStateEnabled(st) return self.enabled[st] end
  function hum:SetStateEnabled(st, on) self.enabled[st] = on end
  function hum:GetState() return self.state end
  function hum:ChangeState(st) self.state = st end
  function hum:FindFirstChildOfClass(class) if class == "Animator" then return animator end end
  local ch = { Name = name, parts = { root, torso }, DescendantAdded = signal(), DescendantRemoving = signal(),
    attrs = {}, marks = {} }
  hum.Parent = ch
  function ch:FindFirstChildOfClass(class)
    if class == "Humanoid" then return hum end
    if class == "ForceField" then return self.shield end
  end
  -- Grab markers land on the model as plain children, which is how the module
  -- reads a hold (BeingGrabbed / RootAnchor).
  function ch:FindFirstChild(child) return self.marks[child] end
  function ch:GetDescendants() return self.parts end
  function ch:GetAttribute(k) return self.attrs[k] end
  return ch, hum, root
end
local function player(name, id, at)
  local ch, hum, root = character(name, at)
  local p = { Name = name, DisplayName = name .. "Display", UserId = id, Character = ch, Chatted = signal(),
    CharacterAdded = signal(), hum = hum, root = root }
  function p:IsA(class) return class == "Player" end
  return p
end
local function respawn(p, at)
  local ch, hum, root = character(p.Name, at)
  p.Character, p.hum, p.root = ch, hum, root
  p.CharacterAdded:Fire(ch)
  return ch
end

local LP = player("stand", 1, CFrame.new(50, 441, 50))
local owner = player("owner", 2, CFrame.new(0, 441, 0) * CFrame.Angles(0, math.rad(30), 0))
local enemy = player("enemy", 3, CFrame.new(10, 441, -20) * CFrame.Angles(0, math.rad(-70), 0))
local friend = player("friend", 4, CFrame.new(-200, 441, 0))
local roster = { LP, owner, enemy, friend }
local Players = { PlayerAdded = signal(), PlayerRemoving = signal() }
function Players:GetPlayers() return table.clone(roster) end
function Players:FindFirstChild(name) for _, p in ipairs(roster) do if p.Name == name then return p end end end
function Players:GetPlayerByUserId(id) for _, p in ipairs(roster) do if p.UserId == id then return p end end end
for _, p in ipairs(roster) do p.Parent = Players end

local store = {}
local renderSteps = {}
local notes, faults = {}, {}
local cleanups = {}
local L = { RunService = RS, UIS = UIS, live = function() return true end, hold = function(c) return c end,
  cleanup = function(fn) table.insert(cleanups, fn) end,
  Cfg = { feat = function(id, default) local v = store[id]; if v == nil then return default end; return v end,
    setFeat = function(id, value) store[id] = value end },
  note = function(_, message) table.insert(notes, message) end,
  fault = function(label, why) table.insert(faults, label .. ": " .. tostring(why)) end,
  own = function(x) return x end,
  mk = function(_, props) local x = table.clone(props); x.Destroy = function() end; return x end,
  Toast = { warn = function() end },
  bind = function(_, _, fn) table.insert(renderSteps, fn) end,
  Universal = { want = { fly = false } }, Move = { want = { freeze = false, spin = false } } }
local T = { c = { accent = "accent" } }
local K = { whitelist = {}, flinging = false, cfg = { flingDuration = 6, returnHome = false } }
local flings, queues, setFlings = {}, {}, {}
local R = { repRoot = true, fling = false,
  validPosition = function(v) return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge end }
-- Like the real startFling, the flag goes up synchronously (Giorgio.lua 18012).
function R.runOne(name)
  table.insert(flings, { name = name, bound = binds[LP.root], fling = R.fling, duration = K.cfg.flingDuration, home = LP.root.CFrame })
  K.flinging = true
  return true
end
function R.beginQueue(name) table.insert(queues, { name = name, bound = binds[LP.root], home = LP.root.CFrame }); return true end
function R.setFling(v) R.fling = v == true; table.insert(setFlings, R.fling); return true end

-- The TSB adapter surface the module uses. A move is taken unless `busy`;
-- taking it puts the slot on cooldown, which is how the module sees acceptance.
local slots = { { index = 1, name = "Normal Punch", cooling = false }, { index = 2, name = "Consecutive Punches", cooling = false },
  { index = 3, name = "Shove", cooling = false }, { index = 4, name = "Uppercut", cooling = false } }
local busy = false
local sends, m1s, dashes, ults = {}, {}, {}, {}
local ultReady = false
local function grab(p, on)
  local ch = p.Character
  if on then
    ch.marks.BeingGrabbed = { Name = "BeingGrabbed" }
    ch.shield = {}                 -- measured: a hold hands the victim a ForceField
  else
    ch.marks.BeingGrabbed = nil
    ch.shield = nil
  end
end
R.TSB = { supported = function() return true end,
  Game = {
    body = function(p) local ch = p.Character; return ch, p.hum, p.root end,
    hotbar = function() return slots end,
    ultimateReady = function() return ultReady end,
    read = function(p)
      local hum, root = p.hum, p.root
      return { player = p, gone = false, alive = hum.Health > 0, valid = true, countering = p.countering == true,
        position = root.Position, health = hum.Health, maxHealth = hum.MaxHealth, ragdoll = p.ragdoll == true,
        frozen = p.frozen == true }
    end,
  },
  Wire = {
    skill = function(index)
      table.insert(sends, { slot = index, pose = R.Stand.pose, at = clock })
      if not busy and not slots[index].cooling then slots[index].cooling = true end
      return true
    end,
    m1 = function(aim) table.insert(m1s, { aim = aim, pose = R.Stand.pose, at = clock }) end,
    dash = function(direction, aim) table.insert(dashes, { dir = direction, aim = aim, at = clock }) end,
    ult = function() table.insert(ults, clock) end },
  selfReady = function(me) return me.alive and not me.frozen end,
  cfg = { enabled = false, voidImmunity = true },
}
-- The ragebot's void gate, as the stand sees it: armed on request, and the only
-- thing that lets our own local root go under -500.
local voidWorks = true
R.TSB.Void = { wanted = false,
  set = function(on) R.TSB.Void.wanted = on == true; return true end,
  tick = function() end,
  safe = function() return R.TSB.Void.wanted and voidWorks end }
local function cool(all) for _, s in ipairs(slots) do s.cooling = all end end
local resetCamera = false

local function frame(dt)
  dt = dt or 1 / 60
  clock += dt
  local due = {}
  for i = #timers, 1, -1 do if timers[i].at <= clock then table.insert(due, 1, table.remove(timers, i)) end end
  for _, t in ipairs(due) do t.fn(table.unpack(t.args)) end
  RS.Heartbeat:Fire(dt)
  -- TSB puts the camera back on our own body every frame; the bound step runs after.
  if resetCamera then camera.CameraSubject = LP.hum end
  for _, fn in ipairs(renderSteps) do fn(dt) end
  RS.RenderStepped:Fire(dt)
end
local function frames(seconds) local n = math.ceil(seconds * 60); for _ = 1, n do frame() end end
local function chat(p, message)
  clock += 0.3 -- a person cannot send two messages closer together than this
  -- Both paths fire for one message, as measured on the rig.
  TCS.MessageReceived:Fire({ Status = "Success", TextSource = { UserId = p.UserId }, Text = message })
  p.Chatted:Fire(message)
end
local function playing()
  local list = {}
  for _, t in ipairs(tracks) do if t.IsPlaying then list[#list + 1] = t end end
  return list
end
local C = {}

-- MODULE

local S = R.Stand
check(S and S.mode == "off" and not S.active, "loads idle")
check(S.prefix == "." and S.listen, "prefix and listen defaults")
check(S.poses.Strike.z == 3 and S.poses.Strike.yaw == 0, "strike defaults to behind the target, facing its back")

-- ---------------------------------------------------------------- owner
check(S.setOwner("stand") and S.owner == nil and S.ownerName == "", "owner can never be ourselves")
S.setOwner("owner")
check(S.owner == owner and store["stand.owner"] == "owner", "owner selected and persisted")
chat(enemy, ".s")
frame()
check(S.mode == "off", "a non-owner cannot command the stand")

-- ---------------------------------------------------------------- summon and the latch law
S.float = 0
chat(owner, ".s")
check(S.mode == "summoned" and #said == 1 and said[1] == S.lines.summon, "summons; line spoken once across both chat paths")
frame()
check(S.active and S.pose == "Idle" and binds[LP.root] == owner.root, "latched to the owner's root")
local pose = CFrame.new(3, 2.5, 4)
check(near(LP.root.CFrame, pose), "upright owner: local CFrame is the raw pose (measured composition)")
check(near(S.lastWorld, owner.root.CFrame * pose), "others see owner * pose")
check(LP.root.AssemblyLinearVelocity == Vector3.zero and LP.root.AssemblyAngularVelocity == Vector3.zero, "velocities zeroed")
check(LP.Character.parts[2].CanCollide == false and LP.hum.PlatformStand == false, "collisions off; no PlatformStand by default")
check(LP.hum.enabled.GettingUp == false and LP.hum.enabled.Ragdoll == false,
  "the states a move leaves behind are held off too")
LP.hum.state = "GettingUp"          -- what a finished move leaves on the humanoid
LP.hum.enabled.GettingUp = true     -- and the game re-enabling it afterwards
frame()
check(LP.hum.state == "Running" and LP.hum.enabled.GettingUp == false,
  "a stand left in GettingUp by a move is put straight back to Running")
-- writing a state the humanoid already holds does not replicate, so it is
-- walked through a real transition now and then and brought back next frame
local seen = {}
local realChange = LP.hum.ChangeState
LP.hum.ChangeState = function(self, st) seen[#seen + 1] = st; return realChange(self, st) end
frames(2.5)
LP.hum.ChangeState = realChange
check(table.find(seen, "Landed") ~= nil, "the state is nudged through a real transition")
check(LP.hum.state == "Running", "and is back to Running afterwards")
check(LP.hum.enabled.Freefall == false and LP.hum.enabled.FallingDown == false and LP.hum.state == "Running",
  "held out of Freefall so the game's idle and the pose play")
check(camera.CameraSubject == owner.hum, "camera on the owner")
resetCamera = true
frames(0.2)
check(camera.CameraSubject == owner.hum, "camera stays on the owner although the game resets it every frame")
local stance = playing()
check(#stance == 1 and stance[1].id == "rbxassetid://102959457211902" and stance[1].Priority == "Movement" and stance[1].Looped,
  "fighting stance plays at Movement priority, looped")
local before = shpCalls
frames(0.5)
check(shpCalls - before >= 29, "binding written every Heartbeat")
check(#tracks == 1, "stance loaded once, not every frame")
stance[1]:Stop() -- what TSB does to other tracks when a move starts
frame()
check(stance[1].IsPlaying and #tracks == 1 and stance[1].plays == 2, "a stance the game stopped is back next frame, same track")
S.stance = "Calm float"
frame()
check(#playing() == 1 and playing()[1].id == "rbxassetid://180435571", "calm float swaps to the R6 idle")
S.stance = "Perfect Concentration"
frame()
stance = playing()
check(#stance == 1 and stance[1].id == "rbxassetid://102959457211902", "and back to the default stance")
S.stance = "Fighting stance"
frame()
check(playing()[1].id == "rbxassetid://14516273501", "the old idle guard is still selectable")
S.stance = "Perfect Concentration"
frame()
stance = playing()

owner.root.CFrame = CFrame.new(120, 441, -40) * CFrame.Angles(0, math.rad(-135), 0)
frame()
check(near(LP.root.CFrame, pose) and near(S.lastWorld, owner.root.CFrame * pose), "follows a moving, turning owner")

-- keep-upright against tilted anchors
math.randomseed(7)
local worst = 0
for _ = 1, 400 do
  local yaw = math.random() * 2 * math.pi - math.pi
  local anchor = CFrame.new(math.random(-500, 500), math.random(0, 600), math.random(-500, 500)) * CFrame.Angles(0, yaw, 0)
    * CFrame.Angles(math.random() * 1.2 - 0.6, 0, math.random() * 1.2 - 0.6)
  owner.root.CFrame = anchor
  local p = { x = math.random() * 20 - 10, y = math.random() * 10 - 5, z = math.random() * 20 - 10,
    pitch = math.random(-60, 60), yaw = math.random(-180, 180), roll = math.random(-60, 60) }
  for k, v in pairs(p) do S.poses.Idle[k] = v end
  frame()
  local poseCF = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(math.rad(p.pitch), math.rad(p.yaw), math.rad(p.roll))
  local expected = CFrame.new(anchor.Position) * CFrame.Angles(0, yaw, 0) * poseCF
  local seen = owner.root.CFrame * LP.root.CFrame
  local err = (seen.Position - expected.Position).Magnitude
  for i = 1, 9 do err = math.max(err, math.abs(seen.m[i] - expected.m[i])) end
  worst = math.max(worst, err)
end
check(worst < 1e-6, "keep upright: server sees anchor position * heading * pose (worst " .. worst .. ")")
for k, v in pairs({ x = 3, y = 2.5, z = 4, pitch = 0, yaw = 0, roll = 0 }) do S.poses.Idle[k] = v end

-- a body lying flat keeps its last heading instead of swinging the stand around
owner.root.CFrame = CFrame.new(0, 441, 0) * CFrame.Angles(0, math.rad(40), 0)
frame()
local standing = S.lastWorld
owner.root.CFrame = CFrame.new(0, 441, 0) * CFrame.Angles(0, math.rad(40), 0) * CFrame.Angles(math.rad(-90), 0, 0)
frame()
check((S.lastWorld.Position - standing.Position).Magnitude < 1e-6, "face-down owner: stand stays put (heading kept)")
check(math.abs(S.lastWorld.UpVector.Y - 1) < 1e-6, "face-down owner: stand stays upright")
owner.root.CFrame = CFrame.new(0, 441, 0) * CFrame.Angles(0, math.rad(30), 0)
frame()

-- ---------------------------------------------------------------- kill-plane safety
-- Without the ragebot's void gate nothing we write may go under -450: TSB's own
-- CharacterHandler zeroes our Health below -500. With it closed the rig held
-- 100 HP at -660, and the deep hide is allowed to use that room.
S.hideDeep = false
S.poses.Hidden.y = -9000
voidWorks = false
chat(owner, ".d")
frame()
check(S.mode == "hidden" and S.pose == "Hidden", "dismiss hides under the owner")
check(LP.root.CFrame.Y >= -450, "no void gate: local Y never below -450 even with a bad saved pose")
owner.root.CFrame = CFrame.new(0, 441, 0) * CFrame.Angles(0, 0, math.rad(170))
frame()
check(LP.root.CFrame.Y >= -450, "local Y clamped with an upside-down anchor")
owner.root.CFrame = CFrame.new(0, 441, 0) * CFrame.Angles(0, math.rad(30), 0)
S.poses.Hidden.y = -300
frame()

-- the deep hide: far below and well behind the owner, but only with the gate
S.hideDeep, S.hideDepth, S.hideAway = true, 3000, 250
frame()
check(LP.root.CFrame.Y >= -450, "deep hide degrades to the safe floor while the gate is open")
check(R.TSB.Void.wanted, "and it keeps asking for the gate")
voidWorks = true
frames(0.3)
check(math.abs(LP.root.CFrame.Y + 3000) < 1e-3, "gate closed: the deep hide gets its full depth")
check((S.lastWorld.Position - owner.root.Position).Magnitude > 3000, "and it is far from the owner, not just under them")
S.hideDepth = 900
frame()

-- the owner dies while the stand is hidden: it holds in the void, it does not fall
owner.hum.Health = 0
frame()
check(S.active and S.pose == "Hold" and binds[LP.root] == nil, "owner down: unbound hold")
check(math.abs(LP.root.CFrame.Y + 900) < 1e-3 and LP.root.AssemblyLinearVelocity == Vector3.zero,
  "the hold goes deep too, and is pinned")
frames(1)
check(math.abs(LP.root.CFrame.Y + 900) < 1e-3, "still pinned a second later")
voidWorks = false
frame()
check(LP.root.CFrame.Y >= -450, "losing the gate mid-hold pulls it back above the kill plane, it does not die")
voidWorks = true
S.free("test")
check(LP.root.CFrame.Y > 400, "freed while the owner is down: steps out where the owner last stood")
respawn(owner, CFrame.new(5, 441, 5) * CFrame.Angles(0, math.rad(30), 0))
frame()

-- ---------------------------------------------------------------- setPose clamps and persists
check(S.side("left") and S.poses.Idle.x == -3 and store["stand.pose.Idle.x"] == -3, "pose command changes and saves the idle side")
check(not S.side("sideways") and S.poses.Idle.x == -3, "unknown side refused")
S.side("right")

-- ---------------------------------------------------------------- release restores everything
chat(owner, ".s")
frame()
check(S.pose == "Idle", "summoned again")
S.free("test")
check(not S.active and S.mode == "off" and binds[LP.root] == nil, "freed: binding cleared")
check(LP.Character.parts[2].CanCollide == true and LP.hum.PlatformStand == false, "collision and PlatformStand restored")
check(LP.hum.enabled.Freefall == true and LP.hum.enabled.FallingDown == true, "humanoid states restored")
check((LP.root.CFrame.Position - (owner.root.CFrame * CFrame.new(3, 0, 4)).Position).Magnitude < 1e-6, "steps out beside the owner")
check(math.abs(LP.root.CFrame.UpVector.Y - 1) < 1e-6, "steps out upright")
check(camera.CameraSubject == LP.hum, "camera returned to our humanoid")
check(#playing() == 0, "stance stopped")

-- ---------------------------------------------------------------- blocks and handovers
chat(owner, ".s"); frame()
K.flinging = true; frame()
check(not S.active and S.blocked == "a Rep Root fling is running" and S.mode == "summoned", "pauses for a fling, keeps its mode")
K.flinging = false; frame()
check(S.active, "resumes after the fling")
R.runOne("enemy")
check(flings[1].bound == nil and flings[1].home.Y > 400, "runOne: released first, home is beside the owner")
K.flinging = false
frames(0.6)
check(S.active, "relatches after the handover window")
R.beginQueue("enemy")
check(queues[1].bound == nil and queues[1].home.Y > 400, "Targets loop: released first, home is beside the owner")
frames(0.6)
L.Universal.want.fly = true; frame()
check(not S.active and S.blocked == "fly is on", "fly pauses the stand")
L.Universal.want.fly = false; frame()
shpFails = true; frame()
check(not S.active and S.blocked == "rep-root write refused", "a refused binding write never leaves the body at the raw pose")
shpFails = false; frame()
check(S.active, "recovers once writes work")
R.repRoot = false; frame()
check(not S.active and S.blocked == "Rep Root is off", "respects the Rep Root switch")
R.repRoot = true; frame()

-- ---------------------------------------------------------------- respawn
respawn(LP, CFrame.new(0, 441, 90))
frame()
check(not S.active and S.blocked == "respawning", "waits out our own respawn")
frames(1.6)
check(S.active and binds[LP.root] == owner.root and #playing() == 1 and playing()[1] ~= stance[1], "relatched with a fresh stance")

-- ---------------------------------------------------------------- the attack: behind, rotation, M1, dash
said, sends, m1s, dashes = {}, {}, {}, {}
cool(false)
chat(owner, ".a")
check(S.mode == "attacking" and S.target == enemy, "blank attack takes the nearest non-owner")
frame()
check(S.pose == "Strike" and binds[LP.root] == enemy.root, "latched onto the target")
local strike = CFrame.new(0, 0, 3)
check(near(S.lastWorld, enemy.root.CFrame * strike), "strike pose: behind the target")
check(S.lastWorld.LookVector:Dot(enemy.root.CFrame.LookVector) > 0.999, "faces the same way as the target: its back")
check((S.lastWorld.Position - enemy.root.Position):Dot(enemy.root.CFrame.LookVector) < 0, "on the back side")
check(camera.CameraSubject == owner.hum, "camera stays on the owner while attacking")
check(#sends == 0, "no swing before the pose reaches the server")
frames(0.1)
check(#sends >= 1 and sends[1].slot == 1 and sends[1].pose == "Strike", "slot 1 first, from behind")
for _ = 1, 6 do frame() end
local order = {}
for _, s in ipairs(sends) do order[#order + 1] = s.slot end
check(table.concat(order, ",") == "1,2,3,4", "rotates 1, 2, 3, 4 as each is taken (" .. table.concat(order, ",") .. ")")
local m1Before = #m1s
frames(1)
check(#m1s > m1Before and m1s[#m1s].pose == "Strike", "M1s fill the gap while every skill cools")
local gaps = true
for i = 2, #m1s do if m1s[i].at - m1s[i - 1].at < 0.12 - 1e-9 then gaps = false end end
check(gaps and #m1s - m1Before >= 7, "M1 as fast as allowed, never above ~8/s (" .. (#m1s - m1Before) .. ")")
check(#dashes >= 2 and dashes[1].dir == "W" and dashes[#dashes].dir == "W", "dash spam dashes forward, never sideways")
local n = #sends
slots[3].cooling = false
frame()
check(#sends == n + 1 and sends[#sends].slot == 3, "a skill fires the frame its cooldown ends")
cool(false)
busy = true
n = #sends
frames(0.5)
check(#sends >= n + 5 and sends[n + 1].slot == sends[#sends].slot, "a move the server has not taken is re-sent until it is")
local punched = #m1s
frames(0.3)
check(#m1s == punched, "no M1s while a move is still being sent")
local dashed = #dashes
frames(1)
check(#dashes - dashed >= 2, "dashes keep going while a move is being re-sent (" .. (#dashes - dashed) .. ")")
LP.frozen = true
frames(1.5)
check(S.pending == nil and S.gate == "stand frozen", "a stale send expires while the stand is frozen, and says why it waits")
LP.frozen = false
busy = false
frames(0.1)
check(slots[sends[#sends].slot].cooling, "taken once the server is free")
enemy.countering = true
cool(false)
n, punched = #sends, #m1s
frames(0.5)
check(#sends == n and #m1s == punched, "holds off during a counter window")
enemy.countering = false

-- ---------------------------------------------------------------- owner-commanded skills
cool(true)
slots[2].cooling = false
S.useSkills = false
n = #sends
chat(owner, ".2")
frame()
check(#sends == n + 1 and sends[#sends].slot == 2, "owner's .2 fires on the target at once")
chat(owner, ".4")
frame()
check(#sends == n + 1, "owner asking for a cooling move does not send it")
frames(1.1)
check(said[#said]:find("cooldown", 1, true) ~= nil, "and says it is cooling")
S.useSkills = true

-- ---------------------------------------------------------------- target guards
chat(owner, ".a owner"); check(S.target == enemy, "cannot target the owner by name")
chat(owner, ".a stand"); check(S.target == enemy, "cannot target itself")
K.whitelist.friend = true
chat(owner, ".a friend"); check(S.target == enemy, "whitelisted players refused")
K.whitelist.friend = nil

-- ---------------------------------------------------------------- kill, void, respawn, again
enemy.hum.Health = 0
frame()
check(S.kills == 1 and S.mode == "attacking" and S.waiting == "waiting for respawn", "kill counted, still hunting")
check(S.pose == "Hidden" and binds[LP.root] == owner.root, "waits in the void under the owner")
frames(1.1)
check(said[#said] == S.lines.done, "reports the kill")
frames(2)
check(S.kills == 1, "a corpse is counted once")
local enemyCh = respawn(enemy, CFrame.new(40, 441, 40))
enemyCh.shield = {}
frame()
check(S.pose == "Hidden" and S.waiting == "spawn protection", "waits out spawn protection")
enemyCh.shield = nil
frame()
check(S.pose == "Hidden" and S.waiting == "spawn protection", "a fresh body gets a moment for its shield to appear")
frames(0.8)
check(S.pose == "Strike" and binds[LP.root] == enemy.root and S.waiting == nil, "back on them when the shield drops")
cool(false)
n = #sends
frames(0.15)
check(#sends > n, "and straight back to work")

-- ---------------------------------------------------------------- fling assist
S.flingAssist, S.flingBelow, S.flingEvery, S.flingDrive = true, 40, 10, 1.3
flings = {}
enemy.hum.Health = 30
frames(0.2)
check(#flings == 1 and flings[1].name == "enemy", "fling assist hands a low target to Rep Root")
check(flings[1].bound == nil and flings[1].fling == true and flings[1].duration == 1.3, "released first, fling on, short drive")
check(not S.active and S.blocked == "fling assist is running", "stand steps aside for the fling")
K.flinging = true
frames(0.5)
K.flinging = false
frames(0.4)
check(K.cfg.flingDuration == 6 and K.cfg.returnHome == false and setFlings[#setFlings] == false, "Rep Root settings restored")
frames(0.3)
check(S.active and S.pose == "Strike", "back behind the target after the fling")
frames(2)
check(#flings == 1, "no second fling inside the interval")
S.flingAssist = false
enemy.hum.Health = 100

-- ---------------------------------------------------------------- the attack angle
check(S.poses.Strike.z == 3 and math.abs(S.poses.Strike.x) < 1e-9, "the default angle is straight behind them")
check(S.angle("left flank"), "a ready angle is taken by name")
check(math.abs(S.poses.Strike.x + 3) < 1e-6 and math.abs(S.poses.Strike.z) < 1e-6, "left flank stands on their left")
check(math.abs(S.poses.Strike.yaw + 90) < 1e-6, "and still turns to face them")
frame()
check((S.lastWorld.Position - enemy.root.Position):Dot(enemy.root.CFrame.RightVector) < -2.9, "the latch follows the angle")
check(S.lastWorld.LookVector:Dot(enemy.root.CFrame.RightVector) > 0.999, "facing back at them from the flank")
check(S.angle("in fr"), "a unique prefix picks an angle")
check(math.abs(S.poses.Strike.z + 3) < 1e-6, "in front is the opposite side")
check(not S.angle("sideways"), "an unknown angle is refused")
S.setApproach({ angle = 30, radius = 5, height = 2 })
check(S.approachPreset == "Custom" and store["stand.approach.radius"] == 5, "a hand-set angle becomes Custom and is saved")
check(math.abs(S.poses.Strike.x - 2.5) < 1e-6 and math.abs(S.poses.Strike.y - 2) < 1e-6, "radius and height reach the pose")
S.angle("behind")
check(S.approachPreset == "Behind" and S.poses.Strike.z == 3, "and back to behind")
S.setFacing("Face away")
check(math.abs(math.abs(S.poses.Strike.yaw) - 180) < 1e-6, "face away turns its back on them")
S.setFacing("Face them")

-- ---------------------------------------------------------------- the squad fan
check(S.spread(1, 1) == 0, "one stand sits on the angle itself")
check(math.abs(S.spread(1, 2) + 70) < 1e-6 and math.abs(S.spread(2, 2) - 70) < 1e-6, "two stands split the fan")
check(math.abs(S.spread(2, 3)) < 1e-6, "the middle of three keeps the angle")
S.squadArc, S.squadGap = 40, 60
check(math.abs(S.spread(1, 3) + 60) < 1e-6, "a fan tighter than the smallest gap widens instead of overlapping")
S.squadArc, S.squadGap = 140, 45
check(math.abs(S.spread(1, 2) - S.spread(2, 2)) >= 45, "no two slots are ever inside the minimum gap")
S.setSquad("friend")
frames(0.3)
check(S.squadCount == 2 and S.squadSlot == 1 and store["stand.squad.names"] == "friend",
  "the roster is sorted by user id, we take our own slot, and it is saved")
local straight = enemy.root.CFrame * CFrame.new(0, 0, 3)
check((S.lastWorld.Position - straight.Position).Magnitude > 2, "our slot is turned off the shared angle")
check(math.abs((S.lastWorld.Position - enemy.root.Position).Magnitude - 3) < 1e-4, "but stays at the chosen distance")
chat(owner, ".a friend")
check(S.target == enemy, "a squadmate is never a target")
S.setSquad("")
frames(0.3)
check(S.squadCount == 1 and near(S.lastWorld, straight), "alone again: straight behind")

-- ---------------------------------------------------------------- the carry
-- MEASURED: a hold carries the victim on our replicated position, so the stand
-- takes hold and then moves. The descent is paced across the hold; snapping it
-- leaves them behind (rig, 2026-09-24).
S.comboOn, S.comboEvery, S.comboTries = true, 0, 3
check(not S.canGrab("Uppercut"), "an ordinary move is not treated as a grab")
check(S.canGrab("Hunter's Grasp"), "a name that gives it away is")
slots[3].name = "Hunter's Grasp"
cool(false)
sends, said = {}, {}
frames(0.2)
check(S.combo and S.combo.slot == 3 and S.combo.kind == "void", "a ready grab opens the attack, not the rotation")
check(sends[#sends].slot == 3 and sends[#sends].pose == "Strike", "sent from the strike pose")
local punched = #m1s
frames(0.3)
check(#m1s == punched, "nothing else is fired while the grab is going out")

-- it takes hold
grab(enemy, true)
-- step() runs before combat() in the same frame, so the hold is noticed on one
-- frame and the latch follows on the next.
frame(); frame()
check(S.combo.grabAt ~= nil and S.pose == "Void" and binds[LP.root] == owner.root,
  "a hold moves the latch onto the owner and starts the ride down")
check(S.waiting == nil, "the hold's own ForceField is not read as spawn protection")
check(S.combo.need > 1000 and S.combo.rate > 300, "it aims past the kill plane and paces the descent")
local first = LP.root.CFrame.Y
frames(0.3)
local second = LP.root.CFrame.Y
check(second < first - 100 and second > -S.combo.need, "it descends, and is not there yet: paced, not snapped")
frames(1.5)
check(LP.root.CFrame.Y <= -S.combo.need, "it reaches the depth it aimed for")
check(LP.root.CFrame.Y < -900, "which is well under TSB's -500 kill plane")
local parked = LP.root.CFrame.Y
frames(0.3)
check(LP.root.CFrame.Y < parked - 100, "and keeps going while the hold lasts: it never parks")
check(said[#said] == S.lines.carry, "and it says so once")

-- the hold ends: it lingers, then comes back and checks
grab(enemy, false)
S.comboEvery = 30   -- so only the verdict can start the next one, and we see it
frame()
check(S.combo ~= nil and S.pose == "Void", "it stays down while the release lands")
check(type(S.grabMoves["Hunter's Grasp"]) == "number", "the hold it just watched is learned")
frames(0.5)
check(S.combo == nil and S.verify ~= nil, "then lets go and waits for the verdict")
cool(false)
frames(0.8)
check(S.verify == nil, "the verdict is taken")
check(S.combo and S.combo.tries == 2, "they lived, so it takes them again")

-- a grab that never lands is retried, then given up on
S.combo.grabAt = nil
cool(true)
slots[3].cooling = false
frames(1.8)
check(S.combo == nil or S.combo.tries > 2, "a grab that never takes hold is re-tried")
S.endCombo("test")
S.verify = nil
S.grabMisses = {}
S.comboEvery = 0
slots[1].name, slots[2].name = "Flowing Water", "Consecutive Punches"
S.grabMoves["Flowing Water"] = 1.5
S.grabMoves["Hunter's Grasp"] = 0.5
cool(false)
check(S.canGrab("Flowing Water"), "a learned grab stays learned")
frames(0.2)
check(S.combo and S.combo.slot == 1, "the longest hold is preferred: more descent budget")
check(S.combo.name == "Flowing Water", "by name")

-- bring: the same hold, delivered to the owner instead
S.endCombo("test"); S.verify = nil
S.comboOn = false
cool(false)
check(S.bring("enemy"), "bring is accepted")
check(S.combo.kind == "bring", "as a carry")
grab(enemy, true)
frame(); frame()
check(S.pose == "Bring" and binds[LP.root] == owner.root, "a held target rides in to the owner")
-- Not on top of them: the grab's finisher knocks down whatever is near the
-- stand, and at the old 4 studs the owner was landing inside their own delivery.
local toDrop = S.lastWorld.Position - owner.root.Position
check(math.abs(toDrop.Magnitude - 14) < 0.6, "delivered well clear of the owner, not in their lap")
check(toDrop.Unit:Dot(owner.root.CFrame.LookVector) > 0.99, "and directly in front of them")
-- the bearing is taken once, so turning to watch does not swing it around
local aimed = S.lastWorld.Position
owner.root.CFrame = owner.root.CFrame * CFrame.Angles(0, math.rad(90), 0)
frame()
check((S.lastWorld.Position - aimed).Magnitude < 1e-4, "the delivery holds its bearing when the owner turns")
owner.root.CFrame = owner.root.CFrame * CFrame.Angles(0, math.rad(-90), 0)
frame()
grab(enemy, false)
frame()
check(S.combo ~= nil and S.pose == "Bring", "it holds the delivery while the release resolves")
frames(0.4)
check(S.combo == nil and said[#said] == S.lines.bring, "and it lets go there, with a word")
check(S.verify == nil, "a delivery has nothing to verify")

-- a carry is an errand on someone you name, not the hunt that .a is
S.endCombo("test"); S.verify = nil
S.mode, S.target, S.engaged, S.waiting = "summoned", nil, nil, nil
cool(false)
local okB, whyB = S.bring("")
check(not okB and S.target == nil and S.mode == "summoned",
  "a bare bring asks who instead of taking the nearest stranger: " .. tostring(whyB))
check(S.bring("enemy"), "a named bring is taken")
check(S.mode == "summoned" and S.target == nil, "and it never turns into a hunt")
check(S.combo and S.combo.target == enemy and S.combo.kind == "bring", "it is just the one errand")
S.endCombo("test")

-- the carry needs the void gate; without it, it refuses rather than pretending
voidWorks = false
R.TSB.Void.wanted = false
cool(false)
local ok, why = S.voidDrop("enemy")
check(not ok and tostring(why):find("void", 1, true) ~= nil, "no gate, no void drop: " .. tostring(why))
voidWorks = true
S.comboOn, S.comboEvery = false, 4
S.endCombo("test"); S.verify = nil
slots[3].name = "Shove"
slots[1].name = "Normal Punch"
cool(false)
frame()

-- ---------------------------------------------------------------- stop, skills in front of the owner, barrage
chat(owner, ".stop")
check(S.mode == "summoned" and S.target == nil, "stop brings it back")
for _, t in ipairs(tracks) do t:Stop() end -- the last move stopped everything
frame()
check(#playing() == 1 and playing()[1].id == "rbxassetid://102959457211902", "pose is back the moment the attack stops")
cool(false)
n = #sends
chat(owner, ".3")
frame()
check(S.pose == "Front" and #sends == n, "steps in front first")
frames(0.1)
check(#sends == n + 1 and sends[#sends].slot == 3 and sends[#sends].pose == "Front", "then fires from in front")
check(near(S.lastWorld, owner.root.CFrame * CFrame.new(0, 0.1, -5.5)), "front pose in front of the owner")
frames(1.3)
check(S.pose == "Idle", "back to idle afterwards")
chat(owner, ".m1")
check(S.barrage, "barrage on")
m1s = {}
frames(1)
check(#m1s >= 5 and m1s[1].pose == "Front", "barrage punches from the front pose")
chat(owner, ".m1"); check(not S.barrage, "barrage off")
chat(owner, ".dash"); check(not S.dashSpam and store["stand.dashSpam"] == false, ".dash toggles dash spam and saves it")
chat(owner, ".dash"); check(S.dashSpam, "and back on")

-- ult
ultReady = false
chat(owner, ".ult"); check(#ults == 0, "no awakening before the bar is full")
ultReady = true
chat(owner, ".ult"); check(#ults == 1, "awakening when ready")

-- ---------------------------------------------------------------- parsing
check(not S.handle("s"), "bare word ignored with a prefix set")
check(S.handle(".S") and S.mode == "summoned", "commands are case-insensitive")
check(not S.handle(".unknown"), "unknown command ignored")
S.setPrefix(" ! ")
check(S.prefix == "!" and store["stand.prefix"] == "!", "prefix trimmed and saved")
chat(owner, "!d"); check(S.mode == "hidden", "new prefix works")
S.setPrefix("")
chat(owner, "s"); check(S.mode == "summoned", "no prefix: bare words work")
S.setPrefix(".")
S.listen = false
chat(owner, ".d"); check(S.mode == "summoned", "listen off ignores the owner")
S.listen = true

-- ---------------------------------------------------------------- low health
LP.hum.Health = 20
frames(0.1)
check(S.mode == "hidden" and S.lowHidden, "hides itself at low health")
chat(owner, ".s"); check(S.mode == "hidden", "refuses to come out while hurt")
chat(owner, ".a enemy"); check(S.mode == "hidden", "refuses to fight while hurt")
LP.hum.Health = 100
chat(owner, ".s"); check(S.mode == "summoned", "comes back once healed")

-- ---------------------------------------------------------------- owner leaves, owner changes
frame()
table.remove(roster, 2)
Players.PlayerRemoving:Fire(owner)
check(S.owner == nil and S.mode == "off" and not S.active and binds[LP.root] == nil, "owner leaving frees the stand")
table.insert(roster, 2, owner)
Players.PlayerAdded:Fire(owner)
check(S.owner == owner, "owner rejoining is recognised")
chat(owner, ".s"); frame()
S.setOwner("friend")
check(S.owner == friend and S.mode == "off" and not S.active, "changing owner frees the stand")
chat(owner, ".s"); check(S.mode == "off", "old owner has no control")
S.setOwner("owner")

-- ---------------------------------------------------------------- emergency stop and unload
chat(owner, ".s"); frame()
UIS.InputBegan:Fire({ KeyCode = "Backspace" }, false)
check(S.mode == "off" and not S.active and binds[LP.root] == nil, "Backspace frees the stand")
chat(owner, ".s"); frame()
for _, fn in ipairs(cleanups) do fn() end
check(S.mode == "off" and not S.active and binds[LP.root] == nil, "unload frees the stand")

-- ---------------------------------------------------------------- the tab
local sliders = {}
C.ctx = function() end
C.section = function() end
C.tiles = function() return { set = function() end } end
C.paragraph = function(_, text) local l = { Text = text }; return { Parent = true, FindFirstChildWhichIsA = function() return l end } end
C.dropdown = function(_, opts) return { opts = opts, set = function() end } end
C.input = function(_, opts) return { opts = opts, set = function(self, v) self.value = v end } end
C.toggle = function(_, opts) return { opts = opts, set = function(self, v) self.value = v end } end
C.slider = function(_, opts)
  local api = { opts = opts, value = opts.default }
  function api:set(v) self.value = v end
  if opts.id and opts.id:find("^stand%.edit%.") then sliders[opts.id:sub(12)] = api end
  return api
end
C.actions = function() end
local tabs = {}
local win = { tab = function(_, opts) table.insert(tabs, opts); return { body = {} } end }
S.setOwner("")
S.build(win)
check(#tabs == 1 and tabs[1].name == "Stand", "one Stand tab")
check(S.commandLabel.Text:find("Choose an owner", 1, true) ~= nil, "commands hidden until an owner is chosen")
S.setOwner("owner")
local list = S.commandLabel.Text
for _, entry in ipairs(S.COMMANDS) do
  for _, name in ipairs(entry.names) do check(list:find("." .. name, 1, true) ~= nil, "command listed: " .. name) end
  check(list:find(entry.desc, 1, true) ~= nil, "description listed: " .. entry.desc)
end
check(list:find("@owner", 1, true) ~= nil, "list names the owner")
S.setPrefix("!")
check(S.commandLabel.Text:find("!summon", 1, true) ~= nil, "list follows the prefix")
S.setPrefix(".")
check(sliders.x and sliders.x.opts.step == 0.01 and sliders.pitch.opts.step == 0.1, "position step 0.01, angle step 0.1")
check(sliders.y.opts.min == -450, "Y slider stops at the safe floor")
S.editing = "Strike"
for _, key in ipairs({ "x", "y", "z", "pitch", "yaw", "roll" }) do
  sliders[key].opts.callback(({ x = 1, y = 2, z = 3, pitch = 10, yaw = 20, roll = 30 })[key])
end
check(S.poses.Strike.x == 1 and S.poses.Strike.roll == 30 and store["stand.pose.Strike.yaw"] == 20, "sliders edit and save the selected pose")
check(sliders.x.opts.callback(0 / 0) == false, "NaN refused")

check(#faults == 0, "no faults: " .. table.concat(faults, "; "))
print(string.format("pass: %d stand assertions (latch law, deep hide and void safety, handovers, attack angle, squad fan, the grab carry and its retry, rotation, M1/dash pacing, kill loop, fling assist, commands, tab)", checks))
