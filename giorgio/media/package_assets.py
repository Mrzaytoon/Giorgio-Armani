"""Build local Giorgio assets without changing timing or writing to remote hosts.

Run with Python + Pillow; FFmpeg/FFprobe and Node + sharp are located automatically
from this workstation's bundled runtimes, or supplied using the CLI switches.
All deployment paths in assets/manifest.json are relative to Giorgio/assets/.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
from fractions import Fraction
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
RESEARCH = ASSETS / "research"
DEFAULT_TOOLS = Path.home() / "AppData/Local/Potassium/tools"
RUNTIME = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies"


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def relative(path):
    return path.relative_to(ASSETS).as_posix()


def file_record(path):
    return {"path": relative(path), "bytes": path.stat().st_size, "sha256": digest(path)}


def probe(path, ffprobe, count_frames=False):
    command = [str(ffprobe), "-v", "error"]
    if count_frames:
        command.append("-count_frames")
    command += ["-show_streams", "-show_format", "-of", "json", str(path)]
    return json.loads(subprocess.check_output(command, text=True))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def icons():
    inventory = json.loads((RESEARCH / "line-md-manifest.json").read_text())
    target = ASSETS / "icons"
    target.mkdir(parents=True, exist_ok=True)
    output = {}
    for icon in inventory["icons"]:
        source = RESEARCH / "line-md-png" / icon["name"]
        frames = sorted(source.glob("*.png"))
        if len(frames) != icon["frames"]:
            raise ValueError(f"{icon['name']}: incorrect source frame count")
        width, height = Image.open(frames[0]).size
        columns = 1024 // width
        rows = 1024 // height
        capacity = columns * rows
        pages = []
        for page_index in range(math.ceil(len(frames) / capacity)):
            first = page_index * capacity
            count = min(capacity, len(frames) - first)
            page_rows = math.ceil(count / columns)
            page = Image.new("RGBA", (columns * width, page_rows * height))
            for index, frame_path in enumerate(frames[first:first + count]):
                with Image.open(frame_path) as frame:
                    if frame.size != (width, height):
                        raise ValueError(f"Mismatched dimensions: {frame_path}")
                    page.paste(frame.convert("RGBA"), ((index % columns) * width, (index // columns) * height))
            path = target / f"{icon['name']}-{page_index + 1:02d}.png"
            page.save(path, optimize=True)
            pages.append({**file_record(path), "first_frame": first, "frame_count": count,
                          "width": page.width, "height": page.height})
        output[icon["name"]] = {
            "type": "atlas", "usage": icon["usage"], "fps": 120, "fps_ratio": "120/1",
            "frames": len(frames), "duration": len(frames) / 120,
            "folder": "icons", "prefix": icon["name"] + "-", "ext": "png", "first": 1,
            "digits": 2, "count": len(frames), "tileWidth": width, "tileHeight": height,
            "cols": columns, "pageCount": len(pages),
            "width": width, "height": height, "columns": columns, "rows": rows,
            "frames_per_page": capacity, "loop": icon["name"].endswith("-loop"),
            "pages": pages, "source_url": icon["source_url"], "license": "MIT",
            "attribution": "Vjacheslav Trushkin (cyberalien), line-md",
        }
    print(f"Packed {sum(x['frames'] for x in output.values())} original 120 fps icon frames.", flush=True)
    return output


def logo(node, node_modules):
    target = ASSETS / "brand"
    target.mkdir(parents=True, exist_ok=True)
    svg = (RESEARCH / "giorgio-armani-official-wordmark.svg").read_text(encoding="utf-8")
    # Boolean data attributes come from HTML extraction, not valid XML.
    svg = svg.replace(" data-v-30605b69", "").replace("currentColor", "#ffffff")
    svg_path = target / "giorgio-armani-white.svg"
    svg_path.write_text(svg, encoding="utf-8")
    png = target / "giorgio-armani-white.png"
    script = "const sharp=require(process.argv[1]);sharp(process.argv[2],{density:672}).resize({width:2048}).png().toFile(process.argv[3]).catch(e=>{console.error(e);process.exit(1)});"
    run(node, "-e", script, node_modules / "sharp", svg_path, png)
    with Image.open(png) as image:
        if image.mode != "RGBA" or not image.getchannel("A").getbbox():
            raise ValueError("Logo is missing transparent alpha or content")
        size = image.size
    return {**file_record(png), "file": relative(png), "width": size[0], "height": size[1], "svg": relative(svg_path),
            "source_url": "https://www.armani.com/en-us/giorgio-armani/",
            "provenance": "Official Armani website wordmark SVG; rendered white on transparency.",
            "license": "Trademark / rights retained by Giorgio Armani; no open-content license asserted."}


def sounds(ffmpeg, ffprobe):
    target = ASSETS / "sounds"
    target.mkdir(parents=True, exist_ok=True)
    selected = {"hover": "select_001.ogg", "click": "click_001.ogg", "tab": "switch_002.ogg",
                "toggle_on": "toggle_001.ogg", "toggle_off": "toggle_004.ogg",
                "open": "open_001.ogg", "close": "close_001.ogg", "saved": "confirmation_001.ogg"}
    output = {}
    for role, name in selected.items():
        source = RESEARCH / "kenney-interface" / "Audio" / name
        path = target / f"{role}.ogg"
        shutil.copyfile(source, path)
        info = probe(path, ffprobe)
        output[role] = {**file_record(path), "duration": float(info["format"]["duration"]),
                        "channels": info["streams"][0]["channels"], "source_file": name,
                        "source_url": "https://kenney.nl/assets/interface-sounds", "license": "CC0-1.0",
                        "attribution": "Kenney, Interface Sounds (1.0)"}
    path = target / "loader.ogg"
    run(ffmpeg, "-hide_banner", "-loglevel", "error", "-i", RESEARCH / "artxmpl-al-01-hq-preview.mp3",
        "-vn", "-c:a", "libvorbis", "-q:a", "6", "-y", path)
    info = probe(path, ffprobe)
    output["loader"] = {**file_record(path), "duration": float(info["format"]["duration"]),
                        "channels": info["streams"][0]["channels"],
                        "source_url": "https://freesound.org/people/artxmp1/sounds/660540/",
                        "license": "CC-BY-4.0", "attribution": "Audio Logo (artxmpl-al-01) by Artxmpl",
                        "modifications": "Public high-quality MP3 preview converted to OGG Vorbis quality 6; full duration preserved."}
    return output


def video(name, source, dimensions, ffmpeg, ffprobe, crop=None, rate=None):
    info = probe(source, ffprobe, count_frames=True)
    stream = next(x for x in info["streams"] if x["codec_type"] == "video")
    source_fps = Fraction(stream["avg_frame_rate"])
    source_count = int(stream["nb_read_frames"])
    source_duration = float(info["format"]["duration"])
    source_size = (stream["width"], stream["height"])
    # A phone upload carries its picture inside a letterboxed rectangle. Removing
    # the bars is lossless, and that rectangle is what "source size" then means:
    # nothing downstream should measure or scale against the dead area.
    content_size = (crop[0], crop[1]) if crop else source_size
    dimensions = dimensions or content_size
    width, height = dimensions
    fps = Fraction(rate) if rate else source_fps
    target = ASSETS / "media" / name
    target.mkdir(parents=True, exist_ok=True)
    filters = [f"crop={crop[0]}:{crop[1]}:{crop[2]}:{crop[3]}"] if crop else []
    if dimensions != content_size:
        filters.append(f"scale={width}:{height}:flags=lanczos")
    spatial = ["-vf", ",".join(filters)] if filters else []
    # passthrough retains every source frame with no interpolation or FPS conversion.
    # An explicit rate is only for a source that is not constant across its own
    # timeline: ffmpeg repeats the frame already being held (dup), never blends a
    # new one, so the sequence lands on the grid its audio was authored against.
    timing = ["-fps_mode", "cfr", "-r", f"{fps.numerator}/{fps.denominator}"] if rate else ["-fps_mode", "passthrough"]
    run(ffmpeg, "-hide_banner", "-loglevel", "error", "-i", source, "-an", *spatial,
        *timing,
        "-q:v", "2", "-pix_fmt", "yuvj444p", "-start_number", "0", "-y", target / "frame-%05d.jpg")
    frames = sorted(target.glob("frame-*.jpg"))
    count = len(frames) if rate else source_count
    if len(frames) != count:
        raise ValueError(f"{name}: expected {count} frames, found {len(frames)}; stale output is not removed automatically")
    if rate:
        # Constant timing may only repeat a held frame: it can neither drop a source
        # frame nor change how long the sequence runs.
        expected = round(float(stream.get("duration") or source_duration) * float(fps))
        if count < source_count or abs(count - expected) > 1:
            raise ValueError(f"{name}: {count} frames at {fps} do not span the source's {expected} frame grid; "
                             "stale output is not removed automatically")
    total_bytes = 0
    frame_index = []
    for index, path in enumerate(frames):
        if path.name != f"frame-{index:05d}.jpg":
            raise ValueError(f"Unexpected frame sequence: {path}")
        with Image.open(path) as image:
            if image.size != dimensions:
                raise ValueError(f"Unexpected frame dimensions: {path}")
            image.verify()
        total_bytes += path.stat().st_size
        frame_index.append({"bytes": path.stat().st_size, "sha256": digest(path)})
    audio = None
    if any(x["codec_type"] == "audio" for x in info["streams"]):
        path = target / "audio.ogg"
        previous_path = target / "manifest.json"
        previous = json.loads(previous_path.read_text()) if previous_path.exists() else {}
        prior_audio = previous.get("audio_details") or {}
        reusable = (path.exists() and previous.get("source_sha256") == digest(source)
                    and prior_audio.get("sha256") == digest(path))
        if not reusable:
            run(ffmpeg, "-hide_banner", "-loglevel", "error", "-i", source, "-vn", "-c:a", "libvorbis", "-q:a", "6", "-y", path)
        audio_info = probe(path, ffprobe)
        audio_stream = next(x for x in audio_info["streams"] if x["codec_type"] == "audio")
        audio = {**file_record(path), "duration": float(audio_info["format"]["duration"]),
                 "channels": audio_stream["channels"], "sample_rate": int(audio_stream["sample_rate"]),
                 "codec": "vorbis", "quality": 6}
    index_path = target / "frames.json"
    write_json(index_path, frame_index)
    output = {"type": "sequence", "id": name, "pattern": relative(target / "frame-%05d.jpg"),
              "folder": relative(target), "prefix": "frame-", "ext": "jpg", "first": 0, "digits": 5, "count": count,
              "title": {"edit-one": "GIORGIO ARMANI / I", "edit-two": "GIORGIO ARMANI / II", "edit-three": "GIORGIO ARMANI / III", "edit-four": "GIORGIO ARMANI / IV", "loader-film": "GIORGIO / Opening film", "background": "Pinstripe motion"}.get(name, name),
              "first_index": 0, "frames": count, "fps": float(fps), "fps_ratio": f"{fps.numerator}/{fps.denominator}",
              "width": width, "height": height, "duration": count / float(fps),
              "source_width": stream["width"], "source_height": stream["height"],
              "source_file": source.name, "source_sha256": digest(source), "source_duration": source_duration,
              "source_path": str(source),
              "source_fps_ratio": stream["avg_frame_rate"], "source_frame_count": source_count,
              "content_crop": list(crop) if crop else None,
              "filter_arguments": spatial, "timing_arguments": timing,
              "encoding": "JPEG q:v 2, full-chroma 4:4:4; "
                          + (f"letterbox cropped to {content_size[0]}x{content_size[1]}, " if crop else "")
                          + ("source pixel dimensions, no spatial scaling" if dimensions == content_size else "Lanczos spatial scaling")
                          + ("; no temporal conversion" if not rate else
                             f"; constant {fps.numerator}/{fps.denominator} timing, {count - source_count} held frames repeated and none interpolated"),
              "frame_bytes": total_bytes, "frame_index": relative(index_path),
              "first_frame": file_record(frames[0]), "last_frame": file_record(frames[-1]), "audio": audio["path"] if audio else None,
              "audio_details": audio, "asset_quality": f"{width}x{height} at {float(fps):g} fps; every source frame preserved"
                               + (f" on a constant {fps.numerator}/{fps.denominator} grid" if rate else ""),
              "license": "User-supplied media; original creator/third-party rights remain with their owners.",
              "provenance": "Local file supplied by the user; original remains unchanged in Downloads."}
    write_json(target / "manifest.json", output)
    print(f"Verified {name}: {count} frames at {float(fps):g} fps, {width}x{height}, {total_bytes / 1048576:.1f} MiB JPEG.", flush=True)
    return output


def metadata(manifest, ffmpeg):
    """Add rebuild evidence and a full-HD image without repeating full conversion."""
    inventory = json.loads((ROOT / "media-reference/inventory.json").read_text())
    sources = {Path(x["path"]).name: Path(x["path"]) for x in inventory}
    for record in [manifest.get("background"), manifest.get("loaderFilm")] + manifest.get("edits", []):
        if not record:
            continue
        source = sources.get(record["source_file"], Path(record["source_path"]))
        record["source_path"] = str(source)
        spatial = record.get("filter_arguments")
        if spatial is None:
            spatial = [] if (record["width"], record["height"]) == (record["source_width"], record["source_height"]) else ["-vf", f"scale={record['width']}:{record['height']}:flags=lanczos"]
        timing = record.get("timing_arguments") or ["-fps_mode", "passthrough"]
        record["conversion_arguments"] = [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(source),
            "-an", *spatial, *timing,
            "-q:v", "2", "-pix_fmt", "yuvj444p", "-start_number", "0", "-y", str(ASSETS / record["pattern"])]
        if record["audio"]:
            record["audio_conversion_arguments"] = [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(source),
                "-vn", "-c:a", "libvorbis", "-q:a", "6", "-y", str(ASSETS / record["audio"])]
        write_json(ASSETS / record["folder"] / "manifest.json", record)
    source = sources["download.mp4"]
    target = ASSETS / "probes"
    target.mkdir(parents=True, exist_ok=True)
    path = target / "edit-one-fullhd.jpg"
    run(ffmpeg, "-hide_banner", "-loglevel", "error", "-ss", "3", "-i", source, "-frames:v", "1",
        "-q:v", "2", "-pix_fmt", "yuvj444p", "-y", path)
    with Image.open(path) as image:
        image.load()
        if image.size != (1920, 1080):
            raise ValueError("Full-HD probe did not preserve source dimensions")
    manifest["probes"] = {"fullhd": {**file_record(path), "width": 1920, "height": 1080,
        "source_file": source.name, "source_time": 3,
        "purpose": "Verify client support for a source-resolution image.",
        "status": "Client IsLoaded=true for 1920x1080 probe; ContentImageSize=0,0 was inconclusive for actual texture resolution. Live playback performance still requires verification."}}
    edit_sizes = sorted({f"{record['width']}x{record['height']}" for record in manifest.get("edits", [])})
    original_sizes = sorted({f"{record['source_width']}x{record['source_height']}" for record in manifest.get("edits", [])})
    loader = manifest.get("loaderFilm")
    background = manifest.get("background", {})
    manifest["asset_quality"] = {
        "edits": f"{', '.join(edit_sizes)} JPEG at original 60 fps, complete duration and separate stereo OGG audio.",
        "loader_film": (f"{loader['width']}x{loader['height']} JPEG at {loader['fps_ratio']} fps, all "
                        f"{loader['source_frame_count']} source frames and complete stereo OGG audio.") if loader else None,
        "background": f"{background.get('width')}x{background.get('height')} JPEG at original 25 fps, all 200 source frames.",
        "icons": "72x72 RGBA at original 120 fps, all 1159 source animation frames.",
        "originals": f"Unchanged original {', '.join(original_sizes)} edit videos and 1600x1200 background remain at source_path.",
        "limit": "Media files preserve original pixel dimensions by default; live rendering performance and effective texture resolution are verified separately from file dimensions."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", type=Path, default=DEFAULT_TOOLS / "ffmpeg.exe")
    parser.add_argument("--ffprobe", type=Path, default=DEFAULT_TOOLS / "ffprobe.exe")
    parser.add_argument("--node", type=Path, default=RUNTIME / "node/bin/node.exe")
    parser.add_argument("--node-modules", type=Path, default=RUNTIME / "node/node_modules")
    parser.add_argument("--only", choices=["all", "static", "video", "metadata"], default="all")
    parser.add_argument("--profile", choices=["source", "compatibility"], default="source", help="Source preserves original pixel dimensions; compatibility explicitly chooses smaller derived frames.")
    args = parser.parse_args()
    manifest_path = ASSETS / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {
        "version": 1, "path_base": "Giorgio/assets/", "deployment": "Local assets; no remote hosting or upload performed."}
    if args.only in ["all", "static"]:
        manifest["icons"] = icons()
        manifest["logo"] = logo(args.node, args.node_modules)
        manifest["sound_details"] = sounds(args.ffmpeg, args.ffprobe)
        manifest["sounds"] = {role: record["path"] for role, record in manifest["sound_details"].items()}
        license_dir = ASSETS / "licenses"
        license_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(RESEARCH / "line-md-LICENSE.txt", license_dir / "line-md-MIT.txt")
        shutil.copyfile(RESEARCH / "kenney-interface/License.txt", license_dir / "kenney-CC0.txt")
        (license_dir / "artxmpl-CC-BY-4.0.txt").write_text(
            "Audio Logo (artxmpl-al-01) by Artxmpl (https://www.patreon.com/artxmpl).\n"
            "Source: https://freesound.org/people/artxmp1/sounds/660540/\n"
            "License: Creative Commons Attribution 4.0, https://creativecommons.org/licenses/by/4.0/\n"
            "Modification: Public high-quality MP3 preview converted to OGG Vorbis quality 6.\n"
            "Full duration retained. The original WAV has not been downloaded.\n", encoding="utf-8")
        write_json(manifest_path, manifest)
    if args.only in ["all", "video"]:
        inventory = json.loads((ROOT / "media-reference/inventory.json").read_text())
        sources = {Path(x["path"]).name: Path(x["path"]) for x in inventory}
        selections = {"background": ("original-e6c90943d3d9da57b997c2898244009e.mp4", (800, 600)),
                      "edit-one": ("download.mp4", (1024, 576)),
                      "edit-two": ("slick.ae_TikTokDownloader.com_2dfe1.mp4", (1024, 576))}
        manifest.setdefault("edits", [])
        for name, (source_name, dimensions) in selections.items():
            if args.profile == "source":
                dimensions = None
            record = video(name, sources[source_name], dimensions, args.ffmpeg, args.ffprobe)
            if name == "background":
                manifest["background"] = record
            else:
                manifest["edits"] = [edit for edit in manifest["edits"] if edit["id"] != name] + [record]
                manifest["edits"].sort(key=lambda edit: {"edit-one": 0, "edit-two": 1, "edit-three": 2, "edit-four": 3}.get(edit["id"], 99))
            write_json(manifest_path, manifest)
    if args.only in ["all", "video", "metadata"]:
        metadata(manifest, args.ffmpeg)
        write_json(manifest_path, manifest)
    print(f"Manifest: {manifest_path}", flush=True)


if __name__ == "__main__":
    main()
