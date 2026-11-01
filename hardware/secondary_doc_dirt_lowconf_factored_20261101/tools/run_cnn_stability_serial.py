"""Verify the active kernel serial output against unchanged integer gold.

The receiver deliberately destroys the shared raw-candidate bank at
emit_begin. Subsequent serial writes must reconstruct the exact gold result
without reading the old candidates. Clear is also applied at the ownership
transfer and at the first serial write; neither may leak a stale result.
The R7 production external reader is used with the legacy input bank tied0.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/cnn_stability_serial"
SIM = Path("E:/model/win64")
SOURCE = ROOT / "01_rtl/cnn_result_stabilizer.v"
ORIGIN_VECTORS = ROOT / "02_sim/cnn_stability/vectors.txt"
VECTORS = OUT / "vectors.txt"
BENCH = OUT / "tb_cnn_stability_serial.sv"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if not VECTORS.exists():
        VECTORS.write_bytes(ORIGIN_VECTORS.read_bytes())
    assert sha(VECTORS) == sha(ORIGIN_VECTORS), "frozen integer-gold vectors drifted"
    inputs = [SOURCE, BENCH, Path(__file__).resolve(), VECTORS, ORIGIN_VECTORS,
              ROOT / "tools/cnn_stability_reference.py"]
    before = {str(p): sha(p) for p in inputs}
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM/"LICENSE.TXT"), LM_LICENSE_FILE=str(SIM/"LICENSE.TXT"))
    commands = [
        ("vlib", [SIM/"vlib.exe", OUT/"work"]),
        ("compile", [SIM/"vlog.exe", "-sv", "-lint", "-work", OUT/"work", SOURCE, BENCH]),
        ("simulate", [SIM/"vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", OUT/"work", "tb_cnn_stability_serial", "-do",
                      "onerror {quit -code 1}; run -all; quit -f"]),
    ]
    for name, args in commands:
        proc = subprocess.run([str(a) for a in args], cwd=OUT, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        (OUT/(name+".log")).write_text(proc.stdout, encoding="utf-8")
        if proc.returncode or re.search(r"\*\* (?:Error|Fatal):", proc.stdout):
            raise RuntimeError(proc.stdout[-7000:])
    assert before == {str(p): sha(p) for p in inputs}, "test input changed during simulation"
    match = re.search(r"PASS SERIAL_GOLD checks=(\d+) vectors=(\d+) emitted=(\d+) bank_reuses=(\d+) clear_boundaries=(\d+) max_latency_cycles=(\d+)", proc.stdout)
    assert match, "missing simulation PASS"
    assert int(match[1]) == 2453 and int(match[2]) == 2485 and int(match[5]) == 2
    summary = {
        "status": "PASS", "production_candidate_applied": True, "hardware_status": "NOT_RUN",
        "production_modules": ["cnn_result_stabilizer"], "input_hashes": before,
        "gold_checks": int(match[1]), "vectors": int(match[2]), "serial_records": int(match[3]),
        "destructive_input_bank_reuses": int(match[4]), "clear_boundaries": int(match[5]),
        "max_latency_cycles": int(match[6]),
        "external_candidate_reader": 1,
        "legacy_input_bank_tied_zero": True,
        "evidence_hashes": {name+".log": sha(OUT/(name+".log")) for name, _ in commands},
        "active_source_unchanged_during_run": True,
        "gold_source": "Unchanged ordinary stabilizer integer-reference vectors",
        "limits": [
            "Kernel serial ownership/ordering/gold/clear checks; parent pipeline integration is a separate regression",
            "1170 replay observations overlap existing training/development; no independent accuracy claim",
            "No camera/DDR/HXA transaction, PCB arithmetic, place/route or real-board proof in this suite",
        ],
    }
    (OUT/"RESULTS.json").write_text(json.dumps(summary, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
