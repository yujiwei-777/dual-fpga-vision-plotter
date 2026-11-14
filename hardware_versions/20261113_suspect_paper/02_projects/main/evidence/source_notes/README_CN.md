# PCB 疑似区域中心标记主板

当前实现与验证入口见 `IMPLEMENTATION_R4.md`，实际发布状态以 `artifacts/RELEASE_REPORT.json` 为准。

独立主板变体，在现有黄色疑似区域中增加框内点状准线，中心采用原图半开坐标，与副板 KEY1 报告一致。保留按需操作面板、中文 OSD 及原接口。

此显示改动不提高定位准确率；缺焊盘定位仍未达到既定 80% 目标。实板状态：`NOT_RUN`。

r4 已完成生成 diagnostic bit：`artifacts/dual_fpga_main_20261113_pcb_suspect_center_diagnostic.bit`。布线后 Slice 93.6463%、ERAM 89.8148%、DSP 92.50%，setup WNS +0.383 ns、hold WNS +0.020 ns、TNS 均为 0。DRC、只读重导入及完整 Slice 物理位置审计通过；CDC/FIFO/DDR 静态检查通过。实际功能测试范围与配套副板路径见 `IMPLEMENTATION_R4.md`。
