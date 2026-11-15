# 2026-11-13：SUSPECT 中心准线与纸张维护

主板使用 main_pcb_suspect_center_20261113，副板使用 secondary_pcb_airwalk_stroke_cont_20261113。

主板把疑似区域画为黄色框，在框内显示每 8 像素一个点的中心准线；准线跟随原图区域，清除旧框时同时清除。副板保留 CNN、PCB、文档描摹与矢量报告，并提供 KEY2 长按退纸、KEY1 长按上纸确认。连续矢量段可保留落笔，独立笔画仍抬笔。

## 下载

- [可直接转发的源码工程包，约 17.8 MB](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.13-suspect-paper/vision_inspection_plotter_suspect_paper_20261113.zip)
- [完整构建归档，约 226 MB](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.13-suspect-paper/vision_inspection_plotter_suspect_paper_20261113_complete.zip)
- [SHA256 校验表](../release/20261113_suspect_paper/SHA256SUMS.txt)

完整解压后打开 `00_开始使用.html`。源码包包含两个指定 bit、550 项冻结输入、模型、约束、IP、仿真材料、构建报告、中文操作说明和校验脚本。完整归档另含成功构建数据库和原始日志，也保留明确标注的历史试验记录。

## 工程与开发

源码位于 [hardware_versions/20261113_suspect_paper](../hardware_versions/20261113_suspect_paper/)。先运行该目录的 `verify_package.py`，再用 `prepare_projects.py D:/fpga/dev_suspect_paper` 生成独立开发副本；脚本适配 AL/PRJ 根路径与等字节 ROM 别名，保持 RTL、模型和约束不变。不要直接使用历史工程头里的旧 E 盘路径。

- [工程打开与开发说明](../hardware_versions/20261113_suspect_paper/03_docs/工程打开与开发.md)
- [接线与按键](HARDWARE_AND_CONTROL.md)
- [功能范围](../hardware_versions/20261113_suspect_paper/03_docs/版本功能.md)
- [逐文件清单](../hardware_versions/20261113_suspect_paper/PACKAGE_MANIFEST.json)

本轮未重新生成 bit，源码直接取自两次成功构建的冻结输入。主板 251 项、副板 299 项已逐文件核对。指定配对以本页和 PAIR_IDENTITY 为准；副板原始发布报告提到的旧主板作为历史记录保留。

## 使用变化

- 主板 SW4:SW3：00 CNN，01 PCB，10 文档；SW2 控制信息叠加，板间网络固定连接副板。
- 主板 KEY4 每次稳定按下执行一次 PCB 识别，长按不连拍。SUSPECT 只是疑似区域，不是精确分割。
- 副板短按 KEY1 书写当前已锁存 CNN/PCB 报告或已准备的文档；先完成上纸确认。副板长按 KEY1 仅在待确认状态执行抬笔 Y 边界确认，不启动普通干跑。
- 短按 KEY2 画一个方框并换行，长按至少 2 秒退纸。换纸后人工放到滚筒大致中部，再长按 KEY1 确认。
- KEY3 复位整个副板应用；KEY4 仍走写字任务停止/重置和 GRBL 状态确认。FPGA 复位本身不证明外部机器停稳。
- 普通任务收到最后一行 ok 后完成逻辑任务；上纸、退纸、安全恢复仍需要新鲜 Idle。已接受任务不因板间断网取消或重放。
- 上纸确认只重建 Y，保留 X 基准；本地 Y 预算 237 mm，页面不足拒绝新任务。维护流程实际行程与滚筒方向需实机核验。
- HDMI 操作面板按需显示状态，尚不显示 N/M 数值进度或百分比。

## 构建与测试边界

| 板卡 | Setup WNS | Hold WNS | TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| 主板 | +0.383 ns | +0.020 ns | 0 | 93.6463% | 89.8148% | 92.50% |
| 副板 | +0.007 ns | +0.020 ns | 0 | 91.0162% | 79.6296% | 40.00% |

综合、布局布线、最终 DRC、只读 reimport、合法兼容物理位置核验及 bitgen 通过。原始 SYN-6024、逻辑 SLICEL PHY-7027 和 RUN-8007 诊断保留，不称为无警告构建。CDC/FIFO/DDR 为静态与行为证据，不代表实板校准或 MTBF 验证。

主板保留中心与显示协议回归、动态操作面板/Type21 回归及 4438724 周期的四目标标签输出等价检查。副板保留 11 组功能回归、纸张维护与文档映射对照；351 点、417 行 G-code 与控制组一致。具体仿真范围见原报告，不冒充全整板联合仿真。本轮只做交付校验和解压/路径适配测试，没有重跑原 RTL 仿真或 FPGA 构建。

该组合实板状态 **NOT_RUN**。副板 setup 余量仅 7 ps。旧版实测不自动适用于本配对。

PCB 保留 C4/C4 模型及 GOOD margin≥192、BAD margin≥32 的策略；弱 GOOD 返回 REVIEW。疑似区域历史缺角命中 21/24、缺焊盘 25/44；本次显示优化不提高定位准确率。CNN margin 不是概率；固定脏斑补偿不可直接推广到新相机。

## bit 身份

```text
main E2E1FE983B3D63056B4044710EF979A42FF8EBEDC81D6440C2301175FBE08011
secondary 5BA649F37D687B66809A6876B2AB9E77657D1C467BAD421E258B04143D5B8EE5
```

## 技术说明与答辩参考

[Markdown 在线阅读](defense_20261114/技术说明与答辩参考.md) · [PDF（48 页）](defense_20261114/技术说明与答辩参考.pdf) · [Word](defense_20261114/技术说明与答辩参考.docx)。文档为 2026-11-14 V1.1 算法详解版，与本配对工程对应。
