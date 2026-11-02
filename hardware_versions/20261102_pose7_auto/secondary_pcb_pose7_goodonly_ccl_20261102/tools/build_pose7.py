"""Isolated pose7 build. Final routed resources/timing have strict release gates.

Mapped timing is diagnostic; legal mapped designs can proceed to real routing.
No override for negative routed timing or the requested final resource limits.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import importlib.util
import json
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
NAME = 'secondary_cnn_multibox'
spec = importlib.util.spec_from_file_location('flow_helpers', ROOT/'tools/build_goodonly_full.py')
flow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flow)
sha, load, put, require, safe = flow.sha, flow.load, flow.put, flow.require, flow.safe
LIMITS = {'slice': 95, 'eram': 90, 'dsp': 95}
CHECKS = {'integer_stages', 'ordinary_cnn', 'document', 'writing', 'cancel_reentry',
          'cdc', 'fifo', 'ddr', 'drc', 'readonly'}


def prepare(args):
    source = safe(args.project_root)
    base = source.parent / flow.BASE_NAME
    baseline = flow.baseline(base, source)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out = safe(args.output or Path('E:/')/('codex_pcb_pose7_'+stamp))
    require(out.drive.upper() == 'E:' and out.name.startswith('codex_pcb_pose7_'), 'Use a fresh E:/codex_pcb_pose7_* build')
    require(not out.exists(), 'Refusing existing build directory')
    tree = flow.xml(source/(NAME+'.al'))
    require(any(n.attrib['Path'].endswith('/pcb_pose7_core.v') for n in tree.findall('Source_Files/Verilog/File')), 'pose7 core is absent from project')
    model = source/'model/pose7_96x96'
    for rel, digest in load(model/'FROZEN_SHA256.json').items():
        require(sha(model/Path(rel).name) == digest, 'Frozen model differs: '+rel)
    out.mkdir()
    records = {}

    def record(p, origin=None):
        records[p.relative_to(out).as_posix()] = {'sha256': sha(p), 'bytes': p.stat().st_size,
                                                'origin': str(origin) if origin else None}

    for folder in ['01_rtl', '04_pin', 'shared', 'main', 'model', 'tools']:
        for origin in sorted((source/folder).rglob('*')):
            if not origin.is_file() or '__pycache__' in origin.parts:
                continue
            safe(origin, source)
            digest = sha(origin)
            dest = out/origin.relative_to(source)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin, dest)
            require(sha(dest) == digest == sha(origin), 'Input changed during freeze')
            record(dest, origin)
    syn, phy = out/'runs/syn_1', out/'runs/phy_1'
    for directory in [out, syn, phy]:
        directory.mkdir(parents=True, exist_ok=True)
        for suffix in ['al', 'prj']:
            flow.write_project(tree, directory, out, source, suffix)
            record(directory/(NAME+'.'+suffix), source/(NAME+'.al'))
    for rel, item in baseline['flow'].items():
        dest = out/'runs'/rel
        shutil.copy2(item['path'], dest)
        require(sha(dest) == item['sha256'], 'Baseline Tcl/config copy differs')
        record(dest, item['path'])
    text = (phy/'run.tcl').read_text(encoding='utf-8-sig')
    for fname, first, last in [('run_place.tcl', 'opt_place', 'opt_place'), ('run_route.tcl', 'opt_route', 'opt_route')]:
        script = re.sub(r'(?m)^set start_step \w+$', 'set start_step '+first, text, count=1)
        script = re.sub(r'(?m)^set end_step \w+$', 'set end_step '+last, script, count=1)
        (phy/fname).write_text(script, encoding='utf-8')
        record(phy/fname)
    config = load(source/'tools/release_audit_doc_dirt_lowconf_factored_config.json')
    config['resolved_memory_references'] = [x for x in config['resolved_memory_references']
        if x['source'].startswith('main/')]
    config['extra_files'] = sorted({p.relative_to(out).as_posix() for p in (out/'model').rglob('*') if p.is_file()} |
                                 {p.relative_to(out).as_posix() for p in (out/'04_pin').rglob('*.tcl')})
    config_path = out/'tools/pose7_source_audit_config.json'
    put(config_path, config)
    record(config_path)
    # Resolve core/default ROM paths in TD's source-relative and run-relative orders.
    # Only identical frozen copies are permitted; never generic weights aliases.
    for directory in [syn, phy]:
        alias = directory/'../model/pose7_96x96'
        alias.mkdir(parents=True, exist_ok=True)
        for asset in (out/'model/pose7_96x96').glob('*.mem'):
            dest = alias/asset.name
            shutil.copy2(asset, dest)
            record(dest, asset)
    readonly = out/'readonly'
    readonly.mkdir()
    template = base/'02_sim'/ (flow.BASE_RUN+'_readonly')/'readonly_reimport.tcl'
    script = template.read_text(encoding='utf-8-sig')
    script = re.sub(r'(?m)^set build \{[^\n]*\}$', 'set build {'+phy.as_posix()+'}', script, count=1)
    script = re.sub(r'(?m)^set audit \{[^\n]*\}$', 'set audit {'+readonly.as_posix()+'}', script, count=1)
    (readonly/'readonly_reimport.tcl').write_text(script, encoding='utf-8')
    record(readonly/'readonly_reimport.tcl', template)
    auditor_spec = importlib.util.spec_from_file_location('source_audit', out/'tools/td_release_audit.py')
    audit = importlib.util.module_from_spec(auditor_spec)
    auditor_spec.loader.exec_module(audit)
    snapshots = {}
    for directory in [syn, phy]:
        snapshot = audit.collect(argparse.Namespace(root=out, run=directory, name=NAME,
                                                    al=None, config=config_path, extra=[]))
        put(directory/'source_snapshot.json', snapshot)
        record(directory/'source_snapshot.json')
        snapshots[directory.name] = {'passed': snapshot['passed'], 'errors': snapshot['errors'],
                                    'manifest_sha256': snapshot['manifest_sha256']}
    put(out/'SOURCE_MANIFEST.json', {'files': records})
    plan = {'status': 'PREPARED_NOT_STARTED', 'source_root': str(source), 'build_root': str(out),
            'source_manifest_sha256': sha(out/'SOURCE_MANIFEST.json'), 'baseline': baseline,
            'snapshots': snapshots, 'hardware_status': 'NOT_RUN', 'limits_strict_less_than': LIMITS,
            'mapped_negative_timing_blocks_route': False, 'negative_final_timing_blocks_bitgen': True}
    put(out/'BUILD_PLAN.json', plan)
    put(source/'reports/pose7/LATEST_BUILD.json', {'build': str(out), 'plan_sha256': sha(out/'BUILD_PLAN.json')})
    require(all(x['passed'] for x in snapshots.values()), 'Source closure failed: '+str(snapshots))
    print(json.dumps(plan, indent=2))


def strict_resources(metrics):
    rows = metrics['resources']
    return set(rows) == set(LIMITS) and all(rows[k]['used']*100 < rows[k]['total']*LIMITS[k] for k in LIMITS)


def execute(args):
    run, plan = flow.validate(args.run)
    syn, phy = run/'runs/syn_1', run/'runs/phy_1'
    phase = args.action
    if phase == 'syn':
        text = flow.invocation(run, phase, syn, 'run.tcl')
        require((syn/'.opt_gate.end.f').exists() and (syn/(NAME+'_gate.db')).exists(), 'Synthesis incomplete')
        illegal = [s for s in text.splitlines() if re.search(r'SYN-5033|unstable comb insts loops|TMR-250[79].*combinational loop|inferred latch', s, re.I)]
        put(run/'SYNTHESIS_REVIEW.json', {**flow.metrics(syn, False), 'illegal_logic_evidence': illegal,
                                         'status': 'MAPPED_ONLY', 'hardware_status': 'NOT_RUN'})
    elif phase == 'place':
        review = load(run/'SYNTHESIS_REVIEW.json')
        require(not review['illegal_logic_evidence'] and flow.report_within_device_capacity(review), 'Illegal or oversized mapping blocks placement')
        flow.invocation(run, phase, phy, 'run_place.tcl')
        require((phy/'.opt_place.end.f').exists(), 'Placement incomplete')
        put(run/'PLACE_REVIEW.json', flow.metrics(phy, True))
    elif phase == 'route':
        require((phy/'.opt_place.end.f').exists(), 'Placement missing')
        flow.invocation(run, phase, phy, 'run_route.tcl')
        require((phy/'.opt_route.end.f').exists() and (phy/(NAME+'_pr.db')).exists(), 'Route incomplete')
        result = flow.metrics(phy, True)
        result.update(final_timing_pass=flow.timing_pass(result['timing_ns']), final_resources_pass=strict_resources(result),
                      routed_database_sha256=sha(phy/(NAME+'_pr.db')), bitgen_allowed=False, hardware_status='NOT_RUN')
        put(run/'PRE_BITGEN_REVIEW.json', result)
    elif phase == 'readonly':
        review = load(run/'PRE_BITGEN_REVIEW.json')
        database = phy/(NAME+'_pr.db')
        before = sha(database)
        text = flow.invocation(run, phase, run/'readonly', 'readonly_reimport.tcl')
        require('TD_READONLY_REIMPORT_PASS' in text and before == sha(database), 'Readonly audit failed or changed DB')
        status = (run/'readonly/readonly.ts').read_text(encoding='utf-8-sig', errors='replace')
        timing = {key: float(re.search(r'\b'+key+r':\s*([-+\d.]+)ns', status)[1]) for key in ['SWNS','STNS','HWNS','HTNS']}
        require(timing == review['timing_ns'], 'Readonly timing differs')
        put(run/'READONLY_VERIFICATION.json', {'status': 'PASS_READONLY', 'timing_ns': timing,
                                              'routed_database_sha256': before})
    elif phase == 'bitgen':
        require(args.gate, 'Current hashed regression/physical evidence is required')
        review, readonly, gate = load(run/'PRE_BITGEN_REVIEW.json'), load(run/'READONLY_VERIFICATION.json'), load(args.gate)
        require(strict_resources(review) and flow.timing_pass(review['timing_ns']) and review['routed_two_corner'], 'Final strict resource/timing gate failed')
        require(readonly['timing_ns'] == review['timing_ns'] and readonly['routed_database_sha256'] == sha(phy/(NAME+'_pr.db')), 'Readonly identity differs')
        require(gate.get('source_manifest_sha256') == plan['source_manifest_sha256'] and
                gate.get('routed_database_sha256') == sha(phy/(NAME+'_pr.db')), 'Evidence belongs to a different build')
        require(all(gate.get('checks', {}).get(k) is True for k in CHECKS), 'Missing current integration or physical checks')
        require(gate.get('evidence'), 'No hashed evidence')
        for row in gate['evidence'].values():
            require(sha(row['path']) == row['sha256'], 'Evidence drift')
        flow.invocation(run, phase, phy, 'run_bitgen.tcl')
        require((phy/'.bitgen.end.f').exists() and (phy/(NAME+'.bit')).exists(), 'Bitgen incomplete')
        put(run/'BITGEN_RESULT.json', {'status': 'DIAGNOSTIC_NOT_RUN', 'bit': str(phy/(NAME+'.bit')),
                                     'bit_sha256': sha(phy/(NAME+'.bit')), 'hardware_status': 'NOT_RUN'})
    flow.validate(run)
    print(json.dumps({'action': phase, 'build': str(run), 'status': 'ACTION_COMPLETE'}))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['prepare', 'inspect', 'syn', 'place', 'route', 'readonly', 'bitgen'])
    p.add_argument('--project-root', type=Path, default=ROOT)
    p.add_argument('--output', type=Path)
    p.add_argument('--run', type=Path)
    p.add_argument('--gate', type=Path)
    a = p.parse_args()
    if a.action == 'prepare':
        prepare(a)
    elif a.action == 'inspect':
        run, plan = flow.validate(a.run)
        print(json.dumps({'status': 'FROZEN_INPUTS_PASS', 'build': str(run), 'plan': plan}, indent=2))
    else:
        execute(a)


if __name__ == '__main__':
    main()
