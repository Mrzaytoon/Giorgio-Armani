local L=getgenv().LUMEN
local G,T,M,A=L.Giorgio,L.T,L.Motion,L.A
L.NAME="GIORGIO"; L.VERSION="2.0"
local ivory=Color3.fromRGB(236,232,222)
local palette={surface=Color3.fromRGB(12,12,12),raised=Color3.fromRGB(22,22,21),overlay=Color3.fromRGB(30,30,28),
  hover=Color3.fromRGB(42,42,39),accent=ivory,accentSoft=Color3.fromRGB(131,128,118),text=ivory,
  textDim=Color3.fromRGB(182,179,170),textMute=Color3.fromRGB(152,149,139),textOff=Color3.fromRGB(106,105,99),
  line=Color3.fromRGB(69,68,63),lineSoft=Color3.fromRGB(41,41,38),lineStrong=Color3.fromRGB(107,105,97),scrim=Color3.new(0,0,0)}
for name,value in pairs(palette) do T.c[name]=value end
T.font.display=Enum.Font.Garamond
T.size.display=34; T.size.hero=40; T.r.sm=4; T.r.md=6; T.r.lg=12
T.base.sidebar=204; T.base.header=90
T.m.fast={.19,0}; T.m.base={.36,0}; T.m.slow={.62,0}; T.m.expressive={.62,.05}
for _,elevation in pairs(T.elev) do elevation.fill=T.c.raised; elevation.line=T.c.line end
T.reindex()
L.Theme.motionOrder={"Calm","Silk","Default","Lively"}
L.Theme.heavenOn=false
if L.Theme.motion=="Heaven" then L.Theme.setMotion("Silk",true) end
-- Legacy decorative footage never enters the new interface.
local oldVideoNew=L.Video.new
L.Video.new=function(parent,opts)
  if opts and opts.folder and opts.folder:find("lumen_fx",1,true) then return nil,"Giorgio supplies its own media" end
  return oldVideoNew(parent,opts)
end
function G.textAnimation(label,window)
  local config=A.CHROME.__default
  local pattern=A.chromePattern(config)
  local gradient=L.mk("UIGradient",{Color=A.chromeSeq(pattern,0),Rotation=config.rot,Parent=label})
  local time,acc=0,1
  local connection
  connection=L.RunService.RenderStepped:Connect(function(dt)
    if not L.live() or not label.Parent then connection:Disconnect(); return end
    if window and (window.hidden or not window.root.Visible) then return end
    time+=dt; acc+=dt
    if acc<1/24 then return end; acc=0
    gradient.Color=A.chromeSeq(pattern,((window and window._iconT or time)*(config.speed or .16)*.5)%1)
  end)
  L.hold(connection)
  return gradient
end
local function kill(controller)
  if controller and controller.destroy then controller:destroy() end
end
local Window=L.Window
function Window.mark(parent,size)
  local mark=L.mk("Frame",{Name="GiorgioMark",Size=UDim2.fromOffset(size,size),BackgroundTransparency=1,Parent=parent})
  local letter=G.text(mark,"Monogram","G",UDim2.fromScale(0,0),UDim2.fromScale(1,1),size,Enum.Font.Garamond)
  letter.TextXAlignment=Enum.TextXAlignment.Center
  return mark
end
local oldNew,oldTab,oldSelect=Window.new,Window.tab,Window.select
local iconMap={ ["Rep Root"]="gauge",Targets="account",Players="account",Offsets="compass",Presets="grid-3",Interface="cog",Activity="document-list" }
function G.styleToast(parts,opts)
  local card=parts.card
  card.BackgroundColor3=T.c.surface
  local corner=card:FindFirstChildOfClass("UICorner"); if corner then corner.CornerRadius=UDim.new(0,10) end
  for _,object in ipairs(card:GetChildren()) do
    if object:IsA("UIStroke") then object.Color=T.c.line; object.Transparency=.45 end
    if object:IsA("TextLabel") and object~=parts.title and object~=parts.count then
      object.Font=T.font.body; object.TextSize=12; object.TextColor3=T.c.textDim
      object.Position=UDim2.fromOffset(64,55); object.Size=UDim2.new(1,-82,0,36)
    end
  end
  if parts.bloom then parts.bloom.Visible=false end
  parts.edge.Visible=false; parts.glyph.Visible=false
  L.uiWrite(parts.well,"BackgroundTransparency",1)
  for _,object in ipairs(parts.well:GetChildren()) do if object:IsA("UIStroke") then object.Enabled=false end end
  parts.well.Position=UDim2.new(0,20,.5,-4); parts.well.Size=UDim2.fromOffset(30,38)
  local monogram=G.text(parts.well,"GiorgioMonogram","G",UDim2.fromScale(0,0),UDim2.fromScale(1,1),35,Enum.Font.Garamond)
  monogram.TextColor3=T.c.text; monogram.TextXAlignment=Enum.TextXAlignment.Center
  local typeName=({info="NOTICE",ok="COMPLETE",warn="ATTENTION",bad="UNAVAILABLE"})[opts.kind or "info"] or "NOTICE"
  local edition=G.text(card,"NoticeEdition","GIORGIO  /  "..typeName,UDim2.fromOffset(64,13),UDim2.new(1,-108,0,12),9,Enum.Font.Code)
  edition.TextColor3=T.c.textMute; edition.ZIndex=4
  parts.title.Font=Enum.Font.Garamond; parts.title.TextSize=21; parts.title.TextColor3=T.c.text
  parts.title.Position=UDim2.fromOffset(64,29); parts.title.Size=UDim2.new(1,-86,0,24)
  parts.count.Position=UDim2.new(1,-18,0,12); parts.count.TextColor3=T.c.textDim
  parts.track.Position=UDim2.new(0,20,1,-8); parts.track.Size=UDim2.new(1,-40,0,1)
  parts.track.BackgroundColor3=T.c.line; parts.timer.BackgroundColor3=T.c.textDim
  parts.timer.BackgroundTransparency=.3
end
function Window.new(opts)
  opts=opts or {}; opts.title="GIORGIO"; opts.subtitle="PRIVATE EDITION  /  REP ROOT"; opts.guiName="Giorgio"
  local self=oldNew(opts)
  local fitting=false
  function self:fitViewport()
    if fitting or not self.root.Parent then return end; fitting=true
    local viewport=L.viewport()
    local preferred=tonumber(L.Cfg.data.scale) or L.autoScale()
    self.scaleObj.Scale=math.max(.05,math.min(preferred,(viewport.X-24)/self.width,(viewport.Y-32)/self.height))
    fitting=false
  end
  self:fitViewport()
  L.hold(self.scaleObj:GetPropertyChangedSignal("Scale"):Connect(function() task.defer(function() if self.root.Parent then self:fitViewport() end end) end))
  local lastViewport=L.viewport()
  L.hold(L.RunService.Heartbeat:Connect(function()
    if not self.root.Parent then return end
    local viewport=L.viewport()
    if viewport~=lastViewport then lastViewport=viewport; self:fitViewport() end
  end))
  kill(self.wordVid); kill(self.orbVid); kill(self.bgVid); kill(self.heroVid)
  self.wordVid=nil; self.orbVid=nil; self.bgVid=nil; self.heroVid=nil
  self.wash.Visible=false
  for _,stroke in ipairs(self.root:GetChildren()) do if stroke:IsA("UIStroke") then stroke.Enabled=false end end
  if self.bgFieldHost then self.bgFieldHost.Visible=false end
  for _,item in ipairs(self.bgDots or {}) do item.obj.Visible=false end
  for _,child in ipairs(self.header:GetChildren()) do
    if child.Name=="OrbMark" or (child:IsA("TextLabel") and child.Position.X.Offset==78) then child:Destroy() end
  end
  local logo=G.asset(G.assets.logo and G.assets.logo.file)
  if logo then
    L.mk("ImageLabel",{Name="GiorgioWordmark",Image=logo,BackgroundTransparency=1,Position=UDim2.fromOffset(28,26),
      Size=UDim2.fromOffset(231,27),ScaleType=Enum.ScaleType.Fit,Parent=self.header})
  else G.text(self.header,"GiorgioWordmark","GIORGIO",UDim2.fromOffset(28,20),UDim2.fromOffset(250,38),34,Enum.Font.Garamond) end
  self.subtitleLbl.Position=UDim2.fromOffset(30,59); self.subtitleLbl.Text="PRIVATE EDITION / REP ROOT"; self.subtitleLbl.TextSize=9
  self.searchHint.Text="CTRL K"; self.searchHint.TextColor3=T.c.textMute
  local edit=G.button(self.header,"GiorgioArmani","Giorgio Armani?",UDim2.new(1,-455,.5,-17),UDim2.fromOffset(182,34),G.openEdit)
  edit.Font=Enum.Font.Garamond; edit.TextSize=21; L.uiWrite(edit,"BackgroundTransparency",1)
  G.textAnimation(edit,self)
  local underline=L.mk("Frame",{Name="Underline",AnchorPoint=Vector2.new(.5,1),Position=UDim2.fromScale(.5,1),
    Size=UDim2.fromOffset(0,1),BackgroundColor3=ivory,BorderSizePixel=0,Parent=edit})
  edit.MouseEnter:Connect(function() M.to(underline,"Size",UDim2.new(1,-18,0,1),"base"); M.to(edit,"Position",UDim2.new(1,-455,.5,-19),"base") end)
  edit.MouseLeave:Connect(function() M.to(underline,"Size",UDim2.fromOffset(0,1),"base"); M.to(edit,"Position",UDim2.new(1,-455,.5,-17),"base") end)
  self.giorgioEditButton=edit
  if G.assets.background then
    local rounding=self.body:FindFirstChildOfClass("UICorner")
    self.giorgioBackground=G.Media.new(self.body,G.assets.background,{cover=true,autoplay=true,loop=true,transparency=.87,ZIndex=1,name="PinstripeFilm",cornerRadius=rounding and rounding.CornerRadius})
    if rounding then L.hold(rounding:GetPropertyChangedSignal("CornerRadius"):Connect(function()
      local media=self.giorgioBackground
      if media.dead then return end
      local images={media.image}; for _,slot in ipairs(media.buffers) do images[#images+1]=slot.image end
      for _,picture in ipairs(images) do local corner=picture:FindFirstChildOfClass("UICorner"); if corner then corner.CornerRadius=rounding.CornerRadius end end
    end)) end
  end
  self.pill.BackgroundColor3=Color3.fromRGB(35,35,32)
  self.pillBar.BackgroundColor3=ivory
  if self.dock then
    for _,object in ipairs(self.dock:GetDescendants()) do
      if object:IsA("TextLabel") and object.Text:upper():find("LUMEN",1,true) then object.Text="GIORGIO"; object.Font=Enum.Font.Garamond end
    end
  end
  return self
end
function Window:tab(opts)
  opts=table.clone(opts or {}); opts.chrome=nil
  local tab=oldTab(self,opts)
  local iconName=iconMap[opts.name]
  if iconName and G.assets.icons and G.assets.icons[iconName] then
    if tab.glyph then tab.glyph.Visible=false end
    tab.giorgioIcon=G.Media.new(tab.button,G.assets.icons[iconName],{Size=UDim2.fromOffset(24,24),Position=UDim2.new(0,12,.5,-12),name="AnimatedIcon"})
    if tab.giorgioIcon then
      tab.giorgioIcon:setFrame(G.assets.icons[iconName].count)
      local hit=tab.button:FindFirstChild("Hit",true)
      if hit then
        hit.MouseEnter:Connect(function() tab.giorgioIcon:seek(0); tab.giorgioIcon:play(); G.sound("hover",.2) end)
      end
    end
  end
  tab.label.TextSize=14; tab.label.Font=Enum.Font.Gotham
  if tab.heads and tab.heads[2] then
    local heading=tab.heads[2][1]; heading.Font=Enum.Font.Garamond; heading.TextSize=34
    heading.Size=UDim2.new(1,-48,0,36); heading.Position=UDim2.fromOffset(24,25)
  end
  tab.sub.TextColor3=T.c.textDim
  return tab
end
function Window:select(index,immediate)
  local tab=self.tabs[index]
  if not tab or self.active==index then return end
  local previous=self.active and self.tabs[self.active]
  local previousIndex=self.active or index
  local pillPosition=self.pill.Position; local barPosition=self.pillBar.Position
  self._giorgioTransition=(self._giorgioTransition or 0)+1
  local serial=self._giorgioTransition
  -- The original selector owns navigation, popovers, saved tab and scroll state.
  -- Masked content transitions below own only appearance.
  self.active=nil
  oldSelect(self,index,true)
  if immediate then
    for _,page in ipairs(self.tabs) do page.page.Visible=page==tab; page.page.Position=UDim2.fromScale(0,0) end
    return
  end
  L.Cfg.set("tab",index)
  self.pill.Position=pillPosition; self.pillBar.Position=barPosition
  M.to(self.pill,"Position",UDim2.fromOffset(0,tab.navY),"slow")
  M.to(self.pillBar,"Position",UDim2.fromOffset(-12,tab.navY+T.px("tab")*.275),"slow")
  local direction=index>=previousIndex and 1 or -1
  for _,other in ipairs(self.tabs) do if other~=tab and other~=previous then other.page.Visible=false end end
  if previous then
    previous.page.Visible=true
    A.groupTo(previous.group,1,"fast")
    M.to(previous.page,"Position",UDim2.fromOffset(0,-24*direction),"base")
    for _,entry in ipairs(previous.heads or {}) do M.to(entry[1],entry[2],1,"fast") end
    task.delay(.24,function() if self._giorgioTransition==serial and self.active~=previous.index then previous.page.Visible=false end end)
  end
  tab.page.Visible=true
  M.set(tab.page,"Position",UDim2.fromOffset(0,42*direction),"base")
  M.to(tab.page,"Position",UDim2.fromOffset(0,0),"slow")
  A.groupSet(tab.group,1)
  M.set(tab.group,"Position",UDim2.fromOffset(0,112),"base")
  task.delay(.07,function()
    if self._giorgioTransition~=serial or self.active~=index then return end
    A.groupTo(tab.group,0,"base"); M.to(tab.group,"Position",UDim2.fromOffset(0,88),"slow")
  end)
  for i,entry in ipairs(tab.heads or {}) do
    M.set(entry[1],entry[2],1,"base")
    task.delay((i-1)*.055,function() if self._giorgioTransition==serial then M.to(entry[1],entry[2],0,"base") end end)
  end
  if tab.giorgioIcon then tab.giorgioIcon:seek(0); tab.giorgioIcon:play() end
  G.sound("open",.35)
end
