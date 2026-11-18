"""Continue physical phases only after the current synthesis receipt passes."""
from pathlib import Path
import json, subprocess, sys, time
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_secondary_plotter_idle_preflight_20261118_r2')
receipt=BUILD/'logs/syn.json'
while True:
    if receipt.is_file():
        row=json.loads(receipt.read_text())
        if row['status']!='RUNNING':
            assert row['status']=='PASS_TOOL_INVOCATION',row
            break
    time.sleep(2)
for script,args in [
 ('build_airwalk.py',['secondary','place']),
 ('build_airwalk.py',['secondary','route']),
 ('signoff_airwalk.py',['route-gate']),
 ('signoff_airwalk.py',['readonly']),
]:
    log=ROOT/'reports'/('live_build_'+args[-1]+'.log')
    print('START',script,*args,flush=True)
    with log.open('xb') as stream:
        cp=subprocess.run([sys.executable,'-B',str(ROOT/'tools'/script),*args],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
    print('FINISH',*args,'exit',cp.returncode,'log',str(log),flush=True)
    if cp.returncode:raise SystemExit(cp.returncode)
