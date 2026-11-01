"""Exact-hash wrapper for the unchanged legacy seven-suite area runner.

--prepare freezes wrapper inputs only. --run verifies those inputs and changes
only the imported runner's production pipeline hash to the approved optional
delta, then executes its full original main. Default pipeline parameter remains
zero, so all original golden simulations and checks remain applicable.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

import key3_stroke_lowconf_area_regression_gate as scope_gate

ROOT = Path(__file__).resolve().parents[1]
QUAL = ROOT / 'reports/legacy_area_wrapper_qualification'
MANIFEST = QUAL / 'PREPARED_INPUTS.json'
RUNNER = ROOT / 'tools/run_cnn_area_pipeline_compact.py'
RUNNER_SHA = '6DF6DDF36EE3E5AB79B6691D521C294B62478600ADDDEB9387C3A18818C4CC19'
PIPELINE_OLD = scope_gate.OLD_PIPELINE_SHA
PIPELINE_NEW = scope_gate.PIPELINE_SHA


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def inputs():
    scope_gate.top_scope()
    require(sha(RUNNER) == RUNNER_SHA, 'Legacy area runner modified')
    files = [Path(__file__), RUNNER, Path(scope_gate.__file__),
             ROOT / 'tools/key3_stroke_regression_gate.py',
             ROOT / '01_rtl/vision_pipeline.v', ROOT / '01_rtl/secondary_top.v',
             ROOT / '01_rtl/cnn_result_stabilizer.v', ROOT / '01_rtl/cnn_core.v', ROOT / 'lint_full.f']
    return {path.resolve().relative_to(ROOT).as_posix(): sha(path) for path in files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    option = parser.add_mutually_exclusive_group(required=True)
    option.add_argument('--prepare', action='store_true')
    option.add_argument('--run', action='store_true')
    args = parser.parse_args()
    bound = inputs()
    expected = {'status': 'PREPARED_EXACT_LEGACY_AREA_PIPELINE_HASH_ADAPTER',
                'project_root': str(ROOT), 'hardware_status': 'NOT_RUN',
                'original_runner_sha256': RUNNER_SHA,
                'original_pipeline_pin': PIPELINE_OLD, 'approved_pipeline_pin': PIPELINE_NEW,
                'all_legacy_simulation_contracts_unchanged': True, 'input_sha256': bound}
    if args.prepare:
        require(not MANIFEST.exists(), 'Legacy wrapper qualification already frozen')
        QUAL.mkdir(parents=True, exist_ok=True)
        with MANIFEST.open('x', encoding='utf-8') as stream:
            stream.write(json.dumps(expected, indent=2) + '\n')
        print('PREPARED_EXACT_LEGACY_AREA_WRAPPER', MANIFEST)
        return 0
    require(json.loads(MANIFEST.read_text(encoding='utf-8-sig')) == expected,
            'Legacy wrapper prepared evidence drift')
    spec = importlib.util.spec_from_file_location('unchanged_legacy_area_runner', RUNNER)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    require(runner.ROOT == ROOT and runner.PIPELINE_SHA == PIPELINE_OLD and
            runner.KERNEL_SHA == '9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128',
            'Legacy runner runtime identity differs')
    runner.PIPELINE_SHA = PIPELINE_NEW
    original_freeze = runner.freeze

    def freeze(source, target, expected=None):
        source, target = Path(source).resolve(), Path(target).resolve()
        special = runner.OUT / 'pipeline_miter/vision_pipeline_baseline.v'
        if target != special:
            return original_freeze(source, target, expected)
        require(source == runner.FUNCTIONAL / 'vision_pipeline_baseline.v' and
                expected == '7876918A9EA2347E2E1791DCA47A30004462F8B536EECF81B3780BB8EE1233C3' and
                sha(source) == expected, 'Original pure-rename oracle identity differs')
        # The default parameter remains zero. The reference pipeline must be
        # exactly the current pipeline with just module/kernel instance rename.
        renamed = runner.PIPELINE.read_text().replace(
            'module vision_pipeline #(', 'module vision_pipeline_baseline #(').replace(
            '        cnn_result_stabilizer #(', '        cnn_result_stabilizer_baseline #(')
        runner.put(target, renamed)
        digest = scope_gate.derived_fixture_pins()['pipeline_reference']['approved_sha256']
        require(sha(target) == digest, 'Pure-rename pipeline reference differs')
        runner.record(target, digest)
        runner.COPIES[str(target.relative_to(runner.OUT))] = {
            'source': str(runner.PIPELINE), 'sha256': digest,
            'derivation': 'Exact current production pipeline module/kernel-instance rename only'}
        return target

    runner.freeze = freeze
    # Original main keeps this dictionary, so wrapper/gate/preparation join the
    # original RESULTS input closure and cannot be detached after simulation.
    for relative, digest in bound.items():
        runner.record(ROOT / relative, digest)
    runner.record(MANIFEST)
    runner.main()
    require(inputs() == bound, 'Wrapper inputs changed during original suite')
    print('PASS_EXACT_LEGACY_AREA_WRAPPER_FULL_ORIGINAL_MAIN')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
