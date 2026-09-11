-- One queue owns the current attempt. Sleeping players never block the next.
-- QUEUE_CORE_BEGIN
local Queue = {}
function Queue.pick(entries, cursor, now)
  local count=#entries
  if count==0 then return nil,0 end
  for offset=1,count do
    local index=(cursor+offset-1)%count+1
    local entry=entries[index]
    if entry.ready and (entry.readyAt or 0)<=now then return entry,index end
  end
  return nil,cursor
end
function Queue.backoff(failures)
  return math.min(2,0.15*2^math.min(failures,4))
end
function Queue.finitePosition(v)
  return v.X==v.X and v.Y==v.Y and v.Z==v.Z
    and math.abs(v.X)<math.huge and math.abs(v.Y)<math.huge and math.abs(v.Z)<math.huge
end
-- QUEUE_CORE_END
R.Queue=Queue
R.validPosition=Queue.finitePosition
R.queueSerial=0
local voidOriginal=workspace.FallenPartsDestroyHeight
-- The guard below overwrites this property with NaN, so anything that needs the
-- map's actual floor has to read the value captured before that happened.
R.voidFloor=voidOriginal
R.voidOriginal=voidOriginal
local voidWriting=false
local function maintainVoid()
  if not L.live() or not R.voidGuard or voidWriting then return end
  local floor=workspace.FallenPartsDestroyHeight
  if floor~=floor then return end
  voidWriting=true
  local ok,err=pcall(function() workspace.FallenPartsDestroyHeight=0/0 end)
  voidWriting=false
  if not ok then R.voidGuard=false; L.fault("reproot.void",err) end
end
function R.setVoidGuard(value)
  R.voidGuard=value==true
  if R.voidGuard then maintainVoid()
  else pcall(function() workspace.FallenPartsDestroyHeight=voidOriginal end) end
  return R.voidGuard==value
end
function R.restoreVoidSetting()
  if R.voidGuard then maintainVoid()
  else workspace.FallenPartsDestroyHeight=voidOriginal end
end
L.hold(workspace:GetPropertyChangedSignal("FallenPartsDestroyHeight"):Connect(maintainVoid))
-- The frame check also covers engines that coalesce a hidden NaN property event.
L.hold(L.RunService.Heartbeat:Connect(maintainVoid))
L.cleanup(function()
  R.voidGuard=false
  pcall(function() workspace.FallenPartsDestroyHeight=voidOriginal end)
end,-100)
R.setVoidGuard(R.voidGuard)

local cameraSubject,cameraSnapshot,focusPlayer
local function releaseCamera()
  if cameraSnapshot then
    local saved=cameraSnapshot
    local camera=workspace.CurrentCamera
    if camera==saved.camera and camera.CameraSubject==cameraSubject then
      local subject=saved.subject
      if not subject or not subject.Parent or (saved.ownSubject and LP.Character~=saved.character) then
        subject=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
      end
      pcall(function() camera.CameraSubject=subject; camera.CameraType=saved.kind end)
    end
  end
  R.cameraOwned=false; cameraSnapshot=nil; focusPlayer=nil
  cameraSubject=nil
end
local function follow(player)
  focusPlayer=player
  if not R.followCamera then return end
  local camera=workspace.CurrentCamera
  local part=rootOf(player)
  if not camera or not part then return end
  local subject=player.Character:FindFirstChildOfClass("Humanoid") or part
  if not cameraSnapshot or cameraSnapshot.camera~=camera then
    cameraSnapshot={camera=camera,subject=camera.CameraSubject,kind=camera.CameraType,
      character=LP.Character,ownSubject=camera.CameraSubject and camera.CameraSubject.Parent==LP.Character}
  end
  R.cameraOwned=true
  cameraSubject=subject
  if camera.CameraType~=Enum.CameraType.Custom then camera.CameraType=Enum.CameraType.Custom end
  if camera.CameraSubject~=subject then camera.CameraSubject=subject end
end
function R.setFollowCamera(value)
  R.followCamera=value==true
  if not R.followCamera then releaseCamera()
  elseif R.queue and R.queue.current then follow(R.queue.current.player) end
  return true
end
L.hold(L.RunService.RenderStepped:Connect(function()
  if not L.live() or not R.followCamera or not focusPlayer then return end
  local part=rootOf(focusPlayer)
  if not part or not Queue.finitePosition(part.Position) then return end
  follow(focusPlayer)
end))

local function readiness(entry)
  local player=entry.player
  if player.Parent~=Players then entry.state="Left"; return false end
  if K.whitelist[player.Name:lower()] then entry.state="Excluded"; return false end
  local ch=player.Character
  local hum=ch and ch:FindFirstChildOfClass("Humanoid")
  local part=hum and hum.RootPart
  if not part or not hum or hum.Health<=0 then entry.state="Waiting for respawn"; return false end
  if hum.Sit or part.Anchored then entry.state="Waiting to stand"; return false end
  if ch:FindFirstChildOfClass("ForceField") then entry.state="Spawn protection"; return false end
  if not Queue.finitePosition(part.Position) then entry.state="Invalid position"; return false end
  entry.state="Ready"; return true
end
local function queueMembers(queue)
  local list={}
  if queue.mode=="Loop target" then
    if queue.fixed and queue.fixed.Parent==Players then list[1]=queue.fixed end
  else
    for _,player in ipairs(Players:GetPlayers()) do
      if player~=LP and (queue.mode=="All players" or K.selected[player.Name]) then list[#list+1]=player end
    end
  end
  table.sort(list,function(a,b) return a.UserId<b.UserId end)
  local entries={}
  for _,player in ipairs(list) do
    local entry=queue.byId[player.UserId]
    if not entry then
      entry={player=player,passes=0,failures=0,readyAt=0}
      queue.byId[player.UserId]=entry
    end
    entry.ready=readiness(entry)
    entries[#entries+1]=entry
  end
  queue.entries=entries
  -- A group keeps short turns even when only one member is currently present,
  -- so new arrivals and changes to the selected group are discovered promptly.
  queue.single=queue.mode=="Loop target"
  return entries
end
function R.endQueue(why,opts)
  local queue=R.queue
  R.queueSerial+=1
  R.queue=nil
  if queue then
    K.runHome=queue.home
    R.cancelPhysics(why or "loop stopped",{home=false})
    -- startFling can yield while the previous transaction releases. Cancelling
    -- its caller prevents a stopped queue from starting after that wait ends.
    if queue.thread and queue.thread~=coroutine.running() then
      pcall(task.cancel,queue.thread)
    end
    -- During a respawn wait the attempt is already over. It owns no velocities,
    -- but the session still owes the operator their original place on stop.
    local own=rootOf(LP)
    if own and LP.Character==queue.character and K.cfg.returnHome and queue.home and not (opts and opts.home==false) then
      K.returnToRunHome()
      own.AssemblyLinearVelocity=Vector3.zero; own.AssemblyAngularVelocity=Vector3.zero
      own.CFrame=queue.home
    end
  end
  releaseCamera()
  return queue~=nil
end
function R.beginQueue(name)
  if not R.repRoot then return false,"Rep Root is off","user" end
  if R.tuning then return false,"Cancel auto-tune before starting a loop","user" end
  if type(name)=="string" and name~="" then R.targetName=name; if R.controls.targetName then R.controls.targetName:set(name) end end
  local fixed=studioTarget()
  if R.loopMode=="Loop target" and not fixed then return false,"Enter one unambiguous target name","user" end
  if R.loopMode=="Selected players" and next(K.selected)==nil then return false,"Pick players in the player panel or add a target below","user" end
  R.endQueue("loop restarted")
  local own=rootOf(LP)
  local serial=R.queueSerial
  local queue={mode=R.loopMode,fixed=fixed,entries={},byId={},cursor=0,passes=0,
    character=LP.Character,home=own and own.CFrame,serial=serial}
  R.queue=queue
  queueMembers(queue)
  queue.thread=task.spawn(function()
    local ok,err=pcall(function()
      while L.live() and R.queue==queue and R.queueSerial==serial do
        local entries=queueMembers(queue)
        if #entries==0 then R.endQueue("all targets left or were removed"); break end
        local ownRoot=rootOf(LP)
        if not ownRoot then queue.state="Waiting for your respawn"; task.wait(0.15); continue end
        if LP.Character~=queue.character then queue.character=LP.Character; queue.home=ownRoot.CFrame end
        local entry,index=Queue.pick(entries,queue.cursor,os.clock())
        if not entry then queue.state="Waiting for targets"; task.wait(0.15); continue end
        queue.cursor=index; queue.current=entry; queue.state="Active"
        entry.state="Driving"; entry.passes+=1; queue.passes+=1
        follow(entry.player)
        K.cfg.flingMode="One target"; K.cfg.maxAttempts=1
        K.cfg.waitRespawn=false; K.cfg.waitSeated=false; K.cfg.watchImmune=false
        K.forgetIntel(entry.player.Name)
        local started=R.runOne(entry.player.Name)
        local began=os.clock()
        if started then
          repeat
            task.wait(0.08)
            if R.queue~=queue or R.queueSerial~=serial or not L.live() then return end
            if entry.player.Parent~=Players or not rootOf(entry.player) or not rootOf(LP) then
              K.stopAttempt("character changed; keeping target queued"); break
            end
            -- Single target holds until death/leave. A group always hands off.
            if not queue.single and os.clock()-began>R.turnDuration+3 then
              K.stopAttempt("next queued target"); break
            end
          until not K.flinging
        end
        if R.queue~=queue or R.queueSerial~=serial or not L.live() then return end
        local evidence=K.lastThrowEvidence
        local gained=started and evidence and evidence.contactCorrelated
        entry.failures=gained and 0 or math.min(entry.failures+1,4)
        entry.readyAt=os.clock()+(gained and 0.05 or Queue.backoff(entry.failures))
        entry.state=gained and "Observed response" or "Retry queued"
        -- Wait for the existing transaction's recovery without dropping camera focus.
        local deadline=os.clock()+1.6
        while K.returningHome and os.clock()<deadline and R.queue==queue do task.wait(0.04) end
        task.wait(0.05)
      end
    end)
    if not ok and R.queue==queue then
      L.fault("reproot.queue",err); R.endQueue("queue error")
      L.Toast.warn("Loop stopped",tostring(err))
    end
  end)
  return true,"Persistent "..R.loopMode:lower().." started"
end
function R.buildQueue(win)
  local page=win:tab({name="Targets",chrome="eye",desc="Persistent loops, selected groups and live queue state"}).body
  C.ctx("reproot")
  R.controls.loopMode=C.dropdown(page,{id="reproot.loopMode",text="Target mode",
    items={"Loop target","Selected players","All players","Single burst"},default=R.loopMode,
    callback=function(v) R.stop("target mode changed"); R.loopMode=v; return true end})
  C.paragraph(page,"Loop target stays with one player through the throw and reacquires after respawn. Groups rotate through ready players; respawning or seated players keep their place without delaying others.")
  C.actions(page,{{text="Add named target",primary=true,callback=function()
    local player=studioTarget()
    if player then K.select(player.Name,true); announce("Added",player.Name.." is in the selected group")
    else L.Toast.warn("Select target","Enter a unique name on the Rep Root page") end
  end},{text="Open player panel",callback=function() L.Side.show() end},
  {text="Clear selected",callback=function() K.clearSelection() end}})
  C.actions(page,{{text="Start loop",primary=true,callback=R.start},{text="Stop / restore",callback=function() R.stop("loop stopped") end}})
  R.controls.turnDuration=C.slider(page,{id="reproot.turnDuration",text="Seconds per group turn",
    desc="Drive time before handing the binding to the next ready target",min=0.25,max=5,step=0.05,default=R.turnDuration,
    callback=function(v) R.turnDuration=math.clamp(v,0.25,5) end})
  C.section(page,"queue status")
  local statusFrame=C.paragraph(page,"No active queue.")
  local label=statusFrame:FindFirstChildWhichIsA("TextLabel",true)
  local acc=0
  local conn
  conn=L.RunService.Heartbeat:Connect(function(dt)
    if not statusFrame.Parent or not L.live() then conn:Disconnect(); return end
    acc+=dt; if acc<0.25 then return end; acc=0
    local queue=R.queue
    if not queue then label.Text="No active queue. Selected players: "..tostring(#K.selectedList()); return end
    local lines={string.format("%s | %s | %d passes",queue.mode,queue.state or "Starting",queue.passes)}
    for index,entry in ipairs(queue.entries) do
      if index>15 then lines[#lines+1]="+ "..(#queue.entries-15).." more"; break end
      lines[#lines+1]=string.format("@%s  -  %s  (%d turns)",entry.player.Name,entry.state or "Queued",entry.passes)
    end
    label.Text=table.concat(lines,"\n")
  end)
  L.hold(conn)
end
