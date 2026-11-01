"""Fresh exact-cycle RTL qualification for one frozen scratch CNN kernel.

Only functional/ is written. This self-contained template can be copied to
qualify another same-cadence candidate by pinning its own candidate hash and
directory; it never imports an optimization preparation routine.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent
ROOT = PARENT.parent
RELEASE = ROOT / 'secondary_cnn_key3_stroke_release_20261031'
TEMPLATE = ROOT / 'secondary_cnn_geometry_phase_scratch_20261031'
SIM = Path('E:/model/win64')
KERNEL_SHA = '8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C'
PIPELINE_SHA = '6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9'
CANDIDATE_SHA = '9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128'
PARAMS = ((1,0,1),(2,1,2),(3,2,3),(4,0,4),(15,15,15))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def put(path, text):
    with Path(path).open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(text)


def once(text, old, new):
    require(text.count(old) == 1, 'Ambiguous replacement ' + old)
    return text.replace(old, new)


def prepare():
    source = RELEASE / '01_rtl/cnn_result_stabilizer.v'
    pipeline_source = RELEASE / '01_rtl/vision_pipeline.v'
    candidate = PARENT / 'cnn_result_stabilizer.v'
    require(sha(source) == KERNEL_SHA, 'Frozen kernel drift')
    require(sha(pipeline_source) == PIPELINE_SHA, 'Frozen pipeline drift')
    require(sha(candidate) == CANDIDATE_SHA, 'Frozen candidate drift')
    old_manifest = TEMPLATE / 'PREPARATION.json'
    template = json.loads(old_manifest.read_text())
    copied = []
    for name in ('cnn_result_stabilizer.v',):
        target = HERE / name
        with target.open('xb') as stream:
            stream.write(candidate.read_bytes())
        copied.append({'source': str(candidate), 'target': str(target), 'sha256': sha(target)})
    put(HERE / 'cnn_result_stabilizer_baseline.v', once(source.read_text(),
        'module cnn_result_stabilizer #(', 'module cnn_result_stabilizer_baseline #('))
    names = ['vision_pipeline.v', 'vision_pipeline_baseline.v',
        'tb_fixed_grid_mapping_miter.sv', 'pipeline_leaf_stubs.sv',
        'tb_area_grid_equivalence.sv', 'generic_vectors.txt',
        'aligned_a20_s1.txt', 'aligned_a20_s19.txt', 'aligned_a22_s6.txt', 'aligned_a32_s31.txt',
        'tb_combined_state_lifecycle.sv', 'tb_cnn_stability_serial.sv', 'vectors.txt']
    names.extend(f'c{c}h{h}l{l}.txt' for c,h,l in PARAMS)
    for name in names:
        origin = TEMPLATE / name
        require(sha(origin) == template['inputs_sha256'][name], 'Template drift ' + name)
        target = HERE / name
        with target.open('xb') as stream:
            stream.write(origin.read_bytes())
        copied.append({'source': str(origin), 'target': str(target), 'sha256': sha(target)})
    require(sha(HERE / 'vision_pipeline.v') == PIPELINE_SHA, 'Unexpected pipeline input')
    require(sha(HERE / 'cnn_result_stabilizer_baseline.v') ==
        template['inputs_sha256']['cnn_result_stabilizer_baseline.v'], 'Unexpected reference kernel')
    origins = {str(path): sha(path) for path in [source, pipeline_source, candidate,
        PARENT / 'PREPARATION.json', PARENT / 'ONLY_DIFF.patch',
        PARENT / 'TD_DIRECTION_RESULTS.json', old_manifest]}
    for record in copied:
        origins[record['source']] = record['sha256']
    manifest = {'status': 'PREPARED_NOT_RUN', 'candidate_sha256': CANDIDATE_SHA,
        'kernel_sha256': KERNEL_SHA, 'pipeline_sha256': PIPELINE_SHA,
        'origins_sha256': origins,
        'inputs_sha256': {path.name: sha(path) for path in HERE.iterdir() if path.is_file()},
        'copied_inputs': copied,
        'scope': 'Exact-cycle actual production pipeline and kernel comparison, controlled leaves',
        'production_modified': False, 'parent_candidate_modified': False,
        'hardware_status': 'NOT_RUN'}
    put(HERE / 'PREPARATION.json', json.dumps(manifest, indent=2) + '\n')
    print('PREPARED ' + CANDIDATE_SHA, flush=True)


def verify():
    data = json.loads((HERE / 'PREPARATION.json').read_text())
    for name,digest in data['inputs_sha256'].items():
        require(sha(HERE / name) == digest, 'Local input drift ' + name)
    for path,digest in data['origins_sha256'].items():
        require(sha(path) == digest, 'Origin drift ' + path)
    return data


def run(label, args, timeout=900):
    require((SIM / 'LICENSE.TXT').is_file(), 'File license missing')
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=(SIM / 'LICENSE.TXT').as_posix(),
        LM_LICENSE_FILE=(SIM / 'LICENSE.TXT').as_posix())
    print('START ' + label, flush=True)
    with (HERE / (label + '.log')).open('x', encoding='utf-8') as stream:
        process = subprocess.run([str(arg) for arg in args], cwd=HERE, env=env,
            stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
            timeout=timeout, creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    put(HERE / (label + '_command.json'), json.dumps({'returncode':process.returncode,
        'args':[str(arg) for arg in args], 'runner_sha256':sha(__file__),
        'manifest_sha256':sha(HERE / 'PREPARATION.json'),
        'MGLS_LICENSE_FILE':env['MGLS_LICENSE_FILE'], 'LM_LICENSE_FILE':env['LM_LICENSE_FILE']},
        indent=2) + '\n')
    text = (HERE / (label + '.log')).read_text(errors='replace')
    require(process.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):',text), label + ' failed')
    print('DONE ' + label, flush=True)
    return text


def sim(label, top, params=()):
    return run(label, [SIM/'vsim.exe', '-batch', '-syncio', '-quiet', '-novopt', '-suppress',
        '12110', '-lib', 'simlib', top, *params,
        '-do', 'onerror {quit -code 1}; run -all; quit -f'])


def evidence():
    return {path.name:sha(path) for path in HERE.iterdir() if path.is_file()}


def quick():
    verify()
    run('vlib', [SIM/'vlib.exe','simlib'])
    files = ['cnn_result_stabilizer_baseline.v','cnn_result_stabilizer.v','pipeline_leaf_stubs.sv',
        'vision_pipeline_baseline.v','vision_pipeline.v','tb_fixed_grid_mapping_miter.sv',
        'tb_area_grid_equivalence.sv','tb_combined_state_lifecycle.sv','tb_cnn_stability_serial.sv']
    text = run('compile', [SIM/'vlog.exe','-sv','-lint','-work','simlib',*files])
    require('Errors: 0, Warnings: 0' in text, 'Compile/lint warning')
    text = sim('production_integer_gold', 'tb_cnn_stability_serial')
    marker = 'PASS SERIAL_GOLD checks=3240 vectors=3307 emitted=2059 bank_reuses=3247 clear_boundaries=2 max_latency_cycles=857'
    require(text.count(marker) == 1, 'Integer gold coverage drift')
    text = sim('production_pipeline', 'tb_cnn_stability_pipeline')
    for marker in ('PASS FIXED_GRID_PUBLIC_CYCLE_MITER cycles=11742298 public_ports=37 controls=11 completed_jobs=113 assertions=527',
        'PASS ORIGINAL_81_JOBS_374_ASSERTIONS_PRESERVED', 'PASS CNN_STABILITY_PIPELINE_ALL checks=527 jobs=113'):
        require(text.count(marker) == 1, 'Pipeline coverage drift: ' + marker)
    verify()
    result = {'status':'PASS_QUICK_RTL_EXACT_CYCLE','candidate_sha256':CANDIDATE_SHA,
        'pipeline':{'cycles':11742298,'public_ports':37,'controls':11,'jobs':113,'assertions':527},
        'integer_gold':{'checks':3240,'vectors':3307,'emitted':2059,'bank_reuses':3247,
            'clear_boundaries':2,'max_latency_cycles':857},
        'evidence_sha256':evidence(), 'hardware_status':'NOT_RUN',
        'production_modified':False, 'parent_candidate_modified':False}
    put(HERE / 'QUICK_RESULTS.json', json.dumps(result,indent=2) + '\n')
    print(json.dumps({'status':result['status'],'candidate':CANDIDATE_SHA}),flush=True)


def matrix():
    verify()
    quick_result = json.loads((HERE / 'QUICK_RESULTS.json').read_text())
    require(quick_result['status'] == 'PASS_QUICK_RTL_EXACT_CYCLE', 'Quick prerequisite missing')
    for name,digest in quick_result['evidence_sha256'].items():
        require(sha(HERE/name) == digest, 'Quick evidence drift ' + name)
    modes = []
    for bits in (20,22,24,32):
        for reader in (0,1):
            for coord in (0,3):
                modes.append((bits,0,coord,reader,(3,2,3),'generic_vectors.txt'))
    for reader in (0,1):
        for params in PARAMS:
            mode = (32,0,0,reader,params,'generic_vectors.txt')
            if mode not in modes:
                modes.append(mode)
    for reader in (0,1):
        for params in PARAMS:
            modes.append((22,6,3,reader,params,'aligned_a22_s6.txt'))
    for bits,shift in ((20,1),(20,19),(32,31)):
        for reader in (0,1):
            modes.append((bits,shift,0,reader,(3,2,3),f'aligned_a{bits}_s{shift}.txt'))
    require(len(modes) == 40, 'Configuration count drift')
    records = []
    for bits,shift,coord,reader,(c,h,l),vectors in modes:
        label = f'miter_a{bits}s{shift}_c{coord}_e{reader}_p{c}_{h}_{l}'
        text = sim(label,'tb_area_grid_equivalence',[f'-gAREA_BITS={bits}',f'-gAREA_SHIFT={shift}',
            f'-gCOORD_SHIFT={coord}',f'-gEXTERNAL_CANDIDATE_READER={reader}',
            f'-gCONFIRM_RESULTS={c}',f'-gHOLD_RESULTS={h}',f'-gLOST_RESULTS={l}','+vectors='+vectors])
        markers = [line.strip('# ') for line in text.splitlines() if 'PASS AREA_GRID_EQUIVALENCE' in line]
        require(len(markers) == 1, 'Kernel miter completion missing ' + label)
        records.append({'mode':label,'summary':markers[0]})
    lifecycle = []
    for c,h,l in PARAMS:
        for reader in (0,1):
            label = f'lifecycle_c{c}h{h}l{l}_e{reader}'
            text = sim(label,'tb_combined_state_lifecycle',[f'-gEXTERNAL_CANDIDATE_READER={reader}',
                f'-gCONFIRM_RESULTS={c}',f'-gHOLD_RESULTS={h}',f'-gLOST_RESULTS={l}',
                f'+vectors=c{c}h{h}l{l}.txt'])
            markers = [line.strip('# ') for line in text.splitlines() if 'PASS COMBINED_STATE_LIFECYCLE' in line]
            require(len(markers) == 1 and 'vectors=2385 gold=2315' in markers[0] and
                markers[0].endswith('aborts=56'), 'Lifecycle coverage drift ' + label)
            lifecycle.append({'mode':label,'summary':markers[0]})
    verify()
    result = {'status':'PASS_SCRATCH_RTL_EXACT_CYCLE','candidate_sha256':CANDIDATE_SHA,
        'source_kernel_sha256':KERNEL_SHA,'source_pipeline_sha256':PIPELINE_SHA,
        'quick_results_sha256':sha(HERE/'QUICK_RESULTS.json'),
        'pipeline_coverage':quick_result['pipeline'],'integer_gold':quick_result['integer_gold'],
        'generic_miter_modes':records,'lifecycle_modes':lifecycle,'aggregate_state_aborts':560,
        'evidence_sha256':evidence(), 'production_modified':False,'parent_candidate_modified':False,
        'hardware_status':'NOT_RUN','limits':['Directed/random simulation, not mathematical formal proof',
            'Actual production pipeline and kernel, with controlled leaf modules',
            'No board place/route/timing/CDC/FIFO/DDR/DRC acceptance or new image-quality claim',
            'Metadata-only resource saving is local; no claim that board placement is solved']}
    put(HERE/'RESULTS.json',json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'candidate':CANDIDATE_SHA,
        'modes':40,'lifecycle_modes':10,'aborts':560}),flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare',action='store_true')
    parser.add_argument('--quick',action='store_true')
    parser.add_argument('--matrix',action='store_true')
    args = parser.parse_args()
    if args.prepare:
        prepare()
    if args.quick:
        quick()
    if args.matrix:
        matrix()
