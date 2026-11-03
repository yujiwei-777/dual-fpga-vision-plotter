"""Bind the released companion bit, frozen sources and verification evidence."""
from datetime import datetime
from pcb_compat_paths import *
from review_pcb_compat_release import validate_gate_evidence, validate_regression

def main():
    release = obj(ROOT/'reports/pcb_compat_release.json')
    snapshot = obj(RUN/'source_snapshot.json')
    gate = obj(RUN/'release_gate.json')
    regression = obj(ROOT/'reports/pcb_compat_regression.json')
    assert release['passed'] is True and all(v is True for v in release['checks'].values())
    assert validate_gate_evidence(gate)['passed']
    assert validate_regression(regression, snapshot=snapshot)['passed']
    assert len(snapshot['files']) == 189 and snapshot['passed'] is True
    assert all(Path(f['path']).is_file() and sha(f['path']) == f['sha256'] for f in snapshot['files'])
    assert sha(BASEBIT) == BASESHA
    bit_hash = sha(BIT)
    assert bit_hash == release['details']['artifact']['sha256']
    evidence = {}
    def bind(path):
        p = Path(path).resolve()
        assert p.is_file(), p
        key = p.relative_to(ROOT.resolve()).as_posix() if p.is_relative_to(ROOT.resolve()) else p.as_posix()
        evidence[key] = {'sha256': sha(p), 'bytes': p.stat().st_size}
    for rel, item in release['evidence'].items():
        p = ROOT/rel
        assert sha(p) == item['sha256'], p
        bind(p)
    for rel, item in gate['evidence'].items():
        p = Path(rel)
        p = p if p.is_absolute() else RUN/p
        assert sha(p) == item['sha256'], p
        bind(p)
    for path, digest in regression['input_hashes'].items():
        assert sha(path) == digest, path
        bind(path)
    for rel in [
        'reports/pcb_compat_release.json', 'reports/pcb_compat_prebitgen_review.json',
        'reports/final_independent_review.md', 'reports/recovered_brightness_baseline_manifest.json',
        'reports/recovered_brightness_baseline_manifest.md', 'reports/recovered_brightness_baseline.py',
        'tools/pcb_compat_paths.py', 'tools/audit_pcb_compat_scope.py',
        'tools/prepare_pcb_compat_audit.py', 'tools/review_pcb_compat_release.py',
        'tools/run_pcb_compat_audit.ps1', 'tools/test_pcb_compat_release_evidence.py',
        'tools/strict_release_review.py', 'tools/td_release_audit.py',
        'tools/release_audit_config.json', 'tools/finalize_pcb_compat_delivery.py',
        '02_sim/pcb_compat_readonly/strict_independent_release_review.json',
        '02_sim/pcb_compat_readonly/physical_capacity/physical_capacity_validation.json',
        '02_sim/pcb_compat_standard_context/bitgen.tcl',
        '02_sim/pcb_compat_standard_context/console_bitgen.log',
    ]:
        bind(ROOT/rel)
    manifest = {
        'schema_version': 1, 'generated_local': datetime.now().astimezone().isoformat(),
        'status': 'DIAGNOSTIC_BIT_GENERATED', 'hardware_status': 'NOT_RUN',
        'artifact': {'path': str(BIT), 'sha256': bit_hash, 'bytes': BIT.stat().st_size},
        'baseline': {'path': str(BASEBIT), 'sha256': BASESHA, 'unchanged': True,
                     'source_provenance': 'POST_HOC_RECONSTRUCTED_BASELINE_NOT_PREBUILD_SNAPSHOT'},
        'timing_ns': gate['timing_ns'], 'resources': gate['resources'],
        'pcb_timeout_ms': 30000, 'ordinary_cnn_timeout_ms': 2000, 'heartbeat_ms': 250,
        'pcb_timeout_status': 'PROVISIONAL_FULL_SECONDARY_PIPELINE_NOT_MEASURED',
        'source_snapshot_sha256': sha(RUN/'source_snapshot.json'),
        'frozen_dependency_count': len(snapshot['files']), 'frozen_dependencies': snapshot['files'],
        'regression_checks': regression['checks'], 'release_checks': release['checks'],
        'raw_adverse_diagnostics': ['RUN-8007: check_design lslices exceed capacity, raw status 1',
                                    'USR-8450: check_io 10 of 39 logical IO unconstrained, retained'],
        'evidence_interpretation': 'Independent compatible placed capacity and 79 physical IO/baseline/context checks passed; standard bitgen passed without unconstr_io override. Raw checks are not clean.',
        'secondary_modified': False, 'evidence': evidence,
    }
    put(ROOT/'reports/PCB_COMPAT_DELIVERY_MANIFEST.json', manifest)
    (ROOT/'artifacts'/('dual_fpga_main_20261101_pcb_auto_compat_diagnostic.bit.sha256')).write_text(bit_hash+'  '+BIT.name+'\n', encoding='ascii')
    report = f'''# PCB 自动定位配套主板交付报告

独立工程：`{ROOT}`。交付状态：诊断 bit 已生成；实板状态：**NOT_RUN**。

## bit 与基线

- 新 bit：`{BIT}`
- SHA256：`{bit_hash}`
- 大小：{BIT.stat().st_size} 字节
- 只读基线：`{BASE}`
- 基线 bit SHA256：`{BASESHA}`，交付时复核未变。
- 未修改副板、模型、旧 bit、其他主板或 `work/`。副板自动定位版的硬件可用性及实际端到端耗时不由本次主板交付证明。

## 行为修改

1. 仅 PCB purpose=1 使用独立 15 位 30000 ms 倒计时；从本任务完整帧 FRAME_ACK 后计时。普通 CNN 保留 2000 ms。心跳和缓存 ACK 发送子状态继续扣减预算，不会重置或延长等待。
2. 每 250 ms 保持心跳；3 秒租约和 PHY 故障规则保留。同一任务不重新抓拍、不重复启动推理；过期 session/frame/job 结果被拒绝。
3. PCB 显示副板 Type8 返回的原图实际工件框，端点沿用排他结束坐标到 HDMI 包含结束坐标的转换。READY、SCANNING、NO_TARGET 和故障不显示旧框；新抓拍清除旧结果，PASS/FAIL/REVIEW 显示当前实际框。主板仍传完整图像。
4. 保留左下角状态和 KEY4 消抖、单次触发：持续按住不重发，松开不取消，忙碌时再次按下不覆盖 SCANNING 或排队新任务。
5. 只修改 hxa_main_link.v、design_top_wrapper.v、hx_result_select.v、key4_hold_debounce.v 四个活动 RTL。普通 CNN、文档复制、图像处理、亮度与 HDMI 的活动依赖保持基线内容；协议数据格式未改。

## 构建与验证

| 指标 | 最终结果 | 门槛 |
|---|---:|---:|
| Setup WNS | +0.384 ns | >=0 |
| Hold WNS | +0.020 ns | >=0 |
| Setup/Hold TNS | 0 / 0 ns | 0 |
| Slice | 19715/21216，92.925% | <95% |
| ERAM | 90/108，83.333% | <90% |
| DSP | 37/40，92.50% | <95% |

已完成当前冻结源码的 lint/编译、协议与 OSD 回归、综合、布局、布线、时序、现有 CDC/FIFO/DDR 约束核验、路由 DRC、只读 reimport、标准 context 和标准 bitgen，生成后复核通过。DSP 数量未增加。

回归清单有 21 项指定检查、13 个绑定日志：5 个完整帧、6400 个 DATA、188 个心跳；覆盖 11 秒等待、29999/30000 ms 边界、普通 CNN 2000 ms、心跳最大间隔 250 ms、当前任务过滤、重复结果 ACK、模式取消和真实租约失联。实际框/状态/CDC 集成 13 项；六组坐标选择表达式通过 400012 次等价检查；普通 CNN、启动故障与 Type15 文档长任务均重新回归。证据校验工具的 14 项正负例测试通过。

最终使用 `01_rtl/imgq_gain_m/main/td_project_pcb_auto_v2/`。前一尝试的布局容量失败日志及 RTL 保留在旧 run 和 `reports/attempt1_rtl/`，没有用失败报告替代最终结果。

## 保留的诊断与适用限制

- 原始辅助 check_design 仍报 RUN-8007 / lslices exceed capacity，raw status=1；check_io 仍报 USR-8450 / 10 of 39 logical IO。没有把这两项原始检查写成 clean。独立核验覆盖全部 19715 个唯一且类型兼容的已放置 Slice、全部 79 个物理 IO/硬 DPHY 绑定及与基线和标准 context 的一致性；标准 bitgen 无 unconstr_io 参数覆盖且完成。这些是附加物理证据，不消除原始诊断。
- 路由 DRC 仅保留已记录的 SLATR-1036/SLATR-1038 NOTE；RTCLK-5078、USR-6113 本轮未出现。没有新增时钟域或 DDR 数据通路；现有约束检查和行为回归不等于全新的穷举异步 CDC 或 DDR 电气证明。
- PCB 30 秒是待验证预算。副板粗搜索约 9.547 秒的保守上界不含后续细配准和检查；尚未证明完整流水线最坏时间小于 30 秒。
- 亮度基线缺少真实原始 prebuild 清单。本轮只读重建 189 项依赖，旧清单差异仅为工程路径迁移及 tone 48→52，其余 187 项一致；mtime 和构建日志为支持证据，不是 bit/源码身份的防篡改证明。详见 recovered_brightness_baseline_manifest.md。本次新主板则保留实际综合前冻结清单，并在生成前后逐项核对。
- 新 bit 尚未进行主副板联动、自动定位真实耗时、实际工件框、KEY4、普通 CNN/文档与 HDMI 实板验证，保持 NOT_RUN。

## 复现与证据

- 源码与 189 项依赖 SHA256：`PCB_COMPAT_DELIVERY_MANIFEST.json`、最终 run 的 `source_snapshot.json`。
- 回归：`pcb_compat_regression.json`、`recovered_link_pcb_wait_regression_v2.md`。
- 最终签核：`pcb_compat_release.json`；独立审查：`final_independent_review.md`。
- 时序与资源：最终 run 的 `release_gate.json`、`camera_to_dsi_display_720p60_cnn_multibox_pr.timing`、`camera_to_dsi_display_720p60_cnn_multibox_phy.area`。
- 原始诊断、物理核验和 bitgen：`02_sim/pcb_compat_readonly/`、`02_sim/pcb_compat_standard_context/`。
- 构建操作：`tools/PCB_COMPAT_BUILD_COMMANDS.md`。已有证据和 bit 不允许由脚本覆盖；复现需使用新的独立副本/run。
'''
    (ROOT/'reports/PCB_AUTO_COMPAT_BUILD_REPORT_20261101.md').write_text(report, encoding='utf-8')
    print({'passed': True, 'bit_sha256': bit_hash, 'dependency_count': len(snapshot['files']), 'evidence_count': len(evidence), 'hardware_status': 'NOT_RUN'})

if __name__ == '__main__':
    main()
