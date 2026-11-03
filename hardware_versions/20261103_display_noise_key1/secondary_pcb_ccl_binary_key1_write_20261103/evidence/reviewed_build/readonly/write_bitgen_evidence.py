import hashlib
import json
from pathlib import Path


BUILD = Path(r"E:\codex_pcb_binary_ccl_retrained_20261103_key1")
SOURCE = Path(r"D:\program\fpga\lab_ex3_osd_SC500_720P\secondary_pcb_ccl_binary_key1_write_20261103")
REPORTS = SOURCE / "reports/retrained"
MANIFEST = json.loads((BUILD / "SOURCE_MANIFEST.json").read_text(encoding="utf-8"))["files"]


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def frozen_sources(*paths):
    result = {}
    for relative in paths:
        record = MANIFEST[relative]
        actual = sha(BUILD / relative)
        if actual != record["sha256"]:
            raise RuntimeError(f"frozen source drift: {relative}")
        result[relative] = actual
    return result


def evidence(check, report, sources, scope, limitations=(), artifacts=()):
    report = report.resolve()
    if not report.is_file():
        raise RuntimeError(f"missing evidence report: {report}")
    rows = [{"path": str(path.resolve()), "sha256": sha(path)} for path in (report, *artifacts)]
    record = {
        "status": "PASS",
        "check": check,
        "scope": scope,
        "limitations": list(limitations),
        "artifacts": rows,
        "source_sha256": sources,
    }
    out = BUILD / "readonly/evidence" / f"{check}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    return {
        "path": str(out.resolve()),
        "sha256": sha(out),
        "status": "PASS",
        "source_sha256": sources,
    }


def require_pass(path, label):
    result = load(path)
    if result.get("status") != "PASS":
        raise RuntimeError(f"{label} did not pass: {result.get('status')}")
    return result


def main():
    pipeline = REPORTS / "binary_validation/pipeline/run_20261103T033308_256929Z/RESULTS.json"
    core = REPORTS / "binary_validation/core/run_20261103T032410_695075Z/RESULTS.json"
    regressions = REPORTS / "regressions/run_20261103T025706_248559Z/RESULTS.json"
    document = REPORTS / "regressions/run_20261103T025706_248559Z/document/RESULTS.json"
    writing = REPORTS / "regressions/run_20261103T025706_248559Z/plotter/RESULTS.json"
    ordinary = REPORTS / "regressions/run_20261103T025706_248559Z/ordinary/integer27/RESULTS.json"
    hxa = REPORTS / "regressions/run_20261103T025706_248559Z/hxa/RESULTS.json"
    reader = REPORTS / "regressions/run_20261103T025706_248559Z/reader/RESULTS.json"
    cdc_report = BUILD / "runs/phy_1/secondary_cdc_route_end.rpt"
    fifo_report = BUILD / "runs/phy_1/secondary_cdc_route_end.rpt"
    physical_review = BUILD / "readonly/PHYSICAL_CDC_DDR_FIFO_REVIEW.json"
    ddr_reports = [reader, BUILD / "readonly/readonly.timing", BUILD / "readonly/readonly.area", BUILD / "readonly/readonly.clocks"]
    drc_report = BUILD / "readonly/routed.drc"
    readonly_report = BUILD / "READONLY_VERIFICATION.json"

    pipe = require_pass(pipeline, "integrated binary PCB pipeline")
    if pipe.get("frames_passed") != 22 or pipe.get("cancels_passed") != 3 or not pipe.get("ordinary_empty_passed"):
        raise RuntimeError("integrated PCB pipeline coverage is incomplete")
    for relative, digest in pipe["frozen_design_inputs"].items():
        if relative in MANIFEST and MANIFEST[relative]["sha256"] != digest:
            raise RuntimeError(f"pipeline source differs from frozen build: {relative}")
    require_pass(core, "binary integer core")
    if load(core).get("samples_passed") != 18:
        raise RuntimeError("binary core vector count differs")
    regression_data = require_pass(regressions, "preserved regression suite")
    if len(regression_data.get("suite_results", [])) != 10 or any(x.get("status") != "PASS" for x in regression_data["suite_results"]):
        raise RuntimeError("preserved regression suite is incomplete")
    for report, label in [(document, "document regression"), (writing, "writing regression"), (ordinary, "ordinary CNN regression"), (hxa, "HXA/FIFO regression"), (reader, "DDR mailbox/reader regression")]:
        require_pass(report, label)

    physical = load(physical_review)
    if physical.get("status") != "PASS_PHYSICAL_CDC_DDR_FIFO_REVIEW":
        raise RuntimeError(f"current routed physical CDC/DDR/FIFO review did not pass: {physical.get('status')}")
    if physical.get("routed_database_sha256") != sha(BUILD / "runs/phy_1/secondary_cnn_multibox_pr.db"):
        raise RuntimeError("physical review is not bound to the current routed database")
    if physical.get("checks", {}).get("source_snapshot_binding", {}).get("matched_file_count") != 176:
        raise RuntimeError("routed source snapshot is not fully bound to the frozen manifest")

    cdc_text = cdc_report.read_text(encoding="utf-8", errors="replace")
    if "CDC_MAPPING_COMPLETE" not in cdc_text:
        raise RuntimeError("current routed CDC mapping report is incomplete")
    drc_text = drc_report.read_text(encoding="utf-8", errors="replace")
    if "Violations found\t: 72" not in drc_text or "| SLATR-1036 | NOTE" not in drc_text or "| SLATR-1038 | NOTE" not in drc_text:
        raise RuntimeError("routed DRC report does not match the reviewed NOTE-only result")
    if any(token in drc_text.upper() for token in ["\nERROR ", "\nFATAL "]):
        raise RuntimeError("routed DRC contains an error")
    if load(readonly_report).get("status") != "PASS_READONLY":
        raise RuntimeError("readonly reimport did not pass")

    evidence_rows = {}
    evidence_rows["binary_integer"] = evidence(
        "binary_integer", pipeline,
        frozen_sources("01_rtl/vision_pipeline.v", "01_rtl/edge_roi_ccl_shared_pcb_candidate.v", "01_rtl/vision_ccl_pcb_candidate.v", "01_rtl/pcb_ccl_binary_core.v", "01_rtl/pcb_fullboard_spatial96.v", "01_rtl/vision_workspace_goodonly.v", "01_rtl/vision_shared_mac.v", "model/experiments/conv4_4/weights.mem", "model/experiments/conv4_4/biases.mem"),
        "18 integer core vectors and 18 full pipeline fixtures, including 22 completed frames, 3 cancellation points, and ordinary-empty reentry.",
        pipe.get("limitations", []), [core])
    evidence_rows["ordinary_cnn"] = evidence(
        "ordinary_cnn", ordinary,
        frozen_sources("01_rtl/cnn_core.v", "01_rtl/vision_pipeline.v", "01_rtl/vision_workspace_goodonly.v", "01_rtl/vision_shared_mac.v", "01_rtl/cnn_result_stabilizer.v", "model/export/weights.mem", "model/export/biases.mem"),
        "27 numerical RTL vectors for the existing ordinary CNN path.",
        ["Archived/synthetic regression vectors only; this does not establish independent field accuracy."])
    evidence_rows["document"] = evidence(
        "document", document,
        frozen_sources("01_rtl/doc_image_frontend.v", "01_rtl/doc_stroke_planner.v", "01_rtl/doc_machine_map.v", "01_rtl/doc_grbl_plotter.v", "01_rtl/doc_grbl_streamer.v", "01_rtl/doc_grbl_response_parser.v"),
        "Blank/noisy/ink frontend, skeleton/path/coordinate mapping, and acknowledged G-code regressions.",
        ["Archived fixtures and RTL simulations; no new handwriting field-quality claim."])
    evidence_rows["writing"] = evidence(
        "writing", writing,
        frozen_sources("01_rtl/grbl_line_formatter.v", "01_rtl/grbl_response_parser.v", "01_rtl/grbl_shared_transport_candidate.v", "01_rtl/grbl_reporter_shared_candidate.v", "01_rtl/doc_copy_pipeline_shared_candidate.v"),
        "Shared report/document transport, ACK serialization, stop/recovery, lost-OK no-replay, and repeated KEY2 behavior.",
        ["GRBL ACK confirms command acceptance, not physical motion completion."])
    evidence_rows["cancel_reentry"] = evidence(
        "cancel_reentry", regressions,
        frozen_sources("01_rtl/secondary_top.v", "01_rtl/hxa_ddr_store.v", "01_rtl/vision_pixel_reader.v", "01_rtl/grbl_shared_transport_candidate.v", "shared/rtl/hxa_secondary_link.v", "shared/rtl/hxa_packet_rx_fifo4.v", "main/user_source/hdl_source/reset_sync.v"),
        "Ten preserved suites covering task ownership, HXA/CRC/lease changes, KEY1, KEY3 reset, cancellation, and reader reentry.",
        ["Behavioral tests do not establish physical CDC metastability margins or external machine behavior."])
    evidence_rows["cdc"] = evidence(
        "cdc", cdc_report,
        frozen_sources("04_pin/apply_cdc_exceptions.tcl", "04_pin/timing.sdc", "01_rtl/hxa_ddr_store.v", "01_rtl/secondary_ddr_wrapper.v"),
        "Current routed database CDC mapping, source-snapshot binding, and max-delay constraint paths are checked in the attached physical review.",
        ["Static mapped connectivity and timing review only; not an independent metastability signoff."],
        [BUILD / "runs/phy_1/secondary_cdc_route_end.sdc", physical_review])
    evidence_rows["fifo"] = evidence(
        "fifo", hxa,
        frozen_sources("shared/rtl/hxa_packet_rx_fifo4.v", "shared/rtl/hxa_secondary_link.v", "01_rtl/grbl_shared_transport_candidate.v"),
        "FIFO behavior regression and current routed Gray-pointer/held-bus topology and timing exception mapping are recorded.",
        ["Behavior is simulation plus static mapping review; no exhaustive formal FIFO proof was run."],
        [fifo_report, physical_review])
    evidence_rows["ddr"] = evidence(
        "ddr", reader,
        frozen_sources("01_rtl/secondary_ddr_wrapper.v", "01_rtl/hxa_ddr_store.v", "01_rtl/vision_pixel_reader.v", "main/user_source/hdl_source/ph1p35_ddr/ddr2/ddr2.v"),
        "DDR source/IP identity, routed clock/timing binding, and dual-clock mailbox/reader behavior are recorded.",
        ["No physical DDR calibration, board memory test, or vendor PHY transaction simulation was performed."],
        [*ddr_reports[1:], physical_review])
    evidence_rows["drc"] = evidence(
        "drc", drc_report,
        frozen_sources("04_pin/timing.sdc", "04_pin/apply_cdc_exceptions.tcl", "01_rtl/secondary_top.v"),
        "Default device DRC completed on the current routed database with no ERROR/FATAL findings; 72 NOTE-level slice attribute findings are retained.",
        ["The 72 NOTE findings are not silently suppressed; details are in routed.drc."], [BUILD / "readonly/drc_reimport.tcl"])
    evidence_rows["readonly"] = evidence(
        "readonly", readonly_report,
        frozen_sources("04_pin/timing.sdc", "01_rtl/secondary_top.v", "01_rtl/secondary_ddr_wrapper.v"),
        "Read-only reimport of the current routed database passed; setup/hold timing, area, clocks, and constraints were re-reported.",
        ["The read-only import does not execute bitgen or test external hardware."], [BUILD / "readonly/readonly.timing", BUILD / "readonly/readonly.area", BUILD / "readonly/readonly.check"])

    database = BUILD / "runs/phy_1/secondary_cnn_multibox_pr.db"
    gate = {
        "source_manifest_sha256": sha(BUILD / "SOURCE_MANIFEST.json"),
        "routed_database_sha256": sha(database),
        "checks": {name: True for name in sorted(evidence_rows)},
        "evidence": evidence_rows,
        "hardware_status": "NOT_RUN",
        "summary_limitations": [
            "CDC report covers mapped constraints, not independent CDC signoff.",
            "DDR PHY calibration and board memory operation remain NOT_RUN.",
            "DRC contains 72 NOTE-level findings and no ERROR/FATAL findings.",
            "All behavioral verification is simulation; the diagnostic bit requires board validation.",
        ],
    }
    out = BUILD / "readonly/BITGEN_EVIDENCE_GATE.json"
    out.write_text(json.dumps(gate, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "EVIDENCE_GATE_READY", "path": str(out), "source_manifest_sha256": gate["source_manifest_sha256"], "routed_database_sha256": gate["routed_database_sha256"], "checks": sorted(evidence_rows)}, indent=2))


if __name__ == "__main__":
    main()
