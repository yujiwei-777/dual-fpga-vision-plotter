# Fixed-threshold Boolean byte comparison

The isolated `close_byte_th16.vh` function implements exactly
`abs(unsigned(a)-unsigned(b)) <= 16`. It uses bitwise Boolean operators and
reduction AND only. No addition, subtraction, ordered comparison, arithmetic
shift, or wrapped increment appears in the RTL expression.

Write `a=16*ah+al`, `b=16*bh+bl`, with all four components in 0..15:

- `ah==bh`: every pair is accepted because the byte distance is at most 15.
- `ah==bh+1`: accept exactly when `al<=bl`.
- `bh==ah+1`: accept exactly when `bl<=al`.
- Every larger high-nibble difference has minimum byte distance 17 and is rejected.

The implementation expresses the two nonwrapping high-nibble adjacency
relations by the location of the increment carry termination. Its terms
enumerate low-bit transition `0->1`, `01->10`, `011->100`, or `0111->1000`
with higher bits unchanged. There is no `1111->0000` case. Low-nibble ordering
uses the first differing bit from MSB to LSB, with equality accepted.

`check_close_byte.py` exhaustively compares the identical Boolean formula to
Python integer absolute difference for all 65,536 unsigned-byte pairs. All
pass; 8,176 are accepted. This also agrees with the independent count
`256*33 - 16*17 = 8176`. The complete result and source hashes are saved in
`close_byte_check.json`.

The function is specialized to threshold 16. A parameterized caller must keep
its existing generic threshold branch for every other value. RGB acceptance
must still AND the three byte decisions; acceptance of one channel must not
substitute for the existing all-channel condition.

Expected benefit is elimination of the explicit subtraction carry/ripple
datapath. Boolean LUT use and depth may increase. This source contains no
arithmetic, but only a measured mapped netlist establishes actual ripple,
SliceL, LUT use and timing; no resource or timing improvement is claimed from
this arithmetic proof. The script checks the formula, not compiled RTL.

Production RTL, reference model and canonical evidence were not changed.
RTL simulation: NOT_RUN. TD: NOT_RUN. Board test: NOT_RUN.
