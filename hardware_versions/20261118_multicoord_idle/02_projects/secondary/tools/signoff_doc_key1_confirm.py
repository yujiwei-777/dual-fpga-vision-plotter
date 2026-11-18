"""Current routed signoff and strictly gated diagnostic bitgen.

No historical PASS is accepted. Device topology text is a frozen reference;
all placed cells, tile queries, DRC/timing and database imports are current.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
from build_doc_key1_confirm import (ROOT, BOARD, NAME, MAIN_RUN, MAIN_HDL, TD, DEFAULT_RUN,
    REPORT, LIMITS, validate, baseline_identity, require, sha, load, put, metrics, safe)
import doc_key1_confirm_strict_checks as strict

CHECKS = {'ordinary_cnn', 'pcb', 'document', 'writing_key2', 'doc_key1_confirm',
          'cancel_reentry', 'cdc', 'fifo', 'ddr'} if BOARD == 'secondary' else {
          'ordinary_cnn', 'pcb', 'document_preview', 'display_styles', 'cdc', 'fifo', 'ddr'}
PREVIEW_SOURCES = {'01_rtl/doc_copy_pipeline_shared_candidate.v', '01_rtl/secondary_top.v'} if BOARD == 'secondary' else {
    MAIN_HDL + name for name in ['doc_copy_preview_cdc.v', 'doc_copy_preview_ram.v',
    'doc_copy_overlay.v', 'hdmi_mixer.v', 'design_top_wrapper.v']}
if BOARD == 'main':
    PREVIEW_SOURCES.add('01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v')
GROUPS = {'control_d': 5, 'control_q': 9, 'control_regs': 5, 'gray_d': 52,
          'link_d': 1, 'request_q': 162, 'return_d': 128, 'return_q': 128,
          'same_domain_d': 60, 'stage2_d': 118}


def directories(run):
    return (run / 'runs/syn_1', run / 'runs/phy_1') if BOARD == 'secondary' else (run / MAIN_RUN, run / MAIN_RUN)


def read(path):
    return Path(path).read_text(encoding='utf-8-sig', errors='replace')


def evidence(path):
    path = Path(path).resolve()
    return {'path': str(path), 'sha256': sha(path)}


def immutable_inputs(run):
    syn, phy = directories(run)
    return {str(p): sha(p) for p in [phy / (NAME + '_pr.db'), phy / (NAME + '.al'),
            syn / (NAME + '_gate.db'), run / 'SOURCE_MANIFEST.json', run / 'BUILD_PLAN.json']}


def template(run):
    _, plan = validate(run)
    value = {'source_manifest_sha256': plan['source_manifest_sha256'],
        'routed_database_sha256': 'SET_AFTER_CURRENT_ROUTE',
        'checks': {name: False for name in sorted(CHECKS)},
        'evidence': {name: {'path': 'ABSOLUTE_CURRENT_REPORT', 'sha256': 'ACTUAL_SHA256',
            'status': 'PASS', 'source_sha256': {'RELATIVE_FROZEN_SOURCE': 'ACTUAL_SHA256'},
            'logs': [{'path': 'ABSOLUTE_CURRENT_LOG', 'sha256': 'ACTUAL_SHA256',
                      'pass_marker': 'ACTUAL_TEST_COMPLETION_MARKER'}]} for name in sorted(CHECKS)},
        'hardware_status': 'NOT_RUN'}
    put(REPORT / 'EXTERNAL_GATE_TEMPLATE.json', value)
    print(REPORT / 'EXTERNAL_GATE_TEMPLATE.json')


def prepare_readonly(run):
    run, plan = validate(run)
    syn, phy = directories(run)
    require((phy / '.opt_route.end.f').is_file() and (phy / (NAME + '_pr.db')).is_file(), 'Actual route prerequisite missing')
    out = run / 'signoff/readonly'
    require(not out.exists(), 'Preserve existing physical evidence; use a new signoff attempt directory')
    out.mkdir(parents=True)
    put(out / 'readonly_input_hashes.json', immutable_inputs(run))
    secondary = r'''
    source {../../04_pin/apply_reset_exceptions.tcl}
    source {../../04_pin/apply_cdc_exceptions.tcl}
    lassign [secondary_verify_reset_mapping preview_readonly] reset_targets reset_records
    lassign [secondary_verify_cdc_mapping preview_readonly] groups records
    set proof [open "$audit/current_cdc_mapping.rpt" w]
    puts $proof "CURRENT_PHYSICAL_CDC_READONLY_PASS"
    puts $proof "RESET_TARGETS [llength $reset_targets]"
    puts $proof "RESET_SYNCHRONIZERS [llength [secondary_reset_specs]]"
    foreach group [lsort [dict keys $groups]] {puts $proof "GROUP $group [llength [dict get $groups $group]]"}
    foreach row $reset_records {puts $proof "RESET_PROOF $row"}
    foreach row $records {puts $proof "CDC_PROOF $row"}
    close $proof
''' if BOARD == 'secondary' else ''
    script = r'''# Import/read/report only. No constraint reload or implementation command.
set build {@PHY@}
set audit {@OUT@}
set name {@NAME@}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -single_run
    load_run_param -run syn_1
    import_db "$build/${name}_pr.db"
    update_timing -mode final
@SECONDARY@
    report_timing_status -file "$audit/readonly.ts"
    report_timing_summary -file "$audit/readonly.timing"
    report_timing_exception -ep_num 4096 -path_num 4 -file "$audit/readonly.exceptions"
    check_timing -verbose -file "$audit/readonly.check"
    report_area -io_info -file "$audit/readonly.area"
    report_clock_utilization -file "$audit/readonly.clocks"
    report_drc -no_waivers -verbose -file "$audit/readonly.drc"
    report_path_skew -no_detailed_paths -file "$audit/readonly.skew"
    puts "RAW_CHECK_DESIGN_STATUS=[catch {check_design} raw_design_reason] REASON=$raw_design_reason"
    puts "CHECK_IO_STATUS=[catch {check_io} io_reason] REASON=$io_reason"
    puts "CHECK_PLB_STATUS=[catch {check_plb_attr -file "$audit/readonly.plb_check"} plb_reason] REASON=$plb_reason"
    export_sdc -file "$audit/readonly.exported.sdc"
    export_adc -verbose -file "$audit/readonly.exported.adc"
    export_io -verbose -file "$audit/readonly.io"
    set sites [open "$audit/readonly.sites.tsv" w]
    set expected [open "$audit/expected_slice_cells.tsv" w]
    puts $sites "cell\tref_name\tis_placed\tcol\trow\toffset"
    puts $expected "cell\tref_name"
    set l_count 0
    set m_count 0
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        puts $sites "$cell\t$ref\t[get_property -quiet IS_PLACED $cell]\t[get_property -quiet PLACED_COL $cell]\t[get_property -quiet PLACED_ROW $cell]\t[get_property -quiet PLACED_OFFSET $cell]"
        if {$ref eq "PH1P_PHY_LSLICE" || $ref eq "PH1P_PHY_MSLICE"} {
            puts $expected "$cell\t$ref"
            if {$ref eq "PH1P_PHY_LSLICE"} {incr l_count} else {incr m_count}
        }
    }
    close $sites
    close $expected
    puts "EXPECTED_SLICE_COUNTS L=$l_count M=$m_count"
    puts READONLY_EXPECTED_SLICE_EXPORT_DONE
    foreach tile {x31y49 x15y64 x2y1 x31y1 x9y1 x2y40 x9y40} {
        puts "TILE_QUERY_BEGIN $tile"
        puts "TILE_QUERY_STATUS=[catch {report_tile $tile} tile_reason]"
        puts "TILE_QUERY_END"
    }
    flow_status -file "$audit/readonly.flow"
    puts TD_READONLY_REIMPORT_PASS
} reason]} {
    puts "TD_READONLY_REIMPORT_FAIL: $reason"
    exit 1
}
exit 0
'''
    for key, value in {'PHY': phy.as_posix(), 'OUT': out.as_posix(), 'NAME': NAME, 'SECONDARY': secondary}.items():
        script = script.replace('@' + key + '@', value)
    path = out / 'readonly_reimport.tcl'
    path.write_text(script, encoding='utf-8')
    put(out / 'PREPARE.json', {'source_manifest_sha256': plan['source_manifest_sha256'],
        'script': evidence(path), 'readonly': True, 'bitgen_invoked': False})
    return out


def run_readonly(run):
    run, plan = validate(run)
    out = run / 'signoff/readonly'
    if not out.exists():
        prepare_readonly(run)
    log = out / 'console_readonly.log'
    require(not log.exists(), 'Refusing to overwrite physical log')
    inputs = load(out / 'readonly_input_hashes.json')
    require(inputs == immutable_inputs(run), 'Readonly prepared against a different current database')
    with log.open('xb') as stream:
        cp = subprocess.run([str(TD), 'readonly_reimport.tcl'], cwd=out, stdout=stream, stderr=subprocess.STDOUT)
    unchanged = all(Path(p).is_file() and sha(p) == digest for p, digest in inputs.items())
    text = read(log)
    result = {'status': 'IMPORTED_CURRENT_DB_NOT_YET_ACCEPTED', 'exit_code': cp.returncode,
        'inputs_unchanged': unchanged, 'log': evidence(log), 'source_manifest_sha256': plan['source_manifest_sha256'],
        'routed_database_sha256': inputs[str(directories(run)[1] / (NAME + '_pr.db'))], 'hardware_status': 'NOT_RUN'}
    put(out / 'readonly_verification.json', result)
    require(cp.returncode == 0 and unchanged and text.count('TD_READONLY_REIMPORT_PASS') == 1 and
            'TD_READONLY_REIMPORT_FAIL' not in text, 'Current read-only import failed')
    validate(run)
    physical_review(run)


def physical_review(run):
    run, plan = validate(run)
    syn, phy = directories(run)
    out = run / 'signoff/readonly'
    log = read(out / 'console_readonly.log')
    inputs = load(out / 'readonly_input_hashes.json')
    require(inputs == immutable_inputs(run), 'Readonly inputs changed after import')
    checks = {}
    synthesis = read(run / 'logs/syn.log')
    suspicious = [line for line in synthesis.splitlines() if re.search(
        r'HDL-5105|SYN-5033|unstable comb insts loops|TMR-250[79].*combinational loop|inferred latch|latch inferred', line, re.I)]
    protected_ddr = [line for line in suspicious if re.fullmatch(
        r"HDL-5369 WARNING: latch inferred for net '\*\*' in .*/ph1p35_ddr/ddr2/src/rtl/mc/alc_mc_top_all\.enc\.sv\(2464\)", line)]
    source_rows = load(run / 'SOURCE_MANIFEST.json')['files']
    ddr_sources = {p: row['sha256'] for p, row in source_rows.items()
        if p.endswith('/ph1p35_ddr/ddr2/src/rtl/mc/alc_mc_top_all.enc.sv')}
    illegal = [line for line in suspicious if line not in protected_ddr]
    checks['synthesis_logic'] = {'passed': not illegal and bool(ddr_sources) and len(protected_ddr) == 1,
        'errors': illegal, 'retained_encrypted_ddr_warning': protected_ddr,
        'protected_frozen_ddr_sources': ddr_sources,
        'scope': 'Only the unchanged encrypted DDR IP warning is retained; source scope forbids DDR changes. Any new latch/loop or missing ROM blocks release.'}
    checks['timing'] = strict.check_timing(read(out / 'readonly.timing'))
    checks['area'] = strict.check_area(read(out / 'readonly.area'))
    # The immutable device topology is not a prior design PASS. Current cell
    # enumeration and fresh report_tile queries are mandatory proof inputs.
    tool = run / 'tools/physical_capacity/validate_device_capacity.py'
    static = run / 'tools/physical_capacity'
    command = [sys.executable, '-B', str(tool)]
    paths = {'chip': static / 'ph1_35p_device_dump.txt_chip',
        'routing': static / 'ph1_35p_device_dump.txt_connmngr',
        'datasheet': static / 'DS1300_logic_and_dram_excerpt.txt',
        'resource-report': static / 'physical_device_resources.txt',
        'tile-report': out / 'console_readonly.log', 'expected-cells': out / 'expected_slice_cells.tsv',
        'expected-log': out / 'console_readonly.log', 'placements': out / 'readonly.sites.tsv',
        'out': out / 'physical_capacity'}
    for key, path in paths.items():
        command += ['--' + key, str(path)]
    cp = subprocess.run(command, capture_output=True)
    (out / 'capacity_validator.log').write_bytes(cp.stdout + cp.stderr)
    require(cp.returncode == 0, 'Current placed-site capacity proof failed')
    checks['placed_sites'] = strict.check_sites(out, checks['area']['resources'].get('slice', {}).get('used', -1))
    checks['check_design'] = strict.check_design(log, checks['placed_sites']['passed'])
    checks['check_io'] = strict.check_simple_command(log, 'check_io', 'CHECK_IO_STATUS')
    checks['check_plb'] = strict.check_plb(log)
    checks['drc'] = strict.check_drc(read(out / 'readonly.drc'))
    checks['readonly'] = {'passed': inputs == immutable_inputs(run) and log.count('TD_READONLY_REIMPORT_PASS') == 1,
                           'errors': []}
    categories = ['no clock', 'clock definition', 'invalid constraint', 'pll/clock buffer clock constraints',
                  'combinational loops', 'no path constraints', 'shadowed/ignored timing exception constraints']
    check_text = read(out / 'readonly.check')
    missing = [name for name in categories if 'checking ' + name + '(0)' not in check_text]
    checks['timing_checks'] = {'passed': not missing, 'errors': missing}
    clocks = read(out / 'readonly.clocks')
    ddr_usr = 'u_ddr/u_ddr2/usr_clk' if BOARD == 'secondary' else 'u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk'
    checks['ddr_clock'] = {'passed': bool(re.search(re.escape(ddr_usr) + r'\s*\|\s*7\.500', clocks)), 'errors': []}
    bad_clocks = re.findall(r'^.*(?:RTCLK-5078|USR-6113).*$', log, re.M)
    checks['clock_warnings'] = {'passed': not bad_clocks, 'errors': bad_clocks}
    if BOARD == 'secondary':
        mapping = read(out / 'current_cdc_mapping.rpt')
        groups = {k: int(v) for k, v in re.findall(r'^GROUP (\w+) (\d+)$', mapping, re.M)}
        checks['cdc_mapping'] = {'passed': groups == GROUPS and 'RESET_SYNCHRONIZERS 5' in mapping,
                                  'groups': groups, 'errors': []}
        effective = read(phy / 'secondary_effective_route_end.exceptions.rpt')
        rows = [tuple(map(int, row)) for row in re.findall(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+set_max_delay ', effective, re.M)]
        slacks = [float(v) for v in re.findall(r'^Slack\s*:\s*([-+\d.]+)ns?\s*$', effective, re.M)]
        checks['cdc_effective_delays'] = {'passed': [r[0] for r in rows] == [290, 128, 9, 52] and
            all(a == b and not c and not d for a, b, c, d in rows) and bool(slacks) and min(slacks) >= 0,
            'rows': rows, 'minimum_slack_ns': min(slacks) if slacks else None, 'errors': []}
    else:
        # Detailed mapped connectivity and dual-clock RAM proof are supplied
        # by the separately source-bound preview CDC regression/review row.
        # Require the actual routed SDC to retain all three bounded crossings.
        sdc = read(out / 'readonly.exported.sdc')
        expected = ['u_copy_preview_cdc/t_s1', 'u_copy_preview_cdc/v_s1', 'u_copy_preview_cdc/b_s1']
        absent = [name for name in expected if name not in sdc]
        checks['preview_constraints_present'] = {'passed': not absent, 'errors': absent,
            'scope': 'Presence only; current mapped CDC/RAM proof remains mandatory in external cdc gate.'}
    route = metrics(phy, True)
    checks['readonly_timing_matches_route'] = {'passed': checks['timing'].get('metrics_ns') == route['timing_ns'], 'errors': []}
    paths = [p for p in out.rglob('*') if p.is_file() and p.name != 'PHYSICAL_REVIEW.json']
    result = {'status': 'PASS_CURRENT_PHYSICAL_SIGNOFF' if all(row['passed'] for row in checks.values()) else 'PHYSICAL_REVIEW_REQUIRED',
        'passed': all(row['passed'] for row in checks.values()), 'checks': checks,
        'source_manifest_sha256': plan['source_manifest_sha256'], 'routed_database_sha256': sha(phy / (NAME + '_pr.db')),
        'evidence': [evidence(p) for p in paths],
        'review_toolchain': [evidence(Path(__file__)), evidence(ROOT / 'tools/doc_key1_confirm_strict_checks.py')],
        'hardware_status': 'NOT_RUN',
        'limits': ['Static implementation and simulation do not establish board DDR calibration, CDC MTBF, or mechanical quality.']}
    put(out / 'PHYSICAL_REVIEW.json', result)
    put(REPORT / 'PHYSICAL_REVIEW.json', result)
    print(json.dumps({'status': result['status'], 'checks': {k: v['passed'] for k, v in checks.items()}}, indent=2))
    return result


def external_gate(run, path):
    run, plan = validate(run)
    _, phy = directories(run)
    gate = load(path)
    manifest = load(run / 'SOURCE_MANIFEST.json')['files']
    require(gate.get('source_manifest_sha256') == plan['source_manifest_sha256'], 'External gate is not for this freeze')
    require(gate.get('routed_database_sha256') == sha(phy / (NAME + '_pr.db')), 'External gate is not for this route')
    require(all(gate.get('checks', {}).get(name) is True for name in CHECKS), 'Missing current functional checks')
    covered = set()
    for name in sorted(CHECKS):
        row = gate.get('evidence', {}).get(name, {})
        require(row.get('status') == 'PASS', 'Current evidence is not PASS: ' + name)
        report = safe(row.get('path', ''))
        require(report.is_relative_to(ROOT) and report.is_file() and sha(report) == row.get('sha256'), 'Current report missing/drifted/outside variant: ' + name)
        sources = row.get('source_sha256', {})
        require(bool(sources), 'Evidence needs tested source hashes: ' + name)
        for relative, digest in sources.items():
            require(relative in manifest and manifest[relative]['sha256'] == digest and sha(run / relative) == digest,
                    'Evidence was not run against current frozen bytes: ' + name + ':' + relative)
            covered.add(relative)
        require(bool(row.get('logs')), 'Actual current logs required: ' + name)
        for log in row['logs']:
            p = safe(log['path'])
            require(p.is_relative_to(ROOT) and p.is_file() and sha(p) == log['sha256'], 'Current test log missing/drifted: ' + name)
            text = read(p)
            require(bool(log.get('pass_marker')) and log['pass_marker'] in text, 'Test completion marker missing: ' + name)
            require(not re.search(r'\*\*\s+(Error|Fatal):|(?:^|\n)(?:# )?Errors:\s*[1-9]\d*', text), 'Test log contains errors: ' + name)
    require(PREVIEW_SOURCES <= covered, 'Current evidence omits document KEY1 confirmation sources: ' + str(sorted(PREVIEW_SOURCES - covered)))
    return gate


def prebitgen(run, gate_path):
    run, plan = validate(run)
    syn, phy = directories(run)
    physical = physical_review(run)
    require(physical['passed'], 'Current physical signoff required')
    external_gate(run, gate_path)
    log_checks = []
    for phase in ['syn', 'place', 'route']:
        receipt = load(run / 'logs' / (phase + '.json'))
        log = run / 'logs' / (phase + '.log')
        require(receipt['status'] == 'PASS_TOOL_INVOCATION' and receipt['log_sha256'] == sha(log), 'Implementation log receipt drift')
        text = read(log)
        require(not re.search(r'HDL-5105|\bBUILD_FAILED\b|\bMAPPING_ERROR\b', text), 'Missing ROM or failed implementation requires current explicit resolution')
        log_checks.append(evidence(log))
    require((syn / '.read_design.begin.f').is_file() and (phy / '.opt_route.end.f').is_file(), 'Actual implementation markers absent')
    result = {'status': 'PASS_CURRENT_PREBITGEN_GATE', 'source_manifest_sha256': plan['source_manifest_sha256'],
        'routed_database_sha256': sha(phy / (NAME + '_pr.db')), 'external_gate': evidence(gate_path),
        'physical_review': evidence(run / 'signoff/readonly/PHYSICAL_REVIEW.json'),
        'implementation_logs': log_checks, 'bitgen_allowed': True, 'hardware_status': 'NOT_RUN'}
    put(run / 'signoff/PREBITGEN_GATE.json', result)
    return result


def bitgen(run, gate_path):
    result = prebitgen(run, gate_path)
    run, plan = validate(run)
    _, phy = directories(run)
    out = run / 'signoff/bitgen'
    require(not out.exists(), 'Refusing to overwrite bitgen evidence')
    out.mkdir()
    artifact_name = 'dual_fpga_' + BOARD + '_20261105_doc_key1_confirm_diagnostic.bit'
    bit = out / artifact_name
    script = r'''# Standard bitgen context; no IO or constraint overrides.
set build {@PHY@}
set name {@NAME@}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -single_run
    load_run_param -run syn_1
    import_db "$build/${name}_pr.db"
    bitgen -bit {@BIT@}
    puts DOC_KEY1_CONFIRM_BITGEN_PASS
} reason]} {
    puts "DOC_KEY1_CONFIRM_BITGEN_FAIL: $reason"
    exit 1
}
exit 0
'''
    for key, value in {'PHY': phy.as_posix(), 'NAME': NAME, 'BIT': bit.as_posix()}.items():
        script = script.replace('@' + key + '@', value)
    tcl = out / 'bitgen.tcl'
    tcl.write_text(script, encoding='utf-8')
    before = immutable_inputs(run)
    with (out / 'bitgen.log').open('xb') as stream:
        cp = subprocess.run([str(TD), 'bitgen.tcl'], cwd=out, stdout=stream, stderr=subprocess.STDOUT)
    text = read(out / 'bitgen.log')
    require(cp.returncode == 0 and text.count('DOC_KEY1_CONFIRM_BITGEN_PASS') == 1 and bit.is_file() and bit.stat().st_size > 1000000, 'Bitgen did not complete')
    require(before == immutable_inputs(run), 'Bitgen changed routed inputs')
    require(not re.search(r'\b[A-Z]+-\d+\s+(ERROR|FATAL|CRITICAL-WARNING)\b|DOC_KEY1_CONFIRM_BITGEN_FAIL', text), 'Bitgen contains adverse diagnostics')
    require(not re.search(r'(?im)^\s*set_param\b|unconstr_io\s+on', script), 'Nonstandard bitgen override is prohibited')
    destination = ROOT / 'artifacts' / artifact_name
    require(not destination.exists(), 'Refusing to overwrite delivered artifact')
    destination.parent.mkdir(exist_ok=True)
    shutil.copy2(bit, destination)
    require(sha(destination) == sha(bit), 'Delivery copy differs')
    destination.with_suffix('.bit.sha256').write_text(sha(bit) + '  ' + artifact_name + '\n', encoding='ascii')
    delivery = {'status': 'DIAGNOSTIC_NOT_RUN', 'bit': evidence(destination), 'bit_bytes': bit.stat().st_size,
        'source_manifest_sha256': plan['source_manifest_sha256'], 'routed_database_sha256': result['routed_database_sha256'],
        'prebitgen_gate': evidence(run / 'signoff/PREBITGEN_GATE.json'), 'bitgen_script': evidence(tcl),
        'bitgen_log': evidence(out / 'bitgen.log'), 'baseline': baseline_identity(),
        'generated_utc': datetime.now(timezone.utc).isoformat(), 'hardware_status': 'NOT_RUN'}
    put(ROOT / 'artifacts/RELEASE_MANIFEST.json', delivery)
    print(json.dumps(delivery, ensure_ascii=False, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['template', 'prepare-readonly', 'readonly', 'review', 'prebitgen', 'bitgen'])
    p.add_argument('--run', type=Path, default=DEFAULT_RUN)
    p.add_argument('--gate', type=Path)
    args = p.parse_args()
    if args.action in {'prebitgen', 'bitgen'}:
        require(args.gate is not None, '--gate with current source-bound evidence is required')
    {'template': lambda: template(args.run), 'prepare-readonly': lambda: prepare_readonly(args.run),
     'readonly': lambda: run_readonly(args.run), 'review': lambda: physical_review(args.run),
     'prebitgen': lambda: prebitgen(args.run, args.gate), 'bitgen': lambda: bitgen(args.run, args.gate)}[args.action]()


if __name__ == '__main__':
    main()
