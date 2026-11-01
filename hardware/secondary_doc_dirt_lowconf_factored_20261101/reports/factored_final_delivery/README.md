The finalizer verifies actual routed outputs and never runs TD. It is pinned to the current factored root, frozen builder, exact BUILD_PLAN hash, production deltas and quality report.

Current preparation is not a release. The real CLI exits 1 with NOT_READY because final routed/bit artifacts do not yet exist. Eighteen negative tests rejected missing outputs, source/plan drift, failed gates, incomplete readonly DB/AL hashes and invalid quality evidence. They did not create route evidence or a release index.

After all real construction stages complete, the parent task may run from this project root:

```powershell
python -B reports/factored_final_delivery/finalize_delivery.py --publish
```

Success writes RELEASE.json and FROZEN_INPUTS.csv only if both are absent. The script verifies native and published bit bytes, all seven regressions, document and low-confidence proofs, final timing/resources, CDC/FIFO/DDR/DRC review, fresh KEY3 proof and readonly DB/AL hashes. Forbidden placement diagnostics remain rejected. Final G-code ok means controller acceptance rather than confirmed mechanical Idle. Hardware validation remains NOT_RUN.
