"""Build fixed-dirt compensation and optional real low scores with original soft flag6.

The exact successful Tcl flows, clock proof, constraints, model bytes and
strict regression/physical/readonly gates are inherited. Only the explicitly
pinned frontend and exact opt-in top/pipeline deltas are permitted. Importing this file never starts TD.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET

import build_vector_release as flow
import key3_physical_gate as key3
import key3_stroke_lowconf_area_regression_gate as regression
import build_key3_stroke_compact_area_sclk as sclk

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'secondary_cnn_key3_stroke_compact_20261101'
BASE_RUN = 'cnn_key3_stroke_compact_area_sclk_Runs_20261101'
BASE_STEM = 'dual_fpga_secondary_20261101_cnn_key3_stroke_compact_area_sclk_diagnostic'
BASE_BIT_SHA = '3C5F52B2247DE0C6DF5E774204D6C0241B326D73AB628352D4ED3042ABDD67F0'
BASE_BUILD_SHA = 'E2DEF209C054A96B17658AAECB3D26627054B9B80E97BDA8829DEA9D7B578647'
SNAPSHOT_SHA = {
    'syn_1': 'F8239CE99617295D7CD655BB231B5717B5B4EA705127C8B20C7E05F5BF4B2518',
    'phy_1': '2DAF0A6AD2DDFECC8E0230B1221ED8D124FF4A9CDAEA0389EEE5F4E7FBEF0527',
}
FRONTEND = '01_rtl/doc_image_frontend.v'
FRONTEND_SHA = '42F2140588B7DB5AB5E815DFDFA0BFD0CEE161944CC198DD1BEAA571B22D05F4'
OLD_FRONTEND_SHA = '69D793BC4B9D38C4BCA3AE39C1C881EB6EC3A2167493FF35D5FFEC2EDCA5EB94'
TOP = '01_rtl/secondary_top.v'
TOP_SHA = 'DCA939F1C76E1920FF99647E1C19B733C6A0177033631317DCAED237FD2106DC'
OLD_TOP_SHA = '64176506920BFF546415A1D1433FE1F6558FAAA565B5845FA826B56566694DCA'
PIPELINE = '01_rtl/vision_pipeline.v'
PIPELINE_SHA = 'D5F83FC41A64071C4BC6E013D731664B8A177094816189D7E6CE22BF83812B42'
OLD_PIPELINE_SHA = '6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9'
LOWCONF_QUALIFICATION = 'reports/cnn_lowconf_qualification'
RUNS = 'dirt_lowconf_area_Runs_20261101'
STEM = 'dual_fpga_secondary_20261101_doc_dirt_lowconf_area_diagnostic'
NAME = 'secondary_cnn_multibox'
SELF = 'tools/build_doc_dirt_lowconf_area.py'
CREATION = 'reports/DIRT_LOWCONF_AREA_CREATION_MANIFEST.json'
QUALIFICATION = 'reports/dirt_qualification'
AUDIT_CONFIG = 'tools/release_audit_doc_dirt_lowconf_area_config.json'
SUITES = frozenset(('cnn_named_top', 'key3_top_reset_release', 'stroke_release',
    'cnn_named_pcb', 'cnn_area_pipeline_compact', 'cnn_stability_core', 'cnn_named_report'))
PHASES = ('gate', 'place_begin', 'place_end', 'route_begin', 'route_end')
PRODUCTION_KINDS = frozenset(('Verilog', 'VHDL', 'ADC_FILE', 'SDC_FILE',
    'IP_FILE', 'ip_fileset', 'include', 'readmem_dependency'))

require, sha, load, save = flow.require, flow.sha, flow.load, flow.save


def local(value):
    path = Path(value)
    return flow.local(path if path.is_absolute() else ROOT / path)


def text(path):
    return Path(path).read_text(encoding='utf-8-sig', errors='replace')


def baseline():
    require(ROOT.name == 'secondary_doc_dirt_lowconf_area_20261101' and ROOT != BASE and
        'work' not in {p.lower() for p in ROOT.resolve().parts}, 'Wrong independent root')
    bit = BASE / 'artifacts' / (BASE_STEM + '.bit')
    build_file = bit.with_name(BASE_STEM + '_BUILD.json')
    require(sha(bit) == BASE_BIT_SHA and sha(build_file) == BASE_BUILD_SHA,
        'Successful area/SCLK baseline bit/build changed')
    build = load(build_file)
    require(build.get('status') == 'DIAGNOSTIC_NOT_RUN' and
        build.get('hardware_validation') == 'NOT_RUN', 'Wrong baseline release status')
    require(Path(build['runs']).resolve() == BASE / BASE_RUN, 'Wrong baseline run')
    require(sha(BASE / BASE_RUN / 'phy_1' / (NAME + '.bit')) == BASE_BIT_SHA,
        'Baseline routed bit differs')
    gate = load(BASE / BASE_RUN / 'phy_1/release_gate.json')
    require(gate.get('passed') is True and gate.get('bitgen_allowed') is True and
        not gate.get('failures') and gate['resources'] == build['resources'] and
        gate['timing_ns'] == build['timing_ns'], 'Baseline release gate differs/fails')
    for relative, field in ((f'02_sim/{BASE_RUN}_readonly/readonly_verification.json',
                           'readonly_verification_sha256'),
                          (f'02_sim/{BASE_RUN}_physical_review/FINAL_PHYSICAL_REVIEW.json',
                           'physical_review_sha256')):
        path = BASE / relative
        require(sha(path) == build[field], 'Baseline final evidence changed: ' + relative)
    result = {}
    for phase, expected in SNAPSHOT_SHA.items():
        path = BASE / BASE_RUN / phase / 'source_snapshot.json'
        require(sha(path) == expected, 'Baseline frozen snapshot changed: ' + phase)
        snap = load(path)
        require(snap.get('passed') is True and not snap.get('errors') and
            Path(snap['project_root']).resolve() == BASE and len(snap['files']) == 201,
            'Baseline source snapshot identity differs')
        files = {}
        for entry in snap['files']:
            source = Path(entry['path']).resolve()
            require(source.is_relative_to(BASE) and
                'work' not in {p.lower() for p in source.parts}, 'Unsafe baseline source')
            relative = source.relative_to(BASE).as_posix()
            require(relative not in files and sha(source) == entry['sha256'],
                'Baseline frozen input changed/duplicate: ' + relative)
            files[relative] = {'kind': entry['kind'], 'sha256': entry['sha256']}
        result[phase] = {'snapshot_sha256': expected,
            'manifest_sha256': snap['manifest_sha256'], 'files': files}
    require(result['syn_1']['files'][FRONTEND]['sha256'] == OLD_FRONTEND_SHA and
        result['syn_1']['files'][TOP]['sha256'] == OLD_TOP_SHA,
        'Unexpected successful baseline frontend/top')
    return result


def scope(baseline_files=None, snapshot=None):
    closed = baseline_files or baseline()
    require(sha(local(FRONTEND)) == FRONTEND_SHA, 'Unreviewed frontend RTL')
    top_parameters = regression.top_scope()
    reviewed_deltas = {FRONTEND: FRONTEND_SHA, TOP: TOP_SHA, PIPELINE: PIPELINE_SHA}
    production = {p: x for p, x in closed['syn_1']['files'].items()
                  if x['kind'] in PRODUCTION_KINDS}
    for relative, item in production.items():
        require(sha(local(relative)) == reviewed_deltas.get(relative, item['sha256']),
            'Protected RTL/model/IP/constraint changed: ' + relative)
    # The project declaration remains identical apart from its root path.
    project = ROOT / (NAME + '.al')
    original = text(BASE / (NAME + '.al'))
    expected = original.replace(str(BASE), str(ROOT)).replace(BASE.as_posix(), ROOT.as_posix())
    require(text(project) == expected, 'Root project changed beyond root rebasing')
    created = load(local(CREATION))
    require(Path(created['baseline_root']).resolve() == BASE and
        Path(created['project_root']).resolve() == ROOT and
        created['baseline_bit_sha256'] == BASE_BIT_SHA and
        created['rtl_delta'] == {FRONTEND: {'before': OLD_FRONTEND_SHA, 'after': FRONTEND_SHA},
                                TOP: {'before': OLD_TOP_SHA, 'after': TOP_SHA},
                                PIPELINE: {'before': OLD_PIPELINE_SHA, 'after': PIPELINE_SHA}},
        'Creation manifest changed scope')
    sclk_proof = sclk.qualification()
    require(sclk_proof['hook_sha256'] == 'B075E954594269ED473318765371C9D92E510B22D2A211D5AE1AD99453DD40E9',
        'Successful reviewed SCLK hook changed')
    inherited_config = load(BASE / 'tools/release_audit_config.json')
    require(sha(ROOT / 'tools/release_audit_config.json') == sha(BASE / 'tools/release_audit_config.json'),
        'Original production audit configuration changed')
    expected_config = json.loads(json.dumps(inherited_config))
    expected_config['resolved_memory_references'].extend(simulation_memory_overrides())
    require(load(local(AUDIT_CONFIG)) == expected_config,
        'Document audit config changed beyond exact simulation-testbench fixture overrides')
    if snapshot is not None:
        value = load(snapshot) if isinstance(snapshot, (str, Path)) else snapshot
        require(value.get('passed') is True and not value.get('errors') and
            Path(value['project_root']).resolve() == ROOT, 'Wrong/failed current snapshot')
        current = {}
        for entry in value['files']:
            source = local(entry['path'])
            relative = source.relative_to(ROOT).as_posix()
            require(relative not in current and sha(source) == entry['sha256'],
                'Current frozen input drift/duplicate: ' + relative)
            current[relative] = entry
        actual = {p: item['kind'] for p, item in current.items() if item['kind'] in PRODUCTION_KINDS}
        require(actual == {p: item['kind'] for p, item in production.items()},
            'Current active source closure differs from successful release')
        for relative in extras(closed):
            require(relative in current and current[relative]['kind'] == 'explicit_dependency',
                'Missing explicit build/proof dependency: ' + relative)
    return {'status': 'PASS_EXACT_AREA_SCLK_BASELINE_WITH_FRONTEND_AND_OPTIN_LOW_SCORE',
        'baseline_bit_sha256': BASE_BIT_SHA, 'production_files': len(production),
        'frontend': {'before': OLD_FRONTEND_SHA, 'after': FRONTEND_SHA},
        'top_and_pipeline_parameters': top_parameters,
        'constraints_models_transport_equal': True, 'sclk_proof': sclk_proof,
        'hardware_status': 'NOT_RUN'}


def extras(closed=None):
    closed = closed or baseline()
    inherited = [p for p, x in closed['syn_1']['files'].items() if x['kind'] == 'explicit_dependency']
    qualified = local(QUALIFICATION)
    require(qualified.is_dir(), 'Archive fixed-dirt model/simulation qualification before prepare')
    additional = [p.relative_to(ROOT).as_posix() for p in qualified.rglob('*')
                  if p.is_file() and '__pycache__' not in p.parts]
    require(any(Path(p).name == 'fixed_dirt_reference.py' for p in additional) and
        (QUALIFICATION + '/PREPARED_INPUTS.json') in additional,
        'Fixed-dirt qualification lacks reference or frozen input manifest')
    lowconf_qualified = local(LOWCONF_QUALIFICATION)
    require(lowconf_qualified.is_dir() and
        (lowconf_qualified / 'PREPARED_INPUTS.json').is_file(),
        'Archive low-confidence production-parameter qualification before prepare')
    additional.extend(p.relative_to(ROOT).as_posix() for p in lowconf_qualified.rglob('*')
        if p.is_file() and '__pycache__' not in p.parts)
    # The unchanged area runner binds one new optional pipeline hash via a
    # separately frozen wrapper; all seven original suite contracts remain.
    wrapper_inputs = regression.wrapper_qualification()
    additional.extend(wrapper_inputs)
    prepared = load(lowconf_qualified / 'PREPARED_INPUTS.json')
    require(prepared.get('status') == 'PREPARED' and
        prepared.get('hardware_status') == 'NOT_RUN' and
        Path(prepared['project_root']).resolve() == ROOT,
        'Low-confidence qualification belongs to another project')
    production = {p for p, x in closed['syn_1']['files'].items()
                  if x['kind'] in PRODUCTION_KINDS}
    for relative, expected in prepared['input_sha256'].items():
        source = local(relative)
        require(source.is_file() and sha(source) == expected,
            'Low-confidence prepared input changed: ' + relative)
        normalized = source.relative_to(ROOT).as_posix()
        if normalized not in production:
            additional.append(normalized)
    for relative in inherited:
        # These named exceptions retain stricter independent checks: the root
        # project is verified as a pure path rebase in scope(); metric evidence
        # must be regenerated in this root and passes the original unmodified
        # compact_metric_gate before any synthesis or bit publication.
        if relative == NAME + '.al' or relative.startswith('02_sim/compact_metric_boundaries/'):
            require(local(relative).is_file(), 'Missing current project/metric dependency: ' + relative)
            continue
        require(sha(local(relative)) == closed['syn_1']['files'][relative]['sha256'],
            'Inherited strict gate/proof dependency changed: ' + relative)
    return tuple(dict.fromkeys((*inherited, SELF, CREATION,
        'tools/build_vector_release.py', 'tools/review_remote_physical.py',
        'tools/key3_stroke_regression_gate.py', 'tools/key3_physical_gate.py',
        'tools/run_doc_dirt_regression.py', 'tools/run_cnn_lowconf_accept.py',
        'tools/key3_stroke_lowconf_area_regression_gate.py',
        'tools/run_cnn_area_pipeline_lowconf_area.py',
        'tools/release_audit_config.json', AUDIT_CONFIG, *additional)))


def simulation_memory_overrides():
    """Exact lexical testbench references; production configuration is intact.

    The conservative scanner does not elaborate plusargs or simulation cwd.
    Each reference resolves to the archived blank2418 fixture for static source
    closure. Every alternative case fixture is independently an explicit input;
    the mandatory fresh runtime test checks their paths and complete hashes.
    """
    source = QUALIFICATION + '/source/'
    reason = ('Simulation-only testbench, absent from the active TD source project. '
        'The scanner cannot elaborate simulator cwd/plusargs. This static binding names '
        'the blank2418 fixture; all six frontend and two integrated case fixtures are '
        'explicitly frozen and separately validated by the mandatory current-root doc '
        'regression. No production memory reference or timing constraint is changed.')
    records = []
    for expression, filename in (('"expected.mem"', 'expected.mem'), ('"input.mem"', 'input.mem'),
                                ('"skeleton.mem"', 'skeleton.mem'), ('"source_y.mem"', 'source_y.mem')):
        records.append({'source': source + 'tb_capture_integrated.sv', 'expression': expression,
            'literal': '../fixtures/blank2418/' + filename, 'reason': reason})
    for expression, filename in (('expected_path', 'expected_binary.mem'), ('image_path', 'source_y.mem')):
        records.append({'source': source + 'tb_frontend.sv', 'expression': expression,
            'literal': '../fixtures/blank2418/' + filename, 'reason': reason})
    return records


def audit_command(action, run, *arguments):
    command = [sys.executable, '-B', str(ROOT / 'tools/td_release_audit.py'), action,
        '--root', str(ROOT), '--run', str(run), '--name', NAME,
        '--config', str(ROOT / AUDIT_CONFIG)]
    for relative in extras():
        command += ['--extra', str(local(relative))]
    return command + [str(v) for v in arguments]


def flow_identity(runs):
    records = {}
    for phase, filename in (('syn_1', 'run.tcl'), ('phy_1', 'run.tcl'), ('phy_1', 'run_bitgen.tcl')):
        path = runs / phase / filename
        origin = BASE / BASE_RUN / phase / filename
        require(sha(path) == sha(origin), 'Flow changed from successful release: ' + str(path))
        content = text(path)
        timings = re.findall(r'(?m)^\s*secondary_apply_phase_timing (\w+) \{([^}]+)\} (\w+)\s*$', content)
        proofs = re.findall(r'(?m)^\s*source \{([^}]*prove_key3_supervisor_clocktrace\.tcl)\}\s*\n\s*secondary_prove_key3_supervisor (\w+)\s*$', content)
        require(tuple(p[0] for p in timings) == PHASES and tuple(p[1] for p in proofs) == PHASES,
            'Five-phase timing/SCLK proofs incomplete')
        require(all((path.parent / p[1]).resolve() == ROOT / '04_pin/timing.sdc' for p in timings) and
            all((path.parent / p[0]).resolve() == ROOT / '04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl'
                for p in proofs), 'Tcl hooks escape current source root')
        options = re.findall(r'(?m)^\s*set_param gate (\w+) (\w+)\s*$', content)
        require(options == ([('add_map_lut_struct', 'high'), ('map_mode', 'area_prior'),
            ('pack_effort', 'high')] if phase == 'syn_1' else []), 'Area-prior mapping differs')
        records[path.relative_to(ROOT).as_posix()] = sha(path)
    return records


def prepare(args, runs):
    require(args.seed == 1 and not runs.exists(), 'Fresh run with successful seed 1 required')
    closed = baseline()
    checked = scope(closed)
    frozen_extras = extras(closed)
    gen = flow.module(ROOT / '_gen_project.py', 'doc_dirt_project_generator')
    tree = gen.load_project()
    snapshots = {}
    for phase in ('syn_1', 'phy_1'):
        directory = runs / phase
        directory.mkdir(parents=True)
        for suffix in ('al', 'prj'):
            gen.write_project(tree, directory, suffix)
        for filename in (('run.tcl', 'settings.cfg') if phase == 'syn_1' else
                         ('run.tcl', 'run_bitgen.tcl', 'settings.cfg')):
            shutil.copy2(BASE / BASE_RUN / phase / filename, directory / filename)
        flow.execute(audit_command('snapshot', directory))
        snapfile = directory / 'source_snapshot.json'
        checked_snapshot = load(snapfile)
        scope(closed, checked_snapshot)
        snapshots[phase] = {'sha256': sha(snapfile), 'manifest_sha256': checked_snapshot['manifest_sha256']}
    scripts = flow_identity(runs)
    for phase in ('syn_1', 'phy_1'):
        scripts[(runs / phase / 'settings.cfg').relative_to(ROOT).as_posix()] = sha(runs / phase / 'settings.cfg')
    save(runs / 'BUILD_PLAN.json', {'root': str(ROOT), 'runs': str(runs), 'baseline': str(BASE),
        'created_utc': datetime.now(timezone.utc).isoformat(), 'seed': args.seed,
        'baseline_bit_sha256': BASE_BIT_SHA, 'baseline_snapshots_sha256': SNAPSHOT_SHA,
        'source_scope': checked, 'source_manifest_sha256': snapshots['syn_1']['manifest_sha256'],
        'snapshots': snapshots, 'flow_sha256': scripts,
        'explicit_dependencies_sha256': {p: sha(local(p)) for p in frozen_extras},
        'required_regressions': sorted(SUITES), 'hardware_validation': 'NOT_RUN'})
    print('PREPARED_NOT_STARTED', runs)


def validate(runs):
    closed = baseline()
    plan = load(runs / 'BUILD_PLAN.json')
    require(Path(plan['root']).resolve() == ROOT and Path(plan['runs']).resolve() == runs and
        plan['baseline_bit_sha256'] == BASE_BIT_SHA and plan['required_regressions'] == sorted(SUITES),
        'Wrong frozen run identity')
    require(plan['source_scope'] == scope(closed), 'Frozen production/SCLK scope changed')
    require(plan['explicit_dependencies_sha256'] == {p: sha(local(p)) for p in extras(closed)},
        'Frozen build/reference/proof inputs changed')
    for relative, expected in plan['flow_sha256'].items():
        require(sha(local(relative)) == expected, 'Frozen flow changed: ' + relative)
    flow_identity(runs)
    for phase in ('syn_1', 'phy_1'):
        path = runs / phase / 'source_snapshot.json'
        require(sha(path) == plan['snapshots'][phase]['sha256'], 'Frozen snapshot file changed')
        scope(closed, path)
    return plan


def regressions(files):
    require(files, 'Supply seven fresh current-root --regression RESULTS.json files')
    result = regression.check(files, required=SUITES)
    evidence = regression.evidence_manifest(files, required=SUITES)
    digest = __import__('hashlib').sha256(json.dumps(evidence, sort_keys=True).encode()).hexdigest().upper()
    path = ROOT / 'reports' / ('DIRT_LOWCONF_REGRESSION_EVIDENCE_' + digest + '.json')
    if path.exists():
        require(load(path) == evidence, 'Regression closure changed')
    else:
        save(path, evidence)
    return result, path


def dirt_regression_gate():
    """Require fresh, source-bound document tests without freezing future logs."""
    directory = local('02_sim/doc_dirt_frontend')
    latest_path = directory / 'LATEST.json'
    latest = load(latest_path)
    result_path = local(latest['results'])
    require(result_path.is_relative_to(directory) and result_path.name == 'RESULTS.json' and
        latest.get('status') == 'PASS' and sha(result_path) == latest['results_sha256'],
        'Document latest result is absent, failed or changed')
    report = load(result_path)
    require(report.get('status') == 'PASS' and report.get('hardware_status') == 'NOT_RUN' and
        Path(report['project_root']).resolve() == ROOT and
        Path(report['compiled_frontend']).resolve() == ROOT / FRONTEND,
        'Document result is not a fresh current-production-root test')
    prepared_path = local(QUALIFICATION + '/PREPARED_INPUTS.json')
    prepared = load(prepared_path)
    require(sha(prepared_path) == report['prepared_manifest_sha256'] and
        prepared['source_sha256'] == report['prepared_source_sha256'] and
        prepared['fixture_sha256'] == report['fixture_sha256'] and
        Path(prepared['root']).resolve() == ROOT, 'Document preparation/result identity differs')
    bound = {prepared_path: sha(prepared_path), latest_path: sha(latest_path), result_path: sha(result_path)}
    for field in ('source_sha256', 'fixture_sha256'):
        require(isinstance(prepared[field], dict) and prepared[field], 'Empty document input closure')
        for relative, expected in prepared[field].items():
            source = local(relative)
            require(sha(source) == expected, 'Document input drift: ' + relative)
            bound[source] = expected
    require(sha(ROOT / FRONTEND) == FRONTEND_SHA and
        prepared['source_sha256'].get(str(Path(FRONTEND))) == FRONTEND_SHA,
        'Document result does not bind production frontend')
    for item in prepared['captures'].values():
        source = Path(item['path']).resolve()
        require(source.is_file() and sha(source) == item['sha256'] and
            'work' not in {p.lower() for p in source.parts}, 'Raw capture changed')
    tests = report['tests']
    require(set(tests['frontend']) == set(prepared['frontend_cases']) | {'lifecycle', 'timeout'} and
        set(tests['integrated']) == set(prepared['integrated_cases']) and
        all(x.get('status') == 'PASS' for group in tests.values() for x in group.values()),
        'Document directed coverage missing or failed')
    for name, expected in prepared['integrated_cases'].items():
        actual = tests['integrated'][name]
        require(all(actual.get(key) == value for key, value in expected.items()) and
            actual.get('checks') and 'PASS CAPTURE_INTEGRATED' in '\n'.join(actual['checks']),
            'Document integrated path/G-code coverage differs: ' + name)
    for name in ('lifecycle', 'timeout'):
        require(tests['frontend'][name].get('checks'), 'Missing document lifecycle/timeout checks')
    require('PASS RESET_DIRTY_ROI_PENDING_AND_BLANK_REENTRY' in
        '\n'.join(tests['frontend']['lifecycle']['checks']) and
        'PASS CANCEL_DIRTY_ROI_PENDING_AND_BLANK_REENTRY' in
        '\n'.join(tests['frontend']['lifecycle']['checks']) and
        'PASS TIMEOUT_PENDING_AND_CANCEL' in '\n'.join(tests['frontend']['timeout']['checks']),
        'Missing document cancel/reset/timeout contract')
    outputs = report.get('output_sha256', {})
    require(isinstance(outputs, dict) and outputs, 'Document output evidence closure empty')
    compiled = set()
    commands_checked = 0
    for relative, expected in outputs.items():
        path = local(result_path.parent / relative)
        require(path.is_relative_to(result_path.parent) and sha(path) == expected,
            'Document simulator output drift/escape: ' + relative)
        bound[path] = expected
        if path.name.endswith('_command.json'):
            command = load(path)
            require(command.get('returncode') == 0 and command.get('argv'),
                'Document simulator subprocess failed')
            logfile = path.with_name(path.name[:-len('_command.json')] + '.log')
            require(logfile.is_file() and sha(logfile) == command['log_sha256'],
                'Document command log is not bound')
            log = text(logfile)
            require(not re.search(r'\*\*\s+(?:Error|Fatal):', log), 'Document simulator error')
            argv = command['argv']
            executable = Path(argv[0]).name.lower()
            require(executable in {'vlib.exe', 'vlog.exe', 'vsim.exe'}, 'Unexpected document simulator executable')
            if executable == 'vlog.exe':
                require('-sv' in argv and '-lint' in argv and 'Errors: 0, Warnings: 0' in log,
                    'Document compile/lint did not pass cleanly')
                sources = {Path(v).resolve() for v in argv[1:] if Path(v).suffix.lower() in {'.v', '.sv'}}
                require(ROOT / FRONTEND in sources and all(p.is_relative_to(ROOT) for p in sources),
                    'Document compilation uses an external/frontend candidate source')
                compiled.update(sources)
            if executable == 'vsim.exe':
                require('-batch' in argv and '-syncio' in argv and 'onerror {quit -code 1}; run -all; quit -f' in argv,
                    'Document simulation must fail closed in batch mode')
            commands_checked += 1
    require(commands_checked >= 16 and ROOT / '01_rtl/doc_copy_pipeline.v' in compiled and
        all(Path(p).resolve() in compiled for p in report['compiled_backend']),
        'Document frontend/integrated compilation coverage missing')
    require(result_path.stat().st_mtime_ns >= max(p.stat().st_mtime_ns for p in bound if p != latest_path),
        'Document result predates current source/fixture/output evidence')
    return {'status': 'PASS_CURRENT_ROOT_DOC_DIRT_FRONTEND_AND_CAPTURE_GCODE',
        'results': result_path.relative_to(ROOT).as_posix(), 'results_sha256': sha(result_path),
        'latest_sha256': sha(latest_path), 'commands_verified': commands_checked,
        'frontend_cases': len(tests['frontend']), 'integrated_cases': len(tests['integrated']),
        'bound_evidence_sha256': {p.relative_to(ROOT).as_posix(): digest for p, digest in bound.items()},
        'hardware_status': 'NOT_RUN'}


def lowconf_regression_gate():
    """Fresh configured-production component proofs; legacy suites stay intact."""
    directory = local('02_sim/cnn_lowconf_accept')
    summary_path = directory / 'RESULTS.json'
    latest_path = directory / 'LATEST.json'
    latest = load(latest_path)
    result_path = local(latest['results'])
    require(result_path.is_relative_to(directory) and result_path.parent != directory and
        result_path.name == 'RESULTS.json' and latest.get('status') == 'PASS' and
        sha(result_path) == latest['results_sha256'] and
        sha(summary_path) == sha(result_path),
        'Low-confidence latest/summary is absent, failed or changed')
    report = load(result_path)
    require(report.get('status') == 'PASS' and report.get('hardware_status') == 'NOT_RUN' and
        Path(report['project_root']).resolve() == ROOT,
        'Low-confidence result is not current-root evidence')
    expected_production = {TOP: TOP_SHA,
        PIPELINE: PIPELINE_SHA,
        '01_rtl/cnn_result_stabilizer.v': '9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128'}
    require(report['production_top_sha256'] == expected_production[TOP] and
        report['production_pipeline_sha256'] == expected_production['01_rtl/vision_pipeline.v'] and
        report['production_kernel_sha256'] == expected_production['01_rtl/cnn_result_stabilizer.v'],
        'Low-confidence result does not bind reviewed production RTL')
    for relative, expected in expected_production.items():
        require(sha(local(relative)) == expected, 'Low-confidence production drift: ' + relative)
    regression.top_scope()
    expected_config = {'TRIANGLE_MARGIN_MIN': 31, 'CIRCLE_MARGIN_MIN': 28,
                       'SQUARE_MARGIN_MIN': 77, 'COLOR_MARGIN_MIN': 0,
                       'CNN_LOWCONF_OUTPUT': 1}
    prepared_path = local(LOWCONF_QUALIFICATION + '/PREPARED_INPUTS.json')
    prepared = load(prepared_path)
    require(sha(prepared_path) == report['prepared_manifest_sha256'] and
        prepared.get('status') == 'PREPARED' and prepared.get('hardware_status') == 'NOT_RUN' and
        Path(prepared['project_root']).resolve() == ROOT and
        report['production_margin_config'] == prepared['production_margin_config'] == expected_config,
        'Low-confidence preparation/result/configuration differs')
    expected_inputs = dict(prepared['input_sha256'])
    expected_inputs[str(prepared_path.relative_to(ROOT))] = sha(prepared_path)
    require(report['input_sha256'] == expected_inputs and len(expected_inputs) == 90,
        'Low-confidence runtime input closure differs from preparation')
    bound = {prepared_path: sha(prepared_path), latest_path: sha(latest_path),
             result_path: sha(result_path), summary_path: sha(summary_path)}
    input_paths = set()
    for relative, expected in expected_inputs.items():
        source = local(relative)
        require(source.is_file() and sha(source) == expected,
            'Low-confidence input drift: ' + relative)
        bound[source] = expected
        input_paths.add(source)
    require(ROOT / 'tools/run_cnn_lowconf_accept.py' in input_paths and
        all(ROOT / p in input_paths for p in expected_production),
        'Missing configured top/pipeline/kernel/runner inputs')
    tests = report['tests']
    markers = {'pipeline': 'PASS LOWCONF_CONFIGURED_PIPELINE_DIRECTED',
               'top_metadata': 'PASS LOWCONF_TOP_METADATA_DIRECTED',
               'report': 'PASS LOWCONF_NAMED_REPORT_12'}
    require(set(tests) == set(markers), 'Low-confidence component coverage differs')
    expected_compiled = {
        'pipeline': {ROOT / '01_rtl/vision_pipeline.v', ROOT / '01_rtl/cnn_result_stabilizer.v'},
        'top_metadata': {ROOT / TOP},
        'report': {ROOT / '01_rtl' / name for name in ('grbl_line_formatter.v',
            'grbl_response_parser.v', 'grbl_streamer.v', 'grbl_vector_font_rom.v', 'grbl_reporter.v')},
    }
    for name, marker in markers.items():
        item = tests[name]
        require(item.get('status') == 'PASS' and item.get('completion_marker') == marker and
            item['checks'].count(marker) == 1 and
            {local(p) for p in item['compiled_production_sources']} == expected_compiled[name],
            'Missing configured production component proof: ' + name)
    pipeline_checks = tests['pipeline']['checks']
    for marker, count in {
        'PASS LOWCONF_NONZERO_THREE_CONFIRM class score7 Type18': 3,
        'PASS LOWCONF_RAW1_ROUNDS_TO_ZERO_NO_CLASS': 1,
        'PASS LOWCONF_RAW2_REAL_SCORE1': 1,
        'PASS LOWCONF_ZERO_HOLDS_PRIOR_FIRST': 1,
        'PASS LOWCONF_ZERO_HOLDS_PRIOR_SECOND': 1,
        'PASS LOWCONF_ZERO_THIRD_CLEARS': 1,
        'PASS LOWCONF_HARD_BACKGROUND_REJECT_PRESERVED': 1,
        'PASS LOWCONF_HIGH_SCORE100_UNCHANGED': 1,
        'PASS LOWCONF_EMPTY_NEVER_INVENTS_CLASS': 1,
        'PASS LOWCONF_OVERFLOW_FAILS_CLOSED': 1,
        'PASS CNN_STABILITY_PIPELINE_ALL checks=489 jobs=107': 1,
    }.items():
        require(pipeline_checks.count(marker) == count,
            'Low-confidence directed contract missing: ' + marker)
    require(tests['top_metadata']['checks'].count('PASS CNN_NAMED_TOP_ALL checks=57') == 1,
        'Configured top metadata assertions differ')
    expected_jobs = [{'job': 400 + c, 'class_id': c, 'score': 7} for c in range(1, 10)]
    expected_jobs += [{'job': 410, 'class_id': 5, 'score': 1},
                      {'job': 411, 'class_id': 5, 'score': 0},
                      {'job': 412, 'class_id': 5, 'score': 100}]
    jobs = tests['report']['jobs']
    require(tests['report'].get('name_center_conf_exact') is True and len(jobs) == 12 and
        all({key: job.get(key) for key in expected} == expected and
            job.get('all_gcode_commands_exact') is True and job.get('gcode_lines', 0) > 0
            for job, expected in zip(jobs, expected_jobs, strict=True)),
        'Low-confidence names/center/CONF/G-code comparison missing')
    outputs = report['output_sha256']
    require(isinstance(outputs, dict) and len(outputs) == 25,
        'Low-confidence output closure is incomplete')
    commands, compiled, command_types = 0, set(), {}
    for relative, expected in outputs.items():
        path = local(relative)
        require(path.is_relative_to(result_path.parent) and path != result_path and
            sha(path) == expected, 'Low-confidence output drift/escape: ' + relative)
        bound[path] = expected
        if path.name.endswith('_command.json'):
            command = load(path)
            argv = command.get('argv')
            require(command.get('returncode') == 0 and isinstance(argv, list) and argv,
                'Low-confidence simulator subprocess failed')
            logfile = path.with_name(path.name[:-len('_command.json')] + '.log')
            require(logfile.is_file() and sha(logfile) == command['log_sha256'] and
                str(logfile.relative_to(ROOT)) in outputs,
                'Low-confidence command/log closure missing')
            log = text(logfile)
            require(not re.search(r'\*\*\s+(?:Error|Fatal):|\bErrors:\s*[1-9]|^#?\s*FAIL\b', log, re.M | re.I),
                'Low-confidence simulator error')
            executable = Path(argv[0]).name.lower()
            require(executable in {'vlib.exe', 'vlog.exe', 'vsim.exe'} and
                path.parent.name in markers, 'Unexpected low-confidence command')
            command_types.setdefault(path.parent.name, []).append(executable)
            if executable == 'vlog.exe':
                require('-sv' in argv and '-lint' in argv and 'Errors: 0, Warnings: 0' in log,
                    'Low-confidence compile/lint did not pass cleanly')
                sources = {Path(v).resolve() for v in argv[1:] if Path(v).suffix.lower() in {'.v', '.sv'}}
                require(all(p.is_relative_to(ROOT) and p in input_paths for p in sources) and
                    expected_compiled[path.parent.name] <= sources,
                    'Low-confidence compile uses unbound/external/candidate source')
                compiled.update(sources)
            elif executable == 'vsim.exe':
                require('-batch' in argv and '-syncio' in argv and
                    'onerror {quit -code 1}; run -all; quit -f' in argv and
                    markers[path.parent.name] in log,
                    'Low-confidence simulation did not pass in fail-closed batch mode')
            commands += 1
    require(commands == 9 and all(sorted(command_types.get(name, [])) ==
        ['vlib.exe', 'vlog.exe', 'vsim.exe'] for name in markers),
        'Low-confidence component command coverage missing')
    require(result_path.stat().st_mtime_ns >= max(p.stat().st_mtime_ns for p in bound
        if p not in {latest_path, summary_path}),
        'Low-confidence result predates current input/output evidence')
    return {'status': 'PASS_CURRENT_CONFIGURED_PRODUCTION_LOWCONF',
        'results': result_path.relative_to(ROOT).as_posix(), 'results_sha256': sha(result_path),
        'latest_sha256': sha(latest_path), 'commands_verified': commands,
        'production_margin_config': expected_config,
        'pipeline_jobs': 107, 'pipeline_checks': 489, 'top_checks': 57, 'report_jobs': 12,
        'bound_evidence_sha256': {p.relative_to(ROOT).as_posix(): digest for p, digest in bound.items()},
        'hardware_status': 'NOT_RUN'}


def routed_gate(runs, base=BASE):
    validate(runs)
    flow.execute(audit_command('gate', runs / 'phy_1', '--syn-run', runs / 'syn_1',
        '--snapshot', runs / 'syn_1/source_snapshot.json',
        '--log', runs / 'syn_1/td_console.log', '--log', runs / 'phy_1/td_console.log'))
    reviewer = flow.module(ROOT / 'tools/review_remote_physical.py', 'doc_dirt_physical_review')
    reviewer.ROOT, reviewer.BASE, reviewer.BASE_RUN = ROOT, BASE, BASE / BASE_RUN
    # Reuse the original reviewer's exact-hash deliberate-update facility for
    # this one proven vision RTL delta. Its legacy variable name mentions PCB
    # ROM; no PCB ROM/model change is being permitted here.
    require(not reviewer.INTENTIONAL_PCB_ROM_SHA256, 'Unexpected physical-review override')
    reviewed_pipeline_scope = regression.top_scope()
    reviewer.INTENTIONAL_PCB_ROM_SHA256 = {PIPELINE: PIPELINE_SHA}
    output = local(ROOT / '02_sim' / (runs.name + '_physical_review'))
    previous = sys.argv
    try:
        sys.argv = [str(ROOT / 'tools/review_remote_physical.py'), '--runs', str(runs), '--output', str(output)]
        require(reviewer.main() == 0, 'CDC/FIFO/DDR/DRC physical review failed')
    finally:
        sys.argv = previous
    proof = key3.check(ROOT, runs)
    report = output / 'FINAL_PHYSICAL_REVIEW.json'
    data = load(report)
    require(data.get('status') == 'PASS_WITH_INHERITED_WARNINGS' and not data.get('errors') and
        data.get('cnn_pcb_source_mismatches') == [PIPELINE] and
        data.get('intentional_pcb_model_updates') == {PIPELINE: PIPELINE_SHA} and
        not data.get('unexpected_cnn_pcb_mismatches') and
        not data.get('intentional_pcb_model_hash_mismatches'),
        'Physical review differs from the sole approved vision source delta')
    old_cnn_review = data['cnn_review']
    data['cnn_review'] = ('Only vision_pipeline.v has the exact reviewed opt-in low-score output delta; '
        'its default parameter zero preserves golden behavior and production top enables it. '
        'Original soft-margin comparisons/flag6, CNN core, stabilizer, ordinary/PCB model bytes, '
        'coordinates, HXA, DDR and constraints remain protected. Real-image and hardware validation '
        'are NOT_RUN. The original reviewer legacy intentional_pcb_model_updates key below records '
        'this vision RTL exception only; no PCB ROM change is permitted.')
    data['intentional_vision_source_updates'] = {PIPELINE: {
        'before': OLD_PIPELINE_SHA, 'after': PIPELINE_SHA,
        'exact_scope': reviewed_pipeline_scope}}
    data['pcb_model_bytes_unchanged'] = True
    for narrative in output.glob('*.md'):
        body = text(narrative)
        if old_cnn_review in body:
            narrative.write_text(body.replace(old_cnn_review, data['cnn_review']), encoding='utf-8')
    data['key3_reset_proof'] = proof
    data['fixed_dirt_lowconf_area_source_scope'] = scope()
    save(report, data)
    logs = text(runs / 'syn_1/td_console.log') + text(runs / 'phy_1/td_console.log')
    require(not any(code in logs for code in ('PHY-7027', 'PHY-9002', 'RTCLK-5078', 'USR-6113', 'HDL-5105')),
        'Forbidden placement/clock/ROM diagnostic')
    return output


def readonly(args, runs):
    phy = runs / 'phy_1'
    output = local(ROOT / '02_sim' / (runs.name + '_readonly'))
    require(not output.exists(), 'Readonly evidence must be fresh')
    flow.execute(audit_command('reimport-template', phy, '--audit-dir', output))
    script = os.path.relpath(output / 'readonly_reimport.tcl', phy).replace('\\', '/')
    flow.execute([str(args.td), script], cwd=phy, log=output / 'td_console.log')
    flow.execute(audit_command('verify-readonly', phy, '--audit-dir', output, '--log', output / 'td_console.log'))
    return output


def bitgen(args, runs):
    document = dirt_regression_gate()
    lowconf = lowconf_regression_gate()
    checks, regression_path = regressions(args.regression)
    flow.audit_command = audit_command
    flow.routed_gate = routed_gate
    flow.regression_gate = lambda files, active_runs: regressions(files)[0]
    flow.BASE_SHA = BASE_BIT_SHA
    # The original unmodified bitgen still requires routed/physical, readonly,
    # clean TD bitgen markers, a new bit output and byte-verified publication.
    flow.bitgen(args, runs, BASE)
    path = ROOT / 'artifacts' / (STEM + '_BUILD.json')
    report = load(path)
    report['baseline_bit_sha256'] = BASE_BIT_SHA
    report['baseline_run'] = BASE_RUN
    report['source_scope'] = scope()
    report['regression_evidence_manifest'] = regression_path.relative_to(ROOT).as_posix()
    report['regression_evidence_manifest_sha256'] = sha(regression_path)
    report['fixed_dirt_frontend_sha256'] = FRONTEND_SHA
    report['document_regression'] = document
    report['lowconfidence_regression'] = lowconf
    report['ordinary_cnn_configuration'] = {
        'shape_margin_min': {'triangle': 31, 'circle': 28, 'square': 77},
        'CNN_LOWCONF_OUTPUT': 1,
        'color_margin_min': 0, 'confidence': 'original FC8 margin scaling; not calibrated probability',
        'confirmation_frames': 3, 'uncertain_hold_frames': 2,
        'zero_scaled_score_can_establish_class': False,
        'core_model_stabilizer_bytes_unchanged': True,
        'pipeline_exact_optin_delta': {'before': OLD_PIPELINE_SHA, 'after': PIPELINE_SHA},
        'original_soft_margin_comparison_and_flag6_preserved': True,
        'default_pipeline_parameter_zero_preserves_golden': True,
        'main_bit_change_required': False}

    report['mapping_strategy'] = {'map_mode': 'area_prior', 'pack_effort': 'high', 'add_map_lut_struct': 'high', 'seed': 1}
    report['hardware_validation'] = 'NOT_RUN'
    report['completion_semantics'] = 'Final G-code ok confirms controller acceptance, not mechanical Idle'
    save(path, report)
    bit = ROOT / 'artifacts' / (STEM + '.bit')
    bit.with_suffix('.bit.sha256').write_text(sha(bit) + '  ' + bit.name + '\n', encoding='ascii')


def main():
    require(sys.version_info[:2] == (3, 11), 'Use release Python 3.11')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('inspect', 'prepare', 'validate', 'syn', 'route', 'gate', 'readonly', 'bitgen'))
    parser.add_argument('--td', type=Path, default=Path('E:/td/bin/td_commands_prompt.exe'))
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--runs', type=Path, default=Path(RUNS))
    parser.add_argument('--stem', default=STEM)
    parser.add_argument('--regression', type=Path, action='append')
    args = parser.parse_args()
    require(args.stem == STEM and local(args.runs) == ROOT / RUNS and args.seed == 1,
        'Build identity/seed cannot be overridden')
    runs = ROOT / RUNS
    if args.action == 'inspect':
        print(json.dumps(scope(), indent=2))
        return 0
    if args.action == 'prepare':
        prepare(args, runs)
        return 0
    validate(runs)
    if args.action == 'validate':
        print('PASS_CURRENT_FROZEN_DIRT_LOWCONF_PLAN')
    elif args.action == 'syn':
        document = dirt_regression_gate()
        lowconf = lowconf_regression_gate()
        result, evidence = regressions(args.regression)
        save(runs / 'PRE_SYN_REGRESSIONS.json', {'results': result, 'closure': str(evidence),
            'document_regression': document, 'lowconfidence_regression': lowconf})
        require(not (runs / 'syn_1/td_console.log').exists(),
            'Preserve prior synthesis invocation; prepare a new independent run')
        flow.execute([str(args.td), 'run.tcl'], cwd=runs / 'syn_1', log=runs / 'syn_1/td_console.log')
        require((runs / 'syn_1/.opt_gate.end.f').is_file() and
            not list((runs / 'syn_1').glob('.*.error.f')), 'Synthesis failed/incomplete')
    elif args.action == 'route':
        syn = runs / 'syn_1'
        require((syn / '.opt_gate.end.f').is_file() and not list(syn.glob('.*.error.f')),
            'Synthesis failed/incomplete')
        # Mapped WNS is informative. The unchanged routed gate decides timing.
        area = text(syn / (NAME + '_gate.area'))
        for kind, limit in (('slice', 95), ('eram', 90), ('dsp', 95)):
            match = re.search(r'^#' + kind + r'\*?\s+(\d+)\s+out of\s+(\d+)', area, re.M)
            require(match and int(match[1]) * 100 < limit * int(match[2]), 'Mapped resource gate failed: ' + kind)
        require(not (runs / 'phy_1/td_console.log').exists(),
            'Preserve prior physical invocation; prepare a new independent run')
        flow.execute([str(args.td), 'run.tcl'], cwd=runs / 'phy_1', log=runs / 'phy_1/td_console.log')
        require((runs / 'phy_1/.opt_route.end.f').is_file() and
            not list((runs / 'phy_1').glob('.*.error.f')), 'Place/route failed/incomplete')
    elif args.action == 'gate':
        routed_gate(runs)
    elif args.action == 'readonly':
        routed_gate(runs)
        readonly(args, runs)
    elif args.action == 'bitgen':
        bitgen(args, runs)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError, AssertionError, ET.ParseError) as error:
        print('BUILD_DOC_DIRT_LOWCONF_AREA_FAIL:', error, file=sys.stderr)
        raise SystemExit(1)
