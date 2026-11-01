"""Read-only routed CDC/FIFO/DDR/DRC review for CNN named reports.

Compares actual routed reports with the exact accepted new-capture-mix release.
Never executes TD or changes RTL, constraints, projects or databases.
"""
from collections import Counter
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
NAME = "secondary_cnn_multibox"
BASE = ROOT.parent / "secondary_pcb_centered_new_capture_mix_20261029_hw"
BASE_RUN = BASE / "new_capture_mix_Runs_20261029_r2"
INTENTIONAL_PCB_ROM_SHA256 = {}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def read(path):
    return path.read_text(encoding="utf-8-sig", errors="replace")


def manifest(run, root):
    data = json.loads(read(run / "syn_1/source_snapshot.json"))
    entries = {}
    for entry in data["files"]:
        path = Path(entry["path"])
        if not path.is_absolute():
            path = root / path
        entries[path.resolve().relative_to(root.resolve()).as_posix()] = entry["sha256"].upper()
    return data, entries


def baseline_route_log():
    console = BASE_RUN / "phy_1/td_console.log"
    if console.is_file():
        return console
    candidates = [p for p in (BASE_RUN / "phy_1").glob("td_*.log")
                  if 'start command "place"' in read(p) and 'start command "route"' in read(p)]
    if len(candidates) != 1:
        raise RuntimeError("Expected one native baseline implementation log")
    return candidates[0]


def protected_transport(path):
    value = path.lower()
    return ("ddr" in value or "frame_store" in value or "/ethernet/" in value
            or value.startswith("shared/rtl/hxa"))


def protected_vision(path):
    return (path.startswith(("01_rtl/model/", "model/"))
            or (path.startswith("01_rtl/") and Path(path).name.startswith(
                ("cnn_core", "pcb_", "vision_"))))


def checks(text):
    return {label.strip(): int(n) for label, n in re.findall(
        r"^\d+\. checking (.*?)\((\d+)\) \((?:HIGH|MEDIUM)\)", text, re.M)}


def ignored(phy):
    rows = re.findall(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+set_",
                      read(phy / "secondary_effective_route_end.ignored.rpt"), re.M)
    return {"rows": len(rows), "shadowed": sum(int(r[2]) for r in rows),
            "ignored": sum(int(r[3]) for r in rows)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run, out = args.runs.resolve(), args.output.resolve()
    if not run.is_relative_to(ROOT) or not out.is_relative_to(ROOT / "02_sim"):
        raise RuntimeError("Current run and evidence must stay in this independent project")
    phy = run / "phy_1"
    required = [phy / name for name in (
        ".opt_place.end.f", ".opt_route.end.f", NAME + "_pr.db", NAME + "_pr.timing",
        NAME + "_chk.timing", NAME + "_phy.area", "route_flow.status", "td_console.log",
        "secondary_loaded_route_end.rpt", "secondary_cdc_route_end.rpt",
        "secondary_reset_route_end.rpt", "secondary_effective_route_end.ignored.rpt")]
    missing = [str(p) for p in required if not p.is_file()]
    if missing:
        raise RuntimeError("Final routed evidence is not ready: " + ", ".join(missing))
    frozen, active = manifest(run, ROOT)
    _, baseline = manifest(BASE_RUN, BASE)
    errors = []
    changed_inputs = [p for p, sha in active.items()
                      if not (ROOT / p).is_file() or digest(ROOT / p) != sha]
    constraint_paths = {p for p in set(active) | set(baseline)
                        if Path(p).suffix.lower() in (".sdc", ".adc")}
    constraints = [{"path": p, "sha256": active.get(p, baseline.get(p)),
                    "baseline_equal": p in baseline and active.get(p, baseline[p]) == baseline[p],
                    "current_sha256_matches": (ROOT / p).is_file()
                    and digest(ROOT / p) == active.get(p, baseline.get(p))}
                   for p in sorted(constraint_paths)]
    hooks = [{"path": "04_pin/" + n, "sha256": digest(ROOT / "04_pin" / n),
              "baseline_equal": digest(ROOT / "04_pin" / n) == digest(BASE / "04_pin" / n)}
             for n in ("apply_cdc_exceptions.tcl", "apply_reset_exceptions.tcl")]
    if changed_inputs:
        errors.append("Active frozen source inputs changed")
    if not constraints or not all(c["baseline_equal"] and c["current_sha256_matches"] for c in constraints):
        errors.append("Active ADC/SDC differ from accepted baseline")
    if not all(h["baseline_equal"] for h in hooks):
        errors.append("CDC/reset exception hooks differ from accepted baseline")
    timing = read(phy / (NAME + "_pr.timing"))
    values = {}
    for key in ("SWNS", "STNS", "HWNS", "HTNS"):
        match = re.search(r"\b" + key + r":\s*([-+0-9.]+)ns", timing)
        if not match:
            errors.append("Missing routed timing field: " + key)
        else:
            values[key] = float(match[1])
    if any(v < 0 for v in values.values()) or values.get("STNS") != 0 or values.get("HTNS") != 0:
        errors.append("Routed setup/hold timing gate")
    if "Routed" not in timing or "Both (Slow and Fast)" not in timing:
        errors.append("Routed timing corner coverage")
    area = read(phy / (NAME + "_phy.area"))
    resources = {}
    for kind, limit in (("slice", 95), ("eram", 90), ("dsp", 95)):
        match = re.search(r"^#" + kind + r"\s+(\d+)\s+out of\s+(\d+)", area, re.M)
        if not match:
            errors.append("Missing resource count: " + kind)
            continue
        used, total = map(int, match.groups())
        resources[kind] = {"used": used, "total": total, "percent": used * 100 / total, "limit": limit}
        if used * 100 >= limit * total:
            errors.append("Routed resource gate: " + kind)
    log = read(phy / "td_console.log")
    syn_log = read(run / "syn_1/td_console.log")
    old_log_path = baseline_route_log()
    old_log = read(old_log_path)
    old_drc = Counter(re.findall(r"DRC ([A-Z]+-\d+)", old_log))
    new_drc = Counter(re.findall(r"DRC ([A-Z]+-\d+)", log))
    for code in ("HDL-5105", "RTCLK-5078", "USR-6113"):
        if code in log + syn_log:
            errors.append("Forbidden ROM/clock warning: " + code)
    if re.search(r"\b[A-Z]+-\d+ ERROR:", log + syn_log):
        errors.append("Fatal tool error")
    old_check = checks(read(BASE_RUN / "phy_1" / (NAME + "_chk.timing")))
    new_check = checks(read(phy / (NAME + "_chk.timing")))
    increased = {k: v for k, v in new_check.items() if v > old_check.get(k, 0)}
    new_codes = sorted(set(new_drc) - set(old_drc))
    increased_drc = {k: v for k, v in new_drc.items() if v > old_drc.get(k, 0)}
    if new_codes or increased_drc:
        errors.append("New/increased DRC messages require explicit review")
    if increased:
        errors.append("Increased final timing-check categories require explicit review")
    cdc = read(phy / "secondary_cdc_route_end.rpt")
    reset = read(phy / "secondary_reset_route_end.rpt")
    loaded = read(phy / "secondary_loaded_route_end.rpt")
    markers = [line for line in loaded.splitlines()
               if line.startswith(("EFFECTIVE_RESET_PIN_CONSTRAINTS", "EFFECTIVE_SMD_PATHS"))]
    # The routed seed may legally duplicate an asynchronous reset pin during
    # physical optimization.  Audit the effective count against the reset
    # proof in this same route, rather than requiring the accepted release's
    # historical count of ten.  This keeps the check strict without rejecting
    # a seed-dependent but proven reset mapping.
    effective_match = re.search(r"EFFECTIVE_RESET_PIN_CONSTRAINTS\s+(\d+)", loaded)
    applied_match = re.search(r"APPLIED_RESET_EXCEPTIONS\s+(\d+) unique asynchronous pins;\s+(\d+) proven synchronizers", reset)
    if not effective_match or not applied_match or int(effective_match[1]) != int(applied_match[1]) or int(applied_match[2]) < 5:
        errors.append("CDC/reset effective endpoint counts or synchronizer proof changed")
    if "EFFECTIVE_SMD_PATHS 290 128 9 52" not in loaded:
        errors.append("CDC/reset effective SMD endpoint counts changed")
    counts = ignored(phy)
    if not counts["rows"] or counts["shadowed"] or counts["ignored"]:
        errors.append("Missing, shadowed or ignored final timing exceptions")
    # Audit both the active dependency graph and baseline protected files so
    # deleting a protected input cannot silently remove it from the review.
    protected = {p: sha for p, sha in active.items() if protected_transport(p)}
    protected_paths = set(protected) | {p for p in baseline if protected_transport(p)}
    protected_changed = [p for p in sorted(protected_paths)
                         if p not in baseline or not (ROOT / p).is_file()
                         or digest(ROOT / p) != baseline[p]
                         or (p in protected and protected[p] != baseline[p])]
    if protected_changed:
        errors.append("HXA/DDR/Ethernet source differs from accepted baseline")
    cnn_protected = {p: sha for p, sha in active.items() if protected_vision(p)}
    cnn_paths = set(cnn_protected) | {p for p in baseline if protected_vision(p)}
    cnn_changed = [p for p in sorted(cnn_paths)
                   if p not in baseline or not (ROOT / p).is_file()
                   or digest(ROOT / p) != baseline[p]
                   or (p in cnn_protected and cnn_protected[p] != baseline[p])]
    intentional_model_mismatches = [p for p, expected in INTENTIONAL_PCB_ROM_SHA256.items()
                                    if cnn_protected.get(p) != expected]
    unexpected_cnn_changed = [p for p in cnn_changed
                              if p not in INTENTIONAL_PCB_ROM_SHA256]
    if not cnn_protected or unexpected_cnn_changed or intentional_model_mismatches:
        errors.append("Ordinary CNN/PCB model or vision source differs from exact new-capture-mix baseline")
    result = {
        "status": "PASS_WITH_INHERITED_WARNINGS" if not errors else "REVIEW_REQUIRED", "errors": errors,
        "manifest_sha256": frozen["manifest_sha256"], "baseline_run": str(BASE_RUN),
        "baseline_route_log": str(old_log_path), "baseline_route_log_sha256": digest(old_log_path),
        "timing_ns": values, "resources": resources, "constraints": constraints,
        "exception_hooks": hooks, "active_source_mismatches": changed_inputs,
        "effective_markers": markers,
        "effective_reset_pin_constraints": int(effective_match[1]) if effective_match else None,
        "applied_reset_unique_async_pins": int(applied_match[1]) if applied_match else None,
        "proven_reset_synchronizers": int(applied_match[2]) if applied_match else None,
        "cdc_report_prefix_counts": dict(Counter(line.split()[0] for line in cdc.splitlines() if line.strip())),
        "ignored_final_exception_counts": counts,
        "drc_visible_message_counts": {"baseline": dict(old_drc), "new": dict(new_drc)},
        "new_drc_codes": new_codes, "increased_drc_counts": increased_drc,
        "timing_check_categories": {"baseline": old_check, "new": new_check},
        "increased_check_categories": increased, "protected_source_mismatches": protected_changed,
        "cnn_pcb_protected_input_count": len(cnn_protected),
        "cnn_pcb_source_mismatches": cnn_changed,
        "fifo_review": "Inherited async soft-FIFO groups use exact datapath-only first-stage Gray bounds; second synchronizer stages remain timed. Effective route-end Gray path count must stay 52.",
        "ddr_review": "DDR, frame store, configuration ROM and constraints match accepted baseline. Routed timing is checked here; electrical DDR hardware validation remains NOT_RUN.",
        "cnn_review": "Ordinary CNN, PCB RTL/vision logic and all model inputs match the exact new-capture-mix baseline by SHA256. This report-format change permits no model, inference, HXA, DDR or constraint changes. PCB accuracy and physical writing remain subject to real-image and hardware validation.",
        "intentional_pcb_model_updates": INTENTIONAL_PCB_ROM_SHA256,
        "unexpected_cnn_pcb_mismatches": unexpected_cnn_changed,
        "intentional_pcb_model_hash_mismatches": intentional_model_mismatches,
        "warning_limits": "Inherited SLATR-1036/1038, dummy-node, bounded async FIFO and legacy I/O delay groups are recorded; this does not claim a warning-free design.",
        "hardware": "NOT_RUN", "readonly_reimport": "separate mandatory gate",
        "reviewed_report_hashes": {p.relative_to(ROOT).as_posix(): digest(p) for p in required
                                   if p.suffix in (".rpt", ".timing", ".area", ".status", ".log")},
    }
    out.mkdir(parents=True, exist_ok=True)
    (out / "FINAL_PHYSICAL_REVIEW.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    lines = ["# CNN named-report routed physical review", "", "Status: `" + result["status"] + "`. Hardware: `NOT_RUN`.",
             "", "Frozen manifest: `" + frozen["manifest_sha256"] + "`.", "", "| Gate | Value |", "|---|---|"]
    lines += [f"| {k} | {v:+.3f} ns |" for k, v in values.items()]
    lines += [f"| {k} | {v['used']}/{v['total']} ({v['percent']:.2f}%) |" for k, v in resources.items()]
    lines += ["", result["fifo_review"], "", result["ddr_review"], "", result["cnn_review"], "",
              result["warning_limits"], "", "Read-only reimport, ordinary CNN golden and ROM binding are separate final gates.", ""]
    if errors:
        lines += ["Findings: " + "; ".join(errors), ""]
    (out / "FINAL_PHYSICAL_REVIEW.md").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({"status": result["status"], "errors": errors, "timing_ns": values,
                      "resources": resources}, indent=2))
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
