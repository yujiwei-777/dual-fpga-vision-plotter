"""Historical capture replay, not a measurement of the new bit on hardware.

Compare the former HDMI two-tap and new causal 2x2 on identical RGB input.
PNG inputs are decoded historical YUYV captures; no claim is made that their
unknown capture-bit identity matches this project's frozen baseline.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw


def average2(c, n, threshold):
    accept = np.max(np.abs(n - c), axis=2) <= threshold
    return np.where(accept[:, :, None], (c + n + 1) >> 1, c)


def old_h1(rgb):
    c = rgb.astype(np.int16)
    out = c.copy()
    out[:, 1:] = average2(c[:, 1:], c[:, :-1], 24)
    # The old SOF branch clears its one-pixel history for the next pixel.
    out[0, 1] = c[0, 1]
    return out.astype(np.uint8)


def spatial2x2(rgb, threshold=16):
    c = rgb.astype(np.int16)
    out = c.copy()
    out[:1, 1:] = average2(c[:1, 1:], c[:1, :-1], threshold)
    out[1:, :1] = average2(c[1:, :1], c[:-1, :1], threshold)
    center = c[1:, 1:]
    total = center.copy()
    for neighbor in (c[1:, :-1], c[:-1, 1:], c[:-1, :-1]):
        accept = np.max(np.abs(neighbor - center), axis=2) <= threshold
        total += np.where(accept[:, :, None], neighbor, center)
    out[1:, 1:] = (total + 2) >> 2
    return out.astype(np.uint8)


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--captures', type=Path, required=True)
    parser.add_argument('--first', type=int, default=8385)
    parser.add_argument('--last', type=int, default=8979)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    chosen = []
    for p in sorted(args.captures.glob('frame_*.json')):
        if '.annotation.' in p.name:
            continue
        d = json.loads(p.read_text(encoding='utf-8-sig'))
        if args.first <= d.get('frame_id', -1) <= args.last:
            counters = d.get('transport_counters', {})
            if counters.get('invalid_packets') != 0 or counters.get('frame_crc_errors') != 0:
                raise RuntimeError(f'Invalid capture: {p}')
            chosen.append((p, d))
    if len(chosen) < 2:
        raise RuntimeError('At least two valid captures required')
    # Explicit flat background ROI, excluding the PCB and its shadow.
    roi = (100, 20, 1100, 150)
    prior = {}; residual_sums = {}; residual_counts = {}; sources = []
    first_images = None
    for p, d in chosen:
        png = p.parent / d['png_file']
        if d.get('png_sha256', '').upper() != digest(png):
            raise RuntimeError(f'PNG hash mismatch: {png}')
        rgb = np.array(Image.open(png).convert('RGB'))
        outputs = {'source': rgb, 'old_h1_threshold24': old_h1(rgb),
                   'spatial2x2_threshold16': spatial2x2(rgb)}
        if first_images is None:
            first_images = outputs
        x0, y0, x1, y1 = roi
        for name, im in outputs.items():
            patch = im[y0:y1, x0:x1].astype(np.float64)
            y = (77 * patch[..., 0] + 150 * patch[..., 1] + 29 * patch[..., 2]) / 256
            if name in prior:
                # Adjacent-frame residual with global brightness change removed.
                delta = y - prior[name]
                delta -= delta.mean()
                residual_sums[name] = residual_sums.get(name, 0) + float((delta * delta).sum())
                residual_counts[name] = residual_counts.get(name, 0) + delta.size
            prior[name] = y
        sources.append({'metadata': str(p.resolve()), 'metadata_sha256': digest(p),
                        'png': str(png.resolve()), 'png_sha256': digest(png),
                        'frame_id': d['frame_id'], 'main_bit_sha256': d.get('main_bit_sha256')})
    rms = {name: float(np.sqrt(residual_sums[name] / residual_counts[name] / 2))
           for name in residual_sums}
    result = {'hardware_status': 'NOT_RUN', 'kind': 'historical_software_replay',
              'capture_identity_matches_current_baseline': False,
              'limitation': 'Historical decoded YUYV RGB replay; not the photographed failure or the new bit output. Does not prove all fine detail is preserved.',
              'frames': len(chosen), 'roi_xyxy': roi,
              'metric': 'RMS((Y[n]-Y[n-1])-mean(Y[n]-Y[n-1])) / sqrt(2)',
              'background_temporal_residual_rms': rms, 'sources': sources}
    (args.out / 'historical_replay.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    # Same pixels at 1:1 scale, no illustrative regeneration or smoothing.
    canvas = Image.new('RGB', (900, 246), (24, 24, 24))
    draw = ImageDraw.Draw(canvas)
    for i, (name, im) in enumerate(first_images.items()):
        draw.text((i * 300 + 8, 7), name, fill='white')
        crop = Image.fromarray(im).crop((50, 20, 350, 240))
        canvas.paste(crop, (i * 300, 26))
    canvas.save(args.out / 'historical_rgb_crop_comparison.png')
    print(json.dumps({'frames': len(chosen), 'rms': rms,
                      'limitation': result['limitation']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
