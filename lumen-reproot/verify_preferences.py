"""Exercise shipped preferences with a deterministic clock and in-memory disk.

Uses the original suite's Roblox/JSON scaffolding, then runs the built config,
control persistence adapter, saved-value restoration, and noclip worker. No
executor, player, user config file, or live filesystem is changed by the tests.
"""
from pathlib import Path
import ast
import argparse
import json
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
UPSTREAM = Path.home() / "AppData/Local/Potassium/workspace/lumen"
RUNTIME = Path.home() / "AppData/Local/Temp/luaudl/luau.exe"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", nargs="?", type=Path, default=ROOT.parent / "LumenRepRoot.lua",
                    help="Assembled script to verify (default: LumenRepRoot.lua)")
SOURCE = parser.parse_args().source.resolve()
source = SOURCE.read_text(encoding="utf-8")
factory_defaults = (ROOT.parent / "giorgio/defaults.json").read_text(encoding="utf-8") if "-- GIORGIO_FACTORY_DEFAULTS" in source else None


def between(start, end, text=source):
    first = text.index(start)
    return text[first:text.index(end, first)]


def module(name):
    start = source.index(f"do -- ==== {name} ====\n")
    match = re.search(r"^do -- ==== ", source[start + 1:], re.M)
    assert match is not None
    return source[start:start + 1 + match.start()]


# Extract the literal only; importing the upstream script would execute its suite.
upstream_tree = ast.parse((UPSTREAM / "verify_logic.py").read_text(encoding="utf-8-sig"))
prelude = next(ast.literal_eval(node.value) for node in upstream_tree.body
               if isinstance(node, ast.Assign)
               and any(isinstance(t, ast.Name) and t.id == "PRELUDE" for t in node.targets))

harness = r'''
local L = getgenv().LUMEN
local now, timers, writes, failWrites = 0, {}, {}, false
task.delay = function(dt, fn) table.insert(timers, {at=now+dt, fn=fn}) end
task.defer = function(fn) table.insert(timers, {at=now, fn=fn}) end
function writefile(path, value)
  table.insert(writes, {path=path, value=value})
  if failWrites then error("simulated disk write failure", 0) end
  FS[path]=value
end
local function advance(dt)
  now+=dt
  while true do
    local picked
    for i, entry in ipairs(timers) do
      if entry.at<=now then picked=i; break end
    end
    if not picked then break end
    table.remove(timers,picked).fn()
  end
end
local checks=0
local function check(condition,message)
  checks+=1
  assert(condition,message)
end
local function signal()
  local callbacks={}
  return {Connect=function(_,fn)
    local conn={Connected=true}
    function conn:Disconnect() self.Connected=false end
    callbacks[conn]=fn
    return conn
  end, Fire=function()
    for conn,fn in pairs(callbacks) do if conn.Connected then fn() end end
  end, Count=function()
    local n=0
    for conn in pairs(callbacks) do if conn.Connected then n+=1 end end
    return n
  end}
end
local RS={Stepped=signal()}
local currentCharacter
local function char() return currentCharacter end
local function stopFly() end
local U={want={noclip=false}}
L.Universal=U
local R={controls={},settings={},POWER_LIMIT=1e18}
local K={cfg={approachSettle=0.3}}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
L.Toast={warn=function() end,ok=function() end}
local C={_def={},_live={},notify=function() end}
local function autoId(opts) return opts.id end
'''

tests = r'''
local Cfg
local startupWrites=0
local function fresh()
  FS={}; writes={}; timers={}; now=0; failWrites=false
  installConfig(); Cfg=L.Cfg
  startupWrites=#writes
end
local function reload()
  timers={}; installConfig(); Cfg=L.Cfg
end
local function saved()
  return L.Http:JSONDecode(FS[Cfg.PATH])
end

fresh()
check(Cfg.data.autoSave==true,"first run must enable auto-save by default")
if FACTORY_DEFAULTS then
  local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
  end
  check(equal(saved(),L.Http:JSONDecode(FACTORY_DEFAULTS)),"a clean installation must seed the complete captured configuration")
  local countBeforeReload=#writes
  reload()
  check(#writes==countBeforeReload,"loading an existing configuration must not seed or write factory defaults again")
end
-- The branded build migrates the previous setup only when no new config exists.
if Cfg.PATH=="Giorgio/config.json" then
  local previous=L.Http:JSONEncode({version=Cfg.VERSION,autoSave=false,features={["reproot.x"]=4.5}})
  FS={ ["LumenRepRoot/config.json"]=previous }; writes={}
  reload()
  check(Cfg.data.autoSave==false and Cfg.feat("reproot.x")==4.5,
    "first Giorgio run must restore the previous local preferences")
  check(FS["LumenRepRoot/config.json"]==previous and FS[Cfg.PATH]==previous,
    "migration must preserve the original preferences file")
  Cfg.setFeat("reproot.x",7.25); Cfg.flush()
  reload()
  check(Cfg.feat("reproot.x")==7.25,
    "later Giorgio runs must not overwrite newer preferences with the old setup")
  fresh()
end
Cfg.setFeat("reproot.x",4)
Cfg.setFeat("reproot.y",-2)
check(#timers==1 and #writes==startupWrites,"related edits should share a single pending save without an early write")
advance(0.59)
check(#writes==startupWrites,"auto-save must wait for the debounce")
advance(0.02)
check(#writes==startupWrites+2 and saved().features["reproot.x"]==4 and saved().features["reproot.y"]==-2,
  "one staged/live save must contain the latest edits")
check(Cfg._dirty==false and Cfg.saveError==false,"successful auto-save must clear dirty and error status")

fresh()
Cfg.setFeat("reproot.x",3)
check(Cfg.setAutoSave(false),"turning auto-save off should persist the preference")
check(saved().autoSave==false,"off preference must reach disk")
local baseline=#writes
Cfg.setFeat("reproot.x",8)
advance(1)
check(#writes==baseline,"a callback queued before disabling must not write later edits")
check(Cfg._dirty and saved().features["reproot.x"]==3,
  "off mode must keep later edits only in memory and mark them unsaved")
Cfg.setFeat("reproot.y",9)
advance(60)
check(#writes==baseline and #timers==0,"auto-save off must schedule no background writes")
check(R.saveConfig(),"the public Save now action must work with auto-save off")
check(saved().features["reproot.x"]==8 and saved().features["reproot.y"]==9 and saved().autoSave==false,
  "manual save must persist edits without enabling auto-save")
check(not Cfg._dirty and not Cfg.saveError,"manual save should clear dirty status")

Cfg.setFeat("reproot.x",12)
baseline=#writes
check(Cfg.setAutoSave(true),"enabling auto-save should flush pending edits")
check(#writes==baseline+2 and saved().autoSave and saved().features["reproot.x"]==12,
  "enable must immediately save both preference and unsaved edits")
advance(1)
check(#writes==baseline+2,"the old debounce must not repeat an already completed enable flush")

fresh()
Cfg.setFeat("reproot.x",7)
failWrites=true
advance(1)
check(Cfg._dirty and Cfg.saveError,"a failed background save must keep edits dirty and report failure")
check(Cfg.feat("reproot.x")==7,"failed writes must retain current settings in memory")
failWrites=false
check(R.saveConfig(),"manual save should retry after a transient write failure")
check(saved().features["reproot.x"]==7 and not Cfg._dirty and not Cfg.saveError,
  "retry must save retained settings and clear failure state")

fresh()
Cfg.setFeat("reproot.x",2)
failWrites=true
check(not Cfg.setAutoSave(false),"failed preference persistence must return false")
check(Cfg.data.autoSave==false and Cfg._dirty and Cfg.saveError,
  "a failed off preference write must still disable background writes for this session")
baseline=#writes
Cfg.setFeat("reproot.x",11)
advance(1)
check(#writes==baseline,"pending timers must stay disabled even if persisting the preference failed")
failWrites=false
R.saveConfig()
check(saved().autoSave==false and saved().features["reproot.x"]==11,
  "manual retry must also retain the failed preference change")

fresh()
Cfg.setAutoSave(false)
for _,key in ipairs({"repRoot","fling","voidGuard","followCamera","preview","noclip","returnHome"}) do
  Cfg.setFeat("reproot."..key,false)
end
Cfg.setFeat("reproot.x",3.25)
Cfg.setFeat("reproot.repPower",123456)
Cfg.setFeat("reproot.loopMode","Selected players")
Cfg.setFeat("reproot.variant",Presets[#Presets].name)
R.saveConfig()
Cfg.setFeat("reproot.x",19)
reload()
check(Cfg.data.autoSave==false,"saved off preference must survive a new config module instance")
check(Cfg.feat("reproot.x")==3.25,"reloading in manual mode must discard unsaved session edits")
baseline=#writes
restoreSettings()
check(not R.repRoot and not R.fling and not R.voidGuard and not R.followCamera and not R.preview and not R.noclip,
  "saved false toggles must survive initialization instead of being reset to on")
check(not K.cfg.returnHome and R.settings.x==3.25 and K.cfg.repPower==123456 and R.loopMode=="Selected players"
  and R.settings.variant==Presets[#Presets].name,
  "saved target settings must restore into the actual feature state")
Cfg.setFeat("reproot.y",6)
advance(10)
check(#writes==baseline,"a reloaded off preference must suppress new background saves")

local autoOpts={id="ignored.autoSave",persist=false,default=true,callback=R.setAutoSave}
bindPersist(autoOpts)
check(autoOpts.callback==R.setAutoSave and autoOpts._id==nil,
  "a nonpersisted auto-save control must not get a second feature preference writer")
autoOpts.callback(true)
check(Cfg.feat("ignored.autoSave")==nil and Cfg.data.autoSave,
  "the auto-save control must use only its canonical schema preference")

-- Drive the actual collision worker and the actual persisted toggle adapter.
local function part(collides)
  return {Parent=true,CanCollide=collides,IsA=function(_,kind) return kind=="BasePart" end}
end
local torso,head,root=part(true),part(true),part(false)
local character={parts={torso,head,root}}
function character:GetDescendants() return self.parts end
currentCharacter=character
local noclipOpts={id="reproot.noclip",default=false,callback=R.setNoclip}
bindPersist(noclipOpts)
check(noclipOpts.callback(true),"the persisted Noclip control should accept enable")
RS.Stepped.Fire()
check(R.noclip and U.want.noclip and not torso.CanCollide and not head.CanCollide and not root.CanCollide,
  "enabled noclip must disable colliding body parts while retaining intent")
check(Cfg.feat("reproot.noclip")==true,"the actual toggle adapter must persist noclip intent")
local accessory=part(true); table.insert(character.parts,accessory)
RS.Stepped.Fire()
check(not accessory.CanCollide,"new body parts must receive noclip on the next physics step")
check(U.suspendNoclip("fling"),"the first physics suspension must acquire its token")
check(torso.CanCollide and head.CanCollide and accessory.CanCollide and not root.CanCollide,
  "suspension must restore original collisions exactly, including originally noncolliding parts")
check(U.want.noclip and RS.Stepped.Count()==0,"suspension must stop the writer without changing user intent")
check(not U.suspendNoclip("fling"),"a duplicate suspension must not acquire a second token")
check(U.suspendNoclip("secondary"),"independent features must be able to nest suspension")
U.resumeNoclip("fling"); RS.Stepped.Fire()
check(torso.CanCollide and RS.Stepped.Count()==0,"releasing one holder must not resume past another holder")
U.resumeNoclip("secondary"); RS.Stepped.Fire()
check(not torso.CanCollide and RS.Stepped.Count()==1,"the final holder should resume one collision writer")
U.suspendNoclip("fling")
noclipOpts.callback(false)
U.resumeNoclip("fling"); RS.Stepped.Fire()
check(not R.noclip and not U.want.noclip and torso.CanCollide and RS.Stepped.Count()==0,
  "turning noclip off while suspended must prevent it from rearming after the attempt")
check(Cfg.feat("reproot.noclip")==false,"off during suspension must also persist off")
currentCharacter=nil
check(U.setNoclip(true),"noclip may wait for a missing character")
local respawned=part(true)
currentCharacter={GetDescendants=function() return {respawned} end}
RS.Stepped.Fire()
check(not respawned.CanCollide,"noclip must apply when a character returns")
U.setNoclip(false)
check(respawned.CanCollide,"disabling after respawn must restore the new body")
U.setNoclip(true); RS.Stepped.Fire()
L.teardown()
check(respawned.CanCollide and not U.want.noclip and RS.Stepped.Count()==0,
  "unloading must synchronously restore collisions and release the noclip writer")

-- Retired generations must never flush a pending callback into a newer run.
fresh()
Cfg.setFeat("reproot.x",17)
getgenv().__LUMEN_GEN+=1
advance(1)
check(#writes==startupWrites and Cfg._dirty,"a retired generation must abandon its delayed save")
print(string.format("%d preference, persistence and noclip checks passed",checks))
'''

config_module = module("lm_15_config.lua")
presets = between("R.settings = {", "\nR.presets=Presets")
noclip = between("local noclipConn, collideSnap", "-- ---------------------------------------------------------------- inf jump")
wrapper = between("function R.setNoclip(value)", "local function studioTarget()")
adapter = between("local function bindPersist(opts)", "\nC.bindPersist = bindPersist")
restoration = between("-- Defaults apply only when no saved choice exists.", "\nR.setNoclip(R.noclip)") + "\nR.setNoclip(R.noclip)"
script = "\n".join([
    prelude, module("lm_00_core.lua"), harness, presets,
    "local FACTORY_DEFAULTS=" + (json.dumps(factory_defaults) if factory_defaults else "nil"),
    "local function installConfig()", config_module, "end",
    noclip, wrapper, adapter,
    "local function restoreSettings()", restoration, "end", tests,
])
with tempfile.TemporaryDirectory(prefix="lumen-preferences-") as folder:
    path = Path(folder) / "preferences.luau"
    path.write_text(script, encoding="utf-8")
    result = subprocess.run([str(RUNTIME), str(path)], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    raise SystemExit(result.returncode)
