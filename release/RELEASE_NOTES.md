# v2026.11.01 · 视觉识别质检与控制描摹系统

2026-11-01 参赛版本，包含主板图像处理与中文 OSD、副板 CNN / PCB 识别、报告书写和文档描摹功能。

发布内容包括两板 RTL、IP 依赖、ADC / SDC、模型与 ROM、参考模型、仿真输入、构建报告及 diagnostic bit。下载 bit 后请用 SHA256SUMS.txt 校验。

使用说明见 [README](https://github.com/yujiwei-777/dual-fpga-vision-plotter/blob/main/README.md)，算法参数与源码入口见 [版本功能范围](https://github.com/yujiwei-777/dual-fpga-vision-plotter/blob/main/docs/VERSION_SCOPE.md)。标签与源码压缩包保留发布时的内容，说明文档在 main 分支持续更新。

实板测试结论及对应 bit 校验值见 [验收记录](https://github.com/yujiwei-777/dual-fpga-vision-plotter/blob/main/release/HARDWARE_ACCEPTANCE.json)，构建与仿真记录见 [验证说明](https://github.com/yujiwei-777/dual-fpga-vision-plotter/blob/main/docs/VALIDATION.md)。

## 主要功能

- 普通 CNN 名称、中心坐标与真实 margin 分数输出，连续确认与不确定保持。
- 固定窗口 PCB 二分类与左下角状态 OSD；主板 KEY4 每次按下触发一次，长按不连拍，松开不取消已接受任务；固定框用于摆放，不是缺陷定位框。
- 整帧 320×180 文档复制、4×4 块读取、骨架和路径规划、固定机位脏斑补偿。
- 单线矢量报告、一次 X 镜像、自动换行、KEY2 方框测试。
- KEY3 副板应用复位、KEY4 写字停止 / 重置；已接受任务的断网保持。
- 主板图像处理、运动区域及变化采样点数显示、亮度调整。运动数值不是累计物体数量；本版已移除 A4 测距，SW4:SW3=11 保留。

## bit 与校验值

主板：dual_fpga_main_20261101_osd_brightness_diagnostic.bit

SHA256：FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515

副板：dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic.bit

SHA256：5066DC18572D27361957A63C1702EA3CD060CAEDAB88A0172F8A3C86451C1F34

## 构建与验证说明

下载完整源码后运行 python -B verify_release.py，检查源文件与 bit 完整性。工具为 Tang Dynasty Release 2026.1 SP2，器件 PH1P35MDG324，speed -3。

主板实际 route：setup +0.384 ns / hold +0.020 ns / Slice 92.73%；副板最终报告：setup +0.005 ns / hold +0.020 ns / Slice 91.70%；两板 TNS 0。

主板部分专项检查和源快照沿用前版记录，差异详见验证说明。CNN margin 未经概率校准；脏斑补偿依赖机位；亮度曲线同时影响传给副板的图像；G-code 的 ok 表示控制器接收命令，机械停止需参考 Idle 状态。各文件遵循原有版权与许可条款。
