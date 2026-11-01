"""Check whole-record payload/metadata RAM ownership in AREA32 and AREA24.

R6 writes complete payload and metadata words per track. Preserve the previous
payload before/on/after-write checks and add every-track metadata commit abort,
missing-update preload, uninitialized-word and fresh-confirmation checks.
R7 also runs all metadata boundaries through the production external-reader
mode with the legacy bank input tied to zero.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/cnn_stability_ram"
SIM = Path("E:/model/win64")
SOURCE = ROOT / "01_rtl/cnn_result_stabilizer.v"
BENCH = OUT / "tb_cnn_stability_ram.sv"
METADATA_BENCH = OUT / "tb_cnn_stability_metadata_atomic.sv"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    inputs = [SOURCE, BENCH, METADATA_BENCH, Path(__file__).resolve()]
    before = {str(p): sha(p) for p in inputs}
    env = os.environ.copy()
    license_file = SIM / "LICENSE.TXT"
    assert license_file.is_file(), "missing file-based ModelSim license"
    env.update(MGLS_LICENSE_FILE=str(license_file), LM_LICENSE_FILE=str(license_file))
    commands = [
        ("vlib", [SIM/"vlib.exe", OUT/"work"]),
        ("compile", [SIM/"vlog.exe", "-sv", "-lint", "-work", OUT/"work", SOURCE, BENCH, METADATA_BENCH]),
        ("simulate32", [SIM/"vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", OUT/"work", "tb_cnn_stability_ram", "-do",
                      "onerror {quit -code 1}; run -all; quit -f"]),
        ("simulate24", [SIM/"vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", OUT/"work", "tb_cnn_stability_ram", "-gAREA_BITS=24", "-do",
                      "onerror {quit -code 1}; run -all; quit -f"]),
        ("metadata32", [SIM/"vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", OUT/"work", "tb_cnn_stability_metadata_atomic", "-do",
                      "onerror {quit -code 1}; run -all; quit -f"]),
        ("metadata24", [SIM/"vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", OUT/"work", "tb_cnn_stability_metadata_atomic", "-gAREA_BITS=24", "-do",
                      "onerror {quit -code 1}; run -all; quit -f"]),
        ("metadata_external32", [SIM/"vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", OUT/"work", "tb_cnn_stability_metadata_atomic", "-gEXTERNAL_CANDIDATE_READER=1", "-do",
                      "onerror {quit -code 1}; run -all; quit -f"]),
        ("metadata_external24", [SIM/"vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", OUT/"work", "tb_cnn_stability_metadata_atomic", "-gAREA_BITS=24", "-gEXTERNAL_CANDIDATE_READER=1", "-do",
                      "onerror {quit -code 1}; run -all; quit -f"]),
    ]
    variants = {}
    metadata_variants = {}
    external_metadata_variants = {}
    for name, args in commands:
        proc = subprocess.run([str(a) for a in args], cwd=OUT, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        (OUT/(name+".log")).write_text(proc.stdout, encoding="utf-8")
        if proc.returncode or re.search(r"\*\* (?:Error|Fatal):", proc.stdout):
            raise RuntimeError(proc.stdout[-6500:])
        if name.startswith("simulate"):
            match = re.search(r"PASS WIDE_RAM_ATOMIC checks=(\d+) aborts=(\d+)", proc.stdout)
            assert match, "missing simulation PASS"
            assert (int(match[1]), int(match[2])) == (10, 5)
            variants[int(name.removeprefix("simulate"))] = {"checks": int(match[1]), "aborts": int(match[2])}
        if name.startswith("metadata"):
            match = re.search(r"PASS METADATA_ATOMIC area_bits=(\d+) boundaries=(\d+) fresh_checks=(\d+) publications=(\d+) max_latency_cycles=(\d+)", proc.stdout)
            assert match, "missing metadata atomic simulation PASS"
            bits = int(re.search(r"(\d+)$", name)[1])
            assert (int(match[1]), int(match[2]), int(match[3])) == (bits, 24, 147)
            mode = int(name.startswith("metadata_external"))
            assert "external_reader="+str(mode) in proc.stdout
            records = external_metadata_variants if mode else metadata_variants
            records[bits] = dict(zip(("abort_boundaries", "fresh_checks", "serial_publications", "max_latency_cycles"), map(int, match.groups()[1:])))
    assert before == {str(p): sha(p) for p in inputs}, "test input changed during simulation"
    summary = {
        "status": "PASS", "production_candidate_applied": True, "hardware_status": "NOT_RUN",
        "production_modules": ["cnn_result_stabilizer"], "input_hashes": before,
        "checks": sum(v["checks"] for v in variants.values()),
        "interrupted_write_boundaries": sum(v["aborts"] for v in variants.values()) + sum(v["abort_boundaries"] for v in metadata_variants.values()) + sum(v["abort_boundaries"] for v in external_metadata_variants.values()),
        "area_bits_variants": variants,
        "metadata_area_bits_variants": metadata_variants,
        "metadata_abort_boundaries": sum(v["abort_boundaries"] for v in metadata_variants.values()),
        "metadata_fresh_history_checks": sum(v["fresh_checks"] for v in metadata_variants.values()),
        "external_metadata_area_bits_variants": external_metadata_variants,
        "external_metadata_abort_boundaries": sum(v["abort_boundaries"] for v in external_metadata_variants.values()),
        "external_metadata_fresh_history_checks": sum(v["fresh_checks"] for v in external_metadata_variants.values()),
        "external_candidate_reader": [0, 1],
        "evidence_hashes": {name+".log": sha(OUT/(name+".log")) for name, _ in commands},
        "active_source_unchanged_during_run": True,
        "coverage": [
            "Uninitialized RAM cannot escape track validity gating",
            "Control reset retains payload memory contents",
            "Clear before, on and after an atomic payload write; reset on write; clear during read",
            "Abort masks RAM write and serial publication on the same edge",
            "Abort invalidates history; empty observation cannot emit retained RAM",
            "Fresh geometry and full 32-bit area overwrite stale payload",
            "All four tracks: allocation APPLY, matched APPLY and missing SELECT after synchronous metadata preload",
            "Both clear and reset suppress complete payload and metadata writes atomically",
            "All metadata fields overwritten on new allocation; three NEW observations required after every abort",
            "Valid serial publication has known exact class/confidence/geometry after RAM reuse",
            "Default reader ignores a poisoned external word; production external reader works with legacy bank input tied to zero",
        ],
        "limits": [
            "Kernel RAM lifecycle only; serial gold, pipeline, CNN and PCB are separate regressions",
            "RTL simulation does not prove physical RAM mapping; module-only TD probe is separate",
            "No real-board or accuracy claim",
        ],
    }
    (OUT/"RESULTS.json").write_text(json.dumps(summary, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
