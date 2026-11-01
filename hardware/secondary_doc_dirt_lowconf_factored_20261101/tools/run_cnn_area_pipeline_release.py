"""Fresh production AREA22/SHIFT6 pipeline/kernel regression against frozen R11.

Only this release's test/evidence directories are written. Production RTL is
pinned and never edited. Controlled CCL/CNN/DDR leaves isolate the real pipeline
and both real stabilizer FSMs; this is not end-to-end image or board testing.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT.parent / 'secondary_cnn_target_stability_20261031'
SPLIT = ROOT.parent / 'secondary_cnn_key3_stroke_split_20261031'
ORIGIN = OLD / 'reports/kernel_area_overlap_combined_candidate'
OUT = ROOT / '02_sim/cnn_area_pipeline_release'
SIM = Path('E:/model/win64')
PIPELINE = ROOT / '01_rtl/vision_pipeline.v'
KERNEL = ROOT / '01_rtl/cnn_result_stabilizer.v'
PIPELINE_SHA = '6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9'
KERNEL_SHA = '8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C'
R11_PIPELINE_SHA = 'C7B43FE8727F1145C2EF060CE9DC464029AF74CB4BD372DF10E1395E5D878413'
R11_KERNEL_SHA = '8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36'
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


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def now():
    return datetime.now(timezone.utc).isoformat()


def require(ok, message):
    if not ok:
        raise AssertionError(message)


def write_json(path, data):
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False)
        stream.write('\n')


def record(path, digest=None):
    path = Path(path).resolve()
    require(path.is_relative_to(ROOT), 'Input escapes release: ' + str(path))
    value = sha(path)
    require(digest is None or value == digest, 'Input changed: ' + str(path))
    INPUTS[str(path)] = value
    return path


def freeze(source, target, digest=None):
    source, target = Path(source).resolve(), Path(target).resolve()
    value = sha(source)
    require(digest is None or value == digest, 'Origin evidence drift: ' + str(source))
    if target.exists():
        require(sha(target) == value, 'Different duplicate origin: ' + str(target))
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(source.read_bytes())
    require(sha(target) == value, 'True copy failed: ' + str(target))
    record(target, value)
    COPIES[str(target.relative_to(OUT))] = {'source': str(source), 'sha256': value}
    return target


def import_sealed_result(source):
    source = Path(source)
    result = json.loads(source.read_text())
    require(str(result['status']).startswith('PASS'), 'Origin result did not pass')
    for key, value in result.get('input_hashes', {}).items():
        path = Path(key)
        require(path.is_relative_to(OLD), 'Unexpected origin input root: ' + key)
        freeze(path, OUT / 'sealed_origin' / path.relative_to(OLD), value)
    for key, value in result.get('evidence_hashes', {}).items():
        path = (source.parent / key).resolve()
        require(path.is_relative_to(OLD), 'Unexpected origin evidence root')
        freeze(path, OUT / 'sealed_origin' / path.relative_to(OLD), value)
    return freeze(source, OUT / 'sealed_origin' / source.relative_to(OLD))


def run_command(directory, label, args, timeout=600):
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))
    print('START ' + str(directory.relative_to(OUT)) + ' ' + label, flush=True)
    logfile = directory / (label + '.log')
    with logfile.open('x', encoding='utf-8') as stream:
        proc = subprocess.run([str(value) for value in args], cwd=directory, env=env,
                              stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
                              timeout=timeout, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    output = logfile.read_text(errors='replace')
    require(proc.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):', output),
            label + ' failed: ' + str(logfile))
    print('DONE ' + str(directory.relative_to(OUT)) + ' ' + label, flush=True)
    return output


def simulate(directory, sources, top, label='simulate', parameters=()):
    if not (directory / 'simlib').exists():
        run_command(directory, 'vlib', [SIM / 'vlib.exe', 'simlib'])
        output = run_command(directory, 'compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', 'simlib', *sources])
        require('Errors: 0, Warnings: 0' in output, 'Compile warnings changed')
    for path in sources:
        record(path)
    return run_command(directory, label, [SIM / 'vsim.exe', '-batch', '-syncio', '-quiet',
        '-novopt', '-suppress', '12110', '-lib', 'simlib', top, *parameters,
        '-do', 'onerror {quit -code 1}; run -all; quit -f'])


def fresh_pipeline_miter():
    directory = OUT / 'pipeline_miter'
    directory.mkdir()
    origin_bench = OLD / 'reports/fixed_grid_mapping_candidate/miter/tb_fixed_grid_mapping_miter.sv'
    origin_stubs = origin_bench.parent / 'pipeline_leaf_stubs.sv'
    bench = freeze(origin_bench, directory / origin_bench.name,
                   '98A159C7E02713647ADCDF99215B5E69CE7499137B078A66F0A6351AB529E26A')
    stubs = freeze(origin_stubs, directory / origin_stubs.name,
                   'B19E7BDF866824235C6B89DC78E4A3FCD41C48FD0EE4C29FFA8ADFCF89AEAAA2')
    text = bench.read_text()
    require(len(PUBLIC) == 37 and len(CONTROL) == 11, 'Monitor cardinality drift')
    for name in PUBLIC + CONTROL:
        require(text.count('CYCLE_MITER ' + name + ' cycle=') == 1, 'Missing monitor ' + name)
    require('if(completions!=81||checks!=374)' in text, 'Original integration guard missing')
    raw_pipeline = OUT / 'origin/vision_pipeline_r11.v'
    raw_kernel = OUT / 'origin/cnn_result_stabilizer_r11.v'
    baseline = directory / 'vision_pipeline_baseline.v'
    payload = raw_pipeline.read_bytes()
    require(payload.count(b'module vision_pipeline #(') == 1, 'Pipeline declaration drift')
    require(payload.count(b'        cnn_result_stabilizer #(') == 1, 'Pipeline kernel instance drift')
    baseline.write_bytes(payload.replace(b'module vision_pipeline #(', b'module vision_pipeline_baseline #(')
                         .replace(b'        cnn_result_stabilizer #(', b'        cnn_result_stabilizer_baseline #('))
    baseline_kernel = directory / 'cnn_result_stabilizer_baseline.v'
    payload = raw_kernel.read_bytes()
    require(payload.count(b'module cnn_result_stabilizer #(') == 1, 'Kernel declaration drift')
    baseline_kernel.write_bytes(payload.replace(b'module cnn_result_stabilizer #(',
                                                b'module cnn_result_stabilizer_baseline #('))
    sources = [stubs, baseline, baseline_kernel, PIPELINE, KERNEL, bench]
    output = simulate(directory, sources, 'tb_cnn_stability_pipeline')
    require(output.count('PASS ORIGINAL_81_JOBS_374_ASSERTIONS_PRESERVED') == 1, 'Original program lost')
    matches = re.findall(r'PASS FIXED_GRID_PUBLIC_CYCLE_MITER cycles=(\d+) public_ports=(\d+) controls=(\d+) completed_jobs=(\d+) assertions=(\d+)', output)
    require(len(matches) == 1, 'Missing cycle miter PASS')
    counts = tuple(map(int, matches[0]))
    require(counts == (11742298, 37, 11, 113, 527), 'Cycle miter coverage drift: ' + str(counts))
    require(output.count('PASS CNN_STABILITY_PIPELINE_ALL checks=527 jobs=113') == 1, 'Completion missing')
    result = {'status': 'PASS', 'fresh': True, 'coverage': dict(zip(
        ('cycles', 'public_ports', 'controls', 'completed_jobs', 'assertions'), counts)),
        'original_program': {'jobs': 81, 'assertions': 374},
        'compared_kernels': {'reference': R11_KERNEL_SHA, 'production': KERNEL_SHA},
        'limits': ['Real production pipeline/control and both real stabilizer FSMs; controlled CCL/CNN/DDR leaves',
                   'No camera/DDR/UART/HXA integration, image accuracy or board validation']}
    write_json(directory / 'RESULTS.json', result)
    return result


def fresh_domain():
    directory = OUT / 'domain'
    directory.mkdir()
    origin = ORIGIN / 'prove_domain.py'
    frozen = freeze(origin, OUT / 'origin/prove_domain_original.py',
                    'EE9DEAE0B5792786BA0839B9B49F2F6222DE3F1F55B4EA78021F680BA5071F99')
    # Keep the complete reviewed static/data-flow argument, binding its exact
    # assertions to the newly promoted production source and local true copies.
    text = frozen.read_text()
    text = text.replace('HERE=Path(__file__).resolve().parent\nROOT=HERE.parents[1]',
        'HERE=Path(__file__).resolve().parent\nROOT=HERE.parents[2]')
    text = text.replace('kernel=HERE/"cnn_result_stabilizer_r11.v"',
        'kernel=ROOT/"02_sim/cnn_area_pipeline_release/origin/cnn_result_stabilizer_r11.v"')
    text = text.replace('candidate=HERE/"cnn_result_stabilizer.v"',
        'candidate=ROOT/"01_rtl/cnn_result_stabilizer.v"')
    text = text.replace(R11_PIPELINE_SHA, PIPELINE_SHA)
    text = text.replace('.LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(24)',
                        '.LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(22),.AREA_SHIFT(6)')
    text = text.replace('ROOT/"02_sim/cnn_stability/reference_trace.jsonl"',
        'ROOT/"02_sim/cnn_area_pipeline_release/origin/reference_trace.jsonl"')
    script = directory / 'prove_release_area_domain.py'
    script.write_text(text)
    record(script)
    run_command(directory, 'prove_domain', [sys.executable, script])
    result = json.loads((directory / 'AREA_DOMAIN_PROOF.json').read_text())
    require(result['status'] == 'PASS_SOURCE_DERIVATION_AND_FINITE_INTEGER_CHECKS', 'Domain proof failed')
    counts = result['integer_checks']
    require(counts['code_domain_size'] == 65536 and counts['raw_replay_frames'] == 1170, 'Domain coverage drift')
    return {'status': 'PASS', 'fresh': True, 'source_pipeline_sha256': PIPELINE_SHA,
            'source_kernel_sha256': KERNEL_SHA, 'coverage': counts}


def fresh_kernel_reference():
    directory = OUT / 'kernel_reference'
    directory.mkdir()
    sealed = OUT / 'sealed_origin/reports/kernel_area_overlap_combined_candidate/production_reference'
    bench = freeze(sealed / 'tb_cnn_stability_serial.sv', directory / 'tb_cnn_stability_serial.sv')
    vectors = freeze(sealed / 'vectors.txt', directory / 'vectors.txt')
    output = simulate(directory, [KERNEL, bench], 'tb_cnn_stability_serial')
    match = re.search(r'PASS SERIAL_GOLD checks=(\d+) vectors=(\d+) emitted=(\d+) bank_reuses=(\d+) clear_boundaries=(\d+) max_latency_cycles=(\d+)', output)
    require(match is not None, 'Kernel integer reference completion missing')
    counts = tuple(map(int, match.groups()))
    require(counts == (3240, 3307, 2059, 3247, 2, 857), 'Integer gold coverage drift')
    result = {'status': 'PASS', 'fresh_rtl_replay': True,
        'oracle_vectors': 'True copy of sealed independent integer-reference expectations; origin generation evidence retained',
        'checks': dict(zip(('gold_checks','events','serial_records','bank_reuses','clear_boundaries','max_cycles'), counts))}
    write_json(directory / 'RESULTS.json', result)
    return result


def fresh_kernel_lifecycle():
    directory = OUT / 'kernel_lifecycle'
    directory.mkdir()
    sealed = OUT / 'sealed_origin/reports/kernel_area_overlap_combined_candidate/state_lifecycle'
    bench = freeze(sealed / 'tb_combined_state_lifecycle.sv', directory / 'tb_combined_state_lifecycle.sv')
    baseline = freeze(sealed / 'cnn_result_stabilizer_baseline.v', directory / 'cnn_result_stabilizer_baseline.v')
    vectors = freeze(sealed / 'c3h2l3.txt', directory / 'vectors.txt')
    records = []
    for external in (0, 1):
        output = simulate(directory, [baseline, KERNEL, bench], 'tb_combined_state_lifecycle',
                          'reader' + str(external), ['-gEXTERNAL_CANDIDATE_READER=' + str(external)])
        match = re.search(r'PASS COMBINED_STATE_LIFECYCLE coord=3 area=22 reader=(\d+) params=3/2/3 vectors=(\d+) gold=(\d+) jobs=(\d+) cycles=(\d+) serial=(\d+) reuses=(\d+) aborts=(\d+)', output)
        require(match is not None, 'Lifecycle completion missing')
        counts = tuple(map(int, match.groups()))
        require(counts[0] == external and counts[1:3] == (2385, 2315) and counts[-1] == 56,
                'Lifecycle coverage changed')
        records.append(dict(zip(('external_reader','vectors','gold','jobs','cycles','serial','reuses','aborts'), counts)))
    result = {'status': 'PASS', 'fresh_rtl_replay': True, 'modes': records,
              'abort_scope': 'All 28 FSM states; clear and asynchronous reset at every state, each reader mode',
              'all_parameter_mode_origin': 'Sealed ten-mode lifecycle retained separately, identical kernel hash'}
    write_json(directory / 'RESULTS.json', result)
    return result


def main():
    started = now()
    require(not OUT.exists(), 'Never overwrite release regression evidence')
    require(sha(PIPELINE) == PIPELINE_SHA and sha(KERNEL) == KERNEL_SHA, 'Production source drift')
    for name in ('LICENSE.TXT', 'vlib.exe', 'vlog.exe', 'vsim.exe'):
        require((SIM / name).is_file(), 'Missing simulator/license file ' + name)
    record(PIPELINE, PIPELINE_SHA)
    record(KERNEL, KERNEL_SHA)
    record(Path(__file__))
    for path in (ROOT/'01_rtl/secondary_top.v', ROOT/'01_rtl/cnn_core.v', ROOT/'lint_full.f'):
        record(path)
    OUT.mkdir(parents=True)
    results = {'status':'RUNNING','started_utc':started,'hardware_status':'NOT_RUN','production_modified':False,'td_run':False}
    try:
        freeze(SPLIT/'01_rtl/vision_pipeline.v', OUT/'origin/vision_pipeline_r11.v', R11_PIPELINE_SHA)
        freeze(SPLIT/'01_rtl/cnn_result_stabilizer.v', OUT/'origin/cnn_result_stabilizer_r11.v', R11_KERNEL_SHA)
        freeze(OLD/'02_sim/cnn_stability/reference_trace.jsonl', OUT/'origin/reference_trace.jsonl',
               '04E7AB74BCF2A5DC0D2801F9880639EA2F60C05A98954E45761BD8A82F91FADE')
        for relative in ('verification/RESULTS.json','production_reference/RESULTS.json','state_lifecycle/RESULTS.json'):
            import_sealed_result(ORIGIN/relative)
        require(sha(OUT/'sealed_origin/reports/kernel_area_overlap_combined_candidate/cnn_result_stabilizer.v') == sha(KERNEL),
                'Historical exhaustive kernel is not current production bytes')
        origin_result = {'status':'PASS','scope':'Historical sealed scratch evidence, true copied and rehashed; not newly run',
                         'same_kernel_as_production':True,'forty_mode_miter':40,'ten_mode_lifecycle':10,'copies':COPIES}
        write_json(OUT/'ORIGIN_IMPORT.json', origin_result)
        # Run the longest test first, with actual release production source paths.
        results['pipeline_miter'] = fresh_pipeline_miter()
        results['domain'] = fresh_domain()
        results['kernel_reference'] = fresh_kernel_reference()
        results['kernel_lifecycle'] = fresh_kernel_lifecycle()
        for key,value in INPUTS.items():
            require(sha(key) == value, 'Input changed during regression: ' + key)
        results.update(status='PASS',completed_utc=now(),input_hashes=INPUTS,
            evidence_hashes={str(path.relative_to(OUT)):sha(path) for path in OUT.rglob('*')
                if path.is_file() and path.suffix in ('.json','.log','.txt','.py','.sv','.v','.jsonl')},
            production_pipeline_sha256=PIPELINE_SHA,production_kernel_sha256=KERNEL_SHA,
            source_to_input_domain='Current pinned R11 fixed-grid pipeline; all ordinary CCL area16 values shift left exactly six',
            limits=['Controlled inference/CCL/DDR leaves; no claim of image accuracy or physical hardware validation',
                    'Historical 40-mode and ten-mode evidence is explicitly imported; fresh tests are separately labelled'])
    except Exception as exc:
        results.update(status='FAIL',completed_utc=now(),error=repr(exc),input_hashes=INPUTS)
        raise
    finally:
        write_json(OUT/'RESULTS.json',results)
    print(json.dumps({'status':results['status'],'pipeline_miter':results['pipeline_miter'],
                      'result_sha256':sha(OUT/'RESULTS.json')},indent=2),flush=True)


if __name__ == '__main__':
    main()
