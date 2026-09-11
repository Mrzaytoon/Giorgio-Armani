"""Reproduce the dedicated build from the user-supplied Lumen snapshot."""
from pathlib import Path
import hashlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
giorgio = '--giorgio' in sys.argv
base = (ROOT / "Lumen.base.lua").read_text(encoding="utf-8-sig")
source = base

def replace_once(old, new):
    global source
    assert source.count(old) == 1, f"Expected one patch site: {old[:100]!r}"
    source = source.replace(old, new, 1)

# Keep the supplied UI, player panel, physics transaction and libraries intact.
# The dedicated build has its own preferences and starts only our page builder.
replace_once('Cfg.DIR       = "Lumen"', 'Cfg.DIR       = "LumenRepRoot"')
replace_once('Cfg.PATH      = "Lumen/config.json"', 'Cfg.PATH      = "LumenRepRoot/config.json"')
replace_once('Cfg.PLACE_DIR = "Lumen/places"', 'Cfg.PLACE_DIR = "LumenRepRoot/places"')
replace_once('Cfg.SCHEMA = {', '''Cfg.SCHEMA = {
  autoSave = { t = "boolean", scope = "global", def = true },
  targetPanelPosition = { t = "table", scope = "global", fields = { x = "number", y = "number" } },''')
replace_once('  return (a and b) and true or false\nend', '''  local ok = (a and b) and true or false
  Cfg.saveError = not ok
  if ok then Cfg._dirty=false; Cfg.lastSaved=os.clock() end
  return ok
end

function Cfg.setAutoSave(on)
  if Cfg.data.autoSave == (on == true) then return true end
  Cfg.set("autoSave", on == true)
  -- Persist the preference once. Further edits remain in memory when off.
  return Cfg.flush()
end''')
replace_once('  if Cfg._pending then return end', '  if Cfg.data.autoSave == false or Cfg._pending then return end')
replace_once('    if L.live() and Cfg._dirty then\n      Cfg._dirty = false\n      Cfg.flush()',
             '    if L.live() and Cfg._dirty and Cfg.data.autoSave ~= false then\n      Cfg.flush()')
replace_once('local function bindPersist(opts)\n', 'local function bindPersist(opts)\n  if opts.persist == false then return end\n')
replace_once('if not getgenv().__LUMEN_NOBOOT then', 'if false then -- dedicated Rep Root entry point appended below')
start = source.index('  local function repWork(part)')
end = source.index('  local function repNanWork(part)', start)
source = source[:start] + (ROOT / "rep-worker.lua").read_text(encoding="utf-8") + source[end:]
replace_once('local FALLBACK_ORDER = { "Rep-root", "Rep-root burst", "Teleport (clean)",\n                         "Void drop", "Overflow", "Rep-root NaN" }',
             'local FALLBACK_ORDER = { "Rep-root", "Rep-root burst" }')
replace_once('K.FLING_ATTACH = { LATCH, REP, REPBURST, REPNAN, MASSLESS, TELE, CONSTR, VOID, INFV }',
             'K.FLING_ATTACH = { REP, REPBURST }')
# No hidden fallback can ever enter a contact/weld/constraint path in this build.
replace_once('  local mode = K.cfg.flingAttach\n', '  local mode = K.cfg.flingAttach\n  if mode ~= REP and mode ~= REPBURST then return false, "Rep Root techniques only" end\n')
# Preserve the original binding, including nil, rather than replacing nil with self.
replace_once('repBind(root, snap.repRoot or root)', 'repBind(root, snap.repRoot)')
replace_once('    pcall(function() workspace.FallenPartsDestroyHeight = snap.fpdh end)',
             '    pcall(function()\n      if L.RepRoot and L.RepRoot.restoreVoidSetting then L.RepRoot.restoreVoidSetting()\n      else workspace.FallenPartsDestroyHeight = snap.fpdh end\n    end)')
replace_once('  local function aimAt(part) return lead.point(part) or part.Position end',
             '  local function aimAt(part) return part.Position end -- no prediction')
# The supplied aim blends camera-flat with up and clamps lift to [0,1], so it can
# never point down. Give the Rep Root pages a say before that blend runs; they
# return nil unless a survey found somewhere for the target to fall.
replace_once("""  local function repAimVector()
    local cam = workspace.CurrentCamera""",
             """  local function repAimVector()
    local studio = L.RepRoot
    if studio and studio.aimOverride then
      local override = studio.aimOverride()
      if override then return override end
    end
    local cam = workspace.CurrentCamera""")
replace_once('    K.runHome = r0 and r0.CFrame or nil',
             '    K.runHome = (L.RepRoot and L.RepRoot.queue and L.RepRoot.queue.home) or (r0 and r0.CFrame or nil)')
# Internal lifecycle events finish one attempt; every public Stop ends the queue.
replace_once('L.cleanup(function()\n  -- Inert hooks and visual/body mutations first;',
             'K.stopAttempt = K.stopFling\n\nL.cleanup(function()\n  -- Inert hooks and visual/body mutations first;')
runner_start = source.index('function K.startFling(name)')
runner_end = source.index('-- ---------------------------------------------------------------- ui', runner_start)
runner = source[runner_start:runner_end]
assert runner.count('K.stopFling(') == 7
source = source[:runner_start] + runner.replace('K.stopFling(', 'K.stopAttempt(') + source[runner_end:]
replace_once('    if attemptCamera and workspace.CurrentCamera == attemptCamera then\n      cameraOverride = thead or handle or thum',
             '    if attemptCamera and workspace.CurrentCamera == attemptCamera and not (L.RepRoot and L.RepRoot.cameraOwned) then\n      cameraOverride = thead or handle or thum')
# Original preflight remains; offset workshop leaves the upright controller on.
replace_once('    hum.PlatformStand = true\n\n    local runners = {',
             '    hum.PlatformStand = not (L.RepRoot and not L.RepRoot.fling)\n\n    local runners = {')
# Avoid introducing collision during the attachment-only approach.
replace_once('      forceCollide()\n      local wanted = aimAt(part) + Vector3.new(0, 0, 3)',
             '      if not L.RepRoot or L.RepRoot.fling then forceCollide() end\n      local wanted = aimAt(part) + Vector3.new(0, 0, 3)')

# Reuse the full supplied Interface page, not a look-alike implementation.
ui_start = base.index('  -- ---- INTERFACE -----------------------------------------------------')
ui_end = base.index('  local activity = win:tab(', ui_start)
interface = base[ui_start:ui_end]
interface = re.sub(r'\bp\b', 'interfacePage', interface)
addon = (ROOT / "rep-root-addon.lua").read_text(encoding="utf-8").replace('-- INTERFACE_FROM_LUMEN', interface)
addon = addon.replace('-- SESSION_ENGINE', (ROOT / "rep-session.lua").read_text(encoding="utf-8"))
addon = addon.replace('-- PLAYER_PANEL', (ROOT.parent / 'giorgio/player-panel.lua' if giorgio else ROOT / "rep-panel.lua").read_text(encoding="utf-8"))
if giorgio:
    sys.path.insert(0,str(ROOT.parent/'giorgio'))
    from integrate import integrate
    source,addon=integrate(source,addon,ROOT.parent/'giorgio')
source += '\ndo -- Rep Root dedicated pages\n' + addon + '\nend\n'
output = ROOT.parent / ("Giorgio.lua" if giorgio else "LumenRepRoot.lua")
staged = ROOT / (".Giorgio.staged.lua" if giorgio else ".LumenRepRoot.staged.lua")
staged.write_text(source, encoding="utf-8")
tools = Path.home() / "AppData/Local/Potassium/tools"
subprocess.run(["node", str(tools / "check.js"), str(staged)], check=True)
staged.replace(output)
print(f"Built {output} ({len(source):,} characters)")
print("Source snapshot SHA256:", hashlib.sha256((ROOT / "Lumen.base.lua").read_bytes()).hexdigest())
