# 双 FPGA 视觉识别与智能描绘系统

**Dual-FPGA Vision & Plotter · FPGA 创新设计大赛参赛工程**

本作品以 HX1P35A 平台为核心，由主从双 FPGA 和串口无线桥接模块协同完成图像采集、视觉识别、PCB 检测、结果显示和写字机输出。主板采集 SC500 摄像头 1280×720 图像，进行图像处理、运动检测与计数、A4 占比估距及 HDMI 信息叠加；副板通过以太网接收图像，执行普通目标 CNN、PCB 二分类及文档笔迹中心线提取，并向 GRBL 执行控制器发送确认式 G-code。

仓库收录用户指定的 **2026-11-01 主副板版本**及其源工程、模型、约束、仿真和构建证据。用户于 2026-11-01 确认本组合全部通过实测，见 [实测与验证说明](docs/VALIDATION.md)。本次发布整理没有修改 RTL、模型、约束或重新生成 bit。

## 系统结构

~~~mermaid
flowchart LR
    CAMERA[SC500 摄像头] --> MAIN[主 FPGA：采集 / 图像处理 / 调度]
    MAIN --> HDMI[HDMI：画面 / 识别框 / 中文 OSD]
    MAIN <-->|以太网 HXA1 / Type18| SECOND[副 FPGA：DDR / CNN / PCB / 笔迹规划]
    SECOND <-->|UART 115200 8N1| BRIDGE[串口无线桥接模块]
    BRIDGE <--> GRBL[GRBL 执行控制器]
    GRBL --> PLOTTER[写字机]
~~~

## 主要功能

| 功能 | 当前版本行为 |
| --- | --- |
| 普通目标识别 | 9 类 CNN；输出名称、图像中心坐标和置信分数；连续确认与短暂不确定保持，允许输出真实低分结果 |
| PCB 检测 | 固定检测窗口、96×96 Y8、4→4 轻量二分类；通过 / 失败 / 复核；主板按住 KEY4 触发，左下角显示状态 |
| 文档复制 | 整帧按比例映射，320×180 网格，每格读取 4×4 源像素；骨架、路径规划、机器坐标和 G-code；不做 OCR，不要求纸张四角或距离标定 |
| 笔迹路径 | 端点优先和分叉拆笔；针对固定机位右侧摄像头脏斑做局部补偿，保留路径容量与边界检查 |
| 写字报告 | 单线中心线矢量字体、一次 X 镜像、报告自动换行；PCB 二分类报告按文字实际高度换行 |
| 本地操作 | 副板 KEY1 提交识别结果报告、KEY2 一次方框测试、KEY3 整体应用复位、KEY4 写字任务停止与重置 |
| 任务保持 | 以太网断链不取消已接受的写字任务；串口错误单独处理，已发送运动命令不盲目重放 |
| 主板显示 | 中文 OSD、PCB 固定框和左下状态、运动检测计数、A4 估距、亮度调整 |

CNN 分数是模型输出经缩放得到的 margin，**不是校准后的正确概率**。描摹路径是几何中心线，不等于汉字标准笔顺。镜头脏斑补偿与当前机位和裁剪有关。

## 工程入口

| 板卡 | 工程入口 |
| --- | --- |
| 主板 | [camera_to_dsi_display_720p60_cnn_multibox.al](hardware/main_osd_brightness_20261101/camera_to_dsi_display_720p60_cnn_multibox.al) |
| 副板 | [secondary_cnn_multibox.al](hardware/secondary_doc_dirt_lowconf_factored_20261101/secondary_cnn_multibox.al) |

两板器件均为 PH1P35MDG324、speed -3；工具记录为 Tang Dynasty **Release 2026.1 SP2 / 6.2.200067**。

~~~text
hardware/                     原封双板可移交工程包
  main_osd_brightness_20261101/ 主板 RTL、IP、模型、约束、bit、证据
  secondary_doc_dirt_lowconf_factored_20261101/
                                副板 RTL、IP、模型、约束、bit、证据
  PACKAGE_MANIFEST.json        原包逐文件身份
  SHA256SUMS.txt               原包校验清单
docs/                         参赛说明、硬件接口、构建和验收状态
release/                      指定 bit 哈希与用户实测确认
verify_release.py             校验源包、bit 与实测声明的绑定
~~~

## 指定 bit

| 板卡 | 文件 |
| --- | --- |
| 主板 | [dual_fpga_main_20261101_osd_brightness_diagnostic.bit](hardware/main_osd_brightness_20261101/artifacts/dual_fpga_main_20261101_osd_brightness_diagnostic.bit) |
| 副板 | [dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic.bit](hardware/secondary_doc_dirt_lowconf_factored_20261101/artifacts/dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic.bit) |

~~~text
主板 SHA256
FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515

副板 SHA256
5066DC18572D27361957A63C1702EA3CD060CAEDAB88A0172F8A3C86451C1F34
~~~

下载后先运行：

~~~powershell
python -B verify_release.py
~~~

校验不需要 FPGA 工具。建议使用 **Python 3.11+**，下载完整仓库到短英文路径。构建流程见 [构建与核验](docs/BUILD_AND_VERIFY.md)；接线和按键见 [硬件与控制](docs/HARDWARE_AND_CONTROL.md)。

## 已有资源与时序记录

| 板卡 | Setup WNS | Hold WNS | TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| 主板实际布线报告 | +0.384 ns | +0.020 ns | 0 | 92.73% | 83.33% | 92.50% |
| 副板最终发布报告 | +0.005 ns | +0.020 ns | 0 | 91.70% | 84.26% | 45.00% |

副板记录包含完整最终构建审查。主板本版综合、布线和 bitgen 日志齐备，但部分源快照、只读 reimport 与专项审查继承自先前版本，不能描述为本版新跑过的全部审查。详细说明见 [验证记录](docs/VALIDATION.md)。

主板亮度曲线也送入 fixed tap，可能改变副板接收到的像素，不能描述成只影响 HDMI。原始证据中的历史 NOT_RUN 状态保留，当前用户实测结论单独记录。

## 版权与使用

仓库包含作者实现及原工程依赖的厂商 IP / 第三方 RTL。原有版权和使用说明保持原样；本次整理未为第三方文件重新授予开源许可。参见 [第三方声明](docs/THIRD_PARTY_NOTICES.md)。ESP32 桥接固件不在本次双 FPGA 源包交付范围内。
