# CNN named-report routed physical review

Status: `REVIEW_REQUIRED`. Hardware: `NOT_RUN`.

Frozen manifest: `E679919D216AC47B3CA755CDC900E6547E14A6681AED9520E60C85926922A857`.

| Gate | Value |
|---|---|
| SWNS | +0.005 ns |
| STNS | +0.000 ns |
| HWNS | +0.020 ns |
| HTNS | +0.000 ns |
| slice | 19455/21216 (91.70%) |
| eram | 91/108 (84.26%) |
| dsp | 18/40 (45.00%) |

Inherited async soft-FIFO groups use exact datapath-only first-stage Gray bounds; second synchronizer stages remain timed. Effective route-end Gray path count must stay 52.

DDR, frame store, configuration ROM and constraints match accepted baseline. Routed timing is checked here; electrical DDR hardware validation remains NOT_RUN.

Ordinary CNN, PCB RTL/vision logic and all model inputs match the exact new-capture-mix baseline by SHA256. This report-format change permits no model, inference, HXA, DDR or constraint changes. PCB accuracy and physical writing remain subject to real-image and hardware validation.

Inherited SLATR-1036/1038, dummy-node, bounded async FIFO and legacy I/O delay groups are recorded; this does not claim a warning-free design.

Read-only reimport, ordinary CNN golden and ROM binding are separate final gates.

Findings: HXA/DDR/Ethernet source differs from accepted baseline
