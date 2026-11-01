"""Frozen-input frontend and captured-YUYV-to-G-code regression for this root.

--prepare writes immutable qualification inputs only, before build preparation.
--run writes logs/results only under 02_sim/doc_dirt_frontend and compiles this
project's 01_rtl files. It never compiles the earlier diagnostic frontend.
"""
from __future__ import annotations
import argparse
import ast
from datetime import datetime,timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
sys.dont_write_bytecode=True
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
QUAL=ROOT/'reports/dirt_qualification'
SOURCE=QUAL/'source'
OUTPUT=ROOT/'02_sim/doc_dirt_frontend'
SIM=Path('E:/model/win64')
OLD=ROOT.parent/'doc_fixed_dirt_compensation_20261101'
BACKEND_NAMES=('doc_stroke_planner.v','doc_stroke_bram.v','doc_path_distance.v',
    'doc_machine_map.v','doc_grbl_plotter.v','doc_grbl_map.v','doc_grbl_streamer.v',
    'doc_grbl_response_parser.v','grbl_line_formatter.v')

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()
def write_json(path,data):Path(path).write_text(json.dumps(data,indent=2),encoding='utf-8')
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module
    spec.loader.exec_module(module);return module

def modules():
    ref=load('doc_dirt_reference',SOURCE/'fixed_dirt_reference.py')
    # Copy of earlier helper functions is a frozen qualification input, while
    # the production stroke reference/suite is loaded from this project root.
    helpers=load('doc_dirt_fixture_reference',SOURCE/'fixture_reference.py')
    helpers.ref=ref
    suite=load('doc_dirt_backend_reference',ROOT/'tools/run_stroke_split_regression.py')
    return ref,helpers,suite

def prepare():
    marker=QUAL/'PREPARED_INPUTS.json'
    assert not marker.exists(),'Qualification inputs already frozen; do not overwrite them.'
    SOURCE.mkdir(parents=True,exist_ok=True);OUTPUT.mkdir(parents=True,exist_ok=True)
    old_runner=SOURCE/'candidate_runner_provenance.py'
    tree=ast.parse(old_runner.read_text(encoding='utf-8'))
    helpers=[node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name in ('golden','fixtures')]
    assert {node.name for node in helpers}=={'golden','fixtures'}
    (SOURCE/'fixture_reference.py').write_text('"""Frozen integer count/reference and synthetic fixtures; ref injected by runner."""\nimport numpy as np\n\n'+
        '\n\n'.join(ast.unparse(node) for node in helpers)+'\n',encoding='utf-8')
    ref,helpers,suite=modules()
    raw={}
    for name,pattern in [('blank2418','*00002418*.yuyv'),('ink2358','*00002358*.yuyv')]:
        matches=list(Path('D:/ai/1/6').rglob(pattern));assert len(matches)==1
        raw[name]={'path':str(matches[0]),'sha256':sha(matches[0])}
    cases={name:ref.load_y(record['path']) for name,record in raw.items()}
    cases.update(helpers.fixtures())
    manifest={'root':str(ROOT),'status':'PREPARED','hardware_status':'NOT_RUN',
        'compile_policy':'Frontend and all backend RTL compile only from this root/01_rtl.',
        'captures':raw,'frontend_cases':{},'integrated_cases':{},'source_provenance':{}}
    for name,y in cases.items():
        fixture=QUAL/'fixtures'/name;fixture.mkdir(parents=True,exist_ok=False)
        image=helpers.golden(y)
        (fixture/'source_y.mem').write_text(''.join(f'{int(v):02x}\n' for v in y.ravel()),encoding='ascii')
        (fixture/'expected_binary.mem').write_text(''.join(f'{int(v)}\n' for v in image.ravel()),encoding='ascii')
        assert np.array_equal(image,ref.canvas(y))
        if name=='blank2418':assert image.sum()==0
        if name=='ink2358':assert image.sum()==1148
        manifest['frontend_cases'][name]={'fixture':str(fixture.relative_to(ROOT)),
            'foreground':int(image.sum()),'output_bits':102400,'source_requests':ref.EXPECTED_READS}
        if name not in raw:continue
        golden=suite.ref.prepare(image,plan_passes=0)
        for file,array in (('input.mem',image),('skeleton.mem',golden['skeleton'])):
            (fixture/file).write_text(''.join(f'{int(v):x}\n' for v in array.ravel()),encoding='ascii')
        stream=golden['stream'];lines=suite.gcode(stream)
        (fixture/'expected.mem').write_text(''.join(f'{x|(yy<<9)|(s<<18)|(e<<19)|(d<<20):06x}\n' for x,yy,s,e,d in stream),encoding='ascii')
        (fixture/'expected_gcode.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
        constants={key.upper():golden[key] for key in ('edge_count','path_count','point_count','baseline_distance','planned_distance')}
        constants.update(OPT_PASSES=0,LIMIT_EDGES=32768,LIMIT_PATHS=2048,LIMIT_POINTS=8192,
            EXPECT_ERROR=0,GCODE_LINES=len(lines),SOURCE_REQUESTS=ref.EXPECTED_READS)
        (fixture/'expected.vh').write_text('\n'.join(f'localparam {k}={v};' for k,v in constants.items())+'\n',encoding='ascii')
        write_json(fixture/'expected_strokes.json',[{'points':list(stroke.points),'closed':stroke.closed} for stroke in golden['strokes']])
        write_json(fixture/'expected_coordinates.json',[{'grid':[x,yy],'pre_mirror_cmm':list(suite.ref.machine((x,yy))),
            'machine_cmm':[21000-suite.ref.machine((x,yy))[0],suite.ref.machine((x,yy))[1]],
            'start':s,'end':e,'dot':d} for x,yy,s,e,d in stream])
        manifest['integrated_cases'][name]={'fixture':str(fixture.relative_to(ROOT)),
            'paths':golden['path_count'],'points':golden['point_count'],'edges':golden['edge_count'],
            'gcode_lines':len(lines),'source_requests':ref.EXPECTED_READS,'foreground':int(image.sum()),
            'canvas_bits_checked':102400,'skeleton_bits_checked':57600}
    # Preserve earlier passing source and evidence without executing them.
    provenance=QUAL/'provenance';provenance.mkdir(exist_ok=False)
    old_files=[OLD/'candidate_frontend/doc_image_frontend.v',OLD/'candidate_frontend/RESULTS.json',
        OLD/'candidate_frontend/README.md',OLD/'candidate_frontend/simulation/compile.log',
        OLD/'candidate_frontend/simulation/blank2418.log',OLD/'candidate_frontend/simulation/ink2358.log',
        OLD/'candidate_frontend/simulation/lifecycle.log',OLD/'candidate_frontend/simulation/timeout.log',
        OLD/'run_capture_gcode_rtl.py',OLD/'fixed_ink_reference.py']
    for index,path in enumerate(old_files):
        target=provenance/(f'{index:02d}_'+path.name);shutil.copyfile(path,target)
        manifest['source_provenance'][str(target.relative_to(ROOT))]={'original':str(path),'sha256':sha(path)}
    (QUAL/'README.md').write_text('''# Frozen document dirt qualification inputs

These inputs belong to `PROJECT_ROOT_NAME`. The regression compiles
`01_rtl/doc_image_frontend.v` and every backend from this root. Earlier
diagnostic source/evidence is retained under `provenance/` for origin only;
it is never an RTL compilation input.

The independent count model and min2 model agree on every fixture. Captured
Y comes from two read-only 1280x720 YUYV files; no RGB-luma conversion is used.
The production integer stroke reference generates skeleton, raw paths,
planned points, mirrored A4 machine coordinates and expected G-code.

Run `python tools/run_doc_dirt_regression.py --run` after these files have
been frozen. Commands, source/fixture/output hashes and RESULTS are written
only under `02_sim/doc_dirt_frontend`. The peer simulates GRBL responses;
physical camera/plotter acceptance remains NOT_RUN. No accuracy claim is
made without pixel labels; broad dark interiors inside the calibrated ROI
may be suppressed and strong shade boundaries may remain. No TD build is
started by this regression.
'''.replace('PROJECT_ROOT_NAME',ROOT.name),encoding='utf-8')
    source_inputs=[Path(__file__),ROOT/'01_rtl/doc_image_frontend.v',*[ROOT/'01_rtl'/name for name in BACKEND_NAMES],
        ROOT/'01_rtl/doc_copy_pipeline.v',ROOT/'model/doc_stroke_reference.py',ROOT/'tools/run_stroke_split_regression.py']
    manifest['source_sha256']={str(path.relative_to(ROOT)):sha(path) for path in source_inputs}
    manifest['fixture_sha256']={str(path.relative_to(ROOT)):sha(path) for path in QUAL.rglob('*') if path.is_file()}
    write_json(marker,manifest)
    print('PREPARED '+str(marker),flush=True)

def run():
    marker=QUAL/'PREPARED_INPUTS.json';manifest=json.loads(marker.read_text(encoding='utf-8'))
    def verify():
        for group in ('source_sha256','fixture_sha256'):
            for path,digest in manifest[group].items():assert sha(ROOT/path)==digest,'Frozen input drift: '+path
        for record in manifest['captures'].values():assert sha(record['path'])==record['sha256'],'Raw capture drift'
    verify();OUTPUT.mkdir(parents=True,exist_ok=True)
    output=OUTPUT/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');output.mkdir(exist_ok=False)
    lic=SIM/'LICENSE.TXT';assert lic.is_file()
    env=os.environ.copy();env.update(MGLS_LICENSE_FILE=str(lic),LM_LICENSE_FILE=str(lic))
    def command(cwd,label,args,marker=None):
        began=time.time();cp=subprocess.run(list(map(str,args)),cwd=cwd,env=env,text=True,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        log=cwd/(label+'.log');log.write_text(cp.stdout,encoding='utf-8',errors='replace')
        write_json(cwd/(label+'_command.json'),{'argv':list(map(str,args)),'returncode':cp.returncode,
            'elapsed_seconds':round(time.time()-began,3),'log_sha256':sha(log)})
        assert cp.returncode==0 and not re.search(r'\*\*\s+(?:Error|Fatal):',cp.stdout),cp.stdout[-6000:]
        if marker:assert marker in cp.stdout,cp.stdout[-6000:]
        return re.findall(r'PASS[^\r\n]*',cp.stdout)
    front=ROOT/'01_rtl/doc_image_frontend.v';backend=[ROOT/'01_rtl'/name for name in BACKEND_NAMES]
    unit=output/'frontend';unit.mkdir()
    command(unit,'vlib',[SIM/'vlib.exe','simlib'])
    command(unit,'compile',[SIM/'vlog.exe','-sv','-lint','-work','simlib',front,SOURCE/'tb_frontend.sv',SOURCE/'tb_timeout.sv'])
    results={'frontend':{},'integrated':{}}
    for name,record in manifest['frontend_cases'].items():
        fixture=ROOT/record['fixture'];actual=unit/(name+'_actual.mem')
        checks=command(unit,name,[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','simlib','tb_frontend',
            '+IMAGE='+str(fixture/'source_y.mem'),'+EXPECTED='+str(fixture/'expected_binary.mem'),
            '+OUTPUT='+str(actual),'+CASE='+name,'-do','onerror {quit -code 1}; run -all; quit -f'],'PASS FRONTEND')
        values=actual.read_text().splitlines();assert len(values)==102400
        assert values==(fixture/'expected_binary.mem').read_text().splitlines()
        results['frontend'][name]={'status':'PASS',**record,'checks':checks,'actual_sha256':sha(actual)}
        print('FRONTEND '+name+': PASS',flush=True)
    fixture=ROOT/manifest['frontend_cases']['blank']['fixture'];actual=unit/'lifecycle_actual.mem'
    checks=command(unit,'lifecycle',[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','simlib','tb_frontend',
        '+IMAGE='+str(fixture/'source_y.mem'),'+EXPECTED='+str(fixture/'expected_binary.mem'),
        '+OUTPUT='+str(actual),'+CASE=lifecycle','+LIFECYCLE=1',
        '-do','onerror {quit -code 1}; run -all; quit -f'],'PASS RESET_DIRTY_ROI_PENDING_AND_BLANK_REENTRY')
    values=actual.read_text().splitlines();assert len(values)==204800 and set(values)=={'0'}
    results['frontend']['lifecycle']={'status':'PASS','checks':checks,'output_bits':len(values),'actual_sha256':sha(actual)}
    results['frontend']['timeout']={'status':'PASS','checks':command(unit,'timeout',
        [SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','simlib','tb_timeout',
        '-do','onerror {quit -code 1}; run -all; quit -f'],'PASS TIMEOUT_PENDING_AND_CANCEL')}
    for name,record in manifest['integrated_cases'].items():
        fixture=ROOT/record['fixture'];cwd=output/('integrated_'+name);cwd.mkdir()
        for filename in ('source_y.mem','input.mem','skeleton.mem','expected.mem','expected.vh'):
            shutil.copyfile(fixture/filename,cwd/filename)
        command(cwd,'vlib',[SIM/'vlib.exe','work'])
        command(cwd,'compile',[SIM/'vlog.exe','-sv','-lint','+define+DOC_BEHAVIORAL_RAM',
            '-work','work',front,*backend,ROOT/'01_rtl/doc_copy_pipeline.v',SOURCE/'tb_capture_integrated.sv'])
        checks=command(cwd,'simulate',[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','work','tb_stroke_split',
            '-do','onerror {quit -code 1}; run -all; quit -f'],'PASS CAPTURE_INTEGRATED')
        actual=(cwd/'gcode.txt').read_text().splitlines();expected=(fixture/'expected_gcode.txt').read_text().splitlines()
        assert actual==expected,'G-code mismatch: '+name
        strokes=[];points=[]
        for row in (cwd/'raw_paths.txt').read_text().splitlines():
            tag,a,b=row.split()
            if tag=='POINT':points.append([int(a),int(b)])
            else:
                assert len(points)==int(b);strokes.append({'points':points,'closed':bool(int(a))});points=[]
        assert not points and strokes==json.loads((fixture/'expected_strokes.json').read_text()),'Path mismatch: '+name
        results['integrated'][name]={'status':'PASS',**record,'checks':checks,
            'gcode_sha256':sha(cwd/'gcode.txt'),'raw_paths_sha256':sha(cwd/'raw_paths.txt'),
            'pen_down_commands':sum(line=='G1 Z+005.00 F01200' for line in actual)}
        print('INTEGRATED '+name+': PASS '+str(record),flush=True)
    verify()
    summary={'status':'PASS','hardware_status':'NOT_RUN','project_root':str(ROOT),
        'compiled_frontend':str(front),'compiled_backend':list(map(str,backend)),
        'prepared_manifest_sha256':sha(marker),'prepared_source_sha256':manifest['source_sha256'],
        'fixture_sha256':manifest['fixture_sha256'],'tests':results,
        'scope':'Production-root RTL; standalone frontend/lifecycle and captured raw YUYV to planner/mapper/plotter/parser/streamer/G-code component chain.',
        'limitations':['Simulated GRBL peer; no physical plotter/camera acceptance.',
            'No pixel ground truth; exact replay is not handwriting accuracy.',
            'No synthesis, timing, DRC, reimport or bitgen is performed by this script.']}
    summary['output_sha256']={str(path.relative_to(output)):sha(path) for path in output.rglob('*')
        if path.is_file() and path.suffix in ('.log','.json','.txt','.mem') and 'work' not in path.parts and 'simlib' not in path.parts}
    write_json(output/'RESULTS.json',summary)
    write_json(OUTPUT/'LATEST.json',{'status':'PASS','results':str(output/'RESULTS.json'),'results_sha256':sha(output/'RESULTS.json')})
    print('PASS DOC DIRT REGRESSION '+str(output/'RESULTS.json'),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--prepare',action='store_true');mode.add_argument('--run',action='store_true')
    options=parser.parse_args()
    if options.prepare:prepare()
    else:run()
