# Display-noise build attempts

V1, V2 and V3 did not produce a bit. Their failed or incomplete evidence remains
available and must not be used as approval for a subsequent attempt.

| Attempt | Result | Retained evidence |
| --- | --- | --- |
| V1 | Synthesis introduced nine PRJ-7001 missing-input warnings for baseline AutoExcluded project entries | Original `td_project_display_noise_v1`, inactive-file audit |
| V2 | Synthesis completed; placement failed during GP Phase 1 with PHY-7027 and PHY-9002 | Original `td_project_display_noise_v2`, copied logs/reports in `attempt2_evidence`, hash manifest `attempt2_failure_and_v3_preparation.json` |
| V3 | Exact arithmetic compression passed fresh spatial simulation and synthesis, but GP Phase 1 placement again failed with PHY-7027 and PHY-9002 | Original V3 run, `attempt3_rtl`, `attempt3_evidence`, `attempt3_failure_and_v4_preparation.json` |
| V4 | Independent run prepared for the selected separable 2x2 candidate; freeze and FPGA-tool execution remain separate | `td_project_display_noise_v4`; requires its own freeze, simulation and implementation |

V2 reported preliminary Slice* 21147/21216 (99.67%), ERAM 93/108 and DSP 37/40.
At GP entry it reported 21649 LUT instances, 20982 sequential instances,
568 MSLICE instances and 4259 LSLICE instances. These are intermediate model
counts, not final placed Slice usage. TD prints the LUTL field utilization
rounded to 1.00 and does not give an exact integer field excess. The successful
baseline also had PHY-7027 warnings in later phases, so that warning alone does
not establish failure; V2's PHY-9002, `.opt_place.error.f`, and lack of a placement
completion marker establish the failed attempt.

The successful baseline's actual final usage is 19715/21216 Slices (92.925%),
with 1012 free Plb slots and 489 free Pmb slots. The strict <95% limit permits
at most 20155 Slices, leaving an acceptance budget of 440 additional Slices.
Source and constraint scope, DSP37 and every original release threshold remain
unchanged. V3 will test an algebraically equivalent spatial implementation;
its results cannot be inferred from these baseline numbers.

Three V2 product RTL files were copied to `attempt2_rtl`; `manifest.json` matches
each one to the exact V2 source snapshot. Before the new spatial implementation,
all 107 files in the old simulation directory were moved intact to
`02_sim/display_noise_attempt2_rtl_v2`. The raw compile log's first vlib command
reported an existing-library warning. A later clean summary does not erase it;
the archived evidence is therefore unsuitable for the current clean-log gate.
The new canonical test directory started with only four test source scripts,
without old libraries, vectors, manifests, logs or success reports.

No old log or implementation result was edited to manufacture a passing result.
The Python preparation tool initially rejected a Windows newline conversion in
the new AL before any FPGA tool ran. Its rejected bytes are preserved as
`attempt2_evidence/rejected_initial_v3_al_newline_conversion.bin`. Preparation
then used a raw-byte path substitution: reversing V3 to V2 in the new AL matches
the original exactly, and the three Tcl scripts and glyph include are unchanged.

Hardware validation remains `NOT_RUN`.

The first V3 source-freeze preflight also stopped before writing a snapshot:
the strict UTF8 reader encountered a CP936 comment in `isp/csi_unpacket_2lane.v`
at byte 1005 (`BD E2` begins the Chinese word for decoding). An independent scan
found 32 unchanged baseline HDL files with strictly decodable CP936 comments;
after comment removal, every one contains only ASCII dependency syntax. The
tool now gives only its HDL dependency scanner a strict, byte-round-tripping,
comments-only CP936 reader. Invalid multibyte sequences, damaged Unicode BOMs
and legacy text outside comments reject. Logs, JSON, XML, Tcl and memory reads
retain their strict Unicode contract. The source bytes and SHA256 values did
not change. Nine encoding tests and the read-only 193-dependency collection
passed; `v3_dependency_readiness.json` is preflight evidence, not a build freeze
or an implementation acceptance.

V3's gate report reduced the spatial module from 277 to 253 logic LUTs and from
159 to 108 ripple instances; seq190, ERAM3 and DSP0 stayed the same. The total
design's preliminary Slice* fell from 21147 to 21099, with ERAM93 and DSP37.
This reduction did not make the design placeable: V3 retained an actual
`.opt_place.error.f`, had no `.opt_place.end.f`, and emitted PHY-9002. No final
placed usage or routed timing is claimed for V3.

Before any next product update, all three V3 RTL files were backed up and matched
to its original source snapshot; the 29 run-file hashes and raw failure logs were
preserved. V4's AL was generated using original-byte run-path substitution only;
the three Tcl scripts and glyph include match V3 byte-for-byte. Active tools were
initially left on V3 pending root authorization. Following authorization, the
Python paths, build wrapper and functional-contract default were switched to V4;
no old run, Tcl implementation input or constraint was edited.

Root confirmed that the concurrent three-neighbor trial owns independent input
and output paths. Only after that confirmation, the full canonical V3 simulation
directory was moved intact to `02_sim/display_noise_attempt3_rtl_v3`. All 107
files match their original SHA256 values, as recorded in
`attempt3_spatial_archive.json`. The new canonical directory again contains only
the four test source scripts, with no inherited library, vectors, logs or PASS
summaries. These source copies still describe V3 until the algorithm owner
updates them; no V4 functional acceptance is inferred from V3's passing tests.

Root subsequently selected the separable 2x2 candidate for V4, expected product
RTL SHA256 `9FE7A1A5323340F854B312C1BBC33D72351D8065551878FA3A93A19469CF80EE`.
Its horizontal guarded average generates H; the synchronous row RAM stores H,
and the next stage forms a guarded vertical average. The final output is not
fed back into the row store. EDGE_TH16, full RGB8 values and the two-cycle
marker/data alignment remain requirements. This is a different algorithm from
the direct per-neighbor implementation of V2/V3 and requires fresh canonical
models, vectors, simulation, replay and source bindings. The three-neighbor
trial was separately evaluated and is not the selected V4 product algorithm.

Historical replay on 100 frames reports residual RMS 3.31496 for the old
horizontal filter and 2.96099 for the selected candidate, a 10.68% reduction.
This compares spatial filters on the same archived input; its source bit is
unconfirmed, and it is neither a new camera measurement nor a hardware test.
V4 preparation does not certify placement, final resource usage or routed
timing. No acceptance limit or constraint has changed.

## 2026-11-03: V4/V5 placement failures and independent V6 preparation

The original sections above are preserved as historical statements at their
recorded stages. V4 subsequently failed actual placement with PHY-7027 SLICEL
field capacity diagnostics and PHY-9002, with `.opt_place.error.f` and no
placement completion. It did not run route or bitgen. Its preliminary Slice*
20888 is not final physical usage. Raw evidence, frozen RTL and the archived
canonical tests are retained in `attempt4_failure_and_v5_preparation.json`,
`attempt4_evidence/`, `attempt4_rtl/` and
`02_sim/display_noise_attempt4_rtl_v4/`.

V5 used the independently verified combined compression: remove masked RAM
forwarding when width>1, retain width-one forwarding, compute the exact rounded
average by split halves, and select the averaged result at the output. It also
used the documented single synthesis-header line
`set synWildParams {gate pack_effort high}`. Fresh canonical 11-case simulation
and a newly source-bound 100-frame replay passed, but actual V5 placement still
failed with PHY-7027 and PHY-9002 and a real `.opt_place.error.f`. There was no
completed placement, route or bitgen. Preliminary Slice* was 20924, ERAM93,
DSP37; the placer did not print a precise integer SLICEL excess. Evidence is in
`attempt5_failure_and_v6_preparation.json`, `attempt5_evidence/`,
`attempt5_rtl/`, and `02_sim/display_noise_attempt5_rtl_v5/`. High packing and a
passing functional simulation are not physical acceptance.

The V6 candidate changes only the fixed EDGE_TH16 RGB-neighbour predicate to an
exact Boolean implementation. Equal high nibbles pass; nonwrapping adjacent
high nibbles pass only with the required low-nibble ordering. The generic
non16 arithmetic branch is retained. Thresholds, averaging, RAM contents,
width-one forwarding, state and the two-cycle output pipeline are unchanged.

The independent no-carry trial passed all 11 cases, comparing RGB and five
markers every cycle including invalid RGB. Each case also exhausts 65536 avg2
pairs, 65536 TH16 byte pairs and 196608 RGB-channel placements. The stream
tests cover 1859523 cycles and 1857539 valid pixels. Its restored frozen RTL
matches V5 SHA256
`B680381A4307D79BC6B259A8B33C177E5F2CD59120FF38EE902BC691438C20A0`;
candidate SHA256 is
`CD72245FA5CF73F16F35C2F655E5F13DD5F4949D14D258A7B99F9179AA219696`.
Raw sources, vectors, logs and hashes are in
`02_sim/display_noise_nocarry_trial/verification.json` and
`NOCARRY_VERIFICATION.md`. This forms a second, separately bound proof leg
after the original V4-to-V5 combined-equivalence evidence.

An actual isolated single-module gate comparison used the same dynamic wrapper,
PH1P35MDG324 speed3 device, default-auto mapping and high packing for both
sources. `02_sim/spatial_module_gate_20261103_schema/comparison.json` records:

| DUT gate metric | Frozen V5 | Boolean candidate | Delta |
|---|---:|---:|---:|
| Logic LUT | 100 | 115 | +15 |
| Ripple | 102 | 48 | -54 |
| Sequential | 119 | 119 | 0 |
| ERAM | 3 | 3 | 0 |
| DSP | 0 | 0 | 0 |

The result is preliminary module synthesis evidence, not a full-design resource,
timing or placement gate. It does not show a zero-carry module and does not
prove that 54 final physical Slices become available. Both source copies,
wrappers, AL/Tcl inputs, manifests, raw logs and gate/after-legalize area reports
are retained in the comparison directory.

Root selected the exact Boolean candidate for independent
`td_project_display_noise_v6`. Product tone and top-level RTL were unchanged.
RUN references were switched to V6; its prebuild source snapshot was frozen and
full-project synthesis was running when this addendum was written. Fresh V6
canonical 11/11 simulation and re-bound replay were separately completed by
their owner. The functional contract identifies V6 and still permits exactly
the original three display-source changes.

No V6 physical success, routed timing, final resource usage or new bit is
claimed here. Collector, pre-bitgen review and finalizer must use the same
strict two-leg equivalence validator, then require all actual implementation
and standard bitgen gates. Existing raw diagnostics, resource/timing limits and
constraints remain unchanged. Hardware validation remains `NOT_RUN`.

## 2026-11-03: V6 actual placement failure and strategy-only V7

The preceding V6-running statement is retained at its original recorded stage.
V6 subsequently failed actual placement with PHY-7027 and PHY-9002, with no
completed placement, route or bitgen. Its preliminary gate counts were 27510
LUT, 21281 REG, 20872 Slice*, ERAM93 and DSP37. The final printed intermediate
placer model was 21435 LUT, 20908 sequential, 568 MSLICE and 4121 LSLICE.
Neither gate estimates nor intermediate placer models certify final physical
usage or timing. The exact integer SLICEL excess was not printed. Original
failure logs, the frozen source snapshot and matched three-RTL backups are
preserved in `attempt6_failure_and_v7_preparation.json`, `attempt6_evidence/`
and `attempt6_rtl/`; no old DB or marker is current acceptance evidence.

Root selected a new independent `td_project_display_noise_v7` that changes
only the documented synthesis strategy line:

```tcl
set synWildParams {gate pack_effort high gate map_mode area_prior}
```

Product spatial RTL remains
`CD72245FA5CF73F16F35C2F655E5F13DD5F4949D14D258A7B99F9179AA219696`;
tone, top-level RTL, integer model and algorithm remain identical to V6. The
TD User Guide V6.2 Optimize Gate table (PDF231/printed230) supports both
ALL-family parameters; the official PH1 AreaOptimizeHigh strategy uses the
exact value `area_prior`, not `area`. Other synthesis bytes, place/route
scripts, constraints and acceptance limits are unchanged. The common strategy
checker must verify the unique logged settings, committed parameter table and
successful optimize_gate; set_param RUN-1003 finish records are not emitted
by this tool and are not invented.

V7 was frozen and synthesis started when this addendum was written. The V6
canonical archive was restored after all 107 files matched SHA256; source,
verification, replay and model hashes are recorded in
`reports/attempt7_spatial_reuse.json`. V7 did not rerun these identical-source
simulations or replay. Their genuine zero-error/zero-warning logs and the
strict V4-to-V5-to-V6 equivalence chain remain required and source-bound.
The functional contract is regenerated against V7. No V7 physical success,
final resource usage, routed timing or new bit is claimed by this addendum.

The separately authorized style arithmetic small-module comparison has also
completed without changing production RTL. The valid 143-IO wrapper trial in
`02_sim/style_operator_math_trial/module_gate_20261103_serialio/` retained all
19 runtime styles, CART and Sobel. DUT gate logic LUT increased from1253 to1366
(+113), while ripple409, seq1095, ERAM2 and DSP0 were unchanged. This is not a
resource saving and not full-design physical acceptance; the math candidate
will not enter V7. The earlier direct-wrapper trial exceeded the device's IO
limit (207 versus160, SYN-8228) and is preserved separately as a failed attempt.
Details, raw hashes and later enhancement scope are in
`reports/STYLE_NEXT_VARIANT_PLAN.md`.

## V7 failure and V8 official area strategy

V7 synthesized but placement again failed with PHY-7027/PHY-9002. Its gate
estimate was20842 Slice*, ERAM93 and DSP37. The last printed intermediate
model was21254 LUT,20908 seq,568 MSLICE and4121 LSLICE. LUT was below the
successful baseline21330, demonstrating that total LUT alone does not prove
SLICEL feasibility. No route or bitgen occurred. All29 run-file hashes,
three snapshot-matched RTL files and107 spatial files are preserved in
attempt7_failure_and_v8_preparation.json, attempt7_evidence/, attempt7_rtl/
and display_noise_attempt7_rtl_v7/. The old V7 strategy tools and actual
require-log/snapshot PASS are independently retained in attempt7_strategy_tools/.

V8 adds no product or constraint change. Its sole authorized synth-header line
selects the exact five official PH1 AreaOptimizeHigh tuples plus separately
authorized gate pack_effort high. The pinned official JSON SHA256 is
6AAF4F51B9494C5F56AEBDB29C277FB350D05A1D122797B8553F9E24CD97792A.
The corresponding RTL/gate commits and optimization completions must pass
real-log verification. Public readback may hide advanced parameters; absent
evidence is not fabricated or treated as verified internal-effective values.
V8 was frozen and synthesis started by root; this history claims no V8 physical
success or new bit. The107 same-source simulation files are restored with all
hashes preserved, documented as reuse in attempt8_spatial_reuse.json, not a new
simulation or replay execution.

## V8 gate completion and genuine parameter readback

V8 completed both optimization stages and wrote its real gate completion
marker. The original wrapper then stopped at the strategy checker: four
advanced parameter rows were absent from the ordinary TD commit tables.
The failed checker report, old checker/tests, original wrapper log, first
readback path failure and its receipt are preserved without alteration in
`attempt8_hidden_table_failure/manifest.json` and the referenced copies.

ROOT's second independent read-only query successfully imported the exact V8
gate DB and returned all six requested parameters. The current DB hash equals
both receipt hashes:
`AD1F531DC01F7D2404DF4C7233CA980937683F8CCA4D1D1307500F78A35B24DB`.
The Tcl, raw successful log and receipt remain in
`parameter_readback_trial/read_v8_parameters.tcl`,
`parameter_readback_trial/console_readback_v2.log` and
`parameter_readback_trial/actual_readback_run_v2.json`.

The enhanced checker verifies their raw contents and path/hash bindings,
including the receipt itself in its resulting review. It uses actual query
values only for absent advanced rows; it does not waive the two public
commit rows, six unique setting commands, setting-before-commit ordering,
no-reset/no-override rule, optimization completions or frozen Tcl binding.
The actual require-log/snapshot rerun passed after this evidence enhancement.
Original failures remain failures. No product/build input or constraint was
changed, and this addendum claims no V8 place/route/bitgen or physical pass.
