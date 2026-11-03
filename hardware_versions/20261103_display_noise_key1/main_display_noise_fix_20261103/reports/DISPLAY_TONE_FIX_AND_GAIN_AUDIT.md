# Display tone continuity and read-only sensor gain audit

## Implemented display-only correction

The frozen baseline is `main_pcb_auto_compat_20261101`, successful bit SHA256
`B048D5BD30915F7C08791A9947D90982B741929E00CC0BE3036F7018C76209BC`.
The only production RTL changed by this subtask is
`01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v`.

The original curve jumps from input 95/output 118 to input 96/output 124.
Small sensor variations near this boundary can become a 6-DN display step.
The display now changes only four input values:

| Channel input | Frozen fixed-tap output | New display output |
|---:|---:|---:|
| 95 | 118 | 118 |
| 96 | 124 | 120 |
| 97 | 125 | 122 |
| 98 | 126 | 124 |
| 99 | 127 | 126 |
| 100 | 127 | 127 |

The display correction is a six-bit equality and constant/bit concatenation,
with an output selection. It adds no RTL multiply, divide or adder. The entire
curve is monotone; maximum adjacent step falls from 6 to 2 DN, maximum change
from the baseline is 4 DN, output range remains 0..243. Raw display bypass is
unchanged. This preserves all eight channel bits; it does not clear low bits.

The original `tone8` curve is computed once and remains the fixed recognition
tap. No module ports, pipeline stages, ready/valid handshakes, frame-mode
latching or isolated-SOF behavior were changed. Physical resource and timing
claims require the separate complete build; absence of new DSP operations in
this module is not a substitute for that report.

## Completed verification

- Integer reference exhausts all 256 channel inputs, checks the exact changed
  input set, monotonicity, adjacent step, range and maximum difference.
- ModelSim compiles the new module and a renamed copy read directly from the
  read-only frozen baseline, checking the fixed-tap data and all interface
  handshake/marker outputs against that baseline every cycle.
- Independently generated lookup vectors check all display and fixed data.
  Both modes cover every value in all 12 channel lanes, with randomized data,
  stalls, isolated SOF, midframe mode changes and reset.
- Result: PASS, 24,520 cycles, 14,772 accepted groups, 4,864 stalled cycles,
  152 isolated SOFs, 11,188 simultaneous consume/produce cycles, 6,939 mode
  changes ignored midframe. ModelSim: zero errors, zero warnings.

Evidence: `display_tone_reference.json`, `display_tone_rtl_regression.json`,
`display_tone_rtl_regression.log`. Reproduce with
`python tools/run_display_tone_regression.py` from this variant; the runner
checks the existing license file and sets both required process variables.
Run this regression serially with other ModelSim jobs on this host.

## Read-only AE/gain findings; no AE changes in this variant

The successful baseline top sets `LOW_NOISE_GAIN_FIRST=0`, AG range 16..143
(1x..15.75x sensor table), startup AG=80 (4x), startup digital gain=128/128
(1x), digital gain maximum=256/128 (2x), exposure maximum=1990.

The overbright control path normally lowers exposure first, then analog gain,
then digital gain. Therefore it can keep a previously raised sensor gain while
shortening exposure. This is a plausible contributor to colored sensor grain;
the actual current gain in the user's scene has not been measured. The audit
found no deterministic table wrap or digital gain 256-to-zero truncation in
the active legal range.

Read-only references in the frozen baseline:

- `.../hdl_source/design_top_wrapper.v`: lines 872..873, 896, 901..908.
- `.../hdl_source/uiisp_beta/ae_auto.v`: startup at 93/139 and decrease policy
  at 358..378.
- `.../hdl_source/uics500_cfg/SC500GainTbl.v`: monotone analog gain table.
- `.../hdl_source/uics500_cfg/uics500regAE.v`: grouped sensor register writer.

Changing gain policy would also change frames used by CNN/PCB/document
processing, so that requires a separate sensor/capture regression. This
variant leaves AE, gain, AWB and other sensor processing untouched.

## Limits

Tone continuity reduces amplification of small input variations near 96 DN;
it does not remove random sensor noise and is not TNR. Scene quality must
still be judged on real HDMI/capture samples, together with the separately
implemented spatial filter. Hardware verification remains NOT_RUN.
