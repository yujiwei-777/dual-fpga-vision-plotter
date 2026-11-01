# Strict independent release review

Overall: FAIL

- area: PASS
- placed_sites: PASS
- check_design: PASS
- check_io: FAIL
  - check_io adverse diagnostic: USR-8450 CRITICAL-WARNING: Please be cautious that there are unconstraint IOs(10 out of 39) in design and tool will auto configure them.
  - check_io adverse diagnostic: This is HIGH RISK and might have undefined behavior on board and damages following. Bitgen will abort.
- check_plb: PASS
- drc: PASS
- timing: PASS
- tracked_clock_warnings: PASS
- readonly_unchanged: PASS
- readonly_completion: PASS

Raw input SHA256:

- console_readonly.log: D12998264F1D65814E50CCBD14E875BC88CBA99DC4AC455C44C7B660E7D8FB2B
- readonly.drc: F5760421A23469348E5857BCA6F738BE317849E8536FA59E7459D88D447851D5
- readonly.timing: 626E3674F0E8A511AFD64D5BED458B0E38A1115C5BD8D9D75CB25DFAF60146FB
- readonly.area: 8965FA288A7CE23F2585A9B878B4499A872587034B80EB6DBEE9DF10859D1160
- readonly.sites.tsv: 44852A0DE9E964CC0A96F61160A24D41B77F4E2618B9FC530B2C435CB05D438F
- expected_slice_cells.tsv: D89EA10F83565B659FAB50D093340AEB48036A0B2B6B6FE83A787452EDFCAA7D
- readonly_input_hashes.json: ADD40A25CB693D33CD08C4B52B9684C44C09F6A05C15B4C73B8378914CE81C45
- readonly_verification.json: 7768D69993EF181C92FF6D167EBB48D6EC04B37D25B80D986B33E0028CD9C17B
- physical_capacity/physical_capacity_validation.json: 37CA450993A1102B5C8327CB3B5A1E15609BEA1D17D2C72E6B9DA3140C1E3CCB
- physical_capacity/named_logic_tiles.tsv: F9B66E748E10C33ADADF8AEC2B6F5B9592820F3ED49F0651919FFF67ADB802F7

Strict read-only command/DRC/timing/placed-site audit. Raw adverse IO diagnostics are never hidden by catch=0.

Hardware: NOT_RUN
