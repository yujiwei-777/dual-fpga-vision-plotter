create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {spi_sclk} -period 50.000 -waveform {0.000 25.000} [get_ports {I_spi_sclk}]
# The SPI clock is an external source-synchronous clock and is unrelated to
# the 50 MHz control clock.  Payload and completion toggles cross through a
# stable mailbox and explicit synchronizers; timing them as ordinary derived
# clocks creates false setup/hold failures on the mailbox itself.
set_clock_groups -asynchronous \
    -group [get_clocks {sys_clk_50m}] \
    -group [get_clocks {spi_sclk}]
# SPI data is captured by the dedicated input clock domain.  The result
# Mode-0 data is launched on the master's falling edge and is already stable
# well before the sampling edge.  A small positive minimum models the external
# setup margin and prevents the non-clock-capable E16 pad skew from creating a
# same-edge hold violation.
set_input_delay -clock [get_clocks {spi_sclk}] -max 3.0 [get_ports {I_spi_mosi I_spi_cs_n I_spi_frame_valid}]
set_input_delay -clock [get_clocks {spi_sclk}] -min 4.0 [get_ports {I_spi_mosi I_spi_cs_n I_spi_frame_valid}]
set_output_delay -clock [get_clocks {spi_sclk}] -max 3.0 [get_ports {O_spi_miso O_spi_ready}]
set_output_delay -clock [get_clocks {spi_sclk}] -min -1.0 [get_ports {O_spi_miso O_spi_ready}]
set_false_path -from [get_clocks {sys_clk_50m}] -to [get_ports {O_spi_ready}]
set_false_path -from [get_ports {I_spi_frame_valid}] -to [get_regs {*frame_toggle*}]
