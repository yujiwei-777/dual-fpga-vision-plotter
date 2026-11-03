"""Frozen pose7 reference and RTL vectors; no fitting and no training writes.

Run with python -B tools/pose7_export_reference.py.  Only reports/pose7 is written.
This standalone reference needs NumPy; it does not import training code.
"""
from __future__ import annotations
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import sys
import zlib
import numpy as np

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL = ROOT / 'model/pose7_96x96'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def save_json(path, obj):
    def convert(v):
        if isinstance(v, np.ndarray): return v.tolist()
        if isinstance(v, np.generic): return v.item()
        raise TypeError(type(v).__name__)
    Path(path).write_text(json.dumps(obj, indent=2, ensure_ascii=False,
                                   default=convert, allow_nan=False) + '\n', encoding='utf-8')


def mem(path, values, bits=8):
    mask = (1 << bits) - 1
    Path(path).write_text(''.join(f'{int(v)&mask:0{(bits+3)//4}x}\n'
                                for v in np.asarray(values).ravel()), encoding='ascii')


def load_model(path):
    path = Path(path)
    # Original manifest keys are relative to the training experiment root.
    # A copied model is verified by the basename, retaining exact file bytes.
    for relative, expected in read_json(path / 'FROZEN_SHA256.json').items():
        basename = relative.replace('\\', '/').split('/')[-1]
        assert digest(path / basename) == expected, basename
    def values(name, dtype):
        return np.array([int(x, 16) for x in (path / name).read_text().split()], dtype=dtype)
    weights = values('weights.mem', np.uint8).view(np.int8)
    biases = values('biases.mem', np.uint32).view(np.int32)
    model = {'meta': read_json(path / 'MODEL.json'),
             'c1_weights': weights[:36].reshape(4, 1, 3, 3),
             'c2_weights': weights[36:].reshape(4, 4, 3, 3),
             'c1_biases': biases[:4], 'c2_biases': biases[4:]}
    for name in ['centre', 'tolerance']:
        model[name] = values(f'feature_{name}.mem', np.uint8).reshape(4, 24, 24)
    model['reference'] = values('orientation_reference.mem', np.uint8).reshape(16, 32)
    assert model['meta']['input_width'] == model['meta']['input_height'] == 96
    assert model['meta']['pass_threshold'] == 106 and model['meta']['fail_threshold'] == 205
    return model


def ccl_gray(y):
    """Independent raster flood fill, same four-connectivity and tie policy."""
    foreground = np.asarray(y[4::8, 4::8] <= 112)
    left = np.zeros_like(foreground); left[:, 1:] = foreground[:, :-1]
    up = np.zeros_like(foreground); up[1:] = foreground[:-1]
    provisional = int((foreground & ~left & ~up).sum())
    result = {'provisional_labels': provisional, 'overflow': provisional > 510,
              'count': 0, 'bbox': None, 'border_touch': False}
    if provisional > 510: return result
    visited = np.zeros_like(foreground)
    candidates = []
    for sy in range(90):
        for sx in range(160):
            if not foreground[sy, sx] or visited[sy, sx]: continue
            queue = deque([(sx, sy)]); visited[sy, sx] = True
            area = 0; x0 = x1 = sx; y0 = y1 = sy
            while queue:
                x, yy = queue.popleft(); area += 1
                x0 = min(x0, x); x1 = max(x1, x)
                y0 = min(y0, yy); y1 = max(y1, yy)
                for xx, yyy in [(x-1, yy), (x+1, yy), (x, yy-1), (x, yy+1)]:
                    if 0 <= xx < 160 and 0 <= yyy < 90 and foreground[yyy, xx] and not visited[yyy, xx]:
                        visited[yyy, xx] = True; queue.append((xx, yyy))
            width, height = x1-x0+1, y1-y0+1
            if area >= 64 and width >= 8 and height >= 4 and width <= 5*height and height <= 5*width and area*12 >= width*height:
                candidates.append((area, sy*160+sx, [8*x0, 8*y0, 8*(x1+1), 8*(y1+1)]))
    candidates.sort(key=lambda c: (-c[0], c[1]))
    result['count'] = min(len(candidates), 4)
    if candidates:
        result['bbox'] = candidates[0][2]
        x0, y0, x1, y1 = result['bbox']
        result['border_touch'] = x0 == 0 or y0 == 0 or x1 == 1280 or y1 == 720
    return result


def sample_roi(y, box):
    x0, y0, x1, y1 = box
    xx = x0 + ((2*np.arange(96, dtype=np.int64)+1)*(x1-x0))//192
    yy = y0 + ((2*np.arange(96, dtype=np.int64)+1)*(y1-y0))//192
    return y[yy[:, None], xx[None, :]].copy(), xx, yy


def orientation(roi, reference):
    xs = 3*np.arange(32)+1; ys = 6*np.arange(16)+3
    thumbs = np.stack([roi[ys[:, None], xs[None, :]],
                       roi[(95-ys)[:, None], (95-xs)[None, :]]]).astype(np.int32)
    means = (thumbs.sum((1, 2))+256) >> 9
    reference_mean = (int(reference.astype(np.int32).sum())+256) >> 9
    ref = reference.astype(np.int32)-reference_mean
    costs = np.abs(thumbs-means[:, None, None]-ref).sum((1, 2), dtype=np.int32)
    return bool(costs[1] < costs[0]), thumbs.astype(np.uint8), means, costs, reference_mean


def conv(x, weights, biases):
    ic, height, width = x.shape
    oh, ow = (height+1)//2, (width+1)//2
    padded = np.pad(x.astype(np.int64), ((0, 0), (1, 1), (1, 1)))
    acc = np.broadcast_to(biases[:, None, None].astype(np.int64), (4, oh, ow)).copy()
    for ci in range(ic):
        for ky in range(3):
            for kx in range(3):
                v = padded[ci, ky:ky+2*oh:2, kx:kx+2*ow:2]
                acc += v[None]*weights[:, ci, ky, kx, None, None].astype(np.int64)
    output = np.clip((acc+64) >> 7, 0, 255).astype(np.uint8)
    # Independent scalar spot checks cover all output channels, padding sides,
    # and interior points, rather than duplicating the slicing calculation.
    for oc in range(4):
        for oy, ox in [(0, 0), (0, ow-1), (oh-1, 0), (oh-1, ow-1), (oh//2, ow//2), (1, 1)]:
            value = int(biases[oc])
            for ci in range(ic):
                for ky in range(3):
                    for kx in range(3):
                        iy, ix = 2*oy+ky-1, 2*ox+kx-1
                        if 0 <= iy < height and 0 <= ix < width:
                            value += int(x[ci, iy, ix])*int(weights[oc, ci, ky, kx])
            assert value == acc[oc, oy, ox]
            assert min(255, max(0, (value+64) >> 7)) == output[oc, oy, ox]
    return output, acc


def score_features(features, model):
    residual = np.maximum(np.abs(features.astype(np.int32)-model['centre'].astype(np.int32))-
                          model['tolerance'].astype(np.int32), 0).max(axis=0)
    windows = residual[:-1, :-1]+residual[1:, :-1]+residual[:-1, 1:]+residual[1:, 1:]
    best_score = -1; best_peak = None
    for y in range(23):
        for x in range(23):
            scalar = sum(int(residual[yy, xx]) for yy in [y, y+1] for xx in [x, x+1])
            assert scalar == windows[y, x]
            if scalar > best_score: best_score, best_peak = scalar, [x, y]
    return best_score, best_peak, residual.astype(np.uint8), windows.astype(np.uint16)


def decision(score):
    return 'PASS' if score <= 106 else 'FAIL' if score >= 205 else 'REVIEW'


def evaluate_roi(roi, model):
    flip, thumbs, means, costs, reference_mean = orientation(roi, model['reference'])
    chosen = roi[::-1, ::-1].copy() if flip else roi.copy()
    c1, a1 = conv(chosen[None].astype(np.int16)-128, model['c1_weights'], model['c1_biases'])
    c2, a2 = conv(c1, model['c2_weights'], model['c2_biases'])
    score, peak, residual, windows = score_features(c2, model)
    return {'flip180': flip, 'thumb_means': means, 'orientation_costs': costs,
            'reference_mean': reference_mean, 'score': score, 'peak_xy': peak,
            'decision': decision(score)}, {'roi': roi, 'oriented_roi': chosen,
            'thumb0': thumbs[0], 'thumb180': thumbs[1], 'conv1': c1, 'conv2': c2,
            'conv1_acc': a1, 'conv2_acc': a2, 'residual': residual, 'windows': windows}


def load_y(meta_path):
    meta_path = Path(meta_path); meta = read_json(meta_path)
    assert (meta['width'], meta['height'], meta['pixel_format']) == (1280, 720, 'YUYV')
    raw = (meta_path.parent/meta['raw_file']).read_bytes()
    assert len(raw) == 1280*720*2
    assert hashlib.sha256(raw).hexdigest().lower() == meta['raw_sha256'].lower()
    assert f'{zlib.crc32(raw)&0xffffffff:08x}' == meta['crc32'].lower()
    assert all(meta['transport_counters'].get(k, 0) == 0 for k in ['invalid_packets', 'packet_crc_errors', 'frame_crc_errors'])
    return np.frombuffer(raw, np.uint8).reshape(720, 1280, 2)[:, :, 0].copy()


def threshold_fixture(target, model):
    f = model['centre'].copy(); remaining = target
    for y, x in [(0, 0), (0, 1), (1, 0), (1, 1)]:
        c = model['centre'][:, y, x].astype(np.int32)
        t = model['tolerance'][:, y, x].astype(np.int32)
        room = np.maximum(c, 255-c)-t
        channel = int(room.argmax()); value = min(remaining, int(room[channel]))
        if value > 0:
            if 255-c[channel] >= c[channel]: f[channel, y, x] = c[channel]+t[channel]+value
            else: f[channel, y, x] = c[channel]-t[channel]-value
            remaining -= value
    assert remaining == 0
    score, peak, residual, windows = score_features(f, model)
    assert score == target
    return f, residual, windows, peak


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, default=DEFAULT_MODEL)
    parser.add_argument('--out', type=Path, default=ROOT/'reports/pose7/vectors')
    parser.add_argument('--frames', action='store_true', help='also export three source Y frames and CCL/ROI contract')
    parser.add_argument('--all-frames', action='store_true', help='independently replay every frozen EVALUATION frame without exporting full pixels')
    args = parser.parse_args()
    assert args.out.resolve().is_relative_to((ROOT/'reports/pose7').resolve())
    args.out.mkdir(parents=True, exist_ok=True)
    model = load_model(args.model)
    golden = np.load(args.model/'INTEGER_GOLDEN_VECTORS.npz')
    cases = [(name, image) for name, image in zip(['golden_good', 'golden_missing_pad', 'golden_missing_corner'], golden['source_y_rois'])]
    cases += [(name+'_180', image[::-1, ::-1].copy()) for name, image in cases[:]]
    # Actual orientation samples have different Y phases. This trap deliberately
    # makes reversing an already sampled thumbnail give a wrong direction.
    phase = np.full((96, 96), 128, np.uint8)
    xx = 3*np.arange(32)+1; yy = 6*np.arange(16)+3
    phase[yy[:, None], xx[None, :]] = model['reference'][::-1, ::-1]
    phase[(95-yy)[:, None], (95-xx)[None, :]] = 255-model['reference']
    phase_flip, phase_thumbs, phase_means, phase_costs, reference_mean = orientation(phase, model['reference'])
    naive180 = phase_thumbs[0, ::-1, ::-1].astype(np.int32)-int(phase_means[0])
    naive_cost180 = int(np.abs(naive180-(model['reference'].astype(np.int32)-reference_mean)).sum())
    assert phase_flip is False and naive_cost180 < int(phase_costs[0])
    save_json(args.out/'THUMB_PHASE_TRAP.json', {'actual_flip180': phase_flip,
        'actual_costs': phase_costs, 'incorrect_reversed_thumbnail_cost180': naive_cost180,
        'incorrect_reversed_thumbnail_flip180': True})
    cases += [('thumb_phase', phase), ('all_zero', np.zeros((96, 96), np.uint8)),
              ('all_255', np.full((96, 96), 255, np.uint8)),
              ('ramp', ((np.arange(96)[:, None]*3+np.arange(96)[None, :]*5)&255).astype(np.uint8))]
    edge = np.full((96, 96), 128, np.uint8); edge[0, 0] = 0; edge[-1, -1] = 255
    cases.append(('edge_impulse', edge))
    records = []
    for index, (name, roi) in enumerate(cases):
        folder = args.out/name; folder.mkdir(exist_ok=True)
        meta, arrays = evaluate_roi(roi, model)
        for key, values in arrays.items():
            mem(folder/(key+'.mem'), values, 32 if key.endswith('_acc') else 16 if key == 'windows' else 8)
        if index < 3:
            expected = golden['features180'][index] if meta['flip180'] else golden['features0'][index]
            assert np.array_equal(expected, arrays['conv2']), name
            assert int(golden['scores'][index]) == meta['score']
            assert bool(golden['selected_flip180'][index]) == meta['flip180']
            assert golden['peaks'][index].tolist() == meta['peak_xy']
        save_json(folder/'EXPECTED.json', meta)
        records.append({'name': name, **meta})
    threshold_records = []
    for target in [0, 106, 107, 204, 205]:
        folder = args.out/f'head_score_{target}'; folder.mkdir(exist_ok=True)
        f, p, w, peak = threshold_fixture(target, model)
        mem(folder/'conv2.mem', f); mem(folder/'residual.mem', p); mem(folder/'windows.mem', w, 16)
        record = {'score': target, 'peak_xy': peak, 'decision': decision(target)}
        save_json(folder/'EXPECTED.json', record); threshold_records.append(record)
    frames = []
    if args.frames:
        rows = read_json(args.model/'EVALUATION_FRAMES.json')
        selected = [next(r for r in rows if r['group'] == g and (g != 'GOOD' or r['role'] == 'test'))
                    for g in ['GOOD', 'MISSING_PAD', 'MISSING_CORNER']]
        for index, row in enumerate(selected):
            y = load_y(row['source_json']); candidate = ccl_gray(y)
            assert candidate['bbox'] == row['bbox'] and candidate['border_touch'] == row['border_touch']
            roi, xs, ys = sample_roi(y, candidate['bbox'])
            assert np.array_equal(roi, golden['source_y_rois'][index])
            folder = args.out/cases[index][0]
            mem(folder/'source_y.mem', y); mem(folder/'sample_x.mem', xs, 16); mem(folder/'sample_y.mem', ys, 16)
            frame = {'name': cases[index][0], 'source_json': row['source_json'], 'source_json_sha256': digest(row['source_json']),
                     **candidate, 'source_Y_SHA256': hashlib.sha256(y.tobytes()).hexdigest().upper()}
            save_json(folder/'FRAME.json', frame); frames.append(frame)
        white = np.full((720, 1280), 255, np.uint8)
        overflow = white.copy(); overflow[4::16, 4::16] = 0
        quality = {}
        for name, y in [('blank', white), ('full_dark_border', np.zeros_like(white)), ('overflow', overflow)]:
            q = ccl_gray(y)
            assert q['overflow'] or q['count'] == 0 or q['border_touch']
            quality[name] = {**q, 'decision': 'REVIEW', 'output_box_valid': False}
        save_json(args.out/'QUALITY_EXPECTED.json', quality)
    if args.all_frames:
        all_frames = []
        for index, row in enumerate(read_json(args.model/'EVALUATION_FRAMES.json')):
            assert digest(row['source_json']) == row['source_json_sha256']
            y = load_y(row['source_json']); candidate = ccl_gray(y)
            assert candidate['bbox'] == row['bbox'] and candidate['border_touch'] == row['border_touch']
            roi, _, _ = sample_roi(y, candidate['bbox'])
            meta, _ = evaluate_roi(roi, model)
            result = 'REVIEW' if candidate['border_touch'] else meta['decision']
            assert meta['score'] == row['score'] and result == row['decision']
            assert meta['peak_xy'] == row['peak_xy'] and meta['flip180'] == row['flip180']
            all_frames.append({'frame_id': row['frame_id'], 'group': row['group'],
                               'bbox': candidate['bbox'], 'border_touch': candidate['border_touch'], **meta,
                               'quality_gated_decision': result})
            if (index+1) % 100 == 0: print(f'ALL_FRAME_REPLAY {index+1}', flush=True)
        save_json(args.out/'ALL_FRAME_REFERENCE_PARITY.json', {
            'status': 'PASS', 'frames': len(all_frames), 'CCL_bbox_ROI_orientation_conv_score_status': 'EXACT',
            'independent_capture_validation': 'NOT_RUN', 'RTL': 'NOT_RUN', 'frames_detail': all_frames})
    save_json(args.out/'INDEX.json', {'model_sha256': digest(args.model/'MODEL.json'),
        'model_frozen_manifest': 'PASS', 'vectors': records, 'threshold_vectors': threshold_records,
        'source_frames': frames, 'RTL': 'NOT_RUN', 'hardware': 'NOT_RUN',
        'note': 'Development/golden replay and synthetic diagnostics, not independent quality validation.'})
    activation_acc = [-2147483648, -65, -64, -63, -1, 0, 63, 64, 65,
                      127, 128, 255*128-65, 255*128-64, 255*128+63, 255*128+64,
                      2147483583]
    # +64 must be widened before adding if using full int32 input range.
    save_json(args.out/'ACTIVATION_EXPECTED.json', [
        {'acc': value, 'rounded_shift': (value+64) >> 7,
         'activation': min(255, max(0, (value+64) >> 7))} for value in activation_acc])
    hashes = {str(p.relative_to(args.out)): digest(p) for p in sorted(args.out.rglob('*')) if p.is_file() and p.name != 'SHA256.json'}
    save_json(args.out/'SHA256.json', hashes)
    print(json.dumps({'status': 'PASS', 'ROI_cases': len(cases), 'head_threshold_cases': len(threshold_records),
                      'source_frames': len(frames), 'output': str(args.out)}, indent=2))


if __name__ == '__main__':
    main()
