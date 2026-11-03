"""Build source-neighbour integer golden vectors and noise/edge evidence."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import random
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MODEL = ROOT / "model/display_spatial_reference.py"
spec = importlib.util.spec_from_file_location("display_spatial_reference", MODEL)
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def gray(v):
    return (v << 16) | (v << 8) | v


def input_word(data=0, rst=1, vs=0, hs=0, de=0, user=0, last=0):
    return (rst << 31) | (vs << 30) | (hs << 29) | (de << 28) | (user << 27) | (last << 26) | data


def output_word(data=0, vs=0, hs=0, de=0, user=0, last=0):
    return (vs << 28) | (hs << 27) | (de << 26) | (user << 25) | (last << 24) | data


def frame_vectors(image, seed, *, gaps=True, sof=True, isolated_sof=False, blank=3):
    rng = random.Random(seed)
    if isolated_sof:
        yield input_word(vs=1, user=1)
        yield input_word(hs=1)
    for y, row in enumerate(image):
        for x, value in enumerate(row):
            if gaps and rng.randrange(9) == 0:
                yield input_word(data=rng.randrange(1 << 24), hs=rng.randrange(2))
                if rng.randrange(3) == 0:
                    yield input_word(vs=rng.randrange(2))
            yield input_word(value, de=1, user=int(sof and not isolated_sof and y == 0 and x == 0),
                             last=int(x == len(row)-1), vs=int(y == 0), hs=int(x == 0))
        for _ in range(blank):
            yield input_word(data=rng.randrange(1 << 24), hs=1)


def emit(name, width, height, vectors, tags):
    folder = HERE / name
    folder.mkdir(exist_ok=True)
    oracle = ref.StreamReference(width, height)
    pending, source_pending = 0, 0
    count, pixels = 0, 0
    with (folder / "stim.mem").open("w") as fs, (folder / "expected.mem").open("w") as fe, (folder / "source.mem").open("w") as fb:
        for word in vectors:
            rst, vs, hs, de, user, last = [(word >> n) & 1 for n in (31, 30, 29, 28, 27, 26)]
            value = word & 0xffffff
            if not rst:
                oracle.reset()
                expected = source = pending = source_pending = 0
            else:
                filtered = oracle.sample(value, de, user, last)
                expected, source = pending, source_pending
                pending = output_word(filtered, vs, hs, de, user, last)
                source_pending = output_word(value, vs, hs, de, user, last)
            fs.write(f"{word:08x}\n")
            fe.write(f"{expected:08x}\n")
            fb.write(f"{source:08x}\n")
            count += 1
            pixels += de
    return {"name": name, "width": width, "height": height, "cycles": count,
            "source_pixels": pixels, "tags": tags,
            "inputs": {p.name: sha(p) for p in (folder / "stim.mem", folder / "expected.mem", folder / "source.mem")}}


def with_reset(vectors):
    return [input_word(rst=0), input_word(rst=0), input_word(), *vectors, input_word(), input_word(), input_word()]


def h1_image(image, edge_th=24):
    result = []
    for y, row in enumerate(image):
        result.append([v if x == 0 or (x == 1 and y == 0)
                       else ref.average(v, [row[x-1]], edge_th)
                       for x, v in enumerate(row)])
    return result


def rms(image, expected):
    errors = [(a-b)**2 for row, gold in zip(image[1:], expected[1:])
              for p, q in zip(row[1:], gold[1:]) for a, b in zip(ref.rgb(p), ref.rgb(q))]
    return math.sqrt(sum(errors)/len(errors))


def main():
    cases = []
    rng = random.Random(20261103)
    w, h = 128, 64
    ground = [[ref.packed((112, 128, 144)) for _ in range(w)] for _ in range(h)]
    noisy = [[ref.packed(max(0, min(255, c + round(rng.gauss(0, 3.3))))
                         for c in ref.rgb(p)) for p in row] for row in ground]
    filtered, old = ref.filter_image(noisy), h1_image(noisy)
    raw_rms, h1_rms, new_rms = rms(noisy, ground), rms(old, ground), rms(filtered, ground)
    assert new_rms < h1_rms * 0.85 and new_rms < raw_rms * 0.67
    cases.append(emit("flat_noise", w, h, with_reset(frame_vectors(noisy, 1)), ["independent_rgb_noise", "de_gaps", "nonrecursive"]))
    edge_frames = []
    for kind in range(5):
        image = []
        for y in range(12):
            row = []
            for x in range(32):
                on = (x >= 16) if kind == 0 else (y >= 6) if kind == 1 else (x >= y+7) if kind == 2 else (x == 16) if kind == 3 else bool((x ^ y) & 1)
                row.append(0xffffff if on else 0x102030)
            image.append(row)
        assert ref.filter_image(image) == image, kind
        edge_frames.extend(frame_vectors(image, kind+5, blank=0))
    cases.append(emit("strong_edges", 32, 12, with_reset(edge_frames), ["horizontal", "vertical", "diagonal", "one_pixel_line", "checkerboard", "back_to_back_frames"]))
    # All 8-bit channel values including non-zero low bits survive flat fields.
    flat_values = []
    for v in range(256):
        image = [[ref.packed((v, (v+17)&255, (255-v))) for _ in range(5)] for _ in range(3)]
        assert ref.filter_image(image) == image
        flat_values.extend(frame_vectors(image, v, gaps=False, blank=0))
    cases.append(emit("rgb8_range", 5, 3, with_reset(flat_values), ["all_256_values", "no_bit_clear", "no_quantization", "first_last_row_column"]))
    # Threshold boundaries differ in exactly one RGB channel; all channels
    # must pass the neighbour guard rather than independently mixing colours.
    for c in range(3):
        for delta in (15, 16, 17, -15, -16, -17):
            a = [128, 128, 128]
            a[c] += delta
            b = ref.packed(a)
            accepted = ref.guard(0x808080, b) == b
            assert accepted == (abs(delta) <= 16)
    boundary = [[ref.packed((128+(x%6), 128+(y%4), 128)) for x in range(16)] for y in range(6)]
    boundary[1][1] = 0x908080
    boundary[1][2] = 0x918080
    boundary[2][1] = 0x809080
    boundary[2][2] = 0x809180
    boundary[3][1] = 0x808090
    boundary[3][2] = 0x808091
    cases.append(emit("threshold_rgb_guard", 16, 6, with_reset(frame_vectors(boundary, 11)), ["threshold_16_inclusive", "threshold_17_reject", "three_channel_guard"]))
    for width, height in ((1, 1), (1, 7), (2, 5), (7, 1), (7, 5)):
        pixels = [[gray((17*x+11*y+3)&255) for x in range(width)] for y in range(height)]
        vectors = list(frame_vectors(pixels, width+height, gaps=False, blank=0))
        vectors += list(frame_vectors(pixels, 82, isolated_sof=True, blank=1))
        # Mid-frame reset and abrupt SOF must never reuse old row samples.
        vectors += list(frame_vectors(pixels, 4))[:max(1, width+2)]
        vectors += [input_word(rst=0), input_word()]
        vectors += list(frame_vectors(pixels, 3))
        cases.append(emit(f"geometry_{width}x{height}", width, height, with_reset(vectors), ["ram_collision", "reset", "isolated_sof", "first_last_row_column"]))
    malformed = [input_word(gray(v), de=1, user=(v==0), last=(v==2)) for v in range(3)]
    malformed += [input_word(gray(30+x), de=1, last=int(x==7)) for x in range(8)]
    malformed += [input_word(gray(45+x), de=1, last=0) for x in range(8)]
    malformed += [input_word(gray(50+x), de=1, last=int(x==7)) for x in range(8)]
    malformed += [input_word(gray(210), de=1, user=1), input_word(gray(211), de=1, user=1)]
    malformed += list(frame_vectors([[gray(200+x+y) for x in range(8)] for y in range(4)], 19))
    malformed += list(frame_vectors([[gray(80) for x in range(8)] for y in range(4)], 20, sof=False))
    cases.append(emit("malformed_reentry", 8, 4, with_reset(malformed), ["early_eol", "missing_eol", "abrupt_sof", "held_sof", "no_sof_after_eof", "no_stale_ram"]))
    # Real 1280x720 geometry, no blanking, no synthetic pixels or final-row
    # drain. Two frames force old-row contents to differ from the new frame.
    full = []
    for frame in range(2):
        image = [[ref.packed(((x//160*21+frame*7)&255,
                              (y//90*19+frame*11)&255,
                              (120+(x+y+frame)%9))) for x in range(1280)] for y in range(720)]
        full.extend(frame_vectors(image, frame, gaps=False, blank=0))
    cases.append(emit("full_720p", 1280, 720, with_reset(full), ["1280x720", "1843200_pixels", "source_row_not_filtered", "back_to_back_frames", "final_row_no_drain"]))
    report = {"algorithm": "H=guarded rounded source horizontal avg2; O=guarded rounded current/previous-row H avg2", "edge_threshold": 16, "reference_sha256": sha(MODEL),
              "rtl_sha256": sha(ROOT / "01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v"),
              "cases": cases,
              "synthetic_noise_rms": {"raw": raw_rms, "baseline_h1": h1_rms,
                                      "guarded_separable_2x2": new_rms,
                                      "change_vs_h1_percent": (new_rms/h1_rms-1)*100},
              "software_assertions": "PASS: strong-edge identity, all RGB8 flat values, threshold boundaries, synthetic noise reduction",
              "hardware_validation": "NOT_RUN",
              "limitations": "Synthetic noise metrics do not establish real-camera quality, defect root cause, or board timing/resources."}
    (HERE / "vectors_manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"cases": len(cases), "cycles": sum(c["cycles"] for c in cases),
                      "noise_rms": report["synthetic_noise_rms"]}, indent=2))


if __name__ == "__main__":
    main()
