"""Replay frozen document fixtures using the current variant's RTL.

The integrated path uses the unchanged document generator/plotter and current
ROM mapper. Shared transport policy has its separate 13-scenario regression.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
CONTROL=ROOT.parent/'secondary_doc_dirt_lowconf_factored_20261101'
SIM=Path('E:/model/win64')


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--design',type=Path,default=ROOT,help='Read-only production/frozen RTL root')
    args=parser.parse_args()
    design=args.design.resolve()
    manifest=design/'SOURCE_MANIFEST.json'
    if manifest.is_file():
        frozen=json.loads(manifest.read_text(encoding='utf-8'))['files']
        assert all(sha(design/name)==row['sha256'] for name,row in frozen.items()),'Frozen source manifest drift'
    out=Path('E:/')/('codex_pose7_document_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    out.mkdir()
    origin=CONTROL/'reports/dirt_qualification'
    shutil.copytree(origin/'fixtures',out/'fixtures')
    for name in ['tb_frontend.sv','tb_capture_integrated.sv']:
        shutil.copyfile(origin/'source'/name,out/name)
    shutil.copyfile(CONTROL/'02_sim/testmodels/ph1p_logic_eram_stub.sv',out/'ph1p_logic_eram_stub.sv')
    names=['doc_image_frontend.v','doc_stroke_planner.v','doc_stroke_bram.v','doc_machine_map.v',
           'doc_grbl_plotter.v','doc_grbl_map.v','doc_grbl_streamer.v','doc_grbl_response_parser.v',
           # grbl_line_formatter.v also defines grbl_decimal; there is no
           # separate grbl_decimal.v in this frozen production layout.
           'grbl_line_formatter.v']
    sources=[design/'01_rtl'/n for n in names]
    assert all(path.is_file() for path in sources),'Missing regression RTL dependency'
    inputs=sources+list((out/'fixtures').rglob('*'))+[out/'tb_frontend.sv',out/'tb_capture_integrated.sv',out/'ph1p_logic_eram_stub.sv']
    pins={str(p):sha(p) for p in inputs if p.is_file()}
    env=os.environ.copy()
    env.update(LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    rows=[]

    def run(label,cmd,cwd=out,marker=None):
        log=out/(label+'.log')
        with log.open('w') as f:cp=subprocess.run(cmd,cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT)
        text=log.read_text(errors='replace')
        passed=cp.returncode==0 and not re.search(r'\*\*\s+(Error|Fatal):',text) and (not marker or marker in text)
        rows.append({'name':label,'status':'PASS' if passed else 'FAIL','log':str(log),'sha256':sha(log)})
        assert passed,(label,str(log),text[-3000:])
        print('PASS '+label,flush=True)

    run('frontend_vlib',[str(SIM/'vlib.exe'),'front_lib'])
    run('frontend_lint',[str(SIM/'vlog.exe'),'-sv','-lint','-work','front_lib',str(sources[0]),str(out/'tb_frontend.sv')])
    for fixture in sorted((out/'fixtures').iterdir()):
        run('frontend_'+fixture.name,[str(SIM/'vsim.exe'),'-batch','-syncio','-lib','front_lib','tb_frontend',
            '+IMAGE='+(fixture/'source_y.mem').as_posix(),'+EXPECTED='+(fixture/'expected_binary.mem').as_posix(),
            '+OUTPUT='+(out/(fixture.name+'_binary.mem')).as_posix(),'+CASE='+fixture.name,
            '-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -code 0'],marker='PASS FRONTEND')
    for case in ['blank2418','ink2358']:
        fixture=out/'fixtures'/case
        lib=out/(case+'_lib')
        run(case+'_vlib',[str(SIM/'vlib.exe'),str(lib)])
        run(case+'_lint',[str(SIM/'vlog.exe'),'-sv','-lint','-work',str(lib),'+incdir+'+fixture.as_posix(),
            *map(str,sources),str(out/'ph1p_logic_eram_stub.sv'),str(out/'tb_capture_integrated.sv')])
        # ModelSim -lib takes a logical library name, not an absolute path.
        # Load from the parent CWD, then enter the fixture before time zero so
        # relative MEM inputs/G-code outputs retain the original bench contract.
        run(case+'_integrated',[str(SIM/'vsim.exe'),'-batch','-syncio','-lib',case+'_lib','tb_stroke_split',
            '-do','onerror {quit -code 1}; onbreak {quit -code 2}; cd {'+fixture.as_posix()+'}; run -all; quit -code 0'],marker='PASS CAPTURE_INTEGRATED')
        expected=(fixture/'expected_gcode.txt').read_text().splitlines()
        actual=(fixture/'gcode.txt').read_text().splitlines()
        assert actual==expected,(case,'G-code differs',len(actual),len(expected))
    assert all(sha(p)==h for p,h in pins.items()),'Input drift'
    result={'status':'PASS','output':str(out),'rows':rows,'input_hashes':pins,
            'design':str(design),'source_manifest_sha256':sha(manifest) if manifest.is_file() else None,
            'scope':'Six frontend full-frame fixtures plus two captured-frame frontend/skeleton/paths/machine-coordinate/G-code comparisons. Actual shared transport is covered separately.',
            'hardware':'NOT_RUN'}
    (out/'RESULTS.json').write_text(json.dumps(result,indent=2))
    (ROOT/'reports/pose7/DOCUMENT_REGRESSION.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k not in ['rows','input_hashes']},indent=2))


if __name__=='__main__':main()
