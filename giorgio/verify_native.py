"""Run native opacity and tooltip contracts against the actual Luau implementation."""
from pathlib import Path
import argparse
import subprocess
import tempfile

root=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("source",nargs="?",type=Path,default=root.parent/"Giorgio.lua")
parser.add_argument("--native-module",action="store_true",help="Use the work-in-progress native module with the assembled factory")
args=parser.parse_args()
source=args.source.read_text(encoding="utf-8")

def between(text,start,end):
    a=text.index(start)
    return text[a:text.index(end,a)]

native=((root/"native-text.lua").read_text(encoding="utf-8") if args.native_module else
        between(source,"do -- Giorgio native-text.lua\n","\ndo -- Giorgio ui-skin.lua"))
factory=between(source,"function L.uiRead(object,property)","\nlocal mk = L.mk")
helpers=between(source,"function A.groupTo(group, alpha, token)","\n-- Rest values are captured ONCE")
reachable=between(source,"  local function reachable(o, pt)","\n  local function under(pt)")
prelude=r'''
local checks,failures=0,0
local function check(ok,message)
  checks+=1
  if not ok then failures+=1; print("FAIL: "..message) end
end
local function near(a,b) return math.abs(a-b)<1e-6 end
-- Roblox stores these rendered properties as float32 even though Luau math is
-- float64. Exact equality with a computed double would mistake internal writes
-- for authored alpha and repeatedly darken the whole interface.
local floatBytes=buffer.create(4)
local function float32(value)
  buffer.writef32(floatBytes,0,value)
  return buffer.readf32(floatBytes,0)
end
local storedFloat32={BackgroundTransparency=true,TextTransparency=true,TextStrokeTransparency=true,
  ImageTransparency=true,Transparency=true,GroupTransparency=true}
local deferred=false
local events={}
local function signal()
  local callbacks={}
  local value={}
  function value:Connect(fn)
    local conn={Connected=true}
    function conn:Disconnect() self.Connected=false end
    callbacks[conn]=fn; return conn
  end
  function value:Fire(...)
    local args=table.pack(...)
    for conn,fn in pairs(callbacks) do
      if conn.Connected then
        if deferred then events[#events+1]=function() if conn.Connected then fn(table.unpack(args,1,args.n)) end end
        else fn(...) end
      end
    end
  end
  function value:DisconnectAll() for conn in pairs(callbacks) do conn:Disconnect() end end
  return value
end
local function drain()
  local count=0
  while #events>0 do
    local fn=table.remove(events,1); fn(); count+=1
    assert(count<10000,"property changes never settled")
  end
end
local guiClasses={Frame=true,CanvasGroup=true,TextLabel=true,TextButton=true,TextBox=true,
  ImageLabel=true,ImageButton=true,ScrollingFrame=true}
local methods={}
local mt={}
function mt.__index(self,key)
  return methods[key] or self._data[key]
end
local function ancestry(object)
  object.AncestryChanged:Fire(object,object.Parent)
  for _,child in ipairs(object:GetChildren()) do ancestry(child) end
end
function mt.__newindex(self,key,value)
  local data=self._data
  if storedFloat32[key] and type(value)=="number" then value=float32(value) end
  if data[key]==value then return end
  if key=="Parent" then
    local previous=data.Parent
    if previous then
      local at=table.find(previous._children,self)
      if at then table.remove(previous._children,at) end
    end
    data.Parent=value
    if value then value._children[#value._children+1]=self end
    ancestry(self)
    local parent=value
    while parent do
      parent.DescendantAdded:Fire(self)
      for _,child in ipairs(self:GetDescendants()) do parent.DescendantAdded:Fire(child) end
      parent=parent.Parent
    end
  else data[key]=value end
  if self._signals[key] then self._signals[key]:Fire() end
end
function methods:IsA(class)
  return self._class==class or class=="GuiObject" and guiClasses[self._class]==true
end
function methods:GetPropertyChangedSignal(property)
  self._signals[property]=self._signals[property] or signal()
  return self._signals[property]
end
function methods:SetAttribute(name,value) self._attributes[name]=value end
function methods:GetAttribute(name) return self._attributes[name] end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
  local result={}
  for _,child in ipairs(self._children) do
    result[#result+1]=child
    for _,descendant in ipairs(child:GetDescendants()) do result[#result+1]=descendant end
  end
  return result
end
function methods:Destroy()
  self.Destroying:Fire()
  for _,child in ipairs(self:GetChildren()) do child:Destroy() end
  self.Parent=nil
  if deferred then drain() end
  for _,event in pairs(self._signals) do event:DisconnectAll() end
  for _,name in ipairs({"AncestryChanged","DescendantAdded","Destroying"}) do self[name]:DisconnectAll() end
end
local Instance={}
function Instance.new(class)
  local object=setmetatable({_class=class,_children={},_attributes={},_signals={},_data={
    BackgroundTransparency=0,TextTransparency=0,TextStrokeTransparency=1,ImageTransparency=0,Transparency=0,
    GroupTransparency=0,Visible=true,Enabled=true,ClipsDescendants=false,
    AbsolutePosition={X=0,Y=0},AbsoluteSize={X=100,Y=100},
    AncestryChanged=signal(),DescendantAdded=signal(),Destroying=signal()}},mt)
  return object
end
local game={}
local L={Giorgio={},paints={}}
local env={LUMEN=L}
local function getgenv() return env end
local function typeof(value) return type(value) end
local A={}
local M={to=function(object,property,value) L.uiWrite(object,property,value) end,
  set=function(object,property,value) L.uiWrite(object,property,value) end}
function L.strokeRest(stroke) return stroke:GetAttribute("Rest") or .2 end
'''
tests=r'''
local N=L.Giorgio.Native
local gui=L.mk("ScreenGui",{})
local outer=L.mk("CanvasGroup",{Parent=gui,GroupTransparency=.25,BackgroundTransparency=.2})
local inner=L.mk("CanvasGroup",{Parent=outer,GroupTransparency=.5,BackgroundTransparency=1})
local label=L.mk("TextLabel",{Parent=inner,TextTransparency=.2,BackgroundTransparency=1})
check(outer:IsA("Frame") and not outer:IsA("CanvasGroup"),"fade groups remain ordinary native Frames")
check(near(outer.BackgroundTransparency,.4),"group root background inherits its own logical opacity")
check(near(label.TextTransparency,.7),"nested groups compose child opacity multiplicatively")
check(near(N.get(label,"TextTransparency"),.2),"logical reads retain the authored child opacity")
N.set(outer,"GroupTransparency",.5)
check(near(label.TextTransparency,.8),"changing an ancestor immediately updates descendants")
N.set(label,"TextTransparency",.4)
check(near(label.TextTransparency,.85),"animated child alpha composes with the current ancestor fade")
label.TextTransparency=.6
check(near(N.get(label,"TextTransparency"),.6) and near(label.TextTransparency,.9),"direct child writes update its base alpha once")
N.set(outer,"GroupTransparency",0); N.set(inner,"GroupTransparency",0)
check(near(label.TextTransparency,.6),"removing parent fades restores the current child alpha")
N.set(outer,"GroupTransparency",.5)
label.Parent=gui
check(near(label.TextTransparency,.6),"moving out of a group releases inherited opacity")
label.Parent=inner
check(near(label.TextTransparency,.8),"moving into a faded subtree reapplies inherited opacity")

local child=L.mk("TextLabel",{TextTransparency=.2})
local declarative=L.mk("CanvasGroup",{Parent=gui,GroupTransparency=.75,child})
check(near(child.TextTransparency,.8),"declarative children inherit the group's initial fade at registration")
local raw=Instance.new("ImageLabel")
raw.ImageTransparency=.2; raw.Parent=declarative
check(near(raw.ImageTransparency,.8),"a child added outside the factory inherits the active fade")

local outlined=L.mk("CanvasGroup",{Parent=gui,GroupTransparency=0})
local stroke=L.mk("UIStroke",{Parent=outlined,Transparency=.2})
stroke:SetAttribute("Rest",.2)
A.groupSet(outlined,.5)
check(near(stroke.Transparency,.6) and near(N.get(stroke,"Transparency"),.2),"shared groupSet fades a logical group's stroke exactly once")
A.groupTo(outlined,0,"base")
check(near(stroke.Transparency,.2),"shared groupTo restores the stroke's base opacity")
local oldGroup=Instance.new("CanvasGroup"); oldGroup.Parent=gui
local oldStroke=L.mk("UIStroke",{Parent=oldGroup,Transparency=.2})
oldStroke:SetAttribute("Rest",.2)
A.groupSet(oldGroup,.5)
check(near(oldStroke.Transparency,.6),"the shared helper retains support for an original CanvasGroup")

deferred=true
local delayed=L.mk("CanvasGroup",{Parent=gui,GroupTransparency=0})
local delayedText=L.mk("TextLabel",{Parent=delayed,TextTransparency=.2})
drain()
N.set(delayed,"GroupTransparency",.5); drain()
check(near(delayedText.TextTransparency,.6) and near(N.get(delayedText,"TextTransparency"),.2),
  "deferred property signals do not feed composed output back into base opacity")
delayedText.TextTransparency=.4; drain()
check(near(delayedText.TextTransparency,.7) and near(N.get(delayedText,"TextTransparency"),.4),
  "deferred direct writes update base opacity without a repeated fade")
deferred=false

local filmGroup=L.mk("CanvasGroup",{Parent=gui,GroupTransparency=0,BackgroundTransparency=1})
local frontPicture=L.mk("ImageLabel",{Parent=filmGroup,ImageTransparency=0,BackgroundTransparency=1})
local backPicture=L.mk("ImageLabel",{Parent=filmGroup,ImageTransparency=0,BackgroundTransparency=1,Visible=false})
local filmCaption=L.mk("TextLabel",{Parent=filmGroup,TextTransparency=.1,TextStrokeTransparency=.75,BackgroundTransparency=1})
deferred=true
for cycle=1,4 do
  A.groupSet(filmGroup,.6); drain()
  check(near(frontPicture.ImageTransparency,.6) and near(backPicture.ImageTransparency,.6),
    "both buffered film surfaces inherit the same window fade")
  check(near(filmCaption.TextTransparency,.64) and near(filmCaption.TextStrokeTransparency,.9),
    "caption and text outline preserve independent authored opacity during a window fade")
  A.groupTo(filmGroup,0,"base"); drain()
  check(near(frontPicture.ImageTransparency,0) and near(backPicture.ImageTransparency,0) and near(filmCaption.TextTransparency,.1),
    "repeated window transitions restore media and caption clarity without accumulating opacity")
end
N.set(filmGroup,"GroupTransparency",.25)
N.set(frontPicture,"ImageTransparency",.2)
N.set(filmGroup,"GroupTransparency",.5)
drain()
check(near(frontPicture.ImageTransparency,.6) and near(N.get(frontPicture,"ImageTransparency"),.2),
  "several queued parent and image updates resolve to the newest authored values")
filmGroup:Destroy(); drain()
check(N.records[frontPicture]==nil and N.records[backPicture]==nil and N.records[filmCaption]==nil,
  "closing a film releases both buffered surfaces and caption opacity records")
deferred=false

local pt={X=50,Y=50}
check(reachable(child,pt)==false,"a tooltip inside a logical group over the fade threshold is unreachable")
N.set(declarative,"GroupTransparency",.5)
check(reachable(child,pt)==true,"the existing tooltip threshold includes half opacity")
declarative.Visible=false
check(reachable(child,pt)==false,"a hidden native group rejects tooltips")
declarative.Visible=true; declarative.ClipsDescendants=true
check(reachable(child,{X=120,Y=50})==false,"clipping remains part of tooltip reachability")
oldGroup.GroupTransparency=.75
check(reachable(oldStroke,pt)==false,"original CanvasGroup tooltips still honor group opacity")

local destroyed=L.mk("CanvasGroup",{Parent=gui,GroupTransparency=.5})
local destroyedText=L.mk("TextLabel",{Parent=destroyed,TextTransparency=.2})
destroyed:Destroy()
check(N.records[destroyedText]==nil and N.records[destroyed]==nil and N.groups[destroyed]==nil,
  "destroying a subtree drops its native records immediately")
print(string.format("Native opacity and tooltip checks: %d passed, %d failed",checks-failures,failures))
assert(failures==0,"native opacity regression failures")
'''
with tempfile.TemporaryDirectory(prefix="giorgio-native-") as folder:
    script=Path(folder)/"native.luau"
    script.write_text("\n".join([prelude,factory,native,helpers,reachable,tests]),encoding="utf-8")
    runtime=Path.home()/"AppData/Local/Temp/luaudl/luau.exe"
    subprocess.run([str(runtime),str(script)],check=True)
