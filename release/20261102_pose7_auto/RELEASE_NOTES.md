# 自动定位 PCB 与配套主板 · 2026-11-02

副板采用 CCL 最大候选定位、96×96 Y8 输入、0/180° 判向和良品空间异常评分；主板显示真实候选框，PCB 结果使用独立 30 秒等待预算。普通 CNN、文档复制和矢量写字功能保留。

完整工程、模型、约束、回归与构建证据见 hardware_versions/20261102_pose7_auto/；运行 python -B verify_release.py 核对新旧归档。源包约 170 MB，源文件字节不变，未重新生成 bit。

- 主板：dual_fpga_main_20261101_pcb_auto_compat_diagnostic.bit
- SHA256：B048D5BD30915F7C08791A9947D90982B741929E00CC0BE3036F7018C76209BC
- 副板：dual_fpga_secondary_20261102_pcb_pose7_goodonly_ccl_diagnostic.bit
- SHA256：AD02D4FC18AA58307EC2A3CBC1C5482B2B92B3FCF93CC0077B76748D11B692A8

主板 setup/hold WNS +0.384/+0.020 ns，Slice 92.93%；副板 +0.002/+0.017 ns，Slice 91.13%，两板 TNS=0。主板保留原始 RUN-8007/USR-8450 诊断及独立容量和 IO 审核记录，不能描述为原始检查全部无警告。副板部分未改源按哈希复用既有回归，具体范围见归档说明。

配对实板状态 NOT_RUN。本版不继承 v2026.11.01 的实测通过记录。只支持 0/180° 判向，不输出未经验证的缺陷位置；异常分数不是概率。详细操作、构建和验证限制见 docs/POSE7_AUTO_20261102.md。
