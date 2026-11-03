# 2026-11-03 Release Record

## Build Identity

- Variant source: `D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_key1_write_20261103/`
- Frozen source manifest SHA256: `B8285CD02FFACDBB6B9913EDC94D14B9D34FA4F5C21E9A484C8A542636347914`
- Routed database SHA256: `E860BA850D48DB69DD7E31355F2810C5E2A25DAEA30AC3910E41418AE901D2A8`
- Bitgen run: `E:/codex_pcb_binary_ccl_retrained_20261103_key1_reviewed_bitgen/`
- Bitgen result: `DIAGNOSTIC_NOT_RUN`; tool invocation passed with exit code 0 and no error markers.
- Hardware status: `NOT_RUN`.

`PRE_BITGEN_REVIEW.json` is the preserved route-stage snapshot and retains its default `bitgen_allowed: false`; the subsequent bitgen invocation separately revalidated strict routed timing/resources and the current hashed evidence gate before running.

## Resource And Timing Results

| Resource | Use | Utilization |
| --- | ---: | ---: |
| Slice | 19258 / 21216 | 90.77% |
| ERAM | 82 / 108 | 75.93% |
| DSP | 18 / 40 | 45.00% |

Routed two-corner timing: setup WNS `+0.021 ns`, setup TNS `0`; hold WNS `+0.020 ns`, hold TNS `0`. The reviewed source-bound build gate, routed DRC, and read-only reimport are in the adjacent JSON and report files. DRC has 24 `SLATR-1036` and 48 `SLATR-1038` NOTE findings; it has no ERROR or WARN findings.

The static physical review contains 443 CDC connectivity proof records, 10 reset/CDC inventory groups, and 478 routed exception slack records. The four constrained groups contain 290, 128, 9, and 52 paths, all dominated, unshadowed, and unignored; minimum reported slack is `+4.854 ns`. All 176 routed source-snapshot entries bind to the frozen manifest after path normalization (174 exact paths and 2 `..` aliases; zero content or size mismatches). Forty-five DDR IP/configuration/constraint files match the frozen build and referenced baseline. This is static connectivity, constraints, and source identity evidence; it is not an independent CDC certification, a formal all-traffic FIFO proof, or a physical DDR board test.

## Functional Results

- KEY1 mode-specific cached report admission: 23 checks passed.
- Syntax: 81 Verilog files passed.
- Preserved regression: 10 suites passed.
- Ordinary CNN integer regression: 27 vectors passed.
- PCB binary integer core: 18 vectors passed.
- PCB integrated pipeline: 18 fixtures, 22 completed frames, 3 cancellation points, and ordinary-empty reentry passed.

Primary test records:

- `../key1_pcb/20261103T023311_470038Z/RESULTS.json`
- `../regressions/run_20261103T025706_248559Z/RESULTS.json`
- `../binary_validation/core/run_20261103T032410_695075Z/RESULTS.json`
- `../binary_validation/pipeline/run_20261103T033308_256929Z/RESULTS.json`
- `../SYNTAX.json`

KEY1 is a local single-press path for the currently selected CNN or PCB purpose. The explicit Type20 remote report commands remain separate existing entry points. Document copying is not started by KEY1.

## Model Limits And Board Test

The PCB C4/C4 evaluation set had 231 valid frames, 222 correct results (96.10%), and 7 missing-pad images accepted as PASS. It is not an independent blind set. Before hardware use, verify KEY1 behavior in both modes, CNN/PCB output content, repeated presses, no stale-result replay, network loss after job acceptance, KEY4 stop, KEY3 reset, document copy, and DDR operation. The bit remains `NOT_RUN` until those board checks are complete.
