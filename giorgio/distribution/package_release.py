"""Build local, bounded binary release parts. This tool never uploads anything."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

MAGIC = b"GIORGIO1\n"
PREFIX_BYTES = len(MAGIC) + 9
MAX_CHUNK_BYTES = 20 * 1024 * 1024
MAX_HEADER_BYTES = 1024 * 1024
RESERVED = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}


def valid_path(value: str) -> bool:
    if value == "Giorgio.lua":
        return True
    if not isinstance(value, str) or len(value) > 240 or not value.startswith("Giorgio/assets/"):
        return False
    for part in value.split("/"):
        if not re.fullmatch(r"[A-Za-z0-9_. -]+", part) or part in {".", ".."}:
            return False
        if part.endswith((".", " ")) or part.split(".")[0].upper() in RESERVED:
            return False
    return True


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), sort_keys=True).encode("ascii")


def chunk_header(rows: list[tuple[dict, bytes]]) -> bytes:
    entries, offset = [], 0
    for meta, payload in rows:
        entries.append({**meta, "offset": offset})
        offset += len(payload)
    header = json_bytes({"schema": 1, "files": entries})
    if len(header) > MAX_HEADER_BYTES:
        raise ValueError("Chunk header exceeds its limit")
    return header


def chunk_size(rows: list[tuple[dict, bytes]]) -> int:
    return PREFIX_BYTES + len(chunk_header(rows)) + sum(len(payload) for _, payload in rows)


def encode_chunk(rows: list[tuple[dict, bytes]]) -> bytes:
    header = chunk_header(rows)
    return MAGIC + f"{len(header):08x}\n".encode("ascii") + header + b"".join(payload for _, payload in rows)


def collect_sources(runtime: Path, assets: Path) -> list[tuple[str, Path]]:
    runtime, assets = runtime.resolve(strict=True), assets.resolve(strict=True)
    if not runtime.is_file() or not assets.is_dir():
        raise ValueError("Runtime must be a file and assets must be a directory")
    result = [("Giorgio.lua", runtime)]
    # research/ holds rebuild inputs that nothing loads at runtime; deploy_assets.py
    # leaves them out of a client too, and shipping them would add ten megabytes to
    # every install. Everything else under assets/ is packaged as found.
    def packaged(path: Path) -> bool:
        parts = path.relative_to(assets).parts
        if parts and parts[0] == "research":
            return False
        if "__pycache__" in parts:
            return False
        return not (len(parts) > 1 and parts[0] == "sounds" and path.suffix.lower() == ".mp3")
    for path in sorted(assets.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Asset symlinks are not packaged: {path}")
        if path.is_file() and packaged(path):
            path.resolve(strict=True).relative_to(assets)
            result.append(("Giorgio/assets/" + path.relative_to(assets).as_posix(), path))
    seen = set()
    for name, _ in result:
        if not valid_path(name) or name.lower() in seen:
            raise ValueError(f"Unsafe or case-colliding install path: {name}")
        seen.add(name.lower())
    return result


def package(runtime: Path, assets: Path, output: Path, version: str, limit: int = MAX_CHUNK_BYTES) -> dict:
    if not 512 <= limit <= MAX_CHUNK_BYTES:
        raise ValueError("Chunk limit must be between 512 bytes and 20 MiB")
    sources = collect_sources(runtime, assets)
    output = output.resolve()
    # Do not allow release output to become an input on the next run.
    if output == assets.resolve() or assets.resolve() in output.parents:
        raise ValueError("Output must be outside the asset directory")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Output directory must be empty; choose a new version directory")
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": 1, "version": version, "entrypoint": "Giorgio.lua", "chunk_limit": limit,
                "total_bytes": 0, "files": [], "chunks": []}
    pending: list[tuple[dict, bytes]] = []

    def flush() -> None:
        if not pending:
            return
        blob = encode_chunk(pending)
        if len(blob) > limit:
            raise ValueError("Internal chunk sizing error")
        filename = f"chunk-{len(manifest['chunks']) + 1:04d}.gpk"
        (output / filename).write_bytes(blob)
        manifest["chunks"].append({"file": filename, "bytes": len(blob), "sha256": digest(blob),
                                   "files": [row[0]["path"] for row in pending]})
        pending.clear()

    for name, path in sources:
        # A single file never straddles parts, allowing a verified file to be resumed independently.
        if path.stat().st_size > limit:
            raise ValueError(f"Individual file exceeds chunk limit: {name}")
        payload = path.read_bytes()
        meta = {"path": name, "bytes": len(payload), "sha256": digest(payload)}
        if chunk_size([(meta, payload)]) > limit:
            raise ValueError(f"Individual file plus its header exceeds chunk limit: {name}")
        if pending and chunk_size(pending + [(meta, payload)]) > limit:
            flush()
        pending.append((meta, payload))
        manifest["files"].append(meta)
        manifest["total_bytes"] += len(payload)
    flush()
    if len(manifest["chunks"]) > 998:
        raise ValueError("Too many release parts; reserve two GitHub release assets for manifest and installer")
    manifest_data = json_bytes(manifest)
    (output / "manifest.json").write_bytes(manifest_data)
    (output / "manifest.sha256.txt").write_text(digest(manifest_data) + "  manifest.json\n", encoding="ascii")
    return manifest


def configure_installer(template: Path, output: Path, manifest_url: str, manifest_file: Path) -> None:
    if not re.fullmatch(r"https://[^\s\"\\]+/manifest\.json", manifest_url):
        raise ValueError("Use the HTTPS release URL ending in /manifest.json")
    source = template.read_text(encoding="utf-8")
    source = source.replace('local MANIFEST_URL = "" -- SET_AT_RELEASE',
                            "local MANIFEST_URL = " + json.dumps(manifest_url), 1)
    source = source.replace('local MANIFEST_SHA256 = "" -- SET_AT_RELEASE',
                            "local MANIFEST_SHA256 = " + json.dumps(digest(manifest_file.read_bytes())), 1)
    output.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, default=root / "Giorgio.lua")
    parser.add_argument("--assets", type=Path, default=root / "giorgio/assets")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--manifest-url", help="Optional future release URL; no network calls are made")
    args = parser.parse_args()
    result = package(args.runtime, args.assets, args.output, args.version)
    if args.manifest_url:
        configure_installer(Path(__file__).with_name("installer.template.lua"), args.output / "InstallGiorgio.lua",
                            args.manifest_url, args.output / "manifest.json")
    print(f"Local package: {len(result['files'])} files, {len(result['chunks'])} parts, {result['total_bytes']:,} payload bytes")


if __name__ == "__main__":
    main()
