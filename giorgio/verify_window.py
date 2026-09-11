"""Exercise assembled window minimise/restore against native opacity and timers.

The renderer is mocked; the actual shipped transition methods and opacity
adapter execute in Luau. No Roblox client or user configuration is touched.
"""
from pathlib import Path
import argparse
import ast
import subprocess
import tempfile

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", nargs="?", type=Path, default=root.parent / "Giorgio.lua")
args = parser.parse_args()
source = args.source.read_text(encoding="utf-8")


def between(start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


# Reuse the native fixture's faithful float32/property-event simulator without
# importing it (which would execute a separate test or parse our arguments).
tree = ast.parse((root / "verify_native.py").read_text(encoding="utf-8"))
prelude = next(ast.literal_eval(node.value) for node in tree.body
               if isinstance(node, ast.Assign)
               and any(isinstance(target, ast.Name) and target.id == "prelude" for target in node.targets))
factory = between("function L.uiRead(object,property)", "\nlocal mk = L.mk")
native = between("do -- Giorgio native-text.lua\n", "\ndo -- Giorgio ui-skin.lua")
helpers = between("function A.groupTo(group, alpha, token)", "\n-- Rest values are captured ONCE")
window = between("function Window:show(transitionGen)", "\nfunction Window:subtitle(text)")
setup = r'''
local originalIndex,originalWrite=mt.__index,mt.__newindex
function mt.__index(object,key)
  if key=="GroupTransparency" and object._class~="CanvasGroup" then error("GroupTransparency is not a property of a native "..object._class) end
  return originalIndex(object,key)
end
function mt.__newindex(object,key,value)
  if key=="GroupTransparency" and object._class~="CanvasGroup" then error("GroupTransparency is not a property of a native "..object._class) end
  return originalWrite(object,key,value)
end
function methods:IsDescendantOf(parent)
  local at=self.Parent
  while at do if at==parent then return true end; at=at.Parent end
  return false
end
function methods:FindFirstChild(name)
  for _,child in ipairs(self:GetChildren()) do if child.Name==name then return child end end
end
local UDim2={}
function UDim2.new(xs,xo,ys,yo) return {X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}} end
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
local host=Instance.new("ScreenGui")
function L.host() return host end
function L.live() return true end
function L.try(_,fn,...) return fn(...) end
L.Cfg={data={}}
local blur=0
function A.blurTo(value) blur=value end
function M.stop() end
function M.resolve(token) return type(token)=="table" and token[1] or token=="base" and .36 or .19,0 end
local now,scheduled,sequence=0,{},0
local task={}
function task.delay(after,callback)
  sequence+=1; scheduled[#scheduled+1]={at=now+after,callback=callback,serial=sequence}
end
function task.defer(callback) task.delay(0,callback) end
local function advance(delta)
  local target=now+delta
  while true do
    table.sort(scheduled,function(a,b) return a.at==b.at and a.serial<b.serial or a.at<b.at end)
    local nextTask=scheduled[1]
    if not nextTask or nextTask.at>target then break end
    table.remove(scheduled,1); now=nextTask.at; nextTask.callback(); drain()
  end
  now=target; drain()
end
local Window={DOCK_IN=UDim2.fromOffset(100,20),DOCK_OUT=UDim2.fromOffset(100,-100),BLUR=8}
Window.__index=Window
'''
tests = r'''
local N=L.Giorgio.Native
local window=setmetatable({width=1000,height=700,hidden=false,shadowRest=.35},Window)
window.shell=L.mk("Frame",{Name="Shell",Parent=host})
window.root=L.mk("CanvasGroup",{Name="Root",Parent=window.shell,BackgroundTransparency=.15,GroupTransparency=0})
window.body=L.mk("Frame",{Parent=window.root,BackgroundTransparency=0})
window.wash=L.mk("Frame",{Parent=window.root,BackgroundTransparency=0})
window.caption=L.mk("TextLabel",{Parent=window.root,TextTransparency=.1})
window.shadow=L.mk("ImageLabel",{Parent=window.shell,ImageTransparency=.35})
window.scrim=L.mk("Frame",{Parent=host,BackgroundTransparency=.5})
window.dock=L.mk("Frame",{Name="Dock",Parent=host,BackgroundTransparency=.05})
local dockTitle=L.mk("TextLabel",{Parent=window.dock,TextTransparency=.1})
local left=L.mk("CanvasGroup",{Parent=window.dock,GroupTransparency=.2,BackgroundTransparency=1})
local right=L.mk("CanvasGroup",{Parent=window.dock,GroupTransparency=.35,BackgroundTransparency=1})
local leftTitle=L.mk("TextLabel",{Parent=left,TextTransparency=.1})
local rightTitle=L.mk("TextLabel",{Parent=right,TextTransparency=.25})
L.Pins={bars={left,right}}
local orbLabel=L.mk("ImageLabel",{Parent=window.dock,ImageTransparency=0})
window.dockOrb={playing=true,labels={orbLabel},plays=0,pauses=0}
function window.dockOrb:play() self.playing=true; self.plays+=1 end
function window.dockOrb:pause() self.playing=false; self.pauses+=1 end
local morphs={}
function window:_morph(done,progress)
  local proxy=L.mk("ScreenGui",{Name="LumenMorph",Parent=host})
  local morph={done=done,progress=progress,proxy=proxy}; morphs[#morphs+1]=morph
  task.delay(.1,function() progress(.89) end)
  task.delay(.7,function() proxy:Destroy(); done() end)
  return .7
end
local function dockRestored()
  return near(N.get(left,"GroupTransparency"),.2) and near(N.get(right,"GroupTransparency"),.35)
    and near(leftTitle.TextTransparency,.28) and near(rightTitle.TextTransparency,.5125)
    and near(dockTitle.TextTransparency,.1)
end
deferred=true
for cycle=1,4 do
  window:minimise(); drain()
  check(window.hidden and window._morphBusy,"minimise starts one transition and marks the hub hidden")
  check(not window.dockOrb.playing and near(N.get(left,"GroupTransparency"),1),"minimise pauses dock playback and hides both native pin strips")
  local generation=window._transitionGen
  window:minimise()
  check(window._transitionGen==generation,"a second minimise while morphing does not restart or double-hide")
  advance(.15)
  check(leftTitle.TextTransparency<1 and leftTitle.TextTransparency>.28,"dock pin strip reveals through logical opacity during the morph")
  advance(.6)
  check(not window.root.Visible and not window.shell.Visible and not window._morphBusy,"minimise finishes and hides the panel after its fade")
  check(dockRestored() and window.dockOrb.playing,"completed dock reveal returns both strips and title to authored values")
  window:restore(); advance(.1)
  check(not window.hidden and window.root.Visible and window.shell.Visible,"restore makes the real window visible")
  check(near(window.caption.TextTransparency,.1) and near(N.get(window.root,"GroupTransparency"),0),"restore returns native text to authored opacity")
  check(window.dock.Position==Window.DOCK_OUT and dockRestored(),"restore parks the dock without losing the next minimise's rest values")
end

window:minimise(); advance(.05)
local stale=morphs[#morphs]
window:restore(); advance(.8)
check(not window.hidden and window.root.Visible and window.shell.Visible,"restore during minimise survives the old deferred hide")
check(not window._morphBusy and stale.proxy.Parent==nil,"restore destroys the old morph and releases the busy flag")
check(dockRestored(),"stale morph callbacks cannot overwrite restored native pin opacity")
window:minimise(); advance(.1)
local newest=morphs[#morphs]
stale.progress(1); stale.done(); drain()
check(window._morphBusy and not window.dockOrb.playing,"callbacks from an older morph cannot finish a newer minimise")
advance(.7)
check(not window._morphBusy and newest.proxy.Parent==nil and dockRestored(),"a fresh minimise succeeds immediately after interruption")
window:restore(); advance(.05)

window:hide(); advance(.05); window:show(); advance(.4)
check(not window.hidden and window.root.Visible and window.shell.Visible,"show during a hide cancels its delayed visibility change")
L.Cfg.data.toggleAction="Minimise"
window:toggle(); advance(.8)
check(window.hidden and not window.root.Visible,"the default toggle actually minimises the main window")
window:toggle(); advance(.1)
check(not window.hidden and window.root.Visible,"toggle restores from the dock")
L.Cfg.data.toggleAction="Hide"
local oldCount=#morphs
window:toggle(); advance(.4)
check(window.hidden and not window.root.Visible and #morphs==oldCount,"Hide preference bypasses the morph and still completes")
window:toggle(); advance(.1)
check(not window.hidden and window.root.Visible,"Hide preference can be toggled back on")

local reattachments=0
L.Side={detached=true,reattach=function() reattachments+=1 end}
window:restore(); window:minimise(); advance(.01)
check(reattachments==0,"a superseded restore cannot reattach the panel during a newer minimise")
window:restore(); advance(.01)
check(reattachments==1,"the current restore reattaches the panel once")
advance(1)
print(string.format("Window transition checks: %d passed, %d failed",checks-failures,failures))
assert(failures==0,"window transition regression failures")
'''
with tempfile.TemporaryDirectory(prefix="giorgio-window-") as folder:
    script = Path(folder) / "window.luau"
    script.write_text("\n".join([prelude, setup, factory, native, helpers, window, tests]), encoding="utf-8")
    runtime = Path.home() / "AppData/Local/Temp/luaudl/luau.exe"
    subprocess.run([str(runtime), str(script)], check=True)
