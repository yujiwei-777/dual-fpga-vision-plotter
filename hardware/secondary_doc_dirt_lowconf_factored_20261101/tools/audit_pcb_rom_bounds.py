#!/usr/bin/env python3
"""Verify the fixed PCB TinyCNN ROM set used by the 22-bit RTL datapath."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


EXPECTED_SHA256 = {
    "pcb_tinycnn_bias.mem": "87F1F5471A799EE0001BBBF595B41A46476AFC205275FFF8E8CF416A53332502",
    "pcb_tinycnn_first.mem": "2DFB03DF5F6436B1879CBB34F25627420B7C23EB60EC9EFC30A35AA7707BCC63",
    "pcb_tinycnn_next.mem": "82556E0AB104CE1073D1A94E69E0966C8A0D8AAFE6DA3AAD385644831A653997",
    "pcb_tinycnn_taps.mem": "1643E460DCC702F91ED9D300CB1F5E6C7C880FF1D1539E3F9853266722A2F6B5",
    "pcb_tinycnn_weights.mem": "EB148029C2A724CF39E6A3D7FCE6EDBB366FA9E41A0E03579BF313C8E439D224",
}


def read_hex(path: Path, width: int, count: int) -> list[int]:
    values = [int(line.strip(), 16) for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    if len(values) != count or any(value >= (1 << width) for value in values):
        raise ValueError(f"{path.name}: expected {count} values of {width} bits")
    return values


def signed(value: int, width: int) -> int:
    sign = 1 << (width - 1)
    return value - (1 << width) if value & sign else value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, default=Path(__file__).resolve().parents[1] / "model")
    args = parser.parse_args()
    model_dir = args.model_dir.resolve()

    for name, expected in EXPECTED_SHA256.items():
        path = model_dir / name
        actual = hashlib.sha256(path.read_bytes()).hexdigest().upper()
        if actual != expected:
            raise SystemExit(f"ROM hash mismatch: {path} expected={expected} actual={actual}")

    biases = [signed(value, 32) for value in read_hex(model_dir / "pcb_tinycnn_bias.mem", 32, 23)]
    first = read_hex(model_dir / "pcb_tinycnn_first.mem", 10, 23)
    nxt = read_hex(model_dir / "pcb_tinycnn_next.mem", 10, 972)
    weights = [signed(value, 8) for value in read_hex(model_dir / "pcb_tinycnn_weights.mem", 8, 972)]
    read_hex(model_dir / "pcb_tinycnn_taps.mem", 8, 972)

    reachable: list[list[int]] = []
    seen_all: set[int] = set()
    for output, tap in enumerate(first):
        seen: set[int] = set()
        indices: list[int] = []
        while tap != 0x3FF:
            if tap >= len(nxt) or tap in seen:
                raise SystemExit(f"invalid tap chain for output {output}: tap={tap}")
            seen.add(tap)
            seen_all.add(tap)
            indices.append(tap)
            tap = nxt[tap]
        reachable.append(indices)

    layer_ranges = ((0, 8, 255, "conv1"), (8, 20, 32767, "conv2"), (20, 23, 32767, "head"))
    max_abs_weight = max(abs(weights[tap]) for tap in seen_all)
    product_bound = max(255, 32767) * max_abs_weight
    all_bounds: list[tuple[str, int]] = []
    for begin, end, input_bound, label in layer_ranges:
        bound = max(abs(biases[index]) + input_bound * sum(abs(weights[t]) for t in reachable[index])
                    for index in range(begin, end))
        all_bounds.append((label, bound))
        if bound >= (1 << 21):
            raise SystemExit(f"{label} accumulator bound does not fit signed 22 bits: {bound}")
    if product_bound >= (1 << 21):
        raise SystemExit(f"MAC product bound does not fit signed 22 bits: {product_bound}")

    print(f"PASS PCB ROM SHA256 set: {len(EXPECTED_SHA256)} files")
    print(f"reachable_taps={len(seen_all)} max_abs_weight={max_abs_weight} product_bound={product_bound}")
    for label, bound in all_bounds:
        print(f"{label}_max_abs_accumulator_bound={bound} signed22=PASS")
    print("logit_difference_signed23=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
