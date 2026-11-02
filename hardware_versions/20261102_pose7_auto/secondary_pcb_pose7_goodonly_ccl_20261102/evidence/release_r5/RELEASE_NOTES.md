# 副板 pose7 diagnostic bit — NOT_RUN

已生成 `dual_fpga_secondary_20261102_pcb_pose7_goodonly_ccl_diagnostic.bit`，SHA256：
`AD02D4FC18AA58307EC2A3CBC1C5482B2B92B3FCF93CC0077B76748D11B692A8`

独立工程为 `D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102`，冻结构建为 `E:/codex_pcb_pose7_20261102_r5`。旧工程、旧 bit、`work/`、主板与模型源目录未覆盖。r3/r4 负时序控制结果保留，交付仅使用 r5 的 routed DB。

## 最终构建结果

| 项目 | 实际值 | 结果 |
|---|---:|---|
| Slice | 19335 / 21216，91.13% | <95% |
| ERAM | 87 / 108，80.56% | <90% |
| DSP | 16 / 40，40.00% | <95% |
| Setup WNS / TNS | +0.002 ns / 0 | PASS |
| Hold WNS / TNS | +0.017 ns / 0 | PASS |

最终报告为真实 Routed、Slow/Fast 两角、Max/Min 均检查。只读重导入时序和资源相同，DB 哈希不变。setup 余量只有 2 ps；不据此推断额外实板余量。80 项声明 Verilog 编译/语法检查、整数与 RTL 对照、普通 CNN、文档与写字回归、取消重入、CDC/FIFO/DDR、DRC 和只读检查的十项 gate 全部通过，579 项证据逐项绑定哈希。bitgen exit=0。

## 包含的功能

- PCB：分时共享灰度 CCL 自动找面积最大的候选，按模型精确裁为 96×96 源 Y8，分别采样两个方向缩略图，选择 0/180°，单次 1→4→4 编码器及良品空间异常评分。旧全图搜索、透视配准和旧判定后端已移除。
- 冻结 pose7 权重、偏置、良品中心、容差、方向参考及模型元数据整套保留；score≤106 PASS、107..204 REVIEW、≥205 FAIL。score 不是置信度百分比。无候选、标签溢出或源边界坏框返回 REVIEW 并清旧框；不输出未经验证的缺陷定位，defect_count=0。
- PCB 状态沿用当前主板实际使用的 Type8，普通检测使用 Type18。REVIEW 的 checked=0，避免被显示成 FAIL。当前二分类配置的 class_id 为 PASS=0、FAIL=1、REVIEW=2、ERROR=3；状态解释以 checked/good 为准。
- 普通 CNN 首次合法候选当次发布当前框、当前类别和真实分数，并标 uncertain；连续三次确认类别，短暂跳类可保留已确认名称，分数不抬高，无目标不发布旧框。KEY1 使用独立锁存快照。
- 普通 CNN 数值、权重、FC_CONF_SHIFT=8 不变。为修复 RAM→DSP 时序增加成对 operand 寄存与 d2 对齐，每个 ROI 增加 49155 cycles（0.39324 ms@125MHz）。
- 保留文档输入与路径、矢量字模、统一 X 镜像、自动换行、KEY1/KEY2/KEY3/KEY4、GRBL、断网已接受任务保持、HXA 与 DDR 行为。

## 验证证据与范围

新 r5 普通 CNN 27 个 ROI 逐值一致；七次完整 miter 各检查 1486848 个乘积，六个 raw-reset 边界、六次空闲 workspace/MAC 复用通过。新 PCB 全流水六帧与三次取消重入通过。其余未改编译源按逐文件哈希复用既有结果，未伪称重跑：包括 PCB 12 ROI/5 head/23 safety、文档二值/骨架/路径/坐标/G-code、13 项写字通信、CNN 发布规则以及 reader/HXA/FIFO 回归。

642 帧开发集回放证明参考一致性，不是独立准确率。reader/DDR 仿真使用行为 app 响应和源切片路由，不是 vendor PHY 电气验收。PCB 全流水约 10.205..10.484 ms 使用抽象 reader，不等于真实 DDR/网络端到端耗时。

## 仍需实板验收

本轮只生成副板 bit，未改主板。主板现有 PCB 等待超时的兼容性仍需实测；原 HDMI 固定指导框不再是自动裁剪边界。新独立良品/缺陷、位置占比/角度/光照、PCB PASS/FAIL/REVIEW 显示、普通 CNN、写字机、断网保持、停止与复位全部为 **NOT_RUN**。详见 `../BOARD_ACCEPTANCE_NOT_RUN.md`。

仅支持 0/180° 判向，未加入在线仿射/透视/任意角度搜索或光度校正。MODEL 中 photometric_calibration 是离线拟合字段。CCL 候选列表 truncated 标志本身不强制 REVIEW；标签 overflow 则拒绝。继承 background_reject 为常零，不能宣称已有学习型硬背景拒绝；显式 Type11 reason80 尚不匹配任务 ID。正常 final-ok 完成是 GRBL 接收确认，不代表机械已 Idle。这些限制未被测试结果掩盖。

## 文件索引

- `RELEASE_MANIFEST.json`：bit、模型、源码 manifest、routed DB、gate 与打包报告哈希。
- `SOURCE_MANIFEST.json`：305 项冻结构建输入；真实源快照仍在 E 构建中。
- `runs/phy_1/secondary_cnn_multibox_pr.timing` 与 `_phy.area`：最终时序和资源。
- `logs/`：综合、布局、布线、只读重导入及 bitgen 日志。
- `../final_gate_r5/GATE_PREPARED_R5.json`、`../physical_gate_r5/PHYSICAL_REVIEW_R5.json`：全部验证 gate 和审计。
- `../cnn_pipeline_r5/README.md`、`../SOURCE_REUSE_REVIEW_R5.md`：新执行与按哈希复用的范围。
