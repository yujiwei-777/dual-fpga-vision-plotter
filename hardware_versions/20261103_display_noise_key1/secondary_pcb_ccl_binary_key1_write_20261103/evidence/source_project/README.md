# KEY1-Triggered PCB/CNN Diagnostic Bit

This independent secondary-board variant changes local report writing so a completed recognition result is cached instead of immediately starting the plotter. Press secondary-board KEY1 once to write the current result for the active vision purpose:

- CNN purpose: write the cached class name, center coordinates, and actual confidence.
- PCB purpose: write the cached `PASS`, `FAIL`, or `REVIEW` result. A PCB result is consumed once.

An absent or expired result is not replayed. KEY1 is accepted only when the GRBL link and pen profile are ready. An accepted report is held locally and continues through network disconnection. Document-copy tasks remain on their existing HXA task path and are not started by KEY1. Explicit Type20 remote write commands remain separate existing entry points (command 1 fixed test; command 2 current CNN report).

The ordinary CNN model and PCB binary C4/C4 model, shared CCL, Type18/Type8 result paths, HXA1, DDR, document-copy planner, KEY2, KEY3 full-secondary reset, KEY4 task reset, vector lettering, mirror, newline handling, and GRBL transport are retained. The main-board project was not modified.

## Bit And Build

Diagnostic bit: [`artifacts/dual_fpga_secondary_20261103_pcb_ccl_binary_key1_write_diagnostic.bit`](artifacts/dual_fpga_secondary_20261103_pcb_ccl_binary_key1_write_diagnostic.bit)

SHA256: `D8AEABE97D2249C13D0CFB31E80196D5F05701B3C214BBA6FDDCEA8D611AAF15`

Hardware status: **NOT_RUN**. This is not yet a board-validated release.

The RTL/model source is frozen in this variant with manifest SHA256 `B8285CD02FFACDBB6B9913EDC94D14B9D34FA4F5C21E9A484C8A542636347914`. The reviewed routed database SHA256 is `E860BA850D48DB69DD7E31355F2810C5E2A25DAEA30AC3910E41418AE901D2A8`. Bitgen ran from the reviewed copy `E:/codex_pcb_binary_ccl_retrained_20261103_key1_reviewed_bitgen/` after the source-bound evidence gate passed. Detailed records are in [`reports/retrained/release_20261103/`](reports/retrained/release_20261103/) and the release index is [`artifacts/RELEASE_MANIFEST.json`](artifacts/RELEASE_MANIFEST.json).

Routed utilization is Slice `19258/21216` (90.77%), ERAM `82/108` (75.93%), and DSP `18/40` (45.00%). Slow-corner setup WNS is `+0.021 ns`, hold WNS is `+0.020 ns`, and setup/hold TNS are both `0`; both slow and fast routed corners were checked. DRC reported 72 NOTE-level slice-attribute findings and no ERROR/WARN findings. The static CDC/FIFO review is bound to the same routed database. DDR source/IP/constraint identity was checked, but no board-level DDR calibration or memory test was run.

## Functional Evidence And Limits

- KEY1 mode/cache/admission test: 23 checks passed.
- Verilog syntax check: 81 files passed.
- Preserved regression suite: 10 suites passed, including ordinary CNN (27 integer vectors), document copy, plotter, controls, reset, reader, and HXA/FIFO.
- PCB integer core: 18 vectors passed.
- Integrated PCB pipeline: 18 fixtures, 22 completed frames, 3 cancellation points, and ordinary-empty reentry passed.
- Routed physical review: 176 source-snapshot entries matched the frozen manifest; two normalized path aliases had matching hashes and sizes. CDC/FIFO max-delay path slack minimum was `+4.854 ns`.

The PCB model remains the user-sample C4/C4 binary model with the existing shared CCL and 1.00x CCL box crop. Its existing evaluation contained 231 valid frames with 222 correct classifications (96.10%), including 7 missing-pad images accepted as PASS. These are not an independent blind test and do not establish field accuracy. The CNN, PCB camera placement, physical KEY1, writing quality, network-disconnect continuation, and DDR electrical behavior still require board testing.

See [`reports/retrained/release_20261103/RELEASE_SUMMARY.md`](reports/retrained/release_20261103/RELEASE_SUMMARY.md) for the test/report paths and their scope.
