"""Read-only unit checks for the factored builder. Never prepares or starts TD."""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import sys
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import build_doc_dirt_lowconf_factored as builder

PARENT = ROOT.parent / 'secondary_doc_dirt_lowconf_area_20261101'
PARENT_BUILDER = PARENT / 'tools/build_doc_dirt_lowconf_area_r2.py'
PARENT_SHA = '3E0897BD497E4359F2E7D5209B731E52F2CDD9BEDF6E61CE957C62C62659E9B6'

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()

def main():
    tests = []
    def positive(name, function):
        result = function()
        tests.append({'name': name, 'status': 'PASS'})
        return result
    def rejected(name, function, fragment):
        try:
            function()
        except RuntimeError as error:
            require(fragment in str(error), name + ': wrong rejection ' + str(error))
            tests.append({'name': name, 'status': 'PASS_REJECTED', 'reason': str(error)})
            return
        raise AssertionError(name + ': invalid input was accepted')

    positive('frozen_parent_builder_unchanged', lambda: require(sha(PARENT_BUILDER) == PARENT_SHA,
             'Parent builder changed'))
    recipe = json.loads((ROOT / 'reports/factored_build_adapter/ADAPTER_REPLACEMENTS.json').read_text())
    expected = PARENT_BUILDER.read_text(encoding='utf-8')
    for before, after in recipe['replacements'].items():
        require(before in expected, 'Missing declared replacement')
        expected = expected.replace(before, after)
    expected = expected.replace('Build fixed-dirt compensation and optional real low scores with original soft flag6.',
         'Build fixed-dirt compensation and factored optional real low scores with original soft flag6.', 1)
    expected = expected.replace('Only vision_pipeline.v has the exact reviewed opt-in low-score output delta;',
         'Only vision_pipeline.v has the exact reviewed factored opt-in low-score output delta;', 1)
    expected = expected.replace("'default_pipeline_parameter_zero_preserves_golden': True,\n        'main_bit_change_required'",
         "'default_pipeline_parameter_zero_preserves_golden': True,\n        'hard_rejection_separated_from_soft_diagnostics': True,\n        'main_bit_change_required'", 1)
    positive('exact_name_pin_metadata_adapter_no_gate_or_flow_relaxation',
         lambda: require((ROOT / builder.SELF).read_text(encoding='utf-8') == expected,
         'Undeclared builder delta'))
    closed = positive('successful_compact_baseline_bit_and_201_input_snapshots', builder.baseline)
    production = {p: x for p, x in closed['syn_1']['files'].items() if x['kind'] in builder.PRODUCTION_KINDS}
    positive('exact_133_production_closure', lambda: require(len(production) == 133, 'Production closure count differs'))
    checked = positive('real_current_scope_all_source_model_constraint_checks', lambda: builder.scope(closed))
    positive('factored_gate_exact_source_semantics', lambda: require(checked['top_and_pipeline_parameters'].get(
        'hard_rejection_separated_from_soft_diagnostics') is True, 'Missing factored source check'))
    positive('no_run_created_by_test_or_import', lambda: require(not (ROOT / builder.RUNS).exists(),
        'Run already exists: run this selftest before prepare'))
    extras = positive('real_qualified_extra_inputs_and_original_dependencies', lambda: builder.extras(closed))
    wrapper = builder.regression.wrapper_qualification()
    positive('all_wrapper_inputs_retained_without_reclassifying_active_rtl', lambda: require(
        all(p in production or p in extras for p in wrapper), 'Omitted wrapper input'))
    positive('audit_config_exact_parent_bytes', lambda: require(sha(ROOT / builder.AUDIT_CONFIG) ==
        sha(PARENT / 'tools/release_audit_doc_dirt_lowconf_area_config.json'), 'Audit config differs'))

    # This object is only an in-memory source-closure unit fixture. It is not a
    # TD source_snapshot.json and is never written into a build/run directory.
    entries = {p: {'path': str(ROOT / p), 'kind': x['kind'], 'sha256': sha(ROOT / p)}
               for p, x in production.items()}
    entries.update({p: {'path': str(ROOT / p), 'kind': 'explicit_dependency', 'sha256': sha(ROOT / p)}
                    for p in extras})
    snapshot = {'passed': True, 'errors': [], 'project_root': str(ROOT), 'files': list(entries.values())}
    positive('in_memory_current_closure_unit_fixture_not_reused_snapshot', lambda: builder.scope(closed, snapshot))
    for relative in ('01_rtl/cnn_core.v', '01_rtl/cnn_result_stabilizer.v', builder.TOP,
                     builder.PIPELINE, builder.FRONTEND):
        altered = copy.deepcopy(snapshot)
        altered['files'] = [x for x in altered['files'] if Path(x['path']).resolve() != ROOT / relative]
        rejected('reject_missing_production_' + relative, lambda s=altered: builder.scope(closed, s),
                 'Current active source closure differs')
    for relative in ('tools/key3_stroke_lowconf_factored_regression_gate.py',
                     builder.regression.WRAPPER_PREPARED, builder.SELF):
        altered = copy.deepcopy(snapshot)
        altered['files'] = [x for x in altered['files'] if Path(x['path']).resolve() != ROOT / relative]
        rejected('reject_missing_explicit_' + relative, lambda s=altered: builder.scope(closed, s),
                 'Missing explicit build/proof dependency')
    altered = copy.deepcopy(snapshot)
    altered['files'].append(copy.deepcopy(altered['files'][0]))
    rejected('reject_duplicate_frozen_source', lambda: builder.scope(closed, altered),
             'Current frozen input drift/duplicate')

    original_sha = builder.sha
    for relative in (builder.FRONTEND, builder.TOP, builder.PIPELINE, '01_rtl/cnn_core.v',
                     '01_rtl/cnn_result_stabilizer.v', '01_rtl/pcb_tinycnn_core.v', '04_pin/timing.sdc'):
        def drift(path, relative=relative):
            return '0' * 64 if Path(path).resolve() == ROOT / relative else original_sha(path)
        with mock.patch.object(builder, 'sha', drift):
            rejected('reject_drift_' + relative, lambda: builder.scope(closed),
                     'Unreviewed frontend RTL' if relative == builder.FRONTEND else 'Protected RTL/model/IP/constraint changed')
    original_load = builder.load
    for name, target, change, fragment in (
        ('creation_root', builder.CREATION, lambda x: x.update(project_root=str(PARENT)), 'Creation manifest changed scope'),
        ('creation_pipeline_pin', builder.CREATION,
         lambda x: x['rtl_delta'][builder.PIPELINE].update(after='0'*64), 'Creation manifest changed scope'),
        ('audit_config', builder.AUDIT_CONFIG,
         lambda x: x['resolved_memory_references'].pop(), 'Document audit config changed')):
        def drift_load(path, target=target, change=change):
            value = original_load(path)
            if Path(path).resolve() == ROOT / target:
                value = copy.deepcopy(value)
                change(value)
            return value
        with mock.patch.object(builder, 'load', drift_load):
            rejected('reject_' + name, lambda: builder.scope(closed), fragment)
    protected = ('tools/build_vector_release.py', 'tools/review_remote_physical.py',
                 'tools/key3_physical_gate.py', 'tools/key3_stroke_regression_gate.py',
                 'tools/run_doc_dirt_regression.py', 'tools/run_cnn_lowconf_accept.py')
    positive('all_original_reviewers_runners_and_physical_gates_byte_equal_parent', lambda: require(
        all(sha(ROOT / p) == sha(PARENT / p) for p in protected), 'Original gate/reviewer/runner changed'))
    positive('fatal_GP1_codes_still_blanket_rejected', lambda: require(
        "('PHY-7027', 'PHY-9002', 'RTCLK-5078', 'USR-6113', 'HDL-5105')" in expected and
        "'Forbidden placement/clock/ROM diagnostic'" in expected, 'Forbidden diagnostics changed'))
    output = {'status': 'PASS', 'test_count': len(tests), 'builder': builder.SELF,
        'builder_sha256': sha(ROOT / builder.SELF), 'parent_builder_sha256': sha(PARENT_BUILDER),
        'scope': checked, 'production_files': len(production), 'extra_inputs': len(extras),
        'wrapper_inputs': len(wrapper), 'synthetic_fixture_is_not_build_approval': True,
        'no_TD_started': True, 'no_run_prepared': True, 'no_production_or_qualification_inputs_modified': True,
        'hardware_status': 'NOT_RUN', 'tests': tests}
    (ROOT / 'reports/factored_build_adapter/SELFTEST.json').write_text(json.dumps(output, indent=2)+'\n', encoding='utf-8')
    print('PASS FACTORED_BUILDER_SELFTEST', len(tests))

if __name__ == '__main__':
    main()
