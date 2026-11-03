# 2026-11-03 KEY1 报告版

主板为 main_pcb_auto_compat_20261101，副板为 secondary_pcb_ccl_binary_key1_write_20261103。主板 bit 不变；副板将识别结果缓存与报告提交分开。本组合实板状态 **NOT_RUN**。

[源码交付包（约 7.9 MiB，可转发）](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.03-ccl-binary-key1-write/vision_inspection_plotter_key1_write_source_20261103.zip) 解压后打开“00_开始使用.html”。包内提供配套 bit、主副板工程、模型、约束、接线与按键说明及回归记录。完整历史报告和检查点在 [完整归档](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/tag/v2026.11.03-ccl-binary-key1-write)。

## 怎么操作

1. 主板 SW2=1，SW4:SW3=00 为普通 CNN，01 为 PCB，10 为文档复制。
2. PCB 模式按一次主板 KEY4，执行一次识别；长按不连续触发。HDMI 显示结果，副板缓存最新合法 PCB 报告。
3. 按副板 KEY1，提交当前模式已缓存的 CNN 或 PCB 报告。PCB 不在识别完成时自动书写，结果只消费一次。
4. 新检测、非 PCB 任务、无目标、明确取消或 KEY4 会使未消费的 PCB 快照失效。串口或笔参数未就绪时不接纳，但保留未消费的快照，条件恢复后可再次按键。
5. 已接纳的报告由副板本地持有，以太网断开不取消、不重放已确认运动命令。

KEY1 不启动文档复制；文档仍走原任务入口。显式 Type20 远程命令保持独立：command=1 固定测试、command=2 当前 CNN 报告。KEY2 方框、KEY3 整体应用复位、KEY4 任务停止/重置保持原有功能。接线和 GRBL 状态流程见 [硬件与控制](HARDWARE_AND_CONTROL.md)。

## 没有改变的算法

普通 CNN 仍为 9 类模型、FC_CONF_SHIFT=8，输出名称、中心点和实际 margin，保留连续确认及低分输出。

PCB 使用共享 CCL 最大合法候选、原框 ×1.0、96×96 源 Y8、C4/C4 GOOD/BAD 二分类。原始 margin<32 为 REVIEW，Type8 分数按 floor((score*100+127)/255) 编码为 0..100。没有启用 pose7 判向、良品异常评分或缺陷定位；框表示候选 PCB 范围。

文档复制保留整帧比例、320×180、4×4 源块判定、固定脏斑补偿、骨架和路径规划。矢量字模、一次 X 镜像、自动换行、HXA1、DDR、Type18 和 GRBL 接口保持。

## 工程与源码身份

| 内容 | 位置 |
| --- | --- |
| 主板工程 | [camera_to_dsi_display_720p60_cnn_multibox.al](../hardware_versions/20261103_ccl_binary_key1_write/main_pcb_auto_compat_20261101/camera_to_dsi_display_720p60_cnn_multibox.al) |
| 副板工程 | [secondary_cnn_multibox.al](../hardware_versions/20261103_ccl_binary_key1_write/secondary_pcb_ccl_binary_key1_write_20261103/secondary_cnn_multibox.al) |
| PCB 模型 | [model/experiments/conv4_4](../hardware_versions/20261103_ccl_binary_key1_write/secondary_pcb_ccl_binary_key1_write_20261103/model/experiments/conv4_4/) |
| 副板冻结输入 | [SOURCE_MANIFEST.json](../hardware_versions/20261103_ccl_binary_key1_write/secondary_pcb_ccl_binary_key1_write_20261103/evidence/SOURCE_MANIFEST.json) |
| 原始发布记录 | [RELEASE_SUMMARY.md](../hardware_versions/20261103_ccl_binary_key1_write/secondary_pcb_ccl_binary_key1_write_20261103/reports/retrained/release_20261103/RELEASE_SUMMARY.md) |
| 证据门槛 | [bitgen_evidence_gate.json](../hardware_versions/20261103_ccl_binary_key1_write/secondary_pcb_ccl_binary_key1_write_20261103/reports/retrained/release_20261103/bitgen_evidence_gate.json) |
| 来源对应关系 | [SOURCE_AND_EVIDENCE_MAPPING.json](../hardware_versions/20261103_ccl_binary_key1_write/SOURCE_AND_EVIDENCE_MAPPING.json) |
| bit 与验收 | [release/20261103_ccl_binary_key1_write](../release/20261103_ccl_binary_key1_write/) |

主板 189 项、副板 324 项冻结输入均按 bit 对应副本核对；副板冻结清单 SHA256 为 B8285CD02FFACDBB6B9913EDC94D14B9D34FA4F5C21E9A484C8A542636347914。

副板项目根目录的部分工具、入口及运行文件与冻结清单存在差异或缺失，归档选取与清单完全一致的 reviewed_bitgen 构建副本。差异见来源映射中的 current_project_vs_frozen；没有以当前目录代替冻结版本。根 .al 仅做相对路径转换，原入口另存；RTL、模型和约束保持原始字节。主板 138 条、副板 84 条 File 引用在包内闭合。

## 文件校验与重建

完整仓库运行 python -B verify_release.py，分别校验四组归档。精简交付包运行 python -B verify_delivery.py，完整归档运行 python -B verify_package.py。校验不重新运行工具或生成 bit。

环境为 Tang Dynasty 2026.1 SP2 / 6.2.200067、PH1P35MDG324、speed -3。解压到短英文目录，开发前复制工程；历史脚本需适配工具路径、测试向量和运行目录。源文件和引用核验通过，不表示异机一键重建已经验证。

## 构建与验证范围

| 板卡 | Setup WNS | Hold WNS | Setup/Hold TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| auto_compat 主板 | +0.384 ns | +0.020 ns | 0 / 0 | 92.93% | 83.33% | 92.50% |
| KEY1 报告版副板 | +0.021 ns | +0.020 ns | 0 / 0 | 90.77% | 75.93% | 45.00% |

副板记录包含独立综合、布局布线、双角时序、DRC、只读重导入和实际 bitgen。DRC 为 72 项 NOTE（24 项 SLATR-1036、48 项 SLATR-1038），没有 ERROR/WARN。原始 pre_bitgen_review 中 bitgen_allowed=false 是当时阶段快照，后续调用单独核对证据和时序资源后完成 bitgen，不能混读两个阶段。

功能记录：KEY1 23 项检查、81 文件语法检查、10 项保留回归（含普通 CNN 27 整数向量）、PCB 核心 18 向量、集成流水线 18 组/22 帧/3 处取消与普通空帧重入。

KEY1 专项使用实际顶层控制块、消抖和任务门控，CNN/DDR/HXA 等叶接口受控；不等于完整实板链路测试。物理审查核对 176 项 routed 源快照、443 条 CDC 连接记录、478 条例外路径 slack，最小 +4.854 ns；45 个 DDR 源/IP/约束文件身份一致。这些是静态和仿真证据，不代替独立 CDC 认证、所有流量 FIFO 形式证明或 DDR 实板校准。

主板原始 RUN-8007 / USR-8450 与独立容量、79 个 IO 对照仍保留。完整归档也保留历史失败记录，不能说每次历史运行均通过。

PCB 模型评估仍为同批采集分块的 231 个有效输入，222 个分类正确，**7 张缺焊盘被接受为 PASS**；不是新板、新工位盲测。margin 不是校准概率。

本组合实板状态 **NOT_RUN**。需实测两种模式的 KEY1、缓存消费和失效、重复按键、断网续写、KEY4、KEY3、文档复制及 DDR。正常末条 ok 只表示控制器接纳命令，不表示机械已 Idle。
