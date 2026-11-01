"""Integer report and machine-command reference for the independent variant."""
from __future__ import annotations

import re
from pathlib import Path


def report_text(class_id: int, confidence: int, judgement: int, cnn: bool,
                job_id: int, center: tuple[int, int]) -> list[str]:
    if cnn:
        if judgement != 2 or not 1 <= class_id <= 9:
            return ["NO TARGET"]
        color = ("RED", "GREEN", "BLUE")[(class_id - 1) // 3]
        shape = ("TRIANGLE", "CIRCLE", "SQUARE")[(class_id - 1) % 3]
        center_x, center_y = center
        return [f"{color:5s} {shape:8s}", f"X{center_x:04d} Y{center_y:04d}",
                f"CONF {confidence:03d}"]
    decision = {0: "REVIEW", 1: "PASS", 2: "FAIL"}[judgement]
    return [f"PCB {job_id:04d} {decision}", "DEFECTS 0"]


def font_segments(path: Path) -> dict[str, list[tuple[int, int, int, int]]]:
    entries: dict[int, int] = {}
    for address, word in re.findall(r"segments\[10'd(\d+)\]=16'h([0-9a-fA-F]+);", path.read_text()):
        entries[int(address)] = int(word, 16)
    glyphs = {}
    for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 :-.":
        base = (ord(char) & 63) * 16
        count = entries.get(base, 0) >> 12
        glyphs[char] = [tuple((entries[base + i] >> shift) & 7 for shift in (9, 6, 3, 0))
                        for i in range(count)]
    return glyphs


def machine_commands(text: list[str], font: dict[str, list[tuple[int, int, int, int]]],
                     offset: int, height: int, square: bool = False) -> list[str]:
    def move(kind: int, x: int, y: int) -> str:
        mirror_x = 20000 - x
        return (f"G{kind} X{mirror_x // 100:03d}.{mirror_x % 100:02d} "
                f"Y{y // 100:03d}.{y % 100:02d} F{7000 if kind == 0 else 3000:05d}")

    up, down = "G1 Z-001.20 F01200", "G1 Z+005.00 F01200"
    commands = ["G21", "G90", "G54", up]
    base_y = 1000 + offset
    if square:
        commands.extend([move(0, 1000, base_y), down, "G4 P0.1"])
        commands.extend(move(1, x, y) for x, y in ((3000, base_y), (3000, base_y + 2000),
                                                   (1000, base_y + 2000), (1000, base_y)))
    else:
        for row, line in enumerate(text):
            for col, char in enumerate(line):
                previous = None
                for x0, y0, x1, y1 in font[char]:
                    start = (1000 + (col * 6 + x0) * 60, base_y + (row * 10 + y0) * 60)
                    end = (1000 + (col * 6 + x1) * 60, base_y + (row * 10 + y1) * 60)
                    if previous != start:
                        if previous is not None:
                            commands.append(up)
                        commands.extend([move(0, *start), down, "G4 P0.1"])
                    commands.append(move(1, *end))
                    previous = end
                if previous is not None:
                    commands.append(up)
    commands.extend([up, move(0, 1000, base_y + height)])
    return commands
