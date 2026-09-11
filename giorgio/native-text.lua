-- Keep text and films in Roblox's native renderer at every interface scale.
-- A logical fade group is an ordinary Frame; opacity is composed per object.
local L=getgenv().LUMEN
local N={groups=setmetatable({}, {__mode="k"}),records=setmetatable({}, {__mode="k"}),
  outputs=setmetatable({}, {__mode="k"}),connections=setmetatable({}, {__mode="k"}),
  groupWatch=setmetatable({}, {__mode="k"})}
L.Giorgio.Native=N
local function properties(object)
  local out={}
  if object:IsA("GuiObject") then out[#out+1]="BackgroundTransparency" end
  if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
    out[#out+1]="TextTransparency"; out[#out+1]="TextStrokeTransparency"
  elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then out[#out+1]="ImageTransparency"
  elseif object:IsA("UIStroke") then out[#out+1]="Transparency" end
  return out
end
local function opacity(object)
  local value=1; local parent=object
  while parent do
    local alpha=N.groups[parent]
    if alpha then value*=1-math.clamp(alpha,0,1) end
    parent=parent.Parent
  end
  return value
end
local function apply(object)
  local record=N.records[object]; if not record then return end
  local factor=opacity(object)
  local output=N.outputs[object]
  for property,base in pairs(record) do
    local value=1-(1-base)*factor
    -- Roblox stores transparency as float32. Guard synchronous property events,
    -- then remember the value actually stored by the engine, not our computed
    -- double, so deferred internal writes cannot become a new authored opacity.
    output._writing=true
    if object[property]~=value then object[property]=value end
    output[property]=object[property]
    output._writing=false
  end
end
local function connect(object,event,callback)
  local connection=event:Connect(callback)
  table.insert(N.connections[object],connection)
  return connection
end
local function forget(object)
  for _,connection in ipairs(N.connections[object] or {}) do connection:Disconnect() end
  N.connections[object]=nil; N.groupWatch[object]=nil
  N.records[object]=nil; N.outputs[object]=nil; N.groups[object]=nil
end
function N.register(object,groupAlpha)
  if not N.records[object] then
    local record={}; N.records[object]=record; N.outputs[object]={}; N.connections[object]={}
    for _,property in ipairs(properties(object)) do
      record[property]=object[property]
      connect(object,object:GetPropertyChangedSignal(property),function()
        local output=N.outputs[object]
        if not output or output._writing or object[property]==output[property] then return end
        record[property]=object[property]; apply(object)
      end)
    end
    if next(record) then connect(object,object.AncestryChanged,function() apply(object) end) end
    connect(object,object.Destroying,function() forget(object) end)
  end
  if groupAlpha~=nil then
    N.groups[object]=groupAlpha
    object:SetAttribute("GiorgioFadeGroup",true)
    object:SetAttribute("GiorgioOpacity",groupAlpha)
    if not N.groupWatch[object] then
      N.groupWatch[object]=connect(object,object.DescendantAdded,function(descendant)
        N.register(descendant)
      end)
    end
    -- Declarative children are parented before their containing group is
    -- registered. They need the initial group opacity immediately too.
    for _,descendant in ipairs(object:GetDescendants()) do N.register(descendant) end
  end
  apply(object)
end
function N.get(object,property)
  if property=="GroupTransparency" and N.groups[object]~=nil then return N.groups[object] end
  local record=N.records[object]
  if record and record[property]~=nil then return record[property] end
  return object[property]
end
function N.set(object,property,value)
  if property=="GroupTransparency" and N.groups[object]~=nil then
    N.groups[object]=value; object:SetAttribute("GiorgioOpacity",value)
    apply(object)
    for _,descendant in ipairs(object:GetDescendants()) do apply(descendant) end
  else
    local record=N.records[object]
    if record and record[property]~=nil then record[property]=value; apply(object)
    else object[property]=value end
  end
end
