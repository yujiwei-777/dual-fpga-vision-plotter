"""Audit this exact independent routed main build, without bitgen.

Run only after run_build_phases_r4.py completes all three phases.  Every evidence
file is generated afresh in a new attempt directory.  Frozen build inputs and
the routed database are hash-checked before and after every subprocess.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[1]
BUILD = Path('E:/codex_pcb_suspect_center_main_20261113_r4')
RUN = BUILD / '01_rtl/imgq_gain_m/main/td_project_display_noise_v8'
NAME = 'camera_to_dsi_display_720p60_cnn_multibox'
TD = Path('E:/td/bin/td_commands_prompt.exe')
MANIFEST_SHA256 = '9CD6B85B690D3A4C9497C2889359F599D5032FF9F0C1D53604F7F4E6C538C4BF'
PHASE_RUNNER_SHA256 = '19491E381743FC7AA63389243DE8A6631451ED683AE7096C76BEF6CB0F8952BD'
SUMMARY_SHA256 = '18EE26D1E54A26AD846E52C79FFA233D6B0B9768720C5F9D387B765CA9D9AA15'
PHASES = (('synth', 'opt_gate'), ('place', 'opt_place'), ('route', 'opt_route'))
REPORTS = ('ts', 'timing', 'exceptions', 'check', 'area', 'clocks', 'flow')


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest().upper()


def read(path):
    raw = Path(path).read_bytes()
    return raw.decode('utf-16' if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8-sig')


def load(path):
    return json.loads(read(path))


def put(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2,
                                    allow_nan=False) + '\n', encoding='utf-8')


def stamp():
    return datetime.now(timezone.utc).isoformat()


def ref(path):
    path = Path(path).resolve()
    return {'path': path.as_posix(), 'sha256': sha(path), 'bytes': path.stat().st_size}


def check_sources():
    require(re.fullmatch(r'[0-9A-F]{64}', MANIFEST_SHA256) and re.fullmatch(r'[0-9A-F]{64}', PHASE_RUNNER_SHA256),
            'R4 release pins not supplied; refusing audit')
    require(SOURCE.name == 'main_pcb_suspect_center_20261113', 'Unexpected source project')
    require(BUILD.resolve() == Path('E:/codex_pcb_suspect_center_main_20261113_r4').resolve(),
            'Unexpected build root')
    require(not BUILD.is_symlink() and not (BUILD.stat().st_file_attributes & 0x400),
            'Linked build root is forbidden')
    manifest = BUILD / 'SOURCE_MANIFEST.json'
    require(sha(manifest) == MANIFEST_SHA256, 'Wrong current-build source manifest')
    records = load(manifest)['files']
    require(bool(records), 'Empty source manifest')
    for relative, row in records.items():
        path = (BUILD / relative).resolve()
        require(path.is_relative_to(BUILD.resolve()) and 'work' not in
                [part.lower() for part in path.parts], 'Escaping/protected input: ' + relative)
        require(path.is_file() and sha(path) == row['sha256'], 'Frozen input changed: ' + relative)
    plan = load(BUILD / 'BUILD_PLAN.json')
    require(plan['source_manifest_sha256'] == MANIFEST_SHA256, 'BUILD_PLAN closure mismatch')
    require(sha(SOURCE / 'tools/run_build_phases_r4.py') == PHASE_RUNNER_SHA256,
            'Current source phase runner changed')
    require(sha(BUILD / 'audits/summarize_readonly.py') == SUMMARY_SHA256,
            'Prepared current-build static summary changed')
    return len(records)


def check_phases():
    current = load(BUILD / 'logs/CURRENT.json')
    require(current.get('phase') == 'route' and current.get('status') == 'COMPLETE'
            and current.get('passed') is True, 'Current route has not completed successfully')
    rows = []
    for phase, marker in PHASES:
        path = BUILD / 'logs' / (phase + '.json')
        row = load(path)
        script = RUN / ('run_display_noise_' + phase + '.tcl')
        log = BUILD / 'logs' / (phase + '.log')
        require(row.get('phase') == phase and row.get('passed') is True
                and row.get('returncode') == 0 and row.get('completion_marker') is True,
                'Missing/failed current phase: ' + phase)
        require(Path(row['cwd']).resolve() == RUN.resolve()
                and row['source_manifest_sha256'] == MANIFEST_SHA256
                and row['script_sha256'] == sha(script) and row['td_sha256'] == sha(TD)
                and row['log_sha256'] == sha(log), 'Phase provenance mismatch: ' + phase)
        require((RUN / ('.' + marker + '.end.f')).is_file(), 'Missing completion marker: ' + phase)
        require(row.get('errors') == [], 'Phase recorded errors: ' + phase)
        require(row['runner_sha256'] == PHASE_RUNNER_SHA256,
                'Current phase runner mismatch: ' + phase)
        rows.append({'receipt': ref(path), 'log': ref(log), 'ended_utc': row['ended_utc']})
    require(not (RUN / '.stop.f').exists() and not list(RUN.glob('.*.error.f')),
            'Stop/error marker in current run')
    return rows


def bound_inputs():
    paths = (BUILD / 'SOURCE_MANIFEST.json', BUILD / 'BUILD_PLAN.json',
             RUN / (NAME + '.al'), RUN / (NAME + '.prj'),
             RUN / (NAME + '_gate.db'), RUN / (NAME + '_pr.db'),
             RUN / (NAME + '_pr.timing'), RUN / (NAME + '_phy.area'),
             RUN / 'source_snapshot.json')
    return {path.resolve().as_posix(): sha(path) for path in paths}


def no_changed(bound):
    check_sources()
    require(bound == bound_inputs(), 'Build source/project/database/report changed during audit')


def launch(command, cwd, log, bound):
    require(not log.exists(), 'Refusing existing log: ' + str(log))
    no_changed(bound)
    started = stamp()
    with log.open('xb') as stream:
        result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    no_changed(bound)
    receipt = {'started_utc': started, 'ended_utc': stamp(), 'command': command,
               'cwd': str(cwd), 'returncode': result.returncode, 'log': ref(log)}
    put(log.with_suffix('.receipt.json'), receipt)
    require(result.returncode == 0, 'Audit command failed; inspect ' + str(log))


PHYSICAL_TCL = r'''
    # Fresh current-routed-database exports; device topology is reference-only.
    set expected [open "$audit/expected_slice_cells.tsv" w]
    puts $expected "cell\tref_name"
    set l_count 0
    set m_count 0
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        if {$ref eq "PH1P_PHY_LSLICE" || $ref eq "PH1P_PHY_MSLICE"} {
            puts $expected "$cell\t$ref"
            if {$ref eq "PH1P_PHY_LSLICE"} {incr l_count} else {incr m_count}
        }
    }
    close $expected
    puts "EXPECTED_SLICE_COUNTS L=$l_count M=$m_count"
    puts READONLY_EXPECTED_SLICE_EXPORT_DONE
    set sites [open "$audit/readonly.sites.tsv" w]
    puts $sites "cell\tref_name\tis_placed\tcol\trow\toffset"
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        puts $sites "$cell\t$ref\t[get_property -quiet IS_PLACED $cell]\t[get_property -quiet PLACED_COL $cell]\t[get_property -quiet PLACED_ROW $cell]\t[get_property -quiet PLACED_OFFSET $cell]"
    }
    close $sites
    foreach tile {x31y49 x15y64 x2y1 x31y1 x9y1 x2y40 x9y40} {
        puts "TILE_QUERY_BEGIN $tile"
        puts "TILE_QUERY_STATUS=[catch {report_tile $tile} tile_reason]"
        puts "TILE_QUERY_END"
    }
'''


def run(args):
    count = check_sources()
    phases = check_phases()
    bound = bound_inputs()
    attempt = args.attempt or datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    require(re.fullmatch(r'[A-Za-z0-9_-]+', attempt) is not None, 'Unsafe attempt name')
    out = BUILD / 'audits' / ('route_acceptance_' + attempt)
    require(not out.exists(), 'Preserve prior evidence; choose a new --attempt')
    out.mkdir()
    start = {'schema': 'main-suspect-center-current-route-audit-r4-v1', 'started_utc': stamp(),
             'runner': ref(__file__), 'build_root': BUILD.as_posix(), 'td': ref(TD),
             'source_manifest_sha256': MANIFEST_SHA256, 'source_files_checked': count,
             'phases': phases, 'bound_input_hashes': bound, 'hardware_status': 'NOT_RUN',
             'bitgen_invoked': False, 'passed': False}
    put(out / 'START.json', start)
    try:
        generic = [sys.executable, '-B', str(BUILD / 'tools/td_release_audit.py')]
        common = ['--root', str(BUILD), '--run', str(RUN), '--name', NAME]
        gate = out / 'release_gate.json'
        command = generic + ['gate'] + common + ['--config', str(BUILD / 'tools/release_audit_config.json'),
            '--snapshot', str(RUN / 'source_snapshot.json'), '--output', str(gate)]
        for phase, _ in PHASES:
            command += ['--log', str(BUILD / 'logs' / (phase + '.log'))]
        launch(command, BUILD, out / 'generic_gate.log', bound)
        require(load(gate).get('passed') is True, 'Generic gate did not pass')

        tcl = out / 'readonly_reimport.tcl'
        launch(generic + ['reimport-template'] + common + ['--audit-dir', str(out), '--output', str(tcl)],
               BUILD, out / 'template_generation.log', bound)
        script = read(tcl)
        needle = '    flow_status -file "$audit/readonly.flow"'
        require(script.count(needle) == 1, 'Unexpected frozen read-only template')
        script = script.replace(needle, PHYSICAL_TCL + '\n' + needle)
        require(not re.search(r'^\s*(?:clear_sdc|read_sdc|read_adc|export_db|place|route|optimize\w*|bitgen|save_project|project_save)\b', script, re.M),
                'Forbidden command in read-only template')
        tcl.write_text(script, encoding='utf-8')
        require(load(out / 'readonly_input_hashes.json') ==
                {str(path.resolve()).replace('\\', '/'): sha(path)
                 for path in (RUN / (NAME + '.al'), RUN / (NAME + '_pr.db'))},
                'Template does not bind exact current AL and routed DB')
        launch([str(TD), tcl.name], out, out / 'readonly_launcher.log', bound)
        text = read(out / 'readonly_launcher.log')
        require(text.splitlines().count('TD_READONLY_REIMPORT_PASS') == 1,
                'Missing/duplicate read-only completion marker')
        require(not re.search(r'\b(?:ERROR|FATAL)\b|TD_READONLY_REIMPORT_FAIL|HDL-5105', text),
                'Read-only tool log contains error/fatal/missing ROM')
        require(all((out / ('readonly.' + suffix)).is_file() for suffix in REPORTS),
                'Read-only report incomplete')
        launch(generic + ['verify-readonly'] + common + ['--audit-dir', str(out),
            '--log', str(out / 'readonly_launcher.log'), '--output', str(out / 'readonly_verification.json')],
            BUILD, out / 'verify_readonly.log', bound)
        require(load(out / 'readonly_verification.json').get('passed') is True,
                'Read-only generic verification did not pass')

        static = BUILD / 'tools/physical_capacity'
        command = [sys.executable, '-B', str(static / 'validate_device_capacity.py')]
        inputs = {'chip': static / 'ph1_35p_device_dump.txt_chip',
                  'routing': static / 'ph1_35p_device_dump.txt_connmngr',
                  'datasheet': static / 'DS1300_logic_and_dram_excerpt.txt',
                  'resource-report': static / 'physical_device_resources.txt',
                  'tile-report': out / 'readonly_launcher.log',
                  'expected-cells': out / 'expected_slice_cells.tsv',
                  'expected-log': out / 'readonly_launcher.log',
                  'placements': out / 'readonly.sites.tsv', 'out': out / 'physical_capacity'}
        for key, path in inputs.items():
            command += ['--' + key, str(path)]
        launch(command, BUILD, out / 'capacity_validator.log', bound)
        physical_path = out / 'physical_capacity/physical_capacity_validation.json'
        physical = load(physical_path)
        used = load(gate)['resources']['slice']['used']
        require(physical.get('passed') is True and physical['expected_slices'] == used
                and physical['placed_compatible_unique_slices'] == used,
                'Current independent placed-site census disagrees with current route area')
        launch([sys.executable, '-B', str(BUILD / 'audits/summarize_readonly.py'),
            '--route-log', str(BUILD / 'logs/route.log'), '--audit-dir', str(out),
            '--release-gate', str(gate), '--readonly-verification', str(out / 'readonly_verification.json'),
            '--readonly-script', str(tcl), '--readonly-log', str(out / 'readonly_launcher.log')],
            BUILD, out / 'summary.log', bound)
        summary = out / 'READONLY_AUDIT_REPORT.json'
        require(load(summary).get('passed') is True, 'Current routed static summary failed')
        no_changed(bound)
        put(out / 'CURRENT_ROUTE_ACCEPTANCE.json', dict(start, passed=True, ended_utc=stamp(),
            generic_gate=ref(gate), readonly_summary=ref(summary), physical_capacity=ref(physical_path),
            scope='Current source closure, fresh synth/place/route receipts, strict routed resource/timing gates, native final DRC, unchanged AL/DB reimport, full current placed Slice census. Functional regression and hardware acceptance are separate.'))
        print('CURRENT_ROUTE_ACCEPTANCE_PASS ' + out.as_posix(), flush=True)
        return 0
    except Exception as exc:
        put(out / 'CURRENT_ROUTE_ACCEPTANCE.json', dict(start, passed=False, ended_utc=stamp(), error=str(exc)))
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attempt', help='Fresh evidence suffix; existing attempts are never overwritten')
    args = parser.parse_args()
    try:
        return run(args)
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        print('CURRENT_ROUTE_ACCEPTANCE_FAILED: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
