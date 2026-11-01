# Factored low-confidence build adapter

This directory contains read-only builder checks and the exact source diff from the frozen r2 adapter. It does not authorize a bit or a recovered placement failure.

Production root: `secondary_doc_dirt_lowconf_factored_20261101`.

Run identity: `dirt_lowconf_factored_Runs_20261101`.

Output stem: `dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic`.

The successful compact area/SCLK release remains the control baseline. The failed r2 run is provenance only. Its GP Phase 1 `PHY-7027` / `PHY-9002` failure is never eligible for a recovered-warning exception.

Before preparing the new run, finish the fresh document/low-confidence/area-wrapper preparation and the compact-metric boundary run, then execute:

```powershell
python -B reports/factored_build_adapter/selftest_builder.py
python -B tools/build_doc_dirt_lowconf_factored.py inspect
```

The selftest verifies the actual source scope, all 133 production inputs, qualified explicit dependencies and negative source-closure cases. Its synthetic source-closure object exists only in memory and is not a TD build snapshot. No TD command, prepare operation or source edit occurs in the selftest.

The parent task alone starts `prepare`, synthesis and route. The unmodified seven-suite, document, low-confidence, CDC/FIFO/DDR/reset, routed timing, DRC, read-only reimport and bitgen gates remain mandatory. Mapped negative WNS remains informative; the routed gate decides timing. All resource limits remain unchanged. Hardware validation remains `NOT_RUN`.
