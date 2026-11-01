from pathlib import Path
import json,re,hashlib
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent
OUT=HERE.parents[1]/'previews'
OUT.mkdir(exist_ok=True)
font=ImageFont.load_default()
def read(name,w,h):
    path=HERE/(name+'.rgb')
    raw=bytes.fromhex(''.join(path.read_text().split()))
    if len(raw)!=w*h*3:raise ValueError((name,len(raw),w*h*3))
    ppm=OUT/(name+'.ppm')
    ppm.write_bytes(f'P6\n{w} {h}\n255\n'.encode()+raw)
    im=Image.frombytes('RGB',(w,h),raw)
    im.save(OUT/(name+'.png'))
    return im
def grid(images,ncol,title,path,labels):
    w=max(im.width for im in images);h=max(im.height for im in images)
    canvas=Image.new('RGB',(ncol*(w+12)+12,46+((len(images)+ncol-1)//ncol)*(h+34)),(8,16,24))
    draw=ImageDraw.Draw(canvas)
    draw.text((12,10),title,font=font,fill=(230,235,240))
    draw.text((12,25),'Actual RTL pixels; synthetic background. Crop atlas uses forced S_x/S_y; not a camera photo.',font=font,fill=(160,180,190))
    for i,im in enumerate(images):
        x=12+(i%ncol)*(w+12);y=46+(i//ncol)*(h+34)
        draw.text((x,y),labels[i],font=font,fill=(225,230,240))
        canvas.paste(im,(x,y+18))
    canvas.save(OUT/path)
frames={}
for scene in (0,1):
    for variant in ('baseline','new'):
        frames[(variant,scene)]=read(f'{variant}_frame_{scene}',1280,720)
crop=(844,44,1220,292)
comparisons=[];labels=[]
for scene,desc in [(0,'bright'),(1,'dark / motion OFF')]:
    for variant in ('baseline','new'):
        comparisons.append(frames[(variant,scene)].crop(crop).resize((752,496),Image.Resampling.NEAREST))
        labels.append(f'{variant.upper()} - {desc}; 2x nearest crop from full streaming frame')
grid(comparisons,2,'Old 16x32 ASCII vs compact 16x16 Chinese OSD: true stream simulation','osd_before_after_rtl.png',labels)
mode_images=[read(f'crop_0_{i}',336,128) for i in range(19)]
grid(mode_images,3,'19 algorithm names: compact Chinese OSD RTL output','osd_19_modes_rtl.png',[f'mode={i}' for i in range(19)])
pcb_images=[read(f'crop_1_{i}',288,96).resize((576,192),Image.Resampling.NEAREST) for i in range(8)]
grid(pcb_images,2,'All 8 PCB states: 2x nearest RTL bitmap crops','osd_8_pcb_states_rtl.png',[f'PCB status={i}' for i in range(8)])
motion_images=[read(f'crop_2_{i}',336,128).resize((672,256),Image.Resampling.NEAREST) for i in range(2)]
grid(motion_images,2,'Motion row enable: 2x nearest RTL bitmap crops','osd_motion_gate_rtl.png',['motion enable=0','motion enable=1'])
log=(HERE/'simulation.log').read_text()
match=re.search(r'TB_MIXER_REGRESSION_PASS frames=(\d+) stream_pixels=(\d+) outside_rgb_compared=(\d+) crops=(\d+)',log)
if not match:raise ValueError('missing final PASS marker')
meta=re.search(r'metadata_checks=(\d+)',log)
result={'status':'PASS','frames':int(match[1]),'stream_pixels':int(match[2]),'outside_rgb_compared':int(match[3]),'crops':int(match[4]),'metadata_checks':int(meta[1]) if meta else None,'camera_photos':False,'full_frames_forced_coordinates':False,'atlas_forced_coordinates':True,'source':'Actual hdmi_mixer O_hdmi_data; all OSD glyph pixels from RTL font ROM','previews':{p.name:hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in OUT.glob('*_rtl.png')}}
(HERE/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
