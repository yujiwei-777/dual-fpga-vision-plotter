# Display-noise main + KEY1 report secondary, 2026-11-03

Main: main_display_noise_fix_20261103, final physical build V8.
Secondary: secondary_pcb_ccl_binary_key1_write_20261103, exact reviewed frozen build.
Hardware acceptance for this pair: NOT_RUN.

Open each board's root .al in Tang Dynasty 2026.1 SP2. Root .al changes only project paths; originals are retained in their source locations. Source, model, constraints and bit bytes are unchanged.

Run: python -B verify_package.py
The recipient source ZIP provides the Chinese offline start page, wiring and operation instructions.
Historical attempts and supplementary trials are evidence only, not active implementations or acceptance.
V8 uses hash-identical canonical V6/V7 simulations plus an equivalence chain; not every simulation was rerun under V8.
Original RUN-8007 / USR-8450 diagnostics are retained alongside placed-capacity/IO/DPHY proof and standard bitgen success.
Tool installation, licenses and bridge firmware are not included. Cross-machine rebuild is not claimed.
