import json,subprocess,math
from pathlib import Path
out=Path('giorgio/media-reference')
ffmpeg=r'C:\Users\61415\AppData\Local\Potassium\tools\ffmpeg.exe'; ffprobe=r'C:\Users\61415\AppData\Local\Potassium\tools\ffprobe.exe'
items=json.loads((out/'inventory.json').read_text())[:3]
measure=[]
for item in items:
    p=item['path']
    probe=json.loads(subprocess.check_output([ffprobe,'-v','error','-select_streams','v:0','-count_frames','-show_entries','stream=nb_read_frames,nb_frames,avg_frame_rate','-of','json',p],text=True))['streams'][0]
    count=int(probe['nb_read_frames']); item['frames']=count
    configs=[(1920,1080,2,3),(960,540,4,7)] if item['index']!=3 else [(1600,1200,2,3),(800,600,5,6)]
    for w,h,cols,rows in configs:
        sizes=[]
        for n,f in enumerate([0.05,0.35,0.65,0.85]):
            t=float(item['duration'])*f;file=out/f"sample-{item['index']:02d}-{w}x{h}-{n}.jpg"
            vf=f'scale={w}:{h}:flags=lanczos,tile={cols}x{rows}'
            subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-ss',str(t),'-i',p,'-vf',vf,'-frames:v','1','-q:v','2','-y',str(file)],check=True)
            sizes.append(file.stat().st_size)
        pages=math.ceil(count/(cols*rows));mean=sum(sizes)/len(sizes)
        measure.append({'source':p,'frames':count,'frame_size':[w,h],'sheet_size':[w*cols,h*rows],'frames_per_sheet':cols*rows,'sheets':pages,'sample_sheet_jpeg_bytes':sizes,'estimated_complete_jpeg_bytes':round(mean*pages),'decoded_rgba_bytes_per_sheet':w*h*cols*rows*4,'decoded_rgba_bytes_all_sheets':w*h*cols*rows*4*pages,'three_sheet_ring_rgba_bytes':w*h*cols*rows*4*3})
(out/'fallback-estimates.json').write_text(json.dumps(measure,indent=2))
(out/'confirmed-media.json').write_text(json.dumps(items,indent=2))
print(json.dumps(measure,indent=2))
