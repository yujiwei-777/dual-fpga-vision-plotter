"""Run PCB core and YUYV pipeline checks against the 50%-99% PCB ROMs."""
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
SOURCE = ROOT / "02_sim/new_capture_mix_vectors3_20261029"
TEST_SOURCE = ROOT / "02_sim/centered_50plus_inputs_20261029"
OUT = ROOT / "02_sim/new_capture_mix_regression_r5_20261029"
SIM = Path("E:/model/win64")
MODEL = ROOT / "model/experiments/conv4_4"
EXPECTED_MODEL = {
    "weights.mem": "9B844CB0B0844F8A72E59192B4F04D3C192B6C1A501DA1F3376CE6BF5354DDE6",
    "biases.mem": "45FAC7544E47F2CD73A5571A6136CB57A82CADD1B130057C8FCB0BC647E51232",
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
TESTS = {
    "tb_real_pcb_core": "BINARY_C4_4_GOLDEN_PASS samples=15 sat=0",
    "tb_real_pcb_pipeline": "PCB_RAW_PIPELINE_GOLDEN_PASS samples=9",
}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def run(name: str, command: list[str], env: dict[str, str]) -> str:
    result = subprocess.run(command, cwd=OUT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / f"{name}.log").write_text(result.stdout, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"{name} exited {result.returncode}:\n{result.stdout[-5000:]}")
    return result.stdout


def main() -> int:
    if OUT.exists():
        raise RuntimeError(f"Refusing to overwrite existing regression: {OUT}")
    if not (SIM / "LICENSE.TXT").is_file():
        raise RuntimeError(f"ModelSim license file is missing: {SIM / 'LICENSE.TXT'}")
    for name, expected in EXPECTED_MODEL.items():
        actual = sha(MODEL / name)
        if actual != expected:
            raise RuntimeError(f"Unexpected {name} hash: {actual}")

    OUT.mkdir(parents=True)
    vectors = OUT / "rtl_vectors"
    vectors.mkdir()
    for path in (SOURCE / "rtl_vectors").iterdir():
        if path.is_file():
            shutil.copy2(path, vectors / path.name)
    test_paths = []
    for name in TESTS:
        path = OUT / f"{name}.sv"
        source_path = TEST_SOURCE / f"{name}.sv"
        testbench = source_path.read_text(encoding="utf-8")
        testbench = testbench.replace(
            "model/selected/weights.mem", "../../model/experiments/conv4_4/weights.mem")
        testbench = testbench.replace(
            "model/selected/biases.mem", "../../model/experiments/conv4_4/biases.mem")
        path.write_text(testbench, encoding="utf-8")
        test_paths.append(path)

    inputs = [*RTL, *(TEST_SOURCE / f"{name}.sv" for name in TESTS), *test_paths, *MODEL.glob("*.mem"),
              *(path for path in vectors.iterdir() if path.is_file()), Path(__file__).resolve()]
    before = {str(path.resolve()): sha(path) for path in inputs}
    env = os.environ.copy()
    env["MGLS_LICENSE_FILE"] = str(SIM / "LICENSE.TXT")
    env["LM_LICENSE_FILE"] = str(SIM / "LICENSE.TXT")

    run("vlib", [str(SIM / "vlib.exe"), "work"], env)
    run("vlog", [str(SIM / "vlog.exe"), "-sv", "-work", "work",
                 *map(str, RTL), *map(str, test_paths)], env)

    results = {}
    for name, marker in TESTS.items():
        output = run(name, [str(SIM / "vsim.exe"), "-c", "-quiet", "-lib", "work", name,
                            "-do", "onerror {quit -code 1}; run -all; quit -f"], env)
        if marker not in output or "Errors: 0" not in output:
            raise RuntimeError(f"{name} failed pass-marker/error-count check")
        results[name] = {"status": "PASS", "marker": marker,
                         "sample_pass_count": output.count("_SAMPLE_PASS"),
                         "log_sha256": sha(OUT / f"{name}.log")}

    after = {str(path.resolve()): sha(path) for path in inputs}
    if before != after:
        raise RuntimeError("RTL, model, regression test or vector input changed during run")

    report = {
        "status": "PASS",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "project_root": str(ROOT),
        "model": {name: {"path": str((MODEL / name).resolve()), "sha256": before[str((MODEL / name).resolve())]}
                  for name in EXPECTED_MODEL},
        "tests": results,
        "input_hashes": before,
        "sample_basis": "50%-99% placement metrics are synthetic re-placements derived from three newly captured source boards; 9-frame RTL pipeline uses virtual camera frames. Not independent-board or real-board validation.",
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
        print("CENTERED_50PLUS_REGRESSION_FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
