# Read-only audit of the 19 display styles

No product RTL, baseline, constraints or bit was changed for this audit. No TD or RTL simulator was run. Arithmetic examples are independent integer calculations derived from the active source. The style source is byte-identical to the specified baseline: SHA256 `9E8D7DC30411E5C38CAD9C52CA1F446E37D353EE6A66B16728544E58BA12EAF9`. Companion JSON records arithmetic examples and exact hashes.

## Actual active implementation

`isp/isp_top_basic_core.v:158` instantiates `style_transfer_96` with 19 runtime modes, CART edge threshold 32 and quantization mask E0. `FIXED_STYLE_MODE=0` does not force all styles to zero in this implementation; runtime selection remains active. `style_controls.v` cycles 0..18 with KEY2 and restores mode 0 with KEY3.

| Mode | Name | Current active operation |
|---:|---|---|
| 0 | ORIG | Display tone mapping, followed by RGB pass-through in the style stage |
| 1 | GRAY | Per-pixel approximate luma replicated into RGB |
| 2 | THRE | Per-pixel fixed luma threshold 128, black/white |
| 3 | INVT | RGB bitwise complement |
| 4 | REDC | Keep R, zero G/B |
| 5 | POST | RGB masked with E0, 8 levels/channel, maximum 224 |
| 6 | SATU | Intended increased saturation; signed offset defect described below |
| 7 | SOBL | Group-averaged 3x3 Sobel, clamp magnitude at 255, repeat one value across four pixels |
| 8 | EDGP | Complement the same group Sobel value, repeat across four pixels |
| 9 | EMBS | Group 3x3 emboss plus 128, clamped and repeated across four pixels |
| 10 | RAIN | Piecewise false colour; unsized concatenation concern below |
| 11 | EROD | Group 3x3 grayscale minimum, repeated across four pixels |
| 12 | DILA | Group 3x3 grayscale maximum, repeated across four pixels |
| 13 | MORP | Group max minus min, repeated across four pixels |
| 14 | BLUE | Keep B, zero R/G |
| 15 | LIFT | Per-channel `v + floor((255-v)/4)` |
| 16 | CNTR | Per-channel `v + floor(v/2) - 64`, saturated |
| 17 | GAML | Piecewise per-channel lift; nonmonotonic boundaries described below |
| 18 | CART | True per-pixel causal `abs(C-L)+abs(C-U)`; black if >=32, otherwise RGB&E0 |

The group Sobel window averages each four-pixel horizontal group before edge calculation. Its effective horizontal granularity is four original pixels; vertical granularity is one row. A finer-looking edge cannot be obtained merely by reducing its threshold or multiplying its output, because the four lanes already share the same edge value. Its first two groups and first two rows have `window_valid=0` and are zero-filled (white-filled in inverted mode). The causal feature is spatially behind the current RGB output position; a per-pixel edge replacement should explicitly define edge location rather than silently carry this approximation forward.

`gray8` uses R/4 + G/2 + G/16 + B/8 with separately truncated terms. White 255 maps to 236. This is a deliberate historical approximation in all active style luma calculations, not a standard full-range luminance transform. Threshold 128 corresponds to a neutral RGB level around 138. Changing this luma formula globally also changes threshold, CART gradients and many existing effects; it should be a separately validated choice.

## Existing defects worth fixing before stronger operators

1. **SATU negative offsets lose their sign.** `style_transfer_96.v:263` uses `offset={1'b0,delta[9:1]}` for signed `delta=value-gray`. The zero bit turns negative half-deltas into large positive numbers, which can subsequently saturate white or wrap into the clamp's negative range. For input RGB (0,200,0), gray is 112 and active arithmetic produces (255,244,255); signed half-delta arithmetic produces (0,244,0). For (100,200,100), active arithmetic produces (0,225,0), while the intended signed result is (75,225,75). A signed arithmetic shift, `delta >>> 1`, or explicit sign extension fixes the arithmetic without DSP, extra RAM or an added pipeline stage. The saturation branch still needs exhaustive signed testing.

2. **GAML has large output reversals.** Active `enhance8_sel` maps 63->126 but 64->80, then 127->158 but 128->144. The source contains a separate monotonic `gamma_light8` reference that is not called by the active enhancement path. Its intended boundaries are 63->126, 64->128, 127->159, 128->160. Replacing the active gamma with this monotonic curve is an existing-style repair. Sharing a compact offset/adder is possible; a 256-entry LUT per lane is unnecessary. There is no basis to claim this repair is already in the current bit.

3. **RAIN contains unsized arithmetic inside concatenations.** In `process_group_class` around lines 383..386, expressions such as `8'hff-((g0-64)<<2)` contain 32-bit unsized constants. Ordinary expression sizing makes that concatenation term 32 bits, so truncating the whole result to 24 bits can remove a supposedly fixed G/R byte. Predicted symptoms are abrupt colour jumps at 64 and 192. Use explicitly sized 8-bit helper results or functions. This is a high-confidence static width concern; confirm the exact mapper/simulator behavior with a directed gray ramp before changing it.

The style arithmetic reference functions share several active formulas, so comparing active logic to those same functions can reproduce a defect on both sides. New tests should include an independent signed mathematical oracle and full ramps across all segment boundaries.

Minimum follow-up scope: create a separate style-repair variant after the current noise build is frozen. First change only the SATU sign expression, GAML piecewise transfer and explicitly sized RAIN channel helper in `style_transfer_96.v`, with independent ramp/colour/handshake tests. SATU/GAML arithmetic behavior above is confirmed from the active expressions and integer evaluation; RAIN remains a static width hypothesis until directed RTL evidence. Keep mode IDs, control ports, pipeline stages, fixed tap and all other styles unchanged. Add edge/threshold/cartoon tuning as a second independently reviewable step after resource and timing results, rather than combining it with the current noise bit.

## Concrete resource-bounded replacements

| Priority | Candidate | Concrete behavior | Resource expectation and limitation |
|---|---|---|---|
| 1 | Fix SATU/GAML/RAIN | Signed saturation, monotonic gamma, explicit RGB byte widths | Replace existing expressions; zero DSP/BRAM growth, actual LUT/timing must be measured |
| 2 | Clean stronger Sobel/ink response | Reuse existing Sobel sum, apply deadband 12..24, then gain 2 or 4 and saturation; EDGP is its inverse | Affects only the existing selected feature mapping; no new windows/DSP/BRAM. Still four-pixel horizontal blocks, so cannot claim finer edges |
| 3 | Adaptive global threshold | Compare per-pixel gray to a frame-latched threshold derived from a scalar luma estimator, initially clamp 64..192 with offset -8..-16 | No histogram or divide per pixel. Existing RAW AE average cannot be reused numerically as if it were post-AWB luma; add/validate an estimate in the actual style input domain. Global adaptation does not remove local shadows |
| 4 | Per-pixel 2D edge mode replacing group Sobel | Extend existing `cartoon_96` mode select to emit per-pixel causal gradient or its inverse for modes 7/8. Feed raw per-pixel RGB to that module for these modes; remove the old group Sobel branch | Reuses CART's existing 320x32-bit luma line store and four-lane abs differences. No added large BRAM/DSP. Removing old Sobel arithmetic is necessary to offset new select/deadband logic. It is a different edge operator, not full 3x3 Sobel |
| 5 | Cartoon palette with full endpoints | Keep 8 levels but expand each 3-bit level to 8 bits via `{q3,q3,q3[2:1]}`: 0,36,73,109,146,182,219,255 | Pure wiring instead of simply zeroing low bits. Retains white at 255 instead of 224. Optional 4-level style can use replicated two-bit levels 0/85/170/255, clearly limited to the selected style |
| 6 | Cartoon outline tuning | Start with existing threshold32; compare 24/32/40 on real frames. Lower threshold draws more outlines but also more grain; higher threshold rejects grain but loses weak edges | Existing threshold parameter, no new memory. Avoid promising that lower threshold alone improves distant scenes. A grayscale deadband and tuned palette generally matter more than an indiscriminate outline increase |

For a local-background ink style without a new large window, a lightweight group-domain envelope/IIR background followed by per-lane `gray < background-offset` can be evaluated. It should be offered as a document/ink visual effect with known horizontal lag and row-start behavior, not silently replace general-purpose binary silhouettes. Otsu, full local mean and hysteresis connectivity are not free parameter changes and should not be introduced under a claim of unchanged resources.

Do not enable the unused `cartoon_sobel_96`, `style_video_96` queue or `denoise_96` merely because their files exist. They are not in the active hierarchy. The former needs two 320x80-bit lines; the old wrapper also allocates a 512x103-bit queue and changes last-row drain behavior. Previous sources explicitly document live-frame cadence/rolling failures from that integration. Replacing arithmetic in the current one-input/one-output pipeline is the safer bounded path.

## Recognition and display contract

The fixed CNN/PCB/document snapshot tap is `tone_fixed_O_tdata` -> `O_clean_rgb` in `isp_top_basic_core.v:184` -> `design_top_wrapper.v:1417` snapshot service. It branches before `style_transfer_96`; the proposed style-only arithmetic replacements leave fixed-tone bytes unchanged, provided ready/valid/markers remain exactly one-for-one and no extra backpressure is introduced. Do not change `display_tone_96.tone8`, CCM, AWB, RAW calibration, snapshot tap or the style/control handshake for this work.

Styles are applied before display DDR packing. Changing their appearance naturally changes stored/display pixels, while the DDR protocol need not change. Motion analysis in `design_top_wrapper.v:1722` uses the pre-HDMI-filter DDR display pixels (`S_video_rd_data`), so it still sees the selected visual style. Stronger binary/edge/cartoon operators can therefore affect motion sensitivity even though the fixed CNN snapshot is independent. Preserving the current motion algorithm does not prove unchanged motion behavior under a new visual style; include per-style motion regressions or separate its source in a future, explicitly scoped change.

The new HDMI spatial filter follows DDR and motion sampling. Its edge guard preserves black/white transitions. It cannot remove false black CART outlines already created earlier from noise, and should not be advertised as pre-Sobel/pre-CART denoising. Real contour cleanliness requires evaluating the upstream edge response as well.

This audit does not include a style enhancement bit. The current build under construction remains a noise/tone repair unless the main task explicitly integrates and revalidates additional operators. All visual and board claims remain NOT_RUN until tested.
