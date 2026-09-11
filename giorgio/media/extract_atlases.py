"""Extract source-rate atlas pages and separate audio for the Giorgio UI.

No fps filter or interpolation is used: every decoded source frame is retained.
The full profile preserves source pixel dimensions. Fit scales only spatially.
Generated files are deliberately outside the Luau source/build pipeline.
"""
from __future__ import annotations
import argparse,json,math,subprocess
from fractions import Fraction
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
TOOLS=Path(r'C:\Users\61415\AppData\Local\Potassium\tools')
DOWNLOADS=Path(r'C:\Users\61415\Downloads')
SOURCES={
    'edit-one': DOWNLOADS/'download.mp4',
    'edit-two': DOWNLOADS/'slick.ae_TikTokDownloader.com_2dfe1.mp4',
    'background': DOWNLOADS/'original-e6c90943d3d9da57b997c2898244009e.mp4',
}

def run(cmd): subprocess.run([str(x) for x in cmd],check=True)

def build(name,profile,max_edge,jpeg_q,dest):
    source=SOURCES[name]
    probe=json.loads(subprocess.check_output([str(TOOLS/'ffprobe.exe'),'-v','error','-count_frames','-show_streams','-show_format','-of','json',str(source)],text=True))
    video=next(x for x in probe['streams'] if x['codec_type']=='video')
    source_w,source_h=video['width'],video['height']; frames=int(video['nb_read_frames']); fps=Fraction(video['avg_frame_rate'])
    w,h=(source_w,source_h) if profile=='full' else ((800,600) if name=='background' else (960,540))
    if max(w,h)>max_edge: raise ValueError('Requested sheet edge cannot hold one frame; use a larger edge or fit profile.')
    cols,rows=max_edge//w,max_edge//h
    page_frames=cols*rows
    target=dest/f'{name}-{profile}-{max_edge}'
    target.mkdir(parents=True,exist_ok=True)
    # Re-running a build is allowed only when the exact output pages belong to this conversion.
    vf=[]
    if (w,h)!=(source_w,source_h): vf.append(f'scale={w}:{h}:flags=lanczos')
    vf.append(f'tile={cols}x{rows}')
    run([TOOLS/'ffmpeg.exe','-hide_banner','-loglevel','error','-i',source,'-an','-vf',','.join(vf),'-fps_mode','passthrough','-q:v',jpeg_q,'-y',target/'page-%05d.jpg'])
    pages=sorted(target.glob('page-*.jpg'))
    expected=math.ceil(frames/page_frames)
    if len(pages)!=expected: raise RuntimeError(f'Expected {expected} pages, found {len(pages)}. Remove stale generated pages or use a fresh destination.')
    audio=None
    if any(x['codec_type']=='audio' for x in probe['streams']):
        audio=target/'audio.ogg'
        run([TOOLS/'ffmpeg.exe','-hide_banner','-loglevel','error','-i',source,'-vn','-c:a','libvorbis','-q:a','6','-y',audio])
    result={'id':name,'source':str(source),'source_size':[source_w,source_h], 'profile':profile,'fps':float(fps),'fps_ratio':str(fps),'frames':frames,'duration':frames/float(fps),'frame_size':[w,h],'columns':cols,'rows':rows,'sheet_size':[w*cols,h*rows],'frames_per_sheet':page_frames,'audio':str(audio.resolve()) if audio else None,'sheets':[{'path':str(p.resolve()),'first_frame':n*page_frames,'frame_count':min(page_frames,frames-n*page_frames),'bytes':p.stat().st_size} for n,p in enumerate(pages)]}
    (target/'manifest.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({'manifest':str((target/'manifest.json').resolve()),'frames':frames,'pages':len(pages),'jpeg_bytes':sum(p.stat().st_size for p in pages),'audio_bytes':audio.stat().st_size if audio else 0}))

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source',choices=[*SOURCES,'all'],default='all')
    ap.add_argument('--profile',choices=['full','fit'],default='full')
    ap.add_argument('--sheet-edge',type=int,default=4096)
    ap.add_argument('--jpeg-q',type=int,default=2)
    ap.add_argument('--dest',type=Path,default=ROOT/'giorgio/media/generated')
    args=ap.parse_args()
    for name in SOURCES if args.source=='all' else [args.source]: build(name,args.profile,args.sheet_edge,args.jpeg_q,args.dest)
