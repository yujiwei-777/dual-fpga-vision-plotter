"""Fail-closed, read-only source gate for the KEY3/stroke release candidate.

The caller still owns baseline_check(), fresh regressions and all physical
gates.  This module proves source scope; it never grants physical acceptance.
check(root=None, baseline=None, snapshot=None, tree=None) returns a JSON-safe
dictionary or raises RuntimeError.  snapshot/tree are optional before prepare.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CONTROL_NAME = "secondary_cnn_named_coords_conf_20261030"
SPLIT_NAME = "secondary_cnn_key3_stroke_split_20261031"
CONTROL_RUN = "cnn_center_report_Runs_20261030"
CONTROL_SNAPSHOT_SHA = "5846BDB74E42117C062D310930EDAEDD0C26588746A12ADF99B3CD1FEBC3704D"
CONTROL_BIT_SHA = "A216CA0717A7C23365EB7EE06E47746D8022FFA634D28C97C6F47476B1DA98E6"
SPLIT_MANIFEST_SHA = "54AC801E94A3E7D1C967560572312F6576CA22CC8E9D4CB67760C4687B8CB16B"
GENERATOR_SHA = "5E8A41FDC5369E52A9C0EF5005DDECD56AE82DB9006D261EEC4A737A5EF2B540"
COMPACT_NAME = "secondary_cnn_key3_stroke_compact_20261101"
RELEASE_NAME = "secondary_cnn_key3_stroke_release_20261031"
CREATION_MANIFEST = "reports/COMPACT_CREATION_MANIFEST.json"
CREATION_MANIFEST_SHA = "72220C1FD51668CD0B9D555EF62AFC268FA4B140B92BC8AC6B417333667BF87E"
KERNEL = "01_rtl/cnn_result_stabilizer.v"
PIPELINE = "01_rtl/vision_pipeline.v"
COMPACT_RTL = {
    KERNEL: ("8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C",
             "9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128"),
    "01_rtl/doc_stroke_planner.v":
        ("DB552C7E3619108DACF894232696B95A573AE194C44E2B6439A744705597E204",
         "1C6AB2F04D6B8CDC0EDAAA6D275A3BCDA314985B5F219BD3EA0A5846518F4CB6"),
    "01_rtl/doc_copy_pipeline.v":
        ("74FEAE6403C59F99D1BD8D9FAFFFDEF147620BA1D580F63BE9B25132A35F8E46",
         "4780D3863ABE4BF0D261445209F914D2636B842E6C1DE23E7987647BAD56E330"),
}
COMPACT_TEST_RUNNERS = {
    "tools/run_stroke_split_regression.py": "69BC73E3DCC627E2B724B09E1FD4CEC3B31D17127C7591533F953427CE91A74B",
    "tools/run_cnn_area_pipeline_compact.py": "6DF6DDF36EE3E5AB79B6691D521C294B62478600ADDDEB9387C3A18818C4CC19",
    "tools/run_compact_metric_boundaries.py": "301A7C5959A60B7428468ABBB6AB9FEFE8116DDD0749A6389EB55AD2D17076EA",
}
APPROVED = {
    "01_rtl/secondary_top.v": "64176506920BFF546415A1D1433FE1F6558FAAA565B5845FA826B56566694DCA",
    "01_rtl/doc_stroke_planner.v": COMPACT_RTL["01_rtl/doc_stroke_planner.v"][1],
    "01_rtl/doc_copy_pipeline.v": COMPACT_RTL["01_rtl/doc_copy_pipeline.v"][1],
    PIPELINE: "6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9",
    KERNEL: COMPACT_RTL[KERNEL][1],
    "04_pin/timing.sdc": "BB8787E049A8DCC445DA077D8C450C77892B14544068C3F94BF5ADEB694700CF",
    "04_pin/apply_reset_exceptions.tcl": "BE1FA0BE99A0097DECEAA38AC7E5FBEEFAC2D54662077D66558292AF6CB30D94",
    "04_pin/prove_key3_supervisor.tcl": "9248199C302656DF4FC264CC6BB74248B4849BF4D447880715D39155DF99C0A5",
}
SKIP_KINDS = {"project", "explicit_dependency", "audit_configuration"}
ACTIVE_KINDS = {"Verilog", "VHDL", "ADC_FILE", "SDC_FILE", "IP_FILE"}
PROOF_DEPENDENCIES = ("04_pin/apply_reset_exceptions.tcl", "04_pin/apply_cdc_exceptions.tcl",
                      "04_pin/prove_key3_supervisor.tcl")


def require(condition, message):
    if not condition:
        raise RuntimeError("Release source scope: " + message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read(path):
    return Path(path).read_text(encoding="utf-8-sig")


def load(path):
    return json.loads(read(path))


def local(root, value):
    path = Path(value)
    path = (path if path.is_absolute() else root / path).resolve()
    require(path.is_relative_to(root), "source escapes independent root: " + str(path))
    require("work" not in {x.lower() for x in path.parts}, "protected work path: " + str(path))
    return path


def verify(path, digest, label):
    require(path.is_file() and sha(path) == digest.upper(), "missing/drifted " + label + ": " + str(path))


def xml(path):
    payload = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;)", "&amp;", read(path))
    return ET.fromstring(payload.replace("::", "_TD_DOUBLE_COLON_"))


def entries(tree, root, base):
    """Preserve excluded entries too; AutoExcluded is not an active source."""
    found, active = {}, {}
    for section in tree.findall("Source_Files/*"):
        for node in section.findall("File"):
            path = Path(node.attrib["Path"])
            path = local(root, path if path.is_absolute() else base / path)
            rel = path.relative_to(root).as_posix()
            require(rel not in found, "duplicate project entry: " + rel)
            attrs = {x.get("Name"): x.get("Val", "").lower() for x in node.findall("FileInfo/Attr")}
            found[rel] = {"kind": section.tag, "auto_excluded": attrs.get("AutoExcluded") == "true",
                          "used_in_syn": attrs.get("UsedInSyn", "true"),
                          "used_in_pnr": attrs.get("UsedInP&R", "true")}
            if not found[rel]["auto_excluded"] and not (attrs.get("UsedInSyn") == attrs.get("UsedInP&R") == "false"):
                active[rel] = section.tag
    return found, active


def generated(root):
    path = local(root, "_gen_project.py")
    verify(path, GENERATOR_SHA, "reviewed project generator")
    # The generator's load_project only parses/imports the project.  Avoid even
    # __pycache__ writes while this read-only gate is running.
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("release_scope_generator", path)
        imported = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(imported)
        require(imported.ROOT.resolve() == root, "generator belongs to another root")
        return imported.load_project()
    finally:
        sys.dont_write_bytecode = previous


def compact_creation_check(root):
    """Bind only three current RTL changes to the immutable copy manifest.

    This grants source scope only. Historical local resource/function reports
    remain provenance; the regression gate still requires fresh current-root
    results before synthesis and bitgen.
    """
    require(root.name == COMPACT_NAME, "compact gate is locked to its independent root")
    release = (root.parent / RELEASE_NAME).resolve()
    require(release != root and "work" not in {p.lower() for p in release.parts},
            "unsafe read-only release root")
    manifest = local(root, CREATION_MANIFEST)
    verify(manifest, CREATION_MANIFEST_SHA, "compact creation manifest")
    data = load(manifest)
    require(data.get("status") == "EXPERIMENTAL_CANDIDATE_NOT_QUALIFIED_NOT_BUILT" and
            data.get("source_baseline_unchanged") is True and data.get("hardware_status") == "NOT_RUN",
            "compact creation status/provenance differs")
    require(Path(data["baseline_root"]).resolve() == release and
            Path(data["project_root"]).resolve() == root, "compact creation belongs to another root")
    require(data.get("production_parameters") == {
        "PCB_ENABLE": 1, "CNN_TRACKS": 4, "CNN_CONFIRM_RESULTS": 3,
        "CNN_HOLD_RESULTS": 2, "CNN_LOST_RESULTS": 3,
        "MAX_EDGES": 32768, "MAX_PATHS": 2048, "MAX_POINTS": 8192,
        "OPT_PASSES": 0, "METRIC_DISTANCE_BOUND": 23164},
        "compact production parameter manifest differs")
    records = data.get("copy_records", [])
    require(len(records) == 352, "compact copy manifest count differs")
    copied, actual_changes = {}, set()
    for item in records:
        relative = item["path"]
        require(relative not in copied, "duplicate compact copy input: " + relative)
        origin = local(release, item["source"])
        require(origin.relative_to(release).as_posix() == relative,
                "compact copied source path identity differs")
        verify(origin, item["sha256"], "read-only release copied input")
        copied[relative] = item["sha256"].upper()
        # Tools/evidence are qualified separately by pinned runners and explicit
        # snapshot dependencies. All RTL/model/IP/constraints/test vectors stay
        # byte-identical except the exact reviewed production delta below.
        if relative.startswith(("tools/", "reports/")):
            continue
        current = local(root, relative)
        if relative == "secondary_cnn_multibox.al":
            require(read(current) == read(origin).replace(RELEASE_NAME, COMPACT_NAME),
                    "compact root project changed beyond rebasing")
        else:
            expected = COMPACT_RTL.get(relative, (None, item["sha256"]))[1]
            verify(current, expected, "compact protected copied source")
            if sha(current) != item["sha256"].upper():
                actual_changes.add(relative)
    require(actual_changes == set(COMPACT_RTL), "compact current source delta is not exactly three RTL files")
    changes = data.get("rtl_changes", [])
    require(len(changes) == len(COMPACT_RTL), "compact recorded RTL change count differs")
    seen, origins = set(), {}
    for item in changes:
        relative = item["path"]
        require(relative in COMPACT_RTL and relative not in seen, "unexpected compact RTL change")
        before, after = COMPACT_RTL[relative]
        require(item.get("before_sha256") == before and item.get("after_sha256") == after and
                copied.get(relative) == before, "compact RTL before/after identity differs")
        verify(local(root, relative), after, "reviewed compact RTL")
        if "candidate_source" in item:
            candidate = Path(item["candidate_source"]).resolve()
            require(candidate.is_relative_to(root.parent) and not candidate.is_relative_to(root) and
                    "work" not in {p.lower() for p in candidate.parts}, "unsafe candidate provenance source")
            verify(candidate, after, "reviewed local candidate source")
            origins[relative] = {"source": str(candidate), "sha256": after}
        seen.add(relative)
    old_copy = read(release / "01_rtl/doc_copy_pipeline.v")
    declaration = "doc_stroke_planner #(.OPT_PASSES(PLANNER_OPT_PASSES),.EXTERNAL_METRIC(1))"
    replacement = "doc_stroke_planner #(.OPT_PASSES(PLANNER_OPT_PASSES),.EXTERNAL_METRIC(1),.METRIC_DISTANCE_BOUND(32'd23164))"
    require(old_copy.count(declaration) == 1 and
            read(root / "01_rtl/doc_copy_pipeline.v") == old_copy.replace(declaration, replacement),
            "doc copy pipeline differs beyond exact finite metric-bound parameter")
    planner = read(root / "01_rtl/doc_stroke_planner.v")
    require("parameter [31:0] METRIC_DISTANCE_BOUND=32'hffffffff" in planner,
            "planner generic default no longer preserves legacy full-domain metric")
    require(".PLANNER_OPT_PASSES(0)" in read(root / "01_rtl/secondary_top.v"),
            "production planner no longer uses zero optimization passes")
    for relative,digest in COMPACT_TEST_RUNNERS.items():
        verify(local(root, relative),digest,"reviewed current compact test runner")
    stroke_runner = read(release / "tools/run_stroke_split_regression.py")
    old_parameter = "doc_stroke_planner #(.OPT_PASSES(OPT_PASSES),.EXTERNAL_METRIC(1),"
    new_parameter = "doc_stroke_planner #(.OPT_PASSES(OPT_PASSES),.EXTERNAL_METRIC(1),.METRIC_DISTANCE_BOUND(32'd23164),"
    old_inputs = 'inputs = [*rtl, ROOT / "model/doc_stroke_reference.py", Path(__file__)]'
    new_inputs = 'inputs = [*rtl, ROOT / "01_rtl/doc_copy_pipeline.v", ROOT / "model/doc_stroke_reference.py", Path(__file__)]'
    require(stroke_runner.count(old_parameter) == stroke_runner.count(old_inputs) == 1 and
        read(root / "tools/run_stroke_split_regression.py") ==
            stroke_runner.replace(old_parameter,new_parameter).replace(old_inputs,new_inputs),
        "document runner differs beyond bound application and current pipeline input binding")
    return {"status": "PASS_EXACT_THREE_RTL_SOURCE_DELTA_ONLY",
        "creation_manifest": CREATION_MANIFEST, "creation_manifest_sha256": CREATION_MANIFEST_SHA,
        "read_only_release_root": str(release), "copied_input_count": len(copied),
        "approved_release_relative_rtl_delta": {key: {"before": value[0], "after": value[1]}
            for key,value in COMPACT_RTL.items()}, "candidate_source_pins": origins,
        "reviewed_current_test_runners":dict(COMPACT_TEST_RUNNERS),
        "formal_regression_acceptance": "NOT_GRANTED_REQUIRES_FRESH_CURRENT_ROOT_SUITES",
        "physical_acceptance": "NOT_GRANTED", "hardware_status": "NOT_RUN"}


def check(root=None, baseline=None, snapshot=None, tree=None):
    root = Path(root or ROOT).resolve()
    compact = compact_creation_check(root)
    require(root != root.parent / CONTROL_NAME and root != root.parent / SPLIT_NAME, "read-only source used as output root")
    require("work" not in {x.lower() for x in root.parts}, "release root is work backup")
    control, split = root.parent / CONTROL_NAME, root.parent / SPLIT_NAME
    control = control.resolve()
    split = split.resolve()
    snapshot_path = control / CONTROL_RUN / "syn_1/source_snapshot.json"
    verify(snapshot_path, CONTROL_SNAPSHOT_SHA, "accepted control frozen snapshot")
    verify(control / "artifacts/dual_fpga_secondary_20261030_cnn_named_coords_conf_diagnostic.bit",
           CONTROL_BIT_SHA, "accepted control bit")
    frozen = load(snapshot_path)
    require(Path(frozen["project_root"]).resolve() == control and len(frozen["files"]) == 138,
            "control frozen snapshot identity/count changed")
    control_sources, control_active = {}, {}
    for item in frozen["files"]:
        source = local(control, item["path"])
        verify(source, item["sha256"], "control frozen input")
        rel = source.relative_to(control).as_posix()
        if item["kind"] not in SKIP_KINDS:
            control_sources[rel] = item["sha256"].upper()
        if item["kind"] in ACTIVE_KINDS:
            control_active[rel] = item["kind"]
    require(len(control_sources) == 132 and len(control_active) == 74, "control closure size changed")
    if baseline is not None:
        require(baseline.get("bit_sha256") == CONTROL_BIT_SHA and
                baseline.get("source_inputs") == control_sources,
                "builder baseline_check result differs from accepted frozen control")

    split_manifest = split / "reports/STROKE_SOURCE_MANIFEST.json"
    verify(split_manifest, SPLIT_MANIFEST_SHA, "reviewed KEY3/stroke manifest")
    split_data = load(split_manifest)
    require(Path(split_data["project_root"]).resolve() == split and len(split_data["files"]) == 169,
            "KEY3/stroke manifest identity/count changed")
    split_sources = {}
    for item in split_data["files"]:
        source = local(split, item["path"])
        verify(source, item["sha256"], "reviewed KEY3/stroke input")
        rel = source.relative_to(split).as_posix()
        require(rel not in split_sources, "duplicate split manifest file")
        split_sources[rel] = item["sha256"].upper()
        verify(local(root, rel), APPROVED.get(rel, item["sha256"]), "release source")

    changed = {rel for rel in control_sources if sha(local(root, rel)) != control_sources[rel]}
    require(changed == {"01_rtl/secondary_top.v", "01_rtl/doc_stroke_planner.v",
                        "01_rtl/doc_copy_pipeline.v", PIPELINE, "04_pin/timing.sdc"},
            "control-relative source changes differ: " + repr(sorted(changed)))
    for rel, digest in control_sources.items():
        verify(local(root, rel), APPROVED.get(rel, digest), "protected control production/model/constraint input")
    for rel, digest in APPROVED.items():
        verify(local(root, rel), digest, "explicitly approved source")

    before = ".LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(24),"
    after = ".LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(22),.AREA_SHIFT(6),"
    split_pipeline = read(split / PIPELINE)
    require(split_pipeline.count(before) == 1 and read(root / PIPELINE) == split_pipeline.replace(before, after),
            "pipeline is not exactly the reviewed AREA_BITS22/AREA_SHIFT6 parameter edit")
    verify(control / "04_pin/apply_reset_exceptions.tcl",
           "A0F8C9F6926B9A7EA3DD16749C5CAB211F4A78FAE77060DD84186DCD9B2C77A7", "control reset hook")
    control_reset = read(control / "04_pin/apply_reset_exceptions.tcl")
    require(read(root / "04_pin/apply_reset_exceptions.tcl") == control_reset.replace(
                "{u_reset125 clk125 por_release rst125_n INV}",
                "{u_reset125 clk125 board_release rst125_n INV}").replace(
                "{u_store_resetddr ddr_clk por_release store_rstddr_n INV}",
                "{u_store_resetddr ddr_clk board_release store_rstddr_n INV}"),
            "reset hook differs beyond the two reviewed POR-to-board_release source changes")
    require(sha(root / "tools/release_audit_config.json") == sha(control / "tools/release_audit_config.json"),
            "memory-resolution/exception audit configuration changed")
    verify(root / "_gen_project.py", GENERATOR_SHA, "reviewed generator")

    # Root project may only rebase its independent-copy path, preserving all
    # other source choices, flags and order exactly.
    old_project = read(split / "secondary_cnn_multibox.al")
    require(read(root / "secondary_cnn_multibox.al") == old_project.replace(SPLIT_NAME, root.name),
            "root project changed beyond independent-root path rebasing")
    tree = tree if tree is not None else generated(root)
    all_entries, active = entries(tree, root, root)
    # The generator removes historical duplicate compact cores and adds the
    # one stabilizer.  Its exact hash and complete generated closure are both
    # checked, rather than accepting an arbitrary 'one additional source'.
    expected_active = dict(control_active)
    expected_active[KERNEL] = "Verilog"
    require(active == expected_active, "generated active source identities differ; missing=" +
            repr(sorted(set(expected_active) - set(active))) + "; added=" + repr(sorted(set(active) - set(expected_active))))
    require(len(all_entries) == 80 and len(active) == 75, "expected 80 project entries / 75 active inputs")
    excluded = sorted(rel for rel in all_entries if rel not in active)
    require(len(excluded) == 5, "historical AutoExcluded entries changed")
    for rel in all_entries:
        require(rel in split_sources or rel in control_sources, "project input absent from reviewed source manifests: " + rel)
        verify(root / rel, APPROVED.get(rel, split_sources.get(rel, control_sources.get(rel))), "generated project entry")

    snapshot_status = "NOT_SUPPLIED_PREPARE_ONLY"
    if snapshot is not None:
        snapshot = load(snapshot) if isinstance(snapshot, (str, Path)) else snapshot
        require(snapshot.get("passed") is True and not snapshot.get("errors"), "generated snapshot did not pass")
        require(Path(snapshot["project_root"]).resolve() == root, "snapshot belongs to another project")
        canonical = [{key: item[key] for key in ("path", "kind", "sha256")}
                     for item in sorted(snapshot["files"], key=lambda item: item["path"].lower())]
        digest = hashlib.sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest().upper()
        require(digest == snapshot.get("manifest_sha256"), "snapshot manifest digest differs")
        seen, current_sources = {}, {}
        for item in snapshot["files"]:
            source = local(root, item["path"])
            rel = source.relative_to(root).as_posix()
            require(rel not in seen, "duplicate snapshot input: " + rel)
            verify(source, item["sha256"], "current snapshot input")
            seen[rel] = item
            if item["kind"] not in SKIP_KINDS:
                current_sources[rel] = item["sha256"].upper()
        expected_sources = {rel: APPROVED.get(rel, digest) for rel, digest in control_sources.items()}
        expected_sources[KERNEL] = APPROVED[KERNEL]
        require(current_sources == expected_sources, "active transitive source/model/IP closure differs from control + stabilizer")
        for rel in PROOF_DEPENDENCIES:
            require(rel in seen and seen[rel]["kind"] == "explicit_dependency",
                    "proof hook must be explicitly frozen with --extra: " + rel)
            verify(root / rel, APPROVED.get(rel, split_sources.get(rel)), "frozen reset/CDC/KEY3 proof hook")
        snapshot_status = "PASS_COMPLETE_CLOSURE_AND_PROOF_HOOKS"

    return {"status": "PASS_SOURCE_SCOPE_ONLY", "root": str(root),
        "control_snapshot_sha256": CONTROL_SNAPSHOT_SHA, "control_bit_sha256": CONTROL_BIT_SHA,
        "split_manifest_sha256": SPLIT_MANIFEST_SHA, "control_source_count": len(control_sources),
        "reviewed_source_count": len(split_sources), "project_entries": len(all_entries),
        "active_project_entries": len(active), "auto_excluded_entries": excluded,
        "intentional_control_changes": sorted(changed), "approved_sha256": dict(APPROVED),
        "new_source": KERNEL, "new_source_sha256": APPROVED[KERNEL],
        "pipeline_contract": {"AREA_BITS": 22, "AREA_SHIFT": 6, "COORD_SHIFT": 3},
        "proof_hook_dependencies": {rel: sha(root / rel) for rel in PROOF_DEPENDENCIES},
        "snapshot_scope": snapshot_status, "protected_sources_unchanged": True,
        "compact_creation": compact,
        "physical_acceptance": "NOT_GRANTED_REQUIRES_CURRENT_DATABASE_ENDPOINT_PROOFS",
        "hardware_status": "NOT_RUN"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--snapshot", type=Path)
    args = parser.parse_args()
    print(json.dumps(check(args.root, snapshot=args.snapshot), indent=2))


if __name__ == "__main__":
    main()
