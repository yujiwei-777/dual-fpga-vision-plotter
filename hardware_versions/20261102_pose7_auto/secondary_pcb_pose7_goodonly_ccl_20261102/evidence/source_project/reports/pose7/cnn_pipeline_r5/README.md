# r5 CNN 外部 MAC 流水回归

权威小型入口：`R5_REGRESSION_BINDING.json`。生产 manifest：`3D847C5B889CEEF42A5CACAD22412145447AB4BC510463722DD0CDC852FC74FE`。

普通 CNN 27 项重新生成整数参考，使用真实共享 workspace 与 shared DSP，明确为 `EXTERNAL_MAC=1`。输入、Conv1、Conv2、logits、颜色累加、类别和置信度均逐值通过。每 ROI 1,880,088 周期，比旧核增加 49,155；27 项输出与旧结果完全相同。编译及仿真零错误、零警告。

附加 miter 将新 external-MAC 核与冻结 r4 local-MAC 核及整数参考比较，完整运行 7 次；每次检查 1,486,848 个乘积，首末 tap 各 49,155、padding 54,752、Conv drain 49,152 和 FC drain 3。6 个 raw-reset 边界和 6 次空闲期间 PCB/CNN workspace、DSP 所有权切换后均可完整重入；零错误、零警告。

r5 PCB 全流水也重新运行，6 帧和 3 次取消重入通过，所有 ROI/方向/特征/累加器/分数/状态保持一致；像素 reader 为抽象模型。

本目录只镜像小型结果、bench 和绑定报告。普通与 miter 全日志/仿真库位于 E:/codex_pose7_ordinary_20261102_r5/。PCB 流水完整路径见绑定报告。

这些结果不代表独立实拍准确率。reset 与 purpose 附加用例测试核及共享资源，未完整展开 HXA/DDR/top 任务授权；物理时序、CDC 和实板仍须分别验收。生产源未修改，实板 NOT_RUN。
