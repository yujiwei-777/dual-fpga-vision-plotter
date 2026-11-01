"""Render exact simulated G-code into readable and mirrored machine views."""
from __future__ import annotations

import json
from pathlib import Path
import re

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/cnn_named_report"


def main() -> None:
    results = json.loads((OUT / "RESULTS.json").read_text())
    assert results["status"] == "PASS"
    samples = {job["job"]: job for job in results["jobs"] if job["job"] in (1, 5, 9)}
    commands: dict[int, list[str]] = {}
    for line in (OUT / "gcode.txt").read_text().splitlines():
        ident, command = line.split("|", 1)
        commands.setdefault(int(ident), []).append(command)
    scale = 2
    image = Image.new("RGB", (1800 * scale, 720 * scale), "white")
    draw = ImageDraw.Draw(image)
    title_font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 27 * scale)
    label_font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 19 * scale)
    small_font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16 * scale)

    def label(x: int, y: int, text: str, font=label_font, fill="#333333") -> None:
        draw.text((x * scale, y * scale), text, font=font, fill=fill)

    label(30, 20, "CNN report: exact RTL G-code preview", title_font, "#111111")
    label(30, 65, "Logical reading view (machine X mirror undone for inspection)")
    label(30, 370, "Machine XY view (exact emitted X mirror; appearance depends on plotter axis direction)")
    for column, (ident, result) in enumerate(samples.items()):
        panel_x = 30 + column * 590
        label(panel_x, 102, f"C{result['class_id']}: {result['text'][0].strip()}")
        label(panel_x, 407, f"{result['gcode_lines']} G-code lines / {result['pen_downs']} pen strokes", small_font)
        for mirrored in (False, True):
            panel_y = 140 if not mirrored else 445
            pen_down = False
            previous = None
            for command in commands[ident]:
                if command.startswith("G1 Z"):
                    pen_down = "Z+005.00" in command
                    continue
                match = re.fullmatch(r"G([01]) X(\d+)\.(\d{2}) Y(\d+)\.(\d{2}) F\d+", command)
                if not match:
                    continue
                kind, ix, fx, iy, fy = map(int, match.groups())
                machine_x, machine_y = ix * 100 + fx, iy * 100 + fy
                local_x = machine_x - 13960 if mirrored else 19000 - machine_x
                local_y = machine_y - 1000
                point = (round((panel_x + local_x / 10) * scale),
                         round((panel_y + local_y / 10) * scale))
                if kind == 1 and pen_down and previous is not None:
                    draw.line((previous, point), fill="#174d66", width=2 * scale)
                previous = point
    label(30, 675, "Coordinates: target center in original 1280 x 720 image pixels. CONF: model margin score 0..100, not probability.", small_font)
    image.resize((1800, 720), Image.Resampling.LANCZOS).save(OUT / "CNN_NAMED_REPORT_PREVIEW.png")
    print("PASS exact G-code preview: " + str(OUT / "CNN_NAMED_REPORT_PREVIEW.png"))


if __name__ == "__main__":
    main()
