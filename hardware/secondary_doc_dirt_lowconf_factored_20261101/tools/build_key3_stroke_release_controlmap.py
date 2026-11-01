"""Fresh full release with the successful control's default gate strategy.

Production RTL, models and timing constraints are unchanged. The original
area-prior runs remain frozen. Every regression, reset/CDC/KEY3 proof, routed
timing/resource check and readonly/bitgen gate from V2 remains in force.
"""
from __future__ import annotations

import copy
from datetime import datetime, timezone
import sys
import xml.etree.ElementTree as ET

import build_key3_stroke_release_v2 as reviewed

base = reviewed.base
flow = reviewed.flow
ROOT = reviewed.ROOT
RUNS = "cnn_key3_stroke_controlmap_Runs_20261031"
SELF = "tools/build_key3_stroke_release_controlmap.py"
EXTRAS = tuple(dict.fromkeys((*reviewed.EXTRAS, SELF)))


def prepare(args, runs):
    flow.require(not runs.exists(), "Fresh control-mapping run required")
    supplement = reviewed.supplementary_scope_check()
    baseline = flow.baseline_check()
    contract = base.production_contract()
    gen = flow.module(ROOT / "_gen_project.py", "key3_controlmap_generator")
    template = ROOT / "tools/accepted_fc8_run_full.tcl"
    flow.require(flow.sha(template) == flow.sha(flow.BASE / "tools/accepted_fc8_run_full.tcl"),
                 "Accepted TD flow changed")
    gen.RUN_FULL = template
    tree = gen.load_project()
    checked = base.scope.check(ROOT, baseline=baseline, tree=tree)
    snapshots, flows = {}, {}
    for phase, start, end, parent in (("syn_1", "read_design", "opt_gate", None),
                                    ("phy_1", "opt_place", "opt_route", "../syn_1")):
        directory = runs / phase
        directory.mkdir(parents=True)
        for suffix in ("al", "prj"):
            project = copy.deepcopy(tree)
            project.set("Path", directory.as_posix())
            for entry in project.findall("Source_Files/*/File"):
                entry.set("Path", gen.rel(entry.attrib["Path"], directory))
            ET.indent(project)
            payload = ET.tostring(project, encoding="unicode").replace("_TD_DOUBLE_COLON_", "::")
            (directory / (flow.NAME + "." + suffix)).write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n' + payload + "\n", encoding="utf-8")
        text = reviewed.instrument_key3(gen.exported_flow(directory, start, end, phase, parent), gen, directory)
        if phase == "syn_1":
            marker = "  if { ![info exists singleRun] } { commit_param -step gate }"
            flow.require(text.count(marker) == 1, "Expected one gate commit")
            text = text.replace(marker,
                "  set_param gate map_mode auto\n"
                "  set_param gate pack_effort medium\n"
                "  set_param gate map_strategy 1\n" + marker + "\n  report_param")
            # Match the successful control, which did not override the hidden
            # LUT-structure option. A fresh project supplies the tool default.
            flow.require("add_map_lut_struct" not in text and "area_prior" not in text,
                         "Unexpected inherited area-prior/hidden gate override")
        else:
            import re
            text, count = re.subn(r"(?m)^(\s*)place\s*$",
                r"\1set_param place seed " + str(args.seed) + r"\n\1place", text)
            flow.require(count == 1, "Expected one seeded place")
            bitflow = reviewed.instrument_key3(
                gen.exported_flow(directory, "bitgen", "bitgen", phase), gen, directory)
            (directory / "run_bitgen.tcl").write_text(bitflow, encoding="utf-8")
        (directory / "run.tcl").write_text(text, encoding="utf-8")
        header = text.split("# This is default flow script", 1)[0]
        (directory / "settings.cfg").write_text("\n".join(
            line for line in header.splitlines() if line.startswith("set ")) + "\n", encoding="utf-8")
    for phase in ("syn_1", "phy_1"):
        directory = runs / phase
        flow.execute(base.audit_command("snapshot", directory))
        snapshot = flow.load(directory / "source_snapshot.json")
        base.active_scope_check(snapshot, baseline)
        # Require this adapter as an explicit sealed dependency, in addition
        # to the full V2 source and proof closure.
        entries = [item for item in snapshot["files"] if flow.local(item["path"]) == ROOT / SELF]
        flow.require(len(entries) == 1 and entries[0]["kind"] == "explicit_dependency"
                     and entries[0]["sha256"] == flow.sha(ROOT / SELF),
                     "Control-mapping adapter not explicitly sealed")
        snapshots[phase] = {"path": (directory / "source_snapshot.json").relative_to(ROOT).as_posix(),
            "sha256": flow.sha(directory / "source_snapshot.json"),
            "manifest_sha256": snapshot["manifest_sha256"]}
        for name in ("run.tcl", "settings.cfg", "run_bitgen.tcl"):
            path = directory / name
            if path.exists():
                flows[path.relative_to(ROOT).as_posix()] = flow.sha(path)
    flow.save(runs / "BUILD_PLAN.json", {"root": str(ROOT), "runs": str(runs),
        "created_utc": datetime.now(timezone.utc).isoformat(), "seed": args.seed,
        "source_manifest_sha256": snapshots["syn_1"]["manifest_sha256"],
        "flow_sha256": flows, "baseline_provenance": baseline, "source_scope": checked,
        "clocktrace_supplement": {**supplement, "snapshots": snapshots,
            "phases": list(reviewed.PHASES)},
        "mapping_experiment": {"gate_map_mode": "auto", "gate_pack_effort": "medium",
            "gate_map_strategy": 1, "gate_add_map_lut_struct": "TOOL_DEFAULT_NO_OVERRIDE",
            "rtl_changed_from_clockproof": False, "constraints_changed_from_clockproof": False,
            "production_contract": contract,
            "rationale": "Reproduce successful control strategy; actual place/route still mandatory"},
        "hardware_validation": "NOT_RUN"})
    print("PREPARED_NOT_STARTED", runs, snapshots["syn_1"]["manifest_sha256"])


def install():
    reviewed.install()
    base.RUNS = flow.RUNS = RUNS
    base.EXTRAS = EXTRAS
    flow.prepare = prepare


if __name__ == "__main__":
    install()
    try:
        raise SystemExit(flow.main())
    except (OSError, ValueError, KeyError, RuntimeError, ET.ParseError) as error:
        print("BUILD_KEY3_STROKE_CONTROLMAP_FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
