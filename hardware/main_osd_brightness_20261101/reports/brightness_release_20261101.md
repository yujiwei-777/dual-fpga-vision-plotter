# 画面亮度增强 bit（2026-11-01）

输出：`D:\program\fpga\lab_ex3_osd_SC500_720P\main_osd_brightness_20261101\artifacts\dual_fpga_main_20261101_osd_brightness_diagnostic.bit`

SHA256：`FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515`

本变体基于 `main_osd_chinese_no_hist_20261031`，仅将 `display_tone_96.v` 中原始显示 tone 曲线的常量 `48` 调为 `52`，约提高中高亮区域 4 个码值。没有修改 `hdmi_mixer`、CNN 输入协议、DDR、运动检测、OSD、HXA1 或摄像头寄存器。

最终 route：setup WNS `+0.384 ns`、hold WNS `+0.020 ns`、TNS `0`；Slice `92.58%`、ERAM `83.33%`、DSP `92.50%`。TD bitgen 日志通过。

实板亮度、过曝和识别影响尚未验证，状态：`NOT_RUN`。
