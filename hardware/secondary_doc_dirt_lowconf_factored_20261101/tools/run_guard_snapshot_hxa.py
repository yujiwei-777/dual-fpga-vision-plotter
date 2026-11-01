"""Run guard -> snapshot -> both HXA endpoints, optionally comparing old guard."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "main/user_source/hdl_source/isp/uial2axis.v",
    "main/user_source/hdl_source/hx_pcb_presence.v",
    "main/user_source/hdl_source/hx_snapshot_service.v",
    "main/user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v",
    "shared/rtl/hxa_packet_codec.v", "shared/rtl/hxa_main_link.v", "shared/rtl/hxa_secondary_link.v",
    "main/02_sim/tb_guard_snapshot_hxa.sv",
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_case(model_bin, folder, guard, expected_failure=None, bad_first=False, secondary=None):
    folder.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(model_bin / "LICENSE.TXT"), LM_LICENSE_FILE=str(model_bin / "LICENSE.TXT"))
    sources = [guard] + [(secondary if secondary and path == "shared/rtl/hxa_secondary_link.v" else ROOT / path)
                         for path in SOURCES]
    hashes = {path.as_posix(): digest(path) for path in sources}
    library = folder / "work"

    def run(args, name):
        log_path = folder / name
        with log_path.open("w", encoding="utf-8") as log:
            result = subprocess.run([str(model_bin / args[0]), *args[1:]], cwd=folder, env=env,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=1200)
        return result.returncode, log_path.read_text(encoding="utf-8", errors="replace")

    if not library.exists():
        code, output = run(["vlib.exe", library.as_posix()], "vlib.log")
        if code:
            raise RuntimeError(output)
    code, output = run(["vlog.exe", "-sv", "-lint", "-work", library.as_posix(),
                        *[path.as_posix() for path in sources]], "vlog.log")
    if code or re.search(r"\*\*\s+(?:Error|Fatal):", output):
        raise RuntimeError(output)
    (folder / "run.do").write_text("onerror {quit -code 1}\nonbreak {quit -code 1}\nrun -all\nquit -f\n", encoding="ascii")
    code, output = run(["vsim.exe", "-c", "-lib", library.as_posix(), "tb_guard_snapshot_hxa",
                        "-gBAD_FIRST=" + str(int(bad_first)), "-do", "run.do"], "simulation.log")
    if expected_failure:
        if expected_failure not in output or "PASS guard snapshot" in output:
            raise RuntimeError("Expected failure marker absent: " + expected_failure + "\n" + output[-3500:])
        status = "EXPECTED_FAILURE"
    else:
        if code or re.search(r"\*\*\s+(?:Error|Fatal):", output) or "PASS guard snapshot HXA integration:" not in output:
            raise RuntimeError("Integrated regression failed:\n" + output[-3500:])
        status = "PASS"
    if any(digest(path) != hashes[path.as_posix()] for path in sources):
        raise RuntimeError("Production/test input changed during regression")
    result = {"status": status, "guard": guard.as_posix(), "source_sha256": hashes,
              "bad_first": bad_first, "expected_failure": expected_failure,
              "markers": [line for line in output.splitlines() if "CHECK " in line or "PASS " in line or (expected_failure and expected_failure in line)]}
    (folder / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{status}: {guard}", flush=True)
    print("\n".join(result["markers"]), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compare-old", type=Path)
    parser.add_argument("--check-known-lease-failure", action="store_true")
    parser.add_argument("--bad-first", action="store_true", help="Require automatic bad-frame recovery and a complete subsequent frame")
    parser.add_argument("--secondary-source", type=Path, help="Read-only source override for reproducing archived behavior")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/guard_snapshot_hxa")
    parser.add_argument("--modelsim-dir", type=Path, default=Path("E:/model/win64"))
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    results = {}
    secondary = args.secondary_source.resolve() if args.secondary_source else None
    if args.compare_old:
        results["old_guard"] = run_case(args.modelsim_dir.resolve(), folder / "before", args.compare_old.resolve(), "LEGAL_FRAME_CAPTURE_ERROR:", secondary=secondary)
    results["fixed_guard"] = run_case(args.modelsim_dir.resolve(), folder / "after", ROOT / "main/user_source/hdl_source/frame_guard.v", bad_first=args.bad_first, secondary=secondary)
    if args.check_known_lease_failure:
        results["bad_frame_lease"] = run_case(args.modelsim_dir.resolve(), folder / "bad_frame_lease", ROOT / "main/user_source/hdl_source/frame_guard.v", "LEASE_RECOVERY_BLOCKED:", True, secondary=secondary)
    status = "NORMAL_FRAME_PASS_BAD_FRAME_LEASE_BLOCKED" if args.check_known_lease_failure else "PASS"
    (folder / "summary.json").write_text(json.dumps({"status": status, "cases": results}, indent=2) + "\n", encoding="utf-8")
    print(f"Evidence: {folder / 'summary.json'}", flush=True)


if __name__ == "__main__":
    main()
