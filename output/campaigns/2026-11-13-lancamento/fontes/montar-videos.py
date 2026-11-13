from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / 'audio/virajingle-jingle-27s.m4a'
def run(args):
    subprocess.run(['ffmpeg', '-y', '-v', 'error', *map(str,args)], check=True)

scenes = [ROOT/'video/cenas'/name for name in ['01-abertura.png','02-lojas.png','03-vitrine.png','04-servicos.png','05-como-funciona.png','06-crie-sua-campanha.png']]
durations = [4.3,4.3,4.3,4.3,6.3,5.0]
inputs=[]
filters=[]
for i,(scene,duration) in enumerate(zip(scenes,durations)):
    inputs += ['-loop','1','-framerate','30','-threads','1','-i',scene]
    frames=round(duration*30)
    filters.append(f"[{i}:v]scale=2160:3840,zoompan=z='1.0+0.025*on/{frames}':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1080x1920:fps=30,trim=duration={duration},setpts=PTS-STARTPTS,fps=30,settb=AVTB,setsar=1,format=yuv420p[s{i}]")
previous='s0'
for i,offset in enumerate([4,8,12,16,22],1):
    filters.append(f'[{previous}][s{i}]xfade=transition=fade:duration=0.3:offset={offset},fps=30,settb=AVTB[m{i}]')
    previous=f'm{i}'
filters.append('[6:a]asplit=2[aout][awave]')
filters.append('[awave]showwaves=s=720x70:mode=cline:rate=30:colors=0xc1f66b:scale=sqrt:draw=full,format=rgba[wave]')
filters.append(f'[{previous}][wave]overlay=x=180:y=1735:shortest=1,format=yuv420p[video]')
master=ROOT/'video/virajingle-apresentacao-27s.mp4'
run([*inputs,'-i',AUDIO,'-filter_complex_threads','1','-filter_complex',';'.join(filters),'-map','[video]','-map','[aout]','-t','27','-c:v','libx264','-preset','veryfast','-crf','19','-threads','2','-c:a','aac','-b:a','192k','-movflags','+faststart',master])
print('Vídeo de apresentação exportado.',flush=True)
story_specs=[('01-sua-loja-tem-refrao',0,8),('02-da-vitrine-para-o-play',8,10),('03-campanha-completa',18,9)]
for name,start,duration in story_specs:
    frames=round(duration*30)
    vf=f"scale=2160:3840,zoompan=z='1.0+0.018*on/{frames}':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1080x1920:fps=30,format=yuv420p"
    run(['-loop','1','-framerate','30','-threads','1','-i',ROOT/f'stories/{name}.png','-ss',start,'-i',AUDIO,'-vf',vf,'-map','0:v:0','-map','1:a:0','-t',duration,'-c:v','libx264','-preset','veryfast','-crf','19','-threads','2','-c:a','aac','-b:a','192k','-movflags','+faststart',ROOT/f'stories/{name}.mp4'])
    print(f'Story {name} exportado.',flush=True)
metadata=[]
for file in [master,*[ROOT/f'stories/{name}.mp4' for name,_,_ in story_specs]]:
    result=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration,size:stream=codec_name,width,height,pix_fmt,sample_rate,channels','-of','json',str(file)],capture_output=True,text=True,check=True)
    metadata.append({'file':str(file.relative_to(ROOT)),**json.loads(result.stdout)})
(ROOT/'fontes/verificacao-videos.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2))
print('Arquivos de vídeo conferidos.',flush=True)
