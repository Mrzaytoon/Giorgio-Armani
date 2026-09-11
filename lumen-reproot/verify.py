"""Run Lumen's supplied regression suites against modules in this built fork."""
from pathlib import Path
import argparse
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", nargs="?", type=Path, default=root.parent / "LumenRepRoot.lua",
                    help="Assembled script to verify (default: LumenRepRoot.lua)")
source_path = parser.parse_args().source.resolve()
upstream = Path.home() / "AppData/Local/Potassium/workspace/lumen"
runtime = Path.home() / "AppData/Local/Temp/luaudl/luau.exe"
source = source_path.read_text(encoding="utf-8")
config_path = re.search(r'Cfg\.PATH\s*=\s*"([^"]+)"', source).group(1)
place_path = re.search(r'Cfg\.PLACE_DIR\s*=\s*"([^"]+)"', source).group(1)
print(f"Verifying assembled script: {source_path}", flush=True)
markers = list(re.finditer(r'^do -- ==== (lm_\d+_\w+\.lua) ====\n', source, re.M))
assert markers, "No original module boundaries found in the assembled script"
last_module_end = min(source.index(boundary) for boundary in
                      ('\ndo -- Giorgio runtime', '\ndo -- Rep Root dedicated pages') if boundary in source)
with tempfile.TemporaryDirectory(prefix="lumen-reproot-tests-") as folder:
    testdir = Path(folder)
    for index, marker in enumerate(markers):
        end = markers[index + 1].start() if index + 1 < len(markers) else last_module_end
        body = source[marker.end():end].rstrip()
        assert body.endswith('end')
        (testdir / marker.group(1)).write_text(body[:-3].rstrip() + '\n', encoding="utf-8")
    for name in ('verify_logic.py', 'verify_spring.py', 'verify_combat.py', 'verify_assets.py'):
        test = (upstream / name).read_text(encoding="utf-8-sig")
        test = test.replace(r'C:\Users\61415\AppData\Local\Potassium\tools\luau.exe', str(runtime))
        if name == 'verify_logic.py':
            test = test.replace('Lumen/config.json', config_path).replace('Lumen/places', place_path)
        if name == 'verify_combat.py':
            # Adapt only contracts intentionally changed by this fork: exact nil
            # restoration, a burst delegating to the shared worker, and Rep-only fallback.
            test = test.replace('repBind(root, snap.repRoot or root)', 'repBind(root, snap.repRoot)')
            test = test.replace('COMBAT.count("repBind(root, root)") >= 3', 'COMBAT.count("repBind(root, root)") >= 2 and "repWork(part, true)" in COMBAT')
            test = test.replace("COMBAT.index('\"Rep-root NaN\" }') > COMBAT.index('FALLBACK_ORDER = { \"Rep-root\"')", "'local FALLBACK_ORDER = { \"Rep-root\", \"Rep-root burst\" }' in COMBAT")
            if 'do -- Giorgio native-text.lua' in source:
                # The same tooltip threshold now reads logical opacity from a
                # native Frame; verify_native.py executes both reachability paths.
                test = test.replace('"GroupTransparency > 0.5" in ATOMS',
                                    "'L.uiRead(n,\"GroupTransparency\") > 0.5' in ATOMS and 'n:GetAttribute(\"GiorgioFadeGroup\")' in ATOMS")
        if name == 'verify_assets.py':
            test = test.replace('PART = WS / "lumen" / "lm_26_assets.lua"', f'PART = pathlib.Path({str(testdir / "lm_26_assets.lua")!r})')
            test = test.replace('LUAU = WS.parent / "tools" / "luau.exe"', f'LUAU = pathlib.Path({str(runtime)!r})')
            test = test.replace('OUT = WS / "lumen" / "_verify_assets.luau"', f'OUT = pathlib.Path({str(testdir / "assets.luau")!r})')
        script = testdir / name
        script.write_text(test, encoding="utf-8")
        result = subprocess.run(['python', str(script)], text=True, capture_output=True, encoding='utf-8', errors='replace')
        report = result.stdout + result.stderr
        if result.returncode:
            print(name, 'FAILED\n', report)
            raise SystemExit(result.returncode)
        summaries = [line for line in report.splitlines() if any(word in line.lower() for word in ('passed', 'checked', 'all checks', 'all spring'))]
        print(name + ': ' + ('; '.join(summaries[-3:]) or 'PASS'))

# The upstream timers deliberately never fire. Keep the scheduler and live
# noclip intent checks as an additional gate against the assembled script.
subprocess.run([sys.executable, str(root / "verify_preferences.py"), str(source_path)], check=True)
if 'do -- Giorgio native-text.lua' in source:
    for verifier in (
        root.parent / "giorgio/verify_native.py",
        root.parent / "giorgio/verify_window.py",
        root.parent / "giorgio/verify_media.py",
        root.parent / "giorgio/verify_player_panel.py",
        root.parent / "giorgio/verify_camera.py",
        root / "verify_queue.py",
    ):
        subprocess.run([sys.executable, str(verifier), str(source_path)], check=True)
