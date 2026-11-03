# V8 synthesis parameter visibility review

Status: read-only audit and **unexecuted** readback Tcl preparation. ROOT owns
all TD processes. This work did not start TD, change RTL/current RUN/build Tcl,
or change `verify_display_noise_build_strategy.py`.

## What the actual V8 log establishes

The captured, still-running log is `synth_log_snapshot.log`; its source path,
byte count and SHA256 are in `evidence.json`. It is a partial snapshot, not a
final synthesis PASS or frozen complete log.

| Parameter | Requested | Actual evidence in captured log | Exact parameter readback established? |
|---|---|---|---|
| gate add_map_lut_struct | high | one set_param start, line395; no printed property row | No |
| gate map_mode | area_prior | exact gate commit table, line1312, default auto, note `*` | Yes, committed public table |
| gate multi_thread_mapping | partition | set_param start line398 **and** `SYN-3001 : multi-thread mapping mode: partition`, line1398 | Runtime mode established; no property-row readback |
| rtl resource_sharing | auto | one set_param start, line399; no printed property row | No |
| rtl shifter_style | shifter_reg | one set_param start, line400; no printed property row | No |
| gate pack_effort | high | exact gate commit table, line1314, default medium, note `*` | Yes, committed public table |

The extra logged `set_param gate opt_area high` at line397 is not a tuple in
the frozen authorized header. It appears during TD's processing of map_mode;
retain it as tool-generated processing evidence, not a human source override.
No claim about a hidden parameter's actual value follows from a command-start
record alone. A start record also does not supply that parameter's default or
the commit-table note that the current checker requires.

## Why the current strict checker cannot pass this normal log as written

`validate_log` requires a unique `RUN-1001 ... name | value | default | note`
row for all six settings. The four advanced settings have no such row in the
actual corresponding RTL/gate commit tables. Requiring exact default/note
fields for those rows is an additional checker contract, not an FPGA resource
or timing requirement stated by the user. The missing optimize_gate completion
in this snapshot is different: synthesis was still running, so that is a valid
pending requirement and must not be bypassed.

Official `SWUG105_TCL_Command_User_Guide.pdf`, section4.1.19, PDF29/printed22,
documents `report_param` as printing DB nondefault **public** parameters by
default. `-detail` includes default-valued parameters; `-file` still writes
only nondefault settings even when combined with `-detail`. Therefore the
absence of advanced/default rows from a normal public table is not by itself
proof that an officially supplied AreaOptimizeHigh option was rejected. It is
also not permission to fabricate those rows or pretend that readback occurred.

The extracted page text and its PDF SHA256 are retained in this directory.
The official PH1 strategy tuples and frozen synthesis source remain separate
source/intent evidence; neither is a readback of active internal state.

## Candidate independent readback, not yet tested

Static inspection of the installed `td_commands_prompt.exe` found:

```text
get_param
step_name param_name -run <string> -help
report_param
-h -help -stage <string> -detail -all -file <string>
```

The executable SHA256, byte offsets and neighboring ASCII strings are bound in
`evidence.json`. This establishes that the command metadata exists in this
installation; it does not establish that execution will succeed, that a hidden
parameter is persisted in an exported DB, or that `-all` prints every desired
entry. `get_param` and `-all` are not described on the public PDF page above.

`read_v8_parameters.tcl` is ready for ROOT to run **after synthesis completes**
from this independent directory. It imports the actual V8 gate DB, queries all
six values directly, and prints values taken only from `get_param` returns.
It contains no `set_param`, `load_run_param`, parameter reset/commit, project
save, optimization, DB export, place, route or bitgen. It does not echo intended
values as observed values. Each failed query or mismatch is explicit, and no
six-value match marker is issued unless all six actual returns match.

Supplementary `report_param -all -detail` reports are caught and recorded if
unsupported; they are not replaced by invented output. ROOT should bind raw
stdout/stderr, script SHA256 and the exact input DB SHA256 before and after
execution. Querying the imported DB is persisted-DB readback; existing actual
optimization logs and no-reset/no-override checks are still needed to bind it
to the completed synthesis that produced that DB. Do not run parameter setters
in the readback process, which would merely read back its own requests.

## Acceptance recommendation after the actual experiment

1. Prefer successful exact readback of all six values from the actual completed
   DB. If available, bind the DB, raw log and unmodified script and keep exact
   value checks; do not continue requiring an impossible public-table row for
   an advanced value that was instead genuinely queried.
2. If TD cannot expose a hidden value, retain official/source validity, one
   legal set request, no parameter diagnostic, no override/reload after the
   requests, corresponding commit, and successful RTL/gate optimization.
   Explicitly label the hidden item as `requested / API processing observed /
   internal readback unavailable`. This is weaker than exact readback and must
   never be reported as all-six exact verification.
3. Retain exact actual public table verification for map_mode and pack_effort.
   Retain the actual partition runtime message for multi_thread_mapping as a
   distinct evidence class. Do not infer the three other hidden values from
   the partition runtime message.
4. The user-facing release gates remain actual final resources, nonnegative
   setup/hold, zero TNS and standard bitgen with the existing independent
   checks. Hidden-parameter visibility is a documented provenance confidence
   issue; it should not silently become an unfulfillable extra product gate.
   Conversely, source intentions alone cannot replace failed physical gates.

No checker changes are authorized by this report. ROOT requested that any
change wait for the actual readback result.
