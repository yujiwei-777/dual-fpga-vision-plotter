"""Integer oracle for the HDMI-only causal 2x2 RGB8 spatial filter.

The image helper is a direct, source-image neighbourhood calculation. The
stream helper models malformed rows/blanking/reset, never the RTL pipeline.
No dependency is needed for vector generation; optional image loading uses
Pillow. RGB channels retain all eight bits.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def rgb(value: int) -> tuple[int, int, int]:
    return (value >> 16 & 255, value >> 8 & 255, value & 255)


def packed(channels) -> int:
    r, g, b = channels
    return (r << 16) | (g << 8) | b


def guard(center: int, neighbour: int, edge_th: int = 16) -> int:
    return neighbour if all(abs(a-b) <= edge_th
                            for a, b in zip(rgb(center), rgb(neighbour))) else center


def average(center: int, neighbours: list[int], edge_th: int = 16) -> int:
    values = [rgb(center)] + [rgb(guard(center, n, edge_th)) for n in neighbours]
    divisor = len(values)
    assert divisor in (1, 2, 4)
    return packed((sum(v[c] for v in values) + divisor // 2) // divisor
                  for c in range(3))


def filter_image(image: list[list[int]], edge_th: int = 16,
                 enabled: bool = True) -> list[list[int]]:
    """Direct oracle over unfiltered source samples, including all borders."""
    result = []
    for y, line in enumerate(image):
        output = []
        for x, center in enumerate(line):
            neighbours = []
            if x:
                neighbours.append(line[x-1])
            if y:
                neighbours.append(image[y-1][x])
                if x:
                    neighbours.append(image[y-1][x-1])
            output.append(average(center, neighbours, edge_th) if enabled else center)
        result.append(output)
    return result


class StreamReference:
    """Input semantics, independent of RAM/read/write scheduling."""

    def __init__(self, width: int, height: int, edge_th: int = 16):
        self.width, self.height, self.edge_th = width, height, edge_th
        self.reset()

    def reset(self):
        self.current_line = []
        self.previous_line = None
        self.y = 0
        self.in_frame = False
        self.pending_sof = False

    def sample(self, value: int, de: bool, user: bool, last: bool) -> int:
        if user:
            self.current_line = []
            self.previous_line = None
            self.y = 0
            self.in_frame = True
            self.pending_sof = not de
        if not de:
            return value
        if self.pending_sof:
            self.current_line = []
            self.previous_line = None
            self.y = 0
            self.in_frame = True
            self.pending_sof = False
        x = len(self.current_line)
        neighbours = []
        if x:
            neighbours.append(self.current_line[x-1])
        if self.in_frame and self.previous_line is not None:
            neighbours.append(self.previous_line[x])
            if x:
                neighbours.append(self.previous_line[x-1])
        result = average(value, neighbours, self.edge_th)
        self.current_line.append(value)
        if last or len(self.current_line) == self.width:
            complete = last and len(self.current_line) == self.width
            self.previous_line = (list(self.current_line)
                                  if complete and self.in_frame and self.y < self.height-1
                                  else None)
            self.current_line = []
            if self.y == self.height-1:
                self.y = 0
                self.in_frame = False
            else:
                self.y += 1
        return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument("--edge-th", type=int, default=16)
    args = p.parse_args()
    from PIL import Image
    source = Image.open(args.input).convert("RGB")
    w, h = source.size
    pixels = [packed(v) for v in source.getdata()]
    result = filter_image([pixels[y*w:(y+1)*w] for y in range(h)], args.edge_th)
    output = Image.new("RGB", (w, h))
    output.putdata([rgb(v) for row in result for v in row])
    output.save(args.output)
    print(json.dumps({"input": str(args.input), "output": str(args.output),
                      "width": w, "height": h, "edge_th": args.edge_th}))


if __name__ == "__main__":
    main()
