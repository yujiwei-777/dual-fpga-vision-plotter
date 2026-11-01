"""Package only the frozen, routed and reimported return/newline release."""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import shutil


ROOT = Path(__file__).resolve().parents[1]
STEM = "dual_fpga_secondary_20261027_pcb_a4_return_x10_newline_diagnostic"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def copy_checked(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and sha(destination) != sha(source):
        raise RuntimeError(f"refusing to overwrite different artifact: {destination}")
    if not destination.exists():
        shutil.copy2(source, destination)
    if sha(destination) != sha(source):
        raise RuntimeError(f"copy mismatch: {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--readonly", type=Path, required=True)
    parser.add_argument("--newline", type=Path, required=True)
    parser.add_argument("--regression", type=Path, required=True)
    parser.add_argument("--lint", type=Path, required=True)
    parser.add_argument("--scope", type=Path, required=True)
    parser.add_argument("--focused", type=Path, required=True)
    args = parser.parse_args()
    runs, readonly_dir = args.runs.resolve(), args.readonly.resolve()
    if not runs.is_relative_to(ROOT) or not readonly_dir.is_relative_to(ROOT / "02_sim"):
        raise RuntimeError("evidence must belong to this independent project")
    syn, phy = runs / "syn_1", runs / "phy_1"
    gate = load(phy / "release_gate.json")
    if not gate.get("passed") or not gate.get("bitgen_allowed"):
        raise RuntimeError("routed release gate failed")
    if not load(readonly_dir / "readonly_verification.json").get("passed"):
        raise RuntimeError("read-only reimport failed")
    if not (phy / ".bitgen.end.f").is_file() or list(phy.glob(".*.error.f")):
        raise RuntimeError("bitgen did not complete cleanly")
    snapshot_path = syn / "source_snapshot.json"
    snapshot = load(snapshot_path)
    # Gate re-collects the physical .al; its run-local project hash differs
    # from the synthesis .al. The gate checks exact non-project hashes and
    # equivalent project semantics against this specific pre-build snapshot.
    if Path(gate["snapshot"]).resolve() != snapshot_path.resolve():
        raise RuntimeError("release gate refers to another frozen source snapshot")
    for name, digest in load(readonly_dir / "readonly_input_hashes.json").items():
        if sha(Path(name)) != digest.upper():
            raise RuntimeError(f"routed/reimported database or project changed: {name}")
    for entry in snapshot["files"]:
        path = Path(entry["path"])
        if not path.is_absolute():
            path = ROOT / path
        if not path.resolve().is_relative_to(ROOT) or sha(path) != entry["sha256"].upper():
            raise RuntimeError(f"frozen source mismatch: {path}")
    full_inventory = load(phy / "source_snapshot.json")
    for entry in full_inventory["files"]:
        path = ROOT / entry["path"]
        if not path.resolve().is_relative_to(ROOT) or sha(path) != entry["sha256"].upper():
            raise RuntimeError(f"full source inventory mismatch: {path}")
    newline_dir, release_dir, lint_dir, scope_dir, focused_dir = (
        path.resolve() for path in (args.newline, args.regression, args.lint, args.scope, args.focused))
    if any(not path.is_relative_to(ROOT / "02_sim")
           for path in (newline_dir, release_dir, lint_dir, scope_dir, focused_dir)):
        raise RuntimeError("test evidence must belong to this variant's 02_sim")
    if load(newline_dir / "RESULTS.json")["status"] != "PASS":
        raise RuntimeError("newline RTL regression failed")
    regression = (release_dir / "RESULTS.txt").read_text()
    if regression.count("Errors: 0") != 7 or "tb_doc_grbl_plotter" not in regression:
        raise RuntimeError("document/KEY2/UART/FIFO regression failed")
    lint = (lint_dir / "summary.txt").read_text()
    if "returncode=0 files=76" not in lint or "Errors: 0, Warnings: 0" not in lint:
        raise RuntimeError("active RTL lint failed")
    scope = load(scope_dir / "SOURCE_SCOPE_COMPARISON.json")
    if scope["status"] != "PASS" or scope["manifest_sha256"] != snapshot["manifest_sha256"]:
        raise RuntimeError("source/model/baseline scope audit failed")
    if load(focused_dir / "RESULTS.json")["status"] != "PASS":
        raise RuntimeError("KEY1/HXA/PCB regression failed")
    physical_review_dir = ROOT / "02_sim/newline_digits_bram_physical_review_20261027"
    physical_review = load(physical_review_dir / "FINAL_PHYSICAL_REVIEW.json")
    if physical_review["errors"] or physical_review["manifest_sha256"] != snapshot["manifest_sha256"]:
        raise RuntimeError("CDC/FIFO/DDR/DRC physical review failed or refers to different RTL")
    for relative, digest in load(newline_dir / "INPUTS.json").items():
        if sha(ROOT / relative) != digest.upper():
            raise RuntimeError(f"regression input changed: {relative}")

    output = ROOT / "artifacts"
    boot = ROOT / "05_boot/best_result"
    artifacts = {}
    for suffix in ("", "_compress"):
        source = phy / f"secondary_cnn_multibox{suffix}.bit"
        name = f"{STEM}{suffix}.bit"
        for destination in (output / name, boot / name):
            copy_checked(source, destination)
        artifacts[name] = {"sha256": sha(source), "bytes": source.stat().st_size}
    frozen_name = "source_snapshot_return_x10_newline_20261027.json"
    copy_checked(snapshot_path, output / frozen_name)
    inventory_name = "full_source_inventory_return_x10_newline_20261027.json"
    copy_checked(phy / "source_snapshot.json", output / inventory_name)
    evidence = [
        phy / "release_gate.json", phy / "secondary_cnn_multibox_pr.timing",
        phy / "secondary_cnn_multibox_phy.area", phy / "route_flow.status",
        phy / "secondary_cnn_multibox_chk.timing", phy / "route_clock_utilization.txt",
        phy / "secondary_cnn_multibox_exception.timing", phy / "bitgen_console.log",
        readonly_dir / "readonly_verification.json", newline_dir / "RESULTS.json",
        newline_dir / "GCODE_METRICS.json", newline_dir / "newline_gcode_trace.txt",
        release_dir / "RESULTS.txt", lint_dir / "summary.txt",
        focused_dir / "RESULTS.json", scope_dir / "SOURCE_SCOPE_COMPARISON.json",
        scope_dir / "SOURCE_CLOSURE_AND_FONT_ELABORATION.json",
        physical_review_dir / "FINAL_PHYSICAL_REVIEW.json",
        ROOT / "02_sim/distinct_coordinates_digits_bram_release_20261027/RESULTS.json",
        ROOT / "REPORT_NEWLINE_CONTRACT.md",
    ]
    manifest = {
        "hardware_validation": "NOT_RUN",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "project": str(ROOT), "runs": str(runs),
        "device": "PH1P35MDG324", "top": "secondary_top",
        "artifacts": artifacts, "source_manifest_sha256": snapshot["manifest_sha256"],
        "physical_project_manifest_sha256": gate["source_manifest_sha256"],
        "source_snapshot_file": frozen_name,
        "full_source_inventory_file": inventory_name,
        "timing_ns": gate["timing_ns"], "resources": gate["resources"],
        "evidence_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in evidence},
        "ordinary_cnn_arithmetic": scope["ordinary_cnn_arithmetic_simulation"],
        "limitations": [
            "Hardware drawing, page direction, KEY4 and disconnect tests have not been run.",
            "The UART priority regression has two unused O_hold0 output connection warnings.",
            "Inherited KEY3 rearm proves fresh Idle, not G54 calibration or partial-line buffer cleanup; externally restore machine state after a mid-line abort/reset before rearming.",
            "Document copying and report/KEY2 cursors are independent; use the appropriate sheet to avoid overlap.",
        ],
    }
    metadata_path = output / "SHA256_20261027_PCB_A4_RETURN_X10_NEWLINE.json"
    metadata_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    timing = gate["timing_ns"]
    rows = "\n".join(
        f"| {key.upper()} | {value['used']}/{value['total']} = {value['percent']:.2f}% |"
        for key, value in gate["resources"].items())
    report = f"""# 副板 X10 返回与整份内容换行构建报告

实板状态：`NOT_RUN`。器件 `PH1P35MDG324`，顶层 `secondary_top`。

## 行为

- KEY2 单击一次绘制一个 20mm 方框；完成后抬笔，实际 X 返回 190mm 的本行起点、Y 下移 25mm；按住不重复启动。
- CNN/PCB 报告与 KEY2 共用持久游标；报告按整份文字和缺陷标记的最大高度，再留 5mm。多次任务和 KEY3 不重置该游标。
- 页面放不下时在任何 G-code 发送前拒绝任务（错误码 12），不回绕覆盖。中断任务预留整块空间。
- 换行须收到对应 `ok` 和新鲜 `Idle` 才完成；没有 `ok` 不重发运动命令。
- 文档保持 16:9 映射 X10..200mm、Y10..116.88mm、一次 X 镜像，正常完成抬笔后返回实际机器 X10.00/Y10.00。
- KEY4/取消/故障不主动发换行或文档返回命令。KEY1 已接纳任务断网继续，不因重连重复启动。
- 文档与报告/KEY2 游标独立，切换操作时应使用对应纸张及预先校准的 G54。

## 构建验收

最终 routed 双角 setup WNS `{timing['SWNS']:+.3f} ns`，hold WNS `{timing['HWNS']:+.3f} ns`；setup/hold TNS 均为 0。

| 资源 | 实际使用 |
|---|---|
{rows}

源码冻结 manifest SHA256：`{snapshot['manifest_sha256']}`。
综合、布局布线、资源时序 gate、只读 reimport 及 bitgen 通过；源快照和精确报告路径见相邻 SHA256 JSON。
FIFO/DDR/CDC/时钟和 DRC 分类审查保存在本轮只读审查目录；原有非致命结构和 I/O 警告逐项记录，不声称零警告。

## 仿真和保护

76 活动 RTL lint 0 errors/0 warnings；换行 15 项加 525 组整数算术对照通过。
文档坐标、正常返回/停止、KEY2、UART、FIFO 回归 7/7；KEY1 断网、HXA 取消分类、PCB 三组 golden 通过。
UART 测试的旧 wrapper 有两条未连接未使用 O_hold0 输出的展开警告。
普通 CNN 算术仿真范围：{scope['ordinary_cnn_arithmetic_simulation']}
模型、PCB/CNN 核心、HXA、DDR 和约束的哈希对照见 `SOURCE_SCOPE_COMPARISON.json`；只读基线及主板、work/ 未修改。

继承限制：KEY3 的新鲜 Idle 只证明机器停稳，不能证明 G54 已校准，也不会自动清理半行命令；半行 abort/Reset 后须先从外部恢复 GRBL 和坐标状态再布防。本轮不声称新增 Reset/坐标自动确认。

## 输出

{chr(10).join('- `' + name + '` SHA256 `' + value['sha256'] + '`' for name, value in artifacts.items())}

旧 `pcb_a4_origin_return` bit 返回实际 X200/Y10 且无自动换行，不能替代本轮新 bit。
本次未操作实体写字机；实板完成描绘、方向、换行、停止和断网续写前维持 `NOT_RUN`。
"""
    report_path = output / "SECONDARY_PCB_A4_RETURN_X10_NEWLINE_BUILD_REPORT_20261027.md"
    report_path.write_text(report, encoding="utf-8")
    print(json.dumps({"status": "PACKAGED_NOT_RUN", "artifacts": artifacts,
                      "report": str(report_path)}, indent=2))


if __name__ == "__main__":
    main()
