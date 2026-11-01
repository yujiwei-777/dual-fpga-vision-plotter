# v2026.11.01 · 双 FPGA 视觉识别与智能描绘系统

首个参赛归档发布，收录用户指定的 2026-11-01 主板亮度 / 中文 OSD 与副板固定脏斑补偿 / CNN 低分输出版本。

包含主副板完整可移交 RTL、IP 依赖、ADC / SDC、模型与 ROM、参考和仿真输入、构建与资源 / 时序报告、精确源清单及两个原始 diagnostic bit。GitHub 自动生成的 Source code 归档包含完整仓库；单独下载的 bit 请用 SHA256SUMS.txt 校验。

用户于 2026-11-01 确认本组合全部通过实测，记录为 PASS_USER_REPORTED，见 HARDWARE_ACCEPTANCE.json。原包历史 NOT_RUN 和构建过程记录保持原样。本次仅整理发布，不修改 RTL / 模型 / 约束，不重新综合或生成 bit。

## 主要功能

- 普通 CNN 名称、中心坐标与真实 margin 分数输出，连续确认与不确定保持。
- 固定窗口 PCB 二分类、主板按住 KEY4 检测及左下角状态 OSD。
- 整帧 320×180 文档复制、4×4 块读取、骨架和路径规划、固定机位脏斑补偿。
- 单线矢量报告、一次 X 镜像、自动换行、KEY2 方框测试。
- KEY3 副板应用复位、KEY4 写字停止 / 重置；已接受任务的断网保持。
- 主板图像处理、运动检测与计数、A4 占比估距和亮度调整。

## 文件身份

主板：dual_fpga_main_20261101_osd_brightness_diagnostic.bit

SHA256：FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515

副板：dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic.bit

SHA256：5066DC18572D27361957A63C1702EA3CD060CAEDAB88A0172F8A3C86451C1F34

## 构建与验证说明

下载完整源码后运行 python -B verify_release.py，核对源包和 bit 身份。TD 工具记录 Release 2026.1 SP2，器件 PH1P35MDG324，speed -3。

主板实际 route：setup +0.384 ns / hold +0.020 ns / Slice 92.73%；副板最终报告：setup +0.005 ns / hold +0.020 ns / Slice 91.70%；两板 TNS 0。

主板部分只读 / 专项审查和源快照继承先前版本，不能描述为当前 brightness 新跑完整审查；当前源对应差异与实际日志已单独说明。CNN margin 不是校准概率；脏斑补偿与机位有关；最终 G-code ok 表示控制器接收，不代表机械 Idle。第三方声明和原版权保留，未另授统一开源许可。
