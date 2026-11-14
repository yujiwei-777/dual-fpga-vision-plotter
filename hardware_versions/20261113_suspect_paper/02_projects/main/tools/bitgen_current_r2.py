"""Generate and publish only the strictly accepted current main diagnostic bit.

Nothing runs on import.  All vendor outputs first go to a fresh build audit
staging directory; publication requires current gate/regression/source checks
and unchanged routed timing/area plus AL/DB/control hashes after bitgen.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
from audit_current_route_r2 import (BUILD, SOURCE, RUN, NAME, TD, MANIFEST_SHA256,
    SUMMARY_SHA256, bound_inputs, check_sources, check_phases, load, no_changed,
    put, read, ref, require, sha, stamp)

STEM = 'dual_fpga_main_20261113_pcb_suspect_center_diagnostic'


def check_ref(row, root=None):
    path = Path(row['path']).resolve()
    if root is not None:
        require(path.is_relative_to(Path(root).resolve()), 'Evidence outside allowed root: ' + str(path))
    require(path.is_file() and sha(path) == row['sha256'], 'Evidence hash mismatch: ' + str(path))
    if 'bytes' in row:
        require(path.stat().st_size == row['bytes'], 'Evidence length mismatch: ' + str(path))
    return path


def check_regression(path, center):
    path = Path(path).resolve()
    require(path.is_relative_to(SOURCE / 'reports'), 'Regression is outside current source reports')
    value = load(path)
    require(value.get('status') == 'PASS' and value.get('frozen_manifest_sha256') == MANIFEST_SHA256,
            'Regression did not pass current frozen build: ' + str(path))
    require(value.get('hardware_status') == 'NOT_RUN', 'Unexpected regression hardware claim')
    require(value.get('inputs_unchanged') is True if center else value.get('input_drift') == [],
            'Regression input drift recorded')
    inputs = value.get('inputs', {})
    require(len(inputs) > 10, 'Regression lacks actual source inputs')
    baseline_control = SOURCE.parent / 'main_pcb_operator_ui_cn_font_shift1_dynamic_osd_20261113/01_rtl/imgq_gain_m/main/user_source/hdl_source'
    for item, row in inputs.items():
        target = Path(item).resolve()
        baseline_miter = target.parent == baseline_control.resolve() and target.name in (
            'hx_result_select.v', 'hdmi_mixer.v')
        require(target.is_relative_to(SOURCE) or target.is_relative_to(BUILD)
                or (center and baseline_miter),
                'Regression input outside current variant/build: ' + item)
        check_ref(dict(row, path=item))
    tests = {'center': value['result']} if center else value['tests']
    require(set(tests) == ({'center'} if center else {'dynamic_status', 'type21_maintenance'}),
            'Missing current regression cases')
    logs = []
    for name, result in tests.items():
        require(result.get('status') == 'PASS', 'Regression case failed: ' + name)
        steps = result.get('steps', [])
        require([step['step'] for step in steps] == ['vlib', 'compile', 'simulation'],
                'Incomplete regression execution: ' + name)
        for step in steps:
            require(step['returncode'] == 0, 'Regression subprocess failed: ' + name)
            logfile = Path(step['log']).resolve()
            require(logfile.is_relative_to(path.parent) and sha(logfile) == step['log_sha256'],
                    'Regression log provenance mismatch: ' + str(logfile))
            require(not re.search(r'\*\*\s+(?:Error|Fatal):|\b(?:REGRESSION_FAILED|TEST_FAILED)\b', read(logfile)),
                    'Regression log contains a failure: ' + str(logfile))
            logs.append(ref(logfile))
        simulation = read(Path(steps[-1]['log']))
        marker = 'SUSPECT_CENTER_PASS ' if center else result['marker']
        require(simulation.count(marker) == 1, 'Missing/duplicate actual simulation PASS marker: ' + name)
    if center:
        require(value.get('marker', '').startswith('# SUSPECT_CENTER_PASS checks=30 '),
                'Unexpected center-check coverage')
        require(sha(path.parent / 'tb_suspect_center.sv') == value['generated_test_sha256'],
                'Generated center test changed')
        for name, digest in value['generated_control_sha256'].items():
            require(sha(path.parent / ('control_' + name)) == digest, 'Generated baseline miter changed')
    return {'result': ref(path), 'logs': logs, 'scope': value['scope']}


def controls(path):
    path = Path(path).resolve()
    require(path.is_relative_to(SOURCE / 'reports'), 'Control receipt outside current source reports')
    value = load(path)
    require(value['build_manifest_sha256'] == MANIFEST_SHA256, 'Control manifest mismatch')
    paths = value.get('baseline_files', {})
    require(len(paths) >= 200, 'Incomplete original baseline/control receipt')
    allowed = (SOURCE.parent / 'main_pcb_operator_ui_cn_font_shift1_dynamic_osd_20261113',
               SOURCE.parent / 'secondary_pcb_airwalk_stroke_cont_20261113/artifacts')
    for target, digest in paths.items():
        resolved = Path(target).resolve()
        require(any(resolved.is_relative_to(root.resolve()) for root in allowed)
                and 'work' not in [part.lower() for part in resolved.parts],
                'Unexpected protected/control path: ' + target)
        require(resolved.is_file() and sha(resolved) == digest, 'Baseline/control changed: ' + target)
    source_snapshot = SOURCE / '01_rtl/imgq_gain_m/main/td_project_display_noise_v8/source_snapshot.json'
    require(sha(source_snapshot) == value['source_project_snapshot_sha256'], 'Source project closure changed')
    source = load(source_snapshot)
    require(source.get('passed') is True and Path(source['project_root']).resolve() == SOURCE.resolve(),
            'Wrong/unpassed source project snapshot')
    for row in source.get('files', []):
        actual = Path(row['path']).resolve()
        require(actual.is_relative_to(SOURCE.resolve()), 'Source dependency escaped independent source')
        check_ref(row)
    return {'receipt': ref(path), 'baseline_files_checked': len(paths),
            'source_snapshot': ref(source_snapshot), 'source_active_files_checked': len(source['files'])}


def acceptance(path):
    path = Path(path).resolve()
    require(path.is_relative_to(BUILD / 'audits') and path.name == 'CURRENT_ROUTE_ACCEPTANCE.json',
            'Acceptance must be this build current-route acceptance report')
    value = load(path)
    require(value.get('passed') is True and value.get('bitgen_invoked') is False
            and value.get('source_manifest_sha256') == MANIFEST_SHA256
            and Path(value['build_root']).resolve() == BUILD.resolve(),
            'Current strict route acceptance is missing/failed/wrong-build')
    require(value['bound_input_hashes'] == bound_inputs(), 'Routed accepted inputs have changed')
    check_ref(value['runner'], SOURCE / 'tools')
    check_ref(value['td'])
    for key in ('generic_gate', 'readonly_summary', 'physical_capacity'):
        evidence = check_ref(value[key], path.parent)
        require(load(evidence).get('passed') is True, 'Accepted report did not pass: ' + key)
    generic = load(Path(value['generic_gate']['path']))
    summary = load(Path(value['readonly_summary']['path']))
    require(summary['source_manifest_file_sha256'] == MANIFEST_SHA256
            and summary['route_gate']['route_db']['sha256'] == sha(RUN / (NAME + '_pr.db')),
            'Summary not bound to exact current DB/manifest')
    # Revalidate report/log provenance; a PASS string by itself is insufficient.
    check_ref(summary['route_gate']['native_log'], BUILD)
    check_ref(summary['route_gate']['generic_gate'], path.parent)
    readonly = summary['readonly_reimport']
    require(readonly['input_hashes_unchanged'] is True and readonly['completion_marker_count'] == 1,
            'Readonly invariance/marker evidence missing')
    for row in list(readonly['reports'].values()) + readonly['scripts']:
        check_ref(row, path.parent)
    for row in readonly['log_scans']:
        check_ref(row['file'], path.parent)
    for key in ('verification_file', 'input_hashes_file'):
        check_ref(readonly[key], path.parent)
    return value, generic, summary


def timing_parser():
    path = BUILD / 'audits/summarize_readonly.py'
    require(sha(path) == SUMMARY_SHA256, 'Pinned static parser changed')
    spec = importlib.util.spec_from_file_location('current_frozen_summary', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TCL = r'''# Current routed DB -> fresh diagnostic staging only.
set build {@RUN@}
set audit {@OUT@}
set name {@NAME@}
set bit {@BIT@}
set bid {@BID@}
cd $build
if {[file exists $bit] || [file exists $bid]} {error "Refusing staged bit/BID overwrite"}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    update_timing -mode final
    report_timing_status -file "$audit/pre_bitgen.ts"
    report_timing_summary -file "$audit/pre_bitgen.timing"
    report_area -io_info -file "$audit/pre_bitgen.area"
    check_timing -verbose -file "$audit/pre_bitgen.check"
    commit_param -step bitgen
    bitgen -bit $bit
    if {![file exists $bit] || [file size $bit] < 100000} {error "Missing/truncated staged bit"}
    export_bid $bid
    if {![file exists $bid] || [file size $bid] < 100} {error "Missing/truncated staged BID"}
    export_bitgen_param -file "$audit/checked_bitgen_param.f"
    update_timing -mode final
    report_timing_summary -file "$audit/post_bitgen.timing"
    report_area -io_info -file "$audit/post_bitgen.area"
    set marker [open "$audit/bitgen.end.json" w]
    puts $marker "{\"status\":\"PASS\",\"bit_bytes\":[file size $bit],\"bid_bytes\":[file size $bid]}"
    close $marker
    puts TD_BITGEN_PASS
} reason]} {
    puts "TD_BITGEN_FAIL: $reason"
    exit 1
}
exit 0
'''


def run(args):
    count = check_sources()
    check_phases()
    bound = bound_inputs()
    accepted, generic, summary = acceptance(args.acceptance)
    regression = {'center': check_regression(args.center_result, True),
                  'controls': check_regression(args.controls_result, False)}
    baseline = controls(args.control_integrity)
    parser = timing_parser()
    attempt = args.attempt or datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    require(re.fullmatch(r'[A-Za-z0-9_-]+', attempt) is not None, 'Unsafe attempt suffix')
    out = BUILD / 'audits' / ('bitgen_' + attempt)
    require(not out.exists(), 'Preserve prior bitgen evidence; choose a fresh --attempt')
    artifacts = SOURCE / 'artifacts'
    require(artifacts.is_dir() and not artifacts.is_symlink()
            and not (artifacts.stat().st_file_attributes & 0x400), 'Unsafe source artifacts directory')
    final_bit, final_bid = artifacts / (STEM + '.bit'), artifacts / (STEM + '.bid')
    final_receipt = artifacts / 'RELEASE_REPORT.json'
    require(not any(path.exists() for path in (final_bit, final_bid, final_receipt)),
            'Refusing existing final artifact/receipt; no target overwrite permitted')
    out.mkdir()
    staged_bit, staged_bid = out / (STEM + '.bit'), out / (STEM + '.bid')
    script = TCL
    for key, val in {'RUN': RUN.as_posix(), 'OUT': out.as_posix(), 'NAME': NAME,
                     'BIT': staged_bit.as_posix(), 'BID': staged_bid.as_posix()}.items():
        script = script.replace('@' + key + '@', val)
    tcl = out / 'bitgen.tcl'
    tcl.write_text(script, encoding='utf-8')
    require(script.count('    bitgen -bit $bit') == 1 and script.count('    import_db ') == 1,
            'Unexpected staged bitgen script')
    receipt = {'schema': 'main-suspect-center-diagnostic-release-r2-v1', 'status': 'NOT_PUBLISHED',
               'started_utc': stamp(), 'runner': ref(__file__), 'script': ref(tcl), 'td': ref(TD),
               'route_acceptance': ref(args.acceptance), 'source_manifest_sha256': MANIFEST_SHA256,
               'source_files_checked': count, 'regressions': regression, 'control_integrity': baseline,
               'input_hashes_before_bitgen': bound, 'hardware_status': 'NOT_RUN',
               'localization_accuracy': 'Display center cross only; no improvement in localization accuracy claimed. Pad localization remains below the prior per-class 80% target.',
               'limits': ['CDC/FIFO/DDR reports are static evidence; no current DDR runtime calibration or traffic proof is certified.',
                          'RTL display/control regressions are targeted; no whole-board IP functional simulation claimed.',
                          'Mechanical drawing, paper load/eject and paired-board operation require hardware tests.']}
    put(out / 'PRE_BITGEN_GATE.json', receipt)
    log = out / 'td_bitgen.log'
    try:
        no_changed(bound)
        controls(args.control_integrity)
        with log.open('xb') as stream:
            result = subprocess.run([str(TD), tcl.name], cwd=out, stdout=stream, stderr=subprocess.STDOUT)
        no_changed(bound)
        controls(args.control_integrity)
        require(result.returncode == 0, 'Vendor bitgen process failed')
        text = read(log)
        require(text.splitlines().count('TD_BITGEN_PASS') == 1
                and not re.search(r'\b(?:ERROR|FATAL)\b|TD_BITGEN_FAIL|HDL-5105', text),
                'Missing/duplicate completion marker or vendor bitgen error')
        marker = load(out / 'bitgen.end.json')
        require(marker.get('status') == 'PASS' and staged_bit.stat().st_size >= 100000
                and staged_bid.stat().st_size >= 100
                and marker['bit_bytes'] == staged_bit.stat().st_size
                and marker['bid_bytes'] == staged_bid.stat().st_size,
                'Staged bit/BID/end-marker integrity failed')
        for prefix in ('pre_bitgen', 'post_bitgen'):
            timing = parser.parse_timing(read(out / (prefix + '.timing')))
            area = parser.parse_area(read(out / (prefix + '.area')))
            require(timing['passed'] and area['passed']
                    and timing['metrics_ns'] == generic['timing_ns']
                    and area['resources'] == generic['resources'],
                    'Current bitgen timing/area differs from accepted routed reports: ' + prefix)
        require(parser.parse_check(read(out / 'pre_bitgen.check'))['passed_core_static_checks'],
                'Current bitgen core static checks failed')
        require((out / 'checked_bitgen_param.f').is_file(), 'Bitgen parameter receipt missing')
        # Every input/report is rechecked before any final bit is visible.
        acceptance(args.acceptance)
        check_regression(args.center_result, True)
        check_regression(args.controls_result, False)
        controls(args.control_integrity)
        no_changed(bound)
        staged = {'bit': ref(staged_bit), 'bid': ref(staged_bid)}
        receipt.update(status='PASS_STAGED_NOT_YET_PUBLISHED', completed_utc=stamp(),
            returncode=result.returncode, log=ref(log), end_marker=ref(out / 'bitgen.end.json'),
            staged=staged, timing_ns=generic['timing_ns'], resources=generic['resources'],
            input_hashes_after_bitgen=bound_inputs(), input_hashes_unchanged=True,
            pre_bitgen_timing=ref(out / 'pre_bitgen.timing'), post_bitgen_timing=ref(out / 'post_bitgen.timing'),
            pre_bitgen_area=ref(out / 'pre_bitgen.area'), post_bitgen_area=ref(out / 'post_bitgen.area'),
            bitgen_parameters=ref(out / 'checked_bitgen_param.f'))
        put(out / 'BITGEN_RECEIPT.json', receipt)
        temporary = []
        for staged_path, final_path in ((staged_bit, final_bit), (staged_bid, final_bid)):
            temp = artifacts / ('.' + final_path.name + '.' + attempt + '.part')
            with staged_path.open('rb') as src, temp.open('xb') as dst:
                shutil.copyfileobj(src, dst)
                dst.flush()
                os.fsync(dst.fileno())
            require(sha(temp) == sha(staged_path), 'Publication copy hash mismatch')
            temporary.append((temp, final_path))
        no_changed(bound)
        controls(args.control_integrity)
        require(not any(path.exists() for path in (final_bit, final_bid, final_receipt)),
                'Final destination appeared during bitgen; refuse overwrite')
        for temp, final_path in temporary:
            os.rename(temp, final_path)  # Windows refuses an existing destination.
        require(sha(final_bit) == staged['bit']['sha256'] and sha(final_bid) == staged['bid']['sha256'],
                'Published bit/BID integrity failed')
        receipt.update(status='PASS_DIAGNOSTIC_NOT_RUN', bit=ref(final_bit), bid=ref(final_bid),
            publication_completed_utc=stamp(), staged_bitgen_receipt=ref(out / 'BITGEN_RECEIPT.json'))
        # The final receipt is the publication-complete marker; never overwrite.
        with final_receipt.open('x', encoding='utf-8') as stream:
            json.dump(receipt, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write('\n')
        print('CURRENT_DIAGNOSTIC_BITGEN_PASS ' + final_bit.as_posix(), flush=True)
        print(json.dumps({'bit': ref(final_bit), 'bid': ref(final_bid), 'receipt': ref(final_receipt)}, indent=2))
        return 0
    except Exception as exc:
        receipt.update(status='FAILED_NOT_ACCEPTED_FOR_PUBLICATION', ended_utc=stamp(), error=str(exc))
        put(out / 'FAILED_BITGEN_RECEIPT.json', receipt)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--acceptance', required=True, type=Path,
                        help='Current strict CURRENT_ROUTE_ACCEPTANCE.json from this r2 build')
    parser.add_argument('--center-result', type=Path, required=True)
    parser.add_argument('--controls-result', type=Path, required=True)
    parser.add_argument('--control-integrity', type=Path, required=True,
                        help='Current r2 source/baseline control-integrity receipt')
    parser.add_argument('--attempt', help='Fresh staged output suffix; never overwrites')
    args = parser.parse_args()
    try:
        return run(args)
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        print('CURRENT_DIAGNOSTIC_BITGEN_FAILED: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
