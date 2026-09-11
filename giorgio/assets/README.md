# Giorgio asset package

`manifest.json` is the deployment contract. Copy its referenced files into the
client's `Giorgio/assets/` folder; every `file`, `path`, `folder` and sound path is
relative to that folder. Nothing has been uploaded or published by the build.
The `research/` directory contains retained research originals and does not need
to be copied into the client cache.

## Included media

| Asset | Deployed image size | Frame rate | Exact frames | Duration |
| --- | --- | --- | --- | --- |
| User's pinstripe background | 1600 × 1200 | 25 fps | 200 | 8 s |
| First Armani edit (`download.mp4`) | 1920 × 1080 | 60 fps | 1,308 | 21.8 s |
| Second Armani edit (`slick.ae_TikTokDownloader.com_2dfe1.mp4`) | 1920 × 1080 | 60 fps | 3,195 | 53.25 s |
| Third Armani edit (`snaptik_7673144844079861025_hd.mp4`) | 1920 × 1080 | 60 fps | 1,011 | 16.85 s |
| Fourth Armani edit (`ssstik.io_1788957591207.mp4`) | 1920 × 1080 | 60 fps | 1,488 | 24.8 s |
| Loader-only film (`ssstik.io_1788956993576.mp4`) | 1080 × 608 | 60 fps | 3,620 | 60.333333 s |
| line-md icon animations | 72 × 72 | 120 fps | 1,159 total | See manifest |

All decoded source frames are retained. Nothing is interpolated, trimmed, or
replaced by a repeated loop. Video JPEGs use FFmpeg quality 2 and full-chroma
4:4:4. The default source-quality profile keeps original pixel dimensions; the
two exceptions are recorded per record in `encoding` and `conversion_arguments`:

- The fourth edit's source is a 3840 × 2160 master. It is Lanczos-scaled once to
  the library's 1920 × 1080 plate, which is already above what the 1040 × 585
  film stage can show. Its own 60/1 timing is untouched.
- The loader-only film's source is a 1080 × 1440 portrait upload whose picture
  occupies 1080 × 608 between two 416px black bars. The bars are cropped away —
  lossless for the picture, and it stops the loader's 640 × 360 stage from
  spending 58% of itself on dead area. That source also runs at a true 60 fps
  until a 30 fps tail, so it is written onto a constant 60/1 grid: FFmpeg
  reported `dup=89 drop=0`, meaning 89 frames the tail already holds are
  repeated, none are dropped, and none are blended. Left at its 58.52 fps
  average, the picture would have drifted roughly 1.5 s behind its own audio by
  the end of the film.
Each edit has its complete original stereo audio converted to OGG Vorbis quality
6; `audio_details.duration` records the encoded audio duration separately from
video duration. The slight source audio/video duration differences are preserved.
The loader-only film also has its complete stereo audio and all original frames.
Its playback record is `loaderFilm`, separate from the three cycling `edits`.
The loader's presentation may choose an excerpt while retaining the complete source
asset; this does not add the loader-only film to the edit cycle.

The original edit videos remain unchanged in the source paths in the manifest,
at 1920 × 1080 except the fourth edit's 3840 × 2160 master. The deployed edit
files are all **1920 × 1080**. The client accepted
`probes/edit-one-fullhd.jpg` (`IsLoaded=true`); its `ContentImageSize=0,0` reading
did not establish the effective runtime texture resolution. Smooth playback and
actual rendered quality still need live verification. `conversion_arguments`
preserves an exact, shell-independent argument list for each current conversion.

Sequence indexing starts at zero: `frame-00000.jpg`. Atlas numbering starts at
one: `gauge-01.png`. `count` always means animation frames. `pageCount` is the
number of PNG atlases, and `first` is the first filename index. Icon atlas cells
are 72 × 72; atlases have 14 columns and up to 14 rows (1008 × 1008 maximum).
The final page can be shorter; its actual dimensions and count appear in `pages`.
For animation frame `f` starting at zero, page is `floor(f/196)+1`, column is
`f%14`, and row is `floor((f%196)/14)`. Play the first 6 icons once and hold their
last frame; the loading animation is marked for looping.

## Provenance and credit

- **Official wordmark:** SVG extracted from the [Giorgio Armani website](https://www.armani.com/en-us/giorgio-armani/),
  rendered white onto transparent PNG at 2048 × 234. Original SVG retained.
  Giorgio Armani owns the brand/trademark; no open-content license is asserted.
- **Striped eagle:** Exact Emporio Armani eagle paths from the brand switcher on
  the [official Emporio Armani website](https://www.armani.com/en-us/emporio-armani/).
  The vector viewBox removes surrounding layout whitespace; transparent PNG is
  2048 × 984. This is the Emporio eagle with GA initials, separately identified
  from the Giorgio Armani wordmark. Original paths and rights are retained.
- **Icons:** [line-md by Vjacheslav Trushkin](https://github.com/cyberalien/line-md),
  MIT. All seven downloaded 120 fps frame sets are complete. The copyright and
  license notice is retained at `licenses/line-md-MIT.txt`.
- **Interface sounds:** [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds),
  CC0. Eight selected OGG files are copied without audio modification. License:
  `licenses/kenney-CC0.txt`.
- **Loading sound:** [Beautiful calming audio logo (artxmpl-al-01)](https://freesound.org/people/artxmp1/sounds/660540/)
  by Artxmpl, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  The source page expressly permits sharing and adaptation with attribution.
  This package uses its public high-quality MP3 preview, converted to OGG, and
  preserves its full duration. It does not claim the quality of the original WAV,
  which was not downloaded. Required product credit:
  **Audio Logo (artxmpl-al-01) by Artxmpl (https://www.patreon.com/artxmpl).**
  Conversion and license details are in `licenses/artxmpl-CC-BY-4.0.txt`.
- **Videos:** Supplied local files from the user. Original creators and other
  rights holders retain their rights. No separate redistribution license is
  asserted. The two other supplied logo reveals and tea-site clip remain motion
  references in `../media-reference/`; they are not falsely presented as branded
  Giorgio loading animation assets.

## Rebuilding and checking

Use `../media/package_assets.py` with Python/Pillow, FFmpeg, FFprobe and Node/sharp.
The tool locates this workstation's runtime defaults; use its CLI switches on
another machine. `--only static`, `--only video`, or `--only metadata` rebuilds a
subset. `--profile source` is the default and preserves original dimensions;
`--profile compatibility` explicitly requests reduced derived frame dimensions
if a separate performance tier is needed. It refuses inconsistent frame counts
instead of silently deleting files. A resolution-only rebuild retains matching,
verified OGG audio files unchanged.
`../media/verify_assets.py` decodes every deployed frame, checks file hashes,
compares every packed icon cell against its exact source frame, checks complete
audio metadata and writes `verification.json`. `preview.jpg` is a static package
contact sheet for local visual inspection, not a runtime replacement.
Use `../media/package_supplied_media.py` to rebuild the fourth edit and the
current loader-only film; it is also the worked example for `video()`'s `crop`
and `rate` arguments. `../media/package_new_media.py` rebuilds the third edit
and the film the loader used before it,
and `../media/extract_symbol.py` to recreate the exact eagle from the saved
official source page. These additions preserve the original two edit records.
