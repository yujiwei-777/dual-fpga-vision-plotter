"""Frozen KEY3 reset, endpoint/branch stroke planner and CNN stability release.

Reuse the accepted build flow and strict routed/readonly/bitgen gates.  This
adapter adds the current source closure, regression suites and KEY3 supervisor
connectivity proof.  No failed physical result is eligible for bit generation.
"""
from __future__ import annotations

import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import build_cnn_stability_r11 as flow
import release_source_scope as scope

ROOT = Path(__file__).resolve().parents[1]
RUNS = "cnn_key3_stroke_Runs_20261031"
STEM = "dual_fpga_secondary_20261031_cnn_key3_stroke_diagnostic"
SYN_SUITES = {"cnn_named_top", "key3_top_reset_release", "stroke_release",
              "cnn_named_pcb", "cnn_area_pipeline_release"}
BIT_SUITES = SYN_SUITES | {"cnn_stability_core", "cnn_named_report"}
LATEST_REGRESSION_EVIDENCE = None
EXTRAS = ("tools/build_key3_stroke_release.py", "tools/release_source_scope.py",
          "tools/key3_stroke_regression_gate.py", "tools/key3_physical_gate.py",
          "04_pin/apply_reset_exceptions.tcl", "04_pin/apply_cdc_exceptions.tcl",
          "04_pin/prove_key3_supervisor.tcl")


def source_scope_check(baseline=None):
    return scope.check(ROOT, baseline=baseline or flow.baseline_check())


def active_scope_check(snapshot, baseline):
    return scope.check(ROOT, baseline=baseline, snapshot=snapshot)


def production_contract():
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", flow.read(ROOT / "01_rtl/vision_pipeline.v"), flags=re.S)
    instances = re.findall(r"\bcnn_result_stabilizer\s*#\s*\((.*?)\)\s*result_stability\s*\(", text, re.S)
    flow.require(len(instances) == 1, "Expected exactly one production stabilizer")
    for key, expected in (("COORD_SHIFT", "3"), ("AREA_BITS", "22"), ("AREA_SHIFT", "6")):
        values = re.findall(r"\." + key + r"\s*\(\s*(\d+)\s*\)", instances[0])
        flow.require(values == [expected], "Production parameter differs: " + key)
    return {"instance": "result_stability", "COORD_SHIFT": 3, "AREA_BITS": 22, "AREA_SHIFT": 6,
            "pipeline_sha256": flow.sha(ROOT / "01_rtl/vision_pipeline.v"),
            "kernel_sha256": flow.sha(ROOT / "01_rtl/cnn_result_stabilizer.v")}


old_audit_command = flow.audit_command


def audit_command(action, run, *extra):
    command = old_audit_command(action, run)
    for relative in EXTRAS:
        path = flow.local(relative)
        flow.require(path.is_file(), "Release build dependency missing: " + relative)
        command += ["--extra", str(path)]
    return command + [str(x) for x in extra]


def regression_gate(files, required):
    import key3_stroke_regression_gate
    global LATEST_REGRESSION_EVIDENCE
    results = key3_stroke_regression_gate.check(files, required=required)
    evidence = key3_stroke_regression_gate.evidence_manifest(files, required=required)
    digest = hashlib.sha256(json.dumps(evidence, sort_keys=True).encode()).hexdigest().upper()
    target = ROOT / "reports" / ("RELEASE_REGRESSION_EVIDENCE_" + digest + ".json")
    if target.exists():
        flow.require(flow.load(target) == evidence, "Frozen regression evidence identity differs")
    else:
        flow.save(target, evidence)
    LATEST_REGRESSION_EVIDENCE = target
    return results


def instrument_key3(text, gen, directory):
    # Calls execute after the existing reset/CDC proof and timing update.
    # The new hook inspects mapped cells only; it adds no SDC exceptions.
    hook = gen.rel(ROOT / "04_pin/prove_key3_supervisor.tcl", directory)
    pattern = r"(?m)^(\s*)secondary_apply_phase_timing (gate|place_begin|place_end|route_begin|route_end) [^\n]+$"
    def replacement(match):
        return (match[0] + "\n" + match[1] + "source {" + hook + "}\n" +
                match[1] + "secondary_prove_key3_supervisor " + match[2])
    text, count = re.subn(pattern, replacement, text)
    flow.require(count == 5, "Expected five phase timing/proof insertion points")
    return text


def prepare(args, runs):
    flow.require(not runs.exists(), "Fresh run directory required")
    contract = production_contract()
    baseline = flow.baseline_check()
    gen = flow.module(ROOT / "_gen_project.py", "key3_stroke_generator")
    template = ROOT / "tools/accepted_fc8_run_full.tcl"
    flow.require(flow.sha(template) == flow.sha(flow.BASE / "tools/accepted_fc8_run_full.tcl"),
                 "Accepted base TD flow changed")
    gen.RUN_FULL = template
    tree = gen.load_project()
    checked = scope.check(ROOT, baseline=baseline, tree=tree)
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
            (target / (flow.NAME + "." + suffix)).write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n' + payload + "\n", encoding="utf-8")
        text = instrument_key3(gen.exported_flow(target, start, end, phase, parent), gen, target)
        marker = "  if { ![info exists singleRun] } { commit_param -step gate }"
        if phase == "syn_1":
            flow.require(text.count(marker) == 1, "Expected one gate commit")
            text = text.replace(marker,
                "  set_param gate add_map_lut_struct high\n"
                "  set_param gate map_mode area_prior\n"
                "  set_param gate pack_effort high\n" + marker + "\n  report_param")
        else:
            text, count = re.subn(r"(?m)^(\s*)place\s*$",
                                  r"\1set_param place seed " + str(args.seed) + r"\n\1place", text)
            flow.require(count == 1, "Expected one seeded place invocation")
            bitflow = instrument_key3(gen.exported_flow(target, "bitgen", "bitgen", phase), gen, target)
            (target / "run_bitgen.tcl").write_text(bitflow, encoding="utf-8")
        (target / "run.tcl").write_text(text, encoding="utf-8")
        header = text.split("# This is default flow script", 1)[0]
        (target / "settings.cfg").write_text("\n".join(line for line in header.splitlines()
            if line.startswith("set ")) + "\n", encoding="utf-8")
    flow.execute(audit_command("snapshot", runs / "syn_1"))
    flow.execute(audit_command("snapshot", runs / "phy_1"))
    snapshot = flow.load(runs / "syn_1/source_snapshot.json")
    active_scope_check(snapshot, baseline)
    flows = {path.relative_to(ROOT).as_posix(): flow.sha(path) for phase in ("syn_1", "phy_1")
             for path in (runs / phase / "run.tcl", runs / phase / "settings.cfg")}
    flows[(runs / "phy_1/run_bitgen.tcl").relative_to(ROOT).as_posix()] = flow.sha(runs / "phy_1/run_bitgen.tcl")
    flow.save(runs / "BUILD_PLAN.json", {"root": str(ROOT), "runs": str(runs),
        "created_utc": datetime.now(timezone.utc).isoformat(), "seed": args.seed,
        "source_manifest_sha256": snapshot["manifest_sha256"], "flow_sha256": flows,
        "baseline_provenance": baseline, "source_scope": checked,
        "mapping_experiment": {"gate_map_mode": "area_prior", "gate_pack_effort": "high",
            "gate_add_map_lut_struct": "high", "rtl_candidate": "KEY3 supervisor + endpoint/branch45 planner + lossless scaled-area CNN stability",
            "constraints_changed": True,
            "constraint_scope": "KEY3 first-stage async input; first two reset synchronizers use board_release; no datapath relaxation",
            "production_contract": contract, "key3_proof": "read-only mapped-cell verification at five phases"},
        "hardware_validation": "NOT_RUN"})
    print("PREPARED_NOT_STARTED", runs, snapshot["manifest_sha256"])


old_physical_review = flow.physical_review


def physical_review(runs):
    import key3_physical_gate
    out = old_physical_review(runs)
    path = out / "FINAL_PHYSICAL_REVIEW.json"
    data = flow.load(path)
    try:
        data["key3_reset_proof"] = key3_physical_gate.check(ROOT, runs)
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        data["status"] = "REVIEW_REQUIRED"
        data["errors"].append("KEY3 supervisor/reset proof: " + str(error))
        flow.save(path, data)
        raise
    flow.save(path, data)
    return out


old_bitgen = flow.bitgen


def bitgen(args, runs):
    old_bitgen(args, runs)
    flow.require(LATEST_REGRESSION_EVIDENCE is not None, "Missing release regression evidence closure")
    path = ROOT / "artifacts" / (args.stem + "_BUILD.json")
    data = flow.load(path)
    data["regression_evidence_manifest"] = str(LATEST_REGRESSION_EVIDENCE.relative_to(ROOT))
    data["regression_evidence_manifest_sha256"] = flow.sha(LATEST_REGRESSION_EVIDENCE)
    data["cnn_stability"] = {"spatial_tracks": 4, "confirmation_results": 3,
        "uncertain_hold_results": 2, "FC_CONF_SHIFT": 8, "contract": production_contract()}
    data["key3"] = "B9 active-low debounced whole-FPGA-application reset; external GRBL/ESP32 not reset"
    data["stroke_policy"] = "endpoint first; original-skeleton junctions continue straight or <=45 degrees; residual edges/loops covered"
    flow.save(path, data)
    bit = ROOT / "artifacts" / (args.stem + ".bit")
    bit.with_suffix(".bit.sha256").write_text(flow.sha(bit) + "  " + bit.name + "\n", encoding="ascii")


def install():
    flow.RUNS, flow.STEM = RUNS, STEM
    flow.ALLOWED_RTL = {"01_rtl/secondary_top.v", "01_rtl/vision_pipeline.v", "01_rtl/doc_stroke_planner.v"}
    flow.REQUIRED_SYN_TESTS, flow.REQUIRED_BIT_TESTS = SYN_SUITES, BIT_SUITES
    flow.source_scope_check, flow.active_scope_check = source_scope_check, active_scope_check
    flow.production_grid_contract, flow.audit_command = production_contract, audit_command
    flow.prepare, flow.regression_gate, flow.physical_review = prepare, regression_gate, physical_review
    flow.bitgen = bitgen


if __name__ == "__main__":
    install()
    try:
        raise SystemExit(flow.main())
    except (OSError, ValueError, KeyError, RuntimeError, ET.ParseError) as error:
        print("BUILD_KEY3_STROKE_RELEASE_FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
