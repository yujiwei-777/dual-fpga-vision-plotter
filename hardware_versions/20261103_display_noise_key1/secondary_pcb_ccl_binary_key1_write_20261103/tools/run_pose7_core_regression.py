"""Prepare/run one ModelSim pose7 regression. No TD or source mutation.

Default only prepares a fresh run directory. Use --run to invoke ModelSim.
The caller must ensure no other vsim is running.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT=Path(__file__).resolve().parents[1]


def save(path, value):
    path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='store_true')
    parser.add_argument('--sim',type=Path,default=Path('E:/model/win64/vsim.exe'))
    parser.add_argument('--design',type=Path,default=ROOT,help='Frozen production RTL/model root; test helpers remain here')
    args=parser.parse_args()
    design=args.design.resolve()
    manifest=design/'SOURCE_MANIFEST.json'
    frozen=json.loads(manifest.read_text(encoding='utf-8'))['files'] if manifest.is_file() else None
    if frozen is not None:
        assert all(digest(design/name)==row['sha256'] for name,row in frozen.items()),'Frozen source drift'
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    run=ROOT/'reports/pose7/core_regression'/('run_'+stamp)
    run.mkdir(parents=True,exist_ok=False)
    model=design/'model/pose7_96x96';vectors=ROOT/'reports/pose7/vectors'
    index=json.loads((vectors/'INDEX.json').read_text(encoding='utf-8'))
    paths={'WEIGHTS_PATH':'weights.mem','BIASES_PATH':'biases.mem','CENTRE_PATH':'feature_centre.mem',
           'TOLERANCE_PATH':'feature_tolerance.mem','ORIENTATION_PATH':'orientation_reference.mem'}
    (run/'pose7_paths.svh').write_text(''.join(f'localparam {name}="{(model/file).as_posix()}";\n' for name,file in paths.items()),encoding='ascii')
    calls=[]
    for row in index['vectors']:
        st={'PASS':0,'FAIL':1,'REVIEW':2}[row['decision']]
        args_roi=[int(row['flip180']),*row['thumb_means'],*row['orientation_costs'],row['score'],*row['peak_xy'],st]
        calls.append(f'run_roi("{row["name"]}",'+','.join(map(str,args_roi))+');\n')
    for row in index['threshold_vectors']:
        st={'PASS':0,'FAIL':1,'REVIEW':2}[row['decision']]
        calls.append('run_head('+','.join(map(str,[row['score'],st,*row['peak_xy']]))+');\n')
    (run/'pose7_case_calls.svh').write_text(''.join(calls),encoding='ascii')
    core=design/'01_rtl/pcb_pose7_core.v';tb=ROOT/'reports/pose7/tb_pose7_core.sv'
    do='\n'.join(['onerror {quit -code 2}','onbreak {quit -code 3}','vlib work',
        f'vlog -sv +incdir+{run.as_posix()} "{core.as_posix()}" "{tb.as_posix()}"',
        f'vsim -voptargs=+acc work.tb_pose7_core +VECTORS={vectors.as_posix()}',
        'run -all','quit -code 0',''])
    (run/'run.do').write_text(do,encoding='ascii')
    pins={str(p):digest(p) for p in [core,tb,Path(__file__),vectors/'SHA256.json',*list(model.glob('*.mem'))]}
    save(run/'SOURCE_SHA256.json',pins)
    result={'status':'PREPARED','run_directory':str(run),'command':[str(args.sim),'-batch','-syncio','-do','run.do'],
            'working_directory':str(run),'RTL':'NOT_RUN','hardware':'NOT_RUN',
            'design':str(design),'source_manifest_sha256':digest(manifest) if manifest.is_file() else None}
    if args.run:
        env=dict(os.environ);env['LM_LICENSE_FILE']='E:/model/win64/LICENSE.TXT';env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']
        with (run/'SIM.log').open('w',encoding='utf-8') as log:
            proc=subprocess.run(result['command'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
        log=(run/'SIM.log').read_text(encoding='utf-8',errors='replace')
        passed=proc.returncode==0 and 'POSE7_CORE_REGRESSION_PASS' in log and 'POSE7_FAIL' not in log and not re.search(r'\*\*\s+(Error|Fatal):',log)
        result.update({'status':'PASS' if passed else 'FAIL','returncode':proc.returncode,'RTL':'PASS' if passed else 'FAIL',
            'ROI_cases_passed':log.count('POSE7_ROI_PASS'),'head_cases_passed':log.count('POSE7_HEAD_PASS'),
            'safety_cases_passed':log.count('POSE7_SAFETY_PASS')})
        result['sources_unchanged']=all(digest(Path(p))==h for p,h in pins.items())
        if not result['sources_unchanged']:result['status']='FAIL_SOURCE_DRIFT'
        if frozen is not None:
            result['frozen_sources_unchanged']=all(digest(design/name)==row['sha256'] for name,row in frozen.items())
            if not result['frozen_sources_unchanged']:result['status']='FAIL_SOURCE_DRIFT'
        result['latency_records']=re.findall(r'POSE7_ROI_PASS[^\r\n]*',log)
    save(run/'RESULTS.json',result)
    print(json.dumps(result,indent=2,ensure_ascii=False))
    if result['status'].startswith('FAIL'):raise SystemExit(1)


if __name__=='__main__':main()
