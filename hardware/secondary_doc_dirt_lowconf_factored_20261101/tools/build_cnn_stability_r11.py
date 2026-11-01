"""Independent CNN stability build; fresh regression, route and readonly gates.

prepare only writes local source snapshots/projects. syn and route are separate
explicit actions. Negative synthesis WNS does not block route; strict resource
limits still apply. Only a fully accepted routed database can generate a bit.
"""
from __future__ import annotations

from collections import Counter
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
BASE = ROOT.parent / "secondary_cnn_named_coords_conf_20261030"
BASE_RUN = "cnn_center_report_Runs_20261030"
BASE_STEM = "dual_fpga_secondary_20261030_cnn_named_coords_conf_diagnostic"
BASE_SHA = "A216CA0717A7C23365EB7EE06E47746D8022FFA634D28C97C6F47476B1DA98E6"
BASE_SNAPSHOT_SHA = "5846BDB74E42117C062D310930EDAEDD0C26588746A12ADF99B3CD1FEBC3704D"
RUNS = "cnn_stability_r11_fixed_grid_Runs_20261031"
STEM = "dual_fpga_secondary_20261031_cnn_target_stability_diagnostic"
TD = Path("E:/td/bin/td_commands_prompt.exe")
ALLOWED_RTL = {"01_rtl/vision_pipeline.v", "01_rtl/secondary_top.v"}
NEW_RTL = "01_rtl/cnn_result_stabilizer.v"
REQUIRED_SYN_TESTS = {"cnn_stability", "cnn_stability_serial", "cnn_stability_ram", "cnn_stability_area24", "cnn_stability_pipeline", "cnn_stability_grid", "cnn_fixed_grid_mapping", "cnn_named_top", "cnn_named_pcb"}
REQUIRED_BIT_TESTS = REQUIRED_SYN_TESTS | {"cnn_named_report", "cnn_stability_core"}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest().upper()


def read(path):
    return Path(path).read_text(encoding="utf-8-sig", errors="replace")


def load(path):
    return json.loads(read(path))


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def local(path):
    path = Path(path)
    path = (path if path.is_absolute() else ROOT / path).resolve()
    require(path.is_relative_to(ROOT) and "work" not in [p.lower() for p in path.parts],
            "Output/input escapes the independent project: " + str(path))
    return path


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    imported = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(imported)
    return imported


def execute(command, cwd=ROOT, log=None):
    print("RUN", subprocess.list2cmdline([str(x) for x in command]), flush=True)
    if log:
        require(not log.exists(), "Never overwrite invocation evidence: " + str(log))
        with log.open("w", encoding="utf-8") as stream:
            result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    else:
        result = subprocess.run(command, cwd=cwd)
    require(result.returncode == 0, "Command failed (exit " + str(result.returncode) + "); inspect its log")


def audit_command(action, run, *extra):
    command = [sys.executable, str(ROOT / "tools/td_release_audit.py"), action,
               "--root", str(ROOT), "--run", str(run), "--name", NAME,
               "--config", str(ROOT / "tools/release_audit_config.json")]
    for path in (Path(__file__).resolve(), ROOT / "_gen_project.py", ROOT / "secondary_cnn_multibox.al",
                 ROOT / "lint_full.f", ROOT / "tools/td_release_audit.py", ROOT / "tools/accepted_fc8_run_full.tcl"):
        command += ["--extra", str(path)]
    return command + [str(x) for x in extra]


def timing_metrics(path):
    text, values = read(path), {}
    for key in ("SWNS", "STNS", "HWNS", "HTNS"):
        match = re.search(r"\b" + key + r":\s*([-+0-9.]+)ns", text)
        require(match is not None, "Missing timing metric " + key + ": " + str(path))
        values[key] = float(match[1])
    return values


def area_metrics(path):
    text, values = read(path), {}
    for kind, limit in (("slice", 95), ("eram", 90), ("dsp", 95)):
        match = re.search(r"^#" + kind + r"\*?\s+(\d+)\s+out of\s+(\d+)", text, re.M)
        require(match is not None, "Missing area metric " + kind + ": " + str(path))
        used, total = map(int, match.groups())
        require(total and used * 100 < total * limit, "Resource gate failed: " + kind)
        values[kind] = {"used": used, "total": total, "percent": used * 100 / total,
                        "strict_limit_percent": limit}
    return values


def baseline_check():
    require(BASE.resolve() != ROOT and "work" not in [p.lower() for p in BASE.parts], "Unsafe baseline root")
    bit = BASE / "artifacts" / (BASE_STEM + ".bit")
    snapshot_path = BASE / BASE_RUN / "syn_1/source_snapshot.json"
    require(sha(bit) == BASE_SHA, "Control baseline bit differs")
    require(sha(snapshot_path) == BASE_SNAPSHOT_SHA, "Control baseline source snapshot differs")
    snapshot = load(snapshot_path)
    require(Path(snapshot["project_root"]).resolve() == BASE.resolve(), "Control snapshot root differs")
    require(len(snapshot["files"]) == 138, "Control snapshot input count differs")
    sources, drift = {}, []
    for item in snapshot["files"]:
        path = Path(item["path"])
        path = (path if path.is_absolute() else BASE / path).resolve()
        require(path.is_relative_to(BASE.resolve()), "Baseline dependency escapes control root")
        if not path.is_file() or sha(path) != item["sha256"].upper():
            drift.append(str(path))
        if item["kind"] not in {"project", "explicit_dependency", "audit_configuration"}:
            sources[path.relative_to(BASE.resolve()).as_posix()] = item["sha256"].upper()
    require(not drift, "Read-only baseline source drift: " + "; ".join(drift))
    phy = BASE / BASE_RUN / "phy_1"
    build_path = BASE / "artifacts" / (BASE_STEM + "_BUILD.json")
    build, gate = load(build_path), load(phy / "release_gate.json")
    require(build["bit_sha256"] == BASE_SHA and Path(build["runs"]).resolve() == (BASE / BASE_RUN).resolve(),
            "Control delivery record belongs to another bit/run")
    require(build["source_manifest_sha256"] == snapshot["manifest_sha256"], "Control delivery source identity differs")
    require(gate.get("passed") and gate.get("bitgen_allowed") and not gate.get("failures"), "Control route gate failed")
    require((phy / ".opt_route.end.f").is_file() and (phy / ".bitgen.end.f").is_file()
            and not list(phy.glob(".*.error.f")), "Control route/bitgen markers failed")
    require(sha(phy / (NAME + ".bit")) == BASE_SHA, "Control bit is not the accepted routed bitgen output")
    timing, resources = timing_metrics(phy / (NAME + "_pr.timing")), area_metrics(phy / (NAME + "_phy.area"))
    require(timing == build["timing_ns"] == gate["timing_ns"], "Control route timing evidence differs")
    require(all(value >= 0 for value in timing.values()) and timing["STNS"] == timing["HTNS"] == 0,
            "Control route does not satisfy timing")
    for name, entry in resources.items():
        require(entry["used"] == build["resources"][name]["used"] and entry["total"] == build["resources"][name]["total"],
                "Control route resource evidence differs: " + name)
    physical_path = BASE / "02_sim" / (BASE_RUN + "_physical_review/FINAL_PHYSICAL_REVIEW.json")
    readonly_path = BASE / "02_sim" / (BASE_RUN + "_readonly/readonly_verification.json")
    require(sha(physical_path) == build["physical_review_sha256"]
            and load(physical_path)["status"] == "PASS_WITH_INHERITED_WARNINGS", "Control physical review differs/fails")
    require(sha(readonly_path) == build["readonly_verification_sha256"] and load(readonly_path).get("passed"),
            "Control readonly verification differs/fails")
    return {"bit": str(bit), "bit_sha256": BASE_SHA, "snapshot": str(snapshot_path),
            "snapshot_sha256": BASE_SNAPSHOT_SHA, "frozen_input_count": len(snapshot["files"]),
            "source_manifest_sha256": snapshot["manifest_sha256"], "delivery_record_sha256": sha(build_path),
            "timing_ns": timing, "resources": resources, "source_inputs": sources}


def source_scope_check(baseline=None):
    baseline = baseline or baseline_check()
    changes = []
    for relative, expected in baseline["source_inputs"].items():
        path = local(relative)
        require(path.is_file(), "Missing baseline source in variant: " + relative)
        if sha(path) != expected:
            changes.append(relative)
    require(set(changes) <= ALLOWED_RTL, "Unapproved production/model/constraint change: " + repr(changes))
    require(local(NEW_RTL).is_file(), "Required target-stability module missing")
    require(sha(ROOT / "tools/release_audit_config.json") == sha(BASE / "tools/release_audit_config.json"),
            "Memory-resolution/exception audit configuration changed")
    return {"baseline_source_count": len(baseline["source_inputs"]), "intentional_changes": sorted(changes),
            "new_source": NEW_RTL, "new_source_sha256": sha(local(NEW_RTL)),
            "protected_sources_unchanged": True}


def active_scope_check(snapshot, baseline):
    added = []
    for item in snapshot["files"]:
        if item["kind"] in {"project", "explicit_dependency", "audit_configuration"}:
            continue
        source = local(item["path"])
        relative = source.relative_to(ROOT).as_posix()
        if relative not in baseline["source_inputs"]:
            added.append(relative)
    require(set(added) == {NEW_RTL}, "Active source/dependency additions differ from stabilizer-only plan: " + repr(added))


def production_grid_contract():
    """Require the reviewed production instance, rather than a report-only flag."""
    path = local("01_rtl/vision_pipeline.v")
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", read(path), flags=re.S)
    instances = re.findall(r"\bcnn_result_stabilizer\s*#\s*\((.*?)\)\s*result_stability\s*\(", text, re.S)
    require(len(instances) == 1, "Expected exactly one production result_stability instance")
    shifts = re.findall(r"\.COORD_SHIFT\s*\(\s*(\d+)\s*\)", instances[0])
    require(shifts == ["3"], "Production stabilizer must explicitly select COORD_SHIFT=3")
    return {"instance": "result_stability", "coord_shift": 3, "pipeline_sha256": sha(path)}


def prepare(args, runs):
    require(not runs.exists(), "Fresh run directory required")
    production_grid_contract()
    baseline = baseline_check()
    scope = source_scope_check(baseline)
    gen = module(ROOT / "_gen_project.py", "stability_generator")
    template = ROOT / "tools/accepted_fc8_run_full.tcl"
    require(sha(template) == sha(BASE / "tools/accepted_fc8_run_full.tcl"), "Accepted TD flow changed")
    gen.RUN_FULL = template
    tree = gen.load_project()
    source_paths = {Path(entry.attrib["Path"]).resolve() for entry in tree.findall("Source_Files/*/File")}
    require(local(NEW_RTL) in source_paths, "Stabilizer omitted from synthesis project")
    require(all(path.is_relative_to(ROOT) for path in source_paths), "Project uses nonlocal inputs")
    for phase, start, end, parent in (("syn_1", "read_design", "opt_gate", None),
                                      ("phy_1", "opt_place", "opt_route", "../syn_1")):
        target = runs / phase
        target.mkdir(parents=True)
        for suffix in ("al", "prj"):
            project = copy.deepcopy(tree)
            project.set("Path", target.as_posix())
            for entry in project.findall("Source_Files/*/File"):
                entry.set("Path", gen.rel(Path(entry.attrib["Path"]), target))
            ET.indent(project)
            payload = ET.tostring(project, encoding="unicode").replace("_TD_DOUBLE_COLON_", "::")
            (target / (NAME + "." + suffix)).write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + payload + "\n", encoding="utf-8")
        flow = gen.exported_flow(target, start, end, phase, parent)
        # R11: reviewed grid/pointer RTL plus the same official PH1 gate-option subset.
        # Set before gate commit, then log the effective gate parameters.
        marker = "  if { ![info exists singleRun] } { commit_param -step gate }"
        if phase == "syn_1":
            require(flow.count(marker) == 1, "Expected one gate parameter commit")
            flow = flow.replace(marker,
                "  set_param gate add_map_lut_struct high\n"
                "  set_param gate map_mode area_prior\n"
                "  set_param gate pack_effort high\n" + marker + "\n  report_param")
        if phase == "phy_1":
            flow, count = re.subn(r"(?m)^(\s*)place\s*$", r"\1set_param place seed " + str(args.seed) + r"\n\1place", flow)
            require(count == 1, "Expected one explicit seeded place invocation")
            (target / "run_bitgen.tcl").write_text(gen.exported_flow(target, "bitgen", "bitgen", phase), encoding="utf-8")
        (target / "run.tcl").write_text(flow, encoding="utf-8")
        header = flow.split("# This is default flow script", 1)[0]
        (target / "settings.cfg").write_text("\n".join(line for line in header.splitlines() if line.startswith("set ")) + "\n", encoding="utf-8")
    execute(audit_command("snapshot", runs / "syn_1"))
    execute(audit_command("snapshot", runs / "phy_1"))
    snapshot = load(runs / "syn_1/source_snapshot.json")
    active_scope_check(snapshot, baseline)
    flows = {path.relative_to(ROOT).as_posix(): sha(path) for phase in ("syn_1", "phy_1")
             for path in (runs / phase / "run.tcl", runs / phase / "settings.cfg")}
    flows[(runs / "phy_1/run_bitgen.tcl").relative_to(ROOT).as_posix()] = sha(runs / "phy_1/run_bitgen.tcl")
    save(runs / "BUILD_PLAN.json", {"root": str(ROOT), "runs": str(runs), "created_utc": datetime.now(timezone.utc).isoformat(),
         "mapping_experiment": {"gate_map_mode": "area_prior", "gate_pack_effort": "high", "gate_add_map_lut_struct": "high", "rtl_candidate": "R11 fixed-grid coordinate/area mapper with R10 exact-grid kernel, pointer insertion pipeline and center-cache top", "constraints_changed": False},
         "seed": args.seed, "source_manifest_sha256": snapshot["manifest_sha256"], "flow_sha256": flows,
         "baseline_provenance": baseline, "source_scope": scope, "hardware_validation": "NOT_RUN"})
    print(json.dumps({"status": "PREPARED_NOT_STARTED", "runs": str(runs), "source_manifest_sha256": snapshot["manifest_sha256"]}, indent=2))


def validate_plan(runs):
    production_grid_contract()
    plan = load(runs / "BUILD_PLAN.json")
    require(Path(plan["root"]).resolve() == ROOT and Path(plan["runs"]).resolve() == runs, "Wrong build-plan root/run")
    require(plan["baseline_provenance"]["bit_sha256"] == BASE_SHA, "Wrong control bit in build plan")
    for relative, expected in plan["flow_sha256"].items():
        require(sha(local(relative)) == expected, "Frozen flow changed: " + relative)
    snapshot = load(runs / "syn_1/source_snapshot.json")
    require(snapshot["manifest_sha256"] == plan["source_manifest_sha256"], "Frozen snapshot identity changed")
    for entry in snapshot["files"]:
        path = local(entry["path"])
        require(path.is_file() and sha(path) == entry["sha256"].upper(), "Frozen build input changed: " + str(path))
    baseline = baseline_check()
    source_scope_check(baseline)
    active_scope_check(snapshot, baseline)
    return plan


def fixed_grid_mapping_contract(path, data, inputs):
    """Bind integer proof and actual production RTL miter to current inputs."""
    require(path == local("02_sim/cnn_fixed_grid_mapping/RESULTS.json"),
            "Fixed-grid mapping evidence must be the current official suite")
    require(data.get("production_candidate_applied") is True,
            "Fixed-grid mapping regression does not verify the applied production candidate")
    pipeline, kernel = local("01_rtl/vision_pipeline.v"), local(NEW_RTL)
    bound = {local(value): str(expected).upper() for value, expected in inputs.items()}
    require(bound.get(pipeline) == sha(pipeline) == data.get("production_pipeline_sha256"),
            "Fixed-grid mapping result does not identify the current production pipeline")
    require({"vision_pipeline", "cnn_result_stabilizer"} <= set(data.get("production_modules", [])),
            "Fixed-grid mapping regression lacks the actual production module identities")
    coverage = data.get("coverage", {})
    integer, miter = coverage.get("integer", {}), coverage.get("miter", {})
    require(all(integer.get(key) == value for key, value in {
                "coordinate_cases": 1536, "area_cases": 65536,
                "coordinate_mismatches": 0, "area_mismatches": 0}.items()),
            "Fixed-grid integer proof lost exhaustive domains or reports mismatches")
    expected_miter = {"cycles": 11742298, "public_ports": 37, "controls": 11,
                      "completed_jobs": 113, "assertions": 527,
                      "original_completed_jobs": 81, "original_assertions": 374}
    require(all(miter.get(key) == value for key, value in expected_miter.items()),
            "Fixed-grid production miter lost the reviewed output/control/job coverage")
    evidence = data.get("evidence_hashes")
    require(isinstance(evidence, dict) and evidence, "Fixed-grid regression lacks simulator/integer logs")
    evidence = {local(path.parent / value): str(expected).upper() for value, expected in evidence.items()}
    for name in ("integer/exhaustive.log", "miter/vlib.log", "miter/compile.log", "miter/simulate.log"):
        log = local(path.parent / name)
        require(log in evidence and log.is_file() and sha(log) == evidence[log],
                "Fixed-grid required log missing or changed: " + name)
        require(path.stat().st_mtime_ns >= log.stat().st_mtime_ns,
                "Fixed-grid result predates its log: " + name)
    children = data.get("child_results", {})
    for name in ("integer", "miter"):
        record = children.get(name)
        require(isinstance(record, dict) and record.get("status") == "PASS",
                "Fixed-grid child did not pass: " + name)
        value = Path(record.get("path", ""))
        child = local(value if value.is_absolute() else path.parent / value)
        require(child.is_relative_to(path.parent / name) and child.name == "RESULTS.json",
                "Fixed-grid child evidence is outside its official suite directory")
        require(child.is_file() and bound.get(child) == record.get("sha256") == sha(child),
                "Fixed-grid child result is not frozen in the top input hashes: " + name)
        child_data = load(child)
        require(child_data.get("status") == "PASS", "Fixed-grid child status drift: " + name)
        require(child_data.get("coverage") == (integer if name == "integer" else miter),
                "Fixed-grid child/top coverage differs: " + name)
        child_inputs = child_data.get("input_hashes") or child_data.get("inputs_sha256")
        require(isinstance(child_inputs, dict) and child_inputs, "Fixed-grid child input hashes missing: " + name)
        newest = 0
        for value, expected in child_inputs.items():
            source = local(value)
            require(source.is_file() and sha(source) == str(expected).upper() == bound.get(source),
                    "Fixed-grid child input changed or missing from top closure: " + str(source))
            newest = max(newest, source.stat().st_mtime_ns)
        child_evidence = child_data.get("evidence_hashes")
        require(isinstance(child_evidence, dict) and child_evidence, "Fixed-grid child log hashes missing: " + name)
        for value, expected in child_evidence.items():
            log = local(child.parent / value)
            digest = str(expected).upper()
            require(log.is_file() and sha(log) == digest and (evidence.get(log) == digest or bound.get(log) == digest),
                    "Fixed-grid child log changed or missing from top closure: " + str(log))
            newest = max(newest, log.stat().st_mtime_ns)
        require(child.stat().st_mtime_ns >= newest and path.stat().st_mtime_ns >= child.stat().st_mtime_ns,
                "Fixed-grid child/top result predates current inputs/logs: " + name)
        if name == "miter":
            compiled = {local(value) for value in child_data.get("compile_sources", [])}
            require({pipeline, kernel} <= compiled,
                    "Fixed-grid miter did not compile the actual production pipeline and kernel")
            require(len(child_data.get("public_ports_compared_every_active_clock", [])) == 37
                    and len(child_data.get("controls_compared_every_active_clock", [])) == 11,
                    "Fixed-grid miter child does not verify all reviewed outputs/controls")
    require("PASS FIXED_GRID_EXHAUSTIVE coordinates=1536 area=65536 coordinate_mismatches=0 area_mismatches=0"
            in read(path.parent / "integer/exhaustive.log"),
            "Fixed-grid exhaustive integer log does not substantiate the reported coverage")
    text = read(path.parent / "miter/simulate.log")
    marker = re.search(r"PASS FIXED_GRID_PUBLIC_CYCLE_MITER cycles=(\d+) public_ports=37 controls=11 "
                       r"completed_jobs=(\d+) assertions=(\d+)", text)
    require(marker is not None and tuple(map(int, marker.groups())) == (11742298, 113, 527)
            and "PASS ORIGINAL_81_JOBS_374_ASSERTIONS_PRESERVED" in text,
            "Fixed-grid simulator markers do not substantiate the reported miter coverage")


def regression_gate(files, required):
    require(files, "Supply fresh current --regression RESULTS.json evidence")
    result, names, covered = {}, set(), set()
    for value in files:
        path = local(value)
        require(path.is_relative_to(ROOT / "02_sim"), "Regression is not inside current 02_sim")
        data = load(path)
        require(data.get("status") == "PASS" or data.get("passed") is True, "Regression did not pass: " + str(path))
        inputs = data.get("input_hashes") or data.get("inputs_sha256")
        require(isinstance(inputs, dict) and inputs, "Regression lacks current input hashes: " + str(path))
        latest = 0
        for value, expected in inputs.items():
            source = local(value)
            require(source.is_file() and sha(source) == str(expected).upper(), "Regression input drift: " + str(source))
            latest = max(latest, source.stat().st_mtime_ns)
            covered.add(source.relative_to(ROOT).as_posix())
        require(path.stat().st_mtime_ns >= latest, "Regression predates a current input: " + str(path))
        for relative, expected in data.get("evidence_hashes", {}).items():
            evidence = local(path.parent / relative)
            require(evidence.is_file() and sha(evidence) == str(expected).upper(), "Regression evidence drift: " + str(evidence))
        if path.parent.name == "cnn_named_top":
            require(data.get("full_lint_source_count", 0) >= 77 and "lint_full.log" in data.get("evidence_hashes", {}),
                    "Current production-top full-source lint evidence missing")
        if path.parent.name in {"cnn_stability_serial", "cnn_stability_ram"}:
            require(data.get("production_candidate_applied") is True,
                    "Serial/RAM regression does not verify the applied production kernel")
        if path.parent.name == "cnn_stability_area24":
            require(data.get("production_candidate_applied") is True and data.get("area_bits") == 24,
                    "Area24 regression does not verify the applied production AREA_BITS=24 kernel")
        if path.parent.name == "cnn_stability_grid":
            require(data.get("production_candidate_applied") is True and data.get("coord_shift") == 3,
                    "Grid regression does not verify the applied production COORD_SHIFT=3 candidate")
            require("cnn_result_stabilizer" in data.get("production_modules", []),
                    "Grid regression lacks the production stabilizer identity")
            grid_inputs = {local(value).relative_to(ROOT).as_posix() for value in inputs}
            require(ALLOWED_RTL | {NEW_RTL} <= grid_inputs,
                    "Grid regression does not cover all current production kernel/pipeline/top inputs")
            require(isinstance(data.get("evidence_hashes"), dict) and data["evidence_hashes"],
                    "Grid regression lacks simulator evidence hashes")
            production_grid_contract()
        if path.parent.name == "cnn_fixed_grid_mapping":
            fixed_grid_mapping_contract(path, data, inputs)
        names.add(path.parent.name)
        result[path.relative_to(ROOT).as_posix()] = sha(path)
    require(required <= names, "Missing required fresh regressions: " + repr(sorted(required - names)))
    require(ALLOWED_RTL | {NEW_RTL} <= covered, "Regressions do not cover all changed/new RTL inputs")
    return result


def physical_review(runs):
    phy, old = runs / "phy_1", BASE / BASE_RUN / "phy_1"
    reports = [phy / name for name in (NAME + "_chk.timing", "secondary_cdc_route_end.rpt", "secondary_reset_route_end.rpt",
               "secondary_effective_route_end.ignored.rpt", "secondary_loaded_route_end.rpt", "td_console.log")]
    require(all(path.is_file() for path in reports), "Final physical proof reports are missing")
    log, syn_log, old_log = read(phy / "td_console.log"), read(runs / "syn_1/td_console.log"), read(old / "td_console.log")
    errors = []
    for code in ("HDL-5105", "RTCLK-5078", "USR-6113"):
        if code in log + syn_log:
            errors.append("Forbidden ROM/clock warning: " + code)
    if re.search(r"\b[A-Z]+-\d+\s*(?:ERROR|FATAL)\b", log + syn_log):
        errors.append("Fatal tool error")
    previous, current = (Counter(re.findall(r"DRC ([A-Z]+-\d+)", value)) for value in (old_log, log))
    increased_drc = {key: value for key, value in current.items() if value > previous.get(key, 0)}
    if increased_drc:
        errors.append("New/increased DRC requires explicit evidence review")
    def checks(text):
        return {label.strip(): int(value) for label, value in re.findall(r"^\d+\. checking (.*?)\((\d+)\) \((?:HIGH|MEDIUM)\)", text, re.M)}
    old_checks, new_checks = checks(read(old / (NAME + "_chk.timing"))), checks(read(phy / (NAME + "_chk.timing")))
    require(old_checks and new_checks, "Final timing-check category reports are empty")
    increased_checks = {key: value for key, value in new_checks.items() if value > old_checks.get(key, 0)}
    if increased_checks:
        errors.append("Increased final timing-check categories require review")
    loaded, reset = read(phy / "secondary_loaded_route_end.rpt"), read(phy / "secondary_reset_route_end.rpt")
    effective = re.search(r"EFFECTIVE_RESET_PIN_CONSTRAINTS\s+(\d+)", loaded)
    applied = re.search(r"APPLIED_RESET_EXCEPTIONS\s+(\d+) unique asynchronous pins;\s+(\d+) proven synchronizers", reset)
    if not effective or not applied or int(effective[1]) != int(applied[1]) or int(applied[2]) < 5:
        errors.append("Effective reset endpoints lack matching synchronizer proof")
    if "EFFECTIVE_SMD_PATHS 290 128 9 52" not in loaded:
        errors.append("Effective CDC/async-FIFO path bounds changed")
    ignored = re.findall(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+set_", read(phy / "secondary_effective_route_end.ignored.rpt"), re.M)
    if not ignored or any(int(row[2]) or int(row[3]) for row in ignored):
        errors.append("Final exceptions missing, shadowed or ignored")
    scope = source_scope_check()
    result = {"status": "PASS_WITH_INHERITED_WARNINGS" if not errors else "REVIEW_REQUIRED", "errors": errors,
              "source_scope": scope, "baseline_run": str(BASE / BASE_RUN),
              "drc_counts": {"baseline": dict(previous), "current": dict(current)}, "increased_drc_counts": increased_drc,
              "timing_check_categories": {"baseline": old_checks, "current": new_checks}, "increased_check_categories": increased_checks,
              "effective_reset_pins": int(effective[1]) if effective else None,
              "proven_synchronizers": int(applied[2]) if applied else None,
              "fifo_cdc_contract": "Unchanged exact datapath-only first-stage Gray bounds; second stages remain timed; effective path counts290/128/9/52",
              "hardware_status": "NOT_RUN", "readonly_reimport": "separate mandatory gate",
              "report_sha256": {path.relative_to(ROOT).as_posix(): sha(path) for path in reports}}
    out = local(ROOT / "02_sim" / (runs.name + "_physical_review"))
    save(out / "FINAL_PHYSICAL_REVIEW.json", result)
    require(not errors, "Physical review failed: " + "; ".join(errors))
    return out


def routed_gate(runs):
    execute(audit_command("gate", runs / "phy_1", "--syn-run", runs / "syn_1", "--snapshot", runs / "syn_1/source_snapshot.json",
                          "--log", runs / "syn_1/td_console.log", "--log", runs / "phy_1/td_console.log"))
    return physical_review(runs)


def readonly(args, runs):
    out = local(ROOT / "02_sim" / (runs.name + "_readonly"))
    require(not out.exists(), "Readonly evidence directory must be fresh")
    execute(audit_command("reimport-template", runs / "phy_1", "--audit-dir", out))
    execute([str(args.td), str(out / "readonly_reimport.tcl")], cwd=runs / "phy_1", log=out / "td_console.log")
    execute(audit_command("verify-readonly", runs / "phy_1", "--audit-dir", out, "--log", out / "td_console.log"))


def bitgen(args, runs):
    regressions = regression_gate(args.regression, REQUIRED_BIT_TESTS)
    physical = routed_gate(runs)
    readonly_dir = local(ROOT / "02_sim" / (runs.name + "_readonly"))
    execute(audit_command("verify-readonly", runs / "phy_1", "--audit-dir", readonly_dir, "--log", readonly_dir / "td_console.log"))
    phy = runs / "phy_1"
    require(not (phy / ".bitgen.begin.f").exists(), "Preserve previous bitgen invocation")
    execute([str(args.td), "run_bitgen.tcl"], cwd=phy, log=phy / "bitgen_console.log")
    require((phy / ".bitgen.end.f").is_file() and not list(phy.glob(".*.error.f")), "Bitgen did not complete")
    bit = phy / (NAME + ".bit")
    require(bit.is_file() and bit.stat().st_size > 0, "New bitstream missing")
    target = local(ROOT / "artifacts" / (args.stem + ".bit"))
    require(not target.exists(), "Never overwrite a delivered bit")
    target.parent.mkdir(exist_ok=True)
    shutil.copy2(bit, target)
    require(sha(target) == sha(bit), "Delivered bit copy differs")
    gate, plan = load(phy / "release_gate.json"), load(runs / "BUILD_PLAN.json")
    save(target.with_name(args.stem + "_BUILD.json"), {"status": "DIAGNOSTIC_NOT_RUN", "hardware_validation": "NOT_RUN",
         "bit": target.name, "bit_sha256": sha(bit), "runs": str(runs), "baseline_bit_sha256": BASE_SHA,
         "source_manifest_sha256": plan["source_manifest_sha256"], "timing_ns": gate["timing_ns"], "resources": gate["resources"],
         "regression_evidence_sha256": regressions, "physical_review_sha256": sha(physical / "FINAL_PHYSICAL_REVIEW.json"),
         "readonly_verification_sha256": sha(readonly_dir / "readonly_verification.json"),
         "completion_semantics": "Final G-code ok confirms controller acceptance, not mechanical Idle"})
    print(json.dumps({"status": "DIAGNOSTIC_NOT_RUN", "bit": str(target), "sha256": sha(bit)}, indent=2))


def main():
    parser = argparse.ArgumentParser(description="R11 verified fixed-grid mapper and exact-grid/pointer sorting with the unchanged PH1 gate-option subset. " + str(__doc__))
    parser.add_argument("action", choices=("inspect", "prepare", "validate", "syn", "route", "gate", "readonly", "bitgen"))
    parser.add_argument("--runs", type=Path, default=Path(RUNS))
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--td", type=Path, default=TD)
    parser.add_argument("--regression", type=Path, action="append")
    parser.add_argument("--stem", default=STEM)
    args = parser.parse_args()
    require(ROOT.name != BASE.name and "work" not in [p.lower() for p in ROOT.parts], "Independent non-work variant required")
    runs = local(args.runs)
    require(runs == local(RUNS), "R11 builder is locked to its independent R11 run")
    if args.action == "inspect":
        result = baseline_check()
        print(json.dumps({**{key: value for key, value in result.items() if key != "source_inputs"},
                          "variant_source_scope": source_scope_check(result)}, indent=2))
        return 0
    if args.action == "prepare":
        prepare(args, runs)
        return 0
    validate_plan(runs)
    if args.action == "syn":
        regressions = regression_gate(args.regression, REQUIRED_SYN_TESTS)
        save(runs / "PRE_SYN_REGRESSIONS.json", regressions)
        execute([str(args.td), "run.tcl"], cwd=runs / "syn_1", log=runs / "syn_1/td_console.log")
        require((runs / "syn_1/.opt_gate.end.f").is_file() and not list((runs / "syn_1").glob(".*.error.f")), "Synthesis did not complete")
    elif args.action == "route":
        syn = runs / "syn_1"
        require((syn / ".opt_gate.end.f").is_file() and not list(syn.glob(".*.error.f")), "Synthesis incomplete/failed")
        area_path = syn / (NAME + "_gate.area")
        area_metrics(area_path)
        execute([str(args.td), "run.tcl"], cwd=runs / "phy_1", log=runs / "phy_1/td_console.log")
        require((runs / "phy_1/.opt_route.end.f").is_file() and not list((runs / "phy_1").glob(".*.error.f")), "Route did not complete")
    elif args.action == "gate":
        routed_gate(runs)
    elif args.action == "readonly":
        routed_gate(runs)
        readonly(args, runs)
    elif args.action == "bitgen":
        bitgen(args, runs)
    else:
        print("PASS frozen build plan, baseline and source scope")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError, ET.ParseError) as error:
        print("BUILD_CNN_STABILITY_FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
