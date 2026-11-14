# Secondary r4 final signoff and diagnostic delivery

Current status: synthesis, placement, routing, current read-only physical signoff and standard bitgen completed. `FINAL_RELEASE.json` and `artifacts/RELEASE_REPORT.json` record the delivered diagnostic bit. Hardware acceptance remains `NOT_RUN`. Main-board delivery is unchanged.

The delivered bit is `artifacts/dual_fpga_secondary_20261113_pcb_paper_load_stroke_cont_diagnostic.bit`, 1,789,542 bytes, SHA256 `5BA649F37D687B66809A6876B2AB9E77657D1C467BAD421E258B04143D5B8EE5`. Final timing is SWNS +0.007 ns, HWNS +0.020 ns, STNS/HTNS 0. Resources are 19,310/21,216 Slice, 86/108 ERAM and 16/40 DSP. The setup margin is only 7 ps.

The final route completed all eight named DRC checkers at Stage 7.2 through 7.9. Current complete placement evidence proves 19,310 expected Slice cells at 19,310 unique compatible physical slots. The unchanged RGMII ODDR `SYN-6024` and two exact logical SLICEL `PHY-7027` critical warnings remain explicitly recorded. `BITGEN_RECEIPT.json` and `POST_BITGEN_INTEGRITY.json` bind the successful output to the unchanged 299-file freeze and routed inputs; bit/BID delivery copies match the generated files.

`tools/signoff_airwalk.py` reads the secondary configuration from `tools/build_airwalk.py`, delegates freeze validation to that wrapper's current `build_opt.validate`, and accepts `--run` without embedding a previous manifest/source hash. It verifies every frozen file plus the current candidate's production bytes before each action. All live tool outputs are bound to the selected freeze and routed DB.

## Evidence already bound

`FUNCTIONAL_GATE.json` has status `PASS_CURRENT_FUNCTIONAL_GATE` with `bitgen_allowed=false`; that gate alone does not authorize bitgen. The completed physical/prebitgen gates and final bitgen receipt provide the separate implementation acceptance. It binds exactly these final reports:

| Group | Current report | Actual tested production inputs | Checked completion logs | Recursive receipts |
| --- | --- | ---: | ---: | ---: |
| preserved | `reports/preserved_airwalk_r4/20261113T112441_370259Z/RESULTS.json` | 43 | 33 | 17 |
| document_integrated | `reports/doc_mapper_r4/20261113T111600_164164Z/RESULT.json` | 9 | 2 | 1 |
| doc_total_ack | `reports/doc_total_ack/20261113T111432_242492Z/RESULTS.json` | 4 | 1 | 1 |

The preserved receipt SHA256 is `96746075C6F3B1844AA81B6B260874106D2142641B39EC45E49F0E89EF99D6D9`. It includes 11 fresh job groups and four already fresh action/paper/document/control receipts. Previous FAIL directories remain preserved and are rejected as gate inputs. The document comparison verifies 954 request/completion pairs at 30 versus 28 cycles and byte-identical 351 points / 417 G-code lines. The ACK test covers normal, dot and empty jobs.

The tool recursively reads actual child receipt source hash maps, verifies current/frozen bytes and raw log hashes/markers, and re-derives each gate row at acceptance time. Inventory-only `production_inputs` / `bound_current_production_sources` entries are checked but cannot supply tested-source coverage. Adding an otherwise current hash to an external gate row is rejected.

`STATIC_AUDIT.json` checks 82 protected CDC/FIFO/DDR/ethernet inputs and the active dependency closure. The only timing-file change is KEY1's first synchronizer target. It separately validates `reports/r4_integration/BASELINE_IDENTITY.json`: the immediate physical/source control is the 20261113 eject bit (`9B75DDF7…41ADFC`), r3_seed2 freeze (`2DE7F709…F58D`), and 273 unchanged production files in the D: control. The 20261111 release is identified only as the older validator inventory trust root. The retained captured-document comparison uses its original 20261111 functional reference; this does not change the immediate physical/source control.

`TOOL_SELF_CHECK.json` records preparation-only checks: no subprocess during prepare, final named DRC parsing and missing/adverse checker rejection, exact 95/90/95 resource boundary rejection, all four negative timing metrics rejected, actual functional receipt binding, invented source coverage rejected, prior FAIL receipt rejected, and pre-route prebitgen blocked without TD. Historical logs are parser fixtures only.

The place log contains two `PHY-7027 CRITICAL-WARNING: Base field: model type (SLICEL) execeed the design limits.` diagnostics in GP Phase 3/4. The same text occurs in r3_seed2, but historical occurrence does not accept the current placement. The new warning policy preserves every warning's phase, log, line and original text. Current read-only enumeration now proves every expected L/M Slice has one unique legal compatible physical slot, with no missing/unplaced/duplicate/incompatible entries and matching area counts. These two warnings are retained with that complete current site proof in the final acceptance. The intermediate `legal = 38420 / 38420` summary and exit code are insufficient. Unknown PHY-7027 variants, PHY-9002 and other unreviewed critical warnings block acceptance. The unchanged RGMII ODDR `SYN-6024` critical warning is separately retained with exact control-message and source-byte checks. Final physical/implementation/bitgen receipts explicitly retain critical-warning details; no warning-free claim is made. Preparation checks also reject unknown PHY-7027, PHY-9002, and duplicate/unplaced/missing Slice entries. The final run has 20 checks; the earlier pre-route run had 21 because it additionally exercised rejection of prebitgen while route evidence was absent.

## Commands from the candidate root

Preparation is safe before route:

```powershell
python -B tools/signoff_airwalk.py prepare --run E:/codex_paper_airwalk_secondary_20261113_r4
python -B tools/check_airwalk_signoff_preparation.py --run E:/codex_paper_airwalk_secondary_20261113_r4
python -B tools/signoff_airwalk.py functional --run E:/codex_paper_airwalk_secondary_20261113_r4 --evidence preserved=reports/preserved_airwalk_r4/20261113T112441_370259Z/RESULTS.json --evidence document_integrated=reports/doc_mapper_r4/20261113T111600_164164Z/RESULT.json --evidence doc_total_ack=reports/doc_total_ack/20261113T111432_242492Z/RESULTS.json
```

The coordinating agent executed the following after the current route completed:

```powershell
python -B tools/signoff_airwalk.py route-gate --run E:/codex_paper_airwalk_secondary_20261113_r4
python -B tools/signoff_airwalk.py readonly --run E:/codex_paper_airwalk_secondary_20261113_r4
python -B tools/signoff_airwalk.py prebitgen --run E:/codex_paper_airwalk_secondary_20261113_r4 --gate reports/airwalk_signoff/codex_paper_airwalk_secondary_20261113_r4/FUNCTIONAL_GATE.json
```

The read-only action imports the current DB using the successful r3_seed2 query context. It verifies mapped reset/CDC groups and effective max-delay coverage, DDR clock, both timing corners, raw IO/PLB commands, DRC details, and complete physical Slice/site compatibility against the device topology. It preserves the exact known logical LSLICE counting discrepancy only when complete unique compatible physical placement proves capacity. Source/AL/gate DB/routed DB/manifest/plan hashes must remain unchanged. The final route DRC group is selected by the eight checker names and their completed stages. This secondary r4 run completed Stage 7.2 through 7.9; the parser also supports the historical main-board Stage 8 group without accepting an earlier partial group.

The explicit `bitgen` action requires the same complete prebitgen gate. It generates only into `run/signoff/bitgen`, checks standard parameters, fresh reimport timing/resources, frozen inputs and DB/AL hashes, then copies verified bit/BID bytes to artifacts. Its target is `dual_fpga_secondary_20261113_pcb_paper_load_stroke_cont_diagnostic.bit`. This action completed with `BITGEN_PASS`, `unconstr_io off`, matching fresh timing/resources, unchanged inputs and verified bit/BID copies. The log also retains two existing `PRJ-5611` compile-order warnings; no warning-free claim is made.

Physical DDR calibration, CDC MTBF, board behavior and mechanics remain `NOT_RUN`.
