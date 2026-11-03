"""Source-bound r3 gate; honestly reuses r2 tests on identical logic/model inputs.

No TD invocation or frozen build mutation. A new assembly archives any old
actionable r3 gate before examining current evidence.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, importlib.util, json, re, sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import prepare_final_gate_r2 as parent_gate
import physical_gate_r3 as physical_gate
from release_guard import sha, load, put, require, safe, verify_inputs, verify_main_protocol
ROOT = HERE.parents[1]
BUILD = Path('E:/codex_pcb_binary_ccl_retrained_20261102_r3').resolve()
PARENT = parent_gate.BUILD.resolve()
MANIFEST = '31F6BE091C83865F4E2E5B1F5CA7EA82108F15654C023B7DB603EFD35D88375F'
PARENT_MANIFEST = parent_gate.MANIFEST
CHECKS = set(parent_gate.CHECKS)
GATE = HERE / 'FINAL_GATE_R3.json'
AUDIT = HERE / 'FINAL_GATE_AUDIT_R3.json'
PHYSICAL = HERE / 'physical_gate_r3/PHYSICAL_REVIEW_R3.json'

def recursive_pins(value):
    """Check every nested explicit input pin map and absolute hashed reference."""
    if isinstance(value, dict):
        for key in ('input_sha256', 'evidence_sha256'):
            if key in value: verify_inputs(value[key])
        if isinstance(value.get('path'), str) and isinstance(value.get('sha256'), str):
            path, digest = Path(value['path']), value['sha256']
            if path.is_absolute() and re.fullmatch('[A-F0-9]{64}', digest):
                require(sha(path) == digest, 'Nested evidence drift: ' + str(path))
        for child in value.values(): recursive_pins(child)
    elif isinstance(value, list):
        for child in value: recursive_pins(child)

def archive():
    paths = [HERE / name for name in ('FINAL_GATE_R3.json', 'FINAL_GATE_AUDIT_R3.json',
        'final_gate_evidence_r3') if (HERE / name).exists()]
    if not paths: return None
    folder = HERE / 'gate_history_r3' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    folder.mkdir(parents=True, exist_ok=False)
    pins = {}
    for path in paths:
        for item in ([path] if path.is_file() else path.rglob('*')):
            if item.is_file(): pins[item.relative_to(HERE).as_posix()] = sha(item)
        path.replace(folder / path.name)
    for relative, digest in pins.items():
        require(sha(folder / relative) == digest, 'Gate archival copy differs')
    put(folder / 'ARCHIVE.json', dict(reason='New r3 audit; previous actionable gate retired',
        files=pins, hardware='NOT_RUN'))
    return str(folder)

def continuation_check():
    """Run real physical proof auditing in-process; no tool execution."""
    a = physical_gate.Audit(BUILD, PARENT, HERE / 'physical_gate_r3')
    require(sha(BUILD / 'SOURCE_MANIFEST.json') == MANIFEST, 'Wrong r3 source manifest')
    a.pin(Path(physical_gate.__file__))
    frozen = a.freeze()
    helper = physical_gate.BASE / 'tools/key3_physical_gate.py'
    a.pin(helper, physical_gate.KEY3_HELPER)
    spec = importlib.util.spec_from_file_location('r3_release_key3', helper)
    key3 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(key3)
    actual = dict(freeze=frozen)
    actual['gate_proofs'] = a.gate_proofs(key3)
    actual['final_routed'] = a.physical(key3)
    actual['reset_cdc'] = a.proofs(key3)
    actual['timing_check_drc'] = a.drc()
    actual['ddr_identity'] = a.ddr()
    actual['readonly'] = a.readonly()
    return a, actual

def validate_gate(gate_path=GATE):
    gate_path = safe(gate_path)
    require(gate_path == GATE.resolve(), 'Only the current r3 gate may authorize bitgen')
    g, audit = load(gate_path), load(AUDIT)
    require(g.get('status') == audit.get('status') == 'PASS', 'Current r3 gate/audit not PASS')
    require(not audit.get('errors') and not audit.get('pending') and not audit.get('missing_checks'),
        'Current r3 audit incomplete')
    require(safe(audit['gate']['path']) == gate_path and audit['gate']['sha256'] == sha(gate_path),
        'Current r3 gate hash/path differs')
    require(g['generated_utc'] == audit['generated_utc'], 'Gate/audit generations differ')
    require(g['source_manifest_sha256'] == audit['source_manifest_sha256'] == MANIFEST ==
        sha(BUILD / 'SOURCE_MANIFEST.json'), 'r3 manifest differs')
    require(g['functional_ancestry_manifest_sha256'] == PARENT_MANIFEST, 'r2 ancestry differs')
    require(g['input_sha256'] == audit['input_sha256'], 'Gate/audit input sets differ')
    verify_inputs(g['input_sha256']); recursive_pins(g)
    require(set(g['checks']) == CHECKS and all(v is True for v in g['checks'].values()),
        'Wrong required check set')
    require(set(g['evidence']) == set(audit['completed_checks']) == CHECKS, 'Evidence incomplete')
    manifest = load(BUILD / 'SOURCE_MANIFEST.json')['files']
    for rel, row in manifest.items():
        path = safe(BUILD / rel)
        require(path.is_relative_to(BUILD) and sha(path) == row['sha256'], 'Frozen r3 drift: ' + rel)
    for name, row in g['evidence'].items():
        require(row['status'] == 'PASS' and sha(row['path']) == row['sha256'], 'Evidence drift: ' + name)
        detail = load(row['path'])
        require(detail['status'] == 'PASS' and detail['source_manifest_sha256'] == MANIFEST,
            'Wrong wrapper identity: ' + name)
        require(bool(row['source_sha256']) and row['source_sha256'] == detail['source_sha256'],
            'Source map differs: ' + name)
        recursive_pins(detail)
        for rel, digest in row['source_sha256'].items():
            require(rel in manifest and manifest[rel]['sha256'] == digest, 'Unbound source: ' + rel)
    require(g['routed_database_sha256'] == audit['routed_database_sha256'] ==
        sha(BUILD / 'runs/phy_1/secondary_cnn_multibox_pr.db'), 'Current routed DB differs')
    continuation_check(); verify_main_protocol(HERE)
    return g, audit, manifest

def assemble(require_complete=False):
    old = archive(); p = parent_gate.Audit()
    wrappers, errors, pending, extras = {}, [], [], {}; dbsha = None
    try:
        for script in (Path(__file__), HERE / 'prepare_final_gate_r2.py', HERE / 'release_guard.py',
                       HERE / 'release_r3.py', HERE / 'physical_gate_r3.py'): p.pin(script)
        extras['r2_functional_freeze'] = parent_gate.freeze(p)
        binding, suites = parent_gate.preserved(p); pcb = parent_gate.binary(p)
        a, actual = continuation_check(); p.inputs.update(a.evidence)
        for rel, digest in p.sources.items():
            require(rel in a.manifest and a.manifest[rel]['sha256'] == digest,
                'r2 functional source differs in r3: ' + rel)
            p.pin(BUILD / rel, digest)
        phys = p.read(PHYSICAL)
        required = {'freeze', 'gate_proofs', 'final_routed', 'reset_cdc', 'timing_check_drc',
            'ddr_identity', 'readonly'}
        require(phys['status'] == 'PASS_PHYSICAL_SUPPLEMENT' and not phys['errors'] and
            not phys['pending'] and not phys['missing_checks'] and required <= set(phys['checks']),
            'Current physical review incomplete')
        require(phys['source_manifest_sha256'] == MANIFEST and
            phys['parent_source_manifest_sha256'] == PARENT_MANIFEST, 'Physical ancestry differs')
        for path, digest in phys['evidence_sha256'].items(): p.pin(path, digest)
        for key in required:
            require(phys['checks'][key] == actual[key], 'Physical re-audit differs: ' + key)
        dbsha = p.pin(BUILD / 'runs/phy_1/secondary_cnn_multibox_pr.db')
        require(phys['checks']['final_routed']['database_sha256'] == dbsha, 'Physical DB differs')
        compat = verify_main_protocol(HERE)
        for name in ('RESULTS.json', 'SOURCE_SHA256.json', 'SIM.log', 'run.do', 'tb_link_pcb_wait.sv'):
            p.pin(HERE / 'main_protocol_compat_v3' / name)
        for path, digest in compat['source_hashes'].items(): p.pin(path, digest)
        extras['main_protocol_compatibility'] = dict(status=compat['status'],
            main_bit_sha256=compat['main_bit_sha256'], scope=compat['scope'], hardware='NOT_RUN')
        def combine(name, parts, scope, functional=True):
            sources = {}
            for part in parts: sources.update(part['reference']['source_sha256'])
            require(bool(sources), 'Empty evidence source map: ' + name)
            wrappers[name] = dict(status='PASS', source_manifest_sha256=MANIFEST,
                functional_ancestry_manifest_sha256=PARENT_MANIFEST,
                execution='REUSED_R2_ON_IDENTICAL_R3_SOURCES' if functional else 'R3_PHYSICAL_WITH_R2_BEHAVIORAL_ANCESTRY',
                source_sha256=sources, support=parts, scope=scope, hardware='NOT_RUN')
        combine('binary_integer', [pcb], 'Original CCL box, exact96 unsigned Y8, both layers/pool/logits/status/control; known model errors retained.')
        combine('ordinary_cnn', [suites[x] for x in ('ordinary', 'publication', 'top_metadata')],
            'Real classifier checks and separately controlled-leaf publication/KEY1 snapshots; truthful r2 reuse.')
        combine('document', [suites['document']], 'Six frontends plus two exact skeleton/path/coordinate/G-code fixtures.')
        combine('writing', [suites[x] for x in ('plotter', 'top_metadata', 'top_reset', 'key3')],
            'Final-ok completion, no motion replay, KEY4/Alarm/Reset, KEY3 whole-board reset.')
        combine('cancel_reentry', [pcb, *[suites[x] for x in ('hxa', 'controls', 'reader', 'plotter', 'top_metadata')]],
            'Packet cancellation/drain/reentry and preserved accepted writing tasks.')
        combine('fifo', [suites['hxa']], 'Actual packed RX FIFO behavioral regression.')
        physical_ref = dict(reference=p.report(PHYSICAL, sources={k:v['sha256'] for k,v in a.manifest.items()
            if k.startswith(('01_rtl/', 'shared/', 'main/', '04_pin/'))}),
            scope=phys['checks'], limitations=[phys['scope']])
        for name, subset in [('cdc', ['reader', 'key3']), ('ddr', ['reader', 'hxa']), ('drc', []), ('readonly', [])]:
            combine(name, [physical_ref, *[suites[x] for x in subset]],
                'Actual r3 routed mapping/timing/DRC/DDR/readonly proof; explicitly inherited behavioral tests.', False)
        p.pin(BUILD / 'BUILD_PLAN.json'); p.pin(BUILD / 'SOURCE_MANIFEST.json', MANIFEST)
        verify_inputs(p.inputs)
    except physical_gate.PendingEvidence as exc: pending.append(str(exc))
    except FileNotFoundError as exc: pending.append(str(exc))
    except (OSError, ValueError, KeyError, TypeError, AssertionError) as exc: errors.append(str(exc))
    missing = sorted(CHECKS - set(wrappers))
    complete = not errors and not pending and not missing and dbsha is not None
    generation = datetime.now(timezone.utc).isoformat()
    report = dict(status='PASS' if complete else ('BLOCKED' if errors else 'PENDING'),
        generated_utc=generation, source_manifest_sha256=MANIFEST,
        functional_ancestry_manifest_sha256=PARENT_MANIFEST, routed_database_sha256=dbsha,
        completed_checks=sorted(wrappers), missing_checks=missing, pending=pending, errors=errors,
        prerequisites=extras, input_sha256=p.inputs, previous_gate_archive=old,
        bitgen_allowed=False, hardware='NOT_RUN', scope='Evidence assembly only; no tool execution.')
    if complete:
        folder = HERE / 'final_gate_evidence_r3'; folder.mkdir(exist_ok=False); evidence = {}
        for name in sorted(CHECKS):
            path = folder / (name + '.json'); put(path, wrappers[name])
            evidence[name] = dict(path=str(path), sha256=sha(path), status='PASS',
                source_sha256=wrappers[name]['source_sha256'])
        gate = dict(status='PASS', generated_utc=generation, source_manifest_sha256=MANIFEST,
            functional_ancestry_manifest_sha256=PARENT_MANIFEST, routed_database_sha256=dbsha,
            checks={k:True for k in sorted(CHECKS)}, evidence=evidence, source_sha256=p.sources,
            input_sha256=p.inputs, hardware='NOT_RUN', known_missing_pad_falsePASS=7,
            scope='Diagnostic evidence current; r2 tests reused on exact r3 logic/model inputs.')
        staged = HERE / 'FINAL_GATE_R3.json.staging'; put(staged, gate)
        report['gate'] = dict(path=str(GATE), sha256=sha(staged)); put(AUDIT, report); staged.replace(GATE)
    else: put(HERE / 'PENDING_FINAL_GATE_R3.json', report)
    print(json.dumps({k:report[k] for k in ('status', 'missing_checks', 'pending', 'errors')}, ensure_ascii=False, indent=2))
    return int(bool(errors) or (require_complete and not complete))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--require-complete', action='store_true')
    args = parser.parse_args(); raise SystemExit(assemble(args.require_complete))
