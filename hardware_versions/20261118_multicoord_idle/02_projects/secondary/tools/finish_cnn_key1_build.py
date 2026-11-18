"""Wait for the read-only physical check, then run the normal release gates."""
from pathlib import Path
import json, subprocess, sys, time
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_secondary_plotter_idle_preflight_20261118_r2')
GATE=ROOT/'reports/airwalk_signoff'/BUILD.name/'FUNCTIONAL_GATE.json'
physical=ROOT/'reports/airwalk_signoff'/BUILD.name/'IMPLEMENTATION_SIGNOFF.json'
while not physical.is_file():
    for phase in ('syn','place','route'):
        p=BUILD/'logs'/(phase+'.json')
        if p.is_file():assert json.loads(p.read_text())['status']!='FAILED_TOOL_INVOCATION',str(p)
    time.sleep(2)
assert json.loads(physical.read_text())['status']=='PASS_CURRENT_IMPLEMENTATION_SIGNOFF'
for label,cmd in [
 ('prebitgen',[str(ROOT/'tools/signoff_airwalk.py'),'prebitgen','--gate',str(GATE)]),
 ('bitgen',[str(ROOT/'tools/signoff_airwalk.py'),'bitgen','--gate',str(GATE)]),
 ('finalize',[str(ROOT/'tools/finalize_cnn_key1.py')]),
]:
    log=ROOT/'reports'/('live_release_'+label+'.log')
    with log.open('xb') as stream:
        cp=subprocess.run([sys.executable,'-B',*cmd],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
    print(label,cp.returncode,str(log),flush=True)
    if cp.returncode:raise SystemExit(cp.returncode)
