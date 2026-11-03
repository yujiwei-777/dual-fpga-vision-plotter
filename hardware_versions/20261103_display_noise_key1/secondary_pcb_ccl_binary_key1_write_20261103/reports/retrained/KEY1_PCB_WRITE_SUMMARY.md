# PCB Report Requires Local KEY1

Date: 2026-11-03

## Source provenance

- Independent variant: `D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_key1_write_20261103/`
- Source reference: `secondary_pcb_ccl_binary_user_retrained_20261102/`
- Reference `01_rtl/secondary_top.v` SHA256: `432CE427595A2D2E9790DB4CDD7E513EE7A2C22E16C334995E7FCCFAA0B29862`
- Variant `01_rtl/secondary_top.v` SHA256: `4D28967DBF6323869793D8094387462E9E818843C7A358D8FBAAD4F8BB47FB02`
- Variant project file SHA256: `2054BB8184EDBE6D766A3AD8DB56C8027AF6A42033FD38D150AFE751D4B95B40`
- No baseline project, bitstream, main-board project, or `work/` file was modified.

## Behavior

PCB inference completion now stores the latest valid verdict and its report payload. It does not start the GRBL report. A debounced press of the secondary-board KEY1 admits that snapshot to the existing report path. The accepted report is single-use; a new inspection, non-PCB task, no-target result, explicit cancellation, or KEY4 invalidates an unconsumed snapshot. KEY1 while the UART is unavailable or the profile is invalid leaves the snapshot available for a later press. Ordinary CNN KEY1 reporting and explicit Type20 reporting remain separate.

## Verification

- Focused top-control lint and simulation: **PASS**, 23 checks. Evidence: `key1_pcb/20261103T023311_470038Z/RESULTS.json`.
- Coverage includes no automatic print at PCB completion, PASS/FAIL/REVIEW snapshot handling, explicit KEY1 admission, duplicate prevention, stale-result invalidation, no-target rejection, and preservation across unavailable UART/profile followed by a successful retry.
- Complete project-file syntax compile: **PASS**, all 81 declared Verilog files. Result: `SYNTAX.json`; compiler output: `E:/codex_pcb_retrained_syntax_20261103T023348_676957Z/`.
- The focused simulation uses controlled interfaces for the CNN/PCB engines, reporter, DDR and network leaves. It validates top-level control behavior, not full-chip numerical integration. ModelSim reports unconnected top-level output-port warnings in this testbench.
- Synthesis, place, route, physical timing, CDC/FIFO/DDR system checks, DRC, reimport, bitgen, and board validation: **NOT_RUN**.

The variant is RTL-only and is not a deliverable bitstream. Hardware status remains `NOT_RUN`.
