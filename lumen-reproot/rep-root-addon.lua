-- Dedicated pages built entirely with the supplied Lumen framework.
local L = getgenv().LUMEN
local C, T, M, Hub = L.C, L.T, L.Motion, L.Hub
local K, Players, LP = L.Combat, L.Players, L.LP
local R = { repRoot=true, fling=true, holdLimit=120, workerActive=false,
  targetName="", controls={}, peak=0, error=0, tuneSerial=0, preview=true,
  POWER_LIMIT=1e18, loopMode="Loop target", turnDuration=1.2, followCamera=true, voidGuard=true,
  voidAim=true, voidRoute=nil, faceTarget=true, facingYaw=nil }
L.RepRoot = R
R.settings = {x=0,y=0,z=0,pitch=-90,yaw=0,roll=0,variant="Lumen maximum"}
local Presets = {
  {name="Lumen original",tag="REFERENCE",desc="The supplied Rep-root drive at the current target position, with a pitched root, aimed thrust and alternating spin.",
    x=0,y=0,z=0,pitch=-90,yaw=0,roll=0,power=4.5e8,spin=9e8,lift=0.55},
  {name="Lumen maximum",tag="DEFAULT / FINITE CEILING",desc="1e18 linear and angular input: the tested finite range, with a persistent target loop. Solver saturation still limits actual transfer.",
    x=0,y=0,z=0,pitch=-90,yaw=0,roll=0,power=1e18,spin=1e18,lift=0.55},
  {name="Rocket burst",tag="0.30 SECOND DRIVE",desc="Lumen's Rep-root burst, mounted three studs below the target with upward thrust.",
    x=0,y=-3,z=0,pitch=-90,yaw=0,roll=0,power=4.5e8,spin=9e8,lift=1},
  {name="Helix drive",tag="ROTATING DIRECTION",desc="The same binding and recovery; rotates the drive direction to sample more angles.",
    x=0,y=-2.5,z=0,pitch=-90,yaw=0,roll=0,power=4.5e8,spin=9e8,lift=0.4},
  {name="Side mount",tag="LATERAL GEOMETRY",desc="Moves the mount to the target's side. Every angle and offset remains editable.",
    x=0.8,y=0,z=0,pitch=0,yaw=90,roll=0,power=4.5e8,spin=9e8,lift=0.2},
  {name="Centre workshop",tag="ANGLE EDITING",desc="Upright, centred geometry. Turn Fling off to work on the mount without a fling drive.",
    x=0,y=0,z=0,pitch=0,yaw=0,roll=0,power=4.5e8,spin=9e8,lift=0.55},
}
R.presets=Presets
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function announce(title,body) L.Toast.info(title,body); L.note("reproot",title..": "..body) end
local function sync()
  for key,control in pairs(R.controls) do
    local value = R.settings[key]
    if value == nil then value = K.cfg[key] end
    if value == nil then value = R[key] end
    if value ~= nil and control.set then
      control:set(value,true)
      if L.Cfg.feat("reproot."..key)~=value then L.Cfg.setFeat("reproot."..key,value) end
    end
  end
  if L.Cfg.feat("reproot.variant")~=R.settings.variant then L.Cfg.setFeat("reproot.variant",R.settings.variant) end
end
function R.setNoclip(value)
  local ok,why=L.Universal.setNoclip(value==true)
  R.noclip=L.Universal.want.noclip
  return ok,why
end
function R.setAutoSave(value)
  local ok=L.Cfg.setAutoSave(value)
  if R.controls.autoSave then R.controls.autoSave:set(L.Cfg.data.autoSave,true) end
  if not ok then L.Toast.warn("Save failed","The setting changed for this session, but could not be written to disk.") end
  return true
end
function R.saveConfig()
  local ok=L.Cfg.flush()
  if ok then L.Toast.ok("Settings saved","Your current setup is saved.")
  else L.Toast.warn("Save failed","Your current settings are still in memory. Try Save now again.") end
  return ok
end
local function studioTarget()
  if R.controls.targetName then R.targetName=R.controls.targetName:get() end
  local query=R.targetName:lower()
  if query=="" then return nil end
  for _,p in ipairs(Players:GetPlayers()) do if p~=LP and p.Name:lower()==query then return p end end
  local found
  for _,p in ipairs(Players:GetPlayers()) do
    if p~=LP and (p.Name:lower():sub(1,#query)==query or p.DisplayName:lower():sub(1,#query)==query) then
      if found then return nil end
      found=p
    end
  end
  return found
end
local function rootOf(player)
  local ch=player and player.Character
  local hum=ch and ch:FindFirstChildOfClass("Humanoid")
  return hum and hum.Health>0 and hum.RootPart or nil
end
-- ROOT_GEOMETRY_BEGIN
local Geometry={}
local function finiteVector(v)
  return v and finite(v.X) and finite(v.Y) and finite(v.Z)
end
local function boundedSettings(settings)
  local copy=table.clone(settings)
  for _,key in ipairs({"x","y","z"}) do copy[key]=finite(copy[key]) and math.clamp(copy[key],-20,20) or 0 end
  for _,key in ipairs({"pitch","yaw","roll"}) do copy[key]=finite(copy[key]) and math.clamp(copy[key],-180,180) or 0 end
  return copy
end
function Geometry.projectedHalf(size,rotation)
  if not finiteVector(size) or math.min(size.X,size.Y,size.Z)<=0 then return nil end
  local right,up,look=rotation.RightVector,rotation.UpVector,rotation.LookVector
  if not finiteVector(right) or not finiteVector(up) or not finiteVector(look) then return nil end
  return Vector3.new(
    math.abs(right.X)*size.X+math.abs(up.X)*size.Y+math.abs(look.X)*size.Z,
    math.abs(right.Y)*size.X+math.abs(up.Y)*size.Y+math.abs(look.Y)*size.Z,
    math.abs(right.Z)*size.X+math.abs(up.Z)*size.Y+math.abs(look.Z)*size.Z)*0.5
end
-- `side` says where our root sits relative to the target: -1 below it (the
-- default, and the mount that throws a target upward), +1 above it, which is the
-- mount that drives a target down toward the void plane.
function Geometry.fit(ownSize,otherSize,targetFrame,settings,side)
  side=(side==1) and 1 or -1
  local fitted=boundedSettings(settings)
  -- Mount angles are world-aligned; offsets are target-local. Project each
  -- rotated box in world space, then convert the below-root offset back.
  local rotation=CFrame.Angles(math.rad(fitted.pitch),math.rad(fitted.yaw),math.rad(fitted.roll))
  local ownHalf=Geometry.projectedHalf(ownSize,rotation)
  local otherHalf=Geometry.projectedHalf(otherSize,targetFrame)
  if not ownHalf or not otherHalf or not finiteVector(ownHalf+otherHalf) then return nil,"Root dimensions are invalid" end
  local overlap=math.min(math.max(math.min(ownHalf.Y,otherHalf.Y)*0.3,0.02),0.45,(ownHalf.Y+otherHalf.Y)*0.3)
  local distance=math.clamp(ownHalf.Y+otherHalf.Y-overlap,0.02,20)
  local localOffset=targetFrame:VectorToObjectSpace(Vector3.new(0,side*distance,0))
  if not finiteVector(localOffset) then return nil,"Target orientation is invalid" end
  fitted.x=math.clamp(localOffset.X,-20,20)
  fitted.y=math.clamp(localOffset.Y,-20,20)
  fitted.z=math.clamp(localOffset.Z,-20,20)
  return fitted,{ownHalf=ownHalf,otherHalf=otherHalf,distance=distance,overlap=overlap,side=side,
    clamped=ownHalf.Y+otherHalf.Y-overlap>20}
end
-- How much of the fall to the void plane an attempt actually delivered, as 0..1.
-- Travel is only counted where there is somewhere to fall: a target pressed into
-- a floor two studs down has not been sent anywhere, however fast it got there.
Geometry.VOID_WEIGHT=3000
function Geometry.voidProgress(sample,context)
  if not sample or not context then return 0 end
  if sample.voided then return 1 end
  local gap=context.gap
  if not finite(gap) or gap<=0 then return 0 end
  local clearance=finite(context.drop) and math.max(context.drop,0) or gap
  local travel=finite(sample.downwardTravel) and math.max(sample.downwardTravel,0) or 0
  local speed=finite(sample.downwardGain) and math.max(sample.downwardGain,0) or 0
  -- Falling only counts as far as there is room to fall, and the whole distance
  -- to the void plane is the denominator: pressing a target into a floor two
  -- studs down has covered two studs of a five hundred stud drop, not all of it.
  -- The carry term uses the measured speed alone. observe() already subtracts
  -- free fall, so adding gravity back here would hand every dead attempt the
  -- credit the evidence model exists to withhold.
  local usable=math.min(travel,clearance)
  local carried=math.min(speed,math.max(clearance-usable,0))
  local dropping=(usable+carried)/gap
  -- Where a floor is in the way the way out is sideways, so the distance covered
  -- toward the nearest opening is the same measurement in a different direction.
  local across=0
  if finite(context.edgeDistance) and context.edgeDistance>0 and finite(sample.edgeTravel) then
    across=math.max(sample.edgeTravel,0)/context.edgeDistance
  end
  return math.clamp(math.max(dropping,across),0,1)
end
-- Which way the void is from here. Pure: the survey does the asking.
function Geometry.route(context)
  if not context then return "up","no survey" end
  local gap,drop=context.gap,context.drop
  if not finite(gap) or gap<=0 then return "up","target is already at the void plane" end
  if not finite(drop) or drop>=gap*0.9 then
    return "down",string.format("%.0f studs of clear fall below the target",math.min(finite(drop) and drop or gap,gap))
  end
  if finite(context.edgeDistance) and context.edgeDistance<=1024 and context.edgeDirection then
    return "lateral",string.format("ground %.0f studs below; nearest opening is %.0f studs away",drop,context.edgeDistance)
  end
  return "up",string.format("enclosed: ground %.0f studs below and no opening within 1024 studs",drop)
end
function Geometry.candidates(ownSize,otherSize,targetFrame,settings,power,spin,context)
  local original=boundedSettings(settings)
  local fitted,geometry=Geometry.fit(ownSize,otherSize,targetFrame,original)
  if not fitted then return nil,geometry end
  power=finite(power) and math.clamp(power,0,R.POWER_LIMIT) or 0
  spin=finite(spin) and math.clamp(spin,0,R.POWER_LIMIT) or 0
  local candidates,seen={},{}
  local function add(value,label)
    value=boundedSettings(value)
    local parts={}
    for _,key in ipairs({"x","y","z","pitch","yaw","roll"}) do table.insert(parts,string.format("%.5f",value[key])) end
    local fingerprint=table.concat(parts,",")
    if not seen[fingerprint] then
      seen[fingerprint]=true
      table.insert(candidates,{settings=value,power=power,spin=spin,label=label})
    end
  end
  add(original,"Current mount")
  -- Void mounts go in before the upward ones. The sampling loop stops early once
  -- the target is already moving fast, so the order decides what actually gets
  -- tried, not just what gets listed.
  local route,rationale=Geometry.route(context)
  if context and route=="down" then
    local above,aboveInfo=Geometry.fit(ownSize,otherSize,targetFrame,original,1)
    if above then
      add(above,"Void drop: fitted above root")
      local nudge=math.min(aboveInfo.distance*0.2,math.max(aboveInfo.overlap*0.7,0.025))
      for _,delta in ipairs({Vector3.new(0,nudge,0),Vector3.new(0,-nudge,0)}) do
        local localDelta=targetFrame:VectorToObjectSpace(delta)
        local shifted=table.clone(above)
        shifted.x+=localDelta.X; shifted.y+=localDelta.Y; shifted.z+=localDelta.Z
        add(shifted,"Void drop variation")
      end
    end
  elseif context and route=="lateral" and context.edgeDirection then
    -- Sit on the far side of the target from the opening, so the drive that is
    -- already aimed through the target carries it out over the edge.
    local away=targetFrame:VectorToObjectSpace(context.edgeDirection*(-geometry.distance))
    if finiteVector(away) then
      local pushed=table.clone(fitted)
      pushed.x=math.clamp(away.X,-20,20); pushed.y=math.clamp(away.Y,-20,20); pushed.z=math.clamp(away.Z,-20,20)
      add(pushed,"Void edge: lateral drive")
      local lifted=table.clone(pushed)
      lifted.y=math.clamp(lifted.y+math.min(geometry.distance*0.5,2),-20,20)
      add(lifted,"Void edge: raised lateral drive")
    end
  end
  add(fitted,"Fitted below root")
  local vertical=math.min(geometry.distance*0.2,math.max(geometry.overlap*0.7,0.025))
  local lateralX=math.min(math.min(geometry.ownHalf.X,geometry.otherHalf.X)*0.35,1.5)
  local lateralZ=math.min(math.min(geometry.ownHalf.Z,geometry.otherHalf.Z)*0.35,1.5)
  for _,delta in ipairs({Vector3.new(0,vertical,0),Vector3.new(0,-vertical,0),
      Vector3.new(lateralX,0,0),Vector3.new(-lateralX,0,0),Vector3.new(0,0,lateralZ),Vector3.new(0,0,-lateralZ)}) do
    local localDelta=targetFrame:VectorToObjectSpace(delta)
    local shifted=table.clone(fitted)
    shifted.x+=localDelta.X; shifted.y+=localDelta.Y; shifted.z+=localDelta.Z
    add(shifted,"Fitted contact variation")
  end
  for _,yaw in ipairs({-15,15}) do
    local angled=table.clone(original)
    angled.yaw=math.clamp(angled.yaw+yaw,-180,180)
    local angleFit=Geometry.fit(ownSize,otherSize,targetFrame,angled)
    if angleFit then add(angleFit,"Fitted angle variation") end
  end
  geometry.route=route; geometry.rationale=rationale
  return candidates,geometry
end
function Geometry.score(evidence,sample,context)
  if not evidence or not evidence.characterStable or not evidence.contactCorrelated then return 0 end
  local gain,travel,confidence=evidence.visibleSpeedGain,evidence.residualDisplacement,evidence.baselineConfidence
  if not finite(gain) or not finite(travel) or gain<=0 or travel<0 then return 0 end
  confidence=finite(confidence) and math.clamp(confidence,0,1) or 0
  local score=(math.min(gain,2000)+math.min(travel,500))*(0.5+confidence*0.5)
  -- Direction is only a modest preference after the existing contact evidence
  -- gate, with enough nearby samples and a trustworthy baseline. It is local
  -- observation, not confirmation of replication or a void elimination.
  if confidence>=0.5 and sample and sample.samples>=2 and sample.nearby>=2 then
    local down,displacement=sample.downwardGain,sample.downwardTravel
    if finite(down) and finite(displacement) then score+=math.min(math.max(down,0),500)*0.3+math.min(math.max(displacement,0),100)*0.5 end
    -- With a survey, reaching the void is the objective rather than a tiebreak:
    -- this term outweighs raw speed, so the mount that drops a target wins over
    -- the mount that merely throws it hard. Still gated on the same contact
    -- evidence, so ordinary falling can never earn it.
    if context then score+=Geometry.VOID_WEIGHT*Geometry.voidProgress(sample,context) end
  end
  return score
end
R.Geometry=Geometry
-- ROOT_GEOMETRY_END
-- The heading that points our body at the target, or nil to leave the mount
-- rotation alone. Kept separate from the camera on purpose: followCamera is the
-- control that moves the view, and this one never touches it.
-- The horizontal bearing a direction points along, or nil if it points straight
-- up or down and has no horizontal bearing to report. Roblox look vectors are -Z.
local function bearing(direction)
  if not finiteVector(direction) then return nil end
  local flat=Vector3.new(direction.X,0,direction.Z)
  if not finite(flat.Magnitude) or flat.Magnitude<0.25 then return nil end
  return math.atan2(-flat.X,-flat.Z)
end
function R.facing(part,mountPosition,rotation)
  if not R.faceTarget then return nil end
  if not finiteVector(part.Position) or not finiteVector(mountPosition) then return R.facingYaw end
  local toTarget=part.Position-mountPosition
  local flat=Vector3.new(toTarget.X,0,toTarget.Z)
  local reach=flat.Magnitude
  -- Mounted directly under or over a target there is no horizontal direction to
  -- face, and a look-at built on that spins on floating point noise. Hold the
  -- last heading rather than inventing one.
  if not finite(reach) or reach<0.5 then return R.facingYaw end
  local want=math.atan2(-flat.X,-flat.Z)
  -- Which axis reads as "forward" depends on the pose. An upright mount runs
  -- along its look vector; the default fling mount is pitched -90, which puts
  -- that vector on the floor and lays the body along its up axis instead.
  local have=rotation and (bearing(rotation.LookVector) or bearing(rotation.UpVector))
  if rotation and not have then return R.facingYaw end
  -- Turn BY the difference. Setting an absolute yaw would discard the heading the
  -- mount rotation already carries and point the body the opposite way.
  local yaw=want-(have or 0)
  if finite(yaw) then R.facingYaw=yaw end
  return R.facingYaw
end
function R.mount(part,currentPosition,elapsed)
  R.aimPart=part
  local s=R.settings
  -- Match the original world-aligned layout at defaults; optional target-local
  -- position offsets rotate with the target, while Euler angles stay editable.
  local offset=part.CFrame:VectorToWorldSpace(Vector3.new(s.x,s.y,s.z))
  local rotation=CFrame.Angles(math.rad(s.pitch),math.rad(s.yaw),math.rad(s.roll))
  if s.variant=="Helix drive" and R.fling then
    offset=offset+Vector3.new(math.cos(elapsed*18),0,math.sin(elapsed*18))*0.15
  end
  local position=currentPosition+offset
  -- Pre-multiplied, so this is a turn about world Y. Every axis keeps its Y
  -- component, which is what the fitted separation was measured from.
  local face=R.facing(part,position,rotation)
  if face then rotation=CFrame.Angles(0,face,0)*rotation end
  return CFrame.new(position)*rotation
end
function R.drive(thrust,part,elapsed,flip)
  if R.settings.variant=="Helix drive" then thrust=CFrame.Angles(0,elapsed*18,0)*thrust end
  local power=finite(K.cfg.repPower) and math.clamp(K.cfg.repPower,0,R.POWER_LIMIT) or R.POWER_LIMIT
  local spin=finite(K.cfg.repSpin) and math.clamp(K.cfg.repSpin,0,R.POWER_LIMIT) or R.POWER_LIMIT
  if not finite(thrust.Magnitude) then thrust=Vector3.yAxis*power
  elseif thrust.Magnitude>0 then thrust=thrust.Unit*power end
  -- Preserve Lumen's actual three-axis alternating drive at default settings.
  return thrust,Vector3.new(spin*flip,spin*flip,spin*flip)
end
function R.observe(part,root,desired)
  local speed=part.AssemblyLinearVelocity.Magnitude
  if finite(speed) then R.peak=math.max(R.peak,speed) end
  local err=(root.Position-desired.Position).Magnitude
  R.error=finite(err) and err or 0
  local sample=R.tuneSample
  if sample and sample.part==part and sample.root==root and finiteVector(part.Position)
      and finiteVector(part.AssemblyLinearVelocity) then
    local elapsed=os.clock()-sample.at
    if elapsed>0 and elapsed<=5 then
      sample.samples+=1
      if finite(err) and err<=sample.nearDistance then sample.nearby+=1 end
      -- Subtract free-fall acceleration as well as baseline velocity; ordinary
      -- falling must not become evidence for a better downward response.
      local downGain=-(part.AssemblyLinearVelocity.Y-sample.velocity.Y+sample.gravity*elapsed)
      local downTravel=-(part.Position.Y-sample.position.Y-sample.velocity.Y*elapsed+0.5*sample.gravity*elapsed*elapsed)
      if finite(downGain) then sample.downwardGain=math.max(sample.downwardGain,downGain,0) end
      if finite(downTravel) then sample.downwardTravel=math.max(sample.downwardTravel,downTravel,0) end
      -- An actual crossing of the void plane is the only unambiguous result here.
      if finite(sample.voidY) and part.Position.Y<=sample.voidY then sample.voided=true end
      if sample.edgeDirection then
        local delta=part.Position-sample.position
        local along=delta.X*sample.edgeDirection.X+delta.Z*sample.edgeDirection.Z
        if finite(along) then sample.edgeTravel=math.max(sample.edgeTravel or 0,along,0) end
      end
    end
  end
end
local function cancelTune()
  R.tuneSerial+=1
  if R.tuneThread and R.tuneThread~=coroutine.running() then pcall(task.cancel,R.tuneThread) end
  R.tuneThread=nil
  R.tuneSample=nil
  if R.tuning then
    local a=R.tuning
    R.settings=table.clone(a.settings)
    K.cfg.repPower=a.power; K.cfg.repSpin=a.spin
    K.cfg.flingDuration=a.duration
    R.tuning=nil
    sync()
  end
end
function R.cancelPhysics(why,opts)
  local busy=K.flinging or K.activeCleanup~=nil or K.returningHome
  K.stopAttempt(why or "stopped by hand",{home=false})
  K.recoverFling(why or "stopped by hand")
  R.workerActive=false
  if busy and K.cfg.returnHome and not (opts and opts.home==false) then K.returnToRunHome() end
  return busy
end
function R.stop(why,opts)
  cancelTune()
  local ended=R.endQueue and R.endQueue(why,opts)
  if not ended then ended=R.cancelPhysics(why,opts) end
  R.workerActive=false
  return ended
end
function R.setRepRoot(v)
  R.repRoot=v==true
  if not R.repRoot then R.stop("Rep Root off") end
  sync(); return true
end
function R.setFling(v)
  if R.tuning then R.stop("tune cancelled by switch change") end
  R.fling=v==true
  if K.flinging then
    local r=rootOf(LP)
    local h=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if h then h.PlatformStand=R.fling end
    if r and not R.fling then r.AssemblyLinearVelocity=Vector3.zero; r.AssemblyAngularVelocity=Vector3.zero end
  end
  sync(); return true
end
function R.applyPreset(name)
  if R.tuning then R.stop("tune cancelled by preset change") end
  for _,p in ipairs(Presets) do if p.name==name then
    for _,key in ipairs({"x","y","z","pitch","yaw","roll"}) do R.settings[key]=p[key] end
    R.settings.variant=p.name
    K.cfg.repPower=p.power; K.cfg.repSpin=p.spin; K.cfg.repLift=p.lift
    K.cfg.flingAttach=p.name=="Rocket burst" and "Rep-root burst" or "Rep-root"
    sync(); announce(p.name,p.tag..". Rep Root and Fling switches unchanged.")
    return true
  end end
  return false
end
local originalStart=K.startFling
function R.runOne(name)
  if not R.repRoot then return false,"Rep Root is off","user" end
  if not R.queue and type(name)=="string" and name~="" then R.targetName=name end
  R.peak=0; R.error=0
  K.lastThrowEvidence=nil
  K.cfg.flingAttach=R.settings.variant=="Rocket burst" and "Rep-root burst" or "Rep-root"
  K.cfg.autoFallback=false
  sync()
  return originalStart(name)
end
function K.startFling(name)
  if R.beginQueue and R.loopMode~="Single burst" and not R.tuning then return R.beginQueue(name) end
  return R.runOne(name)
end
function R.start()
  if R.controls.targetName then R.targetName=R.controls.targetName:get() end
  local ok,why=K.startFling(R.targetName)
  if not ok then L.Toast.warn("Rep Root",tostring(why)) end
  return ok,why
end
local originalStop=K.stopFling
function K.stopAttempt(why,opts)
  R.workerActive=false
  return originalStop(why,opts)
end
-- Public Stop means the whole session. The runner uses stopAttempt for a pass.
function K.stopFling(why,opts) return R.stop(why,opts) end
-- Everything the void decision needs, read from the map itself. Entirely
-- guarded: an executor or fixture without the raycast API returns nil, and every
-- caller then behaves exactly as it did before there was a survey.
R.surveyCache={}
function R.survey(part,maxAge)
  local cache=R.surveyCache
  if cache.part==part and cache.at and (os.clock()-cache.at)<=(maxAge or 0.3) then return cache.context end
  local ok,context=pcall(function()
    -- R.voidFloor is captured before the local void guard overwrites the live
    -- property with NaN; the property itself is only a fallback.
    local voidY=R.voidFloor
    if not finite(voidY) then voidY=workspace.FallenPartsDestroyHeight end
    voidY=finite(voidY) and voidY or -500
    local gravity=finite(workspace.Gravity) and math.clamp(workspace.Gravity,1,1000) or 196.2
    local origin=part.Position
    if not finiteVector(origin) then return nil end
    local gap=origin.Y-voidY
    if not finite(gap) or gap<=0 then return nil end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local ignore={}
    if LP.Character then ignore[#ignore+1]=LP.Character end
    local owner=part.Parent
    if owner and owner~=workspace and owner:IsA("Model") then ignore[#ignore+1]=owner end
    params.FilterDescendantsInstances=ignore
    params.IgnoreWater=true
    local reach=Vector3.new(0,-gap,0)
    local below=workspace:Raycast(origin,reach,params)
    local drop=below and (origin.Y-below.Position.Y) or math.huge
    -- Only look for a way off the side when there is a floor in the way. Twelve
    -- bearings at five ranges is one cheap sweep, once per fit or tune.
    local edgeDistance,edgeDirection=math.huge,nil
    if finite(drop) and drop<gap*0.9 then
      for turn=0,11 do
        local angle=turn*math.pi/6
        local direction=Vector3.new(math.cos(angle),0,math.sin(angle))
        for _,range in ipairs({16,32,64,128,256,512,1024}) do
          if range>=edgeDistance then break end
          local hit=workspace:Raycast(origin+direction*range,reach,params)
          if not hit then edgeDistance=range; edgeDirection=direction; break end
        end
      end
    end
    return {voidY=voidY,gravity=gravity,gap=gap,drop=drop,
      edgeDistance=edgeDistance,edgeDirection=edgeDirection}
  end)
  context=(ok and type(context)=="table" and finite(context.gap)) and context or nil
  R.surveyCache={part=part,at=os.clock(),context=context}
  return context
end
-- The drive direction, when the map offers a way out. Returning nil hands the
-- decision straight back to the supplied camera-relative aim, which is what
-- happens on any map with no reachable void.
function R.aimOverride()
  if not R.voidAim or not R.fling then return nil end
  local part=R.aimPart
  if not part or not part.Parent then return nil end
  local ok,result=pcall(function()
    local context=R.survey(part)
    local route=Geometry.route(context)
    local power=finite(K.cfg.repPower) and math.clamp(K.cfg.repPower,0,R.POWER_LIMIT) or R.POWER_LIMIT
    if route=="down" then
      R.voidRoute="down"
      return Vector3.new(0,-1,0)*power
    elseif route=="lateral" and context.edgeDirection then
      R.voidRoute="lateral"
      -- Mostly outward with a little lift, so the target clears the lip it is
      -- standing on instead of being driven into its edge.
      local direction=context.edgeDirection
      local aim=Vector3.new(direction.X,0.18,direction.Z)
      if finite(aim.Magnitude) and aim.Magnitude>0.05 then return aim.Unit*power end
    end
    R.voidRoute=nil
    return nil
  end)
  if ok then return result end
  R.voidRoute=nil
  return nil
end
function R.autoFit()
  if R.tuning then R.stop("tune cancelled") end
  local own,other=rootOf(LP),rootOf(studioTarget())
  if not own or not other then return false,"Choose a living target first" end
  local context=R.survey(other)
  local route,rationale=Geometry.route(context)
  local fitted,geometry=Geometry.fit(own.Size,other.Size,other.CFrame,R.settings,route=="down" and 1 or -1)
  if not fitted then return false,geometry end
  R.settings=fitted
  sync()
  local why
  if geometry.clamped then why="Root fit reached the 20-stud offset limit"
  elseif geometry.side==1 then why="Above-root fit: the drive now sits on top of the target and pushes it down"
  else why="Below-root fit uses both root sizes, all three angles and the target's orientation" end
  return true,context and (why.." ("..rationale..")") or why
end
function R.autoTune()
  if R.tuning then R.stop("auto-tune cancelled"); return end
  if not R.fling then
    local ok,why=R.autoFit()
    if ok then announce("Geometry fitted",why) else L.Toast.warn("Auto fit",why) end
    return
  end
  if not R.repRoot then L.Toast.warn("Auto tune","Turn Rep Root on first"); return end
  local p=studioTarget()
  local own,other=rootOf(LP),rootOf(p)
  if not own or not other then L.Toast.warn("Auto tune","Choose a living target first"); return end
  R.stop("starting auto-tune")
  R.tuneSerial+=1
  local serial=R.tuneSerial
  local original={settings=table.clone(R.settings),power=K.cfg.repPower,spin=K.cfg.repSpin,duration=K.cfg.flingDuration}
  local context=R.survey(other)
  local candidates,geometry=Geometry.candidates(own.Size,other.Size,other.CFrame,original.settings,original.power,original.spin,context)
  if not candidates then L.Toast.warn("Auto tune",geometry); return end
  local ownCharacter,otherCharacter=LP.Character,p.Character
  local function stable()
    return p.Parent and LP.Character==ownCharacter and p.Character==otherCharacter and rootOf(LP)==own and rootOf(p)==other
  end
  R.tuning=original; R.tuneCount=#candidates
  R.tuneRoute=geometry.route
  announce("Auto tune started","Comparing "..#candidates.." mounts from your current setup and fitted root geometry, using local contact-correlated observations."
    ..(context and (" Void route: "..tostring(geometry.route).." -- "..tostring(geometry.rationale)..".") or " No map survey available; scoring on speed and travel only."))
  local tuneThread=task.spawn(function()
    local best,bestScore=nil,0
    local interrupted
    R.tuneResults={}
    local ok,err=pcall(function()
      for index,candidate in ipairs(candidates) do
        if not L.live() or R.tuneSerial~=serial then return end
        if not stable() then interrupted="Character changed during auto-tune"; break end
        if not finiteVector(other.AssemblyLinearVelocity) or not finiteVector(other.Position) then interrupted="Target motion is invalid"; break end
        if other.AssemblyLinearVelocity.Magnitude>500 then break end
        R.settings=table.clone(candidate.settings); K.cfg.repPower=candidate.power; K.cfg.repSpin=candidate.spin
        K.cfg.flingDuration=0.7; R.tuneIndex=index; sync()
        R.tuneSample={part=other,root=own,at=os.clock(),position=other.Position,velocity=other.AssemblyLinearVelocity,
          gravity=finite(workspace.Gravity) and math.clamp(workspace.Gravity,0,1000) or 196.2,
          samples=0,nearby=0,downwardGain=0,downwardTravel=0,voided=false,edgeTravel=0,
          voidY=context and context.voidY or nil,
          edgeDirection=context and context.edgeDirection or nil,
          nearDistance=math.clamp(math.min(geometry.ownHalf.X,geometry.ownHalf.Y,geometry.ownHalf.Z)*1.5,0.25,2)}
        K.lastThrowEvidence=nil
        local started,why=K.startFling(p.Name)
        if not started then interrupted=tostring(why or "Target attempt was refused"); break end
        local deadline=os.clock()+5
        repeat task.wait(0.08) until not K.flinging or R.tuneSerial~=serial or not L.live() or not stable() or os.clock()>deadline
        if R.tuneSerial~=serial or not L.live() then return end
        if not stable() then interrupted="Character changed during auto-tune"; break end
        if K.flinging then interrupted="Auto-tune sample timed out"; break end
        local evidence=K.lastThrowEvidence
        local sample=R.tuneSample
        local score=Geometry.score(evidence,sample,context)
        R.tuneSample=nil
        table.insert(R.tuneResults,{candidate=index,label=candidate.label,score=score,evidence=evidence,
          nearbySamples=sample and sample.nearby or 0,downwardGain=sample and sample.downwardGain or 0,
          voidProgress=Geometry.voidProgress(sample,context),voided=sample and sample.voided or false})
        if finite(score) and score>bestScore then best=candidate; bestScore=score end
        if other.AssemblyLinearVelocity.Magnitude>500 then break end
        -- Let Lumen finish its existing return routine before a new attempt.
        task.wait(0.3)
      end
    end)
    if R.tuneSerial~=serial then return end
    if not L.live() or not stable() then interrupted="Character or session changed during auto-tune" end
    if not ok or interrupted then
      R.stop("auto-tune cancelled",{home=false})
      if not ok then L.fault("reproot.tune",err); L.Toast.warn("Auto tune stopped",tostring(err))
      elseif L.live() then announce("Original settings restored",interrupted) end
      return
    end
    K.stopAttempt("auto-tune complete")
    R.tuneSample=nil; R.tuneThread=nil
    R.settings=table.clone(best and best.settings or original.settings)
    K.cfg.repPower=best and best.power or original.power
    K.cfg.repSpin=best and best.spin or original.spin
    K.cfg.flingDuration=original.duration
    R.tuning=nil; sync()
    if best then announce("Best observed settings applied","Local evidence score "..math.floor(bestScore)..". Confirm the result from your test partner.")
    else announce("Original settings kept","No motion-adjusted fling response measured. This does not establish anti-fling.") end
  end)
  if R.tuneSerial==serial and R.tuning then R.tuneThread=tuneThread end
end

K.cfg.flingAttach="Rep-root"; K.cfg.autoFallback=false; K.cfg.maxAttempts=1
K.cfg.flingMode="One target"; K.cfg.loopRelentless=false
K.cfg.waitRespawn=false; K.cfg.waitSeated=false; K.cfg.watchImmune=false
K.cfg.repPower=R.POWER_LIMIT; K.cfg.repSpin=R.POWER_LIMIT; K.cfg.repLift=0.55
K.cfg.flingDuration=6; K.cfg.returnHome=true
-- Prediction is disabled at its writers as well as at placement.
K.cfg.autoPredict=false; K.cfg.predictLead=0; K.cfg.predictCap=0
function K.setAutoPredict() K.cfg.autoPredict=false; K.cfg.predictLead=0; K.cfg.predictCap=0; return true end
function K.predictFromPing() K.setAutoPredict(); return nil end
function K.autoTune() K.setAutoPredict(); return nil,"Prediction is disabled in the Rep Root build" end
L.Cfg.set("autoPredict",false)
-- Defaults apply only when no saved choice exists. Loading never starts a loop.
local function savedNumber(key,default,min,max)
  local value=L.Cfg.feat("reproot."..key,default)
  return finite(value) and math.clamp(value,min,max) or default
end
for key,range in pairs({x={0,-20,20},y={0,-20,20},z={0,-20,20},pitch={-90,-180,180},yaw={0,-180,180},roll={0,-180,180}}) do
  R.settings[key]=savedNumber(key,range[1],range[2],range[3])
end
for key,range in pairs({repPower={R.POWER_LIMIT,0,R.POWER_LIMIT},repSpin={R.POWER_LIMIT,0,R.POWER_LIMIT},repLift={0.55,0,1},flingDuration={6,0.15,15},approachSettle={K.cfg.approachSettle,0.05,2}}) do
  K.cfg[key]=savedNumber(key,range[1],range[2],range[3])
end
for key,default in pairs({repRoot=true,fling=true,voidGuard=true,followCamera=true,preview=true,noclip=false,voidAim=true,faceTarget=true}) do
  R[key]=L.Cfg.feat("reproot."..key,default)==true
end
K.cfg.returnHome=L.Cfg.feat("reproot.returnHome",true)==true
R.turnDuration=savedNumber("turnDuration",1.2,0.25,5)
local savedVariant=L.Cfg.feat("reproot.variant","Lumen maximum")
for _,preset in ipairs(Presets) do if preset.name==savedVariant then R.settings.variant=savedVariant end end
local savedMode=L.Cfg.feat("reproot.loopMode","Loop target")
if table.find({"Loop target","Selected players","All players","Single burst"},savedMode) then R.loopMode=savedMode end
local savedTarget=L.Cfg.feat("reproot.targetName","")
R.targetName=type(savedTarget)=="string" and savedTarget or ""
R.setNoclip(R.noclip)

-- SESSION_ENGINE

-- PLAYER_PANEL

local function slider(page,label,key,min,max,step,desc,config)
  local function value() return config and K.cfg[key] or R.settings[key] end
  R.controls[key]=C.slider(page,{id="reproot."..key,text=label,desc=desc,min=min,max=max,step=step,
    default=value(),curve=max>=1e6 and "log" or nil,callback=function(v)
      if R.tuning then R.stop("tune cancelled by edit") end
      if not finite(v) then return false end
      if config then K.cfg[key]=math.clamp(v,min,max) else R.settings[key]=math.clamp(v,min,max) end
    end})
end
function R.build()
  R.controls={}
  local win=L.Window.new({title="LUMEN",subtitle="REP ROOT  /  WORKSHOP",width=940,height=650,guiName="LumenRepRoot"})
  Hub.window=win
  win:navSection("Rep Root")
  local drive=win:tab({name="Rep Root",chrome="torus",desc="Lumen's replication drive, with independent attachment and fling"})
  local p=drive.body
  C.ctx("reproot")
  local tiles=C.tiles(p,{{key="rep",label="Rep Root",value="ON"},{key="fling",label="Fling",value="ON"},{key="state",label="Session",value="Idle"}})
  C.section(p,"control")
  R.controls.repRoot=C.toggle(p,{id="reproot.repRoot",text="Rep Root",desc="The only attachment method used in this build",default=R.repRoot,callback=R.setRepRoot})
  R.controls.fling=C.toggle(p,{id="reproot.fling",text="Fling",desc="Off keeps the mount active so you can edit offsets and angles",default=R.fling,callback=R.setFling})
  R.controls.noclip=C.toggle(p,{id="reproot.noclip",text="Noclip",desc="Disables your collisions. Pauses during your own fling, then resumes; you can pass through floors.",default=R.noclip,callback=R.setNoclip})
  R.controls.targetName=C.input(p,{id="reproot.targetName",text="Target name",desc="Username or a unique prefix; the player panel also works",placeholder="username",default=R.targetName,callback=function(v) R.targetName=v end})
  C.actions(p,{{text="Open player panel",primary=true,callback=function() L.Side.show() end},
    {text="Attach / start",primary=true,callback=R.start},{text="Stop / restore",callback=function() R.stop("stopped by hand") end}})
  C.paragraph(p,"Fling off disables the high-velocity drive. The active replication binding can still affect the target. Backspace stops and restores your character.")
  C.section(p,"drive")
  slider(p,"Linear input","repPower",0,R.POWER_LIMIT,1e5,"Finite ceiling: 1e18; click the number to type a value",true)
  slider(p,"Angular input","repSpin",0,R.POWER_LIMIT,1e5,"Alternating three-axis spin; finite ceiling: 1e18",true)
  slider(p,"Upward share","repLift",0,1,0.01,"0 sends outward; 1 sends upward",true)
  slider(p,"Drive duration","flingDuration",0.15,15,0.05,"Single-burst duration; the target loop holds through the throw",true)
  slider(p,"Approach settle","approachSettle",0.05,2,0.05,"Lumen's arrival phase before the drive",true)
  C.toggle(p,{id="reproot.returnHome",text="Return on stop",default=K.cfg.returnHome,callback=function(v) K.cfg.returnHome=v end})
  C.toggle(p,{id="reproot.voidGuard",text="Disable local void",desc="Prevents local void deletion; does not cancel server-controlled deaths",default=R.voidGuard,callback=R.setVoidGuard})
  C.toggle(p,{id="reproot.voidAim",text="Aim for the void",desc="Drives the target down where the map is open below, or out toward the nearest edge; falls back to the camera aim when neither exists",default=R.voidAim,callback=function(value) R.voidAim=value==true; R.voidRoute=nil end})
  R.controls.followCamera=C.toggle(p,{id="reproot.followCamera",text="View active target",desc="Switches directly to each target's view; follows their replacement character on respawn",default=R.followCamera,callback=R.setFollowCamera})
  R.controls.faceTarget=C.toggle(p,{id="reproot.faceTarget",text="Face the target",desc="Turns your character to look at whoever you are latched to. Body only -- your camera stays where you put it",default=R.faceTarget,callback=function(value)
    R.faceTarget=value==true
    if not R.faceTarget then R.facingYaw=nil end
  end})
  C.section(p,"saved setup")
  R.controls.autoSave=C.toggle(p,{persist=false,text="Auto-save config",desc="Save changes automatically. Turn off to keep edits in this session until you press Save now.",default=L.Cfg.data.autoSave~=false,callback=R.setAutoSave})
  C.actions(p,{{text="Save now",callback=R.saveConfig}})
  C.section(p,"observed response")
  local observed=C.tiles(p,{{key="peak",label="Local peak",value="0"},{key="distance",label="Adjusted travel",value="0"},{key="tune",label="Auto tune",value="Idle"}})
  R.buildQueue(win)
  local offsets=win:tab({name="Offsets",chrome="cards",desc="A live mount workshop, with all six transform controls"})
  p=offsets.body; C.ctx("reproot")
  C.paragraph(p,"Switch Fling off, attach to your target, then adjust the mount. Auto fit uses root dimensions; live auto-tune compares nearby custom settings when Fling is on.")
  C.actions(p,{{text="Auto fit geometry",primary=true,callback=function() local ok,why=R.autoFit(); if ok then announce("Auto fit",why) else L.Toast.warn("Auto fit",why) end end},
    {text="Auto tune / cancel",callback=R.autoTune}})
  C.section(p,"position")
  slider(p,"Offset X","x",-20,20,0.01,"Target-local left / right")
  slider(p,"Offset Y","y",-20,20,0.01,"Target-local down / up")
  slider(p,"Offset Z","z",-20,20,0.01,"Target-local forward / back")
  C.section(p,"angles")
  slider(p,"Pitch","pitch",-180,180,0.1,"X rotation in degrees")
  slider(p,"Yaw","yaw",-180,180,0.1,"Y rotation in degrees")
  slider(p,"Roll","roll",-180,180,0.1,"Z rotation in degrees")
  C.toggle(p,{id="reproot.preview",text="Mount preview",desc="Local translucent marker while a target is selected",default=R.preview,callback=function(v) R.preview=v end})
  C.actions(p,{{text="Reset mount",callback=function() if R.tuning then R.stop("tune cancelled") end; for k,v in pairs({x=0,y=0,z=0,pitch=-90,yaw=0,roll=0}) do R.settings[k]=v end; sync() end}})
  local presets=win:tab({name="Presets",chrome="bolt",desc="Rep Root variants, all using Lumen's recovery sequence"})
  p=presets.body
  C.paragraph(p,"Lumen original is the reference implementation. Lumen maximum has the highest input. Auto-tune identifies the best observed custom settings for the selected target; a universal strongest preset cannot be inferred from input magnitude.")
  for _,preset in ipairs(Presets) do
    C.section(p,preset.name.." / "..preset.tag)
    C.paragraph(p,preset.desc)
    C.actions(p,{{text="Apply "..preset.name,primary=true,callback=function() R.applyPreset(preset.name) end}})
  end
  win:navSection("Lumen")
  C.ctx("interface")
  -- INTERFACE_FROM_LUMEN
  local activity=win:tab({name="Activity",chrome="hero",desc="Lumen diagnostics and observed test results"})
  C.logView(activity.body)
  C.actions(activity.body,{{text="Stop / recover",callback=function() R.stop("manual recovery"); K.recoverFling("manual recovery") end},
    {text="Unload",callback=function() R.stop("unloaded"); L.teardown() end}})
  local accumulator=0
  L.hold(L.RunService.Heartbeat:Connect(function(dt)
    if not L.live() or not win.gui.Parent then return end
    accumulator+=dt; if accumulator<0.2 then return end; accumulator=0
    tiles:set("rep",R.repRoot and "ON" or "OFF"); tiles:set("fling",R.fling and "ON" or "OFF")
    tiles:set("state",R.queue and (K.flinging and "Looping" or "Waiting") or (K.flinging and "Active" or "Idle"))
    observed:set("peak",string.format("%.0f",R.peak))
    observed:set("distance",string.format("%.0f",K.lastThrow or 0))
    observed:set("tune",R.tuning and tostring(R.tuneIndex or 0).." / "..tostring(R.tuneCount or 0) or "Idle")
  end))
  win:select(1,true)
  return win
end
Hub.build=R.build

local preview
L.hold(L.RunService.RenderStepped:Connect(function()
  if not L.live() then return end
  local part=rootOf(studioTarget())
  if R.preview and part then
    if not preview then
      preview=L.mk("Part",{Name="LumenRepRootPreview",Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,
        Transparency=0.75,Color=T.c.accent,Material=Enum.Material.Neon,Size=Vector3.new(2,2,1),Parent=workspace})
      L.own(preview)
    end
    local own=rootOf(LP); if own then preview.Size=own.Size end
    preview.CFrame=R.mount(part,part.Position,0)
  elseif preview then preview:Destroy(); preview=nil end
end))
L.hold(L.UIS.InputBegan:Connect(function(i,processed)
  if not L.live() or processed or L.UIS:GetFocusedTextBox() then return end
  if i.KeyCode==Enum.KeyCode.Backspace then R.stop("emergency stop") end
end))
L.cleanup(function() R.stop("unloaded"); K.stopFling("unloaded",{home=false}) end,150)
local initialWindow=R.build()
initialWindow:show()
announce("Lumen Rep Root ready","Your saved setup is loaded. Open Players to choose a target; the session starts idle.")
