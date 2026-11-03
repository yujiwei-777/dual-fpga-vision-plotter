"""Current-bound ordinary publication integration; default prepares only.

Real production vision_pipeline and packed stabilizer, with controlled CCL/CNN
leaves. Reuses the prior pipeline integration harness technique. This checks
publication/control coupling, not classifier arithmetic, real CCL, DDR or top
network/cache behavior. Exact-SHA prior kernel differential PASS is reused.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BENCH = ROOT / "reports/pose7/tb_cnn_publication_integration.sv"
OUT = ROOT / "reports/pose7/cnn_publication_integration"
EXPECTED = {
    "01_rtl/vision_pipeline.v": "BB0516AC5B8C112AA69010E8F2B44E63F3C24F46D6772072A5845F5EAC26A2BB",
    "01_rtl/cnn_result_stabilizer.v": "5413EDA970B9E68830977F372053EF8AEC920EA610331F17D56A006C29488D33",
}
LEAVES = {
    "vision_color_stats": "01_rtl/vision_color_stats.v",
    "edge_roi_ccl_shared_pcb_candidate": "01_rtl/edge_roi_ccl_shared_pcb_candidate.v",
    "cnn_core": "01_rtl/cnn_core.v",
    "pcb_pose7_core": "01_rtl/pcb_pose7_core.v",
    "vision_shared_mac": "01_rtl/vision_shared_mac.v",
    "vision_workspace_goodonly": "01_rtl/vision_workspace_goodonly.v",
}
PRIOR = Path("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_goodonly_auto_affine6_20261102/reports/stabilizer_packed_regression_prepared/run_20261102T051056_497275Z/RESULTS.json")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Run only when the exclusive simulator owner dispatches this queue item")
    parser.add_argument("--sim-dir", type=Path, default=Path("E:/model/win64"))
    args = parser.parse_args()
    for rel, digest in EXPECTED.items():
        if sha(ROOT / rel) != digest:
            raise RuntimeError("Frozen source drift: " + rel)
    prior = json.loads(PRIOR.read_text(encoding="utf-8-sig"))
    if prior["status"] != "PASS" or prior["compiled_sha256"][r"rtl\cnn_result_stabilizer.v"] != EXPECTED["01_rtl/cnn_result_stabilizer.v"]:
        raise RuntimeError("Prior kernel evidence no longer matches current stabilizer")
    OUT.mkdir(parents=True, exist_ok=True)
    declarations = []
    for name, rel in LEAVES.items():
        body = re.sub(r"/\*.*?\*/|//[^\n]*", "", (ROOT / rel).read_text(encoding="utf-8-sig"), flags=re.S)
        match = re.search(r"\bmodule\s+" + name + r"\b", body)
        if not match:
            raise RuntimeError("Missing leaf declaration: " + name)
        declarations.append(body[match.start():body.index(";", match.end()) + 1] + "\nendmodule\n")
    stub = OUT / "controlled_leaf_interfaces.sv"
    stub.write_text("// Test-only interfaces. Never synthesis inputs.\n" + "\n".join(declarations), encoding="utf-8")
    paths = [*(ROOT / rel for rel in EXPECTED), *(ROOT / rel for rel in LEAVES.values()), BENCH, stub, Path(__file__).resolve()]
    inputs = {str(p): sha(p) for p in paths}
    plan = {"status": "PREPARED_NOT_RUN", "scope": __doc__.strip(), "source_root": str(ROOT),
            "source_hashes": inputs, "production_specialization": "PCB_GOODONLY_AUTO1/CNN_LOWCONF_OUTPUT1/EXTERNAL_READER1/LOCAL_CNN1/PCB_ENABLE1/SHARED_WORKSPACE1",
            "prior_kernel_results": str(PRIOR), "prior_kernel_results_sha256": sha(PRIOR),
            "prior_kernel_complete_observations": 288, "prior_kernel_clear_boundaries": 38,
            "coverage": ["first current bbox/class/actual confidence/uncertain", "third same-class confirms", "HOLD2 current bbox/actual confidence", "soft low and zero margin", "no target no ghost", "hard reject branch", "malformed native bounds/order", "clear before and after raw-bank reuse", "clear at publish/completion", "cancel and config clear"],
            "hardware": "NOT_RUN", "td": "NOT_RUN"}
    if not args.run:
        (OUT / "PREPARED.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"status": plan["status"], "plan": str(OUT / "PREPARED.json"), "run": f"python {Path(__file__).resolve()} --run"}, indent=2))
        return
    sim = args.sim_dir
    if not (sim / "LICENSE.TXT").is_file():
        raise RuntimeError("File-based ModelSim license missing")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    run = OUT / ("run_" + stamp)
    run.mkdir()
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(sim / "LICENSE.TXT"), LM_LICENSE_FILE=str(sim / "LICENSE.TXT"))
    library = run / "simlib"
    commands = [("vlib", [sim / "vlib.exe", library]),
                ("compile", [sim / "vlog.exe", "-sv", "-lint", "-work", library, stub, *(ROOT / rel for rel in EXPECTED), BENCH]),
                ("simulate", [sim / "vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110", "-lib", library,
                              "tb_cnn_publication_integration", "-do", "onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -f"])]
    results = {**plan, "status": "RUNNING", "started_utc": stamp, "commands": []}
    summary = run / "RESULTS.json"
    try:
        for name, argv in commands:
            results["commands"].append({"name": name, "argv": list(map(str, argv))})
            summary.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
            process = subprocess.run(list(map(str, argv)), cwd=run, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
            log = run / (name + ".log")
            log.write_text(process.stdout, encoding="utf-8")
            if process.returncode or re.search(r"\*\*\s+(?:Error|Fatal):", process.stdout):
                raise RuntimeError(f"{name} failed; inspect {log}")
            if name == "simulate":
                match = re.search(r"PASS CNN_PUBLICATION_INTEGRATION checks=(\d+) jobs=(\d+) starts=(\d+)", process.stdout)
                if not match or int(match[1]) < 100 or int(match[2]) < 25:
                    raise RuntimeError("Missing/incomplete publication integration PASS marker")
                results["checks"], results["jobs"], results["stabilizer_starts"] = map(int, match.groups())
        if inputs != {str(p): sha(p) for p in paths}:
            raise RuntimeError("Input drift during simulation")
        results["status"] = "PASS"
    except Exception as error:
        results["status"] = "FAILED"
        results["error"] = str(error)
        raise
    finally:
        results["logs_sha256"] = {p.name: sha(p) for p in run.glob("*.log")}
        summary.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": results["status"], "results": str(summary)}, indent=2))

if __name__ == "__main__":
    main()
