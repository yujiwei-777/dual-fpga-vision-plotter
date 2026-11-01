"""Supplement identity negatives only; does not inspect or alter live bitgen."""
import copy
import importlib.util
import json
from pathlib import Path
from unittest import mock

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('completed_finalizer_test', OUT / 'finalize_completed_delivery.py')
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)


def main():
    cases = []
    f.supplement_inputs()
    def reject(name, function, fragment):
        try:
            function()
        except RuntimeError as error:
            assert fragment in str(error), (name, str(error))
            cases.append({'name': name, 'status': 'EXPECTED_REJECTION', 'reason': str(error)})
            return
        raise AssertionError('Invalid supplement accepted: ' + name)
    original_sha, original_load = f.sha, f.load
    for path in [f.ORIGINAL] + [f.ROOT / p for p in f.SUPPLEMENT]:
        with mock.patch.object(f, 'sha', lambda p, path=path:
                '0' * 64 if Path(p).resolve() == path else original_sha(p)):
            reject('reject_supplement_drift_' + path.name, f.supplement_inputs,
                'Original strict finalizer changed' if path == f.ORIGINAL else 'Manifest-completion input changed')
    for key, value in (('negative_count', 20), ('current_manifest_unchanged', False),
                       ('no_original_rule_or_error_filter_modified', False),
                       ('no_TD_or_gate_or_readonly_or_bitgen_executed', False)):
        def load(path, key=key, value=value):
            data = original_load(path)
            if Path(path).name == 'SELFTEST.json':
                data = copy.deepcopy(data)
                data[key] = value
            return data
        with mock.patch.object(f, 'load', load):
            reject('reject_invalid_negative_proof_' + key, f.supplement_inputs,
                   'Manifest-completion negative proof differs')
    assert f.sha(f.ORIGINAL) == f.ORIGINAL_SHA
    assert not (OUT / 'COMPLETED_RELEASE.json').exists()
    result = {'status': 'PASS_SUPPLEMENT_NEGATIVES_ONLY_NOT_FINAL_RELEASE', 'count': len(cases),
        'cases': cases, 'wrapped_finalizer_unchanged_sha256': f.sha(f.ORIGINAL),
        'completed_finalizer_sha256': f.sha(f.__file__), 'no_gate_or_TD_or_publish_executed': True}
    (OUT / 'COMPLETED_FINALIZER_SELFTEST.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('PASS COMPLETED_FINALIZER_NEGATIVES_ONLY', len(cases))


if __name__ == '__main__':
    main()
