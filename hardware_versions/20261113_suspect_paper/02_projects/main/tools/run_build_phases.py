"""Run fresh synthesis/place/route sequentially; never generates a bit."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, re, subprocess, sys

BUILD=Path('E:/codex_pcb_suspect_center_main_20261113_r1')
RUN=BUILD/'01_rtl/imgq_gain_m/main/td_project_display_noise_v8'
TD=Path('E:/td/bin/td_commands_prompt.exe')
NAME='camera_to_dsi_display_720p60_cnn_multibox'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def stamp():return datetime.now(timezone.utc).isoformat()
def write(p,obj):p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def validate():
    manifest=json.loads((BUILD/'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
    bad=[rel for rel,r in manifest['files'].items() if not (BUILD/rel).is_file() or sha(BUILD/rel)!=r['sha256']]
    if bad:raise RuntimeError('Frozen input mismatch: '+str(bad))

logs=BUILD/'logs';logs.mkdir(exist_ok=True)
for phase,marker in [('synth','opt_gate'),('place','opt_place'),('route','opt_route')]:
    validate()
    script=RUN/f'run_display_noise_{phase}.tcl';log=logs/f'{phase}.log'
    if log.exists():raise RuntimeError('Refusing existing phase log: '+str(log))
    record={'phase':phase,'started_utc':stamp(),'command':[str(TD),script.name],
        'cwd':str(RUN),'source_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),
        'runner_sha256':sha(Path(__file__)),'script_sha256':sha(script),'td_sha256':sha(TD)}
    write(logs/'CURRENT.json',dict(record,status='RUNNING'))
    print('START '+phase+' '+stamp(),flush=True)
    with log.open('wb') as f:cp=subprocess.run([str(TD),script.name],cwd=RUN,stdout=f,stderr=subprocess.STDOUT)
    text=log.read_text(encoding='utf-8',errors='replace')
    errors=[s for s in text.splitlines() if re.search(r'\b(?:ERROR|FATAL)\b|\bBUILD_FAILED\b|\bMAPPING_ERROR\b|HDL-5105',s)]
    record.update(ended_utc=stamp(),returncode=cp.returncode,errors=errors,log_sha256=sha(log),
        completion_marker=(RUN/f'.{marker}.end.f').is_file())
    record['passed']=not errors and cp.returncode==0 and record['completion_marker']
    write(logs/f'{phase}.json',record);write(logs/'CURRENT.json',dict(record,status='COMPLETE' if record['passed'] else 'FAILED'))
    print('END '+phase+' '+str(record['passed'])+' '+stamp(),flush=True)
    validate()
    if not record['passed']:sys.exit(1)
print('FRESH_SYNTH_PLACE_ROUTE_COMPLETE',flush=True)
