"""Exact reference for the CCL -> 1.2 ROI -> restored binary CNN adapter.

Independent crop/mapping arithmetic; no learned reference or BAD fitting.
Use --self-test for arithmetic checks, --source-y/--box for optional replay.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
WEIGHT_SHA = '9B844CB0B0844F8A72E59192B4F04D3C192B6C1A501DA1F3376CE6BF5354DDE6'
BIAS_SHA = '45FAC7544E47F2CD73A5571A6136CB57A82CADD1B130057C8FCB0BC647E51232'


def expand_box(box, source_width=1280, source_height=720):
    """Source pixel half-open x0,y0,x1,y1; retain original for publication."""
    x0, y0, x1, y1 = map(int, box)
    if x0 <= 0 or y0 <= 0 or x1 >= source_width or y1 >= source_height or x1 <= x0 or y1 <= y0:
        return {'valid': False, 'error': 0x0202, 'box': [x0, y0, x1, y1]}
    width = (6 * (x1 - x0) + 4) // 5
    height = (6 * (y1 - y0) + 4) // 5
    left = (x0 + x1 - width) // 2
    top = (y0 + y1 - height) // 2
    crop = [left, top, left + width, top + height]
    if left < 0 or top < 0 or crop[2] > source_width or crop[3] > source_height:
        return {'valid': False, 'error': 0x0203, 'box': [x0, y0, x1, y1], 'crop': crop}
    return {'valid': True, 'error': 0, 'box': [x0, y0, x1, y1], 'crop': crop}


def sample_axes(crop):
    left, top, right, bottom = map(int, crop)
    index = np.arange(96, dtype=np.int64)
    return (left + ((2 * index + 1) * (right - left)) // 192,
            top + ((2 * index + 1) * (bottom - top)) // 192)


def sample_roi(source_y, box):
    result = expand_box(box, source_y.shape[1], source_y.shape[0])
    if not result['valid']:
        return None, result
    sx, sy = sample_axes(result['crop'])
    return source_y[sy[:, None], sx[None, :]].copy(), result


def serial_axis(origin, extent):
    """Cycle-independent mirror of RTL's repeated subtract-192 accumulator."""
    out, cursor, remainder = [], int(origin), int(extent)
    for _ in range(96):
        while remainder >= 192:
            remainder -= 192
            cursor += 1
        out.append(cursor)
        remainder += 2 * int(extent)
    return np.array(out, dtype=np.int64)


def read_signed_mem(path, bits):
    values = []
    for token in Path(path).read_text().split():
        value = int(token, 16)
        if value >= (1 << (bits - 1)):
            value -= 1 << bits
        values.append(value)
    return np.array(values, dtype=np.int64)


def convolution(source, weight, bias, shift=7):
    """NCHW-free C,H,W -> C,H/2,W/2; full precision then exact RTL shift."""
    channels, height, width = source.shape
    padded = np.pad(source.astype(np.int64), ((0, 0), (1, 1), (1, 1)))
    output = np.broadcast_to(bias[:, None, None], (len(bias), height // 2, width // 2)).copy()
    for ky in range(3):
        for kx in range(3):
            pixels = padded[:, ky:ky + height:2, kx:kx + width:2]
            output += np.einsum('oc,chw->ohw', weight[:, :, ky, kx], pixels)
    return np.clip(output >> shift, 0, 32767).astype(np.int64)


def evaluate_roi(roi, model_dir=None):
    model_dir = Path(model_dir or ROOT / 'model/experiments/conv4_4')
    wp, bp = model_dir / 'weights.mem', model_dir / 'biases.mem'
    hashes = [hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in (wp, bp)]
    assert hashes == [WEIGHT_SHA, BIAS_SHA], 'Binary model differs from frozen contract'
    weights, biases = read_signed_mem(wp, 8), read_signed_mem(bp, 32)
    assert weights.size == 308 and biases.size == 10
    assert roi.shape == (96, 96) and roi.dtype == np.uint8
    c1 = convolution(roi[None].astype(np.int64), weights[:36].reshape(4, 1, 3, 3), biases[:4])
    c2 = convolution(c1, weights[36:180].reshape(4, 4, 3, 3), biases[4:8])
    # CHW flatten after 6x6 regional sum>>5. The actual core passes int16 pool
    # values to its MAC; preserve that cast rather than assuming no overflow.
    pooled = (c2.reshape(4, 4, 6, 4, 6).sum(axis=(2, 4)) >> 5)
    operand = pooled.astype(np.int16).astype(np.int64).reshape(64)
    head_acc = biases[8:10] + weights[180:].reshape(2, 64) @ operand
    logits = head_acc >> 8
    # RTL stores signed 20-bit head values. Current frozen coefficients are
    # within their proved bounds; retain an explicit wrap for full equivalence.
    logits = ((logits + (1 << 19)) % (1 << 20)) - (1 << 19)
    winner = int(logits[1] > logits[0])
    margin = int(min(65535, max(0, abs(int(logits[1]) - int(logits[0])))))
    score = int(np.clip(logits[winner], 0, 255))
    status = 2 if margin < 32 else winner
    result = {'class_id': winner, 'status': status, 'margin': margin, 'classifier_score': score,
              'detail_score': min(margin, 4095), 'logits': logits.tolist(),
              'score_semantics': 'legacy best-logit saturation, not calibrated probability',
              'c1_sha256': hashlib.sha256(c1.astype('<i2').tobytes()).hexdigest().upper(),
              'c2_sha256': hashlib.sha256(c2.astype('<i2').tobytes()).hexdigest().upper()}
    return result, c1, c2


def self_test():
    axis_cases = 0
    for extent in range(1, 1537):
        expected = 17 + ((2 * np.arange(96) + 1) * extent) // 192
        assert np.array_equal(expected, serial_axis(17, extent))
        # Independent serial divide-by-five used by expansion controller.
        actual, remainder = extent, extent + 4
        while remainder >= 5:
            actual += 1
            remainder -= 5
        assert actual == (6 * extent + 4) // 5
        axis_cases += 1
    rng = np.random.default_rng(120)
    box_cases = 0
    for _ in range(10000):
        xs, ys = sorted(rng.integers(1, 160, size=2)), sorted(rng.integers(1, 90, size=2))
        if xs[0] == xs[1] or ys[0] == ys[1]:
            continue
        box = [int(xs[0] * 8), int(ys[0] * 8), int(xs[1] * 8), int(ys[1] * 8)]
        item = expand_box(box)
        if item['valid']:
            sx, sy = sample_axes(item['crop'])
            assert np.array_equal(sx, serial_axis(item['crop'][0], item['crop'][2] - item['crop'][0]))
            assert np.array_equal(sy, serial_axis(item['crop'][1], item['crop'][3] - item['crop'][1]))
            assert sx.min() >= 0 and sx.max() < 1280 and sy.min() >= 0 and sy.max() < 720
        box_cases += 1
    assert expand_box([0, 8, 80, 88])['error'] == 0x0202
    assert expand_box([8, 8, 1200, 700])['error'] == 0x0203
    assert expand_box([400, 240, 800, 480])['crop'] == [360, 216, 840, 504]
    return {'status': 'REFERENCE_ARITHMETIC_PASS', 'axis_cases': axis_cases,
            'random_boxes': box_cases, 'rtl_parity': 'NOT_RUN_BY_THIS_TEST'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--source-y', type=Path)
    parser.add_argument('--box', type=int, nargs=4)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), indent=2))
    if args.source_y:
        assert args.box is not None
        source = np.load(args.source_y) if args.source_y.suffix == '.npy' else np.fromfile(args.source_y, np.uint8).reshape(720, 1280)
        roi, result = sample_roi(source, args.box)
        if roi is not None:
            result['inference'], c1, c2 = evaluate_roi(roi)
            if args.output:
                args.output.mkdir(parents=True, exist_ok=True)
                np.savez_compressed(args.output / 'INTEGER_STAGES.npz', roi=roi, c1=c1, c2=c2)
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            (args.output / 'REFERENCE.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
