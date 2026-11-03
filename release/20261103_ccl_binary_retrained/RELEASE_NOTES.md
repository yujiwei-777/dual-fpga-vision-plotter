# CCL 自动定位 PCB 二分类配套工程

推荐下载：[源码交付包（约 5.8 MiB）](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.03-ccl-binary-retrained/vision_inspection_plotter_source_20261103.zip)。解压后打开“00_开始使用.html”，可查看两板工程入口、烧录文件、接线和操作说明。

需要完整训练、构建日志及检查点时，下载下方 dual_fpga_pair_ccl_binary_retrained_20261103.zip。

- 主板：main_pcb_auto_compat_20261101。
- 副板：secondary_pcb_ccl_binary_user_retrained_20261102，原框 ×1.0、96×96 Y8、C4/C4 GOOD/BAD 模型；不启用 pose7 方向校正与异常评分。
- 完整源码、模型、约束、重训、仿真和构建证据随工程包提供；两板 bit 与原文件一致。
- 副板 r3 继承 r2 综合/布局检查点，最终 setup/hold 为 +0.005/+0.020 ns，Slice 90.72%、ERAM 75.93%、DSP 45%。
- 同批采集分块 test 为 222/231 分类正确，仍有 7 张缺焊盘被接受为 PASS。
- 本配对实板状态 NOT_RUN，旧版验收记录独立保留。

解压完整 ZIP 后运行 python -B verify_package.py。仓库根运行 python -B verify_release.py 可校验三组版本。工程入口、输入契约与验证范围见 docs/CCL_BINARY_RETRAINED_20261103.md。
