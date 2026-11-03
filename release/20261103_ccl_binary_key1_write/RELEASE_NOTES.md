# KEY1 报告版 · CNN/PCB 手动提交书写

[下载源码交付包（约 7.9 MiB）](https://github.com/yujiwei-777/dual-fpga-vision-plotter/releases/download/v2026.11.03-ccl-binary-key1-write/vision_inspection_plotter_key1_write_source_20261103.zip)。解压后打开“00_开始使用.html”，查看工程入口、配套 bit、接线和操作说明。完整构建证据见归档包，模型训练背景见 CCL 二分类历史版本说明。

- 主板：main_pcb_auto_compat_20261101。
- 副板：secondary_pcb_ccl_binary_key1_write_20261103。
- CNN/PCB 结果先缓存，按副板 KEY1 才提交当前模式报告；PCB 单次消费，不重放失效结果。文档复制入口不变。
- 主板 189 项、副板 324 项冻结输入；两板工程入口均为包内相对路径。
- 副板 setup/hold +0.021/+0.020 ns，TNS=0；Slice 90.77%、ERAM 75.93%、DSP 45%。
- KEY1 23 项、普通 CNN 27 向量、PCB 核心 18 向量及集成流水线回归记录附在工程包中。
- PCB 模型不变，原分块 test 仍有 7 张缺焊盘误判 PASS。
- 实板状态 NOT_RUN，异机重新构建尚未验证。

精简源码包运行 python -B verify_delivery.py；完整归档运行 python -B verify_package.py；仓库根运行 python -B verify_release.py。
