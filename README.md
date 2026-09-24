# Giorgio

A Roblox interface built on the Lumen UI framework, with a dedicated Rep Root
page. The presentation is an Armani-styled loading sequence, film viewer and
player directory; the functional half is a Rep Root fling transaction with
fitted mount geometry and an auto-tune that measures its own results, plus a
Stand for The Strongest Battlegrounds that an owner commands from chat.

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
| `giorgio/tsb-stand.lua` | The Stand tab: latch, attack angle, squad fan, grab carry |
| `giorgio/tsb-ragebot.lua` | TSB game reads, input wire and void immunity |
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
python giorgio/verify_stand.py               # the Stand: latch, angle, squad, carry (240 checks)
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

## The Stand

Only in The Strongest Battlegrounds (place 10449761463). The stand is this
client's character; an owner chosen on the tab commands it from chat. Every
latch is a `PhysicsRepRootPart` binding — others see us at
`anchorRoot.CFrame * (our LOCAL root CFrame)`, so the raw pose is written as the
local CFrame and the server composes it, with no follow lag.

| Command | What it does |
| --- | --- |
| `.s` / `.d` | Summon beside you, or hide deep in the void |
| `.a [name]` | Hunt a target from your chosen angle; nearest if blank |
| `.stop` | Break off and come back |
| `.b <name>` | Take hold of that player and carry them to you |
| `.v <name>` | Take hold and carry them under the kill plane |
| `.angle <where>` | behind, behind left/right, flanks, in front, above, below |
| `.squad a,b` | Other stands to fan out with |
| `.1`–`.4`, `.m1`, `.dash`, `.ult`, `.fling`, `.pose`, `.say` | The rest |

**The attack angle** is one dial: 0 is directly behind the target, 90 their
right, 180 in front, 270 their left, and it turns to face them from wherever it
is put. A live preview draws every stand's slot on a real body while you tune —
yours solid, the others as ghosts, with a ring for the distance.

**Several stands share a target without a handshake.** A client-made instance
never reaches another client, so there is nothing to send: each stand sorts the
squad by user id, finds itself, and takes that slot of a fan centred on the
angle. Everyone computes the same layout, the fan widens rather than let two
stands share a swing, squadmates are never targeted, and each starts the skill
rotation on its own slot.

**The carry** rests on a measured fact: while a grab holds, the victim rides the
stand's replicated position. So the stand takes hold and then moves — in to you,
or down past the game's own −500 kill plane, which the target's client enforces
on itself. The descent is paced across the hold the move has been watched to
have and never stops while it lasts; snapping the whole distance leaves the
victim behind and they are simply put back on the map. It learns which moves
grab by watching which ones take hold, remembers their hold length, and takes
the target again if they survive.

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
