# Giorgio release preparation

This directory prepares the GitHub release. The development template intentionally has no download URL; the configured release copy receives its URL and manifest hash when packaging. The normal local build remains independent of this installer.

`package_release.py` packages the finished `Giorgio.lua` and the asset directory into numbered binary parts of at most **20 MiB each**, including their headers. Each part contains complete files; a file never spans parts. The manifest lists every install path, byte count and SHA-256, plus each part's size, SHA-256 and file membership. Existing output directories are never overwritten.

`installer.template.lua` is a standalone first-install experience using native text on a black and ivory layout. Its progress bar measures verified local asset bytes, including previously valid files. The received-byte counter updates after each HTTP response; it does not pretend the executor supplies streaming download progress. The installer hashes existing files, skips already complete parts, validates downloaded parts and their individual files before writing, checks every write, and runs the verified runtime exactly once. The runtime then supplies the normal Giorgio loading screen.

The **Minimize** button replaces the expanded screen with a compact card while installation continues. **Open** returns to the expanded screen. Both views report the exact integer number of bytes still to verify, rather than an estimated download time. Before the manifest arrives, the card says that it is calculating the remaining size. The expanded screen stays open until all files and the installed runtime pass verification, unless the user minimizes it. A failed download expands the error message and retains valid local files; running the installer again resumes. The compact card and every progress connection are removed when installation hands off to the runtime.

It installs only `Giorgio.lua` and files beneath `Giorgio/assets/`. It never rewrites a user's configuration. Shared default preferences belong in the runtime build; the runtime can apply them only where no saved preference exists. The package preserves those defaults as part of the runtime's hashed bytes.

SHA-256 is mandatory. Supported `crypt.hash`/`syn.crypt.hash` signatures are selected only after passing the standard `abc` SHA-256 test. The runtime also needs executor file, directory, HTTP and `loadstring` support. Missing capabilities or a disconnected release produce clear errors. Failed or interrupted installs retain verified asset files for the next run. Corrupt chunks are never executed or trusted.

## Publishing the configured release

1. Finish and verify the runtime and asset pack. Keep the release tag immutable after distributing a pinned installer.
2. Choose a **new, empty** output directory and the intended release URL. Generate the local files:

   ```powershell
   python giorgio/distribution/package_release.py --version v1.0.0 --output giorgio/distribution/releases/v1.0.0 --manifest-url https://github.com/OWNER/REPO/releases/download/v1.0.0/manifest.json
   ```

   This command only creates files. It does not create a repository, release, commit or upload. Replace `OWNER/REPO` only after the intended repository is known.

3. Upload numbered `.gpk` parts to the same GitHub Release in multiple batches. All download paths are derived from the one manifest URL; no repository file size workaround or ZIP extractor is needed. Upload `manifest.json` and `InstallGiorgio.lua` after every referenced part is present. `manifest.sha256.txt` is a local audit aid and need not be uploaded.
4. Verify uploaded bytes against the local manifest and test an empty executor workspace plus an interrupted-install resume. Then distribute the configured installer. The template itself intentionally remains unconfigured.

GitHub currently permits up to 1,000 assets per release, each under 2 GiB. Numbered 20 MiB parts are well within the per-file limit; the packer reserves two asset slots for the manifest and installer. A roughly 900 MiB collection needs around 45–50 parts, depending on file boundaries and header overhead. [GitHub's official release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas) (checked 2026-09-09).

## Binary format and verification

Each `.gpk` is `GIORGIO1\n`, followed by eight lowercase hexadecimal digits giving the UTF-8 JSON header length, then a newline, the JSON header, and concatenated raw file bytes. Header rows contain `path`, `bytes`, `sha256` and zero-based `offset`. Payload offsets are contiguous. The installer rejects unknown, duplicate, case-colliding, absolute, parent-traversal, Windows device, stream and trailing-dot paths; gaps, reordered rows and trailing payload data are rejected too.

Run the tiny binary fixtures and actual Luau core checks without producing the full release:

```powershell
python giorgio/distribution/verify_distribution.py
node C:/Users/61415/AppData/Local/Potassium/tools/check.js giorgio/distribution/installer.template.lua
```

The tests use temporary files and mocked download responses. They cover minimizing during an actual fixture install, restore, exact remaining-byte arithmetic, completion and error lifecycle, interrupted-download resume, and preservation of existing user configuration. A networked first-install test still belongs to the configured release verification; no live download success is claimed by these fixtures.
