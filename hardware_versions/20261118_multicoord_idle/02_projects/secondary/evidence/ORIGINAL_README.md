# 写字机启动、空闲恢复与报告连续书写

独立于 `secondary_cnn_key1_live_snapshot_20261118`，旧工程、旧 bit 和 work 备份不变。

* KEY2 画方框不再受普通 CNN 后台推理 busy 阻挡。
* 尚未建立任何普通命令会话时，启动串口噪声或迟到的停止状态触发完整握手重试；控制器晚启动无需按键重新触发。
* 安全空闲时每5秒只发送状态查询。仅在新鲜 Idle 已证明没有待完成运动、且之后没有发送命令时，允许用新鲜查询恢复接收帧错误。
* Alarm、运行/未知启动状态、明确恢复流程及活动任务错误仍保持锁定。不会自动解锁、回零或重发运动命令。
* CNN/PCB 字体同一字形中端点精确相连的转角保持落笔；不同笔画及字符间继续抬笔。完整有向绘制线段、文字及换行与旧规则一致。
* 书写进给仍为5000 mm/min，落笔等待100ms。通过减少重复抬笔、空移及命令提升流畅度，不提高落笔深度。

验证覆盖启动噪声、写字机迟启动、长空闲、空闲帧错误恢复、连续 CNN/PCB/KEY2，以及普通 CNN、PCB、文档复制、按键和纸张管理回归。仿真可以复现旧逻辑的锁定条件；实板故障原因仍须实际 UART 记录确认。

构建：`E:/codex_secondary_plotter_idle_preflight_20261118_r2`。最终签核、资源、时序及 bit 以 `artifacts/RELEASE_REPORT.json` 为准；不存在该文件时表示尚未完成交付。实板状态始终标记 NOT_RUN。

最终已生成 diagnostic bit：`artifacts/dual_fpga_secondary_20261118_plotter_idle_preflight_diagnostic.bit`。Slice 19093/21216（89.99%），ERAM 85/108（78.70%），DSP 16/40（40%）。Setup WNS +0.006 ns，Hold WNS +0.020 ns，TNS=0。19组当前功能验收、物理签核、只读重导入和 bitgen 全部通过；实板 NOT_RUN。
