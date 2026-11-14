"""Wait for this exact build, then perform strict audits and staged bitgen."""
from pathlib import Path
from datetime import datetime,timezone
import json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_pcb_suspect_center_main_20261113_r3')
def stamp():return datetime.now(timezone.utc).isoformat()
def put(obj):
    (ROOT/'reports/COMPLETION_R3.json').write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
state={'status':'WAITING_FOR_FRESH_BUILD','build':str(BUILD),'started_utc':stamp(),'hardware_status':'NOT_RUN'}
put(state)
while True:
    current=json.loads((BUILD/'logs/CURRENT.json').read_text(encoding='utf-8'))
    if current.get('status')=='FAILED':
        state.update(status='BUILD_FAILED',phase=current.get('phase'),errors=current.get('errors'),ended_utc=stamp())
        put(state);print(json.dumps(state),flush=True);sys.exit(1)
    if current.get('phase')=='route' and current.get('status')=='COMPLETE':break
    time.sleep(5)

commands=[('AUDIT',[sys.executable,'-B',str(ROOT/'tools/audit_current_route_r3.py'),'--attempt','r1']),
    ('BITGEN',[sys.executable,'-B',str(ROOT/'tools/bitgen_current_r3.py'),
      '--acceptance',str(BUILD/'audits/route_acceptance_r1/CURRENT_ROUTE_ACCEPTANCE.json'),
      '--center-result',str(ROOT/'reports/center_integration/20261113T133115_864371Z/RESULT.json'),
      '--controls-result',str(ROOT/'reports/regression_controls/20261113T133115_864371Z/RESULT.json'),
      '--control-integrity',str(ROOT/'reports/CONTROL_INPUT_INTEGRITY_R3.json'),'--attempt','r1'])]
for phase,cmd in commands:
    state.update(status='RUNNING_'+phase,phase_started_utc=stamp());put(state)
    print('START '+phase+' '+stamp(),flush=True)
    log=ROOT/'reports'/('r3_'+phase.lower()+'_launcher.log')
    with log.open('xb') as f:cp=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    if cp.returncode:
        state.update(status=phase+'_FAILED',returncode=cp.returncode,log=str(log),ended_utc=stamp())
        put(state);print(json.dumps(state),flush=True);sys.exit(1)
release=json.loads((ROOT/'artifacts/RELEASE_REPORT.json').read_text(encoding='utf-8'))
assert release['status']=='PASS_DIAGNOSTIC_NOT_RUN'
state.update(status='PASS_DIAGNOSTIC_NOT_RUN',bit=release['bit'],resources=release['resources'],
    timing_ns=release['timing_ns'],ended_utc=stamp(),release_report=str(ROOT/'artifacts/RELEASE_REPORT.json'))
put(state)
(BUILD/'FINAL_RELEASE.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(state,ensure_ascii=False),flush=True)
