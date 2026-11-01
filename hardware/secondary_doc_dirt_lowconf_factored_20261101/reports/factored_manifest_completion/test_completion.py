"""Read-only exact-completion tests. Never calls routed gate, readonly or TD."""
import copy
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
from unittest import mock
import xml.etree.ElementTree as ET

OUT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('completion_under_test', OUT / 'complete_release.py')
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


def main():
    cases = []
    proof = c.qualify()
    def reject(name, function, fragment):
        try:
            function()
        except RuntimeError as error:
            assert fragment in str(error), (name, str(error))
            cases.append({'name': name, 'status': 'EXPECTED_REJECTION', 'reason': str(error)})
            return
        raise AssertionError('Invalid completion was accepted: ' + name)

    original_sha, original_load = c.sha, c.load
    paths = [(c.ROOT / p, 'Snapshot source duplicate/drift') for p in c.ADDITIONS]
    paths += [(c.BASE / p, 'Completion input is not unchanged baseline bytes') for p in c.ADDITIONS]
    paths += [(c.RUN / 'phy_1/secondary_cnn_multibox_pr.db', 'Routed snapshot/database/project drift'),
              (c.REVIEWER, 'Original builder/reviewer changed'),
              (c.ROOT / '04_pin/timing.sdc', 'Snapshot source duplicate/drift'),
              (c.ROOT / c.PREPARED, 'Frozen plan/qualification/failure archive changed')]
    for path, fragment in paths:
        with mock.patch.object(c, 'sha', lambda p, path=path:
                '0' * 64 if Path(p).resolve() == path else original_sha(p)):
            reject('reject_byte_drift_' + path.relative_to(c.ROOT.parent).as_posix(), c.qualify, fragment)

    first = next(iter(c.ADDITIONS))
    def change_snapshot(name, target, mutation, fragment):
        def load(path):
            value = original_load(path)
            if Path(path).resolve() == target:
                value = copy.deepcopy(value)
                mutation(value)
            return value
        with mock.patch.object(c, 'load', load):
            reject(name, c.qualify, fragment)
    def edit_entry(data, field, value):
        for x in data['files']:
            if Path(x['path']).resolve() == c.ROOT / first:
                x[field] = value
                return
        raise AssertionError('Missing fixture entry')
    change_snapshot('reject_simulation_file_promoted_to_production', c.RUN / 'syn_1/source_snapshot.json',
        lambda x: edit_entry(x, 'kind', 'Verilog'), 'Production closure expanded')
    change_snapshot('reject_non_extra_origin', c.RUN / 'syn_1/source_snapshot.json',
        lambda x: edit_entry(x, 'origins', ['active production']), 'Completion input kind/origin/qualification differs')
    change_snapshot('reject_additional_protected_manifest_gap', c.BASE_RUN / 'syn_1/source_snapshot.json',
        lambda x: x.update(files=[r for r in x['files'] if not r['path'].endswith('/shared/rtl/hxa_secondary_link.v')]),
        'Protected comparison gap is not the exact five entries')
    with mock.patch.object(c, 'ROOT', c.ROOT.parent):
        reject('reject_wrong_root', c.qualify, 'Wrong completion root/run')

    xml = ET.fromstring('<Project><Source_Files><Verilog><File Path="' + str(c.ROOT / first).replace('\\', '/') +
        '"><FileInfo><Attr Name="AutoExcluded" Val="false"/></FileInfo></File></Verilog></Source_Files></Project>')
    with mock.patch.object(c.builder.flow, 'module', lambda *args: SimpleNamespace(xml=lambda path: xml)):
        reject('reject_active_project_reference', lambda: c.excluded_project(c.ROOT / 'secondary_cnn_multibox.al'),
            'Completion input is active/duplicated')
    reject('reject_unexpected_manifest_invocation', lambda: c.extend_manifest(
        lambda *args: ({}, {}), c.ROOT.parent, c.ROOT.parent, []), 'Unexpected reviewer manifest invocation')
    reject('reject_baseline_entry_already_present', lambda: c.extend_manifest(
        lambda *args: ({}, {first: c.ADDITIONS[first]}), c.BASE_RUN, c.BASE, []),
        'Completion entry already present')

    # The current manifest object and dictionary are returned without alteration.
    data, entries, calls = {'unit': 'current'}, {'existing': 'HASH'}, []
    actual = c.extend_manifest(lambda *args: (data, entries), c.RUN, c.ROOT, calls)
    assert actual[0] is data and actual[1] is entries and calls == ['current']
    assert c.qualify() == proof
    result = {'status': 'PASS_READONLY_MANIFEST_COMPLETION_TESTS_NOT_BUILD_APPROVAL',
        'negative_count': len(cases), 'cases': cases, 'qualification': proof,
        'current_manifest_unchanged': True, 'no_original_rule_or_error_filter_modified': True,
        'no_TD_or_gate_or_readonly_or_bitgen_executed': True, 'adapter_sha256': c.sha(c.__file__)}
    (OUT / 'SELFTEST.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('PASS EXACT_MANIFEST_COMPLETION_SELFTEST', len(cases), 'negative cases')


if __name__ == '__main__':
    main()
