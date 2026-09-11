"""Compile the panel and exercise its shipped filtering/layout helpers in Luau.

No Roblox client, character, user configuration, or live interface is touched.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("source", nargs="?", type=Path, default=Path(__file__).resolve().parent.parent / "Giorgio.lua",
                    help="Assembled script to verify (default: Giorgio.lua)")
parser.add_argument("--panel-module", action="store_true", help="Verify the work-in-progress panel source module")
runtime_dir = Path.home() / "AppData/Local/Temp/luaudl"
parser.add_argument("--runtime", type=Path, default=runtime_dir / "luau.exe")
parser.add_argument("--compiler", type=Path, default=runtime_dir / "luau-compile.exe")
args = parser.parse_args()
source_path = Path(__file__).with_name("player-panel.lua") if args.panel_module else args.source
source = source_path.read_text(encoding="utf-8")
print(f"Verifying panel from: {source_path.resolve()}", flush=True)
subprocess.run([str(args.compiler), "--null", str(source_path)], check=True)
core = source.split("-- PANEL_CORE_BEGIN", 1)[1].split("-- PANEL_CORE_END", 1)[0]
skin = Path(__file__).with_name("ui-skin.lua").read_text(encoding="utf-8") if args.panel_module else source
theme = skin[skin.index("local ivory=Color3.fromRGB"):skin.index("for name,value in pairs(palette)")]
palette = source[source.index("local ink={"):source.index("local serif=",source.index("local ink={"))]
colors = r'''
local Color3={}
function Color3.new(r,g,b) return {R=r,G=g,B=b} end
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
'''
tests = r'''
local assertions=0
local function check(ok,message)
  assertions+=1
  assert(ok,message)
end
check(Directory.matches("alice","Alicia","ALI","All",false,500),"search ignores case")
check(Directory.matches("alice","Alicia","icia","All",false,500),"display names are searchable")
check(not Directory.matches("alice","Alicia","bob","All",true,0),"query and filter both apply")
check(Directory.matches("a.b","First",".","All",false,0),"search punctuation must be literal")
check(not Directory.matches("alice","First",".","All",false,0),"search must not interpret Lua patterns")
check(Directory.matches("alice","Alicia","","Nearby",false,250),"nearby radius includes boundary")
check(not Directory.matches("alice","Alicia","","Nearby",true,251),"queued does not bypass nearby filter")
check(not Directory.matches("alice","Alicia","","Nearby",true,math.huge),"missing characters are not nearby")
check(Directory.matches("alice","Alicia","","Queued",true,math.huge),"queued respawning players stay in group")
check(not Directory.matches("alice","Alicia","","Queued",nil,0),"unselected players stay outside queued filter")

local a={DisplayName="Alice",UserId=10}
local b={DisplayName="alice",UserId=11}
local c={DisplayName="Bob",UserId=12}
local d={DisplayName="Aaron",UserId=13}
local distances={[a]=20,[b]=20,[c]=math.huge,[d]=10}
local records={c,b,d,a}
table.sort(records,function(x,y) return Directory.less(x,y,"distance",distances) end)
check(records[1]==d and records[2]==a and records[3]==b and records[4]==c,"nearest sort is stable with missing characters")
table.sort(records,function(x,y) return Directory.less(x,y,"name",distances) end)
check(records[1]==d and records[2]==a and records[3]==b and records[4]==c,"name sort resolves equal names by user ID")
check(not Directory.less(a,a,"distance",distances),"sort comparison is irreflexive")
check(not Directory.less(a,a,"name",distances),"name comparison is irreflexive")

local function luminance(color)
  local function linear(value) return value<=.04045 and value/12.92 or ((value+.055)/1.055)^2.4 end
  return .2126*linear(color.R)+.7152*linear(color.G)+.0722*linear(color.B)
end
local function contrast(a,b)
  local x,y=luminance(a),luminance(b)
  return (math.max(x,y)+.05)/(math.min(x,y)+.05)
end
check(ink.paper==T.c.surface and ink.white==T.c.raised and ink.charcoal==T.c.text,"directory uses the main interface's actual surface and text colors")
check(contrast(ink.charcoal,ink.paper)>=7 and contrast(ink.charcoal,ink.white)>=7,"primary text stays legible on both dark surfaces")
check(contrast(ink.muted,ink.paper)>=4.5 and contrast(ink.muted,ink.white)>=4.5,"secondary labels retain reading contrast at their small font size")
check(contrast(ink.charcoal,ink.danger)>=4.5,"the Stop button retains readable light text against its dark red fill")
check(contrast(ink.paper,ink.charcoal)>=7,"filled actions retain dark text on the ivory accent")
check(contrast(ink.green,ink.paper)>=4.5,"readiness and queue status remain legible on the dark theme")

local first,count=Directory.window(0,300,66,0)
check(first==1 and count==0,"empty roster renders no rows")
first,count=Directory.window(5000,300,66,1)
check(first==1 and count==1,"stale scroll after departures cannot index outside roster")
first,count=Directory.window(66,300,66,100)
check(first==2 and count==6,"virtualization starts at scrolled index and includes overscan")
for total=0,1000,10 do
  for scroll=0,66000,577 do
    first,count=Directory.window(scroll,300,66,total)
    check(count>=0 and count<=6,"row allocation stays bounded independent of server size")
    check(first>=1 and first<=math.max(total,1),"first row stays valid")
    check(first+count-1<=math.max(total,1),"render slice stays inside roster")
  end
end

for _,viewport in ipairs({{1920,1080},{1280,720},{720,620},{390,844},{844,390},{320,240}}) do
  local vx,vy=viewport[1],viewport[2]
  for _,point in ipairs({{0,0},{-500,-500},{5000,5000},{200,150}}) do
    for _,preferred in ipairs({.85,1,1.1,1.36,1.6,1.76,2.2}) do
      local scale,x,y=Directory.fit(vx,vy,720,620,point[1],point[2],preferred)
      check(scale>0 and scale<=preferred,"scale remains positive and respects size preference")
      check(x>=8 and y>=8,"dragging preserves leading viewport margins")
      check(x+720*scale<=vx-8+.00001 and y+620*scale<=vy-8+.00001,"window stays fully visible on phone and desktop viewports")
    end
  end
end
local scale,x,y=Directory.fit(1920,1080,720,620,nil,nil,1)
check(scale==1 and x==600 and y==230,"first open is centered")
scale,x,y=Directory.fit(2560,1369,720,620,nil,nil,Directory.defaultScale(1.27))
check(scale==1.15 and math.abs(x-866)<.00001 and math.abs(y-328)<.00001,"default stays modest on a large display")
check(Directory.defaultScale(.8)==.8 and Directory.defaultScale(1)==1,"automatic sizing still respects smaller displays")
check(Directory.defaultScale(1.75)==1.15,"a large display cannot inflate the default beyond 115 percent")
local resized=Directory.resize(1920,1080,720,620,100,100,1,72,62)
check(math.abs(resized-1.1)<.00001,"corner movement follows the pointer at the original aspect ratio")
resized=Directory.resize(1920,1080,720,620,100,100,1,-72,-62)
check(math.abs(resized-.9)<.00001,"corner movement can shrink continuously")
resized=Directory.resize(1920,1080,720,620,100,100,1,-10000,-10000)
check(resized==.55,"a desktop resize cannot make the controls arbitrarily small")
for _,viewport in ipairs({{2560,1440},{1920,1080},{1280,720},{390,844},{844,390},{320,240}}) do
  local vx,vy=viewport[1],viewport[2]
  for _,point in ipairs({{8,8},{100,100},{5000,5000},{vx*.5,vy*.5}}) do
    local initial,originX,originY=Directory.fit(vx,vy,720,620,point[1],point[2],1)
    for _,delta in ipairs({{-10000,-10000},{-80,-60},{0,0},{72,62},{300,0},{0,300},{10000,10000}}) do
      resized=Directory.resize(vx,vy,720,620,originX,originY,initial,delta[1],delta[2])
      local fitted,px,py=Directory.fit(vx,vy,720,620,originX,originY,resized)
      check(resized>0 and resized<=2.2,"resizing stays within supported scale limits")
      check(math.abs(px-originX)<.00001 and math.abs(py-originY)<.00001,"resizing keeps the top-left corner stationary")
      check(math.abs(resized-fitted)<.00001,"resizing cannot trigger a second scale correction or jump")
      check(px+720*fitted<=vx-8+.00001 and py+620*fitted<=vy-8+.00001,"the resize grip stays reachable within the viewport")
    end
  end
end
print(string.format("PASS: %d assertions on shipped directory search, sorting, row window, independent default and continuous resizing",assertions))
'''
with tempfile.TemporaryDirectory(prefix="giorgio-panel-") as folder:
    test_path = Path(folder) / "directory-tests.luau"
    test_path.write_text(colors + theme + "\nlocal T={c=palette}\n" + palette + core + tests, encoding="utf-8")
    subprocess.run([str(args.runtime), str(test_path)], check=True)
