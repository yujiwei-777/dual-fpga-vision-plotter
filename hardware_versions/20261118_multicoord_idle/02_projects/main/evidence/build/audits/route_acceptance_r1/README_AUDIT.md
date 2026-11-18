# 主板动态 OSD 当前构建静态审计

候选工程：`E:\codex_main_cnn_multicoord_20261118_r1`

结果：`PASS_CURRENT_BUILD_STATIC_AUDIT`。实板状态：`NOT_RUN`。

| 项目 | 当前只读报告结果 |
|---|---:|
| SLICE | 19811 / 21216 = 93.3776%（要求 <95%） |
| ERAM | 97 / 108 = 89.8148%（要求 <90%） |
| DSP | 37 / 40 = 92.5000%（要求 <95%） |
| Setup WNS / TNS | 0.314 / 0.0 ns |
| Hold WNS / TNS | 0.02 / 0.0 ns |

Route 最终 DRC Stage 6 与八项检查完成：`True`；原生日志错误/ROM 扫描：`True`。
AL/DB 只读输入哈希未变：`True`。当前输入、脚本、日志、报告哈希见 JSON。

CDC/FIFO/DDR：`STATIC_EVIDENCE_ONLY`。SDC 有 2 组 set_clock_groups、22 条 set_path_skew、19 条 set_max_delay；check_timing 报告 6 条 soft FIFO 异步路径。

未运行或证明独立 CDC/FIFO 功能仿真、DDR 运行时校准、内存流量测试或实板功能。

check_timing 非零诊断分类：

- dummy node：3（HIGH）
- soft fifo timing exception constraints：6（HIGH）
- no path constraints：4（MEDIUM）
- shadowed/ignored timing exception constraints：1（MEDIUM）
- no input delay：40（MEDIUM）
- no output delay：63（MEDIUM）
- partial input delay：1（MEDIUM）

机器可读结果：`READONLY_AUDIT_REPORT.json`。本汇总未复用旧构建 PASS，未调用任何构建工具。
