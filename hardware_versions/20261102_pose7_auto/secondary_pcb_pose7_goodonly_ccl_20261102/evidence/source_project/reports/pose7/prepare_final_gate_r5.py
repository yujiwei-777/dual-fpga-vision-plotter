"""Compose exact-source r5 evidence without invoking TD/vsim/bitgen.

Physical-dependent flags stay false unless a complete current r5 audit passes.
Historical execution identities remain explicit. This does not authorize bitgen.
"""
import argparse
import ast
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = Path('E:/codex_pcb_pose7_20261102_r5')
MANIFEST_SHA = '3D847C5B889CEEF42A5CACAD22412145447AB4BC510463722DD0CDC852FC74FE'
NAME = 'secondary_cnn_multibox'
EXPECTED_CHECKS = {'integer_stages', 'ordinary_cnn', 'document', 'writing', 'cancel_reentry',
                   'cdc', 'fifo', 'ddr', 'drc', 'readonly'}


def read(p):
    return Path(p).read_text(encoding='utf-8-sig', errors='replace')


def load(p):
    return json.loads(read(p))


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()


def require(condition, text):
    if not condition:
        raise ValueError(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--physical', type=Path, help='Complete current PHYSICAL_REVIEW_R5.json')
    parser.add_argument('--output', type=Path, default=HERE / 'final_gate_r5/GATE_PREPARED_R5.json')
    args = parser.parse_args()
    output = args.output.resolve()
    require(output.is_relative_to(HERE) and output.suffix == '.json', 'Output must stay in reports/pose7')
    evidence = {}
    errors, pending = [], []

    def pin(p, digest=None):
        p = Path(p).resolve()
        actual = sha(p)
        require(digest is None or actual == digest, 'Evidence drift: ' + str(p))
        evidence[str(p)] = dict(path=str(p), sha256=actual)
        return actual

    require(pin(BUILD / 'SOURCE_MANIFEST.json') == MANIFEST_SHA, 'Wrong r5 manifest')
    manifest = load(BUILD / 'SOURCE_MANIFEST.json')['files']
    for p, row in manifest.items():
        require(sha(BUILD / p) == row['sha256'], 'Frozen source drift: ' + p)
    builder = BUILD / 'tools/build_pose7.py'
    pin(builder)
    nodes = ast.parse(read(builder))
    builder_checks = next(ast.literal_eval(n.value) for n in nodes.body if isinstance(n, ast.Assign) and
        any(isinstance(t, ast.Name) and t.id == 'CHECKS' for t in n.targets))
    require(builder_checks == EXPECTED_CHECKS, 'Builder gate contract changed')

    reuse_path = HERE / 'SOURCE_REUSE_REVIEW_R5.json'
    pin(reuse_path)
    pin(HERE / 'audit_source_reuse_r5.py')
    reuse = load(reuse_path)
    require(reuse['status'] == 'PASS_ONLY_CNN_CORE_CHANGED_AND_SCOPED_REUSE_BINDINGS' and
        reuse['r5_manifest_sha256'] == MANIFEST_SHA and Path(reuse['r5_root']) == BUILD, 'Reuse report identity mismatch')
    require(len(reuse['reused_prior_results']) == 8 and len(reuse['test_tool_changes']) == 2 and
        len(reuse['regenerated_metadata_changes']) == 9 and
        [r['path'] for r in reuse['production_changed']] == ['01_rtl/cnn_core.v'], 'Unexpected change/reuse scope')
    for p, digest in reuse['evidence_sha256'].items():
        pin(p, digest)
    for result in reuse['reused_prior_results']:
        require(result['executed_again_for_r5'] is False, 'Historical test relabeled as r5')
        pin(result['result_path'], result['result_sha256'])
        for row in result['input_bindings']:
            if row['binding'] == 'CONTEXT_ONLY_NOT_COMPILED':
                continue
            pin(row['path'], row['expected'])
            if 'r5_path' in row:
                p = Path(row['r5_path'])
                rel = p.relative_to(BUILD).as_posix()
                require(manifest[rel]['sha256'] == row['r5_sha256'], 'Historical binding differs from frozen source')
                pin(p, row['r5_sha256'])
    core = next(r for r in reuse['reused_prior_results'] if r['name'] == 'pose7 core integer/threshold/cancel')
    reader = next(r for r in reuse['reused_prior_results'] if r['name'] == 'reader/store and source-extracted ownership routing')
    require(core['counts'] == dict(ROI=12, head=5, safety=23), 'Core historical coverage mismatch')
    require(reader['counts'] == dict(cases=12, checks=506, pixels=44, client_words=37, app_words=37), 'Reader coverage mismatch')

    digital_path = HERE / 'cnn_pipeline_r5/INDEPENDENT_REVIEW_R5.json'
    pin(digital_path)
    pin(HERE / 'audit_regressions_r5.py')
    digital = load(digital_path)
    require(digital['status'] == 'PASS_INDEPENDENT_R5_REGRESSION_REVIEW' and
        digital['source_manifest_sha256'] == MANIFEST_SHA and Path(digital['build_root']) == BUILD,
        'New digital review identity differs')
    require(digital['sources_unchanged'] and digital['frozen_sources_unchanged'], 'New digital sources drift')
    require(digital['ordinary']['cases'] == 27 and digital['ordinary']['cycles_per_ROI'] == 1880088 and
        digital['ordinary']['delta_cycles'] == 49155 and digital['ordinary']['all_27_outputs_identical_to_prior'] and
        digital['ordinary']['reference_memories_identical'], 'Ordinary arithmetic incomplete')
    require(digital['edges']['complete'] == 7 and digital['edges']['reset'] == digital['edges']['purpose_reuse'] == 6 and
        digital['edges']['per_complete_products'] == 1486848 and digital['edges']['first_last'] == 49155 and
        digital['edges']['padding'] == 54752 and digital['edges']['conv_drain'] == 49152 and
        digital['edges']['FC_drain'] == 3 and digital['edges']['reference_is_r4_module_rename_only'],
        'Changed ordinary pipeline edge coverage incomplete')
    require(digital['fullpipeline']['frames'] == 6 and digital['fullpipeline']['cancel_reentry'] == 3 and
        digital['fullpipeline']['latency_records_unchanged'], 'New fullpipeline coverage incomplete')
    for p, digest in digital['evidence_sha256'].items():
        pin(p, digest)

    hard_scope = 'Local cnn_core.background_reject remains inherited constant zero, verified in current r5 source. Forced hard-reject publication tests do not prove learned background rejection.'
    body = read(BUILD / '01_rtl/cnn_core.v')
    require('background_reject<=0' in body and 'background_reject<=1' not in body, 'Background limitation changed')
    type11_scope = 'Authenticated explicit Type11 reason0x80 does not compare packet frame ID to accepted task ID. Ordinary transport Type11/network changes preserve accepted writing jobs. This baseline limitation is unchanged.'
    verified = {k: False for k in sorted(EXPECTED_CHECKS)}
    verified.update(integer_stages=True, ordinary_cnn=True, document=True, writing=True, cancel_reentry=True)
    physical_detail = dict(status='NOT_SUPPLIED', flags_accepted=False)
    database_sha = None
    if args.physical is None:
        pending.append('Supply complete current r5 physical supplement after route and read-only reimport; CDC/FIFO/DDR/DRC/readonly remain false.')
    else:
        try:
            physical_path = args.physical.resolve()
            pin(physical_path)
            physical = load(physical_path)
            require(physical['source_manifest_sha256'] == MANIFEST_SHA and
                    Path(physical['build_root']).resolve() == BUILD.resolve(), 'Physical report belongs to another build')
            require(physical['status'] == 'PASS_PHYSICAL_SUPPLEMENT' and not physical['errors'] and not physical['pending'],
                    'Physical supplement is failed or incomplete')
            required_physical = {'freeze', 'gate_proofs', 'final_routed', 'reset_cdc', 'timing_check_drc', 'ddr_identity', 'readonly'}
            require(required_physical <= set(physical['checks']), 'Physical check sections incomplete')
            for p, digest in physical['evidence_sha256'].items():
                pin(p, digest)
            database = BUILD / ('runs/phy_1/' + NAME + '_pr.db')
            database_sha = pin(database)
            current = physical['checks']['final_routed']
            require(current['database_sha256'] == database_sha and
                    physical['checks']['reset_cdc']['database_sha256'] == database_sha, 'Physical DB mismatch')
            require(all(v >= 0 for v in current['timing_ns'].values()) and
                    current['timing_ns']['STNS'] == current['timing_ns']['HTNS'] == 0, 'Final routed timing failed')
            require(all(r['strict_pass'] for r in current['resources'].values()), 'Final strict resource gate failed')
            for k in ('Max', 'Min'):
                require(current['coverage'][k]['endpoints'] > 0 and current['coverage'][k]['paths'] > 0, 'Empty timing coverage')
            pre_path, ro_path = BUILD / 'PRE_BITGEN_REVIEW.json', BUILD / 'READONLY_VERIFICATION.json'
            pin(pre_path); pin(ro_path)
            pre, ro = load(pre_path), load(ro_path)
            require(pre['routed_database_sha256'] == ro['routed_database_sha256'] == database_sha and
                    pre['timing_ns'] == ro['timing_ns'] == current['timing_ns'], 'Builder final reports differ')
            require(pre['routed_two_corner'] and pre['final_timing_pass'] and pre['final_resources_pass'] and
                    ro['status'] == 'PASS_READONLY', 'Builder final gates failed')
            verified.update(cdc=True, fifo=True, ddr=True, drc=True, readonly=True)
            physical_detail = dict(status='PASS_CURRENT_R5_PHYSICAL_AND_DIGITAL_PROTOCOL_EVIDENCE',
                flags_accepted=True, path=str(physical_path), sha256=sha(physical_path),
                digital_ddr_scope='Actual HXA frame CRC reads all115200 modeled DDR words. Actual reader+mailbox and source-extracted routing pass12cases/506checks/44pixels/37words, including old-reply ownership/reentry. Frozen PHY/IP identity and current physical CDC/constraints are audited separately. Not electrical hardware, vendor-controller functional or actual DDR-latency acceptance.',
                timing_ns=current['timing_ns'], resources=current['resources'])
        except (ValueError, OSError, KeyError, AssertionError) as exc:
            errors.append('physical: ' + str(exc))
            database_sha = None
    pin(Path(__file__))
    status = 'REVIEW_REQUIRED' if errors else ('PENDING_PHYSICAL' if pending else 'READY_FOR_FINAL_REVIEW_NO_TOOLS_INVOKED')
    gate = dict(status=status, generated_utc=datetime.now(timezone.utc).isoformat(),
        source_manifest_sha256=MANIFEST_SHA, routed_database_sha256=database_sha, build_root=str(BUILD),
        checks=verified, evidence=evidence, current_r5_results=dict(ordinary=digital['ordinary'], edges=digital['edges'],
            fullpipeline=digital['fullpipeline']), reused_results=reuse['reused_prior_results'],
        physical=physical_detail, errors=errors, pending=pending,
        semantics_limitations=dict(hard_reject=hard_scope, explicit_type11=type11_scope,
            independent_data='642 development frames and synthetic controls establish reference parity; no independent capture accuracy is asserted.',
            latency='PCB fullpipeline10.205..10.484ms uses abstract2..4cycle reader, not actual DDR/mainboard timeout. Ordinary ROI is1880088cycles before localization/link overhead.',
            reader='Reader/store uses controlled8ns/14ns clocks and behavioral app responses; source-extracted routing is read-side only, not full top/HXA FSM or vendor DDR/PHY.',
            cnn_edges='Raw core reset and idle workspace/MAC ownership reuse; no complete top safety authorization is inferred.',
            hardware='Board placement/pose generalization, physical writing, disconnect and reset acceptance remain NOT_RUN.'),
        builder_review=dict(checks=sorted(builder_checks), builder_sha256=sha(builder),
            evidence_format='each value has path/sha256',
            enforcement='Builder consumes booleans and hashes; this composer independently checks report content and retains unfinished physical flags false.'),
        all_build_checks_complete=all(verified.values()), bitgen_invoked=False, bitgen_allowed=False, hardware_status='NOT_RUN')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(gate, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    md = ['# r5 regression and final gate preparation', '', 'Status: `'+status+'`. No TD, simulator or bitgen invoked.', '',
        '- New r5 ordinary CNN: 27 exact input/Conv1/Conv2/logit/class/confidence cases, 1,880,088 cycles each (+49,155).',
        '- New r5 per-tap miter: seven full runs, six raw-reset boundaries, six idle-purpose reuses; 1,486,848 products per complete run.',
        '- New r5 PCB fullpipeline: six frames, three cancellation/drain/reentries; score/features/abstract cycles unchanged.',
        '- Eight historical scopes retain their original run identities and exact source bindings, including r4 12/5/23 core and 12/506 strengthened reader tests.',
        '- Final routed timing, strict resources, five-phase proofs, DRC and read-only same-DB identity remain mandatory.', '', '## Gate flags', '']
    md += [f'- `{k}`: `{str(v).lower()}`' for k, v in verified.items()]
    md += ['', '## Retained limits', '', '- '+hard_scope, '- '+type11_scope,
        '- Abstract/behavioral DDR latency, raw reset and idle ownership tests do not prove hardware/full top operation.',
        '- Independent captures and physical board/writing-machine acceptance remain NOT_RUN.', '', '## Remaining', '']
    md += ['- '+x for x in errors+pending]
    md += ['', f'Hashed evidence entries: {len(evidence)}. This composer never invokes or permits bitgen itself.']
    output.with_suffix('.md').write_text('\n'.join(md)+'\n', encoding='utf-8')
    print(json.dumps(dict(status=status, checks=verified, errors=errors, pending=pending,
        evidence=len(evidence), output=str(output)), indent=2))
    return int(bool(errors))


if __name__ == '__main__':
    raise SystemExit(main())
