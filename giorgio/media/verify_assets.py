"""Verify actual packaged files and write a local visual contact sheet."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageOps

from package_assets import ASSETS, RESEARCH, DEFAULT_TOOLS, digest, probe, write_json


def main():
    manifest = json.loads((ASSETS / "manifest.json").read_text())
    report = {"verified_utc": datetime.now(timezone.utc).isoformat(), "checks": [], "scope": "Local packaged files; live Roblox rendering is not claimed."}
    for name, record in manifest["icons"].items():
        pages = [Image.open(ASSETS / page["path"]).convert("RGBA") for page in record["pages"]]
        source_frames = sorted((RESEARCH / "line-md-png" / name).glob("*.png"))
        assert len(source_frames) == record["count"]
        for index, source in enumerate(source_frames):
            page = pages[index // record["frames_per_page"]]
            offset = index % record["frames_per_page"]
            x = (offset % record["cols"]) * record["tileWidth"]
            y = (offset // record["cols"]) * record["tileHeight"]
            cell = page.crop((x, y, x + record["tileWidth"], y + record["tileHeight"]))
            with Image.open(source) as image:
                difference = ImageChops.difference(cell, image.convert("RGBA"))
                assert not any(channel.getbbox() for channel in difference.split()), (name, index)
        for page, metadata in zip(pages, record["pages"]):
            assert max(page.size) <= 1024
            assert digest(ASSETS / metadata["path"]) == metadata["sha256"]
        report["checks"].append({"asset": name, "frames": len(source_frames), "atlas_frames_identical_to_sources": True, "max_edge": 1024})
    media_records = [manifest["background"]] + manifest["edits"] + ([manifest["loaderFilm"]] if manifest.get("loaderFilm") else [])
    for record in media_records:
        folder = ASSETS / record["folder"]
        files = sorted(folder.glob("frame-*.jpg"))
        indexes = json.loads((ASSETS / record["frame_index"]).read_text())
        assert len(files) == record["count"] == len(indexes)
        for index, (path, expected) in enumerate(zip(files, indexes)):
            assert path.name == f"frame-{index:05d}.jpg"
            assert digest(path) == expected["sha256"] and path.stat().st_size == expected["bytes"]
            with Image.open(path) as image:
                image.load()
                assert image.size == (record["width"], record["height"])
        assert digest(Path(record["source_path"])) == record["source_sha256"]
        item = {"asset": record["id"], "frames": len(files), "all_frames_decoded": True,
                "all_frame_hashes_match": True, "original_source_hash_matches": True,
                "fps": record["fps"], "size": [record["width"], record["height"]],
                "first_frame": files[0].name, "last_frame": files[-1].name}
        if record["audio"]:
            info = probe(ASSETS / record["audio"], DEFAULT_TOOLS / "ffprobe.exe")
            audio = next(x for x in info["streams"] if x["codec_type"] == "audio")
            assert audio["channels"] == 2
            assert abs(float(info["format"]["duration"]) - record["audio_details"]["duration"]) < 0.001
            assert abs(float(info["format"]["duration"]) - record["source_duration"]) < 0.1
            item["audio"] = {"channels": 2, "duration": float(info["format"]["duration"]), "full_duration_within_100ms_of_source": True}
        report["checks"].append(item)
    for name, record in manifest["sound_details"].items():
        assert digest(ASSETS / record["path"]) == record["sha256"]
        assert probe(ASSETS / record["path"], DEFAULT_TOOLS / "ffprobe.exe")["streams"]
    with Image.open(ASSETS / manifest["logo"]["file"]) as logo:
        logo.load()
        alpha = logo.getchannel("A")
        assert alpha.getextrema() == (0, 255)
    if manifest.get("symbol"):
        symbol = manifest["symbol"]
        assert digest(ASSETS / symbol["file"]) == symbol["sha256"]
        with Image.open(ASSETS / symbol["file"]) as image:
            image.load()
            assert image.size == (symbol["width"], symbol["height"])
            assert image.getchannel("A").getextrema() == (0, 255)
        report["checks"].append({"asset": "official_striped_eagle", "transparent_symbol_decoded": True, "hash_matches": True})
    report["checks"].append({"asset": "logo_and_sounds", "transparent_logo_decoded": True, "sounds_probed_and_hashes_match": True})
    preview = Image.new("RGB", (1280, 180 + 257 * len(media_records)), "#0e1118")
    draw = ImageDraw.Draw(preview)
    with Image.open(ASSETS / manifest["logo"]["file"]) as logo:
        logo.thumbnail((820, 110), Image.Resampling.LANCZOS)
        preview.paste(logo, ((preview.width - logo.width) // 2, 28), logo)
    edit_sizes = ", ".join(sorted({f"{record['width']} x {record['height']}" for record in manifest["edits"]}))
    draw.text((30, 130), f"Packaged media / original timing retained / deployed edits: {edit_sizes}", fill="#bfc8d9")
    for row, record in enumerate(media_records):
        for column, index in enumerate([0, record["count"] // 2, record["count"] - 1]):
            path = ASSETS / record["folder"] / f"frame-{index:05d}.jpg"
            with Image.open(path) as image:
                thumb = ImageOps.contain(image, (392, 220), Image.Resampling.LANCZOS)
                x = 30 + column * 415
                y = 172 + row * 257
                preview.paste(thumb, (x + (392 - thumb.width) // 2, y))
                draw.text((x, y + 225), f"{record['id']} / frame {index} / {record['fps']:g} fps", fill="#bfc8d9")
    preview.save(ASSETS / "preview.jpg", quality=94)
    report["result"] = "pass"
    write_json(ASSETS / "verification.json", report)
    print(json.dumps({"result": "pass", "icon_frames": sum(x["count"] for x in manifest["icons"].values()),
        "video_frames": sum(x["count"] for x in media_records), "report": str(ASSETS / "verification.json")}))


if __name__ == "__main__":
    main()
