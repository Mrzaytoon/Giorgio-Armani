"""Tiny binary fixtures exercise the actual Luau installer core; no network or game writes."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from package_release import MAGIC, MAX_CHUNK_BYTES, configure_installer, digest, encode_chunk, json_bytes, package, valid_path

ROOT = Path(__file__).resolve().parent
LUAU = Path.home() / "AppData/Local/Temp/luaudl/luau.exe"
CORE = (ROOT / "installer.template.lua").read_text(encoding="utf-8").split("-- CORE BEGIN:", 1)[1].split("\n", 1)[1].split("-- CORE END", 1)[0]


def lua(value):
    if isinstance(value, bytes):
        return '"' + "".join(f"\\{byte:03d}" for byte in value) + '"'
    if isinstance(value, str):
        return lua(value.encode("utf-8"))
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if value is None:
        return "nil"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + lua(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    raise TypeError(type(value))


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="giorgio-distribution-")
        self.root = Path(self.temp.name)
        self.assets = self.root / "assets"
        (self.assets / "nested").mkdir(parents=True)
        self.runtime = self.root / "Giorgio.lua"
        self.runtime.write_bytes(b"return 'fixture runtime'\n")
        (self.assets / "binary.bin").write_bytes(bytes(range(256)))
        (self.assets / "nested/empty.bin").write_bytes(b"")
        (self.assets / "nested/frame.bin").write_bytes(b"\0\xff\x80\r\n" * 40)
        self.output = self.root / "release"
        self.manifest = package(self.runtime, self.assets, self.output, "test-1", limit=640)

    def tearDown(self):
        self.temp.cleanup()

    def run_core(self, scenario="fresh", transform=None, initial=None):
        manifest = copy.deepcopy(self.manifest)
        bodies = {chunk["file"]: (self.output / chunk["file"]).read_bytes() for chunk in manifest["chunks"]}
        if transform:
            transform(manifest, bodies)
        manifest_bytes = json_bytes(manifest)
        url = "https://example.invalid/releases/test/manifest.json"
        downloads = {url: manifest_bytes, **{url.rsplit("/", 1)[0] + "/" + name: body for name, body in bodies.items()}}
        decode = {manifest_bytes: manifest}
        hashes = {body: digest(body) for body in downloads.values()}
        expected_files = {"Giorgio.lua": self.runtime.read_bytes()}
        expected_files.update({"Giorgio/assets/" + p.relative_to(self.assets).as_posix(): p.read_bytes() for p in self.assets.rglob("*") if p.is_file()})
        for body in list(bodies.values()):
            if body.startswith(MAGIC):
                try:
                    length = int(body[len(MAGIC):len(MAGIC) + 8], 16)
                    start = len(MAGIC) + 9
                    header_body = body[start:start + length]
                    header = json.loads(header_body)
                    decode[header_body] = header
                    for row in header["files"]:
                        data = body[start + length + row["offset"]:start + length + row["offset"] + row["bytes"]]
                        hashes[data] = digest(data)
                except (ValueError, KeyError):
                    pass
        for data in expected_files.values():
            hashes[data] = digest(data)
        initial = initial or {}
        for data in initial.values():
            hashes[data] = digest(data)
        assertions = {
            "fresh": "assert(ok, result); assert(executions == 1); assert(writes == 4); assert(result.bytes == manifest.total_bytes); assert(downloadCount == #manifest.chunks + 1)",
            "resume": "assert(ok, result); assert(executions == 1); assert(writes == 0); assert(downloadCount == 1); assert(result.transferred == 0)",
            "partial": "assert(ok, result); assert(executions == 1); assert(writes == 3); assert(storage['Giorgio.lua'] == expected['Giorgio.lua'])",
            "corrupt_local": "assert(ok, result); assert(executions == 1); assert(writes == 1); assert(storage['Giorgio/assets/binary.bin'] == expected['Giorgio/assets/binary.bin'])",
            "fail": "assert(not ok, 'corrupt release was accepted'); assert(executions == 0); assert(writes == 0)",
            "write_fail": "assert(not ok, 'corrupt write was accepted'); assert(executions == 0)",
            "interrupted": "assert(not ok and executions == 0 and writes > 0); local savedWrites = writes; failFetch = false; local ok2, result2 = pcall(Installer.install, env, releaseURL, releaseHash); assert(ok2, result2); assert(executions == 1 and writes == 4 and savedWrites < writes); ok, result = ok2, result2",
            "wrong_manifest_hash": "assert(not ok, 'wrong manifest hash was accepted'); assert(executions == 0 and writes == 0 and downloadCount == 1)",
            "minimized": "assert(ok, result); assert(executions == 1 and writes == 4); assert(progressView.state.minimized and progressView.state.remaining == 0); assert(progressView.state.phase == 'ready')",
            "existing_config": "assert(ok, result); assert(executions == 1 and writes == 4); assert(storage['Giorgio/config.json'] == 'existing user preferences')",
        }[scenario]
        harness = CORE + "\n" + f"""
local downloads, decoded, hashes = {lua(downloads)}, {lua(decode)}, {lua(hashes)}
local manifest, storage, expected = {lua(manifest)}, {lua(initial)}, {lua(expected_files)}
local writes, executions, downloadCount = 0, 0, 0
local failFetch = {lua(scenario == 'interrupted')}
local progressView = Installer.newProgressView(function() end)
local lastComplete, lastTotal, phases = 0, 0, {{}}
local env = {{
    hash = function(data) return hashes[data] or string.rep('0', 64) end,
    decode = function(data) assert(decoded[data], 'unknown fixture JSON'); return decoded[data] end,
    fetch = function(address)
        downloadCount += 1
        if failFetch and address:find('chunk%-0002') then error('fixture interrupted connection') end
        assert(downloads[address], address); return downloads[address]
    end,
    isfile = function(path) return storage[path] ~= nil end,
    readfile = function(path) assert(storage[path] ~= nil); return storage[path] end,
    writefile = function(path, data)
        assert(Installer.validPath(path)); writes += 1
        storage[path] = {'"corrupted-write"' if scenario == 'write_fail' else 'data'}
    end,
    makefolder = function(path) assert(path == 'Giorgio' or path == 'Giorgio/assets' or path:sub(1, 15) == 'Giorgio/assets/') end,
    yield = function() end,
    progress = function(phase, complete, total, transferred, files, index, count)
        if phase == 'manifest' then lastComplete = 0 end
        assert(complete >= lastComplete and complete <= total)
        lastComplete, lastTotal = complete, total; phases[phase] = true
        progressView:update(phase, complete, total, transferred, files, index, count)
        if {lua(scenario == 'minimized')} and phase == 'checking' then progressView:minimize(true) end
    end,
    execute = function(source)
        executions += 1; assert(source == expected['Giorgio.lua'])
        assert(progressView.alive and progressView.state.phase == 'ready' and progressView.state.remaining == 0)
    end,
}}
local releaseURL, releaseHash = {lua(url)}, {lua('0' * 64 if scenario == 'wrong_manifest_hash' else digest(manifest_bytes))}
local ok, result = pcall(Installer.install, env, releaseURL, releaseHash)
{assertions}
if ok then assert(lastComplete == lastTotal); assert(phases.ready) end
print('PASS {scenario}')
"""
        self.run_luau(harness)

    def run_luau(self, source):
        script = self.root / "fixture.lua"
        script.write_text(source, encoding="utf-8")
        run = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def expected(self):
        return {"Giorgio.lua": self.runtime.read_bytes(), **{"Giorgio/assets/" + p.relative_to(self.assets).as_posix(): p.read_bytes() for p in self.assets.rglob("*") if p.is_file()}}

    def test_fresh_binary_install(self):
        self.assertTrue(all(c["bytes"] <= 640 for c in self.manifest["chunks"]))
        self.run_core()

    def test_deterministic_pack(self):
        result = package(self.runtime, self.assets, self.root / "second", "test-1", limit=640)
        self.assertEqual(result, self.manifest)

    def test_complete_resume_downloads_manifest_only(self):
        self.run_core("resume", initial=self.expected())

    def test_partial_resume_preserves_valid_runtime(self):
        self.run_core("partial", initial={"Giorgio.lua": self.runtime.read_bytes()})

    def test_interrupted_download_resumes_without_rewriting_verified_files(self):
        self.run_core("interrupted")

    def test_manifest_hash_pin_rejected_before_writes(self):
        self.run_core("wrong_manifest_hash")

    def test_download_and_execution_continue_while_minimized(self):
        self.run_core("minimized")

    def test_existing_configuration_is_never_overwritten(self):
        self.run_core("existing_config", initial={"Giorgio/config.json": b"existing user preferences"})

    def test_progress_view_minimizes_restores_and_keeps_exact_remaining_bytes(self):
        self.run_luau(CORE + """
local renders = 0
local view = Installer.newProgressView(function(state)
    renders += 1
    assert(state.remaining == nil or state.remaining == state.total - state.complete)
end)
assert(view.alive and not view.state.minimized and view.state.remaining == nil)
view:update('checking', 0, 987654321, 0, 0)
assert(view.state.remaining == 987654321)
view:minimize(true)
view:update('downloading', 123456789, 987654321, 130000000, 14, 2, 45)
assert(view.state.minimized and view.state.remaining == 864197532)
assert(Installer.formatBytes(view.state.remaining) == '864,197,532')
view:minimize(false)
assert(not view.state.minimized and view.state.remaining == 864197532 and view.alive)
assert(Installer.formatBytes(0) == '0' and Installer.formatBytes(999) == '999')
assert(Installer.formatBytes(1000) == '1,000' and Installer.formatBytes(8589934592) == '8,589,934,592')
assert(renders == 4)
""")

    def test_progress_view_stays_visible_until_verified_and_destroyed(self):
        self.run_luau(CORE + """
local renders = 0
local view = Installer.newProgressView(function() renders += 1 end)
view:update('installing', 99, 100, 100, 2)
assert(view.alive and not view.state.minimized and view.state.remaining == 1)
assert(not pcall(function() view:update('ready', 99, 100, 100, 2) end))
assert(view.state.phase == 'installing' and view.state.remaining == 1)
view:update('ready', 100, 100, 100, 3)
assert(view.alive and not view.state.minimized and view.state.remaining == 0)
local before = renders
view:destroy()
assert(not view:update('manifest', 0, 0, 0, 0))
assert(not view:minimize(true) and not view:fail('late error'))
assert(renders == before)
""")

    def test_failed_minimized_install_expands_without_losing_progress(self):
        self.run_luau(CORE + """
local view = Installer.newProgressView(function() end)
view:update('installing', 300, 1000, 500, 3)
view:minimize(true)
view:fail('Connection interrupted')
assert(view.alive and not view.state.minimized and view.state.phase == 'failed')
assert(view.state.error == 'Connection interrupted' and view.state.remaining == 700)
assert(not view:minimize(true))
""")

    def test_corrupt_local_asset_is_replaced(self):
        initial = self.expected()
        initial["Giorgio/assets/binary.bin"] = b"broken"
        self.run_core("corrupt_local", initial=initial)

    def test_corrupted_download_rejected_before_writes(self):
        def corrupt(manifest, bodies):
            first = manifest["chunks"][0]["file"]
            bodies[first] = bodies[first][:-1] + bytes([bodies[first][-1] ^ 255])
        self.run_core("fail", transform=corrupt)

    def test_file_corruption_rejected_even_if_part_hash_matches(self):
        def corrupt(manifest, bodies):
            chunk = manifest["chunks"][0]
            bodies[chunk["file"]] = bodies[chunk["file"]][:-1] + bytes([bodies[chunk["file"]][-1] ^ 255])
            chunk["sha256"] = digest(bodies[chunk["file"]])
        self.run_core("fail", transform=corrupt)

    def test_traversal_manifest_is_rejected(self):
        for path in ["../escape", "Giorgio/config.json", "Giorgio/assets/../config.json", "Giorgio/assets/x/../../escape", "C:/Giorgio/assets/x", "Giorgio/assets/x:stream", "Giorgio/assets/CON.txt", "Giorgio/assets/foo.", "Giorgio/assets//bad", "Giorgio/assets/\\bad"]:
            with self.subTest(path=path):
                self.assertFalse(valid_path(path))
                def mutate(manifest, bodies):
                    manifest["files"][0]["path"] = path
                self.run_core("fail", transform=mutate)

    def test_unknown_header_path_rejected(self):
        def mutate(manifest, bodies):
            chunk = manifest["chunks"][0]
            row = dict(manifest["files"][0])
            row["path"] = "Giorgio/assets/../escape"
            blob = encode_chunk([(row, self.runtime.read_bytes())])
            bodies[chunk["file"]] = blob
            chunk["bytes"], chunk["sha256"] = len(blob), digest(blob)
        self.run_core("fail", transform=mutate)

    def test_case_collision_rejected(self):
        def mutate(manifest, bodies):
            manifest["files"][2]["path"] = "Giorgio/assets/BINARY.bin"
        self.run_core("fail", transform=mutate)

    def test_header_offset_gap_rejected(self):
        def mutate(manifest, bodies):
            chunk = manifest["chunks"][0]
            blob = bodies[chunk["file"]]
            size = int(blob[len(MAGIC):len(MAGIC) + 8], 16)
            start = len(MAGIC) + 9
            header = json.loads(blob[start:start + size])
            header["files"][0]["offset"] = 1
            encoded = json_bytes(header)
            blob = MAGIC + f"{len(encoded):08x}\n".encode() + encoded + blob[start + size:]
            bodies[chunk["file"]] = blob
            chunk["bytes"], chunk["sha256"] = len(blob), digest(blob)
        self.run_core("fail", transform=mutate)

    def test_trailing_part_data_rejected(self):
        def mutate(manifest, bodies):
            chunk = manifest["chunks"][0]
            blob = bodies[chunk["file"]] + b"unexpected"
            bodies[chunk["file"]] = blob
            chunk["bytes"], chunk["sha256"] = len(blob), digest(blob)
        self.run_core("fail", transform=mutate)

    def test_corrupt_filesystem_write_never_executes(self):
        self.run_core("write_fail")

    def test_oversized_individual_file_rejected(self):
        (self.assets / "too-large.bin").write_bytes(bytes(641))
        with self.assertRaisesRegex(ValueError, "exceeds"):
            package(self.runtime, self.assets, self.root / "oversized", "test", 640)

    def test_release_output_must_be_new_and_outside_assets(self):
        with self.assertRaisesRegex(ValueError, "empty"):
            package(self.runtime, self.assets, self.output, "test")
        with self.assertRaisesRegex(ValueError, "outside"):
            package(self.runtime, self.assets, self.assets / "release", "test")

    def test_template_stays_dormant_and_configured_copy_pins_manifest(self):
        output = self.root / "InstallGiorgio.lua"
        configure_installer(ROOT / "installer.template.lua", output, "https://example.invalid/release/manifest.json", self.output / "manifest.json")
        self.assertIn('local MANIFEST_URL = "" -- SET_AT_RELEASE', (ROOT / "installer.template.lua").read_text(encoding="utf-8"))
        self.assertIn(digest((self.output / "manifest.json").read_bytes()), output.read_text(encoding="utf-8"))
        self.assertNotIn("SET_AT_RELEASE", output.read_text(encoding="utf-8"))


if __name__ == "__main__":
    if not LUAU.is_file():
        raise SystemExit("Real Luau runtime required for installer verification: " + str(LUAU))
    unittest.main(verbosity=2)
