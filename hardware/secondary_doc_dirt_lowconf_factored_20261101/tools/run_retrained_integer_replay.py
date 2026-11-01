"""Re-run integer FC3 inference from the exact ROM text consumed by RTL."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "model" / "fast_strict160_dataset" / "model_selected"
EXPORT = ROOT / "01_rtl" / "model" / "export"
DATA = ROOT / "model" / "fast_strict160_dataset" / "images_strict160.npz"
sys.path.insert(0, r"D:\program\fpga\lab_ex3_osd_SC500_720P\cnn_dualhead_scratch_20261015_r6\tools")
import network  # type: ignore


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def signed_hex(path: Path, bits: int) -> np.ndarray:
    vals = [int(s, 16) for s in path.read_text(encoding="ascii").split()]
    limit = 1 << (bits - 1)
    full = 1 << bits
    return np.asarray([v - full if v >= limit else v for v in vals], dtype=np.int64)


def main() -> int:
    package = np.load(PKG / "quantized.npz")
    weights = signed_hex(EXPORT / "weights.mem", 8).astype(np.int8)
    biases = signed_hex(EXPORT / "biases.mem", 32).astype(np.int64)
    expected_w = np.concatenate([package[f"w{i}"].reshape(-1) for i in range(3)]).astype(np.int8)
    expected_b = np.concatenate([package[f"b{i}"].reshape(-1) for i in range(3)]).astype(np.int64)
    if not np.array_equal(weights, expected_w):
        raise SystemExit("weights.mem does not match quantized.npz")
    if not np.array_equal(biases, expected_b):
        raise SystemExit("biases.mem does not match quantized.npz")
    params = json.loads((EXPORT / "quantization.json").read_text(encoding="utf-8"))
    archive = {f"w{i}": package[f"w{i}"] for i in range(3)}
    archive.update({f"b{i}": package[f"b{i}"] for i in range(3)})
    data = np.load(DATA)
    images, labels = data["images"], data["labels"]
    scores = network.integer_scores(images, [archive[f"w{i}"] for i in range(3)], [archive[f"b{i}"] for i in range(3)], params)
    metrics = network.metrics(scores, labels)
    report = {
        "status": "INTEGER_ROM_REPLAY_PASS",
        "variant": ROOT.name,
        "frames": int(len(images)),
        "weights_entries": int(len(weights)),
        "bias_entries": int(len(biases)),
        "weights_sha256": sha256(EXPORT / "weights.mem"),
        "biases_sha256": sha256(EXPORT / "biases.mem"),
        "quantization_sha256": sha256(EXPORT / "quantization.json"),
        "metrics": metrics,
        "model_input": "RGB8 64x64 HWC",
        "class_id": "color*3+shape+1",
        "background_head": False,
        "hardware_validation": "NOT_RUN",
    }
    out = ROOT / "artifacts" / "INTEGER_ROM_REPLAY_REPORT.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
