# 视觉识别质检与控制描摹系统

2026-11-18 配套工程：多目标中心坐标 OSD、写字机启动与空闲通信保护、连续矢量书写。

**完整解压后，打开 `00_开始使用.html`。**

| 目录 | 内容 |
| --- | --- |
| 01_bit | 配套主、副板 bit，各一份 |
| 02_projects/main | 主板 RTL、IP、约束、仿真和构建证据 |
| 02_projects/secondary | 副板 RTL、CNN/PCB 模型、IP、约束、仿真和构建证据 |
| 03_docs | 接线、按键、版本差异、工程打开与验证说明 |
| 04_verification | 配对身份、文件校验、源码及证据映射 |

校验：`python -B verify_package.py`。

开发前：`python -B prepare_projects.py D:/fpga/dev_multicoord_idle`。目标目录必须不存在，脚本在新目录适配工程路径及 ROM 别名，原始交付文件不变。不要直接用历史 AL/PRJ 头部的 E 盘路径开展构建。

器件 PH1P35MDG324、speed -3；构建工具 Tang Dynasty Release 2026.1 SP2 / 6.2.200067。详见 [工程打开与开发](03_docs/工程打开与开发.md)。

两板构建通过，实板状态 **NOT_RUN**。副板 setup 余量仅 0.006 ns。本包没有修改 RTL、模型、约束或重新生成 bit。

原创 RTL、脚本和文档采用 MIT，厂商 IP 等遵循原条款；见 [第三方说明](03_docs/THIRD_PARTY_NOTICES.md)。FPGA/仿真工具、工具许可证、原始训练集及外部桥接固件不随包提供。
