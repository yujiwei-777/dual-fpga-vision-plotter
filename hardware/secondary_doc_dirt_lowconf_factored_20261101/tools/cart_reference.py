"""CART reference model and deterministic streaming test vectors.

The optional denoise follows the production edge-preserving prefilter.
All differences are widened before arithmetic, including signed gradients.

The production CART definition used by the current reference is deliberately
small and integer-only:

* ``gray = (R>>2) + (G>>1) + (G>>4) + (B>>3)``;
* each output channel keeps its upper four bits (16 levels);
* the edge mask is the complete 3x3 Sobel ``abs(Gx) + abs(Gy)`` magnitude;
* the outer image border is copied/quantised and is never drawn black;
* the default edge threshold is 48.

``cartoon`` keeps the historical call shape (``rgb, threshold, dilate``),
while the explicit helpers below make the quantisation and Sobel stages easy
to compare with RTL.  ``quant_bits=5`` and an explicit threshold of 128 can
still be used to reproduce the earlier eight-level reference.
"""
from pathlib import Path
import argparse
import numpy as np


DEFAULT_CART_THRESHOLD = 48
DEFAULT_CART_QUANT_BITS = 4


def gray_formula(rgb):
    """Return the RTL-compatible integer gray image.

    ``rgb`` may be any array whose final dimension contains RGB channels.
    The calculation matches the fixed weighted sum in the HDL.
    """
    c = np.asarray(rgb, dtype=np.int32)
    if c.ndim < 1 or c.shape[-1] < 3:
        raise ValueError("rgb must have an RGB channel dimension")
    # Match the RTL shift/add implementation exactly.  The extra G>>4 term
    # is intentional: it keeps the fixed-point luma range and threshold
    # stable with the display pipeline's historical weighting.
    return ((c[..., 0] >> 2) + (c[..., 1] >> 1) +
            (c[..., 1] >> 4) + (c[..., 2] >> 3)).clip(0, 255).astype(np.uint8)


def quantize_rgb(rgb, quant_bits=DEFAULT_CART_QUANT_BITS):
    """Quantise RGB channels by clearing the requested number of low bits.

    ``quant_bits=4`` gives 16 levels/channel (the CART production setting),
    while ``quant_bits=5`` gives the legacy eight-level output.  Keeping this
    as a parameter lets old vector generators remain usable during RTL
    equivalence checks.
    """
    if not 0 <= int(quant_bits) <= 8:
        raise ValueError("quant_bits must be in the range 0..8")
    c = np.asarray(rgb, dtype=np.uint8)
    if quant_bits == 0:
        return c.copy()
    return (c & np.uint8(0xFF ^ ((1 << int(quant_bits)) - 1))).astype(np.uint8)


def sobel3x3(gray):
    """Compute a complete integer 3x3 Sobel magnitude.

    Edge pixels use replicated neighbours.  Returning the un-clipped
    ``abs(Gx)+abs(Gy)`` magnitude is useful because the RTL compares this
    value directly with a threshold before it emits a binary edge mask.
    """
    g = np.asarray(gray, dtype=np.int32)
    if g.ndim != 2:
        raise ValueError("gray must be a two-dimensional image")
    p = np.pad(g, ((1, 1), (1, 1)), mode="edge")
    gx = (
        -p[:-2, :-2] + p[:-2, 2:]
        - 2 * p[1:-1, :-2] + 2 * p[1:-1, 2:]
        - p[2:, :-2] + p[2:, 2:]
    )
    gy = (
        p[:-2, :-2] + 2 * p[:-2, 1:-1] + p[:-2, 2:]
        - p[2:, :-2] - 2 * p[2:, 1:-1] - p[2:, 2:]
    )
    return np.abs(gx) + np.abs(gy)


def denoise(rgb, strength=48):
    c = np.asarray(rgb, dtype=np.int32)
    prev = np.concatenate((c[:1], c[:-1]), axis=0)
    vertical = (prev + 3 * c + 2) // 4
    vertical[0] = c[0]
    cg = c.reshape(c.shape[0], -1, 4, 3)
    vg = vertical.reshape(cg.shape)
    smooth = np.empty_like(vg)
    smooth[:, :, 0] = (3*vg[:, :, 0] + vg[:, :, 1] + 2) // 4
    smooth[:, :, 3] = (3*vg[:, :, 3] + vg[:, :, 2] + 2) // 4
    for lane in (1, 2):
        smooth[:, :, lane] = (vg[:, :, lane-1] + 2*vg[:, :, lane] + vg[:, :, lane+1] + 2) // 4
    blend = cg + ((smooth-cg)*strength // 256)
    return np.where(np.abs(vg-cg) > 24, cg, blend).reshape(c.shape).astype(np.uint8)


def tone_map(rgb):
    """Match display_tone_96.v, channel by channel."""
    x = np.asarray(rgb, dtype=np.int32)
    y = np.empty_like(x)
    m = x < 32
    y[m] = x[m] + (x[m] >> 1)
    m2 = (x >= 32) & (x < 96)
    d = x[m2] - 32
    y[m2] = 48 + d + (d >> 3)
    m3 = (x >= 96) & (x < 192)
    d = x[m3] - 96
    y[m3] = 120 + d - (d >> 2)
    m4 = x >= 192
    d = x[m4] - 192
    y[m4] = 192 + d - ((d + 1) >> 2)
    return np.clip(y, 0, 255).astype(np.uint8)


def _stream_group_dilate(edge):
    """Apply the historical four-pixel-group edge expansion."""
    h, w = edge.shape
    expanded = np.zeros_like(edge)
    groups = (w + 3) // 4
    for y in range(h):
        for g in range(groups):
            x0 = 4 * g
            x1 = min(x0 + 4, w)
            own = edge[y, x0:x1].copy()
            m = own.copy()
            if own.size:
                m[:-1] |= own[1:]
                m[1:] |= own[:-1]
            if y != 0 and y != h - 1:
                m |= edge[y - 1, x0:x1]
            if g != 0 and x0 < w and edge[y, x0 - 1]:
                m[0] = True
            if g == 0 and m.size:
                m[0] = False
            if g == groups - 1 and m.size:
                m[-1] = False
            expanded[y, x0:x1] = m
    return expanded


def cartoon_full3x3(rgb, threshold=DEFAULT_CART_THRESHOLD,
                     dilate=False, quant_bits=DEFAULT_CART_QUANT_BITS):
    """Reference for the complete 3x3 Sobel CART implementation."""
    c = np.asarray(rgb, dtype=np.uint8)
    if c.ndim != 3 or c.shape[-1] < 3:
        raise ValueError("rgb must have shape (height, width, 3)")
    h, w, _ = c.shape
    magnitude = sobel3x3(gray_formula(c))
    edge = magnitude >= int(threshold)
    if h and w:
        edge[[0, -1], :] = False
        edge[:, [0, -1]] = False
    if dilate:
        edge = _stream_group_dilate(edge)
    out = quantize_rgb(c, quant_bits=quant_bits)
    out[edge] = 0
    return out


def cartoon(rgb, threshold=DEFAULT_CART_THRESHOLD, dilate=False,
            quant_bits=DEFAULT_CART_QUANT_BITS, full_sobel=True):
    """CART reference with the historical positional API preserved.

    ``full_sobel=True`` selects the complete 3x3 model.  Passing
    ``full_sobel=False`` retains the former causal one-group implementation
    for old vector comparisons.  The old eight-level behaviour is reproduced
    with ``quant_bits=5`` and an explicit threshold of 128.
    """
    if full_sobel:
        return cartoon_full3x3(rgb, threshold=threshold, dilate=dilate,
                               quant_bits=quant_bits)
    c = np.asarray(rgb, dtype=np.int32)
    h, w, _ = c.shape
    luma = gray_formula(c)
    out = quantize_rgb(c, quant_bits=quant_bits)
    edge = np.zeros((h, w), dtype=bool)
    for y in range(h):
        for x in range(w):
            top = luma[y, x] if y == 0 else luma[y-1, x]
            left = luma[y, x] if x == 0 else luma[y, x-1]
            # The hardware sees four lanes at a time.  It can use the next
            # lane within a group, while the fourth lane uses a replicated
            # right edge until the following group is accepted.
            if (x % 4) == 3:
                right = luma[y, x]
            else:
                right = luma[y, x+1] if x+1 < w else luma[y, x]
            mag = abs(int(right)-int(left)) + abs(int(luma[y, x])-int(top))
            # Match the hardware group boundary replication.
            # The no-stall hardware path is causal: it has the previous row
            # and current group, but cannot pause the camera to synthesize a
            # bottom row.  Match its exact boundary behaviour here: the top
            # row and leftmost pixel stay quantised, while the last row/right
            # edge use the available replicated neighbours.
            if x != 0 and y != 0 and mag >= threshold:
                edge[y, x] = True
    if dilate:
        edge = _stream_group_dilate(edge)
    out[edge] = 0
    return out


def vectors(out, width=32, height=9, count=10, prefilter=False, image=None,
            threshold=DEFAULT_CART_THRESHOLD, dilate=False, tone=False,
            quant_bits=DEFAULT_CART_QUANT_BITS, full_sobel=True):
    out.mkdir(parents=True, exist_ok=True)
    yy, xx = np.indices((height, width))
    rng = np.random.default_rng(71)
    modes = ([18]*6 + [0, 18, 0, 18])[:count]
    if count > 10:
        raise ValueError('at most 10 deterministic patterns')
    with (out/'cart_input.mem').open('w') as src, (out/'cart_expected.mem').open('w') as dst:
        for f, mode in enumerate(modes):
            if image is not None and f == 0:
                from PIL import Image
                a = np.array(Image.open(image).convert('RGB').resize((width, height)))
            elif f == 0:
                a = np.full((height, width, 3), (91, 137, 207), dtype=np.uint8)
            elif f in (1, 2, 3, 5):
                mask = {1:xx>=width//2-3, 2:yy>=height//2,
                        3:xx>=yy*3, 5:(xx==width//2-1)&(yy==height//2)}[f]
                a = np.repeat((mask*255).astype(np.uint8)[:, :, None], 3, axis=2)
            elif f == 4:
                a = np.stack((xx*8, yy*29, (xx+yy)*7), axis=2).astype(np.uint8)
            else:
                a = rng.integers(0, 256, (height, width, 3), dtype=np.uint8)
            display = tone_map(a) if tone and mode in (0, 18) else a
            result = cartoon(denoise(display) if prefilter else display,
                             threshold=threshold, dilate=dilate,
                             quant_bits=quant_bits, full_sobel=full_sobel) if mode == 18 else display
            for group in a.reshape(-1, 12):
                src.write(group.tobytes().hex()+'\n')
            for group in result.reshape(-1, 12):
                dst.write(group.tobytes().hex()+'\n')
            if image is not None and f == 0:
                from PIL import Image
                Image.fromarray(np.concatenate((a, result), axis=1)).save(out/'cart_preview.png')
    (out/'cart_modes.mem').write_text(''.join(f'{m:02x}\n' for m in modes), encoding='utf-8')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('output', type=Path)
    p.add_argument('--width', type=int, default=32)
    p.add_argument('--height', type=int, default=9)
    p.add_argument('--count', type=int, default=10)
    p.add_argument('--denoise', action='store_true')
    p.add_argument('--image', type=Path)
    p.add_argument('--threshold', type=int, default=DEFAULT_CART_THRESHOLD)
    p.add_argument('--dilate', action='store_true')
    p.add_argument('--tone', action='store_true')
    p.add_argument('--quant-bits', type=int, default=DEFAULT_CART_QUANT_BITS,
                   help='number of low colour bits cleared (4 = 16 levels)')
    p.add_argument('--legacy-streaming', action='store_true',
                   help='use the former causal group reference instead of full 3x3 Sobel')
    a = p.parse_args()
    vectors(a.output, a.width, a.height, a.count, a.denoise, a.image,
            a.threshold, a.dilate, a.tone, a.quant_bits, not a.legacy_streaming)
