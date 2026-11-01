"""Package the already gated frame-A4 implementation; never rebuild the design."""
from pathlib import Path
from types import SimpleNamespace
from datetime import datetime, timezone
import csv
import hashlib
import importlib.util
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / 'frame_a4_fallback_Runs_20261021/phy_1'
SYN = ROOT / 'frame_a4_fallback_Runs_20261021/syn_1'
OUT = ROOT / 'artifacts'
BOOT = ROOT / '05_boot/best_result'
STEM = 'dual_fpga_secondary_20261021_frame_a4_fallback_diagnostic'
DYNAMIC = ROOT / '02_sim/dynamic_frame_a4_acceptance_20261022_090319'
ROM = ROOT / '02_sim/rom_audit_frame_a4_20261021'
READONLY = ROOT / '02_sim/readonly_reimport_frame_a4_20261021'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def put(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


assert ROOT.name == 'secondary_document_copy_frame_a4_fallback_20261021'
gate = load(RUN / 'release_gate.json')
assert gate['passed'] and gate['bitgen_allowed'] and not gate['failures']
assert load(DYNAMIC / 'result.json')['passed']
assert load(ROM / 'rom_init_audit.json')['passed']
assert load(READONLY / 'readonly_verification.json')['passed']
assert (RUN / '.bitgen.end.f').is_file() and not (RUN / '.bitgen.error.f').exists()
assert sha(RUN / 'secondary_cnn_multibox_pr.db') == '7AFD42B1EBD4D4C2CF5B5BDE7A2605DF62F2DF11858CB6DBD11FDC869641786E'
assert sha(RUN / 'secondary_cnn_multibox.al') == '16C21E41670433810FB6664ECF18C7F416E59AC25126EA80EECD6B9450A0AFB9'
snapshot = load(SYN / 'source_snapshot.json')
assert len(snapshot['files']) == 354
for item in snapshot['files']:
    path = (ROOT / item['path']).resolve()
    assert path.is_relative_to(ROOT) and sha(path) == item['sha256'], item['path']

spec = importlib.util.spec_from_file_location('release_audit', ROOT / 'tools/td_release_audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
inputs = audit.collect(SimpleNamespace(root=ROOT, run=RUN, name='secondary_cnn_multibox', al=None,
                                     config=ROOT / 'tools/release_audit_config.json', extra=[]))
assert inputs['passed'] and not inputs['errors'] and len(inputs['files']) == 117
assert inputs['manifest_sha256'] == gate['source_manifest_sha256']

for path in (OUT, BOOT):
    path.mkdir(parents=True, exist_ok=True)
    assert path.resolve().is_relative_to(ROOT)
artifacts = []
for source_name, target_name in [('secondary_cnn_multibox.bit', STEM + '.bit'),
                                  ('secondary_cnn_multibox_compress.bit', STEM + '_compress.bit')]:
    source = RUN / source_name
    assert source.stat().st_size > 1_000_000
    for folder in (OUT, BOOT):
        dest = folder / target_name
        if dest.exists():
            assert sha(dest) == sha(source), f'Refusing to replace different bit: {dest}'
        else:
            shutil.copy2(source, dest)
        assert sha(dest) == sha(source)
    artifacts.append({'path': f'artifacts/{target_name}', 'bytes': source.stat().st_size,
                      'sha256': sha(source), 'boot_copy': f'05_boot/best_result/{target_name}'})

put(OUT / 'active_input_manifest.json', inputs)
shutil.copy2(SYN / 'source_snapshot.json', OUT / 'source_snapshot.prebuild.json')
with (OUT / 'RTL_MEM_IP_CONSTRAINTS_SHA256.csv').open('w', encoding='utf-8-sig', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['path', 'kind', 'bytes', 'sha256'])
    for item in inputs['files']:
        writer.writerow([str(Path(item['path']).relative_to(ROOT)).replace('\\', '/'),
                         item['kind'], item['bytes'], item['sha256']])

evidence = [
    'frame_a4_fallback_Runs_20261021/phy_1/release_gate.json',
    'frame_a4_fallback_Runs_20261021/phy_1/secondary_cnn_multibox_pr.db',
    'frame_a4_fallback_Runs_20261021/phy_1/secondary_cnn_multibox_pr.timing',
    'frame_a4_fallback_Runs_20261021/phy_1/secondary_cnn_multibox_phy.area',
    'frame_a4_fallback_Runs_20261021/phy_1/td_20261022_091232.log',
    'frame_a4_fallback_Runs_20261021/syn_1/source_snapshot.json',
    '02_sim/dynamic_frame_a4_acceptance_20261022_090319/result.json',
    '02_sim/dynamic_frame_a4_acceptance_20261022_090319/vsim.transcript.log',
    '02_sim/rom_audit_frame_a4_20261021/rom_init_audit.json',
    '02_sim/readonly_reimport_frame_a4_20261021/readonly_verification.json',
    '02_sim/release_review_frame_a4_20261021.md',
    'artifacts/active_input_manifest.json',
    'artifacts/source_snapshot.prebuild.json',
    'artifacts/RTL_MEM_IP_CONSTRAINTS_SHA256.csv',
]
manifest = {
    'generated_utc': datetime.now(timezone.utc).isoformat(),
    'project_root': ROOT.as_posix(), 'top': 'secondary_top', 'device': 'PH1P35MDG324 speed 3',
    'hardware_status': 'NOT_RUN', 'scope': 'Secondary board fixed full-frame A4-aspect copy frontend',
    'artifacts': artifacts, 'timing_ns': gate['timing_ns'], 'resources': gate['resources'],
    'active_input_count': 117, 'prebuild_snapshot_count': 354,
    'active_input_manifest_sha256': inputs['manifest_sha256'],
    'mapping': {'source': [1280, 720], 'canvas': [320, 320], 'active_x': [47, 272],
                'active_y': [96, 222], 'ink_luma_max_inclusive': 112,
                'physical_width_mm': 180, 'requires_corners': False, 'requires_distance': False,
                'runtime_automatic_fallback_selection': False},
    'checks': {'release_gate': 'PASS', 'frontend_dynamic_unit': 'PASS',
               'ddr_cnn_rom_init': 'PASS', 'readonly_reimport': 'PASS', 'bitgen': 'PASS',
               'whole_top_dynamic_this_build': 'NOT_RUN', 'hardware': 'NOT_RUN'},
    'retained_warnings': ['SLATR-1036', 'SLATR-1038', 'PHY-5016',
                          'check_timing dummy/soft-FIFO/I-O-delay items; see release review'],
    'absent_warning_codes': ['RTCLK-5078', 'USR-6113', 'USR-8159'],
    'evidence': [{'path': p, 'sha256': sha(ROOT / p)} for p in evidence],
}
put(OUT / 'RELEASE_MANIFEST.json', manifest)
normal_sha = artifacts[0]['sha256']
compressed_sha = artifacts[1]['sha256']

status = f'''# 整帧 A4 回退副板：本次发布状态

本报告仅认证 `frame_a4_fallback_Runs_20261021`，不使用复制进来的 Run7 或主板报告作为本次验收依据。发布于 2026-10-22，文件名沿用变体日期 20261021。实板状态：**NOT_RUN**。

## 交付

- Bit：`artifacts/{STEM}.bit`
- SHA256：`{normal_sha}`
- 压缩 bit：`artifacts/{STEM}_compress.bit`
- 压缩 SHA256：`{compressed_sha}`
- 两份 bit 已逐字节哈希核对并保存到本工程 `05_boot/best_result/`。
- 器件：PH1P35MDG324，speed 3；顶层：`secondary_top`；工具：TD Release_2026.1_SP2。

## 实际功能与边界

本版固定把完整 1280×720 摄像头帧映射到 320×320 画布的 x=47..272、y=96..222，其余填白；不要求四角或距离标定。完整画面宽度按 A4 宽度比例处理，保留 16:9 构图；机器绘图使用现有 **180 mm 安全宽度**（X=10..190 mm），不是物理 210 mm。墨迹阈值为 Y≤112。

这是独立的固定整帧版，未实现运行时“四角→距离→整帧”自动选择。主板未修改，需已有支持 purpose=2 文档复制的主板发起任务。纸边、桌面纹理或阴影进入画面时也会参与二值化，需要实板验证取景和照明。

## 本次构建结果

| 项目 | 结果 |
| --- | --- |
| 双角 Setup WNS / TNS | +0.001 ns / 0 |
| 双角 Hold WNS / TNS | +0.020 ns / 0 |
| Slice | 18915/21216，89.15% |
| ERAM | 86/108，79.63% |
| DSP | 25/40，62.50% |
| Release gate / 只读 reimport / bitgen | PASS |
| 构建前 354 项输入 SHA256 | 全部匹配 |
| 活动依赖 | 117 项，均在本独立工程内 |
| DDR ROM | 45×52 bit 逐值一致 |
| CNN ROM | 13512 权重、27 偏置逐值一致 |

Setup 最小余量只有 1 ps。既有 SLATR-1036、SLATR-1038、PHY-5016 及 check_timing 的 dummy、soft-FIFO 和 I/O-delay 提示保留并已记录；不能将门控通过理解为 DRC 零警告。RTCLK-5078、USR-6113、USR-8159 本次未出现。

## 动态验证与限制

- 本次 ModelSim 前端动态单元验收通过，Errors=0、Warnings=0；两帧各核对 102400 个输出地址/位，包括 28702 个有效采样和 73698 个白边输出。
- 覆盖阈值 111/112/113、请求和输出背压、待返回时取消及从地址 0 完整重启。仿真时间 6407096 ns。
- 该测试使用行为像素读模型，不代表完整顶层、DDR 硬件、UART/写字机或布局布线后动态仿真通过；本轮未重新完成全链路动态回归。
- Python 整数映射参考通过；71 HDL lint 为 0 errors / 0 warnings；工程顶层端口核对通过。
- 继承的 `model/run_vision_tests.py` 缺 `model/export/quantized.npz`，该项未通过，未改动或补造模型。
- 普通 CNN 权重未改变，硬件连帧、文档绘制和取消恢复仍需上板验证。

## 报告与清单

- `artifacts/RELEASE_MANIFEST.json`：bit、资源、时序与证据 SHA256。
- `artifacts/RTL_MEM_IP_CONSTRAINTS_SHA256.csv`：活动源/IP/约束/MEM 清单。
- `artifacts/source_snapshot.prebuild.json`：原始 354 项构建前快照。
- `02_sim/release_review_frame_a4_20261021.md`：本次 CDC/FIFO/DDR/DRC 与 reimport 审查。
- `02_sim/rom_audit_frame_a4_20261021/ROM_INIT_AUDIT.md`：ROM 逐值与未使用 DDR 第 46 项说明。
- `02_sim/dynamic_frame_a4_acceptance_20261022_090319/README.md`：动态验收命令及覆盖限制。
- `frame_a4_fallback_Runs_20261021/phy_1/td_20261022_091232.log`：本次 bitgen 日志。

原工程、旧 bit、主板和受保护的工作区备份均未修改。完整源工程、约束与 IP 依赖留在本独立目录。
'''
(ROOT / 'BUILD_STATUS_20261021.md').write_text(status, encoding='utf-8')
(ROOT / 'FRAME_A4_FALLBACK_20261021.md').write_text('''# 无四角／无距离的整帧复制模式

本独立副板固定启用 FRAME_AS_A4_WIDTH=1。摄像头 1280×720 完整画面映射为 226×127 有效图像，位于 320×320 白底画布 x=47..272、y=96..222。比例保持，阈值 Y≤112；不要求看见纸边或距离标记。

机器绘图保持现有 180 mm 安全宽度（X=10..190 mm），不是 210 mm 实物原尺寸复制。此版没有运行时四角／距离／整帧自动切换；需要支持 purpose=2 的现有文档复制主板。

Python 整数映射与 ModelSim 动态单元验收均通过。动态测试逐像素检查两完整帧、白底、阈值边界、背压及取消后重启，编译/仿真 Errors=0、Warnings=0。早期运行的 signed/unsigned 极值错误在测试台中修正；未修改活动 RTL。许可证环境已正确设置，不再将许可证不可用列为本次阻塞。

完整构建、SHA256、资源时序、既有警告和验收限制见 BUILD_STATUS_20261021.md。实板状态保持 NOT_RUN；本轮不宣称完整顶层、布局布线后动态仿真或写字机实机验收通过。
''', encoding='utf-8')

contract = ROOT / 'DOCUMENT_COPY_CONTRACT.md'
text = contract.read_text(encoding='utf-8-sig')
note = ('> Active variant override: FRAME_AS_A4_WIDTH=1 maps the full 1280x720 frame '
        'to canvas x=47..272, y=96..222 (226x127), with white padding. No corners or '
        'distance calibration gate. Physical drawing width remains 180 mm. '
        'The generic frontend paper-mapping description below is superseded by '
        'FRAME_A4_FALLBACK_20261021.md for this variant.\n\n')
if note not in text:
    contract.write_text(note + text, encoding='utf-8')

checksum_paths = [OUT / Path(a['path']).name for a in artifacts]
checksum_paths += [OUT / 'RELEASE_MANIFEST.json', OUT / 'active_input_manifest.json',
                   OUT / 'source_snapshot.prebuild.json', OUT / 'RTL_MEM_IP_CONSTRAINTS_SHA256.csv',
                   ROOT / 'BUILD_STATUS_20261021.md', ROOT / 'FRAME_A4_FALLBACK_20261021.md']
(OUT / 'SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(ROOT).as_posix()}\n' for p in checksum_paths), encoding='utf-8')
print(json.dumps({'packaged': True, 'artifacts': artifacts, 'hardware': 'NOT_RUN'}, indent=2))
