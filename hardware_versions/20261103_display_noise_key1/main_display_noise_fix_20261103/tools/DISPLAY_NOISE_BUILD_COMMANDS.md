# Independent display-noise build

Baseline: signed `main_pcb_auto_compat_20261101` bit SHA256
`B048D5BD30915F7C08791A9947D90982B741929E00CC0BE3036F7018C76209BC`.
All 189 entries of its successful prebuild snapshot were checked before copying.
`reports/baseline_source_snapshot_original.json` and
`reports/baseline_dependency_validation.json` are provenance, never new build
acceptance. Only active dependencies and reusable static physical-device data
were copied. No historical run DB, step marker, simulation PASS or release result
was imported as new evidence.

Active run: `01_rtl/imgq_gain_m/main/td_project_display_noise_v5`.
V1 through V4 implementation evidence is retained separately; none produced a bit.
Only three existing RTL files may differ from the frozen baseline:
`design_top_wrapper.v`, `isp/display_tone_96.v`, `a4_display_spatial_h1.v`.
The AE policy is unchanged. CNN fixed tone must match every value and accepted
transaction; preserving that behavior is an explicit regression requirement.

From this independent project root:

```powershell
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage scope
# Freeze only after all intended RTL/test changes are complete.
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage freeze
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage synth
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage place
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage route
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage gate
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage readonly
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage context
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage review
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage bitgen
powershell -NoProfile -File tools/run_display_noise_build.ps1 -Stage post
```

Each stage is explicit; no step automatically starts bitgen. Commands refuse to
overwrite a frozen prebuild snapshot or prior implementation/audit logs. If an
implementation input must change after freeze, preserve the run and create a new
independent run, then update `display_noise_paths.RUN` and the PowerShell run path.
`freeze` captures all active RTL/include/IP/MEM/constraints and the three actual
implementation Tcl scripts. Subsequent steps verify their frozen hashes.

Placement and final route use strict resource counts: Slice <95%, ERAM <90%,
DSP <95%, exactly 37 DSP (no new DSP). Final routed setup/hold WNS must be >=0,
TNS=0, both slow/fast corners checked. A preliminary Slice* estimate does not
replace actual placed count. Existing available BRAM headroom is seven ERAM.

`readonly` exports full compatible unique placed Slice inventory plus pads,
clocks, timing, skew, DRC, raw check_design/check_io/check_plb. `context` repeats
IO checks in the standard bitgen project/run context. Historical RUN-8007 and
USR-8450 remain visible; catch=0 does not imply a clean checker. Existing
physical-site, 79-IO, ADC and DPHY0 source binding proof remains mandatory.
No constraints are altered and bitgen has no unconstr_io or other parameter
override. Supplementary check warning counts may not increase.

Before review, the functional owner produces real
`reports/display_noise_regression.json` with `passed`, named Boolean `checks`,
absolute-path `input_hashes`, and `logs`. Required check names and log paths are
declared in `tools/review_display_noise_release.py`; it rejects missing checks,
stale/missing current RTL, unbound logs or missing success markers. Ordinary CNN,
PCB 30-second timing, document and KEY4 regressions must be rerun in this copy;
copied old logs cannot certify the new top. New tone/spatial checks additionally
cover exhaustive fixed-tap values, stalls, edges/motion, line/frame boundaries,
full RGB8 range, two-cycle video alignment and unchanged CNN/AE contracts.

`review` binds source/scope/gate/regression manifests and freshly rechecks every
gate DB/report/log hash; physical/IO/PLB/DRC/FIFO/DDR reports remain independent.
Both the bitgen wrapper and direct bitgen-Tcl preparation rerun the complete
review. Target:
`artifacts/dual_fpga_main_20261103_display_noise_fix_diagnostic.bit`.
Post-review records actual artifact SHA256 and leaves hardware status `NOT_RUN`.

The initial v1 run is retained unchanged. Nine AutoExcluded AL entries were
absent when only active 189 frozen dependencies were copied, causing new
PRJ-7001 warnings. V2 includes those baseline files plus their eight ordinary IP
support files (17 total), preserving AutoExcluded=true.
`tools/inactive_project_files.json` records their baseline hashes and is frozen
as an extra dependency. Its 17 files are hash-checked separately, without
parsing inactive HDL/IP as active logic. Formal review rejects PRJ-7001.

V2 synthesis completed, but placement failed with PHY-7027 SLICEL field capacity
warnings followed by PHY-9002 and `.opt_place.error.f`. V2 has no completed
placement or routed database. Its original three product RTL files are archived
in `reports/attempt2_rtl/`, each matched to the V2 frozen snapshot. Original
implementation evidence and hashes are recorded in
`reports/attempt2_failure_and_v3_preparation.json`; the original V2 run is intact.
The baseline has 19715 placed Slices and a strict <95% maximum of 20155,
leaving 440 additional Slices. V2's 21147 Slice* is preliminary, not a measured
final placed count. The exact internal SLICEL field excess is not printed by TD.

The entire old spatial simulation directory is archived as
`02_sim/display_noise_attempt2_rtl_v2`, preserving all 107 files and its initial
existing-vlib warning. `reports/attempt2_spatial_archive.json` records every
original hash. The canonical `02_sim/display_noise` was recreated from source
scripts only; a new RTL hash, clean library and complete simulation are required.
An overall PASS copied from the archived summary cannot satisfy the stricter
complete-log checks. No gate or constraint is relaxed.

V3 compressed the exact original spatial arithmetic, but placement still failed
with PHY-7027 and PHY-9002. Its three RTL files, 29 run-file hashes and complete
107-file spatial simulation directory were preserved as attempt3 evidence.
V4 selects a separable 2x2 spatial filter: horizontal guarded averaging produces
an intermediate H pixel; synchronous row RAM stores H, and a guarded vertical
average combines the current H with the previous row's H. Row RAM does not store
the final filter output. This is a new spatial algorithm requiring its own
integer oracle, vectors and full RTL regression. It is not the earlier direct
four-neighbor filter or the independently evaluated three-neighbor trial.
The selected RTL SHA256 is
`9FE7A1A5323340F854B312C1BBC33D72351D8065551878FA3A93A19469CF80EE`;
actual product promotion and all fresh input hashes must be checked before
freezing. EDGE_TH=16, full RGB8 values and two-cycle video alignment are retained.
Historical replay over 100 frames reported residual RMS 3.31496 for the old
horizontal filter and 2.96099 for this candidate (10.68% lower). Those captures
have unknown source-bit identity; this is comparative historical evidence, not
a current camera measurement or a board-quality acceptance claim.
V4 must bind its own prebuild snapshot, fresh functional evidence and all final
physical checks before bitgen. No constraint, timing or resource threshold is
relaxed.

V4 synthesis completed but placement again failed at GP Phase 1 with PHY-7027
and PHY-9002. All 29 original run files are hash-recorded and the three product
RTL files are backed up against the original snapshot in `reports/attempt4_rtl`.
Its 107-file spatial simulation is preserved in
`02_sim/display_noise_attempt4_rtl_v4`; fresh canonical tests started with only
the four source scripts. Failure evidence is never edited into successful
evidence.

V5 retains the same separable guarded 2x2 pixel oracle while reducing equivalent
arithmetic and eliminating unnecessary width>1 RAM forwarding. Its synthesis
header contains the single authorized line:

```tcl
set synWildParams {gate pack_effort high}
```

The unchanged vendor prepare flow applies `set_param gate pack_effort high`
after `load_run_param`/`import_db` and before gate commit/`optimize_gate`.
`E:/td/doc/TD_User_Guide_V6.2.pdf`, PDF page231 / printed230, Optimize Gate
parameter table, documents ALL-family support, default medium and the possible
area/congestion tradeoff. `E:/td/doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf`
section4.1.18, PDF28-29 / printed21-22, documents positional `set_param` syntax.
`E:/td/scripts/DefaultFlow.tcl` lines65,72-77,142,145 establish the order above.
No PH2-only `more_lut_pair` or undocumented parameter is used.

`verify_display_noise_build_strategy.py` pins all three successful-baseline Tcl
hashes. Removing exactly that one header line must restore the synthesis script
byte-for-byte; place and route scripts must remain byte-for-byte identical.
Scope, frozen-input and final release checks repeat this verification. The
actual synthesis log must show one high-setting command before gate commit,
the unique committed `pack_effort | high | medium | *` table row, no subsequent
override or parameter reload, and completed `optimize_gate` plus its end marker.
TD does not emit a set_param finish record; none is required or fabricated.
A source declaration alone cannot certify application. Snapshot
extras already bind the actual three Tcl scripts. All constraints, capacities,
resource/timing thresholds, pixel precision and algorithms remain subject to
their existing independent gates.

V6 retained exact pixel behavior and reduced carry logic but still failed
placement (PHY-7027/PHY-9002). V7 uses the same product RTL and one newly
authorized public mapping strategy in its otherwise identical synth header:

```tcl
set synWildParams {gate pack_effort high gate map_mode area_prior}
```

TD_User_Guide_V6.2 PDF231/printed230 documents `map_mode` for ALL families,
with values `auto`, `area_prior`, `logic_level_prior`, `balance_explore`.
PDF246/printed245 supports PH1P AreaOptimizeHigh, and
`E:/td/doc/strategies/official_strategy_ph1.json` lines34-35 explicitly select
`map_mode area_prior`. The exact value is `area_prior`, not `area`.
The validator requires both unique commands before gate commit, their changed
high/medium/* and area_prior/auto/* property rows, no later override/reload,
and exactly one completed optimize_gate. All prior V6 strategy tools and its
successful actual-log validation are independently preserved under
`reports/attempt6_strategy_tools`; failed placement evidence is unchanged.
V7 has no constraint, capacity, algorithm, precision or acceptance-limit changes.

V7 also failed initialization with PHY-7027/PHY-9002, despite its final
intermediate LUT count21254 being below the baseline21330. Total LUT alone is
not a valid predictor of local SLICEL capacity or a replacement for placement.
V8 retains the same RTL and uses the exact official PH1 AreaOptimizeHigh five
tuples, followed by the separately authorized pack_effort high tuple:

```tcl
set synWildParams {gate add_map_lut_struct high gate map_mode area_prior gate multi_thread_mapping partition rtl resource_sharing auto rtl shifter_style shifter_reg gate pack_effort high}
```

The vendor JSON SHA256 is
`6AAF4F51B9494C5F56AEBDB29C277FB350D05A1D122797B8553F9E24CD97792A`.
TD_User_Guide_V6.2 PDF246/printed245 section9.7 supports PH1P and warns that
this strategy can increase logic depth. The shared validator pins the JSON,
the five exact tuples and the one extra tuple; it requires six unique calls,
their corresponding RTL/gate commit tables and both optimization completions.
Advanced parameters absent from public readback are not silently certified.
Any missing committed evidence fails actual-log validation until genuinely
supported readback is available. No internal-effective value is inferred
solely from set_param acceptance. V7 failure evidence and its accepted old
strategy validation are independently preserved. V8 reuses exactly107 hashed
canonical files with unchanged RTL/model, not a new simulator/replay run;
see reports/attempt8_spatial_reuse.json. No constraints or thresholds changed.

## V8 actual hidden-parameter readback

V8 synthesis genuinely completed, including `.opt_gate.end.f`. The first
strategy check then failed because TD's normal commit tables omit four advanced
rows. That failure is retained in `reports/attempt8_hidden_table_failure/`,
along with the old checker/tests, original wrapper log and first failed DB
readback invocation. No historical PASS was substituted for those results.

ROOT subsequently ran the reviewed read-only
`reports/parameter_readback_trial/read_v8_parameters.tcl` against the actual V8
gate DB. The successful raw output is `console_readback_v2.log`, bound by
`actual_readback_run_v2.json`. `get_param` returned all six exact values. The
DB SHA256 before/after/current is
`AD1F531DC01F7D2404DF4C7233CA980937683F8CCA4D1D1307500F78A35B24DB`;
the reviewed Tcl is pinned to
`8D0F47DE9AEBC97801CD6F4FE77DAE006896321D0CD86AE219F137AB6792F7A2`.

The checker now permits this independently verified query to supply only the
four absent advanced rows. `map_mode` and `pack_effort` still require their
actual commit-table values/defaults/notes. It recomputes DB/Tcl/log hashes,
records the receipt's own SHA256, checks paths and DB size, exact successful
device/DB import, six unique query/actual-value pairs and final markers in
order. Missing/wrong/duplicate values, drift, fake success flags, unsuccessful
import, later mutations/reloads, missing public rows or incomplete synthesis
stages all fail. The one observed import-internal `set_param gate opt_area
high` is accepted only inside the DB import; it is not an exemption for later
parameter changes. No `get_param` finish records are invented.

Rerun `python tools/verify_display_noise_build_strategy.py --require-log
--require-snapshot` to regenerate the current review from raw evidence.
This confirms logged application and the imported completed DB's settings;
it is not a claim about internal optimizer implementation or physical
capacity/timing acceptance. No product, RUN, build Tcl or constraints changed.
