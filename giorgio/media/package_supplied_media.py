"""Replace the loader film and append the fourth supplied Armani edit.

Both films are packaged at 60 fps. The loader source is a portrait phone upload:
its 16:9 picture sits between two 416px black bars, and it runs at a true 60 fps
until a 30 fps tail. Cropping the bars keeps every real pixel and stops the
loader's 640x360 stage from spending most of itself on dead area; the constant
60/1 grid repeats the frames that tail already holds, so picture and audio stay
on one timeline instead of drifting apart over a minute.
"""
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps
from package_assets import ASSETS, ROOT, DEFAULT_TOOLS, video, metadata, write_json

JOBS = {
    "loader-film": {"source": Path.home() / "Downloads/ssstik.io_1788956993576.mp4",
                    "dimensions": None, "crop": (1080, 608, 0, 416), "rate": 60},
    # A 4K master: Lanczos to the library's 1920x1080 plate, its own 60/1 timing kept.
    "edit-four": {"source": Path.home() / "Downloads/ssstik.io_1788957591207.mp4",
                  "dimensions": (1920, 1080), "crop": None, "rate": None},
}


def main():
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = {name: pool.submit(video, name, job["source"], job["dimensions"],
                                  DEFAULT_TOOLS / "ffmpeg.exe", DEFAULT_TOOLS / "ffprobe.exe",
                                  job["crop"], job["rate"]) for name, job in JOBS.items()}
        records = {name: job.result() for name, job in jobs.items()}
    manifest = json.loads((ASSETS / "manifest.json").read_text())
    manifest["edits"] = [x for x in manifest["edits"] if x["id"] != "edit-four"] + [records["edit-four"]]
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
    print(json.dumps({name: {k: x[k] for k in ["count", "source_frame_count", "fps_ratio", "duration", "width", "height"]}
                      for name, x in records.items()}))


if __name__ == "__main__":
    main()
