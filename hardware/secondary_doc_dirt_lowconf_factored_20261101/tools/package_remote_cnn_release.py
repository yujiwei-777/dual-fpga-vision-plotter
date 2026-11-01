"""Package the current-model release only after all frozen routed gates pass."""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
NAME = "secondary_cnn_multibox"
STEM = "dual_fpga_secondary_20261027_pcb_a4_return_x10_newline_remote_cnn_fc8_diagnostic"
BASE = ROOT.parent / "secondary_pcb_a4_origin_return_20261027"
BASE_BIT = BASE / "artifacts/dual_fpga_secondary_20261027_pcb_a4_return_x10_newline_diagnostic.bit"
BASE_SHA = "333E6DD1F4C86E803D4244E18B9AD73F89A3905AB9EECEF1D1992EE7306C6144"
MODEL_SHA = {
    "weights.mem": "82FB0381424A047600E862FD0BBF55D6B23BCF347BE19F1074A9CD32847058DE",
    "biases.mem": "79A3DAA7C5F3E17A2D5882FC89EEAD2AEBE153420B8D02E001655BCB23740A98",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def copy_checked(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    require(not destination.exists() or sha(destination) == sha(source),
            "Refusing to overwrite different artifact: " + str(destination))
    if not destination.exists():
        shutil.copy2(source, destination)
    require(sha(source) == sha(destination), "Artifact copy failed: " + str(destination))


def validate_inputs(values, relative_root=ROOT):
    for name, digest in values.items():
        path = Path(name)
        if not path.is_absolute():
            path = relative_root / path
        require(path.is_file() and sha(path) == digest.upper(), "Evidence input changed: " + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("runs", "readonly", "physical", "rom", "golden", "scope", "newline", "regression", "focused", "lint"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--boundary", type=Path, help="Optional additional confidence boundary RESULTS.json")
    args = parser.parse_args()
    dirs = {key: getattr(args, key).resolve() for key in (
        "readonly", "physical", "rom", "golden", "scope", "newline", "regression", "focused", "lint")}
    require(all(path.is_relative_to(ROOT / "02_sim") for path in dirs.values()),
            "All verification evidence must belong to this variant's 02_sim")
    runs = args.runs.resolve()
    require(runs.is_relative_to(ROOT), "Runs must belong to this independent project")
    syn, phy = runs / "syn_1", runs / "phy_1"
    gate = load(phy / "release_gate.json")
    require(gate.get("passed") and gate.get("bitgen_allowed"), "Final routed release gate failed")
    require(load(dirs["readonly"] / "readonly_verification.json").get("passed"), "Readonly reimport failed")
    require((phy / ".bitgen.end.f").is_file() and not list(phy.glob(".*.error.f")), "Bitgen did not complete cleanly")
    require(sha(BASE_BIT) == BASE_SHA, "Accepted baseline bit changed")
    snapshot_file = syn / "source_snapshot.json"
    snapshot = load(snapshot_file)
    require(Path(gate["snapshot"]).resolve() == snapshot_file.resolve(), "Gate refers to another source freeze")
    validate_inputs(load(dirs["readonly"] / "readonly_input_hashes.json"))
    for source_snapshot in (snapshot, load(phy / "source_snapshot.json")):
        for entry in source_snapshot["files"]:
            path = Path(entry["path"])
            if not path.is_absolute():
                path = ROOT / path
            require(path.resolve().is_relative_to(ROOT) and sha(path) == entry["sha256"].upper(),
                    "Frozen build input changed: " + str(path))
    physical = load(dirs["physical"] / "FINAL_PHYSICAL_REVIEW.json")
    require(not physical.get("errors") and physical["status"] == "PASS_WITH_INHERITED_WARNINGS"
            and physical["manifest_sha256"] == snapshot["manifest_sha256"], "Current CDC/FIFO/DDR/DRC review failed")
    validate_inputs(physical["reviewed_report_hashes"])
    rom = load(dirs["rom"] / "ROM_BINDING_VERIFICATION.json")
    require(rom.get("status") == "PASS" and rom.get("weights_words") == 13512
            and rom.get("bias_words") == 27, "Current ordinary CNN ROM binding is not proven")
    validate_inputs(rom["input_hashes"])
    golden = load(dirs["golden"] / "RESULTS.json")
    require(golden.get("status") == "PASS" and golden.get("simulation_cases_passed", 0) >= 27
            and golden.get("rtl_case_count", 0) >= 27 and golden.get("rom_layout_match")
            and golden.get("contract", {}).get("fc_conf_shift", [None, None])[1] == 8,
            "Current model arithmetic RTL golden failed")
    validate_inputs(golden["input_hashes"])
    for leaf, expected in MODEL_SHA.items():
        for model_dir in [ROOT / "01_rtl/model/export", ROOT / "model/export"] + [p for p in (syn / "model/export", phy / "model/export") if p.is_dir()]:
            require(sha(model_dir / leaf) == expected, "Current model staging mismatch: " + str(model_dir / leaf))
    scope_file = dirs["scope"] / "NONTARGET_SCOPE_AND_REGRESSION.json"
    scope = load(scope_file)
    require(scope.get("status") == "PASS" and not scope.get("errors")
            and scope["manifest_sha256"] == snapshot["manifest_sha256"]
            and scope.get("ordinary_core_change_exactly_padding_priority")
            and scope.get("ordinary_pipeline_change_exactly_fc_conf_shift8")
            and not scope.get("unexpected_changes") and not scope.get("manifest_drift")
            and not scope.get("baseline_drift"), "Non-target source/regression scope failed")
    newline = load(dirs["newline"] / "RESULTS.json")
    require(newline.get("status") == "PASS", "Automatic newline RTL regression failed")
    validate_inputs(load(dirs["newline"] / "INPUTS.json"))
    focused = load(dirs["focused"] / "RESULTS.json")
    require(focused.get("status") == "PASS" and not focused.get("input_changes_during_run"),
            "KEY1/HXA/PCB non-target regression failed")
    require(all(test.get("status") == "PASS" for test in focused["tests"].values()), "Focused subtest failed")
    focused_inputs = dirs["focused"] / "INPUTS.json"
    if focused_inputs.is_file():
        validate_inputs(load(focused_inputs))
    regression = (dirs["regression"] / "RESULTS.txt").read_text(encoding="utf-8-sig")
    require(regression.count("Errors: 0") == 7 and "tb_doc_grbl_plotter" in regression,
            "Document/KEY2/UART/FIFO regression failed")
    lint = (dirs["lint"] / "summary.txt").read_text(encoding="utf-8-sig")
    require("returncode=0 files=76" in lint and "Errors: 0, Warnings: 0" in lint, "76 active RTL lint failed")
    boundary = None
    if args.boundary:
        boundary = args.boundary.resolve()
        require(boundary.is_relative_to(ROOT / "02_sim"), "Boundary evidence must belong to this variant")
        results = load(boundary)
        require(results.get("status") == "PASS", "Confidence boundary regression failed")
        if "input_hashes" in results:
            validate_inputs(results["input_hashes"])

    output = ROOT / "artifacts"
    artifacts = {}
    for suffix in ("", "_compress"):
        source = phy / (NAME + suffix + ".bit")
        leaf = STEM + suffix + ".bit"
        for target in (output / leaf, ROOT / "05_boot/best_result" / leaf):
            copy_checked(source, target)
        artifacts[leaf] = {"sha256": sha(source), "bytes": source.stat().st_size}
    freeze_leaf = "source_snapshot_remote_cnn_20261027.json"
    inventory_leaf = "full_source_inventory_remote_cnn_20261027.json"
    copy_checked(snapshot_file, output / freeze_leaf)
    copy_checked(phy / "source_snapshot.json", output / inventory_leaf)
    evidence = [phy / "release_gate.json", phy / (NAME + "_pr.timing"), phy / (NAME + "_phy.area"),
                phy / (NAME + "_chk.timing"), phy / "route_flow.status", phy / "bitgen_console.log",
                dirs["readonly"] / "readonly_verification.json", dirs["physical"] / "FINAL_PHYSICAL_REVIEW.json",
                dirs["rom"] / "ROM_BINDING_VERIFICATION.json", dirs["golden"] / "RESULTS.json", scope_file,
                dirs["newline"] / "RESULTS.json", dirs["newline"] / "GCODE_METRICS.json",
                dirs["newline"] / "newline_gcode_trace.txt", dirs["regression"] / "RESULTS.txt",
                dirs["focused"] / "RESULTS.json", dirs["lint"] / "summary.txt"]
    if boundary:
        evidence.append(boundary)
    # Some regression bundles keep the G-code trace outside the compact
    # release directory.  The machine-readable RESULTS/INPUTS gates above
    # remain mandatory; include only evidence files that are present here.
    evidence = [p for p in evidence if p.is_file()]
    native = golden["full_native_1170"]
    limitations = [
        "Hardware classification, handwriting, page direction, newline, KEY4 and disconnect tests have not been run.",
        "The 1170 native frames overlap training/development; full-set fitting is not independent accuracy.",
        "Remote-detail test cases are synthetic ROI detail loss, not independently captured distant frames.",
        "RTL golden checks inference arithmetic; it does not measure candidate localization or physical recognition accuracy.",
        "Inherited KEY3 fresh Idle does not certify G54 calibration, Reset handling or partial-line UART buffer cleanup.",
        "Historical vision_*.mem/JSON files are inherited test fixtures and are not the new inference weights.",
        "The UART priority test retains two unused O_hold0 port connection warnings; inherited physical warnings are classified separately.",
    ]
    metadata = {
        "hardware_validation": "NOT_RUN", "generated_utc": datetime.now(timezone.utc).isoformat(),
        "project": str(ROOT), "runs": str(runs), "device": "PH1P35MDG324", "top": "secondary_top",
        "baseline_bit_sha256": BASE_SHA, "ordinary_model_sha256": MODEL_SHA,
        "ordinary_fc_conf_shift": 8, "ordinary_conv2_zero_padding_priority_fixed": True,
        "artifacts": artifacts, "source_manifest_sha256": snapshot["manifest_sha256"],
        "physical_project_manifest_sha256": gate["source_manifest_sha256"],
        "source_snapshot_file": freeze_leaf, "full_source_inventory_file": inventory_leaf,
        "timing_ns": gate["timing_ns"], "resources": gate["resources"],
        "ordinary_cnn_rtl_golden_cases": golden["simulation_cases_passed"],
        "full_native_fitting_check": native, "limitations": limitations,
        "evidence_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in evidence},
    }
    metadata_file = output / "SHA256_20261027_PCB_A4_NEWLINE_REMOTE_CNN_FC8.json"
    metadata_file.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    timing = gate["timing_ns"]
    rows = "\n".join(f"| {k.upper()} | {v['used']}/{v['total']} = {v['percent']:.2f}% |"
                     for k, v in gate["resources"].items())
    report = f"""# 普通 CNN 远距离增强模型接入构建报告

实板状态：`NOT_RUN`。器件 `PH1P35MDG324`，顶层 `secondary_top`。

## 修改

普通 CNN 换用 `fc3_remote_detail_selected`，保持 RGB8 64×64、9 类、13512 个权重和 27 个偏置。
卷积位移仍为 10/8；新 FC3 权重的小数位由 8 变为 9，普通实例按模型契约使用 `FC_CONF_SHIFT=8`，没有降低判定门限。
整数/RTL 对照发现旧共享 workspace 路径在 Conv2 边界没有优先清零 padding；本轮仅修正普通核该选择顺序，PCB 核和权重保持不变。

保留 PCB 二分类、4×4 文档判定、320×180 网格、单次 X 镜像、文档完成返回实际机器 X10/Y10、整份报告高度自动换行、KEY2 单击方框换行、KEY4 停止和已接受任务断网继续。
主板、只读基线和 `work/` 未修改。旧 `vision_*.mem/JSON` 是历史测试夹具，新推理使用本报告列明的 weights/biases。

## 验证

普通 CNN + 实际共享 workspace + shared MAC 的 {golden['simulation_cases_passed']} 帧 RTL golden 通过，逐点核对 Conv1/Conv2 写入、最终三路 logits、RGB sums、类别及置信度。
1170 原样本整数拟合检查为 {native['joint_correct']}/{native['samples']}；这些帧与训练/开发数据重叠，不能解释为独立测试准确率。
合成远距离病例表示 ROI 细节损失；仍缺少独立真实远距离拍摄和实板准确率验证。
76 活动 RTL lint 0 errors/0 warnings；PCB 三组数值 golden、KEY1/HXA、文档/KEY2/UART/FIFO 和自动换行回归通过。
综合 ROM 导出逐字核对、CDC/FIFO/DDR/DRC 分类审查、双角 routed 时序、只读 reimport 和 bitgen 通过。

setup WNS `{timing['SWNS']:+.3f} ns`，hold WNS `{timing['HWNS']:+.3f} ns`；setup/hold TNS 均为 0。

| 资源 | 使用 |
|---|---|
{rows}

源冻结 SHA256：`{snapshot['manifest_sha256']}`。

## 模型与输出

weights.mem SHA256：`{MODEL_SHA['weights.mem']}`。
biases.mem SHA256：`{MODEL_SHA['biases.mem']}`。

{chr(10).join('- `' + name + '` SHA256 `' + value['sha256'] + '`' for name, value in artifacts.items())}

继承限制：KEY3 新鲜 Idle 不证明 G54 标定和半行 UART 清理；Reset 或中途 abort 后需先恢复写字机和坐标。CDC/DDR 工具报告不代替电气和运动验证。
实板完成普通/PCB识别、方向、自动换行、KEY4 停止和断网续写前维持 `NOT_RUN`。
"""
    report_file = output / "SECONDARY_PCB_A4_NEWLINE_REMOTE_CNN_FC8_BUILD_REPORT_20261027.md"
    report_file.write_text(report, encoding="utf-8")
    print(json.dumps({"status": "PACKAGED_NOT_RUN", "artifacts": artifacts,
                      "report": str(report_file), "manifest": str(metadata_file)}, indent=2))


if __name__ == "__main__":
    main()

