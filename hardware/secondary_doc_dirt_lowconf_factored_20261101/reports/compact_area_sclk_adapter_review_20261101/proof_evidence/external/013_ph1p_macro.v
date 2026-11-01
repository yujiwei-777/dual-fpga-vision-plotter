module PH1P_LOGIC_SEQ_DIV (
  clk,
  rst,
  start,
  numer,
  denom,
  quotient,
  remain,
  done
);
  parameter NUMER_WIDTH = 16;               
  parameter DENOM_WIDTH = 16;               
  input                     clk;            
  input                     rst;            
  input                     start;          
  input  [NUMER_WIDTH-1:0]  numer;          
  input  [DENOM_WIDTH-1:0]  denom;          
  output [NUMER_WIDTH-1:0]  quotient;       
  output [DENOM_WIDTH-1:0]  remain;         
  output                    done;           
endmodule
module PH1P_LOGIC_ERAM (
  dia,
  addra, cea, ocea, clka, wea, rsta, bea,
  dib,
  addrb, ceb, oceb, clkb, web, rstb, beb,
  ecc_sbiterrinj, ecc_dbiterrinj,
  doa,
  dob,
  ecc_sbiterr,
  ecc_dbiterr
  );
  parameter DATA_WIDTH_A = 20;                                              
  parameter DATA_WIDTH_B = DATA_WIDTH_A;                                    
  parameter ADDR_WIDTH_A = 10;                                              
  parameter ADDR_WIDTH_B = ADDR_WIDTH_A;                                    
  parameter DATA_DEPTH_A = 2 ** ADDR_WIDTH_A;                               
  parameter DATA_DEPTH_B = 2 ** ADDR_WIDTH_B;                               
  parameter BYTE_ENABLE = 0;                                                
  parameter BYTE_A = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_A / BYTE_ENABLE;     
  parameter BYTE_B = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_B / BYTE_ENABLE;     
  output  ecc_sbiterr;                                                      
  output  ecc_dbiterr;                                                      
  output  [DATA_WIDTH_A-1:0] doa;                                           
  output  [DATA_WIDTH_B-1:0] dob;                                           
  input   [DATA_WIDTH_A-1:0] dia;                                           
  input   [DATA_WIDTH_B-1:0] dib;                                           
  input   ecc_sbiterrinj, ecc_dbiterrinj;                                   
  input   cea;                                                              
  input   ocea;                                                             
  input   clka;                                                             
  input   wea;                                                              
  input   rsta;                                                             
  input   ceb;                                                              
  input   oceb;                                                             
  input   clkb;                                                             
  input   web;                                                              
  input   rstb;                                                             
  input [BYTE_A - 1 : 0] bea;                                               
  input [BYTE_B - 1 : 0] beb;                                               
  input   [ADDR_WIDTH_A-1:0] addra;                                         
  input   [ADDR_WIDTH_B-1:0] addrb;                                         
  parameter MODE = "DP";                     // "DP", "SP", "PDPW", "FIFO".
  parameter REGMODE_A = "NOREG";             // "NOREG", "OUTREG".
  parameter REGMODE_B = "NOREG";             // "NOREG", "OUTREG".
  parameter WRITEMODE_A = "NORMAL";          // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH".
  parameter WRITEMODE_B = "NORMAL";          // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH".
  parameter RESETMODE_A = "ASYNC";           // "SYNC", "ASYNC".
  parameter RESETMODE_B = "ASYNC";           // "SYNC", "ASYNC".
  parameter OREGSET_A = "SET";               // "SET", "RESET".
  parameter OREGSET_B = "SET";               // "SET", "RESET".
  parameter SSROVERCE = "ENABLE";            // "DISABLE", "ENABLE".
  parameter ECC_DECODE = "DISABLE";          // "DISABLE", "ENABLE".
  parameter ECC_ENCODE = "DISABLE";          // "DISABLE", "ENABLE".
  parameter ASYNC_RESET_RELEASE_A = "SYNC";  // "SYNC", "ASYNC".
  parameter ASYNC_RESET_RELEASE_B = "SYNC";  // "SYNC", "ASYNC".
  parameter CLKMODE = "ASYNC";               // "ASYNC", "SYNC".
  parameter DEBUGGABLE = "NO";               // "YES", "NO".
  parameter PACKABLE = "NO";                 // "YES", "NO".
  parameter FORCE_KEEP = "OFF";              // "ON", "OFF".
  parameter INIT_FILE = "NONE";              
  parameter FILL_ALL = "NONE";               
  parameter IMPLEMENT = "20K";               // "20K", "20K(FAST)".
endmodule
module PH1P_LOGIC_DRAM32X16R8 (
 raddr,
 di,
 waddr,
 wclk,
 wrst,
 we,
 rdo
);
input  [5:0]  raddr ;   
input  [15:0] di;       
input  [4:0]  waddr;    
input         wclk;     
input         wrst;     
input         we;       
output [7:0]  rdo ;     
parameter INIT_LUT5A_S0 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S0 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S1 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S1 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S2 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S2 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S3 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S3 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S4 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S4 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S5 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S5 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S6 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S6 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S7 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S7 = 32'h0000_0000;   // DEFAULT 32'h0000.
endmodule
module PH1P_LOGIC_DRAM32X16 (
 raddr,
 di,
 waddr,
 wclk,
 wrst,
 we,
 rdo
);
input  [4:0]  raddr ;   
input  [15:0] di;       
input  [4:0]  waddr;    
input         wclk;     
input         wrst;     
input         we;       
output [15:0] rdo ;     
parameter INIT_LUT5A_S0 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S0 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S1 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S1 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S2 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S2 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S3 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S3 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S4 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S4 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S5 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S5 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S6 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S6 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5A_S7 = 32'h0000_0000;   // DEFAULT 32'h0000.
parameter INIT_LUT5B_S7 = 32'h0000_0000;   // DEFAULT 32'h0000.
endmodule
module PH1P_LOGIC_DRAM64X8R16  (
  raddr,
  di,
  waddr,
  wclk,
  wrst,
  we,
  rdo
);
input  [4:0]  raddr ;   
input  [7:0]  di;       
input  [5:0]  waddr;    
input         wclk;     
input         wrst;     
input         we;       
output [15:0] rdo ;     
parameter INIT_LUT5A_S0 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S0 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S1 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S1 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S2 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S2 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S3 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S3 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S4 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S4 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S5 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S5 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S6 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S6 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S7 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S7 = 32'h0000_0000;    // DEFAULT 32'h0000.
endmodule
module PH1P_LOGIC_DRAM64X8 (
  raddr,
  di,
  waddr,
  wclk,
  wrst,
  we,
  rdo
);
input  [5:0] raddr ;    
input  [7:0] di;        
input  [5:0] waddr;     
input        wclk;      
input        wrst;      
input        we;        
output [7:0] rdo ;      
parameter INIT_LUT5A_S0 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S0 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S1 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S1 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S2 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S2 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S3 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S3 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S4 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S4 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S5 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S5 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S6 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S6 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5A_S7 = 32'h0000_0000;    // DEFAULT 32'h0000.
parameter INIT_LUT5B_S7 = 32'h0000_0000;    // DEFAULT 32'h0000.
endmodule
module PH1P_LOGIC_DRAM (
  di,
  waddr,
  we,
  wclk,
  rclk,
  rrst,
  rce,
  raddr,
  rdoq,
  rdo
  );
  parameter DATA_WIDTH_W = 8;                       // >0.
  parameter DATA_WIDTH_R = DATA_WIDTH_W;            // >0.
  parameter ADDR_WIDTH_W = 6;                       // >0.
  parameter ADDR_WIDTH_R = ADDR_WIDTH_W;            // >0.
  parameter DATA_DEPTH_W = 2 ** ADDR_WIDTH_W;       // >2.
  parameter DATA_DEPTH_R = 2 ** ADDR_WIDTH_R;       // >2.
  parameter INIT_FILE = "NONE";                     
  parameter FILL_ALL = "NONE";                      
  parameter READREG = "DISABLE";                    // "DISABLE", "ENABLE".
  parameter RESETMODE = "SYNC";                     // "SYNC", "ASYNC".
  output  [DATA_WIDTH_R-1:0] rdo;                   
  output  [DATA_WIDTH_R-1:0] rdoq;                  
  input   [DATA_WIDTH_W-1:0] di;                    
  input   we;                                       
  input   wclk;                                     
  input   [ADDR_WIDTH_W-1:0] waddr;                 
  input   [ADDR_WIDTH_R-1:0] raddr;                 
  input   rrst;                                     
  input   rclk;                                     
  input   rce;                                      
endmodule
module PH1P_LOGIC_FIFO(
	clkw, wrst, we, owe, csw, di, fifo_wrpointer, full_flag, afull_flag,
	clkr, rrst, re, ore, csr, dout,fifo_rdpointer, empty_flag, aempty_flag,
	ecc_sbiterr, ecc_dbiterr, ecc_sbiterrinj, ecc_dbiterrinj);
    parameter AE = 96;                      // 0~2^14.
    parameter AF = 96;                      // 0~2^14.
    parameter DATA_WIDTH = 9;               // 1~320.
    parameter ADDR_WIDTH = 10;              // 9~14.
    parameter CLKMODE = "SYNC";             // "SYNC", "ASYNC".
    parameter REGMODE_R = "NOREG";          // "NOREG", "OUTREG".
    parameter SSROVERCE = "DISABLE";        // "ENABLE", "DISABLE".
    parameter ECC_ENCODE = "DISABLE";       // "ENABLE", "DISABLE".
    parameter ECC_DECODE = "DISABLE";       // "ENABLE", "DISABLE".
    parameter FIRSTWRITE_RD = "DISABLE";    // "ENABLE", "DISABLE".
    parameter ASYNC_RESET_RELEASE = "SYNC" ;// "SYNC", "ASYNC".
    input   clkw;                               
    input   wrst;                               
    input   we;                                 
    input   owe;                                
    input   [2:0] csw;                          
    input   [DATA_WIDTH-1:0] di;                
    output  [ADDR_WIDTH-1:0] fifo_wrpointer;    
    output  full_flag;                          
    output  afull_flag;                         
    input    clkr;                              
    input    rrst;                              
    input    re;                                
    input    ore;                               
    input    [2:0] csr;                         
    output   [DATA_WIDTH-1:0] dout;             
    output   [ADDR_WIDTH-1:0] fifo_rdpointer;   
    output  empty_flag;                         
    output  aempty_flag;                        
    output ecc_sbiterr;                         
    output ecc_dbiterr;                         
	input ecc_sbiterrinj;                       
	input ecc_dbiterrinj;                       
endmodule
module  PH1P_LOGIC_BUF(
  o,
  i
);                  // user instantiated logic BUF
output o;           
input i;            
endmodule
module PH1P_LOGIC_MULT (
  p,
  a,
  b,
  cea,
  ceb,
  cepd,
  clk,
  rstan,
  rstbn,
  rstpdn
);
    parameter   INPUT_WIDTH_A       = 18        ; // >0.
    parameter   INPUT_WIDTH_B       = 18        ; // >0.
    parameter   OUTPUT_WIDTH        = 36        ; // >0.
    output      [OUTPUT_WIDTH-1:0]  p           ; 
    input       [INPUT_WIDTH_A-1:0] a           ; 
    input       [INPUT_WIDTH_B-1:0] b           ; 
    input                           cea         ; 
    input                           ceb         ; 
    input                           cepd        ; 
    input                           clk         ; 
    input                           rstan       ; 
    input                           rstbn       ; 
    input                           rstpdn      ; 
    parameter   INPUTFORMAT         = "SIGNED"  ; // "SIGNED", "UNSIGNED".
    parameter   INPUTREGA           = "ENABLE"  ; // "ENABLE", "DISABLE".
    parameter   INPUTREGB           = "ENABLE"  ; // "ENABLE", "DISABLE".
    parameter   OUTPUTREG           = "ENABLE"  ; // "ENABLE", "DISABLE".
    parameter   IMPLEMENT           = "AUTO"    ; // "AUTO", "DSP", "GATE".
    parameter   SRMODE              = "ASYNC"   ; // "ASYNC", "SYNC".
endmodule
module PH1P_LOGIC_RAMFIFO (
  
  // Inputs
  rst,
  di,
  clk,
  re,
  we,
  // Outputs
  dout,
  empty_flag,
  full_flag,
  rdusedw,
  wrusedw
);
   parameter DATA_WIDTH = 8;                    // >0.
   parameter ADDR_WIDTH = 8;                    // >0.
   parameter SHOWAHEAD = 0;                     // 0, 1.
   parameter IMPLEMENT = "20K";                 
   input                     rst;               
   input   [DATA_WIDTH-1:0]  di;                
   input                     re;                
   input                     clk;               
   input                     we;                
   output  [DATA_WIDTH-1:0]  dout;              
   output                    empty_flag;        
   output                    full_flag;         
   output  [ADDR_WIDTH:0]    rdusedw;           
   output  [ADDR_WIDTH:0]    wrusedw;           
endmodule
module PH1P_LOGIC_SHIFTER (
  clk,
  datain,
  dataout,
  depth,
  en
);
parameter DATA_WIDTH = 16;       // >0.
parameter DEPTH_WIDTH = 2;       // >0.
parameter SHIFT_TYPE = "FIXED";  // "FIXED".
parameter DATA_DEPTH = 32;       // >0
parameter INIT_FILE = "NONE";    
input                               clk;        
input                               en;         
input       [DATA_WIDTH-1:0]        datain;     
input       [DEPTH_WIDTH-1:0]       depth;      
output reg  [DATA_WIDTH-1:0]        dataout;    
endmodule
module PH1P_LOGIC_SLICE  (
  ia,
  ib,
  ic,
  id,
  ie,
  imf,
  ima,
  imb,
  cea,
  ceb,
  clk,
  ssr,
  asr,
  oqa,
  oqb,
  ofa,
  ofb,
  fci,
  fco,
  ft_lut5a,
  olut5a
);
input  ia;          
input  ib;          
input  ic;          
input  id;          
input  ie;          
input  ima;         
input  imb;         
input  imf;         
input  clk;         
input  cea;         
input  ceb;         
input  ssr;         
input  asr;         
output  ofa,ofb,oqa,oqb;           
input fci;          
output fco;         
input ft_lut5a;     
output olut5a;      
parameter ADDER_EN    = 1'b0;           // "1", "0"
parameter INIT_LUT5A = 32'h0000_0000;   // 32'h0000_0000~32'hFFFF_FFFF.
parameter INIT_LUT5B = 32'h0000_0000;   // 32'h0000_0000~32'hFFFF_FFFF.
parameter LUTMODE = "DLUT5" ;           // "LUT6", "DLUT5".
parameter LUT5A_SD0 = "IC";             // "IC", "IMA".
parameter LUT5A_SD1 = "IE";             // "IE", "IMF", "FT_LUT5A".
parameter LUT5B_SD2 = "ID";             // "ID", "IMB".
parameter OFA_SD = "QB" ;               // "QB", "LUT6", "LUT5A", "F7CY".
parameter OFB_SD = "LUTX" ;             // "LUTX", "SUM", "QA".
parameter OQAMUX = "RELUT6" ;           // "RELUT6", "QA".
parameter OQBMUX = "RELUT6" ;           // "RELUT6", "QB".
parameter ADDERMUX = "0" ;              // "0", "IMB", "LUT5A", "FT_LUT5A".
parameter LOC_F7CY = "CY";              // "CY", "F7".
parameter CIMUX="FIXED";                // "FIXED", "MUX".
parameter DELAY_EN = "DISABLE" ;        // "DISABLE", "ENABLE".
parameter GSR = "ENABLE" ;              // "ENABLE", "DISABLE".
parameter CEAMUX = "0" ;                // "0", "1", "SIG".
parameter CEBMUX = "0" ;                // "0", "1", "SIG".
parameter SSRMUX = "1" ;                // "0", "1", "SIG", "INV".
parameter ASRMUX = "1" ;                // "0", "1", "SIG", "INV".
parameter CLKMUX = "0" ;                // "0", "1", "SIG", "INV".
parameter REGA_SD = "OFA" ;             // "IMA", "OFA", "LUT5A".
parameter REGB_SD = "SUM" ;             // "IMB", "LUT6", "SUM".
parameter REGA_REGSET_ASYNC = "SET";    // "SET", "RESET".
parameter REGB_REGSET_ASYNC = "SET";    // "SET", "RESET".
parameter REGA_REGSET_SYNC = "RESET";   // "RESET", "SET".
parameter REGB_REGSET_SYNC = "RESET";   // "RESET", "SET".
parameter SSROVERCE = "DISABLE";        // "DISABLE", "ENABLE".
parameter LATCHMODE ="DFF";             // "DFF", "LATCH".
parameter TESTMODE = "OFF" ;           // "OFF", "ON".
parameter DISRAM = "DISABLE" ;         // "DISABLE", "ENABLE".
parameter RAMMODE = "SHIFTER" ;        // "SHIFTER", "DPRAM".
parameter DISREADBACK = "READBACK" ;   // "READBACK", "DISREADBACK".
parameter FCIMUX = "0" ;               // "0", "1", "FCI", "RSB_CI".
endmodule
module PH1P_PHY_DSPADD(

    a, 
    b, 
    opctrl, 
    sum
);
input [26:0]   a;           
input [26:0]   b;           
input [1:0]    opctrl;      
output [26:0]  sum;         
endmodule
module PH1P_PHY_DSPLOGIC (
    a, 
    b, 
    c,
    opctrl, 
    p, 
    wxor
);
input [53:0]   a;           
input [53:0]   b;           
input [53:0]   c;           
input [4:0]    opctrl;      
output [53:0]  p;           
output [1:0]   wxor;        
endmodule
module PH1P_PHY_DSPMULT(

    x, 
    y, 
    opctrl, 
    p
);
input [26:0]   x;       
input [17:0]   y;       
input          opctrl;  
output [44:0]  p;       
endmodule
module PH1P_PHY_DSPMULT_V2 (

    x, 
    y, 
    mul9_mode,
    mul9_signed,
    opctrl, 
    p
);
input [26:0]   x;       
input [17:0]   y;       
input          opctrl;  
input      mul9_mode;   
input      mul9_signed; 
output [44:0]  p;       
endmodule
module PH1P_PHY_DSPSIOU(
    
      y,                 
      xa,                 
      xb,                
      z,

      clk,
      ce,
      rst,
      muxctrl,
      inctrl,             
      cinctrl,
      opctrl,

      cxai,               
      cxbi,               
      cxabi,         
      cyi,
      cpi,
      cci,

      cxao,
      cxbo,
      cxabo,
      cyo,
      cpo,
      cco,

      p,
      overflow,
      underflow,
      wxor,

      add_a, 
      add_b,
      add_opctrl,
      add_sum,
      mult_x, 
      mult_y,
      mult_opctrl,
      mult_p,
      tadd_a,
      tadd_b,
      tadd_c,
      //tadd_d,
      tadd_ci,      
      tadd_opctrl,
      tadd_oversel,
      tadd_sum,
      tadd_co,
      tadd_overflow,
      tadd_underflow,
      logic_a,
      logic_b,
      logic_c,
      logic_opctrl,
      logic_p,
      logic_wxor


);
    input   [17:0]  y;                
    input   [26:0]  xa;               
    input   [26:0]  xb;               
    input   [53:0]  z;                
    input           clk;              
    input   [3:0]   ce;               
    input   [3:0]   rst;              
    input   [6:0]   muxctrl;          
    input   [6:0]   inctrl;           
    input   [2:0]   cinctrl;          
    input   [10:0]  opctrl;           
    input   [26:0]  cxai;             
    input   [26:0]  cxbi;             
    input   [26:0]  cxabi;            
    input   [17:0]  cyi;              
    input   [53:0]  cpi;              
    input           cci;              
    output  [26:0]  cxao;             
    output  [26:0]  cxbo;             
    output  [26:0]  cxabo;            
    output  [17:0]  cyo;              
    output  [53:0]  cpo;              
    output          cco;              
    output  [53:0]  p;                
    output          overflow;         
    output          underflow;        
    output  [1:0]   wxor;             
    output [26:0]   add_a;            
    output [26:0]   add_b;            
    output [1:0]    add_opctrl;       
    input  [26:0]   add_sum;          
    output [26:0]   mult_x;           
    output [17:0]   mult_y;           
    output          mult_opctrl;      
    input  [44:0]   mult_p;           
    output [53:0]   tadd_a;           
    output [53:0]   tadd_b;           
    output [53:0]   tadd_c;           
    output          tadd_ci;          
    output [6:0]    tadd_opctrl;      
    output [5:0]    tadd_oversel;     
    input  [53:0]   tadd_sum;         
    input           tadd_co;          
    input           tadd_overflow;    
    input           tadd_underflow;   
    output [53:0]   logic_a;          
    output [53:0]   logic_b;          
    output [53:0]   logic_c;          
    output [4:0]    logic_opctrl;     
    input  [53:0]   logic_p;          
    input  [1:0]    logic_wxor;       
parameter CLKMUX = "SIG";                   // "0","1","SIG","INV"
parameter CE0 = "SIG";                      // "0","1","SIG","INV"
parameter CE1 = "SIG";                      // "0","1","SIG","INV"
parameter CE2 = "SIG";                      // "0","1","SIG","INV"
parameter CE3 = "SIG";                      // "0","1","SIG","INV"
parameter RST0 = "SIG";                     // "0","1","SIG","INV"
parameter RST1 = "SIG";                     // "0","1","SIG","INV"
parameter RST2 = "SIG";                     // "0","1","SIG","INV"
parameter RST3 = "SIG";                     // "0","1","SIG","INV"
parameter XAREG = "1";                // "0","1","2"
parameter XBREG = "1";                // "0","1","2"
parameter YREG = "1";                 // "0","1","2"
parameter ZREG = "1";                 // "0","1"
parameter INCTRLREG = "1";            // "0","1"
parameter MUXCTRLREG = "1";           // "0","1"
parameter OPCTRLREG = "1";            // "0","1"
parameter CINCTRLREG = "1";           // "0","1"
parameter CXAREG = "1";               // "0","1","2"
parameter CXBREG = "1";               // "0","1","2"
parameter CYREG = "1";                // "0","1","2"
parameter XABREG = "1";               // "0","1"
parameter MREG = "1";                 // "0","1"
parameter POUWREG = "1";              // "0","1"
parameter CCOREG = "1";               // "0","1"
parameter SR0MODE = "ASYNC";          // "ASYNC","SYNC"
parameter SR1MODE = "ASYNC";          // "ASYNC","SYNC"
parameter SR2MODE = "ASYNC";          // "ASYNC","SYNC"
parameter SR3MODE = "ASYNC";          // "ASYNC","SYNC"
parameter USER_GSRN = "ENABLE";       // "ENABLE","DISABLE"
parameter CEXA1 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXA2 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXB1 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXB2 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXAB = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEM = "CE0";                // "CE0","CE1","CE2","CE3"
parameter CEY1 = "CE0";               // "CE0","CE1","CE2","CE3"
parameter CEY2 = "CE0";               // "CE0","CE1","CE2","CE3"
parameter CEPOU = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CECOUT = "CE0";             // "CE0","CE1","CE2","CE3"
parameter CEINCTRL = "CE0";           // "CE0","CE1","CE2","CE3"
parameter CEMUXCTRL = "CE0";          // "CE0","CE1","CE2","CE3"
parameter CEOPCTRL = "CE0";           // "CE0","CE1","CE2","CE3"
parameter CECINCTRL = "CE0";          // "CE0","CE1","CE2","CE3"
parameter CEZ = "CE0";                // "CE0","CE1","CE2","CE3"
parameter CEW = "CE0";                // "CE0","CE1","CE2","CE3"
parameter RSTXA1 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXA2 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXB1 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXB2 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXAB = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTM = "RST0";              // "RST0","RST1","RST2","RST3"
parameter RSTY1 = "RST0";             // "RST0","RST1","RST2","RST3"
parameter RSTY2 = "RST0";             // "RST0","RST1","RST2","RST3"
parameter RSTPOU = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTCOUT = "RST0";           // "RST0","RST1","RST2","RST3"
parameter RSTINCTRL = "RST0";         // "RST0","RST1","RST2","RST3"
parameter RSTMUXCTRL = "RST0";        // "RST0","RST1","RST2","RST3"
parameter RSTOPCTRL = "RST0";         // "RST0","RST1","RST2","RST3"
parameter RSTCINCTRL = "RST0";        // "RST0","RST1","RST2","RST3"
parameter RSTZ = "RST0";              // "RST0","RST1","RST2","RST3"
parameter RSTW = "RST0";              // "RST0","RST1","RST2","RST3"
parameter XA_INPUT = "XA";            // "XA","CXAI","CXABI","CXBI"
parameter XB_INPUT = "XB";            // "XB","CXBI","CXABI","CXAI"
parameter Y_INPUT = "Y";              // "Y","CYI"
parameter CXABO_OUTPUT = "CXBO";      // "CXAO","CXBO"
parameter [53:0] RND = 54'b0;         // 54'b0 - 54'h3FFFFFFFFFFFFF
parameter USE_OVERFLOW = "P53";       // "P53","P52", "P51", "P50", "P49", "P48", "P47", "P46", "P45", "P44", "P43", "P42", "P41", "P40", "P39", "P38", "P37", "P36", "P35", "P34", "P33", "P32", "P31", "P30", "P29", "P28", "P27", "P26", "P25", "P24", "P23", "P22", "P21", "P20", "P19", "P18", "P17", "P16", "P15", "P14", "P13", "P12", "P11", "P10", "P9", "P8", "P7", "P6", "P5", "P4", "P3", "P2", "P1", "P0"
endmodule
module PH1P_PHY_DSPSIOU_V2 (
    
      y,                 
      xa,                 
      xb,                
      z,

      clk,
      ce,
      rst,
      muxctrl,
      inctrl,             
      cinctrl,
      opctrl,

      cxai,               
      cxbi,               
      cxabi,         
      cyi,
      cpi,
      cci,

      cxao,
      cxbo,
      cxabo,
      cyo,
      cpo,
      cco,

      p,
      overflow,
      underflow,
      wxor,

      add_a, 
      add_b,
      add_opctrl,
      add_sum,
      mul9_mode,
      mul9_signed,
      mult_x, 
      mult_y,
      mult_opctrl,
      mult_p,
      tadd_a,
      tadd_b,
      tadd_c,
      //tadd_d,
      tadd_ci,      
      tadd_opctrl,
      tadd_oversel,
      tadd_sum,
      tadd_co,
      tadd_overflow,
      tadd_underflow,
      logic_a,
      logic_b,
      logic_c,
      logic_opctrl,
      logic_p,
      logic_wxor


);
    input   [17:0]  y;                
    input   [26:0]  xa;               
    input   [26:0]  xb;               
    input   [53:0]  z;                
    input           clk;              
    input   [3:0]   ce;               
    input   [3:0]   rst;              
    input   [6:0]   muxctrl;          
    input   [6:0]   inctrl;           
    input   [2:0]   cinctrl;          
    input   [10:0]  opctrl;           
    input   [26:0]  cxai;             
    input   [26:0]  cxbi;             
    input   [26:0]  cxabi;            
    input   [17:0]  cyi;              
    input   [53:0]  cpi;              
    input           cci;              
    output  [26:0]  cxao;             
    output  [26:0]  cxbo;             
    output  [26:0]  cxabo;            
    output  [17:0]  cyo;              
    output  [53:0]  cpo;              
    output          cco;              
    output  [53:0]  p;                
    output          overflow;         
    output          underflow;        
    output  [1:0]   wxor;             
    output [26:0]   add_a;            
    output [26:0]   add_b;            
    output [1:0]    add_opctrl;       
    input  [26:0]   add_sum;          
    output [26:0]   mult_x;           
    output [17:0]   mult_y;           
    output          mult_opctrl;      
    output          mul9_mode;        
    output          mul9_signed;      
    input  [44:0]   mult_p;           
    output [53:0]   tadd_a;           
    output [53:0]   tadd_b;           
    output [53:0]   tadd_c;           
    output          tadd_ci;          
    output [6:0]    tadd_opctrl;      
    output [5:0]    tadd_oversel;     
    input  [53:0]   tadd_sum;         
    input           tadd_co;          
    input           tadd_overflow;    
    input           tadd_underflow;   
    output [53:0]   logic_a;          
    output [53:0]   logic_b;          
    output [53:0]   logic_c;          
    output [4:0]    logic_opctrl;     
    input  [53:0]   logic_p;          
    input  [1:0]    logic_wxor;       
parameter CLKMUX = "SIG";                   // "0","1","SIG","INV"
parameter CE0 = "SIG";                      // "0","1","SIG","INV"
parameter CE1 = "SIG";                      // "0","1","SIG","INV"
parameter CE2 = "SIG";                      // "0","1","SIG","INV"
parameter CE3 = "SIG";                      // "0","1","SIG","INV"
parameter RST0 = "SIG";                     // "0","1","SIG","INV"
parameter RST1 = "SIG";                     // "0","1","SIG","INV"
parameter RST2 = "SIG";                     // "0","1","SIG","INV"
parameter RST3 = "SIG";                     // "0","1","SIG","INV"
parameter MULT_MODE = "NORMAL";             // "NORMAL" , "DUAL_9X9"
parameter MULT9_SIGNED = "UNSIGNED";        // "UNSIGNED" , "SIGNED"
parameter XAREG = "1";                // "0","1","2"
parameter XBREG = "1";                // "0","1","2"
parameter YREG = "1";                 // "0","1","2"
parameter ZREG = "1";                 // "0","1"
parameter INCTRLREG = "1";            // "0","1"
parameter MUXCTRLREG = "1";           // "0","1"
parameter OPCTRLREG = "1";            // "0","1"
parameter CINCTRLREG = "1";           // "0","1"
parameter CXAREG = "1";               // "0","1","2"
parameter CXBREG = "1";               // "0","1","2"
parameter CYREG = "1";                // "0","1","2"
parameter XABREG = "1";               // "0","1"
parameter MREG = "1";                 // "0","1"
parameter POUWREG = "1";              // "0","1"
parameter CCOREG = "1";               // "0","1"
parameter SR0MODE = "ASYNC";          // "ASYNC","SYNC"
parameter SR1MODE = "ASYNC";          // "ASYNC","SYNC"
parameter SR2MODE = "ASYNC";          // "ASYNC","SYNC"
parameter SR3MODE = "ASYNC";          // "ASYNC","SYNC"
parameter USER_GSRN = "ENABLE";       // "ENABLE","DISABLE"
parameter CEXA1 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXA2 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXB1 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXB2 = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEXAB = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CEM = "CE0";                // "CE0","CE1","CE2","CE3"
parameter CEY1 = "CE0";               // "CE0","CE1","CE2","CE3"
parameter CEY2 = "CE0";               // "CE0","CE1","CE2","CE3"
parameter CEPOU = "CE0";              // "CE0","CE1","CE2","CE3"
parameter CECOUT = "CE0";             // "CE0","CE1","CE2","CE3"
parameter CEINCTRL = "CE0";           // "CE0","CE1","CE2","CE3"
parameter CEMUXCTRL = "CE0";          // "CE0","CE1","CE2","CE3"
parameter CEOPCTRL = "CE0";           // "CE0","CE1","CE2","CE3"
parameter CECINCTRL = "CE0";          // "CE0","CE1","CE2","CE3"
parameter CEZ = "CE0";                // "CE0","CE1","CE2","CE3"
parameter CEW = "CE0";                // "CE0","CE1","CE2","CE3"
parameter RSTXA1 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXA2 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXB1 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXB2 = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTXAB = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTM = "RST0";              // "RST0","RST1","RST2","RST3"
parameter RSTY1 = "RST0";             // "RST0","RST1","RST2","RST3"
parameter RSTY2 = "RST0";             // "RST0","RST1","RST2","RST3"
parameter RSTPOU = "RST0";            // "RST0","RST1","RST2","RST3"
parameter RSTCOUT = "RST0";           // "RST0","RST1","RST2","RST3"
parameter RSTINCTRL = "RST0";         // "RST0","RST1","RST2","RST3"
parameter RSTMUXCTRL = "RST0";        // "RST0","RST1","RST2","RST3"
parameter RSTOPCTRL = "RST0";         // "RST0","RST1","RST2","RST3"
parameter RSTCINCTRL = "RST0";        // "RST0","RST1","RST2","RST3"
parameter RSTZ = "RST0";              // "RST0","RST1","RST2","RST3"
parameter RSTW = "RST0";              // "RST0","RST1","RST2","RST3"
parameter XA_INPUT = "XA";            // "XA","CXAI","CXABI","CXBI"
parameter XB_INPUT = "XB";            // "XB","CXBI","CXABI","CXAI"
parameter Y_INPUT = "Y";              // "Y","CYI"
parameter CXABO_OUTPUT = "CXBO";      // "CXAO","CXBO"
parameter [53:0] RND = 54'b0;         // 54'b0 - 54'h3FFFFFFFFFFFFF
parameter USE_OVERFLOW = "P53";       // "P53","P52", "P51", "P50", "P49", "P48", "P47", "P46", "P45", "P44", "P43", "P42", "P41", "P40", "P39", "P38", "P37", "P36", "P35", "P34", "P33", "P32", "P31", "P30", "P29", "P28", "P27", "P26", "P25", "P24", "P23", "P22", "P21", "P20", "P19", "P18", "P17", "P16", "P15", "P14", "P13", "P12", "P11", "P10", "P9", "P8", "P7", "P6", "P5", "P4", "P3", "P2", "P1", "P0"
endmodule
module PH1P_PHY_DSPTADD(
 a,
 b,
 c, 
 //d,
 ci,
 opctrl,
 oversel,

 sum,
 co,	
 overflow,
 underflow
 
);
 input [53:0]	a;          
 input [53:0]	b;          
 input [53:0]	c;          
 input 	        ci;         
 input [6:0]    opctrl;     
 input [5:0]    oversel;    
 output	[53:0]	sum;        
 output		co;             
 output 	overflow;       
 output		underflow;      
endmodule
module PH1P_PHY_IOCLK
(
 clkin,
 clkout
);
 input clkin;               
 output clkout;             
endmodule
module PH1P_PHY_OSCDIV 
(
 div,
 rstn,
 stdby,
 osc_clk
);
 input rstn;                 
 input stdby;                
 input [6:0] div;
 output osc_clk;             
endmodule
module PH1P_PHY_OSC 
(
 stdby,
 osc_loop_dis 
// osc // osc clk

); 
    input stdby;
    input osc_loop_dis;
endmodule
module PH1P_PHY_PLL(
        refclk,
        refclk_rst,
        fbclk,
        clkc,
        clkcb,
        lock,
        pllreset,
        clkc_rst,
        clkc_en,            
        wakeup,             
        cps_step,          
        pllpd,              
        drp_clk,            
        drp_rstn,          
        drp_sel,   
        drp_rd,    
        drp_wr,    
        drp_addr,  
        drp_wdata,         
        drp_err,           
        drp_rdy,           
        drp_rdata,         
        psdone,
        psclk,
        psdown,
        psstep,
        psclksel,           
        ssc_reset,
        scan_clk, 
        scan_enable, 
        scan_mode, 
        scan_resetn 
);
    input           refclk;         
    input           fbclk;          
    output  [6:0]   clkc;           
    output  [6:0]   clkcb;          
    output          lock;           
    input           pllreset;       
    input   [1:0]   clkc_rst;       
    input           refclk_rst;     
    input           wakeup;         
    input   [6:0]   clkc_en;        
    input           cps_step;       
    input           pllpd;          
    input           psclk;          
    input   [2:0]   psclksel;       
    input           psstep;         
    input           psdown;         
    output          psdone;         
    input           drp_clk;        
    input           drp_rstn;       
    input           drp_sel;        
    input           drp_rd;         
    input           drp_wr;         
    input  [7:0]    drp_addr;       
    input  [7:0]    drp_wdata;      
    output          drp_err;        
    output          drp_rdy;        
    output [7:0]    drp_rdata;      
    input           ssc_reset;      
    input           scan_clk    ;   
    input           scan_enable ;   
    input           scan_mode   ;   
    input           scan_resetn ;   
parameter FBKCLK                 = "CLKC0_EXT";     // CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT
                                                    // CLKC0_INT, CLKC1_INT, CLKC2_INT, CLKC3_INT, CLKC4_INT, CLKC5_INT, CLKC6_INT, VCO_PHASE0
parameter FBKCLK_INT             = "VCO_PHASE0";    // CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT
                                                    // CLKC0_INT, CLKC1_INT, CLKC2_INT, CLKC3_INT, CLKC4_INT, CLKC5_INT, CLKC6_INT, VCO_PHASE0
parameter FIN                    = "100.0000";      
parameter REFCLK_DIV             = 1;               // 1~128
parameter FBCLK_DIV              = 1;               // 1~128
parameter CLKC0_FPHASE           = 0;               // 0~7
parameter CLKC1_FPHASE           = 0;               // 0~7
parameter CLKC2_FPHASE           = 0;               // 0~7
parameter CLKC3_FPHASE           = 0;               // 0~7
parameter CLKC4_FPHASE           = 0;               // 0~7
parameter CLKC5_FPHASE           = 0;               // 0~7
parameter CLKC6_FPHASE           = 0;               // 0~7
parameter PREDIV_MUXC0           = "VCO";           // "VCO", "CLKC_INT_MAIN", "REFCLK"
parameter PREDIV_MUXC1           = "VCO";           // "VCO", "CLKC0_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC2           = "VCO";           // "VCO", "CLKC1_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC3           = "VCO";           // "VCO", "CLKC2_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC4           = "VCO";           // "VCO", "CLKC3_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC5           = "VCO";           // "VCO", "CLKC4_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC6           = "VCO";           // "VCO", "CLKC5_INT", "HIGH", "REFCLK"
parameter CLKC0_CPHASE           = 0;               // 0~127
parameter CLKC1_CPHASE           = 0;               // 0~127
parameter CLKC2_CPHASE           = 0;               // 0~127
parameter CLKC3_CPHASE           = 0;               // 0~127
parameter CLKC4_CPHASE           = 0;               // 0~127
parameter CLKC5_CPHASE           = 0;               // 0~127
parameter CLKC6_CPHASE           = 0;               // 0~127
parameter CLKC0_DIV              = 1;               // 1~128
parameter CLKC1_DIV              = 1;               // 1~128
parameter CLKC2_DIV              = 1;               // 1~128
parameter CLKC3_DIV              = 1;               // 1~128
parameter CLKC4_DIV              = 1;               // 1~128
parameter CLKC5_DIV              = 1;               // 1~128
parameter CLKC6_DIV              = 1;               // 1~128
parameter CLKC0_DUTY_INT         = 1;               // 1~127
parameter CLKC1_DUTY_INT         = 1;               // 1~127
parameter CLKC2_DUTY_INT         = 1;               // 1~127
parameter CLKC3_DUTY_INT         = 1;               // 1~127
parameter CLKC4_DUTY_INT         = 1;               // 1~127
parameter CLKC5_DUTY_INT         = 1;               // 1~127
parameter CLKC6_DUTY_INT         = 1;               // 1~127
parameter DIVOUT_MUXC0           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC1           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC2           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC3           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC4           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC5           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC6           = "DIV";           // "DIV", "REFCLK"
parameter CLKC0_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC1_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC2_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC3_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC4_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC5_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC6_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter WORK_MODE              = "USER";          // "USER", "LOCK_BEFORE_WAKE_UP"
parameter PD_DIG                 = "ENABLE";        // "ENABLE", "DISABLE"
parameter PLL_USR_RST            = "ENABLE";        // "ENABLE", "DISABLE"
parameter PLL_FEED_TYPE          = "INTERNAL";      // "INTERNAL", "EXTERNAL"
parameter PLL_FASTLOOP           = "DISABLE"  ;     // "ENABLE", "DISABLE"
parameter LPF_RES                = 3;               // 0~3
parameter LPF_CAP                = 3;               // 0~31
parameter ICP_CUR                = 1;               // 0~31
parameter FRAC_ENABLE            = "DISABLE";       // "ENABLE", "DISABLE"
parameter SDM_FRAC               = 0;               // 0~(2^24-1)
parameter PHASE_PATH_SEL         = 0;               // 0~7
parameter DYN_PHASE_PATH_SEL     = "DISABLE";       // "ENABLE", "DISABLE"
parameter DYN_FPHASE_EN          = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC1_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC2_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC3_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC4_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC5_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC6_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC0_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC1_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC2_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC3_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC4_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC5_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC6_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter SSC_ENABLE             = "DISABLE";       // "ENABLE", "DISABLE"
parameter SSC_RST                = "ENABLE";        // "ENABLE", "DISABLE"
parameter SSC_MODE               = "CENTER";        // "UP", "DOWN", "CENTER"
parameter SSC_FREQ_DIV           = 0;               // 0~(2^18-1)
parameter SSC_RNGE               = 242;             // 0~(2^24-1)
parameter REFCLK_DET_BYP         = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_FRAC_EN          = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_FRAC             = 0;               // 0~7
parameter PI_OUT_SEL             = "NORMAL";        // "NORMAL", "PI"
parameter PI_FRAC_EN             = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_PI_SHIFT_EN      = "DISABLE";       // "ENABLE", "DISABLE"
parameter FEEDBK_MODE            = "NORMAL";        // "NORMAL", "SOURCESYNC", "NOCOMP", "ZERODELAY"
parameter DYN_CPHASE_EN          = "DISABLE";       // "ENABLE", "DISABLE"
parameter PADDRW                        = 32;
parameter PDATAW                        = 32;
endmodule
module PH1P_PHY_PLL_V2(
        refclk,
        refclk_rst,
        fbclk,
        clkc,
        clkcb,
        lock,
        pllreset,
        clkc_rst,
        clkc_en,            
        wakeup,             
        cps_step,          
        pllpd,              
        drp_clk,            
        drp_rstn,          
        drp_sel,   
        drp_rd,    
        drp_wr,    
        drp_addr,  
        drp_wdata,         
        drp_err,           
        drp_rdy,           
        drp_rdata,         
        psdone,
        psclk,
        psdown,
        psstep,
        psclksel,           
        ssc_reset,
        scan_clk, 
        scan_enable,  
        scan_mode, 
        scan_resetn 
);
    input           refclk;         
    input           fbclk;          
    output  [6:0]   clkc;           
    output  [6:0]   clkcb;          
    output          lock;           
    input           pllreset;       
    input   [1:0]   clkc_rst;       
    input           refclk_rst;     
    input           wakeup;         
    input   [6:0]   clkc_en;        
    input           cps_step;       
    input           pllpd;          
    input           psclk;          
    input   [2:0]   psclksel;       
    input           psstep;         
    input           psdown;         
    output          psdone;         
    input           drp_clk;        
    input           drp_rstn;       
    input           drp_sel;        
    input           drp_rd;         
    input           drp_wr;         
    input  [7:0]    drp_addr;       
    input  [7:0]    drp_wdata;      
    output          drp_err;        
    output          drp_rdy;        
    output [7:0]    drp_rdata;      
    input           ssc_reset;      
    input           scan_clk    ;   
    input           scan_enable ;   
    input           scan_mode   ;   
    input           scan_resetn ;   
parameter FBKCLK                 = "CLKC0_EXT";     // CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT
                                                    // CLKC0_INT, CLKC1_INT, CLKC2_INT, CLKC3_INT, CLKC4_INT, CLKC5_INT, CLKC6_INT, VCO_PHASE0
parameter FBKCLK_INT             = "VCO_PHASE0";    // CLKC0_EXT, CLKC1_EXT, CLKC2_EXT, CLKC3_EXT, CLKC4_EXT, CLKC5_EXT, CLKC6_EXT,
                                                    // CLKC0_INT, CLKC1_INT, CLKC2_INT, CLKC3_INT, CLKC4_INT, CLKC5_INT, CLKC6_INT, VCO_PHASE0
parameter FIN                    = "100.0000";      
parameter REFCLK_DIV             = 1;               // 1~128
parameter FBCLK_DIV              = 1;               // 1~128
parameter CLKC0_FPHASE           = 0;               // 0~7
parameter CLKC1_FPHASE           = 0;               // 0~7
parameter CLKC2_FPHASE           = 0;               // 0~7
parameter CLKC3_FPHASE           = 0;               // 0~7
parameter CLKC4_FPHASE           = 0;               // 0~7
parameter CLKC5_FPHASE           = 0;               // 0~7
parameter CLKC6_FPHASE           = 0;               // 0~7
parameter PREDIV_MUXC0           = "VCO";           // "VCO", "CLKC_INT_MAIN", "REFCLK"
parameter PREDIV_MUXC1           = "VCO";           // "VCO", "CLKC0_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC2           = "VCO";           // "VCO", "CLKC1_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC3           = "VCO";           // "VCO", "CLKC2_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC4           = "VCO";           // "VCO", "CLKC3_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC5           = "VCO";           // "VCO", "CLKC4_INT", "HIGH", "REFCLK"
parameter PREDIV_MUXC6           = "VCO";           // "VCO", "CLKC5_INT", "HIGH", "REFCLK"
parameter CLKC0_CPHASE           = 0;               // 0~127
parameter CLKC1_CPHASE           = 0;               // 0~127
parameter CLKC2_CPHASE           = 0;               // 0~127
parameter CLKC3_CPHASE           = 0;               // 0~127
parameter CLKC4_CPHASE           = 0;               // 0~127
parameter CLKC5_CPHASE           = 0;               // 0~127
parameter CLKC6_CPHASE           = 0;               // 0~127
parameter CLKC0_DIV              = 1;               // 1~128
parameter CLKC1_DIV              = 1;               // 1~128
parameter CLKC2_DIV              = 1;               // 1~128
parameter CLKC3_DIV              = 1;               // 1~128
parameter CLKC4_DIV              = 1;               // 1~128
parameter CLKC5_DIV              = 1;               // 1~128
parameter CLKC6_DIV              = 1;               // 1~128
parameter CLKC0_DUTY_INT         = 1;               // 1~127
parameter CLKC1_DUTY_INT         = 1;               // 1~127
parameter CLKC2_DUTY_INT         = 1;               // 1~127
parameter CLKC3_DUTY_INT         = 1;               // 1~127
parameter CLKC4_DUTY_INT         = 1;               // 1~127
parameter CLKC5_DUTY_INT         = 1;               // 1~127
parameter CLKC6_DUTY_INT         = 1;               // 1~127
parameter DIVOUT_MUXC0           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC1           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC2           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC3           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC4           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC5           = "DIV";           // "DIV", "REFCLK"
parameter DIVOUT_MUXC6           = "DIV";           // "DIV", "REFCLK"
parameter CLKC0_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC1_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC2_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC3_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC4_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC5_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC6_ENABLE           = "DISABLE";       // "ENABLE", "DISABLE"
parameter WORK_MODE              = "USER";          // "USER", "LOCK_BEFORE_WAKE_UP"
parameter PD_DIG                 = "ENABLE";        // "ENABLE", "DISABLE"
parameter PLL_USR_RST            = "ENABLE";        // "ENABLE", "DISABLE"
parameter PLL_FEED_TYPE          = "INTERNAL";      // "INTERNAL", "EXTERNAL"
parameter PLL_FASTLOOP           = "DISABLE"  ;     // "ENABLE", "DISABLE"
parameter LPF_RES                = 3;               // 0~3
parameter LPF_CAP                = 3;               // 0~31
parameter ICP_CUR                = 1;               // 0~31
parameter FRAC_ENABLE            = "DISABLE";       // "ENABLE", "DISABLE"
parameter SDM_FRAC               = 0;               // 0~(2^28-1)
parameter PHASE_PATH_SEL         = 0;               // 0~7
parameter DYN_PHASE_PATH_SEL     = "DISABLE";       // "ENABLE", "DISABLE"
parameter DYN_FPHASE_EN          = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC1_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC2_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC3_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC4_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC5_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC6_FPHASE_RSTSEL    = 0;               // 0, 1
parameter CLKC0_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC1_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC2_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC3_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC4_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC5_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter CLKC6_DUTY50           = "ENABLE";        // "ENABLE", "DISABLE"
parameter SSC_ENABLE             = "DISABLE";       // "ENABLE", "DISABLE"
parameter SSC_RST                = "ENABLE";        // "ENABLE", "DISABLE"
parameter SSC_MODE               = "CENTER";        // "UP", "DOWN", "CENTER"
parameter SSC_FREQ_DIV           = 0;               // 0~(2^18-1)
parameter SSC_RNGE               = 242;             // 0~(2^24-1)
parameter REFCLK_DET_BYP         = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_FRAC_EN          = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_FRAC             = 0;               // 0~7
parameter PI_OUT_SEL             = "NORMAL";        // "NORMAL", "PI"
parameter PI_FRAC_EN             = "DISABLE";       // "ENABLE", "DISABLE"
parameter CLKC0_PI_SHIFT_EN      = "DISABLE";       // "ENABLE", "DISABLE"
parameter FEEDBK_MODE            = "NORMAL";        // "NORMAL", "SOURCESYNC", "NOCOMP", "ZERODELAY"
parameter DYN_CPHASE_EN          = "DISABLE";       // "ENABLE", "DISABLE"
parameter PADDRW                        = 32;
parameter PDATAW                        = 32;
endmodule
module PH1P_PHY_HR_PAD (
        ipad,
        opad,
        bpad,
        rst,
        ce,
        isclk,
        ipclk,
        osclk,
        opclk,
        ts,
        doq,
        di,
        diq,
        odly_in,
        odly_out,
        idly_in,
        in_dly,
        out_dly,
        pdr,
        dl_tdi,
        dl_tdo,
        diff_in,
        diff_out,
        rdiff_enb,
        te_n,
        lb_enb,
        ck_dl_o,
        dl_ck_o,
        rst_align
);
input            idly_in;
input            odly_in;
input            dl_tdi;   
output           dl_tdo;   
output           odly_out;
input            ipad;
output           opad;
inout            bpad;
input            rst;      
input            ce;
input            isclk;    
input            ipclk;    
input            osclk;    
input            opclk;    
input            ts;
input  [9:0]     doq;
output           di;
output [9:0]     diq;
input  [7:0]     in_dly;
input  [7:0]	 out_dly;
input            diff_in;  
output           diff_out; 
input            rdiff_enb;
input            pdr;
input            te_n;
input            lb_enb;
output           ck_dl_o;
output           dl_ck_o;
input            rst_align;
parameter INRST             = "0";              // "0", "PROGRST"
parameter ISCLKSWI          = "SIG";            // "SIG", "INV"
parameter IPCLKSWI          = "SIG";            // "SIG", "INV"
parameter OSCLKSWI          = "SIG";            // "SIG", "INV"
parameter OPCLKSWI          = "SIG";            // "SIG", "INV"
parameter INDELMUX          = "NODEL";          // "NODEL", "FIXDEL", "PROGDEL"
parameter OUTDELMUX         = "NODEL";          // "NODEL", "FIXDEL", "PROGDEL"
parameter INDEL             = 1;                // 1~256
parameter OUTDEL            = 1;                // 1~256
parameter IDDRMODE          = "OFF";            // "OFF" , "SDFF" , "DDRX1" , "DDRX1_PIPE" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5"
parameter ODDRMODE          = "OFF";            // "OFF" , "SDFF" , "DDRX1" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5"
parameter TSMUX             = "1";              // "1" , "0" , "TS" , "INV" , "TS_REG" , "TS_REG_INV"
parameter TO_REGSET         = "RESET";          // "RESET", "SET"
parameter RSTMUX            = "RST";            // "RST" , "INV"
parameter OUTRST            = "0";              // "0", "PROGRST"
parameter OUTCE             = "PROGCE";         // "1", "PROGCE"
parameter IDLYSYNC          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter ODLYSYNC          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter INCE              = "PROGCE";         // "1", "PROGCE"
parameter IN_REGSET         = "RESET";          // "RESET", "SET"
parameter DO_REGSET         = "RESET";          // "RESET", "SET"
parameter GSR               = "ENABLE";         // "ENABLE", "DISABLE"
parameter CEMUX             = "CE";             // "CE", "INV"
parameter OUTRST_MODE       = "ASYNC";          // "SYNC" , "ASYNC"
parameter INRST_MODE        = "ASYNC";          // "SYNC" , "ASYNC"
parameter IOTEST            = "DISABLE";        // "ENABLE","DISABLE"
parameter ODLYSRC           = "CASCADE";        // "IOB" , "SOFT" , "CASCADE" , "ODDR"
parameter IDLYSRC           = "CASCADE";        // "CASCADE","SOFT", "IOB"
parameter PCLK_POS_NEG_EN   = "DISABLE";        // "DISABLE" , "ENABLE"
parameter OSERDESMODE       = "SERDES";         // "SERDES"  , "DDR"
parameter ISERDESMODE       = "SERDES";         // "SERDES"  , "DDR"
parameter LOWPOWEREN        = "DISABLE";        // "DISABLE" , "ENABLE"
parameter IPCLK_POS_NEG_EN  = "DISABLE";        // "DISABLE" , "ENABLE"
parameter ISERDESSRC        = "NORMAL";         // "NORMAL"  , "DELAYCAS"
parameter DLYTEST           = "DISABLE";        // "DISABLE" , "ENABLE"
parameter COMPONENTFIFOEN   = "DISABLE";        // "DISABLE" , "ENABLE"
parameter IEVENDATASAMP     = "DISABLE";        // "DISABLE" , "ENABLE"
parameter DIRBYPEN          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter DLY_TO_IOB_EN     = "ENABLE"  ;       // "ENABLE" , "DISABLE"
parameter LVDS_EN           = "ENABLE";         // "ENABLE" , "DISABLE"
parameter MODE              = "IN";           // "NONE", "IN", "OUT", "BI"
parameter DIFF_MODE         = "P";            // "P", "N","S"
parameter IOTYPE            = "LVCMOS18";     // "LVTTL33" ,"LVCMOS33" , "LVCMOS25" , "LVCMOS18" , "LVCMOS15" , "LVCMOS12" , "HSTL18_I", "HSTL_I" , "SSTL18_I" , "SSTL15" , "SSTL15_R" ,"SSTL135" ,"SSTL12" , "POD12" , "HSUL12" ,  "DIFF_HSTL18_I"  ,"DIFF_HSTL_I"  , "DIFF_SSTL18_I" , "DIFF_SSTL15", "DIFF_SSTL15_R" , "DIFF_SSTL135" , "DIFF_SSTL12" , "DIFF_POD12" ,  "DIFF_HSUL12" , "LVDS33", "LVDS25" , "LVDS18", "TMDS33", "LVDS33_E", "LVDS25_E" , "LVDS18_E", "VREF_DRIVE"
parameter DRIVE           = "8";            // "NONE" , "4" , "8" , "12" ,"16","FIXED"
parameter PULLMODE        = "NONE" ;        // "PULLUP" , "PULLDOWN" , "NONE" , "KEEPER"
endmodule
module PH1P_PHY_HR_PAD_V2 (
        ipad,
        opad,
        bpad,
        rst,
        ce,
        isclk,
        ipclk,
        osclk,
        opclk,
        ts,
        doq,
        di,
        diq,
        odly_in,
        odly_out,
        idly_in,
        in_dly,
        out_dly,
        pdr,
        dl_tdi,
        dl_tdo,
        diff_in,
        diff_out,
        rdiff_enb,
        dl_in_rtn,
        dl_out_rtn,
        lb_enb,
        te_n,
        ck_dl_o,
        dl_ck_o,
        rst_align
);
input            dl_in_rtn;   
output           dl_out_rtn;  
input            idly_in;
input            odly_in;
input            dl_tdi;      
output           dl_tdo;      
output           odly_out;
input            ipad;        
output           opad;        
inout            bpad;        
input            rst;         
input            ce;
input            isclk;       
input            ipclk;       
input            osclk;       
input            opclk;       
input            ts;
input  [9:0]     doq;
output           di;
output [9:0]     diq;
input  [7:0]     in_dly;
input  [7:0]     out_dly;
input            diff_in;     
output           diff_out;    
input            rdiff_enb;
input            lb_enb;
input            pdr;
input            te_n;
output           ck_dl_o;
output           dl_ck_o;
input            rst_align;
parameter LB_TO_DI          = "DISABLE";        // "ENABLE", "DISABLE"
parameter INRST             = "0";              // "0", "PROGRST"
parameter ISCLKSWI          = "SIG";            // "SIG", "INV"
parameter IPCLKSWI          = "SIG";            // "SIG", "INV"
parameter OSCLKSWI          = "SIG";            // "SIG", "INV"
parameter OPCLKSWI          = "SIG";            // "SIG", "INV"
parameter INDELMUX          = "NODEL";          // "NODEL", "FIXDEL", "PROGDEL"
parameter OUTDELMUX         = "NODEL";          // "NODEL", "FIXDEL", "PROGDEL"
parameter INDEL             = 1;                // 1~256
parameter OUTDEL            = 1;                // 1~256
parameter IDDRMODE          = "OFF";            // "OFF" , "SDFF" , "DDRX1" , "DDRX1_PIPE" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5"
parameter ODDRMODE          = "OFF";            // "OFF" , "SDFF" , "DDRX1" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5"
parameter TSMUX             = "1";              // "1" , "0" , "TS" , "INV" , "TS_REG" , "TS_REG_INV"
parameter TO_REGSET         = "RESET";          // "RESET", "SET"
parameter RSTMUX            = "RST";            // "RST" , "INV"
parameter OUTRST            = "0";              // "0", "PROGRST"
parameter OUTCE             = "PROGCE";         // "1", "PROGCE"
parameter IDLYSYNC          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter ODLYSYNC          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter INCE              = "PROGCE";         // "1", "PROGCE"
parameter IN_REGSET         = "RESET";          // "RESET", "SET"
parameter DO_REGSET         = "RESET";          // "RESET", "SET"
parameter GSR               = "ENABLE";         // "ENABLE", "DISABLE"
parameter CEMUX             = "CE";             // "CE", "INV"
parameter OUTRST_MODE       = "ASYNC";          // "SYNC" , "ASYNC"
parameter INRST_MODE        = "ASYNC";          // "SYNC" , "ASYNC"
parameter IOTEST            = "DISABLE";        // "ENABLE","DISABLE"
parameter ODLYSRC           = "CASCADE";        // "IOB" , "SOFT" , "CASCADE" , "ODDR"
parameter IDLYSRC           = "CASCADE";        // "CASCADE","SOFT", "IOB"
parameter PCLK_POS_NEG_EN   = "DISABLE";        // "DISABLE" , "ENABLE"
parameter OSERDESMODE       = "SERDES";         // "SERDES"  , "DDR"
parameter ISERDESMODE       = "SERDES";         // "SERDES"  , "DDR"
parameter LOWPOWEREN        = "DISABLE";        // "DISABLE" , "ENABLE"
parameter IPCLK_POS_NEG_EN  = "DISABLE";        // "DISABLE" , "ENABLE"
parameter ISERDESSRC        = "NORMAL";         // "NORMAL"  , "DELAYCAS"
parameter DLYTEST           = "DISABLE";        // "DISABLE" , "ENABLE"
parameter COMPONENTFIFOEN   = "DISABLE";        // "DISABLE" , "ENABLE"
parameter IEVENDATASAMP     = "DISABLE";        // "DISABLE" , "ENABLE"
parameter DIRBYPEN          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter DLY_TO_IOB_EN     = "ENABLE";         // "ENABLE" , "DISABLE"
parameter LVDS_EN           = "ENABLE";         // "ENABLE" , "DISABLE"
parameter MODE              = "IN";           // "NONE", "IN", "OUT", "BI"
parameter DIFF_MODE         = "P";            // "P", "N","S"
parameter IOTYPE            = "LVCMOS18";     // "LVTTL33" ,"LVCMOS33" , "LVCMOS25" , "LVCMOS18" , "LVCMOS15" , "LVCMOS12" , "HSTL18_I", "HSTL_I" , "SSTL18_I" , "SSTL15" , "SSTL15_R" ,"SSTL135" ,"SSTL12" , "POD12" , "HSUL12" ,  "DIFF_HSTL18_I"  ,"DIFF_HSTL_I"  , "DIFF_SSTL18_I" , "DIFF_SSTL15", "DIFF_SSTL15_R" , "DIFF_SSTL135" , "DIFF_SSTL12" , "DIFF_POD12" ,  "DIFF_HSUL12" , "LVDS33", "LVDS25" ,"MINI_LVDS", "SUB_LVDS", "LVDS18", "TMDS33", "LVDS33_E", "LVDS25_E" , "LVDS18_E", "VREF_DRIVE"
parameter DRIVE           = "8";            // "NONE" , "2", "4", "6" , "8" , "12" ,"16","FIXED"
parameter PULLMODE        = "NONE" ;        // "PULLUP" , "PULLDOWN" , "NONE" , "KEEPER"
endmodule
module PH1P_PHY_HR_PAD_V3 (
        ipad,
        opad,
        bpad,
        rst,
        ce,
        isclk,
        ipclk,
        osclk,
        opclk,
        ts,
        doq,
        di,
        diq,
        odly_in,
        odly_out,
        idly_in,
        in_dly,
        out_dly,
        pdr,
        dl_tdi,
        dl_tdo,
        diff_in,
        diff_out,
        rdiff_enb,
        dl_in_rtn,
        dl_out_rtn,
        lb_enb,
        te_n,
        ck_dl_o,
        dl_ck_o,
        rst_align
);
input            dl_in_rtn;   
output           dl_out_rtn;  
input            idly_in;
input            odly_in;
input            dl_tdi;      
output           dl_tdo;      
output           odly_out;
input            ipad;        
output           opad;        
inout            bpad;        
input            rst;         
input            ce;
input            isclk;       
input            ipclk;       
input            osclk;       
input            opclk;       
input            ts;
input  [9:0]     doq;
output           di;
output [9:0]     diq;
input  [7:0]     in_dly;
input  [7:0]     out_dly;
input            diff_in;     
output           diff_out;    
input            rdiff_enb;
input            lb_enb;
input            pdr;
input            te_n;
output           ck_dl_o;
output           dl_ck_o;
input            rst_align;
parameter LB_TO_DI          = "DISABLE";        // "ENABLE", "DISABLE"
parameter INRST             = "0";              // "0", "PROGRST"
parameter ISCLKSWI          = "SIG";            // "SIG", "INV"
parameter IPCLKSWI          = "SIG";            // "SIG", "INV"
parameter OSCLKSWI          = "SIG";            // "SIG", "INV"
parameter OPCLKSWI          = "SIG";            // "SIG", "INV"
parameter INDELMUX          = "NODEL";          // "NODEL", "FIXDEL", "PROGDEL"
parameter OUTDELMUX         = "NODEL";          // "NODEL", "FIXDEL", "PROGDEL"
parameter INDEL             = 1;                // 1~256
parameter OUTDEL            = 1;                // 1~256
parameter IDDRMODE          = "OFF";            // "OFF" , "SDFF" , "DDRX1" , "DDRX1_PIPE" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5"
parameter ODDRMODE          = "OFF";            // "OFF" , "SDFF" , "DDRX1" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5"
parameter TSMUX             = "1";              // "1" , "0" , "TS" , "INV" , "TS_REG" , "TS_REG_INV"
parameter TO_REGSET         = "RESET";          // "RESET", "SET"
parameter RSTMUX            = "RST";            // "RST" , "INV"
parameter OUTRST            = "0";              // "0", "PROGRST"
parameter OUTCE             = "PROGCE";         // "1", "PROGCE"
parameter IDLYSYNC          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter ODLYSYNC          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter INCE              = "PROGCE";         // "1", "PROGCE"
parameter IN_REGSET         = "RESET";          // "RESET", "SET"
parameter DO_REGSET         = "RESET";          // "RESET", "SET"
parameter GSR               = "ENABLE";         // "ENABLE", "DISABLE"
parameter CEMUX             = "CE";             // "CE", "INV"
parameter OUTRST_MODE       = "ASYNC";          // "SYNC" , "ASYNC"
parameter INRST_MODE        = "ASYNC";          // "SYNC" , "ASYNC"
parameter IOTEST            = "DISABLE";        // "ENABLE","DISABLE"
parameter ODLYSRC           = "CASCADE";        // "IOB" , "SOFT" , "CASCADE" , "ODDR"
parameter IDLYSRC           = "CASCADE";        // "CASCADE","SOFT", "IOB"
parameter PCLK_POS_NEG_EN   = "DISABLE";        // "DISABLE" , "ENABLE"
parameter OSERDESMODE       = "SERDES";         // "SERDES"  , "DDR"
parameter ISERDESMODE       = "SERDES";         // "SERDES"  , "DDR"
parameter LOWPOWEREN        = "DISABLE";        // "DISABLE" , "ENABLE"
parameter IPCLK_POS_NEG_EN  = "DISABLE";        // "DISABLE" , "ENABLE"
parameter ISERDESSRC        = "NORMAL";         // "NORMAL"  , "DELAYCAS"
parameter DLYTEST           = "DISABLE";        // "DISABLE" , "ENABLE"
parameter COMPONENTFIFOEN   = "DISABLE";        // "DISABLE" , "ENABLE"
parameter IEVENDATASAMP     = "DISABLE";        // "DISABLE" , "ENABLE"
parameter DIRBYPEN          = "DISABLE";        // "ENABLE" , "DISABLE"
parameter DLY_TO_IOB_EN     = "ENABLE";         // "ENABLE" , "DISABLE"
parameter LVDS_EN           = "ENABLE";         // "ENABLE" , "DISABLE"
parameter MODE              = "IN";           // "NONE", "IN", "OUT", "BI"
parameter DIFF_MODE         = "P";            // "P", "N","S"
parameter IOTYPE            = "LVCMOS18";     // "LVTTL33" ,"LVCMOS33" , "LVCMOS25" , "LVCMOS18" , "LVCMOS15" , "LVCMOS12" , "HSTL18_I", "HSTL_I" , "SSTL18_I" , "SSTL15" , "SSTL15_R" ,"SSTL135" ,"SSTL12" , "POD12" , "HSUL12" ,  "DIFF_HSTL18_I"  ,"DIFF_HSTL_I"  , "DIFF_SSTL18_I" , "DIFF_SSTL15", "DIFF_SSTL15_R" , "DIFF_SSTL135" , "DIFF_SSTL12" , "DIFF_POD12" ,  "DIFF_HSUL12" , "LVDS33", "LVDS25" ,"MINI_LVDS", "SUB_LVDS", "LVDS18", "TMDS33", "LVDS33_E", "LVDS25_E" , "LVDS18_E", "VREF_DRIVE"
parameter DRIVE           = "8";            // "NONE" , "4" , "8" , "12" ,"16","FIXED"
parameter PULLMODE        = "NONE" ;        // "PULLUP" , "PULLDOWN" , "NONE" , "KEEPER"
endmodule
module PH1P_PHY_HD_PAD (
        ipad,
        opad,
        bpad,
        rst,
        ce,
        ipclk,
        osclk,
        ts,
        doq,
        di,
        diq,
        dly_in,
        dly_out,
        dly_src_sel,
        dly,
        lb_enb,
        in_dl_through,
        out_dl_through,
        in_dl_return,
        out_dl_return
);
input            dly_in;
input            dly_src_sel;    
input            in_dl_through;  
input            in_dl_return;   
output           out_dl_through; 
output           out_dl_return;  
output           dly_out;
input            ipad;           
output           opad;           
inout            bpad;           
input            rst;            
input            ce;
input            ipclk;          
input            osclk;          
input            ts;
input            lb_enb;
input  [1:0]     doq;
output           di;
output [1:0]     diq;
input  [4:0]     dly;
parameter IPCLKSWI          = "SIG";            // "SIG", "INV"
parameter IDDRMODE          = "BYPASS";         // "BYPASS", "SDR", "DDRX1_OPPOSITE", "DDRX1_SAME_EDGE", "DDRX1_SAME_EDGE_PIPE"
parameter DI_SEL            = "SIG";            // "SIG", "INV", "0", "1"
parameter INCKEN            = "DISABLE";        // "ENABLE", "DISABLE"
parameter IN_REGSET         = "RESET";          // "RESET", "SET"
parameter DI_TEST           = "DO";             // "DI", "DO"
parameter OSCLKSWI          = "SIG";            // "SIG", "INV"
parameter DOQ0MUX           = "SIG";            // "SIG", "INV", "0", "1"
parameter DOQ1MUX           = "SIG";            // "SIG", "INV", "0", "1"
parameter ODDRMODE          = "BYPASS";         // "BYPASS", "SDR", "DDRX1"
parameter OTYPE             = "DIRECTD0";       // "DIRECTD0", "TEST" ,"DDRSDR"
parameter OUT_REGSET        = "RESET";          // "RESET", "SET"
parameter TESTSEL           = "PREVIO";         // "PREVIO", "OCLK"
parameter TSMUX             = "SIG";            // "SIG", "INV", "0", "1"
parameter TSMODE            = "NONE";           // "NONE", "SDFF"
parameter TS_REGSET         = "RESET";          // "RESET", "SET"
parameter INRST             = "DISABLE";        // "ENABLE", "DISABLE"
parameter OUTRST            = "DISABLE";        // "ENABLE", "DISABLE"
parameter GSR               = "ENABLE";         // "ENABLE", "DISABLE"
parameter SRMODE            = "SYNC";           // "ASYNC", "SYNC"
parameter RSTMUX            = "RST";            // "RST", "INV"
parameter INCE              = "PROGCE";         // "1", "PROGCE"
parameter OUTCE             = "PROGCE";         // "1", "PROGCE"
parameter CEMUX             = "CE";             // "CE", "INV"
parameter IPCLK_DLY         = "DISABLE";        // "ENABLE", "DISABLE"
parameter IDLYEN            = "DISABLE";        // "DISABLE", "ENABLE"
parameter ODLYEN            = "DISABLE";        // "DISABLE", "ENABLE"
parameter DLYSRC            = "IOB";            // "IOB", "ODDR"
parameter DLYCASSRC         = "CASCADE";        // "CASCADE", "SOFT"
parameter DLYCAS_MODE       = "NONE";           // "MASTER", "MIDDLE", "END", "NONE"
parameter MODE               = "IN";            // "NONE", "IN", "OUT", "BI"
parameter IOTYPE             = "LVCMOS18";      // "LVTTL33","LVCMOS33" , "LVCMOS25" , "LVCMOS18" , "LVCMOS15", "LVDS33_E", "LVDS25_E", "LVDS18_E"
endmodule
module PH1P_PHY_DDRPHY_BANKREF (
     i_pclk   ,
     i_preset ,
     i_penable,
     i_psel   ,
     i_pwrite ,
     i_paddr  ,
     i_pwdata ,
     o_prdata ,
     o_pready ,
     o_pslverr,

     i_scan_clk     ,
     i_scan_rst_n   ,
     i_scan_mode_n  ,
     i_scan_enable_n,
     i_scan_in      ,
     o_scan_out      
);
input         i_pclk          ; 
input         i_preset        ; 
input         i_psel          ; 
input         i_penable       ; 
input         i_pwrite        ; 
input  [7:0]  i_paddr         ; 
input  [7:0]  i_pwdata        ; 
output [7:0]  o_prdata        ; 
output        o_pready        ; 
output        o_pslverr       ; 
input         i_scan_clk      ; 
input         i_scan_rst_n    ; 
input         i_scan_mode_n   ; 
input         i_scan_enable_n ; 
input  [2:0]  i_scan_in       ; 
output [2:0]  o_scan_out      ; 
parameter VCCIO           = "1V80"; // "1V80", "1V50", "1V35", "1V20"
parameter BYTE0_MODE      = "NONE"; // "NONE", "IN"
parameter BYTE1_MODE      = "NONE"; // "NONE", "IN"
parameter BYTE2_MODE      = "NONE"; // "NONE", "IN"
parameter BYTE3_MODE      = "NONE"; // "NONE", "IN"
parameter BYTE0_TYPE      = "DDR2"; // "DDR2", "DDR3", "DDR4AC", "DDR4DX"
parameter BYTE1_TYPE      = "DDR2"; // "DDR2", "DDR3", "DDR4AC", "DDR4DX"
parameter BYTE2_TYPE      = "DDR2"; // "DDR2", "DDR3", "DDR4AC", "DDR4DX"
parameter BYTE3_TYPE      = "DDR2"; // "DDR2", "DDR3", "DDR4AC", "DDR4DX"
parameter VREF            = "INT" ; // "EXT", "INT", "VREF", "NONE"
parameter VREF_BYTE0_SEL  = "SRAM"; // "SRAM", "DDR"
parameter VREF_BYTE1_SEL  = "SRAM"; // "SRAM", "DDR"
parameter VREF_BYTE2_SEL  = "SRAM"; // "SRAM", "DDR"
parameter VREF_BYTE3_SEL  = "SRAM"; // "SRAM", "DDR"
endmodule
module PH1P_PHY_HD_BANKREF (
        det18_vccio,
        det25_vccio,
        det33_vccio

);
	output	det18_vccio;
        output	det25_vccio;
        output	det33_vccio;
        parameter VCCIO_FORCE          = "DISABLE";   // "DISABLE", "3P3", "2P5", "1P8_1P5"
endmodule
module PH1P_PHY_ERAM (
  dia, 
  dia_extra, 
  csa,
  addra, 
  ocea, 
  clka, 
  wea,
  orsta, 
  dib, 
  dib_extra, 
  csb,
  addrb, 
  oceb, 
  clkb, 
  web,
  orstb, 
  doa,
  doa_extra,
  dob,
  dob_extra,
  ecc_sbiterr,
  ecc_dbiterr,
  ecc_sbiterrinj,
  ecc_dbiterrinj,
//  fifoctrl_fifoen,// fifoctrl_* comes from fifoctrl hard module, just for simulation, no need customer/SW to connection
  fifoctrl_waddr,//following 4 signs just for simulation, no need connection
  fifoctrl_raddr,// 
  fifoctrl_we,   //
  fifoctrl_re,    //
  addra_casin, // cascade addra in
  addrb_casin, // cascade addrb in
  addra_casout, // cascade addra out
  addrb_casout  // cascade addra out
);
output  [15:0] doa;
output  [15:0] dob;
output  [3:0] doa_extra;
output  [3:0] dob_extra;
input   [15:0] dia;         
input   [15:0] dib;         
input   [3:0] dia_extra;    
input   [3:0] dib_extra;    
input   [2:0] csa;          
input   [2:0] csb;          
input   ocea;               
input   clka;               
input   wea;                
input   orsta;              
input   oceb;               
input   clkb;               
input   web;                
input   orstb;              
input   [13:0] addra;       
input   [13:0] addrb;       
output  ecc_sbiterr;
output  ecc_dbiterr; 
input   [13:0] fifoctrl_waddr;  
input   [13:0] fifoctrl_raddr;  
input   fifoctrl_we;            
input   fifoctrl_re;            
input   [13:0] addra_casin;     
input   [13:0] addrb_casin;     
output  [13:0] addra_casout;    
output  [13:0] addrb_casout;    
input   ecc_sbiterrinj;
input   ecc_dbiterrinj;
parameter MODE = "DP20K";               // "DP20K", "FIFO20K"
parameter FIFOMODE = "DISABLE";         // "DISABLE", "ENABLE"
parameter DATA_WIDTH_A = "20";          // "1", "2", "5", "10", "20", "40"
parameter DATA_WIDTH_B = "20";          // "1", "2", "5", "10", "20", "40"
parameter CLKMODE = "ASYNC";  // "ASYNC","SYNC"
parameter READBACK = "DISABLE"; // "DISABLE","ENABLE"
parameter DEVICE = "PHONEX";
parameter SPEEDLEVEL ="1";
parameter REGMODE_A = "NOREG";         // "NOREG", "OUTREG"
parameter REGMODE_B = "NOREG";         // "NOREG", "OUTREG"
parameter WRITEMODE_A = "NORMAL";      // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH"
parameter WRITEMODE_B = "NORMAL";      // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH"
parameter GSR = "ENABLE";              // "DISABLE", "ENABLE"
parameter OREGSET_A = "SET";  // "SET", "RESET"
parameter OREGSET_B = "SET";  // "SET", "RESET"
parameter ASYNC_RESET_RELEASE_A = "SYNC";  // "SYNC", "ASYNC"
parameter ASYNC_RESET_RELEASE_B = "SYNC";  // "SYNC", "ASYNC"
parameter RESETMODE_A = "ASYNC";          // "ASYNC", "SYNC"
parameter RESETMODE_B = "ASYNC";          // "ASYNC", "SYNC"
parameter SSROVERCE = "DISABLE"; // "DISABLE","ENABLE"
parameter ECC_DECODE = "DISABLE"; // "DISABLE","ENABLE"
parameter ECC_ENCODE = "DISABLE"; // "DISABLE","ENABLE"
parameter OCEAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter OCEBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter RSTAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter RSTBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter CLKAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter CLKBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter WEAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter WEBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter CSA0 = "SIG" ;  // "0","1","SIG"
parameter CSA1 = "SIG" ;  // "0","1","SIG","INV"
parameter CSA2 = "SIG" ;  // "0","1","SIG","INV"
parameter CSB0 = "SIG" ;  // "0","1","SIG"
parameter CSB1 = "SIG" ;  // "0","1","SIG","INV"
parameter CSB2 = "SIG" ;  // "0","1","SIG","INV"
parameter LADDRCAS_A = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter LADDRCAS_B = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter HADDRCAS_A = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter HADDRCAS_B = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter INIT_ENABLE=1; 
parameter INIT_FILE = "";
parameter INITP_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_10 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_11 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_12 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_13 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_14 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_15 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_16 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_17 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_18 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_19 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_20 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_21 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_22 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_23 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_24 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_25 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_26 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_27 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_28 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_29 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_30 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_31 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_32 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_33 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_34 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_35 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_36 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_37 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_38 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_39 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
endmodule
module PH1P_LOGIC_DPHY_LVCMOS(
    io_clk_pad_n, 
    io_clk_pad_p, 
    io_data_pad_n,
    io_data_pad_p,

    i_ck_lvcmos_tx_en,
    i_ck_p_lvcmos_idelay_value,
    i_ck_p_lvcmos_tx,
    o_ck_p_lvcmos_rx,
    i_ck_n_lvcmos_tx,
    o_ck_n_lvcmos_rx,

    i_l0_lvcmos_tx_en,
    i_l0_p_lvcmos_idelay_value,
    i_l0_p_lvcmos_tx,
    o_l0_p_lvcmos_rx,
    i_l0_n_lvcmos_tx,
    o_l0_n_lvcmos_rx,

    i_l1_lvcmos_tx_en,
    i_l1_p_lvcmos_idelay_value,
    i_l1_p_lvcmos_tx,
    o_l1_p_lvcmos_rx,
    i_l1_n_lvcmos_tx,
    o_l1_n_lvcmos_rx,

    i_l2_lvcmos_tx_en,
    i_l2_p_lvcmos_idelay_value,
    i_l2_p_lvcmos_tx,
    o_l2_p_lvcmos_rx,
    i_l2_n_lvcmos_tx,
    o_l2_n_lvcmos_rx,

    i_l3_lvcmos_tx_en,
    i_l3_p_lvcmos_idelay_value,
    i_l3_p_lvcmos_tx,
    o_l3_p_lvcmos_rx,
    i_l3_n_lvcmos_tx,
    o_l3_n_lvcmos_rx
);
    inout      io_clk_pad_n;               
    inout      io_clk_pad_p;               
    inout[3:0] io_data_pad_n;              
    inout[3:0] io_data_pad_p;              
    input      i_ck_lvcmos_tx_en;          
    input[6:0] i_ck_p_lvcmos_idelay_value; 
    input      i_ck_p_lvcmos_tx;           
    output     o_ck_p_lvcmos_rx;           
    input      i_ck_n_lvcmos_tx;           
    output     o_ck_n_lvcmos_rx;           
    input      i_l0_lvcmos_tx_en;          
    input[6:0] i_l0_p_lvcmos_idelay_value; 
    input      i_l0_p_lvcmos_tx;           
    output     o_l0_p_lvcmos_rx;           
    input      i_l0_n_lvcmos_tx;           
    output     o_l0_n_lvcmos_rx;           
    input      i_l1_lvcmos_tx_en;          
    input[6:0] i_l1_p_lvcmos_idelay_value; 
    input      i_l1_p_lvcmos_tx;           
    output     o_l1_p_lvcmos_rx;           
    input      i_l1_n_lvcmos_tx;           
    output     o_l1_n_lvcmos_rx;           
    input      i_l2_lvcmos_tx_en;          
    input[6:0] i_l2_p_lvcmos_idelay_value; 
    input      i_l2_p_lvcmos_tx;           
    output     o_l2_p_lvcmos_rx;           
    input      i_l2_n_lvcmos_tx;           
    output     o_l2_n_lvcmos_rx;           
    input      i_l3_lvcmos_tx_en;          
    input[6:0] i_l3_p_lvcmos_idelay_value; 
    input      i_l3_p_lvcmos_tx;           
    output     o_l3_p_lvcmos_rx;           
    input      i_l3_n_lvcmos_tx;           
    output     o_l3_n_lvcmos_rx;           
    parameter DPHY_LOCATION = "DPHY0";          // "DPHY0", "DPHY1"
    parameter CK_RX_IOSTANDARD    = "LVCMOS18"; // "LVCMOS12","LVCMOS18"
    parameter CK_TX_SLEW_RATE     = "SLOW";     // "SLOW","MEDIUM","FAST"
    parameter CK_TX_DRIVESTRENGTH = "4mA";      // "4mA","8mA","12mA","16mA"
    parameter L0_RX_IOSTANDARD    = "LVCMOS18"; // "LVCMOS12","LVCMOS18"
    parameter L0_TX_SLEW_RATE     = "SLOW";     // "SLOW","MEDIUM","FAST"
    parameter L0_TX_DRIVESTRENGTH = "4mA";      // "4mA","8mA","12mA","16mA"
    parameter L1_RX_IOSTANDARD    = "LVCMOS18"; // "LVCMOS12","LVCMOS18"
    parameter L1_TX_SLEW_RATE     = "SLOW";     // "SLOW","MEDIUM","FAST"
    parameter L1_TX_DRIVESTRENGTH = "4mA";      // "4mA","8mA","12mA","16mA"
    parameter L2_RX_IOSTANDARD    = "LVCMOS18"; // "LVCMOS12","LVCMOS18"
    parameter L2_TX_SLEW_RATE     = "SLOW";     // "SLOW","MEDIUM","FAST"
    parameter L2_TX_DRIVESTRENGTH = "4mA";      // "4mA","8mA","12mA","16mA"
    parameter L3_RX_IOSTANDARD    = "LVCMOS18"; // "LVCMOS12","LVCMOS18"
    parameter L3_TX_SLEW_RATE     = "SLOW";     // "SLOW","MEDIUM","FAST"
    parameter L3_TX_DRIVESTRENGTH = "4mA";      // "4mA","8mA","12mA","16mA"
endmodule
module PH1P_LOGIC_DPHY_LVDS_RX(
    io_clk_pad_n, 
    io_clk_pad_p, 
    io_data_pad_n,
    io_data_pad_p,

    i_pll_to_phy_sample_clk,
    o_phy_to_pll_ref_clk,   
    o_fabric_div5_10_clk,   
    o_fabric_div4_8_clk,    

    i_phy_rst_n,            

    i_ck_rx_en,
    i_ck_idelay_value,

    i_l0_rx_en,
    i_l0_slave_deser_clk_en,
    i_l0_idelay_value,
    o_l0_rx_data,      
    o_l0_rx_slave_data,

    i_l1_rx_en,
    i_l1_slave_deser_clk_en,
    i_l1_idelay_value,
    o_l1_rx_data,
    o_l1_rx_slave_data,

    i_l2_rx_en,
    i_l2_slave_deser_clk_en,
    i_l2_idelay_value,
    o_l2_rx_data,
    o_l2_rx_slave_data,

    i_l3_rx_en,
    i_l3_slave_deser_clk_en,
    i_l3_idelay_value,
    o_l3_rx_data,
    o_l3_rx_slave_data

);
    inout        io_clk_pad_n;            
    inout        io_clk_pad_p;            
    inout[3:0]   io_data_pad_n;           
    inout[3:0]   io_data_pad_p;           
    input        i_pll_to_phy_sample_clk; 
    output       o_phy_to_pll_ref_clk;    
    output       o_fabric_div5_10_clk;    
    output       o_fabric_div4_8_clk;     
    input        i_phy_rst_n;             
    input        i_ck_rx_en;              
    input[5:0]   i_ck_idelay_value;       
    input        i_l0_rx_en;              
    input        i_l0_slave_deser_clk_en; 
    input[5:0]   i_l0_idelay_value;       
    output[15:0] o_l0_rx_data;            
    output[15:0] o_l0_rx_slave_data;      
    input        i_l1_rx_en;              
    input        i_l1_slave_deser_clk_en; 
    input[5:0]   i_l1_idelay_value;       
    output[15:0] o_l1_rx_data;            
    output[15:0] o_l1_rx_slave_data;      
    input        i_l2_rx_en;              
    input        i_l2_slave_deser_clk_en; 
    input[5:0]   i_l2_idelay_value;       
    output[15:0] o_l2_rx_data;            
    output[15:0] o_l2_rx_slave_data;      
    input        i_l3_rx_en;              
    input        i_l3_slave_deser_clk_en; 
    input[5:0]   i_l3_idelay_value;       
    output[15:0] o_l3_rx_data;            
    output[15:0] o_l3_rx_slave_data;      
    parameter DPHY_RX_LOCATION = "DPHY0";             // "DPHY0", "DPHY1"
    parameter S2P_RATIO        = "1:8";               // "1:8","1:16"
    parameter SAMPLE_CLOCK_SEL = "CLK_LANE";          // "CLK_LANE","PLL"
    parameter CK_EQUALIZER                  = "0dB";      // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter CK_VGA_GAIN                   = "0dB";      // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter CK_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter CK_TERMINATOR                 = "AC100ohm"; // "NONE","DC100ohm","AC100ohm"
    parameter CK_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter CK_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter CK_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter CK_INTERNAL_AC_CAP_ENABLE     = "DISABLE";  // "ENABLE","DISABLE"
    parameter L0_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter L0_EQUALIZER                  = "0dB";      // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L0_VGA_GAIN                   = "0dB";      // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L0_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter L0_TERMINATOR                 = "AC100ohm"; // "NONE","DC100ohm","AC100ohm"
    parameter L0_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter L0_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter L0_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter L0_INTERNAL_AC_CAP_ENABLE     = "DISABLE";  // "ENABLE","DISABLE"
    parameter L1_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter L1_EQUALIZER                  = "0dB";      // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L1_VGA_GAIN                   = "0dB";      // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L1_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter L1_TERMINATOR                 = "AC100ohm"; // "NONE","DC100ohm","AC100ohm"
    parameter L1_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter L1_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter L1_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter L1_INTERNAL_AC_CAP_ENABLE     = "DISABLE";  // "ENABLE","DISABLE"
    parameter L2_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter L2_EQUALIZER                  = "0dB";      // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L2_VGA_GAIN                   = "0dB";      // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L2_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter L2_TERMINATOR                 = "AC100ohm"; // "NONE","DC100ohm","AC100ohm"
    parameter L2_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter L2_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter L2_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter L2_INTERNAL_AC_CAP_ENABLE     = "DISABLE";  // "ENABLE","DISABLE"
    parameter L3_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter L3_EQUALIZER                  = "0dB";      // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L3_VGA_GAIN                   = "0dB";      // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L3_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter L3_TERMINATOR                 = "AC100ohm"; // "NONE","DC100ohm","AC100ohm"
    parameter L3_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter L3_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter L3_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter L3_INTERNAL_AC_CAP_ENABLE     = "DISABLE";  // "ENABLE","DISABLE"
endmodule
module PH1P_LOGIC_DPHY_LVDS_TX(
    io_clk_pad_n,
    io_clk_pad_p,
    io_data_pad_n,
    io_data_pad_p,

    i_phy_dpll_ref_clk,
    o_fabric_div5_10_clk,
    o_fabric_div4_8_clk,

    i_phy_dpll_rst_n,
    i_phy_dpll_pwdn_n,
    i_phy_dpll_vco_bypass_n,
    o_phy_dpll_locked,
    i_phy_dpll_multi_ratio,
    i_phy_dpll_div_ratio,

    i_phy_rst_n,

    i_ck_tx_en,       
    i_ck_odelay_value,
    i_ck_tx_data,

    i_l0_tx_en,  
    i_l0_odelay_value,
    i_l0_tx_data,

    i_l1_tx_en,                  
    i_l1_odelay_value,                
    i_l1_tx_data,                

    i_l2_tx_en,                  
    i_l2_odelay_value,                
    i_l2_tx_data,       

    i_l3_tx_en,                   
    i_l3_odelay_value,                 
    i_l3_tx_data                 

);
    inout       io_clk_pad_n;            
    inout       io_clk_pad_p;            
    inout[3:0]  io_data_pad_n;           
    inout[3:0]  io_data_pad_p;           
    input       i_phy_dpll_ref_clk;      
    output      o_fabric_div5_10_clk;    
    output      o_fabric_div4_8_clk;     
    input       i_phy_dpll_rst_n;        
    input       i_phy_dpll_pwdn_n;       
    input       i_phy_dpll_vco_bypass_n; 
    output      o_phy_dpll_locked;       
    input[6:0]  i_phy_dpll_multi_ratio;  
    input[5:0]  i_phy_dpll_div_ratio;    
    input       i_phy_rst_n;             
    input       i_ck_tx_en;              
    input[3:0]  i_ck_odelay_value;       
    input[15:0] i_ck_tx_data;            
    input       i_l0_tx_en;              
    input[3:0]  i_l0_odelay_value;       
    input[15:0] i_l0_tx_data;            
    input       i_l1_tx_en;              
    input[3:0]  i_l1_odelay_value;       
    input[15:0] i_l1_tx_data;            
    input       i_l2_tx_en;              
    input[3:0]  i_l2_odelay_value;       
    input[15:0] i_l2_tx_data;            
    input       i_l3_tx_en;              
    input[3:0]  i_l3_odelay_value;       
    input[15:0] i_l3_tx_data;            
    parameter DPHY_TX_LOCATION = "DPHY0";           // "DPHY0", "DPHY1"
    parameter P2S_RATIO           = "8:1";          // "8:1","16:1"
    parameter LVDS_OUTPUT_VCM     = "1.2v";         // "0.7v","0.75v","0.8v","0.9v","1v","1.1v","1.2v","1.3v"
    parameter LVDS_EXTRA_VOD_GAIN = "DISABLE";      // "ENABLE","DISABLE"
    parameter LVDS_OVER_CURRENT_PROTECT = "DISABLE";// "ENABLE","DISABLE"
    parameter CK_DE_EMPHASIS     = "0dB";           // "0dB","-5dB"
    parameter CK_LVDS_OUTPUT_VOD = "3.5mA";         // "2.5mA","3mA","3.5mA","4mA","4.5mA","5mA","5.5mA","6mA"
    parameter L0_DE_EMPHASIS     = "0dB";           // "0dB","-5dB"
    parameter L0_LVDS_OUTPUT_VOD = "3.5mA";         // "2.5mA","3mA","3.5mA","4mA","4.5mA","5mA","5.5mA","6mA"
    parameter L1_DE_EMPHASIS     = "0dB";           // "0dB","-5dB"
    parameter L1_LVDS_OUTPUT_VOD = "3.5mA";         // "2.5mA","3mA","3.5mA","4mA","4.5mA","5mA","5.5mA","6mA"
    parameter L2_DE_EMPHASIS     = "0dB";           // "0dB","-5dB"
    parameter L2_LVDS_OUTPUT_VOD = "3.5mA";         // "2.5mA","3mA","3.5mA","4mA","4.5mA","5mA","5.5mA","6mA"
    parameter L3_DE_EMPHASIS     = "0dB";           // "0dB","-5dB"
    parameter L3_LVDS_OUTPUT_VOD = "3.5mA";         // "2.5mA","3mA","3.5mA","4mA","4.5mA","5mA","5.5mA","6mA"
endmodule
module PH1P_LOGIC_DPHY_MIPI_RX(
    io_clk_pad_n, 
    io_clk_pad_p, 
    io_data_pad_n,
    io_data_pad_p,

    o_fabric_div4_8_clk, 

    i_phy_rst_n,

    i_ck_lp_rx_en,
    o_ck_lp_rx_p,
    o_ck_lp_rx_n,
    i_ck_hs_rx_en,
    i_ck_hs_terminator_sel,
    i_ck_hs_idelay_en,   
    i_ck_hs_idelay_value,

    i_l0_lp_rx_en,
    i_l0_lp_tx_en,
    o_l0_lp_rx_p,              
    o_l0_lp_rx_n,              
    i_l0_lp_tx_p,              
    i_l0_lp_tx_n,     
    i_l0_hs_rx_en,    
    i_l0_hs_terminator_sel,
    i_l0_hs_slave_deser_clk_en,
    i_l0_hs_idelay_en,   
    i_l0_hs_idelay_value,                  
    o_l0_hs_rx_data,      
    o_l0_hs_rx_slave_data,

    i_l1_lp_rx_en,
    i_l1_lp_tx_en,
    o_l1_lp_rx_p,              
    o_l1_lp_rx_n,              
    i_l1_lp_tx_p,              
    i_l1_lp_tx_n,    
    i_l1_hs_rx_en,    
    i_l1_hs_terminator_sel, 
    i_l1_hs_slave_deser_clk_en,
    i_l1_hs_idelay_en,   
    i_l1_hs_idelay_value,                  
    o_l1_hs_rx_data,      
    o_l1_hs_rx_slave_data,

    i_l2_lp_rx_en,
    i_l2_lp_tx_en,
    o_l2_lp_rx_p,              
    o_l2_lp_rx_n,              
    i_l2_lp_tx_p,              
    i_l2_lp_tx_n,  
    i_l2_hs_rx_en,    
    i_l2_hs_terminator_sel,
    i_l2_hs_slave_deser_clk_en,
    i_l2_hs_idelay_en,   
    i_l2_hs_idelay_value,                     
    o_l2_hs_rx_data,      
    o_l2_hs_rx_slave_data,

    i_l3_lp_rx_en,
    i_l3_lp_tx_en,
    o_l3_lp_rx_p,              
    o_l3_lp_rx_n,              
    i_l3_lp_tx_p,              
    i_l3_lp_tx_n,  
    i_l3_hs_rx_en,    
    i_l3_hs_terminator_sel,
    i_l3_hs_slave_deser_clk_en,
    i_l3_hs_idelay_en,   
    i_l3_hs_idelay_value,                     
    o_l3_hs_rx_data,      
    o_l3_hs_rx_slave_data 
);
    inout        io_clk_pad_n;               
    inout        io_clk_pad_p;               
    inout[3:0]   io_data_pad_n;              
    inout[3:0]   io_data_pad_p;              
    output       o_fabric_div4_8_clk;        
    input        i_phy_rst_n;                
    input        i_ck_lp_rx_en;              
    output       o_ck_lp_rx_p;               
    output       o_ck_lp_rx_n;               
    input        i_ck_hs_rx_en;              
    input[1:0]   i_ck_hs_terminator_sel;     
    input        i_ck_hs_idelay_en;          
    input[5:0]   i_ck_hs_idelay_value;       
    input        i_l0_lp_rx_en;              
    input        i_l0_lp_tx_en;              
    output       o_l0_lp_rx_p;               
    output       o_l0_lp_rx_n;               
    input        i_l0_lp_tx_p;               
    input        i_l0_lp_tx_n;               
    input        i_l0_hs_rx_en;              
    input[1:0]   i_l0_hs_terminator_sel;     
    input        i_l0_hs_slave_deser_clk_en; 
    input        i_l0_hs_idelay_en;          
    input[5:0]   i_l0_hs_idelay_value;       
    output[15:0] o_l0_hs_rx_data;            
    output[15:0] o_l0_hs_rx_slave_data;      
    input        i_l1_lp_rx_en;              
    input        i_l1_lp_tx_en;              
    output       o_l1_lp_rx_p;               
    output       o_l1_lp_rx_n;               
    input        i_l1_lp_tx_p;               
    input        i_l1_lp_tx_n;               
    input        i_l1_hs_rx_en;              
    input[1:0]   i_l1_hs_terminator_sel;     
    input        i_l1_hs_slave_deser_clk_en; 
    input        i_l1_hs_idelay_en;          
    input[5:0]   i_l1_hs_idelay_value;       
    output[15:0] o_l1_hs_rx_data;            
    output[15:0] o_l1_hs_rx_slave_data;      
    input        i_l2_lp_rx_en;              
    input        i_l2_lp_tx_en;              
    output       o_l2_lp_rx_p;               
    output       o_l2_lp_rx_n;               
    input        i_l2_lp_tx_p;               
    input        i_l2_lp_tx_n;               
    input        i_l2_hs_rx_en;              
    input[1:0]   i_l2_hs_terminator_sel;     
    input        i_l2_hs_slave_deser_clk_en; 
    input        i_l2_hs_idelay_en;          
    input[5:0]   i_l2_hs_idelay_value;       
    output[15:0] o_l2_hs_rx_data;            
    output[15:0] o_l2_hs_rx_slave_data;      
    input        i_l3_lp_rx_en;              
    input        i_l3_lp_tx_en;              
    output       o_l3_lp_rx_p;               
    output       o_l3_lp_rx_n;               
    input        i_l3_lp_tx_p;               
    input        i_l3_lp_tx_n;               
    input        i_l3_hs_rx_en;              
    input[1:0]   i_l3_hs_terminator_sel;     
    input        i_l3_hs_slave_deser_clk_en; 
    input        i_l3_hs_idelay_en;          
    input[5:0]   i_l3_hs_idelay_value;       
    output[15:0] o_l3_hs_rx_data;            
    output[15:0] o_l3_hs_rx_slave_data;      
    parameter DPHY_RX_LOCATION = "DPHY0";             // "DPHY0", "DPHY1"
    parameter HS_S2P_RATIO = "1:8";                   // "1:8","1:16"
    parameter CK_HS_EQUALIZER = "0dB";                // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter CK_HS_VGA_GAIN  = "12dB";               // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L0_HS_SLAVE_DESER_CLK_OFFSET = "16ps";  // "0ps","16ps","32ps","48ps"
    parameter L0_HS_EQUALIZER              = "0dB";   // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L0_HS_VGA_GAIN               = "12dB";  // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L1_HS_SLAVE_DESER_CLK_OFFSET = "16ps";  // "0ps","16ps","32ps","48ps"
    parameter L1_HS_EQUALIZER              = "0dB";   // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L1_HS_VGA_GAIN               = "12dB";  // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L2_HS_SLAVE_DESER_CLK_OFFSET = "16ps";  // "0ps","16ps","32ps","48ps"
    parameter L2_HS_EQUALIZER              = "0dB";   // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L2_HS_VGA_GAIN               = "12dB";  // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
    parameter L3_HS_SLAVE_DESER_CLK_OFFSET = "16ps";  // "0ps","16ps","32ps","48ps"
    parameter L3_HS_EQUALIZER              = "0dB";   // "0dB","1dB","2dB","3dB","4dB","5dB","6dB","7dB"
    parameter L3_HS_VGA_GAIN               = "12dB";  // "0dB","1.5dB","3dB","4.5dB","6dB","8dB","10dB","12dB"
endmodule
module PH1P_LOGIC_DPHY_MIPI_TX(
    io_clk_pad_n,
    io_clk_pad_p,
    io_data_pad_n,
    io_data_pad_p,

    i_phy_dpll_ref_clk,
    o_fabric_div4_8_clk,

    i_phy_dpll_rst_n,
    i_phy_dpll_pwdn_n,
    i_phy_dpll_vco_bypass_n,
    o_phy_dpll_locked,
    i_phy_dpll_multi_ratio,
    i_phy_dpll_div_ratio,

    i_phy_rst_n,

    i_ck_lp_tx_en,
    i_ck_lp_tx_p,
    i_ck_lp_tx_n,
    i_ck_hs_tx_en,
    i_ck_hs_odelay_value,
    i_ck_hs_tx_data,

    i_l0_lp_tx_en,
    i_l0_lp_tx_p,
    i_l0_lp_tx_n,
    o_l0_lp_rx_p,
    o_l0_lp_rx_n,
    i_l0_hs_tx_en,
    i_l0_hs_odelay_value,
    i_l0_hs_tx_data,

    i_l1_lp_tx_en,
    i_l1_lp_tx_p,
    i_l1_lp_tx_n,
    o_l1_lp_rx_p,
    o_l1_lp_rx_n,
    i_l1_hs_tx_en,
    i_l1_hs_odelay_value,
    i_l1_hs_tx_data,

    i_l2_lp_tx_en,
    i_l2_lp_tx_p,
    i_l2_lp_tx_n,
    o_l2_lp_rx_p,
    o_l2_lp_rx_n,
    i_l2_hs_tx_en,
    i_l2_hs_odelay_value,
    i_l2_hs_tx_data,

    i_l3_lp_tx_en,
    i_l3_lp_tx_p,
    i_l3_lp_tx_n,
    o_l3_lp_rx_p,
    o_l3_lp_rx_n,
    i_l3_hs_tx_en,
    i_l3_hs_odelay_value,
    i_l3_hs_tx_data
);
    inout       io_clk_pad_n;            
    inout       io_clk_pad_p;            
    inout[3:0]  io_data_pad_n;           
    inout[3:0]  io_data_pad_p;           
    input       i_phy_dpll_ref_clk;      
    output      o_fabric_div4_8_clk;     
    input       i_phy_dpll_rst_n;        
    input       i_phy_dpll_pwdn_n;       
    input       i_phy_dpll_vco_bypass_n; 
    output      o_phy_dpll_locked;       
    input[6:0]  i_phy_dpll_multi_ratio;  
    input[5:0]  i_phy_dpll_div_ratio;    
    input       i_phy_rst_n;             
    input       i_ck_lp_tx_en;           
    input       i_ck_lp_tx_p;            
    input       i_ck_lp_tx_n;            
    input       i_ck_hs_tx_en;           
    input[3:0]  i_ck_hs_odelay_value;    
    input[15:0] i_ck_hs_tx_data;         
    input       i_l0_lp_tx_en;           
    input       i_l0_lp_tx_p;            
    input       i_l0_lp_tx_n;            
    output      o_l0_lp_rx_p;            
    output      o_l0_lp_rx_n;            
    input       i_l0_hs_tx_en;           
    input[3:0]  i_l0_hs_odelay_value;    
    input[15:0] i_l0_hs_tx_data;         
    input       i_l1_lp_tx_en;           
    input       i_l1_lp_tx_p;            
    input       i_l1_lp_tx_n;            
    output      o_l1_lp_rx_p;            
    output      o_l1_lp_rx_n;            
    input       i_l1_hs_tx_en;           
    input[3:0]  i_l1_hs_odelay_value;    
    input[15:0] i_l1_hs_tx_data;         
    input       i_l2_lp_tx_en;           
    input       i_l2_lp_tx_p;            
    input       i_l2_lp_tx_n;            
    output      o_l2_lp_rx_p;            
    output      o_l2_lp_rx_n;            
    input       i_l2_hs_tx_en;           
    input[3:0]  i_l2_hs_odelay_value;    
    input[15:0] i_l2_hs_tx_data;         
    input       i_l3_lp_tx_en;           
    input       i_l3_lp_tx_p;            
    input       i_l3_lp_tx_n;            
    output      o_l3_lp_rx_p;            
    output      o_l3_lp_rx_n;            
    input       i_l3_hs_tx_en;           
    input[3:0]  i_l3_hs_odelay_value;    
    input[15:0] i_l3_hs_tx_data;         
    parameter DPHY_TX_LOCATION = "DPHY0";   // "DPHY0", "DPHY1"
    parameter HS_OUTPUT_IMPEDANCE = "50ohm";     // "70ohm","64ohm","58ohm","54ohm","50ohm","47ohm","44ohm","41ohm"
    parameter HS_P2S_RATIO        = "8:1";       // "8:1","16:1"
    parameter HS_OUTPUT_VOD       = "212.5mV";   // "175mV","187.5mV","200mV","212.5mV","225mV","237.5mV","250mV"
    parameter CK_LP_OUTPUT_IMPEDANCE = "110ohm"; // "110ohm","130ohm","160ohm","200ohm"
    parameter CK_LP_OUTPUT_SLEW_RATE = "SLOW";   // "SLOW","MEDIUM","FAST"
    parameter CK_HS_DE_EMPHASIS      = "0dB";    // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter L0_LP_OUTPUT_IMPEDANCE = "110ohm"; // "110ohm","130ohm","160ohm","200ohm"
    parameter L0_LP_OUTPUT_SLEW_RATE = "SLOW";   // "SLOW","MEDIUM","FAST"
    parameter L0_HS_DE_EMPHASIS      = "0dB";    // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter L1_LP_OUTPUT_IMPEDANCE = "110ohm"; // "110ohm","130ohm","160ohm","200ohm"
    parameter L1_LP_OUTPUT_SLEW_RATE = "SLOW";   // "SLOW","MEDIUM","FAST"
    parameter L1_HS_DE_EMPHASIS      = "0dB";    // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter L2_LP_OUTPUT_IMPEDANCE = "110ohm"; // "110ohm","130ohm","160ohm","200ohm"
    parameter L2_LP_OUTPUT_SLEW_RATE = "SLOW";   // "SLOW","MEDIUM","FAST"
    parameter L2_HS_DE_EMPHASIS      = "0dB";    // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter L3_LP_OUTPUT_IMPEDANCE = "110ohm"; // "110ohm","130ohm","160ohm","200ohm"
    parameter L3_LP_OUTPUT_SLEW_RATE = "SLOW";   // "SLOW","MEDIUM","FAST"
    parameter L3_HS_DE_EMPHASIS      = "0dB";    // "0dB","1.5dB","3dB","4.5dB","7dB"
endmodule
module PH1P_LOGIC_HPT(
    io_clk_pad_n,
    io_clk_pad_p,
    io_data_pad_n,
    io_data_pad_p,

    i_tx_rst_n,
    i_rx_rst_n,

    i_rx_pll_to_phy_sample_clk,
    o_rx_phy_to_pll_ref_clk,
    o_rx_div4_8_clk,
    o_rx_div5_10_clk,

    o_tx_div4_8_clk,
    o_tx_div5_10_clk,

    i_tx_dpll_ref_clk,
    i_tx_dpll_rst_n,
    i_tx_dpll_pwdn_n,
    i_tx_dpll_vco_bypass_n,
    o_tx_dpll_locked,
    i_tx_dpll_multi_ratio,
    i_tx_dpll_div_ratio,

    i_tx_ck_en,
    i_tx_ck_odelay,
    i_tx_ck_data,
    i_rx_ck_en,
    i_rx_ck_idelay,
    i_rx_ck_terminator_sel,
    i_rx_ck_ac_coupling_n,
    i_rx_ck_equalizer_sel,
    i_rx_ck_vga_gain_sel,

    i_tx_l0_en,
    i_tx_l0_odelay,
    i_tx_l0_data,
    i_rx_l0_en,
    i_rx_l0_terminator_sel,
    i_rx_l0_ac_coupling_n,
    i_rx_l0_equalizer_sel,
    i_rx_l0_vga_gain_sel,
    i_rx_l0_slave_deser_clk_en,
    i_rx_l0_idelay,
    o_rx_l0_data,
    o_rx_l0_slave_data,

    i_tx_l1_en,
    i_tx_l1_odelay,
    i_tx_l1_data,
    i_rx_l1_en,
    i_rx_l1_terminator_sel,
    i_rx_l1_ac_coupling_n,
    i_rx_l1_equalizer_sel,
    i_rx_l1_vga_gain_sel,
    i_rx_l1_slave_deser_clk_en,
    i_rx_l1_idelay,
    o_rx_l1_data,
    o_rx_l1_slave_data,

    i_tx_l2_en,
    i_tx_l2_odelay,
    i_tx_l2_data,
    i_rx_l2_en,
    i_rx_l2_terminator_sel,
    i_rx_l2_ac_coupling_n,
    i_rx_l2_equalizer_sel,
    i_rx_l2_vga_gain_sel,
    i_rx_l2_slave_deser_clk_en,
    i_rx_l2_idelay,
    o_rx_l2_data,
    o_rx_l2_slave_data,

    i_tx_l3_en,
    i_tx_l3_odelay,
    i_tx_l3_data,
    i_rx_l3_en,
    i_rx_l3_terminator_sel,
    i_rx_l3_ac_coupling_n,
    i_rx_l3_equalizer_sel,
    i_rx_l3_vga_gain_sel,
    i_rx_l3_slave_deser_clk_en,
    i_rx_l3_idelay,
    o_rx_l3_data,
    o_rx_l3_slave_data
);
    inout        io_clk_pad_n;                
    inout        io_clk_pad_p;                
    inout[3:0]   io_data_pad_n;               
    inout[3:0]   io_data_pad_p;               
    input        i_tx_rst_n;                  
    input        i_rx_rst_n;                  
    input        i_rx_pll_to_phy_sample_clk;  
    output       o_rx_phy_to_pll_ref_clk;     
    output       o_rx_div4_8_clk;             
    output       o_rx_div5_10_clk;            
    output       o_tx_div4_8_clk;             
    output       o_tx_div5_10_clk;            
    input        i_tx_dpll_ref_clk;           
    input        i_tx_dpll_rst_n;             
    input        i_tx_dpll_pwdn_n;            
    input        i_tx_dpll_vco_bypass_n;      
    output       o_tx_dpll_locked;            
    input[6:0]   i_tx_dpll_multi_ratio;       
    input[5:0]   i_tx_dpll_div_ratio;         
    input        i_tx_ck_en;                  
    input[3:0]   i_tx_ck_odelay;              
    input[15:0]  i_tx_ck_data;                
    input        i_rx_ck_en;                  
    input[5:0]   i_rx_ck_idelay;              
    input[1:0]   i_rx_ck_terminator_sel;      
    input        i_rx_ck_ac_coupling_n;       
    input[2:0]   i_rx_ck_equalizer_sel;       
    input[2:0]   i_rx_ck_vga_gain_sel;        
    input        i_tx_l0_en;                  
    input[3:0]   i_tx_l0_odelay;              
    input[15:0]  i_tx_l0_data;                
    input        i_rx_l0_en;                  
    input[1:0]   i_rx_l0_terminator_sel;      
    input        i_rx_l0_ac_coupling_n;       
    input[2:0]   i_rx_l0_equalizer_sel;       
    input[2:0]   i_rx_l0_vga_gain_sel;        
    input        i_rx_l0_slave_deser_clk_en;  
    input[5:0]   i_rx_l0_idelay;              
    output[15:0] o_rx_l0_data;                
    output[15:0] o_rx_l0_slave_data;          
    input        i_tx_l1_en;                  
    input[3:0]   i_tx_l1_odelay;              
    input[15:0]  i_tx_l1_data;                
    input        i_rx_l1_en;                  
    input[1:0]   i_rx_l1_terminator_sel;      
    input        i_rx_l1_ac_coupling_n;       
    input[2:0]   i_rx_l1_equalizer_sel;       
    input[2:0]   i_rx_l1_vga_gain_sel;        
    input        i_rx_l1_slave_deser_clk_en;  
    input[5:0]   i_rx_l1_idelay;              
    output[15:0] o_rx_l1_data;                
    output[15:0] o_rx_l1_slave_data;          
    input        i_tx_l2_en;                  
    input[3:0]   i_tx_l2_odelay;              
    input[15:0]  i_tx_l2_data;                
    input        i_rx_l2_en;                  
    input[1:0]   i_rx_l2_terminator_sel;      
    input        i_rx_l2_ac_coupling_n;       
    input[2:0]   i_rx_l2_equalizer_sel;       
    input[2:0]   i_rx_l2_vga_gain_sel;        
    input        i_rx_l2_slave_deser_clk_en;  
    input[5:0]   i_rx_l2_idelay;              
    output[15:0] o_rx_l2_data;                
    output[15:0] o_rx_l2_slave_data;          
    input        i_tx_l3_en;                  
    input[3:0]   i_tx_l3_odelay;              
    input[15:0]  i_tx_l3_data;                
    input        i_rx_l3_en;                  
    input[1:0]   i_rx_l3_terminator_sel;      
    input        i_rx_l3_ac_coupling_n;       
    input[2:0]   i_rx_l3_equalizer_sel;       
    input[2:0]   i_rx_l3_vga_gain_sel;        
    input        i_rx_l3_slave_deser_clk_en;  
    input[5:0]   i_rx_l3_idelay;              
    output[15:0] o_rx_l3_data;                
    output[15:0] o_rx_l3_slave_data;          
    parameter HPT_LOCATION = "HPT0";      // "HPT0", "HPT1"
    parameter TX_P2S_RATIO                     = "8:1";      // "8:1","16:1"
    parameter TX_OUTPUT_IMPEDANCE              = "50ohm";    // "70ohm","64ohm","58ohm","54ohm","50ohm","47ohm","44ohm","41ohm"
    parameter TX_OUTPUT_VOD                    = "450mV";    // "175mV","187.5mV","200mV","212.5mV","225mV","237.5mV","250mV","450mV"
    parameter RX_S2P_RATIO                     = "1:8";      // "1:8","1:16"
    parameter RX_SAMPLE_CLOCK_SEL              = "CLK_LANE"; // "CLK_LANE","PLL"
    parameter TX_CK_DE_EMPHASIS                = "0dB";      // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter RX_CK_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_CK_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_CK_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter RX_CK_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter TX_L0_DE_EMPHASIS                = "0dB";      // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter RX_L0_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter RX_L0_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L0_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L0_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter RX_L0_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter TX_L1_DE_EMPHASIS                = "0dB";      // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter RX_L1_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter RX_L1_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L1_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L1_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter RX_L1_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter TX_L2_DE_EMPHASIS                = "0dB";      // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter RX_L2_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter RX_L2_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L2_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L2_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter RX_L2_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
    parameter TX_L3_DE_EMPHASIS                = "0dB";      // "0dB","1.5dB","3dB","4.5dB","7dB"
    parameter RX_L3_SLAVE_DESER_CLK_OFFSET     = "16ps";     // "0ps","16ps","32ps","48ps"
    parameter RX_L3_IDELAY_ENABLE              = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L3_VCM_COMPENSATION           = "ENABLE";   // "ENABLE","DISABLE"
    parameter RX_L3_DUTY_COMPENSATION          = "0%";       // "0%","1%","2%","3%","4%","5%","6%","7%"
    parameter RX_L3_DUTY_COMPENSATION_POLARITY = "DECREASE"; // "DECREASE","INCREASE"
endmodule
module PH1P_PHY_MIPIIO_RX(
    io_clk_pad_n,
    io_clk_pad_p,
    io_data_pad_n,
    io_data_pad_p,

    i_pll_to_phy_sample_clk,
    o_phy_to_pll_ref_clk,
    o_fabric_div5_10_clk,
    o_fabric_div4_8_clk,

    i_phy_rst_n,
    i_phy_clk_polarity_sel,
    i_phy_hs_sample_clk_sel,
    i_phy_hs_s2p_ratio_sel,  

    i_ck_ls_rx_en,
    i_ck_ls_glitch_reject_sel,
    i_ck_ls_trip_h2l_sel,
    i_ck_ls_trip_l2h_sel,
    i_ck_ls_idelay_value, 
    o_ck_ls_rx_p,
    o_ck_ls_rx_n,
    i_ck_hs_rx_en,
    i_ck_hs_terminator_sel,
    i_ck_hs_equalizer_sel,
    i_ck_hs_idelay_en,
    i_ck_hs_idelay_value,
    i_ck_hs_vga_gain_sel,
    i_ck_hs_filter_sel,    

    i_l0_ls_rx_en,
    i_l0_ls_lp_tx_en,
    i_l0_ls_glitch_reject_sel,
    i_l0_ls_trip_h2l_sel,
    i_l0_ls_trip_l2h_sel,
    i_l0_ls_idelay_value,  
    o_l0_ls_rx_p,
    o_l0_ls_rx_n,
    i_l0_ls_lp_tx_p,
    i_l0_ls_lp_tx_n,
    i_l0_hs_rx_en,
    i_l0_hs_slave_deser_clk_en,
    i_l0_hs_slave_deser_clk_offset,
    i_l0_hs_idelay_en,
    i_l0_hs_idelay_value,
    i_l0_hs_terminator_sel,
    i_l0_hs_equalizer_sel,
    i_l0_hs_vga_gain_sel,
    i_l0_hs_filter_sel,   
    o_l0_hs_rx_data,
    o_l0_hs_rx_slave_data,

    i_l1_ls_rx_en,
    i_l1_ls_lp_tx_en,
    i_l1_ls_glitch_reject_sel,
    i_l1_ls_trip_h2l_sel,
    i_l1_ls_trip_l2h_sel,
    i_l1_ls_idelay_value, 
    o_l1_ls_rx_p,
    o_l1_ls_rx_n,
    i_l1_ls_lp_tx_p,
    i_l1_ls_lp_tx_n,
    i_l1_hs_rx_en,
    i_l1_hs_slave_deser_clk_en,
    i_l1_hs_slave_deser_clk_offset,
    i_l1_hs_idelay_en,
    i_l1_hs_idelay_value,
    i_l1_hs_terminator_sel,
    i_l1_hs_equalizer_sel,
    i_l1_hs_vga_gain_sel,
    i_l1_hs_filter_sel,    
    o_l1_hs_rx_data,
    o_l1_hs_rx_slave_data,

    i_l2_ls_rx_en,
    i_l2_ls_lp_tx_en,
    i_l2_ls_glitch_reject_sel,
    i_l2_ls_trip_h2l_sel,
    i_l2_ls_trip_l2h_sel,
    i_l2_ls_idelay_value,  
    o_l2_ls_rx_p,
    o_l2_ls_rx_n,
    i_l2_ls_lp_tx_p,
    i_l2_ls_lp_tx_n,
    i_l2_hs_rx_en,
    i_l2_hs_slave_deser_clk_en,
    i_l2_hs_slave_deser_clk_offset,
    i_l2_hs_idelay_en,
    i_l2_hs_idelay_value,
    i_l2_hs_terminator_sel,
    i_l2_hs_equalizer_sel,
    i_l2_hs_vga_gain_sel,
    i_l2_hs_filter_sel,    
    o_l2_hs_rx_data,
    o_l2_hs_rx_slave_data,

    i_l3_ls_rx_en,
    i_l3_ls_lp_tx_en,
    i_l3_ls_glitch_reject_sel,
    i_l3_ls_trip_h2l_sel,
    i_l3_ls_trip_l2h_sel,
    i_l3_ls_idelay_value,  
    o_l3_ls_rx_p,
    o_l3_ls_rx_n,
    i_l3_ls_lp_tx_p,
    i_l3_ls_lp_tx_n,
    i_l3_hs_rx_en,
    i_l3_hs_slave_deser_clk_en,
    i_l3_hs_slave_deser_clk_offset,
    i_l3_hs_idelay_en,
    i_l3_hs_idelay_value,
    i_l3_hs_terminator_sel,
    i_l3_hs_equalizer_sel,
    i_l3_hs_vga_gain_sel,
    i_l3_hs_filter_sel,    
    o_l3_hs_rx_data,
    o_l3_hs_rx_slave_data
);
    inout        io_clk_pad_n;                  
    inout        io_clk_pad_p;                  
    inout[3:0]   io_data_pad_n;                 
    inout[3:0]   io_data_pad_p;                 
    input        i_pll_to_phy_sample_clk;       
    output       o_phy_to_pll_ref_clk;          
    output       o_fabric_div5_10_clk;          
    output       o_fabric_div4_8_clk;           
    input        i_phy_rst_n;                   
    input        i_phy_clk_polarity_sel;        
    input        i_phy_hs_sample_clk_sel;       
    input        i_phy_hs_s2p_ratio_sel;        
    input        i_ck_ls_rx_en;                 
    input[1:0]   i_ck_ls_glitch_reject_sel;     
    input[2:0]   i_ck_ls_trip_h2l_sel;          
    input[2:0]   i_ck_ls_trip_l2h_sel;          
    input[6:0]   i_ck_ls_idelay_value;          
    output       o_ck_ls_rx_p;                  
    output       o_ck_ls_rx_n;                  
    input        i_ck_hs_rx_en;                 
    input[1:0]   i_ck_hs_terminator_sel;        
    input[2:0]   i_ck_hs_equalizer_sel;         
    input        i_ck_hs_idelay_en;             
    input[5:0]   i_ck_hs_idelay_value;          
    input[2:0]   i_ck_hs_vga_gain_sel;          
    input        i_ck_hs_filter_sel;            
    input        i_l0_ls_rx_en;                 
    input        i_l0_ls_lp_tx_en;              
    input[1:0]   i_l0_ls_glitch_reject_sel;     
    input[2:0]   i_l0_ls_trip_h2l_sel;          
    input[2:0]   i_l0_ls_trip_l2h_sel;          
    input[6:0]   i_l0_ls_idelay_value;          
    output       o_l0_ls_rx_p;                  
    output       o_l0_ls_rx_n;                  
    input        i_l0_ls_lp_tx_p;               
    input        i_l0_ls_lp_tx_n;               
    input        i_l0_hs_rx_en;                 
    input        i_l0_hs_slave_deser_clk_en;    
    input[1:0]   i_l0_hs_slave_deser_clk_offset;
    input        i_l0_hs_idelay_en;             
    input[5:0]   i_l0_hs_idelay_value;          
    input[1:0]   i_l0_hs_terminator_sel;        
    input[2:0]   i_l0_hs_equalizer_sel;         
    input[2:0]   i_l0_hs_vga_gain_sel;          
    input        i_l0_hs_filter_sel;            
    output[15:0] o_l0_hs_rx_data;               
    output[15:0] o_l0_hs_rx_slave_data;         
    input        i_l1_ls_rx_en;                 
    input        i_l1_ls_lp_tx_en;              
    input[1:0]   i_l1_ls_glitch_reject_sel;     
    input[2:0]   i_l1_ls_trip_h2l_sel;          
    input[2:0]   i_l1_ls_trip_l2h_sel;          
    input[6:0]   i_l1_ls_idelay_value;          
    output       o_l1_ls_rx_p;                  
    output       o_l1_ls_rx_n;                  
    input        i_l1_ls_lp_tx_p;               
    input        i_l1_ls_lp_tx_n;               
    input        i_l1_hs_rx_en;                 
    input        i_l1_hs_slave_deser_clk_en;    
    input[1:0]   i_l1_hs_slave_deser_clk_offset;
    input        i_l1_hs_idelay_en;             
    input[5:0]   i_l1_hs_idelay_value;          
    input[1:0]   i_l1_hs_terminator_sel;        
    input[2:0]   i_l1_hs_equalizer_sel;         
    input[2:0]   i_l1_hs_vga_gain_sel;          
    input        i_l1_hs_filter_sel;            
    output[15:0] o_l1_hs_rx_data;               
    output[15:0] o_l1_hs_rx_slave_data;         
    input        i_l2_ls_rx_en;                 
    input        i_l2_ls_lp_tx_en;              
    input[1:0]   i_l2_ls_glitch_reject_sel;     
    input[2:0]   i_l2_ls_trip_h2l_sel;          
    input[2:0]   i_l2_ls_trip_l2h_sel;          
    input[6:0]   i_l2_ls_idelay_value;          
    output       o_l2_ls_rx_p;                  
    output       o_l2_ls_rx_n;                  
    input        i_l2_ls_lp_tx_p;               
    input        i_l2_ls_lp_tx_n;               
    input        i_l2_hs_rx_en;                 
    input        i_l2_hs_slave_deser_clk_en;    
    input[1:0]   i_l2_hs_slave_deser_clk_offset;
    input        i_l2_hs_idelay_en;             
    input[5:0]   i_l2_hs_idelay_value;          
    input[1:0]   i_l2_hs_terminator_sel;        
    input[2:0]   i_l2_hs_equalizer_sel;         
    input[2:0]   i_l2_hs_vga_gain_sel;          
    input        i_l2_hs_filter_sel;            
    output[15:0] o_l2_hs_rx_data;               
    output[15:0] o_l2_hs_rx_slave_data;         
    input        i_l3_ls_rx_en;                 
    input        i_l3_ls_lp_tx_en;              
    input[1:0]   i_l3_ls_glitch_reject_sel;     
    input[2:0]   i_l3_ls_trip_h2l_sel;          
    input[2:0]   i_l3_ls_trip_l2h_sel;          
    input[6:0]   i_l3_ls_idelay_value;          
    output       o_l3_ls_rx_p;                  
    output       o_l3_ls_rx_n;                  
    input        i_l3_ls_lp_tx_p;               
    input        i_l3_ls_lp_tx_n;               
    input        i_l3_hs_rx_en;                 
    input        i_l3_hs_slave_deser_clk_en;    
    input[1:0]   i_l3_hs_slave_deser_clk_offset;
    input        i_l3_hs_idelay_en;             
    input[5:0]   i_l3_hs_idelay_value;          
    input[1:0]   i_l3_hs_terminator_sel;        
    input[2:0]   i_l3_hs_equalizer_sel;         
    input[2:0]   i_l3_hs_vga_gain_sel;          
    input        i_l3_hs_filter_sel;            
    output[15:0] o_l3_hs_rx_data;               
    output[15:0] o_l3_hs_rx_slave_data;         
    parameter PHY_RX_EN        = "ENABLE";  // "ENABLE", "DISABLE"
    parameter DPHY_RX_LOCATION = "DPHY0";   // "DPHY0", "DPHY1"
    parameter DPHY_TIMING_MODE = "MIPI";    // "MIPI", "LVDS", "LVCMOS"
endmodule
module PH1P_PHY_MIPIIO_TX (
    io_clk_pad_n,
    io_clk_pad_p,
    io_data_pad_n,
    io_data_pad_p,

    i_phy_hs_mipi_cp_sel,

    i_phy_hs_mipi_latch_res_sel,
    i_phy_vcp_ref_sel,
    i_phy_dpll_freq_lock_bypass,
    i_phy_dpll_freq_lock_speed,
    i_phy_dpll_ki_sel,
    i_phy_dpll_kp_sel,
    i_phy_dpll_lock_detect_sel,
    o_phy_dpll_freq_locked,
    i_phy_hs_vcm_gen_sel,
    i_phy_clk_polarity_sel,

    i_phy_dpll_ref_clk,
    o_fabric_div5_10_clk,
    o_fabric_div4_8_clk,

    i_phy_dpll_rst_n,
    i_phy_dpll_pwdn_n,
    i_phy_dpll_vco_bypass_n,
    o_phy_dpll_locked,
    i_phy_dpll_multi_ratio,
    i_phy_dpll_div_ratio,

    i_phy_rst_n,
    i_phy_mipi_mode_en,
    i_phy_hs_mipi_impedance_sel, 
    i_phy_hs_p2s_ratio_sel,
    i_phy_hs_mipi_vod_sel,       
    i_phy_hs_lvds_vcm_sel,    
    i_phy_hs_lvds_vod_extra_gain,   
    i_phy_hs_lvds_ocp_en,        

    i_ck_ls_lp_tx_en,
    i_ck_ls_lvcmos_tx_en,
    i_ck_ls_lp_impedance_sel,
    i_ck_ls_lvcmos_drv_sel,
    i_ck_ls_slew_rate_sel,
    i_ck_ls_tx_p,
    i_ck_ls_tx_n,
    i_ck_hs_mipi_tx_en,
    i_ck_hs_lvds_tx_en,
    i_ck_hs_odelay_value,
    i_ck_hs_mipi_de_emphasis_sel,
    i_ck_hs_lvds_de_emphasis_sel,
    i_ck_hs_lvds_vod_sel,
    i_ck_hs_tx_data,

    i_l0_ls_lp_tx_en,
    i_l0_ls_lvcmos_tx_en,
    i_l0_ls_lp_impedance_sel,
    i_l0_ls_lvcmos_drv_sel,
    i_l0_ls_slew_rate_sel,
    i_l0_ls_tx_p,
    i_l0_ls_tx_n,
    o_l0_ls_lp_rx_p,
    o_l0_ls_lp_rx_n,
    i_l0_hs_mipi_tx_en,
    i_l0_hs_lvds_tx_en,
    i_l0_hs_odelay_value,
    i_l0_hs_mipi_de_emphasis_sel,
    i_l0_hs_lvds_de_emphasis_sel,
    i_l0_hs_lvds_vod_sel,
    i_l0_hs_tx_data,

    i_l1_ls_lp_tx_en,
    i_l1_ls_lvcmos_tx_en,
    i_l1_ls_lp_impedance_sel,
    i_l1_ls_lvcmos_drv_sel,
    i_l1_ls_slew_rate_sel,
    i_l1_ls_tx_p,
    i_l1_ls_tx_n,
    o_l1_ls_lp_rx_p,
    o_l1_ls_lp_rx_n,
    i_l1_hs_mipi_tx_en,
    i_l1_hs_lvds_tx_en,
    i_l1_hs_odelay_value,
    i_l1_hs_mipi_de_emphasis_sel,
    i_l1_hs_lvds_de_emphasis_sel,
    i_l1_hs_lvds_vod_sel,
    i_l1_hs_tx_data,

    i_l2_ls_lp_tx_en,
    i_l2_ls_lvcmos_tx_en,
    i_l2_ls_lp_impedance_sel,
    i_l2_ls_lvcmos_drv_sel,
    i_l2_ls_slew_rate_sel,
    i_l2_ls_tx_p,
    i_l2_ls_tx_n,
    o_l2_ls_lp_rx_p,
    o_l2_ls_lp_rx_n,
    i_l2_hs_mipi_tx_en,
    i_l2_hs_lvds_tx_en,
    i_l2_hs_odelay_value,
    i_l2_hs_mipi_de_emphasis_sel,
    i_l2_hs_lvds_de_emphasis_sel,
    i_l2_hs_lvds_vod_sel,
    i_l2_hs_tx_data,

    i_l3_ls_lp_tx_en,
    i_l3_ls_lvcmos_tx_en,
    i_l3_ls_lp_impedance_sel,
    i_l3_ls_lvcmos_drv_sel,
    i_l3_ls_slew_rate_sel,
    i_l3_ls_tx_p,
    i_l3_ls_tx_n,
    o_l3_ls_lp_rx_p,
    o_l3_ls_lp_rx_n,
    i_l3_hs_mipi_tx_en,
    i_l3_hs_lvds_tx_en,
    i_l3_hs_odelay_value,
    i_l3_hs_mipi_de_emphasis_sel,
    i_l3_hs_lvds_de_emphasis_sel,
    i_l3_hs_lvds_vod_sel,
    i_l3_hs_tx_data
);
    inout        io_clk_pad_n;                
    inout        io_clk_pad_p;                
    inout[3:0]   io_data_pad_n;               
    inout[3:0]   io_data_pad_p;               
    input[2:0]   i_phy_hs_mipi_cp_sel;        
    input[1:0]   i_phy_hs_mipi_latch_res_sel; 
    input[1:0]   i_phy_vcp_ref_sel;           
    input        i_phy_dpll_freq_lock_bypass; 
    input        i_phy_dpll_freq_lock_speed;  
    input[1:0]   i_phy_dpll_ki_sel;           
    input[1:0]   i_phy_dpll_kp_sel;           
    input[1:0]   i_phy_dpll_lock_detect_sel;  
    output       o_phy_dpll_freq_locked;      
    input        i_phy_hs_vcm_gen_sel;        
    input        i_phy_clk_polarity_sel;      
    input        i_phy_dpll_ref_clk;          
    output       o_fabric_div5_10_clk;        
    output       o_fabric_div4_8_clk;         
    input        i_phy_dpll_rst_n;            
    input        i_phy_dpll_pwdn_n;           
    input        i_phy_dpll_vco_bypass_n;     
    output       o_phy_dpll_locked;           
    input [6:0]  i_phy_dpll_multi_ratio;      
    input [5:0]  i_phy_dpll_div_ratio;        
    input        i_phy_rst_n;                 
    input        i_phy_mipi_mode_en;          
    input[2:0]   i_phy_hs_mipi_impedance_sel; 
    input        i_phy_hs_p2s_ratio_sel;      
    input[2:0]   i_phy_hs_mipi_vod_sel;       
    input[2:0]   i_phy_hs_lvds_vcm_sel;       
    input        i_phy_hs_lvds_vod_extra_gain;
    input        i_phy_hs_lvds_ocp_en;        
    input        i_ck_ls_lp_tx_en;            
    input        i_ck_ls_lvcmos_tx_en;        
    input[1:0]   i_ck_ls_lp_impedance_sel;    
    input[1:0]   i_ck_ls_lvcmos_drv_sel;      
    input[1:0]   i_ck_ls_slew_rate_sel;       
    input        i_ck_ls_tx_p;                
    input        i_ck_ls_tx_n;                
    input        i_ck_hs_mipi_tx_en;          
    input        i_ck_hs_lvds_tx_en;          
    input[3:0]   i_ck_hs_odelay_value;        
    input[2:0]   i_ck_hs_mipi_de_emphasis_sel;
    input[1:0]   i_ck_hs_lvds_de_emphasis_sel;
    input[2:0]   i_ck_hs_lvds_vod_sel;        
    input[15:0]  i_ck_hs_tx_data;             
    input        i_l0_ls_lp_tx_en;            
    input        i_l0_ls_lvcmos_tx_en;        
    input[1:0]   i_l0_ls_lp_impedance_sel;    
    input[1:0]   i_l0_ls_lvcmos_drv_sel;      
    input[1:0]   i_l0_ls_slew_rate_sel;       
    input        i_l0_ls_tx_p;                
    input        i_l0_ls_tx_n;                
    output       o_l0_ls_lp_rx_p;             
    output       o_l0_ls_lp_rx_n;             
    input        i_l0_hs_mipi_tx_en;          
    input        i_l0_hs_lvds_tx_en;          
    input[3:0]   i_l0_hs_odelay_value;        
    input[2:0]   i_l0_hs_mipi_de_emphasis_sel;
    input[1:0]   i_l0_hs_lvds_de_emphasis_sel;
    input[2:0]   i_l0_hs_lvds_vod_sel;        
    input[15:0]  i_l0_hs_tx_data;             
    input        i_l1_ls_lp_tx_en;            
    input        i_l1_ls_lvcmos_tx_en;        
    input[1:0]   i_l1_ls_lp_impedance_sel;    
    input[1:0]   i_l1_ls_lvcmos_drv_sel;      
    input[1:0]   i_l1_ls_slew_rate_sel;       
    input        i_l1_ls_tx_p;                
    input        i_l1_ls_tx_n;                
    output       o_l1_ls_lp_rx_p;             
    output       o_l1_ls_lp_rx_n;             
    input        i_l1_hs_mipi_tx_en;          
    input        i_l1_hs_lvds_tx_en;          
    input[3:0]   i_l1_hs_odelay_value;        
    input[2:0]   i_l1_hs_mipi_de_emphasis_sel;
    input[1:0]   i_l1_hs_lvds_de_emphasis_sel;
    input[2:0]   i_l1_hs_lvds_vod_sel;        
    input[15:0]  i_l1_hs_tx_data;             
    input        i_l2_ls_lp_tx_en;            
    input        i_l2_ls_lvcmos_tx_en;        
    input[1:0]   i_l2_ls_lp_impedance_sel;    
    input[1:0]   i_l2_ls_lvcmos_drv_sel;      
    input[1:0]   i_l2_ls_slew_rate_sel;       
    input        i_l2_ls_tx_p;                
    input        i_l2_ls_tx_n;                
    output       o_l2_ls_lp_rx_p;             
    output       o_l2_ls_lp_rx_n;             
    input        i_l2_hs_mipi_tx_en;          
    input        i_l2_hs_lvds_tx_en;          
    input[3:0]   i_l2_hs_odelay_value;        
    input[2:0]   i_l2_hs_mipi_de_emphasis_sel;
    input[1:0]   i_l2_hs_lvds_de_emphasis_sel;
    input[2:0]   i_l2_hs_lvds_vod_sel;        
    input[15:0]  i_l2_hs_tx_data;             
    input        i_l3_ls_lp_tx_en;            
    input        i_l3_ls_lvcmos_tx_en;        
    input[1:0]   i_l3_ls_lp_impedance_sel;    
    input[1:0]   i_l3_ls_lvcmos_drv_sel;      
    input[1:0]   i_l3_ls_slew_rate_sel;       
    input        i_l3_ls_tx_p;                
    input        i_l3_ls_tx_n;                
    output       o_l3_ls_lp_rx_p;             
    output       o_l3_ls_lp_rx_n;             
    input        i_l3_hs_mipi_tx_en;          
    input        i_l3_hs_lvds_tx_en;          
    input[3:0]   i_l3_hs_odelay_value;        
    input[2:0]   i_l3_hs_mipi_de_emphasis_sel;
    input[1:0]   i_l3_hs_lvds_de_emphasis_sel;
    input[2:0]   i_l3_hs_lvds_vod_sel;        
    input[15:0]  i_l3_hs_tx_data;             
    parameter PHY_TX_EN        = "ENABLE";  // "ENABLE", "DISABLE"
    parameter DPHY_TX_LOCATION = "DPHY0";   // "DPHY0", "DPHY1"
    parameter DPHY_TIMING_MODE = "MIPI";    // "MIPI", "LVDS", "LVCMOS"
endmodule
module PH1P_PHY_CLOCK_ALIGNER ( 
        refclk,
        fbclk,
        rst_n,
        clk_out,
        lock     
);
input       refclk;                                         
input       fbclk;                                          
input       rst_n;                                          
output      clk_out;                                        
output      lock;                                           
parameter   FIN                =   "100.0000";              
parameter   POST_DIV           =   0;                       // 0~7
parameter   BYPASS             =   "DISABLE"  ;             // "ENABLE", "DISABLE"
parameter   FEED_TYPE          =   "INTERNAL"  ;            // "INTERNAL", "EXTERNAL"
parameter   POWER_DOWN         =   "DISABLE";               // "ENABLE", "DISABLE"
endmodule
module PH1P_PHY_ERAM_V2 (
  dia, 
  dia_extra, 
  csa,
  addra, 
  ocea, 
  clka, 
  wea,
  orsta, 
  dib, 
  dib_extra, 
  csb,
  addrb, 
  oceb, 
  clkb, 
  web,
  orstb, 
  doa,
  doa_extra,
  dob,
  dob_extra,
  ecc_sbiterr,
  ecc_dbiterr,
  ecc_sbiterrinj,
  ecc_dbiterrinj,
//  fifoctrl_fifoen,// fifoctrl_* comes from fifoctrl hard module, just for simulation, no need customer/SW to connection
  fifoctrl_waddr,//following 4 signs just for simulation, no need connection
  fifoctrl_raddr,// 
  fifoctrl_we,   //
  fifoctrl_re,    //
  addra_casin, // cascade addra in
  addrb_casin, // cascade addrb in
  addra_casout, // cascade addra out
  addrb_casout,  // cascade addra out
  pib_rst_redmeet_n, // input for internal test, default 1
  probe_redmeet_pa, // output for test port A
  probe_redmeet_pb // output for test port B
);
output  [15:0] doa;
output  [15:0] dob;
output  [3:0] doa_extra;
output  [3:0] dob_extra;
input   [15:0] dia;         
input   [15:0] dib;         
input   [3:0] dia_extra;    
input   [3:0] dib_extra;    
input   [2:0] csa;          
input   [2:0] csb;          
input   ocea;               
input   clka;               
input   wea;                
input   orsta;              
input   oceb;               
input   clkb;               
input   web;                
input   orstb;              
input   [13:0] addra;       
input   [13:0] addrb;       
output  ecc_sbiterr;
output  ecc_dbiterr; 
input   [13:0] fifoctrl_waddr;  
input   [13:0] fifoctrl_raddr;  
input   fifoctrl_we;            
input   fifoctrl_re;            
input   [13:0] addra_casin;     
input   [13:0] addrb_casin;     
output  [13:0] addra_casout;    
output  [13:0] addrb_casout;    
input   ecc_sbiterrinj;
input   ecc_dbiterrinj;
input  pib_rst_redmeet_n; 
output  probe_redmeet_pa; 
output  probe_redmeet_pb; 
parameter MODE = "DP20K";               // "DP20K", "FIFO20K"
parameter FIFOMODE = "DISABLE";         // "DISABLE", "ENABLE"
parameter DATA_WIDTH_A = "20";          // "1", "2", "5", "10", "20", "40"
parameter DATA_WIDTH_B = "20";          // "1", "2", "5", "10", "20", "40"
parameter CLKMODE = "ASYNC";            // "ASYNC","SYNC"
parameter READBACK = "DISABLE";         // "DISABLE","ENABLE"
parameter DEVICE = "PHONEX";
parameter SPEEDLEVEL ="1";
parameter REGMODE_A = "NOREG";          // "NOREG", "OUTREG"
parameter REGMODE_B = "NOREG";          // "NOREG", "OUTREG"
parameter WRITEMODE_A = "NORMAL";       // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH"
parameter WRITEMODE_B = "NORMAL";       // "NORMAL", "READBEFOREWRITE", "WRITETHROUGH"
parameter GSR = "ENABLE";               // "DISABLE", "ENABLE"
parameter OREGSET_A = "SET";            // "SET", "RESET"
parameter OREGSET_B = "SET";            // "SET", "RESET"
parameter ASYNC_RESET_RELEASE_A = "SYNC";  // "SYNC", "ASYNC"
parameter ASYNC_RESET_RELEASE_B = "SYNC";  // "SYNC", "ASYNC"
parameter RESETMODE_A = "ASYNC";          // "ASYNC", "SYNC"
parameter RESETMODE_B = "ASYNC";          // "ASYNC", "SYNC"
parameter SSROVERCE = "DISABLE";  // "DISABLE","ENABLE"
parameter ECC_DECODE = "DISABLE"; // "DISABLE","ENABLE"
parameter ECC_ENCODE = "DISABLE"; // "DISABLE","ENABLE"
parameter OCEAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter OCEBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter RSTAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter RSTBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter CLKAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter CLKBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter WEAMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter WEBMUX = "SIG"; // "0", "1", "INV", "SIG"
parameter CSA0 = "SIG" ;  // "0","1","SIG"
parameter CSA1 = "SIG" ;  // "0","1","SIG","INV"
parameter CSA2 = "SIG" ;  // "0","1","SIG","INV"
parameter CSB0 = "SIG" ;  // "0","1","SIG"
parameter CSB1 = "SIG" ;  // "0","1","SIG","INV"
parameter CSB2 = "SIG" ;  // "0","1","SIG","INV"
parameter LADDRCAS_A = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter LADDRCAS_B = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter HADDRCAS_A = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter HADDRCAS_B = "NORMAL";// "NORMAL","CASFB","FIFO"
parameter INIT_ENABLE=1; 
parameter INIT_FILE = "";
parameter INITP_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INITP_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_00 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_01 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_02 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_03 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_04 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_05 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_06 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_07 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_08 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_09 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_0F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_10 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_11 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_12 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_13 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_14 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_15 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_16 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_17 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_18 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_19 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_1F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_20 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_21 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_22 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_23 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_24 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_25 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_26 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_27 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_28 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_29 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_2F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_30 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_31 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_32 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_33 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_34 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_35 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_36 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_37 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_38 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_39 = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3A = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3B = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3C = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3D = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3E = 256'h0000000000000000000000000000000000000000000000000000000000000000;
parameter INIT_3F = 256'h0000000000000000000000000000000000000000000000000000000000000000;
endmodule
module PH1P_PHY_GCLK(
 seln,
 cen,
 drct,
 clkin,
 clkout
 );
 input [1:0] seln , cen , drct , clkin;
 output clkout;
 parameter PRESELECT = "CLK0";       // "CLK0", "CLK1".
 parameter HOLD = "YES";	         // "YES", "NO".
 parameter SEL_TRIGGER = "POS";      // "POS", "NEG.
 parameter GSR = "ENABLE";           // "ENABLE", "DISABLE".
endmodule
module PH1P_PHY_LCLK
(
 ce,
 clkin,
 rst,
 clkout,
 clkdivout
);
 input  ce; 
 input  rst ;
 input  clkin;                          
 output clkout  ;                       
 output clkdivout ;                     
 parameter CEMD = "SYNC";              // "SYNC" , "ASYNC".
 parameter CLKSEL = "ORG";             // "ORG" , "INV".
 parameter DIV = "1";                  // "1", "2", "3", "4", "5", "6", "7", "8", "3P5"
 parameter LCLK = "BYPASS";            // "BYPASS" , "DIV2TO8" , "DIV1" , "GND".
 parameter GSR = "ENABLE";             // "ENABLE", "DISABLE".
endmodule
module PH1P_PHY_MLCLK
(
 ce ,
 clkin ,
 clkout
);
 input ce ;
 input clkin ;                          
 output clkout;                         
 parameter GSR = "ENABLE";             // "ENABLE", "DISABLE"
 parameter BYPASS="ENABLE";            // "ENABLE", "DISABLE"
endmodule
module PH1P_PHY_SCLK
(
 ce ,
 clkin ,
 clkout
);
 input ce ;
 input clkin ;                         
 output clkout;                        
 parameter GSR = "ENABLE";             // "ENABLE", "DISABLE"
 parameter BYPASS = "ENABLE";          // "ENABLE", "DISABLE"
 parameter DELAY  = 0;                 // 0~3
endmodule
module PH1P_PHY_HCLK
(
 ce ,
 clkin ,
 clkout
);
 input ce ;                             
 input clkin ;                          
 output clkout;                         
 parameter GSR = "ENABLE";             // "ENABLE","DISABLE".
 parameter BYPASS = "ENABLE";          // "ENABLE","DISABLE".
 parameter DELAY  = 0;                 // 0~3.
endmodule
module PH1P_PHY_SCLK_V2
(
 ce ,
 clkin ,
 dlytrim ,
 clkout
);
 input ce ;
 input clkin ;                          
 input [1:0] dlytrim ;  
 output clkout;                         
 parameter GSR = "ENABLE";             // "ENABLE", "DISABLE"
 parameter BYPASS = "ENABLE";          // "ENABLE", "DISABLE"
 parameter DELAY  = 0;                 // 0~3
 parameter DELAY_DYN = "DISABLE";      // "ENABLE", "DISABLE"
endmodule
module  PH1P_PHY_PCIE_V1
(
    // Transcation Layer Clock Signals
    tl_clk_user                                 ,
    tl_clk_user_ce_n                            ,

    // Physical Layer Clock Signals
    pl_pclk_user                                ,

    // Other Clock And Reset Signals
    tl_clk_gate                                 ,
    tl_clk_user_freq                            ,
    tl_power_on_rst                             ,
    tl_por                                      ,
    tl_mperst                                   ,
    tl_rdy                                      ,
    tl_rdy_conf                                 ,
    tl_rst                                      ,
    tl_crst                                     ,
    tl_k_rst                                    ,
    tl_flr_req                                  ,

    // User APB Configure Signals
    tl_cfg_pclk                                 ,
    tl_cfg_prst                                 ,
    tl_cfg_penable                              ,
    tl_cfg_psel                                 ,
    tl_cfg_pwrite                               ,
    tl_cfg_paddr                                ,
    tl_cfg_pstrb                                ,
    tl_cfg_pwdata                               ,
    tl_cfg_pready                               ,
    tl_cfg_prdata                               ,
    tl_cfg_pslverr                              ,

    // CFG Direct Access
    tl_cfg_tcvc                                 ,
    tl_cfg_busdev                               ,
    tl_cfg_max_payload_size                     ,
    tl_cfg_max_read_request_size                ,
    tl_cfg_current_link_speed                   ,
    tl_cfg_negotiated_width                     ,
    tl_cfg_read_completion_boundary             ,
    tl_cfg_pfregs_vfnums                        ,
    tl_cfg_pfregs_vfenable                      ,
    tl_cfg_pfregs_vfmse                         ,
    tl_cfg_pfregs_cmd                           ,
    tl_cfg_vfregs_bit_sel                       ,
    tl_cfg_vfregs_bit                           ,
    tl_cfg_pf0_primary_bus                      ,
    tl_cfg_pf1_primary_bus                      ,

    // PF Legacy INT/MSI
    tl_int_status                               ,
    tl_int_msireq                               ,
    tl_int_msinum                               ,
    tl_int_msiack                               ,
    tl_int_msi_enable                           ,
    tl_int_msi_multi_enable                     ,
    tl_int_pf0_msi_pending                      ,
    tl_int_pf1_msi_pending                      ,
    tl_int_pf0_msi_mask                         ,
    tl_int_pf1_msi_mask                         ,
    tl_int_pincontrol                           ,
    tl_int_pinstate                             ,

    // PF MSIX
    tl_cfg_msix_enable                          ,
    tl_cfg_msix_function_mask                   ,

    // VF MSI
    tl_int_vfmsifid                             ,
    tl_int_vfmsinum                             ,
    tl_int_vfmsireq                             ,
    tl_int_vfmsiack                             ,
    tl_int_vfmsi_enable_mask_sel                ,
    tl_int_vfmsi_enable                         ,
    tl_int_vfmsi_mask                           ,

    // Physical Ltssm Signals
    pl_equ_phase                                ,
    tl_ltssm                                    ,
    pl_ltssm                                    ,
    pl_link_up                                  ,
    pl_ltssm_enable                             ,

    // PM Clock
    pl_clkreq_in                                ,
    tl_pm_l1ss_entack                           ,
    tl_pm_refclk_rem                            ,
    pl_clkreq_oen                               ,
    tl_pm_l1ss_entreq                           ,
    tl_pm_l1ss_status                           ,

    // PM Legacy/Native
    pl_wake_in                                  ,
    tl_pm_auxpwr                                ,
    tl_pm_data                                  ,
    tl_pm_event                                 ,
    tl_pm_lx_control                            ,
    pl_wake_oen                                 ,
    tl_pm_lx_status                             ,

    // PM Link Width/Speed
    tl_pm_bwchange_linkwidth_change_req         ,
    tl_pm_bwchange_allowed_linkwidth            ,
    tl_pm_bwchange_linkspeed_change_req         ,
    tl_pm_bwchange_max_linkspeed                ,

    // Report
    tl_report_error_10_1_bits                   ,
    tl_report_error_22_12_bits                  ,
    tl_report_error_63_40_bits                  ,
    tl_report_header                            ,
    tl_report_hotplug                           ,
    tl_report_latency                           ,
    tl_report_state_pf0_misc_control            ,
    tl_report_state_pf1_misc_control            ,
    tl_report_vfstate_override_sel              ,
    tl_report_vfstate_override_bit              ,
    tl_report_event                             ,

    // Rx Interface
    tl_rx_wait                                  ,
    tl_rx_masknp                                ,
    tl_rx_bardec                                ,
    tl_rx_data                                  ,
    tl_rx_eop                                   ,
    tl_rx_err                                   ,
    tl_rx_mchit                                 ,
    tl_rx_sop                                   ,
    tl_rx_valid                                 ,

    // Tx Interface
    tl_tx_data                                  ,
    tl_tx_eop                                   ,
    tl_tx_err                                   ,
    tl_tx_sop                                   ,
    tl_tx_stream                                ,
    tl_tx_valid                                 ,
    tl_tx_wait                                  ,
    tl_tx_credits                               ,

    // External Register Interface
    tl_cfg_xrdata                               ,
    tl_cfg_xready                               ,
    tl_cfg_xaddr                                ,
    tl_cfg_xenable                              ,
    tl_cfg_xfid                                 ,
    tl_cfg_xstrb                                ,
    tl_cfg_xwdata                               ,
    tl_cfg_xwrite                               ,

    // VPD Cap Signals
    tl_vpd_rddata                               ,
    tl_vpd_ready                                ,
    tl_vpd_addr                                 ,
    tl_vpd_enable                               ,
    tl_vpd_status                               ,
    tl_vpd_wrdata                               ,
    tl_vpd_write                                ,

    // OBFF Signals
    tl_pm_obffcontrol                           ,
    tl_pm_obffstatus                            ,

    // PTM Signals
    tl_ptm_in                                   ,
    tl_ptm_out                                  ,

    // DOE Cap Signals
    tl_doe_rddata                               ,
    tl_doe_pf0_status                           ,
    tl_doe_pf1_status                           ,
    tl_doe_control                              ,
    tl_doe_wrdata                               ,

    // SCAN & DFT Signals
    scan_clk                                    ,
    scan_in                                     ,
    scan_out                                    ,
    scan_mode_n                                 ,
    scan_rst_n                                  ,
    scan_enable_n                               ,
    scancompress_mode_n                         ,
    mbist_mode_n                                ,
    dft_jtag_tck                                ,
    dft_jtag_trst_n                             ,
    dft_jtag_tms                                ,
    dft_jtag_tdi                                ,
    dft_jtag_tdo                                ,

    // Pin Share Select
    pinshare_grp0_out_sel                       ,
    pinshare_grp1_out_sel                       ,

    // Test
    test_in_errinj_8_0_bits                     ,
    test_in_errinj_20_16_bits                   ,
    test_out_rxval                              ,
    test_out_txdatak                            ,
    test_out_txval                              ,
    pl_sideband                                 ,

    // All Signals Are Hardwire Below
    // Serdes Bonded Interface
    cfg_power_on_rst_n                          ,
    cfg_pipe_lane_flip                          ,
    cfg_pcs_pipe_rst_n                          ,
    cfg_pcs_apb_rst_n                           ,
    cfg_pclk_source_sel                         ,
    cfg_pcie_lane_enable                        ,
    cfg_core_sram_init_done                     ,
    cfg_core_bypass                             ,
    serdes_osc_clk                              ,
    pl_pclk                                     ,

    //PIPE Signals
    pl_sideband_in                              ,
    pl_sideband_out                             ,
    pl_pclk_rate                                ,
    pl_phystatus                                ,
    pl_powerdown                                ,
    pl_rate                                     ,
    pl_rxdata                                   ,
    pl_rxdatak                                  ,
    pl_rxdatavalid                              ,
    pl_rxelecidle                               ,
    pl_rxstandby                                ,
    pl_rxstartblock                             ,
    pl_rxstatus                                 ,
    pl_rxsyncheader                             ,
    pl_rxvalid                                  ,
    pl_txcompliance                             ,
    pl_txdata                                   ,
    pl_txdatak                                  ,
    pl_txdatavalid                              ,
    pl_txdetectrx                               ,
    pl_txelecidle                               ,
    pl_txstartblock                             ,
    pl_txsyncheader                             ,
    pl_width                                     

);
    input                           tl_clk_user                             ;
    input                           tl_clk_user_ce_n                        ;
    output                          pl_pclk_user                            ;
    output                          tl_clk_gate                             ;
    input       [8:0]               tl_clk_user_freq                        ;
    input                           tl_power_on_rst                         ;
    input                           tl_por                                  ;
    input                           tl_mperst                               ;
    output                          tl_rdy                                  ;
    output                          tl_rdy_conf                             ;
    input                           tl_rst                                  ;
    input                           tl_crst                                 ;
    input                           tl_k_rst                                ;
    output      [1:0]               tl_flr_req                              ;
    input                           tl_cfg_pclk                             ;
    input                           tl_cfg_prst                             ;
    input                           tl_cfg_penable                          ;
    input                           tl_cfg_psel                             ;
    input                           tl_cfg_pwrite                           ;
    input       [31:0]              tl_cfg_paddr                            ;
    input       [3:0]               tl_cfg_pstrb                            ;
    input       [31:0]              tl_cfg_pwdata                           ;
    output                          tl_cfg_pready                           ;
    output      [31:0]              tl_cfg_prdata                           ;
    output                          tl_cfg_pslverr                          ;
    output      [7:0]               tl_cfg_tcvc                             ;
    output      [12:0]              tl_cfg_busdev                           ;
    output      [2:0]               tl_cfg_max_payload_size                 ;
    output      [2:0]               tl_cfg_max_read_request_size            ;
    output      [2:0]               tl_cfg_current_link_speed               ;
    output      [3:0]               tl_cfg_negotiated_width                 ;
    output                          tl_cfg_read_completion_boundary         ;
    output      [17:0]              tl_cfg_pfregs_vfnums                    ;
    output      [1:0]               tl_cfg_pfregs_vfenable                  ;
    output      [1:0]               tl_cfg_pfregs_vfmse                     ;
    output      [7:0]               tl_cfg_pfregs_cmd                       ;
    input       [2:0]               tl_cfg_vfregs_bit_sel                   ;
    output      [3:0]               tl_cfg_vfregs_bit                       ;
    input       [7:0]               tl_cfg_pf0_primary_bus                  ;
    input       [7:0]               tl_cfg_pf1_primary_bus                  ;
    input       [1:0]               tl_int_status                           ;
    input       [1:0]               tl_int_msireq                           ;
    input       [9:0]               tl_int_msinum                           ;
    output      [1:0]               tl_int_msiack                           ;
    output      [1:0]               tl_int_msi_enable                       ;
    output      [5:0]               tl_int_msi_multi_enable                 ;
    input       [31:0]              tl_int_pf0_msi_pending                  ;
    input       [31:0]              tl_int_pf1_msi_pending                  ;
    output      [31:0]              tl_int_pf0_msi_mask                     ;
    output      [31:0]              tl_int_pf1_msi_mask                     ;
    input       [3:0]               tl_int_pincontrol                       ;
    output      [3:0]               tl_int_pinstate                         ;
    output      [1:0]               tl_cfg_msix_enable                      ;
    output      [1:0]               tl_cfg_msix_function_mask               ;
    input       [15:0]              tl_int_vfmsifid                         ;
    input       [4:0]               tl_int_vfmsinum                         ;
    input                           tl_int_vfmsireq                         ;
    output                          tl_int_vfmsiack                         ;
    input       [7:0]               tl_int_vfmsi_enable_mask_sel            ;
    output      [2:0]               tl_int_vfmsi_enable                     ;
    output      [31:0]              tl_int_vfmsi_mask                       ;
    output      [1:0]               pl_equ_phase                            ;
    output      [4:0]               tl_ltssm                                ;
    output      [4:0]               pl_ltssm                                ;
    output                          pl_link_up                              ;
    input                           pl_ltssm_enable                         ;
    input                           pl_clkreq_in                            ;
    input       [3:0]               tl_pm_l1ss_entack                       ;
    input                           tl_pm_refclk_rem                        ;
    output                          pl_clkreq_oen                           ;
    output                          tl_pm_l1ss_entreq                       ;
    output      [2:0]               tl_pm_l1ss_status                       ;
    input                           pl_wake_in                              ;
    input                           tl_pm_auxpwr                            ;
    input       [19:0]              tl_pm_data                              ;
    input       [1:0]               tl_pm_event                             ;
    input       [2:0]               tl_pm_lx_control                        ;
    output                          pl_wake_oen                             ;
    output                          tl_pm_lx_status                         ;
    input                           tl_pm_bwchange_linkwidth_change_req     ;
    input       [3:0]               tl_pm_bwchange_allowed_linkwidth        ;
    input                           tl_pm_bwchange_linkspeed_change_req     ;
    input       [2:0]               tl_pm_bwchange_max_linkspeed            ;
    input       [9:0]               tl_report_error_10_1_bits               ;
    input       [10:0]              tl_report_error_22_12_bits              ;
    input       [23:0]              tl_report_error_63_40_bits              ;
    input       [255:0]             tl_report_header                        ;
    input       [9:0]               tl_report_hotplug                       ;
    input       [32:0]              tl_report_latency                       ;
    input       [11:0]              tl_report_state_pf0_misc_control        ;
    input       [11:0]              tl_report_state_pf1_misc_control        ;
    input       [1:0]               tl_report_vfstate_override_sel          ;
    input       [3:0]               tl_report_vfstate_override_bit          ;
    output      [7:0]               tl_report_event                         ;
    input                           tl_rx_wait                              ;
    input                           tl_rx_masknp                            ;
    output      [47:0]              tl_rx_bardec                            ;
    output      [255:0]             tl_rx_data                              ;
    output                          tl_rx_eop                               ;
    output      [7:0]               tl_rx_err                               ;
    output      [9:0]               tl_rx_mchit                             ;
    output                          tl_rx_sop                               ;
    output      [7:0]               tl_rx_valid                             ;
    input       [255:0]             tl_tx_data                              ;
    input                           tl_tx_eop                               ;
    input       [7:0]               tl_tx_err                               ;
    input                           tl_tx_sop                               ;
    input                           tl_tx_stream                            ;
    input       [7:0]               tl_tx_valid                             ;
    output                          tl_tx_wait                              ;
    output      [95:0]              tl_tx_credits                           ;
    input       [31:0]              tl_cfg_xrdata                           ;
    input                           tl_cfg_xready                           ;
    output      [11:0]              tl_cfg_xaddr                            ;
    output                          tl_cfg_xenable                          ;
    output      [15:0]              tl_cfg_xfid                             ;
    output      [3:0]               tl_cfg_xstrb                            ;
    output      [31:0]              tl_cfg_xwdata                           ;
    output                          tl_cfg_xwrite                           ;
    input       [63:0]              tl_vpd_rddata                           ;
    input       [1:0]               tl_vpd_ready                            ;
    output      [29:0]              tl_vpd_addr                             ;
    output      [1:0]               tl_vpd_enable                           ;
    output      [5:0]               tl_vpd_status                           ;
    output      [63:0]              tl_vpd_wrdata                           ;
    output      [1:0]               tl_vpd_write                            ;
    input       [3:0]               tl_pm_obffcontrol                       ;
    output      [3:0]               tl_pm_obffstatus                        ;
    input       [67:0]              tl_ptm_in                               ;
    output      [71:0]              tl_ptm_out                              ;
    input       [63:0]              tl_doe_rddata                           ;
    input       [12:0]              tl_doe_pf0_status                       ;
    input       [12:0]              tl_doe_pf1_status                       ;
    output      [11:0]              tl_doe_control                          ;
    output      [63:0]              tl_doe_wrdata                           ;
    input                           scan_clk                                ;
    input       [9:0]               scan_in                                 ;
    output      [9:0]               scan_out                                ;
    input                           scan_mode_n                             ;
    input                           scan_rst_n                              ;
    input                           scan_enable_n                           ;
    input                           scancompress_mode_n                     ;
    input                           mbist_mode_n                            ;
    input                           dft_jtag_tck                            ;
    input                           dft_jtag_trst_n                         ;
    input                           dft_jtag_tms                            ;
    input                           dft_jtag_tdi                            ;
    output                          dft_jtag_tdo                            ;
    input       [2:0]               pinshare_grp0_out_sel                   ;
    input       [1:0]               pinshare_grp1_out_sel                   ;
    input       [8:0]               test_in_errinj_8_0_bits                 ;
    input       [4:0]               test_in_errinj_20_16_bits               ;
    output      [3:0]               test_out_rxval                          ;
    output      [15:0]              test_out_txdatak                        ;
    output      [3:0]               test_out_txval                          ;
    output      [255:0]             pl_sideband                             ;
    output                          cfg_power_on_rst_n                      ;
    output      [1:0]               cfg_pipe_lane_flip                      ;
    output                          cfg_pcs_pipe_rst_n                      ;
    output                          cfg_pcs_apb_rst_n                       ;
    output      [1:0]               cfg_pclk_source_sel                     ;
    output      [3:0]               cfg_pcie_lane_enable                    ;
    output                          cfg_core_sram_init_done                 ;
    output                          cfg_core_bypass                         ;
    input                           serdes_osc_clk                          ;
    input                           pl_pclk                                 ;
    input       [179:0]             pl_sideband_in                          ;
    output      [255:0]             pl_sideband_out                         ;
    output      [4:0]               pl_pclk_rate                            ;
    input       [3:0]               pl_phystatus                            ;
    output      [3:0]               pl_powerdown                            ;
    output      [2:0]               pl_rate                                 ;
    input       [127:0]             pl_rxdata                               ;
    input       [15:0]              pl_rxdatak                              ;
    input       [3:0]               pl_rxdatavalid                          ;
    input       [3:0]               pl_rxelecidle                           ;
    output      [3:0]               pl_rxstandby                            ;
    input       [3:0]               pl_rxstartblock                         ;
    input       [11:0]              pl_rxstatus                             ;
    input       [7:0]               pl_rxsyncheader                         ;
    input       [3:0]               pl_rxvalid                              ;
    output      [3:0]               pl_txcompliance                         ;
    output      [127:0]             pl_txdata                               ;
    output      [15:0]              pl_txdatak                              ;
    output      [3:0]               pl_txdatavalid                          ;
    output      [3:0]               pl_txdetectrx                           ;
    output      [3:0]               pl_txelecidle                           ;
    output      [3:0]               pl_txstartblock                         ;
    output      [7:0]               pl_txsyncheader                         ;
    output      [2:0]               pl_width                                ;
    parameter       CFG_DNS                                 =   64'h0000_0000_dcba_1edb         ;
    parameter       CFG_TLAUXCLK_FR_USER                    =   1'b0                            ;
    parameter       PCIE_CFG_QUICK_LINK                     =   1'b0                            ;
    parameter       PCIE_CFG_TL_POS_EN                      =   1'b0                            ;
    parameter       PCIE_CFG_LANE_ENABLE                    =   4'hf                            ;
    parameter       PCIE_CFG_PCLK_SOURCE_SEL                =   2'b00                           ;
    parameter       PCIE_CFG_PIPE_LANE_FLIP                 =   2'b00                           ;
    parameter       PCIE_CFG_DEVICE_TYPE                    =   "EP"                            ;
    parameter       PCIE_CFG_LINK_SPEED                     =   4'b0011                         ;
    parameter       PCIE_CFG_LINK_WIDTH                     =   4'b1100                         ;
    parameter       PCIE_CFG_CONTROLLER_LOCATION            =   "X69Y120"                       ;
    parameter       PCIE_CFG_QUAD_LOCATION                  =   4'b1000                         ;
    parameter       PCIE_CFG_LANE0_LOCATION                 =   4'b1000                         ;
    parameter       PCIE_CFG_REF_CLK_LOCATION               =   8'b00000001                     ;
    parameter       PCIE_CFG_REF_CLK_FREQ                   =   8'd100                          ;
    parameter       PCIE_CFG_TL_CLK_FREQ                    =   9'd125                          ;
    parameter       PCIE_CFG_PF0_ENABLE                     =   1'b1                            ;
    parameter       PCIE_CFG_PF1_ENABLE                     =   1'b0                            ;
    parameter       PCIE_CFG_MAX_PAYLOAD_SIZE               =   3'b000                          ;
    parameter       PCIE_CFG_EXT_TAG                        =   1'b1                            ;
    parameter       PCIE_CFG_SLOT_CLOCK                     =   1'b1                            ;
    parameter       PCIE_CFG_FUNC_LVL_RESET                 =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VENDOR_ID                  =   16'h1edb                        ;
    parameter       PCIE_CFG_PF0_DEVICE_ID                  =   16'h0000                        ;
    parameter       PCIE_CFG_PF0_REV_NUM                    =   8'h00                           ;
    parameter       PCIE_CFG_PF0_SUB_VENDOR_ID              =   16'h0000                        ;
    parameter       PCIE_CFG_PF0_SUB_DEVICE_ID              =   16'h0000                        ;
    parameter       PCIE_CFG_PF0_CLASS_CODE                 =   24'h000000                      ;
    parameter       PCIE_CFG_PF1_VENDOR_ID                  =   16'h1edb                        ;
    parameter       PCIE_CFG_PF1_DEVICE_ID                  =   16'h0001                        ;
    parameter       PCIE_CFG_PF1_REV_NUM                    =   8'h00                           ;
    parameter       PCIE_CFG_PF1_SUB_VENDOR_ID              =   16'h0000                        ;
    parameter       PCIE_CFG_PF1_SUB_DEVICE_ID              =   16'h0000                        ;
    parameter       PCIE_CFG_PF1_CLASS_CODE                 =   24'h000000                      ;
    parameter       PCIE_CFG_PF0_BAR0_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR0_64BIT                 =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR0_PREFETCHABLE          =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR0_MASK                  =   32'hFFFFFF80                    ;
    parameter       PCIE_CFG_PF0_BAR1_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR1_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_BAR2_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR2_64BIT                 =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR2_PREFETCHABLE          =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR2_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_BAR3_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR3_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_BAR4_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR4_64BIT                 =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR4_PREFETCHABLE          =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR4_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_BAR5_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF0_BAR5_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_EXP_ROM_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_BAR0_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR0_64BIT                 =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR0_PREFETCHABLE          =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR0_MASK                  =   32'hFFFFFF80                    ;
    parameter       PCIE_CFG_PF1_BAR1_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR1_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_BAR2_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR2_64BIT                 =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR2_PREFETCHABLE          =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR2_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_BAR3_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR3_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_BAR4_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR4_64BIT                 =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR4_PREFETCHABLE          =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR4_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_BAR5_TYPE                  =   1'b0                            ;
    parameter       PCIE_CFG_PF1_BAR5_MASK                  =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_EXP_ROM_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_VF_VER_ID                  =   8'h00                           ;
    parameter       PCIE_CFG_PF0_VF_TOTAL_NUM               =   9'h00                           ;
    parameter       PCIE_CFG_PF0_VF_OFFSIT                  =   16'h0000                        ;
    parameter       PCIE_CFG_PF0_VF_DEVICE_ID               =   16'h0000                        ;
    parameter       PCIE_CFG_PF0_VF_DEPENDENCY_LINK         =   8'h00                           ;
    parameter       PCIE_CFG_PF0_VF_PAGE_SIZE               =   12'h000                         ;
    parameter       PCIE_CFG_PF0_VF_SUB_DEVICE_ID           =   16'h000                         ;
    parameter       PCIE_CFG_PF1_VF_VER_ID                  =   8'h00                           ;
    parameter       PCIE_CFG_PF1_VF_TOTAL_NUM               =   9'h00                           ;
    parameter       PCIE_CFG_PF1_VF_OFFSIT                  =   16'h0000                        ;
    parameter       PCIE_CFG_PF1_VF_DEVICE_ID               =   16'h0000                        ;
    parameter       PCIE_CFG_PF1_VF_DEPENDENCY_LINK         =   8'h00                           ;
    parameter       PCIE_CFG_PF1_VF_PAGE_SIZE               =   12'h000                         ;
    parameter       PCIE_CFG_PF1_VF_SUB_DEVICE_ID           =   16'h000                         ;
    parameter       PCIE_CFG_PF0_VF_BAR0_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR0_64BIT              =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR0_PREFETCHABLE       =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR0_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_VF_BAR1_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR1_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_VF_BAR2_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR2_64BIT              =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR2_PREFETCHABLE       =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR2_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_VF_BAR3_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR3_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_VF_BAR4_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR4_64BIT              =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR4_PREFETCHABLE       =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR4_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_VF_BAR5_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF0_VF_BAR5_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_VF_BAR0_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR0_64BIT              =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR0_PREFETCHABLE       =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR0_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_VF_BAR1_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR1_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_VF_BAR2_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR2_64BIT              =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR2_PREFETCHABLE       =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR2_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_VF_BAR3_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR3_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_VF_BAR4_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR4_64BIT              =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR4_PREFETCHABLE       =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR4_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF1_VF_BAR5_TYPE               =   1'b0                            ;
    parameter       PCIE_CFG_PF1_VF_BAR5_MASK               =   32'h00000000                    ;
    parameter       PCIE_CFG_PF0_INT_PIN                    =   3'b000                          ;
    parameter       PCIE_CFG_PF1_INT_PIN                    =   3'b000                          ;
    parameter       PCIE_CFG_PF0_MSI_ENABLE                 =   1'b0                            ;
    parameter       PCIE_CFG_PF0_MSI_MME                    =   3'b000                          ;
    parameter       PCIE_CFG_PF0_MSI_MASKING                =   1'b0                            ;
    parameter       PCIE_CFG_PF1_MSI_ENABLE                 =   1'b0                            ;
    parameter       PCIE_CFG_PF1_MSI_MME                    =   3'b000                          ;
    parameter       PCIE_CFG_PF1_MSI_MASKING                =   1'b0                            ;
    parameter       PCIE_CFG_PF0_MSIX_ENABLE                =   1'b0                            ;
    parameter       PCIE_CFG_PF0_MSIX_TAB_SIZE              =   11'b0                           ;
    parameter       PCIE_CFG_PF0_MSIX_TAB_OFFSET            =   29'b0                           ;
    parameter       PCIE_CFG_PF0_MSIX_TAB_BIR               =   3'b0                            ;
    parameter       PCIE_CFG_PF0_MSIX_PBA_OFFSET            =   29'b0                           ;
    parameter       PCIE_CFG_PF0_MSIX_PBA_BIR               =   3'b0                            ;
    parameter       PCIE_CFG_PF1_MSIX_ENABLE                =   1'b0                            ;
    parameter       PCIE_CFG_PF1_MSIX_TAB_SIZE              =   11'b0                           ;
    parameter       PCIE_CFG_PF1_MSIX_TAB_OFFSET            =   29'b0                           ;
    parameter       PCIE_CFG_PF1_MSIX_TAB_BIR               =   3'b0                            ;
    parameter       PCIE_CFG_PF1_MSIX_PBA_OFFSET            =   29'b0                           ;
    parameter       PCIE_CFG_PF1_MSIX_PBA_BIR               =   3'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_D1_SUPPORT           =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_D2_SUPPORT           =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_ASPM_L0_SUPPORT      =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_ASPM_L1_SUPPORT      =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_PME_D0_SUPPORT       =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_PME_D1_SUPPORT       =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_PME_D2_SUPPORT       =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_PME_D3HOT_SUPPORT    =   1'b0                            ;
    parameter       PCIE_CFG_POWER_MGT_PME_D3COLD_SUPPORT   =   1'b0                            ;
    parameter       PCIE_CFG_AER_CAP_ENABLE                 =   1'b1                            ;
    parameter       PCIE_CFG_AER_ECRC_GEN_ENABLE            =   1'b0                            ;
    parameter       PCIE_CFG_AER_ECRC_CHK_ENABLE            =   1'b0                            ;
    parameter       PCIE_CFG_DSN_CAP_ENABLE                 =   1'b0                            ;
    parameter       PCIE_CFG_DSN_NUM                        =   64'h0000_0000_0000_0000         ;
    parameter       PCIE_CFG_EXTERNAL_REG_ENABLE            =   1'b0                            ;
    parameter       PCIE_CFG_EXTERNAL_FIRST_OFFSET          =   8'h00                           ;
endmodule
module PH1P_PHY_HXT_V1 (
rx0_n                             ,
rx0_p                             ,
rx1_n                             ,
rx1_p                             ,
rx2_n                             ,
rx2_p                             ,
rx3_n                             ,
rx3_p                             ,
tx0_n                             ,
tx0_p                             ,
tx1_n                             ,
tx1_p                             ,
tx2_n                             ,
tx2_p                             ,
tx3_n                             ,
tx3_p                             ,
rx_cdrclk_n                       ,
rx_cdrclk_p                       ,
ref0_clk_p                        ,
ref0_clk_n                        ,
ref1_clk_p                        ,
ref1_clk_n                        ,
refclk_extres_en                  ,
refclk_se                         ,
tx0_usr2clk                       ,
rx0_usr2clk                       ,
tx0_out2clk                       ,
rx0_out2clk                       ,
tx0_outclk                        ,
rx0_outclk	                      ,
l0_resetmode_sel                  ,
tx0_reset                         ,
tx0_pma_reset                     ,
tx0_pcs_reset                     ,
tx0_pcsfifo_reset                 ,
tx0_userrdy                       ,
rx0_reset                         ,
rx0_pma_reset                     ,
rx0_pcs_reset                     ,
rx0_pcsfifo_reset                 ,
rx0_userrdy                       ,
tx0_resetdone                     ,
rx0_resetdone                     ,
tx0_data                          ,
tx0_ctrl0_data                    ,
tx0_ctrl1_data                    ,
tx0_ctrl2_data                    ,
tx0_data_en                       ,
tx0_header                        ,
tx0_sequence                      ,
tx0_8b10b_en                      ,
rx0_gearboxslip                   ,
rx0_slide                         ,
rx0_8b10b_en                      ,
rx0_gpon_en                       ,
rx0_data                          ,
rx0_ctrl0_data                    ,
rx0_ctrl1_data                    ,
rx0_ctrl2_data                    ,
rx0_ctrl3_data                    ,
rx0_header                        ,
rx0_datavalid                     ,
rx0_headervalid                   ,
rx0_startofseq                    ,
tx0_pcsfifo_rd_halffull           ,
tx0_pcsfifo_rd_empty              ,
tx0_pcsfifo_wr_halffull           ,
tx0_pcsfifo_wr_full               ,
tx0_piso_pop_halffull             ,
tx0_piso_push_aempty              ,
tx0_piso_pop_empty                ,
tx0_piso_push_afull               ,
tx0_piso_push_halffull            ,
tx0_piso_push_full                ,
rx0_sipo_pop_halffull             ,
rx0_sipo_pop_aempty               ,
rx0_sipo_pop_empty                ,
rx0_sipo_push_afull               ,
rx0_sipo_push_halffull            ,
rx0_sipo_push_full                ,
rx0_rmfifo_high                   ,
rx0_rmfifo_low                    ,
rx0_rmfifo_overflow               ,
rx0_rmfifo_underflow              ,
rx0_wordrealign                   ,
rx0_wordaligned                   ,
rx0_rmfifo_corcnt                 ,
rx0_sipo_align_lock               ,
rx0_pll_lock                      ,
rx0_pma_prbs_error                ,
tx0_dpll_lock                     ,
tx0_pi_lock                       ,
tx0_pll_lock                      ,
tx0_req                           ,
tx0_pstate                        ,
tx0_rate                          ,
tx0_detrx_req                     ,
tx0_detrx_result                  ,
tx0_ack                           ,
rx0_req                           ,
rx0_pstate                        ,
rx0_rate                          ,
rx0_ack                           ,
tx0_polarity                      ,
tx0_eq_ctrl                       ,
tx0_eq_pre                        ,
tx0_eq_main                       ,
tx0_eq_post                       ,
tx0_eq_preset                     ,
tx0_eq_getlocal_pset_coef         ,
tx0_eq_local_tx_pset_coef         ,
tx0_eq_local_tx_coef_valid        ,
tx0_eq_localfs                    ,
tx0_eq_locallf                    ,
rx0_polarity                      ,
rx0_adapt_cont                    ,
rx0_adapt_in_prog                 ,
rx0_adapt_req                     ,
rx0_adapt_invalid_req             ,
rx0_adapt_ctrl                    ,
rx0_adapt_ack                     ,
rx0_adapt_fom                     ,
rx0_txmain_dir                    ,
rx0_txpost_dir                    ,
rx0_txpre_dir                     ,
tx1_usr2clk                       ,
rx1_usr2clk                       ,
tx1_out2clk                       ,
rx1_out2clk                       ,
tx1_outclk                        ,
rx1_outclk                        ,
l1_resetmode_sel                  ,
tx1_reset                         ,
tx1_pma_reset                     ,
tx1_pcs_reset                     ,
tx1_pcsfifo_reset                 ,
tx1_userrdy                       ,
rx1_reset                         ,
rx1_pma_reset                     ,
rx1_pcs_reset                     ,
rx1_pcsfifo_reset                 ,
rx1_userrdy                       ,
tx1_resetdone                     ,
rx1_resetdone                     ,
tx1_data                          ,
tx1_ctrl0_data                    ,
tx1_ctrl1_data                    ,
tx1_ctrl2_data                    ,
tx1_data_en                       ,
tx1_header                        ,
tx1_sequence                      ,
tx1_8b10b_en                      ,
rx1_gearboxslip                   ,
rx1_slide                         ,
rx1_8b10b_en                      ,
rx1_gpon_en                       ,
rx1_data                          ,
rx1_ctrl0_data                    ,
rx1_ctrl1_data                    ,
rx1_ctrl2_data                    ,
rx1_ctrl3_data                    ,
rx1_header                        ,
rx1_datavalid                     ,
rx1_headervalid                   ,
rx1_startofseq                    ,
tx1_pcsfifo_rd_halffull           ,
tx1_pcsfifo_rd_empty              ,
tx1_pcsfifo_wr_halffull           ,
tx1_pcsfifo_wr_full               ,
tx1_piso_pop_halffull             ,
tx1_piso_push_aempty              ,
tx1_piso_pop_empty                ,
tx1_piso_push_afull               ,
tx1_piso_push_halffull            ,
tx1_piso_push_full                ,
rx1_sipo_pop_halffull             ,
rx1_sipo_pop_aempty               ,
rx1_sipo_pop_empty                ,
rx1_sipo_push_afull               ,
rx1_sipo_push_halffull            ,
rx1_sipo_push_full                ,
rx1_rmfifo_high                   ,
rx1_rmfifo_low                    ,
rx1_rmfifo_overflow               ,
rx1_rmfifo_underflow              ,
rx1_wordrealign                   ,
rx1_wordaligned                   ,
rx1_rmfifo_corcnt                 ,
rx1_sipo_align_lock               ,
rx1_pll_lock                      ,
rx1_pma_prbs_error                ,
tx1_dpll_lock                     ,
tx1_pi_lock                       ,
tx1_pll_lock                      ,
tx1_req                           ,
tx1_pstate                        ,
tx1_rate                          ,
tx1_detrx_req                     ,
tx1_detrx_result                  ,
tx1_ack                           ,
rx1_req                           ,
rx1_pstate                        ,
rx1_rate                          ,
rx1_ack                           ,
tx1_polarity                      ,
tx1_eq_ctrl                       ,
tx1_eq_pre                        ,
tx1_eq_main                       ,
tx1_eq_post                       ,
tx1_eq_preset                     ,
tx1_eq_getlocal_pset_coef         ,
tx1_eq_local_tx_pset_coef         ,
tx1_eq_local_tx_coef_valid        ,
tx1_eq_localfs                    ,
tx1_eq_locallf                    ,
rx1_polarity                      ,
rx1_adapt_cont                    ,
rx1_adapt_in_prog                 ,
rx1_adapt_req                     ,
rx1_adapt_invalid_req             ,
rx1_adapt_ctrl                    ,
rx1_adapt_ack                     ,
rx1_adapt_fom                     ,
rx1_txmain_dir                    ,
rx1_txpost_dir                    ,
rx1_txpre_dir                     ,
tx2_usr2clk                       ,
rx2_usr2clk                       ,
tx2_out2clk                       ,
rx2_out2clk                       ,
tx2_outclk                        ,
rx2_outclk                        ,
l2_resetmode_sel                  ,
tx2_reset                         ,
tx2_pma_reset                     ,
tx2_pcs_reset                     ,
tx2_pcsfifo_reset                 ,
tx2_userrdy                       ,
rx2_reset                         ,
rx2_pma_reset                     ,
rx2_pcs_reset                     ,
rx2_pcsfifo_reset                 ,
rx2_userrdy                       ,
tx2_resetdone                     ,
rx2_resetdone                     ,
tx2_data                          ,
tx2_ctrl0_data                    ,
tx2_ctrl1_data                    ,
tx2_ctrl2_data                    ,
tx2_data_en                       ,
tx2_header                        ,
tx2_sequence                      ,
tx2_8b10b_en                      ,
rx2_gearboxslip                   ,
rx2_slide                         ,
rx2_8b10b_en                      ,
rx2_gpon_en                       ,
rx2_data                          ,
rx2_ctrl0_data                    ,
rx2_ctrl1_data                    ,
rx2_ctrl2_data                    ,
rx2_ctrl3_data                    ,
rx2_header                        ,
rx2_datavalid                     ,
rx2_headervalid                   ,
rx2_startofseq                    ,
tx2_pcsfifo_rd_halffull           ,
tx2_pcsfifo_rd_empty              ,
tx2_pcsfifo_wr_halffull           ,
tx2_pcsfifo_wr_full               ,
tx2_piso_pop_halffull             ,
tx2_piso_push_aempty              ,
tx2_piso_pop_empty                ,
tx2_piso_push_afull               ,
tx2_piso_push_halffull            ,
tx2_piso_push_full                ,
rx2_sipo_pop_halffull             ,
rx2_sipo_pop_aempty               ,
rx2_sipo_pop_empty                ,
rx2_sipo_push_afull               ,
rx2_sipo_push_halffull            ,
rx2_sipo_push_full                ,
rx2_rmfifo_high                   ,
rx2_rmfifo_low                    ,
rx2_rmfifo_overflow               ,
rx2_rmfifo_underflow              ,
rx2_wordrealign                   ,
rx2_wordaligned                   ,
rx2_rmfifo_corcnt                 ,
rx2_sipo_align_lock               ,
rx2_pll_lock                      ,
rx2_pma_prbs_error                ,
tx2_dpll_lock                     ,
tx2_pi_lock                       ,
tx2_pll_lock                      ,
tx2_req                           ,
tx2_pstate                        ,
tx2_rate                          ,
tx2_detrx_req                     ,
tx2_detrx_result                  ,
tx2_ack                           ,
rx2_req                           ,
rx2_pstate                        ,
rx2_rate                          ,
rx2_ack                           ,
tx2_polarity                      ,
tx2_eq_ctrl                       ,
tx2_eq_pre                        ,
tx2_eq_main                       ,
tx2_eq_post                       ,
tx2_eq_preset                     ,
tx2_eq_getlocal_pset_coef         ,
tx2_eq_local_tx_pset_coef         ,
tx2_eq_local_tx_coef_valid        ,
tx2_eq_localfs                    ,
tx2_eq_locallf                    ,
rx2_polarity                      ,
rx2_adapt_cont                    ,
rx2_adapt_in_prog                 ,
rx2_adapt_req                     ,
rx2_adapt_invalid_req             ,
rx2_adapt_ctrl                    ,
rx2_adapt_ack                     ,
rx2_adapt_fom                     ,
rx2_txmain_dir                    ,
rx2_txpost_dir                    ,
rx2_txpre_dir                     ,
tx3_usr2clk                       ,
rx3_usr2clk                       ,
tx3_out2clk                       ,
rx3_out2clk                       ,
tx3_outclk                        ,
rx3_outclk                        ,
l3_resetmode_sel                  ,
tx3_reset                         ,
tx3_pma_reset                     ,
tx3_pcs_reset                     ,
tx3_pcsfifo_reset                 ,
tx3_userrdy                       ,
rx3_reset                         ,
rx3_pma_reset                     ,
rx3_pcs_reset                     ,
rx3_pcsfifo_reset                 ,
rx3_userrdy                       ,
tx3_resetdone                     ,
rx3_resetdone                     ,
tx3_data                          ,
tx3_ctrl0_data                    ,
tx3_ctrl1_data                    ,
tx3_ctrl2_data                    ,
tx3_data_en                       ,
tx3_header                        ,
tx3_sequence                      ,
tx3_8b10b_en                      ,
rx3_gearboxslip                   ,
rx3_slide                         ,
rx3_8b10b_en                      ,
rx3_gpon_en                       ,
rx3_data                          ,
rx3_ctrl0_data                    ,
rx3_ctrl1_data                    ,
rx3_ctrl2_data                    ,
rx3_ctrl3_data                    ,
rx3_header                        ,
rx3_datavalid                     ,
rx3_headervalid                   ,
rx3_startofseq                    ,
tx3_pcsfifo_rd_halffull           ,
tx3_pcsfifo_rd_empty              ,
tx3_pcsfifo_wr_halffull           ,
tx3_pcsfifo_wr_full               ,
tx3_piso_pop_halffull             ,
tx3_piso_push_aempty              ,
tx3_piso_pop_empty                ,
tx3_piso_push_afull               ,
tx3_piso_push_halffull            ,
tx3_piso_push_full                ,
rx3_sipo_pop_halffull             ,
rx3_sipo_pop_aempty               ,
rx3_sipo_pop_empty                ,
rx3_sipo_push_afull               ,
rx3_sipo_push_halffull            ,
rx3_sipo_push_full                ,
rx3_rmfifo_high                   ,
rx3_rmfifo_low                    ,
rx3_rmfifo_overflow               ,
rx3_rmfifo_underflow              ,
rx3_wordrealign                   ,
rx3_wordaligned                   ,
rx3_rmfifo_corcnt                 ,
rx3_sipo_align_lock               ,
rx3_pll_lock                      ,
rx3_pma_prbs_error                ,
tx3_dpll_lock                     ,
tx3_pi_lock                       ,
tx3_pll_lock                      ,
tx3_req                           ,
tx3_pstate                        ,
tx3_rate                          ,
tx3_detrx_req                     ,
tx3_detrx_result                  ,
tx3_ack                           ,
rx3_req                           ,
rx3_pstate                        ,
rx3_rate                          ,
rx3_ack                           ,
tx3_polarity                      ,
tx3_eq_ctrl                       ,
tx3_eq_pre                        ,
tx3_eq_main                       ,
tx3_eq_post                       ,
tx3_eq_preset                     ,
tx3_eq_getlocal_pset_coef         ,
tx3_eq_local_tx_pset_coef         ,
tx3_eq_local_tx_coef_valid        ,
tx3_eq_localfs                    ,
tx3_eq_locallf                    ,
rx3_polarity                      ,
rx3_adapt_cont                    ,
rx3_adapt_in_prog                 ,
rx3_adapt_req                     ,
rx3_adapt_invalid_req             ,
rx3_adapt_ctrl                    ,
rx3_adapt_ack                     ,
rx3_adapt_fom                     ,
rx3_txmain_dir                    ,
rx3_txpost_dir                    ,
rx3_txpre_dir                     ,
other_quad_rxclk                  ,
local_quad_rxclk                  ,
phy_reset                         ,
phy_pipe_reset                    ,
cmnresetdone                      ,
refclkout                         ,
groupclkout                       ,
group0sigout                      ,
group1sigout                      ,
group2sigout                      ,
group3sigout                      ,
vdh_ready                         ,
mcu_serdes_rxd                    ,
mcu_serdes_txd                    ,
mcu_phy_rst_sel                   ,
mcu_phy_rst                       ,
mcu_enable                        ,
mcu_core_rst                      ,
mcu_irq_o                         ,
mcu_exchg_info_0                  ,
mcu_sysrstreq                     ,
cmn_pll_lock                      ,
apb4_clk_i                        ,
apb4_preset_i                     ,
apb4_psel_i                       ,
apb4_penable_i                    ,
apb4_pwrite_i                     ,
apb4_paddr_i                      ,
apb4_pwdata_i                     ,
apb4_pstrb_i                      ,
apb4_pprot_i                      ,
apb4_prdata_o                     ,
apb4_pready_o                     ,
apb4_pslverr_o                    ,
scan_rst_n                        ,
scan_mode_n                       ,
scan_clk                          ,
scan_enable_n                     ,
scancompress_mode                 ,
scan_in                           ,
scan_out                          ,
mbist_mode_n                      ,
dft_jtag_tck                      ,
dft_jtag_trst_n                   ,
dft_jtag_tms                      ,
dft_jtag_tdi                      ,
dft_jtag_tdo                      ,
jtag_tck                          ,
jtag_tms                          ,
jtag_tdi                          ,
jtag_tdo                          ,
jtag_tdo_en                       ,
pcie_osc_clk                      ,
mac_phy_txdata                    ,
mac_phy_txdatak                   ,
mac_phy_txdatavalid               ,
mac_phy_txsyncheader              ,
phy_mac_rxdata                    ,
phy_mac_rxdatak                   ,
phy_mac_rxsyncheader              ,
mac_phy_txdeemph                  ,
mac_phy_rxpresethint              ,
mac_phy_fs                        ,
mac_phy_lf                        ,
mac_phy_local_pset_index          ,
mac_phy_getlocal_pset_coef        ,
mac_phy_rxeqeval                  ,
mac_phy_rxeqinprogress            ,
mac_phy_invalid_req               ,
phy_mac_dirfeedback               ,
phy_mac_fomfeedback               ,
phy_mac_local_tx_pset_coef        ,
phy_mac_local_tx_coef_valid       ,
phy_mac_localfs                   ,
phy_mac_locallf                   ,
mac_phy_blockaligncontrol         ,
mac_phy_txmargin                  ,
mac_phy_txswing                   ,
mac_phy_powerdown                 ,
mac_phy_width                     ,
mac_phy_pclk_rate                 ,
mac_phy_rate                      ,
mac_phy_txstartblock              ,
mac_phy_txelecidle                ,
mac_phy_txcompliance              ,
mac_phy_txdetectrx_loopback       ,
mac_phy_rxpolarity                ,
mac_phy_rxstandby                 ,
phy_mac_pclk                      ,
phy_mac_rxstartblock              ,
phy_mac_rxelecidle                ,
phy_mac_phystatus                 ,
phy_mac_rxvalid                   ,
phy_mac_rxstatus                  ,
phy_mac_rxdatavalid               ,
pcie_core_sram_init_done          ,
pcie_pclk_source_sel              ,
pcie_pipe_lane_flip               ,
pcie_pipe_lane_enable             ,
pcie_core_bypass                  ,
pcie_power_on_rst_n               ,
pcie_pcs_pipe_rst_n               ,
pcie_pcs_apb_rst_n
);
input                           rx0_n                                ;
input                           rx0_p                                ;
input                           rx1_n                                ;
input                           rx1_p                                ;
input                           rx2_n                                ;
input                           rx2_p                                ;
input                           rx3_n                                ;
input                           rx3_p                                ;
output                          tx0_n                                ;
output                          tx0_p                                ;
output                          tx1_n                                ;
output                          tx1_p                                ;
output                          tx2_n                                ;
output                          tx2_p                                ;
output                          tx3_n                                ;
output                          tx3_p                                ;
output                          rx_cdrclk_n                          ;
output                          rx_cdrclk_p                          ;
input                           ref0_clk_p                           ;
input                           ref0_clk_n                           ;
input                           ref1_clk_p                           ;
input                           ref1_clk_n                           ;
input                           refclk_extres_en                     ;
input     [1:0]                 refclk_se                            ;
input                           tx0_usr2clk                          ;
input                           rx0_usr2clk                          ;
output                          tx0_out2clk                          ;
output                          rx0_out2clk                          ;
output                          tx0_outclk                           ;
output                          rx0_outclk                           ;
input                           l0_resetmode_sel                     ;
input                           tx0_reset                            ;
input                           tx0_pma_reset                        ;
input                           tx0_pcs_reset                        ;
input                           tx0_pcsfifo_reset                    ;
input                           tx0_userrdy                          ;
input                           rx0_reset                            ;
input                           rx0_pma_reset                        ;
input                           rx0_pcs_reset                        ;
input                           rx0_pcsfifo_reset                    ;
input                           rx0_userrdy                          ;
output                          tx0_resetdone                        ;
output                          rx0_resetdone                        ;
input     [63:0]                tx0_data                             ;
input     [7:0]                 tx0_ctrl0_data                       ;
input     [7:0]                 tx0_ctrl1_data                       ;
input     [7:0]                 tx0_ctrl2_data                       ;
input                           tx0_data_en                          ;
input     [2:0]                 tx0_header                           ;
input     [6:0]                 tx0_sequence                         ;
input                           tx0_8b10b_en                         ;
input                           rx0_gearboxslip                      ;
input                           rx0_slide                            ;
input                           rx0_8b10b_en                         ;
input                           rx0_gpon_en                          ;
output    [63:0]                rx0_data                             ;
output    [7:0]                 rx0_ctrl0_data                       ;
output    [7:0]                 rx0_ctrl1_data                       ;
output    [7:0]                 rx0_ctrl2_data                       ;
output    [7:0]                 rx0_ctrl3_data                       ;
output    [2:0]                 rx0_header                           ;
output                          rx0_datavalid                        ;
output                          rx0_headervalid                      ;
output                          rx0_startofseq                       ;
output                          tx0_pcsfifo_rd_halffull              ;
output                          tx0_pcsfifo_rd_empty                 ;
output                          tx0_pcsfifo_wr_halffull              ;
output                          tx0_pcsfifo_wr_full                  ;
output                          tx0_piso_pop_halffull                ;
output                          tx0_piso_push_aempty                 ;
output                          tx0_piso_pop_empty                   ;
output                          tx0_piso_push_afull                  ;
output                          tx0_piso_push_halffull               ;
output                          tx0_piso_push_full                   ;
output                          rx0_sipo_pop_halffull                ;
output                          rx0_sipo_pop_aempty                  ;
output                          rx0_sipo_pop_empty                   ;
output                          rx0_sipo_push_afull                  ;
output                          rx0_sipo_push_halffull               ;
output                          rx0_sipo_push_full                   ;
output                          rx0_rmfifo_high                      ;
output                          rx0_rmfifo_low                       ;
output                          rx0_rmfifo_overflow                  ;
output                          rx0_rmfifo_underflow                 ;
output                          rx0_wordrealign                      ;
output                          rx0_wordaligned                      ;
output    [1:0]                 rx0_rmfifo_corcnt                    ;
output                          rx0_sipo_align_lock                  ;
output                          rx0_pll_lock                         ;
output                          rx0_pma_prbs_error                   ;
output                          tx0_dpll_lock                        ;
output                          tx0_pi_lock                          ;
output                          tx0_pll_lock                         ;
input                           tx0_req                              ;
input     [1:0]                 tx0_pstate                           ;
input     [2:0]                 tx0_rate                             ;
input                           tx0_detrx_req                        ;
output                          tx0_detrx_result                     ;
output                          tx0_ack                              ;
input                           rx0_req                              ;
input     [1:0]                 rx0_pstate                           ;
input     [2:0]                 rx0_rate                             ;
output                          rx0_ack                              ;
input                           tx0_polarity                         ;
input     [1:0]                 tx0_eq_ctrl                          ;
input     [5:0]                 tx0_eq_pre                           ;
input     [5:0]                 tx0_eq_main                          ;
input     [5:0]                 tx0_eq_post                          ;
input     [4:0]                 tx0_eq_preset                        ;
input                           tx0_eq_getlocal_pset_coef            ;
output    [17:0]                tx0_eq_local_tx_pset_coef            ;
output                          tx0_eq_local_tx_coef_valid           ;
output    [5:0]                 tx0_eq_localfs                       ;
output    [5:0]                 tx0_eq_locallf                       ;
input                           rx0_polarity                         ;
input                           rx0_adapt_cont                       ;
input                           rx0_adapt_in_prog                    ;
input                           rx0_adapt_req                        ;
input                           rx0_adapt_invalid_req                ;
input     [1:0]                 rx0_adapt_ctrl                       ;
output                          rx0_adapt_ack                        ;
output    [7:0]                 rx0_adapt_fom                        ;
output    [1:0]                 rx0_txmain_dir                       ;
output    [1:0]                 rx0_txpost_dir                       ;
output    [1:0]                 rx0_txpre_dir                        ;
input                           tx1_usr2clk                          ;
input                           rx1_usr2clk                          ;
output                          tx1_out2clk                          ;
output                          rx1_out2clk                          ;
output                          tx1_outclk                           ;
output                          rx1_outclk                           ;
input                           l1_resetmode_sel                     ;
input                           tx1_reset                            ;
input                           tx1_pma_reset                        ;
input                           tx1_pcs_reset                        ;
input                           tx1_pcsfifo_reset                    ;
input                           tx1_userrdy                          ;
input                           rx1_reset                            ;
input                           rx1_pma_reset                        ;
input                           rx1_pcs_reset                        ;
input                           rx1_pcsfifo_reset                    ;
input                           rx1_userrdy                          ;
output                          tx1_resetdone                        ;
output                          rx1_resetdone                        ;
input     [63:0]                tx1_data                             ;
input     [7:0]                 tx1_ctrl0_data                       ;
input     [7:0]                 tx1_ctrl1_data                       ;
input     [7:0]                 tx1_ctrl2_data                       ;
input                           tx1_data_en                          ;
input     [2:0]                 tx1_header                           ;
input     [6:0]                 tx1_sequence                         ;
input                           tx1_8b10b_en                         ;
input                           rx1_gearboxslip                      ;
input                           rx1_slide                            ;
input                           rx1_8b10b_en                         ;
input                           rx1_gpon_en                          ;
output    [63:0]                rx1_data                             ;
output    [7:0]                 rx1_ctrl0_data                       ;
output    [7:0]                 rx1_ctrl1_data                       ;
output    [7:0]                 rx1_ctrl2_data                       ;
output    [7:0]                 rx1_ctrl3_data                       ;
output    [2:0]                 rx1_header                           ;
output                          rx1_datavalid                        ;
output                          rx1_headervalid                      ;
output                          rx1_startofseq                       ;
output                          tx1_pcsfifo_rd_halffull              ;
output                          tx1_pcsfifo_rd_empty                 ;
output                          tx1_pcsfifo_wr_halffull              ;
output                          tx1_pcsfifo_wr_full                  ;
output                          tx1_piso_pop_halffull                ;
output                          tx1_piso_push_aempty                 ;
output                          tx1_piso_pop_empty                   ;
output                          tx1_piso_push_afull                  ;
output                          tx1_piso_push_halffull               ;
output                          tx1_piso_push_full                   ;
output                          rx1_sipo_pop_halffull                ;
output                          rx1_sipo_pop_aempty                  ;
output                          rx1_sipo_pop_empty                   ;
output                          rx1_sipo_push_afull                  ;
output                          rx1_sipo_push_halffull               ;
output                          rx1_sipo_push_full                   ;
output                          rx1_rmfifo_high                      ;
output                          rx1_rmfifo_low                       ;
output                          rx1_rmfifo_overflow                  ;
output                          rx1_rmfifo_underflow                 ;
output                          rx1_wordrealign                      ;
output                          rx1_wordaligned                      ;
output    [1:0]                 rx1_rmfifo_corcnt                    ;
output                          rx1_sipo_align_lock                  ;
output                          rx1_pll_lock                         ;
output                          rx1_pma_prbs_error                   ;
output                          tx1_dpll_lock                        ;
output                          tx1_pi_lock                          ;
output                          tx1_pll_lock                         ;
input                           tx1_req                              ;
input     [1:0]                 tx1_pstate                           ;
input     [2:0]                 tx1_rate                             ;
input                           tx1_detrx_req                        ;
output                          tx1_detrx_result                     ;
output                          tx1_ack                              ;
input                           rx1_req                              ;
input     [1:0]                 rx1_pstate                           ;
input     [2:0]                 rx1_rate                             ;
output                          rx1_ack                              ;
input                           tx1_polarity                         ;
input     [1:0]                 tx1_eq_ctrl                          ;
input     [5:0]                 tx1_eq_pre                           ;
input     [5:0]                 tx1_eq_main                          ;
input     [5:0]                 tx1_eq_post                          ;
input     [4:0]                 tx1_eq_preset                        ;
input                           tx1_eq_getlocal_pset_coef            ;
output    [17:0]                tx1_eq_local_tx_pset_coef            ;
output                          tx1_eq_local_tx_coef_valid           ;
output    [5:0]                 tx1_eq_localfs                       ;
output    [5:0]                 tx1_eq_locallf                       ;
input                           rx1_polarity                         ;
input                           rx1_adapt_cont                       ;
input                           rx1_adapt_in_prog                    ;
input                           rx1_adapt_req                        ;
input                           rx1_adapt_invalid_req                ;
input     [1:0]                 rx1_adapt_ctrl                       ;
output                          rx1_adapt_ack                        ;
output    [7:0]                 rx1_adapt_fom                        ;
output    [1:0]                 rx1_txmain_dir                       ;
output    [1:0]                 rx1_txpost_dir                       ;
output    [1:0]                 rx1_txpre_dir                        ;
input                           tx2_usr2clk                          ;
input                           rx2_usr2clk                          ;
output                          tx2_out2clk                          ;
output                          rx2_out2clk                          ;
output                          tx2_outclk                           ;
output                          rx2_outclk                           ;
input                           l2_resetmode_sel                     ;
input                           tx2_reset                            ;
input                           tx2_pma_reset                        ;
input                           tx2_pcs_reset                        ;
input                           tx2_pcsfifo_reset                    ;
input                           tx2_userrdy                          ;
input                           rx2_reset                            ;
input                           rx2_pma_reset                        ;
input                           rx2_pcs_reset                        ;
input                           rx2_pcsfifo_reset                    ;
input                           rx2_userrdy                          ;
output                          tx2_resetdone                        ;
output                          rx2_resetdone                        ;
input     [63:0]                tx2_data                             ;
input     [7:0]                 tx2_ctrl0_data                       ;
input     [7:0]                 tx2_ctrl1_data                       ;
input     [7:0]                 tx2_ctrl2_data                       ;
input                           tx2_data_en                          ;
input     [2:0]                 tx2_header                           ;
input     [6:0]                 tx2_sequence                         ;
input                           tx2_8b10b_en                         ;
input                           rx2_gearboxslip                      ;
input                           rx2_slide                            ;
input                           rx2_8b10b_en                         ;
input                           rx2_gpon_en                          ;
output    [63:0]                rx2_data                             ;
output    [7:0]                 rx2_ctrl0_data                       ;
output    [7:0]                 rx2_ctrl1_data                       ;
output    [7:0]                 rx2_ctrl2_data                       ;
output    [7:0]                 rx2_ctrl3_data                       ;
output    [2:0]                 rx2_header                           ;
output                          rx2_datavalid                        ;
output                          rx2_headervalid                      ;
output                          rx2_startofseq                       ;
output                          tx2_pcsfifo_rd_halffull              ;
output                          tx2_pcsfifo_rd_empty                 ;
output                          tx2_pcsfifo_wr_halffull              ;
output                          tx2_pcsfifo_wr_full                  ;
output                          tx2_piso_pop_halffull                ;
output                          tx2_piso_push_aempty                 ;
output                          tx2_piso_pop_empty                   ;
output                          tx2_piso_push_afull                  ;
output                          tx2_piso_push_halffull               ;
output                          tx2_piso_push_full                   ;
output                          rx2_sipo_pop_halffull                ;
output                          rx2_sipo_pop_aempty                  ;
output                          rx2_sipo_pop_empty                   ;
output                          rx2_sipo_push_afull                  ;
output                          rx2_sipo_push_halffull               ;
output                          rx2_sipo_push_full                   ;
output                          rx2_rmfifo_high                      ;
output                          rx2_rmfifo_low                       ;
output                          rx2_rmfifo_overflow                  ;
output                          rx2_rmfifo_underflow                 ;
output                          rx2_wordrealign                      ;
output                          rx2_wordaligned                      ;
output    [1:0]                 rx2_rmfifo_corcnt                    ;
output                          rx2_sipo_align_lock                  ;
output                          rx2_pll_lock                         ;
output                          rx2_pma_prbs_error                   ;
output                          tx2_dpll_lock                        ;
output                          tx2_pi_lock                          ;
output                          tx2_pll_lock                         ;
input                           tx2_req                              ;
input     [1:0]                 tx2_pstate                           ;
input     [2:0]                 tx2_rate                             ;
input                           tx2_detrx_req                        ;
output                          tx2_detrx_result                     ;
output                          tx2_ack                              ;
input                           rx2_req                              ;
input     [1:0]                 rx2_pstate                           ;
input     [2:0]                 rx2_rate                             ;
output                          rx2_ack                              ;
input                           tx2_polarity                         ;
input     [1:0]                 tx2_eq_ctrl                          ;
input     [5:0]                 tx2_eq_pre                           ;
input     [5:0]                 tx2_eq_main                          ;
input     [5:0]                 tx2_eq_post                          ;
input     [4:0]                 tx2_eq_preset                        ;
input                           tx2_eq_getlocal_pset_coef            ;
output    [17:0]                tx2_eq_local_tx_pset_coef            ;
output                          tx2_eq_local_tx_coef_valid           ;
output    [5:0]                 tx2_eq_localfs                       ;
output    [5:0]                 tx2_eq_locallf                       ;
input                           rx2_polarity                         ;
input                           rx2_adapt_cont                       ;
input                           rx2_adapt_in_prog                    ;
input                           rx2_adapt_req                        ;
input                           rx2_adapt_invalid_req                ;
input     [1:0]                 rx2_adapt_ctrl                       ;
output                          rx2_adapt_ack                        ;
output    [7:0]                 rx2_adapt_fom                        ;
output    [1:0]                 rx2_txmain_dir                       ;
output    [1:0]                 rx2_txpost_dir                       ;
output    [1:0]                 rx2_txpre_dir                        ;
input                           tx3_usr2clk                          ;
input                           rx3_usr2clk                          ;
output                          tx3_out2clk                          ;
output                          rx3_out2clk                          ;
output                          tx3_outclk                           ;
output                          rx3_outclk                           ;
input                           l3_resetmode_sel                     ;
input                           tx3_reset                            ;
input                           tx3_pma_reset                        ;
input                           tx3_pcs_reset                        ;
input                           tx3_pcsfifo_reset                    ;
input                           tx3_userrdy                          ;
input                           rx3_reset                            ;
input                           rx3_pma_reset                        ;
input                           rx3_pcs_reset                        ;
input                           rx3_pcsfifo_reset                    ;
input                           rx3_userrdy                          ;
output                          tx3_resetdone                        ;
output                          rx3_resetdone                        ;
input     [63:0]                tx3_data                             ;
input     [7:0]                 tx3_ctrl0_data                       ;
input     [7:0]                 tx3_ctrl1_data                       ;
input     [7:0]                 tx3_ctrl2_data                       ;
input                           tx3_data_en                          ;
input     [2:0]                 tx3_header                           ;
input     [6:0]                 tx3_sequence                         ;
input                           tx3_8b10b_en                         ;
input                           rx3_gearboxslip                      ;
input                           rx3_slide                            ;
input                           rx3_8b10b_en                         ;
input                           rx3_gpon_en                          ;
output    [63:0]                rx3_data                             ;
output    [7:0]                 rx3_ctrl0_data                       ;
output    [7:0]                 rx3_ctrl1_data                       ;
output    [7:0]                 rx3_ctrl2_data                       ;
output    [7:0]                 rx3_ctrl3_data                       ;
output    [2:0]                 rx3_header                           ;
output                          rx3_datavalid                        ;
output                          rx3_headervalid                      ;
output                          rx3_startofseq                       ;
output                          tx3_pcsfifo_rd_halffull              ;
output                          tx3_pcsfifo_rd_empty                 ;
output                          tx3_pcsfifo_wr_halffull              ;
output                          tx3_pcsfifo_wr_full                  ;
output                          tx3_piso_pop_halffull                ;
output                          tx3_piso_push_aempty                 ;
output                          tx3_piso_pop_empty                   ;
output                          tx3_piso_push_afull                  ;
output                          tx3_piso_push_halffull               ;
output                          tx3_piso_push_full                   ;
output                          rx3_sipo_pop_halffull                ;
output                          rx3_sipo_pop_aempty                  ;
output                          rx3_sipo_pop_empty                   ;
output                          rx3_sipo_push_afull                  ;
output                          rx3_sipo_push_halffull               ;
output                          rx3_sipo_push_full                   ;
output                          rx3_rmfifo_high                      ;
output                          rx3_rmfifo_low                       ;
output                          rx3_rmfifo_overflow                  ;
output                          rx3_rmfifo_underflow                 ;
output                          rx3_wordrealign                      ;
output                          rx3_wordaligned                      ;
output    [1:0]                 rx3_rmfifo_corcnt                    ;
output                          rx3_sipo_align_lock                  ;
output                          rx3_pll_lock                         ;
output                          rx3_pma_prbs_error                   ;
output                          tx3_dpll_lock                        ;
output                          tx3_pi_lock                          ;
output                          tx3_pll_lock                         ;
input                           tx3_req                              ;
input     [1:0]                 tx3_pstate                           ;
input     [2:0]                 tx3_rate                             ;
input                           tx3_detrx_req                        ;
output                          tx3_detrx_result                     ;
output                          tx3_ack                              ;
input                           rx3_req                              ;
input     [1:0]                 rx3_pstate                           ;
input     [2:0]                 rx3_rate                             ;
output                          rx3_ack                              ;
input                           tx3_polarity                         ;
input     [1:0]                 tx3_eq_ctrl                          ;
input     [5:0]                 tx3_eq_pre                           ;
input     [5:0]                 tx3_eq_main                          ;
input     [5:0]                 tx3_eq_post                          ;
input     [4:0]                 tx3_eq_preset                        ;
input                           tx3_eq_getlocal_pset_coef            ;
output    [17:0]                tx3_eq_local_tx_pset_coef            ;
output                          tx3_eq_local_tx_coef_valid           ;
output    [5:0]                 tx3_eq_localfs                       ;
output    [5:0]                 tx3_eq_locallf                       ;
input                           rx3_polarity                         ;
input                           rx3_adapt_cont                       ;
input                           rx3_adapt_in_prog                    ;
input                           rx3_adapt_req                        ;
input                           rx3_adapt_invalid_req                ;
input     [1:0]                 rx3_adapt_ctrl                       ;
output                          rx3_adapt_ack                        ;
output    [7:0]                 rx3_adapt_fom                        ;
output    [1:0]                 rx3_txmain_dir                       ;
output    [1:0]                 rx3_txpost_dir                       ;
output    [1:0]                 rx3_txpre_dir                        ;
input     [3:0]                 other_quad_rxclk		     ;
output    [3:0]                 local_quad_rxclk		     ;
input                           phy_reset                            ;
input                           phy_pipe_reset                       ;
output                          cmnresetdone                         ;
output    [1:0]                 refclkout                            ;
output    [7:0]                 groupclkout                          ;
output    [7:0]                 group0sigout                         ;
output    [7:0]                 group1sigout                         ;
output    [7:0]                 group2sigout                         ;
output    [7:0]                 group3sigout                         ;
output                          vdh_ready                            ;
input                           mcu_serdes_rxd                       ;
output                          mcu_serdes_txd                       ;
input                           mcu_phy_rst_sel                      ;
input                           mcu_phy_rst                          ;
input                           mcu_enable                           ;
input                           mcu_core_rst                         ;
output                          mcu_irq_o                            ;
output                          mcu_exchg_info_0                     ;
output                          mcu_sysrstreq                        ;
output                          cmn_pll_lock                         ;
input                           apb4_clk_i                           ;
input                           apb4_preset_i                        ;
input                           apb4_psel_i                          ;
input                           apb4_penable_i                       ;
input                           apb4_pwrite_i                        ;
input     [31:0]                apb4_paddr_i                         ;
input     [31:0]                apb4_pwdata_i                        ;
input     [3:0]                 apb4_pstrb_i                         ;
input     [2:0]                 apb4_pprot_i                         ;
output    [31:0]                apb4_prdata_o                        ;
output                          apb4_pready_o                        ;
output                          apb4_pslverr_o                       ;
input                           scan_rst_n                           ;
input                           scan_mode_n                          ;
input                           scan_clk                             ;
input                           scan_enable_n                        ;
input                           scancompress_mode                    ;
input     [9: 0]                scan_in                              ;
output    [9: 0]                scan_out                             ;
input                           mbist_mode_n                         ;
input                           dft_jtag_tck                         ;
input                           dft_jtag_trst_n                      ;
input                           dft_jtag_tms                         ;
input                           dft_jtag_tdi                         ;
output                          dft_jtag_tdo                         ;
input                           jtag_tck                             ;
input                           jtag_tms                             ;
input                           jtag_tdi                             ;
output                          jtag_tdo                             ;
output                          jtag_tdo_en                          ;
output                          pcie_osc_clk                         ;
input                           mac_phy_blockaligncontrol            ;
input    [2: 0]                 mac_phy_txmargin                     ;
input                           mac_phy_txswing                      ;
input    [3: 0]                 mac_phy_powerdown                    ;
input    [1: 0]                 mac_phy_width                        ;
input    [2: 0]                 mac_phy_pclk_rate                    ;
input    [1: 0]                 mac_phy_rate                         ;
input    [127: 0]               mac_phy_txdata                       ;
input    [15: 0]                mac_phy_txdatak                      ;
input    [3: 0]                 mac_phy_txdatavalid                  ;
input    [7: 0]                 mac_phy_txsyncheader                 ;
input    [3: 0]                 mac_phy_txstartblock                 ;
input    [3: 0]                 mac_phy_txelecidle                   ;
input    [3: 0]                 mac_phy_txcompliance                 ;
input    [3: 0]                 mac_phy_txdetectrx_loopback          ;
input    [3: 0]                 mac_phy_rxpolarity                   ;
input    [71: 0]                mac_phy_txdeemph                     ;
input    [11: 0]                mac_phy_rxpresethint                 ;
input    [23: 0]                mac_phy_fs                           ;
input    [23: 0]                mac_phy_lf                           ;
input    [19: 0]                mac_phy_local_pset_index             ;
input    [3: 0]                 mac_phy_getlocal_pset_coef           ;
input    [3: 0]                 mac_phy_rxeqeval                     ;
input    [3: 0]                 mac_phy_rxeqinprogress               ;
input    [3: 0]                 mac_phy_invalid_req                  ;
input    [3: 0]                 mac_phy_rxstandby                    ;
output                          phy_mac_pclk                         ;
output   [127: 0]               phy_mac_rxdata                       ;
output   [15: 0]                phy_mac_rxdatak                      ;
output   [7: 0]                 phy_mac_rxsyncheader                 ;
output   [3: 0]                 phy_mac_rxstartblock                 ;
output   [3: 0]                 phy_mac_rxelecidle                   ;
output   [3: 0]                 phy_mac_phystatus                    ;
output   [3: 0]                 phy_mac_rxvalid                      ;
output   [11: 0]                phy_mac_rxstatus                     ;
output   [3: 0]                 phy_mac_rxdatavalid                  ;
output   [23: 0]                phy_mac_dirfeedback                  ;
output   [31: 0]                phy_mac_fomfeedback                  ;
output   [71: 0]                phy_mac_local_tx_pset_coef           ;
output   [3: 0]                 phy_mac_local_tx_coef_valid          ;
output   [23: 0]                phy_mac_localfs                      ;
output   [23: 0]                phy_mac_locallf                      ;
input    [1:0]                  pcie_pclk_source_sel                 ;
input    [1:0]                  pcie_pipe_lane_flip                  ;
input    [3:0]                  pcie_pipe_lane_enable                ;
input                           pcie_core_bypass                     ;
input                           pcie_power_on_rst_n                  ;
input                           pcie_pcs_pipe_rst_n                  ;
input                           pcie_pcs_apb_rst_n                   ;
input                           pcie_core_sram_init_done             ;
parameter                       PH1P_LANE_SEL                               =      "DISABLE";
parameter     [3:0]             TX_LANE_ENABLE                              =      4'h0;
parameter     [3:0]             RX_LANE_ENABLE                              =      4'h0;
parameter     [0:0]             CFG_WAKEUP_BYPASS                           =      1'h0;
parameter     [4:0]             CFG_JTAG_CTRL                               =      5'h00;
parameter     [2:0]             CFG_OSC_CTRL                                =      3'b101;
parameter     [5:0]             CFG_CLK_CTRL                                =      6'h32 ;
parameter     [0:0]             PH1P_HXT_MCU_MODE                           =      1'h0;
parameter     [3:0]             CFG_CORE_MCU_CTRL                           =     ( PH1P_HXT_MCU_MODE == 1'b1 ) ? 4'hc : 4'h3;
parameter     [31:0]            MCU_CLK_FREQ                                =      32'h0;
parameter     [31:0]            TOP00_VLD                                   =      32'h01050501;
parameter     [31:0]            TOP01_VLD                                   =      32'h00000000;
parameter     [31:0]            TOP02_VLD                                   =      32'h00000000;
parameter     [31:0]            TOP03_VLD                                   =     ( PH1P_HXT_MCU_MODE == 1'b1 ) ? {28'h0,CFG_CLK_CTRL[3:0]} :32'h00000000;
parameter     [31:0]            ZCAL00_VLD                                  =      32'h00000030;
parameter     [31:0]            ZCAL01_VLD                                  =      32'h00000003;
parameter     [31:0]            ZCAL02_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL03_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL04_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL05_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL06_VLD                                  =      32'h00000342;
parameter     [31:0]            CDRDRV_VLD                                  =      32'h00000000;
parameter     [31:0]            REFCLK_CTL_VLD                              =      32'h0000000f;
parameter     [31:0]            JM_CTL_VLD                                  =      32'h00000000;
parameter     [31:0]            CMN_PLL_CLOCK_VLD                           =      32'h5a2e0300;
parameter     [31:0]            CMN_PLL_FRAC_N00_VLD                        =      32'h00000000;
parameter     [31:0]            CMN_PLL_FRAC_N01_VLD                        =      32'h00000000;
parameter     [31:0]            CMN_PLL_CAL00_VLD                           =      32'h05300486;
parameter     [31:0]            CMN_PLL_TDC_CTL00_VLD                       =      32'h00000000;
parameter     [31:0]            CMN_PLL_TEST00_VLD                          =      32'h00000160;
parameter     [31:0]            ADC_BG_OSC00_VLD                            =      32'h00207020;
parameter     [31:0]            PMA_QUAD_RSV_VLD                            =      32'h00000000;
parameter     [31:0]            CMN_DEBUG_0_VLD                             =      32'h00000000;
parameter     [31:0]            CMN_ILM_CTL_ADDR_VLD                        =      32'h00000000;
parameter     [31:0]            CMN_ILM_WR_PORT_VLD                         =      32'h00000000;
parameter     [31:0]            CMN_ILM_RD_TRIG_VLD                         =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_CLK_PATH00_VLD                     =      32'h00000043;
parameter     [31:0]            LANE0_TX_DCC_CTRL_VLD                       =      32'h00003420;
parameter     [31:0]            LANE0_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE0_TX_RCV_DET_CTL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_PLL_MAIN_CTL_VLD                   =      32'h00000003;
parameter     [31:0]            LANE0_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE0_TX_FBDIV_CTL00_VLD                    =      32'h06000000;
parameter     [31:0]            LANE0_TX_FBDIV_CTL01_VLD                    =      32'h00080000;
parameter     [31:0]            LANE0_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE0_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE0_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE0_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE0_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE0_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00000002;
parameter     [31:0]            LANE0_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE0_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE0_RX_ATT_CTLE00_VLD                     =      32'h00000400;
parameter     [31:0]            LANE0_RX_ATT_CTLE01_VLD                     =      32'h00000050;
parameter     [31:0]            LANE0_RX_ATT_CTLE02_VLD                     =      32'h04502050;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h00000000;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h03000600;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h00080000;
parameter     [31:0]            LANE0_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE0_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE0_RX_DESER_CDR00_VLD                    =      32'h03600000;
parameter     [31:0]            LANE0_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_6_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE0_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE0_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE0_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE0_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE0_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE0_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE0_TX_PI_CTL_VLD                         =      32'h00003000;
parameter     [31:0]            LANE0_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE0_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE0_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE0_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE0_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE0_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE0_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE0_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE0_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE0_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE0_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE0_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE0_RX_SIPO_ALIGN_VLD                     =      32'h00007430;
parameter     [31:0]            LANE0_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE0_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE0_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE0_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE0_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE0_RX_EQ_CTL_VLD                         =      32'h00000080;
parameter     [31:0]            LANE0_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE0_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE0_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_CLK_PATH00_VLD                     =      32'h00000043;
parameter     [31:0]            LANE1_TX_DCC_CTRL_VLD                       =      32'h00003420;
parameter     [31:0]            LANE1_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE1_TX_RCV_DET_CTL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_PLL_MAIN_CTL_VLD                   =      32'h00000003;
parameter     [31:0]            LANE1_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE1_TX_FBDIV_CTL00_VLD                    =      32'h06000000;
parameter     [31:0]            LANE1_TX_FBDIV_CTL01_VLD                    =      32'h00080000;
parameter     [31:0]            LANE1_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE1_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE1_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE1_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE1_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE1_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00000002;
parameter     [31:0]            LANE1_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE1_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE1_RX_ATT_CTLE00_VLD                     =      32'h00000400;
parameter     [31:0]            LANE1_RX_ATT_CTLE01_VLD                     =      32'h00000050;
parameter     [31:0]            LANE1_RX_ATT_CTLE02_VLD                     =      32'h04502050;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h00000000;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h03000600;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h00080000;
parameter     [31:0]            LANE1_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE1_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE1_RX_DESER_CDR00_VLD                    =      32'h03600000;
parameter     [31:0]            LANE1_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_6_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE1_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE1_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE1_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE1_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE1_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE1_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE1_TX_PI_CTL_VLD                         =      32'h00003000;
parameter     [31:0]            LANE1_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE1_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE1_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE1_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE1_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE1_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE1_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE1_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE1_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE1_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE1_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE1_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE1_RX_SIPO_ALIGN_VLD                     =      32'h00007430;
parameter     [31:0]            LANE1_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE1_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE1_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE1_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE1_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE1_RX_EQ_CTL_VLD                         =      32'h00000080;
parameter     [31:0]            LANE1_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE1_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE1_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_CLK_PATH00_VLD                     =      32'h00000043;
parameter     [31:0]            LANE2_TX_DCC_CTRL_VLD                       =      32'h00003420;
parameter     [31:0]            LANE2_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE2_TX_RCV_DET_CTL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_PLL_MAIN_CTL_VLD                   =      32'h00000003;
parameter     [31:0]            LANE2_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE2_TX_FBDIV_CTL00_VLD                    =      32'h06000000;
parameter     [31:0]            LANE2_TX_FBDIV_CTL01_VLD                    =      32'h00080000;
parameter     [31:0]            LANE2_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE2_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE2_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE2_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE2_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE2_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00000002;
parameter     [31:0]            LANE2_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE2_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE2_RX_ATT_CTLE00_VLD                     =      32'h00000400;
parameter     [31:0]            LANE2_RX_ATT_CTLE01_VLD                     =      32'h00000050;
parameter     [31:0]            LANE2_RX_ATT_CTLE02_VLD                     =      32'h04502050;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h00000000;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h03000600;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h00080000;
parameter     [31:0]            LANE2_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE2_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE2_RX_DESER_CDR00_VLD                    =      32'h03600000;
parameter     [31:0]            LANE2_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_6_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE2_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE2_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE2_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE2_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE2_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE2_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE2_TX_PI_CTL_VLD                         =      32'h00003000;
parameter     [31:0]            LANE2_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE2_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE2_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE2_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE2_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE2_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE2_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE2_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE2_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE2_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE2_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE2_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE2_RX_SIPO_ALIGN_VLD                     =      32'h00007430;
parameter     [31:0]            LANE2_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE2_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE2_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE2_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE2_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE2_RX_EQ_CTL_VLD                         =      32'h00000080;
parameter     [31:0]            LANE2_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE2_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE2_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_CLK_PATH00_VLD                     =      32'h00000043;
parameter     [31:0]            LANE3_TX_DCC_CTRL_VLD                       =      32'h00003420;
parameter     [31:0]            LANE3_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE3_TX_RCV_DET_CTL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_PLL_MAIN_CTL_VLD                   =      32'h00000003;
parameter     [31:0]            LANE3_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE3_TX_FBDIV_CTL00_VLD                    =      32'h06000000;
parameter     [31:0]            LANE3_TX_FBDIV_CTL01_VLD                    =      32'h00080000;
parameter     [31:0]            LANE3_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE3_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE3_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE3_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE3_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE3_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00000002;
parameter     [31:0]            LANE3_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE3_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE3_RX_ATT_CTLE00_VLD                     =      32'h00000400;
parameter     [31:0]            LANE3_RX_ATT_CTLE01_VLD                     =      32'h00000050;
parameter     [31:0]            LANE3_RX_ATT_CTLE02_VLD                     =      32'h04502050;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h00000000;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h03000600;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h00080000;
parameter     [31:0]            LANE3_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE3_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE3_RX_DESER_CDR00_VLD                    =      32'h03600000;
parameter     [31:0]            LANE3_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_6_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE3_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE3_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE3_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE3_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE3_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE3_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE3_TX_PI_CTL_VLD                         =      32'h00003000;
parameter     [31:0]            LANE3_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE3_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE3_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE3_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE3_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE3_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE3_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE3_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE3_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE3_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE3_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE3_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE3_RX_SIPO_ALIGN_VLD                     =      32'h00007430;
parameter     [31:0]            LANE3_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE3_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE3_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE3_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE3_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE3_RX_EQ_CTL_VLD                         =      32'h00000080;
parameter     [31:0]            LANE3_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE3_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE3_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [3:0]             OTHER_QUAD_RXCLK_EN                         =      4'b0000;
parameter     [63:0]            LANE0_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE1_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE2_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE3_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE0_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE1_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE2_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE3_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
endmodule
module PH1P_PHY_HXT_V2 (
rx0_n                             ,
rx0_p                             ,
rx1_n                             ,
rx1_p                             ,
rx2_n                             ,
rx2_p                             ,
rx3_n                             ,
rx3_p                             ,
tx0_n                             ,
tx0_p                             ,
tx1_n                             ,
tx1_p                             ,
tx2_n                             ,
tx2_p                             ,
tx3_n                             ,
tx3_p                             ,
ref0_clk_p                        ,
ref0_clk_n                        ,
ref1_clk_p                        ,
ref1_clk_n                        ,
phy_extres_en                     ,
refclk_se                         ,
tx0_usr2clk                       ,
rx0_usr2clk                       ,
tx0_out2clk                       ,
rx0_out2clk                       ,
tx0_outclk                        ,
rx0_outclk                      ,
l0_resetmode_sel                  ,
tx0_reset                         ,
tx0_pma_reset                     ,
tx0_pcs_reset                     ,
tx0_pcsfifo_reset                 ,
tx0_userrdy                       ,
rx0_reset                         ,
rx0_pma_reset                     ,
rx0_pcs_reset                     ,
rx0_pcsfifo_reset                 ,
rx0_userrdy                       ,
tx0_resetdone                     ,
rx0_resetdone                     ,
tx0_data                          ,
tx0_ctrl0_data                    ,
tx0_ctrl1_data                    ,
tx0_ctrl2_data                    ,
tx0_data_en                       ,
tx0_header                        ,
tx0_sequence                      ,
tx0_8b10b_en                      ,
rx0_gearboxslip                   ,
rx0_slide                         ,
rx0_8b10b_en                      ,
rx0_gpon_en                       ,
rx0_data                          ,
rx0_ctrl0_data                    ,
rx0_ctrl1_data                    ,
rx0_ctrl2_data                    ,
rx0_ctrl3_data                    ,
rx0_header                        ,
rx0_datavalid                     ,
rx0_headervalid                   ,
rx0_startofseq                    ,
tx0_pcsfifo_rd_halffull           ,
tx0_pcsfifo_rd_empty              ,
tx0_pcsfifo_wr_halffull           ,
tx0_pcsfifo_wr_full               ,
tx0_piso_pop_halffull             ,
tx0_piso_push_aempty              ,
tx0_piso_pop_empty                ,
tx0_piso_push_afull               ,
tx0_piso_push_halffull            ,
tx0_piso_push_full                ,
rx0_sipo_pop_halffull             ,
rx0_sipo_pop_aempty               ,
rx0_sipo_pop_empty                ,
rx0_sipo_push_afull               ,
rx0_sipo_push_halffull            ,
rx0_sipo_push_full                ,
rx0_rmfifo_high                   ,
rx0_rmfifo_low                    ,
rx0_rmfifo_overflow               ,
rx0_rmfifo_underflow              ,
rx0_wordrealign                   ,
rx0_wordaligned                   ,
rx0_rmfifo_corcnt                 ,
rx0_sipo_align_lock               ,
rx0_pll_lock                      ,
rx0_pma_prbs_error                ,
tx0_dpll_lock                     ,
tx0_pi_lock                       ,
tx0_pll_lock                      ,
tx0_req                           ,
tx0_pstate                        ,
tx0_rate                          ,
tx0_detrx_req                     ,
tx0_detrx_result                  ,
tx0_ack                           ,
rx0_req                           ,
rx0_pstate                        ,
rx0_rate                          ,
rx0_ack                           ,
tx0_polarity                      ,
tx0_eq_ctrl                       ,
tx0_eq_pre                        ,
tx0_eq_main                       ,
tx0_eq_post                       ,
tx0_eq_preset                     ,
tx0_eq_getlocal_pset_coef         ,
tx0_eq_local_tx_pset_coef         ,
tx0_eq_local_tx_coef_valid        ,
tx0_eq_localfs                    ,
tx0_eq_locallf                    ,
rx0_polarity                      ,
rx0_adapt_cont                    ,
rx0_adapt_in_prog                 ,
rx0_adapt_req                     ,
rx0_adapt_invalid_req             ,
rx0_adapt_ctrl                    ,
rx0_adapt_ack                     ,
rx0_adapt_fom                     ,
rx0_txmain_dir                    ,
rx0_txpost_dir                    ,
rx0_txpre_dir                     ,
tx1_usr2clk                       ,
rx1_usr2clk                       ,
tx1_out2clk                       ,
rx1_out2clk                       ,
tx1_outclk                        ,
rx1_outclk                        ,
l1_resetmode_sel                  ,
tx1_reset                         ,
tx1_pma_reset                     ,
tx1_pcs_reset                     ,
tx1_pcsfifo_reset                 ,
tx1_userrdy                       ,
rx1_reset                         ,
rx1_pma_reset                     ,
rx1_pcs_reset                     ,
rx1_pcsfifo_reset                 ,
rx1_userrdy                       ,
tx1_resetdone                     ,
rx1_resetdone                     ,
tx1_data                          ,
tx1_ctrl0_data                    ,
tx1_ctrl1_data                    ,
tx1_ctrl2_data                    ,
tx1_data_en                       ,
tx1_header                        ,
tx1_sequence                      ,
tx1_8b10b_en                      ,
rx1_gearboxslip                   ,
rx1_slide                         ,
rx1_8b10b_en                      ,
rx1_gpon_en                       ,
rx1_data                          ,
rx1_ctrl0_data                    ,
rx1_ctrl1_data                    ,
rx1_ctrl2_data                    ,
rx1_ctrl3_data                    ,
rx1_header                        ,
rx1_datavalid                     ,
rx1_headervalid                   ,
rx1_startofseq                    ,
tx1_pcsfifo_rd_halffull           ,
tx1_pcsfifo_rd_empty              ,
tx1_pcsfifo_wr_halffull           ,
tx1_pcsfifo_wr_full               ,
tx1_piso_pop_halffull             ,
tx1_piso_push_aempty              ,
tx1_piso_pop_empty                ,
tx1_piso_push_afull               ,
tx1_piso_push_halffull            ,
tx1_piso_push_full                ,
rx1_sipo_pop_halffull             ,
rx1_sipo_pop_aempty               ,
rx1_sipo_pop_empty                ,
rx1_sipo_push_afull               ,
rx1_sipo_push_halffull            ,
rx1_sipo_push_full                ,
rx1_rmfifo_high                   ,
rx1_rmfifo_low                    ,
rx1_rmfifo_overflow               ,
rx1_rmfifo_underflow              ,
rx1_wordrealign                   ,
rx1_wordaligned                   ,
rx1_rmfifo_corcnt                 ,
rx1_sipo_align_lock               ,
rx1_pll_lock                      ,
rx1_pma_prbs_error                ,
tx1_dpll_lock                     ,
tx1_pi_lock                       ,
tx1_pll_lock                      ,
tx1_req                           ,
tx1_pstate                        ,
tx1_rate                          ,
tx1_detrx_req                     ,
tx1_detrx_result                  ,
tx1_ack                           ,
rx1_req                           ,
rx1_pstate                        ,
rx1_rate                          ,
rx1_ack                           ,
tx1_polarity                      ,
tx1_eq_ctrl                       ,
tx1_eq_pre                        ,
tx1_eq_main                       ,
tx1_eq_post                       ,
tx1_eq_preset                     ,
tx1_eq_getlocal_pset_coef         ,
tx1_eq_local_tx_pset_coef         ,
tx1_eq_local_tx_coef_valid        ,
tx1_eq_localfs                    ,
tx1_eq_locallf                    ,
rx1_polarity                      ,
rx1_adapt_cont                    ,
rx1_adapt_in_prog                 ,
rx1_adapt_req                     ,
rx1_adapt_invalid_req             ,
rx1_adapt_ctrl                    ,
rx1_adapt_ack                     ,
rx1_adapt_fom                     ,
rx1_txmain_dir                    ,
rx1_txpost_dir                    ,
rx1_txpre_dir                     ,
tx2_usr2clk                       ,
rx2_usr2clk                       ,
tx2_out2clk                       ,
rx2_out2clk                       ,
tx2_outclk                        ,
rx2_outclk                        ,
l2_resetmode_sel                  ,
tx2_reset                         ,
tx2_pma_reset                     ,
tx2_pcs_reset                     ,
tx2_pcsfifo_reset                 ,
tx2_userrdy                       ,
rx2_reset                         ,
rx2_pma_reset                     ,
rx2_pcs_reset                     ,
rx2_pcsfifo_reset                 ,
rx2_userrdy                       ,
tx2_resetdone                     ,
rx2_resetdone                     ,
tx2_data                          ,
tx2_ctrl0_data                    ,
tx2_ctrl1_data                    ,
tx2_ctrl2_data                    ,
tx2_data_en                       ,
tx2_header                        ,
tx2_sequence                      ,
tx2_8b10b_en                      ,
rx2_gearboxslip                   ,
rx2_slide                         ,
rx2_8b10b_en                      ,
rx2_gpon_en                       ,
rx2_data                          ,
rx2_ctrl0_data                    ,
rx2_ctrl1_data                    ,
rx2_ctrl2_data                    ,
rx2_ctrl3_data                    ,
rx2_header                        ,
rx2_datavalid                     ,
rx2_headervalid                   ,
rx2_startofseq                    ,
tx2_pcsfifo_rd_halffull           ,
tx2_pcsfifo_rd_empty              ,
tx2_pcsfifo_wr_halffull           ,
tx2_pcsfifo_wr_full               ,
tx2_piso_pop_halffull             ,
tx2_piso_push_aempty              ,
tx2_piso_pop_empty                ,
tx2_piso_push_afull               ,
tx2_piso_push_halffull            ,
tx2_piso_push_full                ,
rx2_sipo_pop_halffull             ,
rx2_sipo_pop_aempty               ,
rx2_sipo_pop_empty                ,
rx2_sipo_push_afull               ,
rx2_sipo_push_halffull            ,
rx2_sipo_push_full                ,
rx2_rmfifo_high                   ,
rx2_rmfifo_low                    ,
rx2_rmfifo_overflow               ,
rx2_rmfifo_underflow              ,
rx2_wordrealign                   ,
rx2_wordaligned                   ,
rx2_rmfifo_corcnt                 ,
rx2_sipo_align_lock               ,
rx2_pll_lock                      ,
rx2_pma_prbs_error                ,
tx2_dpll_lock                     ,
tx2_pi_lock                       ,
tx2_pll_lock                      ,
tx2_req                           ,
tx2_pstate                        ,
tx2_rate                          ,
tx2_detrx_req                     ,
tx2_detrx_result                  ,
tx2_ack                           ,
rx2_req                           ,
rx2_pstate                        ,
rx2_rate                          ,
rx2_ack                           ,
tx2_polarity                      ,
tx2_eq_ctrl                       ,
tx2_eq_pre                        ,
tx2_eq_main                       ,
tx2_eq_post                       ,
tx2_eq_preset                     ,
tx2_eq_getlocal_pset_coef         ,
tx2_eq_local_tx_pset_coef         ,
tx2_eq_local_tx_coef_valid        ,
tx2_eq_localfs                    ,
tx2_eq_locallf                    ,
rx2_polarity                      ,
rx2_adapt_cont                    ,
rx2_adapt_in_prog                 ,
rx2_adapt_req                     ,
rx2_adapt_invalid_req             ,
rx2_adapt_ctrl                    ,
rx2_adapt_ack                     ,
rx2_adapt_fom                     ,
rx2_txmain_dir                    ,
rx2_txpost_dir                    ,
rx2_txpre_dir                     ,
tx3_usr2clk                       ,
rx3_usr2clk                       ,
tx3_out2clk                       ,
rx3_out2clk                       ,
tx3_outclk                        ,
rx3_outclk                        ,
l3_resetmode_sel                  ,
tx3_reset                         ,
tx3_pma_reset                     ,
tx3_pcs_reset                     ,
tx3_pcsfifo_reset                 ,
tx3_userrdy                       ,
rx3_reset                         ,
rx3_pma_reset                     ,
rx3_pcs_reset                     ,
rx3_pcsfifo_reset                 ,
rx3_userrdy                       ,
tx3_resetdone                     ,
rx3_resetdone                     ,
tx3_data                          ,
tx3_ctrl0_data                    ,
tx3_ctrl1_data                    ,
tx3_ctrl2_data                    ,
tx3_data_en                       ,
tx3_header                        ,
tx3_sequence                      ,
tx3_8b10b_en                      ,
rx3_gearboxslip                   ,
rx3_slide                         ,
rx3_8b10b_en                      ,
rx3_gpon_en                       ,
rx3_data                          ,
rx3_ctrl0_data                    ,
rx3_ctrl1_data                    ,
rx3_ctrl2_data                    ,
rx3_ctrl3_data                    ,
rx3_header                        ,
rx3_datavalid                     ,
rx3_headervalid                   ,
rx3_startofseq                    ,
tx3_pcsfifo_rd_halffull           ,
tx3_pcsfifo_rd_empty              ,
tx3_pcsfifo_wr_halffull           ,
tx3_pcsfifo_wr_full               ,
tx3_piso_pop_halffull             ,
tx3_piso_push_aempty              ,
tx3_piso_pop_empty                ,
tx3_piso_push_afull               ,
tx3_piso_push_halffull            ,
tx3_piso_push_full                ,
rx3_sipo_pop_halffull             ,
rx3_sipo_pop_aempty               ,
rx3_sipo_pop_empty                ,
rx3_sipo_push_afull               ,
rx3_sipo_push_halffull            ,
rx3_sipo_push_full                ,
rx3_rmfifo_high                   ,
rx3_rmfifo_low                    ,
rx3_rmfifo_overflow               ,
rx3_rmfifo_underflow              ,
rx3_wordrealign                   ,
rx3_wordaligned                   ,
rx3_rmfifo_corcnt                 ,
rx3_sipo_align_lock               ,
rx3_pll_lock                      ,
rx3_pma_prbs_error                ,
tx3_dpll_lock                     ,
tx3_pi_lock                       ,
tx3_pll_lock                      ,
tx3_req                           ,
tx3_pstate                        ,
tx3_rate                          ,
tx3_detrx_req                     ,
tx3_detrx_result                  ,
tx3_ack                           ,
rx3_req                           ,
rx3_pstate                        ,
rx3_rate                          ,
rx3_ack                           ,
tx3_polarity                      ,
tx3_eq_ctrl                       ,
tx3_eq_pre                        ,
tx3_eq_main                       ,
tx3_eq_post                       ,
tx3_eq_preset                     ,
tx3_eq_getlocal_pset_coef         ,
tx3_eq_local_tx_pset_coef         ,
tx3_eq_local_tx_coef_valid        ,
tx3_eq_localfs                    ,
tx3_eq_locallf                    ,
rx3_polarity                      ,
rx3_adapt_cont                    ,
rx3_adapt_in_prog                 ,
rx3_adapt_req                     ,
rx3_adapt_invalid_req             ,
rx3_adapt_ctrl                    ,
rx3_adapt_ack                     ,
rx3_adapt_fom                     ,
rx3_txmain_dir                    ,
rx3_txpost_dir                    ,
rx3_txpre_dir                     ,
phy_reset                         ,
phy_pipe_reset                    ,
cmnresetdone                      ,
refclkout                         ,
groupclkout                       ,
group0sigout                      ,
group1sigout                      ,
group2sigout                      ,
group3sigout                      ,
vdh_ready                         ,
mcu_serdes_rxd                    ,
mcu_serdes_txd                    ,
mcu_phy_rst_sel                   ,
mcu_phy_rst                       ,
mcu_enable                        ,
mcu_core_rst                      ,
mcu_irq_o                         ,
mcu_exchg_info_0                  ,
mcu_sysrstreq                     ,
cmn_pll_lock                      ,
apb4_clk_i                        ,
apb4_preset_i                     ,
apb4_psel_i                       ,
apb4_penable_i                    ,
apb4_pwrite_i                     ,
apb4_paddr_i                      ,
apb4_pwdata_i                     ,
apb4_pstrb_i                      ,
apb4_pprot_i                      ,
apb4_prdata_o                     ,
apb4_pready_o                     ,
apb4_pslverr_o                    ,
scan_rst_n                        ,
scan_mode_n                       ,
scan_clk                          ,
scan_enable_n                     ,
scancompress_mode                 ,
scan_in                           ,
scan_out                          ,
mbist_mode_n                      ,
dft_jtag_tck                      ,
dft_jtag_trst_n                   ,
dft_jtag_tms                      ,
dft_jtag_tdi                      ,
dft_jtag_tdo                      ,
jtag_tck                          ,
jtag_tms                          ,
jtag_tdi                          ,
jtag_tdo                          ,
jtag_tdo_en                       ,
pcie_osc_clk                      ,
mac_phy_txdata                    ,
mac_phy_txdatak                   ,
mac_phy_txdatavalid               ,
mac_phy_txsyncheader              ,
phy_mac_rxdata                    ,
phy_mac_rxdatak                   ,
phy_mac_rxsyncheader              ,
mac_phy_txdeemph                  ,
mac_phy_rxpresethint              ,
mac_phy_fs                        ,
mac_phy_lf                        ,
mac_phy_local_pset_index          ,
mac_phy_getlocal_pset_coef        ,
mac_phy_rxeqeval                  ,
mac_phy_rxeqinprogress            ,
mac_phy_invalid_req               ,
phy_mac_dirfeedback               ,
phy_mac_fomfeedback               ,
phy_mac_local_tx_pset_coef        ,
phy_mac_local_tx_coef_valid       ,
phy_mac_localfs                   ,
phy_mac_locallf                   ,
mac_phy_blockaligncontrol         ,
mac_phy_txmargin                  ,
mac_phy_txswing                   ,
mac_phy_powerdown                 ,
mac_phy_width                     ,
mac_phy_pclk_rate                 ,
mac_phy_rate                      ,
mac_phy_txstartblock              ,
mac_phy_txelecidle                ,
mac_phy_txcompliance              ,
mac_phy_txdetectrx_loopback       ,
mac_phy_rxpolarity                ,
mac_phy_rxstandby                 ,
phy_mac_pclk                      ,
phy_mac_rxstartblock              ,
phy_mac_rxelecidle                ,
phy_mac_phystatus                 ,
phy_mac_rxvalid                   ,
phy_mac_rxstatus                  ,
phy_mac_rxdatavalid               ,
pcie_core_sram_init_done          ,
pcie_pclk_source_sel              ,
pcie_pipe_lane_flip               ,
pcie_pipe_lane_enable             ,
pcie_core_bypass                  ,
pcie_power_on_rst_n               ,
pcie_pcs_pipe_rst_n               ,
pcie_pcs_apb_rst_n
);
input                           rx0_n                                ;
input                           rx0_p                                ;
input                           rx1_n                                ;
input                           rx1_p                                ;
input                           rx2_n                                ;
input                           rx2_p                                ;
input                           rx3_n                                ;
input                           rx3_p                                ;
output                          tx0_n                                ;
output                          tx0_p                                ;
output                          tx1_n                                ;
output                          tx1_p                                ;
output                          tx2_n                                ;
output                          tx2_p                                ;
output                          tx3_n                                ;
output                          tx3_p                                ;
input                           phy_extres_en                        ;
inout                           ref0_clk_p                           ;
inout                           ref0_clk_n                           ;
inout                           ref1_clk_p                           ;
inout                           ref1_clk_n                           ;
input     [1:0]                 refclk_se                            ;
input                           tx0_usr2clk                          ;
input                           rx0_usr2clk                          ;
output                          tx0_out2clk                          ;
output                          rx0_out2clk                          ;
output                          tx0_outclk                           ;
output                          rx0_outclk                           ;
input                           l0_resetmode_sel                     ;
input                           tx0_reset                            ;
input                           tx0_pma_reset                        ;
input                           tx0_pcs_reset                        ;
input                           tx0_pcsfifo_reset                    ;
input                           tx0_userrdy                          ;
input                           rx0_reset                            ;
input                           rx0_pma_reset                        ;
input                           rx0_pcs_reset                        ;
input                           rx0_pcsfifo_reset                    ;
input                           rx0_userrdy                          ;
output                          tx0_resetdone                        ;
output                          rx0_resetdone                        ;
input     [63:0]                tx0_data                             ;
input     [7:0]                 tx0_ctrl0_data                       ;
input     [7:0]                 tx0_ctrl1_data                       ;
input     [7:0]                 tx0_ctrl2_data                       ;
input                           tx0_data_en                          ;
input     [2:0]                 tx0_header                           ;
input     [6:0]                 tx0_sequence                         ;
input                           tx0_8b10b_en                         ;
input                           rx0_gearboxslip                      ;
input                           rx0_slide                            ;
input                           rx0_8b10b_en                         ;
input                           rx0_gpon_en                          ;
output    [63:0]                rx0_data                             ;
output    [7:0]                 rx0_ctrl0_data                       ;
output    [7:0]                 rx0_ctrl1_data                       ;
output    [7:0]                 rx0_ctrl2_data                       ;
output    [7:0]                 rx0_ctrl3_data                       ;
output    [2:0]                 rx0_header                           ;
output                          rx0_datavalid                        ;
output                          rx0_headervalid                      ;
output                          rx0_startofseq                       ;
output                          tx0_pcsfifo_rd_halffull              ;
output                          tx0_pcsfifo_rd_empty                 ;
output                          tx0_pcsfifo_wr_halffull              ;
output                          tx0_pcsfifo_wr_full                  ;
output                          tx0_piso_pop_halffull                ;
output                          tx0_piso_push_aempty                 ;
output                          tx0_piso_pop_empty                   ;
output                          tx0_piso_push_afull                  ;
output                          tx0_piso_push_halffull               ;
output                          tx0_piso_push_full                   ;
output                          rx0_sipo_pop_halffull                ;
output                          rx0_sipo_pop_aempty                  ;
output                          rx0_sipo_pop_empty                   ;
output                          rx0_sipo_push_afull                  ;
output                          rx0_sipo_push_halffull               ;
output                          rx0_sipo_push_full                   ;
output                          rx0_rmfifo_high                      ;
output                          rx0_rmfifo_low                       ;
output                          rx0_rmfifo_overflow                  ;
output                          rx0_rmfifo_underflow                 ;
output                          rx0_wordrealign                      ;
output                          rx0_wordaligned                      ;
output    [1:0]                 rx0_rmfifo_corcnt                    ;
output                          rx0_sipo_align_lock                  ;
output                          rx0_pll_lock                         ;
output                          rx0_pma_prbs_error                   ;
output                          tx0_dpll_lock                        ;
output                          tx0_pi_lock                          ;
output                          tx0_pll_lock                         ;
input                           tx0_req                              ;
input     [1:0]                 tx0_pstate                           ;
input     [2:0]                 tx0_rate                             ;
input                           tx0_detrx_req                        ;
output                          tx0_detrx_result                     ;
output                          tx0_ack                              ;
input                           rx0_req                              ;
input     [1:0]                 rx0_pstate                           ;
input     [2:0]                 rx0_rate                             ;
output                          rx0_ack                              ;
input                           tx0_polarity                         ;
input     [1:0]                 tx0_eq_ctrl                          ;
input     [5:0]                 tx0_eq_pre                           ;
input     [5:0]                 tx0_eq_main                          ;
input     [5:0]                 tx0_eq_post                          ;
input     [4:0]                 tx0_eq_preset                        ;
input                           tx0_eq_getlocal_pset_coef            ;
output    [17:0]                tx0_eq_local_tx_pset_coef            ;
output                          tx0_eq_local_tx_coef_valid           ;
output    [5:0]                 tx0_eq_localfs                       ;
output    [5:0]                 tx0_eq_locallf                       ;
input                           rx0_polarity                         ;
input                           rx0_adapt_cont                       ;
input                           rx0_adapt_in_prog                    ;
input                           rx0_adapt_req                        ;
input                           rx0_adapt_invalid_req                ;
input     [1:0]                 rx0_adapt_ctrl                       ;
output                          rx0_adapt_ack                        ;
output    [7:0]                 rx0_adapt_fom                        ;
output    [1:0]                 rx0_txmain_dir                       ;
output    [1:0]                 rx0_txpost_dir                       ;
output    [1:0]                 rx0_txpre_dir                        ;
input                           tx1_usr2clk                          ;
input                           rx1_usr2clk                          ;
output                          tx1_out2clk                          ;
output                          rx1_out2clk                          ;
output                          tx1_outclk                           ;
output                          rx1_outclk                           ;
input                           l1_resetmode_sel                     ;
input                           tx1_reset                            ;
input                           tx1_pma_reset                        ;
input                           tx1_pcs_reset                        ;
input                           tx1_pcsfifo_reset                    ;
input                           tx1_userrdy                          ;
input                           rx1_reset                            ;
input                           rx1_pma_reset                        ;
input                           rx1_pcs_reset                        ;
input                           rx1_pcsfifo_reset                    ;
input                           rx1_userrdy                          ;
output                          tx1_resetdone                        ;
output                          rx1_resetdone                        ;
input     [63:0]                tx1_data                             ;
input     [7:0]                 tx1_ctrl0_data                       ;
input     [7:0]                 tx1_ctrl1_data                       ;
input     [7:0]                 tx1_ctrl2_data                       ;
input                           tx1_data_en                          ;
input     [2:0]                 tx1_header                           ;
input     [6:0]                 tx1_sequence                         ;
input                           tx1_8b10b_en                         ;
input                           rx1_gearboxslip                      ;
input                           rx1_slide                            ;
input                           rx1_8b10b_en                         ;
input                           rx1_gpon_en                          ;
output    [63:0]                rx1_data                             ;
output    [7:0]                 rx1_ctrl0_data                       ;
output    [7:0]                 rx1_ctrl1_data                       ;
output    [7:0]                 rx1_ctrl2_data                       ;
output    [7:0]                 rx1_ctrl3_data                       ;
output    [2:0]                 rx1_header                           ;
output                          rx1_datavalid                        ;
output                          rx1_headervalid                      ;
output                          rx1_startofseq                       ;
output                          tx1_pcsfifo_rd_halffull              ;
output                          tx1_pcsfifo_rd_empty                 ;
output                          tx1_pcsfifo_wr_halffull              ;
output                          tx1_pcsfifo_wr_full                  ;
output                          tx1_piso_pop_halffull                ;
output                          tx1_piso_push_aempty                 ;
output                          tx1_piso_pop_empty                   ;
output                          tx1_piso_push_afull                  ;
output                          tx1_piso_push_halffull               ;
output                          tx1_piso_push_full                   ;
output                          rx1_sipo_pop_halffull                ;
output                          rx1_sipo_pop_aempty                  ;
output                          rx1_sipo_pop_empty                   ;
output                          rx1_sipo_push_afull                  ;
output                          rx1_sipo_push_halffull               ;
output                          rx1_sipo_push_full                   ;
output                          rx1_rmfifo_high                      ;
output                          rx1_rmfifo_low                       ;
output                          rx1_rmfifo_overflow                  ;
output                          rx1_rmfifo_underflow                 ;
output                          rx1_wordrealign                      ;
output                          rx1_wordaligned                      ;
output    [1:0]                 rx1_rmfifo_corcnt                    ;
output                          rx1_sipo_align_lock                  ;
output                          rx1_pll_lock                         ;
output                          rx1_pma_prbs_error                   ;
output                          tx1_dpll_lock                        ;
output                          tx1_pi_lock                          ;
output                          tx1_pll_lock                         ;
input                           tx1_req                              ;
input     [1:0]                 tx1_pstate                           ;
input     [2:0]                 tx1_rate                             ;
input                           tx1_detrx_req                        ;
output                          tx1_detrx_result                     ;
output                          tx1_ack                              ;
input                           rx1_req                              ;
input     [1:0]                 rx1_pstate                           ;
input     [2:0]                 rx1_rate                             ;
output                          rx1_ack                              ;
input                           tx1_polarity                         ;
input     [1:0]                 tx1_eq_ctrl                          ;
input     [5:0]                 tx1_eq_pre                           ;
input     [5:0]                 tx1_eq_main                          ;
input     [5:0]                 tx1_eq_post                          ;
input     [4:0]                 tx1_eq_preset                        ;
input                           tx1_eq_getlocal_pset_coef            ;
output    [17:0]                tx1_eq_local_tx_pset_coef            ;
output                          tx1_eq_local_tx_coef_valid           ;
output    [5:0]                 tx1_eq_localfs                       ;
output    [5:0]                 tx1_eq_locallf                       ;
input                           rx1_polarity                         ;
input                           rx1_adapt_cont                       ;
input                           rx1_adapt_in_prog                    ;
input                           rx1_adapt_req                        ;
input                           rx1_adapt_invalid_req                ;
input     [1:0]                 rx1_adapt_ctrl                       ;
output                          rx1_adapt_ack                        ;
output    [7:0]                 rx1_adapt_fom                        ;
output    [1:0]                 rx1_txmain_dir                       ;
output    [1:0]                 rx1_txpost_dir                       ;
output    [1:0]                 rx1_txpre_dir                        ;
input                           tx2_usr2clk                          ;
input                           rx2_usr2clk                          ;
output                          tx2_out2clk                          ;
output                          rx2_out2clk                          ;
output                          tx2_outclk                           ;
output                          rx2_outclk                           ;
input                           l2_resetmode_sel                     ;
input                           tx2_reset                            ;
input                           tx2_pma_reset                        ;
input                           tx2_pcs_reset                        ;
input                           tx2_pcsfifo_reset                    ;
input                           tx2_userrdy                          ;
input                           rx2_reset                            ;
input                           rx2_pma_reset                        ;
input                           rx2_pcs_reset                        ;
input                           rx2_pcsfifo_reset                    ;
input                           rx2_userrdy                          ;
output                          tx2_resetdone                        ;
output                          rx2_resetdone                        ;
input     [63:0]                tx2_data                             ;
input     [7:0]                 tx2_ctrl0_data                       ;
input     [7:0]                 tx2_ctrl1_data                       ;
input     [7:0]                 tx2_ctrl2_data                       ;
input                           tx2_data_en                          ;
input     [2:0]                 tx2_header                           ;
input     [6:0]                 tx2_sequence                         ;
input                           tx2_8b10b_en                         ;
input                           rx2_gearboxslip                      ;
input                           rx2_slide                            ;
input                           rx2_8b10b_en                         ;
input                           rx2_gpon_en                          ;
output    [63:0]                rx2_data                             ;
output    [7:0]                 rx2_ctrl0_data                       ;
output    [7:0]                 rx2_ctrl1_data                       ;
output    [7:0]                 rx2_ctrl2_data                       ;
output    [7:0]                 rx2_ctrl3_data                       ;
output    [2:0]                 rx2_header                           ;
output                          rx2_datavalid                        ;
output                          rx2_headervalid                      ;
output                          rx2_startofseq                       ;
output                          tx2_pcsfifo_rd_halffull              ;
output                          tx2_pcsfifo_rd_empty                 ;
output                          tx2_pcsfifo_wr_halffull              ;
output                          tx2_pcsfifo_wr_full                  ;
output                          tx2_piso_pop_halffull                ;
output                          tx2_piso_push_aempty                 ;
output                          tx2_piso_pop_empty                   ;
output                          tx2_piso_push_afull                  ;
output                          tx2_piso_push_halffull               ;
output                          tx2_piso_push_full                   ;
output                          rx2_sipo_pop_halffull                ;
output                          rx2_sipo_pop_aempty                  ;
output                          rx2_sipo_pop_empty                   ;
output                          rx2_sipo_push_afull                  ;
output                          rx2_sipo_push_halffull               ;
output                          rx2_sipo_push_full                   ;
output                          rx2_rmfifo_high                      ;
output                          rx2_rmfifo_low                       ;
output                          rx2_rmfifo_overflow                  ;
output                          rx2_rmfifo_underflow                 ;
output                          rx2_wordrealign                      ;
output                          rx2_wordaligned                      ;
output    [1:0]                 rx2_rmfifo_corcnt                    ;
output                          rx2_sipo_align_lock                  ;
output                          rx2_pll_lock                         ;
output                          rx2_pma_prbs_error                   ;
output                          tx2_dpll_lock                        ;
output                          tx2_pi_lock                          ;
output                          tx2_pll_lock                         ;
input                           tx2_req                              ;
input     [1:0]                 tx2_pstate                           ;
input     [2:0]                 tx2_rate                             ;
input                           tx2_detrx_req                        ;
output                          tx2_detrx_result                     ;
output                          tx2_ack                              ;
input                           rx2_req                              ;
input     [1:0]                 rx2_pstate                           ;
input     [2:0]                 rx2_rate                             ;
output                          rx2_ack                              ;
input                           tx2_polarity                         ;
input     [1:0]                 tx2_eq_ctrl                          ;
input     [5:0]                 tx2_eq_pre                           ;
input     [5:0]                 tx2_eq_main                          ;
input     [5:0]                 tx2_eq_post                          ;
input     [4:0]                 tx2_eq_preset                        ;
input                           tx2_eq_getlocal_pset_coef            ;
output    [17:0]                tx2_eq_local_tx_pset_coef            ;
output                          tx2_eq_local_tx_coef_valid           ;
output    [5:0]                 tx2_eq_localfs                       ;
output    [5:0]                 tx2_eq_locallf                       ;
input                           rx2_polarity                         ;
input                           rx2_adapt_cont                       ;
input                           rx2_adapt_in_prog                    ;
input                           rx2_adapt_req                        ;
input                           rx2_adapt_invalid_req                ;
input     [1:0]                 rx2_adapt_ctrl                       ;
output                          rx2_adapt_ack                        ;
output    [7:0]                 rx2_adapt_fom                        ;
output    [1:0]                 rx2_txmain_dir                       ;
output    [1:0]                 rx2_txpost_dir                       ;
output    [1:0]                 rx2_txpre_dir                        ;
input                           tx3_usr2clk                          ;
input                           rx3_usr2clk                          ;
output                          tx3_out2clk                          ;
output                          rx3_out2clk                          ;
output                          tx3_outclk                           ;
output                          rx3_outclk                           ;
input                           l3_resetmode_sel                     ;
input                           tx3_reset                            ;
input                           tx3_pma_reset                        ;
input                           tx3_pcs_reset                        ;
input                           tx3_pcsfifo_reset                    ;
input                           tx3_userrdy                          ;
input                           rx3_reset                            ;
input                           rx3_pma_reset                        ;
input                           rx3_pcs_reset                        ;
input                           rx3_pcsfifo_reset                    ;
input                           rx3_userrdy                          ;
output                          tx3_resetdone                        ;
output                          rx3_resetdone                        ;
input     [63:0]                tx3_data                             ;
input     [7:0]                 tx3_ctrl0_data                       ;
input     [7:0]                 tx3_ctrl1_data                       ;
input     [7:0]                 tx3_ctrl2_data                       ;
input                           tx3_data_en                          ;
input     [2:0]                 tx3_header                           ;
input     [6:0]                 tx3_sequence                         ;
input                           tx3_8b10b_en                         ;
input                           rx3_gearboxslip                      ;
input                           rx3_slide                            ;
input                           rx3_8b10b_en                         ;
input                           rx3_gpon_en                          ;
output    [63:0]                rx3_data                             ;
output    [7:0]                 rx3_ctrl0_data                       ;
output    [7:0]                 rx3_ctrl1_data                       ;
output    [7:0]                 rx3_ctrl2_data                       ;
output    [7:0]                 rx3_ctrl3_data                       ;
output    [2:0]                 rx3_header                           ;
output                          rx3_datavalid                        ;
output                          rx3_headervalid                      ;
output                          rx3_startofseq                       ;
output                          tx3_pcsfifo_rd_halffull              ;
output                          tx3_pcsfifo_rd_empty                 ;
output                          tx3_pcsfifo_wr_halffull              ;
output                          tx3_pcsfifo_wr_full                  ;
output                          tx3_piso_pop_halffull                ;
output                          tx3_piso_push_aempty                 ;
output                          tx3_piso_pop_empty                   ;
output                          tx3_piso_push_afull                  ;
output                          tx3_piso_push_halffull               ;
output                          tx3_piso_push_full                   ;
output                          rx3_sipo_pop_halffull                ;
output                          rx3_sipo_pop_aempty                  ;
output                          rx3_sipo_pop_empty                   ;
output                          rx3_sipo_push_afull                  ;
output                          rx3_sipo_push_halffull               ;
output                          rx3_sipo_push_full                   ;
output                          rx3_rmfifo_high                      ;
output                          rx3_rmfifo_low                       ;
output                          rx3_rmfifo_overflow                  ;
output                          rx3_rmfifo_underflow                 ;
output                          rx3_wordrealign                      ;
output                          rx3_wordaligned                      ;
output    [1:0]                 rx3_rmfifo_corcnt                    ;
output                          rx3_sipo_align_lock                  ;
output                          rx3_pll_lock                         ;
output                          rx3_pma_prbs_error                   ;
output                          tx3_dpll_lock                        ;
output                          tx3_pi_lock                          ;
output                          tx3_pll_lock                         ;
input                           tx3_req                              ;
input     [1:0]                 tx3_pstate                           ;
input     [2:0]                 tx3_rate                             ;
input                           tx3_detrx_req                        ;
output                          tx3_detrx_result                     ;
output                          tx3_ack                              ;
input                           rx3_req                              ;
input     [1:0]                 rx3_pstate                           ;
input     [2:0]                 rx3_rate                             ;
output                          rx3_ack                              ;
input                           tx3_polarity                         ;
input     [1:0]                 tx3_eq_ctrl                          ;
input     [5:0]                 tx3_eq_pre                           ;
input     [5:0]                 tx3_eq_main                          ;
input     [5:0]                 tx3_eq_post                          ;
input     [4:0]                 tx3_eq_preset                        ;
input                           tx3_eq_getlocal_pset_coef            ;
output    [17:0]                tx3_eq_local_tx_pset_coef            ;
output                          tx3_eq_local_tx_coef_valid           ;
output    [5:0]                 tx3_eq_localfs                       ;
output    [5:0]                 tx3_eq_locallf                       ;
input                           rx3_polarity                         ;
input                           rx3_adapt_cont                       ;
input                           rx3_adapt_in_prog                    ;
input                           rx3_adapt_req                        ;
input                           rx3_adapt_invalid_req                ;
input     [1:0]                 rx3_adapt_ctrl                       ;
output                          rx3_adapt_ack                        ;
output    [7:0]                 rx3_adapt_fom                        ;
output    [1:0]                 rx3_txmain_dir                       ;
output    [1:0]                 rx3_txpost_dir                       ;
output    [1:0]                 rx3_txpre_dir                        ;
input                           phy_reset                            ;
input                           phy_pipe_reset                       ;
output                          cmnresetdone                         ;
output    [1:0]                 refclkout                            ;
output    [7:0]                 groupclkout                          ;
output    [7:0]                 group0sigout                         ;
output    [7:0]                 group1sigout                         ;
output    [7:0]                 group2sigout                         ;
output    [7:0]                 group3sigout                         ;
output                          vdh_ready                            ;
input                           mcu_serdes_rxd                       ;
output                          mcu_serdes_txd                       ;
input                           mcu_phy_rst_sel                      ;
input                           mcu_phy_rst                          ;
input                           mcu_enable                           ;
input                           mcu_core_rst                         ;
output                          mcu_irq_o                            ;
output                          mcu_exchg_info_0                     ;
output                          mcu_sysrstreq                        ;
output                          cmn_pll_lock                         ;
input                           apb4_clk_i                           ;
input                           apb4_preset_i                        ;
input                           apb4_psel_i                          ;
input                           apb4_penable_i                       ;
input                           apb4_pwrite_i                        ;
input     [31:0]                apb4_paddr_i                         ;
input     [31:0]                apb4_pwdata_i                        ;
input     [3:0]                 apb4_pstrb_i                         ;
input     [2:0]                 apb4_pprot_i                         ;
output    [31:0]                apb4_prdata_o                        ;
output                          apb4_pready_o                        ;
output                          apb4_pslverr_o                       ;
input                           scan_rst_n                           ;
input                           scan_mode_n                          ;
input                           scan_clk                             ;
input                           scan_enable_n                        ;
input                           scancompress_mode                    ;
input     [9: 0]                scan_in                              ;
output    [9: 0]                scan_out                             ;
input                           mbist_mode_n                         ;
input                           dft_jtag_tck                         ;
input                           dft_jtag_trst_n                      ;
input                           dft_jtag_tms                         ;
input                           dft_jtag_tdi                         ;
output                          dft_jtag_tdo                         ;
input                           jtag_tck                             ;
input                           jtag_tms                             ;
input                           jtag_tdi                             ;
output                          jtag_tdo                             ;
output                          jtag_tdo_en                          ;
output                          pcie_osc_clk                         ;
input                           mac_phy_blockaligncontrol            ;
input    [2: 0]                 mac_phy_txmargin                     ;
input                           mac_phy_txswing                      ;
input    [3: 0]                 mac_phy_powerdown                    ;
input    [1: 0]                 mac_phy_width                        ;
input    [2: 0]                 mac_phy_pclk_rate                    ;
input    [1: 0]                 mac_phy_rate                         ;
input    [127: 0]               mac_phy_txdata                       ;
input    [15: 0]                mac_phy_txdatak                      ;
input    [3: 0]                 mac_phy_txdatavalid                  ;
input    [7: 0]                 mac_phy_txsyncheader                 ;
input    [3: 0]                 mac_phy_txstartblock                 ;
input    [3: 0]                 mac_phy_txelecidle                   ;
input    [3: 0]                 mac_phy_txcompliance                 ;
input    [3: 0]                 mac_phy_txdetectrx_loopback          ;
input    [3: 0]                 mac_phy_rxpolarity                   ;
input    [71: 0]                mac_phy_txdeemph                     ;
input    [11: 0]                mac_phy_rxpresethint                 ;
input    [23: 0]                mac_phy_fs                           ;
input    [23: 0]                mac_phy_lf                           ;
input    [19: 0]                mac_phy_local_pset_index             ;
input    [3: 0]                 mac_phy_getlocal_pset_coef           ;
input    [3: 0]                 mac_phy_rxeqeval                     ;
input    [3: 0]                 mac_phy_rxeqinprogress               ;
input    [3: 0]                 mac_phy_invalid_req                  ;
input    [3: 0]                 mac_phy_rxstandby                    ;
output                          phy_mac_pclk                         ;
output   [127: 0]               phy_mac_rxdata                       ;
output   [15: 0]                phy_mac_rxdatak                      ;
output   [7: 0]                 phy_mac_rxsyncheader                 ;
output   [3: 0]                 phy_mac_rxstartblock                 ;
output   [3: 0]                 phy_mac_rxelecidle                   ;
output   [3: 0]                 phy_mac_phystatus                    ;
output   [3: 0]                 phy_mac_rxvalid                      ;
output   [11: 0]                phy_mac_rxstatus                     ;
output   [3: 0]                 phy_mac_rxdatavalid                  ;
output   [23: 0]                phy_mac_dirfeedback                  ;
output   [31: 0]                phy_mac_fomfeedback                  ;
output   [71: 0]                phy_mac_local_tx_pset_coef           ;
output   [3: 0]                 phy_mac_local_tx_coef_valid          ;
output   [23: 0]                phy_mac_localfs                      ;
output   [23: 0]                phy_mac_locallf                      ;
input    [1:0]                  pcie_pclk_source_sel                 ;
input    [1:0]                  pcie_pipe_lane_flip                  ;
input    [3:0]                  pcie_pipe_lane_enable                ;
input                           pcie_core_bypass                     ;
input                           pcie_power_on_rst_n                  ;
input                           pcie_pcs_pipe_rst_n                  ;
input                           pcie_pcs_apb_rst_n                   ;
input                           pcie_core_sram_init_done             ;
parameter                       PH1P_LANE_SEL                               =      "DISABLE";
parameter     [3:0]             TX_LANE_ENABLE                              =      4'h0;
parameter     [3:0]             RX_LANE_ENABLE                              =      4'h0;
parameter     [0:0]             CFG_WAKEUP_BYPASS                           =      1'h0;
parameter     [4:0]             CFG_JTAG_CTRL                               =      5'h00;
parameter     [2:0]             CFG_OSC_CTRL                                =      3'b101;
parameter     [5:0]             CFG_CLK_CTRL                                =      6'h32 ;
parameter     [0:0]             PH1P_HXT_MCU_MODE                           =      1'h0;
parameter     [3:0]             CFG_CORE_MCU_CTRL                           =     ( PH1P_HXT_MCU_MODE == 1'b1 ) ? 4'hc : 4'h3;
parameter     [31:0]            MCU_CLK_FREQ                                =      32'h0;
parameter     [31:0]            TOP00_VLD                                   =      32'h01050501;
parameter     [31:0]            TOP01_VLD                                   =      32'h00000000;
parameter     [31:0]            TOP02_VLD                                   =      32'h00000000;
parameter     [31:0]            TOP03_VLD                                   =     ( PH1P_HXT_MCU_MODE == 1'b1 ) ? {28'h0,CFG_CLK_CTRL[3:0]} :32'h00000000;
parameter     [31:0]            ZCAL00_VLD                                  =      32'h00000030;
parameter     [31:0]            ZCAL01_VLD                                  =      32'h00000003;
parameter     [31:0]            ZCAL02_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL03_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL04_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL05_VLD                                  =      32'h00002020;
parameter     [31:0]            ZCAL06_VLD                                  =      32'h00000342;
parameter     [31:0]            CDRDRV_VLD                                  =      32'h00000000;
parameter     [31:0]            REFCLK_CTL_VLD                              =      32'h0000000f;
parameter     [31:0]            JM_CTL_VLD                                  =      32'h00000000;
parameter     [31:0]            REFCLK0_PPM_LOCK_VLD                        =      32'h00000000;
parameter     [31:0]            REFCLK1_PPM_LOCK_VLD                        =      32'h00000000;
parameter     [31:0]            CMN_PLL_CLOCK_VLD                           =      32'h5a2e0300;
parameter     [31:0]            CMN_PLL_FRAC_N00_VLD                        =      32'h00000000;
parameter     [31:0]            CMN_PLL_FRAC_N01_VLD                        =      32'h00000000;
parameter     [31:0]            CMN_PLL_CAL00_VLD                           =      32'h05300486;
parameter     [31:0]            CMN_PLL_TDC_CTL00_VLD                       =      32'h00000000;
parameter     [31:0]            CMN_PLL_TEST00_VLD                          =      32'h00000160;
parameter     [31:0]            ADC_BG_OSC00_VLD                            =      32'h00207020;
parameter     [31:0]            PMA_QUAD_RSV_VLD                            =      32'h00000000;
parameter     [31:0]            PMA_QUAD_RSV_0_VLD                          =      32'h00000000;
parameter     [31:0]            PMA_QUAD_RSV_1_VLD                          =      32'h00000000;
parameter     [31:0]            PMA_QUAD_RSV_2_VLD                          =      32'h00000000;
parameter     [31:0]            PMA_QUAD_RSV_3_VLD                          =      32'h00000000;
parameter     [31:0]            CMN_DEBUG_0_VLD                             =      32'h00000000;
parameter     [31:0]            CMN_ILM_CTL_ADDR_VLD                        =      32'h00000000;
parameter     [31:0]            CMN_ILM_WR_PORT_VLD                         =      32'h00000000;
parameter     [31:0]            CMN_ILM_RD_TRIG_VLD                         =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_CLK_PATH00_VLD                     =      32'h01200043;
parameter     [31:0]            LANE0_TX_DCC_CTRL_VLD                       =      32'h00003425;
parameter     [31:0]            LANE0_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE0_TX_RCV_DET_CTL_VLD                    =      32'h00000001;
parameter     [31:0]            LANE0_TX_PLL_MAIN_CTL_VLD                   =      32'h0007007d;
parameter     [31:0]            LANE0_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE0_TX_FBDIV_CTL00_VLD                    =      32'h06400000;
parameter     [31:0]            LANE0_TX_FBDIV_CTL01_VLD                    =      32'h05080000;
parameter     [31:0]            LANE0_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE0_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE0_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE0_TX_PLL_SSC_RNGE_G3_VLD                =      32'h00000040;
parameter     [31:0]            LANE0_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE0_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE0_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00010102;
parameter     [31:0]            LANE0_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE0_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE0_RX_ATT_CTLE00_VLD                     =      32'h03000701;
parameter     [31:0]            LANE0_RX_ATT_CTLE01_VLD                     =      32'h01000050;
parameter     [31:0]            LANE0_RX_ATT_CTLE02_VLD                     =      32'h05503452;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000011;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h20202020;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h20202020;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h20202020;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h0000050c;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h04000604;
parameter     [31:0]            LANE0_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h05080000;
parameter     [31:0]            LANE0_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE0_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE0_RX_PLL_PATH_WITH_DIV_VLD              =      32'h00000000;
parameter     [31:0]            LANE0_RX_DESER_CDR00_VLD                    =      32'h0361120f;
parameter     [31:0]            LANE0_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_6_VLD                     =      32'h40001007;
parameter     [31:0]            LANE0_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_EQ_G3_CTL_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_RX_DIG_EQ_G3_CTL_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE0_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE0_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE0_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE0_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE0_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE0_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE0_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE0_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE0_TX_PI_CTL_VLD                         =      32'h00008340;
parameter     [31:0]            LANE0_TX_PI_CTL_G3_VLD                      =      32'h00008340;
parameter     [31:0]            LANE0_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE0_TX_DPLL_CTL_1_VLD                     =      32'h00004000;
parameter     [31:0]            LANE0_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE0_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE0_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE0_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE0_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE0_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE0_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE0_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE0_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE0_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE0_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE0_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE0_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE0_RX_SIPO_ALIGN_VLD                     =      32'h0004adf0;
parameter     [31:0]            LANE0_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE0_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE0_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE0_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE0_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE0_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE0_RX_EQ_CTL_0_VLD                       =      32'h00000080;
parameter     [31:0]            LANE0_RX_EQ_CTL_1_VLD                       =      32'h00000080;
parameter     [31:0]            LANE0_RX_EQ_CTL_2_VLD                       =      32'h00000080;
parameter     [31:0]            LANE0_RX_EQ_CTL_3_VLD                       =      32'h00000080;
parameter     [31:0]            LANE0_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE0_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE0_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE0_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE0_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_CLK_PATH00_VLD                     =      32'h01200043;
parameter     [31:0]            LANE1_TX_DCC_CTRL_VLD                       =      32'h00003425;
parameter     [31:0]            LANE1_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE1_TX_RCV_DET_CTL_VLD                    =      32'h00000001;
parameter     [31:0]            LANE1_TX_PLL_MAIN_CTL_VLD                   =      32'h0007007d;
parameter     [31:0]            LANE1_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE1_TX_FBDIV_CTL00_VLD                    =      32'h06400000;
parameter     [31:0]            LANE1_TX_FBDIV_CTL01_VLD                    =      32'h05080000;
parameter     [31:0]            LANE1_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE1_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE1_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE1_TX_PLL_SSC_RNGE_G3_VLD                =      32'h00000040;
parameter     [31:0]            LANE1_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE1_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE1_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00010102;
parameter     [31:0]            LANE1_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE1_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE1_RX_ATT_CTLE00_VLD                     =      32'h03000701;
parameter     [31:0]            LANE1_RX_ATT_CTLE01_VLD                     =      32'h01000050;
parameter     [31:0]            LANE1_RX_ATT_CTLE02_VLD                     =      32'h05503452;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000011;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h20202020;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h20202020;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h20202020;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h0000050c;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h04000604;
parameter     [31:0]            LANE1_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h05080000;
parameter     [31:0]            LANE1_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE1_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE1_RX_PLL_PATH_WITH_DIV_VLD              =      32'h00000000;
parameter     [31:0]            LANE1_RX_DESER_CDR00_VLD                    =      32'h0361120f;
parameter     [31:0]            LANE1_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_6_VLD                     =      32'h40001007;
parameter     [31:0]            LANE1_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_EQ_G3_CTL_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_RX_DIG_EQ_G3_CTL_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE1_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE1_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE1_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE1_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE1_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE1_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE1_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE1_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE1_TX_PI_CTL_VLD                         =      32'h00008340;
parameter     [31:0]            LANE1_TX_PI_CTL_G3_VLD                      =      32'h00008340;
parameter     [31:0]            LANE1_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE1_TX_DPLL_CTL_1_VLD                     =      32'h00004000;
parameter     [31:0]            LANE1_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE1_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE1_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE1_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE1_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE1_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE1_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE1_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE1_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE1_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE1_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE1_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE1_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE1_RX_SIPO_ALIGN_VLD                     =      32'h0004adf0;
parameter     [31:0]            LANE1_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE1_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE1_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE1_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE1_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE1_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE1_RX_EQ_CTL_0_VLD                       =      32'h00000080;
parameter     [31:0]            LANE1_RX_EQ_CTL_1_VLD                       =      32'h00000080;
parameter     [31:0]            LANE1_RX_EQ_CTL_2_VLD                       =      32'h00000080;
parameter     [31:0]            LANE1_RX_EQ_CTL_3_VLD                       =      32'h00000080;
parameter     [31:0]            LANE1_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE1_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE1_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE1_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE1_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_CLK_PATH00_VLD                     =      32'h01200043;
parameter     [31:0]            LANE2_TX_DCC_CTRL_VLD                       =      32'h00003425;
parameter     [31:0]            LANE2_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE2_TX_RCV_DET_CTL_VLD                    =      32'h00000001;
parameter     [31:0]            LANE2_TX_PLL_MAIN_CTL_VLD                   =      32'h0007007d;
parameter     [31:0]            LANE2_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE2_TX_FBDIV_CTL00_VLD                    =      32'h06400000;
parameter     [31:0]            LANE2_TX_FBDIV_CTL01_VLD                    =      32'h05080000;
parameter     [31:0]            LANE2_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE2_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE2_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE2_TX_PLL_SSC_RNGE_G3_VLD                =      32'h00000040;
parameter     [31:0]            LANE2_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE2_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE2_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00010102;
parameter     [31:0]            LANE2_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE2_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE2_RX_ATT_CTLE00_VLD                     =      32'h03000701;
parameter     [31:0]            LANE2_RX_ATT_CTLE01_VLD                     =      32'h01000050;
parameter     [31:0]            LANE2_RX_ATT_CTLE02_VLD                     =      32'h05503452;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000011;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h20202020;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h20202020;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h20202020;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h0000050c;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h04000604;
parameter     [31:0]            LANE2_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h05080000;
parameter     [31:0]            LANE2_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE2_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE2_RX_PLL_PATH_WITH_DIV_VLD              =      32'h00000000;
parameter     [31:0]            LANE2_RX_DESER_CDR00_VLD                    =      32'h0361120f;
parameter     [31:0]            LANE2_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_6_VLD                     =      32'h40001007;
parameter     [31:0]            LANE2_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_EQ_G3_CTL_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_RX_DIG_EQ_G3_CTL_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE2_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE2_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE2_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE2_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE2_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE2_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE2_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE2_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE2_TX_PI_CTL_VLD                         =      32'h00008340;
parameter     [31:0]            LANE2_TX_PI_CTL_G3_VLD                      =      32'h00008340;
parameter     [31:0]            LANE2_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE2_TX_DPLL_CTL_1_VLD                     =      32'h00004000;
parameter     [31:0]            LANE2_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE2_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE2_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE2_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE2_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE2_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE2_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE2_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE2_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE2_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE2_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE2_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE2_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE2_RX_SIPO_ALIGN_VLD                     =      32'h0004adf0;
parameter     [31:0]            LANE2_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE2_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE2_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE2_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE2_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE2_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE2_RX_EQ_CTL_0_VLD                       =      32'h00000080;
parameter     [31:0]            LANE2_RX_EQ_CTL_1_VLD                       =      32'h00000080;
parameter     [31:0]            LANE2_RX_EQ_CTL_2_VLD                       =      32'h00000080;
parameter     [31:0]            LANE2_RX_EQ_CTL_3_VLD                       =      32'h00000080;
parameter     [31:0]            LANE2_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE2_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE2_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE2_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE2_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE00_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE01_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE02_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE03_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_FFE04_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_CLK_PATH00_VLD                     =      32'h01200043;
parameter     [31:0]            LANE3_TX_DCC_CTRL_VLD                       =      32'h00003425;
parameter     [31:0]            LANE3_TX_DRV_CTRL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE3_TX_RCV_DET_CTL_VLD                    =      32'h00000001;
parameter     [31:0]            LANE3_TX_PLL_MAIN_CTL_VLD                   =      32'h0007007d;
parameter     [31:0]            LANE3_TX_PLL_LOOP_CTL_VLD                   =      32'h07036a7b;
parameter     [31:0]            LANE3_TX_FBDIV_CTL00_VLD                    =      32'h06400000;
parameter     [31:0]            LANE3_TX_FBDIV_CTL01_VLD                    =      32'h05080000;
parameter     [31:0]            LANE3_TX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_TX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE3_TX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE3_TX_PLL_TEST_CTL_VLD                   =      32'h00000040;
parameter     [31:0]            LANE3_TX_PLL_SSC_RNGE_G3_VLD                =      32'h00000040;
parameter     [31:0]            LANE3_TX_GLBL_MISC00_VLD                    =      32'h00000123;
parameter     [31:0]            LANE3_TX_GLBL_MISC01_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_RESERVE00_VLD                      =      32'h00000000;
parameter     [31:0]            LANE3_RX_GLOBAL_MISC_RESERVED00_VLD         =      32'h00010102;
parameter     [31:0]            LANE3_RX_LOS_ACJTAG00_VLD                   =      32'h00000000;
parameter     [31:0]            LANE3_RX_AFE_TERM_ATT00_VLD                 =      32'h08070000;
parameter     [31:0]            LANE3_RX_ATT_CTLE00_VLD                     =      32'h03000701;
parameter     [31:0]            LANE3_RX_ATT_CTLE01_VLD                     =      32'h01000050;
parameter     [31:0]            LANE3_RX_ATT_CTLE02_VLD                     =      32'h05503452;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC00_VLD         =      32'h00000011;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC01_VLD         =      32'h20202020;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC02_VLD         =      32'h20202020;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC03_VLD         =      32'h20202020;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC04_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC05_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC06_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_DFE_SUMMER_VDAC_IDAC07_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL00_VLD            =      32'h1b130300;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL01_VLD            =      32'h34030332;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL02_VLD            =      32'h0000050c;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL03_VLD            =      32'h04000604;
parameter     [31:0]            LANE3_RX_CLK_PATH_WITH_PLL04_VLD            =      32'h05080000;
parameter     [31:0]            LANE3_RX_PLL_FRACN_CTL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_RX_PLL_SSC_FREQ_DIV_VLD               =      32'h00000000;
parameter     [31:0]            LANE3_RX_PLL_SSC_RNGE_VLD                   =      32'h00000000;
parameter     [31:0]            LANE3_RX_PLL_PATH_WITH_DIV_VLD              =      32'h00000000;
parameter     [31:0]            LANE3_RX_DESER_CDR00_VLD                    =      32'h0361120f;
parameter     [31:0]            LANE3_RX_DESER_CDR02_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DESER_CDR03_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DESER_CDR04_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_1_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_4_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_5_VLD                     =      32'h18000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_6_VLD                     =      32'h40001007;
parameter     [31:0]            LANE3_RX_DIG_CALI_7_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_8_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_9_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_10_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_11_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_12_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_13_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_CALI_14_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_EQ_G3_CTL_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_RX_DIG_EQ_G3_CTL_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_TX_CLK_CTRL_0_VLD                     =      32'h00000400;
parameter     [31:0]            LANE3_TX_RST_CTRL_0_VLD                     =      32'h0000000f;
parameter     [31:0]            LANE3_LANE_PROTOCOL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_ENC_EN_VLD                         =      32'h00000000;
parameter     [31:0]            LANE3_TX_DATA_CTRL_0_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE3_TX_LBERT_ERR_TRIG_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_PATTERN_0_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_PATTERN_1_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_TX_LBERT_PATTERN_2_VLD                =      32'h00000000;
parameter     [31:0]            LANE3_TX_C16_PISO_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_TX_C16_DATA_CTRL_0_VLD                =      32'h14000130;
parameter     [31:0]            LANE3_TX_C16_LBERT_CTRL_VLD                 =      32'h00000001;
parameter     [31:0]            LANE3_TX_C16_LBERT_PATTERN_VLD              =      32'h00000000;
parameter     [31:0]            LANE3_TX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE3_TX_PI_CTL_VLD                         =      32'h00008340;
parameter     [31:0]            LANE3_TX_PI_CTL_G3_VLD                      =      32'h00008340;
parameter     [31:0]            LANE3_TX_DPLL_CTL_VLD                       =      32'h00004000;
parameter     [31:0]            LANE3_TX_DPLL_CTL_1_VLD                     =      32'h00004000;
parameter     [31:0]            LANE3_TX_PCSFIFO_STS_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_TX_PWR_CTL_VLD                        =      32'h10280900;
parameter     [31:0]            LANE3_TX_PCIE_EQ_G1_VLD                     =      32'h00003f00;
parameter     [31:0]            LANE3_TX_PCIE_EQ_G2_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_TX_PCIE_EQ_G3_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_CLK_CTRL_0_VLD                     =      32'h01800000;
parameter     [31:0]            LANE3_RX_RST_CTRL_0_VLD                     =      32'h0000003f;
parameter     [31:0]            LANE3_RX_DATA_WIDTH_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_RX_ENC_EN_VLD                         =      32'h0800fe00;
parameter     [31:0]            LANE3_RX_DATA_CTRL_0_VLD                    =      32'h00000380;
parameter     [31:0]            LANE3_RX_DATA_CTRL_1_VLD                    =      32'h00000001;
parameter     [31:0]            LANE3_RX_GEARBOX_CTL_VLD                    =      32'h00000030;
parameter     [31:0]            LANE3_RX_ALIGN_EN_CTRL_VLD                  =      32'h00000000;
parameter     [31:0]            LANE3_RX_ALIGN_COMMA_MASK_VLD               =      32'h000003ff;
parameter     [31:0]            LANE3_RX_ALIGN_COMMA_VLD                    =      32'h00fa0305;
parameter     [31:0]            LANE3_RX_SKIP_CTRL_VLD                      =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP1_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP1_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP2_PATTERN1_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP2_PATTERN2_VLD                 =      32'h00000000;
parameter     [31:0]            LANE3_RX_SKIP_MARK_VLD                      =      32'h00001808;
parameter     [31:0]            LANE3_RX_SIPO_ALIGN_VLD                     =      32'h0004adf0;
parameter     [31:0]            LANE3_RX_SIPO_STS_VLD                       =      32'h00000000;
parameter     [31:0]            LANE3_RX_LBERT_CTRL_VLD                     =      32'h00000001;
parameter     [31:0]            LANE3_RX_LBERT_ERRCNT_LATCH_VLD             =      32'h00000000;
parameter     [31:0]            LANE3_RX_C16_LBERT_CTRL_0_VLD               =      32'h00000001;
parameter     [31:0]            LANE3_RX_C16_LBERT_ERRCNT_LATCH_VLD         =      32'h00000000;
parameter     [31:0]            LANE3_RX_PWR_CTL_VLD                        =      32'h00280080;
parameter     [31:0]            LANE3_RX_EQ_CTL_0_VLD                       =      32'h00000080;
parameter     [31:0]            LANE3_RX_EQ_CTL_1_VLD                       =      32'h00000080;
parameter     [31:0]            LANE3_RX_EQ_CTL_2_VLD                       =      32'h00000080;
parameter     [31:0]            LANE3_RX_EQ_CTL_3_VLD                       =      32'h00000080;
parameter     [31:0]            LANE3_MISC_CTL_0_VLD                        =      32'h00001c6c;
parameter     [31:0]            LANE3_MISC_CTL_1_VLD                        =      32'h00000000;
parameter     [31:0]            LANE3_PCS_TX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_PCS_TX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_PCS_RX_CTL_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_PCS_RX_STS_INT_VLD                    =      32'h00000000;
parameter     [31:0]            LANE3_DEBUG_IO_CTRL_VLD                     =      32'h00000000;
parameter     [31:0]            LANE3_DEBUG_CLK_CTRL_VLD                    =      32'h00000000;
parameter     [63:0]            LANE0_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE1_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE2_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE3_TX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE0_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE1_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE2_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [63:0]            LANE3_RX_SPEEDCHANGE_FBKDIV                 =      64'h0;
parameter     [0:0]             PIPE_PCLK_SOURCE_SEL                        =      1'h0;
parameter     [3:0]             PIPE_LANE_MODE_SEL                          =      4'h0;
parameter     [0:0]             PIPE_LANE0_TXOUT2CLK_PCLKSEL                =      1'h0;
parameter     [0:0]             PIPE_LANE1_TXOUT2CLK_PCLKSEL                =      1'h0;
parameter     [0:0]             PIPE_LANE2_TXOUT2CLK_PCLKSEL                =      1'h0;
parameter     [0:0]             PIPE_LANE3_TXOUT2CLK_PCLKSEL                =      1'h0;
endmodule
module PH1P_PHY_DDRPHY_BYTE (
    ////////////////////////////////////
    // PIB2BYTE
    ////////////////////////////////////
    // Clk & Rst_n
    lclk                ,
    ioclk               , 
    usr_clk             , 
    ac_fifo_rst_n       , 
    dx_fifo_rst_n       , 
    ac_phy_rst_n        , 
    dx_phy_rst_n        , 
    dqs_rst_n           , 
    ctl_rst_n           , 
 
    // IO_Ctl
    ctl_te              , 
    ctl_pdr             , 
    ctl_oe              , 
    
    // FIFO_Ctl
    ac_rfifo_en         , 
    ac_rfifo_mode       , 
    dx_rfifo_en         , 
    dx_rfifo_mode       , 
    dx_rfifo_empty      , 
    
    // Data Port
    ctl_wdata           , 
    ctl_rdata           , 
    ctl_rdata_vld       , 
    ctl_rdqs_gate       , 
    
    // APB
    apb_pclk            , 
    apb_prst_n          , 
    apb_psel            , 
    apb_penable         , 
    apb_pwrite          , 
    apb_paddr           , 
    apb_pwdata          , 

    apb_prdy            , 
    apb_prdata          , 
    apb_pslverr         , 
    
    // Delayline Config Bus
    dly_psel            , 
    dly_pdata           , 
    dly_paddr           , 
    dly_gate            , 
    
    // MISC - MDL
    cal_clk_en          , 
    cal_mode            , 
    cal_en              , 
    cal_out             , 
    cal_en_out          , 
    
    // MISC - DCC
    dcc_clrsr           , 
    dcc_start           , 
    dcc_done            , 
    
    // MISC - DL_BIST
    dl_osc_en           , 
    dl_test_mode        , 
    dl_osc_wlsel        , 
    dl_osc_wdqsel       , 
    dl_osc_div          , 
    dl_osc_out          , 
   
    // MISC - Debug
    o_debug             , 
    
    // MISC - Loopback
    lb_mode             , 
    lb_en               , 
    lb_sel              , 
    lb_ck_sel           , 
   
    // MISC
    dqs_pupd_en         , 
    dqs_gate_status     , 
    wrlvl_mode          , 
    dqsn_cnt            , 

    ////////////////////////////////////
    // BYTE2PAD
    ////////////////////////////////////
    // Clk & Rst_n 
    phy_phyclk          ,
    phy_ctlclk_ac       ,
    phy_ddrclk_ac       ,
    phy_ctlclk_wdq      , 
    phy_ctlclk_dqs      , 
    phy_ddrclk_dqs      , 
    phy_ddrclk_wdq      , 

    phy_ac_wr_rst_n     , 
    phy_dx_wr_rst_n     , 
    phy_ac_rd_rst_n     , 
    phy_dx_rd_rst_n     , 

    // IO_Ctl
    phy_pdr_md          , 
    phy_te_md           , 
    phy_oe_md           , 

    phy_oe_dq           , 
    phy_oe_dqsp         , 
    phy_oe_dqsn         , 
    phy_pdr_dq          , 
    phy_pdr_dqsp        , 
    phy_pdr_dqsn        , 
    phy_te_dq           , 
    phy_te_dqsp         , 
    phy_te_dqsn         , 

    // Delayline Ctl
    phy_wr_bdl_dly_dq   , 
    phy_wr_bdl_dly_dqsp , 
    phy_wr_bdl_dly_dqsn , 
    phy_wr_bdl_dly_se   , 
    phy_rd_bdl_dly_dq   , 
    phy_rd_bdl_dly_dqsp , 
    phy_rd_bdl_dly_dqsn , 
    phy_rd_bdl_dly_se   , 

    phy_wr_bdl_byp_dq   , 
    phy_wr_bdl_byp_dqsp , 
    phy_wr_bdl_byp_dqsn , 
    phy_wr_bdl_byp_se   , 
    phy_rd_bdl_byp_dq   , 
    phy_rd_bdl_byp_dqsp , 
    phy_rd_bdl_byp_dqsn , 
    phy_rd_bdl_byp_se   , 

    // Data Port
    phy_wdata           , 
    phy_rdata           , 

    // RDQS
    phy_rdqs_p          , 
    phy_rdqs_n          , 
    phy_rdqs_o          , 
    phy_rdqs_gate       , 

    // MISC - DL_BIST
    phy_osc_en          , 
    phy_test_mode       , 

    // MISC - Loopback
    phy_lb_en           , 
    phy_lb_ck_sel       ,
    
    ////////////////////////////////////
    // MISC
    ////////////////////////////////////
    // DFT
    scan_mode           ,
    scan_clk            ,                               
    scan_rst_n          ,                               
    scan_enable         ,                               
    scancompress_mode   ,                               
    scan_in             ,                               
    scan_out            ,

    // Normal Mode Tie 0 
    dfi_io_pd           ,
    dcc_up_en           ,  
    dfi_dcc_vt_update   ,
    apb_sync_path_en    , 
    qs_gate             ,
    dly_ranksel         , 
    aa_code_invert      , 
    aa_en               ,

    // Normal Mode Tie 1
    ctl_phy_clk_gate    , 
    ctl_clk_gate        , 
    ctl_rd_clk_gate   

);
input  [ 3  : 0 ]  lclk                ; 
input  [ 3  : 0 ]  ioclk               ; 
input              usr_clk             ; 
input              ac_fifo_rst_n       ; 
input              dx_fifo_rst_n       ; 
input              ac_phy_rst_n        ; 
input              dx_phy_rst_n        ; 
input              dqs_rst_n           ; 
input              ctl_rst_n           ; 
input  [ 7  : 0 ]  ctl_te              ;
input  [ 7  : 0 ]  ctl_pdr             ;
input  [ 7  : 0 ]  ctl_oe              ;
input              ac_rfifo_en         ;
input              ac_rfifo_mode       ;
input              dx_rfifo_en         ;
input              dx_rfifo_mode       ;
output             dx_rfifo_empty      ;
input  [103 : 0 ]  ctl_wdata           ;
output [103 : 0 ]  ctl_rdata           ;
output             ctl_rdata_vld       ;
input  [ 7  : 0 ]  ctl_rdqs_gate       ;
input              apb_pclk            ; 
input              apb_prst_n          ; 
input              apb_psel            ;
input              apb_penable         ;
input              apb_pwrite          ;
input  [ 9  : 0 ]  apb_paddr           ;
input  [ 31 : 0 ]  apb_pwdata          ;
output             apb_prdy            ;
output [ 31 : 0 ]  apb_prdata          ;
output             apb_pslverr         ;
input              dly_psel            ;
input  [ 8  : 0 ]  dly_pdata           ;
input  [ 5  : 0 ]  dly_paddr           ;
input              dly_gate            ;
input  [ 6  : 0 ]  cal_clk_en          ;
input              cal_mode            ;
input  [ 6  : 0 ]  cal_en              ;
output [ 6  : 0 ]  cal_out             ;
output [ 6  : 0 ]  cal_en_out          ;
input              dcc_clrsr           ;
input              dcc_start           ;
output             dcc_done            ;
input              dl_test_mode        ;
input              dl_osc_en           ;
input  [ 1  : 0 ]  dl_osc_wlsel        ;
input  [ 1  : 0 ]  dl_osc_wdqsel       ;
input  [ 3  : 0 ]  dl_osc_div          ;
output             dl_osc_out          ;
output [ 15 : 0 ]  o_debug             ;
input              lb_mode             ;
input  [ 7  : 0 ]  lb_en               ;
input  [ 1  : 0 ]  lb_sel              ;
input  [ 1  : 0 ]  lb_ck_sel           ;
input              dqs_pupd_en         ;
output [ 1  : 0 ]  dqs_gate_status     ;
input              wrlvl_mode          ;
output [ 1  : 0 ]  dqsn_cnt            ;
output             phy_phyclk          ; 
output             phy_ctlclk_ac       ; 
output             phy_ddrclk_ac       ; 
output             phy_ctlclk_wdq      ; 
output             phy_ctlclk_dqs      ; 
output             phy_ddrclk_dqs      ; 
output             phy_ddrclk_wdq      ; 
output             phy_ac_wr_rst_n     ; 
output             phy_dx_wr_rst_n     ; 
output             phy_ac_rd_rst_n     ; 
output             phy_dx_rd_rst_n     ; 
output [ 23 : 0 ]  phy_pdr_md          ; 
output [ 23 : 0 ]  phy_te_md           ; 
output [ 23 : 0 ]  phy_oe_md           ; 
output             phy_oe_dq           ; 
output             phy_oe_dqsp         ; 
output             phy_oe_dqsn         ; 
output             phy_pdr_dq          ; 
output             phy_pdr_dqsp        ; 
output             phy_pdr_dqsn        ; 
output             phy_te_dq           ; 
output             phy_te_dqsp         ; 
output             phy_te_dqsn         ; 
output [ 59 : 0 ]  phy_wr_bdl_dly_dq   ; 
output [ 5  : 0 ]  phy_wr_bdl_dly_dqsp ; 
output [ 5  : 0 ]  phy_wr_bdl_dly_dqsn ; 
output [ 5  : 0 ]  phy_wr_bdl_dly_se   ; 
output [ 59 : 0 ]  phy_rd_bdl_dly_dq   ; 
output [ 5  : 0 ]  phy_rd_bdl_dly_dqsp ; 
output [ 5  : 0 ]  phy_rd_bdl_dly_dqsn ; 
output [ 5  : 0 ]  phy_rd_bdl_dly_se   ; 
output [ 9  : 0 ]  phy_wr_bdl_byp_dq   ; 
output             phy_wr_bdl_byp_dqsp ; 
output             phy_wr_bdl_byp_dqsn ; 
output             phy_wr_bdl_byp_se   ; 
output [ 9  : 0 ]  phy_rd_bdl_byp_dq   ; 
output             phy_rd_bdl_byp_dqsp ; 
output             phy_rd_bdl_byp_dqsn ; 
output             phy_rd_bdl_byp_se   ; 
output [103 : 0 ]  phy_wdata           ; 
input  [103 : 0 ]  phy_rdata           ; 
input              phy_rdqs_p          ; 
input              phy_rdqs_n          ; 
output             phy_rdqs_o          ; 
output             phy_rdqs_gate       ; 
output             phy_osc_en          ; 
output             phy_test_mode       ; 
output             phy_lb_en           ; 
output [ 1  : 0 ]  phy_lb_ck_sel       ; 
input              scan_mode           ;
input              scan_clk            ;                               
input              scan_rst_n          ;                               
input              scan_enable         ;                               
input              scancompress_mode   ;                               
input  [ 2  : 0 ]  scan_in             ;                               
output [ 2  : 0 ]  scan_out            ;
input              dfi_io_pd           ;
input              dcc_up_en           ;  
input              dfi_dcc_vt_update   ;
input              dly_ranksel         ; 
input              qs_gate             ;
input              apb_sync_path_en    ; 
input              aa_code_invert      ; 
input              aa_en               ;
input              ctl_clk_gate        ; 
input              ctl_rd_clk_gate     ; 
input              ctl_phy_clk_gate    ; 
parameter        BYTE_TYPE           = "DX"         ; // "DX"     , "AC"
parameter        DDR_CLK_SWI_SEL     = "IOCLK1"     ; // "IOCLK0" , "IOCLK1", "IOCLK2", "IOCLK3", "GND"
parameter        CTL_CLK_SWI_SEL     = "IOCLK0"     ; // "LCLK0"  , "LCLK1" , "LCLK2" , "LCLK3" , "IOCLK0", "IOCLK1", "IOCLK2", "IOCLK3", "GND"
parameter        DLY_TEST_EN         = "DISABLE"    ; // "DISABLE", "ENABLE"
parameter        DLY_CAL_MODE        = "FULL"       ; // "FULL"   , "HALF"
parameter        WL_GATE_DIS_EN      = "ENABLE"     ; // "DISABLE", "ENABLE"
parameter        DQS_GATE_TYPE       = "DQS"        ; // "DQS"    , "IO"
parameter        DCC_EN              = "DISABLE"    ; // "DISABLE", "ENABLE"
parameter        DCC_CLK_SEL         = "CLK_IO"     ; // "CLK_IO" , "CLK_WL"
endmodule
module PH1P_PHY_DDRPHY_PAD (
   // inout
   pad         ,
   
   // clk & rst_n 
   ctl_phy_clk , 
   ctl_clk_dqs ,
   ctl_clk_wdq , 
   ctl_clk_ac  , 
   ddr_clk_dqs , 
   ddr_clk_wdq , 
   ddr_clk_ac  , 
  
   dx_wr_rst_n , 
   ac_wr_rst_n ,
   dx_rd_rst_n ,
   ac_rd_rst_n , 
   
   // rdqs
   rdqs        ,
   rdqs_gate   ,
  
  // data_path
   diq         , 
   doq         ,
   
   // io ctrl
   pdr_md     ,
   ts_md      ,  
   te_md      , 
   pdr_dq     , 
   pdr_dqs    ,
   pdr_dqsn   ,
   te_dq      ,  
   te_dqs     , 
   te_dqsn    ,
   ts_dq      , 
   ts_dqs     ,
   ts_dqsn    ,
  
   // delayline
   out_bdl_dly,
   out_bdl_byp,
   in_bdl_dly , 
   in_bdl_byp ,
   
   // misc 
   lb_enb     ,
   qs_n_div   , 
   indd       ,
   indqs        

);
inout            pad              ; 
input            ctl_clk_ac       ; 
input            ctl_clk_wdq      ; 
input            ctl_clk_dqs      ; 
input            ctl_phy_clk      ; 
input            ddr_clk_ac       ; 
input            ddr_clk_wdq      ; 
input            ddr_clk_dqs      ; 
input            ac_wr_rst_n      ; 
input            dx_wr_rst_n      ; 
input            ac_rd_rst_n      ; 
input            dx_rd_rst_n      ; 
input            rdqs             ; 
input            rdqs_gate        ; 
output [7:0]     diq              ; 
input  [7:0]     doq              ; 
input  [1:0]     pdr_md           ; 
input  [1:0]     te_md            ; 
input  [1:0]     ts_md            ; 
input            pdr_dq           ; 
input            pdr_dqs          ; 
input            pdr_dqsn         ; 
input            ts_dq            ; 
input            ts_dqs           ; 
input            ts_dqsn          ; 
input            te_dq            ; 
input            te_dqs           ; 
input            te_dqsn          ; 
input            in_bdl_byp       ; 
input  [5:0]     in_bdl_dly       ; 
input            out_bdl_byp      ; 
input  [5:0]     out_bdl_dly      ; 
input            lb_enb           ;
output           indd             ; 
output           indqs            ; 
output           qs_n_div         ; 
parameter DDR_SIGNAL_TYPE   = "AC"          ; // "DQ", "AC", "DQSP", "DQSN", "NONE"
parameter OCLK_SEL          = "CLK_IO"      ; // "CLK_IO", "CLK_WL", "CLK_WDQ"
parameter DATA_WIDTH        = "X8"          ; // "X4", "X8"
parameter DDR_RST_TYPE      = "ASYNC"       ; // "SYNC", "ASYNC"
parameter DATA_OUT_SYNC     = "DISABLE"     ; // "ENABLE", "DISABLE"
parameter DISABLE_GSR       = "DISABLE"     ; // "DISABLE", "ENABLE"
parameter IOTYPE            = "SSTL15"      ; // "SSTL18_I", SSTL15", "SSTL135", "SSTL12", "DIFF_SSTL18_I", "DIFF_SSTL15", "DIFF_SSTL135", "DIFF_SSTL12", "POD12", "DIFF_POD12", "SSTL15_PZQ", "SSTL12_PZQ", "DIFF_SSTL15_PZQ", "DIFF_SSTL12_PZQ", "POD12_PZQ", "DIFF_POD_PZQ", "LVCMOS15", "LVCMOS12"
parameter MODE              = "NONE"        ; // "NONE", "OUT", "BI", "IN"
parameter ODT_SRC_SEL       = "SRAM"        ; // "DQ", "AC", "DQS", "SRAM"
parameter DRV               = "40"          ; // "34", "40", "48", "60", "75", "80"
parameter ODT               = "120"         ; // "40", "48", "60", "75","80", "120"
endmodule
module PH1P_PHY_DDRPHY_PAD_V2 (
   // inout 
   pad        ,
   
   // clk & rst_n
   ctl_phy_clk, 
   ctl_clk_dqs,
   ctl_clk_wdq,
   ctl_clk_ac , 
   ddr_clk_dqs, 
   ddr_clk_wdq, 
   ddr_clk_ac, 
  
   dx_rd_rst_n, 
   ac_rd_rst_n, 
   dx_wr_rst_n,
   ac_wr_rst_n,
 
   // rdqs
   rdqs_gate  , 
   rdqs       ,
  
   // data path
   diq        , 
   doq        ,

   // io ctrl
   pdr_md     ,
   te_md      ,
   ts_md      , 
   pdr_dq     ,  
   pdr_dqs    ,
   pdr_dqsn   ,
   te_dq      ,   
   te_dqs     , 
   te_dqsn    ,
   ts_dq      , 
   ts_dqs     , 
   ts_dqsn    ,
  
   // delayline
   out_bdl_dly,
   out_bdl_byp,
   in_bdl_dly ,
   in_bdl_byp ,
   
   // dlbist
   dl_out     ,
   dl_in      ,
   
   // misc
   lb_enb     ,
   qs_n_div   ,
   indd       , 
   indqs 
);
inout            pad              ; 
input            ctl_clk_ac       ; 
input            ctl_clk_wdq      ; 
input            ctl_clk_dqs      ; 
input            ctl_phy_clk      ; 
input            ddr_clk_ac       ; 
input            ddr_clk_wdq      ; 
input            ddr_clk_dqs      ; 
input            ac_rd_rst_n      ; 
input            dx_rd_rst_n      ; 
input            ac_wr_rst_n      ; 
input            dx_wr_rst_n      ; 
input            rdqs             ; 
input            rdqs_gate        ; 
input  [1:0]     pdr_md           ; 
input  [1:0]     te_md            ; 
input  [1:0]     ts_md            ; 
input            pdr_dq           ; 
input            pdr_dqs          ; 
input            pdr_dqsn         ; 
input            ts_dq            ; 
input            ts_dqs           ; 
input            ts_dqsn          ; 
input            te_dq            ; 
input            te_dqs           ; 
input            te_dqsn          ; 
input  [7:0]     doq              ; 
output [7:0]     diq              ; 
input            in_bdl_byp       ; 
input  [5:0]     in_bdl_dly       ; 
input            out_bdl_byp      ; 
input  [5:0]     out_bdl_dly      ; 
input            dl_in            ; 
output           dl_out           ; 
input            lb_enb           ;
output           indd             ;
output           indqs            ; 
output           qs_n_div         ; 
parameter DDR_SIGNAL_TYPE   = "AC"          ; // "DQ", "AC", "DQSP", "DQSN", "NONE"
parameter OCLK_SEL          = "CLK_IO"      ; // "CLK_IO", "CLK_WL", "CLK_WDQ"
parameter DATA_WIDTH        = "X8"          ; // "X4", "X8"
parameter DDR_RST_TYPE      = "ASYNC"       ; // "SYNC", "ASYNC"
parameter DATA_OUT_SYNC     = "DISABLE"     ; // "ENABLE", "DISABLE"
parameter DISABLE_GSR       = "DISABLE"     ; // "DISABLE", "ENABLE"
parameter IOTYPE            = "SSTL15"      ; // "SSTL18_I", SSTL15", "SSTL135", "SSTL12", "DIFF_SSTL18_I", "DIFF_SSTL15", "DIFF_SSTL135", "DIFF_SSTL12", "POD12", "DIFF_POD12", "SSTL15_PZQ", "SSTL12_PZQ", "DIFF_SSTL15_PZQ", "DIFF_SSTL12_PZQ", "POD12_PZQ", "DIFF_POD_PZQ", "LVCMOS15", "LVCMOS12"
parameter MODE              = "NONE"        ; // "NONE", "OUT", "BI", "IN", "VREF"
parameter ODT_SRC_SEL       = "SRAM"        ; // "DQ", "AC", "DQS", "SRAM"
parameter DRV               = "40"          ; // "34", "40", "48", "60", "75", "80", "120"
parameter ODT               = "120"         ; // "0" , "40", "48", "60", "75", "80", "120"
endmodule
module PH1P_PHY_DDRPHY_PAD_V3 (
   // inout
   pad         ,
   
   // clk & rst_n 
   ctl_phy_clk , 
   ctl_clk_dqs ,
   ctl_clk_wdq , 
   ctl_clk_ac  , 
   ddr_clk_dqs , 
   ddr_clk_wdq , 
   ddr_clk_ac  , 
  
   dx_wr_rst_n , 
   ac_wr_rst_n ,
   dx_rd_rst_n ,
   ac_rd_rst_n , 
   
   // rdqs
   rdqs        ,
   rdqs_gate   ,
  
  // data_path
   diq         , 
   doq         ,
   
   // io ctrl
   pdr_md     ,
   ts_md      ,  
   te_md      , 
   pdr_dq     , 
   pdr_dqs    ,
   pdr_dqsn   ,
   te_dq      ,  
   te_dqs     , 
   te_dqsn    ,
   ts_dq      , 
   ts_dqs     ,
   ts_dqsn    ,
  
   // delayline
   out_bdl_dly,
   out_bdl_byp,
   in_bdl_dly , 
   in_bdl_byp ,
   
   // misc 
   lb_enb     ,
   qs_n_div   , 
   indd       ,
   indqs        

);
inout            pad              ; 
input            ctl_clk_ac       ; 
input            ctl_clk_wdq      ; 
input            ctl_clk_dqs      ; 
input            ctl_phy_clk      ; 
input            ddr_clk_ac       ; 
input            ddr_clk_wdq      ; 
input            ddr_clk_dqs      ; 
input            ac_wr_rst_n      ; 
input            dx_wr_rst_n      ; 
input            ac_rd_rst_n      ; 
input            dx_rd_rst_n      ; 
input            rdqs             ; 
input            rdqs_gate        ; 
output [7:0]     diq              ; 
input  [7:0]     doq              ; 
input  [1:0]     pdr_md           ; 
input  [1:0]     te_md            ; 
input  [1:0]     ts_md            ; 
input            pdr_dq           ; 
input            pdr_dqs          ; 
input            pdr_dqsn         ; 
input            ts_dq            ; 
input            ts_dqs           ; 
input            ts_dqsn          ; 
input            te_dq            ; 
input            te_dqs           ; 
input            te_dqsn          ; 
input            in_bdl_byp       ; 
input  [5:0]     in_bdl_dly       ; 
input            out_bdl_byp      ; 
input  [5:0]     out_bdl_dly      ; 
input            lb_enb           ;
output           indd             ; 
output           indqs            ; 
output           qs_n_div         ; 
parameter DDR_SIGNAL_TYPE   = "AC"          ; // "DQ", "AC", "DQSP", "DQSN", "NONE"
parameter OCLK_SEL          = "CLK_IO"      ; // "CLK_IO", "CLK_WL", "CLK_WDQ"
parameter DATA_WIDTH        = "X8"          ; // "X4", "X8"
parameter DDR_RST_TYPE      = "ASYNC"       ; // "SYNC", "ASYNC"
parameter DATA_OUT_SYNC     = "DISABLE"     ; // "ENABLE", "DISABLE"
parameter DISABLE_GSR       = "DISABLE"     ; // "DISABLE", "ENABLE"
parameter IOTYPE            = "SSTL15"      ; // "SSTL18_I", SSTL15", "SSTL135", "SSTL12", "LVSTL11", "DIFF_SSTL18_I", "DIFF_SSTL15", "DIFF_SSTL135", "DIFF_SSTL12", "DIFF_LVSTL11", "POD12", "DIFF_POD12", "SSTL15_PZQ", "SSTL12_PZQ", "DIFF_SSTL15_PZQ", "DIFF_SSTL12_PZQ", "POD12_PZQ", "DIFF_POD_PZQ", "LVCMOS15", "LVCMOS12"
parameter MODE              = "NONE"        ; // "NONE", "OUT", "BI", "IN"
parameter ODT_SRC_SEL       = "SRAM"        ; // "DQ", "AC", "DQS", "SRAM"
parameter DRV               = "40"          ; // "34", "40", "48", "60", "75", "80", "120"
parameter ODT               = "120"         ; // "34", "40", "48", "60", "75", "80", "120"
endmodule
module PH1P_PHY_HR_BANKREF (
        vref_sel,
        vref1_rank0_ctrl,
        vref1_rank1_ctrl,
        vref2_rank0_ctrl,
        vref2_rank1_ctrl,
        det18_vccio,
        det25_vccio,
        det33_vccio,
        rterm_trim

);
        input [1:0] rterm_trim;
        input [1:0] vref_sel;
        input [7:0] vref1_rank0_ctrl;
        input [7:0] vref1_rank1_ctrl;
        input [7:0] vref2_rank0_ctrl;
        input [7:0] vref2_rank1_ctrl;
	output	    det18_vccio;
        output	    det25_vccio;
        output	    det33_vccio;
        parameter MODE                 = "IN" ;       // "NONE", "IN", "OUT", "BI"
        parameter BYTE01_IOTYPE               = "NONE";      // "NONE", "LVCMOS12", "HSTL18_I", "HSTL_I" , "SSTL18_I" , "SSTL15" , "SSTL15_R" ,"SSTL135" ,"SSTL12" , "POD12" , "HSUL12"
        parameter BYTE23_IOTYPE               = "NONE";      // "NONE", "LVCMOS12", "HSTL18_I", "HSTL_I" , "SSTL18_I" , "SSTL15" , "SSTL15_R" ,"SSTL135" ,"SSTL12" , "POD12" , "HSUL12"
        parameter VCCIO_FORCE          = "DISABLE";   // "DISABLE", "3P3", "2P5", "1P8_1P5_1P2"
        parameter PRE_EMP              = "OFF";       // "OFF", "ON"
        parameter VOCM                 = "L2";        // "L1", "L2", "L3", "L4"
        parameter VOD                  = "300M";      // "250M", "300M", "350M"
        parameter LVDSTXEN             = "DISABLE";   // "DISABLE", "ENABLE"
        parameter TMDSTXEN             = "DISABLE";   // "DISABLE", "ENABLE"
        parameter VREF                 = "INT" ;      // "EXT","INT","VREF"
        parameter VREF1_RANK0_SEL      = "SRAM";      // "SRAM","DDR"
        parameter VREF1_RANK1_SEL      = "SRAM";      // "SRAM","DDR"
        parameter VREF2_RANK0_SEL      = "SRAM";      // "SRAM","DDR"
        parameter VREF2_RANK1_SEL      = "SRAM";      // "SRAM","DDR"
endmodule
module PH1P_PHY_HR_BANKREF_V2 (
        vref_sel,
        vref1_rank0_ctrl,
        vref1_rank1_ctrl,
        vref2_rank0_ctrl,
        vref2_rank1_ctrl,
        det18_vccio,
        det25_vccio,
        det33_vccio,
        rterm_trim

);
        input [1:0] rterm_trim;
        input [1:0] vref_sel;
        input [7:0] vref1_rank0_ctrl;
        input [7:0] vref1_rank1_ctrl;
        input [7:0] vref2_rank0_ctrl;
        input [7:0] vref2_rank1_ctrl;
	output	    det18_vccio;
        output	    det25_vccio;
        output	    det33_vccio;
        parameter MODE                 = "IN" ;       // "NONE", "IN", "OUT", "BI"
        parameter BYTE01_IOTYPE        = "NONE";      // "NONE", "LVCMOS12", "HSTL18_I", "HSTL_I" , "SSTL18_I" , "SSTL15" , "SSTL15_R" ,"SSTL135" ,"SSTL12" , "POD12" , "HSUL12"
        parameter BYTE23_IOTYPE        = "NONE";      // "NONE", "LVCMOS12", "HSTL18_I", "HSTL_I" , "SSTL18_I" , "SSTL15" , "SSTL15_R" ,"SSTL135" ,"SSTL12" , "POD12" , "HSUL12"
        parameter VCCIO_FORCE          = "DISABLE";   // "DISABLE", "3P3", "2P5", "1P8_1P5_1P2"
        parameter PRE_EMP              = "OFF";       // "OFF", "ON"
        parameter VOCM                 = "L4";        // "L1", "L2", "L3", "L4", "L5", "L6"
        parameter VOD                  = "300M";      // "250M", "300M", "350M"
        parameter LVDSTXEN             = "DISABLE";   // "DISABLE", "ENABLE"
        parameter TMDSTXEN             = "DISABLE";   // "DISABLE", "ENABLE"
        parameter VREF                 = "INT" ;      // "EXT","INT","VREF"
        parameter VREF1_RANK0_SEL      = "SRAM";      // "SRAM","DDR"
        parameter VREF1_RANK1_SEL      = "SRAM";      // "SRAM","DDR"
        parameter VREF2_RANK0_SEL      = "SRAM";      // "SRAM","DDR"
        parameter VREF2_RANK1_SEL      = "SRAM";      // "SRAM","DDR"
        parameter LVDS_TYPE            = "NONE";      // "NONE", "LVDS25", "MINI_LVDS"
endmodule
module PH1P_PHY_MCU (
              core_clk        ,
              timer_clk       , 
              ahb_clk         ,     
              fb_clk          ,     
                              
              core_reset      ,
              por_reset       ,
              dpll_freq_lock  ,
              dpll_lock       ,

              core_clk_en     ,
              dbg_stop        ,
              dbg_stop_on_reset,
              dbg_stop_at_boot,
              dbg_mux_sel     ,
              
              nmi             ,      
              clic_irq        , 
                              
              jtag_tck        ,
              jtag_tms        ,
              jtag_tdi        ,
              jtag_tdo        ,
              jtag_tdo_oe     ,
                              
              gpio0_in        ,                  
              gpio0_out       ,                  
              gpio0_dir       ,
              gpio1_in        ,
              gpio1_out       ,                  
              gpio1_dir       ,
              gpio2_in        ,
              gpio2_out       ,                  
              gpio2_dir       ,
              gpio3_in        ,               
              gpio3_out       ,                  
              gpio3_dir       ,
              gpio4_in        ,               
              gpio4_out       ,                  
              gpio4_dir       ,
              gpio5_in        ,              
              gpio5_out       ,                  
              gpio5_dir       ,
              gpio6_in        ,               
              gpio6_out       ,                  
              gpio6_dir       ,
              gpio7_in        ,                                
              gpio7_out       ,                  
              gpio7_dir       ,                  
                              
              uart0_tx        ,
              uart0_rx        ,
                              
              uart1_tx        ,
              uart1_rx        ,  
                              
              i2c_sda_in      ,    
              i2c_sda_out     ,    
              i2c_sda_sel     , 
              i2c_scl_in      ,   
              i2c_scl_out     ,    
              i2c_scl_sel     ,   
                              
              qspi1_clk       ,
              qspi1_ss        ,
              qspi1_d0_in     ,                              
              qspi1_d1_in     ,                              
              qspi1_d2_in     ,                              
              qspi1_d3_in     ,                                                               
              qspi1_d0_out    ,                             
              qspi1_d1_out    ,                             
              qspi1_d2_out    ,                             
              qspi1_d3_out    ,                             
              qspi1_dir       ,  
                              
              htrans          , 
              hwrite          , 
              haddr           , 
              hsize           , 
              hburst          , 
              hprot           , 
              hmastlock       , 
              hwdata          , 
              hrdata          , 
              hresp           , 
              hready          , 
                              
              apb_clk         ,
              apb_rst         ,
              paddr           ,   
              psel            ,
              penable         ,
              pwrite          , 
              pwdata          ,   
              pstrobe         ,   
              pprot           ,   
              prdata          ,
              pready          ,
              pslverr         ,
              qspi0_dw32_sel  ,
              qspi0_spare_sel ,
	      //for DFT SCAN Port
              scan_mode_n     ,    
              scan_en_n       ,    
              pll_bypass      ,    
              pib_pll_bypass  , 
              //scan clock    ,   
              scan_rst_n      ,     
              scan_in         ,        
              wrapper_scan_in_0,
              wrapper_scan_in_1,
              chain_scan_in    ,
              wrapper_scan_out_1,
              wrapper_scan_out_2,
              chain_scan_out    ,
              core_sysrst       ,
              dft_jtag_tck      ,
              dft_jtag_rst      ,
              dft_jtag_tms      ,
              dft_jtag_tdi      ,
              dft_jtag_tdo      ,
              dft_jtag_tdo_oe
  
);
input         core_clk    ;      
input         timer_clk   ;      
output        ahb_clk     ;      
input         fb_clk      ;      
input         core_reset  ;      
input         por_reset   ;      
output        dpll_freq_lock;    
output        dpll_lock     ;    
input         core_clk_en      ; 
input         dbg_stop         ; 
input         dbg_stop_at_boot ; 
input         dbg_stop_on_reset; 
input [1:0]   dbg_mux_sel      ; 
input         nmi         ; 
input [22:0]  clic_irq    ; 
input         jtag_tck    ; 
input         jtag_tms    ; 
input         jtag_tdi    ; 
output        jtag_tdo    ; 
output        jtag_tdo_oe ; 
input         gpio0_in    ; 
output        gpio0_out   ; 
output        gpio0_dir   ; 
input         gpio1_in    ; 
output        gpio1_out   ; 
output        gpio1_dir   ; 
input         gpio2_in    ; 
output        gpio2_out   ; 
output        gpio2_dir   ; 
input         gpio3_in    ; 
output        gpio3_out   ; 
output        gpio3_dir   ; 
input         gpio4_in    ; 
output        gpio4_out   ; 
output        gpio4_dir   ; 
input         gpio5_in    ; 
output        gpio5_out   ; 
output        gpio5_dir   ; 
input         gpio6_in    ; 
output        gpio6_out   ; 
output        gpio6_dir   ; 
input         gpio7_in    ; 
output        gpio7_out   ; 
output        gpio7_dir   ; 
output        uart0_tx    ; 
input         uart0_rx    ; 
output        uart1_tx    ; 
input         uart1_rx    ; 
input         i2c_sda_in  ; 
output        i2c_sda_out ; 
output        i2c_sda_sel ; 
input         i2c_scl_in  ; 
output        i2c_scl_out ; 
output        i2c_scl_sel ; 
output        qspi1_clk   ; 
output        qspi1_ss    ; 
input         qspi1_d0_in ; 
input         qspi1_d1_in ; 
input         qspi1_d2_in ; 
input         qspi1_d3_in ; 
output        qspi1_d0_out; 
output        qspi1_d1_out; 
output        qspi1_d2_out; 
output        qspi1_d3_out; 
output [3:0]  qspi1_dir   ; 
output [1:0]  htrans      ; 
output        hwrite      ; 
output [30:0] haddr       ; 
output [2:0]  hsize       ; 
output [2:0]  hburst      ; 
output [3:0]  hprot       ; 
output        hmastlock   ; 
output [31:0] hwdata      ; 
input  [31:0] hrdata      ; 
input  [1:0]  hresp       ; 
input         hready      ; 
input         apb_clk     ; 
input         apb_rst     ; 
output [19: 0]paddr       ; 
output        psel        ; 
output        penable     ; 
output        pwrite      ; 
output [31:0] pwdata      ; 
output [3:0]  pstrobe     ; 
output [2:0]  pprot       ; 
input  [31:0] prdata      ; 
input         pready      ; 
input         pslverr     ; 
input         qspi0_dw32_sel;
input         qspi0_spare_sel;
output        core_sysrst ; 
input         dft_jtag_tck;
input         dft_jtag_rst;
input         dft_jtag_tms;
input         dft_jtag_tdi;
output        dft_jtag_tdo;
output        dft_jtag_tdo_oe;
input  scan_mode_n;
input  scan_en_n;
input  pll_bypass;
input  pib_pll_bypass;
input  scan_rst_n;
input  [72:0] scan_in;
input  wrapper_scan_in_0;
input  wrapper_scan_in_1;
input  chain_scan_in;
output wrapper_scan_out_1;
output wrapper_scan_out_2;
output chain_scan_out;
parameter  MCU_JTAG_SEL        =  "1";           
parameter  TIMING_MODE         =  "BYPASS_BYPASS";// "BYPASS_BYPASS" , "NEGATIVE_NEGATIVE"
parameter  MCU_RESET_VECTOR    =  32'hffffffff ;  
parameter  CORE_CLK_SRC        =  "GCLK" ;       // "GCLK", "OSC_DIV"
parameter  ICACHE_DISABLE_INIT =  "ENABLE";      // "DISABLE", "ENABLE"
parameter  DCACHE_DISABLE_INIT =  "ENABLE";      // "DISABLE", "ENABLE"
parameter  EMA_SRC             =  "DEFAULT";     // "PARAMETER", "DEFAULT"
parameter  EMA                 =  3'b011;        // 0~7
parameter  EMAW                =  2'b00;         // 0~3
parameter  EMAS                =  1'b0;          // 0~1
parameter  STOV                =  "DISABLE";     // "DISABLE", "ENABLE"
parameter  WABL                =  "DISABLE";     // "DISABLE", "ENABLE"
parameter  WABLM               =  "NONE";        // "NONE", "MARGIN", "DELAY", "MARGIN_AND_DELAY"
parameter   MCU_DPLL_POST_DIV                =   0;                  // 0~7
parameter   MCU_ALIGNER_BYPASS               =   "DISABLE"  ;        // "ENABLE", "DISABLE"
parameter   MCU_DPLL_BYPASS                  =   "DISABLE"  ;        // "ENABLE", "DISABLE"
parameter   MCU_DPLL_FEED_TYPE               =   "INTERNAL" ;        // "INTERNAL", "EXTERNAL"
parameter   MCU_DPLL_POWER_DOWN              =   "DISABLE"  ;        // "ENABLE", "DISABLE"
parameter   MCU_DPLL_RST_SRC                 =   "MCU"      ;        // "MCU", "DPLL_RST"
parameter   AHB_FREQ                         =   "50"       ;        // 1~150
parameter   QSPI1_FREQ                       =   "20"       ;        // 1~75
endmodule
module  PH1P_PHY_ADC (
    adc_clk,
    adc_rst,
    adc_enable_n,
    adc_ovsample_sel,
    adc_soc, 
    adc_sel_diff,
    adc_sel_ref,
    adc_data,
    adc_valid,   
    adc_channel_en, 
    adc_channel_sel,
    adc_io_sel_n,
  
    adc_vauxp_1,
    adc_vauxn_1,
    adc_vauxp_2,
    adc_vauxn_2,
    adc_vauxp_3,
    adc_vauxn_3,
    adc_vauxp_4,
    adc_vauxn_4,
    adc_vauxp_5,
    adc_vauxn_5,
    adc_vauxp_6,
    adc_vauxn_6,   
    adc_vauxp_7,
    adc_vauxn_7,  
    adc_vauxp_8,
    adc_vauxn_8   
    
);
input           adc_clk;            
input           adc_rst;            
input           adc_enable_n;
input   [1:0]   adc_ovsample_sel;
input           adc_soc;
input           adc_sel_diff;
input   [1:0]   adc_sel_ref;
output  [11:0]  adc_data;
output          adc_valid;
input           adc_channel_en;
input           adc_channel_sel;
input   [15:0]  adc_io_sel_n;
input           adc_vauxp_1;    
input           adc_vauxn_1;    
input           adc_vauxp_2;    
input           adc_vauxn_2;    
input           adc_vauxp_3;    
input           adc_vauxn_3;    
input           adc_vauxp_4;    
input           adc_vauxn_4;    
input           adc_vauxp_5;    
input           adc_vauxn_5;    
input           adc_vauxp_6;    
input           adc_vauxn_6;    
input           adc_vauxp_7;    
input           adc_vauxn_7;    
input           adc_vauxp_8;    
input           adc_vauxn_8;    
parameter	FILE_PATH	=	"/users/adc_test/analog_input.txt";
parameter	CHANGE_CLK	=	1000	;
parameter   VREF        =   "1.20";
endmodule
module PH1P_PHY_TVS ( 
    clk,
    ena_n, 
    tvs_voltage_sel,
    tvs_volt_measure_sel,
    tvs_ovsample_sel,
    tvs_trim,
    vsample,
    data_out,
    data_valid
);
input            clk;                   
input            ena_n;                 
input            vsample;               
input  [1:0]     tvs_voltage_sel;       
input            tvs_volt_measure_sel;  
input  [1:0]     tvs_ovsample_sel;      
input  [4:0]     tvs_trim;              
output [11:0]    data_out;              
output           data_valid;            
endmodule
module  PH1P_PHY_CONFIG (
    //Inputs
        osc_clk_i,
        usrtrstn_i, 
        usrtrstn_sel_n_i, 
        jtag_pib_sel_i,
        ptck_i,
        ptms_i,
        ptdi_i,
        ipa_out_i, 
        ipb_out_i,
        dna_clk_i, 
        dna_din_i, 
        dna_shift_n_i, 
        ecc_enable_n_i, 
        ecc_endaddrdebug_n_i, 
        ecc_endaddr_i, 
        multboot_en_n_i, 
        multboot_code_i, 
        multboot_addr_i, 
        usr_gsr_n_i, 
        gsr_sync_clk_i, 
        icap_enable_i,
        icap_clk_i,
        icap_cs_n_i,
        icap_rdwr_n_i,
        icap_data_i,
        tck_i, 
        tms_i, 
        tdi_i,
        ddr3_tdo_i,
        ddr3_tdoen_i,
    //Outputs
        ptdo_o,
        ptdoe_o,
        cwc_rst_o, 
        cwc_scanen_o, 
        cwc_rti_o, 
        cwc_shift_o, 
        cwc_update_o, 
        cwc_tck_o, 
        cwc_tdi_o, 
        cwc_tms_o, 
        dna_do_o, 
        ecc_clk_o, 
        ecc_stop_o, 
        ecc_done_o, 
        ecc_info_o,
        icap_busy_n_o,
        icap_data_o,
        done_o, 
        wakeup_o,
        wakeup_mux_dly20_o,
        tdo_o, 
        tdoe_o,
        ddr3_tck_o,
        ddr3_trst_n_o,
        ddr3_tms_o,
        ddr3_tdi_o,
        s_tck_o,
        s_tms_o,
        s_tdi_o,
        s_tdoen_i,
        s_tdo_i

);
        input                                   osc_clk_i               ;       
        input                                   usrtrstn_i              ;       
        input                                   usrtrstn_sel_n_i        ;       
        input                                   jtag_pib_sel_i          ;       
        input                                   ptck_i                  ;       
        input                                   ptms_i                  ;       
        input                                   ptdi_i                  ;       
        output                                  ptdo_o                  ;       
        output                                  ptdoe_o                 ;       
        input                                   ipa_out_i               ;       
        input                                   ipb_out_i               ;       
        output                                  cwc_rst_o               ;       
        output  [1:0]                           cwc_scanen_o            ;       
        output  [1:0]                           cwc_rti_o               ;       
        output                                  cwc_shift_o             ;       
        output                                  cwc_update_o            ;       
        output                                  cwc_tck_o               ;       
        output                                  cwc_tdi_o               ;       
        output                                  cwc_tms_o               ;       
        input                                   dna_clk_i               ;       
        input                                   dna_din_i               ;       
        input                                   dna_shift_n_i           ;       
        output                                  dna_do_o                ;       
        input                                   ecc_enable_n_i          ;       
        input                                   ecc_endaddrdebug_n_i    ;       
        input   [22:0]                          ecc_endaddr_i           ;       
        output                                  ecc_clk_o               ;       
        output                                  ecc_stop_o              ;       
        output                                  ecc_done_o              ;       
        output  [37:0]                          ecc_info_o              ;       
        input                                   multboot_en_n_i         ;       
        input   [7:0]                           multboot_code_i         ;       
        input   [31:0]                          multboot_addr_i         ;       
        input                                   usr_gsr_n_i             ;       
        input                                   gsr_sync_clk_i          ;       
        input                                   icap_enable_i           ;       
        input                                   icap_clk_i              ;       
        input                                   icap_cs_n_i             ;       
        input                                   icap_rdwr_n_i           ;       
        input   [31:0]                          icap_data_i             ;       
        output                                  icap_busy_n_o           ;       
        output  [31:0]                          icap_data_o             ;       
        output                                  done_o                  ;       
        output                                  wakeup_o                ;       
        output                                  wakeup_mux_dly20_o      ;       
        input   [1:0]                           ddr3_tdo_i              ;       
        input   [1:0]                           ddr3_tdoen_i            ;       
        output  [1:0]                           ddr3_tck_o              ;       
        output                                  ddr3_trst_n_o           ;       
        output                                  ddr3_tms_o              ;       
        output                                  ddr3_tdi_o              ;       
        output                                   s_tck_o                 ;       
        output                                   s_tms_o                 ;       
        output                                   s_tdi_o                 ;       
        input                                    s_tdoen_i               ;       
        input                                    s_tdo_i                 ;       
        input                                   tck_i                   ;       
        input                                   tms_i                   ;       
        input                                   tdi_i                   ;       
        output                                  tdo_o                   ;       
        output                                  tdoe_o                  ;       
        parameter       PJTAG_EN                =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       JTAG_PERSISTN           =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       SPIX4_PERSISTN          =       "DISABLE"                ;      // "ENABLE", "DISABLE"
        parameter       MULTBOOT_ADDRSRC_SEL    =       "STATIC"                ;       // "STATIC", "DYNAMIC"
        parameter       MULTBOOT_STATIC_ADDR    =       32'h0080_0000           ;
        parameter       GSRN_SYNC_SEL           =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       USR_GSRN_EN             =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       ECCERR_REPORT_EN        =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       ECC_PROTECT             =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       SEC_OPTION              =       "CORRECT_AND_CONTINUE"  ;       // "CONTINUE", "HOLD", "CORRECT_AND_CONTINUE", "CORRECT_AND_HOLD"
        parameter       ECC_FREQ                =       "2MHz"                  ;       // "2MHz", "3MHz", "5MHz", "11MHz"
        parameter       EXT_DNA_CLK_I           =       "SIG"                   ;       // "0", "1", "SIG", "INV"
        parameter       EXT_GSR_SYNC_CLK_I      =       "SIG"                   ;       // "0", "1", "SIG", "INV"
        parameter       EXT_ICAP_CLK_I          =       "SIG"                   ;       // "0", "1", "SIG", "INV"
        parameter       DOWNLOAD_MODE           =       "NONE"                  ;       // "SPIX1_X2", "SPIX4", "PCMX8", "PCMX16", "PCMX32", "NONE"
        parameter       INIT_FILE               =       "NONE"                  ;        
endmodule
module  PH1P_PHY_CONFIG_V2 (
    //Inputs
        osc_clk_i,
        usrtrstn_i, 
        usrtrstn_sel_n_i, 
        jtag_pib_sel_i,
        qspi_pib_sel_i,
        ptck_i,
        ptms_i,
        ptdi_i,
        ipa_out_i, 
        ipb_out_i,
        dna_clk_i, 
        dna_din_i, 
        dna_shift_n_i, 
        ecc_enable_n_i, 
        ecc_endaddrdebug_n_i, 
        ecc_endaddr_i, 
        multboot_en_i, 
        multboot_code_i, 
        multboot_addr_i, 
        usr_gsr_n_i, 
        gsr_sync_clk_i, 
        icap_enable_i,
        icap_clk_i,
        icap_cs_n_i,
        icap_rdwr_n_i,
        icap_data_i,
        tck_i, 
        tms_i, 
        tdi_i,
        ddr3_tdo_i,
        ddr3_tdoen_i,
    //Outputs
        eco_version_o,
        ptdo_o,
        ptdoe_o,
        cwc_rst_o, 
        cwc_scanen_o, 
        cwc_rti_o, 
        cwc_shift_o, 
        cwc_update_o, 
        cwc_tck_o, 
        cwc_tdi_o, 
        cwc_tms_o, 
        dna_do_o, 
        ecc_clk_o, 
        ecc_stop_o, 
        ecc_done_o, 
        ecc_info_o,
        icap_busy_n_o,
        icap_data_o,
        done_o, 
        wakeup_o,
        wakeup_mux_dly20_o,
        tdo_o, 
        tdoe_o,
        ddr3_tck_o,
        ddr3_trst_n_o,
        ddr3_tms_o,
        ddr3_tdi_o,
        s_tck_o,
        s_tms_o,
        s_tdi_o,
        s_tdoen_i,
        s_tdo_i,
        dualboot_o

);
        input                                   osc_clk_i               ;       
        output  [1:0]                           dualboot_o              ;       
        output  [3:0]                           eco_version_o           ;        
        input                                   usrtrstn_i              ;       
        input                                   usrtrstn_sel_n_i        ;       
        input                                   jtag_pib_sel_i          ;       
        input                                   ptck_i                  ;       
        input                                   ptms_i                  ;       
        input                                   ptdi_i                  ;       
        output                                  ptdo_o                  ;       
        output                                  ptdoe_o                 ;       
        input                                   qspi_pib_sel_i          ;       
        input                                   ipa_out_i               ;       
        input                                   ipb_out_i               ;       
        output                                  cwc_rst_o               ;       
        output  [1:0]                           cwc_scanen_o            ;       
        output  [1:0]                           cwc_rti_o               ;       
        output                                  cwc_shift_o             ;       
        output                                  cwc_update_o            ;       
        output                                  cwc_tck_o               ;       
        output                                  cwc_tdi_o               ;       
        output                                  cwc_tms_o               ;       
        input                                   dna_clk_i               ;       
        input                                   dna_din_i               ;       
        input                                   dna_shift_n_i           ;       
        output                                  dna_do_o                ;       
        input                                   ecc_enable_n_i          ;       
        input                                   ecc_endaddrdebug_n_i    ;       
        input   [22:0]                          ecc_endaddr_i           ;       
        output                                  ecc_clk_o               ;       
        output                                  ecc_stop_o              ;       
        output                                  ecc_done_o              ;       
        output  [37:0]                          ecc_info_o              ;       
        input                                   multboot_en_i           ;       
        input   [7:0]                           multboot_code_i         ;       
        input   [31:0]                          multboot_addr_i         ;       
        input                                   usr_gsr_n_i             ;       
        input                                   gsr_sync_clk_i          ;       
        input                                   icap_enable_i           ;       
        input                                   icap_clk_i              ;       
        input                                   icap_cs_n_i             ;       
        input                                   icap_rdwr_n_i           ;       
        input   [31:0]                          icap_data_i             ;       
        output                                  icap_busy_n_o           ;       
        output  [31:0]                          icap_data_o             ;       
        output                                  done_o                  ;       
        output                                  wakeup_o                ;       
        output                                  wakeup_mux_dly20_o      ;       
        input   [1:0]                           ddr3_tdo_i              ;       
        input   [1:0]                           ddr3_tdoen_i            ;       
        output  [1:0]                           ddr3_tck_o              ;       
        output                                  ddr3_trst_n_o           ;       
        output                                  ddr3_tms_o              ;       
        output                                  ddr3_tdi_o              ;       
        output                                   s_tck_o                ;       
        output                                   s_tms_o                ;       
        output                                   s_tdi_o                ;       
        input                                    s_tdoen_i              ;       
        input                                    s_tdo_i                ;       
        input                                   tck_i                   ;       
        input                                   tms_i                   ;       
        input                                   tdi_i                   ;       
        output                                  tdo_o                   ;       
        output                                  tdoe_o                  ;       
        parameter       PJTAG_EN                =       "DISABLE"               ;       // "ENABLE","DISABLE"
        parameter       JTAG_PERSISTN           =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       SPIX4_PERSISTN          =       "ENABLE"                ;       // "ENABLE", "DISABLE"
        parameter       MULTBOOT_ADDRSRC_SEL    =       "STATIC"                ;       // "STATIC", "DYNAMIC"
        parameter       MULTBOOT_STATIC_ADDR    =       32'h0080_0000           ;
        parameter       GSRN_SYNC_SEL           =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       USR_GSRN_EN             =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       INIT_FILE               =       "NONE"                  ;
        parameter       ECCERR_REPORT_EN        =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       ECC_PROTECT             =       "DISABLE"               ;       // "ENABLE", "DISABLE"
        parameter       SEC_OPTION              =       "CORRECT_AND_CONTINUE"  ;       // "CONTINUE", "HOLD", "CORRECT_AND_CONTINUE", "CORRECT_AND_HOLD"
        parameter       ECC_FREQ                =       "2MHz"                  ;       // "2MHz", "3MHz", "5MHz", "11MHz"
        parameter       DEVICE                  =       "PH1P35"                ;       // "PH1P35", "PH1P50"
        parameter       EXT_DNA_CLK_I           =       "SIG"                   ;       // "0", "1", "SIG", "INV"
        parameter       EXT_GSR_SYNC_CLK_I      =       "SIG"                   ;       // "0", "1", "SIG", "INV"
        parameter       EXT_ICAP_CLK_I          =       "SIG"                   ;       // "0", "1", "SIG", "INV"
endmodule
module  PH1P_LOGIC_BUFG(
  o,
  i
);              //  driver for global clk resource
output o;       
input i;        
endmodule
module  PH1P_LOGIC_MBOOT (
        //Inputs
        multiboot_en_n_i, 
        multiboot_code_i, 
        multiboot_addr_i

);
        input           multiboot_en_n_i;       
        input   [7:0]   multiboot_code_i;       
        input   [31:0]  multiboot_addr_i;       
        parameter               MULTBOOT_ADDRSRC_SEL = "STATIC";        // "STATIC", "DYNAMIC"
        parameter               MULTBOOT_STATIC_ADDR = 32'h0080_0000;   // Bitstream starting address in SPI FLash
endmodule
module  PH1P_LOGIC_MBOOT_V2 (
        //Inputs
        multiboot_en_i, 
        multiboot_code_i, 
        multiboot_addr_i

);
        input           multiboot_en_i;       
        input   [7:0]   multiboot_code_i;       
        input   [31:0]  multiboot_addr_i;       
        parameter               MULTBOOT_ADDRSRC_SEL = "STATIC";        // "STATIC", "DYNAMIC"
        parameter               MULTBOOT_STATIC_ADDR = 32'h0080_0000;   // Bitstream starting address in SPI FLash
endmodule
module  PH1P_LOGIC_DNA (
        //Inputs
        dna_clk_i, 
        dna_din_i, 
        dna_shift_n_i, 
        //Outpus
        dna_do_o

);
        output          dna_do_o;               
        input           dna_clk_i;              
        input           dna_din_i;              
        input           dna_shift_n_i;          
        parameter       EXT_DNA_CLK_I = "SIG";  // "0", "1", "SIG", "INV"
endmodule
module  PH1P_LOGIC_ICAP (
        //Inputs
        icap_enable_i,
        icap_clk_i,
        icap_cs_n_i,
        icap_rdwr_n_i,
        icap_data_i,
        //Outputs
        icap_busy_n_o,
        icap_data_o
);
        input                   icap_enable_i;      
        input                   icap_clk_i;         
        input                   icap_cs_n_i;        
        input                   icap_rdwr_n_i;      
        input   [31:0]          icap_data_i;        
        output                  icap_busy_n_o;      
        output  [31:0]          icap_data_o;        
        parameter   EXT_ICAP_CLK_I = "SIG";         // "0", "1", "SIG", "INV"
endmodule
module  PH1P_LOGIC_GSRN (
        //Inputs
        usr_gsr_n_i, 
        gsr_sync_clk_i

);
        input           usr_gsr_n_i;                    
        input           gsr_sync_clk_i;                 
        parameter       GSRN_SYNC_SEL = "DISABLE";      // "ENABLE", "DISABLE"
        parameter       USR_GSRN_EN     = "DISABLE";    // "ENABLE", "DISABLE"
        parameter       EXT_GSR_SYNC_CLK_I = "SIG";     // "0", "1", "SIG", "INV"
endmodule
module  PH1P_LOGIC_ECC (
        //Inputs
        ecc_enable_n_i, 
        ecc_endaddrdebug_n_i, 
        ecc_endaddr_i,
        //Outputs
        ecc_clk_o, 
        ecc_stop_o, 
        ecc_done_o, 
        ecc_info_o

);
        input               ecc_enable_n_i          ;       
        input               ecc_endaddrdebug_n_i    ;       
        input   [22:0]      ecc_endaddr_i           ;       
        output              ecc_clk_o               ;       
        output              ecc_stop_o              ;       
        output              ecc_done_o              ;       
        output  [37:0]      ecc_info_o              ;       
        parameter       ECCERR_REPORT_EN        =       "DISABLE" ;       // "ENABLE", "DISABLE"
        parameter       ECC_PROTECT             =       "DISABLE" ;       // "ENABLE",  "DISABLE"
        parameter       SEC_OPTION              =       "CORRECT_AND_CONTINUE";       // "CONTINUE",  "HOLD", "CORRECT_AND_CONTINUE", "CORRECT_AND_HOLD"
        parameter       ECC_FREQ                =       "2MHz"    ;       // "2MHz", "3MHz", "5MHz", "11MHz"
endmodule
module  PH1P_LOGIC_GCTRL (
        //Ouputs
        done_o,
        wakeup_o,
        wakeup_mux_dly20_o

);
        output          done_o                  ;       
        output          wakeup_o                ;       
        output          wakeup_mux_dly20_o      ;       
endmodule
module  PH1P_LOGIC_TRSTN (
        //Inputs
        usrtrstn_i,
        usrtrstn_sel_n_i
);
        input   usrtrstn_i;             
        input   usrtrstn_sel_n_i;       
endmodule
module PH1P_LOGIC_BOUNDARYSCAN (
       //Inputs
	bs_tdo_i,
	bs_tdoen_i,
	//Outputs
	bs_tck_o,
	bs_tms_o,
	bs_tdi_o
);
	input               bs_tdo_i              ;       
        input               bs_tdoen_i            ;       
        output              bs_tck_o              ;       
        output              bs_tms_o              ;       
        output              bs_tdi_o              ;       
endmodule
module  PH1P_LOGIC_JTAG (
        //Inputs
        jtag_pib_sel_i, 
        ptck_i, 
        ptms_i, 
        ptdi_i,
        tck_i, 
        tms_i, 
        tdi_i,
        usr_tdo_i,
        usr_tdoen_i,
        //Outputs
        ptdo_o, 
        ptdoe_o,
        tdo_o, 
        tdoe_o,
        usr_tck_o,
        usr_tms_o,
        usr_tdi_o
);
        input               jtag_pib_sel_i         ;       
        input               ptck_i                 ;       
        input               ptms_i                 ;       
        input               ptdi_i                 ;       
        output              ptdo_o                 ;       
        output              ptdoe_o                ;       
        input               tck_i                  ;       
        input               tms_i                  ;       
        input               tdi_i                  ;       
        output              tdo_o                  ;       
        output              tdoe_o                 ;       
        input               usr_tdo_i              ;       
        input               usr_tdoen_i            ;       
        output              usr_tck_o              ;       
        output              usr_tms_o              ;       
        output              usr_tdi_o              ;       
        parameter       PJTAG_EN                =       "DISABLE" ;       // "ENABLE", "DISABLE"
endmodule
module  PH1P_LOGIC_QSPI2MCU (
        qspi_pib_sel_i
);
        input               qspi_pib_sel_i          ;       
endmodule
module  PH1P_LOGIC_DEVICE_VERSION(
        device_version_o
);
        output  [3:0]           device_version_o ;       
endmodule
module  PH1P_LOGIC_DUALBOOT(
        dualboot_o
);
        output  [1:0]           dualboot_o ;       
endmodule
module PH1P_LOGIC_HR_ISERDES
(
  sclk,
  pclk,
  rst,
  idata,
  odata
);
input         sclk;       
input         pclk;       
input         rst;        
input         idata;      
output [9:0]  odata;      
parameter IDDRMODE  = "DDRX1";       // "DDRX1", "DDRX1_PIPE", "DDRX2", "DDRX3P5", "DDRX4", "DDRX5".
endmodule
module PH1P_LOGIC_HR_OSERDES
(
  sclk,
  pclk,
  rst,
  idata,
  odata
);
input         sclk;
input         pclk;
input         rst;
input [9:0]   idata;
output        odata;
parameter ODDRMODE  = "DDRX1";       // "DDRX1", "DDRX2", "DDRX3P5", "DDRX4", "DDRX5".
endmodule
module PH1P_LOGIC_IDDR
(
        q1,
        q0,
        clk,
        d,
        rst
);
output           q1;        
output           q0;        
input            clk;        
input            d;          
input            rst;        
parameter ASYNCRST      = "ENABLE";     // "ENABLE", "DISABLE".
parameter PIPEMODE      = "PIPED";      // "PIPED", "NONE".
endmodule
module PH1P_LOGIC_IDDRx2
(
        q3,
        q2,
        q1,
        q0,
        pclk,
        sclk,
        d,
        rst
);
output           q3;            
output           q2;            
output           q1;            
output           q0;            
input            pclk;          
input            sclk;          
input            d;             
input            rst;           
parameter ASYNCRST      = "ENABLE";     // "ENABLE", "DISABLE".
endmodule
module PH1P_LOGIC_ODDR
(
        q,
        clk,
        d1,
        d0,
        rst
);
output           q;           
input            clk;         
input            d1;          
input            d0;          
input            rst;         
parameter ASYNCRST      = "ENABLE";     // "ENABLE", "DISABLE".
endmodule
module PH1P_LOGIC_ODDRx2
(
        q,
        pclk,
        sclk,
        d3,
        d2,
        d1,
        d0,
        rst
);
output           q;                
input            pclk;             
input            sclk;             
input            d3;               
input            d2;               
input            d1;               
input            d0;               
input            rst;              
parameter ASYNCRST      = "ENABLE";     // "ENABLE", "DISABLE".
endmodule
module PH1P_LOGIC_DYNAMIC_HR_IDELAY (
  i,
  cas_i,
  dly,
  cas_rtn_i,
  cas_o,
  cas_rtn_o,
  o
  );
input          i;           
input   [7:0]  dly;         
input          cas_rtn_i;   
output         cas_rtn_o;   
output         o;           
input          cas_i;       
output         cas_o;       
parameter  CAS_MODE    =  "NONE";     // "NONE", "MASTER", "MIDDLE", "END".
parameter  DEVICE      =  "PH1P100";  // "PH1P100", "PH1P35", "PH1P50".
endmodule
module PH1P_LOGIC_DYNAMIC_HR_ODELAY (
  i,
  cas_i,
  dly,
  cas_rtn_i,
  cas_o,
  cas_rtn_o,
  o
  );
input          i;           
input   [7:0]  dly;         
input          cas_rtn_i;   
output         cas_rtn_o;   
output         o;           
input          cas_i;       
output         cas_o;       
parameter  CAS_MODE    =  "NONE";     // "NONE", "MASTER", "MIDDLE", "END".
parameter  DEVICE      =  "PH1P100";  // "PH1P100", "PH1P35",  "PH1P50".
endmodule
module PH1P_LOGIC_HD_IDDR (
        q1,
        q0,
        clk,
        d,
        rst
);
output           q1;        
output           q0;        
input            clk;        
input            d;          
input            rst;        
parameter ASYNCRST  = "ENABLE";                      // "ENABLE","DISABLE"
parameter MODE     = "OPPOSITE_EDGE";                // "SAME_EDGE_PIPE","SAME_EDGE","OPPOSITE_EDGE"
endmodule
module PH1P_LOGIC_HD_ODDR (
        q,
        clk,
        d1,
        d0,
        rst
);
output           q;           
input            clk;         
input            d1;          
input            d0;          
input            rst;         
parameter ASYNCRST      = "ENABLE";     // "ENABLE", "DISABLE".
endmodule
module PH1P_LOGIC_DYNAMIC_HD_IDELAY (
  i,
  cas_i,
  dly,
  cas_rtn_i,
  cas_rtn_o,
  cas_o,
  o
  );
input          i;           
input   [4:0]  dly;         
input          cas_rtn_i;   
output         cas_rtn_o;   
output         o;           
input          cas_i;       
output         cas_o;       
parameter  CAS_MODE    =   "NONE"; // NONE, MASTER,MIDDLE, END
endmodule
module PH1P_LOGIC_DYNAMIC_HD_ODELAY (
  i,
  cas_i,
  dly,
  cas_rtn_i,
  cas_rtn_o,
  cas_o,
  o
  );
input          i;         
input   [4:0]  dly;       
input          cas_rtn_i; 
output         cas_rtn_o; 
output         o;         
input          cas_i;     
output         cas_o;     
parameter  CAS_MODE    =   "NONE"; // NONE, MASTER,MIDDLE, END
endmodule
module PH1P_LOGIC_IBUF_DIFF(
    i_p,
    i_n,
    interm_disable,
    o,
    o_p,
    o_n
);
input   i_p;
input   i_n;
input   interm_disable;
output  o;
output  o_p;
output  o_n;
parameter   DIFF_TERM   =   "FALSE";     // "FALSE", "TRUE"
endmodule
module PH1P_LOGIC_OBUF_DIFF(
    i,
    t,
    o_p,
    o_n
);
input   i;
input   t;
output  o_p;
output  o_n;
endmodule
module PH1P_LOGIC_IOBUF_DIFF(
    i,
    interm_disable,
    t,
    o_p,
    o_n,
    io_p,
    io_n
);
input   i;
input   interm_disable;
input   t;
output  o_p;
output  o_n;
inout   io_p;
inout   io_n;
parameter   DIFF_TERM   =   "FALSE";     // "FALSE", "TRUE"
endmodule
module PH1P_LOGIC_IOBUF (
  i,
  o
);
input i;    
output o;   
endmodule
module PH1P_LOGIC_IBUF (
  i,
  o
);
input i;    
output o;   
endmodule
module PH1P_LOGIC_OBUF (
  i,
  o
);
input i;    
output o;   
endmodule
module PH1P_LOGIC_IOTRIBUF (
  i,
  t,
  o,
  io
);
input i;      
input t;      
output o;     
inout io;     
endmodule
