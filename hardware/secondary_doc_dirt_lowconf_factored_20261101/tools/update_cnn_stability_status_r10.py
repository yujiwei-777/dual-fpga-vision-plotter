"""Read existing evidence and render a current R10 status report; never builds hardware.

Default output is reports/r10_status_preview. Publishing is an explicit caller choice:
  python tools/update_cnn_stability_status_r10.py --output-dir artifacts
Unrelated fields/experiment history in the previous status JSON are retained. This
tool does not modify RTL, regressions, build directories, the original overview,
the control project, work/, or any bitstream.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAME = "secondary_cnn_multibox"
STEM = "CNN_TARGET_STABILITY_STATUS"
RUN_NAMES = {
    "R1": "cnn_stability_Runs_20261031",
    **{f"R{x}": f"cnn_stability_r{x}_Runs_20261031" for x in range(2, 8)},
    "R8": "cnn_stability_r8_area_Runs_20261031",
    "R8b": "cnn_stability_r8b_resume_Runs_20261031",
    "R9": "cnn_stability_r9_pointer_Runs_20261031",
    "R10": "cnn_stability_r10_grid_Runs_20261031",
}
SUITES = ("cnn_stability", "cnn_stability_serial", "cnn_stability_ram",
          "cnn_stability_area24", "cnn_stability_pipeline", "cnn_named_top",
          "cnn_named_pcb", "cnn_named_report", "cnn_stability_core", "cnn_stability_grid")
EXPECTED_R10 = {
    "01_rtl/cnn_result_stabilizer.v": "8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36",
    "01_rtl/vision_pipeline.v": "88F00AC396BC103CB7A802BD349F290E3E85D68BEAD8B7CFDA5F9282F23A36FC",
    "01_rtl/secondary_top.v": "E2230101BB9E144AF86BBB26C4D4A8F39B832C547D91B34E6F71BE32B2EC71D6",
}


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest().upper()


def read_json(path: Path, default=None):
    if not path.is_file():
        return default
    return json.loads(path.read_text(encoding="utf-8-sig"))


def file_record(path: Path):
    result = {"path": str(path.resolve()), "exists": path.is_file()}
    if path.is_file():
        result.update(sha256=sha(path), bytes=path.stat().st_size)
    return result


def path_from(value, parent=ROOT):
    path = Path(value)
    return path if path.is_absolute() else parent / path


def metrics(path: Path, kind):
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    result = {}
    if kind == "timing":
        for key in ("SWNS", "STNS", "HWNS", "HTNS"):
            match = re.search(r"\b" + key + r":\s*([-+0-9.]+)ns", text)
            if not match:
                return None
            result[key] = float(match[1])
    else:
        for key, limit in (("slice", 95), ("eram", 90), ("dsp", 95)):
            match = re.search(r"^#" + key + r"\*?\s+(\d+)\s+out of\s+(\d+)", text, re.M)
            if not match or not int(match[2]):
                return None
            used, total = map(int, match.groups())
            result[key] = dict(used=used, total=total, percent=100 * used / total,
                               strict_limit_percent=limit, passed=100 * used < total * limit)
    return result


def process_snapshot():
    """Get actual PID/command line evidence; stale RUNNING JSON is not liveness."""
    script = ("Get-CimInstance Win32_Process | Where-Object { "
              "$_.Name -match '^(python|pythonw|td_commands_prompt)(\\.exe)?$' } | "
              "Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json -Compress")
    try:
        proc = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                              capture_output=True, text=True, timeout=20,
                              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if proc.returncode:
            return {"status": "UNAVAILABLE", "error": proc.stderr.strip(), "processes": []}
        rows = json.loads(proc.stdout or "[]")
        if isinstance(rows, dict):
            rows = [rows]
        return {"status": "OBSERVED", "processes": rows}
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        return {"status": "UNAVAILABLE", "error": str(error), "processes": []}


def detached_status(path: Path, processes):
    data = read_json(path)
    if data is None:
        return None
    data = copy.deepcopy(data)
    match = next((row for row in processes["processes"] if row.get("ProcessId") == data.get("pid")), None)
    # A reused PID cannot establish liveness without the exact run identity.
    same_command = bool(match and path.parent.name.lower() in str(match.get("CommandLine", "")).lower())
    data["process_observation"] = {
        "snapshot_status": processes["status"], "pid_found": bool(match),
        "same_run_command_line": same_command,
        "matching_process": match if same_command else None,
        "live_current_run_confirmed": same_command,
    }
    if data.get("status") == "RUNNING" and not same_command:
        data["liveness_note"] = "RUNNING is a persisted declaration; process liveness was not confirmed."
    return data


def verify_files(entries, parent=ROOT):
    checks = []
    iterator = entries.items() if isinstance(entries, dict) else ((row.get("path") or row["archive"], row) for row in entries)
    for name, item in iterator:
        expected = item if isinstance(item, str) else item.get("sha256")
        path = path_from(name, parent)
        actual = sha(path) if path.is_file() else None
        checks.append({"path": str(path.resolve()), "expected_sha256": expected,
                       "actual_sha256": actual, "matches": actual == str(expected).upper()})
    return checks


def regression_status(suite, previous):
    path = ROOT / "02_sim" / suite / "RESULTS.json"
    data = read_json(path, {})
    result = copy.deepcopy(previous)
    inputs = data.get("input_hashes") or data.get("inputs_sha256") or {}
    checks = verify_files(inputs)
    evidence = verify_files(data.get("evidence_hashes", {}), path.parent)
    latest = max((Path(row["path"]).stat().st_mtime_ns for row in checks
                  if Path(row["path"]).is_file()), default=0)
    fresh = path.is_file() and path.stat().st_mtime_ns >= latest
    passed = (data.get("status") == "PASS" or data.get("passed") is True)
    good = passed and bool(checks) and fresh and all(row["matches"] for row in checks + evidence)
    result.update(status="PASS" if good else "MISSING_STALE_OR_FAILED", result=file_record(path),
                  input_hash_verification=checks, evidence_hash_verification=evidence,
                  result_not_older_than_current_inputs=fresh,
                  input_count=len(checks), reported_status=data.get("status"),
                  scope=data.get("scope"), limits=data.get("limits", result.get("limits", [])),
                  logs={name: file_record(path.parent / name) for name in data.get("evidence_hashes", {})})
    # Current evidence is authoritative; old human count descriptions must not survive unchanged.
    counts = {key: value for key, value in data.items() if isinstance(value, (int, float)) and not isinstance(value, bool)}
    if isinstance(data.get("checks"), list):
        counts["checks_list_entries_including_summary"] = len(data["checks"])
        summary = [line for line in data["checks"] if re.search(r"ALL.*(?:checks|jobs|assertions)=", str(line))]
        if summary:
            counts["reported_summaries"] = summary
    if isinstance(data.get("jobs"), list):
        counts["report_jobs"] = len(data["jobs"])
    if isinstance(data.get("tests"), dict):
        counts["test_markers"] = {name: item.get("marker") for name, item in data["tests"].items()}
    # Some inherited runners record logs in the frozen archive rather than an
    # evidence_hashes member. Hash them without inventing an expected hash.
    for log_path in path.parent.glob("*.log"):
        result["logs"].setdefault(log_path.name, file_record(log_path))
    result["current_counts"] = counts
    if data.get("coverage") is not None:
        result["coverage"] = data["coverage"]
    result["scope_and_count"] = data.get("scope") or json.dumps(counts, ensure_ascii=False)
    result["reused_from_unchanged_sources"] = suite in {"cnn_named_report", "cnn_stability_core"}
    return result


def run_status(label, previous, processes):
    run = ROOT / RUN_NAMES[label]
    syn, phy = run / "syn_1", run / "phy_1"
    result = copy.deepcopy(previous)
    syn_errors = sorted(path.name for path in syn.glob(".*.error.f"))
    phy_errors = sorted(path.name for path in phy.glob(".*.error.f"))
    syn_complete = ((syn / ".opt_gate.end.f").is_file() and not syn_errors
                    and (syn / f"{NAME}_gate.db").is_file())
    route_complete = (phy / ".opt_route.end.f").is_file() and not phy_errors
    area = metrics(syn / f"{NAME}_gate.area", "area")
    syn_timing = metrics(syn / f"{NAME}_gate.timing", "timing") if syn_complete else None
    route_timing = metrics(phy / f"{NAME}_pr.timing", "timing") if route_complete else None
    detached = {action: detached_status(run / f"DETACHED_{action.upper()}.json", processes)
                for action in ("syn", "route", "gate", "readonly", "bitgen")}
    active = [key for key, val in detached.items() if val and val.get("status") == "RUNNING"
              and val["process_observation"]["live_current_run_confirmed"]]
    if phy_errors:
        status = "PHYSICAL_IMPLEMENTATION_FAILED_NO_ROUTE_NO_BIT"
    elif syn_errors:
        status = "SYNTHESIS_FAILED_NO_BIT"
    elif route_complete:
        status = "ROUTE_COMPLETE_FINAL_GATES_PENDING"
    elif active:
        status = "RUNNING_" + active[-1].upper() + "_PROCESS_CONFIRMED"
    elif syn_complete:
        status = "SYNTHESIS_COMPLETE_ROUTE_NOT_COMPLETED"
    elif (syn / ".opt_gate.begin.f").is_file():
        status = "SYNTHESIS_INCOMPLETE_NO_LIVE_RUNNER_CONFIRMED"
    else:
        status = "PREPARED_OR_NOT_STARTED"
    if syn_complete and area and not all(row["passed"] for row in area.values()):
        status = "RESOURCE_GATE_FAILED_NO_ROUTE_NO_BIT"
    log_path = phy / "td_console.log"
    log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
    failure = read_json(run / "PHYSICAL_FAILURE.json")
    if phy_errors and "PHY-9002" in log:
        status = "PLACER_INITIALIZATION_FAILED_NO_ROUTE_NO_BIT"
    if label == "R8":
        status = "SYNTHESIS_INCOMPLETE_INTERRUPTION_CAUSE_UNKNOWN"
        result["interruption_review"] = file_record(ROOT / "reports/r8_interruption_review/R8_INTERRUPTION_REVIEW.json")
        result["interruption_cause"] = "UNKNOWN; no opt_gate end marker/database/timing, not a proved timing failure"
    result.update(attempt=label, run=str(run), status=status,
                  synthesis_complete=syn_complete, synthesis_resources=area,
                  synthesis_timing_ns=syn_timing, routed_timing_ns=route_timing,
                  routed_timing_available=route_complete and route_timing is not None,
                  synthesis_area_is_final=syn_complete,
                  resource_gate_pass=bool(area) and all(row["passed"] for row in area.values()),
                  synthesis_area_report=file_record(syn / f"{NAME}_gate.area"),
                  synthesis_timing_report=file_record(syn / f"{NAME}_gate.timing"),
                  synthesis_log=file_record(syn / "td_console.log"),
                  markers={"synthesis": sorted(path.name for path in syn.glob(".*.f")),
                           "physical": sorted(path.name for path in phy.glob(".*.f"))},
                  error_markers={"synthesis": syn_errors, "physical": phy_errors},
                  detached=detached, bit_generated=False)
    if label == "R10" and not (run / "BUILD_PLAN.json").is_file():
        result["status"] = "R10_WAITING_FOR_BUILD_PLAN"
    # A negative synthesis WNS is diagnostic; it does not veto actual place/route.
    result["route_eligibility"] = {
        "synthesis_complete": syn_complete,
        "strict_resource_gate_pass": bool(area) and all(row["passed"] for row in area.values()),
        "negative_synthesis_wns_blocks_route": False,
        "eligible_to_attempt_route": syn_complete and bool(area) and all(row["passed"] for row in area.values()),
        "note": "Final timing must be measured after route; synthesis-only negative WNS is not a physical timing failure.",
    }
    sequence = read_json(run / "CONSTRUCTION_SEQUENCE.json")
    if sequence:
        result["construction_sequence"] = sequence
        result["construction_sequence_record"] = file_record(run / "CONSTRUCTION_SEQUENCE.json")
    if failure:
        result["physical_failure"] = file_record(run / "PHYSICAL_FAILURE.json")
        result["physical_failure_details"] = failure
    elif phy_errors:
        result["physical_failure_details"] = {
            "stage": "GP Phase 1" if "GP Phase1" in log else "See physical log",
            "error_codes": sorted(set(re.findall(r"PHY-(?:7027|9002)", log))),
            "local_slicel_exact_deficit": None,
            "interpretation": "LUTL=1.00 is rounded and also appears in the successful control; no exact deficit is inferred.",
            "log": file_record(log_path)}
    return result


def archive_status(run):
    result = {}
    for name in ("frozen_build_inputs", "frozen_regression_evidence", "frozen_physical_project"):
        parent = run / name
        path = parent / "ARCHIVE_MANIFEST.json"
        manifest = read_json(path, {})
        checks = verify_files(manifest.get("files", {}), parent)
        result[name] = dict(**file_record(path), file_count=manifest.get("file_count", len(checks)),
                            all_file_hashes_verified=bool(checks) and all(row["matches"] for row in checks),
                            mismatches=[row for row in checks if not row["matches"]])
    return result


def render_markdown(data):
    current = data["attempts"][-1]
    lines = ["# 普通 CNN 多目标稳定化：R10 状态", "",
             f"更新时间（UTC）：{data['updated_utc']}", "",
             f"当前状态：`{data['status']}`。实板：`NOT_RUN`。", "",
             "R10 保留 R9 的 2-bit 指针排序，并将普通 CNN 的历史几何无损保存为 8 像素网格单位（COORD_SHIFT=3）；顶层直接锁存整数中心坐标。"
             "原模型、置信门限、PCB、文档、GRBL、协议和主板不在本次算法修改范围。", "",
             "## 构建结果", "", "| 轮次 | Slice | ERAM | DSP | 综合 WNS / TNS (ns) | 阶段 |",
             "|---|---:|---:|---:|---|---|"]
    for attempt in data["attempts"]:
        area, timing = attempt.get("synthesis_resources") or {}, attempt.get("synthesis_timing_ns")
        resource = [f"{area[k]['used']}/{area[k]['total']} ({area[k]['percent']:.2f}%)" if k in area else "未得到"
                    for k in ("slice", "eram", "dsp")]
        ts = f"{timing['SWNS']:+.3f} / {timing['STNS']:.3f}" if timing else "未完成/未得到"
        lines.append("| " + " | ".join([attempt["attempt"], *resource, ts, attempt["status"]]) + " |")
    lines.extend(["", "R8 只有中间面积报告和 RTL 检查点，缺少完整 gate 完成证据，异常退出原因未知。"
                  "R8b 已完整综合并通过资源门槛，随后真实 place 在 GP Phase 1 以 PHY-9002 失败，未进入 route。", "",
                  "R9 已保存独立综合、真实 GP Phase 1 失败和协调器 FAILED 证据；R9 的失败保留为历史，当前活动候选为 R10。", "",
                  "综合时序仅是综合估计，不能作为布线签核。没有 route 完成 marker 时，本报告不发布最终时序。"
                  "综合 WNS 为负不阻止在综合完整、资源达标后继续真实 place/route。"
                  "LUTL=1.00 是两位小数，成功基线也出现过，不能由此算出具体 SLICEL 超额数量。", "",
                  "## R10 当前阶段", "", f"`{current['status']}`", ""])
    for action, info in current["detached"].items():
        if info:
            observed = info["process_observation"]
            lines.append(f"- {action}: 记录 `{info.get('status')}`；PID `{info.get('pid')}`；"
                         f"实际同一 run 命令进程确认：`{observed['live_current_run_confirmed']}`。")
    sequence = current.get("construction_sequence")
    if sequence:
        lines.append(f"- 单次阶段协调器：`{sequence.get('status')}`；当前等待/执行 `{sequence.get('current_stage')}`；"
                     "依赖顺序为 syn → route → gate → readonly → bitgen；任一步失败即停止。")
    timing = current.get("routed_timing_ns")
    lines.extend(["", "最终布线时序：" + (json.dumps(timing) if timing else "未得到；不宣称 setup/hold 或 TNS 通过。"), "",
                  "## 回归", "", "| 套件 | 当前证据及输入校验 | 当前计数 |", "|---|---|---|"])
    for name, result in data["regressions"].items():
        if name in SUITES:
            counts = json.dumps(result.get("current_counts", {}), ensure_ascii=False).replace("|", "\\|")
            lines.append(f"| {name} | {result['status']} | {counts} |")
    lines.extend(["", "十类证据全部通过：`" + str(data["regression_gate_all_ten_pass"]) + "`。"
                  "沿用的报告/CNN 数值套件均重新核对当前输入和日志 SHA256。", "",
                  "## 源码及构建清单", "",
                  f"源清单 SHA256：`{data['source_manifest_sha256']}`。", ""])
    for name, value in data["current_production"].items():
        lines.append(f"- `{name}`：`{value['sha256']}`；匹配 R10 预期：`{value['matches_expected_r10']}`。")
    lines.extend(["", "归档逐文件 SHA256 核验（缺失时保持待完成）：", ""])
    for name, value in data["frozen_archives"].items():
        lines.append(f"- `{name}`：{value['file_count']} 项；全部哈希匹配：`{value['all_file_hashes_verified']}`。")
    grid = data["regressions"].get("cnn_stability_grid", {}).get("coverage", {})
    if grid:
        lines.extend(["", "grid 对照：20 种参数配置、106 个生命周期中断边界、4 种 transfer 配置；"
                      "保留非对齐输入明确拒绝和破坏性 raw-bank 复用。具体覆盖计数见 JSON 的 grid coverage。"])
    lines.extend(["", "完整路径、BUILD_PLAN、source_snapshot、归档清单、每项回归输入与日志哈希见配套 JSON。", "",
                  "## 交付与限制", "", f"新 bit 已生成：`{data['delivery']['new_bit_generated']}`。", ""])
    lines.extend("- " + value for value in data["limits"])
    lines.extend(["", "要求：setup/hold WNS ≥ 0、TNS = 0、Slice < 95%、ERAM < 90%、DSP < 95%；"
                  "最终 CDC/FIFO/DDR/DRC、只读 reimport 和 bitgen 须有对应证据。", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "reports/r10_status_preview")
    parser.add_argument("--previous-status", type=Path, default=ROOT / "artifacts" / (STEM + ".json"))
    args = parser.parse_args()
    output = path_from(args.output_dir).resolve()
    if not output.is_relative_to(ROOT) or "work" in [part.lower() for part in output.relative_to(ROOT).parts]:
        raise SystemExit("Report output must remain in the independent project and outside work/.")
    old = read_json(path_from(args.previous_status), {})
    data = copy.deepcopy(old)
    run = ROOT / RUN_NAMES["R10"]
    plan_path, snapshot_path = run / "BUILD_PLAN.json", run / "syn_1/source_snapshot.json"
    plan, snapshot = read_json(plan_path, {}), read_json(snapshot_path, {})
    processes = process_snapshot()
    old_attempts = {row["attempt"]: row for row in old.get("attempts", [])}
    # Preserve the exact prior summary before replacing current-stage fields.
    previous_record = file_record(path_from(args.previous_status))
    history = data.setdefault("historical_status_summaries", {})
    if previous_record.get("sha256") not in history:
        history[previous_record.get("sha256", "missing")] = {
            "record": previous_record,
            "updated_utc": old.get("updated_utc"), "candidate": old.get("candidate"),
            "status": old.get("status"), "current_build_failure": old.get("current_build_failure"),
            "final_root_review": old.get("final_root_review"),
            "regression_gate_all_nine_pass": old.get("regression_gate_all_nine_pass"),
            "final_physical_stages": old.get("final_physical_stages"),
        }
    data.pop("regression_gate_all_nine_pass", None)
    data.update(schema_version=2, updated_utc=datetime.now(timezone.utc).isoformat(),
                project_root=str(ROOT), candidate="R10 lossless 8-pixel grid geometry + cached report center; R9 pointer sorting retained",
                hardware_status="NOT_RUN", build_plan=file_record(plan_path),
                source_list=file_record(snapshot_path), source_manifest_sha256=plan.get("source_manifest_sha256"),
                mapping_experiment=plan.get("mapping_experiment"),
                source_scope_verification=plan.get("source_scope"),
                frozen_archives=archive_status(run),
                attempts=[run_status(label, old_attempts.get(label, {}), processes) for label in RUN_NAMES])
    data["current_production"] = {}
    for name, expected in EXPECTED_R10.items():
        data["current_production"][name] = dict(**file_record(ROOT / name), expected_r10_sha256=expected,
                                                matches_expected_r10=sha(ROOT / name) == expected)
    data.setdefault("implementation", {}).update(
        coord_shift=3, coordinate_grid_pixels=8,
        ordinary_raw_endpoint_geometry_only=True,
        x_endpoint_bits=8, y_endpoint_bits=7,
        current_image_coordinate_units_restored_at_publish=True,
        current_report_center_cached_without_recomputing_extents=True,
        r9_pointer_sort_retained=True,
    )
    source_checks = verify_files(snapshot.get("files", []))
    data["source_snapshot_verification"] = {
        "snapshot_passed": snapshot.get("passed"), "files_checked": len(source_checks),
        "manifest_matches_plan": snapshot.get("manifest_sha256") == plan.get("source_manifest_sha256"),
        "all_current_hashes_match": bool(source_checks) and all(row["matches"] for row in source_checks),
        "mismatches": [row for row in source_checks if not row["matches"]],
    }
    data["regressions"] = {suite: regression_status(suite, old.get("regressions", {}).get(suite, {})) for suite in SUITES}
    data["regression_gate_all_ten_pass"] = all(item["status"] == "PASS" for item in data["regressions"].values())
    current = data["attempts"][-1]
    data["status"] = current["status"]
    data["current_build_failure"] = current.get("physical_failure_details")
    data["most_recent_prior_failure"] = data["attempts"][-2].get("physical_failure_details")
    phy = run / "phy_1"
    release = read_json(phy / "release_gate.json", {})
    physical_path = ROOT / "02_sim" / (run.name + "_physical_review/FINAL_PHYSICAL_REVIEW.json")
    readonly_path = ROOT / "02_sim" / (run.name + "_readonly/readonly_verification.json")
    stages = {"place": "COMPLETE" if (phy / ".opt_place.end.f").is_file() else "NOT_COMPLETE",
              "route": "COMPLETE" if current["routed_timing_available"] else "NOT_COMPLETE",
              "setup_hold_and_tns_routed": current["routed_timing_ns"] or "NOT_AVAILABLE",
              "cdc_fifo_ddr_final": file_record(physical_path), "drc_final": file_record(physical_path),
              "release_gate": file_record(phy / "release_gate.json"),
              "readonly_reimport": file_record(readonly_path),
              "bitgen": "COMPLETE" if (phy / ".bitgen.end.f").is_file() else "NOT_RUN"}
    data["final_physical_stages"] = stages
    target = ROOT / "artifacts/dual_fpga_secondary_20261031_cnn_target_stability_diagnostic.bit"
    build_record = target.with_name(target.stem + "_BUILD.json")
    build = read_json(build_record, {})
    physical = read_json(physical_path, {})
    readonly = read_json(readonly_path, {})
    timing = current.get("routed_timing_ns")
    timing_pass = bool(timing) and all(value >= 0 for value in timing.values()) and timing["STNS"] == timing["HTNS"] == 0
    release_proof = (
        current["routed_timing_available"] and timing_pass and release.get("passed") is True
        and release.get("bitgen_allowed") is True and not physical.get("errors", ["missing"])
        and physical.get("status") == "PASS_WITH_INHERITED_WARNINGS" and readonly.get("passed") is True
        and (phy / ".bitgen.end.f").is_file() and not list(phy.glob(".*.error.f"))
        and build.get("source_manifest_sha256") == plan.get("source_manifest_sha256")
        and physical_path.is_file() and build.get("physical_review_sha256") == sha(physical_path)
        and readonly_path.is_file() and build.get("readonly_verification_sha256") == sha(readonly_path)
        and data["regression_gate_all_ten_pass"]
    )
    delivered = bool(target.is_file() and build.get("bit_sha256") == sha(target)
                     and build.get("runs") == str(run) and release_proof)
    baseline_bit = Path(data.get("baseline", {}).get("bit", "missing"))
    baseline_preserved = baseline_bit.is_file() and sha(baseline_bit) == data.get("baseline", {}).get("bit_sha256")
    data["delivery"] = dict(new_bit_generated=delivered, target_path=str(target),
                            target_absence_verified=not target.exists(), target_record=file_record(target),
                            build_record=file_record(build_record),
                            existing_control_bit_preserved=baseline_preserved,
                            no_formal_or_diagnostic_release_claim=not delivered)
    if target.exists() and not delivered:
        data["delivery"]["warning"] = "A target file exists but matching release provenance was not verified."
    if delivered:
        data["status"] = "DIAGNOSTIC_NOT_RUN"
        current["bit_generated"] = True
    data["limits"] = [
        "实板状态 NOT_RUN；尚未以新的静止/多角度独立实拍序列完成验收。",
        "1170 个回放观测与既有训练/开发数据重叠，不能宣称独立识别准确率提升；不是连续的所有相机帧。",
        "稳定化不能纠正某个角度持续高置信度的模型误分类。低置信保留期使用当前框和 CONF=0。",
        "十类套件含受控 pipeline/top 叶模块；没有新增完整相机→DDR→HXA→UART 全板事务仿真。",
        "文档/HXA/GRBL 等生产文件按源清单保护；源码不变不能替代新增完整事务仿真或实板测试。",
        "综合报告与布局可放性、最终布线时序分开；没有 route 完成证据时不发布最终 setup/hold/TNS。",
        "R8 中断原因未知；R8b 完整综合通过资源门槛后在 GP Phase 1 失败，未得到 routed timing。",
        "R9 同样在真实 GP Phase 1 失败，协调器 FAILED；其历史不能作为 R10 最终物理实现证据。",
        "COORD_SHIFT=3 仅适用于已证明对齐的普通 CNN raw 端点；PCB、一般坐标和对外协议仍使用原单位。",
        "LUTL=1.00 为舍入显示且成功基线也出现，不能据此推算精确局部 SLICEL 缺口。",
        "add_map_lut_struct=high 来自官方配置，但未公开完整内部语义；不保证解决局部可放性。",
    ]
    data["r9_pointer_sort_evidence"] = {
        name: file_record(ROOT / "reports/pipeline_indirect_sort_candidate" / name)
        for name in ("R9_PROMOTION_AUDIT.json", "PUBLISH_EQUIVALENCE.json", "BOUNDARY_EQUIVALENCE.json")}
    data["r10_grid_evidence"] = {
        "coordinate_contract_review": file_record(ROOT / "reports/coordinate_grid_review/README.md"),
        "production_grid_result": file_record(ROOT / "02_sim/cnn_stability_grid/RESULTS.json"),
        "production_grid_driver": file_record(ROOT / "tools/run_cnn_stability_grid.py"),
        "grid_result_coverage": data["regressions"].get("cnn_stability_grid", {}).get("coverage"),
        "historical_r9_failure": file_record(ROOT / RUN_NAMES["R9"] / "PHYSICAL_FAILURE.json"),
        "historical_r9_construction_sequence": file_record(ROOT / RUN_NAMES["R9"] / "CONSTRUCTION_SEQUENCE.json"),
    }
    data["inherited_history_note"] = (
        "Unknown independent experiment fields are preserved verbatim from the prior JSON. "
        "pre_synthesis_coverage_review and non_adopted_experiments are historical evidence, "
        "not new R10 physical signoff. Current authority: attempts[R10], source_snapshot_verification, "
        "regressions, final_physical_stages and delivery."
    )
    data["final_root_review"] = {
        "utc": data["updated_utc"], "review_type": "automated evidence refresh, not physical signoff",
        "regression_evidence_sha256": {f"02_sim/{key}/RESULTS.json": item["result"].get("sha256")
                                      for key, item in data["regressions"].items()},
        "target_bit_exists": target.exists(), "source_snapshot": data["source_snapshot_verification"],
    }
    data["markdown_report"] = str(output / (STEM + ".md"))
    data["status_generator"] = file_record(Path(__file__))
    output.mkdir(parents=True, exist_ok=True)
    (output / (STEM + ".json")).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / (STEM + ".md")).write_text(render_markdown(data), encoding="utf-8")
    print(json.dumps({"status": data["status"], "output": str(output),
                      "regressions_all_ten_pass": data["regression_gate_all_ten_pass"],
                      "source_snapshot_hashes_match": data["source_snapshot_verification"]["all_current_hashes_match"],
                      "new_bit_generated": delivered}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
