"""Package the current Giorgio script with its verified portable local asset tree."""
from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "giorgio/assets"


def main():
    report = json.loads((ROOT / "giorgio/deployment.json").read_text())
    if report.get("result") != "pass":
        raise ValueError("Verify and deploy the assets before packaging")
    script = ROOT / "Giorgio.lua"
    if not script.is_file():
        raise ValueError("Build Giorgio.lua before packaging")
    destination = ROOT / "giorgio/dist/Giorgio.zip"
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = destination.with_suffix(".staged.zip")
    with zipfile.ZipFile(stage, "w", zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as bundle:
        bundle.write(script, "Giorgio.lua")
        bundle.write(ROOT / "giorgio/INSTALL.txt", "README.txt")
        for record in report["files"]:
            relative = Path(record["path"])
            source = (ASSETS / relative).resolve()
            if ASSETS.resolve() not in source.parents:
                raise ValueError(f"Unsafe asset path: {relative}")
            if hashlib.sha256(source.read_bytes()).hexdigest() != record["sha256"]:
                raise ValueError(f"Asset changed after deployment: {relative}")
            bundle.write(source, f"Giorgio/assets/{relative.as_posix()}")
    with zipfile.ZipFile(stage) as bundle:
        damaged = bundle.testzip()
        if damaged:
            raise ValueError(f"Bundle readback failed: {damaged}")
        count = len(bundle.infolist())
    stage.replace(destination)
    metadata = {"result": "pass", "path": str(destination), "entries": count,
                "bytes": destination.stat().st_size,
                "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
                "all_zip_entries_readback_verified": True}
    destination.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata))


if __name__ == "__main__":
    main()
