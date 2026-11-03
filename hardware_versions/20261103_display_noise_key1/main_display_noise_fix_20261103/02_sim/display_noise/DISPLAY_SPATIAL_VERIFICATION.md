# HDMI spatial filter verification

Result: **PASS**, 11/11 independent integer-oracle RTL cases. Board validation: **NOT_RUN**.

## Algorithm and scope

The display-only module first computes H from current source C and original source L: rounded avg2 when all RGB differences are <=16, otherwise C; the first column is C. It then averages current H with previous-row H under the same RGB guard; first-row output is H. Missing or rejected neighbours substitute the current sample. All RGB channels retain eight bits. Strong two-level edges are preserved; low-contrast texture can be smoothed and requires real-camera comparison.

This separable v6 candidate preserves frozen v5/v4 image behavior exactly. V6 changes only the fixed TH16 neighbour predicate: high-nibble equality or explicit nonwrapping adjacent-high relations plus Boolean low-nibble ordering replace signed subtraction. The same abs(a-b)<=16 decision and RGB three-channel AND remain. The separate nocarry trial checks every byte pair, all 196,608 single-channel RGB placements, all 65,536 avg2 pairs and full-cycle RGB/markers including invalid RGB against frozen v5. Its verification hash is bound in equivalence_evidence. The prior combined proof from v5 to v4 remains bound in prior_equivalence_evidence. No threshold, precision, pipeline, model or filtering algorithm changed.

The inherited v5 resource-only changes use an 8-bit split rounded-average sum, move neighbour selection to the output, and omit masked RAM forwarding when width>1. Row RAM stores horizontally averaged H, never final vertical output. H is always formed from original current/left source pixels; there is no recursive row or frame feedback. The image algorithm, integer model and replay script remain unchanged from separable v4.

One synchronous line RAM stores 1280 x 24 bits of H, the horizontal-pass result. Final vertical output is never written back. Validity masks prevent stale/uninitialized samples after reset, frame boundaries, short rows or SOF restart. Width-one geometry retains explicit collision forwarding; for width>1 every possible read/write collision has the upper-neighbour validity masked. A supplemental reachable-state control enumeration confirms this for arbitrary DE/SOF/EOL inputs on tested small geometries. No DSP or previous-frame storage is introduced. Actual ERAM/Slice use and timing must be established by synthesis/route.

Pixel data and vsync/hsync/de/user/last pass through the same two register stages. The DDR read request must use the original timing generator DE; the delayed display DE belongs only to the post-read display path.

## Evidence

ModelSim SE-64 2020.4; file license E:/model/win64/LICENSE.TXT supplied through both license environment variables. One simulator process at a time. Compilation and all simulation transcripts report zero errors and warnings. Every cycle checks all five timing markers; every active output checks exact RGB against the integer oracle, plus ENABLE=0 delayed identity. Case equality rejects X data.

This canonical separable v6 run uses a fresh directory and library after the complete v5 evidence was archived and hash-verified in ../display_noise_attempt5_rtl_v5/. V5 replay JSON/image were independently copied and SHA-verified in reports/display_noise_replay_attempt5_v5/ before the new current-product 100-frame replay. Historical v2 logs are retained in ../display_noise_attempt2_rtl_v2/. The earlier vlib already-exists warning was missed by the original summarizer, which checked only the later vlog summary; that historical compile is not used to satisfy the clean zero-warning gate. No historical raw log has been changed. Both combined and nocarry equivalence trial directories remain preserved.

| Case | Cycles | Active pixels | SOF | EOL |
|---|---:|---:|---:|---:|
| flat_noise | 9623 | 8192 | 1 | 64 |
| strong_edges | 2230 | 1920 | 5 | 60 |
| rgb8_range | 3846 | 3840 | 256 | 768 |
| threshold_rgb_guard | 135 | 96 | 1 | 6 |
| geometry_1x1 | 20 | 4 | 4 | 4 |
| geometry_1x7 | 64 | 22 | 4 | 22 |
| geometry_2x5 | 67 | 32 | 4 | 16 |
| geometry_7x1 | 45 | 28 | 4 | 4 |
| geometry_7x5 | 156 | 112 | 4 | 16 |
| malformed_reentry | 131 | 93 | 4 | 11 |
| full_720p | 1843206 | 1843200 | 2 | 1440 |

Total: 1,859,523 cycles, 1,857,539 active output pixels.

The complete-geometry test sends two 1280x720 frames back to back without line/frame blanking. It checks all 1,843,200 source pixels, 2 SOF and 1,440 EOL markers, including the final row with no invented drain pixels. Other cases cover random DE gaps, all 256 RGB8 channel levels/low bits, 16/17 threshold boundaries in each channel, strong horizontal/vertical/diagonal edges, a one-pixel line, checkerboard, width-one RAM collision, isolated/held/abrupt SOF, early/missing EOL, and reset before initialized RAM.

## Synthetic noise result

A flat RGB field with independent Gaussian input noise sigma=3.3 and fixed random seed gives newly calculated RMS 3.3042 before filtering, 2.3723 with the exact historical horizontal 2-tap rule, and 1.7732 with separable guarded averaging (-25.26% against historical h1). Borders are excluded consistently from all three RMS measurements. The test asserts the reduction and exact preservation of strong-edge images and flat RGB8 fields.

The separate historical 100-frame RGB replay was also recomputed: source RMS3.8284718, exact old h1 threshold24 RMS3.3149624, separable threshold16 RMS2.9609883, a 10.6781% reduction against h1. Frames8385..8979 use ROI[100,20,1100,150], validated PNG hashes and zero recorded transport errors. The vectorized replay is checked against the integer model. It binds the actual RTL, model and replay script hashes. Historical capture bit identity is unknown; this does not establish new-bit camera performance, visible-detail quality, or the source of distant texture artifacts. Full-frame TNR, AE/ISP changes, CNN/ROI input changes, and style-operator changes are outside this module. Board visual validation remains NOT_RUN.

## Reproduce and hashes

Run generate_vectors.py, then run_display_noise.ps1, then summarize_results.py from this folder. verification.json records every transcript hash and tested source hash; vectors_manifest.json records all input vector hashes.

| File | SHA256 |
|---|---|
| 01_rtl\imgq_gain_m\main\user_source\hdl_source\a4_display_spatial_h1.v | CD72245FA5CF73F16F35C2F655E5F13DD5F4949D14D258A7B99F9179AA219696 |
| model\display_spatial_reference.py | 8C5BB22686DB26CFDB2F1C256038AEBC42C01E4FD01F652194700307FEAA5609 |
| 02_sim\display_noise\generate_vectors.py | 8B624B7C4E3DD75AD102E7BE676059CC682A0E652F9470C5AEE7F02F88459D83 |
| 02_sim\display_noise\tb_display_spatial.sv | FBE2DACBFF2A61ECFDCE0B5583EFB3C5BE514230915F6FCD9DC332BCCBF42469 |
| 02_sim\display_noise\run_display_noise.ps1 | 7DEEF7FED7E02FFD411EBA226224C2FA69270F1874F3D6F9CA337246E93E21B2 |
| 02_sim\display_noise\vectors_manifest.json | 2DC916E066223FD8140F2D75C5605E73F8A11DB2D20713EBDB3440E8463E18C7 |
| 02_sim\display_noise\summarize_results.py | B105E4A398706C583382C86293444CA6B4ED3CD6366CB104E38B7705A3C194D1 |
