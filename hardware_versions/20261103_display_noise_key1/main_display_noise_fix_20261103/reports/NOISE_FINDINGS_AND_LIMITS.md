# Noise investigation: confirmed observations and remaining limits

## Reported failure

The user confirmed that the grain and colored texture are visible directly
on the display and occur in original mode. The supplied photograph is:

`D:/wx/xwechat_files/wxid_nx0w2w38rykj12_9293/temp/RWTemp/2026-11/9e20f478899dc29eb19741386f9343c8/7a76ae847e54f07f6b6ac5a8300ae635.jpg`

A photograph of a display also contains the display/camera sampling pattern.
The user's direct-view confirmation establishes a real visible problem, but
the photograph alone does not identify the processing stage responsible for
the intermittent severe texture. No corresponding raw frame, gain registers,
or reproducible board capture has been collected for this particular event.

## Implemented candidate

The independent project uses the frozen `main_pcb_auto_compat_20261101`
baseline. It repairs a display-tone discontinuity and uses nonrecursive,
edge-guarded horizontal and vertical neighbor averaging on the HDMI branch.
The row memory stores the horizontal intermediate result. It is a spatial
filter, with no previous-frame storage and no TNR. It retains RGB8 channel
precision and resolution; it does not clear low bits. Averaging can soften
low-contrast fine texture, so full precision does not mean lossless detail.

Fixed CNN/PCB/document pixels retain the baseline contract. Motion detection
logic, parameters and connections are unchanged, but its display-tone tap
changes at inputs 96..99 (up to 4 DN). Therefore motion input pixels and events
must not be described as bit-identical to the baseline.

Sensor exposure, analog/digital gain, AWB and lens-shading settings remain
unchanged. The read-only gain audit found a plausible amplification mechanism,
not a measured fault-time cause. See `DISPLAY_TONE_FIX_AND_GAIN_AUDIT.md`.

## Measured offline effect

The 100 historical frames 8385..8979 are a different capture. Their transport
metadata reported no corrupt packets/CRC errors, but the capture bit identity
is unknown. On ROI [100,20,1100,150], the temporal residual RMS was:

| Processing | RMS |
|---|---:|
| Source | 3.82847 |
| Baseline horizontal filter, threshold 24 | 3.31496 |
| Candidate separable filter, threshold 16 | 2.96099 |

The candidate reduced this metric by about 10.68% relative to the baseline
filter. This is an offline result on historical data. It does not establish
that the photographed severe failure is fixed or that board output matches
this capture. Source hashes and the exact model/RTL binding are preserved in
`display_noise_replay/historical_replay.json`.

## Delivery status

Full implementation and standard bitgen gates still determine whether a new
diagnostic bit may be delivered. An in-progress synthesis, a preliminary
Slice estimate, and isolated module tests are not physical acceptance.
Hardware validation remains `NOT_RUN` until actual board testing.

Stronger style operators are isolated trials. They are not part of the V8
production source snapshot or evidence for a delivered style-enhancement bit.
