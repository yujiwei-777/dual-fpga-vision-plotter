"""Serial ModelSim run; requires the existing valid file license."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from display_tone_reference import generate


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    generate(root)
    sim = root / "02_sim" / "display_tone"
    reports = root / "reports"
    rtl_rel = Path("01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v")
    baseline = root.parent / "main_pcb_auto_compat_20261101" / rtl_rel
    frozen = re.sub(r"\bmodule\s+display_tone_96\b", "module display_tone_96_frozen",
                    baseline.read_text(encoding="utf-8"), count=1)
    (sim / "display_tone_96_frozen.v").write_text(frozen, encoding="utf-8")
    env = os.environ.copy()
    license_file = Path(r"E:\model\win64\LICENSE.TXT")
    if not license_file.is_file():
        raise RuntimeError(f"File license does not exist: {license_file}")
    env["MGLS_LICENSE_FILE"] = str(license_file)
    env["LM_LICENSE_FILE"] = str(license_file)
    tool_dir = Path(r"E:\model\win64")
    commands = [
        [str(tool_dir / "vlib.exe"), "tone_work"],
        [str(tool_dir / "vlog.exe"), "-sv", "-work", "tone_work",
         str(root / rtl_rel), "display_tone_96_frozen.v", "tb_display_tone_regression.sv"],
        [str(tool_dir / "vsim.exe"), "-batch", "tone_work.tb_display_tone_regression",
         "-do", "onerror {quit -code 1}; run -all; quit -code 0"],
    ]
    outputs = []
    success = False
    try:
        for command in commands:
            result = subprocess.run(command, cwd=sim, env=env, capture_output=True,
                                    text=True, errors="replace", timeout=120)
            outputs.append("COMMAND: " + subprocess.list2cmdline(command) + "\n" +
                           result.stdout + result.stderr + f"\nEXIT: {result.returncode}\n")
            if result.returncode:
                raise RuntimeError(f"ModelSim command failed with exit {result.returncode}")
        log = "\n".join(outputs)
        if "PASS display_tone frozen_tap_cycle_compare" not in log:
            raise RuntimeError("Simulation did not report PASS")
        if re.search(r"\*\* (?:Error|Fatal):", log):
            raise RuntimeError("ModelSim log contains an error")
        success = True
    finally:
        log = "\n".join(outputs)
        (reports / "display_tone_rtl_regression.log").write_text(log, encoding="utf-8")
        summary = {
            "status": "PASS" if success else "FAIL",
            "baseline_fixed_tap_cycle_equivalence": success,
            "integer_reference_data_and_markers": success,
            "regression": "all256 channel values, 12 lanes, raw/tone modes, isolated SOF, mode latching, stalls, reset",
            "pass_line": next((line for line in log.splitlines() if "PASS display_tone" in line), None),
            "rtl_sha256": hashlib.sha256((root / rtl_rel).read_bytes()).hexdigest().upper(),
            "tb_sha256": hashlib.sha256((sim / "tb_display_tone_regression.sv").read_bytes()).hexdigest().upper(),
            "license_mode": "existing file license, both process variables explicitly set",
        }
        (reports / "display_tone_rtl_regression.json").write_text(
            json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
