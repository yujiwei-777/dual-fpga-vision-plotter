from pathlib import Path
import re,json,hashlib
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
BASE=ROOT.parent/'main_osd_large_font_20261030'
REL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source')
RTL=ROOT/REL
OLD=BASE/REL
HERE.mkdir(parents=True,exist_ok=True)
source=(RTL/'hdmi_mixer.v').read_text(encoding='utf-8')
header=source.split(')(\n',1)[1].split(');',1)[0]
header=re.sub(r'//[^\n]*','',header)
direction=None
width=''
ports=[]
for part in header.split(','):
    part=part.strip()
    match=re.fullmatch(r'(input|output)\s+(?:(?:wire|reg)\s*)?(\[[^]]+\])?\s*(\w+)',part)
    if match:
        direction,width,name=match.groups();width=width or ''
    elif re.fullmatch(r'\w+',part):name=part
    else:raise ValueError(repr(part))
    ports.append((direction,width,name))
decl=[]
for direction,width,name in ports:
    if direction=='input':decl.append(f'reg {width} {name}=0;')
    else:decl.extend([f'wire {width} N_{name};',f'wire {width} B_{name};'])
(HERE/'signals.vh').write_text('\n'.join(decl)+'\n')
instances=[]
for prefix,mod in [('N','hdmi_mixer'),('B','hdmi_mixer_baseline')]:
    con=[f'.{name}({name if dr=="input" else prefix+"_"+name})' for dr,_,name in ports]
    instances.append(f'{mod} #(.LOGO_ENABLE(0),.LATENCY_OSD_ENABLE(1)) dut_{prefix}('+',\n'.join(con)+');')
(HERE/'instances.vh').write_text('\n'.join(instances)+'\n')
base=(OLD/'hdmi_mixer.v').read_text(encoding='utf-8').replace('module hdmi_mixer ','module hdmi_mixer_baseline ',1).replace('hxa_multibox_overlay #','hxa_multibox_overlay_baseline #')
(HERE/'hdmi_mixer_baseline.v').write_text(base,encoding='utf-8')
overlay=(OLD/'hxa_multibox_overlay.v').read_text(encoding='utf-8').replace('module hxa_multibox_overlay #','module hxa_multibox_overlay_baseline #',1)
(HERE/'hxa_multibox_overlay_baseline.v').write_text(overlay,encoding='utf-8')
files=[RTL/'hdmi_mixer.v',RTL/'osd_compact_panel.v',RTL/'osd_compact_font_rom.v',RTL/'osd_decimal_snapshot.v',RTL/'hxa_multibox_overlay.v',RTL/'doc_copy_overlay.v',OLD/'osd_large_font_rom.v',OLD/'osd_char_lib.v',OLD/'pcb_status_large_text.v',OLD/'pcb_status_text_rom.v',HERE/'hdmi_mixer_baseline.v',HERE/'hxa_multibox_overlay_baseline.v',HERE/'tb_mixer_regression.sv']
(HERE/'compile_sources.txt').write_text('\n'.join(str(p) for p in files)+'\n')
manifest={str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in files if p.exists()}
(HERE/'input_hashes.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('MIXER_HARNESS_READY ports=',len(ports))
