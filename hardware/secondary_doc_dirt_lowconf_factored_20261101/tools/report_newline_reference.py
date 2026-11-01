"""Integer contract for report/KEY2 pagination; no FPGA or machine I/O.

All lengths are hundredths of a millimetre.  PCB physical marks retain the
baseline image-to-workspace scale before the report block's Y offset is added.
This reference specifies layout bounds rather than measuring font ink pixels.
Run with --output to retain the independently computed numerical test results.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import random


@dataclass(frozen=True)
class Profile:
    origin_x: int = 1000
    origin_y: int = 1000
    work_x: int = 19000
    work_y: int = 29700
    safe_y_max: int = 28700
    font_step: int = 60
    gap: int = 500


@dataclass(frozen=True)
class Marker:
    x0: int
    y0: int
    x1: int
    y1: int
    kind: int


@dataclass(frozen=True)
class Reservation:
    start_y: int
    ink_bottom: int
    next_y: int
    row_offset: int
    admitted: bool


def mirror_x(x: int, x_min: int, x_max: int) -> int:
    if not x_min <= x <= x_max:
        raise ValueError("X outside calibrated workspace")
    return x_min + x_max - x


def marker_segments(marker: Marker, row_offset: int = 0,
                    profile: Profile = Profile()) -> list[tuple[int, int, int, int]]:
    """Return logical (pre-mirror) mark endpoints, preserving baseline scale."""
    x0, x1 = (min(1280, max(0, x)) for x in (marker.x0, marker.x1))
    y0, y1 = (min(720, max(0, y)) for y in (marker.y0, marker.y1))
    if x1 <= x0 or y1 <= y0 or marker.kind not in (1, 2):
        return []
    px, py = (x0 + x1) // 2, (y0 + y1) // 2
    cx = profile.origin_x + px * (profile.work_x - profile.origin_x) // 1280
    cy = profile.origin_y + py * (profile.work_y - profile.origin_y) // 720
    radius = 100 if marker.kind == 1 else 200
    horizontal = marker.kind == 1 or x1 - x0 >= y1 - y0
    vertical = marker.kind == 1 or not horizontal
    result = []
    if horizontal:
        result.append((max(profile.origin_x, cx - radius), cy + row_offset,
                       min(profile.work_x, cx + radius), cy + row_offset))
    if vertical:
        result.append((cx, max(profile.origin_y, cy - radius) + row_offset,
                       cx, min(profile.work_y, cy + radius) + row_offset))
    return result


def reserve(start_y: int, *, key2: bool = False, defect_count: int = 0,
            markers: tuple[Marker, ...] = (), profile: Profile = Profile()) -> Reservation:
    if defect_count not in range(5):
        raise ValueError("report defect capacity is 0..4")
    offset = start_y - profile.origin_y
    if key2:
        bottom = start_y + 2000
        next_y = start_y + 2500
    else:
        # Header and DEFECTS line plus each defect's coordinate line.  Glyph
        # rows span 0..6 and line spacing is ten font steps in the baseline.
        bottom = start_y + ((defect_count + 1) * 10 + 6) * profile.font_step
        for marker in markers[:defect_count]:
            for _, y0, _, y1 in marker_segments(marker, offset, profile):
                bottom = max(bottom, y0, y1)
        next_y = bottom + profile.gap
    admitted = (offset >= 0 and bottom <= profile.safe_y_max
                and next_y <= profile.safe_y_max)
    return Reservation(start_y, bottom, next_y, offset, admitted)


def run_checks() -> dict:
    p = Profile()
    checks = []
    assert mirror_x(1000, 1000, 19000) == 19000
    assert mirror_x(19000, 1000, 19000) == 1000
    assert mirror_x(20000, 1000, 20000) == 1000  # document return-to-X10
    checks.append("single X mirror and document physical return X10")

    expected = [1960, 2560, 3160, 3760, 4360]
    reports = [reserve(1000, defect_count=n) for n in range(5)]
    assert [r.ink_bottom for r in reports] == expected
    assert [r.next_y for r in reports] == [x + 500 for x in expected]
    checks.append("0..4 defects reserve whole text height plus 5mm")

    squares = []
    cursor = p.origin_y
    while True:
        r = reserve(cursor, key2=True)
        if not r.admitted:
            break
        squares.append(asdict(r))
        cursor = r.next_y
    assert len(squares) == 11
    assert squares[-1]["next_y"] == 28500
    assert not reserve(cursor, key2=True).admitted
    checks.append("11 separate KEY2 squares at 25mm pitch; no page wrap")

    edge_mark = Marker(620, 706, 660, 720, 1)
    edge_layout = reserve(1000, defect_count=1, markers=(edge_mark,))
    assert not edge_layout.admitted
    checks.append("near-bottom PCB mark rejects entire report before movement")

    rng = random.Random(20261027)
    tested = 0
    for _ in range(5000):
        xa, xb = sorted(rng.sample(range(1281), 2))
        ya, yb = sorted(rng.sample(range(721), 2))
        marker = Marker(xa, ya, xb, yb, rng.choice((1, 2)))
        shift = rng.randrange(24001)
        original = marker_segments(marker)
        shifted = marker_segments(marker, shift)
        # Translating the page block cannot rescale either axis of the mark.
        assert len(original) == len(shifted)
        for a, b in zip(original, shifted):
            assert a[0] == b[0] and a[2] == b[2]
            assert a[1] + shift == b[1] and a[3] + shift == b[3]
        r = reserve(p.origin_y + shift, defect_count=1, markers=(marker,))
        if r.admitted:
            for x0, y0, x1, y1 in shifted:
                assert p.origin_x <= mirror_x(x0, p.origin_x, p.work_x) <= p.work_x
                assert p.origin_x <= mirror_x(x1, p.origin_x, p.work_x) <= p.work_x
                assert p.origin_y <= y0 <= p.safe_y_max
                assert p.origin_y <= y1 <= p.safe_y_max
            assert r.next_y >= max(max(s[1], s[3]) for s in shifted) + p.gap
        tested += 1
    checks.append(f"{tested} PCB marks retain physical scale after Y translation")
    return {"status": "PASS", "scope": "independent integer layout reference; not RTL proof",
            "checks": checks, "profile": asdict(p),
            "text_layouts": [asdict(r) for r in reports], "key2_layouts": squares,
            "bottom_marker_rejected": asdict(edge_layout)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    results = run_checks()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            raise SystemExit("refusing to overwrite prior numerical evidence")
        args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
