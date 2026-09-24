"""Compile the build and run the shipped stand module in a Luau fixture."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
runtime = Path.home() / "AppData/Local/Temp/luaudl"
subprocess.run([str(runtime / "luau-compile.exe"), "--null", str(root / "Giorgio.lua")], check=True)
module = (root / "giorgio/tsb-stand.lua").read_text(encoding="utf-8")
assert module in (root / "Giorgio.lua").read_text(encoding="utf-8"), "rebuild Giorgio.lua before testing"
fixture = (root / "giorgio/tsb-stand.spec.luau").read_text(encoding="utf-8")
assert fixture.count("-- MODULE") == 1
with tempfile.TemporaryDirectory(prefix="giorgio-stand-") as folder:
    target = Path(folder) / "suite.luau"
    target.write_text(fixture.replace("-- MODULE", module), encoding="utf-8")
    subprocess.run([str(runtime / "luau.exe"), str(target)], check=True)
