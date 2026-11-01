module ph1p_clock;
// <---------------Cut code below this line--------------->
// Clock Aligner  (PH1P_PHY_CLOCK_ALIGNER)
// Used for PH1P35,PH1P50 only
// Anlogic HDL Language Template
PH1P_PHY_CLOCK_ALIGNER #(
  .FIN          ( "100.0000" ), //    No use in fact.Tag refclk frequency.  
  .POST_DIV     ( 0          ), //  0~7.  Post Divide Value, div = 2**POST_DIV.  
  .BYPASS       ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Clock Aligner Bypass Mode, 1'b0:Clock Aligner Mode; 1'b1:Bypass Mode.  
  .FEED_TYPE    ( "INTERNAL" ), //  "INTERNAL", "EXTERNAL".  Clock Aligner Feedback Clk Select, 1'b0:Internal Feedback Clk; 1'b1:External Feedback Clk.  
  .POWER_DOWN   ( "DISABLE"  )  //  "ENABLE", "DISABLE".  Clock Aligner Power Down Mode, 1'b0:Power Down; 1'b1:Power Up.  
)u_PH1P_PHY_CLOCK_ALIGNER(
  .refclk       ( refclk     ), //  1-Bit input. Reference Clk Input.           
  .fbclk        ( fbclk      ), //  1-Bit input. Feedback Clk Input.            
  .rst_n        ( rst_n      ), //  1-Bit input. Rst input.                     
  .clk_out      ( clk_out    ), //  1-Bit output. Calibrated Clk Output.         
  .lock         ( lock       )  //  1-Bit output. Clock Aligner Lock Indicator Output. 
);
//End of u_PH1P_PHY_CLOCK_ALIGNER instantiation




// <---------------Cut code below this line--------------->
// Region Clock  (PH1P_PHY_LCLK)
// Used for PH1P100 only
// Anlogic HDL Language Template
PH1P_PHY_LCLK #(
  .CEMD         ( "SYNC"     ), //  "SYNC" , "ASYNC".  Synchronous asynchronous selection.  
  .CLKSEL       ( "ORG"      ), //  "ORG" , "INV".  Clock select.  
  .DIV          ( "1"        ), //  "1", "2", "3", "4", "5", "6", "7", "8", "3P5".  Frequency division coefficient.  
  .LCLK         ( "BYPASS"   ), //  "BYPASS" , "DIV2TO8" , "DIV1" , "GND".  Clkout Output selection mode.  
  .GSR          ( "ENABLE"   )  //  "ENABLE", "DISABLE".  Global reset enable.  
)u_PH1P_PHY_LCLK(
  .ce           ( ce         ), //  1-Bit input.                                
  .rst          ( rst        ), //  1-Bit input.                                
  .clkin        ( clkin      ), //  1-Bit input.                                
  .clkout       ( clkout     ), //  1-Bit output.                                
  .clkdivout    ( clkdivout  )  //  1-Bit output.                                
);
//End of u_PH1P_PHY_LCLK instantiation




// <---------------Cut code below this line--------------->
// General Clock Buffer  (PH1P_LOGIC_BUFG)
// Anlogic HDL Language Template
PH1P_LOGIC_BUFG u_PH1P_LOGIC_BUFG(
  .o            ( o          ), //  1-Bit output. BUFG output port.              
  .i            ( i          )  //  1-Bit input. BUFG input port.               
);
//End of u_PH1P_LOGIC_BUFG instantiation




// <---------------Cut code below this line--------------->
// Global Clock Select  (PH1P_PHY_GCLK)
// Anlogic HDL Language Template
PH1P_PHY_GCLK #(
  .PRESELECT    ( "CLK0"     ), //  "CLK0", "CLK1".  Initial clock output selection.  
  .HOLD         ( "YES"      ), //  "YES", "NO".  Output hold setting.  
  .SEL_TRIGGER  ( "POS"      ), //  "POS", "NEG.  Sampling edge selection.  
  .GSR          ( "ENABLE"   )  //  "ENABLE", "DISABLE".  Global reset enable.  
)u_PH1P_PHY_GCLK(
  .seln         ( seln       ), //  2-Bit input.                                
  .cen          ( cen        ), //  2-Bit input.                                
  .drct         ( drct       ), //  2-Bit input.                                
  .clkin        ( clkin      ), //  2-Bit input.                                
  .clkout       ( clkout     )  //  1-Bit output.                                
);
//End of u_PH1P_PHY_GCLK instantiation




// <---------------Cut code below this line--------------->
// IO Clock  (PH1P_PHY_IOCLK)
// Anlogic HDL Language Template
PH1P_PHY_IOCLK u_PH1P_PHY_IOCLK(
  .clkin        ( clkin      ), //  1-Bit input.                                
  .clkout       ( clkout     )  //  1-Bit output.                                
);
//End of u_PH1P_PHY_IOCLK instantiation




// <---------------Cut code below this line--------------->
// Multi-zone Clock for  (PH1P_PHY_MLCLK)
// Anlogic HDL Language Template
PH1P_PHY_MLCLK #(
  .GSR          ( "ENABLE"   ), //  "ENABLE", "DISABLE".        
  .BYPASS       ( "ENABLE"   )  //  "ENABLE", "DISABLE".        
)u_PH1P_PHY_MLCLK(
  .ce           ( ce         ), //  1-Bit input.                                
  .clkin        ( clkin      ), //  1-Bit input.                                
  .clkout       ( clkout     )  //  1-Bit output.                                
);
//End of u_PH1P_PHY_MLCLK instantiation




// <---------------Cut code below this line--------------->
// OSC Clock SIP (PH1P_PHY_OSC)
// Anlogic HDL Language Template
PH1P_PHY_OSC u_PH1P_PHY_OSC(
  .stdby        ( stdby      ), //  1-Bit input.                                
  .osc_loop_dis ( osc_loop_dis )  //  1-Bit input.                                
);
//End of u_PH1P_PHY_OSC instantiation




// <---------------Cut code below this line--------------->
// OSC Divider  (PH1P_PHY_OSCDIV)
// Anlogic HDL Language Template
PH1P_PHY_OSCDIV u_PH1P_PHY_OSCDIV(
  .rstn         ( rstn       ), //  1-Bit input. OSCDIV reset,low effective.    
  .stdby        ( stdby      ), //  1-Bit input. OSCDIV output control signals,stdby=1'b1,clock pause output;stdby=1'b0,clock output. 
  .div          ( div        ), //  7-Bit input. OSCDIV output divider control signals. 
  .osc_clk      ( osc_clk    )  //  1-Bit output. OSCDIV clock output.           
);
//End of u_PH1P_PHY_OSCDIV instantiation




// <---------------Cut code below this line--------------->
// Physical phase-locked loop  (PH1P_PHY_PLL)
// Used for PH1P100 only
// Anlogic HDL Language Template
PH1P_PHY_PLL #(
  .FBKCLK       ( "CLKC0_EXT" ), //  CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT.    
  .FBKCLK_INT   ( "VCO_PHASE0" ), //  CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT.    
  .FIN          ( "100.0000" ), //    No use in fact.Tag refclk frequency.  
  .REFCLK_DIV   ( 1          ), //  1~128.  Reference clock frequency division.  
  .FBCLK_DIV    ( 1          ), //  1~128.  Feedback clock frequency division.  
  .CLKC0_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 0.  
  .CLKC1_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 1.  
  .CLKC2_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 2.  
  .CLKC3_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 3.  
  .CLKC4_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 4.  
  .CLKC5_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 5.  
  .CLKC6_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 6.  
  .PREDIV_MUXC0 ( "VCO"      ), //  "VCO", "CLKC_INT_MAIN", "REFCLK".  Clock source selection control for output path 0 divider.  
  .PREDIV_MUXC1 ( "VCO"      ), //  "VCO", "CLKC0_INT", "HIGH", "REFCLK".  Clock source selection control for output path 1 divider.  
  .PREDIV_MUXC2 ( "VCO"      ), //  "VCO", "CLKC1_INT", "HIGH", "REFCLK".  Clock source selection control for output path 2 divider.  
  .PREDIV_MUXC3 ( "VCO"      ), //  "VCO", "CLKC2_INT", "HIGH", "REFCLK".  Clock source selection control for output path 3 divider.  
  .PREDIV_MUXC4 ( "VCO"      ), //  "VCO", "CLKC3_INT", "HIGH", "REFCLK".  Clock source selection control for output path 4 divider.  
  .PREDIV_MUXC5 ( "VCO"      ), //  "VCO", "CLKC4_INT", "HIGH", "REFCLK".  Clock source selection control for output path 5 divider.  
  .PREDIV_MUXC6 ( "VCO"      ), //  "VCO", "CLKC5_INT", "HIGH", "REFCLK".  Clock source selection control for output path 6 divider.  
  .CLKC0_CPHASE ( 0          ), //  0~127.  Output path 0 divider initial value control for coarse phase adjustment.  
  .CLKC1_CPHASE ( 0          ), //  0~127.  Output path 1 divider initial value control for coarse phase adjustment.  
  .CLKC2_CPHASE ( 0          ), //  0~127.  Output path 2 divider initial value control for coarse phase adjustment.  
  .CLKC3_CPHASE ( 0          ), //  0~127.  Output path 3 divider initial value control for coarse phase adjustment.  
  .CLKC4_CPHASE ( 0          ), //  0~127.  Output path 4 divider initial value control for coarse phase adjustment.  
  .CLKC5_CPHASE ( 0          ), //  0~127.  Output path 5 divider initial value control for coarse phase adjustment.  
  .CLKC6_CPHASE ( 0          ), //  0~127.  Output path 6 divider initial value control for coarse phase adjustment.  
  .CLKC0_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 0, 1=div1, 128=div128.  
  .CLKC1_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 1, 1=div1, 128=div128.  
  .CLKC2_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 2, 1=div1, 128=div128.  
  .CLKC3_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 3, 1=div1, 128=div128.  
  .CLKC4_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 4, 1=div1, 128=div128.  
  .CLKC5_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 5, 1=div1, 128=div128.  
  .CLKC6_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 6, 1=div1, 128=div128.  
  .CLKC0_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 0, range={1,CLKC0_DIV-1}; when CLKC0_DIV=1, this parameter no use.  
  .CLKC1_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 1, range={1,CLKC1_DIV-1}; when CLKC1_DIV=1, this parameter no use.  
  .CLKC2_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 2, range={1,CLKC2_DIV-1}; when CLKC2_DIV=1, this parameter no use.  
  .CLKC3_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 3, range={1,CLKC3_DIV-1}; when CLKC3_DIV=1, this parameter no use.  
  .CLKC4_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 4, range={1,CLKC4_DIV-1}; when CLKC4_DIV=1, this parameter no use.  
  .CLKC5_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 5, range={1,CLKC5_DIV-1}; when CLKC5_DIV=1, this parameter no use.  
  .CLKC6_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 6, range={1,CLKC6_DIV-1}; when CLKC6_DIV=1, this parameter no use.  
  .DIVOUT_MUXC0 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 0 output source selection control.  
  .DIVOUT_MUXC1 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 1 output source selection control.  
  .DIVOUT_MUXC2 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 2 output source selection control.  
  .DIVOUT_MUXC3 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 3 output source selection control.  
  .DIVOUT_MUXC4 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 4 output source selection control.  
  .DIVOUT_MUXC5 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 5 output source selection control.  
  .DIVOUT_MUXC6 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 6 output source selection control.  
  .CLKC0_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 0 divider enable control.  
  .CLKC1_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 1 divider enable control.  
  .CLKC2_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 2 divider enable control.  
  .CLKC3_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 3 divider enable control.  
  .CLKC4_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 4 divider enable control.  
  .CLKC5_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 5 divider enable control.  
  .CLKC6_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 6 divider enable control.  
  .WORK_MODE    ( "USER"     ), //  "USER", "LOCK_BEFORE_WAKE_UP".  Work mode.  
  .PD_DIG       ( "ENABLE"   ), //  "ENABLE", "DISABLE".  Default setting ENABLE.  
  .PLL_USR_RST  ( "ENABLE"   ), //  "ENABLE", "DISABLE".  PLL user reset enable control.  
  .PLL_FEED_TYPE ( "INTERNAL" ), //  "INTERNAL", "EXTERNAL".  PLL feedback mode selection control.  
  .PLL_FASTLOOP ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL fastloop mode selection control.  
  .LPF_RES      ( 3          ), //  0~3.  Parameters related to bandwidth settings.  
  .LPF_CAP      ( 3          ), //  0~31.  Parameters related to bandwidth settings.  
  .ICP_CUR      ( 1          ), //  0~31.  Parameters related to bandwidth settings.  
  .FRAC_ENABLE  ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Fractional frequency division enable.  
  .SDM_FRAC     ( 0          ), //  0~(2^24-1).  PLL feedback divider ratio fractional value control. Fractional value=SDM_FRAC/2^24.  
  .PHASE_PATH_SEL ( 0          ), //  0~7.  Selection of output path in dynamic fine phase adjustment.  
  .DYN_PHASE_PATH_SEL ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL dynamic phase adjustment enable.  
  .DYN_FPHASE_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL dynamic fine phase adjustment enable.  
  .CLKC0_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 0. Set 0 when CLKC0_FPHASE=0~3, set 1 when CLKC0_FPHASE=4~7.  
  .CLKC1_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 1. Set 0 when CLKC1_FPHASE=0~3, set 1 when CLKC1_FPHASE=4~7.  
  .CLKC2_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 2. Set 0 when CLKC2_FPHASE=0~3, set 1 when CLKC2_FPHASE=4~7.  
  .CLKC3_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 3. Set 0 when CLKC3_FPHASE=0~3, set 1 when CLKC3_FPHASE=4~7.  
  .CLKC4_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 4. Set 0 when CLKC4_FPHASE=0~3, set 1 when CLKC4_FPHASE=4~7.  
  .CLKC5_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 5. Set 0 when CLKC5_FPHASE=0~3, set 1 when CLKC5_FPHASE=4~7.  
  .CLKC6_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 6. Set 0 when CLKC6_FPHASE=0~3, set 1 when CLKC6_FPHASE=4~7.  
  .CLKC0_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC0 50% duty cycle enable control.  
  .CLKC1_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC1 50% duty cycle enable control.  
  .CLKC2_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC2 50% duty cycle enable control.  
  .CLKC3_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC3 50% duty cycle enable control.  
  .CLKC4_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC4 50% duty cycle enable control.  
  .CLKC5_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC5 50% duty cycle enable control.  
  .CLKC6_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC6 50% duty cycle enable control.  
  .SSC_ENABLE   ( "DISABLE"  ), //  "ENABLE", "DISABLE".  SSC mode enable.  
  .SSC_RST      ( "ENABLE"   ), //  "ENABLE", "DISABLE".  SSC reset enable control.  
  .SSC_MODE     ( "CENTER"   ), //  "UP", "DOWN", "CENTER".  SSC mode selection.  
  .SSC_FREQ_DIV ( 0          ), //  0~(2^18-1).  SSC triangle modulation frequency control.  
  .SSC_RNGE     ( 242        ), //  0~(2^24-1).  SSC triangle modulation amplitude control.  
  .REFCLK_DET_BYP ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Reference clock detection bypass enable."DISABLE":enable detection; "ENABLE":bypass detection.  
  .CLKC0_FRAC_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Path 0 Fractional 1/8 div function enable. If this is enabled, PI_OUT_SEL should be "NORMAL".  
  .CLKC0_FRAC   ( 0          ), //  0~7.  1/8 fraction div control for path 0. 0 for no fracn; 1 for 1/8; 2 for 2/8; 3 for 3/8; 4 for -4/8; 5 for -3/8; 6 for -2/8; 7 for -1/8.  
  .PI_OUT_SEL   ( "NORMAL"   ), //  "NORMAL", "PI".  Select clock source for path 0. PI output is only used for fine phase shift.  
  .PI_FRAC_EN   ( "DISABLE"  ), //  "ENABLE", "DISABLE".  "ENABLE" for output path 0 fractional divide mode; "DISABLE" for fine phase shift mode.  
  .CLKC0_PI_SHIFT_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output path 0 phase shifter by PI enable.  
  .FEEDBK_MODE  ( "NORMAL"   ), //  "NORMAL", "SOURCESYNC", "NOCOMP", "ZERODELAY".  No use in fact.Tag feedback mode.  
  .DYN_CPHASE_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL dynamic coarse phase adjustment enable.  
  .PADDRW       ( 32         ),                                 
  .PDATAW       ( 32         )                                  
)u_PH1P_PHY_PLL(
  .refclk       ( refclk     ), //  1-Bit input. PLL reference clock input.     
  .fbclk        ( fbclk      ), //  1-Bit input. PLL feedback clock input.      
  .clkc         ( clkc       ), //  7-Bit output. PLL clock output.              
  .clkcb        ( clkcb      ), //  7-Bit output. PLL clock output, inverse with clkc. 
  .lock         ( lock       ), //  1-Bit output. PLL locks output, high active. 
  .pllreset     ( pllreset   ), //  1-Bit input. PLL reset, high active.        
  .clkc_rst     ( clkc_rst   ), //  2-Bit input. Output clock reset, high active. clkc_rst[0] for clkc[0:3], clkc_rst[1] for clkc[4:6]. 
  .refclk_rst   ( refclk_rst ), //  1-Bit input. PLL reference clock reset.     
  .wakeup       ( wakeup     ), //  1-Bit input. PLL wakeup_sync, Switching from internal feedback to external feedback enable under lock before mode. 
  .clkc_en      ( clkc_en    ), //  7-Bit input. Output clock enable.           
  .cps_step     ( cps_step   ), //  1-Bit input. Dynamic phase coarse adjustment control. 
  .pllpd        ( pllpd      ), //  1-Bit input. PLL power switch, high for PLL power down. 
  .psclk        ( psclk      ), //  1-Bit input. Dynamic phase adjustment clock. 
  .psclksel     ( psclksel   ), //  3-Bit input. Output path selection for dynamic phase adjustment. 0 to 6 correspond to clkc[0] to clkc[6]. 
  .psstep       ( psstep     ), //  1-Bit input. Dynamic fine phase adjustment trigger signal, high active. 
  .psdown       ( psdown     ), //  1-Bit input. Dynamic phase shift mode, low for left shift, high for right shift. 
  .psdone       ( psdone     ), //  1-Bit output. Dynamic phase shift finish flag. 
  .drp_clk      ( drp_clk    ), //  1-Bit input. Configure the clock input dynamically. 
  .drp_rstn     ( drp_rstn   ), //  1-Bit input. Dynamic configuration reset signal, low level reset. 
  .drp_sel      ( drp_sel    ), //  1-Bit input. Dynamic configuration chip selective signal input, high active. 
  .drp_rd       ( drp_rd     ), //  1-Bit input. Dynamic configuration read enable signal, high active. 
  .drp_wr       ( drp_wr     ), //  1-Bit input. Dynamic configuration write enable signal, high active. 
  .drp_addr     ( drp_addr   ), //  8-Bit input. Dynamically configure the write address signal. 
  .drp_wdata    ( drp_wdata  ), //  8-Bit input. Configure data input signals dynamically. 
  .drp_err      ( drp_err    ), //  1-Bit output. Dynamic configuration error flag bit, high active. 
  .drp_rdy      ( drp_rdy    ), //  1-Bit output. Configure the read end flag dynamically. 
  .drp_rdata    ( drp_rdata  ), //  8-Bit output. Dynamically configure the data read port. 
  .ssc_reset    ( ssc_reset  ), //  1-Bit input. Spread Frequency Enable reset signal, high active. It needs fixed to high when using SSC. 
  .scan_clk     ( scan_clk   ), //  1-Bit input. DFT Scan CLK Input.            
  .scan_enable  ( scan_enable ), //  1-Bit input. DFT Scan Enable Input.         
  .scan_mode    ( scan_mode  ), //  1-Bit input. DFT Scan Mode Input.           
  .scan_resetn  ( scan_resetn )  //  1-Bit input. DFT Scan Rst Input.            
);
//End of u_PH1P_PHY_PLL instantiation




// <---------------Cut code below this line--------------->
// Physical phase-locked loop  (PH1P_PHY_PLL_V2)
// Used for PH1P35,PH1P50 only
// Anlogic HDL Language Template
PH1P_PHY_PLL_V2 #(
  .FBKCLK       ( "CLKC0_EXT" ), //  CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT.    
  .FBKCLK_INT   ( "VCO_PHASE0" ), //  CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT,.    
  .FIN          ( "100.0000" ), //    No use in fact.Tag refclk frequency.  
  .REFCLK_DIV   ( 1          ), //  1~128.  Reference clock frequency division.  
  .FBCLK_DIV    ( 1          ), //  1~128.  Feedback clock frequency division.  
  .CLKC0_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 0.  
  .CLKC1_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 1.  
  .CLKC2_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 2.  
  .CLKC3_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 3.  
  .CLKC4_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 4.  
  .CLKC5_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 5.  
  .CLKC6_FPHASE ( 0          ), //  0~7.  Output phase fine adjustment parameters of clock 6.  
  .PREDIV_MUXC0 ( "VCO"      ), //  "VCO", "CLKC_INT_MAIN", "REFCLK".  Clock source selection control for output path 0 divider.  
  .PREDIV_MUXC1 ( "VCO"      ), //  "VCO", "CLKC0_INT", "HIGH", "REFCLK".  Clock source selection control for output path 1 divider.  
  .PREDIV_MUXC2 ( "VCO"      ), //  "VCO", "CLKC1_INT", "HIGH", "REFCLK".  Clock source selection control for output path 2 divider.  
  .PREDIV_MUXC3 ( "VCO"      ), //  "VCO", "CLKC2_INT", "HIGH", "REFCLK".  Clock source selection control for output path 3 divider.  
  .PREDIV_MUXC4 ( "VCO"      ), //  "VCO", "CLKC3_INT", "HIGH", "REFCLK".  Clock source selection control for output path 4 divider.  
  .PREDIV_MUXC5 ( "VCO"      ), //  "VCO", "CLKC4_INT", "HIGH", "REFCLK".  Clock source selection control for output path 5 divider.  
  .PREDIV_MUXC6 ( "VCO"      ), //  "VCO", "CLKC5_INT", "HIGH", "REFCLK".  Clock source selection control for output path 6 divider.  
  .CLKC0_CPHASE ( 0          ), //  0~127.  Output path 0 divider initial value control for coarse phase adjustment.  
  .CLKC1_CPHASE ( 0          ), //  0~127.  Output path 1 divider initial value control for coarse phase adjustment.  
  .CLKC2_CPHASE ( 0          ), //  0~127.  Output path 2 divider initial value control for coarse phase adjustment.  
  .CLKC3_CPHASE ( 0          ), //  0~127.  Output path 3 divider initial value control for coarse phase adjustment.  
  .CLKC4_CPHASE ( 0          ), //  0~127.  Output path 4 divider initial value control for coarse phase adjustment.  
  .CLKC5_CPHASE ( 0          ), //  0~127.  Output path 5 divider initial value control for coarse phase adjustment.  
  .CLKC6_CPHASE ( 0          ), //  0~127.  Output path 6 divider initial value control for coarse phase adjustment.  
  .CLKC0_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 0, 1=div1, 128=div128.  
  .CLKC1_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 1, 1=div1, 128=div128.  
  .CLKC2_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 2, 1=div1, 128=div128.  
  .CLKC3_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 3, 1=div1, 128=div128.  
  .CLKC4_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 4, 1=div1, 128=div128.  
  .CLKC5_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 5, 1=div1, 128=div128.  
  .CLKC6_DIV    ( 1          ), //  1~128.  Output divide ratio for clock 6, 1=div1, 128=div128.  
  .CLKC0_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 0, range={1,CLKC0_DIV-1}; when CLKC0_DIV=1, this parameter no use.  
  .CLKC1_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 1, range={1,CLKC1_DIV-1}; when CLKC1_DIV=1, this parameter no use.  
  .CLKC2_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 2, range={1,CLKC2_DIV-1}; when CLKC2_DIV=1, this parameter no use.  
  .CLKC3_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 3, range={1,CLKC3_DIV-1}; when CLKC3_DIV=1, this parameter no use.  
  .CLKC4_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 4, range={1,CLKC4_DIV-1}; when CLKC4_DIV=1, this parameter no use.  
  .CLKC5_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 5, range={1,CLKC5_DIV-1}; when CLKC5_DIV=1, this parameter no use.  
  .CLKC6_DUTY_INT ( 1          ), //  1~127.  Output clock duty cycle control for path 6, range={1,CLKC6_DIV-1}; when CLKC6_DIV=1, this parameter no use.  
  .DIVOUT_MUXC0 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 0 output source selection control.  
  .DIVOUT_MUXC1 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 1 output source selection control.  
  .DIVOUT_MUXC2 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 2 output source selection control.  
  .DIVOUT_MUXC3 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 3 output source selection control.  
  .DIVOUT_MUXC4 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 4 output source selection control.  
  .DIVOUT_MUXC5 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 5 output source selection control.  
  .DIVOUT_MUXC6 ( "DIV"      ), //  "DIV", "REFCLK".  Clock output path 6 output source selection control.  
  .CLKC0_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 0 divider enable control.  
  .CLKC1_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 1 divider enable control.  
  .CLKC2_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 2 divider enable control.  
  .CLKC3_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 3 divider enable control.  
  .CLKC4_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 4 divider enable control.  
  .CLKC5_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 5 divider enable control.  
  .CLKC6_ENABLE ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output clock path 6 divider enable control.  
  .WORK_MODE    ( "USER"     ), //  "USER", "LOCK_BEFORE_WAKE_UP".  Work mode.  
  .PD_DIG       ( "ENABLE"   ), //  "ENABLE", "DISABLE".  Default setting ENABLE.  
  .PLL_USR_RST  ( "ENABLE"   ), //  "ENABLE", "DISABLE".  PLL user reset enable control.  
  .PLL_FEED_TYPE ( "INTERNAL" ), //  "INTERNAL", "EXTERNAL".  PLL feedback mode selection control.  
  .PLL_FASTLOOP ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL fastloop mode selection control.  
  .LPF_RES      ( 3          ), //  0~3.  Parameters related to bandwidth settings.  
  .LPF_CAP      ( 3          ), //  0~31.  Parameters related to bandwidth settings.  
  .ICP_CUR      ( 1          ), //  0~31.  Parameters related to bandwidth settings.  
  .FRAC_ENABLE  ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Fractional frequency division enable.  
  .SDM_FRAC     ( 0          ), //  0~(2^28-1).  PLL feedback divider ratio fractional value control. Fractional value=SDM_FRAC/2^28.  
  .PHASE_PATH_SEL ( 0          ), //  0~7.  Selection of output path in dynamic fine phase adjustment.  
  .DYN_PHASE_PATH_SEL ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL dynamic phase adjustment enable.  
  .DYN_FPHASE_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL dynamic fine phase adjustment enable.  
  .CLKC0_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 0. Set 0 when CLKC0_FPHASE=0~3, set 1 when CLKC0_FPHASE=4~7.  
  .CLKC1_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 1. Set 0 when CLKC1_FPHASE=0~3, set 1 when CLKC1_FPHASE=4~7.  
  .CLKC2_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 2. Set 0 when CLKC2_FPHASE=0~3, set 1 when CLKC2_FPHASE=4~7.  
  .CLKC3_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 3. Set 0 when CLKC3_FPHASE=0~3, set 1 when CLKC3_FPHASE=4~7.  
  .CLKC4_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 4. Set 0 when CLKC4_FPHASE=0~3, set 1 when CLKC4_FPHASE=4~7.  
  .CLKC5_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 5. Set 0 when CLKC5_FPHASE=0~3, set 1 when CLKC5_FPHASE=4~7.  
  .CLKC6_FPHASE_RSTSEL ( 0          ), //  0, 1.  Divider reset release clock phase selection for output path 6. Set 0 when CLKC6_FPHASE=0~3, set 1 when CLKC6_FPHASE=4~7.  
  .CLKC0_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC0 50% duty cycle enable control.  
  .CLKC1_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC1 50% duty cycle enable control.  
  .CLKC2_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC2 50% duty cycle enable control.  
  .CLKC3_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC3 50% duty cycle enable control.  
  .CLKC4_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC4 50% duty cycle enable control.  
  .CLKC5_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC5 50% duty cycle enable control.  
  .CLKC6_DUTY50 ( "ENABLE"   ), //  "ENABLE", "DISABLE".  CLKC6 50% duty cycle enable control.  
  .SSC_ENABLE   ( "DISABLE"  ), //  "ENABLE", "DISABLE".  SSC mode enable.  
  .SSC_RST      ( "ENABLE"   ), //  "ENABLE", "DISABLE".  SSC reset enable control.  
  .SSC_MODE     ( "CENTER"   ), //  "UP", "DOWN", "CENTER".  SSC mode selection.  
  .SSC_FREQ_DIV ( 0          ), //  0~(2^18-1).  SSC triangle modulation frequency control.  
  .SSC_RNGE     ( 242        ), //  0~(2^24-1).  SSC triangle modulation amplitude control.  
  .REFCLK_DET_BYP ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Reference clock detection bypass enable."DISABLE":enable detection; "ENABLE":bypass detection.  
  .CLKC0_FRAC_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Path 0 Fractional 1/8 div function enable. If this is enabled, PI_OUT_SEL should be "NORMAL".  
  .CLKC0_FRAC   ( 0          ), //  0~7.  1/8 fraction div control for path 0. 0 for no fracn; 1 for 1/8; 2 for 2/8; 3 for 3/8; 4 for -4/8; 5 for -3/8; 6 for -2/8; 7 for -1/8.  
  .PI_OUT_SEL   ( "NORMAL"   ), //  "NORMAL", "PI".  Select clock source for path 0. PI output is only used for fine phase shift.  
  .PI_FRAC_EN   ( "DISABLE"  ), //  "ENABLE", "DISABLE".  "ENABLE" for output path 0 fractional divide mode; "DISABLE" for fine phase shift mode.  
  .CLKC0_PI_SHIFT_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  Output path 0 phase shifter by PI enable.  
  .FEEDBK_MODE  ( "NORMAL"   ), //  "NORMAL", "SOURCESYNC", "NOCOMP", "ZERODELAY".  No use in fact.Tag feedback mode.  
  .DYN_CPHASE_EN ( "DISABLE"  ), //  "ENABLE", "DISABLE".  PLL dynamic coarse phase adjustment enable.  
  .PADDRW       ( 32         ),                                 
  .PDATAW       ( 32         )                                  
)u_PH1P_PHY_PLL_V2(
  .refclk       ( refclk     ), //  1-Bit input. PLL reference clock input.     
  .fbclk        ( fbclk      ), //  1-Bit input. PLL feedback clock input.      
  .clkc         ( clkc       ), //  7-Bit output. PLL clock output.              
  .clkcb        ( clkcb      ), //  7-Bit output. PLL clock output, inverse with clkc. 
  .lock         ( lock       ), //  1-Bit output. PLL locks output, high active. 
  .pllreset     ( pllreset   ), //  1-Bit input. PLL reset, high active.        
  .clkc_rst     ( clkc_rst   ), //  2-Bit input. Output clock reset, high active. clkc_rst[0] for clkc[0:3], clkc_rst[1] for clkc[4:6]. 
  .refclk_rst   ( refclk_rst ), //  1-Bit input. PLL reference clock reset.     
  .wakeup       ( wakeup     ), //  1-Bit input. PLL wakeup_sync, Switching from internal feedback to external feedback enable under lock before mode. 
  .clkc_en      ( clkc_en    ), //  7-Bit input. Output clock enable.           
  .cps_step     ( cps_step   ), //  1-Bit input. Dynamic phase coarse adjustment control. 
  .pllpd        ( pllpd      ), //  1-Bit input. PLL power switch, high for PLL power down. 
  .psclk        ( psclk      ), //  1-Bit input. Dynamic phase adjustment clock. 
  .psclksel     ( psclksel   ), //  3-Bit input. Output path selection for dynamic phase adjustment. 0 to 6 correspond to clkc[0] to clkc[6]. 
  .psstep       ( psstep     ), //  1-Bit input. Dynamic fine phase adjustment trigger signal, high active. 
  .psdown       ( psdown     ), //  1-Bit input. Dynamic phase shift mode, low for left shift, high for right shift. 
  .psdone       ( psdone     ), //  1-Bit output. Dynamic phase shift finish flag. 
  .drp_clk      ( drp_clk    ), //  1-Bit input. Configure the clock input dynamically. 
  .drp_rstn     ( drp_rstn   ), //  1-Bit input. Dynamic configuration reset signal, low level reset. 
  .drp_sel      ( drp_sel    ), //  1-Bit input. Dynamic configuration chip selective signal input, high active. 
  .drp_rd       ( drp_rd     ), //  1-Bit input. Dynamic configuration read enable signal, high active. 
  .drp_wr       ( drp_wr     ), //  1-Bit input. Dynamic configuration write enable signal, high active. 
  .drp_addr     ( drp_addr   ), //  8-Bit input. Dynamically configure the write address signal. 
  .drp_wdata    ( drp_wdata  ), //  8-Bit input. Configure data input signals dynamically. 
  .drp_err      ( drp_err    ), //  1-Bit output. Dynamic configuration error flag bit, high active. 
  .drp_rdy      ( drp_rdy    ), //  1-Bit output. Configure the read end flag dynamically. 
  .drp_rdata    ( drp_rdata  ), //  8-Bit output. Dynamically configure the data read port. 
  .ssc_reset    ( ssc_reset  ), //  1-Bit input. Spread Frequency Enable reset signal, high active. It needs fixed to high when using SSC. 
  .scan_clk     ( scan_clk   ), //  1-Bit input. DFT Scan CLK Input.            
  .scan_enable  ( scan_enable ), //  1-Bit input. DFT Scan Enable Input.         
  .scan_mode    ( scan_mode  ), //  1-Bit input. DFT Scan Mode Input.           
  .scan_resetn  ( scan_resetn )  //  1-Bit input. DFT Scan Rst Input.            
);
//End of u_PH1P_PHY_PLL_V2 instantiation




// <---------------Cut code below this line--------------->
// Sector Clock  (PH1P_PHY_SCLK)
// Used for PH1P100 only
// Anlogic HDL Language Template
PH1P_PHY_SCLK #(
  .GSR          ( "ENABLE"   ), //  "ENABLE", "DISABLE".        
  .BYPASS       ( "ENABLE"   ), //  "ENABLE", "DISABLE".        
  .DELAY        ( 0          )  //  0~3.                        
)u_PH1P_PHY_SCLK(
  .ce           ( ce         ), //  1-Bit input.                                
  .clkin        ( clkin      ), //  1-Bit input.                                
  .clkout       ( clkout     )  //  1-Bit output.                                
);
//End of u_PH1P_PHY_SCLK instantiation




// <---------------Cut code below this line--------------->
// Sector Clock  (PH1P_PHY_SCLK_V2)
// Used for PH1P35,PH1P50 only
// Anlogic HDL Language Template
PH1P_PHY_SCLK_V2 #(
  .GSR          ( "ENABLE"   ), //  "ENABLE", "DISABLE".        
  .BYPASS       ( "ENABLE"   ), //  "ENABLE", "DISABLE".        
  .DELAY        ( 0          ), //  0~3.                        
  .DELAY_DYN    ( "DISABLE"  )  //  "ENABLE", "DISABLE".        
)u_PH1P_PHY_SCLK_V2(
  .ce           ( ce         ), //  1-Bit input.                                
  .clkin        ( clkin      ), //  1-Bit input.                                
  .dlytrim      ( dlytrim    ), //  2-Bit input.                                
  .clkout       ( clkout     )  //  1-Bit output.                                
);
//End of u_PH1P_PHY_SCLK_V2 instantiation




// <---------------Cut code below this line--------------->
// Horizontal Clock Buffer  (PH1P_PHY_HCLK)
// Anlogic HDL Language Template
PH1P_PHY_HCLK #(
  .GSR          ( "ENABLE"   ), //  "ENABLE","DISABLE".  Global reset enable.  
  .BYPASS       ( "ENABLE"   ), //  "ENABLE","DISABLE".  Input directly connected to output enable function.  
  .DELAY        ( 0          )  //  0~3.  Delay parameter.      
)u_PH1P_PHY_HCLK(
  .ce           ( ce         ), //  1-Bit input. Input clock enable.            
  .clkin        ( clkin      ), //  1-Bit input. Input clock.                   
  .clkout       ( clkout     )  //  1-Bit output. Output clock.                  
);
//End of u_PH1P_PHY_HCLK instantiation




endmodule
