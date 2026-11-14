当前主板中心十字构建的严格审计入口：

```powershell
D:/conda/python.exe -B D:/program/fpga/lab_ex3_osd_SC500_720P/main_pcb_suspect_center_20261113/tools/audit_current_route.py --attempt r1
```

仅在 `run_build_phases.py` 完成当前 r1 综合、布局、布线后执行。脚本已通过语法解析和当前 225 个冻结输入的只读哈希核验；准备阶段未调用 vendor 工具或执行本审计。

每次尝试写入新的 `E:/codex_pcb_suspect_center_main_20261113_r1/audits/route_acceptance_<attempt>/`，拒绝覆盖旧证据。先验证当前三阶段回执、日志、工具、Tcl、源清单和完成标记，随后运行冻结的通用 release gate，并显式绑定当前 synth/place/route 三份日志。门槛为布线 setup/hold WNS ≥ 0、TNS = 0、Slice < 95%、ERAM < 90%、DSP < 95%。

只读重导入模板来自本构建冻结的 `td_release_audit.py`。仅补充当前路由数据库的完整 Slice 枚举、位置导出及 tile 查询，不重载约束、不修改布局、不生成 bit。独立 capacity validator 将当前 Slice 名称和实际位置逐个对应至冻结器件拓扑，要求合法、类型兼容且位置不重复，并与本次路由面积报告精确对账。拓扑文本是器件参考，不是历史工程通过报告。

最后调用当前构建既有的 `audits/summarize_readonly.py`，用显式参数绑定本次 gate、只读验证、脚本、日志和原始路由日志，检查最终 DRC 阶段、时序、面积和 CDC/FIFO/DDR 静态证据。源清单、AL、PRJ、综合/路由数据库和路由报告在每个子进程前后核验不变。最终成功凭据是 `CURRENT_ROUTE_ACCEPTANCE.json` 的 `passed: true`，失败日志保留。

此入口不运行 bitgen，也不把静态证据当成功能仿真、DDR 运行时校准、机械运动完成或实板验收；实板状态仍为 `NOT_RUN`。后续交付须另行绑定当前功能回归和 bitgen 前门禁。

严格审计通过后的 bitgen 入口已准备，尚未执行：

```powershell
D:/conda/python.exe -B D:/program/fpga/lab_ex3_osd_SC500_720P/main_pcb_suspect_center_20261113/tools/bitgen_current.py --acceptance E:/codex_pcb_suspect_center_main_20261113_r1/audits/route_acceptance_r1/CURRENT_ROUTE_ACCEPTANCE.json --attempt r1
```

`--acceptance` 可指定本构建的新审计尝试，`--attempt` 必须使用全新后缀；不支持复用其他构建。默认绑定当前变体的中心十字与动态面板/Type21 实际 RTL 回归（两份 `20261113T125205_684881Z/RESULT.json`），可以显式指定同一变体的新报告，但仍需完整源清单、输入哈希、实际三步工具回执、日志哈希及唯一 PASS 标记。

bitgen 在新的构建 `audits/bitgen_<attempt>/` 内暂存 bit/BID；不直接写最终产物。校验当前严格审计及其原始报告、AL/PRJ/综合与路由数据库、清单、路由报告、当前源工程依赖和 217 个原基线/控制文件，运行前后再次复核。工具重新导入当前路由库，bitgen 前后均生成最终时序与面积报告；必须与已接受结果精确一致并通过相同门槛。所有校验通过后才无覆盖发布至当前独立工程的 `artifacts/`，最终名称 `dual_fpga_main_20261113_pcb_suspect_center_diagnostic.bit`，并发布对应 BID 与带 SHA256 的 `RELEASE_REPORT.json`。最终报告存在且状态为 `PASS_DIAGNOSTIC_NOT_RUN` 才表示发布完成。

静态预检查已通过：225 个冻结输入、当前两份 RTL 回归及日志、217 个基线/控制文件、193 个当前源工程闭包依赖，以及冻结的时序/面积解析器。未执行本 bitgen，未修改旧基线、受保护目录或冻结构建输入。
