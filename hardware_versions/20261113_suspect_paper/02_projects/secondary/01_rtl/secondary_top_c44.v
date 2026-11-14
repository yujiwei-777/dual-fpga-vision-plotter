// Independent resource-reduced PCB binary top.
// The wrapped production top keeps all link, DDR, document-copy and GRBL
// behavior; only the PCB classifier parameters are fixed to C1=4/C2=4.
module secondary_top_c44(
    input wire I_sys_clk,I_sw2,I_key1_n,I_key2_n,I_key3_n,I_key4_n,
    input wire [3:0] I_rgmii_rxd,
    input wire I_rgmii_rx_ctl,I_rgmii_rxc,
    output wire [3:0] O_rgmii_txd,
    output wire O_rgmii_tx_ctl,O_rgmii_txc,O_phy_rst,
    input wire I_uart_rx,I_esp_link_ready,
    output wire O_uart_tx,
    output wire [12:0] ddr_addr,
    output wire [1:0] ddr_ba,
    output wire [0:0] ddr_cke,ddr_odt,ddr_cs_n,ddr_ck_p,ddr_ck_n,
    output wire ddr_ras_n,ddr_cas_n,ddr_we_n,
    inout wire [1:0] ddr_dm,ddr_dqs_p,ddr_dqs_n,
    inout wire [15:0] ddr_dq,
    output wire [3:0] O_led
);
    secondary_top #(.PCB_BINARY_CLASSES(1),.PCB_BINARY_C1_CHANNELS(4),.PCB_BINARY_C2_CHANNELS(4)) u_impl(
        .I_sys_clk(I_sys_clk),.I_sw2(I_sw2),.I_key1_n(I_key1_n),.I_key2_n(I_key2_n),.I_key3_n(I_key3_n),.I_key4_n(I_key4_n),
        .I_rgmii_rxd(I_rgmii_rxd),.I_rgmii_rx_ctl(I_rgmii_rx_ctl),.I_rgmii_rxc(I_rgmii_rxc),
        .O_rgmii_txd(O_rgmii_txd),.O_rgmii_tx_ctl(O_rgmii_tx_ctl),.O_rgmii_txc(O_rgmii_txc),.O_phy_rst(O_phy_rst),
        .I_uart_rx(I_uart_rx),.I_esp_link_ready(I_esp_link_ready),.O_uart_tx(O_uart_tx),
        .ddr_addr(ddr_addr),.ddr_ba(ddr_ba),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_cs_n(ddr_cs_n),
        .ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),.ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),
        .ddr_dm(ddr_dm),.ddr_dqs_p(ddr_dqs_p),.ddr_dqs_n(ddr_dqs_n),.ddr_dq(ddr_dq),.O_led(O_led));
endmodule
