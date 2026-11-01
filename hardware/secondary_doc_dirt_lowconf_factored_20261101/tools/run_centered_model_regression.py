"""Run PCB core and full YUYV-pipeline regressions for the centered model.

The output directory is unique and fail-closed so previous simulation evidence
is never replaced. RESULTS.json is suitable for the release runner's
hash-bound regression gate.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SIM_SOURCE = ROOT / "02_sim/centered_model_adoption_20261029"
VECTOR_SOURCE = SIM_SOURCE / "rtl_vectors"
OUT = ROOT / "02_sim/centered_model_release_regression_r1_20261029"
SIM = Path("E:/model/win64")
MODEL = ROOT / "model/experiments/conv4_4"
EXPECTED = {
    "weights.mem": "7EA53F804E7A4BB96A31E44E7D6B2968B6FE028BD793715B575CFF95CB12A126",
    "biases.mem": "B3C0DDEA018C58919626A72CE9C7F9E75EB5BAC1486E34ABD2730B4403BBF134",
}
RTL = [
    ROOT / "01_rtl/vision_color_stats.v",
    ROOT / "01_rtl/edge_roi_ccl.v",
    ROOT / "01_rtl/vision_pixel_reader.v",
    ROOT / "01_rtl/vision_ccl.v",
    ROOT / "01_rtl/pcb_defect_cluster.v",
    ROOT / "01_rtl/vision_workspace.v",
    ROOT / "01_rtl/vision_shared_mac.v",
    ROOT / "01_rtl/pcb_fullboard_spatial96.v",
    ROOT / "01_rtl/vision_pipeline.v",
    ROOT / "01_rtl/cnn_core.v",
]
TESTS = ["tb_real_pcb_core", "tb_real_pcb_pipeline"]
MARKERS = {
    "tb_real_pcb_core": "BINARY_C4_4_GOLDEN_PASS samples=15 sat=0",
    "tb_real_pcb_pipeline": "PCB_RAW_PIPELINE_GOLDEN_PASS samples=9",
}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def run(name: str, command: list[str], cwd: Path, env: dict[str, str]) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / f"{name}.log").write_text(result.stdout, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"{name} exited {result.returncode}:\n{result.stdout[-5000:]}")
    return result.stdout


def main() -> int:
    if OUT.exists():
        raise RuntimeError(f"Refusing to overwrite existing regression output: {OUT}")
    if not (SIM / "LICENSE.TXT").is_file():
        raise RuntimeError(f"ModelSim license file is missing: {SIM / 'LICENSE.TXT'}")
    for name, expected in EXPECTED.items():
        actual = sha(MODEL / name)
        if actual != expected:
            raise RuntimeError(f"Unexpected centered model {name}: {actual}")

    OUT.mkdir(parents=True)
    vectors = OUT / "rtl_vectors"
    vectors.mkdir()
    for path in VECTOR_SOURCE.iterdir():
        if path.is_file():
            shutil.copy2(path, vectors / path.name)
    tests = []
    for name in TESTS:
        target = OUT / f"{name}.sv"
        shutil.copy2(SIM_SOURCE / f"{name}.sv", target)
        tests.append(target)

    inputs = [*RTL, *(SIM_SOURCE / f"{name}.sv" for name in TESTS),
              MODEL / "weights.mem", MODEL / "biases.mem",
              *(p for p in VECTOR_SOURCE.iterdir() if p.is_file())]
    before = {str(path.resolve()): sha(path) for path in inputs}
    env = os.environ.copy()
    env["MGLS_LICENSE_FILE"] = str(SIM / "LICENSE.TXT")
    env["LM_LICENSE_FILE"] = str(SIM / "LICENSE.TXT")

    run("vlib", [str(SIM / "vlib.exe"), "work"], OUT, env)
    run("vlog", [str(SIM / "vlog.exe"), "-sv", "-work", "work",
                 *map(str, RTL), *map(str, tests)], OUT, env)

    results = {}
    for test in TESTS:
        output = run(test, [str(SIM / "vsim.exe"), "-c", "-quiet", "-lib", "work", test,
                            "-do", "onerror {quit -code 1}; run -all; quit -f"], OUT, env)
        marker = MARKERS[test]
        if marker not in output or "Errors: 0" not in output:
            raise RuntimeError(f"{test} did not produce its clean pass marker")
        results[test] = {
            "status": "PASS",
            "marker": marker,
            "sample_pass_count": output.count("_SAMPLE_PASS"),
            "log_sha256": sha(OUT / f"{test}.log"),
        }

    after = {str(path.resolve()): sha(path) for path in inputs}
    if before != after:
        raise RuntimeError("RTL, model or vector inputs changed during simulation")

    report = {
        "status": "PASS",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "project_root": str(ROOT),
        "model": {name: {"path": str((MODEL / name).resolve()), "sha256": before[str((MODEL / name).resolve())]}
                  for name in EXPECTED},
        "tests": results,
        "input_hashes": before,
        "sample_basis": "Existing real PCB captures with virtual centered placements plus synthetic controls; not independent real-world accuracy evidence.",
        "hardware_status": "NOT_RUN",
    }
    report_path = OUT / "RESULTS.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "results": str(report_path), "tests": results}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print("CENTERED_MODEL_REGRESSION_FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
