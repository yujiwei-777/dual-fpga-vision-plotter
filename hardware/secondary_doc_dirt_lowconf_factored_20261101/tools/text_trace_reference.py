"""Reference model for the bounded FPGA text-trace path.

Input is a 180x320 uint8 luma image.  Black pixels are luma < 128.  The
model emits one horizontal centre line for each row containing at least two
black samples and, when the envelope is tall enough, one vertical centre
line.  Coordinates are the same 64x32 quantized values used by the RTL.
"""
from __future__ import annotations
from typing import Iterable, List, Tuple

Segment = Tuple[int, int, int, int]


def _mx(v: int) -> int:
    return min(63, (v * 13) >> 6)


def _my(v: int) -> int:
    return min(31, (v * 50) >> 8)


def trace(luma: Iterable[Iterable[int]]) -> List[Segment]:
    rows = [list(row) for row in luma]
    if len(rows) != 180 or any(len(row) != 320 for row in rows):
        raise ValueError("expected 180x320 luma")
    segs: List[Segment] = []
    minx, maxx, miny, maxy = 320, -1, 180, -1
    for y, row in enumerate(rows):
        dark = [x for x, value in enumerate(row) if value < 128]
        if dark:
            minx, maxx = min(minx, dark[0]), max(maxx, dark[-1])
            miny, maxy = min(miny, y), max(maxy, y)
        if len(dark) >= 2 and len(segs) < 256:
            segs.append((_mx(dark[0]), _my(y), _mx(dark[-1]), _my(y)))
    if maxy >= 0 and maxy - miny >= 4 and len(segs) < 256:
        cx = _mx((minx + maxx) // 2)
        segs.append((cx, _my(miny), cx, _my(maxy)))
    return segs[:256]


if __name__ == "__main__":
    blank = [[255] * 320 for _ in range(180)]
    assert trace(blank) == []
    page = [[255] * 320 for _ in range(180)]
    for y in range(60, 100):
        for x in range(80, 240):
            if y in (60, 99) or x in (80, 239):
                page[y][x] = 0
    result = trace(page)
    assert result and result[-1][0] == result[-1][2]
    print(f"PASS text trace reference: {len(result)} segments")
