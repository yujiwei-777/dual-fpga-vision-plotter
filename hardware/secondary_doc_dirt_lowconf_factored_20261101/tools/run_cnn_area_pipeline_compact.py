"""Fresh compact-production CNN qualification, with a separately frozen reference.

The 8655 reference and historical derivation are imported, never represented as
fresh production tests. Every simulator launch below compiles the current new
root's 9C946 kernel and 6D9B pipeline directly. Only this suite is written.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '02_sim/cnn_area_pipeline_compact'
SIM = Path('E:/model/win64')
OLD = ROOT.parent / 'secondary_cnn_target_stability_20261031'
RELEASE = ROOT.parent / 'secondary_cnn_key3_stroke_release_20261031'
SPLIT = ROOT.parent / 'secondary_cnn_key3_stroke_split_20261031'
FUNCTIONAL = ROOT.parent / 'secondary_cnn_metadata_flat_scratch_20261031/functional'
ORIGIN = OLD / 'reports/kernel_area_overlap_combined_candidate'
PIPELINE = ROOT / '01_rtl/vision_pipeline.v'
KERNEL = ROOT / '01_rtl/cnn_result_stabilizer.v'
PIPELINE_SHA = '6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9'
KERNEL_SHA = '9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128'
REFERENCE_SHA = '8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C'
R11_KERNEL_SHA = '8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36'
R11_PIPELINE_SHA = 'C7B43FE8727F1145C2EF060CE9DC464029AF74CB4BD372DF10E1395E5D878413'
PARAMS = ((1, 0, 1), (2, 1, 2), (3, 2, 3), (4, 0, 4), (15, 15, 15))
PUBLIC = '''word_req byte_addr busy done result_job_id config_version color_id shape_id
confidence valid x0 x1 y0 y1 area pcb_checked pcb_good pcb_status defect_count
defect_boxes defect_kinds multi_count multi_boxes multi_flags teach_success
teach_failed teach_code teach_commit taught_station_header ext_reader_request
ext_reader_invalidate ext_pixel_x ext_pixel_y yolo_pixel_valid yolo_pixel_rgb
yolo_pixel_last color_word_active'''.split()
CONTROL = '''state box_index box_total sample_index purpose_q map_bits_left area_bits_left
map_job raw_slot_order insert_physical_slot stable_raw_released'''.split()
INPUTS = {}
COPIES = {}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def now():
    return datetime.now(timezone.utc).isoformat()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def put(path, text):
    with Path(path).open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(text)


def write_json(path, data):
    put(path, json.dumps(data, indent=2, ensure_ascii=False) + '\n')


def record(path, expected=None):
    path = Path(path).resolve()
    require(path.is_relative_to(ROOT), 'Input escapes compact root: ' + str(path))
    digest = sha(path)
    require(expected is None or digest == expected, 'Input hash mismatch: ' + str(path))
    INPUTS[str(path)] = digest
    return path


def freeze(source, target, expected=None):
    source, target = Path(source).resolve(), Path(target).resolve()
    require(target.is_relative_to(OUT), 'Copy escapes suite')
    digest = sha(source)
    require(expected is None or digest == expected, 'Origin hash mismatch: ' + str(source))
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(source.read_bytes())
    record(target, digest)
    COPIES[str(target.relative_to(OUT))] = {'source': str(source), 'sha256': digest}
    return target


def import_evidence():
    """Import complete existing local file evidence, including origin closure."""
    pinned = {
        'RESULTS.json': '50A3FF531E8EEE7227296BA8353F8937BB5C4A23B05D527DFB01243CD0F66247',
        'QUICK_RESULTS.json': '3D9AAD17842E4F10948172AF0EFEE9386963713222BFED530B9F72858E0127D6',
        'PREPARATION.json': '86452D333245213B0CB51B44EBBEC1C6100F4645DC442806C8C6BA099155BC80',
        'FINAL_AUDIT.json': 'F9B6F138173D16F8060C9D011B99A60C5A971FA05B51FCE57EC1681F5AF12AAA',
        'run_regression.py': '54DE43B460E5488FD8123EA28C008B15676E232689372F612C0D8937552F6316',
    }
    for name, digest in pinned.items():
        require(sha(FUNCTIONAL / name) == digest, 'Historical metadata evidence drift ' + name)
    old = load(FUNCTIONAL / 'RESULTS.json')
    require(old['status'] == 'PASS_SCRATCH_RTL_EXACT_CYCLE' and old['candidate_sha256'] == KERNEL_SHA
            and old['source_kernel_sha256'] == REFERENCE_SHA, 'Historical kernel identities changed')
    require(len(old['generic_miter_modes']) == 40 and len(old['lifecycle_modes']) == 10
            and old['aggregate_state_aborts'] == 560, 'Historical coverage changed')
    for path in FUNCTIONAL.iterdir():
        if path.is_file():
            freeze(path, OUT / 'imported_metadata_functional' / path.name)
    for result_name in ('RESULTS.json', 'QUICK_RESULTS.json'):
        for name, digest in load(FUNCTIONAL / result_name)['evidence_sha256'].items():
            record(OUT / 'imported_metadata_functional' / name, digest)
    prep = load(FUNCTIONAL / 'PREPARATION.json')
    for name, digest in prep['inputs_sha256'].items():
        record(OUT / 'imported_metadata_functional' / name, digest)
    for name, digest in prep['origins_sha256'].items():
        path = Path(name).resolve()
        require(path.is_relative_to(ROOT.parent), 'Historical origin escapes workspace')
        freeze(path, OUT / 'imported_metadata_origins' / path.relative_to(ROOT.parent), digest)
    for relative in ('verification/RESULTS.json', 'production_reference/RESULTS.json', 'state_lifecycle/RESULTS.json'):
        source = ORIGIN / relative
        data = load(source)
        require(str(data['status']).startswith('PASS'), 'Historical derivation failed')
        for name, digest in data.get('input_hashes', {}).items():
            path = Path(name).resolve()
            require(path.is_relative_to(OLD), 'Historical derivation input escapes origin')
            freeze(path, OUT / 'imported_area_derivation' / path.relative_to(OLD), digest)
        for name, digest in data.get('evidence_hashes', {}).items():
            path = (source.parent / name).resolve()
            require(path.is_relative_to(OLD), 'Historical derivation evidence escapes origin')
            freeze(path, OUT / 'imported_area_derivation' / path.relative_to(OLD), digest)
        freeze(source, OUT / 'imported_area_derivation' / source.relative_to(OLD))
    frozen = freeze(RELEASE / '01_rtl/cnn_result_stabilizer.v',
                    OUT / 'origin/cnn_result_stabilizer_reference.v', REFERENCE_SHA)
    text = frozen.read_text()
    require(text.count('module cnn_result_stabilizer #(') == 1, 'Reference declaration changed')
    target = OUT / 'origin/cnn_result_stabilizer_baseline.v'
    put(target, text.replace('module cnn_result_stabilizer #(', 'module cnn_result_stabilizer_baseline #('))
    require(sha(target) == sha(FUNCTIONAL / 'cnn_result_stabilizer_baseline.v'), 'Reference rename is not historical oracle')
    record(target)
    freeze(SPLIT / '01_rtl/cnn_result_stabilizer.v', OUT / 'origin/cnn_result_stabilizer_r11.v', R11_KERNEL_SHA)
    freeze(SPLIT / '01_rtl/vision_pipeline.v', OUT / 'origin/vision_pipeline_r11.v', R11_PIPELINE_SHA)
    freeze(OLD / '02_sim/cnn_stability/reference_trace.jsonl', OUT / 'origin/reference_trace.jsonl',
           '04E7AB74BCF2A5DC0D2801F9880639EA2F60C05A98954E45761BD8A82F91FADE')
    data = {'status': 'PASS', 'fresh': False, 'scope': 'Historical evidence imported by byte copy and SHA256 closure; no new simulation',
        'historical_candidate_sha256': KERNEL_SHA, 'historical_reference_sha256': REFERENCE_SHA,
        'production_kernel_sha256': KERNEL_SHA, 'reference_kernel_sha256': REFERENCE_SHA,
        'forty_mode_miter': 40, 'ten_mode_lifecycle': 10, 'aggregate_aborts': 560,
        'chain': ['R11 kernel to area-grid 8655 reference: imported original area/domain evidence',
                  '8655 reference to metadata-flat 9C946: imported previous fresh exact-cycle evidence',
                  'Current compact production 9C946 vs frozen 8655: fresh suites run separately below'],
        'copies': dict(COPIES)}
    write_json(OUT / 'ORIGIN_IMPORT.json', data)
    record(OUT / 'ORIGIN_IMPORT.json')
    return old


def run_command(directory, label, args, timeout=900):
    env = os.environ.copy()
    license_file = (SIM / 'LICENSE.TXT').as_posix()
    env.update(MGLS_LICENSE_FILE=license_file, LM_LICENSE_FILE=license_file)
    command = [str(arg) for arg in args]
    print('START ' + str(directory.relative_to(OUT)) + ' ' + label, flush=True)
    logfile = directory / (label + '.log')
    started = now()
    failure = None
    returncode = None
    with logfile.open('x', encoding='utf-8') as stream:
        try:
            process = subprocess.run(command, cwd=directory, env=env, stdin=subprocess.DEVNULL,
                stdout=stream, stderr=subprocess.STDOUT, timeout=timeout,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            returncode = process.returncode
        except Exception as exc:
            failure = repr(exc)
    output = logfile.read_text(errors='replace')
    write_json(directory / (label + '_command.json'), {'command': command, 'args': command,
        'returncode': returncode, 'exception': failure, 'started_utc': started, 'completed_utc': now(),
        'runner_sha256': sha(__file__), 'log_sha256': sha(logfile),
        'production_kernel_sha256': sha(KERNEL), 'production_pipeline_sha256': sha(PIPELINE),
        'MGLS_LICENSE_FILE': license_file, 'LM_LICENSE_FILE': license_file})
    require(failure is None and returncode == 0, 'Process failed ' + str(logfile))
    require(not re.search(r'\*\*\s+(?:Error|Fatal):|\bErrors:\s*[1-9]|^#?\s*FAIL\b', output, re.M),
            'Simulator failure ' + str(logfile))
    if Path(command[0]).name.lower() in ('vlog.exe', 'vsim.exe'):
        require(re.search(r'(?:^|\n)#?\s*Errors: 0, Warnings: \d+\s*$', output), 'Missing terminal summary ' + str(logfile))
        warning_codes = re.findall(r'\*\* Warning: \(vsim-(\d+)\)', output)
        require(all(code == '8891' for code in warning_codes), 'Unexpected simulation warning ' + str(logfile))
    print('DONE ' + str(directory.relative_to(OUT)) + ' ' + label, flush=True)
    return output


def compile_sources(directory, sources):
    run_command(directory, 'vlib', [SIM / 'vlib.exe', 'simlib'])
    for source in sources:
        record(source)
    text = run_command(directory, 'compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', 'simlib', *sources])
    require(re.search(r'Errors: 0, Warnings: 0\s*$', text), 'Compile/lint warnings')


def simulate(directory, top, label='simulate', params=()):
    return run_command(directory, label, [SIM / 'vsim.exe', '-batch', '-syncio', '-quiet', '-novopt',
        '-suppress', '12110', '-lib', 'simlib', top, *params,
        '-do', 'onerror {quit -code 1}; run -all; quit -f'])


def exact(text, marker):
    require([line.lstrip('# ').strip() for line in text.splitlines()].count(marker) == 1,
            'Missing/duplicate exact completion: ' + marker)


def fresh_pipeline():
    directory = OUT / 'pipeline_miter'
    directory.mkdir()
    bench = freeze(FUNCTIONAL / 'tb_fixed_grid_mapping_miter.sv', directory / 'tb_fixed_grid_mapping_miter.sv',
        '98A159C7E02713647ADCDF99215B5E69CE7499137B078A66F0A6351AB529E26A')
    stubs = freeze(FUNCTIONAL / 'pipeline_leaf_stubs.sv', directory / 'pipeline_leaf_stubs.sv',
        'B19E7BDF866824235C6B89DC78E4A3FCD41C48FD0EE4C29FFA8ADFCF89AEAAA2')
    baseline = freeze(FUNCTIONAL / 'vision_pipeline_baseline.v', directory / 'vision_pipeline_baseline.v',
        '7876918A9EA2347E2E1791DCA47A30004462F8B536EECF81B3780BB8EE1233C3')
    renamed = PIPELINE.read_text().replace('module vision_pipeline #(', 'module vision_pipeline_baseline #(').replace(
        '        cnn_result_stabilizer #(', '        cnn_result_stabilizer_baseline #(')
    require(renamed == baseline.read_text(), 'Baseline pipeline contains nonrename changes')
    text = bench.read_text()
    require(len(PUBLIC) == 37 and len(CONTROL) == 11, 'Monitor cardinality changed')
    for name in PUBLIC + CONTROL:
        require(text.count('CYCLE_MITER ' + name + ' cycle=') == 1, 'Missing monitor ' + name)
    require('if(completions!=81||checks!=374)' in text, 'Original program guard removed')
    compile_sources(directory, [stubs, baseline, OUT / 'origin/cnn_result_stabilizer_baseline.v', PIPELINE, KERNEL, bench])
    text = simulate(directory, 'tb_cnn_stability_pipeline')
    for marker in ('PASS FIXED_GRID_PUBLIC_CYCLE_MITER cycles=11742298 public_ports=37 controls=11 completed_jobs=113 assertions=527',
        'PASS ORIGINAL_81_JOBS_374_ASSERTIONS_PRESERVED', 'PASS CNN_STABILITY_PIPELINE_ALL checks=527 jobs=113'):
        exact(text, marker)
    data = {'status': 'PASS', 'fresh': True,
        'coverage': dict(cycles=11742298, public_ports=37, controls=11, completed_jobs=113, assertions=527),
        'original_program': dict(jobs=81, assertions=374),
        'compared_kernels': {'reference': REFERENCE_SHA, 'production': KERNEL_SHA},
        'production_compiled_directly': [str(PIPELINE), str(KERNEL)]}
    write_json(directory / 'RESULTS.json', data)
    return data


def fresh_domain():
    directory = OUT / 'domain'
    directory.mkdir()
    original = freeze(ORIGIN / 'prove_domain.py', OUT / 'origin/prove_domain_original.py',
        'EE9DEAE0B5792786BA0839B9B49F2F6222DE3F1F55B4EA78021F680BA5071F99')
    text = original.read_text().replace('HERE=Path(__file__).resolve().parent\nROOT=HERE.parents[1]',
        'HERE=Path(__file__).resolve().parent\nROOT=HERE.parents[2]')
    text = text.replace('kernel=HERE/"cnn_result_stabilizer_r11.v"',
        'kernel=ROOT/"02_sim/cnn_area_pipeline_compact/origin/cnn_result_stabilizer_r11.v"')
    text = text.replace('candidate=HERE/"cnn_result_stabilizer.v"', 'candidate=ROOT/"01_rtl/cnn_result_stabilizer.v"')
    text = text.replace(R11_PIPELINE_SHA, PIPELINE_SHA).replace(REFERENCE_SHA, KERNEL_SHA)
    text = text.replace('.LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(24)', '.LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(22),.AREA_SHIFT(6)')
    text = text.replace('ROOT/"02_sim/cnn_stability/reference_trace.jsonl"',
        'ROOT/"02_sim/cnn_area_pipeline_compact/origin/reference_trace.jsonl"')
    script = directory / 'prove_compact_area_domain.py'
    put(script, text)
    record(script)
    run_command(directory, 'prove_domain', [sys.executable, script])
    proof = load(directory / 'AREA_DOMAIN_PROOF.json')
    require(proof['status'] == 'PASS_SOURCE_DERIVATION_AND_FINITE_INTEGER_CHECKS' and
        proof['integer_checks']['code_domain_size'] == 65536 and proof['integer_checks']['raw_replay_frames'] == 1170,
        'Domain proof coverage changed')
    return {'status': 'PASS', 'fresh': True, 'source_pipeline_sha256': PIPELINE_SHA,
        'source_kernel_sha256': KERNEL_SHA, 'reference_kernel_sha256': REFERENCE_SHA,
        'coverage': proof['integer_checks'],
        'chain': 'Caller source/domain derivation preserved from R11/8655; current metadata-only kernel is bound by hash and freshly compared against 8655, not assumed same source'}


def fresh_integer_gold():
    directory = OUT / 'kernel_reference'
    directory.mkdir()
    bench = freeze(FUNCTIONAL / 'tb_cnn_stability_serial.sv', directory / 'tb_cnn_stability_serial.sv')
    freeze(FUNCTIONAL / 'vectors.txt', directory / 'vectors.txt')
    compile_sources(directory, [KERNEL, bench])
    text = simulate(directory, 'tb_cnn_stability_serial')
    exact(text, 'PASS SERIAL_GOLD checks=3240 vectors=3307 emitted=2059 bank_reuses=3247 clear_boundaries=2 max_latency_cycles=857')
    data = {'status': 'PASS', 'fresh_rtl_replay': True,
        'checks': dict(gold_checks=3240, events=3307, serial_records=2059, bank_reuses=3247, clear_boundaries=2, max_cycles=857)}
    write_json(directory / 'RESULTS.json', data)
    return data


def configuration_modes():
    modes = [(bits, 0, coord, reader, (3, 2, 3), 'generic_vectors.txt')
        for bits in (20, 22, 24, 32) for reader in (0, 1) for coord in (0, 3)]
    for reader in (0, 1):
        for params in PARAMS:
            mode = (32, 0, 0, reader, params, 'generic_vectors.txt')
            if mode not in modes:
                modes.append(mode)
    modes.extend((22, 6, 3, reader, params, 'aligned_a22_s6.txt') for reader in (0, 1) for params in PARAMS)
    modes.extend((bits, shift, 0, reader, (3, 2, 3), f'aligned_a{bits}_s{shift}.txt')
        for bits, shift in ((20, 1), (20, 19), (32, 31)) for reader in (0, 1))
    require(len(modes) == 40 and len(set(modes)) == 40, 'Configuration coverage changed')
    return modes


def fresh_configurations(previous):
    directory = OUT / 'kernel_configurations'
    directory.mkdir()
    bench = freeze(FUNCTIONAL / 'tb_area_grid_equivalence.sv', directory / 'tb_area_grid_equivalence.sv')
    for name in ('generic_vectors.txt', 'aligned_a20_s1.txt', 'aligned_a20_s19.txt', 'aligned_a22_s6.txt', 'aligned_a32_s31.txt'):
        freeze(FUNCTIONAL / name, directory / name)
    compile_sources(directory, [OUT / 'origin/cnn_result_stabilizer_baseline.v', KERNEL, bench])
    expected = {mode['mode']: mode['summary'] for mode in previous['generic_miter_modes']}
    records = []
    for bits, shift, coord, reader, (c, h, l), vectors in configuration_modes():
        label = f'miter_a{bits}s{shift}_c{coord}_e{reader}_p{c}_{h}_{l}'
        params = [f'-gAREA_BITS={bits}', f'-gAREA_SHIFT={shift}', f'-gCOORD_SHIFT={coord}',
            f'-gEXTERNAL_CANDIDATE_READER={reader}', f'-gCONFIRM_RESULTS={c}', f'-gHOLD_RESULTS={h}',
            f'-gLOST_RESULTS={l}', '+vectors=' + vectors]
        text = simulate(directory, 'tb_area_grid_equivalence', label, params)
        exact(text, expected[label])
        values = re.search(r'vectors=(\d+) jobs=(\d+) rejected=(\d+) cycle_checks=(\d+) serial=(\d+) bank_reuses=(\d+)', expected[label])
        require(values is not None, 'Configuration marker format changed')
        records.append({'mode': label, 'summary': expected[label], 'area_bits': bits, 'area_shift': shift,
            'coord_shift': coord, 'external_reader': reader, 'parameters': [c, h, l], 'vectors_file': vectors,
            'counts': dict(zip(('vectors', 'jobs', 'rejected', 'cycle_checks', 'serial', 'bank_reuses'), map(int, values.groups())))})
    data = {'status': 'PASS', 'fresh_rtl_replay': True, 'mode_count': 40,
        'reference_kernel_sha256': REFERENCE_SHA, 'production_kernel_sha256': KERNEL_SHA, 'modes': records}
    write_json(directory / 'RESULTS.json', data)
    return data


def fresh_lifecycle(previous):
    directory = OUT / 'kernel_lifecycle'
    directory.mkdir()
    bench = freeze(FUNCTIONAL / 'tb_combined_state_lifecycle.sv', directory / 'tb_combined_state_lifecycle.sv')
    for c, h, l in PARAMS:
        freeze(FUNCTIONAL / f'c{c}h{h}l{l}.txt', directory / f'c{c}h{h}l{l}.txt')
    compile_sources(directory, [OUT / 'origin/cnn_result_stabilizer_baseline.v', KERNEL, bench])
    expected = {mode['mode']: mode['summary'] for mode in previous['lifecycle_modes']}
    records = []
    for c, h, l in PARAMS:
        for reader in (0, 1):
            label = f'lifecycle_c{c}h{h}l{l}_e{reader}'
            params = [f'-gEXTERNAL_CANDIDATE_READER={reader}', f'-gCONFIRM_RESULTS={c}',
                f'-gHOLD_RESULTS={h}', f'-gLOST_RESULTS={l}', f'+vectors=c{c}h{h}l{l}.txt']
            text = simulate(directory, 'tb_combined_state_lifecycle', label, params)
            exact(text, expected[label])
            values = re.search(r'vectors=(\d+) gold=(\d+) jobs=(\d+) cycles=(\d+) serial=(\d+) reuses=(\d+) aborts=(\d+)', expected[label])
            require(values is not None, 'Lifecycle marker format changed')
            counts = dict(zip(('vectors', 'gold', 'jobs', 'cycles', 'serial', 'reuses', 'aborts'), map(int, values.groups())))
            require(counts['vectors'] == 2385 and counts['gold'] == 2315 and counts['aborts'] == 56, 'Lifecycle coverage drift')
            records.append({'mode': label, 'summary': expected[label], 'external_reader': reader,
                'parameters': [c, h, l], 'area_bits': 22, 'area_shift': 6, 'coord_shift': 3, **counts})
    data = {'status': 'PASS', 'fresh_rtl_replay': True, 'mode_count': 10, 'aggregate_aborts': sum(mode['aborts'] for mode in records),
        'reference_kernel_sha256': REFERENCE_SHA, 'production_kernel_sha256': KERNEL_SHA,
        'abort_scope': 'All 28 FSM states, clear and asynchronous reset, five parameter sets and both readers', 'modes': records}
    require(data['aggregate_aborts'] == 560, 'Aggregate abort coverage changed')
    write_json(directory / 'RESULTS.json', data)
    return data


def main():
    require(not OUT.exists(), 'Never overwrite fresh evidence; use a new run directory after a failure')
    require(sha(PIPELINE) == PIPELINE_SHA and sha(KERNEL) == KERNEL_SHA, 'Compact production source drift')
    for name in ('LICENSE.TXT', 'vsim.exe', 'vlog.exe', 'vlib.exe'):
        require((SIM / name).is_file(), 'Missing simulator or file license: ' + name)
    OUT.mkdir(parents=True)
    for path in (PIPELINE, KERNEL, ROOT / '01_rtl/secondary_top.v', ROOT / '01_rtl/cnn_core.v', ROOT / 'lint_full.f', Path(__file__)):
        record(path)
    result = {'status': 'RUNNING', 'started_utc': now(), 'hardware_status': 'NOT_RUN', 'production_modified': False, 'td_run': False}
    try:
        previous = import_evidence()
        result['pipeline_miter'] = fresh_pipeline()
        result['domain'] = fresh_domain()
        result['kernel_reference'] = fresh_integer_gold()
        result['kernel_configurations'] = fresh_configurations(previous)
        result['kernel_lifecycle'] = fresh_lifecycle(previous)
        for path, digest in INPUTS.items():
            require(sha(path) == digest, 'Source/evidence changed during fresh regression: ' + path)
        result.update(status='PASS', completed_utc=now(), input_hashes=INPUTS,
            evidence_hashes={str(path.relative_to(OUT)): sha(path) for path in OUT.rglob('*')
                if path.is_file() and path.suffix in ('.json', '.jsonl', '.log', '.txt', '.py', '.sv', '.v', '.patch')},
            production_pipeline_sha256=PIPELINE_SHA, production_kernel_sha256=KERNEL_SHA,
            reference_kernel_sha256=REFERENCE_SHA, imported_evidence='ORIGIN_IMPORT.json',
            limits=['Directed and random RTL simulation with controlled CCL/CNN/DDR leaves, not formal proof',
                'Imported historical evidence is provenance only; all stated compact fresh tests ran on current production paths',
                'No claim of image accuracy, board testing, placement, route, timing, CDC, FIFO, DDR, DRC or bitgen acceptance'])
    except Exception as exc:
        result.update(status='FAIL', completed_utc=now(), error=repr(exc), input_hashes=INPUTS)
        raise
    finally:
        write_json(OUT / 'RESULTS.json', result)
    print(json.dumps({'status': result['status'], 'results_sha256': sha(OUT / 'RESULTS.json'),
        'fresh_configurations': 40, 'fresh_lifecycle_modes': 10, 'aggregate_aborts': 560}, indent=2), flush=True)


if __name__ == '__main__':
    main()
