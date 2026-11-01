
set_pin_assignment	{ I_sys_clk }			{ LOCATION = C4; IOSTANDARD  = LVCMOS33; PULLTYPE = PULLUP; }

set_pin_assignment	{ O_cam_scl }		{ LOCATION = K3; IOSTANDARD  = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment	{ IO_cam_sda }		{ LOCATION = J3; IOSTANDARD  = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment	{ O_cam_24m }	{ LOCATION = L3; IOSTANDARD  = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment	{ O_cam_rst }		{ LOCATION = L2; IOSTANDARD  = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }

# HX1P35A manual PDF page 23: KEY1=D5, KEY2=A9, KEY3=B9 (active low)
set_pin_assignment	{ I_button[0] }			{ LOCATION = D5;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment	{ I_button[1] }			{ LOCATION = A9;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { I_button[2] } { LOCATION = B9; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
set_pin_assignment { I_button[3] } { LOCATION = C7; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }

# SW1 (A4): target-detection master switch. Slide switch, ACTIVE HIGH
# (manual: up = 1, down = 0) -- do NOT invert in the HDL.
set_pin_assignment	{ I_sw1 }				{ LOCATION = A4;  IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }

# SW2=0 selects PC host mode; SW2=1 reserves the RGMII link for a future aux board.
set_pin_assignment	{ I_sw2 }				{ LOCATION = B4; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }

# HX1P35A onboard PHY RGMII pins
set_pin_assignment	{ I_rgmii_rxd[0] }		{ LOCATION = N9; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment	{ I_rgmii_rxd[1] }		{ LOCATION = T7; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment	{ I_rgmii_rxd[2] }		{ LOCATION = T8; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment	{ I_rgmii_rxd[3] }		{ LOCATION = T9; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment	{ I_rgmii_rx_ctl }		{ LOCATION = N8; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment	{ I_rgmii_rxc }		{ LOCATION = V3; IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment	{ O_rgmii_txd[0] }		{ LOCATION = R11; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; PULLTYPE = NONE; }
set_pin_assignment	{ O_rgmii_txd[1] }		{ LOCATION = P11; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; PULLTYPE = NONE; }
set_pin_assignment	{ O_rgmii_txd[2] }		{ LOCATION = T10; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; PULLTYPE = NONE; }
set_pin_assignment	{ O_rgmii_txd[3] }		{ LOCATION = R12; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; PULLTYPE = NONE; }
set_pin_assignment	{ O_rgmii_tx_ctl }		{ LOCATION = R10; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; PULLTYPE = NONE; }
set_pin_assignment	{ O_rgmii_txc }		{ LOCATION = U9; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; PULLTYPE = NONE; }
set_pin_assignment	{ O_phy_rst }			{ LOCATION = V8; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
set_pin_assignment	{ O_tmds_ch0_p }		{ LOCATION = G16; IOSTANDARD = TMDS33; PULLTYPE = NONE; }
set_pin_assignment	{ O_tmds_ch1_p }		{ LOCATION = F17; IOSTANDARD = TMDS33; PULLTYPE = NONE; }
set_pin_assignment	{ O_tmds_ch2_p }		{ LOCATION = H14; IOSTANDARD = TMDS33; PULLTYPE = NONE; }
set_pin_assignment	{ O_tmds_clk_p }		{ LOCATION = C17; IOSTANDARD = TMDS33; PULLTYPE = NONE; }


# PCB/report mode; synchronised to network domain.
set_pin_assignment { I_sw3 } { LOCATION = E11; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }
