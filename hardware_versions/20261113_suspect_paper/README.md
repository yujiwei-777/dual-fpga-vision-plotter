# 视觉识别质检与控制描摹系统

2026-11-13 双板工程：主板 SUSPECT 黄色框与点状中心准线，副板纸张上纸确认、退纸与连续矢量书写。

**解压后先打开 [00_开始使用.html](00_开始使用.html)。** 仅需烧录时使用 `01_bit/` 中配套文件；阅读或开发使用 `02_projects/`。两板器件均为 PH1P35MDG324、speed -3，构建工具 Tang Dynasty Release 2026.1 SP2 / 6.2.200067。

| 目录 | 内容 |
| --- | --- |
| 01_bit | 指定的主、副板 bit |
| 02_projects/main | 主板 251 项冻结输入、约束、IP 与构建证据 |
| 02_projects/secondary | 副板 299 项冻结输入、模型、IP、仿真材料与构建证据 |
| 03_docs | 中文接线、操作、工程开发和版本限制说明 |
| 04_verification | 配对身份、范围说明与校验结果 |

校验：`python -B verify_package.py`。开发前运行 `python -B prepare_projects.py D:/fpga/dev_suspect_paper`，在新目录适配工程路径；交付原件不变。详细入口见 [工程打开与开发](03_docs/工程打开与开发.md)。

源码、模型、约束和 bit 保留原始字节，没有重新生成 bit。实板状态 **NOT_RUN**；副板 setup 余量仅 0.007 ns。原始静态审计和回归范围见 [验证与限制](03_docs/验证与限制.md)。

完整成功构建检查点、原始日志及历史试验单独收于 `_complete.zip`，下载入口：https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/tag/v2026.11.13-suspect-paper。

原创 RTL、脚本和文档采用 MIT；厂商 IP、第三方模块、模型与 bit 的许可范围见 [第三方说明](03_docs/第三方与版权说明.md)。工具、许可证、原始训练数据集和无线桥接固件不随包提供。
