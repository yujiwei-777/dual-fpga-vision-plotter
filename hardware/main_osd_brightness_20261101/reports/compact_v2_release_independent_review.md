# Compact OSD v2 release evidence independent review

Status: final routed/read-only evidence pending. No permission to generate a bit is implied by this interim report. The reviewer did not start TD or alter RTL, constraints, databases, or audit tools.

## Audit script scope and findings

`td_release_audit.py gate` checks routed confidence, both timing corners, max/min checks, final timing mode, route invocation, all four WNS/TNS values, resource fractions using unrounded counts, pre-build input hashes, and routed DB/report freshness. Its tracked clock warnings are recorded rather than automatically rejected. `verify-readonly` checks database/project hashes and WNS/TNS plus required report presence; it explicitly leaves CDC/DRC content for independent review.

The initial `verify_compact_physical.py` has a permissive `raw_check_only_known_capacity_issue` condition: a nonzero check_design status is accepted if the entire console contains both `lslices exceed capacity` and `RUN-8007`. This is not sufficient to establish that no additional check_design error appeared. The status-zero branch does not inspect errors either. The finding was immediately sent to the main agent. Its DRC parsing only considers matching tabular rows, so unparsed error text also needs raw-report review. The reviewer did not modify this tool.

The bitgen Tcl does not read acceptance JSON itself; it is intended to run after acceptance in the external build sequence. Therefore generic gate success alone must not be presented as a complete physical/read-only acceptance.

## Pending raw evidence

The final review must inspect `02_sim/compact_readonly_v2` console, DRC, timing/area, skew/clocks, check_design, physical capacity and supplementary audit results directly. Required findings are nonnegative setup/hold WNS, zero setup/hold TNS, Slice <95%, ERAM <90%, DSP <95%, no RTCLK-5078/USR-6113, and only the independently evidenced pre-existing logical LSLICE counting discrepancy in the retained raw check_design output.

The main agent reports placement resources of 19,741 Slice (93.05%), 90 ERAM (83.33%), and 37 DSP (92.50%). These are provisional placement figures until checked against the final read-only area report.
