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
set_clock_groups -asynchronous -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -group [get_clocks {rgmii_rxc}]
set_clock_groups -asynchronous -group [get_clocks {eth_pll_clk_125m eth_pll_clk_125m_90}] -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK sys_clk_50m pll_clk_100m pll_clk_24m HDMI_SERIAL_CLK u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk rgmii_rxc}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -max 2.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -min 1.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -max -clock_fall -add_delay 2.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
set_input_delay -clock [get_clocks {rgmii_rxc}] -min -clock_fall -add_delay 1.500 [get_ports {{I_rgmii_rxd[*]} I_rgmii_rx_ctl}]
create_generated_clock -name {eth_pll_txc_pad} -source [get_pins {u_eth_pll/ph1p_phy_pll_wrapper_d2616deaaa79_Inst/u_PH1P_PHY_PLL.clkc[1]}] -master_clock {eth_pll_clk_125m_90} -add -multiply_by 1.000 -phase 0.000 [get_ports {O_rgmii_txc}]
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -max 1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -min -1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -clock_fall -max -add_delay 1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_output_delay -clock [get_clocks {eth_pll_txc_pad}] -clock_fall -min -add_delay -1.200 [get_ports {O_rgmii_tx_ctl {O_rgmii_txd[*]}}]
set_false_path -rise_from [get_clocks {eth_pll_clk_125m_90}] -rise_to [get_clocks {eth_pll_txc_pad}] -setup
set_false_path -fall_from [get_clocks {eth_pll_clk_125m_90}] -fall_to [get_clocks {eth_pll_txc_pad}] -setup
set_false_path -rise_from [get_clocks {eth_pll_clk_125m_90}] -fall_to [get_clocks {eth_pll_txc_pad}] -hold
set_false_path -fall_from [get_clocks {eth_pll_clk_125m_90}] -rise_to [get_clocks {eth_pll_txc_pad}] -hold
set_path_skew -from [get_regs {u_snapshot_service/u_capture_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_capture_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_snapshot_service/u_capture_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_capture_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_snapshot_service/u_packet_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_packet_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_snapshot_service/u_packet_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_snapshot_service/u_packet_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_in/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/wr_to_rd_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_video_out/U_w128_d512_fifo/soft_fifo_al_4057d6b76aa6_Inst/rd_to_wr_cross_inst/sync_r1[*]}] 7.200
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/wr_to_rd_cross_inst/sync_r1[*]}] 7.700
set_path_skew -from [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/ip_layer_inst/icmp_echo_data_fifo/rd_to_wr_cross_inst/sync_r1[*]}] 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/wr_to_rd_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo/rd_to_wr_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/wr_to_rd_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo/rd_to_wr_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/wr_to_rd_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {u_udp_cfg/u_udp_stack/mac_layer_inst/udp_pkg_buf_inst/rd_to_wr_cross_inst/sync_r1[*]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_multibox_cdc/held[*]}] -to [get_regs {u_multibox_cdc/staged[*]}] -datapath_only 13.000
set_path_skew -from [get_regs {u_multibox_cdc/held[*]}] -to [get_regs {u_multibox_cdc/staged[*]}] 7.700
set_max_delay -from [get_regs {u_multibox_cdc/req}] -to [get_regs {u_multibox_cdc/req_s1}] -datapath_only 13.000
set_max_delay -from [get_regs {u_multibox_cdc/ack}] -to [get_regs {u_multibox_cdc/ack_s1}] -datapath_only 7.700
set_max_delay -from [get_regs {u_copy_status_cdc/held[*]}] -to [get_regs {u_copy_status_cdc/staged[*]}] -datapath_only 13.000
set_path_skew -from [get_regs {u_copy_status_cdc/held[*]}] -to [get_regs {u_copy_status_cdc/staged[*]}] 7.700
set_max_delay -from [get_regs {u_copy_status_cdc/req}] -to [get_regs {u_copy_status_cdc/req_s1}] -datapath_only 13.000
set_max_delay -from [get_regs {u_copy_status_cdc/ack}] -to [get_regs {u_copy_status_cdc/ack_s1}] -datapath_only 7.700
set_false_path -through [get_nets {u_copy_status_cdc/mailbox_rst_n}] -to [get_regs {u_copy_status_cdc/u_src_reset/sync_ff[*] u_copy_status_cdc/u_px_reset/sync_ff[*]}]
set_max_delay -from [get_regs {u_main_link/online S_sw3_eth S_sw4_eth_s2}] -to [get_regs {u_multibox_cdc/online_s1}] -datapath_only 13.000
set_max_delay -from [get_regs {u_result_select/box_hold[*] u_result_select/valid_hold u_result_select/pcb_hold}] -to [get_clocks {HDMI_PIXEL_CLK}] -datapath_only 13.000
set_max_delay -from [get_regs {u_result_select/req}] -to [get_regs {u_result_select/req_sync[0]}] -datapath_only 13.000
set_max_delay -from [get_regs {u_result_select/ack}] -to [get_regs {u_result_select/ack_sync[0]}] -datapath_only 7.700
set_max_delay -from [get_regs {u_main_link/online}] -to [get_regs {S_aux_online_px_s1 u_result_select/online_sync[0]}] -datapath_only 13.000
set_false_path -from [get_ports {I_button[3]}] -to [get_regs {u_key4_pcb_oneshot/key_meta}]
set_false_path -through [get_nets {u_multibox_cdc/mailbox_rst_n}] -to [get_regs {u_multibox_cdc/u_src_reset/sync_ff[*] u_multibox_cdc/u_px_reset/sync_ff[*]}]
set_false_path -through [get_nets {u_result_select/mailbox_rst_n}] -to [get_regs {u_result_select/u_src_reset/sync_ff[*] u_result_select/u_px_reset/sync_ff[*]}]
set_max_delay -from [get_regs {u_pcb_status_cdc/held[*]}] -to [get_regs {u_pcb_status_cdc/staged[*]}] -datapath_only 13.000
set_path_skew -from [get_regs {u_pcb_status_cdc/held[*]}] -to [get_regs {u_pcb_status_cdc/staged[*]}] 7.700
set_max_delay -from [get_regs {u_pcb_status_cdc/req}] -to [get_regs {u_pcb_status_cdc/req_s1}] -datapath_only 13.000
set_max_delay -from [get_regs {u_pcb_status_cdc/ack}] -to [get_regs {u_pcb_status_cdc/ack_s1}] -datapath_only 7.700
set_false_path -through [get_nets {u_pcb_status_cdc/mailbox_rst_n}] -to [get_regs {u_pcb_status_cdc/u_src_reset/sync_ff[*] u_pcb_status_cdc/u_px_reset/sync_ff[*]}]
