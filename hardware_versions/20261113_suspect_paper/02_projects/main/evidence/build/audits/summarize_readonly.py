"""Summarize this independent main dynamic-OSD build; never launches tools.

Reads only current-build evidence. Writes READONLY_AUDIT_REPORT.json and
README_AUDIT.md inside --audit-dir. This is a static audit, not functional or
hardware signoff. The build root is the parent of this script's audits folder.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys

NAME = "camera_to_dsi_display_720p60_cnn_multibox"
RUN_REL = "01_rtl/imgq_gain_m/main/td_project_display_noise_v8"
LIMITS = {"slice": 95, "eram": 90, "dsp": 95}
REPORT_NAMES = ("ts", "timing", "exceptions", "check", "area", "clocks", "flow")


def read(path):
    raw = Path(path).read_bytes()
    return raw.decode("utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8-sig")


def load(path):
    return json.loads(read(path))


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def ref(path):
    path = Path(path).resolve()
    return {"path": path.as_posix(), "sha256": sha(path), "bytes": path.stat().st_size}


def within(path, root):
    path = Path(path).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f"Evidence/output escapes this independent build: {path}")
    return path


def scan_log(text):
    errors, missing_rom = [], []
    for line_number, line in enumerate(text.splitlines(), 1):
        if re.search(r"\b(?:ERROR|FATAL)\b|\*\*\s+(?:Error|Fatal):|\bBUILD_FAILED\b|\bMAPPING_ERROR\b", line):
            errors.append({"line": line_number, "text": line.strip()})
        if re.search(r"HDL-5105|(?:readmem[hb]|initiali[sz]ation|INIT_FILE|\.mem|ROM).*?"
                     r"(?:not found|cannot open|could not open|failed to open|does not exist|missing)", line, re.I):
            missing_rom.append({"line": line_number, "text": line.strip()})
    return {"errors": errors, "missing_rom": missing_rom,
            "passed": not errors and not missing_rom}


def parse_drc(text):
    # TD numbers the final DRC stage after the optimization passes actually
    # used. This run has post-route/hold/skew optimization and final Stage 8;
    # a run without those passes may have final Stage 6 instead.
    parents = list(re.finditer(r"(?m)^[^\r\n]*?:\s*Stage (\d+)\s*\|\s*Design Rule Check\s*$", text))
    if not parents:
        return {"passed": False, "stages": [], "scope": "No final Design Rule Check block found"}
    parent = parents[-1][1]
    checker_names = ["Run Pin Swap Checker", "Run Net Connection Checker", "Run Lut Bridge Checker",
                     "Run Multi Drive Checker", "Run Clock Status Checker", "Run Abnormal Path Checker",
                     "Run Route Region Checker", "Run Bound Checker"]
    rows = []
    for stage in [parent, *[f"{parent}.{i}" for i in range(1, 9)]]:
        pattern = re.escape(stage)
        starts = [m.start() for m in re.finditer(rf"(?m)^[^\r\n]*?:\s*Stage {pattern}\s*\|", text)]
        ends = [m.start() for m in re.finditer(rf"(?m)^[^\r\n]*?:\s*End Stage {pattern}\s*\|", text)]
        name = "Design Rule Check" if stage == parent else checker_names[int(stage.rsplit('.', 1)[1])-1]
        named = bool(re.search(rf"(?m)^[^\r\n]*?:\s*Stage {pattern}\s*\|\s*{re.escape(name)}\s*$", text))
        rows.append({"stage": f"Stage {stage}", "started": len(starts) == 1,
                     "ended": len(ends) == 1, "start_count": len(starts), "end_count": len(ends),
                     "checker": name, "ordered": named and len(starts) == len(ends) == 1 and starts[0] < ends[0],
                     "_starts": starts, "_ends": ends})
    ordered = all(row["ordered"] for row in rows)
    if ordered:
        ordered = (rows[0]["_starts"][0] < rows[1]["_starts"][0]
                   and rows[-1]["_ends"][0] < rows[0]["_ends"][0]
                   and all(a["_ends"][0] < b["_starts"][0] for a, b in zip(rows[1:], rows[2:])))
    for row in rows:
        row.pop("_starts")
        row.pop("_ends")
    return {"passed": ordered, "parent_stage": parent, "stages": rows,
            "scope": "Native route-log completion markers; no separate check_design or check_io claimed"}


def parse_timing(text):
    metrics, errors = {}, []
    for key in ("SWNS", "STNS", "HWNS", "HTNS"):
        values = re.findall(rf"\b{key}:\s*([-+]?\d+(?:\.\d+)?)ns", text)
        if len(values) != 1:
            errors.append(f"Missing/duplicate timing metric: {key}")
        else:
            metrics[key] = float(values[0])
            if metrics[key] < 0 or (key.endswith("TNS") and metrics[key] != 0):
                errors.append(f"Timing threshold failed: {key}")
    for label, pattern in (("Routed", r"Confidence\s*:\s*Routed"),
                           ("Both corners", r"Check Corner\s*:\s*Both \(Slow and Fast\)"),
                           ("Slow max/min", r"^Slow\s*\|\s*yes\s+yes"),
                           ("Fast max/min", r"^Fast\s*\|\s*yes\s+yes")):
        if not re.search(pattern, text, re.M):
            errors.append(f"Missing timing scope: {label}")
    return {"passed": not errors, "metrics_ns": metrics, "errors": errors}


def parse_area(text):
    resources, reported = {}, {}
    for match in re.finditer(r"^\s*#([A-Za-z_][A-Za-z_0-9 ]*?)\*?\s+(\d+)\s+out of\s+(\d+)\b", text, re.M):
        key = re.sub(r"\s+", "_", match[1].strip().lower())
        used, total = int(match[2]), int(match[3])
        if key in reported:
            raise ValueError(f"Duplicate area report entry: {key}")
        reported[key] = {"used": used, "total": total, "percent": used * 100.0 / total if total else None}
    errors = []
    for key, limit in LIMITS.items():
        row = reported.get(key)
        if not row or not row["total"]:
            errors.append(f"Missing/invalid resource: {key}")
            continue
        resources[key] = dict(row, strict_limit_percent=limit)
        if row["used"] * 100 >= row["total"] * limit:
            errors.append(f"{key} requires strictly less than {limit}%")
    return {"passed": not errors, "resources": resources, "reported_capacity": reported, "errors": errors}


def parse_check(text):
    sections = [{"number": int(m[1]), "name": m[2].strip(), "count": int(m[3]), "severity": m[4]}
                for m in re.finditer(r"(?m)^\s*(\d+)\.\s+checking\s+(.+?)\((\d+)\)\s+\((HIGH|MEDIUM|LOW)\)", text)]
    counts = {row["name"]: row["count"] for row in sections}
    core = ("no clock", "clock definition", "invalid constraint", "pll/clock buffer clock constraints", "combinational loops")
    errors = [f"Missing/nonzero timing diagnostic: {key}" for key in core if counts.get(key) != 0]
    entries = [{"from_clock": m[1].strip(), "to_clock": m[2].strip(), "constraint": m[3].strip()}
               for m in re.finditer(r"(?m)^\s*From Clock:\s*(.*?),\s*To Clock:\s*(.*?),\s*Constraint:\s*(.+)$", text)]
    soft_count = re.search(r"There are (\d+) max-delay datapath-only paths that are part of the provided async clock paths", text)
    soft = int(soft_count[1]) if soft_count else None
    if soft is None or len(entries) != soft:
        errors.append("Soft FIFO asynchronous path count missing/inconsistent")
    return {"passed_core_static_checks": not errors, "errors": errors, "diagnostic_sections": sections,
            "nonzero_sections": [row for row in sections if row["count"]],
            "soft_fifo_async_path_count": soft, "soft_fifo_entries": entries,
            "no_unconstrained_pll_clock_pins": bool(re.search(r"There are 0 clock pins that have no clock constraints\.", text)),
            "pll_frequency_mismatch_zero": bool(re.search(r"There are 0 clocks whose clock frequency do not match the PLL setting\.", text)),
            "scope": "All diagnostic section counts retained; nonzero findings are not silently treated as zero"}


def summarize(args):
    root = Path(__file__).resolve().parents[1]
    run = root / RUN_REL
    out = within(args.audit_dir, root / "audits")
    if not out.is_dir():
        raise ValueError("--audit-dir must already contain completed current-build read-only evidence")
    route_log = within(args.route_log, root)
    gate_path = within(args.release_gate or root / "audits/release_gate.json", root)
    verification_path = within(args.readonly_verification or out / "readonly_verification.json", root)
    manifest_path, snapshot_path = root / "SOURCE_MANIFEST.json", run / "source_snapshot.json"
    manifest, snapshot, gate, verification = map(load, (manifest_path, snapshot_path, gate_path, verification_path))
    al, db = run / (NAME + ".al"), run / (NAME + "_pr.db")
    immutable = {p: sha(p) for p in (manifest_path, al, db)}
    failures = []
    def check(ok, message):
        if not ok:
            failures.append(message)

    check(gate.get("passed") is True, "Generic release gate did not pass")
    check(verification.get("passed") is True, "Generic read-only verification did not pass")
    check(Path(gate.get("run", "")).resolve() == run.resolve() and gate.get("name") == NAME,
          "Generic gate belongs to another project/run")
    check(snapshot.get("passed") is True and Path(snapshot.get("project_root", "")).resolve() == root.resolve(),
          "Source snapshot did not pass or belongs to another build")
    check(gate.get("source_manifest_sha256") == snapshot.get("manifest_sha256"),
          "Generic gate and current source snapshot closure differ")
    source_errors = []
    for relative, row in manifest.get("files", {}).items():
        path = within(root / relative, root)
        if not path.is_file() or sha(path) != row.get("sha256"):
            source_errors.append(relative)
    check(bool(manifest.get("files")) and not source_errors, "Frozen source manifest coverage/hash verification failed")
    plan_path = root / "BUILD_PLAN.json"
    if plan_path.is_file():
        check(load(plan_path).get("source_manifest_sha256") == immutable[manifest_path], "BUILD_PLAN source manifest hash differs")

    route_scan, drc = scan_log(read(route_log)), parse_drc(read(route_log))
    check(route_scan["passed"], "Native route log contains ERROR/FATAL or missing ROM evidence")
    check(drc["passed"], "Native route final DRC and eight named checker blocks are missing, duplicated or out of order")
    check((run / ".opt_route.end.f").is_file(), "Current route completion marker missing")
    check(not (run / ".stop.f").exists() and not list(run.glob(".*.error.f")), "Stop/failed-step marker exists")
    gate_route_log = next((item for path, item in gate.get("evidence", {}).items()
                           if Path(path).resolve() == route_log), None)
    check(bool(gate_route_log) and gate_route_log.get("sha256") == sha(route_log),
          "Supplied native route log is not hash-bound in the generic gate; rerun gate with --log")

    reports = {suffix: out / ("readonly." + suffix) for suffix in REPORT_NAMES}
    report_refs = {path.name: ref(path) for path in reports.values()}
    timing, area = parse_timing(read(reports["timing"])), parse_area(read(reports["area"]))
    route_timing = parse_timing(read(run / (NAME + "_pr.timing")))
    route_area = parse_area(read(run / (NAME + "_phy.area")))
    check(timing["passed"] and area["passed"] and route_timing["passed"] and route_area["passed"],
          "Actual read-only/native route timing or resource checks failed")
    check(timing["metrics_ns"] == route_timing["metrics_ns"] == gate.get("timing_ns"),
          "Read-only/native route/generic gate timing differs")
    check(area["resources"] == route_area["resources"] == gate.get("resources"),
          "Read-only/native route/generic gate resource results differ")
    check(bool(re.search(r"Timing Mode\s*:\s*final", read(reports["flow"]))), "Read-only flow is not final timing mode")

    hashes_path = out / "readonly_input_hashes.json"
    expected = load(hashes_path)
    required_hashes = {p.resolve(): digest for p, digest in immutable.items() if p in (al, db)}
    recorded = {within(path, root): digest for path, digest in expected.items()}
    check(all(recorded.get(path) == digest for path, digest in required_hashes.items()),
          "Read-only input receipt does not bind current AL and routed DB")
    changed = [str(path) for path, digest in recorded.items() if not path.is_file() or sha(path) != digest]
    check(not changed, "Read-only input hashes changed")
    scripts = [within(args.readonly_script, root)] if args.readonly_script else sorted(out.glob("*.tcl"))
    logs = [within(path, root) for path in args.readonly_log] if args.readonly_log else sorted(out.glob("*.log"))
    check(bool(scripts) and bool(logs), "Read-only script/log provenance missing")
    readonly_log_scans = [{"file": ref(path), **scan_log(read(path))} for path in logs]
    check(all(item["passed"] for item in readonly_log_scans), "Read-only log contains ERROR/FATAL or missing ROM evidence")
    marker_count = sum(read(path).splitlines().count("TD_READONLY_REIMPORT_PASS") for path in logs)
    check(marker_count == 1, "Read-only completion marker must occur exactly once")
    prohibited = []
    for script in scripts:
        prohibited.extend({"script": str(script), "line": number, "text": line.strip()}
                          for number, line in enumerate(read(script).splitlines(), 1)
                          if re.match(r"\s*(?:clear_sdc|read_sdc|read_adc|export_db|place|route|optimize\w*|bitgen|save_project|project_save)\b", line))
    check(not prohibited, "Non-read-only command found in audit Tcl")
    readonly_log_text = "\n".join(read(path) for path in logs).replace("\\", "/")
    check(db.as_posix() in readonly_log_text and al.as_posix() in readonly_log_text,
          "Read-only log does not show this build's AL and routed DB paths")

    sdc_path = root / "04_pin/camera_to_dsi_display_720p60.sdc"
    sdc = read(sdc_path)
    check_info = parse_check(read(reports["check"]))
    check(check_info["passed_core_static_checks"], "Core static check_timing/soft FIFO evidence failed")
    check(check_info["no_unconstrained_pll_clock_pins"] and check_info["pll_frequency_mismatch_zero"],
          "PLL clock-constraint/frequency static evidence missing")
    constraint_counts = {command: len(re.findall(rf"(?m)^\s*{command}\b", sdc))
                         for command in ("set_clock_groups", "set_path_skew", "set_max_delay")}
    check(all(constraint_counts.values()), "CDC constraint command categories missing")
    ddr = area["reported_capacity"].get("ddr_byte")
    check(ddr is not None and ddr["used"] > 0, "DDR byte resource evidence missing")
    check(all(sha(path) == digest for path, digest in immutable.items()), "AL, routed DB or source manifest changed during summary")

    result = {"schema_version": 1, "candidate_root": root.as_posix(),
              "generated_utc": datetime.now(timezone.utc).isoformat(),
              "status": "PASS_CURRENT_BUILD_STATIC_AUDIT" if not failures else "STATIC_AUDIT_FAILED",
              "passed": not failures, "failures": failures, "hardware_status": "NOT_RUN",
              "scope": "Current-build static evidence only; no functional simulation, DDR runtime calibration or hardware signoff claimed",
              "source_manifest_file_sha256": immutable[manifest_path],
              "source_snapshot_manifest_sha256": snapshot.get("manifest_sha256"),
              "frozen_sources": {"checked_files": len(manifest.get("files", {})), "hash_failures": source_errors},
              "route_gate": {"generic_gate": ref(gate_path), "generic_passed": gate.get("passed"),
                             "native_log": ref(route_log), "independent_log_scan": route_scan,
                             "timing": route_timing, "area": route_area, "route_db": ref(db), "project_al": ref(al)},
              "drc": drc,
              "readonly_reimport": {"verification": verification, "verification_file": ref(verification_path),
                                    "input_hashes_file": ref(hashes_path), "input_hashes_unchanged": not changed,
                                    "changed_inputs": changed, "reports": report_refs,
                                    "timing": timing, "area": area,
                                    "scripts": [ref(path) for path in scripts], "log_scans": readonly_log_scans,
                                    "completion_marker_count": marker_count, "prohibited_commands": prohibited},
              "cdc_fifo_ddr": {"status": "STATIC_EVIDENCE_ONLY", "standalone_simulation_run": False,
                               "ddr_runtime_calibration_run": False, "constraint_file": ref(sdc_path),
                               "constraint_command_counts": constraint_counts, "check_timing": check_info,
                               "ddr_resources_after_route": ddr,
                               "limitations": ["Constraint/report presence does not establish CDC/FIFO functional correctness.",
                                               "No DDR memory traffic test or runtime calibration result is certified by this report.",
                                               "Nonzero diagnostic categories require contextual review; they remain listed verbatim."]},
              "provenance": {"summary_script": ref(Path(__file__)), "source_manifest": ref(manifest_path),
                             "source_snapshot": ref(snapshot_path),
                             "native_route_timing": ref(run / (NAME + "_pr.timing")),
                             "native_route_area": ref(run / (NAME + "_phy.area"))}}
    (out / "READONLY_AUDIT_REPORT.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    metrics = timing["metrics_ns"]
    rows = ["# 主板动态 OSD 当前构建静态审计", "", f"候选工程：`{root}`", "",
            f"结果：`{result['status']}`。实板状态：`NOT_RUN`。", "",
            "| 项目 | 当前只读报告结果 |", "|---|---:|"]
    for key in LIMITS:
        item = area["resources"].get(key)
        rows.append(f"| {key.upper()} | {item['used']} / {item['total']} = {item['percent']:.4f}%（要求 <{LIMITS[key]}%） |" if item else f"| {key.upper()} | 缺失 |")
    rows += [f"| Setup WNS / TNS | {metrics.get('SWNS')} / {metrics.get('STNS')} ns |",
             f"| Hold WNS / TNS | {metrics.get('HWNS')} / {metrics.get('HTNS')} ns |", "",
             f"Route 最终 DRC Stage {drc.get('parent_stage', '?')} 与八项检查完成：`{drc['passed']}`；原生日志错误/ROM 扫描：`{route_scan['passed']}`。",
             f"AL/DB 只读输入哈希未变：`{not changed}`。当前输入、脚本、日志、报告哈希见 JSON。", "",
             f"CDC/FIFO/DDR：`STATIC_EVIDENCE_ONLY`。SDC 有 {constraint_counts['set_clock_groups']} 组 set_clock_groups、"
             f"{constraint_counts['set_path_skew']} 条 set_path_skew、{constraint_counts['set_max_delay']} 条 set_max_delay；"
             f"check_timing 报告 {check_info['soft_fifo_async_path_count']} 条 soft FIFO 异步路径。", "",
             "未运行或证明独立 CDC/FIFO 功能仿真、DDR 运行时校准、内存流量测试或实板功能。", "",
             "check_timing 非零诊断分类：", ""]
    rows += [f"- {item['name']}：{item['count']}（{item['severity']}）" for item in check_info["nonzero_sections"]] or ["- 无。"]
    if failures:
        rows += ["", "未通过项：", "", *[f"- {message}" for message in failures]]
    rows += ["", "机器可读结果：`READONLY_AUDIT_REPORT.json`。本汇总未复用旧构建 PASS，未调用任何构建工具。", ""]
    (out / "README_AUDIT.md").write_text("\n".join(rows), encoding="utf-8")
    print(json.dumps({"status": result["status"], "passed": result["passed"], "failures": failures,
                      "report": (out / "READONLY_AUDIT_REPORT.json").as_posix()}, ensure_ascii=False, indent=2))
    return 0 if result["passed"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--route-log", type=Path, required=True, help="This build's native TD route log")
    parser.add_argument("--audit-dir", type=Path, required=True, help="Completed read-only report directory within this build")
    parser.add_argument("--release-gate", type=Path, help="Default: build-root/audits/release_gate.json")
    parser.add_argument("--readonly-verification", type=Path, help="Default: audit-dir/readonly_verification.json")
    parser.add_argument("--readonly-script", type=Path, help="Default: all *.tcl in audit-dir")
    parser.add_argument("--readonly-log", type=Path, action="append", help="Repeat if needed; default: all *.log in audit-dir")
    args = parser.parse_args()
    try:
        return summarize(args)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"AUDIT_ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
