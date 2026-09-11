"""Exercise actual Rep Root geometry, observations and tune cancellation without a game client."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
RUNTIME = Path.home() / "AppData/Local/Temp/luaudl/luau.exe"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", nargs="?", type=Path, help="Optional assembled script; otherwise verify the addon source")
args = parser.parse_args()
source = (args.source or ROOT / "rep-root-addon.lua").read_text(encoding="utf-8")
start = source.index("do -- Rep Root dedicated pages") if args.source else 0
start = source.index("local L = getgenv().LUMEN", start)
addon = source[start:source.index('K.cfg.flingAttach="Rep-root"; K.cfg.autoFallback=false;', start)]

prelude = r'''
local checks=0
local function check(value,message) checks+=1; assert(value,message) end
local function near(a,b,message) check(math.abs(a-b)<1e-7,message) end
local V={}
V.__index=function(value,key)
  if key=='Magnitude' then return math.sqrt(value.X^2+value.Y^2+value.Z^2) end
  if key=='Unit' then return value/value.Magnitude end
  return V[key]
end
local Vector3={}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},V) end
function V.__add(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
function V.__sub(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function V.__mul(a,b)
  if type(a)=='number' then a,b=b,a end
  return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
function V.__div(a,b) return a*(1/b) end
Vector3.zero=Vector3.new(0,0,0); Vector3.yAxis=Vector3.new(0,1,0)
local CF={}
CF.__index=CF
local CFrame={}
local function frame(matrix,position)
  return setmetatable({matrix=matrix,Position=position or Vector3.zero,
    RightVector=Vector3.new(matrix[1],matrix[4],matrix[7]),
    UpVector=Vector3.new(matrix[2],matrix[5],matrix[8]),
    LookVector=Vector3.new(-matrix[3],-matrix[6],-matrix[9])},CF)
end
function CFrame.new(x,y,z)
  local position=type(x)=='table' and x or Vector3.new(x or 0,y or 0,z or 0)
  return frame({1,0,0,0,1,0,0,0,1},position)
end
function CFrame.Angles(x,y,z)
  local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
  return frame({cy*cz,-cy*sz,sy,cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy,sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy})
end
function CF:VectorToWorldSpace(v)
  local m=self.matrix
  return Vector3.new(m[1]*v.X+m[2]*v.Y+m[3]*v.Z,m[4]*v.X+m[5]*v.Y+m[6]*v.Z,m[7]*v.X+m[8]*v.Y+m[9]*v.Z)
end
function CF:VectorToObjectSpace(v)
  local m=self.matrix
  return Vector3.new(m[1]*v.X+m[4]*v.Y+m[7]*v.Z,m[2]*v.X+m[5]*v.Y+m[8]*v.Z,m[3]*v.X+m[6]*v.Y+m[9]*v.Z)
end
function CF.__mul(a,b)
  local m={}
  for row=0,2 do for col=0,2 do
    local sum=0; for k=0,2 do sum+=a.matrix[row*3+k+1]*b.matrix[k*3+col+1] end
    m[row*3+col+1]=sum
  end end
  return frame(m,a.Position+a:VectorToWorldSpace(b.Position))
end
local now,pending=0,{}
local os={clock=function() return now end}
local task={}
function task.spawn(fn)
  local thread=coroutine.create(fn)
  local ok,wait=coroutine.resume(thread); assert(ok,wait)
  if coroutine.status(thread)~='dead' then table.insert(pending,{thread=thread,at=now+(wait or 0)}) end
  return thread
end
function task.wait(dt) return coroutine.yield(dt or 0.03) end
function task.cancel(thread) if coroutine.status(thread)~='dead' then coroutine.close(thread) end end
local workspace={Gravity=196.2}
local players={}
function players:GetPlayers() return self.members end
local function character()
  local root={Size=Vector3.new(2,2,1),Position=Vector3.new(0,4,0),CFrame=CFrame.new(0,4,0),AssemblyLinearVelocity=Vector3.zero}
  local ch={}
  local hum={Health=100,RootPart=root,PlatformStand=false}
  function ch:FindFirstChildOfClass(class) return class=='Humanoid' and hum or nil end
  root.Parent=ch
  return ch
end
local selfPlayer={Name='Self',DisplayName='Self',Parent=players,Character=character()}
local target={Name='Alpha',DisplayName='Alpha',Parent=players,Character=character()}
players.members={selfPlayer,target}
local features,notes,faults={}, {}, {}
local live=true
local combat={cfg={repPower=123456,repSpin=234567,flingDuration=6,returnHome=true},flinging=false}
local attempts,behaviour,attemptAt=0,'normal',0
local studio
function combat.startFling()
  if behaviour=='refuse' then return false,'fixture refusal' end
  attempts+=1; attemptAt=now; combat.flinging=true
  if behaviour=='error' then error('fixture start failure') end
  return true
end
function combat.stopFling() combat.flinging=false; return true end
function combat.recoverFling() combat.flinging=false end
function combat.returnToRunHome() end
local fixtureL={C={},T={},Motion={},Hub={},Combat=combat,Players=players,LP=selfPlayer,
  Toast={info=function(title,body) table.insert(notes,{title,body}) end,warn=function(title,body) table.insert(notes,{title,body}) end},
  Cfg={feat=function(key) return features[key] end,setFeat=function(key,value) features[key]=value end},
  note=function() end,live=function() return live end,fault=function(where,err) table.insert(faults,{where,err}) end}
local function getgenv() return {LUMEN=fixtureL} end
'''

tests = r'''
studio=R
local Geometry=R.Geometry
local originalSettings=table.clone(R.settings)
local function offset(settings) return Vector3.new(settings.x,settings.y,settings.z) end
local function corners(size,rotation)
  local result=Vector3.zero
  for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
    local v=rotation:VectorToWorldSpace(Vector3.new(size.X*x,size.Y*y,size.Z*z)*0.5)
    result=Vector3.new(math.max(result.X,math.abs(v.X)),math.max(result.Y,math.abs(v.Y)),math.max(result.Z,math.abs(v.Z)))
  end end end
  return result
end
for _,angles in ipairs({{0,0,0},{-90,0,0},{0,0,90},{30,40,50},{-85,170,-130},{180,-180,180}}) do
  for _,scale in ipairs({0.05,0.35,1,2,8,100}) do
    local size=Vector3.new(2,3,0.75)*scale
    local rotation=CFrame.Angles(math.rad(angles[1]),math.rad(angles[2]),math.rad(angles[3]))
    local half=Geometry.projectedHalf(size,rotation)
    local reference=corners(size,rotation)
    near(half.X,reference.X,'rotated X extent matches eight corners')
    near(half.Y,reference.Y,'rotated Y extent matches eight corners')
    near(half.Z,reference.Z,'rotated Z extent matches eight corners')
    for _,targetRotation in ipairs({CFrame.Angles(0,0,0),CFrame.Angles(0.8,-0.5,0.3),CFrame.Angles(0,0,math.pi)}) do
      local settings={x=3,y=4,z=5,pitch=angles[1],yaw=angles[2],roll=angles[3],variant='fixture'}
      local fitted,info=Geometry.fit(size,Vector3.new(2,2,1)*scale,targetRotation,settings)
      check(fitted~=nil,'valid root sizes fit')
      local world=targetRotation:VectorToWorldSpace(offset(fitted))
      near(world.X,0,'fit remains below in world X')
      near(world.Z,0,'fit remains below in world Z')
      near(world.Y,-info.distance,'fit remains below a tilted or inverted target')
      check(info.distance>0 and info.distance<=20,'fit distance is bounded')
      check(fitted.pitch==settings.pitch and fitted.yaw==settings.yaw and fitted.roll==settings.roll,'all custom angles preserved')
      check(settings.x==3 and settings.y==4 and settings.z==5,'fit leaves input table intact')
      local choices=Geometry.candidates(size,Vector3.new(2,2,1)*scale,targetRotation,settings,1e30,0/0)
      check(#choices>=2 and #choices<=10,'candidate count is bounded')
      check(choices[1].settings.y==4,'current mount remains the first comparison')
      for index,choice in ipairs(choices) do
        check(choice.power==R.POWER_LIMIT and choice.spin==0,'candidate power and spin finite and clamped')
        for _,key in ipairs({'x','y','z'}) do check(math.abs(choice.settings[key])<=20,'candidate offset in control range') end
        for _,key in ipairs({'pitch','yaw','roll'}) do check(math.abs(choice.settings[key])<=180,'candidate angle in control range') end
        if index>1 then check(targetRotation:VectorToWorldSpace(offset(choice.settings)).Y<0,'fitted candidate remains below target') end
      end
    end
  end
end
check(Geometry.fit(Vector3.new(0,2,1),Vector3.new(2,2,1),CFrame.new(),originalSettings)==nil,'zero root extent rejected')
check(Geometry.fit(Vector3.new(0/0,2,1),Vector3.new(2,2,1),CFrame.new(),originalSettings)==nil,'NaN root extent rejected')
check(Geometry.fit(Vector3.new(math.huge,2,1),Vector3.new(2,2,1),CFrame.new(),originalSettings)==nil,'infinite root extent rejected')
local evidence={characterStable=true,contactCorrelated=true,visibleSpeedGain=400,residualDisplacement=60,baselineConfidence=0.8}
local sample={samples=3,nearby=3,downwardGain=300,downwardTravel=40}
local base=Geometry.score(evidence)
check(Geometry.score(evidence,sample)>base,'reliable downward measurements get bounded preference')
check(Geometry.score(evidence,sample)<=2700,'evidence score has a finite ceiling without a survey')

-- ---- void route ------------------------------------------------------------
-- A survey is optional everywhere. Without one nothing may change, which is what
-- keeps every check above this line describing the same behaviour it always did.
check(Geometry.route(nil)=='up','no survey cannot claim a void route')
check(Geometry.score(evidence,sample,nil)==Geometry.score(evidence,sample),'no survey scores exactly as before')
check(Geometry.voidProgress(sample,nil)==0 and Geometry.voidProgress(nil,{gap=100})==0,'progress needs both a sample and a survey')

local openMap={gap=500,drop=math.huge,gravity=196.2,edgeDistance=math.huge}
local ledge={gap=500,drop=8,gravity=196.2,edgeDistance=40,edgeDirection=Vector3.new(1,0,0)}
local sealed={gap=500,drop=8,gravity=196.2,edgeDistance=math.huge}
check(Geometry.route(openMap)=='down','clear fall below the target is a drop')
check(Geometry.route(ledge)=='lateral','a floor with a nearby opening routes sideways')
check(Geometry.route(sealed)=='up','an enclosed map has no void route')
check(Geometry.route({gap=0,drop=math.huge,gravity=196.2})=='up','a target at the void plane has nowhere left to go')
check(Geometry.route({gap=0/0,drop=math.huge,gravity=196.2})=='up','a NaN gap cannot claim a route')

-- Falling is measured against the whole distance to the void, and capped by the
-- room that actually exists: a target shoved into a floor has not been voided.
local blocked={downwardTravel=400,downwardGain=900,edgeTravel=0}
check(Geometry.voidProgress(blocked,{gap=500,drop=2,gravity=196.2})<0.05,'a floor two studs down is not a void drop')
local falling={downwardTravel=100,downwardGain=200,edgeTravel=0}
local progress=Geometry.voidProgress(falling,openMap)
check(progress>0.5 and progress<=1,'a real drop on an open map is most of the way there')
check(Geometry.voidProgress({voided=true,downwardTravel=0,downwardGain=0},openMap)==1,'crossing the void plane is complete')
check(Geometry.voidProgress({downwardTravel=1e9,downwardGain=1e9,edgeTravel=1e9},openMap)<=1,'progress is bounded above')
check(Geometry.voidProgress({downwardTravel=0/0,downwardGain=math.huge,edgeTravel=0/0},openMap)==0,'invalid motion earns no progress')
-- On a ledge the sideways distance covered is the same measurement turned 90 degrees.
check(Geometry.voidProgress({downwardTravel=0,downwardGain=0,edgeTravel=20},ledge)>0.4,'covering half the distance to the opening counts')
check(Geometry.voidProgress({downwardTravel=0,downwardGain=0,edgeTravel=-50},ledge)==0,'travel away from the opening is not progress')

-- Reaching the void has to beat throwing someone hard, or the tune keeps picking
-- the launch it already preferred.
local fast={characterStable=true,contactCorrelated=true,visibleSpeedGain=2000,residualDisplacement=500,baselineConfidence=1}
local fastSample={samples=3,nearby=3,downwardGain=0,downwardTravel=0,edgeTravel=0}
local dropped={characterStable=true,contactCorrelated=true,visibleSpeedGain=200,residualDisplacement=20,baselineConfidence=1}
local droppedSample={samples=3,nearby=3,downwardGain=0,downwardTravel=0,edgeTravel=0,voided=true}
check(Geometry.score(dropped,droppedSample,openMap)>Geometry.score(fast,fastSample,openMap),'a voided target beats a faster one that stayed up')
check(Geometry.score(evidence,sample,openMap)<=2700+Geometry.VOID_WEIGHT,'surveyed score still has a finite ceiling')
local unsure=table.clone(evidence); unsure.baselineConfidence=0.1
near(Geometry.score(unsure,sample,openMap),Geometry.score(unsure),'an uncertain baseline earns no void credit either')
local noContact=table.clone(evidence); noContact.contactCorrelated=false
check(Geometry.score(noContact,droppedSample,openMap)==0,'a target that fell on its own still cannot win')

-- ---- facing the target ------------------------------------------------------
-- The whole design rests on one property: a world-Y yaw pre-multiplied onto the
-- mount rotation leaves the Y component of every axis alone, and the fitted
-- separation is measured from exactly those components. If that ever stops being
-- true, the body could turn and quietly drag the contact geometry with it.
for _,angles in ipairs({{0,0,0},{-90,0,0},{30,40,50},{-85,170,-130}}) do
  local mount=CFrame.Angles(math.rad(angles[1]),math.rad(angles[2]),math.rad(angles[3]))
  local plain=Geometry.projectedHalf(Vector3.new(2,3,0.75),mount)
  for _,yaw in ipairs({0,0.3,1.2,math.pi,-2.4,6.0}) do
    local turned=Geometry.projectedHalf(Vector3.new(2,3,0.75),CFrame.Angles(0,yaw,0)*mount)
    near(turned.Y,plain.Y,'a world-Y facing yaw cannot change the fitted separation')
  end
end

R.faceTarget=true; R.facingYaw=nil
local function at(x,y,z) return {Position=Vector3.new(x,y,z)} end
-- Roblox look vectors are -Z, so facing a target on -Z is a yaw of zero.
local upright=CFrame.Angles(0,0,0)
local origin=Vector3.new(0,0,0)
near(R.facing(at(0,0,-10),origin,upright),0,'a target straight ahead needs no turn')
near(R.facing(at(10,0,0),origin,upright),math.atan2(-10,0),'a target to the side turns the body toward it')
local held=R.facing(at(10,0,0),origin,upright)
-- Mounted directly under a target there is no horizontal heading to compute.
check(R.facing(at(0,0,0),Vector3.new(0,-0.01,0),upright)==held,'straight overhead holds the last heading instead of spinning')
check(R.facing(at(0.2,0,0.2),origin,upright)==held,'noise inside the deadzone does not re-aim')
check(R.facing(at(0/0,0,0),origin,upright)==held,'an invalid target position holds the last heading')
R.faceTarget=false
check(R.facing(at(10,0,0),origin,upright)==nil,'turning the option off leaves the mount rotation alone')
R.faceTarget=true; R.facingYaw=nil
check(R.facing(at(0,0,0),origin,upright)==nil,'with no heading yet, overhead stays unrotated rather than guessing')

-- The body must end up pointing AT the target from any mount pose, including the
-- pitched-flat fling mount whose look vector aims at the floor.
for _,pose in ipairs({{0,0,0},{-90,0,0},{-90,35,0},{0,120,0},{-90,0,25}}) do
  local rotation=CFrame.Angles(math.rad(pose[1]),math.rad(pose[2]),math.rad(pose[3]))
  for _,spot in ipairs({{0,0,-10},{10,0,0},{0,0,10},{-10,0,0},{7,0,7}}) do
    R.facingYaw=nil
    local target=at(spot[1],spot[2],spot[3])
    local yaw=R.facing(target,origin,rotation)
    local turned=CFrame.Angles(0,yaw,0)*rotation
    local forward=turned.LookVector
    local flatForward=Vector3.new(forward.X,0,forward.Z)
    if flatForward.Magnitude<0.25 then
      forward=turned.UpVector
      flatForward=Vector3.new(forward.X,0,forward.Z)
    end
    flatForward=flatForward/flatForward.Magnitude
    local wanted=Vector3.new(spot[1],0,spot[3])
    wanted=wanted/wanted.Magnitude
    check(flatForward.X*wanted.X+flatForward.Z*wanted.Z>0.999,'the body points at the target from any mount pose')
  end
end
R.facingYaw=nil

-- ---- above-root fit ---------------------------------------------------------
-- The mount that sends a target down is the mirror of the one that sends it up.
for _,targetRotation in ipairs({CFrame.Angles(0,0,0),CFrame.Angles(0.8,-0.5,0.3)}) do
  local settings={x=0,y=0,z=0,pitch=-90,yaw=0,roll=0,variant='fixture'}
  local below,belowInfo=Geometry.fit(Vector3.new(2,2,1),Vector3.new(2,2,1),targetRotation,settings,-1)
  local above,aboveInfo=Geometry.fit(Vector3.new(2,2,1),Vector3.new(2,2,1),targetRotation,settings,1)
  check(belowInfo.side==-1 and aboveInfo.side==1,'each fit reports which side it mounted')
  near(belowInfo.distance,aboveInfo.distance,'both sides use the same fitted separation')
  near(above.x,-below.x,'above-root X mirrors below-root')
  near(above.y,-below.y,'above-root Y mirrors below-root')
  near(above.z,-below.z,'above-root Z mirrors below-root')
  local default=Geometry.fit(Vector3.new(2,2,1),Vector3.new(2,2,1),targetRotation,settings)
  near(default.y,below.y,'omitting the side keeps the original below-root fit')
end

-- A surveyed drop puts the void mounts in front of the upward ones, because the
-- sampling loop stops early once the target is moving and later mounts are never
-- reached. Without a survey the list is byte-for-byte what it was.
local plain=Geometry.candidates(Vector3.new(2,2,1),Vector3.new(2,2,1),CFrame.new(),originalSettings,1e8,1e8)
local routed=Geometry.candidates(Vector3.new(2,2,1),Vector3.new(2,2,1),CFrame.new(),originalSettings,1e8,1e8,openMap)
check(#routed>#plain,'a void route adds mounts')
check(routed[2].label:find('Void drop')~=nil,'the void mount is tried before the upward fit')
check(plain[2].label=='Fitted below root','no survey leaves the candidate order untouched')
local sideways=Geometry.candidates(Vector3.new(2,2,1),Vector3.new(2,2,1),CFrame.new(),originalSettings,1e8,1e8,ledge)
check(sideways[2].label:find('Void edge')~=nil,'a ledge routes the first mounts sideways')
local enclosed=Geometry.candidates(Vector3.new(2,2,1),Vector3.new(2,2,1),CFrame.new(),originalSettings,1e8,1e8,sealed)
check(#enclosed==#plain,'an enclosed map adds nothing to chase')
local invalid=table.clone(evidence); invalid.contactCorrelated=false
check(Geometry.score(invalid,sample)==0,'ordinary motion without contact evidence cannot win')
invalid=table.clone(evidence); invalid.characterStable=false
check(Geometry.score(invalid,sample)==0,'character replacement cannot win')
invalid=table.clone(evidence); invalid.visibleSpeedGain=math.huge
check(Geometry.score(invalid,sample)==0,'infinite motion cannot win')
invalid=table.clone(evidence); invalid.residualDisplacement=0/0
check(Geometry.score(invalid,sample)==0,'NaN evidence cannot win')
invalid=table.clone(evidence); invalid.baselineConfidence=0.1
near(Geometry.score(invalid,sample),Geometry.score(invalid),'uncertain baseline cannot earn downward bonus')
local remoteRoot=target.Character:FindFirstChildOfClass('Humanoid').RootPart
local ownRoot=selfPlayer.Character:FindFirstChildOfClass('Humanoid').RootPart
R.tuneSample={part=remoteRoot,root=ownRoot,at=0,position=Vector3.new(0,20,0),velocity=Vector3.new(0,-5,0),gravity=196.2,
  samples=0,nearby=0,nearDistance=1,downwardGain=0,downwardTravel=0}
for _,elapsed in ipairs({0.1,0.2,0.3}) do
  now=elapsed
  remoteRoot.Position=Vector3.new(0,20-5*elapsed-0.5*196.2*elapsed^2,0)
  remoteRoot.AssemblyLinearVelocity=Vector3.new(0,-5-196.2*elapsed,0)
  R.observe(remoteRoot,ownRoot,CFrame.new(ownRoot.Position))
end
near(R.tuneSample.downwardGain,0,'ordinary free fall receives no downward velocity gain')
near(R.tuneSample.downwardTravel,0,'ordinary free fall receives no downward displacement gain')
local function root(player) return player.Character:FindFirstChildOfClass('Humanoid').RootPart end
local function reset(mode)
  R.stop('fixture reset'); pending={}; now=0; live=true; behaviour=mode or 'normal'; attempts=0; notes={}; faults={}
  selfPlayer.Character=character(); target.Character=character(); target.Parent=players
  R.settings=table.clone(originalSettings); R.targetName='Alpha'; R.repRoot=true; R.fling=true
  K.cfg.repPower=123456; K.cfg.repSpin=234567; K.cfg.flingDuration=6; K.flinging=false
end
local function step()
  now+=0.04
  if K.flinging then
    local other,own=root(target),root(selfPlayer)
    local elapsed=now-attemptAt
    other.Position=Vector3.new(0,4-50*elapsed,0)
    other.AssemblyLinearVelocity=Vector3.new(0,-50,0)
    local desired=R.mount(other,other.Position,0)
    own.Position=desired.Position
    R.observe(other,own,desired)
    if behaviour~='timeout' and elapsed>=0.18 then
      K.flinging=false
      K.lastThrowEvidence={characterStable=true,contactCorrelated=behaviour~='no_evidence',
        visibleSpeedGain=attempts==2 and 900 or 200,residualDisplacement=30,baselineConfidence=0.9}
    end
  end
  for _,entry in ipairs(table.clone(pending)) do
    if coroutine.status(entry.thread)~='dead' and entry.at<=now then
      local ok,wait=coroutine.resume(entry.thread); assert(ok,wait)
      entry.at=now+(wait or 0)
    end
  end
end
local function steps(count) for _=1,count do step() end end
local function restored(message)
  for key,value in pairs(originalSettings) do check(R.settings[key]==value,message..': '..key) end
  check(K.cfg.repPower==123456 and K.cfg.repSpin==234567 and K.cfg.flingDuration==6,message..': engine settings')
  check(R.tuning==nil and R.tuneThread==nil and R.tuneSample==nil and not K.flinging,message..': complete cleanup')
end
reset()
local expected=Geometry.candidates(root(selfPlayer).Size,root(target).Size,root(target).CFrame,R.settings,K.cfg.repPower,K.cfg.repSpin)
R.autoTune(); steps(250)
check(attempts==#expected,'all bounded candidates compared when target stays stable')
for key,value in pairs(expected[2].settings) do check(R.settings[key]==value,'best locally observed candidate applied') end
check(K.cfg.repPower==123456 and K.cfg.repSpin==234567 and K.cfg.flingDuration==6,'tuning preserves configured force and restores duration')
check(R.tuning==nil and R.tuneThread==nil and R.tuneSample==nil,'successful tune clears lifecycle state')
reset('no_evidence'); R.autoTune(); steps(250); restored('no response keeps original setup')
reset(); R.autoTune(); steps(15); check(attempts>=2,'cancel fixture reaches a fitted candidate')
R.stop('manual stop'); local stoppedAttempts=attempts; steps(250); restored('manual stop'); check(attempts==stoppedAttempts,'no later attempt after stop')
reset(); R.autoTune(); steps(2); target.Character=character(); steps(20); restored('target respawn cancels')
reset(); R.autoTune(); steps(2); selfPlayer.Character=character(); steps(20); restored('own respawn cancels')
reset(); R.autoTune(); steps(2); target.Parent=nil; steps(20); restored('target leaving cancels')
reset(); R.autoTune(); steps(2); live=false; steps(20); restored('session ending cancels')
reset('timeout'); R.autoTune(); steps(150); restored('timed out sample cancels')
reset('refuse'); R.autoTune(); restored('refused start cancels synchronously')
reset('error'); R.autoTune(); restored('failed start cancels synchronously'); check(#faults==1,'unexpected failure reported once')
reset(); R.fling=false; R.autoTune(); check(attempts==0 and R.settings.y<0,'fling-off tune only fits geometry')
print(tostring(checks)..' geometry / evidence / tuning lifecycle checks passed')
'''

facing = re.search(r"function R\.facing\b.*?\nend", addon, re.S)
assert facing, "R.facing is missing from the addon"
for forbidden in ("Camera", "followCamera", "cameraOwned"):
    assert forbidden not in facing.group(0), f"facing must stay body-only; it references {forbidden}"

with tempfile.TemporaryDirectory(prefix="reproot-geometry-") as folder:
    fixture = Path(folder) / "geometry.luau"
    fixture.write_text(prelude + "\n" + addon + "\n" + tests, encoding="utf-8")
    result = subprocess.run([str(RUNTIME), str(fixture)], text=True, capture_output=True)
    print(result.stdout + result.stderr, end="")
    raise SystemExit(result.returncode)
