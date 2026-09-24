-- Giorgio TSB Stand tab. Embedded by integrate.py after the TSB adapter, so the
-- addon chunk's locals (L, C, T, K, R, Players, LP) and R.TSB (the game reads and
-- input wire) are already in scope.
--
-- The stand is this client's character. An owner, chosen on the tab, commands it
-- from chat. Every latch -- beside the owner, in front of the owner, behind a
-- target, hidden below the owner -- is a PhysicsRepRootPart binding and nothing
-- else: no BodyPosition, no weld, no world-space CFrame chase.
--
-- MEASURED ON THE RIG (TSB place 10449761463, version 17455, 2026-09-23):
--   * While our root's PhysicsRepRootPart is the anchor's root, every other client
--     sees us at anchorRoot.CFrame * (our root's LOCAL CFrame). Writing the usual
--     world mount (anchor.CFrame * offset) read 0.00 studs locally and 452.9 studs
--     on the owner's screen.
--   * Writing the raw offset as our local CFrame held rel(-3.0, 2.5, 4.0) on the
--     owner's screen at every sample through 240 studs of live walking. The
--     server composes, so there is no follow lag. Rotation composes too.
--   * The binding reads back changed almost every frame (578 rebinds in ~10 s),
--     so it is written every Heartbeat.
--   * Hits resolve at the composed position: an M1 fired while latched in front
--     of the owner took 100 -> 97 HP.
--   * Skills: a KeyPress only equips on keyboard. "Console Move" with the tool
--     runs the move with nothing equipped, latched, accepted in 0.08-0.10 s. A
--     move sent while another is still animating is ignored, so the next one is
--     re-sent until the hotbar shows its Cooldown marker.
--   * M1 fired the instant M1Ready flips registers at the game's own pace (4 in
--     3 s); faster sends are dropped by the server.
--   * The latched body has no floor under its local position, so it sat in
--     Freefall playing FallAnim (arms up), and that state's flicker kept
--     stopping any pose track. With Freefall held off the humanoid stays in
--     Running, TSB's own Animate plays its idle guard, and a pose track played
--     10/10 samples with 0 stops. PlatformStand is off by default: it stops both.
-- Consequence: our LOCAL body sits at the raw pose coordinates, near the world
-- origin, while everyone else sees it on the anchor. The camera stays on the
-- owner and a local marker shows where the stand really is.
--
-- MEASURED ON THE RIG (same place, 2026-09-24), the carry law this file's grab
-- combo rests on. Stand on the Hunter kit, victim the owner's alt:
--   * A grab that connects CARRIES the victim on our composed position. The
--     victim's model gains BeingGrabbed, RootAnchor, NoRotate, Freeze and a
--     ForceField together and loses them together; BeingGrabbed is the edge.
--   * Latching to the owner during a grab delivered the victim from 22 studs
--     away to 8 studs from the owner and held it for the whole grab. That is
--     the bring.
--   * A PACED descent past TSB's own -500 kill plane kills: over one 1.5 s
--     Flowing Water hold the victim's own client read 441 -> 428 -> 309 -> 130
--     -> -215 -> -546 and Died fired at -546. Our own HP never moved.
--   * Snapping the whole distance in one frame does NOT: the carry is slew
--     limited (it tracked at ~900 studs/s), the victim was left behind and put
--     back on the map at release. So the drop is spread across the hold, and
--     the hold is whatever this move has been watched to be.
--   * Hold windows: Flowing Water 1.50-1.64 s, Lethal Whirlwind Stream 0.46 s.
--     A grab connects ~0.59 s after the Console Move is taken.
--   * Our own body survives below -500 only while the ragebot's void gate is
--     closed (measured 100 HP at composed -660), so the deep hide and the void
--     drop both arm it first and quietly stay shallow when they cannot.
--   * Our own client LIES about a carried victim's position -- it draws them
--     beside our local body near the origin, so it read y=0 while their client
--     read y=441. Nothing here judges a carry from our own view of the target;
--     it reads the marker, and checks the outcome only after the release.
do
local RS, UIS = L.RunService, L.UIS or game:GetService("UserInputService")
local TCS = game:GetService("TextChatService")
local shp = rawget(getgenv(), "sethiddenproperty") or rawget(getgenv(), "sethiddenprop")

local POSE_KEYS = { "x", "y", "z", "pitch", "yaw", "roll" }
local POSE_NAMES = { "Idle", "Front", "Strike", "Hidden", "Bring" }
local POSE_INFO = {
  Idle = "Beside the owner while summoned. Offsets are owner-local.",
  Front = "In front of the owner for commanded skills and the barrage, facing where the owner faces.",
  Strike = "On the target while attacking. Target-local: +Z is behind them; yaw 0 faces their back, 180 faces them. The attack angle above drives these.",
  Hidden = "The void under the owner: dismissed, or waiting for a target to respawn. Deep hide replaces it with its own depth and distance.",
  Bring = "Where a carried player is delivered. Directly in front of the owner and far enough out that the grab's own damage does not reach them -- the stand rides here still holding them, so they land where it lands.",
}
local POSE_DEFAULTS = {
  Idle   = { x = 3, y = 2.5,  z = 4,    pitch = 0, yaw = 0,   roll = 0 },
  Front  = { x = 0, y = 0.1,  z = -5.5, pitch = 0, yaw = 0,   roll = 0 },
  Strike = { x = 0, y = 0,    z = 3,    pitch = 0, yaw = 0,   roll = 0 },
  Hidden = { x = 0, y = -300, z = 0,    pitch = 0, yaw = 0,   roll = 0 },
  -- Straight out in front of the owner. The first version delivered at z -4 and
  -- that was too literal: the grab's finisher damages and knocks down whatever
  -- is around the stand, so the owner was landing inside their own delivery.
  Bring  = { x = 0, y = 0.5,  z = -14,  pitch = 0, yaw = 180, roll = 0 },
}
-- The Strike pose said as an angle around the target. 0 is directly behind them,
-- 90 their right, 180 in front, 270 their left. Rotating the behind-offset
-- (0, h, r) by yaw t gives (r sin t, h, r cos t), and a body turned by that same
-- yaw looks straight back down the offset -- so one number places and aims it.
local APPROACH_NAMES = { "Behind", "Behind left", "Behind right", "Left flank", "Right flank",
  "In front", "Above", "Below", "Point blank", "Custom" }
local APPROACH_PRESETS = {
  ["Behind"]       = { angle = 0,   radius = 3,   height = 0 },
  ["Behind left"]  = { angle = 315, radius = 3.2, height = 0 },
  ["Behind right"] = { angle = 45,  radius = 3.2, height = 0 },
  ["Left flank"]   = { angle = 270, radius = 3,   height = 0 },
  ["Right flank"]  = { angle = 90,  radius = 3,   height = 0 },
  ["In front"]     = { angle = 180, radius = 3,   height = 0 },
  ["Above"]        = { angle = 0,   radius = 1.5, height = 5 },
  ["Below"]        = { angle = 0,   radius = 1.5, height = -4 },
  ["Point blank"]  = { angle = 0,   radius = 1,   height = 0 },
}
local FACINGS = { "Face them", "Face away" }
-- The carry. TSB's own CharacterHandler.Client zeroes a player's Health when
-- THEIR root drops below this, which is what a void drop spends.
local KILL_PLANE = -500
local GRAB_WAIT = 1.6           -- a sent grab has this long to take hold
local GRAB_HOLD_DEFAULT = 1.35  -- assumed hold until one has been watched
local CARRY_RATE = { 150, 2500 }
local GRAB_MARKS = { "BeingGrabbed", "RootAnchor" }
-- Names that give a grab away before we have ever watched one connect. Anything
-- else has to earn the label by actually taking hold of someone.
local GRAB_HINTS = { "grasp", "grab", "flowing water", "snatch", "seize", "choke", "carry", "drag" }
local GRAB_GIVE_UP = 3          -- hinted move that never holds after this many takes
local BRING_LINGER = 0.3        -- stay at the delivery while the release resolves
local SIDES = {
  right  = { x = 3,  y = 2.5, z = 4 },
  left   = { x = -3, y = 2.5, z = 4 },
  behind = { x = 0,  y = 2,   z = 5 },
  above  = { x = 0,  y = 6,   z = 0.5 },
}
local RANGE = { x = { -40, 40 }, y = { -450, 60 }, z = { -40, 40 },
  pitch = { -180, 180 }, yaw = { -180, 180 }, roll = { -180, 180 } }
-- Our local Y is the pose's Y. TSB's CharacterHandler.Client zeroes Health when
-- the local root drops below Y -500, so nothing we write may go under this.
local SAFE_Y = -450
-- The idle pose. Every id here was load-tested on TSB's own R6 rig on
-- 2026-09-24 and came back with a real length; the ones that are refused to us
-- (Aka Stance, Those Who Know, Take Me On, Superhero) are left out rather than
-- shipped as a stance that silently does nothing. They are the game's own emote
-- idles, read out of ReplicatedStorage.Emotes, so they are looping stances
-- built to be stood in -- unlike the old default, which is TSB's idle guard and
-- is really just a breathing pose with the arms hanging down (measured from the
-- owner's screen: shoulders never leaving -3 to -8 degrees).
local STANCES = { "Perfect Concentration", "The Shadow", "Chosen", "Arms crossed", "Honored",
  "First Rule", "Behold", "Hunter pose", "Ready to strike", "Found you", "By my sword",
  "Shadow", "Into the void", "Fighting stance", "Calm float", "Off", "Custom" }
local STANCE_IDS = {
  ["Perfect Concentration"] = "102959457211902", -- 6.67 s, head bowed, focused
  ["The Shadow"] = "84711944358577",             -- 6.00 s
  ["Chosen"] = "18897538537",                    -- 20.00 s, the longest loop here
  ["Arms crossed"] = "16524243757",              -- 5.50 s ("Cross")
  ["Honored"] = "15503060948",                   -- 5.83 s
  ["First Rule"] = "15503546989",                -- 7.33 s
  ["Behold"] = "121985820220625",                -- 4.17 s
  ["Hunter pose"] = "123794818363362",           -- 2.00 s
  ["Ready to strike"] = "18897713456",           -- 4.50 s ("Attack")
  ["Found you"] = "124365816989281",             -- 3.00 s
  ["By my sword"] = "102174454129081",           -- 4.00 s
  ["Shadow"] = "18897705219",                    -- 1.75 s
  ["Into the void"] = "18459183268",             -- 1.73 s ("Void")
  ["Fighting stance"] = "14516273501",           -- 8.97 s, TSB's own idle guard
  ["Calm float"] = "180435571",                  -- 1.00 s, Roblox's R6 idle
}
-- A new pose reaches the server one physics send later; swing after it has.
local SETTLE = 0.08
local RESEND, GIVE_UP = 0.08, 1.2

local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function feat(key, default) return L.Cfg.feat("stand." .. key, default) end
local function saveFeat(key, value) L.Cfg.setFeat("stand." .. key, value) end
local function number(key, default, min, max)
  local v = feat(key, default)
  return finite(v) and math.clamp(v, min, max) or default
end
local function flag(key, default)
  local v = feat(key, default)
  if type(v) ~= "boolean" then return default end
  return v
end
local function text(key, default)
  local v = feat(key, default)
  return type(v) == "string" and v or default
end

local S = {
  owner = nil, ownerName = text("owner", ""), prefix = text("prefix", "."),
  listen = flag("listen", true),
  mode = "off",            -- off | summoned | hidden | attacking
  target = nil, engaged = nil, waiting = nil, kills = 0,
  frontUntil = 0, barrage = false, pauseUntil = 0, lowHidden = false,
  requests = {}, pending = nil, rotation = 1,
  poses = {}, editing = "Idle",
  float = number("float", 0.35, 0, 2), upright = flag("upright", true),
  -- A new key: PlatformStand stops TSB's own animations, so the old default of
  -- "on" (saved as stand.hover by the first release) must not carry over.
  hover = flag("platformStand", false), camera = flag("camera", true), preview = flag("preview", true),
  stance = text("stance", "Perfect Concentration"), stanceCustom = text("stanceCustom", ""),
  useSkills = flag("useSkills", true), useM1 = flag("useM1", true), autoUlt = flag("autoUlt", false),
  dashSpam = flag("dashSpam", true), dashGap = number("dashGap", 0.35, 0.2, 3),
  waitShield = flag("waitShield", true), lowHP = number("lowHP", 25, 0, 90),
  -- attack angle, and the fan when several stands share one target
  approach = { angle = number("approach.angle", 0, -180, 360), radius = number("approach.radius", 3, 0.5, 30),
    height = number("approach.height", 0, -20, 20) },
  approachPreset = text("approach.preset", "Behind"), facing = text("approach.facing", "Face them"),
  squadOn = flag("squad.on", true), squadNames = text("squad.names", ""),
  squadArc = number("squad.arc", 140, 20, 340), squadGap = number("squad.gap", 45, 10, 180),
  squadSlot = 1, squadCount = 1, squadAt = 0,
  previewAngles = flag("previewAngles", true), previewWho = text("previewWho", ""),
  -- the deep hide
  hideDeep = flag("hideDeep", true), hideDepth = number("hideDepth", 900, 60, 8000),
  hideAway = number("hideAway", 250, 0, 2000), voidAt = 0, voidReady = false,
  -- the grab carry
  combo = nil, verify = nil, comboOn = flag("combo", true), comboTries = number("comboTries", 3, 1, 8),
  comboEvery = number("comboEvery", 4, 0, 60), lastCombo = -math.huge,
  voidMargin = number("voidMargin", 80, 20, 400), carryRate = number("carryRate", 700, CARRY_RATE[1], CARRY_RATE[2]),
  carryAdapt = flag("carryAdapt", true), voidLinger = number("voidLinger", 0.35, 0, 3),
  grabMoves = {}, grabMisses = {}, carried = 0, comboState = "idle",
  flingAssist = flag("flingAssist", false), flingBelow = number("flingBelow", 40, 1, 100),
  flingEvery = number("flingEvery", 10, 2, 60), flingDrive = number("flingDrive", 1.2, 0.3, 6),
  flingBusy = false, lastFling = -math.huge,
  speak = flag("speak", true),
  lines = {
    summon = text("line.summon", "At your service."),
    dismiss = text("line.dismiss", "Understood."),
    attack = text("line.attack", "Target acquired."),
    done = text("line.done", "Target down."),
    carry = text("line.carry", "Going down."),
    bring = text("line.bring", "Delivered."),
  },
  active = false, anchorRoot = nil, pose = nil, poseSince = 0, blocked = nil,
  lastWorld = nil, lastOwnerFrame = nil,
  lastCommand = "none", controls = {}, sliders = {},
}
if not table.find(STANCES, S.stance) then S.stance = "Fighting stance" end
if not table.find(APPROACH_NAMES, S.approachPreset) then S.approachPreset = "Behind" end
if not table.find(FACINGS, S.facing) then S.facing = "Face them" end
-- What each move has been watched to do, carried across sessions: a hold in
-- seconds for one that took someone, false for a hinted name that never did.
do
  local saved = feat("grabMoves", nil)
  if type(saved) == "table" then
    for name, hold in pairs(saved) do
      if type(name) == "string" and (hold == false or (type(hold) == "number" and hold > 0 and hold < 30)) then
        S.grabMoves[name] = hold
      end
    end
  end
end
R.Stand = S

for _, name in ipairs(POSE_NAMES) do
  local pose = {}
  for _, key in ipairs(POSE_KEYS) do
    local range = RANGE[key]
    pose[key] = number("pose." .. name .. "." .. key, POSE_DEFAULTS[name][key], range[1], range[2])
  end
  S.poses[name] = pose
end
-- The first release struck from in front, and saved that default verbatim. A
-- Strike pose still exactly at it was never tuned, so it moves to the new
-- default, behind the target; any pose someone actually edited is left alone.
do
  local old, strike = { x = 0, y = 0, z = -3, pitch = 0, yaw = 180, roll = 0 }, S.poses.Strike
  local untouched = true
  for _, key in ipairs(POSE_KEYS) do if strike[key] ~= old[key] then untouched = false end end
  if untouched then
    for _, key in ipairs(POSE_KEYS) do
      strike[key] = POSE_DEFAULTS.Strike[key]
      saveFeat("pose.Strike." .. key, strike[key])
    end
  end
end

-- ---------------------------------------------------------------- players
local function body(player)
  local ch = player and player.Character
  local hum = ch and ch:FindFirstChildOfClass("Humanoid")
  local root = hum and hum.RootPart
  if hum and root and root.Parent and hum.Health > 0 and R.validPosition(root.Position) then
    return ch, hum, root
  end
end

-- ---------------------------------------------------------------- the squad
-- Several stands, one target, and not one message between them. Every stand
-- sees the same server, so each sorts the squad by UserId, finds itself, and
-- takes that slot of the fan. Slot i of n lands on the same angle on every
-- client, and a stand that dies, leaves or joins just re-packs the list on the
-- next scan -- there is no handshake to lose and nothing to replicate. (A
-- client-made instance never reaches another client, so a handshake would have
-- had to go through chat; this needs no channel at all.)
local function squadNameSet()
  local names = {}
  for word in tostring(S.squadNames or ""):gmatch("[^,%s]+") do names[word:lower():gsub("^@", "")] = true end
  return names
end

local function squadRoster()
  local names = squadNameSet()
  local list = {}
  for _, p in ipairs(Players:GetPlayers()) do
    if p == LP or (p ~= S.owner and names[p.Name:lower()]) then list[#list + 1] = p end
  end
  table.sort(list, function(a, b) return a.UserId < b.UserId end)
  return list
end

local function refreshSquad()
  if not S.squadOn then S.squadSlot, S.squadCount = 1, 1; return end
  local list = squadRoster()
  local slot = 1
  for index, p in ipairs(list) do if p == LP then slot = index end end
  S.squadSlot, S.squadCount = slot, math.max(#list, 1)
end

-- Slot i of n, fanned across the arc and centred on the chosen angle. Stands
-- packed closer than the minimum gap widen the fan instead of overlapping, so
-- two of them never end up inside each other's swing; the fan never closes the
-- full circle, so the first and last are not on top of each other either.
local function spread(slot, count)
  if not S.squadOn or count <= 1 then return 0 end
  local arc = math.clamp(math.max(S.squadArc, S.squadGap * (count - 1)), 0, 360 - 360 / count)
  return arc * ((slot - 1) / (count - 1) - 0.5)
end
S.spread = spread

local function excluded(player)
  if K.whitelist and K.whitelist[player.Name:lower()] == true then return true end
  -- A squadmate is another stand, never a target.
  if S.squadOn and player ~= LP and squadNameSet()[player.Name:lower()] then return true end
  return false
end

-- Exact username first, then a unique prefix of username or display name.
local function findPlayer(query, skip)
  query = tostring(query or ""):gsub("^@", ""):lower()
  if query == "" then return nil end
  for _, p in ipairs(Players:GetPlayers()) do
    if not skip[p] and p.Name:lower() == query then return p end
  end
  local found
  for _, p in ipairs(Players:GetPlayers()) do
    if not skip[p] and (p.Name:lower():sub(1, #query) == query or p.DisplayName:lower():sub(1, #query) == query) then
      if found then return nil, "more than one player matches" end
      found = p
    end
  end
  return found
end

local function nearestToOwner()
  local _, _, ownerRoot = body(S.owner)
  if not ownerRoot then return nil end
  local best, bestDistance
  for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP and p ~= S.owner and not excluded(p) then
      local _, _, root = body(p)
      if root then
        local distance = (root.Position - ownerRoot.Position).Magnitude
        if distance <= 250 and (not best or distance < bestDistance) then best, bestDistance = p, distance end
      end
    end
  end
  return best
end

-- Why the target cannot be hit right now, or nil when it can. A respawned body
-- gets its ForceField a moment after it appears (measured: one sample latched
-- onto a fresh body before its shield showed), so a new body is given a short
-- grace first. The body the attack began on gets none.
local lastBody = setmetatable({}, { __mode = "k" })
local respawnedAt = setmetatable({}, { __mode = "k" })
local RESPAWN_GRACE = 0.75
-- Is someone in a grab right now? Measured: a hold puts BeingGrabbed and
-- RootAnchor on the model together and takes them off together.
local function heldBy(model)
  if not model then return false end
  for _, mark in ipairs(GRAB_MARKS) do
    if model:FindFirstChild(mark) then return true end
  end
  return false
end

local function targetState(target)
  if not target or target.Parent ~= Players then return "left" end
  local ch, hum = body(target)
  if not ch or hum:GetAttribute("Dead") == true then return "waiting for respawn" end
  local previous = lastBody[target]
  if previous ~= ch then
    if previous ~= nil then respawnedAt[ch] = os.clock() end
    lastBody[target] = ch
  end
  -- A grab hands its victim a ForceField for the whole hold (measured), which
  -- read as spawn protection and sent the stand to the void -- away from the
  -- one window it exists to use. A held body is never shielded, it is caught.
  if S.waitShield and not heldBy(ch) then
    if respawnedAt[ch] and os.clock() - respawnedAt[ch] < RESPAWN_GRACE then return "spawn protection" end
    if ch:FindFirstChildOfClass("ForceField") then return "spawn protection" end
  end
  return nil
end

-- ---------------------------------------------------------------- voice
local lastSay, queued = 0, nil
local function send(message)
  lastSay = os.clock()
  task.spawn(function()
    pcall(function()
      local channel = TCS.ChatInputBarConfiguration.TargetTextChannel
      if not channel then
        local channels = TCS:FindFirstChild("TextChannels")
        channel = channels and channels:FindFirstChild("RBXGeneral")
      end
      if channel then channel:SendAsync(message) end
    end)
  end)
end
-- One line a second keeps clear of chat's rate limit. A line inside that second
-- is held, not dropped, and a newer one replaces it: the latest news wins.
local function say(message, force)
  if not S.speak and not force then return end
  message = tostring(message or ""):sub(1, 180)
  if message == "" then return end
  local wait = 1 - (os.clock() - lastSay)
  if wait <= 0 and not queued then send(message); return end
  local first = queued == nil
  queued = message
  if first then
    task.delay(math.max(wait, 0), function()
      local line = queued
      queued = nil
      if line and L.live() then send(line) end
    end)
  end
end

local lastRefusal = 0
local function refuse(message)
  if os.clock() - lastRefusal < 3 then return end
  lastRefusal = os.clock()
  say(message)
end

-- ---------------------------------------------------------------- the latch
local function poseFrame(name)
  local p = S.poses[name]
  return CFrame.new(p.x, p.y, p.z) * CFrame.Angles(math.rad(p.pitch), math.rad(p.yaw), math.rad(p.roll))
end

-- The void gate lives in the TSB adapter and is shared with the Combat tab. We
-- only ever close it for ourselves and hand it back when that tab is not using
-- it. Nothing here assumes it worked: floorY asks every time.
local function voidAPI()
  local adapter = R.TSB
  return adapter and adapter.Void or nil
end

local function voidSafe()
  local void = voidAPI()
  return void ~= nil and void.safe() == true
end

local function wantVoid(on)
  local void = voidAPI()
  if not void then S.voidReady = false; return false end
  if on then
    if not void.wanted then void.set(true) else void.tick() end
    S.voidReady = void.safe() == true
    return S.voidReady
  end
  local adapter = R.TSB
  local shared = adapter and adapter.cfg and adapter.cfg.enabled and adapter.cfg.voidImmunity
  if void.wanted and not shared then void.set(false) end
  S.voidReady = false
  return false
end

-- How low our LOCAL root may go. TSB zeroes our Health below -500, so -450 is
-- the floor until the gate is closed; with it closed the rig held 100 HP at
-- -660, and the deep hide and the void drop get the room they need. Losing the
-- gate does not kill the stand -- it just quietly stops going deep.
local function floorY()
  return voidSafe() and -9000 or SAFE_Y
end

local function clampY(frame)
  local limit = floorY()
  if frame.Position.Y < limit then return frame + Vector3.new(0, limit - frame.Position.Y, 0) end
  return frame
end

-- The anchor's horizontal heading. A body lying flat has no horizontal look
-- vector; its up axis then carries the heading, and failing that the last good
-- heading for this anchor is kept, so a ragdoll never swings the stand around.
local headings = setmetatable({}, { __mode = "k" })
local function heading(anchorRoot, frame)
  local look = frame.LookVector
  local flat = Vector3.new(look.X, 0, look.Z)
  if flat.Magnitude >= 0.2 then
    local yaw = math.atan2(-flat.X, -flat.Z)
    headings[anchorRoot] = yaw
    return yaw
  end
  if headings[anchorRoot] then return headings[anchorRoot] end
  local up = frame.UpVector
  flat = Vector3.new(up.X, 0, up.Z)
  if flat.Magnitude >= 0.2 then return math.atan2(-flat.X, -flat.Z) end
  return nil
end

-- The LOCAL CFrame that the server will compose with the anchor. With "keep
-- upright" a tilted or ragdolled anchor still gets an upright stand: we pre-undo
-- the anchor's tilt and keep only its heading. For an upright anchor this is the
-- raw pose, exactly what the rig measured.
-- The pose before the anchor's tilt is taken out. Three of them are not simply
-- their saved sliders: the deep hide swaps in its own depth and distance, the
-- void drop is ramped frame by frame by the carry, and Strike is turned by this
-- stand's share of the squad fan.
local function baseFrame(name)
  if name == "Hidden" and S.hideDeep then
    return CFrame.new(0, -S.hideDepth, S.hideAway)
  end
  if name == "Void" then
    local combo = S.combo
    return CFrame.new(0, -((combo and combo.depth) or S.hideDepth), 0)
  end
  local frame = poseFrame(name)
  if name == "Strike" then
    local delta = spread(S.squadSlot, S.squadCount)
    if delta ~= 0 then frame = CFrame.Angles(0, math.rad(delta), 0) * frame end
  end
  return frame
end

local function localFrame(anchorRoot, anchorFrame, name, bob)
  local frame = CFrame.new(0, bob or 0, 0) * baseFrame(name)
  if S.upright then
    local yaw = heading(anchorRoot, anchorFrame)
    -- A delivery is aimed ONCE, when the grab takes hold, and keeps that
    -- bearing. Re-deriving it from the owner's live facing every frame carries
    -- the body around them as they turn to watch -- which reads as the stand
    -- circling behind the owner instead of holding station out in front.
    local combo = S.combo
    if name == "Bring" and combo and combo.dropYaw then yaw = combo.dropYaw end
    if yaw then frame = anchorFrame.Rotation:Inverse() * CFrame.Angles(0, yaw, 0) * frame end
  end
  return clampY(frame)
end

-- Every state that can take the pose away from us. Freefall and FallingDown are
-- the ones a floating body falls into by itself; GettingUp is the one a MOVE
-- leaves behind. MEASURED from the owner's screen on 2026-09-24: the stand
-- replicated as FallingDown while idle, and after a .a then .s cycle it sat in
-- GettingUp for good -- the pose looked wrong from outside even though our own
-- client read Running and the stance track was still playing at full weight.
local HELD_STATES = { Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.FallingDown,
  Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.Ragdoll }
local latch = { character = nil, root = nil, hum = nil, platform = false, states = {}, parts = {}, conns = {},
  camera = nil, subject = nil, cameraSet = nil }
local stance = { track = nil, id = nil, hum = nil }
local stateNudged = 0

local function stanceId()
  if S.stance == "Off" then return nil end
  if S.stance == "Custom" then
    local id = tostring(S.stanceCustom or ""):match("%d+")
    return id
  end
  return STANCE_IDS[S.stance] or STANCE_IDS["Fighting stance"]
end

-- Movement priority: above the Core fall animation the latched body is stuck in,
-- below the Action tracks that M1s and skills play. TSB stops other tracks when a
-- move starts, which used to leave the stand posing wrong after an attack; the
-- track is checked every frame and brought straight back when it has stopped.
local function setStance(hum)
  local want = hum and stanceId() or nil
  if want ~= stance.id or hum ~= stance.hum then
    if stance.track then
      local old = stance.track
      pcall(function() old:Stop(0.2) end)
    end
    -- Recorded before loading, so a refused asset is not retried every frame.
    stance.track, stance.id, stance.hum = nil, want, hum
    if not want then return end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    local animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. want
    local ok, track = pcall(animator.LoadAnimation, animator, animation)
    if not ok or not track then return end
    track.Priority = Enum.AnimationPriority.Movement
    track.Looped = true
    stance.track = track
  end
  local track = stance.track
  if track and not track.IsPlaying then
    pcall(function()
      track:Play(0.15)
      track:AdjustWeight(1)
    end)
  end
end

local function wanted()
  if S.mode == "off" then return nil end
  if not body(S.owner) then return nil, "Hold" end
  -- A carry owns the latch while it lasts: on the target until the grab takes
  -- hold, then on the owner, riding down to the void or in to the delivery.
  local combo = S.combo
  if combo then
    if not combo.grabAt then
      if body(combo.target) then return combo.target, "Strike" end
      return S.owner, "Idle"
    end
    return S.owner, combo.kind == "bring" and "Bring" or "Void"
  end
  if S.mode == "attacking" then
    if not targetState(S.target) then return S.target, "Strike" end
    return S.owner, "Hidden"
  end
  if S.mode == "hidden" then return S.owner, "Hidden" end
  if S.barrage or os.clock() < S.frontUntil then return S.owner, "Front" end
  return S.owner, "Idle"
end

local function blockedReason()
  if not R.repRoot then return "Rep Root is off" end
  if type(shp) ~= "function" then return "this executor has no sethiddenproperty" end
  if S.flingBusy then return "fling assist is running" end
  if os.clock() < S.pauseUntil then return "paused" end
  if K.flinging or K.activeCleanup or K.returningHome then return "a Rep Root fling is running" end
  if R.queue then return "the Targets loop is running" end
  if R.tuning then return "auto-tune is running" end
  local universal = L.Universal and L.Universal.want
  if universal and universal.fly then return "fly is on" end
  local move = L.Move and L.Move.want
  if move and (move.freeze or move.spin) then return "freeze or spin is on" end
  return nil
end

local function restoreCamera()
  local camera = latch.camera
  if camera and camera == workspace.CurrentCamera and latch.cameraSet and camera.CameraSubject == latch.cameraSet then
    local own = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    pcall(function() camera.CameraSubject = own or latch.subject end)
  end
  latch.camera, latch.subject, latch.cameraSet = nil, nil, nil
end

local function dropConnections()
  for _, conn in ipairs(latch.conns) do conn:Disconnect() end
  table.clear(latch.conns)
end

-- Where a released stand is put down: beside the owner (their last living
-- position if they are dead), never the pose's own world spot, which for the
-- hidden pose is 300 studs under the map.
local function stepOut()
  local _, _, ownerRoot = body(S.owner)
  local base = ownerRoot and ownerRoot.CFrame or S.lastOwnerFrame
  local out = base and base * CFrame.new(S.poses.Idle.x, 0, S.poses.Idle.z)
  if not out and S.lastWorld and S.pose ~= "Hidden" then out = S.lastWorld end
  if not out then return nil end
  local look = out.LookVector
  local flat = Vector3.new(look.X, 0, look.Z)
  out = flat.Magnitude > 0.2 and CFrame.lookAt(out.Position, out.Position + flat) or CFrame.new(out.Position)
  return clampY(out)
end

-- Everything the latch changed, undone. Safe to call twice and after a death.
local function release(why)
  if not S.active then return end
  S.active = false
  dropConnections()
  setStance(nil)
  local root, hum = latch.root, latch.hum
  if root and root.Parent and LP.Character == latch.character then
    pcall(shp, root, "PhysicsRepRootPart", nil)
    local out = stepOut()
    pcall(function()
      if out then root.CFrame = out end
      root.AssemblyLinearVelocity = Vector3.zero
      root.AssemblyAngularVelocity = Vector3.zero
    end)
    for part, was in pairs(latch.parts) do
      pcall(function() if part.Parent then part.CanCollide = was end end)
    end
    pcall(function()
      if hum.Parent then
        hum.PlatformStand = latch.platform
        for state, was in pairs(latch.states) do hum:SetStateEnabled(state, was) end
      end
    end)
  end
  table.clear(latch.parts)
  restoreCamera()
  S.anchorRoot, S.pose, S.pending = nil, nil, nil
  if why then L.note("stand", "released: " .. tostring(why)) end
end
S.release = release

local function begin(ch, hum, root)
  table.clear(latch.parts)
  dropConnections()
  for _, d in ipairs(ch:GetDescendants()) do
    if d:IsA("BasePart") then latch.parts[d] = d.CanCollide end
  end
  latch.character, latch.root, latch.hum = ch, root, hum
  latch.platform = hum.PlatformStand
  -- The latched body has no floor under its local position, so it would sit in
  -- Freefall, whose animation (arms up) overrides everything and whose flicker
  -- kept stopping the pose track (measured: never stopped once the state held).
  latch.states = {}
  for _, state in ipairs(HELD_STATES) do
    latch.states[state] = hum:GetStateEnabled(state)
    hum:SetStateEnabled(state, false)
  end
  latch.conns[1] = ch.DescendantAdded:Connect(function(d)
    if d:IsA("BasePart") and latch.parts[d] == nil then latch.parts[d] = d.CanCollide end
  end)
  latch.conns[2] = ch.DescendantRemoving:Connect(function(d) latch.parts[d] = nil end)
  S.active = true
end

local born = setmetatable({}, { __mode = "k" })
L.hold(LP.CharacterAdded:Connect(function(ch) born[ch] = os.clock() end))

local function hold(frame, anchorRoot, poseName, ch, hum, root)
  if not S.active then begin(ch, hum, root) end
  local ok = pcall(shp, root, "PhysicsRepRootPart", anchorRoot)
  if not ok then return false end
  for part in pairs(latch.parts) do
    if part.Parent then part.CanCollide = false end
  end
  if S.hover and not hum.PlatformStand then hum.PlatformStand = true end
  if not S.hover then
    -- Held every frame, not just at the latch. The game re-enables these after
    -- its own moves, and one frame in a disabled state is enough to replicate
    -- it: the stand then sits in GettingUp on everyone else's screen until the
    -- next latch. Anything that is not Running is put back to Running, so the
    -- pose outside matches the pose we are playing.
    for _, state in ipairs(HELD_STATES) do
      if hum:GetStateEnabled(state) then hum:SetStateEnabled(state, false) end
    end
    if hum:GetState() ~= Enum.HumanoidStateType.Running then
      hum:ChangeState(Enum.HumanoidStateType.Running)
    end
    -- A state written while the humanoid already holds it does not replicate:
    -- measured both ways, our client read Running for 120 straight frames while
    -- the owner's still showed the Freefall it drifted into during a move. A
    -- real transition does replicate, so the state is nudged through Landed
    -- every couple of seconds and the line above walks it back to Running on
    -- the next frame. Invisible here, and it keeps the body standing over there.
    if os.clock() - stateNudged >= 2 then
      stateNudged = os.clock()
      hum:ChangeState(Enum.HumanoidStateType.Landed)
    end
  end
  root.CFrame = frame
  root.AssemblyLinearVelocity = Vector3.zero
  root.AssemblyAngularVelocity = Vector3.zero
  if S.pose ~= poseName or S.anchorRoot ~= anchorRoot then S.poseSince = os.clock() end
  S.anchorRoot, S.pose = anchorRoot, poseName
  setStance(hum)
  return true
end

local function step()
  local _, _, ownerRoot = body(S.owner)
  if ownerRoot then S.lastOwnerFrame = ownerRoot.CFrame end
  if S.mode == "off" then
    if S.active then release("off") end
    if S.voidReady then wantVoid(false) end
    S.blocked = nil
    return
  end
  local now = os.clock()
  -- Who else is standing here, at 4 Hz: joins, deaths and leaves re-pack the fan.
  if now - S.squadAt >= 0.25 then S.squadAt = now; refreshSquad() end
  -- The gate is closed ahead of time, not at the moment it is needed: locating
  -- TSB's kill-plane closure takes a tick, and a carry cannot wait for it.
  if now - S.voidAt >= 0.2 then
    S.voidAt = now
    wantVoid((S.hideDeep or S.comboOn) and S.mode ~= "off")
  end
  local reason = blockedReason()
  local ch, hum, root = body(LP)
  if not reason then
    if not ch then reason = "waiting for your character"
    elseif born[ch] and os.clock() - born[ch] < 1.5 then reason = "respawning" end
  end
  if reason then
    if S.active then release(reason) end
    S.blocked = reason
    return
  end
  S.blocked = nil
  -- A death ends the old latch with nothing left to restore.
  if S.active and (latch.character ~= ch or latch.root ~= root) then
    S.active = false
    dropConnections()
    table.clear(latch.parts)
    restoreCamera()
  end

  local anchorPlayer, poseName = wanted()
  if poseName == "Hold" then
    -- The owner is dead. Wait in the void, unbound and pinned, until they are back.
    -- The deep hide applies here too, so a stand waiting out its owner is not
    -- left hanging in plain sight three hundred studs under the map.
    hold(clampY(CFrame.new(baseFrame("Hidden").Position)), nil, "Hold", ch, hum, root)
    S.lastWorld = nil
    return
  end
  local _, _, anchorRoot = body(anchorPlayer)
  if not anchorRoot then return end

  local anchorFrame = anchorRoot.CFrame
  local bob = S.float > 0 and poseName ~= "Strike" and math.sin(os.clock() * 2.2) * S.float or 0
  local frame = localFrame(anchorRoot, anchorFrame, poseName, bob)
  if not hold(frame, anchorRoot, poseName, ch, hum, root) then
    release("rep-root write refused")
    S.blocked = "rep-root write refused"
    return
  end
  S.lastWorld = anchorFrame * frame
  if poseName == "Strike" and S.target and S.engaged ~= S.target.Character then S.engaged = S.target.Character end
  if latch.cameraSet and not S.camera then restoreCamera() end
end

-- TSB puts the camera back on our own humanoid every frame (measured: a
-- Heartbeat write never held). Writing just before the camera module updates
-- means the frame is always rendered on the owner, whoever reset it in between.
local function aimCamera()
  if not S.camera or not S.active then return end
  local _, ownerHum = body(S.owner)
  local camera = workspace.CurrentCamera
  if not ownerHum or not camera or camera.CameraSubject == ownerHum then return end
  if latch.camera ~= camera then latch.camera, latch.subject = camera, camera.CameraSubject end
  pcall(function() camera.CameraSubject = ownerHum end)
  latch.cameraSet = ownerHum
end

-- ---------------------------------------------------------------- combat
local function tsb()
  local adapter = R.TSB
  return adapter and adapter.supported() and adapter or nil
end

local function lowHealth()
  if S.lowHP <= 0 then return false end
  local _, hum = body(LP)
  return hum ~= nil and hum.Health / math.max(hum.MaxHealth, 1) * 100 <= S.lowHP
end

local lastM1, lastDash, lastUlt = 0, 0, 0

local function settled(poseName)
  return S.active and S.pose == poseName and os.clock() - S.poseSince >= SETTLE
end

-- ---------------------------------------------------------------- the carry
-- What a move has been watched to do. A hold in seconds means it took someone
-- and held them that long; false means a hinted name that kept failing to. The
-- table is saved, so a kit is only learned once.
local function saveGrabMoves()
  saveFeat("grabMoves", S.grabMoves)
end

local function learnGrab(name, hold)
  if not name then return end
  local known = S.grabMoves[name]
  -- Averaged, so one clipped sample cannot ruin a good pace.
  local value = type(known) == "number" and (known * 0.6 + hold * 0.4) or hold
  S.grabMoves[name] = math.clamp(value, 0.15, 10)
  S.grabMisses[name] = nil
  saveGrabMoves()
end

local function missedGrab(name)
  if not name or type(S.grabMoves[name]) == "number" then return end
  local misses = (S.grabMisses[name] or 0) + 1
  S.grabMisses[name] = misses
  if misses >= GRAB_GIVE_UP then S.grabMoves[name] = false; saveGrabMoves() end
end

local function canGrab(name)
  if not name then return false end
  local known = S.grabMoves[name]
  if known ~= nil then return known ~= false end
  local lower = name:lower()
  for _, hint in ipairs(GRAB_HINTS) do
    if lower:find(hint, 1, true) then return true end
  end
  return false
end
S.canGrab = canGrab

local function grabHold(name)
  local known = name and S.grabMoves[name]
  return type(known) == "number" and known or GRAB_HOLD_DEFAULT
end

-- The ready slot that can take hold, longest hold first: every extra tenth of a
-- second of hold is another ~70 studs of descent budget.
local function grabSlot(slots)
  local best
  for index = 1, 4 do
    local slot = slots[index]
    if slot and slot.name and not slot.cooling and canGrab(slot.name) then
      if not best or grabHold(slot.name) > grabHold(slots[best].name) then best = index end
    end
  end
  return best
end

-- The rotation never spends a grab while the carry wants one: a grab put on
-- cooldown as an ordinary move is a combo that cannot open. The combo is the
-- only caller for those slots, so nothing is wasted by holding them back. An
-- owner asking for a slot by number still gets it -- that goes through requests.
local function nextReady(slots)
  local reserve = S.comboOn and S.mode == "attacking"
  for offset = 0, 3 do
    local index = (S.rotation + offset - 1) % 4 + 1
    local slot = slots[index]
    if slot and slot.name and not slot.cooling and not (reserve and canGrab(slot.name)) then return index end
  end
  return nil
end

-- The owner's own requests go first, oldest first; otherwise, while attacking,
-- the rotation's next ready slot. A requested slot already cooling is refused.
local function chooseSlot(slots, now, attacking)
  local best, bestAt
  for index, request in pairs(S.requests) do
    if now > request.untilAt then S.requests[index] = nil
    else
      local slot = slots[index]
      if not slot or not slot.name then S.requests[index] = nil; refuse("Slot " .. index .. " is empty.")
      elseif slot.cooling and not request.sent then S.requests[index] = nil; refuse(slot.name .. " is on cooldown.")
      elseif not slot.cooling and (not best or request.at < bestAt) then best, bestAt = index, request.at end
    end
  end
  if best then return best end
  if attacking and S.useSkills then return nextReady(slots) end
  return nil
end

-- One carry, from the send to the verdict:
--   casting     the grab is sent and re-sent until it takes hold
--   carrying    it has hold, so the latch moves to the owner and the stand
--               either ramps down into the void or rides straight to delivery
--   letting go  the hold ended; stay put a moment so the release lands here
-- Nothing is judged while the grab is up -- our client draws a carried body
-- beside our local root, not where it really is -- so the verdict waits for the
-- release and is read from the target's own state.
local function endCombo(why, verdict)
  local combo = S.combo
  if not combo then return end
  S.combo, S.comboState = nil, "idle"
  S.lastCombo = os.clock()
  if verdict and combo.kind == "void" then
    S.verify = { target = combo.target, at = os.clock() + 0.6, tries = combo.tries }
  end
  if why then L.note("stand", "carry ended: " .. tostring(why)) end
end
S.endCombo = endCombo

local function beginCombo(kind, target, tries)
  if S.combo then return false, "already carrying someone" end
  if not S.owner or not body(S.owner) then return false, "the owner is not here" end
  local adapter = tsb()
  if not adapter then return false, "carries need The Strongest Battlegrounds" end
  if not target or not body(target) then return false, "no one to take" end
  local why = targetState(target)
  if why then return false, why end
  local index = grabSlot(adapter.Game.hotbar())
  if not index then return false, "no grab is ready" end
  if kind == "void" and not wantVoid(true) then
    return false, "void immunity is not armed"
  end
  S.combo = { kind = kind, target = target, slot = index, name = adapter.Game.hotbar()[index].name,
    firstAt = os.clock(), sentAt = -math.huge, tries = (tries or 0) + 1, depth = 0 }
  S.comboState = "casting"
  return true
end
S.beginCombo = beginCombo

-- True while the carry owns the frame: no swings, no dashes, no rotation.
local function comboStep(now, adapter, slots)
  local combo = S.combo
  local target = combo.target
  local model = adapter.Game.body(target)

  if not combo.grabAt then
    S.comboState = "casting " .. tostring(combo.name)
    if heldBy(model) then
      combo.grabAt = now
      combo.hold = grabHold(combo.name)
      local _, _, ownerRoot = body(S.owner)
      combo.ownerY = ownerRoot and ownerRoot.Position.Y or 0
      combo.dropYaw = ownerRoot and heading(ownerRoot, ownerRoot.CFrame) or nil
      if combo.kind == "void" then
        -- The whole descent has to fit inside this one hold: between grabs the
        -- victim is returned to the map, which spends the progress. So aim past
        -- the kill plane with margin and pace it to arrive just before the hold
        -- is due to end (measured: 1041 studs over a 1.5 s hold killed).
        combo.need = math.max(combo.ownerY - (KILL_PLANE - S.voidMargin), 50)
        combo.rate = S.carryAdapt
          and math.clamp(combo.need / math.max(combo.hold - 0.15, 0.3), CARRY_RATE[1], CARRY_RATE[2])
          or S.carryRate
        say(S.lines.carry)
      end
      return true
    end
    if targetState(target) == "left" then endCombo("they left"); return false end
    if now - combo.firstAt > GRAB_WAIT then
      missedGrab(combo.name)
      local index = combo.tries < S.comboTries and grabSlot(slots) or nil
      if index then
        combo.slot, combo.name = index, slots[index].name
        combo.firstAt, combo.sentAt, combo.tries = now, -math.huge, combo.tries + 1
        return true
      end
      endCombo("nothing took hold")
      return false
    end
    if now - combo.sentAt >= RESEND and settled("Strike") then
      adapter.Wire.skill(combo.slot)
      combo.sentAt = now
    end
    return true
  end

  if heldBy(model) then
    S.comboState = combo.kind == "bring" and "carrying them in" or "carrying them down"
    if combo.kind == "void" then
      -- MEASURED the hard way: the victim descends only while WE are descending,
      -- at our rate and a little behind us. A run that reached its depth early
      -- and parked for the last 0.4 s of the hold gained nothing in that time
      -- and stopped 191 studs above the kill plane. So the ramp never stops
      -- while the hold lasts; the depth we aimed for only sets the pace.
      combo.depth = math.min((now - combo.grabAt) * combo.rate, combo.need * 2)
    end
    return true
  end

  if not combo.releasedAt then
    combo.releasedAt = now
    learnGrab(combo.name, now - combo.grabAt)
    S.carried += 1
    if combo.kind == "bring" then say(S.lines.bring) end
  end
  S.comboState = "letting go"
  -- A delivery holds station for a moment too: the finisher's knockback lands
  -- where the stand is standing, so it must not be halfway home by then.
  local linger = combo.kind == "void" and S.voidLinger or BRING_LINGER
  if now - combo.releasedAt >= linger then endCombo("released", true) end
  return true
end

-- The verdict, and the retry the owner asked for: if they are not down, take
-- them again until the attempt budget runs out.
local function verifyStep(now)
  local verify = S.verify
  if not verify or now < verify.at then return end
  S.verify = nil
  local state = targetState(verify.target)
  if state == "waiting for respawn" or state == "left" then return end
  if not S.comboOn or S.mode ~= "attacking" or S.target ~= verify.target then return end
  if verify.tries >= S.comboTries then
    refuse("They slipped it. Going back to the fists.")
    S.lastCombo = now + math.max(S.comboEvery, 2)
    return
  end
  beginCombo("void", verify.target, verify.tries)
end

-- Fling assist: the proven Rep Root transaction, once, on the target. The latch
-- is handed over by the R.runOne wrapper below and comes back when it ends.
local function flingNow(target)
  if S.flingBusy then return false, "already flinging" end
  if not target or not body(target) then return false, "no target to fling" end
  if not R.repRoot then return false, "Rep Root is off" end
  if K.flinging or R.queue or R.tuning then return false, "Rep Root is busy" end
  S.flingBusy, S.lastFling = true, os.clock()
  local saved = { fling = R.fling, duration = K.cfg.flingDuration, returnHome = K.cfg.returnHome }
  R.fling = true
  K.cfg.flingDuration = S.flingDrive
  K.cfg.returnHome = true
  -- Its own thread: startFling can yield up to 1.5 s while a previous attempt
  -- recovers, and the stand's frame loop must never wait on that.
  task.spawn(function()
    local ok, why = pcall(R.runOne, target.Name)
    if not ok or why == false then L.note("stand", "fling assist refused: " .. tostring(why)) end
    local deadline = os.clock() + S.flingDrive + 8
    task.wait(0.1)
    while L.live() and (K.flinging or K.activeCleanup or K.returningHome) and os.clock() < deadline do task.wait(0.05) end
    K.cfg.flingDuration, K.cfg.returnHome = saved.duration, saved.returnHome
    -- setFling re-syncs every control and saved value from the restored config.
    if R.setFling then R.setFling(saved.fling) else R.fling = saved.fling end
    S.flingBusy = false
    S.pauseUntil = os.clock() + 0.2
  end)
  return true
end
S.flingNow = flingNow

local function combat()
  local now = os.clock()
  if S.mode == "attacking" then
    local state = targetState(S.target)
    if state == "left" then
      S.mode, S.target, S.engaged, S.waiting = "summoned", nil, nil, nil
      say("They left.")
      return
    end
    if state == "waiting for respawn" and S.engaged then
      -- The body we were fighting is gone: a kill. Wait in the void for the next one.
      S.kills += 1
      S.engaged = nil
      say(S.lines.done)
    end
    S.waiting = state
  end
  if S.mode ~= "off" and S.mode ~= "hidden" and lowHealth() then
    S.mode, S.target, S.engaged, S.barrage, S.lowHidden = "hidden", nil, nil, false, true
    table.clear(S.requests)
    endCombo("too hurt to carry")
    S.verify = nil
    say("I need to recover.")
    return
  end
  local adapter = tsb()
  if not adapter or not S.active then S.gate = adapter and "latch off" or "not in TSB"; return end
  -- A send the server never took expires even while we cannot act, so one
  -- stuck move can never wedge the rotation.
  if S.pending and now - S.pending.at > GIVE_UP then
    S.rotation = S.pending.slot % 4 + 1
    S.requests[S.pending.slot] = nil
    S.pending = nil
  end
  local me = adapter.Game.read(LP)
  if not adapter.selfReady(me) then
    S.gate = me.frozen and "stand frozen" or me.ragdoll and "stand knocked down" or me.seated and "stand seated"
      or me.anchored and "stand anchored" or "stand cannot act"
    return
  end

  local slots = adapter.Game.hotbar()
  verifyStep(now)
  if S.combo and comboStep(now, adapter, slots) then S.gate = nil; return end

  local attacking = S.mode == "attacking" and not S.waiting and settled("Strike")
  local fronting = S.mode == "summoned" and settled("Front")
  local other = attacking and adapter.Game.read(S.target) or nil
  if other and (other.gone or not other.valid) then S.gate = "target unreadable"; return end
  if other and other.countering then S.gate = "target countering"; return end
  S.gate = nil
  local aimAt = other and other.position
  if not aimAt then
    local _, _, ownerRoot = body(S.owner)
    aimAt = ownerRoot and (ownerRoot.CFrame * CFrame.new(0, 0, -25)).Position
  end
  local aim = aimAt and CFrame.new(aimAt) or nil

  -- A grab is worth more than the next move in the rotation: it is the whole
  -- combo. Only while actually on them, and only once the void can hold us.
  if attacking and S.comboOn and not S.pending and now - S.lastCombo >= S.comboEvery and grabSlot(slots) then
    if beginCombo("void", S.target) then return end
    S.lastCombo = now   -- refused (no owner, no void gate): wait out the interval
  end

  -- Dashes run on their own clock, weaving between and around every move. One
  -- still on TSB's cooldown is simply refused, so trying often costs nothing.
  if S.dashSpam and (attacking or (fronting and S.barrage)) and now - lastDash >= S.dashGap then
    adapter.Wire.dash(Enum.KeyCode.W, aim) -- forward: straight at the target's back
    lastDash = now
  end

  if attacking and S.flingAssist and not S.flingBusy and now - S.lastFling >= S.flingEvery then
    local health = other.health and other.maxHealth and other.health / other.maxHealth * 100 or 100
    if health <= S.flingBelow or (other.ragdoll and not nextReady(slots)) then flingNow(S.target); return end
  end

  -- A skill that has not been taken yet is re-sent until its cooldown shows.
  if S.pending then
    local slot = slots[S.pending.slot]
    if slot and slot.cooling then
      S.rotation = S.pending.slot % 4 + 1
      if S.requests[S.pending.slot] then S.requests[S.pending.slot] = nil end
      if S.mode == "summoned" then S.frontUntil = math.max(S.frontUntil, now + 0.9) end
      S.pending = nil
    else
      if now - S.pending.sentAt >= RESEND and (attacking or fronting) then
        adapter.Wire.skill(S.pending.slot)
        S.pending.sentAt = now
      end
      return
    end
  end

  if attacking or fronting then
    local index = chooseSlot(slots, now, attacking)
    if index then
      if S.requests[index] then S.requests[index].sent = true end
      adapter.Wire.skill(index)
      S.pending = { slot = index, at = now, sentAt = now }
      if S.mode == "summoned" then S.frontUntil = math.max(S.frontUntil, now + 1.2) end
      return
    end
  end

  if attacking and S.autoUlt and adapter.Game.ultimateReady() and now - lastUlt > 2 then
    adapter.Wire.ult(); lastUlt = now; return
  end

  local punching = (attacking and S.useM1) or (fronting and S.barrage)
  if punching and aim and now - lastM1 >= 0.12 and LP.Character and LP.Character:GetAttribute("M1Ready") ~= false then
    adapter.Wire.m1(aim)
    lastM1 = now
  end
end

-- ---------------------------------------------------------------- actions
function S.summon()
  if not S.owner then return false, "Choose an owner first" end
  if lowHealth() then refuse("Too hurt to come out."); return false, "health below the dismiss threshold" end
  S.target, S.engaged, S.waiting, S.barrage, S.lowHidden = nil, nil, nil, false, false
  if S.mode ~= "summoned" then S.mode = "summoned"; say(S.lines.summon) end
  return true
end

function S.dismiss()
  if not S.owner then return false, "Choose an owner first" end
  S.target, S.engaged, S.waiting, S.barrage, S.frontUntil = nil, nil, nil, false, 0
  table.clear(S.requests)
  S.endCombo("dismissed"); S.verify = nil
  if S.mode ~= "hidden" then S.mode = "hidden"; say(S.lines.dismiss) end
  return true
end

function S.stop()
  S.barrage, S.frontUntil = false, 0
  table.clear(S.requests)
  S.endCombo("stopped"); S.verify = nil
  if S.mode == "attacking" then S.mode, S.target, S.engaged, S.waiting = "summoned", nil, nil, nil end
  return true
end

-- The UI's full release: stand goes back to being an ordinary character.
function S.free(why)
  S.mode, S.target, S.engaged, S.waiting, S.barrage, S.frontUntil = "off", nil, nil, nil, false, 0
  table.clear(S.requests)
  S.endCombo(why or "released"); S.verify = nil
  release(why or "released")
  return true
end

local function pickTarget(query)
  local target, why
  if query and query ~= "" then target, why = findPlayer(query, { [LP] = true, [S.owner] = true })
  else target = nearestToOwner() end
  if not target then return nil, why or "no one in range" end
  if target == S.owner or target == LP then return nil, "not them" end
  if excluded(target) then return nil, "they are on the whitelist" end
  return target
end

function S.attack(query)
  if not S.owner then return false, "Choose an owner first" end
  if lowHealth() then refuse("Too hurt to fight."); return false, "health below the dismiss threshold" end
  local target, why = pickTarget(query)
  if not target then refuse("No target: " .. tostring(why) .. "."); return false, why end
  S.target, S.mode, S.barrage, S.engaged, S.waiting = target, "attacking", false, nil, nil
  S.endCombo("new target"); S.verify = nil
  -- Each stand starts the rotation on its own slot, so a squad opening on one
  -- target does not fire four copies of the same move into the same frame.
  S.rotation, S.pending = (S.squadSlot - 1) % 4 + 1, nil
  S.lastCombo = -math.huge
  say(S.lines.attack)
  return true
end

-- Take them and carry them somewhere. "void" rides them past TSB's own kill
-- plane; "bring" delivers them to the owner. Both are the same measured trick.
--
-- Neither of these acquires a target the way .a does. .a is the hunt: say it
-- bare and it picks the nearest. A carry is a single errand on someone you
-- name, so a bare one only works on whoever is already being fought, and
-- otherwise asks who -- being handed the nearest stranger is not what "bring
-- him here" means. A bring is not a hunt either: it does not take the target
-- over, and the stand goes straight back beside the owner once they are down.
local function carry(kind, query)
  if not S.owner then return false, "Choose an owner first" end
  if lowHealth() then refuse("Too hurt for that."); return false, "health below the dismiss threshold" end
  local target, why
  if query and query ~= "" then target, why = pickTarget(query)
  elseif S.target then target = S.target
  else why = kind == "bring" and "say who to bring" or "say who" end
  if not target then refuse("Who? " .. tostring(why) .. "."); return false, why end
  if kind == "void" then
    if S.mode ~= "attacking" or S.target ~= target then
      S.target, S.mode, S.barrage, S.engaged, S.waiting = target, "attacking", false, nil, nil
      S.rotation, S.pending = (S.squadSlot - 1) % 4 + 1, nil
    end
  elseif S.mode ~= "attacking" and S.mode ~= "summoned" then
    local ok, reason = S.summon()
    if not ok then return false, reason end
  end
  local ok, reason = beginCombo(kind, target)
  if not ok then refuse("Can't take them: " .. tostring(reason) .. ".") end
  return ok, reason
end

function S.bring(query) return carry("bring", query) end
function S.voidDrop(query) return carry("void", query) end

function S.skill(index)
  if not S.owner then return false, "Choose an owner first" end
  if not tsb() then refuse("Skills need The Strongest Battlegrounds."); return false end
  if S.mode ~= "attacking" and S.mode ~= "summoned" then
    local ok, why = S.summon()
    if not ok then return false, why end
  end
  local now = os.clock()
  S.requests[index] = { at = now, untilAt = now + 2 }
  if S.mode == "summoned" then S.frontUntil = math.max(S.frontUntil, now + 1.2) end
  return true
end

function S.toggleBarrage()
  if not S.owner then return false, "Choose an owner first" end
  if S.mode == "attacking" then return false, "already attacking" end
  if S.mode ~= "summoned" then local ok, why = S.summon(); if not ok then return false, why end end
  S.barrage = not S.barrage
  return true
end

function S.toggleDash()
  S.dashSpam = not S.dashSpam
  saveFeat("dashSpam", S.dashSpam)
  if S.controls.dashSpam then S.controls.dashSpam:set(S.dashSpam, true) end
  say(S.dashSpam and "Dashing." or "No more dashing.")
  return true
end

function S.ult()
  local adapter = tsb()
  if not adapter then refuse("Awakening needs The Strongest Battlegrounds."); return false end
  if not adapter.Game.ultimateReady() then refuse("Not ready yet."); return false end
  adapter.Wire.ult(); lastUlt = os.clock()
  return true
end

function S.fling(query)
  if not S.owner then return false, "Choose an owner first" end
  local target, why
  if (not query or query == "") and S.mode == "attacking" and S.target then target = S.target
  else target, why = pickTarget(query) end
  if not target then refuse("No target: " .. tostring(why) .. "."); return false, why end
  local ok, reason = flingNow(target)
  if not ok then refuse("Can't fling: " .. tostring(reason) .. ".") end
  return ok, reason
end

local function refreshSliders()
  local pose = S.poses[S.editing]
  for key, control in pairs(S.sliders) do control:set(pose[key], true) end
  if S.poseInfo then S.poseInfo.Text = POSE_INFO[S.editing] end
end

local function setPose(name, values)
  local pose = S.poses[name]
  for key, value in pairs(values) do
    local range = RANGE[key]
    if range and finite(value) then
      pose[key] = math.clamp(value, range[1], range[2])
      saveFeat("pose." .. name .. "." .. key, pose[key])
    end
  end
  if S.editing == name then refreshSliders() end
end

function S.side(which)
  local values = SIDES[tostring(which or ""):lower()]
  if not values then refuse("Sides: right, left, behind, above."); return false end
  setPose("Idle", values)
  return true
end

-- The attack angle is written straight into the Strike pose, so the latch, the
-- sliders, the preview and the saved config all keep seeing one pose and
-- nothing else. The squad fan is applied on top of it at latch time, because it
-- depends on who else is standing here and must not be saved.
local function applyApproach()
  local a = S.approach
  local t = math.rad(a.angle)
  local yaw = S.facing == "Face away" and a.angle + 180 or a.angle
  setPose("Strike", { x = math.sin(t) * a.radius, y = a.height, z = math.cos(t) * a.radius,
    pitch = 0, yaw = (yaw + 180) % 360 - 180, roll = 0 })
end

function S.setApproach(values, keepPreset)
  for key, value in pairs(values) do
    if finite(value) then
      if key == "angle" then S.approach.angle = (value % 360 + 360) % 360
      elseif key == "radius" then S.approach.radius = math.clamp(value, 0.5, 30)
      elseif key == "height" then S.approach.height = math.clamp(value, -20, 20) end
    end
  end
  for key, value in pairs(S.approach) do saveFeat("approach." .. key, value) end
  if not keepPreset then
    S.approachPreset = "Custom"
    saveFeat("approach.preset", "Custom")
    pcall(function() if S.controls.preset then S.controls.preset:set("Custom", true) end end)
  end
  pcall(function()
    for key, control in pairs(S.angleControls or {}) do
      if S.approach[key] then control:set(S.approach[key], true) end
    end
  end)
  applyApproach()
  return true
end

function S.setFacing(value)
  if not table.find(FACINGS, value) then return false, "Face them or Face away" end
  S.facing = value
  saveFeat("approach.facing", value)
  applyApproach()
  return true
end

-- One word from chat picks a ready-made angle.
function S.angle(which)
  local query = tostring(which or ""):lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
  local name
  for _, candidate in ipairs(APPROACH_NAMES) do
    if candidate:lower() == query then name = candidate end
  end
  if not name then
    for _, candidate in ipairs(APPROACH_NAMES) do
      if candidate ~= "Custom" and candidate:lower():sub(1, #query) == query and query ~= "" then name = name or candidate end
    end
  end
  local preset = name and APPROACH_PRESETS[name]
  if not preset then
    refuse("Angles: behind, behind left, behind right, left flank, right flank, in front, above, below, point blank.")
    return false, "unknown angle"
  end
  S.approachPreset = name
  saveFeat("approach.preset", name)
  pcall(function() if S.controls.preset then S.controls.preset:set(name, true) end end)
  S.setApproach(preset, true)
  return true
end

-- A saved preset owns the Strike pose; a hand-tuned one ("Custom") is left
-- exactly as it was saved, so nobody's tuning is overwritten on load.
if S.approachPreset ~= "Custom" then applyApproach() end

-- ---------------------------------------------------------------- commands
-- One table drives the chat parser, the tab's list and the in-chat summary.
local COMMANDS, LOOKUP = {}, {}
local function command(names, args, desc, fn)
  local entry = { names = names, args = args, desc = desc, fn = fn }
  COMMANDS[#COMMANDS + 1] = entry
  for _, name in ipairs(names) do LOOKUP[name] = entry end
end
command({ "s", "summon" }, "", "summon the stand beside you", function() S.summon() end)
command({ "d", "dismiss" }, "", "hide the stand in the void under you", function() S.dismiss() end)
command({ "a", "attack" }, "[name]", "hunt a player from behind until you say stop; nearest to you if blank", function(rest) S.attack(rest) end)
command({ "stop" }, "", "stop attacking or punching and come back", function() S.stop() end)
command({ "1", "2", "3", "4" }, "", "use that skill now, on the target or in front of you", function(_, word) S.skill(tonumber(word)) end)
command({ "m1" }, "", "punch barrage in front of you; say it again to stop", function() S.toggleBarrage() end)
command({ "dash" }, "", "turn dash spam on or off", function() S.toggleDash() end)
command({ "ult" }, "", "awaken when the bar is full", function() S.ult() end)
command({ "b", "bring" }, "name", "take hold of that player and carry them to you", function(rest) S.bring(rest) end)
command({ "v", "void" }, "name", "take hold of that player and carry them under the kill plane", function(rest) S.voidDrop(rest) end)
command({ "angle" }, "behind | left flank | in front | above | ...", "the angle the stand strikes from", function(rest) S.angle(rest) end)
command({ "squad" }, "[name, name]", "other stands to fan out with; blank clears the list", function(rest) S.setSquad(rest) end)
command({ "fling" }, "[name]", "one Rep Root fling; the current target if blank", function(rest) S.fling(rest) end)
command({ "pose" }, "right | left | behind | above", "where the stand waits beside you", function(rest) S.side(rest) end)
command({ "say" }, "text", "make the stand talk", function(rest) say(rest, true) end)
command({ "cmds" }, "", "the stand lists these in chat", function()
  local p = S.prefix
  say(string.format("%ss %sd %sa name %sstop %s1-4 %sm1 %sb name %sv name %sangle where %sdash %sult %spose side %ssay text",
    p, p, p, p, p, p, p, p, p, p, p, p, p), true)
end)
S.COMMANDS = COMMANDS

-- The roster the fan is computed from. Typed as names, kept as typed, matched
-- case-insensitively against whoever is actually in the server.
function S.setSquad(value)
  value = tostring(value or ""):gsub("[^%w_,@%s]", ""):sub(1, 200)
  S.squadNames = value
  saveFeat("squad.names", value)
  pcall(function() if S.controls.squad then S.controls.squad:set(value) end end)
  refreshSquad()
  return true
end

function S.handle(message, fromUI)
  if not S.listen and not fromUI then return false end
  message = tostring(message or ""):match("^%s*(.-)%s*$")
  local prefix = S.prefix or ""
  if prefix ~= "" then
    if message:sub(1, #prefix):lower() ~= prefix:lower() then return false end
    message = message:sub(#prefix + 1)
  end
  local word, rest = message:match("^(%S+)%s*(.-)$")
  if not word then return false end
  word = word:lower()
  local entry = LOOKUP[word]
  if not entry then return false end
  S.lastCommand = prefix .. word .. (rest ~= "" and (" " .. rest) or "")
  local ok, err = pcall(entry.fn, rest, word)
  if not ok then L.fault("stand.command", err) end
  return ok
end

-- Both chat paths deliver the owner's message to this client in the same frame
-- (measured), so each message is handled once. The window is far shorter than
-- anyone can type and send the same command twice.
local recent = {}
local function heard(player, message)
  if not player or player == LP or player ~= S.owner or type(message) ~= "string" then return end
  local key = player.UserId .. "\0" .. message
  local now = os.clock()
  if recent[key] and now - recent[key] < 0.25 then return end
  recent[key] = now
  for k, at in pairs(recent) do if now - at > 5 then recent[k] = nil end end
  S.handle(message)
end
L.hold(TCS.MessageReceived:Connect(function(msg)
  if msg.Status ~= Enum.TextChatMessageStatus.Success then return end
  local source = msg.TextSource
  if source then heard(Players:GetPlayerByUserId(source.UserId), msg.Text) end
end))
local function hookChat(player)
  L.hold(player.Chatted:Connect(function(message) heard(player, message) end))
end
for _, player in ipairs(Players:GetPlayers()) do hookChat(player) end

-- ---------------------------------------------------------------- owner
local ownerItems = { "None" }
local function refreshOwnerItems()
  table.clear(ownerItems)
  ownerItems[1] = "None"
  local names = {}
  for _, p in ipairs(Players:GetPlayers()) do if p ~= LP then names[#names + 1] = p.Name end end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  for _, name in ipairs(names) do ownerItems[#ownerItems + 1] = name end
end

local function refreshCommands()
  local label = S.commandLabel
  if not label then return end
  if not S.owner then
    label.Text = S.ownerName ~= "" and (S.ownerName .. " is not in this server. Their commands appear here when they join.")
      or "Choose an owner above. Their chat commands appear here."
    return
  end
  local p = S.prefix
  local lines = { "@" .. S.owner.Name .. " types these in chat" .. (p ~= "" and "" or " (no prefix)") .. ":" }
  for _, entry in ipairs(COMMANDS) do
    local names = {}
    for _, name in ipairs(entry.names) do names[#names + 1] = p .. name end
    local usage = table.concat(names, "  ") .. (entry.args ~= "" and ("  " .. entry.args) or "")
    lines[#lines + 1] = usage .. "   -   " .. entry.desc
  end
  label.Text = table.concat(lines, "\n")
end

function S.setOwner(name)
  name = tostring(name or "")
  if name == "None" then name = "" end
  local player = name ~= "" and Players:FindFirstChild(name) or nil
  if player and not player:IsA("Player") then player = nil end
  if player == LP then player = nil; name = "" end
  if player ~= S.owner or name ~= S.ownerName then S.free("owner changed"); S.lastOwnerFrame = nil end
  S.owner, S.ownerName = player, name
  saveFeat("owner", name)
  refreshCommands()
  return true
end

function S.setPrefix(value)
  value = tostring(value or ""):gsub("%s", ""):sub(1, 3)
  S.prefix = value
  saveFeat("prefix", value)
  if S.controls.prefix then S.controls.prefix:set(value) end
  refreshCommands()
end

L.hold(Players.PlayerAdded:Connect(function(player)
  hookChat(player)
  refreshOwnerItems()
  if S.ownerName ~= "" and player.Name == S.ownerName then S.owner = player; refreshCommands() end
end))
L.hold(Players.PlayerRemoving:Connect(function(player)
  if player == S.owner then
    S.free("owner left"); S.owner = nil
    task.defer(refreshCommands)
  elseif player == S.target then
    S.mode, S.target, S.engaged, S.waiting = "summoned", nil, nil, nil
  end
  task.defer(refreshOwnerItems)
end))
refreshOwnerItems()
do
  local saved = S.ownerName ~= "" and Players:FindFirstChild(S.ownerName)
  if saved and saved ~= LP and saved:IsA("Player") then S.owner = saved end
end

-- ---------------------------------------------------------------- lifecycle
-- Every Rep Root transaction owns the binding while it runs, and records the
-- body's position as "home" when it starts. Hand the body back first, standing
-- beside the owner, so home is never the raw pose coordinates under the map.
local baseRunOne = R.runOne
function R.runOne(name)
  if S.active then release("Rep Root fling started") end
  S.pauseUntil = os.clock() + 0.5
  return baseRunOne(name)
end
local baseBeginQueue = R.beginQueue
if baseBeginQueue then
  function R.beginQueue(name)
    if S.active then release("Targets loop started") end
    S.pauseUntil = os.clock() + 0.5
    return baseBeginQueue(name)
  end
end

L.bind("GiorgioStandCamera", Enum.RenderPriority.Camera.Value - 1, function()
  if L.live() then pcall(aimCamera) end
end)

L.hold(RS.Heartbeat:Connect(function()
  if not L.live() then return end
  local ok, err = pcall(step)
  if not ok then L.fault("stand.step", err); release("error") end
  ok, err = pcall(combat)
  if not ok then L.fault("stand.combat", err) end
end))

-- Where the stand really is. Our own body sits at the raw pose coordinates, so
-- without this the operator never sees their stand beside the owner.
local marker
-- ... and where it is going to stand on the target. The angle rig is drawn on a
-- live body, so turning the dial moves a real mark on a real player: our own
-- slot solid, every other stand's slot a ghost, and a ring for the scale. This
-- is the only way to see, before committing, that no two stands in the fan are
-- inside each other's swing.
local rig = { parts = {}, on = false }
local RING_DOTS = 16
local function rigPart(key, size, transparency, colour)
  local part = rig.parts[key]
  if not part or not part.Parent then
    part = L.mk("Part", { Name = "GiorgioStandAngle", Anchored = true, CanCollide = false, CanTouch = false,
      CanQuery = false, Material = Enum.Material.Neon, Parent = workspace })
    L.own(part)
    rig.parts[key] = part
  end
  part.Size = size
  part.Transparency = transparency
  part.Color = colour or T.c.accent
  return part
end

local function clearRig()
  if not rig.on then return end
  for key, part in pairs(rig.parts) do
    pcall(function() part:Destroy() end)
    rig.parts[key] = nil
  end
  rig.on = false
end

-- The body the angles are drawn on: whoever is being fought, else the player
-- named for the preview, else the nearest one to the owner.
local function previewBody()
  if S.mode == "attacking" and S.target then
    local _, _, root = body(S.target)
    if root then return root end
  end
  if S.previewWho ~= "" then
    local named = Players:FindFirstChild(S.previewWho)
    if named and named ~= LP then
      local _, _, root = body(named)
      if root then return root end
    end
  end
  local near = nearestToOwner()
  if near then return (select(3, body(near))) end
  return nil
end

local function drawRig()
  if not (S.previewAngles and S.mode ~= "off") then clearRig(); return end
  local targetRoot = previewBody()
  if not targetRoot then clearRig(); return end
  rig.on = true
  local frame = targetRoot.CFrame
  local a = S.approach
  -- the scale ring, at the chosen radius and height
  for dot = 1, RING_DOTS do
    local t = math.rad((dot - 1) * 360 / RING_DOTS)
    local part = rigPart("ring" .. dot, Vector3.new(0.35, 0.35, 0.35), 0.75, T.c.accent)
    part.CFrame = frame * CFrame.new(math.sin(t) * a.radius, a.height, math.cos(t) * a.radius)
  end
  -- one block per stand in the fan; ours is the solid one
  local count = math.max(S.squadCount, 1)
  for slot = 1, count do
    local delta = spread(slot, count)
    local pose = CFrame.Angles(0, math.rad(delta), 0) * poseFrame("Strike")
    local mine = slot == S.squadSlot
    local block = rigPart("slot" .. slot, Vector3.new(1.6, 3, 1), mine and 0.35 or 0.8, T.c.accent)
    block.CFrame = frame * pose
    -- a nose on each, so the facing is readable at a glance
    local nose = rigPart("nose" .. slot, Vector3.new(0.3, 0.3, 1.6), mine and 0.35 or 0.85, T.c.accent)
    nose.CFrame = frame * pose * CFrame.new(0, 0, -1.3)
  end
  for slot = count + 1, 8 do
    for _, key in ipairs({ "slot" .. slot, "nose" .. slot }) do
      local part = rig.parts[key]
      if part then pcall(function() part:Destroy() end); rig.parts[key] = nil end
    end
  end
end

L.hold(RS.RenderStepped:Connect(function()
  if not L.live() then return end
  local frame
  if S.preview then
    if S.active and S.anchorRoot and S.lastWorld then frame = S.lastWorld
    elseif not S.active and S.owner then
      local _, _, ownerRoot = body(S.owner)
      if ownerRoot then frame = ownerRoot.CFrame * localFrame(ownerRoot, ownerRoot.CFrame, S.editing, 0) end
    end
  end
  if frame then
    if not marker then
      marker = L.mk("Part", { Name = "GiorgioStandMarker", Anchored = true, CanCollide = false, CanTouch = false,
        CanQuery = false, Transparency = 0.7, Color = T.c.accent, Material = Enum.Material.Neon,
        Size = Vector3.new(2, 2, 1), Parent = workspace })
      L.own(marker)
    end
    marker.CFrame = frame
  elseif marker then
    marker:Destroy(); marker = nil
  end
  local ok, err = pcall(drawRig)
  if not ok then L.fault("stand.preview", err); S.previewAngles = false end
end))

L.hold(UIS.InputBegan:Connect(function(input, processed)
  if not L.live() or processed or UIS:GetFocusedTextBox() then return end
  if input.KeyCode == Enum.KeyCode.Backspace and S.mode ~= "off" then S.free("emergency stop") end
end))
L.cleanup(function() S.free("unloaded") end, 140)

-- ---------------------------------------------------------------- the tab
function S.build(win)
  S.controls, S.sliders = {}, {}
  local page = win:tab({ name = "Stand", chrome = "compass",
    desc = "A TSB stand your owner commands from chat. Every latch is Rep Root." }).body
  C.ctx("stand")
  local tiles = C.tiles(page, { { key = "owner", label = "Owner", value = "None" },
    { key = "mode", label = "Stand", value = "Off" }, { key = "latch", label = "Latch", value = "Free" },
    { key = "kills", label = "Kills", value = "0" }, { key = "carry", label = "Carry", value = "idle" } })

  C.section(page, "owner")
  S.controls.owner = C.dropdown(page, { id = "stand.owner", persist = false, text = "Owner",
    items = ownerItems, default = S.ownerName ~= "" and S.ownerName or "None",
    callback = function(v) return S.setOwner(v) end })
  S.controls.prefix = C.input(page, { id = "stand.prefix", persist = false, text = "Command prefix",
    desc = "Typed before every command; press Enter to apply. Leave blank for bare words.", placeholder = "none",
    default = S.prefix, callback = function(v) S.setPrefix(v) end })
  C.toggle(page, { id = "stand.listen", text = "Take orders from the owner",
    desc = "Only the owner's chat is read. Backspace frees the stand.", default = S.listen,
    callback = function(v) S.listen = v == true end })
  local function run(fn, ...)
    local ok, why = fn(...)
    if ok == false and why then L.Toast.warn("Stand", tostring(why)) end
  end
  C.actions(page, {
    { text = "Summon", primary = true, callback = function() run(S.summon) end },
    { text = "Dismiss", callback = function() run(S.dismiss) end },
    { text = "Stop", callback = function() run(S.stop) end },
    { text = "Free stand", callback = function() run(S.free, "freed from the tab") end },
  })

  C.section(page, "commands")
  S.commandLabel = C.paragraph(page, ""):FindFirstChildWhichIsA("TextLabel", true)
  refreshCommands()

  C.section(page, "pose")
  C.dropdown(page, { id = "stand.editing", persist = false, text = "Editing pose", items = POSE_NAMES,
    default = S.editing, callback = function(v) S.editing = v; refreshSliders() end })
  S.poseInfo = C.paragraph(page, POSE_INFO[S.editing]):FindFirstChildWhichIsA("TextLabel", true)
  local labels = {
    x = { "Offset X", "Anchor-local left / right" }, y = { "Offset Y", "Anchor-local down / up" },
    z = { "Offset Z", "Anchor-local forward (-) / behind (+)" }, pitch = { "Pitch", "X rotation in degrees" },
    yaw = { "Yaw", "Y rotation in degrees; 180 turns to face the anchor" }, roll = { "Roll", "Z rotation in degrees" },
  }
  for _, key in ipairs(POSE_KEYS) do
    local range = RANGE[key]
    S.sliders[key] = C.slider(page, { id = "stand.edit." .. key, persist = false, text = labels[key][1],
      desc = labels[key][2], min = range[1], max = range[2], step = (key == "x" or key == "y" or key == "z") and 0.01 or 0.1,
      default = S.poses[S.editing][key], callback = function(v)
        if not finite(v) then return false end
        setPose(S.editing, { [key] = v })
      end })
  end
  C.actions(page, {
    { text = "Reset pose", callback = function() setPose(S.editing, POSE_DEFAULTS[S.editing]) end },
    { text = "Idle right", callback = function() S.side("right") end },
    { text = "Idle left", callback = function() S.side("left") end },
    { text = "Idle behind", callback = function() S.side("behind") end },
    { text = "Idle above", callback = function() S.side("above") end },
  })
  C.dropdown(page, { id = "stand.stance", text = "Idle pose", items = STANCES, default = S.stance,
    callback = function(v) S.stance = v end })
  C.paragraph(page, "The game's own emote stances, every one load-tested on this rig. Perfect Concentration is the default: head bowed, still, the way a stand waits. Fighting stance and Calm float are the old two -- the first is TSB's idle guard, which is really just breathing with the arms down. The pose is held every frame and the humanoid is pinned to Running, so a move can no longer leave it standing wrong afterwards.")
  C.input(page, { id = "stand.stanceCustom", text = "Custom animation ID", desc = "Used when the animation is Custom",
    placeholder = "rbxassetid", default = S.stanceCustom, callback = function(v) S.stanceCustom = tostring(v or "") end })
  C.slider(page, { id = "stand.float", text = "Float motion", desc = "Studs of gentle bob; 0 holds still",
    min = 0, max = 2, step = 0.05, default = S.float, callback = function(v) if finite(v) then S.float = v end end })
  C.toggle(page, { id = "stand.upright", text = "Keep upright", desc = "Ignores the anchor's tilt and ragdolls; keeps its heading",
    default = S.upright, callback = function(v) S.upright = v == true end })
  C.toggle(page, { id = "stand.platformStand", text = "PlatformStand", desc = "Stiff hover. Off keeps TSB's own idle animation and the pose above; on stops both",
    default = S.hover, callback = function(v)
      S.hover = v == true
      if not S.hover and S.active and latch.hum and latch.hum.Parent then latch.hum.PlatformStand = latch.platform end
    end })
  C.toggle(page, { id = "stand.preview", text = "Show where others see it", desc = "Local marker at the stand's real position, or at the pose you are editing",
    default = S.preview, callback = function(v) S.preview = v == true end })
  C.toggle(page, { id = "stand.camera", text = "Camera on the owner", desc = "Your own body sits far from the stand; this keeps your view on the owner",
    default = S.camera, callback = function(v) S.camera = v == true end })

  C.section(page, "attack angle")
  C.paragraph(page, "Where the stand stands on its target. 0 is directly behind them, 90 their right, 180 in front, 270 their left; it turns to face them from wherever you put it. Turn on the preview below and the angle is drawn on a live body while you move the dial.")
  S.angleControls = {}
  S.controls.preset = C.dropdown(page, { id = "stand.approachPreset", text = "Ready angle", items = APPROACH_NAMES,
    default = S.approachPreset, callback = function(v)
      if v == "Custom" then S.approachPreset = "Custom"; return end
      return S.angle(v)
    end })
  S.angleControls.angle = C.slider(page, { id = "stand.approach.angle", persist = false, text = "Angle around them",
    desc = "Degrees clockwise from directly behind", min = 0, max = 359, step = 1, default = S.approach.angle,
    callback = function(v) if not finite(v) then return false end; S.setApproach({ angle = v }) end })
  S.angleControls.radius = C.slider(page, { id = "stand.approach.radius", persist = false, text = "Distance from them",
    desc = "Studs", min = 0.5, max = 30, step = 0.1, default = S.approach.radius,
    callback = function(v) if not finite(v) then return false end; S.setApproach({ radius = v }) end })
  S.angleControls.height = C.slider(page, { id = "stand.approach.height", persist = false, text = "Height on them",
    desc = "Studs above or below their root", min = -20, max = 20, step = 0.1, default = S.approach.height,
    callback = function(v) if not finite(v) then return false end; S.setApproach({ height = v }) end })
  C.dropdown(page, { id = "stand.approach.facing", text = "Facing", items = FACINGS, default = S.facing,
    callback = function(v) return S.setFacing(v) end })
  C.toggle(page, { id = "stand.previewAngles", text = "Live angle preview",
    desc = "Draws every stand's slot on the target while you tune: yours solid, the rest ghosts, with a ring for the distance",
    default = S.previewAngles, callback = function(v) S.previewAngles = v == true end })
  C.input(page, { id = "stand.previewWho", text = "Preview on", desc = "A player to draw the angles on while nothing is being attacked; blank uses the nearest",
    placeholder = "nearest", default = S.previewWho, callback = function(v) S.previewWho = tostring(v or "") end })

  C.section(page, "squad")
  C.paragraph(page, "Several stands on one target. Each one sorts this list by user id, finds itself and takes that slot of the fan, so every stand computes the same layout with no messages between them -- a stand that joins, dies or leaves just re-packs it. Squad members are never targeted, and each one starts the skill rotation on its own slot so they do not all fire the same move into the same frame.")
  S.controls.squad = C.input(page, { id = "stand.squad.names", text = "Other stands",
    desc = "Account names, comma separated. This account is always in the fan.", placeholder = "none",
    default = S.squadNames, callback = function(v) S.setSquad(v) end })
  C.toggle(page, { id = "stand.squad.on", text = "Fan out", default = S.squadOn,
    callback = function(v) S.squadOn = v == true; refreshSquad() end })
  C.slider(page, { id = "stand.squad.arc", text = "Fan width", desc = "Degrees the stands are spread across, centred on the angle above",
    min = 20, max = 340, step = 5, default = S.squadArc, callback = function(v) if finite(v) then S.squadArc = v end end })
  C.slider(page, { id = "stand.squad.gap", text = "Smallest gap between stands", desc = "The fan widens rather than let two stands share a swing",
    min = 10, max = 180, step = 5, default = S.squadGap, callback = function(v) if finite(v) then S.squadGap = v end end })

  C.section(page, "the carry")
  C.paragraph(page, "Measured on the rig on 2026-09-24: while a grab holds, the victim rides the stand's replicated position. So the stand takes hold and then moves -- down past The Strongest Battlegrounds' own -500 kill plane, which their client enforces on itself, or in to the owner. The descent is paced across the hold the move has been watched to have, because snapping the whole distance leaves them behind and they are simply put back on the map. It learns which moves grab by watching which ones take hold, and remembers them.")
  C.toggle(page, { id = "stand.combo", text = "Carry to the void while attacking",
    desc = "Opens with a grab whenever one is ready, rides them under the kill plane, and takes them again if they survive",
    default = S.comboOn, callback = function(v) S.comboOn = v == true end })
  C.slider(page, { id = "stand.comboTries", text = "Attempts per target", min = 1, max = 8, step = 1, default = S.comboTries,
    callback = function(v) if finite(v) then S.comboTries = v end end })
  C.slider(page, { id = "stand.comboEvery", text = "Seconds between carries", min = 0, max = 60, step = 0.5, default = S.comboEvery,
    callback = function(v) if finite(v) then S.comboEvery = v end end })
  C.slider(page, { id = "stand.voidMargin", text = "Studs past the kill plane", desc = "How far below -500 to aim; the rig killed at -546",
    min = 20, max = 400, step = 5, default = S.voidMargin, callback = function(v) if finite(v) then S.voidMargin = v end end })
  C.toggle(page, { id = "stand.carryAdapt", text = "Pace the drop to the move",
    desc = "Spreads the descent across the hold this move has been measured to have; off uses the fixed rate below",
    default = S.carryAdapt, callback = function(v) S.carryAdapt = v == true end })
  C.slider(page, { id = "stand.carryRate", text = "Descent rate (studs/second)", desc = "Used when the pacing above is off; the carry tracked ~900/s on the rig",
    min = CARRY_RATE[1], max = CARRY_RATE[2], step = 10, default = S.carryRate,
    callback = function(v) if finite(v) then S.carryRate = v end end })
  C.slider(page, { id = "stand.voidLinger", text = "Seconds to wait down there", desc = "Held after the grab lets go, so the release happens where the stand is",
    min = 0, max = 3, step = 0.05, default = S.voidLinger, callback = function(v) if finite(v) then S.voidLinger = v end end })
  C.slider(page, { id = "stand.bringDistance", text = "Delivery distance",
    desc = "Studs in front of the owner a brought player is dropped. The grab's finisher hurts and knocks down whatever is near the stand, so this is the owner's clearance from their own delivery -- the bearing is fixed when the grab lands, so turning to watch does not swing it around them",
    min = 4, max = 40, step = 0.5, default = -S.poses.Bring.z,
    callback = function(v) if not finite(v) then return false end; setPose("Bring", { z = -v }) end })
  C.actions(page, {
    { text = "Forget learned grabs", callback = function()
      S.grabMoves, S.grabMisses = {}, {}
      saveFeat("grabMoves", {})
      L.Toast.warn("Stand", "Grab moves forgotten; it will learn them again.")
    end },
  })

  C.section(page, "the deep hide")
  C.paragraph(page, "Dismissed, or waiting out a respawn, the stand goes further than under the owner's feet. It needs the same void immunity the carry does; without it the stand quietly stays above -450 rather than killing itself.")
  C.toggle(page, { id = "stand.hideDeep", text = "Hide deep", default = S.hideDeep,
    callback = function(v) S.hideDeep = v == true end })
  C.slider(page, { id = "stand.hideDepth", text = "Depth below the owner", min = 60, max = 8000, step = 20, default = S.hideDepth,
    callback = function(v) if finite(v) then S.hideDepth = v end end })
  C.slider(page, { id = "stand.hideAway", text = "Distance behind the owner", min = 0, max = 2000, step = 10, default = S.hideAway,
    callback = function(v) if finite(v) then S.hideAway = v end end })

  C.section(page, "combat")
  if not (R.TSB and R.TSB.supported()) then
    C.paragraph(page, "Summon, dismiss, poses and attack latches work anywhere. Skills, M1, dashes and awakening fire through The Strongest Battlegrounds' own input remote, so they only run there.")
  end
  C.paragraph(page, "While attacking the stand rotates skills 1, 2, 3, 4, re-firing each the moment its cooldown ends, and fills every gap with M1s at the game's own pace. A kill sends it to the void until the target respawns.")
  C.toggle(page, { id = "stand.useSkills", text = "Rotate skills", default = S.useSkills,
    callback = function(v) S.useSkills = v == true end })
  C.toggle(page, { id = "stand.useM1", text = "M1 between skills", default = S.useM1,
    callback = function(v) S.useM1 = v == true end })
  S.controls.dashSpam = C.toggle(page, { id = "stand.dashSpam", text = "Dash spam", desc = "Forward dashes while attacking or in the barrage, as often as the game allows",
    default = S.dashSpam, callback = function(v) S.dashSpam = v == true end })
  C.slider(page, { id = "stand.dashGap", text = "Seconds between dashes", min = 0.2, max = 3, step = 0.05, default = S.dashGap,
    callback = function(v) if finite(v) then S.dashGap = v end end })
  C.toggle(page, { id = "stand.autoUlt", text = "Awaken automatically", desc = "Fires the awakening when the bar is full during an attack",
    default = S.autoUlt, callback = function(v) S.autoUlt = v == true end })
  C.toggle(page, { id = "stand.waitShield", text = "Wait out spawn protection", desc = "After a respawn, stay in the void until the target's ForceField drops",
    default = S.waitShield, callback = function(v) S.waitShield = v == true end })
  C.slider(page, { id = "stand.lowHP", text = "Hide below health %", desc = "The stand dismisses itself here and refuses to fight until healed; 0 turns it off",
    min = 0, max = 90, step = 1, default = S.lowHP, callback = function(v) if finite(v) then S.lowHP = v end end })

  C.section(page, "fling assist")
  C.paragraph(page, "Optional, off by default. Hands the target to Giorgio's Rep Root fling (your Rep Root drive and void-aim settings) for one short burst, then comes straight back and restores your Rep Root settings. Measured in TSB on 2026-09-23: the handover works, but the Rep Root fling itself moved the target 0 studs/s, with or without the stand, so for now this adds nothing in TSB.")
  C.toggle(page, { id = "stand.flingAssist", text = "Fling assist", default = S.flingAssist,
    callback = function(v) S.flingAssist = v == true end })
  C.slider(page, { id = "stand.flingBelow", text = "Fling when target health is below %", desc = "Also flings a knocked-down target once every skill is cooling",
    min = 1, max = 100, step = 1, default = S.flingBelow, callback = function(v) if finite(v) then S.flingBelow = v end end })
  C.slider(page, { id = "stand.flingEvery", text = "Seconds between flings", min = 2, max = 60, step = 0.5, default = S.flingEvery,
    callback = function(v) if finite(v) then S.flingEvery = v end end })
  C.slider(page, { id = "stand.flingDrive", text = "Fling drive (seconds)", min = 0.3, max = 6, step = 0.05, default = S.flingDrive,
    callback = function(v) if finite(v) then S.flingDrive = v end end })

  C.section(page, "voice")
  C.toggle(page, { id = "stand.speak", text = "Stand speaks", desc = "Short replies in chat; say still works when this is off",
    default = S.speak, callback = function(v) S.speak = v == true end })
  for _, entry in ipairs({ { "summon", "Summon line" }, { "dismiss", "Dismiss line" }, { "attack", "Attack line" },
    { "done", "Kill line" }, { "carry", "Carry line" }, { "bring", "Delivery line" } }) do
    C.input(page, { id = "stand.line." .. entry[1], text = entry[2], default = S.lines[entry[1]],
      callback = function(v) S.lines[entry[1]] = tostring(v or "") end })
  end

  C.section(page, "status")
  local statusFrame = C.paragraph(page, "Idle.")
  local status = statusFrame:FindFirstChildWhichIsA("TextLabel", true)
  local modes = { off = "Off", summoned = "Summoned", hidden = "Hidden", attacking = "Attacking" }
  local acc = 0
  local conn
  conn = RS.Heartbeat:Connect(function(dt)
    if not statusFrame.Parent or not L.live() then conn:Disconnect(); return end
    acc += dt; if acc < 0.2 then return end; acc = 0
    tiles:set("owner", S.owner and S.owner.Name or (S.ownerName ~= "" and "Away" or "None"))
    tiles:set("mode", S.flingBusy and "Flinging" or (modes[S.mode] or S.mode))
    tiles:set("latch", S.active and (S.pose or "On") or (S.blocked and "Paused" or "Free"))
    tiles:set("kills", tostring(S.kills))
    tiles:set("carry", S.combo and (S.comboState or "on") or (S.squadCount > 1 and ("slot " .. S.squadSlot .. "/" .. S.squadCount) or "idle"))
    local lines = {}
    lines[#lines + 1] = "Owner: " .. (S.owner and ("@" .. S.owner.Name) or (S.ownerName ~= "" and (S.ownerName .. " (not in server)") or "none"))
    lines[#lines + 1] = "Stand: " .. (modes[S.mode] or S.mode)
      .. (S.mode == "attacking" and S.target and (" @" .. S.target.Name) or "")
      .. (S.waiting and ("  |  " .. S.waiting) or "")
      .. (S.barrage and "  |  barrage" or "") .. (S.dashSpam and "  |  dash spam" or "")
    lines[#lines + 1] = "Latch: " .. (S.active and (S.anchorRoot and ("PhysicsRepRootPart -> " .. (S.anchorRoot.Parent and S.anchorRoot.Parent.Name or "?") .. ", pose " .. tostring(S.pose)) or "holding in the void (owner is down)") or "free")
    lines[#lines + 1] = "Skills: next " .. S.rotation .. (S.pending and ("  |  sending " .. S.pending.slot) or "")
      .. (S.gate and ("  |  holding: " .. S.gate) or "")
    lines[#lines + 1] = string.format("Angle: %s  %.0f deg, %.1f studs, %+.1f up  |  %s", S.approachPreset,
      S.approach.angle, S.approach.radius, S.approach.height, S.facing)
    lines[#lines + 1] = "Squad: slot " .. S.squadSlot .. " of " .. S.squadCount
      .. (S.squadCount > 1 and string.format("  |  my share %+.0f deg", spread(S.squadSlot, S.squadCount)) or "  |  alone")
    local learned = {}
    for name, hold in pairs(S.grabMoves) do
      if type(hold) == "number" then learned[#learned + 1] = string.format("%s %.2fs", name, hold) end
    end
    table.sort(learned)
    lines[#lines + 1] = "Carry: " .. (S.combo and (S.comboState .. " @" .. S.combo.target.Name
        .. (S.combo.kind == "void" and string.format("  |  %.0f / %.0f studs down", S.combo.depth or 0, S.combo.need or 0) or "")
        .. "  |  try " .. S.combo.tries)
      or (S.verify and "checking the drop" or "idle"))
      .. "  |  carried " .. S.carried .. "  |  void " .. (S.voidReady and "armed" or "not armed")
    lines[#lines + 1] = "Grabs known: " .. (#learned > 0 and table.concat(learned, ", ") or "none yet")
    if S.blocked then lines[#lines + 1] = "Waiting: " .. S.blocked end
    lines[#lines + 1] = "Last command: " .. S.lastCommand
    status.Text = table.concat(lines, "\n")
  end)
  L.hold(conn)
end

end
