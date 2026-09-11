-- Independent roster window. Only visible cards are allocated and updated.
do
local Side=L.Side
local Panel={rows={},roster={},thumbs=Side._thumbs or {},pendingThumbs={},filter="All",query="",serial=0}
R.Panel=Panel
local mk=L.mk
local W,H,PITCH=440,690,116
local palette={bg=Color3.fromRGB(13,16,24),card=Color3.fromRGB(23,28,40),hover=Color3.fromRGB(32,40,57),
  line=Color3.fromRGB(67,80,109),text=Color3.fromRGB(238,243,255),dim=Color3.fromRGB(146,161,189),
  accent=Color3.fromRGB(143,170,255),accentDark=Color3.fromRGB(45,60,101),green=Color3.fromRGB(105,221,178),
  red=Color3.fromRGB(255,153,167)}
local function rounded(obj,r) L.corner(r or 12,obj); return obj end
local function frame(parent,name,pos,size,color)
  return mk("Frame",{Name=name,Position=pos,Size=size,BackgroundColor3=color or palette.card,
    BorderSizePixel=0,Parent=parent})
end
local function label(parent,name,text,pos,size,fontSize,color,font)
  return mk("TextLabel",{Name=name,Text=text,Position=pos,Size=size,BackgroundTransparency=1,
    TextSize=fontSize or 14,TextColor3=color or palette.text,Font=font or T.font.body,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,
    TextTruncate=Enum.TextTruncate.AtEnd,Parent=parent})
end
local function button(parent,name,text,pos,size,callback,style)
  local bg=style=="primary" and palette.accentDark or palette.hover
  local color=style=="danger" and palette.red or palette.text
  local b=rounded(mk("TextButton",{Name=name,Text=text,Position=pos,Size=size,AutoButtonColor=false,
    BackgroundColor3=bg,BorderSizePixel=0,TextSize=12,Font=T.font.medium,TextColor3=color,Parent=parent}),9)
  b.MouseEnter:Connect(function() M.to(b,"BackgroundColor3",bg:Lerp(palette.accent,.14),"fast") end)
  b.MouseLeave:Connect(function() M.to(b,"BackgroundColor3",bg,"fast") end)
  b.MouseButton1Down:Connect(function() M.to(b,"TextTransparency",.3,"fast") end)
  b.MouseButton1Up:Connect(function() M.to(b,"TextTransparency",0,"fast") end)
  b.Activated:Connect(function() M.to(b,"TextTransparency",0,"fast"); L.try("reproot.panel."..name,callback) end)
  return b
end
local function living(player)
  local ch=player and player.Character
  local hum=ch and ch:FindFirstChildOfClass("Humanoid")
  return hum,hum and hum.RootPart
end
local function distance(player)
  local _,a=living(LP); local _,b=living(player)
  if not a or not b then return math.huge end
  local value=(a.Position-b.Position).Magnitude
  return finite(value) and value or math.huge
end
local function getState(player)
  local hum,part=living(player)
  if K.whitelist[player.Name:lower()] then return "Excluded",palette.dim end
  if not hum or not part or hum.Health<=0 then return "Respawning",palette.dim end
  if R.queue and R.queue.current and R.queue.current.player==player and K.flinging then return "Active target",palette.accent end
  if hum.Sit or part.Anchored then return "Seated",palette.dim end
  if player.Character:FindFirstChildOfClass("ForceField") then return "Spawn protection",palette.dim end
  return "Ready",palette.green
end
function Panel.view(player)
  local hum=living(player)
  if not hum then return L.Toast.warn("View unavailable","This player is waiting for a character.") end
  if R.queue and R.controls.followCamera then R.controls.followCamera:set(false) end
  local camera=workspace.CurrentCamera
  if Side.spectating==player.Name then
    camera.CameraSubject=living(LP); Side.spectating=nil
  else
    camera.CameraSubject=hum; camera.CameraType=Enum.CameraType.Custom; Side.spectating=player.Name
  end
  Side.state.selected=player.Name
  Panel.render()
end
function Panel.target(player)
  Side.state.selected=player.Name
  R.controls.targetName:set(player.Name)
  R.controls.loopMode:set("Loop target")
  R.start()
end
function Panel.queuePlayer(player)
  K.select(player.Name,not K.selected[player.Name])
  Panel.refresh()
end
local function makeRow()
  local row={}
  row.frame=rounded(mk("CanvasGroup",{Name="PlayerCard",Size=UDim2.new(1,-10,0,PITCH-10),
    BackgroundColor3=palette.card,BorderSizePixel=0,GroupTransparency=0,Parent=Panel.list}),13)
  row.stroke=L.stroke(palette.line,1,.65,row.frame)
  row.avatar=rounded(mk("ImageLabel",{Name="Avatar",Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(42,42),
    BackgroundColor3=palette.hover,BorderSizePixel=0,Image="",Parent=row.frame}),12)
  row.initial=label(row.avatar,"Initial","",UDim2.fromScale(0,0),UDim2.fromScale(1,1),17,palette.accent,T.font.strong)
  row.initial.TextXAlignment=Enum.TextXAlignment.Center
  row.name=label(row.frame,"DisplayName","",UDim2.fromOffset(65,11),UDim2.new(1,-165,0,21),15,palette.text,T.font.strong)
  row.user=label(row.frame,"Username","",UDim2.fromOffset(65,33),UDim2.new(1,-165,0,16),11,palette.dim)
  row.distance=label(row.frame,"Distance","",UDim2.new(1,-94,0,13),UDim2.fromOffset(80,17),11,palette.dim,T.font.mono)
  row.distance.TextXAlignment=Enum.TextXAlignment.Right
  row.state=label(row.frame,"State","",UDim2.new(1,-112,0,34),UDim2.fromOffset(98,17),10,palette.green)
  row.state.TextXAlignment=Enum.TextXAlignment.Right
  row.health=rounded(frame(row.frame,"HealthTrack",UDim2.fromOffset(12,58),UDim2.new(1,-24,0,2),palette.hover),2)
  row.healthFill=rounded(frame(row.health,"Fill",UDim2.fromScale(0,0),UDim2.fromScale(1,1),palette.green),2)
  row.view=button(row.frame,"View","View",UDim2.fromOffset(12,70),UDim2.new(.28,-10,0,25),function() if row.player then Panel.view(row.player) end end)
  row.fling=button(row.frame,"Fling","Fling",UDim2.new(.28,8,0,70),UDim2.new(.30,-10,0,25),function() if row.player then Panel.target(row.player) end end,"primary")
  row.queue=button(row.frame,"Queue","+ Queue",UDim2.new(.58,4,0,70),UDim2.new(.42,-16,0,25),function() if row.player then Panel.queuePlayer(row.player) end end)
  Panel.rows[#Panel.rows+1]=row
  return row
end
local function avatar(row,player)
  local url=Panel.thumbs[player.UserId]
  row.avatar.Image=url or ""; row.initial.Visible=not url
  row.initial.Text=player.DisplayName:sub(1,1):upper()
  if url or Panel.pendingThumbs[player.UserId] then return end
  Panel.pendingThumbs[player.UserId]=true
  task.spawn(function()
    local ok,imageUrl=pcall(Players.GetUserThumbnailAsync,Players,player.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size150x150)
    Panel.pendingThumbs[player.UserId]=nil
    if not L.live() then return end
    if ok and imageUrl then Panel.thumbs[player.UserId]=imageUrl; if Side.open then Panel.render() end end
  end)
end
function Panel.render()
  if not Side.open or not Panel.list then return end
  local height=Panel.list.AbsoluteSize.Y/(Panel.scale.Scale>0 and Panel.scale.Scale or 1)
  local count=math.min(12,math.ceil(height/PITCH)+2)
  local first=math.max(1,math.floor(Panel.list.CanvasPosition.Y/PITCH)+1)
  for slot=1,math.max(count,#Panel.rows) do
    local row=Panel.rows[slot]
    local index=first+slot-1
    local player=slot<=count and Panel.roster[index] or nil
    if player then
      row=row or makeRow()
      local changed=row.player~=player
      row.player=player; row.frame.Name="Player_"..player.Name; row.frame.Visible=true
      local y=(index-1)*PITCH
      if changed then
        row.frame.Position=UDim2.fromOffset(8,y+5); row.frame.GroupTransparency=.35
        M.to(row.frame,"Position",UDim2.fromOffset(0,y),"base")
        M.to(row.frame,"GroupTransparency",0,"base")
        avatar(row,player)
      else
        M.to(row.frame,"Position",UDim2.fromOffset(0,y),"base")
        local url=Panel.thumbs[player.UserId]
        if url and row.avatar.Image~=url then row.avatar.Image=url; row.initial.Visible=false end
      end
      row.name.Text=player.DisplayName; row.user.Text="@"..player.Name
      local d=distance(player)
      row.distance.Text=d==math.huge and "--" or d>=10000 and string.format("%.1fk st",d/1000) or string.format("%.0f st",d)
      local state,color=getState(player); row.state.Text=state; row.state.TextColor3=color
      local hum=living(player); local health=hum and hum.MaxHealth>0 and math.clamp(hum.Health/hum.MaxHealth,0,1) or 0
      M.to(row.healthFill,"Size",UDim2.fromScale(health,1),"base")
      row.queue.Text=K.selected[player.Name] and "Queued  -" or "+ Queue"
      row.view.Text=Side.spectating==player.Name and "Viewing" or "View"
      row.fling.Text=R.fling and "Fling" or "Attach"
      local highlighted=K.selected[player.Name] or (R.queue and R.queue.current and R.queue.current.player==player)
      M.to(row.stroke,"Color",highlighted and palette.accent or palette.line,"fast")
      M.to(row.stroke,"Transparency",highlighted and .18 or .65,"fast")
    elseif row then row.player=nil; row.frame.Visible=false end
  end
end
function Panel.refresh()
  if not Side.open or not Panel.list then return 0 end
  local roster={}; local total,queued=0,0
  for _,player in ipairs(Players:GetPlayers()) do
    if player~=LP then
      total+=1; if K.selected[player.Name] then queued+=1 end
      local query=Panel.query:lower()
      local matches=query=="" or player.Name:lower():find(query,1,true) or player.DisplayName:lower():find(query,1,true)
      local include=Panel.filter=="All" or (Panel.filter=="Queued" and K.selected[player.Name]) or (Panel.filter=="Nearby" and distance(player)<=250)
      if matches and include then roster[#roster+1]=player end
    end
  end
  local distances={}
  if Side.state.sort~="name" then for _,p in ipairs(roster) do distances[p]=distance(p) end end
  table.sort(roster,function(a,b)
    if Side.state.sort=="name" then
      local an,bn=a.DisplayName:lower(),b.DisplayName:lower()
      if an~=bn then return an<bn end
    elseif distances[a]~=distances[b] then return distances[a]<distances[b] end
    return a.UserId<b.UserId
  end)
  Panel.roster=roster
  Panel.count.Text=string.format("%02d players  /  %02d queued",total,queued)
  Panel.list.CanvasSize=UDim2.fromOffset(0,#roster*PITCH)
  Panel.empty.Visible=#roster==0
  Panel.empty.Text=Panel.filter=="Queued" and "Your queue is empty\nAdd players with + Queue" or "No players found\nTry a different search or filter"
  local current=R.queue and R.queue.current and R.queue.current.player
  Panel.active.Text=current and current.DisplayName or (R.queue and "Waiting for a ready player" or "Ready when you are")
  Panel.session.Text=R.queue and (K.flinging and "SESSION ACTIVE" or "WAITING FOR RESPAWN") or "SESSION IDLE"
  Panel.session.TextColor3=R.queue and palette.green or palette.dim
  local nc=R.noclip and (K.flinging and "Noclip: paused" or "Noclip: on") or "Noclip: off"
  Panel.noclip.Text=nc
  Panel.autosave.Text=L.Cfg.data.autoSave~=false and "Auto-save: on" or "Auto-save: off"
  Panel.saved.Text=L.Cfg.saveError and "Save failed - try Save now" or L.Cfg._dirty and (L.Cfg.data.autoSave==false and "Unsaved changes" or "Saving changes...") or "Settings saved"
  Panel.saved.TextColor3=L.Cfg.saveError and palette.red or palette.dim
  Panel.render()
  return #roster
end
local function fit()
  if not Panel.root then return end
  local vp=L.viewport()
  local sc=math.min(1,math.max(.4,(vp.X-32)/W),math.max(.4,(vp.Y-40)/H))
  Panel.scale.Scale=sc
  local pos=Panel.position or Vector2.new(vp.X-W*sc-24,math.max(20,(vp.Y-H*sc)/2))
  Panel.position=Vector2.new(math.clamp(pos.X,8,math.max(8,vp.X-W*sc-8)),math.clamp(pos.Y,8,math.max(8,vp.Y-H*sc-8)))
  M.set(Panel.root,"Position",UDim2.fromOffset(Panel.position.X,Panel.position.Y),"base")
end
local function build()
  if Panel.gui and Panel.gui.Parent then return end
  Panel.rows={}
  Panel.gui=mk("ScreenGui",{Name="LumenTargets",ResetOnSpawn=false,IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=10000,Parent=L.host()})
  L.own(Panel.gui)
  Panel.root=rounded(mk("CanvasGroup",{Name="TargetPanel",Size=UDim2.fromOffset(W,H),BackgroundColor3=palette.bg,
    BorderSizePixel=0,GroupTransparency=0,Parent=Panel.gui}),21)
  L.stroke(palette.line,1,.2,Panel.root)
  mk("UIGradient",{Rotation=105,Color=ColorSequence.new(Color3.fromRGB(235,241,255),Color3.fromRGB(165,176,206)),Parent=Panel.root})
  Panel.scale=mk("UIScale",{Scale=1,Parent=Panel.root})
  local saved=L.Cfg.data.targetPanelPosition
  if saved then local vp=L.viewport(); Panel.position=Vector2.new(saved.x*vp.X,saved.y*vp.Y) end
  fit()
  local accent=frame(Panel.root,"Accent",UDim2.fromOffset(22,23),UDim2.fromOffset(3,35),palette.accent); rounded(accent,2)
  label(Panel.root,"Eyebrow","LUMEN  /  REP ROOT",UDim2.fromOffset(36,21),UDim2.fromOffset(300,15),10,palette.accent,T.font.mono)
  label(Panel.root,"Title","Players",UDim2.fromOffset(35,37),UDim2.fromOffset(280,32),27,palette.text,T.font.strong)
  Panel.count=label(Panel.root,"Count","",UDim2.fromOffset(23,79),UDim2.fromOffset(280,18),12,palette.dim)
  local grip=mk("TextButton",{Name="DragTitle",Text="",BackgroundTransparency=1,Position=UDim2.fromOffset(12,10),
    Size=UDim2.new(1,-76,0,64),Parent=Panel.root})
  button(Panel.root,"Close","X",UDim2.new(1,-54,0,23),UDim2.fromOffset(30,30),function() Side.hide() end)
  local searchFrame=rounded(frame(Panel.root,"SearchBox",UDim2.fromOffset(22,108),UDim2.new(1,-44,0,40)),11)
  L.stroke(palette.line,1,.6,searchFrame)
  label(searchFrame,"SearchIcon",">",UDim2.fromOffset(12,0),UDim2.fromOffset(20,40),15,palette.accent,T.font.mono)
  Panel.search=mk("TextBox",{Name="Search",Position=UDim2.fromOffset(37,0),Size=UDim2.new(1,-46,1,0),Text="",PlaceholderText="Search name or @username",
    PlaceholderColor3=palette.dim,TextColor3=palette.text,TextSize=13,Font=T.font.body,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,ClearTextOnFocus=false,Parent=searchFrame})
  Panel.search:GetPropertyChangedSignal("Text"):Connect(function() Panel.query=Panel.search.Text; Panel.list.CanvasPosition=Vector2.zero; Panel.refresh() end)
  Panel.filters={}
  for index,name in ipairs({"All","Queued","Nearby"}) do
    Panel.filters[name]=button(Panel.root,"Filter"..name,name,UDim2.fromOffset(22+(index-1)*83,158),UDim2.fromOffset(77,30),function()
      Panel.filter=name; Panel.list.CanvasPosition=Vector2.zero
      for key,b in pairs(Panel.filters) do M.to(b,"TextColor3",key==name and palette.accent or palette.dim,"fast") end
      Panel.refresh()
    end)
  end
  Panel.sort=button(Panel.root,"Sort","Nearest",UDim2.new(1,-120,0,158),UDim2.fromOffset(98,30),function()
    Side.setSort(Side.state.sort=="name" and "distance" or "name")
  end)
  Panel.list=mk("ScrollingFrame",{Name="Roster",Position=UDim2.fromOffset(22,203),Size=UDim2.new(1,-38,0,329),
    BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),ScrollBarThickness=3,
    ScrollBarImageColor3=palette.accent,ScrollBarImageTransparency=.45,ScrollingDirection=Enum.ScrollingDirection.Y,
    ElasticBehavior=Enum.ElasticBehavior.Never,Parent=Panel.root})
  Panel.list:GetPropertyChangedSignal("CanvasPosition"):Connect(Panel.render)
  Panel.empty=label(Panel.root,"Empty","",UDim2.fromOffset(30,275),UDim2.new(1,-60,0,65),14,palette.dim)
  Panel.empty.TextXAlignment=Enum.TextXAlignment.Center; Panel.empty.TextWrapped=true
  frame(Panel.root,"Divider",UDim2.fromOffset(22,544),UDim2.new(1,-44,0,1),palette.line).BackgroundTransparency=.55
  Panel.session=label(Panel.root,"Session","SESSION IDLE",UDim2.fromOffset(23,558),UDim2.fromOffset(310,15),9,palette.dim,T.font.mono)
  Panel.active=label(Panel.root,"ActivePlayer","Ready when you are",UDim2.fromOffset(23,577),UDim2.new(1,-46,0,22),15,palette.text,T.font.strong)
  button(Panel.root,"StartQueue","Start queue",UDim2.fromOffset(22,610),UDim2.fromOffset(122,35),function()
    R.controls.loopMode:set("Selected players"); R.start()
  end,"primary")
  button(Panel.root,"ClearQueue","Clear",UDim2.fromOffset(153,610),UDim2.fromOffset(69,35),function() K.clearSelection(); Panel.refresh() end)
  button(Panel.root,"StopAll","STOP",UDim2.fromOffset(231,610),UDim2.new(1,-253,0,35),function() R.stop("stopped from player panel"); Panel.refresh() end,"danger")
  Panel.noclip=button(Panel.root,"Noclip","Noclip: off",UDim2.fromOffset(22,654),UDim2.fromOffset(122,24),function()
    R.controls.noclip:set(not R.noclip); Panel.refresh()
  end)
  Panel.autosave=button(Panel.root,"AutoSave","Auto-save: on",UDim2.fromOffset(153,654),UDim2.fromOffset(135,24),function()
    R.setAutoSave(L.Cfg.data.autoSave==false); Panel.refresh()
  end)
  button(Panel.root,"SaveNow","Save now",UDim2.fromOffset(297,654),UDim2.new(1,-319,0,24),function() R.saveConfig(); Panel.refresh() end)
  -- Save state is also visible when the main workshop is closed.
  Panel.saved=label(Panel.root,"SavedStatus","",UDim2.new(1,-202,0,80),UDim2.fromOffset(180,17),10,palette.dim)
  Panel.saved.TextXAlignment=Enum.TextXAlignment.Right
  local drag
  grip.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
      drag={start=Vector2.new(input.Position.X,input.Position.Y),origin=Panel.position,touch=input.UserInputType==Enum.UserInputType.Touch and input or nil}
    end
  end)
  L.hold(L.UIS.InputChanged:Connect(function(input)
    if not drag or not Side.open then return end
    if input==drag.touch or (not drag.touch and input.UserInputType==Enum.UserInputType.MouseMovement) then
      Panel.position=drag.origin+Vector2.new(input.Position.X,input.Position.Y)-drag.start; fit()
    end
  end))
  L.hold(L.UIS.InputEnded:Connect(function(input)
    if drag and (input==drag.touch or input.UserInputType==Enum.UserInputType.MouseButton1) then
      drag=nil; local vp=L.viewport()
      L.Cfg.set("targetPanelPosition",{x=Panel.position.X/vp.X,y=Panel.position.Y/vp.Y})
    end
  end))
  local elapsed=0; local lastViewport=L.viewport()
  L.hold(L.RunService.Heartbeat:Connect(function(dt)
    if not L.live() or not Side.open then return end
    elapsed+=dt; if elapsed<.4 then return end; elapsed=0
    if L.viewport()~=lastViewport then lastViewport=L.viewport(); fit() end
    Panel.refresh()
  end))
end
function Side.show()
  build(); Side.open=true; Side.detached=true; Side.panel=Panel.root; Side.list=Panel.list
  Panel.serial+=1; Panel.gui.Enabled=true
  fit(); Panel.root.GroupTransparency=.2
  M.to(Panel.root,"GroupTransparency",0,"base")
  Panel.root.Position=UDim2.fromOffset(Panel.position.X+16,Panel.position.Y)
  M.to(Panel.root,"Position",UDim2.fromOffset(Panel.position.X,Panel.position.Y),"base")
  Side.state.sort=L.Cfg.data.sideSort or "distance"
  Panel.sort.Text=Side.state.sort=="name" and "A - Z" or "Nearest"
  Panel.filters[Panel.filter].TextColor3=palette.accent
  Panel.refresh(); return true
end
function Side.hide(instant)
  Side.open=false; Panel.serial+=1; local serial=Panel.serial
  if not Panel.gui then return true end
  if instant then Panel.gui.Enabled=false; return true end
  M.to(Panel.root,"GroupTransparency",1,"fast")
  task.delay(.2,function() if Panel.serial==serial and Panel.gui then Panel.gui.Enabled=false end end)
  return true
end
function Side.toggle() if Side.open then return Side.hide() else return Side.show() end end
function Side.refresh() return Panel.refresh() end
function Side.select(name) Side.state.selected=name; Panel.render() end
function Side.setSort(mode)
  Side.state.sort=mode=="name" and "name" or "distance"
  L.Cfg.set("sideSort",Side.state.sort)
  if Panel.sort then Panel.sort.Text=Side.state.sort=="name" and "A - Z" or "Nearest" end
  return Panel.refresh()
end
function Side.cycleSort() return Side.setSort(Side.state.sort=="name" and "distance" or "name") end
function Side.detach() return Side.show() end
function Side.reattach() return true end
function Side.setSize() fit(); return true end
L.cleanup(function() Side.open=false; Panel.serial+=1 end,170)
end
