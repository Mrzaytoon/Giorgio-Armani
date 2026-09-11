local L=getgenv().LUMEN
local G,M=L.Giorgio,L.Motion
local WHITE=L.T.c.text
local function ease(x) x=math.clamp(x,0,1); return 1-(1-x)^3 end
local function line(parent,name)
  return L.mk("Frame",{Name=name,AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=WHITE,BorderSizePixel=0,Parent=parent})
end
function G.load(onReady)
  if G.loader then G.loader:close(true,true) end
  if L.Cfg.feat("giorgio.showLoader",true)==false then G.booting=false; onReady(); return end
  G.booting=true
  local self={dead=false,time=0,muted=L.Cfg.feat("giorgio.sfx",true)==false}; G.loader=self
  self.gui=L.mk("ScreenGui",{Name="GiorgioPrelude",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=20000,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,Parent=L.host()}); L.own(self.gui)
  local canvas=L.mk("CanvasGroup",{Name="CinematicCanvas",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(3,3,3),
    BorderSizePixel=0,GroupTransparency=0,Parent=self.gui})
  local viewport=L.viewport()
  local stage=L.mk("Frame",{Name="Choreography",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.47),
    Size=UDim2.fromOffset(700,400),BackgroundTransparency=1,Parent=canvas})
  local stageScale=L.mk("UIScale",{Scale=math.min(L.autoScale(),(viewport.X-40)/700,(viewport.Y-150)/660),Parent=stage})
  local orbitHost=L.mk("Frame",{Name="Orbit",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
    Size=UDim2.fromOffset(300,300),BackgroundTransparency=1,Parent=stage})
  local orbitLines={}
  for ring=1,3 do
    orbitLines[ring]={}
    for index=1,48 do orbitLines[ring][index]=line(orbitHost,"OrbitLine") end
  end
  local points={}
  for index=1,52 do
    local point=line(stage,"Particle"); point.Size=UDim2.fromOffset(index%3==0 and 2 or 1.3,index%3==0 and 2 or 1.3)
    L.corner(10,point); points[index]=point
  end
  local flare=L.A.img and L.A.img.glow and L.mk("ImageLabel",{Name="CoreGlow",Image=L.A.img.glow,BackgroundTransparency=1,
    ImageColor3=WHITE,Size=UDim2.fromOffset(190,190),AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Parent=orbitHost})
  local core=line(orbitHost,"Core"); core.Position=UDim2.fromScale(.5,.5); core.Size=UDim2.fromOffset(4,4); L.corner(5,core)
  local rays={}
  for index=1,8 do
    local ray=line(orbitHost,"Ray"); ray.Position=UDim2.fromScale(.5,.5); ray.Rotation=index*22.5
    ray.Size=UDim2.fromOffset(80,1); rays[index]=ray
    L.mk("UIGradient",{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.1),NumberSequenceKeypoint.new(1,1)}),Parent=ray})
  end
  local logoSpec=G.assets.logo
  local logoId=logoSpec and G.asset(logoSpec.file)
  local logoWidth,logoHeight=500,logoSpec and 500*logoSpec.height/logoSpec.width or 64
  local logoHost=L.mk("Frame",{Name="LogoAssembly",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
    Size=UDim2.fromOffset(logoWidth,logoHeight),BackgroundTransparency=1,Parent=stage})
  local strips={}
  if logoId then
    for index=1,12 do
      local y=math.floor((index-1)*logoSpec.height/12)
      local nextY=math.floor(index*logoSpec.height/12)
      local mask=L.mk("Frame",{Name="LogoStripe",BackgroundTransparency=1,ClipsDescendants=true,
        Size=UDim2.fromOffset(logoWidth,(nextY-y)*logoWidth/logoSpec.width+.3),Parent=logoHost})
      local picture=L.mk("ImageLabel",{Name="Wordmark",BackgroundTransparency=1,Image=logoId,ImageColor3=WHITE,
        Size=UDim2.fromOffset(logoWidth,logoHeight),Position=UDim2.fromOffset(0,-y*logoWidth/logoSpec.width),
        ScaleType=Enum.ScaleType.Fit,ImageTransparency=1,Parent=mask})
      strips[index]={mask=mask,picture=picture}
    end
  else
    local fallback=G.text(logoHost,"Wordmark","GIORGIO ARMANI",UDim2.fromScale(0,0),UDim2.fromScale(1,1),42,Enum.Font.Garamond)
    fallback.TextTransparency=1; strips[1]={mask=fallback,picture=fallback}
  end
  local symbolSpec=G.assets.symbol
  local symbolId=symbolSpec and G.asset(symbolSpec.file)
  local symbol=symbolId and L.mk("ImageLabel",{Name="ArmaniEagle",Image=symbolId,ImageColor3=WHITE,ImageTransparency=1,
    BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,252,.5,0),
    Size=UDim2.fromOffset(106,106*symbolSpec.height/symbolSpec.width),ScaleType=Enum.ScaleType.Fit,Parent=stage})
  local edition=G.text(stage,"Edition","P R I V A T E   E D I T I O N",UDim2.new(.5,-180,.5,logoHeight/2+36),UDim2.fromOffset(360,24),11)
  edition.TextXAlignment=Enum.TextXAlignment.Center; edition.TextTransparency=1
  local footer=G.text(canvas,"Readiness","PREPARING YOUR SETUP",UDim2.new(.5,-240,1,-90),UDim2.fromOffset(480,22),12,Enum.Font.Code)
  footer.TextXAlignment=Enum.TextXAlignment.Center; footer.TextColor3=Color3.fromRGB(127,126,120)
  local progress=L.mk("Frame",{Name="ProgressTrack",AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,1,-55),
    Size=UDim2.fromOffset(160,1),BackgroundColor3=Color3.fromRGB(37,37,34),BorderSizePixel=0,Parent=canvas})
  local fill=line(progress,"Progress"); fill.AnchorPoint=Vector2.zero; fill.Position=UDim2.fromScale(0,0); fill.Size=UDim2.fromScale(0,1)
  if G.assets.loaderFilm and L.Cfg.feat("giorgio.introFilm",true) then
    self.media=G.Media.new(stage,G.assets.loaderFilm,{Size=UDim2.fromOffset(640,360),Position=UDim2.new(.5,-320,.5,112),transparency=1,name="IntroductionFilm"})
    if self.media and self.media.audio then self.media.audio.Volume=0 end
  end
  local duration=self.media and (L.Cfg.feat("giorgio.fullIntroFilm",false) and 4.4+self.media.duration or 11) or 6.5
  self.duration=duration
  task.spawn(function()
    local critical={logoId,symbolId}
    local ids={}; for _,id in pairs(critical) do if id then ids[#ids+1]=id end end
    pcall(function() game:GetService("ContentProvider"):PreloadAsync(ids) end)
  end)
  local started=false
  function self:close(immediate,suppressReady)
    if self.dead then return end; self.dead=true
    if self.connection then self.connection:Disconnect() end
    if self.sound then self.sound:Stop(); self.sound:Destroy() end
    if self.media then self.media:pause() end
    if G.loader==self then G.loader=nil end
    G.booting=false
    if not started and not suppressReady and L.live() then started=true; onReady() end
    local function release() if self.media then self.media:destroy() end; self.gui:Destroy() end
    if immediate then release()
    else M.to(canvas,"GroupTransparency",1,"slow"); task.delay(.65,release) end
  end
  local skip=G.button(canvas,"SkipIntro","Skip intro",UDim2.new(1,-146,1,-72),UDim2.fromOffset(116,34),function() self:close() end); skip.TextSize=14
  local mute
  mute=G.button(canvas,"IntroSound",self.muted and "Sound off" or "Sound on",UDim2.fromOffset(30,30),UDim2.fromOffset(116,34),function()
    self.muted=not self.muted; mute.Text=self.muted and "Sound off" or "Sound on"
  end)
  mute.TextSize=14
  self.sound=G.sound("loader",.85)
  local function projected(theta,ring,time,shrink)
    local x,y,z=132*math.cos(theta),132*math.sin(theta),0
    local tilt=.75+ring*.42
    y,z=y*math.cos(tilt),y*math.sin(tilt)
    local rotation=time*.52+ring*math.pi/3
    x,y=x*math.cos(rotation)-y*math.sin(rotation),x*math.sin(rotation)+y*math.cos(rotation)
    local depth=1/(1+z/530)
    return Vector2.new(150+x*depth*shrink,150+y*depth*shrink)
  end
  self.connection=L.RunService.RenderStepped:Connect(function(dt)
    if not L.live() then self:close(true); return end
    self.time+=dt; local t=self.time
    viewport=L.viewport()
    stageScale.Scale=math.max(.15,math.min(L.autoScale(),(viewport.X-40)/700,(viewport.Y-150)/660))
    local filmProgress=self.media and ease((t-4.1)/1.65) or 0
    stage.Position=UDim2.fromScale(.5,.47-.19*filmProgress)
    if self.media then
      if t>=4.4 and not self.filmStarted then self.filmStarted=true; self.media:play() end
      self.media.rest=1-filmProgress
      L.uiWrite(self.media.image,"ImageTransparency",self.media.rest)
      if self.media.audio then self.media.audio.Volume=self.muted and 0 or L.Cfg.feat("giorgio.introVolume",.65)*filmProgress end
    end
    if self.sound and self.sound.Parent then self.sound.Volume=self.muted and 0 or L.Cfg.feat("giorgio.sfxVolume",.35)*.85*(t>=4.7 and .22 or 1) end
    local orbitAlpha=ease(t/.55)*(1-ease((t-2.65)/.9))
    local shrink=1-ease((t-2.7)/1.0)*.96
    for ring,segments in ipairs(orbitLines) do
      for index,segment in ipairs(segments) do
        local a=projected((index-1)/48*math.pi*2,ring,t,shrink)
        local b=projected(index/48*math.pi*2,ring,t,shrink)
        local delta=b-a
        segment.Position=UDim2.fromOffset((a.X+b.X)/2,(a.Y+b.Y)/2)
        segment.Size=UDim2.fromOffset(delta.Magnitude+.5,1.15)
        segment.Rotation=math.deg(math.atan2(delta.Y,delta.X))
        segment.BackgroundTransparency=1-orbitAlpha*.64
      end
    end
    local pointMorph=ease((t-2.6)/.8)
    local pointFade=ease(t/.65)*(1-ease((t-4)/.4))
    for index,point in ipairs(points) do
      local phase=index*2.399963+t*.65
      local radius=25+math.sqrt(index/52)*69
      local x=math.cos(phase)*radius; local y=math.sin(phase)*radius*.66
      local lineX=(index-26.5)*4.7
      local lineY=math.sin(index*.28-t*4)*12*math.sin(math.clamp((t-3)/1.2,0,1)*math.pi)
      point.Position=UDim2.new(.5,x+(lineX-x)*pointMorph,.5,y+(lineY-y)*pointMorph)
      point.BackgroundTransparency=1-pointFade*(.36+(index%4)*.15)
    end
    local glow=math.max(0,(1-ease((t-2.7)/.7))*(.65+.15*math.sin(t*2)))
    if flare then flare.ImageTransparency=1-glow*.72 end
    core.BackgroundTransparency=1-glow
    for _,ray in ipairs(rays) do ray.BackgroundTransparency=1-glow*.26 end
    local logoProgress=ease((t-3.8)/1.15)
    for index,strip in ipairs(strips) do
      local p=ease((t-3.8-(index-1)*.035)/.65)
      strip.mask.Position=UDim2.fromOffset((index%2==0 and 1 or -1)*(1-p)*32,(index-1)*logoHeight/12)
      if strip.picture:IsA("ImageLabel") then strip.picture.ImageTransparency=1-p else strip.picture.TextTransparency=1-p end
    end
    edition.TextTransparency=1-ease((t-5)/.6)
    logoHost.Position=UDim2.new(.5,symbol and -64*logoProgress or 0,.5,10*(1-logoProgress))
    if symbol then local p=ease((t-4.1)/.9); symbol.ImageTransparency=1-p; symbol.Position=UDim2.new(.5,252+(1-p)*24,.5,0) end
    fill.Size=UDim2.fromScale(math.min(1,t/duration),1)
    footer.Text=t<2.6 and "PREPARING YOUR SETUP" or t<4.8 and "SHAPING YOUR SPACE" or "PRIVATE VIEWING  /  GIORGIO"
    skip.Text=t>=5.8 and "Continue" or "Skip intro"
    if t>=duration then self:close() end
  end)
end
L.cleanup(function() if G.loader then G.loader:close(true,true) end end,190)
