# Fresh RTL qualification of frozen metadata flattening

Candidate SHA256:
`9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128`.
Original kernel SHA256:
`8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C`.

The parent candidate and its prior integer/TD evidence are read-only. All new
copies, ModelSim libraries, logs and manifests are created in this directory.
The actual frozen production kernel and pipeline are compared with the candidate
using the same cadence, observations, raw mailbox and serial ownership contract.
No previous geometry, uncertainty, narrow-comparison or phase candidate is used.

`python run_regression.py --prepare --quick` first executes lint, the 3,307-vector
integer replay and the production 113-job/37-public-port cycle miter. The pipeline
retains all original 81 jobs/374 assertions and the extended 527 assertions.
`python run_regression.py --matrix` then runs all 40 existing kernel parameter
families and 10 lifecycle parameter groups, covering 560 state-specific clear/reset
aborts with re-entry. Destructive raw-bank reuse at emit_begin and serial record
ordering are checked by the unchanged testbenches. Specialized invalid input
rejection, confirmation/hold/lost behavior and external/internal readers remain
covered. The runner seals the copied sources, origins and all resulting evidence.

This directory is also a reusable same-cadence validation template: copy its
runner into a new independent functional directory and pin that candidate's own
hash before preparation. Never replace this frozen candidate or its evidence.

No TD is launched, no source is promoted, and no bit is generated. Local resource
improvement is not evidence that full-board placement or timing will pass.
Production, release bit, models, PCB, main-board files and `work/` remain unchanged.
Hardware validation: `NOT_RUN`.
