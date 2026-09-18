"""Integrate Giorgio presentation without changing the Rep Root transaction."""
import json
import re


def lua(value):
    if isinstance(value, dict):
        return '{'+','.join('['+json.dumps(k,ensure_ascii=False)+']='+lua(v) for k,v in value.items())+'}'
    if isinstance(value, list):
        return '{'+','.join(lua(v) for v in value)+'}'
    if value is None: return 'nil'
    if value is True: return 'true'
    if value is False: return 'false'
    return json.dumps(value,ensure_ascii=False)


def integrate(source, addon, root):
    def replace(old,new):
        nonlocal source
        assert source.count(old)==1, f'Expected one Giorgio patch site: {old[:100]}'
        source=source.replace(old,new,1)

    source=source.replace('"LumenRepRoot"','"Giorgio"').replace('"LumenRepRoot/','"Giorgio/')
    replace('function L.mk(class, props)\n  local inst = Instance.new(class)', '''function L.uiRead(object,property)
  local native=L.Giorgio and L.Giorgio.Native
  if native then return native.get(object,property) end
  return object[property]
end
function L.uiWrite(object,property,value)
  local native=L.Giorgio and L.Giorgio.Native
  if native then native.set(object,property,value) else object[property]=value end
end
function L.mk(class, props)
  local native=L.Giorgio and L.Giorgio.Native
  local nativeGroup=native and class=="CanvasGroup"
  local inst = Instance.new(nativeGroup and "Frame" or class)''')
    replace('      elseif k == "Parent" then\n        parent = v', '      elseif k == "Parent" then\n        parent = v\n      elseif nativeGroup and k=="GroupTransparency" then -- handled as logical opacity')
    replace('  if parent then inst.Parent = parent end\n  return inst', '  if parent then inst.Parent = parent end\n  if native then native.register(inst,nativeGroup and (props and props.GroupTransparency or 0) or nil) end\n  return inst')
    replace('  self.obj[self.prop] = value','  L.uiWrite(self.obj,self.prop,value)')
    replace('  local current = obj[prop]','  local current = L.uiRead(obj,prop)')
    replace('{ b, "GroupTransparency", b.GroupTransparency }','{ b, "GroupTransparency", L.uiRead(b,"GroupTransparency") }')
    replace('if e[1].Parent then e[1][e[2]] = 1 + (e[3] - 1) * a end','if e[1].Parent then L.uiWrite(e[1],e[2],1 + (e[3] - 1) * a) end')
    replace('local W, GAP, MARGIN = 300, 8, 18','local W, GAP, MARGIN = 364, 10, 20')
    replace('  local height = hasBody and 70 or 48','  local height = hasBody and 108 or 76')
    replace('Name = "LumenToasts", ResetOnSpawn = false','Name = "GiorgioNotices", ResetOnSpawn = false')
    replace('  local entryHovered = false\n  local entry = {','''  if L.Giorgio and L.Giorgio.styleToast then
    L.Giorgio.styleToast({card=card,wrap=wrap,title=titleLbl,count=countLbl,
      well=well,glyph=glyph,edge=edge,bloom=bloom,timer=timer,track=timerTrack},opts)
  end
  local entryHovered = false
  local entry = {''')
    replace('  local from = obj[prop]','  local from = L.uiRead(obj,prop)')
    replace('        obj[prop] = from + (target - from) * e','        L.uiWrite(obj,prop,from + (target - from) * e)')
    replace('if n:IsA("CanvasGroup") and n.GroupTransparency > 0.5 then return false end', 'if (n:IsA("CanvasGroup") or n:GetAttribute("GiorgioFadeGroup")) and L.uiRead(n,"GroupTransparency") > 0.5 then return false end')
    # Native logical groups already compose opacity onto their own strokes.
    # Keep the original helper's explicit stroke fade for real CanvasGroups.
    replace('  M.to(group, "GroupTransparency", alpha, token)\n  for _, d in ipairs(group:GetChildren()) do',
            '  M.to(group, "GroupTransparency", alpha, token)\n  if group:GetAttribute("GiorgioFadeGroup") then return end\n  for _, d in ipairs(group:GetChildren()) do')
    replace('  M.set(group, "GroupTransparency", alpha)\n  for _, d in ipairs(group:GetChildren()) do',
            '  M.set(group, "GroupTransparency", alpha)\n  if group:GetAttribute("GiorgioFadeGroup") then return end\n  for _, d in ipairs(group:GetChildren()) do')
    replace('Cfg.load()\n\nend\ndo -- ==== lm_34_defaults.lua', '''-- Carry the previous local setup forward once; retain the original file.
pcall(function()
  if not isfile(Cfg.PATH) and isfile("LumenRepRoot/config.json") then
    if not isfolder(Cfg.DIR) then makefolder(Cfg.DIR) end
    writefile(Cfg.PATH,readfile("LumenRepRoot/config.json"))
  end
end)
Cfg.load()

end
do -- ==== lm_34_defaults.lua''')
    defaults=json.loads((root/'defaults.json').read_text(encoding='utf-8'))
    seed='''-- GIORGIO_FACTORY_DEFAULTS
pcall(function()
  if not isfile(Cfg.PATH) then
    if not isfolder(Cfg.DIR) then makefolder(Cfg.DIR) end
    writefile(Cfg.PATH,FACTORY_JSON)
  end
end)
'''.replace('FACTORY_JSON',lua(json.dumps(defaults,ensure_ascii=False,separators=(',',':'))))
    replace('Cfg.load()\n\nend\ndo -- ==== lm_34_defaults.lua',seed+'Cfg.load()\n\nend\ndo -- ==== lm_34_defaults.lua')
    replace('    local gw, gh = vp.X, vp.Y','    local gw, gh = 0, 0 -- supplied pinstripe footage replaces the lattice')
    replace('  A.hairline(root, Color3.new(1, 1, 1), 0, 0.5)\n  A.hairline(root, T.c.accent, 1, 0.25)',
            '  -- Native rounded pinstripe edges carry the window boundary.')
    replace('    if opts.onClick then L.try("atoms.click", opts.onClick) end',
            '    if opts.onClick then if L.Giorgio then L.Giorgio.sound("click",.35) end; L.try("atoms.click", opts.onClick) end')
    data=json.loads((root/'assets/manifest.json').read_text(encoding='utf-8'))
    fields=('title','file','folder','prefix','ext','first','digits','count','fps','width','height','duration','audio','cols','rows','tileWidth','tileHeight')
    def compact(spec): return {k:v for k,v in spec.items() if k in fields}
    data={'logo':compact(data['logo']),'symbol':compact(data['symbol']),'loaderFilm':compact(data['loaderFilm']),'icons':{k:compact(v) for k,v in data['icons'].items()},
          'background':compact(data['background']),'edits':[compact(v) for v in data['edits']], 'sounds':data['sounds']}
    runtime=(root/'runtime-media.lua').read_text(encoding='utf-8').replace('-- ASSET_MANIFEST',lua(data))
    source+='\ndo -- Giorgio runtime\n'+runtime+'\nend\n'
    for name in ('native-text.lua','ui-skin.lua','loader.lua'):
        source+='\ndo -- Giorgio '+name+'\n'+(root/name).read_text(encoding='utf-8')+'\nend\n'
    addon=addon.replace('Lumen maximum','Giorgio maximum').replace('Lumen original','Giorgio classic')
    addon=addon.replace('Lumen','Giorgio').replace('"LUMEN"','"GIORGIO"')
    start=addon.index('    -- MADE IN HEAVEN MODE.')
    end=addon.index('    C.segmented(interfacePage, {\n      text = "Density"',start)
    addon=addon[:start]+addon[end:]
    addon=addon.replace('local savedVariant=L.Cfg.feat("reproot.variant","Giorgio maximum")',
                        'local savedVariant=L.Cfg.feat("reproot.variant","Giorgio maximum")\nif savedVariant=="Lumen maximum" then savedVariant="Giorgio maximum" elseif savedVariant=="Lumen original" then savedVariant="Giorgio classic" end')
    extra='''  local giorgioSettingsPage
  for _,tab in ipairs(win.tabs) do if tab.name=="Interface" then giorgioSettingsPage=tab.body; break end end
  assert(giorgioSettingsPage,"Giorgio Interface page missing")
  C.section(interfacePage,"Giorgio audiovisual")
  C.toggle(interfacePage,{id="giorgio.sfx",text="Interface sound",default=true,callback=function() end})
  C.slider(interfacePage,{id="giorgio.sfxVolume",text="Interface volume",min=0,max=1,step=.01,default=.35,callback=function() end})
  C.slider(interfacePage,{id="giorgio.editVolume",text="Film volume",min=0,max=2,step=.01,default=.65,callback=function(value)
    local window=L.Giorgio.editWindow; if window then window:setVolume(value,false) end
  end})
  C.toggle(interfacePage,{id="giorgio.showLoader",text="Show loading sequence",default=true,callback=function() end})
  C.toggle(interfacePage,{id="giorgio.introFilm",text="Film in the introduction",default=true,callback=function() end})
  C.slider(interfacePage,{id="giorgio.introVolume",text="Introduction film volume",min=0,max=2,step=.01,default=.65,callback=function() end})
  C.toggle(interfacePage,{id="giorgio.fullIntroFilm",text="Play the complete intro film",default=false,callback=function() end})
  C.actions(interfacePage,{{text="Replay introduction",callback=function() L.Giorgio.load(function() end,true) end},
    {text="Giorgio Armani?",callback=L.Giorgio.openEdit}})
  C.paragraph(interfacePage,"Audio Logo (artxmpl-al-01) by Artxmpl (patreon.com/artxmpl), CC BY 4.0. Interface sounds: Kenney, CC0. Animated icons: line-md by Vjacheslav Trushkin, MIT. Giorgio Armani artwork belongs to its respective owner.")
'''.replace('interfacePage','giorgioSettingsPage')
    assert addon.count('  local activity=win:tab(')==1
    addon=addon.replace('  local activity=win:tab(',extra+'  local activity=win:tab(',1)
    addon=addon.replace('initialWindow:show()','L.Giorgio.load(function() initialWindow:show() end)')
    return source,addon
