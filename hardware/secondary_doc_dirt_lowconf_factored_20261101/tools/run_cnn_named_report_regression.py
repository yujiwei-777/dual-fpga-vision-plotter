"""Run production reporter RTL, then compare text and every G-code command."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from cnn_named_report_reference import font_segments, machine_commands, report_text

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/cnn_named_report"
SIM = Path("E:/model/win64")
ENV = os.environ.copy()
ENV.update(MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"), LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"))
SOURCES = [ROOT / "01_rtl" / name for name in (
    "grbl_line_formatter.v", "grbl_response_parser.v", "grbl_streamer.v",
    "grbl_vector_font_rom.v", "grbl_reporter.v")]
SOURCES.append(OUT / "tb_cnn_named_report.sv")
INPUTS = SOURCES + [ROOT / "tools/cnn_named_report_reference.py", Path(__file__).resolve()]


def run(name: str, args: list[object]) -> str:
    result = subprocess.run([arg.as_posix() if isinstance(arg, Path) else str(arg) for arg in args], cwd=OUT, env=ENV, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (OUT / f"{name}.log").write_text(result.stdout)
    if result.returncode or re.search(r"\*\*\s+(?:Error|Fatal):", result.stdout):
        raise RuntimeError(name + " failed:\n" + result.stdout[-6000:])
    return result.stdout


def main() -> None:
    if not (SIM / "LICENSE.TXT").is_file():
        raise RuntimeError("file license E:/model/win64/LICENSE.TXT is missing")
    OUT.mkdir(parents=True, exist_ok=True)
    before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest().upper() for path in INPUTS}
    run("vlib", [SIM / "vlib.exe", OUT / "work"])
    run("compile", [SIM / "vlog.exe", "-sv", "-lint", "-work", OUT / "work", *SOURCES])
    log = run("simulate", [SIM / "vsim.exe", "-batch", "-quiet", "-novopt", "-suppress", "12110", "-lib", OUT / "work",
                           "tb_cnn_named_report", "-do", "run -all; quit -f"])
    assert "PASS CNN_NAMED_REPORT_ALL 33 jobs plus capacity and safety" in log
    traces: dict[int, dict[int, list[tuple[int, str]]]] = {}
    for line in (OUT / "glyph_trace.txt").read_text().splitlines():
        ident, row, col, char = map(int, line.split("|"))
        traces.setdefault(ident, {}).setdefault(row, []).append((col, chr(char)))
    commands: dict[int, list[str]] = {}
    for line in (OUT / "gcode.txt").read_text().splitlines():
        ident, command = line.split("|", 1)
        commands.setdefault(int(ident), []).append(command)
    font = font_segments(ROOT / "01_rtl/grbl_vector_font_rom.v")
    results = []
    for line in (OUT / "jobmeta.txt").read_text().splitlines():
        ident, cls, conf, judgement, cnn, square, old_offset, new_offset, count = map(int, line.split("|"))
        valid_target = cnn and judgement == 2 and 1 <= cls <= 9
        center = (639, 359) if ident == 12 else (210, 110)
        expected_text = [] if square else report_text(cls, conf, judgement, bool(cnn), ident, center)
        actual_text = []
        for row in sorted(traces.get(ident, {})):
            cells = traces[ident][row]
            assert [col for col, _ in cells] == list(range(len(cells))), (ident, row, cells)
            actual_text.append("".join(char for _, char in cells))
        assert [text.rstrip() for text in actual_text] == [text.rstrip() for text in expected_text], (
            ident, actual_text, expected_text)
        height = 2500 if square else 2060 if valid_target else 860 if cnn else 1460
        assert new_offset - old_offset == height, (ident, old_offset, new_offset, height)
        expected_gcode = machine_commands(expected_text, font, old_offset, height, bool(square))
        actual_gcode = commands[ident]
        if actual_gcode != expected_gcode:
            mismatch = next(((i, a, b) for i, (a, b) in enumerate(zip(actual_gcode, expected_gcode)) if a != b),
                            (len(actual_gcode), len(expected_gcode)))
            raise AssertionError((ident, mismatch))
        assert count == len(actual_gcode)
        results.append({"job": ident, "class_id": cls, "text": actual_text,
                        "all_gcode_commands_exact": True, "gcode_lines": count,
                        "pen_downs": actual_gcode.count("G1 Z+005.00 F01200"),
                        "newline_delta_cmm": height})
    after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest().upper() for path in INPUTS}
    assert before == after, "RTL/test input changed during validation"
    safety_trace = (OUT / "safety_trace.txt").read_text().splitlines()
    assert safety_trace == ["CAPACITY|13|14|12|0|26780", "STOP|2|4|0|0|0"], safety_trace
    summary = {"status": "PASS", "hardware_status": "NOT_RUN", "jobs": results,
               "page_exhaustion": "13 reports fit; 14th rejected with error12 before commands; cursor retained",
               "stop_final_conf_line": "no new complete command or DONE; !, ?, Ctrl-X, ? with fresh Hold/Idle; automatic safe rearm",
               "input_hashes": before, "confidence_contract": "rounded RTL margin score 0..100; not probability",
               "coordinate_contract": "floor bbox center in original 1280x720 image pixels; packed x/y in low32",
               "scope": "production reporter/formatter/font/streamer/parser; simulated UART ACKs; no CNN inference, DDR or PHY simulation"}
    (OUT / "RESULTS.json").write_text(json.dumps(summary, indent=2))
    print(f"PASS: {len(results)} reports; exact glyphs, all G-code commands, coordinates, newline and ACK completion")


if __name__ == "__main__":
    main()
