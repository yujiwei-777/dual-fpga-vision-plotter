"""Independent CNN named/coordinate/confidence report build and release runner.

prepare writes fresh local projects and freezes inputs, but never starts TD.
syn/route/readonly/bitgen start TD only when explicitly invoked.  The accepted
new-capture-mix baseline is read-only. All verification is recomputed for this run; copied
historical PASS files are not release evidence.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
NAME = "secondary_cnn_multibox"
BASE_NAME = "secondary_pcb_centered_new_capture_mix_20261029_hw"
BASE_RUN = "new_capture_mix_Runs_20261029_r2"
BASE_BIT = "artifacts/dual_fpga_secondary_20261029_pcb_new_capture_mix_diagnostic.bit"
BASE_SHA = "1B5CD153492CBA6D4A2783F55C3BBACE339E6360329D4C29AE322279C94BF2FE"
RUNS = "cnn_named_report_Runs_20261030"
TD = Path("E:/td/bin/td_commands_prompt.exe")
STEM = "dual_fpga_secondary_20261030_cnn_named_coords_conf_diagnostic"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest().upper()


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def save(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    imported = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(imported)
    return imported


def local(path):
    path = Path(path).resolve()
    require(path.is_relative_to(ROOT), "Build output escapes this independent project: " + str(path))
    require("work" not in [p.lower() for p in path.parts], "work/ is read-only")
    return path


def audit_command(action, run, *extra):
    command = [sys.executable, str(ROOT / "tools/td_release_audit.py"), action,
               "--root", str(ROOT), "--run", str(run), "--name", NAME,
               "--config", str(ROOT / "tools/release_audit_config.json")]
    for dependency in (Path(__file__).resolve(), ROOT / "_gen_project.py",
                       ROOT / "tools/review_remote_physical.py",
                       ROOT / "tools/accepted_fc8_run_full.tcl"):
        command += ["--extra", str(dependency)]
    return command + [str(x) for x in extra]


def execute(command, cwd=ROOT, log=None):
    print("RUN", subprocess.list2cmdline([str(x) for x in command]), flush=True)
    if log:
        require(not log.exists(), "Refusing to overwrite an existing invocation log: " + str(log))
        with log.open("w", encoding="utf-8") as stream:
            result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    else:
        result = subprocess.run(command, cwd=cwd)
    require(result.returncode == 0, "Command failed; inspect its log (exit " + str(result.returncode) + ")")


def baseline_check(base):
    require(base.resolve() != ROOT, "Cannot build in the read-only baseline")
    require(sha(base / BASE_BIT) == BASE_SHA, "Accepted new-capture-mix baseline bit hash differs")
    path = base / BASE_RUN / "syn_1/source_snapshot.json"
    frozen = load(path)
    require(Path(frozen["project_root"]).resolve() == base.resolve(), "Baseline snapshot belongs to another root")
    mismatches = []
    captured = {}
    for entry in frozen["files"]:
        source = Path(entry["path"])
        source = source if source.is_absolute() else base / source
        require(source.resolve().is_relative_to(base.resolve()), "Baseline snapshot escapes its root")
        relative = source.resolve().relative_to(base.resolve()).as_posix()
        require(relative not in captured, "Duplicate baseline snapshot input: " + relative)
        captured[relative] = entry["sha256"].upper()
        if not source.is_file() or sha(source) != entry["sha256"].upper():
            mismatches.append(str(source))
    require(captured, "Baseline snapshot has no captured inputs")
    require(not mismatches, "Baseline frozen input drift: " + "; ".join(mismatches))
    build_path = (base / BASE_BIT).with_name(Path(BASE_BIT).stem + "_BUILD.json")
    build = load(build_path)
    require(build["bit_sha256"] == BASE_SHA and build["routed_run"] == BASE_RUN,
            "Baseline delivery record does not bind the expected bit and run")
    require(build["evidence_sha256"]["source_snapshot"] == sha(path), "Baseline snapshot delivery hash differs")
    phy = base / BASE_RUN / "phy_1"
    require((phy / ".opt_route.end.f").is_file() and (phy / ".bitgen.end.f").is_file()
            and not list(phy.glob(".*.error.f")), "Baseline implementation did not complete cleanly")
    require(sha(phy / (NAME + ".bit")) == BASE_SHA, "Baseline bit does not match routed-run bitgen output")
    timing = (phy / (NAME + "_pr.timing")).read_text(encoding="utf-8-sig")
    area = (phy / (NAME + "_phy.area")).read_text(encoding="utf-8-sig")
    require("Routed" in timing and "Both (Slow and Fast)" in timing,
            "Baseline lacks routed two-corner timing evidence")
    timing_ns = {}
    for field, key in (("SWNS", "setup_wns"), ("STNS", "setup_tns"),
                       ("HWNS", "hold_wns"), ("HTNS", "hold_tns")):
        match = re.search(r"\b" + field + r":\s*([-+0-9.]+)ns", timing)
        require(match is not None, "Baseline timing metric missing: " + field)
        timing_ns[field] = float(match[1])
        require(timing_ns[field] >= 0 and (not field.endswith("TNS") or timing_ns[field] == 0),
                "Baseline timing acceptance failed: " + field)
        require(timing_ns[field] == build["timing_final_ns"][key], "Baseline delivery timing differs: " + field)
    resources = {}
    for kind, limit in (("slice", 95), ("eram", 90), ("dsp", 95)):
        match = re.search(r"^#" + kind + r"\s+(\d+)\s+out of\s+(\d+)", area, re.M)
        require(match is not None, "Baseline area metric missing: " + kind)
        used, total = map(int, match.groups())
        require(total > 0 and used * 100 < total * limit, "Baseline resource acceptance failed: " + kind)
        require((used, total) == (build["resources"][kind]["used"], build["resources"][kind]["total"]),
                "Baseline delivery resource counts differ: " + kind)
        resources[kind] = {"used": used, "total": total, "percent": used * 100 / total}
    status = (phy / "route_flow.status").read_text(encoding="utf-8-sig")
    require(re.search(r"Timing Mode\s*:\s*final", status)
            and re.search(r"^\s*route\s*\|\s*[1-9]\d*\s*\|", status, re.M),
            "Baseline route execution evidence missing")
    readonly_dir = base / "02_sim/new_capture_mix_r2_readonly"
    for file, key in (("readonly.timing", "readonly_timing"), ("readonly.ts", "readonly_timing_status")):
        require(sha(readonly_dir / file) == build["evidence_sha256"][key], "Baseline readonly delivery hash differs: " + file)
    readonly_timing = (readonly_dir / "readonly.ts").read_text(encoding="utf-8-sig")
    for field, expected in timing_ns.items():
        match = re.search(r"\b" + field + r":\s*([-+0-9.]+)ns", readonly_timing)
        require(match is not None and float(match[1]) == expected, "Baseline readonly timing differs: " + field)
    for file in ("readonly.area", "readonly.exceptions", "readonly.check", "readonly.clocks", "readonly.flow"):
        require((readonly_dir / file).is_file(), "Baseline readonly evidence missing: " + file)
    readonly_flow = (readonly_dir / "readonly.flow").read_text(encoding="utf-8-sig")
    require(re.search(r"^\s*import_db\s*\|\s*[1-9]\d*\s*\|", readonly_flow, re.M)
            and not re.search(r"^\s*(?:place|route|bitgen)\s*\|", readonly_flow, re.M),
            "Baseline readonly flow did not remain read-only")
    canonical = json.dumps(captured, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"bit": str(base / BASE_BIT), "bit_sha256": BASE_SHA,
            "snapshot": str(path), "snapshot_sha256": sha(path),
            "frozen_input_count": len(frozen["files"]),
            "baseline_source_manifest_sha256": hashlib.sha256(canonical).hexdigest().upper(),
            "baseline_manifest_format": "relative_path_hash_map",
            "delivery_record_sha256": sha(build_path), "timing_ns": timing_ns, "resources": resources,
            "routed_timing_sha256": sha(phy / (NAME + "_pr.timing")),
            "routed_area_sha256": sha(phy / (NAME + "_phy.area")),
            "readonly_timing_sha256": sha(readonly_dir / "readonly.timing")}


def write_project(gen, tree, target, suffix):
    # Match the accepted fc8_nostage run.  TD resolves ROM paths relative to
    # active HDL sources.  Run-local old model copies could shadow these inputs.
    out = copy.deepcopy(tree)
    out.set("Path", target.as_posix())
    for entry in out.findall("Source_Files/*/File"):
        entry.set("Path", gen.rel(Path(entry.attrib["Path"]), target))
    ET.indent(out)
    payload = ET.tostring(out, encoding="unicode").replace("_TD_DOUBLE_COLON_", "::")
    (target / f"{NAME}.{suffix}").write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + payload + "\n", encoding="utf-8")


def prepare(args, runs, base):
    require(not runs.exists(), "Run directory must be new; never replace an old build")
    provenance = baseline_check(base)
    gen = module(ROOT / "_gen_project.py", "vector_generator")
    # Source-only variants intentionally omit td_project*/ databases.  Retain
    # the accepted editable flow locally; tools/ has the same relative depth
    # as the original td_project_key1_build/ for its ../04_pin source hooks.
    template = ROOT / "tools/accepted_fc8_run_full.tcl"
    accepted_template = base / "tools/accepted_fc8_run_full.tcl"
    if not accepted_template.is_file():
        accepted_template = base / "td_project_key1_build/run_full.tcl"
    require(accepted_template.is_file(), "Accepted editable TD flow is missing")
    if template.exists():
        require(sha(template) == sha(accepted_template), "Local editable TD flow differs from baseline")
    else:
        shutil.copy2(accepted_template, template)
    gen.RUN_FULL = template
    tree = gen.load_project()
    for phase, start, end, parent in (("syn_1", "read_design", "opt_gate", None),
                                      ("phy_1", "opt_place", "opt_route", "../syn_1")):
        target = runs / phase
        target.mkdir(parents=True)
        for suffix in ("al", "prj"):
            write_project(gen, tree, target, suffix)
        flow = gen.exported_flow(target, start, end, phase, parent)
        if phase == "phy_1":
            flow, count = re.subn(r"(?m)^(\s*)place\s*$", r"\1set_param place seed " + str(args.seed) + r"\n\1place", flow)
            require(count == 1, "Expected one editable place invocation for the explicit seed")
        (target / "run.tcl").write_text(flow, encoding="utf-8")
        header = flow.split("# This is default flow script", 1)[0]
        (target / "settings.cfg").write_text("\n".join(line for line in header.splitlines() if line.startswith("set ")) + "\n", encoding="utf-8")
        if phase == "phy_1":
            (target / "run_bitgen.tcl").write_text(gen.exported_flow(target, "bitgen", "bitgen", phase), encoding="utf-8")
    execute(audit_command("snapshot", runs / "syn_1"))
    execute(audit_command("snapshot", runs / "phy_1"))
    freeze = load(runs / "syn_1/source_snapshot.json")
    # Freeze flow scripts too; changing a seed/constraint invocation requires
    # a new run rather than silently retargeting a completed source snapshot.
    flows = {p.relative_to(ROOT).as_posix(): sha(p) for phase in ("syn_1", "phy_1")
             for p in (runs / phase / "run.tcl", runs / phase / "settings.cfg")}
    flows[(runs / "phy_1/run_bitgen.tcl").relative_to(ROOT).as_posix()] = sha(runs / "phy_1/run_bitgen.tcl")
    save(runs / "BUILD_PLAN.json", {"root": str(ROOT), "runs": str(runs), "baseline": str(base),
         "created_utc": datetime.now(timezone.utc).isoformat(), "seed": args.seed,
         "source_manifest_sha256": freeze["manifest_sha256"], "baseline_provenance": provenance,
         "flow_sha256": flows, "hardware_validation": "NOT_RUN"})
    print(json.dumps({"status": "PREPARED_NOT_STARTED", "runs": str(runs),
                      "source_manifest_sha256": freeze["manifest_sha256"], "seed": args.seed}, indent=2))


def validate_plan(runs, base):
    plan = load(runs / "BUILD_PLAN.json")
    require(Path(plan["root"]).resolve() == ROOT and Path(plan["runs"]).resolve() == runs,
            "Build plan belongs to another independent project/run")
    require(Path(plan["baseline"]).resolve() == base, "Build baseline differs from prepared plan")
    for relative, expected in plan["flow_sha256"].items():
        path = local(ROOT / relative)
        require(sha(path) == expected, "Frozen flow script changed: " + relative)
    frozen = load(runs / "syn_1/source_snapshot.json")
    require(frozen["manifest_sha256"] == plan["source_manifest_sha256"], "Pre-build freeze changed")
    for entry in frozen["files"]:
        source = Path(entry["path"])
        path = local(source if source.is_absolute() else ROOT / source)
        require(path.is_file() and sha(path) == entry["sha256"].upper(), "Frozen input changed: " + str(path))
    return plan


def routed_gate(runs, base):
    syn, phy = runs / "syn_1", runs / "phy_1"
    execute(audit_command("gate", phy, "--syn-run", syn, "--snapshot", syn / "source_snapshot.json",
                          "--log", syn / "td_console.log", "--log", phy / "td_console.log"))
    reviewer = module(ROOT / "tools/review_remote_physical.py", "vector_physical_review")
    reviewer.ROOT, reviewer.BASE, reviewer.BASE_RUN = ROOT, base, base / BASE_RUN
    output = local(ROOT / "02_sim" / (runs.name + "_physical_review"))
    original = sys.argv
    try:
        sys.argv = [str(ROOT / "tools/review_remote_physical.py"), "--runs", str(runs), "--output", str(output)]
        require(reviewer.main() == 0, "Current CDC/FIFO/DDR/DRC physical review failed")
    finally:
        sys.argv = original
    return output


def readonly(args, runs):
    phy = runs / "phy_1"
    out = local(ROOT / "02_sim" / (runs.name + "_readonly"))
    require(not out.exists(), "Read-only evidence directory must be new")
    execute(audit_command("reimport-template", phy, "--audit-dir", out))
    execute([str(args.td), (out / "readonly_reimport.tcl").as_posix()],
            cwd=phy, log=out / "td_console.log")
    execute(audit_command("verify-readonly", phy, "--audit-dir", out, "--log", out / "td_console.log"))
    return out


def regression_gate(files, runs):
    require(files, "Supply fresh --regression RESULTS.json evidence before bitgen")
    results = {}
    for file in files:
        file = local(file)
        require(file.is_relative_to(ROOT / "02_sim"), "Regression evidence must belong to current 02_sim")
        data = load(file)
        require(data.get("status") == "PASS" or data.get("passed") is True, "Regression failed: " + str(file))
        inputs = data.get("input_hashes") or data.get("inputs_sha256")
        require(isinstance(inputs, dict) and inputs, "Regression needs current input hashes: " + str(file))
        latest_input_ns = 0
        for value, expected in inputs.items():
            path = Path(value)
            path = local(path if path.is_absolute() else ROOT / path)
            require(path.is_file() and sha(path) == str(expected).upper(), "Regression input drift: " + str(path))
            latest_input_ns = max(latest_input_ns, path.stat().st_mtime_ns)
        require(file.stat().st_mtime_ns >= latest_input_ns,
                "Regression report predates its current source inputs: " + str(file))
        results[file.relative_to(ROOT).as_posix()] = sha(file)
    return results


def bitgen(args, runs, base):
    physical = routed_gate(runs, base)
    readonly_dir = local(ROOT / "02_sim" / (runs.name + "_readonly"))
    execute(audit_command("verify-readonly", runs / "phy_1", "--audit-dir", readonly_dir,
                          "--log", readonly_dir / "td_console.log"))
    regressions = regression_gate(args.regression, runs)
    phy = runs / "phy_1"
    require(not (phy / ".bitgen.begin.f").exists(), "Bitgen already started; preserve its original result")
    execute([str(args.td), "run_bitgen.tcl"], cwd=phy, log=phy / "bitgen_console.log")
    require((phy / ".bitgen.end.f").is_file() and not list(phy.glob(".*.error.f")), "Bitgen did not complete cleanly")
    bit = phy / (NAME + ".bit")
    require(bit.is_file() and bit.stat().st_size > 0, "No new bitstream")
    artifacts = local(ROOT / "artifacts")
    artifacts.mkdir(exist_ok=True)
    target = local(artifacts / (args.stem + ".bit"))
    require(not target.exists(), "Refusing to overwrite a release artifact")
    shutil.copy2(bit, target)
    require(sha(target) == sha(bit), "Release copy hash mismatch")
    plan = load(runs / "BUILD_PLAN.json")
    gate = load(phy / "release_gate.json")
    save(artifacts / (args.stem + "_BUILD.json"), {"status": "DIAGNOSTIC_NOT_RUN",
         "hardware_validation": "NOT_RUN", "bit": target.name, "bit_sha256": sha(bit),
         "runs": str(runs), "baseline_bit_sha256": BASE_SHA,
         "source_manifest_sha256": plan["source_manifest_sha256"],
         "timing_ns": gate["timing_ns"], "resources": gate["resources"],
         "regression_evidence_sha256": regressions,
         "physical_review_sha256": sha(physical / "FINAL_PHYSICAL_REVIEW.json"),
         "readonly_verification_sha256": sha(readonly_dir / "readonly_verification.json"),
         "completion_semantics": "Final G-code ok confirms controller acceptance, not mechanical Idle"})
    print(json.dumps({"status": "DIAGNOSTIC_NOT_RUN", "bit": str(target), "sha256": sha(target)}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inspect", "prepare", "syn", "route", "gate", "readonly", "bitgen"))
    parser.add_argument("--runs", type=Path, default=Path(RUNS))
    parser.add_argument("--baseline", type=Path, default=ROOT.parent / BASE_NAME)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--td", type=Path, default=TD)
    parser.add_argument("--regression", type=Path, action="append")
    parser.add_argument("--stem", default=STEM)
    args = parser.parse_args()
    require("work" not in [p.lower() for p in ROOT.parts] and ROOT.name != BASE_NAME, "Only an independent variant can run this tool")
    runs = local(args.runs if args.runs.is_absolute() else ROOT / args.runs)
    base = args.baseline.resolve()
    if args.action == "inspect":
        print(json.dumps(baseline_check(base), indent=2))
        return 0
    if args.action == "prepare":
        prepare(args, runs, base)
        return 0
    validate_plan(runs, base)
    if args.action in ("syn", "route"):
        phase = "syn_1" if args.action == "syn" else "phy_1"
        run = runs / phase
        if phase == "phy_1":
            require((runs / "syn_1/.opt_gate.end.f").is_file(), "Synthesis did not complete")
        require(not (run / "td_console.log").exists(), "Preserve completed/failed invocations; prepare a new run")
        execute([str(args.td), "run.tcl"], cwd=run, log=run / "td_console.log")
        require((run / (".opt_gate.end.f" if phase == "syn_1" else ".opt_route.end.f")).is_file()
                and not list(run.glob(".*.error.f")), "TD process returned without completing its flow")
    elif args.action == "gate":
        routed_gate(runs, base)
    elif args.action == "readonly":
        routed_gate(runs, base)
        readonly(args, runs)
    elif args.action == "bitgen":
        bitgen(args, runs, base)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print("BUILD_VECTOR_RELEASE_FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
