create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {rgmii_rxc} -period 8.000 -waveform {0.000 4.000} [get_ports {I_rgmii_rxc}]
derive_clocks
rename_clock -name {eth125} [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {eth125_90} [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {ddr_ref100} [get_clocks {u_ddr_ref_pll/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]

# Reset exceptions are installed only after apply_reset_exceptions.tcl proves
# the five synchronizers' D/Q/clock/async-source connections. Do not blanket-cut
# rst125_n or por_release: downstream consumer recovery/removal must remain
# visible, including the RX-to-MAC reset release paths.

# Center-aligned RGMII input budget used by the board-tested implementation.
# RXD/RX_CTL are delayed in the FPGA by the same PH1P HDIO code (31); these
# values describe the external PHY/PCB window and are applied on both edges.
set_input_delay -clock [get_clocks {rgmii_rxc}] -max 2.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -min 1.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -max -clock_fall -add_delay 2.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -min -clock_fall -add_delay 1.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
# TXC is a forwarded clock.  The PH1P delay primitive is modeled by the
# device implementation; no EG-series tap conversion or invented phase is
# applied here.  External TXC/TXD timing remains visible to the analyzer.
create_generated_clock -name {eth_txc_pad} -source [get_pins {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}] -master_clock {eth125_90} -add -multiply_by 1.000 [get_ports {O_rgmii_txc}]
set_output_delay -clock [get_clocks {eth_txc_pad}] -max 1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_txc_pad}] -min -1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_txc_pad}] -clock_fall -max -add_delay 1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_txc_pad}] -clock_fall -min -add_delay -1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
# Do not cut the forwarded-clock relationship here.  The TXC clock is
# generated from eth125_90 and TXD/TX_CTL are checked against eth_txc_pad on
# both edges; the old four exceptions matched no paths and made the audit
# ambiguous.  Reset and asynchronous control exceptions below remain narrow.

# Asynchronous control inputs stop only at their first synchronizer stage.
# I_sw2 is retained as a pin-compatible, intentionally unused production
# input; there is no SW2 synchronizer in this build and therefore no timing
# exception is required for it.
set_false_path -from [get_ports {I_uart_rx}] -to [get_regs {u_uart/u_rx/rx_meta}]
# I_esp_link_ready remains a pin-compatible, intentionally unused input in
# the UART-only bridge.  There is no data-path register to constrain here.
# apply_cdc_exceptions.tcl proves exact register Q/D pins at each build phase
# and loads a generated SDC. Held mailbox requests retain the 7 ns budget;
# returns, mailbox first stages and asynchronous Gray first stages retain
# 7.5 ns. All second stages and same-clock Gray paths remain normally timed.
# PHY link status is cut only at its proven first-stage D pin.


# Local KEY1 is asynchronous to eth125; stop at the first synchronizer stage.
set_false_path -from [get_ports {I_key1_n}] -to [get_regs {key1_meta}]
# Local KEY2 is asynchronous to eth125; stop only at its first synchronizer.
set_false_path -from [get_ports {I_key2_n}] -to [get_regs {u_key2_test/key_meta}]
# KEY3 is asynchronous to the always-on 50 MHz supervisor; KEY4 remains in
# eth125. Stop only at each exact first stage; later stages remain timed.
set_false_path -from [get_ports {I_key3_n}] -to [get_regs {u_board_reset/key_meta}]
set_false_path -from [get_ports {I_key4_n}] -to [get_regs {key4_meta}]
