# 无“直方图”文字主板 bit（2026-10-31）

输出：`D:\program\fpga\lab_ex3_osd_SC500_720P\main_osd_chinese_no_hist_20261031\artifacts\dual_fpga_main_20261031_osd_chinese_no_hist_diagnostic.bit`

SHA256：`03AC1511A99AE16BD6113BE71C52C059FA4F7A17C75535C41709451EF18DF175`

基线 SHA256：`7733B6D65811E01C6A07CBA90C54884053B5872B090CCA26ED1B18990321DB06`；文件大小 `1789547` 字节，和基线相比有 `765109` 个字节不同。

修改仅涉及 `osd_compact_panel.v` 的模式行 cell 7..13：固定输出空格，隐藏“直方图”和 ON/OFF 指示；其它模式、布局、颜色、视频流水和接口保持不变。

验证：ModelSim 单元测试 74,186 checks，0 errors，0 warnings；TD bitgen 日志出现 `COMPACT_OSD_BITGEN_PASS`。route 结果为 setup WNS +0.382 ns、hold WNS +0.020 ns、TNS 0，Slice 92.58%，ERAM 83.33%，DSP 92.50%。

硬件状态：`NOT_RUN`。

辅助只读审查中的历史 RUN-8007/USR-8450 记录保留在 `02_sim/compact_readonly_v2/`，bitgen 未使用 `unconstr_io` 覆盖。
