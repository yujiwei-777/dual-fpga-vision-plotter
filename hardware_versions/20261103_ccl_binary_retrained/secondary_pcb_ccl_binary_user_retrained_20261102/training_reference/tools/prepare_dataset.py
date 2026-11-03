"""Prepare only the user-approved binary PCB sources; do not fit a model.

The input contract is the ORIGINAL CCL box (1.0), sampled to 96x96 Y8.
Capture-folder blocks and guard bands are frozen before reading image pixels.
Existing complete output is verified, never overwritten.
"""
from collections import Counter, defaultdict
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent
OUT = ROOT / 'data'
REFERENCE = BASE / 'secondary_pcb_ccl_binary_roi120_20261102/tools/binary_validation_reference.py'
PRIOR = BASE / 'secondary_pcb_ccl_binary_roi120_20261102/reports/binary_restore/scale_sweep_user_only/FRAMES_ALLOWED_SCALES.json'
GROUPS = [
    (Path('D:/ai/1/0/1'), 'MISSING_PAD', 1),
    (Path('D:/ai/1/0/2'), 'GOOD', 0),
    (Path('D:/ai/1/0/de08d7322eef4609b468c9fa93a1b39b'), 'MISSING_CORNER', 1),
    (Path('D:/ai/1/8/1/2'), 'MISSING_PAD', 1),
    (Path('D:/ai/1/8/1/dff8edb30db143cd9cc9df11e729234c/3ec6043a95f54d5caa5fb0681ddcc101'), 'GOOD', 0),
]
SPLIT_CODE = {'train': 0, 'validation': 1, 'test': 2, 'guard': 3}
EXPECTED_COUNTS = [214, 219, 209, 201, 651]


def sha_bytes(value):
    return hashlib.sha256(value).hexdigest().upper()


def sha(path):
    return sha_bytes(Path(path).read_bytes())


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def save(name, value):
    path = OUT / name
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n')


def key(path):
    return str(Path(path).resolve()).replace('\\', '/').lower()


def policy():
    return {
        'schema_version': 1,
        'purpose': 'PCB supervised binary retraining dataset preparation only; no training',
        'allowed_roots': ['D:/ai/1/0/', 'D:/ai/1/8/1/'],
        'labels': [{'root': p.as_posix(), 'truth': t, 'label': label} for p, t, label in GROUPS],
        'label_source': 'Explicit human folder labels; ignore ordinary CNN class annotations and capture purpose',
        'expected_source_counts': EXPECTED_COUNTS,
        'source': {'width': 1280, 'height': 720, 'format': 'YUYV', 'Y_byte': 0,
                   'verify': ['raw byte count', 'metadata SHA256', 'CRC32', 'transport error counters',
                              'prior frozen source SHA256', 'prior frozen source-Y SHA256']},
        'ccl': {'grid': [160, 90], 'source_sample': '(8*x+4,8*y+4)',
                'foreground': 'source Y <= 112', 'connectivity': 4, 'max_provisional_labels': 510,
                'area_min': 64, 'width_min': 8, 'height_min': 4, 'max_reciprocal_aspect': 5,
                'density_gate': 'area*12 >= bbox_area', 'choice': 'largest area; first raster pixel tie break'},
        'roi': {'expansion_numerator': 1, 'expansion_denominator': 1, 'box': 'original CCL source half-open box',
                'shape': [96, 96], 'dtype': 'uint8', 'input': 'unsigned source Y8; no rotation or Y-128',
                'x': 'x0 + floor((2*u+1)*(x1-x0)/192), u=0..95',
                'y': 'y0 + floor((2*v+1)*(y1-y0)/192), v=0..95'},
        'gates': ['ccl_overflow', 'no_candidate', 'source_border'],
        'split': {'capture_group': 'resolved frame JSON parent directory',
                  'order': 'frame_id, then normalized absolute source JSON path',
                  'block_size': 20, 'block_id': 'zero-based index within capture_group // 20',
                  'block_roles': {'0_mod_5': 'validation', '2_mod_5': 'test', 'otherwise': 'train'},
                  'guard': 'At every adjacent nominal-role transition, 2 frames before and 2 frames after become guard',
                  'split_codes': SPLIT_CODE, 'random_split': False,
                  'training_exclusions': ['validation', 'test', 'guard', 'all gated records']},
        'manifest': 'Every approved source, including gates and guard; NPZ contains valid ROIs only',
        'reference_path': str(REFERENCE), 'reference_sha256': sha(REFERENCE),
        'prior_source_index': str(PRIOR), 'prior_source_index_sha256': sha(PRIOR),
        'preparation_script': str(Path(__file__).resolve()), 'preparation_script_sha256': sha(__file__),
        'limitations': [
            'Sources have been observed in prior development; block test is not independent new-session or new-board evaluation.',
            'No model fitting, accuracy assertion, RTL validation, synthesis, bitgen or hardware testing is performed here.',
            'CCL boundary gates are retained as REVIEW-source records and never fabricated as training images.',
        ],
    }


def enumerate_sources():
    rows = []
    counts = []
    seen = set()
    for root, truth, label in GROUPS:
        assert root.is_dir(), root
        paths = sorted((p for p in root.rglob('*.json') if not p.name.endswith('.annotation.json')), key=key)
        counts.append(len(paths))
        for path in paths:
            source_key = key(path)
            assert source_key not in seen, ('duplicate_source', path)
            seen.add(source_key)
            meta = read(path)
            rows.append({'source_json': str(path.resolve()), 'source_json_sha256': sha(path),
                         'frame_id': int(meta['frame_id']), 'capture_group': str(path.parent.resolve()),
                         'capture_session_id': meta.get('capture_session_id'),
                         'capture_batch_id': meta.get('capture_batch_id'),
                         'user_group_root': str(root), 'truth': truth, 'group': truth, 'label': label})
    assert counts == EXPECTED_COUNTS, ('source_count_changed', counts)
    assert len(rows) == 1494
    by_capture = defaultdict(list)
    for row in rows:
        by_capture[row['capture_group']].append(row)
    ordered = []
    transitions = []
    for capture_group in sorted(by_capture, key=key):
        group = sorted(by_capture[capture_group], key=lambda r: (r['frame_id'], key(r['source_json'])))
        for i, row in enumerate(group):
            block = i // 20
            role = 'validation' if block % 5 == 0 else 'test' if block % 5 == 2 else 'train'
            row.update({'capture_index': i, 'block_id': block, 'nominal_split': role, 'split': role})
        for i in range(1, len(group)):
            if group[i - 1]['nominal_split'] != group[i]['nominal_split']:
                indices = list(range(max(0, i - 2), min(len(group), i + 2)))
                for j in indices:
                    group[j]['split'] = 'guard'
                transitions.append({'capture_group': capture_group, 'transition_index': i,
                                    'left_role': group[i - 1]['nominal_split'],
                                    'right_role': group[i]['nominal_split'], 'guard_indices': indices})
        ordered.extend(group)
    for i, row in enumerate(ordered):
        row.update({'manifest_index': i, 'split_code': SPLIT_CODE[row['split']]})
    return ordered, transitions


def split_audit(rows, transitions):
    by_capture = defaultdict(list)
    for row in rows:
        by_capture[row['capture_group']].append(row)
    violations = []
    for group, records in by_capture.items():
        records.sort(key=lambda r: r['capture_index'])
        blocks = defaultdict(set)
        for row in records:
            blocks[row['block_id']].add(row['nominal_split'])
        assert all(len(roles) == 1 for roles in blocks.values())
        kept = [r for r in records if r['split'] != 'guard']
        for a, b in zip(kept, kept[1:]):
            if a['split'] != b['split'] and b['capture_index'] - a['capture_index'] < 5:
                violations.append([a['manifest_index'], b['manifest_index']])
    assert not violations, violations
    for t in transitions:
        group = by_capture[t['capture_group']]
        assert all(group[i]['split'] == 'guard' for i in t['guard_indices'])
    raw_splits = defaultdict(set)
    raw_rows = defaultdict(list)
    for row in rows:
        if 'raw_sha256' in row:
            raw_splits[row['raw_sha256']].add(row['split'])
            raw_rows[row['raw_sha256']].append(row['manifest_index'])
    duplicate_groups = [indices for indices in raw_rows.values() if len(indices) > 1]
    cross_split = [{'sha256': h, 'splits': sorted(v), 'manifest_indices': raw_rows[h]}
                   for h, v in raw_splits.items() if len(v) > 1]
    assert not cross_split, ('cross_split_raw_duplicates', cross_split)
    return {'status': 'PASS', 'capture_groups': len(by_capture),
            'physical_blocks': sum(len(set(r['block_id'] for r in group)) for group in by_capture.values()),
            'role_transitions': len(transitions), 'unguarded_adjacent_split_violations': violations,
            'duplicate_raw_groups': duplicate_groups, 'cross_split_raw_duplicates': cross_split,
            'guard_records': sum(r['split'] == 'guard' for r in rows)}


def verify_existing():
    checksums = read(OUT / 'SHA256.json')
    assert set(checksums) == {p.name for p in OUT.iterdir() if p.is_file() and p.name != 'SHA256.json'}
    assert all(sha(OUT / name) == digest for name, digest in checksums.items()), 'output hash mismatch'
    assert read(OUT / 'POLICY.json') == policy(), 'policy or script/reference/source-index changed'
    manifest = read(OUT / 'MANIFEST.json')['frames']
    selection, transitions = enumerate_sources()
    assert len(manifest) == len(selection) == 1494
    for row, frozen in zip(manifest, selection):
        assert all(row[k] == v for k, v in frozen.items()), row['source_json']
        assert sha(row['raw_path']) == row['raw_sha256'], row['raw_path']
    assert split_audit(manifest, transitions) == read(OUT / 'SPLIT_AUDIT.json')
    verify_npz(manifest)
    print(json.dumps({'existing': 'VERIFIED_WITHOUT_OVERWRITE', **read(OUT / 'SUMMARY.json')}, indent=2))


def verify_npz(manifest):
    valid = [r for r in manifest if r['gate'] == 'VALID']
    with np.load(OUT / 'DATASET.npz', allow_pickle=False) as data:
        assert data['images'].shape == (len(valid), 96, 96)
        assert data['images'].dtype == np.uint8 and data['labels'].dtype == np.uint8
        assert np.array_equal(data['metadata_index'], data['manifest_index'])
        assert data['manifest_index'].tolist() == [r['manifest_index'] for r in valid]
        assert data['labels'].tolist() == [r['label'] for r in valid]
        assert data['split'].tolist() == [r['split'] for r in valid]
        assert data['split_code'].tolist() == [r['split_code'] for r in valid]
        for image, row in zip(data['images'], valid):
            assert sha_bytes(image.tobytes()) == row['roi_sha256']


def main():
    assert ROOT.name == 'pcb_ccl_binary_user_retrain_20261102'
    assert OUT.resolve().parent == ROOT
    if OUT.exists() and any(OUT.iterdir()):
        verify_existing()
        return
    OUT.mkdir(parents=True, exist_ok=True)
    rows, transitions = enumerate_sources()
    save('POLICY.json', policy())
    save('SELECTION_BEFORE_EXTRACTION.json', {'records': rows, 'transitions': transitions})
    source_index = {key(r['source_json']): r for r in read(PRIOR)}
    assert set(source_index) == {key(r['source_json']) for r in rows}
    split_audit(rows, transitions)
    spec = importlib.util.spec_from_file_location('frozen_binary_dataset_reference', REFERENCE)
    reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reference)
    images = []
    valid_rows = []
    for n, row in enumerate(rows):
        frozen = source_index[key(row['source_json'])]
        assert row['source_json_sha256'] == frozen['source_json_sha256']
        assert row['truth'] == frozen['group'], ('truth_mismatch', row, frozen['group'])
        y, raw, raw_path = reference.load_y(row['source_json'])
        cc = reference.ccl(y)
        assert cc == frozen['ccl'], ('CCL_mismatch', row['source_json'])
        raw_hash, y_hash = sha_bytes(raw), sha_bytes(y.tobytes())
        assert raw_hash == frozen['raw_sha256'] and y_hash == frozen['source_y_sha256']
        gates = []
        if cc['overflow']:
            gates.append('ccl_overflow')
        if cc['bbox'] is None:
            gates.append('no_candidate')
        if cc['border_touch']:
            gates.append('source_border')
        row.update({'domain': frozen['domain'], 'raw_path': str(raw_path.resolve()),
                    'raw_sha256': raw_hash, 'raw_bytes': len(raw), 'source_y_sha256': y_hash,
                    'ccl': cc, 'ccl_box': cc['bbox'], 'roi_box': cc['bbox'],
                    'gate': 'VALID' if not gates else 'REVIEW', 'gate_reasons': gates,
                    'dataset_index': None, 'roi_sha256': None})
        if not gates:
            roi, _, _ = reference.sample(y, cc['bbox'])
            roi_hash = sha_bytes(roi.tobytes())
            assert roi_hash == frozen['results']['1.00']['roi_sha256']
            row.update({'dataset_index': len(images), 'roi_sha256': roi_hash})
            images.append(roi)
            valid_rows.append(row)
        if (n + 1) % 200 == 0:
            print(json.dumps({'verified_sources': n + 1, 'valid_rois': len(images)}), flush=True)
    save('MANIFEST.json', {'schema_version': 1, 'policy': 'POLICY.json', 'frames': rows})
    np.savez_compressed(OUT / 'DATASET.npz', images=np.stack(images).astype(np.uint8),
                        labels=np.array([r['label'] for r in valid_rows], np.uint8),
                        split=np.array([r['split'] for r in valid_rows], dtype='<U10'),
                        split_code=np.array([r['split_code'] for r in valid_rows], np.uint8),
                        metadata_index=np.array([r['manifest_index'] for r in valid_rows], np.int32),
                        manifest_index=np.array([r['manifest_index'] for r in valid_rows], np.int32))
    audit = split_audit(rows, transitions)
    save('SPLIT_AUDIT.json', audit)
    verify_npz(rows)
    groups = {}
    for group in sorted(set(r['capture_group'] for r in rows), key=key):
        subset = [r for r in rows if r['capture_group'] == group]
        groups[group] = {'sources': len(subset), 'truth': dict(Counter(r['truth'] for r in subset)),
                         'split': dict(Counter(r['split'] for r in subset)),
                         'valid_split': dict(Counter(r['split'] for r in subset if r['gate'] == 'VALID')),
                         'gates': dict(Counter(g for r in subset for g in r['gate_reasons']))}
    split_stats = {}
    for split in SPLIT_CODE:
        subset = [r for r in rows if r['split'] == split]
        split_stats[split] = {'sources': len(subset),
                              'valid': len([r for r in subset if r['gate'] == 'VALID']),
                              'valid_labels': dict(Counter(r['truth'] for r in subset if r['gate'] == 'VALID')),
                              'gates': dict(Counter(g for r in subset for g in r['gate_reasons']))}
    summary = {'status': 'PASS_DATA_PREPARATION', 'input_contract': 'CCL1.0 original box -> 96x96 unsigned Y8',
               'sources': len(rows), 'valid_rois': len(images), 'gated_sources': len(rows) - len(images),
               'source_labels': dict(Counter(r['truth'] for r in rows)),
               'splits': split_stats, 'capture_groups': groups, 'split_audit': audit,
               'npz_keys': ['images', 'labels', 'split', 'split_code', 'metadata_index', 'manifest_index'],
               'split_codes': SPLIT_CODE, 'npz_hashes_verified': True, 'training': 'NOT_RUN',
               'RTL': 'NOT_RUN', 'hardware': 'NOT_RUN', 'limitations': policy()['limitations']}
    save('SUMMARY.json', summary)
    save('SHA256.json', {p.name: sha(p) for p in sorted(OUT.iterdir()) if p.is_file()})
    print(json.dumps(summary, indent=2, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
