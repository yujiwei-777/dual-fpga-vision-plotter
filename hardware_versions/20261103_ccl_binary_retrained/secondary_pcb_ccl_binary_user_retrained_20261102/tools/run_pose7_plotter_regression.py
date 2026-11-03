"""Prepare/run inherited shared plotter transport unit regression, no TD."""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import hashlib,json,os
from pathlib import Path
import subprocess,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',action='store_true')
    parser.add_argument('--sim',type=Path,default=Path('E:/model/win64/vsim.exe'));args=parser.parse_args()
    run=ROOT/'reports/pose7/plotter_regression'/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    run.mkdir(parents=True,exist_ok=False)
    files=[ROOT/'01_rtl'/name for name in ['grbl_line_formatter.v','grbl_response_parser.v','grbl_shared_transport_candidate.v']]
    files.append(ROOT/'reports/pose7/tb_pose7_plotter.sv')
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
    pins={str(p):digest(p) for p in [*files,Path(__file__)]}
    (run/'SOURCE_SHA256.json').write_text(json.dumps(pins,indent=2)+'\n',encoding='utf-8')
    do='\n'.join(['onerror {quit -code 2}','onbreak {quit -code 3}','vlib work',
        'vlog -sv '+' '.join('"'+p.as_posix()+'"' for p in files),
        'vsim -voptargs=+acc work.tb_pose7_plotter','run -all','quit -code 0',''])
    (run/'run.do').write_text(do,encoding='ascii')
    result={'status':'PREPARED','command':[str(args.sim),'-batch','-syncio','-do','run.do'],
        'working_directory':str(run),'network_HXA_integration':'NOT_RUN','hardware':'NOT_RUN'}
    if args.run:
        env=dict(os.environ);env['LM_LICENSE_FILE']='E:/model/win64/LICENSE.TXT';env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']
        with (run/'SIM.log').open('w',encoding='utf-8') as log:
            process=subprocess.run(result['command'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
        log=(run/'SIM.log').read_text(encoding='utf-8',errors='replace')
        passed=process.returncode==0 and 'POSE7_PLOTTER_REGRESSION_PASS' in log and 'PLOTTER_FAIL' not in log and '** Error' not in log
        result.update({'status':'PASS' if passed else 'FAIL','returncode':process.returncode,
                       'cases_passed':log.count('PLOTTER_CASE_PASS'),'sources_unchanged':all(digest(Path(p))==h for p,h in pins.items())})
        if not result['sources_unchanged']:result['status']='FAIL_SOURCE_DRIFT'
    (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
    if result['status'].startswith('FAIL'):raise SystemExit(1)


if __name__=='__main__':main()
