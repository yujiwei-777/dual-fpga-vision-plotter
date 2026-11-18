# 2026-11-18：多目标坐标与空闲串口保护

主板 `main_cnn_multicoord_20261118`，副板 `secondary_plotter_idle_preflight_20261118`（r2）。

- [下载可直接转发的完整源码工程包，约 25.2 MiB](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.18-multicoord-idle/vision_plotter_multicoord_idle_20261118.zip)
- [SHA256 校验](../release/20261118_multicoord_idle/SHA256SUMS.txt)
- [源工程](../hardware_versions/20261118_multicoord_idle/)
- [中文使用页](../hardware_versions/20261118_multicoord_idle/00_开始使用.html)（下载后本地打开）

## 本版变化

最多四个普通 CNN 目标，每个目标独立显示名称、实际分数和原图中心 X/Y，名称与坐标共用槽位；SW2 关闭识别显示时一起隐藏。坐标使用 1280×720 原图像素；分数不是正确概率。CNN 模式隐藏写字操作面板。

副板 KEY2 不再被普通 CNN 后台推理 busy 阻挡。启动尚未建立普通命令会话时，噪声或迟到停止状态可触发完整握手重试。安全空闲每 5 秒仅查询状态；已证明新鲜 Idle 且其后没有发送命令时，接收帧错误可重新确认。活动命令错误、Alarm、Reset 或未知/移动状态仍保持相应恢复限制，不自动解锁、回零或重放运动。

CNN/PCB 字体同字形中端点精确相连的转角连续落笔，分离笔画和字符仍抬笔。12 组报告逐条核对有向绘制线段及其顺序，文字、坐标、分数和换行不变；[命令与落笔次数对照](../hardware_versions/20261118_multicoord_idle/02_projects/secondary/reports/FONT_FLOW_SUMMARY.md)。XY 书写请求 5000 mm/min，空走 7000，Z 1200，落笔等待 100 ms。实际耗时由机械和控制器决定。

文档取原图中央宽高各 80%（x128..1151，y72..647），外围留空，不拉伸。有限 A4 纸面额度关闭；自动换行、上退纸及坐标数值检查保留。当前显示风格环为 16 档，保留原 ID 0–4、6–14、17、18，历史 19 档说明不能直接套用本版。

## 使用与重建

完整解压后打开 `00_开始使用.html`。仅烧录用 `01_bit/`；开发先运行 `python -B verify_package.py`，再运行 `python -B prepare_projects.py D:/fpga/dev_multicoord_idle`。不能直接依赖历史工程头中的 E 盘路径。

- [功能与限制](../hardware_versions/20261118_multicoord_idle/03_docs/版本功能.md)
- [接线与按键](../hardware_versions/20261118_multicoord_idle/03_docs/接线与操作.md)
- [工程入口及开发](../hardware_versions/20261118_multicoord_idle/03_docs/工程打开与开发.md)
- [原始签核与验证范围](../hardware_versions/20261118_multicoord_idle/03_docs/验证与限制.md)

器件 PH1P35MDG324、speed -3；Tang Dynasty Release 2026.1 SP2 / 6.2.200067。543 项冻结输入保留原字节；另附可搬移的 20 项坐标/像素流水/启动 UART/空闲 UART smoke。完整历史回归的本机路径需要适配；没有在接收者机器重新综合/布线。

## 构建与实板状态

| 板卡 | Setup WNS | Hold WNS | TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| 主板 | +0.314 ns | +0.020 ns | 0 | 93.38% | 89.81% | 92.50% |
| 副板 | +0.006 ns | +0.020 ns | 0 | 89.99% | 78.70% | 40.00% |

两板原始综合、布局布线、物理签核、只读 reimport 和 bitgen 通过，副板为 19 组当前功能验收。源码包经解压、校验、路径适配及 20 项定向仿真核验。整理期间未修改 RTL、模型、约束或重新生成 bit。

**实板 NOT_RUN**。实际启动及长空闲故障原因仍需 UART 记录；重点确认首次/长空闲后的 KEY1/KEY2、四目标坐标开关、CNN/PCB/文档、上退纸、KEY4 停止和断网续写。正常最后 ok 是控制器接收完成，不是机械已停。副板 6 ps 时序余量、厂商 DDR 既有警告与历史试验日志保留。

## bit SHA256

```text
main      52E2A1E8F2FC0B58873BBEE897E4D2F01BDABB1624AD9D98F38E19718DA66718
secondary E34B64D98152F4D15B06E995021CFDF82DAE9E1EA9DFF33BAA5420135F32A201
```

[2026-11-13 历史配对](SUSPECT_PAPER_20261113.md) 及更早版本继续保留。
