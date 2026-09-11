"""Preserve and append the two newly supplied full-resolution films."""
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps
from package_assets import ASSETS, ROOT, DEFAULT_TOOLS, video, metadata, write_json


def main():
    sources = {
        "edit-three": Path.home() / "Downloads/snaptik_7673144844079861025_hd.mp4",
        "loader-film": Path.home() / "Downloads/ssstik.io_1788860654210.mp4",
    }
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = {name: pool.submit(video, name, source, None, DEFAULT_TOOLS / "ffmpeg.exe", DEFAULT_TOOLS / "ffprobe.exe") for name, source in sources.items()}
        records = {name: job.result() for name, job in jobs.items()}
    manifest = json.loads((ASSETS / "manifest.json").read_text())
    manifest["edits"] = [x for x in manifest["edits"] if x["id"] != "edit-three"] + [records["edit-three"]]
    manifest["loaderFilm"] = records["loader-film"]
    manifest["loaderFilm"]["usage"] = "Loader only; excluded from alternating film list."
    metadata(manifest, DEFAULT_TOOLS / "ffmpeg.exe")
    write_json(ASSETS / "manifest.json", manifest)
    for name, record in records.items():
        sheet = Image.new("RGB", (1280, 780), "#0b0b0b")
        draw = ImageDraw.Draw(sheet)
        for i in range(12):
            index = round((record["count"] - 1) * i / 11)
            source = ASSETS / record["folder"] / f"frame-{index:05d}.jpg"
            with Image.open(source) as image:
                thumb = ImageOps.contain(image, (306, 172), Image.Resampling.LANCZOS)
                x, y = 10 + (i % 4) * 320, 10 + (i // 4) * 254
                sheet.paste(thumb, (x, y))
                draw.text((x, y + 184), f"{name} / {index / record['fps']:.2f}s", fill="white")
        sheet.save(ROOT / "media-reference" / f"{name}-contact-sheet.jpg", quality=92)
    print(json.dumps({name: {k: x[k] for k in ["count", "fps", "duration", "width", "height"]} for name, x in records.items()}))


if __name__ == "__main__":
    main()
