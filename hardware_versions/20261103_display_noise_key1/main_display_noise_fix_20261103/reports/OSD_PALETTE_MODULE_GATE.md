# OSD palette: isolated measured module comparison

The ROOT agent subsequently ran both prepared module cases. This is a later
measurement; the preserved preparation context's `PREPARED_NOT_RUN` and
`NOT_MEASURED` fields describe the earlier preparation only. The independent
simulation receipt describes simulation, not a production build.

| Retained DUT resource | Baseline | Palette | Difference |
|---|---:|---:|---:|
| logic LUT | 254 | 245 | -9 |
| sequential cells | 62 | 34 | -28 |
| ripple | 0 | 0 | 0 |
| ERAM | 0 | 0 | 0 |
| DSP | 0 | 0 | 0 |

Both the gate and after-legalize DUT reports give these counts. The two cases
use identical 133-IO source wrappers, PH1P35MDG324 speed 3, default auto mapping
and pack_effort high. The 112 metadata wrapper FF are identical in both cases
and excluded from the DUT comparison. All normal panel inputs and eight PCB
statuses remain dynamic; all outputs remain external. The earlier ModelSim
comparison passed 2,984,788 cycles and 53 asynchronous reset checks, including
invalid-cycle outputs. Only source module declarations were renamed for the
common area DUT; each stage's distinct source hashes remain manifest-bound.

Actual evidence:

- `02_sim/osd_palette_equiv_trial/module_gate_20261103_dynamicio/comparison.json`
- Both `baseline/` and `palette/` copies of input_manifest.json, area_result.json,
  console.log, module_area_gate.area and module_area_after_legalize.area.
- Their module_source.v, module_area_top.v, module_area.al, run.tcl and identical
  osd_compact_glyphs.vh; the preparation script and shared helper.
- `02_sim/osd_palette_equiv_trial/verification.json`, compile.log and transcript.log.

The comparison SHA256 is
`850C6A53BF6E0475ECD4E4C78D30148A4385A7D561348F6F999818AAFBB3F30F`.
The raw console warnings are preserved, including SYN-5025 undriven-pin
defaults and SYN-6021 unconstrained IO in these unconstrained module tests.
No claim of warning-free gate synthesis is made.

This candidate is **not promoted into product RTL or V8**. The module result
does not establish a full-board Slice saving, placement capacity, routed
timing or image-quality improvement. The strategy is not V8's complete
AreaOptimizeHigh strategy. No product, RUN, constraint or V8 snapshot change
is represented by this experiment. Hardware validation remains `NOT_RUN`.
