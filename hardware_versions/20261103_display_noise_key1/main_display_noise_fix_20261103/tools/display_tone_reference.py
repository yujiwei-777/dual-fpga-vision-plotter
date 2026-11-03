"""Integer-only tone reference; fixed recognition curve stays frozen."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def fixed_tone(value: int) -> int:
    if not 0 <= value <= 255:
        raise ValueError(value)
    if value < 32:
        offset_bits = value >> 1
    elif value < 96:
        offset_bits = (value >> 3) + 12
    else:
        offset_bits = (52 - (value >> 2) -
                       int(value >= 192 and (value & 3) == 3)) & 63
    offset = offset_bits - 64 if offset_bits & 32 else offset_bits
    return (value + offset) & 255


def display_tone(value: int) -> int:
    # Concatenation {5'b01111, value[1:0], 1'b0} in the RTL.
    return 120 + ((value & 3) << 1) if 96 <= value <= 99 else fixed_tone(value)


def generate(root: Path) -> dict:
    sim = root / "02_sim" / "display_tone"
    reports = root / "reports"
    sim.mkdir(parents=True, exist_ok=True)
    reports.mkdir(parents=True, exist_ok=True)
    fixed = [fixed_tone(x) for x in range(256)]
    display = [display_tone(x) for x in range(256)]
    assert all(0 <= x <= 255 for x in fixed + display)
    assert max(fixed) == max(display) == 243
    assert all(a <= b for a, b in zip(display, display[1:]))
    assert max(b - a for a, b in zip(display, display[1:])) == 2
    changed = [x for x in range(256) if fixed[x] != display[x]]
    assert changed == [96, 97, 98, 99]
    assert display[95:101] == [118, 120, 122, 124, 126, 127]
    assert max(abs(a - b) for a, b in zip(fixed, display)) == 4
    for name, curve in (("fixed_curve.hex", fixed), ("display_curve.hex", display)):
        (sim / name).write_text("".join(f"{x:02x}\n" for x in curve), encoding="ascii")
    rtl_rel = Path("01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v")
    baseline = root.parent / "main_pcb_auto_compat_20261101" / rtl_rel
    baseline_sha = hashlib.sha256(baseline.read_bytes()).hexdigest().upper()
    assert baseline_sha == "063737B3786DFCEECB8CCCD5314BDB150256BEF77CA02898D02F65D5CE56EDDC"
    report = {
        "status": "PASS",
        "kind": "exhaustive_integer_reference",
        "input_values": 256,
        "baseline_rtl_sha256": baseline_sha,
        "variant_rtl_sha256": hashlib.sha256((root / rtl_rel).read_bytes()).hexdigest().upper(),
        "fixed_tap": "frozen function unchanged; RTL cycle comparison is separate",
        "changed_source_values": changed,
        "old_values_95_through_100": fixed[95:101],
        "display_values_95_through_100": display[95:101],
        "baseline_max_adjacent_step": max(b - a for a, b in zip(fixed, fixed[1:])),
        "display_max_adjacent_step": max(b - a for a, b in zip(display, display[1:])),
        "maximum_display_decrease_dn": 4,
        "output_range": [min(display), max(display)],
        "changes_ae_gain_awb": False,
        "adds_dsp_operations": False,
        "physical_resource_result": "pending synthesis",
        "limitations": "Display curve continuity only; not temporal denoising or a sensor noise fix.",
    }
    (reports / "display_tone_reference.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    print(json.dumps(generate(args.root.resolve()), indent=2, ensure_ascii=False))
