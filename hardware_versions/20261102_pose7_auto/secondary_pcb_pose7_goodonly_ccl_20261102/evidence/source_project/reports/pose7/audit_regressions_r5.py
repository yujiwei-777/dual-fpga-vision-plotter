"""Independently read existing r5 integer logs/benches/pins. No tool execution."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
BUILD = Path('E:/codex_pcb_pose7_20261102_r5')
MANIFEST = '3D847C5B889CEEF42A5CACAD22412145447AB4BC510463722DD0CDC852FC74FE'


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
        assert digest is None or actual == digest, ('Evidence changed', str(p))
        evidence[str(p)] = actual
        return actual

    assert pin(BUILD / 'SOURCE_MANIFEST.json') == MANIFEST
    manifest = load(BUILD / 'SOURCE_MANIFEST.json')['files']
    assert all(sha(BUILD / p) == r['sha256'] for p, r in manifest.items())
    binding_path = HERE / 'cnn_pipeline_r5/R5_REGRESSION_BINDING.json'
    pin(binding_path)
    binding = load(binding_path)
    assert binding['status'] == 'PASS' and Path(binding['design']) == BUILD and binding['source_manifest_sha256'] == MANIFEST
    assert binding['sources_unchanged'] and binding['frozen_sources_unchanged']
    for p, digest in binding['production_bindings'].items():
        assert manifest[p]['sha256'] == digest
        pin(BUILD / p, digest)
    mirror = binding_path.parent / 'MIRROR_INDEX.json'
    pin(mirror)
    for name, row in load(mirror)['files'].items():
        p = mirror.parent / name
        assert p.stat().st_size == row['bytes']
        pin(p, row['sha256'])
    for p, digest in binding['logs'].items():
        pin(p, digest)
        body = read(p)
        assert not re.search(r'\*\*\s+(?:Error|Fatal):', body)
        assert all(int(n) == 0 for n in re.findall(r'(?:Errors|Warnings):\s*(\d+)', body))

    def input_pins(pins):
        production = []
        for p, digest in pins.items():
            pin(p, digest)
            try:
                rel = Path(p).relative_to(BUILD).as_posix()
            except ValueError:
                continue
            if rel == 'SOURCE_MANIFEST.json':
                assert digest == MANIFEST
            else:
                assert manifest[rel]['sha256'] == digest
                production.append(rel)
        return production

    op = Path(binding['ordinary']['result'])
    pin(op, binding['ordinary']['result_sha256'])
    ordinary = load(op)
    assert ordinary['status'] == 'PASS' and ordinary['rtl_case_count'] == ordinary['simulation_cases_passed'] == 27
    ordinary_inputs = input_pins(ordinary['input_hashes'])
    lint, sim, bench = op.parent / 'lint.log', op.parent / 'simulation.log', op.parent / 'tb_remote_detail.sv'
    for p in (lint, sim, bench):
        pin(p)
    assert all(s in read(lint) for s in ('cnn_core.v', 'vision_workspace_goodonly.v', 'vision_shared_mac.v', 'Errors: 0, Warnings: 0'))
    assert all(s in read(bench) for s in ('.USE_SHARED_WORKSPACE(1)', '.EXTERNAL_MAC(1)', 'SHAPE INPUT', 'FEATURE1', 'FEATURE2', 'LOGIT', 'COLOR SUM', 'CLASS/CONF'))
    assert 'PASS ALL CNN REMOTE DETAIL cases=27' in read(sim)
    regex = r'PASS CNN CASE (\d+) cycles=(\d+) logits=([-\d,]+) class=(\d+) color_conf=(\d+) shape_conf=(\d+)'
    new_rows = re.findall(regex, read(sim))
    old_result = load(HERE / 'ORDINARY_CNN_REGRESSION.json')
    old_output = Path(old_result['output'])
    old_sim = old_output / 'simulation.log'
    pin(old_sim)
    old_rows = re.findall(regex, read(old_sim))
    assert len(new_rows) == len(old_rows) == 27
    for index, (new, old) in enumerate(zip(new_rows, old_rows)):
        assert int(new[0]) == index and int(new[1]) == 1880088
        assert int(new[1]) - int(old[1]) == 49155 and new[2:] == old[2:]
        expected = ordinary['case_rows'][index]
        assert [int(n) for n in new[2].split(',')] == expected['logits']
        assert [int(n) for n in new[3:]] == [expected['rtl_class_id'], expected['color_conf'], expected['shape_conf']]
    for name in ('pixels.mem', 'shape.mem', 'feature1.mem', 'feature2.mem', 'results.mem'):
        assert pin(op.parent / name) == pin(old_output / name)
    assert ordinary['case_rows'] == old_result['case_rows']

    ep = Path(binding['edges']['result'])
    pin(ep, binding['edges']['result_sha256'])
    edges = load(ep)
    assert edges['status'] == 'PASS' and edges['returncode'] == 0 and Path(edges['design']) == BUILD
    assert edges['source_manifest_sha256'] == MANIFEST and edges['sources_unchanged'] and edges['frozen_sources_unchanged']
    assert edges['new_external_MAC'] == edges['new_shared_workspace'] == 1
    assert len(edges['complete_records']) == 7 and len(edges['reset_records']) == len(edges['purpose_records']) == 6
    edge_pins = ep.parent / 'SOURCE_SHA256.json'
    pin(edge_pins)
    edge_inputs = input_pins(load(edge_pins))
    edge_log = read(ep.parent / 'SIM.log')
    for k in ('complete_records', 'reset_records', 'purpose_records'):
        assert all(row in edge_log for row in edges[k])
    assert 'CNN_R5_PIPELINE_EDGES_PASS complete_runs=7 reset_cases=6 purpose_cases=6' in edge_log
    for i, row in enumerate(edges['complete_records'], 1):
        assert row == f'CNN_R5_EDGE_COMPLETE_PASS run={i} products=1486848 first=49155 last=49155 padding=54752 c_drains=49152 f_drains=3 cycles=1880088'
    old_core = Path('E:/codex_pcb_pose7_20261102_r4/01_rtl/cnn_core.v')
    pin(old_core)
    reference = ep.parent / 'cnn_core_reference.v'
    pin(reference)
    assert read(reference) == read(old_core).replace('module cnn_core #(', 'module cnn_core_reference #(', 1)
    edge_bench = ep.parent / 'tb_remote_detail.sv'
    pin(edge_bench)
    assert all(s in read(edge_bench) for s in ('dut.product_q!==product_expect[slot]', 'dut.product_last!==last_expect[slot]',
        'consume_count>=issue_count', 'Conv last product escaped drain', 'FC last product escaped drain',
        'reference_core.pooled_activation_q!==f1_ref', 'reference_core.scores[i]!==results[i]',
        'purpose changed while active', 'idle CNN consumed PCB workspace/MAC product', 'reset left tap valid/output active'))
    pin(ep.parent / 'run.do')
    assert all(s in read(ep.parent / 'run.do') for s in ('cnn_core.v', 'vision_workspace_goodonly.v', 'vision_shared_mac.v', 'cnn_core_reference.v', 'vlog -sv -lint'))

    pp = Path(binding['PCB_fullpipeline']['result'])
    pin(pp, binding['PCB_fullpipeline']['result_sha256'])
    pipe = load(pp)
    assert pipe['status'] == pipe['RTL'] == 'PASS' and pipe['returncode'] == 0
    assert Path(pipe['design']) == BUILD and pipe['source_manifest_sha256'] == MANIFEST
    assert pipe['frames_passed'] == 6 and pipe['cancellation_cases_passed'] == 3
    assert pipe['sources_unchanged'] and pipe['frozen_sources_unchanged']
    pipe_pins = pp.parent / 'SOURCE_SHA256.json'
    pin(pipe_pins)
    pipe_inputs = input_pins(load(pipe_pins))
    pipe_log = read(pp.parent / 'SIM.log')
    assert 'POSE7_FULLPIPELINE_REGRESSION_PASS frames=6 cancellation=3' in pipe_log
    old_pipe = HERE / 'fullpipeline_regression/run_20261102T065938_659248Z/RESULTS.json'
    pin(old_pipe)
    assert pipe['latency_records'] == load(old_pipe)['latency_records']
    for p in pp.parent.iterdir():
        if p.suffix in ('.do', '.svh') or p.name == 'CASES.json':
            pin(p)
    report = dict(status='PASS_INDEPENDENT_R5_REGRESSION_REVIEW', generated_utc=datetime.now(timezone.utc).isoformat(),
        build_root=str(BUILD), source_manifest_sha256=MANIFEST,
        ordinary=dict(result=str(op), result_sha256=sha(op), cases=27, cycles_per_ROI=1880088,
            delta_cycles=49155, all_27_outputs_identical_to_prior=True, reference_memories_identical=True,
            production_inputs=ordinary_inputs, execution='ACTUALLY_EXECUTED_ON_R5', scope=binding['ordinary']['scope']),
        edges=dict(result=str(ep), result_sha256=sha(ep), complete=7, reset=6, purpose_reuse=6,
            per_complete_products=1486848, first_last=49155, padding=54752, conv_drain=49152, FC_drain=3,
            reference_is_r4_module_rename_only=True, production_inputs=edge_inputs,
            execution='ACTUALLY_EXECUTED_ON_R5_EXTERNAL_MAC_WITH_FROZEN_R4_LOCAL_REFERENCE',
            limitations=edges['limitations']),
        fullpipeline=dict(result=str(pp), result_sha256=sha(pp), frames=6, cancel_reentry=3,
            production_inputs=pipe_inputs, latency_records_unchanged=True, execution='ACTUALLY_EXECUTED_ON_R5',
            scope=pipe['latency_scope']),
        sources_unchanged=True, frozen_sources_unchanged=True, evidence_sha256=evidence,
        limitations=binding['limitations'], hardware_status='NOT_RUN', bitgen_allowed=False)
    out = HERE / 'cnn_pipeline_r5/INDEPENDENT_REVIEW_R5.json'
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (out.with_suffix('.md')).write_text('# r5 independent digital regression review\n\nAll input hashes, compile logs, simulation markers and small mirrors were rechecked without executing a tool.\n\n- New 27-case ordinary CNN external-MAC/shared-workspace replay passes. Outputs match prior cases; each ROI costs 1,880,088 cycles (+49,155).\n- New seven-run per-tap miter, six raw-reset boundaries and six idle-purpose reuse checks pass. Each full run checks 1,486,848 products. Frozen r4 local reference differs only by module name.\n- New six-frame / three-cancel PCB fullpipeline passes; results and abstract latency match r4.\n\nScope limits retain behavioral memories, raw core reset, idle owner switching and abstract pixel reader. They do not establish full top/HXA admission, real DDR latency, physical timing/CDC, independent accuracy or board/machine acceptance.\n', encoding='utf-8')
    print(json.dumps(dict(status=report['status'], evidence=len(evidence), output=str(out)), indent=2))


if __name__ == '__main__':
    main()
