"""Exercise the shipped media player with a deterministic Luau event/audio harness.

This checks clock and resource lifecycle behavior, not Roblox's actual decode speed.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("source", nargs="?", type=Path, default=Path(__file__).resolve().parent.parent / "Giorgio.lua",
                    help="Assembled script to verify (default: Giorgio.lua)")
parser.add_argument("--media-module", action="store_true", help="Verify the work-in-progress media source module")
parser.add_argument("--runtime", type=Path, default=Path.home() / "AppData/Local/Temp/luaudl/luau.exe")
parser.add_argument("--compiler", type=Path, default=Path.home() / "AppData/Local/Temp/luaudl/luau-compile.exe")
args = parser.parse_args()
source_path = Path(__file__).with_name("runtime-media.lua") if args.media_module else args.source
source = source_path.read_text(encoding="utf-8")
if not args.media_module:
    source = source.split("do -- Giorgio runtime\n", 1)[1]
source = source.split("local lastSound={}", 1)[0].replace("G.assets=-- ASSET_MANIFEST", "G.assets={}")
print(f"Verifying media from: {source_path.resolve()}", flush=True)

harness = r'''
local now,inRender=0,false
local fileCalls,renderFileCalls,preloadCalls,renderPreloads=0,0,0,0
local loadedImages,missingFiles,failedIds={},{},{}
local fileBytes,cacheFiles,folders,registeredBytes={},{},{},{}
local scheduled,instances={},{}
local preloadJobs,inflightIds={},{}
local maximumPreloadJobs,duplicatePreloads=0,0
local registrationsThisHeartbeat,maximumRegistrationsPerHeartbeat,workerRegistrations=0,0,0
local function releasePreload(thread)
  local ids=preloadJobs[thread]
  if not ids then return end
  for _,id in ipairs(ids) do
    inflightIds[id]-=1
    if inflightIds[id]==0 then inflightIds[id]=nil end
  end
  preloadJobs[thread]=nil
end
local surfaceDecodeDelay=0
local watchedSurfaces={}
local function sampleSurfaces()
  for surface,watch in pairs(watchedSurfaces) do
    local visiblePicture=false
    for _,picture in ipairs(instances) do
      if picture.ClassName=="ImageLabel" and picture.Parent==surface and picture.Visible and picture.ImageTransparency<.999 and picture.IsLoaded then
        visiblePicture=true; break
      end
    end
    watch.checks+=1
    if not visiblePicture then watch.blanks+=1 end
  end
end
local function event()
  local handlers={}
  return {
    Connect=function(_,fn)
      local c={Connected=true,fn=fn}; handlers[#handlers+1]=c
      function c:Disconnect() self.Connected=false end
      return c
    end,
    Fire=function(_,...)
      for _,c in ipairs(handlers) do if c.Connected then c.fn(...) end end
    end,
  }
end
local task={}
local function resumeThread(thread)
  local item=scheduled[thread]
  if not item then return end
  local ok,delay=coroutine.resume(thread)
  assert(ok,delay)
  if coroutine.status(thread)=="dead" then scheduled[thread]=nil
  else item.at=now+(delay or 1/60) end
end
function task.spawn(fn)
  local thread=coroutine.create(fn); scheduled[thread]={at=now}; resumeThread(thread); return thread
end
function task.wait(seconds) return coroutine.yield(seconds or 1/60) end
function task.cancel(thread) releasePreload(thread); scheduled[thread]=nil; coroutine.close(thread) end
local os={clock=function() return now end}
local Enum={ScaleType={Crop="Crop",Fit="Fit"},AssetFetchStatus={Success="Success",Failure="Failure"}}
local UDim2={fromScale=function(x,y) return {x,y} end,fromOffset=function(x,y) return {x,y} end}
local Vector2={new=function(x,y) return {X=x,Y=y} end}
local content={}
function content:PreloadAsync(ids,callback)
  preloadCalls+=1; if inRender then renderPreloads+=1 end
  assert(#ids<=6,"decode batches must remain bounded")
  local thread=coroutine.running()
  preloadJobs[thread]=ids
  local jobs=0; for _ in pairs(preloadJobs) do jobs+=1 end
  maximumPreloadJobs=math.max(maximumPreloadJobs,jobs)
  for _,id in ipairs(ids) do
    if inflightIds[id] then duplicatePreloads+=1 end
    inflightIds[id]=(inflightIds[id] or 0)+1
  end
  task.wait(.04)
  for _,id in ipairs(ids) do
    local status=failedIds[id] and Enum.AssetFetchStatus.Failure or Enum.AssetFetchStatus.Success
    if status==Enum.AssetFetchStatus.Success then loadedImages[id]=true end
    callback(id,status)
  end
  releasePreload(thread)
end
local game={GetService=function(_,name) assert(name=="ContentProvider"); return content end}
local guiTypes={Frame=true,ImageLabel=true}
local function instance(class,props)
  props=props or {}; props.ClassName=class
  props.Visible=props.Visible~=false; props.Enabled=props.Enabled~=false; props.ZIndex=props.ZIndex or 1
  if class=="ImageLabel" then props.ImageTransparency=props.ImageTransparency or 0 end
  if class=="Sound" then
    props.IsLoaded=true; props.IsPlaying=false; props.Playing=false; props.TimePosition=0
    props.TimeLength=999; props.PlaybackSpeed=1; props.Ended=event()
  end
  local methods={}
  local surfaceReadyAt=now
  function methods:IsA(name) return name==class or (name=="GuiObject" and guiTypes[class]==true) end
  function methods:Destroy()
    props.Parent=nil; props.destroyed=true
    if class=="Sound" then props.Playing=false; props.IsPlaying=false end
    for _,child in ipairs(instances) do if child.Parent==self then child:Destroy() end end
  end
  function methods:Stop()
    props.Playing=false; props.IsPlaying=false; props.TimePosition=0
    props.audioActualPosition=0; props.audioSampleElapsed=0
  end
  function methods:AdvanceAudio(dt)
    if not props.IsPlaying then return end
    props.audioActualPosition=(props.audioActualPosition or props.TimePosition)+dt*props.PlaybackSpeed
    props.audioSampleElapsed=(props.audioSampleElapsed or 0)+dt
    local quantum=props.fixtureAudioQuantum or 0
    if quantum<=0 or props.audioSampleElapsed+1e-9>=quantum then
      props.TimePosition=props.audioActualPosition
      props.audioSampleElapsed=quantum>0 and props.audioSampleElapsed%quantum or 0
    end
    if props.audioActualPosition>=props.TimeLength then
      props.TimePosition=props.TimeLength; props.audioActualPosition=props.TimeLength
      props.Playing=false; props.IsPlaying=false; props.Ended:Fire()
    end
  end
  local object=setmetatable({}, {
    __index=function(_,key)
      if key=="IsLoaded" and class=="ImageLabel" then
        -- The connected executor only presents/decode-loads an image when its
        -- label is visible and not fully transparent, even after preloading.
        return props.Visible and props.ImageTransparency<1 and loadedImages[props.Image]==true and now>=surfaceReadyAt
      end
      return methods[key] or props[key]
    end,
    __newindex=function(_,key,value)
      if class=="ImageLabel" and key=="Image" and value~=props.Image then surfaceReadyAt=now+surfaceDecodeDelay end
      props[key]=value
      if class=="Sound" and key=="Playing" then props.IsPlaying=value and props.IsLoaded end
      if class=="Sound" and key=="TimePosition" then props.audioActualPosition=value; props.audioSampleElapsed=0 end
      sampleSurfaces()
    end,
  })
  instances[#instances+1]=object
  return object
end
local render,heartbeat=event(),event()
local env={}
local live=true
local heldConnections={}
local decoderHost=instance("ScreenGui",{Parent=game})
local L={Giorgio={},Motion={},T={},RunService={RenderStepped=render,Heartbeat=heartbeat},
  mk=instance,host=function() return decoderHost end,own=function(object) return object end,live=function() return live end,Cfg={feat=function(_,default) return default end},
  hold=function(connection) heldConnections[#heldConnections+1]=connection; return connection end}
env.LUMEN=L
local function getgenv() return env end
local function fileCall()
  fileCalls+=1; if inRender then renderFileCalls+=1 end
end
local function isfile(path)
  fileCall()
  if path:sub(1,14)=="Giorgio/cache/" then return cacheFiles[path]~=nil end
  return not missingFiles[path]
end
local function readfile(path)
  fileCall(); assert(not missingFiles[path],"missing file: "..path)
  return cacheFiles[path] or fileBytes[path] or "source:"..path
end
local function writefile(path,bytes) fileCall(); cacheFiles[path]=bytes end
local function isfolder(path) fileCall(); return folders[path]==true end
local function makefolder(path) fileCall(); folders[path]=true end
local function getcustomasset(path)
  fileCall()
  if scheduled[coroutine.running()] then
    registrationsThisHeartbeat+=1; workerRegistrations+=1
    maximumRegistrationsPerHeartbeat=math.max(maximumRegistrationsPerHeartbeat,registrationsThisHeartbeat)
  end
  -- Reproduce the executor's basename-only registration. Distinct source
  -- folders with identical filenames collide unless G.asset isolates them.
  local id="asset:"..path:match("([^/\\]+)$")
  registeredBytes[id]=cacheFiles[path] or fileBytes[path] or "source:"..path
  return id
end
local function step(dt)
  now+=dt
  registrationsThisHeartbeat=0; heartbeat:Fire(dt)
  for _,object in ipairs(instances) do
    if object.ClassName=="Sound" then object:AdvanceAudio(dt) end
  end
  local due={}
  for thread,item in pairs(scheduled) do if item.at<=now then due[#due+1]=thread end end
  for _,thread in ipairs(due) do if scheduled[thread] then resumeThread(thread) end end
  inRender=true; render:Fire(dt); inRender=false
  sampleSurfaces()
end
local function advance(seconds,dt)
  dt=dt or 1/60
  for _=1,math.ceil(seconds/dt) do step(dt) end
end
local function count(map) local n=0; for _ in pairs(map) do n+=1 end; return n end
local function surfaceCount(parent)
  local total=0
  for _,object in ipairs(instances) do
    if object.ClassName=="ImageLabel" and object.Parent==parent then total+=1 end
  end
  return total
end
local function playerSurfaceCount(player)
  local seen={[player.image]=true}
  for _,slot in ipairs(player.buffers) do seen[slot.image]=true end
  return count(seen)
end
local assertions=0
local function check(ok,message) assertions+=1; assert(ok,message) end
local function near(a,b,message) check(math.abs(a-b)<1e-7,message.." ("..tostring(a).." vs "..tostring(b)..")") end
local screen=instance("ScreenGui",{Parent=game})
'''

tests = r'''
fileBytes["Giorgio/assets/collision/first/frame-00001.jpg"]="clip-A"
fileBytes["Giorgio/assets/collision/second/frame-00001.jpg"]="clip-B"
local firstCollision=G.asset("collision/first/frame-00001.jpg")
local secondCollision=G.asset("collision/second/frame-00001.jpg")
check(firstCollision and secondCollision and firstCollision~=secondCollision,
  "same-sized frames with matching basenames from separate films register as distinct textures")
check(registeredBytes[firstCollision]=="clip-A" and registeredBytes[secondCollision]=="clip-B",
  "registering the next film cannot overwrite the first film's registered picture")
local callsBeforeCached=fileCalls
check(G.asset("collision/first/frame-00001.jpg")==firstCollision and fileCalls==callsBeforeCached,
  "an existing asset ID is reused without repeating filesystem or registration work")
local spec={folder="tests",prefix="frame-",ext="jpg",first=0,digits=5,count=600,fps=60,duration=10,audio="test.ogg"}
local film=G.Media.new(screen,spec,{autoplay=true})
check(film.playing and film.buffering,"autoplay waits for the first picture before moving its clock")
advance(.1)
check(film.warming and film.position==0 and not film.audio.IsPlaying,
  "the audio clock waits for bounded lookahead to load instead of immediately outrunning the decoder")
advance(1.1)
check(film.position>.1 and film.shown>1,"autoplay starts after initial decode (position="..film.position..", shown="..film.shown..", preloaded="..film.stats.preloaded..")")
check(film.audio.IsPlaying,"first play starts audio")
near(film.audio.TimePosition,film.position,"audio clock and picture source time stay aligned")
check(#film.workers==3 and maximumPreloadJobs>=3,
  "60 fps media overlaps a bounded set of three preload workers instead of serializing every batch")

film:pause()
local pausedPosition,pausedFrame=film.position,film.shown
advance(.5)
near(film.position,pausedPosition,"pause freezes the source clock")
check(film.shown==pausedFrame and not film.audio.IsPlaying,"pause freezes both picture and sound")
film:play(); advance(.2)
check(film.position>pausedPosition,"play resumes a paused film")
near(film.audio.TimePosition,film.position,"resume does not reset audio to the beginning")

film:stop()
check(not film.playing and not film.audio.IsPlaying,"stop silences audio immediately")
near(film.position,0,"stop resets time immediately")
advance(.15)
check(film.shown==1,"stop returns to the first picture after a bounded decode")
film:play(); advance(.4)
check(film.audio.IsPlaying and film.position>0,"play after stop starts a fresh audio run")

film:seek(5)
near(film.position,5,"seeking changes the requested source time immediately")
check(not film.audio.IsPlaying,"seek pauses audio until the new picture is decoded")
advance(.45)
check(film.shown>=301 and film.position>=5,"seek loads the new region without replaying skipped frames")
near(film.audio.TimePosition,film.position,"playing seek resumes audio at the new position")
film:pause(); film:seek(2); advance(.15)
near(film.position,2,"a paused seek stays paused after loading")
check(film.shown==121 and not film.audio.IsPlaying,"a paused seek displays exactly the requested frame")

film:play(); advance(.2)
screen.Enabled=false; step(1/60)
local hiddenPosition=film.position
check(not film.audio.IsPlaying,"hiding the UI pauses its sound")
advance(.4)
near(film.position,hiddenPosition,"hidden media does not advance invisibly")
screen.Enabled=true; advance(.2)
check(film.position>hiddenPosition and film.audio.IsPlaying,"showing a playing film resumes both tracks")
near(film.audio.TimePosition,film.position,"hidden resume has no audio jump")

film:seek(9.9); advance(.5)
near(film.position,10,"normal completion lands at the exact duration")
check(film.ended and not film.playing and film.shown==600,"normal completion leaves the last frame paused")
film:play(); advance(.5)
check(film.position>0 and film.position<.8 and film.audio.IsPlaying,"play after completion restarts the film")

film.audio.IsLoaded=false; film.audio.Playing=false; film.audioActive=false
advance(.4)
local silentPosition=film.position
check(silentPosition>.4,"a missing or delayed sound does not freeze pictures")
film.audio.TimePosition=0; film.audio.IsLoaded=true
step(1/60)
check(film.position>=silentPosition,"late audio readiness cannot rewind the picture")
near(film.audio.TimePosition,film.position,"late audio joins at the current source time")
film.audio.TimeLength=film.position+.1
advance(.3)
check(film.audioExhausted and film.playing,"shorter audio hands the clock back to video")
check(film.position>film.audio.TimeLength,"pictures continue after audio finishes")

film:seek(1); film.audio.TimeLength=999; film.rate=2; advance(.5)
check(film.audio.PlaybackSpeed==2,"the audio follows an explicitly changed playback rate")
near(film.audio.TimePosition,film.position,"changing rate preserves audio synchronization")
check(not film:seek(0/0) and not film:seek(math.huge),"nonfinite seeks cannot poison playback")
check(film.stats.maxBuffered<=68,"full-HD page references stay within bounded lookahead, history and the displayed page")
check(playerSurfaceCount(film)==9,"a full-HD film uses a bounded surface pool independent of its frame count")
check(surfaceCount(G.decodeHost)==0,"all tiny decoder images are retired with their media owners")
check(renderFileCalls==0 and renderPreloads==0,"render callbacks perform no filesystem registration or preload calls")

film:destroy()
check(film.dead and not film.audio.IsPlaying and film.frameObj.Parent==nil,"destroy removes the visual and stops audio")
check(not G.players[film] and count(film.ready)==0,"destroy releases the player registry and frame references")
local filmWorkersStopped=true
for _,worker in ipairs(film.workers) do
  if scheduled[worker] or preloadJobs[worker] then filmWorkersStopped=false end
end
check(filmWorkersStopped,"destroy cancels all parallel media workers and their pending preload jobs")
local callsAfterDestroy=preloadCalls
advance(.2)
check(preloadCalls==callsAfterDestroy,"a destroyed player's worker cannot continue decoding")
film:destroy(); film:play()
check(not film.playing,"repeated destroy and play cannot revive a disposed player")

-- Force the source clock ahead of decoding. Stop every fixture worker so exact
-- requested frames stay absent, then deliver older frames as a slow decoder
-- would. The normal render loop must advance to each newest usable picture.
local late=G.Media.new(screen,{folder="late-fallback",prefix="frame-",ext="jpg",first=0,digits=5,count=600,fps=60,duration=10},{autoplay=false})
advance(.2)
for _,worker in ipairs(late.workers) do task.cancel(worker) end
late.workers={}; late.worker=nil
local lateWatch={checks=0,blanks=0}; watchedSurfaces[late.frameObj]=lateWatch
local function deliverLateFrame(index)
  local id=G.asset(string.format("late-fallback/frame-%05d.jpg",index-1))
  loadedImages[id]=true; late.ready[index-1]={id=id,loaded=true}
end
deliverLateFrame(7)
late.position=19/60; late.buffering=false; late.warming=false; late:play()
advance(.05)
check(late.shown==7 and late.position>=22/60,
  "a late decoder presents its newest ready frame while the source clock continues past absent exact frames")
deliverLateFrame(22); advance(.05)
check(late.shown==22 and late.image.IsLoaded,
  "a newly delivered late frame replaces the older picture without waiting for an exact clock-frame match")
advance(.1)
check(late.shown==22 and late.image.IsLoaded,
  "an extended decode gap holds the most recent loaded frame instead of rewinding or clearing it")
check(lateWatch.checks>0 and lateWatch.blanks==0,"late-frame fallback never flashes a blank presentation surface")
watchedSurfaces[late.frameObj]=nil; late:destroy()

surfaceDecodeDelay=.045
local overlap=G.Media.new(screen,{folder="overlap-decode",prefix="frame-",ext="jpg",first=0,digits=5,count=600,fps=60,duration=10},
  {autoplay=true})
advance(1)
local overlapStart=overlap.stats.presented
local overlapWatch={checks=0,blanks=0}; watchedSurfaces[overlap.frameObj]=overlapWatch
advance(1)
check(overlap.stats.presented-overlapStart>=50,
  "parallel decode surfaces keep presenting at least 50 distinct frames in a simulated 60 Hz second despite 45 ms per-label readiness")
check(overlapWatch.blanks==0 and overlap.image.IsLoaded,
  "overlapping decode keeps a loaded picture continuously visible")
check(playerSurfaceCount(overlap)==9,"overlapping decode uses a fixed-size surface pool")
check(overlap.stats.maxBuffered<=68 and count(overlap.ready)<=68,
  "parallel preload workers keep frame records bounded while playback advances")
watchedSurfaces[overlap.frameObj]=nil; overlap:destroy(); surfaceDecodeDelay=0

-- Real Roblox audio positions can update less often than RenderStepped. A
-- decoder with every requested page ready must still present each source frame
-- between those samples, while remaining close to the audio's reported time.
local quantized=G.Media.new(screen,{folder="quantized-audio",prefix="frame-",ext="jpg",first=0,digits=5,count=600,fps=60,duration=10,audio="quantized.ogg"},
  {autoplay=true})
quantized.audio.fixtureAudioQuantum=1/20
advance(1)
local distinctFrames,audioSamples,maxAudioDrift={},0,0
local previousSample=quantized.audio.TimePosition
local previousFrame=quantized.shown
local monotonic=true
for _=1,60 do
  step(1/60)
  distinctFrames[quantized.shown]=true
  if quantized.shown<previousFrame then monotonic=false end
  previousFrame=quantized.shown
  if quantized.audio.TimePosition~=previousSample then
    audioSamples+=1; previousSample=quantized.audio.TimePosition
  end
  maxAudioDrift=math.max(maxAudioDrift,math.abs(quantized.position-quantized.audio.TimePosition))
end
check(audioSamples>=19 and audioSamples<=21,"the quantized sound fixture publishes only 20 audio position samples per second")
check(count(distinctFrames)>=58,
  "a 20 Hz audio position clock still permits at least 58 distinct pictures in a simulated 60 Hz second")
check(maxAudioDrift<=.0800001,"picture time stays within 80 ms of a quantized audio clock")
check(monotonic,"quantized audio correction cannot rewind normal picture playback")
quantized:destroy()

local loopSpec={folder="loop",prefix="frame-",ext=".jpg",first=0,digits=5,count=12,fps=12,duration=1}
local loop=G.Media.new(screen,loopSpec,{autoplay=true,loop=true,prefetchFrames=30})
advance(1.6)
check(#loop.workers==2,"lower-frame-rate media uses only two preload workers")
check(loop.playing and loop.position>=0 and loop.position<1,"loop wraps a silent source clock")
check(count(loop.ready)<=12,"wraparound prefetch does not duplicate pages")
loop:destroy()

local atlasSpec={folder="atlas",prefix="icon-",ext="png",first=1,digits=2,count=253,fps=120,cols=14,rows=14,tileWidth=72,tileHeight=72}
local atlas=G.Media.new(screen,atlasSpec,{autoplay=true})
advance(1.8)
check(atlas.shown>196,"atlas animation reaches its second sheet")
check(atlas.image.Image==G.asset("atlas/icon-02.png"),"atlas filenames use the declared first index and extension")
local cell=(atlas.shown-1)%196
check(atlas.image.ImageRectOffset.X==(cell%14)*72 and atlas.image.ImageRectOffset.Y==math.floor(cell/14)*72,"atlas frame cropping advances on the correct page")
check(atlas.stats.maxBuffered<=2,"hundreds of atlas frames use at most two loaded page references")
check(#atlas.workers==1,"atlas animation does not allocate unnecessary parallel preload workers")
atlas:destroy()

missingFiles["Giorgio/assets/missing/frame-00000.jpg"]=true
local missing=G.Media.new(screen,{folder="missing",prefix="frame-",ext="jpg",first=0,digits=5,count=20,fps=20},{autoplay=true})
advance(.2)
check(missing.error and missing.buffering and missing.position==0,"a missing initial asset is reported instead of pretending playback started")
missingFiles["Giorgio/assets/missing/frame-00000.jpg"]=nil
advance(1.3)
check(missing.shown>0 and missing.position>0,"installing a previously missing frame recovers without reopening")
missing:destroy()

local failedId=G.asset("fail/frame-00000.jpg")
failedIds[failedId]=true
local failed=G.Media.new(screen,{folder="fail",prefix="frame-",ext="jpg",first=0,digits=5,count=1,fps=1},{autoplay=true})
advance(.2)
check(failed.stats.preloadErrors>0 and failed.buffering,"decode failure leaves an explicit error and a stationary clock")
failedIds[failedId]=nil
advance(1.3)
check(not failed.buffering,"a temporary decode failure is retried")
failed:destroy()

-- ContentProvider success is not an ImageLabel presentation guarantee. Delay
-- each label's readiness independently and inspect both render boundaries and
-- every property mutation so a hide-before-show flash is observable too.
surfaceDecodeDelay=.3
local slowSpec={folder="surface-delay",prefix="frame-",ext="jpg",first=0,digits=5,count=100,fps=10,duration=10}
local slow=G.Media.new(screen,slowSpec,{autoplay=false})
advance(.1)
check(slow.ready[0].loaded and not slow.image.IsLoaded and slow.buffering,
  "preload completion cannot start the player before its visible ImageLabel is ready")
advance(.3)
check(not slow.buffering and slow.image.IsLoaded,"the initial picture waits for independent presentation readiness")
local watch={checks=0,blanks=0}; watchedSurfaces[slow.frameObj]=watch
local oldPicture,oldId=slow.image,slow.image.Image
slow:seek(5); advance(.12)
check(slow.pending and slow.ready[50].loaded and not slow.back.IsLoaded,
  "a sought frame can be prefetched successfully while its back ImageLabel is still decoding")
check(slow.image==oldPicture and oldPicture.Image==oldId and oldPicture.Visible and oldPicture.IsLoaded,
  "seek holds the old loaded picture while the replacement surface is unready")
advance(.35)
check(slow.shown==51 and slow.image~=oldPicture and slow.image.Visible and slow.image.IsLoaded,
  "seek swaps surfaces only after the replacement picture is ready")
check(oldPicture.Visible and oldPicture.ImageTransparency>=.999 and oldPicture.ImageTransparency<1,
  "the old picture remains decode-eligible while visually concealed after a successful replacement")

oldPicture,oldId=slow.image,slow.image.Image
slow:seek(2); advance(.1)
local cancelledId=slow.back.Image
slow:seek(8); advance(.12)
check(slow.image==oldPicture and slow.image.Image==oldId and slow.image.Visible,
  "a newer seek keeps the last completed picture while cancelling an unready seek")
advance(.4)
check(slow.shown==81 and slow.image.Image~=cancelledId,
  "a cancelled seek cannot surface its old pending image after a newer request")

slow:play(); advance(1.1)
check(slow.shown>81,"normal next-frame playback keeps advancing with delayed picture surfaces")
check(watch.checks>100 and watch.blanks==0,
  "seek cancellation and next-frame swaps never expose a blank surface after the first loaded picture")
watchedSurfaces[slow.frameObj]=nil
slow:destroy(); surfaceDecodeDelay=0

-- The main interface and the film window share a renderer implementation, not
-- a surface, clock, or alpha. Replacement of a film must not flash the backdrop.
surfaceDecodeDelay=.12
local backgroundParent=instance("Frame",{Parent=screen})
local editParent=instance("Frame",{Parent=screen})
local background=G.Media.new(backgroundParent,{folder="background-isolation",prefix="frame-",ext="jpg",first=0,digits=5,count=40,fps=20,duration=2},
  {autoplay=true,loop=true,cover=true,transparency=.87})
local edit=G.Media.new(editParent,{folder="edit-isolation",prefix="frame-",ext="jpg",first=0,digits=5,count=200,fps=20,duration=10,audio="isolated.ogg"},
  {autoplay=true})
advance(1.5)
local backgroundWatch={checks=0,blanks=0}; watchedSurfaces[background.frameObj]=backgroundWatch
local editWatch={checks=0,blanks=0}; watchedSurfaces[edit.frameObj]=editWatch
check(background.image.ScaleType==Enum.ScaleType.Crop and edit.image.ScaleType==Enum.ScaleType.Fit,
  "background cropping and film aspect fitting remain separate")
check(background.frameObj.Parent==backgroundParent and edit.frameObj.Parent==editParent and not background.frameObj.ClipsDescendants and not edit.frameObj.ClipsDescendants,
  "each image stays in its own fitted window without the engine scissor regression")
edit:seek(6); advance(.4)
near(background.image.ImageTransparency,.87,"a film seek cannot reset the background's authored transparency")
check(background.back.ImageTransparency>=.999 and background.back.ImageTransparency<1,
  "background replacement surfaces remain decode-eligible without doubling its visible opacity")
near(edit.image.ImageTransparency,0,"films remain fully opaque without inheriting the background wash")
local backgroundPosition=background.position
edit:pause(); advance(.1)
check(background.position>backgroundPosition,"pausing a film cannot pause the interface background")
local oldEditAudio=edit.audio
edit:destroy(); watchedSurfaces[edit.frameObj]=nil
local replacement=G.Media.new(editParent,{folder="next-edit-isolation",prefix="frame-",ext="jpg",first=0,digits=5,count=50,fps=25,duration=2,audio="next-isolated.ogg"},
  {autoplay=true})
advance(.4)
check(not oldEditAudio.IsPlaying and replacement.audio.IsPlaying and replacement.position>0,
  "replacing a film retires its sound and starts the next independent media clock")
check(background.playing and background.frameObj.Parent==backgroundParent and background.image.IsLoaded,
  "replacing a film preserves the background renderer and visible picture")
check(backgroundWatch.blanks==0 and editWatch.blanks==0,
  "independent background and edit surfaces stay populated during seeks and playback")
watchedSurfaces[background.frameObj]=nil
background:destroy(); replacement:destroy(); surfaceDecodeDelay=0


-- Mirroring shares the decoded stream and keeps it alive only while a view is
-- visible. It must not create another audio player or media preloader.
local hiddenParent=instance("Frame",{Parent=screen,ZIndex=4})
local mirrorParent=instance("Frame",{Parent=screen})
local shared=G.Media.new(hiddenParent,{folder="shared-backdrop",prefix="frame-",ext="jpg",first=0,digits=5,count=40,fps=10,duration=4},
  {autoplay=true,loop=true,transparency=.87})
check(shared.frameObj.ZIndex>hiddenParent.ZIndex and shared.image.ZIndex>hiddenParent.ZIndex,
  "media renders above its opaque parent backing instead of disappearing behind it")
advance(1.2)
local jobsBefore=count(scheduled)
local mirror=G.Media.mirror(mirrorParent,shared,{transparency=.87,cover=true})
check(count(scheduled)==jobsBefore and not mirror.audio and not mirror.workers,
  "a backdrop mirror starts no audio, preloader, or registration worker")
hiddenParent.Visible=false
local start=shared.position
advance(.3)
check(shared.position>start and mirror.image.IsLoaded and mirror.image.Image~="",
  "visible panel mirror keeps the shared stream moving when the main window is hidden")
near(mirror.image.ImageTransparency,.87,"mirror preserves the shared backdrop opacity")
check(mirror.image.Parent==mirror.frameObj and mirror.back.Parent==G.decodeHost,
  "mirror keeps one presentation surface and one tiny shared decode surface")
mirrorParent.Visible=false; start=shared.position; advance(.2)
near(shared.position,start,"hidden source and hidden mirror suspend playback together")
mirrorParent.Visible=true; advance(.2)
check(shared.position>start,"showing the mirror resumes the source without a second media clock")
local decodePicture=mirror.back
shared:destroy()
check(mirror.dead and not mirror.frameObj.Parent and not decodePicture.Parent,
  "source teardown also removes mirror presentation, decode surface and connection")

local retired=G.Media.new(screen,spec,{autoplay=true})
live=false; step(1/60)
check(retired.dead and count(G.players)==0 and count(scheduled)==0,"retiring the UI cancels every media worker and connection")
check(count(preloadJobs)==0 and count(inflightIds)==0,"retiring the UI leaves no in-flight parallel preload jobs")
check(duplicatePreloads==0,"parallel workers never submit a second decode job for an asset that is already loading")
check(workerRegistrations>100 and maximumRegistrationsPerHeartbeat<=1,
  "all media workers share a maximum of one new asset registration per heartbeat, excluding synchronous constructor assets")
check(surfaceCount(G.decodeHost)==0,"all tiny decoder images are retired with their media owners")
check(renderFileCalls==0 and renderPreloads==0,"all render callbacks avoid filesystem operations, registration and preloading")
print(string.format("PASS: %d media lifecycle assertions; %d bounded preload batches; zero file/preload calls in render callbacks",assertions,preloadCalls))
'''

with tempfile.TemporaryDirectory(prefix="giorgio-media-") as folder:
    path = Path(folder) / "media-tests.luau"
    path.write_text(harness + source + tests, encoding="utf-8")
    subprocess.run([str(args.compiler), "--null", str(path)], check=True)
    subprocess.run([str(args.runtime), str(path)], check=True)
