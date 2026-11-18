# Operator metadata and physical paper contract

This independent variant preserves the baseline models and accepted report/document ownership. All hardware remains `NOT_RUN`. SUSPECT accuracy remains `EXPLORATORY_NOT_PASSED`.

## Pending preview

Type21 / OPR1 views the existing CNN/PCB caches. When a capable peer first samples a valid pending snapshot, the cache is locked; later valid ordinary frames do not replace it. A current no-target result, mode/session/config invalidation, new PCB transaction, explicit cancellation or reset clears stale preview. KEY1 admits that same cache; the accepted reporter snapshot is independent of further detection, packet session changes and Ethernet loss. A legacy peer without operator capability retains prior local KEY1 behavior. Snapshot sampling proves serialization started, not that HDMI already displayed or the human confirmed it. Document WAIT_KEY1 already owns a committed plan.

## Paper arithmetic

All distances are integer centi-millimetres (cmm).

`physical occupied cursor = rebased_y_cmm + newline_offset_cmm`.

The first page origin is Y=10mm; the A4 bottom safety margin is 10mm. Initial remaining report height is therefore 277mm. The cursor excludes the original 10mm margin. G92 changes work coordinates but never rewinds the physical paper budget. A completed KEY2 square returns X to the existing work X=0 at the next line and acknowledges G92 X0 Y0; only its final ACK advances rebased_y. A real completed soft-reset recovery moves rebased_y back into newline_offset because GRBL clears G92. Error/stop reserves started work and does not reclaim space.

Document uses the fixed 10..116.88mm mapper, so its committed plan can be prepared on occupied paper but KEY1 writing is allowed only when physical occupied cursor is zero. Accepted DRAW immediately reserves 111.88mm relative to the original 10mm origin (complete drawing height plus 5mm gap), even if later interrupted. Subsequent reports may start below that reservation. No dynamic document coordinate offset or machine motion is introduced.

## KEY2 and new paper

A debounced short press starts one square on release. A hold of at least two seconds requests only new-paper acknowledgement, once; release never starts an additional square. A press made while busy/unsafe is discarded until release and never deferred. Held-through-reset keys remain unarmed.

New-paper acknowledgement is a controlled upper-paper operation. After a completed KEY2 eject and manual paper loading, a long KEY1 hold sends `G90`, moves only `Y` to the configured first-row safety margin (default 10 mm; X is unchanged), waits for a fresh `Idle`, then sends `G92 X0 Y0`. It is accepted only when all preparation/drawing/report owners are idle, UART guard/profile are ready, and recovery is clear. Results: 0 none, 1 OK, 2 BUSY, 3 UNSAFE, 4 NEED_FRAME_RESET. A simultaneous accepted document reserve wins against new-page clear. Rejected requests are not replayed later.

When NEED_FRAME_RESET is shown, use the explicit GRBL recovery path to clear G92, reconfirm the calibrated work frame, then acknowledge new paper. KEY3 resets the complete application and GRBL startup recovery performs Ctrl-X; do not assume a volatile G92 survives. New-paper UI readiness alone is not proof of mechanical standstill: normal task completion follows final command `ok`, which means accepted rather than physically stopped. The operator must wait for the machine to stop before replacing paper.

## PCB reasons

Reason byte: 0 none/processing; 1 PASS; 2 MODEL FAIL; 3 LOW MARGIN; 4 NO TARGET; 5 CCL OVERFLOW; 6 SOURCE BORDER; 7 BBOX INVALID; 8 INPUT INVALID; 9 PIXEL READY TIMEOUT; 10 PIXEL REPLY TIMEOUT; 11 INFER TIMEOUT; 12 NUMERIC INVALID; 13 CANCEL; 14 REENTRY; 15 DRAIN LOCKED. Raw 16-bit error remains in the local PCB cache and recovery/ACK diagnostics. OPR1 bytes36..41 publish the accepted-command progress extension: byte36 flags, byte37 phase, bytes38..39 acknowledged G-code count, bytes40..41 total count (zero when unknown). The values are accepted-command progress only and never claim physical motion completion. These diagnostics do not name a verified defect type, change scores/margins, or alter classification.

## Regression scope

`tools/run_operator_ui_regression.py`: real KEY2 FSM, current top cache/snapshot/metadata, actual top + document controller, actual report/formatter/GRBL byte parser and transport, actual PCB wrapper with controlled classifier outputs. Five isolated ModelSim libraries; no FPGA build or physical CDC claim. Existing retained baseline tests are included. Additional current CNN publication and 22 classifier integer cases are run separately.

## Resource-constrained OPR1 publication

The 48-byte Type21 envelope and version remain unchanged. Byte34 and byte35 remain zero; bytes36..41 are the progress extension described above; bytes42..43 remain zero. Reason enum byte19, snapshot/job IDs bytes8..15, centre bytes20..23, paper bytes28..33, report_error byte44, and page_result byte45 retain their existing semantics. All preview locking and independent accepted-job snapshots remain intact. Internal UART ACK counters, last acknowledged G-code, safety/recovery state, and existing job-status transport remain unchanged. The main board may display bytes36..41 as instruction progress, with unknown totals shown as `-----`; it must not present them as physical completion or machine position.

KEY2 shares only the two mutually exclusive long-press and acceptance-wait timers. It preserves exact cycle-visible outputs, debounce, press/release, rejected-press discard, two-second page acknowledgement, and all task timeouts. The Type21 byte serializer uses a literal 48-entry mux with the same atomic held snapshot and no extra cycles.
