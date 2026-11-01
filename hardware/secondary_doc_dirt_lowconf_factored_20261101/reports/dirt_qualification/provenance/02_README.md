# Fixed dirt ROI compensation — standalone candidate

This is an isolated document frontend experiment. The existing production
project, bit, models and `work/` remain unchanged. No synthesis or bitgen is
started here; hardware status is `NOT_RUN`.

The user confirmed a non-removable gray patch inside the camera. This
candidate applies local background compensation only to the fixed area
corresponding to that patch, rather than adapting the entire image or
turning the region white. The defaults apply only to the current 1280×720
SC500 readout and camera position; camera/readout changes require new
capture validation.

| Coordinate system | Compensated range, inclusive |
| --- | --- |
| Camera pixels | x=1152..1279, y=448..719 |
| 320×180 raster | x=288..319, y=112..179 |
| 320×320 canvas | x=288..319, y=182..249 |

Every active raster cell reads its exact, disjoint 4×4 source block. This
corrects the released endpoint/clamp sampling, which could count an edge
pixel several times. Outside the fixed ROI, the decision is unchanged:
at least two of the 16 source pixels must satisfy `Y <= 112`. No additional
background reads occur outside the ROI.

Inside the ROI only, another 16 serial reads sample the Cartesian product
of offsets `(-10,-2,6,14)` relative to the source cell origin, with probe
coordinates clamped to the camera. The decision is:

```text
background = (sum_of_16_probes + 8) >> 4
ink = second_min <= 112 && second_min + 12 <= background
```

Equal minima count as two distinct source pixels. The final cell pixel
(sample 15) updates both minima before a separate `ST_DECIDE` state reads
them. Similarly, the final background sample is accumulated before the
decision state. Real strokes through the ROI remain eligible; there is
no hard white mask, component deletion, erosion or opening.

The canvas, full-frame mapping, ready/valid interface, registered request
address, single outstanding request and output backpressure contract are
preserved. Full frames emit 102400 bits and make exactly
`921600 + 2176*16 = 956416` accepted camera reads, an increase of 3.78%
over exact 4×4 sampling. There are no RAM arrays, multipliers, division
operators or DSP primitives in this RTL. Synthesis utilization and timing
have not been measured.

`fixed_dirt_reference.py` implements the second-minimum rule. The runner
independently counts source pixels below `min(112, background-12)` inside
the ROI and verifies that both reference formulations agree. ModelSim
then checks every output bit, every source address, 16/32 requests per
cell, delayed input readiness, delayed responses and output backpressure.
Synthetic fixtures exercise thin/diagonal strokes and dots over the gray
patch, all ROI boundaries, dark pixels arriving as sample 15, edge pixels,
uniform dark interiors, gradients and particles. Lifecycle tests dirty
the ROI accumulators with black source data, cancel/reset during background
reads, then replay complete blank frames. A separate short-timeout test
leaves a pixel response pending and checks timeout/cancel release.

Run `python run_frontend.py`; an optional first argument chooses a fresh
simulation subdirectory. The runner supplies both file-license variables
for ModelSim, preserves logs and command hashes, and records `RESULTS.json`.
It verifies that the old experimental candidate, current production
document RTL and production bit retain their initial SHA256 values.

## Completed standalone verification

`RESULTS.json` records PASS for six full-frame fixtures, cancellation and
reset during dirty ROI background sampling followed by two complete blank
reentries, and the pending-response timeout test. All complete frames match
102400 bits and exactly 956416 accepted requests. Compile/lint and completed
simulations report zero errors and zero warnings. Real blank2418 contains
0 foreground points; ink2358 contains 1148. These counts do not establish
pixel accuracy. The test source/production/old-candidate hashes remained
unchanged. The RTL SHA256 is
`42F2140588B7DB5AB5E815DFDFA0BFD0CEE161944CC198DD1BEAA571B22D05F4`.

Limitations: no pixel-level handwriting truth or physical plotter test is
available. Broad dark interiors inside the ROI can be suppressed, and
sharp shading boundaries can remain. The ROI does not correct optical
blur or recover details obscured by dirt. Passing the binary comparison
does not establish handwriting accuracy or integrated resource/timing
acceptance. This directory is not a production release.
