"""Run one R11 fixed-grid build stage with durable evidence, no retries and no UI window."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SUITES = ["cnn_stability", "cnn_stability_serial", "cnn_stability_ram",
          "cnn_stability_area24", "cnn_stability_pipeline", "cnn_stability_grid", "cnn_fixed_grid_mapping", "cnn_named_top",
          "cnn_named_pcb", "cnn_named_report", "cnn_stability_core"]


def now():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builder", required=True)
    parser.add_argument("--runs", required=True)
    parser.add_argument("--action", choices=["syn", "route", "gate", "readonly", "bitgen"], required=True)
    args = parser.parse_args()
    builder = (ROOT / args.builder).resolve()
    runs = (ROOT / args.runs).resolve()
    if builder != (ROOT / "tools/build_cnn_stability_r11.py").resolve() or not builder.is_file():
        raise RuntimeError("R11 runner requires its exact reviewed R11 builder")
    if runs != (ROOT / "cnn_stability_r11_fixed_grid_Runs_20261031").resolve() or "work" in [v.lower() for v in runs.parts]:
        raise RuntimeError("R11 runner is locked to its independent R11 run")
    if not (runs / "BUILD_PLAN.json").is_file():
        raise RuntimeError("R11 build plan is required before any stage")
    status = runs / ("DETACHED_" + args.action.upper() + ".json")
    log = runs / ("detached_" + args.action + ".log")
    if status.exists() or log.exists():
        raise RuntimeError("Stage evidence must never be overwritten")
    command = [sys.executable, str(builder), args.action, "--runs", str(runs)]
    for suite in SUITES:
        command += ["--regression", str(ROOT / "02_sim" / suite / "RESULTS.json")]
    result = {"status": "RUNNING", "started_utc": now(), "pid": os.getpid(),
              "action": args.action, "command": command, "log": str(log), "exit_code": None}
    status.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    try:
        with log.open("x", encoding="utf-8") as stream:
            completed = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                                       stdout=stream, stderr=subprocess.STDOUT)
        result.update(status="PASS" if completed.returncode == 0 else "FAILED", exit_code=completed.returncode)
    except BaseException as error:
        result.update(status="RUNNER_ERROR", error=repr(error))
    result["completed_utc"] = now()
    status.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
