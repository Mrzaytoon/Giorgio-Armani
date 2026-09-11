"""Exercise the shipped queue with a deterministic clock and fake player lifecycles."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root=Path(__file__).resolve().parent
runtime=Path.home()/"AppData/Local/Temp/luaudl/luau.exe"
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("source",nargs="?",type=Path,
                    help="Optional assembled script; otherwise verify rep-session.lua")
source_path=parser.parse_args().source
session=(root/'rep-session.lua').read_text(encoding='utf-8')
if source_path:
    assembled=source_path.read_text(encoding='utf-8')
    # Extract the exact embedded session, including any presentation-build edits.
    start=assembled.index(session.splitlines()[0])
    end=min(assembled.index(boundary,start) for boundary in
            ('\n-- Giorgio / player directory.', '\n-- Independent roster window.')
            if boundary in assembled[start:])
    session=assembled[start:end]
prelude=r'''
local now=0
local os={clock=function() return now end}
local pending={}
local task={spawn=function(fn)
  local thread=coroutine.create(fn); table.insert(pending,thread)
  local ok,err=coroutine.resume(thread); assert(ok,err); return thread
end,wait=function(dt) now+=(dt or 0.03); coroutine.yield() end,
cancel=function(thread) coroutine.close(thread) end}
local function signal() return {Connect=function(_,fn) return {Disconnect=function() end} end} end
local workspace={FallenPartsDestroyHeight=-500,GetPropertyChangedSignal=function() return signal() end}
local Vector3={zero={X=0,Y=0,Z=0}}
local Players={members={}}
function Players:GetPlayers() return self.members end
local function player(name,id)
  local part={Position={X=0,Y=2,Z=0},CFrame=name..'-home',Anchored=false}
  local hum={Health=100,Sit=false,RootPart=part}
  local ch={hum=hum,FindFirstChildOfClass=function(self,class) return class=='Humanoid' and self.hum or nil end}
  return {Name=name,UserId=id,Character=ch,Parent=Players}
end
local LP=player('Self',1)
local a,b,c=player('Alpha',2),player('Beta',3),player('Gamma',4)
Players.members={LP,a,b,c}
local function rootOf(p)
  return p and p.Character and p.Character.hum.Health>0 and p.Character.hum.RootPart or nil
end
local attempts={}
local K={selected={},whitelist={},cfg={returnHome=true},forgetIntel=function() end,
  stopFling=function() K.flinging=false end}
-- The closure needs the declared local, not a global from a table initializer.
function K.stopFling() K.flinging=false end
K.stopAttempt=K.stopFling
function K.returnToRunHome() end
local R={repRoot=true,fling=true,voidGuard=true,followCamera=false,loopMode='Selected players',
  controls={},targetName='Alpha',turnDuration=0.25}
function R.runOne(name) attempts[#attempts+1]=name; K.flinging=false; return true end
function R.cancelPhysics() K.flinging=false end
local L={live=function() return true end,hold=function() end,cleanup=function() end,
  fault=function(_,err) error(err) end,Cfg={setFeat=function() end},Toast={warn=function() end},
  RunService={Heartbeat=signal(),RenderStepped=signal()}}
local C={}
local function announce() end
local function studioTarget()
  for _,p in Players.members do if p.Name==R.targetName then return p end end
end
'''
tests=r'''
local count=0
local function check(condition,message) count+=1; assert(condition,message) end
local function steps(n)
  for _=1,n do
    for _,thread in table.clone(pending) do
      if coroutine.status(thread)~='dead' then local ok,err=coroutine.resume(thread); assert(ok,err) end
    end
  end
end
local function reset()
  R.endQueue('test reset'); pending={}; attempts={}; now=0
  K.selected={Alpha=true,Beta=true,Gamma=true}; R.loopMode='Selected players'
  Players.members={LP,a,b,c}; a.Parent=Players; b.Parent=Players; c.Parent=Players
  a.Character.hum.Health=100; b.Character.hum.Health=100; c.Character.hum.Health=100
  a.Character.hum.Sit=false; b.Character.hum.Sit=false; c.Character.hum.Sit=false
end
reset()
a.Character.hum.Health=0
check(R.beginQueue('Alpha'),'queue starts')
steps(20)
check(table.find(attempts,'Alpha')==nil,'dead player must not receive a turn')
check(table.find(attempts,'Beta')~=nil and table.find(attempts,'Gamma')~=nil,'dead first player must not block healthy players')
a.Character.hum.Health=100
steps(20)
check(table.find(attempts,'Alpha')~=nil,'respawn must re-enter without restarting queue')
local beta,gamma=0,0
for _,name in attempts do if name=='Beta' then beta+=1 elseif name=='Gamma' then gamma+=1 end end
check(math.abs(beta-gamma)<=1,'ready peers must get fair turns')
reset()
R.loopMode='Loop target'; a.Character.hum.Health=0
R.beginQueue('Alpha'); steps(12)
check(R.queue~=nil and #attempts==0,'single dead target must remain queued')
a.Character.hum.Health=100; steps(10)
check(#attempts>0,'single target resumes on respawn')
a.Parent=nil; Players.members={LP,b,c}; steps(6)
check(R.queue==nil,'single target leaving ends the session')
reset()
R.beginQueue('Alpha'); local old=pending[1]
R.endQueue('stop'); R.loopMode='Loop target'; R.beginQueue('Beta')
local current=R.queue
if coroutine.status(old)~='dead' then local ok,err=coroutine.resume(old); assert(ok,err) end
check(R.queue==current,'cancelled coroutine cannot stop a newer session')
steps(6)
check(R.queue and R.queue.fixed==b,'restart keeps the new target')
reset()
local runImmediately=R.runOne
R.runOne=function(name)
  task.wait(1.6) -- the original runner waits for a previous transaction here
  attempts[#attempts+1]=name; K.flinging=true; return true
end
R.beginQueue('Alpha')
R.endQueue('stop during handoff')
steps(10)
check(#attempts==0 and not K.flinging,'stop during a yielding start must prevent a late dispatch')
R.runOne=runImmediately
reset()
b.Character.hum.Sit=true
R.beginQueue('Alpha'); steps(12)
check(table.find(attempts,'Beta')==nil,'seated player is skipped')
b.Character.hum.Sit=false; steps(12)
check(table.find(attempts,'Beta')~=nil,'standing player re-enters')
K.selected={}; steps(5)
check(R.queue==nil,'empty selection releases the session')
reset()
R.loopMode='All players'; Players.members={LP,a}; R.beginQueue('Alpha'); steps(6)
check(R.queue and not R.queue.single,'a one-member group must keep bounded turns for new arrivals')
Players.members={LP,a,b}; steps(15)
check(table.find(attempts,'Beta')~=nil,'all-player mode discovers arrivals')
R.endQueue('done'); local before=#attempts; steps(15)
check(#attempts==before,'stop prevents further dispatches')
check(R.Queue.pick({},0,0)==nil,'empty selection is safe')
local e,i=R.Queue.pick({{ready=false},{ready=true},{ready=true}},0,0)
check(e~=nil and i==2,'unready first entry does not block second')
e,i=R.Queue.pick({{ready=false},{ready=true},{ready=true}},i,0)
check(i==3,'round-robin advances')
check(R.Queue.backoff(100)<=2,'no-response retries remain bounded')
check(not R.validPosition({X=0/0,Y=0,Z=0}),'NaN position is rejected')
check(not R.validPosition({X=math.huge,Y=0,Z=0}),'infinite position is rejected')
R.setVoidGuard(false)
check(workspace.FallenPartsDestroyHeight==-500,'void toggle restores original floor')
R.setVoidGuard(true)
check(workspace.FallenPartsDestroyHeight~=workspace.FallenPartsDestroyHeight,'void enabled removes local deletion floor')
print(string.format('PASS: %d queue, respawn, fairness, cancellation and void checks',count))
'''
with tempfile.TemporaryDirectory(prefix='reproot-queue-') as folder:
    script=Path(folder)/'queue.luau'
    script.write_text(prelude+session+tests,encoding='utf-8')
    subprocess.run([str(runtime),str(script)],check=True)
