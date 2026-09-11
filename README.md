# Giorgio

A Roblox interface built on the Lumen UI framework, with a dedicated Rep Root
page. The presentation is an Armani-styled loading sequence, film viewer and
player directory; the functional half is a Rep Root fling transaction with
fitted mount geometry and an auto-tune that measures its own results.

## Install

The runtime and its media are distributed as a GitHub Release, not as a file in
this repository — the asset pack is roughly 1.2 GB of full-resolution frame
sequences. Run the installer once in your executor:

```lua
loadstring(game:HttpGet("https://github.com/Mrzaytoon/Giorgio-Armani/releases/latest/download/InstallGiorgio.lua"))()
```

It shows a progress screen while it downloads, verifies every file it writes,
and starts Giorgio automatically when it finishes.

- **It resumes.** Every run re-hashes what is already on disk and downloads only
  the parts still missing, so disconnecting halfway and running it again picks
  up where it stopped rather than starting over.
- **It minimises.** The screen collapses to a compact bar that keeps reporting
  progress; downloading and installing continue either way.
- **It never touches your configuration.** An existing `Giorgio/config.json` is
  left exactly as it is.

Afterwards, `Giorgio.lua` runs directly — the installer is only needed for a
first install or to repair a damaged one.

Requires an executor with file, folder, HTTP, `loadstring` and SHA-256
(`crypt.hash` or `syn.crypt.hash`) support. Missing capabilities produce a clear
error rather than a partial install.

## Layout

| Path | What it is |
| --- | --- |
| `Giorgio.lua` | The built runtime. **Generated — do not edit.** |
| `lumen-reproot/` | The Lumen snapshot, its patch set, and the Rep Root pages |
| `giorgio/` | Presentation: loader, media player, UI skin, player panel |
| `giorgio/media/` | Asset packaging, verification and deployment tools |
| `giorgio/assets/` | Runtime assets and their attribution, minus the film media |
| `giorgio/distribution/` | Release packager and the installer template |

`Giorgio.lua` is assembled from the sources above:

```bash
python lumen-reproot/build.py --giorgio
```

The build applies a fixed set of single-site patches to the Lumen snapshot,
splices in the Giorgio modules, embeds the asset manifest, and refuses to write
the output unless it compiles.

## Checks

Each subsystem has a harness that runs without a Roblox client:

```bash
python lumen-reproot/verify_geometry.py      # mount geometry, evidence, tune lifecycle
python lumen-reproot/verify_queue.py         # queue, respawn, fairness, cancellation
python lumen-reproot/verify_preferences.py   # persistence and noclip
python giorgio/verify_window.py              # window transitions
python giorgio/verify_native.py              # native opacity and tooltips
python giorgio/verify_player_panel.py        # directory search, sorting, row windowing
python giorgio/verify_camera.py              # camera handoff, stop, respawn
python giorgio/media/verify_assets.py        # decodes and hashes every packaged frame
python giorgio/distribution/verify_distribution.py  # install, resume, minimise
```

## Rep Root geometry

The mount that throws a target upward is the one sitting under it. `Geometry.fit`
produces both that fit and its mirror above the target, and a survey asks the map
which is worth using: a downward raycast for clear fall, then a twelve-bearing
sweep out to 1024 studs for the nearest opening when there is a floor in the way.

Auto-tune scores each candidate on contact-correlated evidence, then weights how
much of the distance to the void plane the attempt actually covered. Travel is
capped by the clearance that exists, so driving a target into a floor two studs
down scores as two studs of a five hundred stud drop rather than as a success.
With no survey available, scoring falls back to speed and travel exactly as
before.

## Credits and licensing

Full attribution is in [`giorgio/assets/CREDITS.md`](giorgio/assets/CREDITS.md)
and the licence texts in `giorgio/assets/licenses/`.

- **Audio Logo (artxmpl-al-01)** by Artxmpl (<https://www.patreon.com/artxmpl>), CC BY 4.0
- **Interface sounds** by Kenney (<https://kenney.nl/assets/interface-sounds>), CC0
- **Animated icons** — line-md by Vjacheslav Trushkin, MIT
- **Giorgio Armani wordmark, eagle and film footage** belong to their respective
  owners. This is a personal interface using that material; it is not an official
  Giorgio Armani product, no affiliation is claimed, and no redistribution
  licence over that material is asserted.
