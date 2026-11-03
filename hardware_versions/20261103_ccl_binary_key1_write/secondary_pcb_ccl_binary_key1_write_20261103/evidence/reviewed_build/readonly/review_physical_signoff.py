from __future__ import annotations

import hashlib
import json
import posixpath
import re
from collections import Counter
from pathlib import Path


BUILD = Path(r"E:\codex_pcb_binary_ccl_retrained_20261103_key1")
SOURCE = Path(r"D:\program\fpga\lab_ex3_osd_SC500_720P\secondary_pcb_ccl_binary_key1_write_20261103")
BASE_BUILD = Path(r"E:\codex_pcb_pose7_20261102_r5")
BASE_PLAN = json.loads((BUILD / "BUILD_PLAN.json").read_text(encoding="utf-8-sig"))
BASE_MANIFEST = json.loads((BASE_BUILD / "SOURCE_MANIFEST.json").read_text(encoding="utf-8-sig"))["files"]
NAME = "secondary_cnn_multibox"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig", errors="replace")


def require(ok: bool, message: str, errors: list[str]) -> None:
    if not ok:
        errors.append(message)


def main() -> int:
    phy = BUILD / "runs/phy_1"
    ro = BUILD / "readonly"
    errors: list[str] = []
    checks: dict[str, object] = {}
    evidence: dict[str, str] = {}

    manifest_path = BUILD / "SOURCE_MANIFEST.json"
    manifest = json.loads(read(manifest_path))
    evidence[str(manifest_path)] = sha(manifest_path)
    frozen_errors = []
    for rel, entry in manifest["files"].items():
        path = BUILD / rel
        if not path.is_file() or sha(path) != entry["sha256"].upper():
            frozen_errors.append(rel)
    require(not frozen_errors, "Frozen source manifest mismatch", errors)
    checks["manifest"] = {"entries": len(manifest["files"]), "mismatches": frozen_errors}

    # The tool snapshot may spell a dependency as runs/model/... while the
    # frozen manifest records its project-relative source as runs/syn_1/../model/....
    # Compare normalized paths and hashes so these aliases are explicit evidence.
    snapshot_path = phy / "source_snapshot.json"
    snapshot = json.loads(read(snapshot_path)) if snapshot_path.is_file() else {}
    if snapshot_path.is_file():
        evidence[str(snapshot_path)] = sha(snapshot_path)
    manifest_sha = sha(manifest_path)
    plan_manifest_sha = str(BASE_PLAN.get("source_manifest_sha256", "")).upper()
    plan_manifest_bound = plan_manifest_sha == manifest_sha
    require(plan_manifest_bound, "Frozen source manifest hash differs from BUILD_PLAN.json", errors)
    snapshot_root = str(BUILD).replace("\\", "/").rstrip("/")
    manifest_index: dict[str, list[tuple[str, dict[str, object]]]] = {}
    for rel, entry in manifest["files"].items():
        normalized = posixpath.normpath(rel.replace("\\", "/")).casefold()
        manifest_index.setdefault(normalized, []).append((rel, entry))
    source_matches = 0
    exact_path_matches = 0
    path_aliases: list[dict[str, object]] = []
    snapshot_errors: list[str] = []
    snapshot_files = snapshot.get("files", [])
    for item in snapshot_files:
        absolute = str(item.get("path", "")).replace("\\", "/")
        prefix = snapshot_root + "/"
        if not absolute.casefold().startswith(prefix.casefold()):
            snapshot_errors.append(f"Snapshot path is outside build root: {absolute}")
            continue
        relative = posixpath.normpath(absolute[len(prefix):])
        normalized = relative.casefold()
        candidates = manifest_index.get(normalized, [])
        if not candidates:
            snapshot_errors.append(f"Snapshot source is absent from manifest after path normalization: {relative}")
            continue
        snapshot_hash = str(item.get("sha256", "")).upper()
        candidate_hashes = {str(candidate.get("sha256", "")).upper() for _, candidate in candidates}
        candidate_bytes = {candidate.get("bytes") for _, candidate in candidates}
        if candidate_hashes != {snapshot_hash} or candidate_bytes != {item.get("bytes")}:
            snapshot_errors.append(f"Snapshot source hash/size differs from manifest: {relative}")
            continue
        source_matches += 1
        manifest_paths = [manifest_rel for manifest_rel, _ in candidates]
        if relative in manifest_paths:
            exact_path_matches += 1
        else:
            path_aliases.append({"snapshot_path": relative, "manifest_paths": manifest_paths,
                                 "sha256": snapshot_hash, "bytes": item.get("bytes")})
    snapshot_content = [
        {key: item[key] for key in ("path", "kind", "sha256")}
        for item in sorted(snapshot_files, key=lambda entry: str(entry.get("path", "")).lower())
    ]
    snapshot_closure_sha = hashlib.sha256(
        json.dumps(snapshot_content, sort_keys=True).encode()
    ).hexdigest().upper()
    snapshot_manifest_sha = str(snapshot.get("manifest_sha256", "")).upper()
    snapshot_manifest_bound = snapshot_manifest_sha == snapshot_closure_sha
    require(snapshot_path.is_file(), "Routed source snapshot is missing", errors)
    require(snapshot_manifest_bound, "Routed source snapshot closure digest is invalid", errors)
    require(not snapshot_errors and source_matches == len(snapshot_files),
            f"Routed source snapshot does not bind cleanly to frozen manifest: {snapshot_errors}", errors)
    checks["source_snapshot_binding"] = {
        "status": "PASS" if snapshot_path.is_file() and plan_manifest_bound and snapshot_manifest_bound and not snapshot_errors and source_matches == len(snapshot_files) else "FAIL",
        "snapshot_file_count": len(snapshot_files),
        "matched_file_count": source_matches,
        "exact_path_match_count": exact_path_matches,
        "normalized_path_alias_count": len(path_aliases),
        "normalized_path_aliases": path_aliases,
        "build_manifest_file_sha256": manifest_sha,
        "build_plan_manifest_sha256": plan_manifest_sha,
        "build_plan_manifest_bound": plan_manifest_bound,
        "snapshot_manifest_sha256": snapshot.get("manifest_sha256"),
        "recomputed_snapshot_closure_sha256": snapshot_closure_sha,
        "snapshot_closure_digest_valid": snapshot_manifest_bound,
        "errors": snapshot_errors,
        "path_normalization": "POSIX normpath on project-relative paths; backslashes normalized to slashes before comparison.",
    }

    db = phy / f"{NAME}_pr.db"
    expected_db = "E860BA850D48DB69DD7E31355F2810C5E2A25DAEA30AC3910E41418AE901D2A8"
    require(db.is_file() and sha(db) == expected_db, "Routed database hash differs from frozen readonly verification", errors)
    if db.is_file():
        evidence[str(db)] = sha(db)

    cdc_report = ro / "physical_cdc_readonly.rpt"
    cdc_text = read(cdc_report) if cdc_report.is_file() else ""
    if cdc_report.is_file():
        evidence[str(cdc_report)] = sha(cdc_report)
    require("PHYSICAL_CDC_READONLY_PASS" in cdc_text, "Current routed DB physical CDC connectivity proof did not complete", errors)
    expected_groups = {
        "control_d": 5, "control_q": 9, "control_regs": 5, "gray_d": 52,
        "link_d": 1, "request_q": 162, "return_d": 128,
        "return_q": 128, "same_domain_d": 60, "stage2_d": 118,
    }
    actual_groups = {name: int(count) for name, count in re.findall(r"^GROUP (\w+) (\d+)$", cdc_text, re.M)}
    require(actual_groups == expected_groups, f"CDC physical proof group inventory mismatch: {actual_groups}", errors)
    require("RESET_TARGETS 10" in cdc_text and "RESET_SYNCHRONIZERS 5" in cdc_text,
            "Reset synchronizer proof inventory mismatch", errors)
    checks["physical_cdc_fifo"] = {
        "proof_status": "PASS" if not any("CDC" in e or "synchronizer" in e or "routed DB physical" in e for e in errors) else "FAIL",
        "groups": actual_groups,
        "proof_records": sum(1 for line in cdc_text.splitlines() if line.startswith(("CDC_PROOF ", "RESET_PROOF "))),
        "scope": "Current routed cell/net connectivity, two-stage synchronizers, Gray FIFO pointers, held mailbox buses, return buses, clocks/resets, and reset synchronizers.",
    }

    exception_path = phy / "secondary_effective_route_end.exceptions.rpt"
    exception_text = read(exception_path) if exception_path.is_file() else ""
    if exception_path.is_file():
        evidence[str(exception_path)] = sha(exception_path)
    path_rows = [(int(total), int(dominated), int(shadowed), int(ignored)) for total, dominated, shadowed, ignored in
                 re.findall(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+set_", exception_text, re.M)]
    expected_counts = [290, 128, 9, 52]
    effective = bool(path_rows) and [r[0] for r in path_rows] == expected_counts and all(r[0] == r[1] and not r[2] and not r[3] for r in path_rows)
    slack_rows = [float(v) for v in re.findall(r"^Slack\s*:\s*([-+\d.]+)ns?\s*$", exception_text, re.M)]
    require(effective, f"CDC/FIFO exception coverage is missing, shadowed, ignored, or mismatched: {path_rows}", errors)
    require(bool(slack_rows) and min(slack_rows) >= 0, "No nonnegative routed max-delay slack evidence for CDC/mailbox paths", errors)
    checks["cdc_fifo_timing"] = {
        "effective_constraint_path_counts": [r[0] for r in path_rows],
        "expected_counts": expected_counts,
        "all_paths_dominated_unshadowed_unignored": effective,
        "reported_slack_count": len(slack_rows),
        "minimum_reported_slack_ns": min(slack_rows) if slack_rows else None,
    }

    plan_protected = BASE_PLAN["original_vendor_flow"].get("protected_constraint_ip_sha256", {})
    source_manifest_files = manifest["files"]
    ddr_rel = [rel for rel in source_manifest_files if "ph1p35_ddr/ddr2/" in rel.replace("\\", "/")]
    protected_checked = {}
    for rel in ddr_rel:
        path = BUILD / rel
        expected = plan_protected.get(rel)
        reference = BASE_MANIFEST.get(rel, {}).get("sha256")
        actual = sha(path) if path.is_file() else None
        entry_hash = source_manifest_files[rel]["sha256"].upper()
        ok = bool(actual and actual == entry_hash and reference and actual == reference.upper()
                  and (expected is None or actual == expected.upper()))
        protected_checked[rel] = {"sha256": actual, "manifest_match": actual == entry_hash,
                                  "pose7_r5_match": None if reference is None else actual == reference.upper(),
                                  "original_flow_protected_match": None if expected is None else actual == expected.upper()}
        if not ok:
            errors.append(f"DDR source/IP/constraint identity mismatch: {rel}")
            continue
        evidence[str(path)] = actual
    require(bool(ddr_rel), "DDR IP/constraint files absent from frozen manifest", errors)
    checks["ddr_identity"] = {
        "status": "PASS" if ddr_rel and all(v["manifest_match"] and v["pose7_r5_match"] and v["original_flow_protected_match"] is not False for v in protected_checked.values()) else "FAIL",
        "checked_file_count": len(ddr_rel),
        "files": protected_checked,
        "wrapper_contract_sha256": source_manifest_files.get("01_rtl/secondary_ddr_wrapper.v", {}).get("sha256"),
        "store_mailbox_sha256": source_manifest_files.get("01_rtl/hxa_ddr_store.v", {}).get("sha256"),
        "scope": "Frozen DDR2 IP, configuration ROM, ADC/SDC and wrapper identity; not a DDR electrical or hardware memory test.",
    }

    readonly_check = ro / "readonly.check"
    check_text = read(readonly_check) if readonly_check.is_file() else ""
    clocks_text = read(ro / "readonly.clocks") if (ro / "readonly.clocks").is_file() else ""
    checks["timing_constraints"] = {
        "no_clock_nets": re.search(r"checking no clock\(0\)", check_text) is not None,
        "invalid_constraints": re.search(r"checking invalid constraint\(0\)", check_text) is not None,
        "comb_loops": re.search(r"checking combinational loops\(0\)", check_text) is not None,
        "soft_fifo_timing_exception_checks": re.search(r"checking soft fifo timing exception constraints\(2\)", check_text) is not None,
        "generated_clock_connectivity": re.search(r"2\.5 There are 0 generated clocks that are not connected to their master clocks", check_text) is not None,
        "ddr_user_and_ref_clock_reported": "u_ddr/u_ddr2/usr_clk" in clocks_text and "ddr_ref100" in clocks_text,
        "ddr_controller_clock_period_7p5ns": re.search(r"u_ddr/u_ddr2/usr_clk\s*\|\s*7\.500", clocks_text) is not None,
    }
    require(all(checks["timing_constraints"].values()), "Readonly timing/clock/FIFO constraint audit has missing or failing categories", errors)
    if readonly_check.is_file():
        evidence[str(readonly_check)] = sha(readonly_check)

    drc_path = ro / "routed.drc"
    drc_evidence_path = ro / "evidence/drc.json"
    drc_text = read(drc_path) if drc_path.is_file() else ""
    drc_evidence = json.loads(read(drc_evidence_path)) if drc_evidence_path.is_file() else {}
    if drc_path.is_file():
        evidence[str(drc_path)] = sha(drc_path)
    if drc_evidence_path.is_file():
        evidence[str(drc_evidence_path)] = sha(drc_evidence_path)
    if (ro / "drc_reimport.tcl").is_file():
        evidence[str(ro / "drc_reimport.tcl")] = sha(ro / "drc_reimport.tcl")
    drc_rows = re.findall(r"^\|\s*([A-Z]+-\d+)\s*\|\s*(NOTE|WARN(?:ING)?|ERROR|FATAL)\s*\|.*?\|\s*(\d+)\s*\|\s*$", drc_text, re.M | re.I)
    notes = Counter({rule: int(count) for rule, severity, count in drc_rows if severity.upper() == "NOTE"})
    errors_n = sum(int(count) for _, severity, count in drc_rows if severity.upper() in {"ERROR", "FATAL"})
    warns_n = sum(int(count) for _, severity, count in drc_rows if severity.upper().startswith("WARN"))
    drc_hash_match = drc_evidence.get("artifacts", [{}])[0].get("sha256") == (sha(drc_path) if drc_path.is_file() else None)
    require(drc_path.is_file() and drc_evidence.get("status") == "PASS" and drc_hash_match and errors_n == 0 and warns_n == 0 and sum(notes.values()) == 72,
            "Routed DRC report is missing or contains ERROR/WARN/unexpected NOTE count", errors)
    checks["drc"] = {"status": "PASS" if drc_path.is_file() and drc_evidence.get("status") == "PASS" and drc_hash_match and not errors_n and not warns_n else "FAIL",
                      "notes": dict(notes), "error_count": errors_n, "warning_count": warns_n,
                      "source": str(drc_path)}

    result = {
        "status": "PASS_PHYSICAL_CDC_DDR_FIFO_REVIEW" if not errors else "REVIEW_REQUIRED",
        "errors": errors,
        "build_root": str(BUILD),
        "source_root": str(SOURCE),
        "routed_database_sha256": sha(db) if db.is_file() else None,
        "checks": checks,
        "evidence_sha256": evidence,
        "bit_status": "ALREADY_GENERATED_BEFORE_THIS_REVIEW; no gate retroactively asserted",
        "scope_limits": [
            "Static mapped connectivity and timing evidence only; this does not prove FIFO data-loss behavior under all traffic.",
            "DDR IP/config/constraints and routed clock/timing binding are checked; board-level DDR calibration and memory test remain NOT_RUN.",
            "DRC NOTE items are recorded; absence of ERROR/WARN does not certify PCB pin/electrical conditions beyond the tool report.",
        ],
    }
    out = ro / "PHYSICAL_CDC_DDR_FIFO_REVIEW.json"
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "errors": errors,
                      "checks": checks}, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
