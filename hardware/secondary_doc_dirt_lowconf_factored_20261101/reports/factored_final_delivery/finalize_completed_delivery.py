"""Wrap the frozen strict finalizer with the exact five-entry comparison proof."""
import argparse
import csv
import importlib.util
import io
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
ORIGINAL = OUT / 'finalize_delivery.py'
ORIGINAL_SHA = '89B57D35EBC1ED16E9794B1437B7093BD39684627AFED32CBE8721FC047FE13B'
SUPPLEMENT = {
    'reports/factored_manifest_completion/complete_release.py': '1A507D511DD0B64ABC3D3262AD6AEFEE1FCD98BA630A1411E8F4416CCEC5698B',
    'reports/factored_manifest_completion/SELFTEST.json': '2BDEB05AC8140BE1EBDB6BDB96832AC1A40A682D9673B62779607EA9C605D46B',
    'reports/factored_manifest_completion/test_completion.py': 'DE313FD7D0890E6C1A709FF77F3F2B821CD4056046A03A60D5370D946D2CEF52',
    'reports/factored_manifest_completion/ORIGINAL_FAILURE_ARCHIVE.json': '5D13BFB317CF2B48646329D8134B2E79D47D2746048F32E22875E17BCD9E6BF2',
}


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


original = module(ORIGINAL, 'original_factored_finalizer')
require, sha, load = original.require, original.sha, original.load


def supplement_inputs():
    require(ROOT == original.ROOT and sha(ORIGINAL) == ORIGINAL_SHA, 'Original strict finalizer changed')
    for relative, expected in SUPPLEMENT.items():
        require(sha(ROOT / relative) == expected, 'Manifest-completion input changed: ' + relative)
    tests = load(ROOT / 'reports/factored_manifest_completion/SELFTEST.json')
    require(tests['status'] == 'PASS_READONLY_MANIFEST_COMPLETION_TESTS_NOT_BUILD_APPROVAL' and
            tests['negative_count'] == 21 and len(tests['cases']) == 21 and
            all(x['status'] == 'EXPECTED_REJECTION' for x in tests['cases']) and
            tests['adapter_sha256'] == SUPPLEMENT['reports/factored_manifest_completion/complete_release.py'] and
            tests['current_manifest_unchanged'] is True and
            tests['no_original_rule_or_error_filter_modified'] is True and
            tests['no_TD_or_gate_or_readonly_or_bitgen_executed'] is True,
            'Manifest-completion negative proof differs')
    return tests


def verify():
    tests = supplement_inputs()
    completion = module(ROOT / 'reports/factored_manifest_completion/complete_release.py',
                        'final_exact_manifest_completion')
    proof = completion.qualify()
    physical_path = ROOT / '02_sim' / (original.RUN.name + '_physical_review/FINAL_PHYSICAL_REVIEW.json')
    physical = load(physical_path)
    require(physical.get('baseline_manifest_completion') == proof and
            physical.get('baseline_manifest_completion_adapter_sha256') == SUPPLEMENT[
                'reports/factored_manifest_completion/complete_release.py'], 'Missing/changed physical completion proof')
    require(tests['qualification'] == proof, 'Qualification changed after negative tests')
    # No original threshold, source, CDC/FIFO/DDR/reset, readonly, regression,
    # bit-byte or final diagnostic check is replaced or patched here.
    report = original.verify()
    hashes = dict(SUPPLEMENT)
    hashes[ORIGINAL.relative_to(ROOT).as_posix()] = ORIGINAL_SHA
    archive = load(ROOT / 'reports/factored_manifest_completion/ORIGINAL_FAILURE_ARCHIVE.json')
    hashes.update(archive['files_sha256'])
    inventory = []
    for relative, expected in hashes.items():
        path = (ROOT / relative).resolve(strict=True)
        require(path.is_relative_to(ROOT) and sha(path) == expected, 'Supplement evidence changed: ' + relative)
        report['bound_evidence_sha256'][relative] = expected
        inventory.append({'path': relative, 'sha256': expected, 'bytes': path.stat().st_size,
                          'kind': 'post_route_comparison_proof_not_production'})
    require(completion.qualify() == proof, 'Completion proof changed during final verification')
    report['baseline_manifest_completion'] = proof
    report['manifest_completion_note'] = (
        'Exactly five AutoExcluded simulation-only explicit dependencies were absent from the successful '
        'baseline frozen comparison map. Their baseline/current bytes match exact pinned hashes. '
        'Only the original reviewer baseline manifest return mapping was extended; production source '
        'graph, baseline snapshots, original reviewer rules and errors remain unchanged. The original '
        'failed review is retained by hash. All original final release gates passed independently.')
    report['verification_supplement_inventory'] = inventory
    report['wrapped_finalizer_sha256'] = ORIGINAL_SHA
    report['finalizer_sha256'] = sha(__file__)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    report = verify()
    if args.publish:
        targets = [OUT / name for name in ('COMPLETED_RELEASE.json', 'COMPLETED_FROZEN_INPUTS.csv',
                                            'MANIFEST_COMPLETION_INPUTS.csv')]
        require(not any(p.exists() for p in targets), 'Preserve existing completed release/inventory')
        targets[0].write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
        for target, rows in ((targets[1], report['source_inventory']),
                             (targets[2], report['verification_supplement_inventory'])):
            buf = io.StringIO(newline='')
            writer = csv.DictWriter(buf, fieldnames=('path', 'sha256', 'bytes', 'kind'))
            writer.writeheader()
            writer.writerows(rows)
            target.write_text(buf.getvalue(), encoding='utf-8-sig')
    print(json.dumps({k: report[k] for k in ('status', 'bit', 'bit_sha256', 'timing_ns', 'resources')}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, AssertionError, KeyError, ValueError) as error:
        import sys
        print('COMPLETED_FINAL_DELIVERY_FAIL:', error, file=sys.stderr)
        raise SystemExit(1)
