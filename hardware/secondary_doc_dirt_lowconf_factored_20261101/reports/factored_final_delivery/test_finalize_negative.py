"""Negative unit checks only; no release success or physical evidence is synthesized."""
import copy
import importlib.util
import json
from pathlib import Path
from unittest import mock

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('factored_finalizer_under_test', OUT / 'finalize_delivery.py')
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)


def main():
    cases = []
    protected = [f.ROOT / p for p in f.PRODUCTION_PINS] + [f.RUN / 'BUILD_PLAN.json',
        f.ROOT / 'tools/build_doc_dirt_lowconf_factored.py']
    before = {str(p): f.sha(p) for p in protected}
    def reject(name, function, fragment):
        try:
            function()
        except RuntimeError as error:
            assert fragment in str(error), (name, str(error))
            cases.append({'name': name, 'status': 'EXPECTED_REJECTION', 'reason': str(error)})
            return
        raise AssertionError('Invalid input was accepted: ' + name)

    reject('actual_build_without_routed_bit_is_not_ready', f.verify, 'NOT_READY: missing')
    original_sha = f.sha
    for path in protected[:4]:
        with mock.patch.object(f, 'sha', lambda p, path=path:
             '0' * 64 if Path(p).resolve() == path else original_sha(p)):
            reject('source_or_plan_drift_' + path.name, f.verify_production,
                'Frozen build plan differs' if path.name == 'BUILD_PLAN.json' else 'Production pin differs')
    with mock.patch.object(f, 'ROOT', f.ROOT.parent):
        reject('wrong_independent_root', f.verify_production, 'Wrong/protected root')
    reject('non_diagnostic_build_status', lambda: f.verify_gate(
        {'status': 'FAILED', 'hardware_validation': 'NOT_RUN'}, {}), 'Bit status differs')
    build = {'status': 'DIAGNOSTIC_NOT_RUN', 'hardware_validation': 'NOT_RUN',
        'baseline_bit_sha256': f.BASE_SHA, 'runs': str(f.RUN), 'bit': f.BIT.name}
    for gate in ({'passed': False}, {'passed': True, 'bitgen_allowed': False},
                 {'passed': True, 'bitgen_allowed': True, 'failures': ['synthetic failure']}):
        reject('failed_routed_gate_' + str(len(cases)), lambda g=gate: f.verify_gate(build, g), 'Routed gate failed')
    reject('failed_readonly', lambda: f.verify_readonly_identity(
        {'passed': False}, {}), 'Readonly verification failed')
    reject('missing_readonly_DB_AL_hashes', lambda: f.verify_readonly_identity(
        {'passed': True, 'failures': [], 'hardware_status': 'NOT_RUN'}, {}), 'Readonly DB/AL closure differs')
    quality = f.load(f.ROOT / 'reports/factored_delivery_quality/QUALITY.json')
    for name, mutation, fragment in (
        ('quality_hardware_claim', lambda q: q.update(hardware_status='PASS'), 'Quality scope differs'),
        ('quality_unbound_plan', lambda q: q.update(build_plan_bound=False), 'Quality root/run/plan differs'),
        ('quality_wrong_source_scope', lambda q: q.update(source_scope={}), 'Quality current-source/RTL evidence differs'),
        ('quality_wrong_production', lambda q: q.update(production_sha256={}), 'Quality production pins differ'),
        ('quality_physical_overclaim', lambda q: q.update(physical_build_acceptance_claimed=True), 'Quality overclaims'),
        ('quality_missing_limits', lambda q: q.update(limitations=[]), 'Quality overclaims')):
        value = copy.deepcopy(quality)
        mutation(value)
        reject(name, lambda q=value: f.verify_quality(q, quality['source_scope'],
             quality['doc_regression'], quality['lowconfidence_regression']), fragment)
    assert {str(p): f.sha(p) for p in protected} == before
    assert not (OUT / 'RELEASE.json').exists() and not (OUT / 'FROZEN_INPUTS.csv').exists()
    result = {'status': 'PASS_NEGATIVE_SELFTEST_ONLY_NOT_RELEASE_EVIDENCE',
        'cases': cases, 'count': len(cases), 'actual_finalizer_status': 'NOT_READY',
        'no_TD_started': True, 'no_PASS_release_or_fake_route_artifacts_created': True,
        'protected_inputs_unchanged': True, 'finalizer_sha256': f.sha(OUT / 'finalize_delivery.py'),
        'test_sha256': f.sha(__file__), 'hardware_status': 'NOT_RUN'}
    (OUT / 'NEGATIVE_SELFTEST.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('PASS NEGATIVE_FINALIZER_SELFTEST_ONLY', len(cases), 'actual release NOT_READY')

if __name__ == '__main__':
    main()
