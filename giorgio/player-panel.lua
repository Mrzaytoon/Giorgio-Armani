-- Giorgio / player directory. Included inside the dedicated addon's scope.
-- The visible row pool is bounded; this window never owns a physics worker.
do
local Side=L.Side
local Panel={rows={},roster={},thumbs=Side._thumbs or {},portraits={},pending={},filter="All",query="",serial=0}
R.Panel=Panel
local mk=L.mk
local W,H,PITCH=720,620,66
local ink={paper=T.c.surface,white=T.c.raised,charcoal=T.c.text,muted=T.c.textMute,line=T.c.line,
  wash=T.c.hover,portrait=T.c.raised,green=Color3.fromRGB(150,184,158),danger=Color3.fromRGB(131,47,42)}
local serif=Enum.Font.Bodoni
local FONT=T.font.body
local MONO=T.font.mono

-- PANEL_CORE_BEGIN
local Directory={}
function Directory.matches(name,display,query,filter,queued,dist)
  local q=string.lower(query or "")
  local found=q=="" or string.find(string.lower(name),q,1,true)~=nil
    or string.find(string.lower(display),q,1,true)~=nil
  return found and (filter=="All" or filter=="Queued" and queued==true or filter=="Nearby" and dist<=250)
end
function Directory.window(scroll,height,pitch,total)
  local visible=math.max(1,math.ceil(height/pitch)+1)
  local first=math.clamp(math.floor(math.max(0,scroll)/pitch)+1,1,math.max(1,total))
  return first,math.min(visible,total-first+1)
end
function Directory.less(a,b,mode,distances)
  if mode=="name" then
    local an,bn=string.lower(a.DisplayName),string.lower(b.DisplayName)
    if an~=bn then return an<bn end
  elseif distances[a]~=distances[b] then return distances[a]<distances[b] end
  return a.UserId<b.UserId
end
function Directory.fit(vx,vy,width,height,x,y,preferred)
  local scale=math.max(.05,math.min(preferred or 1,(vx-16)/width,(vy-16)/height))
  local px=x or (vx-width*scale)*.5
  local py=y or (vy-height*scale)*.5
  return scale,math.clamp(px,8,math.max(8,vx-width*scale-8)),math.clamp(py,8,math.max(8,vy-height*scale-8))
end
function Directory.defaultScale(automatic)
  return math.min(automatic or 1,1.15)
end
function Directory.resize(vx,vy,width,height,x,y,start,dx,dy)
  -- Project the pointer onto the corner's diagonal, keeping the opposite
  -- corner still and the directory's columns at their authored proportions.
  local maximum=math.max(.05,math.min(2.2,(vx-x-8)/width,(vy-y-8)/height))
  local desired=start+(dx*width+dy*height)/(width*width+height*height)
  return math.clamp(desired,math.min(.55,maximum),maximum)
end
-- PANEL_CORE_END
Panel.Directory=Directory

local function animate(object,property,value,token)
  if object[property]~=value then M.to(object,property,value,token or "fast") end
end
local function frame(parent,name,pos,size,color)
  return mk("Frame",{Name=name,Position=pos,Size=size,BackgroundColor3=color or ink.paper,BorderSizePixel=0,Parent=parent})
end
local function text(parent,name,value,pos,size,fontSize,color,font)
  return mk("TextLabel",{Name=name,Text=value,Position=pos,Size=size,BackgroundTransparency=1,
    Font=font or FONT,TextSize=fontSize or 12,TextColor3=color or ink.charcoal,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,Parent=parent})
end
local function line(parent,name,pos,size)
  return frame(parent,name,pos,size or UDim2.new(1,0,0,1),ink.line)
end
local function sound(name,volume)
  if L.Giorgio and L.Giorgio.sound then L.Giorgio.sound(name,volume) end
end
local function button(parent,name,value,pos,size,callback,style)
  local filled=style=="solid" or style=="danger"
  local base=style=="danger" and ink.danger or ink.charcoal
  local foreground=style=="danger" and ink.charcoal or filled and ink.paper or ink.charcoal
  local b=mk("TextButton",{Name=name,Text=value,Position=pos,Size=size,AutoButtonColor=false,
    BackgroundTransparency=filled and 0 or 1,BackgroundColor3=filled and base or ink.wash,
    BorderSizePixel=0,TextSize=11,Font=FONT,TextColor3=foreground,Parent=parent})
  local underline=frame(b,"HoverRule",UDim2.new(0,filled and 12 or 0,1,-1),UDim2.new(0,0,0,1),foreground)
  b.MouseEnter:Connect(function()
    sound("hover",.14)
    animate(underline,"Size",UDim2.new(1,filled and -24 or 0,0,1),"base")
    if not filled then animate(b,"BackgroundTransparency",.5) end
  end)
  b.MouseLeave:Connect(function()
    animate(underline,"Size",UDim2.fromOffset(0,1),"base")
    if not filled then animate(b,"BackgroundTransparency",1) end
    animate(b,"TextTransparency",0)
  end)
  b.MouseButton1Down:Connect(function() animate(b,"TextTransparency",.4) end)
  b.MouseButton1Up:Connect(function() animate(b,"TextTransparency",0) end)
  b.Activated:Connect(function()
    animate(b,"TextTransparency",0)
    if L.live() and Side.open then sound("click",.32); L.try("giorgio.players."..name,callback) end
  end)
  return b
end
local function living(player)
  local character=player and player.Character
  local humanoid=character and character:FindFirstChildOfClass("Humanoid")
  return humanoid,humanoid and humanoid.RootPart
end
local function distance(player)
  local _,a=living(LP); local _,b=living(player)
  if not a or not b then return math.huge end
  local value=(a.Position-b.Position).Magnitude
  return finite(value) and value or math.huge
end
local function metric(value)
  if value==math.huge then return "—" end
  return value>=10000 and string.format("%.1fk",value/1000) or string.format("%.0f",value)
end
local function state(player)
  if not player then return "No player selected",ink.muted end
  local humanoid,part=living(player)
  if K.whitelist[player.Name:lower()] then return "Excluded",ink.muted end
  if not humanoid or not part or humanoid.Health<=0 then return "Respawning",ink.muted end
  if R.queue and R.queue.current and R.queue.current.player==player and K.flinging then return "Active target",ink.green end
  if humanoid.Sit or part.Anchored then return "Seated",ink.muted end
  if player.Character:FindFirstChildOfClass("ForceField") then return "Spawn protection",ink.muted end
  return "Ready",ink.green
end
local function selectedPlayer()
  local name=Side.state.selected
  local player=name and Players:FindFirstChild(name)
  return player~=LP and player or nil
end
local function restoreView()
  local previous=Panel.cameraSnapshot
  local camera=workspace.CurrentCamera
  Side.spectating=nil
  if previous and camera==previous.camera and camera.CameraSubject==Panel.cameraSubject and camera.CameraType==Enum.CameraType.Custom then
    local subject=previous.subject
    if not subject or not subject.Parent or previous.own and subject.Parent~=LP.Character then subject=living(LP) end
    if subject then camera.CameraSubject=subject end
    camera.CameraType=previous.kind
  end
  Panel.cameraSnapshot=nil; Panel.cameraSubject=nil
end
local function updateView()
  if not Side.spectating then return end
  if R.followCamera or R.cameraOwned then restoreView(); return end
  local player=Players:FindFirstChild(Side.spectating)
  if not player then restoreView(); return end
  local camera=workspace.CurrentCamera
  if not camera then return end
  local snapshot=Panel.cameraSnapshot
  if snapshot and snapshot.camera==camera then
    local expected=Panel.cameraSubject
    local localHumanoid=living(LP)
    local respawnReset=expected and (not expected.Parent or expected.Health<=0) and camera.CameraSubject==localHumanoid
    if camera.CameraType~=Enum.CameraType.Custom or camera.CameraSubject~=expected and not respawnReset then
      -- A new camera owner wins. Only an engine reset after target death is
      -- reacquired; otherwise this would fight cutscenes and other view tools.
      restoreView(); return
    end
  end
  local humanoid,part=living(player)
  if not humanoid or not part or humanoid.Health<=0 then return end
  if not Panel.cameraSnapshot or Panel.cameraSnapshot.camera~=camera then
    local subject=camera.CameraSubject
    if subject==Panel.cameraSubject then subject=snapshot and snapshot.subject or living(LP) end
    Panel.cameraSnapshot={camera=camera,subject=subject,kind=camera.CameraType,
      own=subject and subject.Parent==LP.Character}
  end
  Panel.cameraSubject=humanoid
  if camera.CameraSubject~=humanoid then camera.CameraSubject=humanoid end
  if camera.CameraType~=Enum.CameraType.Custom then camera.CameraType=Enum.CameraType.Custom end
end
-- Manual view and the queue share one camera. Transfer ownership before the
-- queue captures its restore subject, and release manual view on every Stop.
local sessionFollowCamera=R.setFollowCamera
function R.setFollowCamera(value)
  if value==true then restoreView() end
  return sessionFollowCamera(value)
end
local sessionStop=R.stop
function R.stop(why,opts)
  restoreView()
  return sessionStop(why,opts)
end
function Panel.view(player)
  if not player or player==LP or player.Parent~=Players then return false end
  if Side.spectating==player.Name then restoreView()
  else
    if R.controls.followCamera then R.controls.followCamera:set(false)
    elseif R.setFollowCamera then R.setFollowCamera(false) end
    Side.spectating=player.Name; updateView()
  end
  Side.select(player.Name)
  return true
end
function Panel.goTo(player)
  if not player or player==LP or player.Parent~=Players then return false,"Select a player first." end
  if R.queue or K.flinging or K.returningHome or R.tuning then
    L.Toast.warn("Go to unavailable","Stop the active session before moving to a player.")
    return false,"Session active"
  end
  local humanoid,own=living(LP)
  local targetHumanoid,target=living(player)
  if not humanoid or humanoid.Health<=0 or not own or not own.Parent or own.Anchored
    or not targetHumanoid or targetHumanoid.Health<=0 or not target or not target.Parent then
    L.Toast.warn("Go to unavailable","Both players need a ready character.")
    return false,"Character unavailable"
  end
  local p=target.Position
  if not finite(p.X) or not finite(p.Y) or not finite(p.Z) then return false,"Target position unavailable" end
  humanoid.Sit=false
  own.CFrame=target.CFrame*CFrame.new(3,0,3)
  own.AssemblyLinearVelocity=Vector3.zero; own.AssemblyAngularVelocity=Vector3.zero
  Side.select(player.Name); Panel.refresh()
  return true
end
function Panel.target(player)
  if not player or player.Parent~=Players then return end
  Side.select(player.Name)
  R.controls.targetName:set(player.Name)
  R.controls.loopMode:set("Loop target")
  R.start(); Panel.refresh()
end
function Panel.queuePlayer(player)
  if not player or player.Parent~=Players then return end
  K.select(player.Name,not K.selected[player.Name]); Panel.refresh()
end
function Panel.stop()
  R.stop("stopped from player panel")
  Panel.refresh()
end
L.hold(L.RunService.RenderStepped:Connect(function() if L.live() and Side.spectating then updateView() end end))
L.hold(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() if L.live() then updateView() end end))
local function thumbnail(player,portrait)
  local cache=portrait and Panel.portraits or Panel.thumbs
  local key=tostring(player.UserId)..(portrait and ":portrait" or ":head")
  if cache[player.UserId] or Panel.pending[key] then return cache[player.UserId] end
  -- A transient failure may retry after ten seconds, never on every row refresh.
  if Panel.retry and (Panel.retry[key] or 0)>os.clock() then return nil end
  Panel.pending[key]=true
  task.spawn(function()
    local ok,url,ready=pcall(Players.GetUserThumbnailAsync,Players,player.UserId,
      portrait and Enum.ThumbnailType.AvatarBust or Enum.ThumbnailType.HeadShot,
      portrait and Enum.ThumbnailSize.Size420x420 or Enum.ThumbnailSize.Size150x150)
    Panel.pending[key]=nil
    if not L.live() then return end
    if ok and ready and type(url)=="string" and url~="" then cache[player.UserId]=url
    else Panel.retry=Panel.retry or {}; Panel.retry[key]=os.clock()+10 end
    if Side.open then Panel.render() end
  end)
  return nil
end
local function makeRow()
  local row={}
  row.frame=mk("CanvasGroup",{Name="DirectoryRow",Size=UDim2.new(1,-7,0,PITCH),BackgroundColor3=ink.wash,
    BackgroundTransparency=1,BorderSizePixel=0,GroupTransparency=0,Parent=Panel.list})
  row.select=mk("TextButton",{Name="SelectPlayer",Text="",Size=UDim2.fromScale(1,1),
    BackgroundTransparency=1,AutoButtonColor=false,Parent=row.frame})
  row.rule=line(row.frame,"Rule",UDim2.new(0,0,1,-1))
  row.marker=frame(row.frame,"SelectedRule",UDim2.fromOffset(0,12),UDim2.fromOffset(2,40),ink.charcoal)
  row.marker.Visible=false
  row.avatar=mk("ImageLabel",{Name="Headshot",Position=UDim2.fromOffset(11,12),Size=UDim2.fromOffset(32,32),
    BackgroundColor3=ink.portrait,BorderSizePixel=0,Image="",Parent=row.frame})
  row.initial=text(row.avatar,"Initial","",UDim2.fromScale(0,0),UDim2.fromScale(1,1),22,ink.muted,serif)
  row.initial.TextXAlignment=Enum.TextXAlignment.Center
  row.name=text(row.frame,"DisplayName","",UDim2.fromOffset(54,7),UDim2.new(1,-88,0,20),13)
  row.user=text(row.frame,"Username","",UDim2.fromOffset(54,26),UDim2.new(1,-86,0,15),9,ink.muted)
  row.view=button(row.frame,"View","View",UDim2.fromOffset(54,42),UDim2.fromOffset(40,20),function() Panel.view(row.player) end)
  row.fling=button(row.frame,"Target","Fling",UDim2.fromOffset(102,42),UDim2.fromOffset(40,20),function() Panel.target(row.player) end)
  row.distance=text(row.frame,"Distance","",UDim2.new(1,-94,0,44),UDim2.fromOffset(86,17),9,ink.muted,MONO)
  row.distance.TextXAlignment=Enum.TextXAlignment.Right
  row.queue=button(row.frame,"Queue","+",UDim2.new(1,-31,0,8),UDim2.fromOffset(24,26),function() Panel.queuePlayer(row.player) end)
  row.queue.TextSize=18
  row.select.Activated:Connect(function() if row.player and Side.open then Side.select(row.player.Name) end end)
  row.select.MouseEnter:Connect(function() animate(row.frame,"BackgroundTransparency",.35) end)
  row.select.MouseLeave:Connect(function() animate(row.frame,"BackgroundTransparency",row.player and Side.state.selected==row.player.Name and 0 or 1) end)
  Panel.rows[#Panel.rows+1]=row
  return row
end
local function renderStage()
  local player=selectedPlayer()
  if Panel.stagePlayer~=player then
    Panel.stagePlayer=player
    M.set(Panel.stageContent,"GroupTransparency",.68,"base")
    M.set(Panel.stageContent,"Position",UDim2.fromOffset(0,12),"base")
    M.to(Panel.stageContent,"GroupTransparency",0,"base")
    M.to(Panel.stageContent,"Position",UDim2.fromOffset(0,0),"base")
  end
  Panel.portrait.Image=player and thumbnail(player,true) or ""
  Panel.monogram.Visible=Panel.portrait.Image==""
  Panel.monogram.Text=player and player.DisplayName:sub(1,1):upper() or "G"
  Panel.identity.Text=player and player.DisplayName or "Your directory."
  Panel.username.Text=player and "@"..player.Name or "Select a player to begin"
  Panel.identifier.Text=player and tostring(player.UserId) or "GIORGIO  /  PLAYERS"
  local status,color=state(player)
  Panel.playerState.Text=status:upper(); Panel.playerState.TextColor3=color
  local humanoid=living(player)
  Panel.health.Text=humanoid and string.format("%.0f / %.0f",math.max(0,humanoid.Health),humanoid.MaxHealth) or "—"
  Panel.distance.Text=player and metric(distance(player)) or "—"
  local ratio=humanoid and humanoid.MaxHealth>0 and math.clamp(humanoid.Health/humanoid.MaxHealth,0,1) or 0
  animate(Panel.healthFill,"Size",UDim2.fromScale(ratio,1),"base")
  Panel.stageView.Text=player and Side.spectating==player.Name and "Return to me" or "View player"
  Panel.stageFling.Text=R.fling and "Fling  ↗" or "Attach  ↗"
  Panel.stageQueue.Text=player and K.selected[player.Name] and "−  Remove from queue" or "+  Add to queue"
  Panel.stageView.Active=player~=nil; Panel.stageFling.Active=player~=nil; Panel.stageQueue.Active=player~=nil
  Panel.stageGoto.Active=player~=nil
  Panel.stageView.TextTransparency=player and 0 or .55
  Panel.stageFling.TextTransparency=player and 0 or .55
  Panel.stageQueue.TextTransparency=player and 0 or .55
  Panel.stageGoto.TextTransparency=player and 0 or .55
end
function Panel.render()
  if not Side.open or not Panel.list then return end
  local height=Panel.list.AbsoluteSize.Y/math.max(.05,Panel.scale.Scale)
  local first,count=Directory.window(Panel.list.CanvasPosition.Y,height,PITCH,#Panel.roster)
  for slot=1,math.max(count,#Panel.rows) do
    local row=Panel.rows[slot]
    local index=first+slot-1
    local player=slot<=count and Panel.roster[index] or nil
    if player then
      row=row or makeRow()
      local changed=row.player~=player
      row.player=player; row.frame.Name="Player_"..player.Name; row.frame.Visible=true
      M.set(row.frame,"Position",UDim2.fromOffset(0,(index-1)*PITCH),"fast")
      if changed then M.set(row.frame,"GroupTransparency",.38); M.to(row.frame,"GroupTransparency",0,"fast") end
      row.name.Text=player.DisplayName; row.user.Text="@"..player.Name
      row.avatar.Image=thumbnail(player,false) or ""
      row.initial.Visible=row.avatar.Image==""; row.initial.Text=player.DisplayName:sub(1,1):upper()
      row.distance.Text=metric(distance(player)).." st"
      row.view.Text=Side.spectating==player.Name and "Back" or "View"
      row.fling.Text=R.fling and "Fling" or "Attach"
      local queued=K.selected[player.Name]==true
      row.queue.Text=queued and "−" or "+"
      row.queue.TextColor3=queued and ink.green or ink.muted
      row.marker.Visible=Side.state.selected==player.Name
      animate(row.frame,"BackgroundTransparency",row.marker.Visible and 0 or 1)
    elseif row then row.player=nil; row.frame.Visible=false end
  end
  renderStage()
end
function Panel.refresh()
  if not Side.open or not Panel.list then return 0 end
  local roster,distances={},{}
  local total,queued=0,0
  for _,player in ipairs(Players:GetPlayers()) do
    if player~=LP then
      total+=1
      if K.selected[player.Name] then queued+=1 end
      local dist=distance(player)
      if Directory.matches(player.Name,player.DisplayName,Panel.query,Panel.filter,K.selected[player.Name],dist) then
        roster[#roster+1]=player; distances[player]=dist
      end
    end
  end
  table.sort(roster,function(a,b) return Directory.less(a,b,Side.state.sort,distances) end)
  Panel.roster=roster
  if not selectedPlayer() then Side.state.selected=roster[1] and roster[1].Name or nil end
  Panel.count.Text=string.format("%02d IN SESSION",total)
  Panel.queueCount.Text=string.format("%02d SELECTED",queued)
  Panel.list.CanvasSize=UDim2.fromOffset(0,#roster*PITCH)
  local maxScroll=math.max(0,#roster*PITCH-Panel.list.AbsoluteSize.Y/math.max(.05,Panel.scale.Scale))
  if Panel.list.CanvasPosition.Y>maxScroll then Panel.list.CanvasPosition=Vector2.new(0,maxScroll) end
  Panel.empty.Visible=#roster==0
  Panel.empty.Text=Panel.filter=="Queued" and "Your queue is empty.\nUse + beside a player." or "No players found.\nTry another name or filter."
  local current=R.queue and R.queue.current and R.queue.current.player
  local running=R.queue or K.flinging or R.tuning
  Panel.session.Text=R.tuning and "TUNING" or running and (K.flinging and "SESSION ACTIVE" or "WAITING FOR RESPAWN") or "SESSION IDLE"
  Panel.session.TextColor3=running and ink.green or ink.muted
  Panel.active.Text=current and current.DisplayName or running and "Waiting for a ready player" or "Ready when you are"
  Panel.noclip.Text=R.noclip and (K.flinging and "Noclip  ·  Paused" or "Noclip  ·  On") or "Noclip  ·  Off"
  Panel.autosave.Text=L.Cfg.data.autoSave~=false and "Auto-save  ·  On" or "Auto-save  ·  Off"
  Panel.noclip.TextColor3=R.noclip and ink.charcoal or ink.muted
  Panel.autosave.TextColor3=L.Cfg.data.autoSave~=false and ink.charcoal or ink.muted
  Panel.saved.Text=L.Cfg.saveError and "Save failed · retry" or L.Cfg._dirty and (L.Cfg.data.autoSave==false and "Unsaved changes" or "Saving…") or "Settings saved"
  Panel.saved.TextColor3=L.Cfg.saveError and ink.danger or ink.muted
  Panel.mode.Text=(R.loopMode or "Loop target").."  ↓"
  Panel.sort.Text=Side.state.sort=="name" and "A—Z  ↓" or "Nearest  ↓"
  Panel.render()
  return #roster
end
local function preferredScale()
  return Panel.preferredScale or Directory.defaultScale(L.autoScale())
end
local function updateSizeLabel()
  if Panel.sizeReset then
    Panel.sizeReset.Text=string.format("Size %d%%  ·  Reset",math.floor(Panel.scale.Scale*100+.5))
  end
end
local function fit()
  if not Panel.root then return end
  local viewport=L.viewport()
  local scale,x,y=Directory.fit(viewport.X,viewport.Y,W,H,Panel.position and Panel.position.X,Panel.position and Panel.position.Y,preferredScale())
  Panel.scale.Scale=scale; Panel.position=Vector2.new(x,y)
  M.set(Panel.root,"Position",UDim2.fromOffset(x,y),"base")
  updateSizeLabel()
end
local function saveGeometry(saveScale)
  if not Panel.position then return end
  local viewport=L.viewport()
  L.Cfg.set("targetPanelPosition",{x=Panel.position.X/viewport.X,y=Panel.position.Y/viewport.Y})
  if saveScale then L.Cfg.setFeat("giorgio.panelScale",Panel.preferredScale) end
end
local function finishGesture()
  local resizing=Panel.resize~=nil
  if not Panel.drag and not resizing then return end
  Panel.drag=nil; Panel.resize=nil
  saveGeometry(resizing)
end
local function closeModes()
  if Panel.modeMenu then Panel.modeMenu.Visible=false end
end
local function mirrorBackground()
  local G=L.Giorgio
  local main=L.Hub and L.Hub.window
  local source=main and main.giorgioBackground
  if Panel.backgroundSource==source and Panel.background then return end
  if Panel.background then Panel.background:destroy(); Panel.background=nil end
  Panel.backgroundSource=source
  if Panel.root and source and G and G.Media and G.Media.mirror then
    local corner=Panel.root:FindFirstChildOfClass("UICorner")
    Panel.background=G.Media.mirror(Panel.root,source,{name="PlayerPinstripeFilm",cover=true,transparency=.87,ZIndex=0,
      cornerRadius=corner and corner.CornerRadius})
  end
end
local function build()
  if Panel.gui and Panel.gui.Parent then return end
  Panel.rows={}
  Panel.gui=mk("ScreenGui",{Name="GiorgioPlayers",ResetOnSpawn=false,IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=10000,Enabled=false,Parent=L.host()})
  L.own(Panel.gui)
  Panel.root=mk("CanvasGroup",{Name="PlayerDirectory",Size=UDim2.fromOffset(W,H),BackgroundColor3=ink.paper,
    BorderSizePixel=0,GroupTransparency=0,ClipsDescendants=true,Parent=Panel.gui})
  L.corner(3,Panel.root); L.stroke(ink.line,1,.1,Panel.root)
  Panel.scale=mk("UIScale",{Scale=1,Parent=Panel.root})
  mirrorBackground()
  L.Cfg.declare("giorgio.panelScale",{t="number",min=.05,max=2.2})
  local panelScale=L.Cfg.feat("giorgio.panelScale",nil)
  Panel.preferredScale=finite(panelScale) and math.clamp(panelScale,.05,2.2) or nil
  local size=L.Cfg.data.sideSize
  if finite(size) then
    Side.state.size=math.clamp(math.floor(size),1,3)
  end
  local saved=L.Cfg.data.targetPanelPosition
  if type(saved)=="table" and finite(saved.x) and finite(saved.y) then
    local viewport=L.viewport(); Panel.position=Vector2.new(saved.x*viewport.X,saved.y*viewport.Y)
  end
  fit()
  text(Panel.root,"Masthead","G I O R G I O",UDim2.fromOffset(28,17),UDim2.fromOffset(250,19),11)
  text(Panel.root,"Title","Players",UDim2.fromOffset(26,34),UDim2.fromOffset(330,60),50,ink.charcoal,serif)
  text(Panel.root,"Edition","THE PLAYER DIRECTORY",UDim2.fromOffset(354,27),UDim2.fromOffset(240,17),9,ink.muted,MONO)
  Panel.count=text(Panel.root,"Count","",UDim2.fromOffset(355,49),UDim2.fromOffset(225,20),12)
  local grip=mk("TextButton",{Name="DragTitle",Text="",Position=UDim2.fromOffset(12,6),Size=UDim2.new(1,-70,0,91),
    BackgroundTransparency=1,AutoButtonColor=false,Parent=Panel.root})
  button(Panel.root,"Close","×",UDim2.new(1,-59,0,21),UDim2.fromOffset(32,32),function() Side.hide() end).TextSize=24
  line(Panel.root,"HeaderRule",UDim2.fromOffset(28,98),UDim2.new(1,-56,0,1))
  Panel.saved=text(Panel.root,"Saved","Settings saved",UDim2.new(1,-246,0,76),UDim2.fromOffset(218,15),9,ink.muted)
  Panel.saved.TextXAlignment=Enum.TextXAlignment.Right
  local search=frame(Panel.root,"SearchField",UDim2.fromOffset(28,111),UDim2.fromOffset(277,35),ink.paper)
  search.BackgroundTransparency=1
  local searchMark=L.A.Icon.search(search,17,ink.muted)
  searchMark.Name="SearchMark"; searchMark.Position=UDim2.fromOffset(1,9)
  Panel.search=mk("TextBox",{Name="SearchPlayers",Position=UDim2.fromOffset(29,0),Size=UDim2.new(1,-54,1,0),
    Text=Panel.query,PlaceholderText="Find a player",TextColor3=ink.charcoal,PlaceholderColor3=ink.muted,
    TextSize=13,Font=FONT,TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1,ClearTextOnFocus=false,Parent=search})
  button(search,"ClearSearch","×",UDim2.new(1,-23,0,4),UDim2.fromOffset(23,27),function() Panel.search.Text="" end).TextColor3=ink.muted
  line(search,"SearchRule",UDim2.new(0,0,1,0))
  Panel.search:GetPropertyChangedSignal("Text"):Connect(function()
    Panel.query=Panel.search.Text; Side.state.query=Panel.query
    Panel.list.CanvasPosition=Vector2.zero; Panel.refresh()
  end)
  Panel.filters={}
  Panel.filterRule=frame(Panel.root,"ActiveFilterRule",UDim2.fromOffset(28,183),UDim2.fromOffset(36,2),ink.charcoal)
  local filterLayout={{"All",28,36},{"Queued",74,58},{"Nearby",144,56}}
  for _,spec in ipairs(filterLayout) do
    local name,x,width=spec[1],spec[2],spec[3]
    Panel.filters[name]=button(Panel.root,"Filter"..name,name,UDim2.fromOffset(x,155),UDim2.fromOffset(width,29),function()
      Panel.filter=name; Panel.list.CanvasPosition=Vector2.zero
      M.to(Panel.filterRule,"Position",UDim2.fromOffset(x,183),"base")
      M.to(Panel.filterRule,"Size",UDim2.fromOffset(width,2),"base")
      for key,b in pairs(Panel.filters) do animate(b,"TextColor3",key==name and ink.charcoal or ink.muted) end
      Panel.refresh()
    end)
    Panel.filters[name].TextColor3=name==Panel.filter and ink.charcoal or ink.muted
  end
  Panel.sort=button(Panel.root,"Sort","Nearest  ↓",UDim2.fromOffset(215,155),UDim2.fromOffset(90,29),function() Side.cycleSort() end)
  Panel.sort.TextSize=10; Panel.sort.TextColor3=ink.muted
  Panel.list=mk("ScrollingFrame",{Name="Roster",Position=UDim2.fromOffset(28,196),Size=UDim2.fromOffset(284,300),
    BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),ScrollBarThickness=2,
    ScrollBarImageColor3=ink.charcoal,ScrollBarImageTransparency=.65,ScrollingDirection=Enum.ScrollingDirection.Y,
    ElasticBehavior=Enum.ElasticBehavior.Never,Parent=Panel.root})
  Panel.list:GetPropertyChangedSignal("CanvasPosition"):Connect(Panel.render)
  Panel.empty=text(Panel.root,"EmptyRoster","",UDim2.fromOffset(40,277),UDim2.fromOffset(250,100),14,ink.muted)
  Panel.empty.TextWrapped=true; Panel.empty.TextXAlignment=Enum.TextXAlignment.Center
  line(Panel.root,"ColumnRule",UDim2.fromOffset(323,112),UDim2.fromOffset(1,384))

  local stage=frame(Panel.root,"SelectedPlayer",UDim2.fromOffset(343,115),UDim2.fromOffset(349,381),ink.paper)
  stage.BackgroundTransparency=1
  Panel.stageContent=mk("CanvasGroup",{Name="Identity",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,GroupTransparency=0,Parent=stage})
  local content=Panel.stageContent
  local portraitMat=frame(content,"PortraitMat",UDim2.fromOffset(0,0),UDim2.fromOffset(349,222),ink.portrait)
  mk("UIGradient",{Rotation=75,Color=ColorSequence.new(ink.paper,ink.portrait),Parent=portraitMat})
  text(portraitMat,"PortraitLabel","P O R T R A I T",UDim2.fromOffset(14,12),UDim2.fromOffset(160,14),8,ink.muted)
  Panel.monogram=text(portraitMat,"Monogram","G",UDim2.fromOffset(55,26),UDim2.fromOffset(240,196),150,ink.muted,serif)
  Panel.monogram.TextTransparency=.48; Panel.monogram.TextXAlignment=Enum.TextXAlignment.Center
  Panel.portrait=mk("ImageLabel",{Name="AvatarPortrait",Position=UDim2.fromOffset(62,0),Size=UDim2.fromOffset(224,222),
    BackgroundTransparency=1,Image="",ScaleType=Enum.ScaleType.Fit,Parent=portraitMat})
  Panel.playerState=text(portraitMat,"Status","",UDim2.fromOffset(14,201),UDim2.fromOffset(285,15),8,ink.green,MONO)
  Panel.identifier=text(content,"PlayerID","",UDim2.fromOffset(1,231),UDim2.fromOffset(349,14),8,ink.muted,MONO)
  Panel.identity=text(content,"DisplayName","Your directory.",UDim2.fromOffset(-1,247),UDim2.fromOffset(349,34),29,ink.charcoal,serif)
  Panel.username=text(content,"Username","Select a player to begin",UDim2.fromOffset(1,280),UDim2.fromOffset(238,19),11,ink.muted)
  Panel.stageQueue=button(content,"StageQueue","+  Add to queue",UDim2.fromOffset(197,303),UDim2.fromOffset(152,25),function() Panel.queuePlayer(selectedPlayer()) end)
  Panel.stageQueue.TextSize=10
  text(content,"HealthLabel","HEALTH",UDim2.fromOffset(1,305),UDim2.fromOffset(55,14),8,ink.muted)
  Panel.health=text(content,"HealthValue","—",UDim2.fromOffset(54,303),UDim2.fromOffset(89,17),9,ink.charcoal,MONO)
  text(content,"DistanceLabel","STUDS",UDim2.fromOffset(228,279),UDim2.fromOffset(49,18),8,ink.muted)
  Panel.distance=text(content,"DistanceValue","—",UDim2.fromOffset(278,279),UDim2.fromOffset(70,18),12,ink.charcoal,MONO)
  Panel.distance.TextXAlignment=Enum.TextXAlignment.Right
  local healthTrack=frame(content,"HealthTrack",UDim2.fromOffset(1,328),UDim2.fromOffset(348,1),ink.line)
  Panel.healthFill=frame(healthTrack,"Fill",UDim2.fromScale(0,0),UDim2.fromScale(0,1),ink.charcoal)
  Panel.stageView=button(content,"StageView","View player",UDim2.fromOffset(0,342),UDim2.fromOffset(113,36),function() Panel.view(selectedPlayer()) end)
  L.stroke(ink.line,1,0,Panel.stageView)
  Panel.stageGoto=button(content,"StageGoto","Go to  ↗",UDim2.fromOffset(122,342),UDim2.fromOffset(105,36),function() Panel.goTo(selectedPlayer()) end)
  L.stroke(ink.line,1,0,Panel.stageGoto)
  Panel.stageFling=button(content,"StageTarget","Fling  ↗",UDim2.fromOffset(236,342),UDim2.fromOffset(113,36),function() Panel.target(selectedPlayer()) end,"solid")

  line(Panel.root,"SessionRule",UDim2.fromOffset(28,509),UDim2.new(1,-56,0,1))
  Panel.session=text(Panel.root,"SessionStatus","SESSION IDLE",UDim2.fromOffset(28,522),UDim2.fromOffset(210,14),8,ink.muted,MONO)
  Panel.active=text(Panel.root,"SessionTarget","Ready when you are",UDim2.fromOffset(28,539),UDim2.fromOffset(212,22),14)
  Panel.queueCount=text(Panel.root,"QueueCount","00 SELECTED",UDim2.fromOffset(258,521),UDim2.fromOffset(151,14),8,ink.muted,MONO)
  Panel.mode=button(Panel.root,"QueueMode","Loop target  ↓",UDim2.fromOffset(254,537),UDim2.fromOffset(146,27),function()
    Panel.modeMenu.Visible=not Panel.modeMenu.Visible
  end)
  button(Panel.root,"StartQueue","Start",UDim2.fromOffset(416,524),UDim2.fromOffset(79,37),function()
    local player=selectedPlayer()
    if player and (R.loopMode=="Loop target" or R.loopMode=="Single burst") then R.controls.targetName:set(player.Name) end
    R.start(); Panel.refresh()
  end,"solid")
  button(Panel.root,"ClearQueue","Clear",UDim2.fromOffset(505,524),UDim2.fromOffset(61,37),function() K.clearSelection(); Panel.refresh() end)
  button(Panel.root,"StopAll","STOP",UDim2.fromOffset(580,524),UDim2.fromOffset(112,37),Panel.stop,"danger")
  Panel.modeMenu=frame(Panel.root,"ModeOptions",UDim2.fromOffset(250,354),UDim2.fromOffset(177,168),ink.white)
  Panel.modeMenu.Visible=false; Panel.modeMenu.ZIndex=20; L.stroke(ink.line,1,0,Panel.modeMenu)
  for i,mode in ipairs({"Loop target","Selected players","All players","Single burst"}) do
    local option=button(Panel.modeMenu,"Mode"..i,mode,UDim2.fromOffset(8,8+(i-1)*38),UDim2.fromOffset(161,36),function()
      R.controls.loopMode:set(mode); closeModes(); Panel.refresh()
    end)
    option.ZIndex=21
  end
  line(Panel.root,"PreferencesRule",UDim2.fromOffset(28,577),UDim2.new(1,-56,0,1))
  Panel.noclip=button(Panel.root,"Noclip","Noclip  ·  Off",UDim2.fromOffset(28,586),UDim2.fromOffset(141,25),function()
    if R.controls.noclip then R.controls.noclip:set(not R.noclip) else R.setNoclip(not R.noclip) end
    Panel.refresh()
  end)
  Panel.noclip.TextXAlignment=Enum.TextXAlignment.Left; Panel.noclip.TextSize=10
  Panel.autosave=button(Panel.root,"AutoSave","Auto-save  ·  On",UDim2.fromOffset(190,586),UDim2.fromOffset(146,25),function()
    R.setAutoSave(L.Cfg.data.autoSave==false); Panel.refresh()
  end)
  Panel.autosave.TextXAlignment=Enum.TextXAlignment.Left; Panel.autosave.TextSize=10
  local save=button(Panel.root,"SaveNow","Save now ↗",UDim2.fromOffset(350,586),UDim2.fromOffset(102,25),function() R.saveConfig(); Panel.refresh() end)
  save.TextSize=10
  Panel.sizeReset=button(Panel.root,"ResetSize","",UDim2.fromOffset(475,586),UDim2.fromOffset(181,25),function()
    finishGesture(); Panel.preferredScale=nil
    L.Cfg.setFeat("giorgio.panelScale",nil)
    fit(); Panel.refresh(); saveGeometry(false)
  end)
  Panel.sizeReset.TextSize=10; Panel.sizeReset.TextColor3=ink.muted
  local resizeGrip=mk("TextButton",{Name="ResizeCorner",Text="",Position=UDim2.new(1,-42,1,-42),
    Size=UDim2.fromOffset(42,42),BackgroundTransparency=1,AutoButtonColor=false,Active=true,Parent=Panel.root})
  for i=1,3 do
    local mark=line(resizeGrip,"ResizeMark"..i,UDim2.fromOffset(28-i*5,31),UDim2.fromOffset(i*5,1))
    mark.AnchorPoint=Vector2.new(0,1); mark.Rotation=-45; mark.BackgroundColor3=ink.muted
  end
  updateSizeLabel()

  grip.InputBegan:Connect(function(input)
    if Side.open and not Panel.resize and not Panel.drag and (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch) then
      closeModes()
      fit()
      Panel.drag={start=Vector2.new(input.Position.X,input.Position.Y),origin=Panel.position,
        touch=input.UserInputType==Enum.UserInputType.Touch and input or nil}
    end
  end)
  resizeGrip.InputBegan:Connect(function(input)
    if not Side.open or Panel.drag or Panel.resize then return end
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
      closeModes(); fit()
      Panel.resize={start=Vector2.new(input.Position.X,input.Position.Y),origin=Panel.position,scale=Panel.scale.Scale,
        touch=input.UserInputType==Enum.UserInputType.Touch and input or nil}
    end
  end)
  L.hold(L.UIS.InputChanged:Connect(function(input)
    local gesture=Panel.resize or Panel.drag
    if not gesture or not Side.open then return end
    if input==gesture.touch or not gesture.touch and input.UserInputType==Enum.UserInputType.MouseMovement then
      local delta=Vector2.new(input.Position.X,input.Position.Y)-gesture.start
      if Panel.resize then
        local viewport=L.viewport()
        Panel.preferredScale=Directory.resize(viewport.X,viewport.Y,W,H,gesture.origin.X,gesture.origin.Y,gesture.scale,delta.X,delta.Y)
        Panel.position=gesture.origin
      else Panel.position=gesture.origin+delta end
      fit(); Panel.render()
    end
  end))
  L.hold(L.UIS.InputEnded:Connect(function(input)
    local gesture=Panel.resize or Panel.drag
    if gesture and (input==gesture.touch or not gesture.touch and input.UserInputType==Enum.UserInputType.MouseButton1) then finishGesture() end
  end))
  L.hold(L.UIS.WindowFocusReleased:Connect(finishGesture))
  L.hold(Players.PlayerAdded:Connect(function() Panel.refresh() end))
  L.hold(Players.PlayerRemoving:Connect(function(player)
    if Side.spectating==player.Name then restoreView() end
    task.defer(function() if L.live() then Panel.refresh() end end)
  end))
  local elapsed,lastViewport=0,L.viewport()
  L.hold(L.RunService.Heartbeat:Connect(function(dt)
    if not L.live() or not Side.open and not Side.spectating then return end
    elapsed+=dt; if elapsed<.35 then return end; elapsed=0
    if Side.open then
      mirrorBackground()
      local viewport=L.viewport()
      if viewport~=lastViewport then
        finishGesture(); lastViewport=viewport; fit()
      end
      Panel.refresh()
    end
  end))
end
function Side.show()
  if not L.live() then return false,"Interface unloaded" end
  build()
  if Side.open then return true end
  Side.open=true; Side.detached=true; Side.panel=Panel.root; Side.list=Panel.list
  Panel.serial+=1; Panel.gui.Enabled=true; closeModes(); fit()
  mirrorBackground()
  Side.state.sort=L.Cfg.data.sideSort=="name" and "name" or "distance"
  M.set(Panel.root,"GroupTransparency",.8,"base")
  M.set(Panel.root,"Position",UDim2.fromOffset(Panel.position.X,Panel.position.Y+18),"base")
  M.to(Panel.root,"GroupTransparency",0,"base")
  M.to(Panel.root,"Position",UDim2.fromOffset(Panel.position.X,Panel.position.Y),"base")
  Panel.stagePlayer=nil; Panel.refresh()
  sound("open",.28)
  return true
end
function Side.hide(instant)
  finishGesture(); Side.open=false; Panel.serial+=1; closeModes()
  local serial=Panel.serial
  if not Panel.gui then return true end
  if instant then Panel.gui.Enabled=false; return true end
  M.to(Panel.root,"GroupTransparency",1,"fast")
  M.to(Panel.root,"Position",UDim2.fromOffset(Panel.position.X,Panel.position.Y+12),"fast")
  local duration=M.resolve("fast")
  task.delay(duration+.1,function()
    if L.live() and Panel.serial==serial and Panel.gui and not Side.open then Panel.gui.Enabled=false end
  end)
  return true
end
function Side.toggle() return Side.open and Side.hide() or Side.show() end
function Side.refresh() return Panel.refresh() end
function Side.refreshView() return Panel.render() end
function Side.actSpectate() return Panel.view(selectedPlayer()) end
function Side.actGoto() return Panel.goTo(selectedPlayer()) end
function Side.select(name)
  local player=type(name)=="string" and Players:FindFirstChild(name)
  Side.state.selected=player and player~=LP and player.Name or nil
  Panel.render()
end
function Side.setSort(mode)
  Side.state.sort=mode=="name" and "name" or "distance"
  L.Cfg.set("sideSort",Side.state.sort)
  if Panel.list then Panel.list.CanvasPosition=Vector2.zero end
  return Panel.refresh()
end
function Side.cycleSort() return Side.setSort(Side.state.sort=="name" and "distance" or "name") end
function Side.detach() return Side.show() end
function Side.reattach() Side.detached=true; return true end
function Side.setSize(index)
  if finite(index) then
    Side.state.size=math.clamp(math.floor(index),1,3)
    Panel.preferredScale=Directory.defaultScale(L.autoScale())*({.85,1,1.1})[Side.state.size]
    L.Cfg.set("sideSize",Side.state.size)
    L.Cfg.setFeat("giorgio.panelScale",Panel.preferredScale)
  end
  fit(); Panel.refresh(); return true
end
L.cleanup(function()
  finishGesture(); restoreView(); Side.open=false; Panel.serial+=1
  if Panel.background then Panel.background:destroy(); Panel.background=nil end
end,170)
end
