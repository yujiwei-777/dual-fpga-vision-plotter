create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

create_clock -name {rgmii_rxc} -period 8.000 -waveform {0.000 4.000} [get_ports {I_rgmii_rxc}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


rename_clock -name {eth_pll_clk_125m} [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {eth_pll_clk_125m_90} [get_clocks {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}]

set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK eth_pll_clk_125m eth_pll_clk_125m_90}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] \
    -group [get_clocks {rgmii_rxc}]


# RGMII IO starting budgets retained from the existing hx1p35a_img_proc
# source-synchronous design. Physical PHY/PCB timing verification is pending;
# no claim of external-IO signoff is made from these initial budgets alone.
set_input_delay -clock [get_clocks {rgmii_rxc}] -max 2.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -min 1.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -max -clock_fall -add_delay 2.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -min -clock_fall -add_delay 1.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]

create_generated_clock -name {eth_pll_txc_pad} \
    -source [get_pins {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}] \
    -master_clock {eth_pll_clk_125m_90} -add -multiply_by 1.000 -phase 0.000 [get_ports {O_rgmii_txc}]

# YT8511C/H datasheet PDF page 87: receiver setup/hold each require 1.0 ns.
# Actual forwarded TXC is already shifted 90 degrees. Add a provisional
# 0.2 ns PCB skew budget to each requirement: max=+1.2, min=-1.2.
# A positive min would relax the PHY hold requirement incorrectly.
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -max 1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -min -1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -clock_fall -max -add_delay 1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -clock_fall -min -add_delay -1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]

# TXC 时钟路径本身（90° ODDR -> 生成时钟 pad）不计时，避免双重计数
set_false_path -rise_from [get_clocks {eth_pll_clk_125m_90}] -rise_to [get_clocks {eth_pll_txc_pad}] -setup
set_false_path -fall_from [get_clocks {eth_pll_clk_125m_90}] -fall_to [get_clocks {eth_pll_txc_pad}] -setup
set_false_path -rise_from [get_clocks {eth_pll_clk_125m_90}] -fall_to [get_clocks {eth_pll_txc_pad}] -hold
set_false_path -fall_from [get_clocks {eth_pll_clk_125m_90}] -rise_to [get_clocks {eth_pll_txc_pad}] -hold

# Gray bus skew and related I2C clock; reviewed 2026-09-16.
# TD 2026.1 SP2 set_path_skew is independent of set_clock_groups/false_path.
# DDR usr_clk will be 133.333 MHz (7.500 ns) with the corrected 100 MHz ref.
# Each FIFO direction is constrained separately; never combine the two buses.
# Budget = min(source period, destination period) - 0.300 ns = 7.200 ns.

# Camera 59.995 MHz -> DDR 133.333 MHz, 9-bit Gray pointer.
set_path_skew -from [get_regs {u_snapshot_service/u_capture_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_capture_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
# DDR -> camera, 9-bit Gray pointer.
set_path_skew -from [get_regs {u_snapshot_service/u_capture_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_capture_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.200

# DDR 133.333 MHz -> Ethernet 125 MHz, 8-bit Gray pointer.
set_path_skew -from [get_regs {u_snapshot_service/u_packet_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_packet_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
# Ethernet -> DDR, 8-bit Gray pointer.
set_path_skew -from [get_regs {u_snapshot_service/u_packet_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_packet_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.200

# Original camera -> DDR video FIFO, 9 bits in each direction.
set_path_skew -from [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/sync_r1[*]}] 7.200

# Original DDR -> HDMI 75.002 MHz video FIFO, 9 bits in each direction.
set_path_skew -from [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/sync_r1[*]}] 7.200

# I2C SCL is generated as an I_clk-domain enable in uii2c.v.
# No generated clock or asynchronous reset exception is required here.

# DIAGNOSTIC_ENABLE=0 removes S_dbg_cam_cfg_seen and its two sampling stages.
# No exception is required for this unobservable status chain. If diagnostics
# are enabled, audit the mapped source/stage-0 crossing before constraining it.

# Preview HDMI/ETH and UDP FIFO Gray buses; 7.7 ns = 8 ns minus 0.3 ns.
# UDP TX and ICMP FIFOs currently share a clock; their ordinary timing remains.
# u_udp_cfg/u_video_fifo: 13 bits in each direction.
set_path_skew -from [get_regs {u_udp_cfg/u_video_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_video_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_video_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_video_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
# u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo: 12 bits in each direction.
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
# u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo: 7 bits in each direction.
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
# u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst: 7 bits in each direction.
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
# u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo: 12 bits in each direction.
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
# u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo: 7 bits in each direction.
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
# u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo: 11 bits in each direction.
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
# RX LCLK is asynchronous to ETH125, even though both are nominally 125 MHz.
# These exact pointer-to-stage-1 paths use bounded datapath delay, not a phase relationship.
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/sync_r1[*]}] -datapath_only 7.700

# Type18 bundled-data mailbox. Held is frozen from request until ACK returns.
# Capture occurs after two request synchronizers plus one extra settling clock.
# Bound each route to one HDMI period minus 0.3 ns, and bus skew to ETH period
# minus 0.3 ns. No false-path exception is applied to the held metadata bus.
set_max_delay -from [get_regs {u_multibox_cdc/held[*]}] -to [get_regs {u_multibox_cdc/staged[*]}] -datapath_only 13.000
set_path_skew -from [get_regs {u_multibox_cdc/held[*]}] -to [get_regs {u_multibox_cdc/staged[*]}] 7.700
set_max_delay -from [get_regs {u_multibox_cdc/req}] -to [get_regs {u_multibox_cdc/req_s1}] -datapath_only 13.000
set_max_delay -from [get_regs {u_multibox_cdc/ack}] -to [get_regs {u_multibox_cdc/ack_s1}] -datapath_only 7.700
set_max_delay -from [get_regs {u_main_link/online S_sw2_eth_s2 S_sw3_eth}] -to [get_regs {u_multibox_cdc/online_s1}] -datapath_only 13.000
