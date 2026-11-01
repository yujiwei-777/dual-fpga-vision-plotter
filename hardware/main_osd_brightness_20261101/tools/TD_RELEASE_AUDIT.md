# TD 构建输入与 bitgen 验收

`td_release_audit.py` 只读取设计、约束、MEM、日志和数据库，写 JSON/审查 Tcl；不会改 RTL/SDC、运行 place/route 或改已有 bit。

## 构建前

先生成干净 `.al`，在首次 `read_design` 前执行：

```powershell
python tools/td_release_audit.py snapshot --root . --run <syn_run> --name <project_name> --config tools/release_audit_config.json
```

输出 `source_snapshot.json` 必须 PASS。快照覆盖 `.al` 的活动引用、IP-XACT 文件集、include、已知 `$readmemh/$readmemb` 及 `--extra` 指定依赖。相对 MEM 同时检查运行目录和源码目录；若两处存在且内容不同则拒绝。路径解析跟随目录联接，拒绝独立工程外的依赖与 `work/`。条件分支和参数覆盖必须有 `release_audit_config.json` 中的明确源码/表达式/理由；脚本不声称具有完整 HDL elaboration 能力。

也兼容本项目 `_gen_project.py` 在构建前生成的 `project_root/name/files[{path,sha256}]` 源树快照。每个活动输入必须被该快照覆盖，或为运行目录中与已冻结源文件哈希一致的副本。不得在构建后补写快照来认证旧实现。

## bitgen 前

```powershell
python tools/td_release_audit.py gate --root . --run <phy_run> --syn-run <syn_run> --name <project_name> --snapshot <syn_run>/source_snapshot.json --config tools/release_audit_config.json
```

成功 exit 0，`release_gate.json` 中 `bitgen_allowed=true`。失败 exit 1。要求：

- 源/约束/IP/MEM 与构建前快照逐文件一致，且源文件不晚于综合开始。
- 最终 `.opt_route.end.f`、routed DB、`route_flow.status` 和最终报告存在且时间顺序合理。
- `_pr.timing` 明确为 Routed，Slow/Fast 两角 Max/Min 均已检查。
- SWNS/HWNS ≥ 0，STNS/HTNS = 0。
- 按实际计数计算 Slice < 95%、ERAM < 90%、DSP < 95%，等于门槛也拒绝。
- 综合与实现日志无致命错误和缺失 ROM/MEM 警告（包括 HDL-5105）。

默认读取 syn/phy 目录内最新 `td_*.log`；可重复 `--log` 明确指定实际日志。`.stop.f` 或步骤 error marker 会拒绝。不会以 `bitgen` 成功替代时序验收。剩余 CDC、FIFO、DDR、DRC 和时钟覆盖报告仍须人工/专项审查。

本次副板源树生成器快照遗漏了 IP-XACT 内的 `.txt` DDR 配置 ROM。保留原快照不变，使用：

```powershell
--supplemental 02_sim/release_audit_20261020/rom_binding/supplemental_frozen_ddr_input.json
```

这是限定为 `ddrphy_cfg_rom.txt` 的补充冻结证据；脚本重新验证历史源清单、当前 ROM、当前综合 `elaborate.db`、只读导出网表和导出前后 `.al`/DB 的 SHA256，并从网表 INIT_VALUE 解析 **45 个 52 位字**逐值核对。历史清单及 ROM 必须早于本次综合。缺少任何一项则拒绝，不能用当前文件时间替代数据库内容证据。后续新构建应直接在构建前快照纳入所有 IP-XACT 文件集，无需此补充。

## 只读 reimport

```powershell
python tools/td_release_audit.py reimport-template --root . --run <phy_run> --name <project_name> --audit-dir 02_sim/readonly_reimport
```

生成 Tcl 与 `readonly_input_hashes.json`。在 TD 中执行生成的脚本；它只导入设备/工程/`_pr.db`，执行最终 timing/area/clock/exception/check 报告，不重新读取或清除约束、不导出 DB、不运行 place/route/bitgen。日志应包含 `TD_READONLY_REIMPORT_PASS`。

```powershell
python tools/td_release_audit.py verify-readonly --root . --run <phy_run> --name <project_name> --audit-dir 02_sim/readonly_reimport --log <actual_td_log>
```

核对导入前后 `.al`/DB SHA256 不变、最终时序仍通过、各报告存在。实板状态始终单独标记为 `NOT_RUN`，不得把工具验收解释为实板稳定性通过。

若需只读导出 elaboration 网表以证明 ROM 初始化内容，可运行 `rom-template` 子命令，参数同 `reimport-template`，生成模板仅导入 `<name>_elaborate.db` 并 `write_verilog` 到新的审查目录。它不修改设计数据库。

工具回归：`python tools/test_td_release_audit.py`。覆盖有效双角结果、等于资源门槛、缺失 ROM 日志、源被修改、单角未检查、过期 DB、负 hold、构建后补快照，共 8 项。
