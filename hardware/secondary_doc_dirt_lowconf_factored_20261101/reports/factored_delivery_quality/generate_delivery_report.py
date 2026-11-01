"""Index fresh factored-root evidence; write only this new report directory.

Adapted from r2 lowconf_area_delivery. Imported images and 51-frame software
evidence remain explicitly historical. Nothing here authorizes bit generation.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
RUN = ROOT / 'dirt_lowconf_factored_Runs_20261101'
CONTROL = ROOT.parent / 'secondary_doc_dirt_20261101/reports/dirt_delivery_quality'
ORIGIN = ROOT.parent / 'secondary_doc_dirt_lowconf_area_20261101/reports/lowconf_area_delivery/generate_delivery_report.py'
SEVEN = ('cnn_named_top', 'key3_top_reset_release', 'stroke_release',
         'cnn_named_pcb', 'cnn_area_pipeline_compact', 'cnn_stability_core', 'cnn_named_report')
SUITES = SEVEN + ('compact_metric_boundaries', 'cnn_lowconf_accept')
PINS = {'CNN_LOWCONF_OUTPUT': 1, 'TRIANGLE_MARGIN_MIN': 31,
        'CIRCLE_MARGIN_MIN': 28, 'SQUARE_MARGIN_MIN': 77, 'COLOR_MARGIN_MIN': 0}
PRODUCTION = {
    '01_rtl/secondary_top.v': 'DCA939F1C76E1920FF99647E1C19B733C6A0177033631317DCAED237FD2106DC',
    '01_rtl/vision_pipeline.v': '02E7954C55C5696E299D7B980DE0C4BF95C1FDF65531D1D005CFDC6882D099D5',
    '01_rtl/doc_image_frontend.v': '42F2140588B7DB5AB5E815DFDFA0BFD0CEE161944CC198DD1BEAA571B22D05F4',
    '01_rtl/cnn_result_stabilizer.v': '9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128',
    '01_rtl/cnn_core.v': 'CD3C6128836B816D5CA211722E22090E4676173CA52DB462592224E18C3E5ED3',
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def ready():
    required = [ROOT / '02_sim' / name / 'RESULTS.json' for name in SUITES]
    required.extend((ROOT / '02_sim/doc_dirt_frontend/LATEST.json',
                     ROOT / '02_sim/cnn_lowconf_accept/LATEST.json',
                     ROOT / 'reports/factored_source_creation/CONE_EQUIVALENCE.json'))
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    return {'status': 'INPUT_FILES_PRESENT_NOT_YET_VALIDATED' if not missing else 'WAITING_FOR_FRESH_EVIDENCE',
            'missing': missing, 'hardware_status': 'NOT_RUN'}


def main():
    assert ROOT.name == 'secondary_doc_dirt_lowconf_factored_20261101'
    assert 'work' not in {part.lower() for part in ROOT.resolve().parts}
    assert not (OUT / 'QUALITY.json').exists(), 'Preserve an existing quality report'
    assert not ready()['missing'], ready()
    evidence = {}

    def bind_file(path, expected=None):
        path = Path(path).resolve(strict=True)
        assert 'work' not in {part.lower() for part in path.parts}, 'Backup path is outside report scope'
        digest = sha(path)
        assert expected is None or expected.upper() == digest, 'Evidence hash mismatch: ' + str(path)
        key = path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path)
        assert key not in evidence or evidence[key] == digest, 'Evidence changed during report'
        evidence[key] = digest
        return digest

    def bind_json(path, expected=None):
        bind_file(path, expected)
        return load(path)

    def bind_map(values):
        for relative, digest in values.items():
            path = Path(relative)
            bind_file(path if path.is_absolute() else ROOT / path, digest)

    bind_file(ORIGIN, '4EC83E74E8FB9096B3F41596EE18B479C04B4F7DE801D51DB14C01A418DE5A85')
    bind_file(__file__)
    for relative, digest in PRODUCTION.items():
        bind_file(ROOT / relative, digest)

    # All calls below are existing read-only gate functions. No prepare,
    # regressions() publication, TD flow, or builder manifest write is invoked.
    sys.path.insert(0, str(ROOT / 'tools'))
    import build_doc_dirt_lowconf_factored as builder
    assert builder.ROOT == ROOT and builder.RUNS == RUN.name
    for name in ('build_doc_dirt_lowconf_factored.py',
                 'key3_stroke_lowconf_factored_regression_gate.py',
                 'key3_stroke_regression_gate.py'):
        bind_file(ROOT / 'tools' / name)
    source_scope = builder.scope()
    assert source_scope['top_and_pipeline_parameters']['parameters'] == PINS
    assert source_scope['constraints_models_transport_equal'] is True
    plan = None
    if (RUN / 'BUILD_PLAN.json').is_file():
        plan = bind_json(RUN / 'BUILD_PLAN.json')
        assert Path(plan['root']).resolve() == ROOT and Path(plan['runs']).resolve() == RUN
        assert plan['source_scope'] == source_scope
        assert plan['hardware_validation'] == 'NOT_RUN'
    baseline = builder.baseline()
    for relative, record in baseline['syn_1']['files'].items():
        if record['kind'] in builder.PRODUCTION_KINDS:
            bind_file(ROOT / relative, PRODUCTION.get(relative, record['sha256']))

    # Bind the independent exact source reconstruction and exhaustive local
    # proof, while retaining its explicit initialized-binary / local-cone scope.
    eq_path = ROOT / 'reports/factored_source_creation/CONE_EQUIVALENCE.json'
    eq = bind_json(eq_path)
    assert eq['status'] == 'PASS_EXACT_SOURCE_TWO_STATE_CONE_EQUIVALENCE'
    assert eq['hardware_status'] == 'NOT_RUN' and eq['candidate_pipeline_sha256'] == PRODUCTION['01_rtl/vision_pipeline.v']
    assert eq['source_reconstruction_exact'] and eq['flag6_hard_and_soft_conditions_unchanged']
    assert eq['four_state_x_propagation_equivalence_claimed'] is False
    assert eq['python_boolean_truth_table_cases'] == eq['rtl_abstract_param_checks'] == 16384
    assert eq['rtl_raw_numeric_param_checks'] == 2097160 and eq['rtl_disabled_state_hold_param_checks'] == 16384
    eq_result = Path(eq['result']).resolve(strict=True)
    assert eq_result.is_relative_to(ROOT / 'reports/factored_source_creation')
    eq_detail = bind_json(eq_result, eq['result_sha256'])
    assert all(eq[key] == value for key, value in eq_detail.items())
    bind_map(eq['input_sha256'])
    bind_file(ROOT / 'reports/factored_source_creation/CREATION.json', eq['creation_manifest_sha256'])
    for command in eq['commands']:
        assert command['returncode'] == 0
        bind_file(eq_result.parent / (command['name'] + '.log'), command['log_sha256'])

    suites = {}
    for name in SUITES:
        path = ROOT / '02_sim' / name / 'RESULTS.json'
        data = bind_json(path)
        wanted = 'PASS_FRESH_COMBINED_METRIC_BOUNDARIES' if name == 'compact_metric_boundaries' else 'PASS'
        assert data['status'] == wanted and data['hardware_status'] == 'NOT_RUN', name
        suites[name] = {'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                        'scope': data.get('scope', 'See the source-bound suite RESULTS.json.')}
    seven_paths = [ROOT / '02_sim' / name / 'RESULTS.json' for name in SEVEN]
    validated_seven = builder.regression.evidence_manifest(seven_paths, required=builder.SUITES)
    bind_map(validated_seven)
    doc_gate = builder.dirt_regression_gate()
    low_gate = builder.lowconf_regression_gate()
    bind_map(doc_gate['bound_evidence_sha256'])
    bind_map(low_gate['bound_evidence_sha256'])
    latest = bind_json(ROOT / '02_sim/doc_dirt_frontend/LATEST.json')
    doc_path = Path(latest['results']).resolve(strict=True)
    doc = bind_json(doc_path, latest['results_sha256'])
    assert Path(doc['project_root']).resolve() == ROOT
    assert doc['prepared_source_sha256']['01_rtl\\doc_image_frontend.v'] == PRODUCTION['01_rtl/doc_image_frontend.v']
    low_latest = bind_json(ROOT / '02_sim/cnn_lowconf_accept/LATEST.json')
    low = bind_json(low_latest['results'], low_latest['results_sha256'])
    assert low['production_margin_config'] == PINS
    assert low['production_top_sha256'] == PRODUCTION['01_rtl/secondary_top.v']
    assert low['production_pipeline_sha256'] == PRODUCTION['01_rtl/vision_pipeline.v']

    # Verify the historical source manifest and every illustration byte before
    # reusing a figure. Current RTL outputs must match the annotated figure's
    # source data, including binary/path/G-code hashes, not only path counts.
    control_manifest = bind_json(CONTROL / 'OUTPUT_MANIFEST.json')
    assert control_manifest['status'] == 'PASS' and control_manifest['hardware_status'] == 'NOT_RUN'
    control = bind_json(CONTROL / 'QUALITY_REPORT.json', control_manifest['artifacts_sha256']['QUALITY_REPORT.json'])
    for relative, record in control['provenance'].items():
        bind_file(CONTROL / relative, record['sha256'])
    shadow = control['software_groups']['含纸边／阴影的空白纸']
    assert shadow['frames'] == 5
    assert [shadow['methods'][method]['paths_total_successful'] for method in ('released', 'exact_4x4', 'fixed_region')] == [41, 36, 71]
    assert control['evidence_scope']['existing_software_replay_frames'] == 51
    comparisons, copies = {}, []
    for name in ('blank2418', 'ink2358'):
        actual = doc['tests']['integrated'][name]
        expected = control['examples'][name]['new_root_rtl']
        assert actual == expected, 'Fresh RTL no longer matches historical figure: ' + name
        png = CONTROL / control['examples'][name]['plot']
        png_hash = bind_file(png, control_manifest['artifacts_sha256'][png.name])
        target = OUT / png.name
        assert not target.exists(), 'Preserve existing illustration'
        copies.append((png, target, png_hash))
        comparisons[name] = {'current_rtl': actual,
            'prior_baseline_rtl': control['examples'][name]['old_control'],
            'prior_scope': 'Historical old-baseline RTL; not rerun for this candidate.',
            'figure_source': str(png), 'figure_source_sha256': png_hash,
            'figure_source_manifest': str(CONTROL / 'OUTPUT_MANIFEST.json'),
            'figure_source_manifest_sha256': sha(CONTROL / 'OUTPUT_MANIFEST.json'),
            'plot': target.name, 'plot_sha256': png_hash,
            'plot_provenance': 'Byte-identical historical illustration; independent fresh current-root binary, skeleton, paths, machine coordinates and G-code results match its annotated source data.'}
    limitations = control['limitations'] + [
        '51-frame software results are inherited; only two real captures were replayed through the complete current-root RTL frontend/backend.',
        'Six frontend fixtures plus lifecycle/timeout cases are not six independent real handwriting captures.',
        'Synthetic crossings include missed weak target cells (Y96:1/384; Y104:87/384); actual weak pen strokes crossing this fixed ROI have not been captured.',
        'The local equivalence proof covers initialized binary states and does not claim four-state X equivalence or full-board equivalence.',
        'Accepting nonzero low margins can expose weak incorrect classifications; no training or accuracy improvement is claimed.',
        'The score is a scaled margin, not a calibrated probability; genuinely zero scores cannot establish a new class.',
        'A confirmed identity can be retained at score zero for two uncertain results; nonzero low scores require three confirming observations.',
        'Final G-code ok proves controller acceptance, not physical mechanical Idle or plotter readability.',
        'Main-board brightness and other main-board changes remain outside this secondary-only candidate.',
        'No bit is authorized by this report; full current-root physical gates, readonly reimport and bitgen requirements remain separate.',
    ]
    report = {
        'status': 'PASS_SOFTWARE_AND_RTL_SCOPE_ONLY', 'created_utc': datetime.now(timezone.utc).isoformat(),
        'root': str(ROOT), 'project_root': str(ROOT), 'run': str(RUN), 'hardware_status': 'NOT_RUN',
        'adapted_from': {'path': str(ORIGIN), 'sha256': sha(ORIGIN)},
        'physical_build_acceptance_claimed': False, 'bitgen_authorized_by_this_report': False,
        'bit_delivery_requires': {'setup_wns_ns_min': 0, 'hold_wns_ns_min': 0,
            'tns_ns': 0, 'slice_percent_strict_max': 95, 'eram_percent_strict_max': 90,
            'dsp_percent_strict_max': 95,
            'checks': ['synthesis', 'place', 'route', 'CDC', 'FIFO', 'DDR', 'DRC', 'readonly reimport', 'bitgen']},
        'build_plan_bound': plan is not None, 'source_scope': source_scope,
        'production_sha256': PRODUCTION, 'equivalence_proof': eq,
        'suites': suites, 'seven_suite_validated_file_count': len(validated_seven),
        'document_gate': doc_gate, 'lowconf_gate': low_gate,
        'doc_regression': doc_gate, 'lowconfidence_regression': low_gate,
        'document_results': {'path': str(doc_path), 'sha256': sha(doc_path)},
        'fixed_dirt': {'roi_camera_xyxy_inclusive': [1152, 448, 1279, 719],
            'roi_grid_xyxy_inclusive': [288, 112, 319, 179], 'grid': [320, 180],
            'threshold': 112, 'minimum_dark_pixels': 2, 'roi_minimum_contrast': 12,
            'source_requests_per_frame': 956416, 'extra_requests_percent': 3.7777777777777777,
            'roi_rule': 'second_min <= 112 and second_min + 12 <= ((sum16_background_probes + 8) >> 4)',
            'background_probe_offsets': [-10, -2, 6, 14],
            'outside_roi_rule': 'Exact disjoint 4x4 blocks; at least two Y <= 112',
            'blankets_roi_white': False, 'existing_software_replay_frames': 51,
            'current_real_frame_rtl_replays': 2, 'current_frontend_fixtures': 6,
            'lifecycle_and_timeout_cases_additional': True, 'examples': comparisons,
            'five_shadow_edge_blank_software_paths': {'released_baseline': 41, 'exact_4x4_only': 36, 'fixed_dirt': 71},
            'synthetic_crossings_inherited': control['synthetic_crossing']},
        'ordinary_cnn': {'parameters': PINS, 'fc_conf_shift': 8, 'confirmation_frames': 3,
            'zero_confidence_hold_frames': 2,
            'confidence_formula': '(min(color_margin, shape_margin) * 100 + 127) // 255',
            'score_is_calibrated_probability': False, 'nonzero_low_score_can_confirm': True,
            'zero_score_can_establish_new_class': False, 'soft_rejection_flag6_retained': True,
            'hard_background_rejection_retained': True,
            'class_names_center_coordinates_real_score_in_writer': True,
            'output_path': 'Existing Type18 and KEY1 report; main bit unchanged',
            'new_model_training': False, 'new_model_accuracy_claimed': False},
        'limitations': limitations,
    }
    # Complete validation before creating any copied image or quality output.
    for key, digest in evidence.items():
        path = Path(key)
        assert sha(path if path.is_absolute() else ROOT / path) == digest, 'Evidence drifted during report'
    for source, target, digest in copies:
        shutil.copyfile(source, target)
        assert sha(target) == digest
        evidence[target.relative_to(ROOT).as_posix()] = digest
    report['bound_evidence_sha256'] = evidence
    (OUT / 'QUALITY.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    (OUT / 'README.md').write_text(
        '# 副板固定脏斑与等价低分输出验证\n\n'
        '本目录仅汇总软件和 RTL 证据；不授权生成或交付 bit。完整物理门槛另行核验，实板状态为 `NOT_RUN`。\n\n'
        '- 低分逻辑仅分离 hard reject 与 soft flag6；默认参数 0 保留旧行为，生产参数 1 保留真实低分。阈值 31/28/77、FC8、模型、PCB、稳定器及主板未改变。\n'
        '- 精确源码局部对照通过：16,384 个布尔条件，RTL 2,097,160 次原始数值比较及 16,384 次保持周期；不宣称四态 X 或整板全域等价。\n'
        '- 七套现工程回归、metric 边界、低分输出、6 个前端用例及附加生命周期/超时用例均通过。2 张实拍完整 RTL 链路复现：空白 2418 为 0 条路径；笔迹 2358 为 30 条路径、351 点、417 行 G-code。\n'
        '- 51 帧软件对照是历史证据，不是 51 帧新 RTL 回放。5 张纸边/阴影空白图路径总数为 41 → 36 → 71，固定脏斑补偿不能当作通用背景去除。\n'
        '- 缺少真实弱墨穿过脏斑的样本；合成 Y=96 漏 1/384、Y=104 漏 87/384 个目标点，浅墨仍可能丢失。机位、裁剪或读出方式改变后需重新核验固定区域。\n'
        '- 分数是缩放 margin，不是校准概率。非零低分需连续 3 次确认；真正 0 分不能新建类别，已确认类别可在 0 分不确定结果中保持 2 次。不宣称准确率提高。\n'
        '- 对照 PNG 复用历史控制图；已先核对当前二值图、骨架、路径、机器坐标及 G-code 结果完全一致，源图片和清单 SHA256 见 QUALITY.json。\n'
        '- 最后一条 ok 表示控制器接收，不能证明机械 Idle、字迹可读性或实机运行成功。\n', encoding='utf-8')
    outputs = {p.name: sha(p) for p in OUT.iterdir() if p.is_file() and p.name != 'OUTPUT_MANIFEST.json'}
    (OUT / 'OUTPUT_MANIFEST.json').write_text(json.dumps({'status': 'PASS_SOFTWARE_AND_RTL_SCOPE_ONLY',
        'hardware_status': 'NOT_RUN', 'artifacts_sha256': outputs}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': report['status'], 'quality_sha256': sha(OUT / 'QUALITY.json'),
        'suites': len(suites), 'validated_seven_files': len(validated_seven),
        'doc_result_sha256': sha(doc_path), 'build_plan_bound': plan is not None,
        'bitgen_authorized': False}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-ready', action='store_true', help='Only report missing input files; do not write.')
    args = parser.parse_args()
    print(json.dumps(ready(), indent=2)) if args.check_ready else main()
