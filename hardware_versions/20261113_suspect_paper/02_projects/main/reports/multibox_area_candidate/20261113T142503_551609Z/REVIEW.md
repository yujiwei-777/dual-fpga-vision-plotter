# Isolated four-target badge offset area candidate

The actual `hxa_multibox_overlay.v` module was copied with its real initialized
glyph ROM and all outputs. Production inputs and frozen builds were not edited.

The candidate reuses one 11-bit X subtraction and one 10-bit Y subtraction per
slot for both badge hit detection and text offsets. `use_ripple = 0` is the
documented vendor directive. The optimized predicate is restricted to default
1280×720, BADGE_W=144; other parameter values retain the original expression.

For the default loader, badge_x <= 1136 and badge_y <= 1007 even for malformed
raw source words. Hence badge_x+144 < 2048 and badge_y+16 < 1024: negative
modulo differences cannot enter the badge hit interval. Slot-zero priority,
banner override, label/border priority and all outputs retain their original
ordering.

## Evidence

- ModelSim full-output miter: 4,438,724 matching cycles, including three complete
  1280×720 rasters, four overlapping boxes, clipped and malformed input,
  randomized natural coordinate axes, 12-bit raster aliases, reset and link/update
  transitions. Actual outputs checked: O_hit, O_color, O_summary_bcd and slots.
- Fresh independent area-only TD synthesis succeeded for both modules.
- Common 32-bit serial input wrapper preserves arbitrary box data and all 77
  output bits while fitting device IO limits. Wrapper overhead is included in
  both totals; these totals are not whole-board resource estimates.

| Resource | Original | Candidate | Difference |
|---|---:|---:|---:|
| Raw LUT | 735 | 654 | -81 |
| Legalized Slice | 568 | 507 | -61 |
| FF | 493 | 493 | 0 |
| Dedicated adder Slice | 32 | 0 | -32 |
| ERAM | 1 | 1 | 0 |
| DSP | 0 | 0 | 0 |

The immediately preceding `20261113T142246_665682Z` probe failed solely because
the unwrapped top exposed 322 IOs, above the device limit. It is preserved as
failure evidence and was not used for the comparison.

## Integration boundary

Candidate module: `candidate/hxa_multibox_overlay.v`

Candidate SHA256:
`95A538C533526F672A0850FCE611913044E58BCF6EF110C458B83E14203B6CD9`

Saved baseline module SHA256 (CRLF):
`63E94A56D65F7F2DFF210EBCC2137E775D77B45B90B9BEE38E5F43ABBFFC7C60`

Original production/control source SHA256 (LF), as recorded in INPUTS.json:
`51362EF60E6A5DEBC11F6C63E28D4F3A796F44B28420D54E7530DCE4473B9933`

The two baseline files have identical UTF-8 text after universal-newline
decoding; the saved probe source uses CRLF. Candidate integration later changes
the active variant source by design. RESULT.json's unchanged-input flag states
the historical probe run-end check, not that later integration is forbidden.

Machine-readable receipts, logs, source hashes and area report hashes are bound
in `INPUTS.json` and `RESULT.json`. Saving 81 raw LUT is sufficient to consider
whole-board integration. It does not prove whole-board placement or timing.
No whole-board build or bitgen was run by this probe. Hardware: NOT_RUN.
