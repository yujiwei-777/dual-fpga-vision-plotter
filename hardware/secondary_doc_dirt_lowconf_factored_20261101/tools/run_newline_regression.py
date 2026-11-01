"""Verify newline G-code and ACK/Idle ordering in a fresh ModelSim library.

This runner never deletes a prior simulation directory and hashes every input
before/after simulation, so a report describes the exact RTL that was tested.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path("E:/model/win64")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / "02_sim").resolve()):
        raise SystemExit("output must be a new directory inside this variant's 02_sim")
    license_path = TOOLS / "LICENSE.TXT"
    if not license_path.is_file():
        raise SystemExit(f"ModelSim file license not found: {license_path}")
    output.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "01_rtl" / name for name in (
        "grbl_line_formatter.v", "grbl_reporter.v", "grbl_response_parser.v",
        "grbl_streamer.v", "grbl_vector_font_rom.v",
    )]
    sources += [ROOT / "02_sim/doc_plotter/tb_grbl_reporter_newline.sv"]
    hashes = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sources}
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(license_path), LM_LICENSE_FILE=str(license_path))
    results = {}
    commands = (
        ("vlib", [str(TOOLS / "vlib.exe"), "work"]),
        ("lint", [str(TOOLS / "vlog.exe"), "-sv", "-lint", "-work", "work", *map(str, sources)]),
        ("arithmetic", [str(TOOLS / "vsim.exe"), "-c", "-quiet", "-lib", "work",
                        "tb_grbl_reporter_marker_arithmetic", "-do",
                        "onerror {quit -code 1}; run -all; quit -code 0"]),
        ("simulation", [str(TOOLS / "vsim.exe"), "-c", "-quiet", "-lib", "work",
                        "tb_grbl_reporter_newline", "-do",
                        "onerror {quit -code 1}; run -all; quit -code 0"]),
    )
    for name, command in commands:
        process = subprocess.run(command, cwd=output, env=env, text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (output / f"{name}.log").write_text(process.stdout, encoding="utf-8", errors="replace")
        results[name] = {"returncode": process.returncode}
        if process.returncode or re.search(r"\*\*\s+(?:Error|Fatal):", process.stdout):
            (output / "RESULTS.json").write_text(json.dumps(results, indent=2))
            raise SystemExit(f"{name} failed; see {output / (name + '.log')}")
        if name in ("arithmetic", "simulation"):
            markers = re.findall(r"PASS[^\r\n]*", process.stdout)
            results[name]["checks"] = markers
            expected = "ALL NEWLINE" if name == "simulation" else "MARKER ARITHMETIC"
            if not any(expected in marker for marker in markers):
                raise SystemExit("simulation did not reach final PASS marker")
    if any(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != value
           for name, value in hashes.items()):
        raise SystemExit("input RTL or bench changed during simulation")
    jobs = {}
    for entry in (output / "newline_gcode_trace.txt").read_text().splitlines():
        match = re.fullmatch(r"LINE (\d+) JOB (\d+) (.*)", entry)
        if not match:
            raise SystemExit(f"invalid G-code trace entry: {entry}")
        _, job_id, command = match.groups()
        job = jobs.setdefault(job_id, {"gcode_lines": 0, "pen_lifts": 0, "xy_cmm": []})
        job["gcode_lines"] += 1
        job["pen_lifts"] += command == "G1 Z-001.20 F01200"
        xy = re.fullmatch(r"G[01] X(\d+)\.(\d\d) Y(\d+)\.(\d\d) F\d+", command)
        if xy:
            xi, xf, yi, yf = map(int, xy.groups())
            job["xy_cmm"].append([xi * 100 + xf, yi * 100 + yf])
    for job in jobs.values():
        points = job.pop("xy_cmm")
        job["xy_commands"] = len(points)
        if points:
            job["bounds_cmm"] = [min(point[0] for point in points), min(point[1] for point in points),
                                  max(point[0] for point in points), max(point[1] for point in points)]
            job["final_xy_cmm"] = points[-1]
    (output / "INPUTS.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
    (output / "GCODE_METRICS.json").write_text(json.dumps(jobs, indent=2), encoding="utf-8")
    (output / "RESULTS.json").write_text(json.dumps({"status": "PASS", **results}, indent=2), encoding="utf-8")
    print(f"PASS newline regression: {output}")


if __name__ == "__main__":
    main()
