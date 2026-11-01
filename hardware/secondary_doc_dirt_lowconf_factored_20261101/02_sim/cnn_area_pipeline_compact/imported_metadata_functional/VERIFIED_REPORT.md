# Frozen metadata flattening: full RTL qualification passed

Candidate: `9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128`.
The parent candidate and its earlier synthesis/truth evidence were not modified.

| Fresh RTL suite | Result |
|---|---|
| compile / lint | zero errors and zero warnings |
| actual production pipeline exact-cycle miter | 11,742,298 cycles; 37 public ports; 11 controls; 113 jobs; 527 assertions |
| retained original pipeline program | 81 jobs and 374 assertions preserved |
| serialized integer replay | 3,240 checks; 3,307 vectors; 2,059 emitted records; 3,247 bank reuses |
| integer replay completion latency | maximum 857 clocks, unchanged |
| exact-cycle kernel configurations | all 40 passed |
| lifecycle configurations | all 10 passed; 560 targeted clear/reset aborts plus re-entry |

The unchanged benches cover internal/external candidate readers, parameterized
area/coordinate grids, malformed-input rejection, confirmation/hold/lost tracking,
raw-bank destructive reuse at emit_begin, serial slot order, clear/reset priority
and suppression of stale output after abort/re-entry. The actual production kernel
and pipeline are exercised with controlled leaf modules; this is directed/random
simulation, not a mathematical formal proof or independent camera-quality test.

`RESULTS.json` SHA256:
`50A3FF531E8EEE7227296BA8353F8937BB5C4A23B05D527DFB01243CD0F66247`.

`FINAL_AUDIT.json` verifies all sealed input/origin/result hashes and all 54 log
files. The only simulation warning code is 8891, from the inherited `-novopt`
visibility option. Compile/lint has no warning. The audit itself is reproducible
from the newly sealed `audit_evidence.py` source.

This establishes the frozen candidate's same-cycle RTL behavior for the recorded
coverage. Its earlier local synthesis saving of 3 Slice / 2 logic LUT does not
establish full-board placeability, timing, CDC, FIFO, DDR, DRC or bitgen acceptance.
No TD was run here, no source was promoted and no bit was generated. Models, PCB,
release, main board and `work/` remain unchanged. Hardware validation: `NOT_RUN`.
