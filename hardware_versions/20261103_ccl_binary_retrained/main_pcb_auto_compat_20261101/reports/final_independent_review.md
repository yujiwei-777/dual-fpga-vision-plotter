# Final independent source and release-gate review

Reviewed on 2026-11-01, Asia/Shanghai. Scope is the frozen V2 companion main-board source and the release tools named below. This review did not modify RTL or release tools. It writes only this report.

## Conclusion

No new deterministic functional defect was found in the four frozen RTL changes. Current source hashes match the V2 simulations and prebuild snapshot. The initial missing-regression-coverage gate weakness was reported immediately and has been corrected by the tool owner during this review; the corrected validator passes the complete manifest and rejects three in-memory incomplete variants.

One release-evidence hardening item remains: review_pcb_compat_release.py reads release_gate.json's passed flag without rechecking its evidence hashes, and its evidence dictionary does not directly include every prerequisite JSON. Current routed gate evidence was independently rehashed in this review and no drift was found. This is a future stale-evidence protection gap, not evidence of current DB/report drift. Final physical gate, standard-context bitgen and post-bitgen result remain the root agent's responsibility.

## Frozen functional inputs

All paths below are relative to main_pcb_auto_compat_20261101/.

| Input | SHA256 |
|---|---|
| 01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v | 60362844CDEDF666F75C2B5019405C2844D6EEEA1A0F8C4F03F220DC7C1FB740 |
| 01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v | CFC74557B9E0EB32AFC58E4F8FD80289C0400DFB020A59B6D66B6E11EC5A799A |
| 01_rtl/imgq_gain_m/main/user_source/hdl_source/hx_result_select.v | 4AAF5AA2B8A6C60376528605B3369345E5A227A724C056B3FC91A5B6EAFB081F |
| 01_rtl/imgq_gain_m/main/user_source/hdl_source/key4_hold_debounce.v | 647E4AE545EB270F70A09E508E8F2DF0C917EDA987A1476F408CE3BB4D3DF01C |

Source scope evidence lists exactly these four changed active sources. Other active source/dependency hashes and the protected baseline bit remain separately checked by the scope tool. This is a comparison of the recovered active source inputs; it does not retroactively improve the provenance of an older bit.

## Timer and task lifecycle

- hxa_main_link.v lines 87-92 use an independent parameter-sized remaining budget. The default and explicit top-level instance are 30000 ms. Ordinary control_ms remains 12 bits and saturates at 3000.
- A current valid FRAME_ACK loads the PCB budget at lines 802-806. It is not started during capture or transport; ordinary CNN loads zero and retains its 2000 ms result timeout.
- The nonzero budget decrements on tick_ms outside the state case, including LOAD_CONTROL/TX_START/TX_WAIT used for heartbeats and cached result ACKs. These control sends do not reload the budget.
- Successful result commit, terminal failure, cancel, offline/PHY failure, reset, discovery restart and new capture clear the budget. Zero does not wrap because decrement is guarded by reduction-OR active.
- A result already staged before timeout has the existing commit priority. A packet completed after cancellation cannot become the next task: CANCEL clears result_seen and job_active; a fresh capture clears staged-result flags and increments job_id.
- Session filtering occurs before payload decoding. Current frame and payload job ID are checked before accepting Type8. Completed-result retransmission only schedules the cached ACK and does not start a capture or replace the active job.
- The 3 s lease and 250 ms heartbeat remain independent. Existing lease renewal on any accepted session packet was preserved; it was not silently restricted or expanded in this change.
- Evidence: link_pcb_wait_v2/transcript_batch_final.log reports five complete frames, 6400 DATA packets, 188 heartbeats, a measured 30000 ms PCB timeout, ordinary 2000 ms timeout, wrong identity rejection, cached ACK deadline preservation and real lease loss.

## Result clear and CDC mailbox

- Top-level remote_clear is only S_mode_pcb_eth && S_snap_capture_req. It does not reset the mailbox or change unrelated ordinary-CNN updates.
- hx_result_select keeps the held request/ack protocol. clear_pending retains a capture invalidation while a prior request is outstanding. Payload and valid state are not changed while the receiving mailbox owns that request.
- If clear and a result toggle share a source clock, dirty records the toggle, an invalid publication is sent first, and the latest payload can be sent after acknowledgment. The next legitimate result is not discarded by a delayed clear.
- The pixel endpoint retains request synchronization and settling before capturing held data, and output selection still changes at frame_start. No new clock domain, asynchronous data path or video stage was introduced.
- The added port only treats ===1'b1 as clear, so older named-port instances omitting remote_clear do not receive an X/Z-driven clear in simulation.
- Evidence: pcb_actual_box_v2/transcript.log covers same-edge clear/result, capture while mailbox busy, clear of a prior valid result, and delivery of the new valid result. Existing FIFO/mailbox path-skew and physical timing checks still belong to the release gate.

## Current task box and KEY4 state

- PCB mode selects the actual Type8 coordinates, using the existing exclusive-end to inclusive-HDMI conversion. It does not substitute the old fixed placement rectangle or an old Type18 summary.
- A PCB box requires current remote source, PCB metadata tag and terminal PASS/FAIL/REVIEW status. READY, SCANNING, NO_TARGET and link error hide it; a new capture also clears the prior mailbox validity.
- SW2-off visibility remains enabled for PCB. Ordinary CNN and document/other modes retain their existing overlay gates. Mode entry cannot display a previous ordinary-CNN result as a PCB object.
- Busy KEY4 re-press no longer overwrites SCANNING with READY. Release does not cancel the accepted task. Debounce and fresh-release single-pulse behavior are unchanged.
- The V2 six-coordinate mux absorption is Boolean-equivalent to the V1 two-level selector. The real extracted expressions pass 400012 comparisons including invalid endpoint subtraction behavior.
- Evidence: pcb_actual_box_v2 integration has 13 passing checks including a real 2.1 s simulated SCANNING interval, valid/empty results, state gating and old-result isolation; KEY4 one-shot regression passes four qualified presses plus reset-held, mode-held and bounce cases.

## Release tools and preserved diagnostics

Reviewed tools: review_pcb_compat_release.py, prepare_pcb_compat_audit.py, run_pcb_compat_audit.ps1, and the directly used strict_release_review.py/td_release_audit.py helpers.

- The routed gate uses current active source collection, the prebuild snapshot, run identity and pre-synthesis timestamp; requires route completion and routed both-corner setup/hold reports; applies exact integer Slice/ERAM/DSP strict limits; records raw logs and DB/report hashes.
- Read-only preparation refuses existing Tcl evidence, checks the snapshot and routed-gate status, and emits no place/route/save/constraint override. Read-only DB/AL hashes are captured and later compared.
- Standard-context generation uses the actual standard project/run-param context. Bitgen generation requires independent prebitgen review and refuses to overwrite an existing bit or Tcl evidence.
- The PowerShell launcher checks each native process exit status and refuses to overwrite existing TD logs. Its bitgen stage reruns independent review before generating the standard bitgen script.
- strict_release_review retains raw check_design failure and raw check_io warnings. A logical LSLICE exception needs the exact recognized diagnostic plus complete compatible unique physical placement evidence. check_io catch=0 alone is not treated as a clean command.
- Current raw readonly console still contains RUN-8007 and USR-8450 (10 out of 39). These are adverse diagnostics, not clean checks; independent physical capacity, 79-pad/source-pin/baseline-context checks and standard bitgen are additional evidence. They must remain visible in final limitations.
- DRC acceptance is narrowly limited to counted SLATR-1036/SLATR-1038 NOTE entries. Other rules/severity, missing counts, mismatched summaries or negative routed timing reject release. RTCLK-5078 and USR-6113 remain explicitly tracked.

## Findings and resolution

1. RESOLVED during this review: the original validator accepted any nonempty all-true regression map, allowing a required test to be omitted. The tool owner added 21 explicitly required checks, five required current RTL inputs bound to the routed snapshot, and 13 named hash-bound logs. Reviewed corrected script SHA256: 92375BE9C8236DD92897C0235045B4DCBBC4B011FB31835960F4196E72E651AE. In-memory negative probes removing document_type15, current hxa_main_link input, or the packet-level final log were all rejected; complete current evidence passed. No production files were mutated by these probes.

2. HARDENING RECOMMENDATION: revalidate release_gate.json evidence hashes at every final review and include prerequisite source_snapshot, release_gate, scope, readonly verification, standard-context input hashes, regression JSON and audit-tool hashes in the final evidence dictionary. prepare bitgen should validate that review's evidence rather than only its passed flag. Current actual gate evidence was independently rehashed and had no mismatches, and the launcher reruns review immediately before bitgen, reducing the present exposure.

## Evidence and limits

Current aggregate reports/pcb_compat_regression.json contains 21 checks, 38 input hashes and 13 logs, including the current downcounter link and V2 top hashes above. Five ordinary-CNN/startup/document regressions were rerun with vsim -batch; all compiled and simulated with zero errors/warnings and exit 0. These simulations use behavioral snapshot/peer boundaries and do not replace PHY, DDR electrical, actual PCB inference latency or HDMI board testing.

The observed routed gate reports setup WNS +0.384 ns, hold WNS +0.020 ns, setup/hold TNS 0; Slice 19715/21216 (92.925%), ERAM 90/108 (83.333%), DSP 37/40 (92.50%). These numbers are observations from current release_gate.json, not a substitute for the root's final physical review or standard bitgen.

The 30 s PCB budget is provisional until the full secondary pipeline's worst-case duration and board testing are measured. Hardware status: NOT_RUN. This report does not claim successful bitgen or authorize deletion of raw adverse diagnostics.

## Resolution addendum: final evidence hardening

The tool owner subsequently implemented the release-gate evidence and prerequisite-JSON binding recommended above. The original findings remain in this report as review history; the current resolution supersedes the statement that those two gaps remain open.

Reviewed final review_pcb_compat_release.py SHA256: FA9432CBD7BEFE6C08428C36CF31D3D475FAA0E9561E4B5FA9DC7B948ED24B8B. Evidence test source SHA256: 674B89A78FE7C12E83F65278233C9021CB92334C0D0312AD733A0B9085CD7206. No RTL, constraints, tools or build inputs were edited by this addendum review.

- validate_gate_evidence now requires passed=true, bitgen_allowed=true, an empty failures list, and matching run/name/snapshot identity. It checks every bound evidence file's SHA256, checks recorded timestamps when present, rejects paths outside the run and duplicate canonical paths, and requires all nine expected items: final timing, physical area, route flow, route-end marker, synthesis-start marker, routed DB, synthesis log, placement log and routing log.
- Final review now records SHA256 for seven prerequisite JSON documents: source_snapshot, release_gate, source_scope, regression, readonly_verification, readonly_input_hashes and standard-context input_hashes. A read-only check against the current prebitgen review confirmed all seven bindings match their current bytes. All nine current routed-gate evidence items independently passed the new validator.
- The already-hardened regression validator still requires the 21 named checks, five current RTL inputs bound to the routed snapshot, and 13 named hash-bound logs with clean completion markers.
- The final PowerShell bitgen stage reruns the independent review before preparing standard bitgen. The preparation helper also rechecks the prebuild snapshot and gate status, requires a passing prebitgen review and refuses to overwrite existing bit/Tcl evidence. Standard bitgen remains free of unconstr_io or set_param overrides.

The reviewer independently reran python -B -m unittest discover -s main_pcb_auto_compat_20261101/tools -p test_pcb_compat_release_evidence.py -v. All 14 tests passed, exit 0, in 1.074 seconds. These are two complete-evidence positive cases plus twelve adversarial test methods, several of which iterate over every required item. They exercise arbitrary check maps, missing individual checks/RTL/logs, truthy strings, stale RTL, unbound logs, absent PASS markers, snapshot mismatch, a bare gate passed flag, missing each of the nine gate items and routed-DB byte drift. Temporary fixtures are isolated outside the real build and deleted by the test harness.

These resolutions do not remove or downgrade raw RUN-8007 or USR-8450 diagnostics. Their original logs, strict review details and physical/context interpretation remain required release evidence. This addendum concerns source and evidence-gate review only; it does not assert completion of the concurrently executing bitgen or any hardware test. Hardware remains NOT_RUN.
