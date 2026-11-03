"""Read-only verification of the V4 -> V5 -> V6 spatial implementation chain.

These two trials supplement the fresh canonical integer-oracle regression.
They never certify physical resources, timing or camera/board image quality.
"""
import argparse
import hashlib
from pathlib import Path
import re

from display_noise_paths import ROOT, obj, read, sha, put

V4 = '9FE7A1A5323340F854B312C1BBC33D72351D8065551878FA3A93A19469CF80EE'
V5 = 'B680381A4307D79BC6B259A8B33C177E5F2CD59120FF38EE902BC691438C20A0'
V6 = 'CD72245FA5CF73F16F35C2F655E5F13DD5F4949D14D258A7B99F9179AA219696'
CASES = {
    'flat_noise': (128, 64, 9623, 8192),
    'strong_edges': (32, 12, 2230, 1920),
    'rgb8_range': (5, 3, 3846, 3840),
    'threshold_rgb_guard': (16, 6, 135, 96),
    'geometry_1x1': (1, 1, 20, 4),
    'geometry_1x7': (1, 7, 64, 22),
    'geometry_2x5': (2, 5, 67, 32),
    'geometry_7x1': (7, 1, 45, 28),
    'geometry_7x5': (7, 5, 156, 112),
    'malformed_reentry': (8, 4, 131, 93),
    'full_720p': (1280, 720, 1843206, 1843200),
}
SOURCES = {
    'combined': frozenset('''a4_display_spatial_combined.v a4_display_spatial_frozen.v
        tb_display_spatial.sv run_combined.ps1 summarize_combined.py vectors_manifest.json
        prove_control.py control_invariant.json'''.split()),
    'nocarry': frozenset('''a4_display_spatial_nocarry.v a4_display_spatial_frozen.v
        close_byte_th16.vh check_close_byte.py close_byte_check.json ARITHMETIC_REVIEW.md
        prepare_trial.py tb_display_spatial.sv run_nocarry.ps1 vectors_manifest.json
        summarize_nocarry.py'''.split()),
}
UNSPECIFIED = object()


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def clean_log(text, marker):
    return (marker in text and
            bool(re.search(r'(?m)^(?:# )?Errors: 0, Warnings: 0\s*$', text)) and
            not re.search(r'\*\*\s+(?:Warning|Error|Fatal):|(?m:^[# ]*Errors:\s*[1-9]\d*)|(?m:^[# ]*Errors:\s*\d+, Warnings:\s*[1-9]\d*)', text))


def validate(root=ROOT):
    """Return passed/errors/stages/evidence{absolute path:SHA256}/logs. No writes."""
    root = Path(root).resolve()
    errors, evidence, logs, stages = [], {}, [], {}

    def bind(path, digest=UNSPECIFIED):
        path = Path(path).resolve()
        require(path.is_relative_to(root) and path.is_file(), 'Missing/outside chain evidence: ' + str(path))
        actual = sha(path)
        require(digest is UNSPECIFIED or (isinstance(digest, str) and
                re.fullmatch(r'[0-9A-F]{64}', digest) and digest == actual),
                'Chain evidence SHA256 missing/mismatch: ' + str(path))
        evidence[path.as_posix()] = actual
        return path

    def bound_object(path, digest=UNSPECIFIED):
        return obj(bind(path, digest))

    try:
        bind(root / '01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v', V6)
        bind(root / 'reports/attempt4_rtl/a4_display_spatial_h1.v', V4)
        bind(root / 'reports/attempt5_rtl/a4_display_spatial_h1.v', V5)
        reference = bind(root / 'model/display_spatial_reference.py')
        reference_sha = sha(reference)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        errors.append(str(exc))
        return {'passed': False, 'errors': errors, 'stages': stages, 'evidence': evidence, 'logs': logs}
    for stage, original_sha, candidate_sha, candidate_name in (
        ('combined', V4, V5, 'a4_display_spatial_combined.v'),
        ('nocarry', V5, V6, 'a4_display_spatial_nocarry.v'),
    ):
        try:
            folder = root / ('02_sim/display_noise_' + stage + '_trial')
            report = bound_object(folder / 'verification.json')
            stages[stage] = report
            require(report.get('status') == 'PASS' and report.get('board_validation') == 'NOT_RUN', stage + ': rejected trial status')
            require(report.get('candidate_sha256') == candidate_sha and report.get('frozen_product_sha256') == original_sha,
                    stage + ': broken exact candidate/frozen chain')
            require(report.get('frozen_only_change') == 'module name' and report.get('reference_sha256') == reference_sha,
                    stage + ': reference or restored-module contract changed')
            sources = report.get('source_sha256', {})
            require(isinstance(sources, dict) and set(sources) == SOURCES[stage], stage + ': source evidence set reduced/expanded')
            for filename, digest in sources.items():
                bind(folder / filename, digest)
            bind(folder / candidate_name, candidate_sha)
            frozen = (folder / 'a4_display_spatial_frozen.v').read_bytes()
            declaration = b'module a4_display_spatial_frozen #('
            require(frozen.count(declaration) == 1, stage + ': frozen module declaration is not unique')
            restored = frozen.replace(declaration, b'module a4_display_spatial_h1 #(', 1)
            require(hashlib.sha256(restored).hexdigest().upper() == original_sha,
                    stage + ': restoring the module name does not reproduce frozen RTL')
            compile_path = bind(folder / 'compile.log', report.get('compile_sha256'))
            require(clean_log(read(compile_path), 'Top level modules:'), stage + ': compile log is not clean/completed')
            logs.append(compile_path.as_posix())
            manifest = bound_object(folder / 'vectors_manifest.json', sources['vectors_manifest.json'])
            require(manifest.get('rtl_sha256') == original_sha and manifest.get('reference_sha256') == reference_sha and
                    manifest.get('edge_threshold') == 16, stage + ': vector source/threshold contract changed')
            cases, vector_cases = report.get('cases', []), manifest.get('cases', [])
            for rows, description in ((cases, 'trial'), (vector_cases, 'vector')):
                require(isinstance(rows, list) and all(isinstance(c, dict) for c in rows) and len(rows) == len(CASES) and
                        {c.get('name') for c in rows} == set(CASES), stage + ': incomplete/duplicate ' + description + ' cases')
            vectors = {c['name']: c for c in vector_cases}
            total_cycles = total_valid = 0
            for case in cases:
                name = case['name']
                vector = vectors[name]
                expected = CASES[name]
                require(tuple(case.get(k) for k in ('width', 'height', 'cycles', 'valid_pixels')) == expected and
                        tuple(vector.get(k) for k in ('width', 'height', 'cycles', 'source_pixels')) == expected,
                        stage + ': geometry/cycle/pixel coverage changed: ' + name)
                inputs = vector.get('inputs', {})
                require(isinstance(inputs, dict) and set(inputs) == {'stim.mem', 'expected.mem', 'source.mem'}, stage + ': missing vector inputs: ' + name)
                for filename, digest in inputs.items():
                    bind(folder / name / filename, digest)
                transcript = bind(folder / name / 'transcript.log', case.get('transcript_sha256'))
                logs.append(transcript.as_posix())
                text = read(transcript)
                require(case.get('status') == 'PASS' and clean_log(text, 'frozen_all_cycles_including_invalid_data_equal'),
                        stage + ': case log/status failed: ' + name)
                matches = re.findall(r'PASS pixel oracle WIDTH=(\d+) HEIGHT=(\d+) cycles=(\d+) valid=(\d+) sof=(\d+) eol=(\d+) all_markers_and_ENABLE0_checked frozen_all_cycles_including_invalid_data_equal', text)
                require(len(matches) == 1 and tuple(map(int, matches[0][:4])) == expected and
                        tuple(map(int, matches[0][4:])) == (case.get('sof'), case.get('eol')),
                        stage + ': transcript transaction counts changed: ' + name)
                exhaustive = ('PASS exhaustive RTL avg2 pairs=65536' if stage == 'combined' else
                              'PASS exhaustive RTL avg2 pairs=65536 TH16_byte_pairs=65536 TH16_rgb_channel_pairs=196608')
                require(len(re.findall(r'(?m)^(?:# )?' + re.escape(exhaustive) + r'\r?$', text)) == 1,
                        stage + ': missing exhaustive arithmetic coverage: ' + name)
                total_cycles += expected[2]
                total_valid += expected[3]
            require(report.get('total_cycles') == total_cycles and report.get('total_valid_pixels') == total_valid,
                    stage + ': total cycle/pixel counts mismatch')
            if stage == 'combined':
                control = bound_object(folder / 'control_invariant.json', sources['control_invariant.json'])
                require(report.get('rtl_avg2_exhaustive_pairs_per_case') == 65536 and
                        report.get('control_invariant') == control and control.get('status') == 'PASS',
                        stage + ': control/arithmetic evidence missing')
                rows = control.get('cases', [])
                expected_geometries = {(1, 2), (1, 7), (2, 1), (2, 2), (2, 5), (3, 3), (7, 1), (7, 5), (16, 6)}
                require(len(rows) == 9 and {(r.get('width'), r.get('height')) for r in rows} == expected_geometries,
                        stage + ': control-state coverage reduced')
                for row in rows:
                    require(row.get('reachable_states', 0) > 0 and row.get('transitions') == row['reachable_states'] * 8 and
                            row.get('explicit_forwarding_required') is (row['width'] == 1) and
                            ((row['width'] == 1 and row.get('unmasked_collisions', 0) > 0) or
                             (row['width'] > 1 and row.get('unmasked_collisions') == 0)),
                            stage + ': invalid row forwarding invariant')
            else:
                arithmetic = bound_object(folder / 'close_byte_check.json', sources['close_byte_check.json'])
                require(arithmetic.get('status') == 'PASS' and arithmetic.get('byte_pairs') == 65536 and
                        arithmetic.get('accepted') == 8176 and report.get('independent_python_byte_pairs') == 65536 and
                        report.get('accepted_byte_pairs') == 8176 and report.get('per_case_exhaustive_rtl') ==
                        {'avg2_byte_pairs': 65536, 'th16_byte_pairs': 65536, 'th16_rgb_channel_pairs': 196608},
                        stage + ': byte/RGB predicate exhaustive coverage changed')
                require(set(arithmetic.get('source_sha256', {})) == {'close_byte_th16.vh', 'check_close_byte.py'},
                        stage + ': incomplete independent arithmetic sources')
                for filename, digest in arithmetic['source_sha256'].items():
                    bind(folder / filename, digest)
        except (OSError, ValueError, KeyError, TypeError) as exc:
            errors.append(stage + ': ' + str(exc))
    return {'passed': not errors, 'errors': errors, 'stages': stages,
            'evidence': evidence, 'logs': logs, 'hardware_status': 'NOT_RUN',
            'scope': 'Implementation-equivalence evidence supplements fresh canonical tests; no physical or camera acceptance.'}


def validate_binding(regression, chain):
    """Require every independently validated proof input in collector hashes."""
    errors = []
    if chain.get('passed') is not True:
        errors.append('Equivalence chain must pass before evidence binding')
    hashes = {str(Path(p).resolve()).replace('\\', '/').casefold(): value
              for p, value in regression.get('input_hashes', {}).items()}
    for path, digest in chain.get('evidence', {}).items():
        if hashes.get(str(Path(path).resolve()).replace('\\', '/').casefold()) != digest:
            errors.append('Unbound/stale implementation-equivalence evidence: ' + path)
    return {'passed': not errors, 'errors': errors, 'required_evidence_count': len(chain.get('evidence', {}))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    result = validate()
    if args.out:
        put(args.out, result)
    print({'passed': result['passed'], 'errors': result['errors'], 'evidence_count': len(result['evidence'])})
    raise SystemExit(int(not result['passed']))
