create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
# SPI pins are source-synchronous generated outputs; the receiving board
# samples them with SCLK.  No unrelated Ethernet/DDR clocks are in this
# bridge-only target.
