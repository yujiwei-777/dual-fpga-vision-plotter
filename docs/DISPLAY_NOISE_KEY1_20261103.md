# 2026-11-03 显示空间滤波主板 + KEY1 写字副板

主板使用 main_display_noise_fix_20261103，副板使用 secondary_pcb_ccl_binary_key1_write_20261103。配套 bit、源工程、模型、约束和构建证据分别归档，旧版仍保留。

## 下载

[下载可转发源码包](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.03-display-noise-key1/vision_inspection_plotter_display_noise_key1_source_20261103.zip) · [完整构建归档](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/tag/v2026.11.03-display-noise-key1)

- vision_inspection_plotter_display_noise_key1_source_20261103.zip：约 10 MB，可直接转发。解压后打开 00_开始使用.html，包含两板工程、bit、模型、约束、接线与使用说明。
- dual_fpga_pair_display_noise_key1_20261103_complete.zip：约 476 MB，包含完整构建记录、仿真材料、最终检查点及明确标识的历史试验。
- 仅需烧录时，可单独下载 main / secondary 两个 bit。SHA256SUMS.txt 可核对文件。

## 本组合功能

主板显示支路采用 EDGE_TH=16 的二维保边空间滤波，保留 RGB8；不是 TNR。显示亮度表仅修正输入 96..99 四个值，普通 CNN 固定亮度支路保持原值。低对比纹理可能变柔；没有对应的严重噪声故障原始帧，尚未证明该实板现象已消除。

副板与上一 KEY1 报告版字节一致：CNN/PCB 结果先缓存，按副板 KEY1 提交当前模式的报告；PCB 结果单次消费。KEY2 方框、KEY3 应用复位、KEY4 任务停止与重置、矢量字模、镜像和换行保留。已接受写字任务断网后继续。

## 构建与验证

| 板卡 | Setup WNS | Hold WNS | TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| display_noise_fix 主板 | +0.174 ns | +0.020 ns | 0 | 92.59% | 86.11% | 92.50% |
| KEY1 写字副板 | +0.021 ns | +0.020 ns | 0 | 90.77% | 75.93% | 45.00% |

主板 193 项、副板 324 项构建输入已核对。主板最终 V8 使用源码哈希一致的 V6/V7 仿真与逐周期等价链，不是 V8 重跑所有仿真。原始 RUN-8007 / USR-8450 诊断与独立容量、79 个 IO、DPHY 对照及标准 bitgen 记录一并保留。

交付包已通过逐文件哈希、ZIP CRC、解压复验、文档导航和 222 条工程引用核对。没有修改 RTL、模型或约束，也没有重新生成 bit。异机工具重建尚未验证。

本组合实板状态 **NOT_RUN**。PCB 同批分块测试仍有 7 张缺焊盘被接受为 PASS；不是新板、新工位的准确率。margin 分数不是校准后的概率。正常末条 ok 表示 GRBL 接纳命令，不等于机械已 Idle。

版权和第三方模块沿用各文件原有条款；不附带工具、许可证或桥接固件。

## 工程入口与构建来源

- [主板工程](../hardware_versions/20261103_display_noise_key1/main_display_noise_fix_20261103/camera_to_dsi_display_720p60_cnn_multibox.al)
- [副板工程](../hardware_versions/20261103_display_noise_key1/secondary_pcb_ccl_binary_key1_write_20261103/secondary_cnn_multibox.al)
- [来源与证据映射](../hardware_versions/20261103_display_noise_key1/SOURCE_AND_EVIDENCE_MAPPING.json)
- [主板交付清单](../hardware_versions/20261103_display_noise_key1/main_display_noise_fix_20261103/reports/DISPLAY_NOISE_DELIVERY_MANIFEST.json)
- [主板最终构建报告](../hardware_versions/20261103_display_noise_key1/main_display_noise_fix_20261103/reports/DISPLAY_NOISE_BUILD_REPORT_20261103.md)
- [主板噪声调查与限制](../hardware_versions/20261103_display_noise_key1/main_display_noise_fix_20261103/reports/NOISE_FINDINGS_AND_LIMITS.md)
- [副板 KEY1 控制与验证范围](CCL_BINARY_KEY1_WRITE_20261103.md)
- [接线、模式与按键](HARDWARE_AND_CONTROL.md)

两板为 PH1P35MDG324、speed -3，工具 Tang Dynasty 2026.1 SP2 / 6.2.200067。主板最终构建目录为 01_rtl/imgq_gain_m/main/td_project_display_noise_v8，副板源自 324 项 reviewed_bitgen 冻结清单。根 .al 仅改为相对路径，原始入口另存；其余源文件字节保留。历史脚本迁移时需适配工具路径、启动目录和测试向量，不能把不同策略的重建结果当作原布线结果。

主板空间滤波先计算当前像素与左邻的保边平均 H，再与前一行 H 做保边平均；各级任一 RGB 通道差超过 16 时放弃该邻点，行缓存存 H，不存最终输出。没有帧历史或递归反馈。DDR 请求仍使用原始 VTC 时序，像素与五个标志同步延迟两拍。

AE、增益、AWB、LSC 和识别模型没有改动。96..99 的显示亮度修正进入 DDR，可能改变运动输入；亮度阶段差异为 -4..0 DN，帧差变化不超过 4 DN，这不是对后续所有运动事件的形式保证。gain8 风格化与 OSD 调色试验未启用。

实测需要分别核对画面噪声与细节、运动框、普通 CNN、PCB、文档、写字机、断网续写和 DDR；不沿用其他 bit 组合的实测结论。
