"""Copy the verified local Giorgio runtime assets; keep unrelated files intact."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ASSETS = Path(__file__).resolve().parents[1] / "assets"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination == ASSETS.resolve() or ASSETS.resolve() in destination.parents:
        raise ValueError("Deployment destination must be outside the source assets folder")
    manifest = json.loads((ASSETS / "manifest.json").read_text())
    verified = json.loads((ASSETS / "verification.json").read_text())
    if verified.get("result") != "pass":
        raise ValueError("Run verify_assets.py before deployment")
    # Research downloads are rebuild inputs. These folders contain runtime assets
    # plus their full attribution, frame indexes and quality evidence.
    sources = []
    for folder in ["brand", "icons", "media", "sounds", "licenses", "probes"]:
        sources.extend(path for path in (ASSETS / folder).rglob("*") if path.is_file()
                       and not (folder == "sounds" and path.suffix.lower() == ".mp3"))
    sources.extend(ASSETS / name for name in ["manifest.json", "verification.json", "README.md", "CREDITS.md", "preview.jpg"])
    files = []
    total_bytes = 0
    for source in sorted(sources):
        relative = source.relative_to(ASSETS)
        target = (destination / relative).resolve()
        if destination not in target.parents:
            raise ValueError(f"Asset escapes destination: {relative}")
        target.parent.mkdir(parents=True, exist_ok=True)
        source_hash = digest(source)
        if not target.exists() or digest(target) != source_hash:
            shutil.copy2(source, target)
        if digest(target) != source_hash:
            raise ValueError(f"Copy verification failed: {relative}")
        size = source.stat().st_size
        total_bytes += size
        files.append({"path": relative.as_posix(), "bytes": size, "sha256": source_hash})
    report = {
        "result": "pass", "verified_utc": datetime.now(timezone.utc).isoformat(),
        "destination": str(destination), "source_verification_utc": verified["verified_utc"],
        "file_count": len(files), "total_bytes": total_bytes,
        "all_destination_hashes_match_source": True, "unrelated_files_removed": False,
        "media_quality": manifest["asset_quality"], "files": files,
    }
    report_path = ASSETS.parent / "deployment.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ["result", "destination", "file_count", "total_bytes"]}))


if __name__ == "__main__":
    main()
