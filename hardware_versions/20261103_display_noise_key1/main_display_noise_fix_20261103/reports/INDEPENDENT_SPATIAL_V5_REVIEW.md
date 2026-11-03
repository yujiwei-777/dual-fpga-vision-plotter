# Independent read-only spatial V5 evidence review

Reviewed on 2026-11-03. No product, model, build snapshot, raw log or existing verification file was modified. No simulator or TD run was started for this review.

Result: **PASS for the reviewed functional evidence and hash bindings**. No blocking stale-row, boundary, width-one forwarding or invalid-output issue was found. Physical resource/timing acceptance and camera quality remain separate requirements. Board validation remains **NOT_RUN**.

Archive note: after this review, build tools moved the complete V5 canonical evidence to `02_sim/display_noise_attempt5_rtl_v5/` and verified all 107 archived file hashes. The canonical paths below identify the paths used during the reviewed run; the preserved V5 logs, vectors and verification.json now reside in that archive. `02_sim/display_noise/` was reset to four source files for a future independent candidate. This review does not apply V5 results to that future candidate.

## Exact reviewed identity

| Evidence | SHA256 |
|---|---|
| Current product `a4_display_spatial_h1.v` | `B680381A4307D79BC6B259A8B33C177E5F2CD59120FF38EE902BC691438C20A0` |
| Canonical `02_sim/display_noise/verification.json` | `2D0104E5484172B15D897817D9B8BDE0E2BAD3716463EBC184558509A059C319` |
| Combined trial `verification.json` | `D9BE9654EDA2154ED64C8B966BDBBBF30770729818D4E462D5E7DCC3994977DE` |
| Historical replay JSON | `8670DFFAAAAF4543D438F17B9AB11B77B7F607B12F5995C994B02AE8733DCDAE` |
| Unchanged integer model | `8C5BB22686DB26CFDB2F1C256038AEBC42C01E4FD01F652194700307FEAA5609` |
| Unchanged replay script | `8255C55F5FDA2DC589371E1838C620C561991CA7866376B8B3A7C42DA710C462` |
| Frozen separable V4, restored module name | `9FE7A1A5323340F854B312C1BBC33D72351D8065551878FA3A93A19469CF80EE` |

The review recomputed every canonical required-source hash: exactly seven entries, including the current summarizer. It checked the compile log and all eleven transcript hashes against verification.json, parsed their actual PASS/count summaries and zero-error/zero-warning output, checked all 33 vector hashes, and independently counted cycles and DE-active pixels directly from stimulus files. No old product hash is substituted for the current V5 identity.

## Canonical and equivalence coverage

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

Total: **1,859,523 cycles and 1,857,539 active pixels**. The canonical testbench checks all five markers every cycle, active RGB against the independently structured integer stream oracle, and ENABLE=0 identity on active pixels. The full geometry test has two consecutive 1280×720 frames, no inserted line blanking, and different source values between frames.

The separate combined trial uses a product candidate byte-identical to the current V5 RTL and a frozen V4 copy whose sole change is its module name. Restoring that name reproduces the frozen product hash above. Its compiled sources, verification metadata, all eleven actual transcripts and vector hashes were rechecked. It compares **all RGB bits and all five markers every cycle, including invalid RGB**, rejects X output, retains the integer-oracle and bypass checks, and exhausts **65,536 byte pairs in RTL** for avg2 in every case. Width-one instances exercise the retained forwarding branch. All 22 existing transcript files across canonical and combined evidence match their recorded hashes.

The candidate differs from frozen separable V4 only by width-gated forwarding, the exact split avg2 identity, and selecting the filtered output instead of muxing the neighbour input. It does not change the state machine, validity expressions, threshold16 or image algorithm. The split sum fits eight bits: 127+127+1=255. Moving the mux is exact because rounded avg2(C,C)=C. This equivalence concerns separable V4/V5; the earlier unused direct four-neighbour filter was a different algorithm.

## Boundary and stale-data reasoning

- Reset invalidates frame/row/left/pipeline state and resets output; RAM contents need no initialization because an upper sample cannot be selected until a complete valid row exists.
- A valid or blanking SOF clears prior-row validity. An isolated blanking SOF records a pending start without inventing a valid pixel. The next source pixel starts at x=0.
- A short row or missing EOL cannot authorize its partial row as an upper neighbour. A subsequent complete row overwrites all addresses before vertical access is enabled. EOF also clears frame validity; input without a new SOF cannot expose the prior frame vertically.
- For width>1, adjacent source pixels read current x and retire the previous x, so addresses differ. Normal row wrap writes the previous last column and reads zero. The exceptional same-address case after SOF or a one-pixel short row has upper validity false. DE gaps retire writes before a later read. Therefore the removed forwarding path has no unmasked use.
- Width one genuinely needs forwarding when adjacent rows arrive without blanking; the original branch remains. With a DE gap, the pending value is already written to RAM before the next read.
- Invalid RGB uses p_data; the horizontal pass substitutes the current source when DE is false, so invalid output cannot expose row RAM. The all-cycle frozen comparison exercises this directly.
- Row RAM stores horizontal intermediate H formed from original C/L. Final vertical output is never written back; there is no recursive vertical or previous-frame feedback.

A second agent independently checked these control cases and read the width-one, malformed and full-frame logs; it found no substantive boundary defect. Small-geometry exhaustive control-state enumeration supplements the reasoning, including arbitrary DE/SOF/EOL combinations. It is **not** a formal proof over all 1280×720 RTL states. HDL simulation does not establish TD RAM inference, read-during-write packing or physical timing; those require the build checks.

## Historical replay binding and limits

The replay binds the actual current RTL, unchanged model and unchanged replay script hashes. All 100 source metadata and PNG hashes were independently recomputed; recorded invalid_packets and frame_crc_errors are zero, and IDs lie within 8385..8979. The canonical verification binds this new replay JSON hash and exactly matches its recorded RMS values.

| Identical historical RGB input | Background temporal residual RMS |
|---|---:|
| Source | 3.8284718077 |
| Former H1 threshold24 | 3.3149623782 |
| Separable threshold16 | 2.9609882604 |

This is a 10.6781% reduction relative to former H1 on the selected flat ROI. Historical capture bit identity is unknown. These are software replay results, not measurements of this new bit or proof that every distant texture/detail is preserved. Low-contrast texture can be smoothed by a guarded spatial filter. Full-frame TNR, new camera captures, physical timing and real-board visual acceptance are outside this review.
