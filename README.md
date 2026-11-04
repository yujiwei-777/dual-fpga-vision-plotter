# 视觉识别质检与控制描摹系统

**Vision Inspection, Control & Tracing System · Dual-FPGA · FPGA 创新设计大赛参赛工程**

本作品基于 HX1P35A 平台，采用主从双 FPGA 与串口无线桥接协同架构，集成高清图像采集、视觉识别、PCB 质检和写字机控制，实现从图像感知、结果判定到报告书写与笔迹描摹的完整流程。

主板负责 SC500 摄像头 1280×720 图像采集、图像处理与风格化、运动区域检测、成像质量自动调节和 HDMI 信息叠加，并调度板间图像与识别结果传输；副板通过以太网接收图像，完成轻量化 CNN 目标识别、自动定位 PCB 二分类检测和文档笔迹提取，再将识别结果或笔迹转换为写字机路径；无线桥接模块负责转发副板与执行控制器之间的串口数据。

系统既能显示并书写目标名称、中心坐标和置信分数，输出 PCB 检测报告，也能将普通黑笔手写内容提取为中心线路径，按比例驱动写字机描摹，无需 OCR 或纸张四角定位。报告采用单线矢量字体，支持坐标镜像与自动换行；通过逐行应答、任务锁存和停止恢复机制，衔接视觉处理与 GRBL 运动控制，并在板间网络断开后保持已接受的写字任务。

## 系统结构

![系统总体框图：主板采集与显示，副板识别及路径规划，经无线桥接驱动 DLC32 写字机](docs/assets/pdf_20261102/architecture-system.png)

总体框图提取自技术文档第 5 页，展示模块分工与数据流。[简版架构图](docs/assets/system-architecture.png) · [简版 SVG 矢量图](docs/assets/system-architecture.svg)

<details>
<summary>展开硬件连接与模块接口图</summary>

硬件连接与接口（技术文档第 6 页）：

![SC500、双 FPGA、DDR、HDMI、以太网与 DLC32 的硬件连接](docs/assets/pdf_20261102/architecture-hardware.png)

关键电路与模块接口（技术文档第 8 页）：

![MIPI、ISP、DDR、HXA1、CNN 和 GRBL 模块接口](docs/assets/pdf_20261102/architecture-modules.png)

这些图保留文档中的概念性连接，具体 RTL 支路、模式及按键操作见[当前版本说明](docs/DISPLAY_NOISE_KEY1_20261103.md)。

</details>

## 实拍展示

| HDMI 图像采集与显示 | 多目标识别与信息叠加 |
| --- | --- |
| ![HDMI 显示器上的摄像头实时画面](docs/assets/hdmi-live.jpg) | ![绿色圆柱与红色三角物块的识别演示](docs/assets/cnn-targets.jpg) |
| **不同物块识别** | **写字机执行平台** |
| ![红色与蓝色物块的多目标识别画面](docs/assets/cnn-multiple.jpg) | ![安装笔夹的写字机与开发阶段纸面绘制结果](docs/assets/plotter-hardware.jpg) |

照片取自项目开发阶段的实拍记录，画面中的 OSD 为当时版本。更多图像处理效果及文档路径回放见 [演示图集](docs/GALLERY.md)。

| 局部运动检测 | 手写笔迹采集 |
| --- | --- |
| ![手部运动区域检测画面](docs/assets/pdf_20261102/motion-detection.jpg) | ![摄像头采集纸面手写笔迹](docs/assets/pdf_20261102/document-input.jpg) |

图像风格化与增强效果：

![红蓝通道、伪彩、卡通化、海报化及亮度增强实拍对照](docs/assets/pdf_20261102/style-overview-2.jpg)

以上新增图片提取自 2026-11-02 技术文档；完整 18 种效果、CNN 样本和历史 PCB 取景画面见[图集](docs/GALLERY.md#技术文档补充图片)。

## 程序特色

1. **双 FPGA 分工处理。** 主板采集并处理 720p 图像，负责 HDMI 显示、运动检测和板间调度；副板执行 CNN、PCB 检测与文档路径规划，降低单板同时承担显示和识别任务的压力。
2. **视觉结果可直接执行。** 普通 CNN 输出类别名称、图像中心坐标和模型 margin；PCB 输出 PASS、FAIL 或 REVIEW。识别报告可交给写字机书写，形成从图像输入到实体输出的闭环。
3. **CNN 与 PCB 使用不同识别流程。** 普通目标采用 9 类轻量化 CNN；PCB 先以共享 CCL 定位候选区域，再用 96×96 Y8 输入进行 GOOD/BAD 二分类，低 margin 单独标为 REVIEW。
4. **手写描摹不依赖文字识别。** 文档模式直接从整帧提取黑色笔迹，经过骨架化和路径规划生成机器轨迹；不做 OCR，不要求检测纸张四角。路径保留中心线特征，并对分叉处进行拆笔处理。
5. **识别报告采用适合落笔的路径。** 报告文字使用单线矢量字模，统一坐标镜像与边界检查，并按内容高度自动换行；减少栅格字体逐行描边产生的重复路径。
6. **显示链路兼顾图像质量与边缘。** 当前主板版本加入 RGB8 二维保边空间滤波，对低对比纹理可能产生柔化；这是空间滤波，不是帧间 TNR，也不代表所有摄像头噪声都已消除。
7. **写字任务有明确的接收与停止流程。** G-code 按行等待 GRBL `ok` 后再发送下一条；已接受的任务不因板间以太网短暂断开而取消，副板 KEY4 用于任务停止与重置，KEY3 用于副板应用复位。
8. **源码和硬件交付可核验。** 仓库保留配套主副板工程、模型、约束、构建证据和 bit，并提供文件哈希及工程引用校验。当前配对 bit 的实板验收状态为 `NOT_RUN`，功能与测试边界见版本说明。

## 主要功能

| 功能 | 当前版本行为 |
| --- | --- |
| 图像处理与风格化 | 支持原图及 18 种处理模式，包括灰度、二值化、Sobel 边缘、形态学、伪彩、海报化、卡通化和亮度增强；按键切换并显示当前模式 |
| 运动区域检测 | 硬件帧差结合亮度自适应阈值、区域筛选和连续确认，叠加运动框及区域内变化采样点数；SW1 控制运动显示 |
| 成像质量自动调节 | 根据亮度与颜色统计自动调整曝光、模拟 / 数字增益和白平衡；显示支路采用保留 RGB8 的二维保边空间滤波（非 TNR） |
| 普通目标识别 | 9 类 CNN；输出名称、图像中心坐标和置信分数；连续确认与短暂不确定保持，允许输出真实低分结果 |
| PCB 检测 | 共享 CCL 自动定位最大候选，以原框采样 96×96 Y8，执行 GOOD / BAD 二分类；输出 PASS / FAIL / REVIEW；主板 KEY4 每次按下触发一次 |
| 文档复制 | 整帧按比例映射，320×180 网格，每格读取 4×4 源像素；骨架、路径规划、机器坐标和 G-code；不做 OCR，不要求纸张四角或距离标定 |
| 笔迹路径 | 端点优先和分叉拆笔；针对固定机位右侧摄像头脏斑做局部补偿，保留路径容量与边界检查 |
| 写字报告 | 单线中心线矢量字体、一次 X 镜像、报告自动换行；PCB 二分类报告按文字实际高度换行 |
| 本地操作 | 副板 KEY1 提交当前 CNN/PCB 缓存报告（PCB 单次消费）、KEY2 一次方框测试、KEY3 整体应用复位、KEY4 写字任务停止与重置 |
| 任务保持 | 以太网断链不取消已接受的写字任务；串口错误单独处理，已发送运动命令不盲目重放 |
| 主板显示 | 中文信息叠加、算法模式与延迟字段、PCB 实际检测框和左下状态、识别框及结果显示 |

CNN 分数是模型输出经缩放得到的 margin，**不是校准后的正确概率**。描摹路径是几何中心线，不等于汉字标准笔顺。镜头脏斑补偿与当前机位和裁剪有关。

风格化使用传统图像算子与定点流水线实现。自动曝光、增益和白平衡根据场景统计反馈调节；显示空间滤波与自动成像控制分别工作。算法与源码入口见 [图像风格化、运动检测与成像调节](docs/VERSION_SCOPE.md#图像风格化运动检测与成像调节)。

## 模式与操作

主板通过 SW4:SW3 选择任务模式，板间识别需选择向副板传图的通路。两板同名按键功能不同，完整接线与操作见 [硬件与控制](docs/HARDWARE_AND_CONTROL.md)。

| SW4:SW3 | 模式 | 主要操作 |
| --- | --- | --- |
| 00 | 普通 CNN | 显示目标名称、中心坐标与分数；副板 KEY1 锁存结果并书写报告 |
| 01 | PCB 检测 | 主板 KEY4 按下并消抖后识别一次，长按不连拍；结果先缓存，按副板 KEY1 才书写 PCB 报告 |
| 10 | 文档复制 | 按整帧比例提取笔迹并生成中心线路径，不依赖纸张四角定位 |
| 11 | 保留 | 暂无功能 |

PCB 框来自副板返回的原图候选坐标，表示检测对象范围，不表示缺陷位置。当前模型不做方向校正，摆放角度变化仍需实测。文档使用 A4 纸面坐标和安全边界，与相机测距是两项不同功能。运动数值表示所选运动区域内的变化采样点数，不是累计物体数量。与旧版介绍的具体差异及 RTL 依据见 [当前版本功能范围](docs/DISPLAY_NOISE_KEY1_20261103.md)。

## 当前版本：2026-11-03 显示空间滤波 + KEY1 报告版

配套主板为 display_noise_fix，副板为 pcb_ccl_binary_key1_write。主板更新二维保边空间滤波和亮度表局部修正，保留 RGB8；副板与上一 KEY1 写字版相同。CNN/PCB 结果先缓存，按副板 KEY1 才提交当前模式的报告；PCB 结果只消费一次，失效结果不重放。文档复制入口保持独立。该组合实板状态 **NOT_RUN**。

[下载可直接转发的源码交付包（约 10 MB）](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.03-display-noise-key1/vision_inspection_plotter_display_noise_key1_source_20261103.zip)。解压后打开“00_开始使用.html”，包含配套 bit、两板工程、接线和使用说明。[完整构建归档](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/tag/v2026.11.03-display-noise-key1) 单独提供日志、验证记录与检查点。

历史版本：[KEY1 报告原版](docs/CCL_BINARY_KEY1_WRITE_20261103.md)、[CCL 二分类原版](docs/CCL_BINARY_RETRAINED_20261103.md)、[pose7 版](docs/POSE7_AUTO_20261102.md)、[2026-11-01 固定窗口版](hardware/)。

## 工程入口

| 板卡 | 工程入口 |
| --- | --- |
| 主板 | [camera_to_dsi_display_720p60_cnn_multibox.al](hardware_versions/20261103_display_noise_key1/main_display_noise_fix_20261103/camera_to_dsi_display_720p60_cnn_multibox.al) |
| 副板 | [secondary_cnn_multibox.al](hardware_versions/20261103_display_noise_key1/secondary_pcb_ccl_binary_key1_write_20261103/secondary_cnn_multibox.al) |

两板器件均为 PH1P35MDG324、speed -3；工具记录为 Tang Dynasty **Release 2026.1 SP2 / 6.2.200067**。

~~~text
hardware_versions/20261103_display_noise_key1/
  main_display_noise_fix_20261103/             主板源码、约束、bit 与构建证据
  secondary_pcb_ccl_binary_key1_write_20261103/ 副板冻结源码、模型、bit 与回归证据
  PACKAGE_MANIFEST.json                     文件与 bit 身份
  SOURCE_AND_EVIDENCE_MAPPING.json          冻结输入和证据哈希映射
hardware/                                  2026-11-01 原版完整归档
docs/                                      功能、操作与验证说明
release/20261103_display_noise_key1/                 新版身份与验收记录
verify_release.py                          分别校验五组归档
~~~

## 下载与校验

| 板卡 | 文件 |
| --- | --- |
| 主板 | [dual_fpga_main_20261103_display_noise_fix_diagnostic.bit](hardware_versions/20261103_display_noise_key1/main_display_noise_fix_20261103/artifacts/dual_fpga_main_20261103_display_noise_fix_diagnostic.bit) |
| 副板 | [dual_fpga_secondary_20261103_pcb_ccl_binary_key1_write_diagnostic.bit](hardware_versions/20261103_display_noise_key1/secondary_pcb_ccl_binary_key1_write_20261103/artifacts/dual_fpga_secondary_20261103_pcb_ccl_binary_key1_write_diagnostic.bit) |

~~~text
主板 SHA256
B7F39A1E4E4906074BA59BB8C124BA1B24690C6D33D20BFA47C7AF817C60D485

副板 SHA256
D8AEABE97D2249C13D0CFB31E80196D5F05701B3C214BBA6FDDCEA8D611AAF15
~~~

下载后先运行：

~~~powershell
python -B verify_release.py
~~~

校验不需要 FPGA 工具。建议使用 **Python 3.11+**，下载完整仓库到短英文路径。构建流程见 [构建与核验](docs/BUILD_AND_VERIFY.md)；接线和按键见 [硬件与控制](docs/HARDWARE_AND_CONTROL.md)。

## 资源与时序

| 板卡 | Setup WNS | Hold WNS | TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| display_noise_fix 主板 | +0.174 ns | +0.020 ns | 0 | 92.59% | 86.11% | 92.50% |
| KEY1 报告版副板 | +0.021 ns | +0.020 ns | 0 | 90.77% | 75.93% | 45.00% |

主板 193 项、副板 324 项构建输入已校验。主板最终 V8 通过源码哈希一致的 V6/V7 仿真与逐周期等价链验证，未重跑全部 V8 仿真。副板保留独立综合、布局布线、双角时序和只读核验记录；KEY1 控制 23 项、普通 CNN 27 向量、PCB 核心 18 向量及集成流水线回归已记录。主板原始诊断 RUN-8007 / USR-8450 与独立容量、IO 对照记录同时保留。

PCB 的 231 个有效留出帧中，分类正确 222 个（96.10%）；仍有 **7 张缺焊盘被接受为 PASS**。这些是同批采集分块测试，不能作为新板、新工位的准确率。验证范围见 [新版说明](docs/DISPLAY_NOISE_KEY1_20261103.md)。

本版显示亮度表仅修正输入 96..99，CNN 固定亮度支路不变；显示变化进入 DDR，运动输入可能受影响。低对比纹理可能变柔，严重噪声现象尚缺少对应故障原始帧验证。

## 版权与使用

本项目作者原创的 RTL、脚本和文档采用 [MIT 许可证](LICENSE)，允许在保留版权与许可声明的前提下使用、修改和再分发，包括商业使用。

厂商 IP、第三方模块及其衍生部分保留原有版权和许可，不因本仓库采用 MIT 而重新授权。工具生成文件与 bit 不统一授予 MIT 权利；使用范围见 [第三方与许可范围说明](docs/THIRD_PARTY_NOTICES.md)。ESP32 桥接固件需另行配置。
