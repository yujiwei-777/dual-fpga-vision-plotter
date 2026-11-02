"""Read-only r4/r5 identity comparison and exact, explicitly historical reuse."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[1]
R3 = Path('E:/codex_pcb_pose7_20261102_r3')
R4 = Path('E:/codex_pcb_pose7_20261102_r4')
R5 = Path('E:/codex_pcb_pose7_20261102_r5')
R4_SHA = '052CDD89A612A1ECF03AAFE1E91D0D343F9AEC131C6F6773DEA5C1C1CD31D178'
R5_SHA = '3D847C5B889CEEF42A5CACAD22412145447AB4BC510463722DD0CDC852FC74FE'


def read(p):
    return Path(p).read_text(encoding='utf-8-sig', errors='replace')


def load(p):
    return json.loads(read(p))


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()


def main():
    evidence = {}

    def pin(p, digest=None):
        p = Path(p).resolve()
        actual = sha(p)
        assert digest is None or actual == digest, ('Evidence drift', str(p))
        evidence[str(p)] = actual
        return actual

    def relpath(p):
        for root in (R5, R4, R3, SOURCE):
            try:
                rel = Path(p).relative_to(root).as_posix()
            except ValueError:
                continue
            if rel in m5:
                return rel
        return None

    def binding(p, digest, context=None):
        if context:
            return dict(path=str(p), expected=digest, binding='CONTEXT_ONLY_NOT_COMPILED', reason=context)
        pin(p, digest)
        rel = relpath(p)
        result = dict(path=str(p), expected=digest, actual=digest,
                      binding='HISTORICAL_TEST_ASSET_UNCHANGED')
        if rel:
            assert m5[rel]['sha256'] == digest
            pin(R5 / rel, digest)
            result.update(binding='EXACT_TESTED_SOURCE_REUSE', r5_path=str(R5 / rel), r5_sha256=digest)
        return result

    assert pin(R4 / 'SOURCE_MANIFEST.json') == R4_SHA
    assert pin(R5 / 'SOURCE_MANIFEST.json') == R5_SHA
    m4 = load(R4 / 'SOURCE_MANIFEST.json')['files']
    m5 = load(R5 / 'SOURCE_MANIFEST.json')['files']
    assert set(m4) == set(m5)
    assert all(sha(R4 / p) == row['sha256'] for p, row in m4.items())
    assert all(sha(R5 / p) == row['sha256'] for p, row in m5.items())
    generated = {'runs/phy_1/secondary_cnn_multibox.al', 'runs/syn_1/source_snapshot.json',
        'readonly/readonly_reimport.tcl', 'runs/syn_1/secondary_cnn_multibox.al',
        'secondary_cnn_multibox.prj', 'runs/phy_1/source_snapshot.json',
        'runs/syn_1/secondary_cnn_multibox.prj', 'runs/phy_1/secondary_cnn_multibox.prj',
        'secondary_cnn_multibox.al'}
    tool_names = {'tools/run_pose7_core_regression.py', 'tools/run_pose7_fullpipeline_regression.py'}
    changes = {'production': [], 'test_tools': [], 'generated_metadata': []}
    for p in m4:
        if m4[p]['sha256'] != m5[p]['sha256']:
            category = 'generated_metadata' if p in generated else 'test_tools' if p in tool_names else 'production'
            changes[category].append(dict(path=p, r4_sha256=m4[p]['sha256'], r5_sha256=m5[p]['sha256']))
    assert [r['path'] for r in changes['production']] == ['01_rtl/cnn_core.v']
    assert len(changes['test_tools']) == 2 and len(changes['generated_metadata']) == 9
    assert sha(R5 / '01_rtl/cnn_core.v') == '15262A8F5EA85739C5F9271A92B6A0143C88255F9A9F804975CCE4BAAB2621D8'
    assert sha(R5 / '01_rtl/pcb_pose7_core.v') == '6E00FE06A31F928748FE165C0E7A03C1F49F2C13EF98B733E9AD1DA08F101CAC'
    protected = load(R5 / 'BUILD_PLAN.json')['baseline']['protected_constraint_ip_sha256']
    assert all(pin(R5 / p, digest) == digest for p, digest in protected.items())
    model = load(R5 / 'model/pose7_96x96/FROZEN_SHA256.json')
    assert all(pin(R5 / 'model/pose7_96x96' / Path(p.replace('\\', '/')).name, digest) == digest
               for p, digest in model.items())
    snap = load(R5 / 'runs/syn_1/source_snapshot.json')
    active = [r for r in snap['files'] if r['kind'] == 'Verilog']
    assert snap['passed'] and not snap['errors'] and len(active) == 75
    assert all(sha(r['path']) == r['sha256'] for r in active)
    assert all(sha(SOURCE / Path(r['path']).relative_to(R5)) == r['sha256'] for r in active)

    prior_path = HERE / 'SOURCE_REUSE_REVIEW_R4.json'
    pin(prior_path)
    prior = load(prior_path)
    reused = []
    for old in prior['reused_prior_results']:
        if old['name'] == 'ordinary CNN arithmetic and model replay':
            continue
        pin(old['result_path'], old['result_sha256'])
        data = load(old['result_path'])
        if 'result_status' in old:
            assert data['status'] == old['result_status'] == 'PASS'
        exclusions = {}
        if old['name'] == 'current CNN publication integration':
            compiled = old['compiled_inputs']
            assert not any(Path(p).name in ('cnn_core.v', 'pcb_pose7_core.v') for p in compiled)
            for row in old['input_bindings']:
                if Path(row['path']).name in ('cnn_core.v', 'pcb_pose7_core.v'):
                    exclusions[row['path']] = 'Controlled leaf replaces this module; hash is context, not compiled production arithmetic. New ordinary-CNN regression must validate changed cnn_core.'
        rows = []
        for row in old['input_bindings']:
            if 'sha256' in row and 'expected' not in row:
                rows.append(binding(R4 / row['path'], row['sha256']))
            else:
                reason = exclusions.get(row['path'])
                if row['binding'] == 'CONTEXT_ONLY_EXCLUDED':
                    reason = reason or row['reason']
                rows.append(binding(row['path'], row['expected'], reason))
        if 'source_pins_path' in old:
            pin(old['source_pins_path'], old['source_pins_sha256'])
            for row in load(old['source_pins_path'])['test_artifacts'].values():
                pin(row['path'], row['sha256'])
        for row in old.get('logs', []):
            pin(row['path'], row['sha256'])
        for row in old.get('rows', []):
            assert row['status'] == 'PASS' and row['final_errors'] == 0 and row['pass_marker'] in read(row['log'])
            pin(row['log'], row['sha256'])
        for name, digest in old.get('logs_verified', {}).items():
            pin(Path(old['result_path']).parent / name, digest)
        reused.append(dict(name=old['name'], result_path=old['result_path'], result_sha256=old['result_sha256'],
            execution='HISTORICAL_EXECUTION_REUSED_ON_IDENTICAL_TESTED_INPUTS', executed_again_for_r5=False,
            input_bindings=rows, scope=old['scope'], limitations=old.get('limitations', [])))
    assert len(reused) == 6
    hxa = next(r for r in reused if r['name'] == 'HXA CRC and FIFO')
    assert 'POSE7_FIFO4_PASS: 41 payload/header/control checks' in read(Path(hxa['result_path']).parent / 'SIM.log')

    core_path = HERE / 'core_regression/run_20261102T065853_582280Z/RESULTS.json'
    core = load(core_path)
    assert core['status'] == core['RTL'] == 'PASS' and core['returncode'] == 0
    assert Path(core['design']) == R4 and core['source_manifest_sha256'] == R4_SHA
    assert core['ROI_cases_passed'] == 12 and core['head_cases_passed'] == 5 and core['safety_cases_passed'] == 23
    assert core['sources_unchanged'] and core['frozen_sources_unchanged']
    pin(core_path)
    pins_path = core_path.parent / 'SOURCE_SHA256.json'
    pin(pins_path)
    core_bindings = [binding(p, digest) for p, digest in load(pins_path).items()]
    core_log = core_path.parent / 'SIM.log'
    assert 'POSE7_CORE_REGRESSION_PASS roi_cases=12 head_cases=5 safety_cases=23' in read(core_log)
    assert not re.search(r'\*\*\s+(?:Error|Fatal):', read(core_log))
    assert all(int(n) == 0 for n in re.findall(r'Errors:\s*(\d+)', read(core_log)))
    pin(core_log)
    for n in (8, 9, 10):
        assert 'POSE7_SAFETY_PASS name=cancel_' + str(n) + ' ' in read(core_log)
    vector_path = HERE / 'vectors/SHA256.json'
    pin(vector_path)
    for rel, digest in load(vector_path).items():
        pin(vector_path.parent / rel.replace('\\', '/'), digest)
    reused.append(dict(name='pose7 core integer/threshold/cancel', result_path=str(core_path), result_sha256=sha(core_path),
        execution='ACTUALLY_EXECUTED_ON_R4_REUSED_FOR_IDENTICAL_R5_PCB_CORE', executed_again_for_r5=False,
        input_bindings=core_bindings, counts=dict(ROI=12, head=5, safety=23),
        scope='Exact ROI, orientation, Conv1, Conv2, anomaly score/status and three new operand-state cancellation checks. No changed ordinary CNN arithmetic is covered.'))

    reader_path = HERE / 'reader_regression_r4/INDEPENDENT_REVIEW.json'
    reader = load(reader_path)
    pin(reader_path)
    assert reader['status'] == 'PASS_READONLY_R4_READER_EVIDENCE_REVIEW'
    assert reader['source_manifest_sha256'] == R4_SHA and Path(reader['build_root']) == R4
    assert reader['counts'] == dict(cases=12, checks=506, pixels=44, client_words=37, app_words=37)
    reader_bindings = [binding(p, digest) for p, digest in reader['source_evidence_sha256'].items()]
    assert reader['final_errors'] == reader['final_warnings'] == 0
    assert reader['independent_pixel_comparison']['python_YUYV_RGB_oracle_matches']
    reused.append(dict(name='reader/store and source-extracted ownership routing', result_path=str(reader_path), result_sha256=sha(reader_path),
        execution='ACTUALLY_EXECUTED_ON_R4_REUSED_FOR_IDENTICAL_R5_READ_PATH', executed_again_for_r5=False,
        input_bindings=reader_bindings, counts=reader['counts'], scope=reader['digital_ddr_scope'],
        limitations=reader['limitations'], original_result=reader['original_result'], late_reply=reader['late_reply']))
    assert len(reused) == 8
    for rel in ('01_rtl/cnn_core.v',):
        body = read(R5 / rel)
        assert 'background_reject<=0' in body and not re.search(r'background_reject\s*<=\s*1', body)
    report = dict(status='PASS_ONLY_CNN_CORE_CHANGED_AND_SCOPED_REUSE_BINDINGS',
        generated_utc=datetime.now(timezone.utc).isoformat(), source_root=str(SOURCE),
        r4_root=str(R4), r5_root=str(R5), r4_manifest_sha256=R4_SHA, r5_manifest_sha256=R5_SHA,
        frozen_entries=len(m5), production_changed=changes['production'],
        test_tool_changes=changes['test_tools'], regenerated_metadata_changes=changes['generated_metadata'],
        active_verilog=len(active), protected_ip_constraints=len(protected), frozen_model_assets=len(model),
        reused_prior_results=reused, evidence_sha256=evidence,
        r5_required=['Bind new 27-case ordinary CNN workspace + external MAC integer regression to actual r5 cnn_core.',
            'Bind new six-frame/three-cancel PCB fullpipeline execution on r5.',
            'Complete current five-phase reset/CDC/KEY3, routed resources/timing/DRC and read-only DB identity.'],
        not_claimed=['No historical execution is renamed as r5.',
            'Old ordinary arithmetic is not reused for changed cnn_core; old publication compiles controlled leaves and does not cover its datapath.',
            'Local background_reject remains constant zero; a forced hard-reject branch does not establish learned background rejection.',
            'Reader/store supplement remains controlled-clock read-side behavior, not complete top/HXA FSM, vendor DDR/PHY or measured board latency.',
            'HXA authenticated explicit Type11 reason80 retains baseline lack of task-ID comparison.',
            'Failed r3/r4 setup results remain failed; only fresh r5 final routed timing can satisfy release.'],
        bitgen_allowed=False, hardware_status='NOT_RUN')
    out = HERE / 'SOURCE_REUSE_REVIEW_R5.json'
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    md = ['# r5 source identity and historical regression reuse', '',
        'Status: `'+report['status']+'`. No TD, simulator or build tool is invoked.', '',
        '- All 305 r5 frozen inputs match; 75 active Verilog files match the snapshot and current D source.',
        '- Only production `cnn_core.v` changes from r4. Two test runner updates and nine regenerated metadata files are listed separately.',
        '- All 86 protected IP/constraint entries and 8 frozen model assets match.',
        '- Eight historical scopes are rehashed and rebound to identical r5 tested inputs, retaining original execution identity.',
        '- Core arithmetic (12 ROI / 5 head / 23 safety) and strengthened reader supplement (12 cases / 506 checks) are explicitly reused from r4.',
        '- New ordinary-CNN arithmetic and new fullpipeline tests are required; their success is not claimed by this source audit.', '',
        '## Remaining and scope limits', '']
    md += ['- '+x for x in report['r5_required'] + report['not_claimed']]
    (HERE / 'SOURCE_REUSE_REVIEW_R5.md').write_text('\n'.join(md)+'\n', encoding='utf-8')
    print(json.dumps(dict(status=report['status'], production_changed=changes['production'],
        test_tool_changes=len(changes['test_tools']), metadata_changes=len(changes['generated_metadata']),
        historical_scopes=len(reused), evidence_hashes=len(evidence), output=str(out)), indent=2))


if __name__ == '__main__':
    main()
