"""Exact five-file baseline comparison closure; preserves every original gate.

Only the original reviewer's baseline manifest return value is extended.
No source, snapshot, reviewer, constraint, database or error list is edited.
"""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path
import re
import sys
from unittest import mock

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_doc_dirt_lowconf_factored as builder

RUN = ROOT / 'dirt_lowconf_factored_Runs_20261101'
BASE = ROOT.parent / 'secondary_cnn_key3_stroke_compact_20261101'
BASE_RUN = BASE / 'cnn_key3_stroke_compact_area_sclk_Runs_20261101'
REVIEWER = ROOT / 'tools/review_remote_physical.py'
BUILDER_SHA = '2ADA653BB3BB7FD72B3424FA379A3620E5AE363C87505DE90F249C8753B14CBA'
REVIEWER_SHA = '34E80D868E86B1A136C71AC23A10231B57215EAEC8CD7227F9CB7F866EDA13AE'
PLAN_SHA = '1D147B5094B6CED1242C55BF48CFB6C80819A414F3212CAECB4EEA444C1956FE'
PREPARED = 'reports/cnn_lowconf_qualification/PREPARED_INPUTS.json'
PREPARED_SHA = 'F1934B4034CF54B1CA4C90A3662C4E8326A094EEFAEC4E4BB4047CB844C41C2C'
ARCHIVE = 'reports/factored_manifest_completion/ORIGINAL_FAILURE_ARCHIVE.json'
ARCHIVE_SHA = '5D13BFB317CF2B48646329D8134B2E79D47D2746048F32E22875E17BCD9E6BF2'
ADDITIONS = {
    'main/user_source/hdl_source/ethernet/uimdio_ctr.v': 'F22F85D0AB26C4E7C402B0DDD2D25A6F4BE852994226ADD50A2850F732EFF43F',
    'main/user_source/hdl_source/ethernet/uiphyrst.v': 'B272B8584D09DCDC516763C2A3F475D3005E172918FC339D448D7A675883937F',
    'main/user_source/hdl_source/ethernet/uirgmii_rx.v': '38769F122B452F1ABA2CC9F69E59669B5BFD01CE27A6E1BD67082EDCE28EBDB5',
    'main/user_source/hdl_source/ethernet/uirgmii_tx.v': '30374E9D9D21743A484084E3F1AD48DC12230883E890E5B37E79B1CD13A2C8A2',
    'shared/rtl/hxa_yolo_result_codec.v': '9EF958DFFAFCC25F2F6DB6C17D06B6B63589282C09479208457B7DA8658E816F',
}
FROZEN = {
    'syn_1/source_snapshot.json': '43BE06B106675F0076F5D05F38A2FD8FCE92DF2182BE45C49448500AFC6F5DD7',
    'phy_1/source_snapshot.json': '5DDF6114C74D1020CFC09F02A8F85D2A8E133D8108287A8C9BEB394665CDF17F',
    'phy_1/secondary_cnn_multibox_pr.db': '9AEA65015C522CCF102EA4999578F921A8474A60CCE6ADF524C39A7715CC152B',
    'phy_1/secondary_cnn_multibox.al': '3194B56F95AB6C0764BD0B9BF7285F1EBCFEBEDDEBB43BE239159F0F5B9C916C',
    'syn_1/secondary_cnn_multibox.al': '22FD86E21A4A5875C3DFAEF1C0A4C0AF33A8469D15476538C3DCBA6AA653F44D',
}
ROOT_PROJECT_SHA = 'DD4EB6BBE870C89334BDDFB26A368722CDAD4BA6C3665CBD298C2391657338BD'
require, sha, load, save = builder.require, builder.sha, builder.load, builder.save
_original_gate = builder.routed_gate


def snapshot(path, root):
    data = load(path)
    require(data.get('passed') is True and not data.get('errors') and
            Path(data['project_root']).resolve() == root, 'Snapshot identity/status differs')
    entries = {}
    for item in data['files']:
        source = Path(item['path']).resolve()
        require(source.is_relative_to(root) and 'work' not in {p.lower() for p in source.parts},
                'Snapshot source escapes approved root')
        key = source.relative_to(root).as_posix()
        require(key not in entries and source.is_file() and sha(source) == item['sha256'],
                'Snapshot source duplicate/drift: ' + key)
        entries[key] = item
    return data, entries


def excluded_project(path, root_project=False):
    # Use the byte-pinned original parser for TD's UsedInP&R/pseudo-XML syntax.
    audit = builder.flow.module(ROOT / 'tools/td_release_audit.py', 'completion_xml_parser')
    seen = {}
    for node in audit.xml(path).findall('./Source_Files/*/File'):
        source = Path(node.get('Path', ''))
        source = (source if source.is_absolute() else path.parent / source).resolve()
        if not source.is_relative_to(ROOT):
            continue
        key = source.relative_to(ROOT).as_posix()
        if key not in ADDITIONS:
            continue
        attrs = {x.get('Name'): x.get('Val', '').lower() for x in node.findall('./FileInfo/Attr')}
        require(key not in seen and attrs.get('AutoExcluded') == 'true',
                'Completion input is active/duplicated in project: ' + key)
        seen[key] = attrs
    require(not root_project or set(seen) == set(ADDITIONS), 'Root project lacks exact five excluded references')
    return sorted(seen)


def qualify():
    require(ROOT.name == 'secondary_doc_dirt_lowconf_factored_20261101' and
            builder.ROOT == ROOT and builder.BASE == BASE and builder.BASE_RUN == BASE_RUN.name and
            RUN == ROOT / builder.RUNS and 'work' not in {p.lower() for p in ROOT.parts}, 'Wrong completion root/run')
    require(sha(ROOT / builder.SELF) == BUILDER_SHA and sha(REVIEWER) == REVIEWER_SHA and
            sha(BASE / 'tools/review_remote_physical.py') == REVIEWER_SHA, 'Original builder/reviewer changed')
    require(sha(RUN / 'BUILD_PLAN.json') == PLAN_SHA and sha(ROOT / PREPARED) == PREPARED_SHA and
            sha(ROOT / ARCHIVE) == ARCHIVE_SHA, 'Frozen plan/qualification/failure archive changed')
    builder.validate(RUN)
    for relative, digest in FROZEN.items():
        require(sha(RUN / relative) == digest, 'Routed snapshot/database/project drift: ' + relative)
    require(sha(ROOT / 'secondary_cnn_multibox.al') == ROOT_PROJECT_SHA, 'Root project drift')
    archive = load(ROOT / ARCHIVE)
    for relative, digest in archive['files_sha256'].items():
        require(sha(ROOT / relative) == digest, 'Original failure archive drift')
    original = load(OUT / 'original_physical_review_failure/FINAL_PHYSICAL_REVIEW.json')
    require(original['status'] == 'REVIEW_REQUIRED' and
            original['errors'] == ['HXA/DDR/Ethernet source differs from accepted baseline'] and
            original['protected_source_mismatches'] == sorted(ADDITIONS) and
            not original['active_source_mismatches'] and not original['unexpected_cnn_pcb_mismatches'] and
            not original['new_drc_codes'] and not original['increased_drc_counts'] and
            not original['increased_check_categories'], 'Original failure is not the exact manifest-only issue')
    prepared = load(ROOT / PREPARED)
    require(Path(prepared['project_root']).resolve() == ROOT and prepared['status'] == 'PREPARED' and
            prepared['hardware_status'] == 'NOT_RUN', 'Prepared provenance differs')
    proof, current, baseline = {}, {}, {}
    reviewer = builder.flow.module(REVIEWER, 'completion_scope_reviewer')
    for phase in ('syn_1', 'phy_1'):
        _, current[phase] = snapshot(RUN / phase / 'source_snapshot.json', ROOT)
        _, baseline[phase] = snapshot(BASE_RUN / phase / 'source_snapshot.json', BASE)
        production = {p for p, x in current[phase].items() if x['kind'] in builder.PRODUCTION_KINDS}
        require(len(production) == 133 and not (set(ADDITIONS) & production), 'Production closure expanded')
        gap = {p for p in current[phase] if reviewer.protected_transport(p) and p not in baseline[phase]}
        require(gap == set(ADDITIONS), 'Protected comparison gap is not the exact five entries')
        for relative, digest in ADDITIONS.items():
            item = current[phase].get(relative, {})
            require(relative not in baseline[phase] and item.get('kind') == 'explicit_dependency' and
                    item.get('origins') == ['--extra'] and item.get('sha256') == digest and
                    prepared['input_sha256'].get(relative.replace('/', '\\')) == digest,
                    'Completion input kind/origin/qualification differs: ' + relative)
            require(sha(ROOT / relative) == digest and sha(BASE / relative) == digest,
                    'Completion input is not unchanged baseline bytes: ' + relative)
        proof[phase] = {'current_snapshot_sha256': sha(RUN / phase / 'source_snapshot.json'),
            'baseline_snapshot_sha256': sha(BASE_RUN / phase / 'source_snapshot.json'),
            'production_inputs': len(production), 'protected_manifest_gap': sorted(gap)}
    projects = {str(p.relative_to(ROOT)): excluded_project(p, p.parent == ROOT) for p in (
        ROOT / 'secondary_cnn_multibox.al', RUN / 'syn_1/secondary_cnn_multibox.al', RUN / 'phy_1/secondary_cnn_multibox.al')}
    return {'status': 'PASS_EXACT_FIVE_INACTIVE_SIMULATION_DEPENDENCY_BASELINE_COMPARISON_EXTENSION',
        'root': str(ROOT), 'run': str(RUN), 'additions': ADDITIONS, 'phases': proof,
        'excluded_project_entries': projects, 'prepared_sha256': PREPARED_SHA, 'archive_sha256': ARCHIVE_SHA,
        'builder_sha256': BUILDER_SHA, 'reviewer_sha256': REVIEWER_SHA, 'plan_sha256': PLAN_SHA,
        'database_sha256': FROZEN['phy_1/secondary_cnn_multibox_pr.db'],
        'production_source_graph_changed': False, 'baseline_snapshot_files_changed': False,
        'reviewer_rules_or_errors_filtered': False, 'hardware_status': 'NOT_RUN'}


def extend_manifest(original, run, root, calls):
    run, root = Path(run).resolve(), Path(root).resolve()
    require((run, root) in ((RUN, ROOT), (BASE_RUN, BASE)), 'Unexpected reviewer manifest invocation')
    data, entries = original(run, root)
    calls.append(('current' if run == RUN else 'baseline'))
    if run == BASE_RUN:
        require(not (set(ADDITIONS) & set(entries)), 'Completion entry already present in frozen baseline')
        return data, {**entries, **ADDITIONS}
    return data, entries


def completed_gate(runs, base=BASE):
    require(Path(runs).resolve() == RUN and Path(base).resolve() == BASE, 'Unexpected gate run/base')
    proof = qualify()
    original_module, calls = builder.flow.module, []
    def module(path, name):
        reviewer = original_module(path, name)
        if Path(path).resolve() == REVIEWER:
            require(sha(path) == REVIEWER_SHA, 'Reviewer changed during dispatch')
            original = reviewer.manifest
            reviewer.manifest = lambda run, root: extend_manifest(original, run, root, calls)
        return reviewer
    with mock.patch.object(builder.flow, 'module', module):
        result = _original_gate(runs, base)
    require(calls == ['current', 'baseline'], 'Original reviewer manifest call sequence differs')
    require(qualify() == proof, 'Completion evidence changed while original gate ran')
    path = result / 'FINAL_PHYSICAL_REVIEW.json'
    report = load(path)
    require(report['status'] == 'PASS_WITH_INHERITED_WARNINGS' and not report['errors'] and
            report['protected_source_mismatches'] == [], 'Original reviewer did not pass unfiltered')
    report['baseline_manifest_completion'] = proof
    report['baseline_manifest_completion_adapter_sha256'] = sha(__file__)
    save(path, report)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('qualify', 'gate', 'readonly', 'bitgen'))
    parser.add_argument('--td', type=Path, default=Path('E:/td/bin/td_commands_prompt.exe'))
    parser.add_argument('--regression', type=Path, action='append')
    args = parser.parse_args()
    args.stem = builder.STEM
    if args.action == 'qualify':
        print(json.dumps(qualify(), indent=2))
    elif args.action == 'gate':
        completed_gate(RUN)
    elif args.action == 'readonly':
        completed_gate(RUN)
        builder.readonly(args, RUN)
    else:
        with mock.patch.object(builder, 'routed_gate', completed_gate):
            builder.bitgen(args, RUN)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, AssertionError, KeyError, ValueError) as error:
        print('EXACT_MANIFEST_COMPLETION_FAIL:', error, file=sys.stderr)
        raise SystemExit(1)
