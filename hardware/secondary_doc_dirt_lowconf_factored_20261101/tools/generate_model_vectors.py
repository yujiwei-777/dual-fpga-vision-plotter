"""Regenerate integer RTL golden vectors for the installed PCB ROM."""
from pathlib import Path
import shutil
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "02_sim/centered_50plus_inputs_20261029/rtl_vectors"
OUT = ROOT / "02_sim/new_capture_mix_vectors3_20261029/rtl_vectors"
MODEL = ROOT / "model/experiments/conv4_4"


def qmem(path: Path, signed: bool) -> np.ndarray:
    values = [int(v, 16) for v in path.read_text().split()]
    if signed:
        return np.asarray(values, dtype=np.uint8).view(np.int8)
    return np.asarray(values, dtype=np.uint32).view(np.int32)


def conv_integer(x: np.ndarray, weight: np.ndarray, bias: np.ndarray, shift: int):
    padded = np.pad(x.astype(np.int64), ((0, 0), (0, 0), (1, 1), (1, 1)))
    windows = np.lib.stride_tricks.sliding_window_view(
        padded, (3, 3), axis=(-2, -1))[:, :, ::2, ::2]
    acc = np.einsum("nihwyx,oiyx->nohw", windows, weight.astype(np.int64), optimize=True)
    acc += bias.astype(np.int64)[None, :, None, None]
    shifted = acc >> shift
    return shifted.clip(0, 32767).astype(np.int16)


def write_hex(path: Path, values: np.ndarray, width: int) -> None:
    mask = (1 << (width * 4)) - 1
    path.write_text("".join(f"{int(v) & mask:0{width}x}\n" for v in values.ravel()), encoding="ascii")


def main() -> None:
    if OUT.exists():
        raise RuntimeError(f"refusing to overwrite {OUT}")
    OUT.mkdir(parents=True)
    pixels = np.asarray([int(v, 16) for v in (SOURCE / "input_pixels.mem").read_text().split()], dtype=np.uint8)
    if pixels.size % (96 * 96):
        raise RuntimeError("input pixel vector size is not a multiple of 96x96")
    images = pixels.reshape(-1, 1, 96, 96)
    weights = qmem(MODEL / "weights.mem", True)
    biases = qmem(MODEL / "biases.mem", False)
    q = {
        "w1": weights[:36].reshape(4, 1, 3, 3),
        "b1": biases[:4],
        "w2": weights[36:180].reshape(4, 4, 3, 3),
        "b2": biases[4:8],
        "w3": weights[180:].reshape(2, 64),
        "b3": biases[8:],
    }
    f1 = conv_integer(images, q["w1"], q["b1"], 7)
    f2 = conv_integer(f1, q["w2"], q["b2"], 7)
    pooled = (f2.astype(np.int64).reshape(-1, 4, 4, 6, 4, 6)
              .sum(axis=(3, 5)) >> 5).reshape(-1, 64)
    logits = (pooled @ q["w3"].astype(np.int64).T + q["b3"].astype(np.int64)) >> 8
    # The RTL workspace is laid out as y, x, channel (channel is the
    # innermost address), while the integer reference uses channel, y, x.
    write_hex(OUT / "expected_f1.mem", f1.transpose(0, 2, 3, 1), 4)
    write_hex(OUT / "expected_f2.mem", f2.transpose(0, 2, 3, 1), 4)
    write_hex(OUT / "expected_pool.mem", pooled, 4)
    write_hex(OUT / "expected_logits.mem", logits, 8)
    shutil.copy2(SOURCE / "input_pixels.mem", OUT / "input_pixels.mem")
    for name in ("raw_frames.bin", "samples.json", "virtual_frame_provenance.json"):
        shutil.copy2(SOURCE / name, OUT / name)
    print({"samples": int(images.shape[0]), "logits_shape": list(logits.shape), "output": str(OUT)})


if __name__ == "__main__":
    main()
