# 多目标坐标 OSD 版本

最多四个目标分别显示名称、原始分数和原图中心点坐标，名称与坐标使用同一槽位，随识别显示开关一起显示或隐藏。无效槽位隐藏。

右上角面板每个目标使用两行；CNN 模式仍隐藏写字面板。普通模型、Type18/Type21、DDR、文档中央80%取景、画风控制保持基线行为。

bit：`artifacts/dual_fpga_main_20261118_cnn_multicoord_diagnostic.bit`

已完成当前源码绑定的 RTL 回归、综合、布局、布线、最终 DRC、只读重导入、实际放置资源核验和 bitgen。实板状态：NOT_RUN。

最终资源：Slice 19811/21216（93.38%），ERAM 97/108（89.81%），DSP 37/40（92.50%）。Setup WNS +0.314 ns，Hold WNS +0.020 ns，TNS=0。

详细签核及 SHA256：`artifacts/RELEASE_REPORT.json`。
