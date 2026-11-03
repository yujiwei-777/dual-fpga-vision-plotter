/*****************************************************************
Company : Nanjing Weiku Robot Technology Co., Ltd.
Brand   : VLKUS
Technical forum:www.uisrc.com
@Author      :   
@Time        :   2024/11/11
@Description :   native data convert to axi stream 
*****************************************************************/

module uial2axis #(
    parameter IMG_WIDTH        = 1280,
    parameter IMG_HEIGHT       = 720,
    parameter INPUT_DATA_WIDTH = 128
) (
    // native interface
    input I_native_clk,
    input I_rst_n,

    input [INPUT_DATA_WIDTH-1:0] I_data      ,
    input                        I_data_valid,
    input                        I_data_start,
    input                        I_data_end  ,

    output                          axis_tvalid,
    output [INPUT_DATA_WIDTH-1 : 0] axis_tdata,
    output                          axis_tuser,
    output                          axis_tlast
);
/*********************************************************
******************1.function declaration******************
*********************************************************/
  function integer clogb2(input integer bit_depth);
    begin
      for (clogb2 = 0; bit_depth > 0; clogb2 = clogb2 + 1) bit_depth = bit_depth >> 1;
    end
  endfunction
/*********************************************************
******************2.constant declaration******************
*********************************************************/
  localparam IMG_WIDTH_4X = (IMG_WIDTH >> 2);
/*********************************************************
******************3.wire signals declaration**************
*********************************************************/
  // AXI Stream internal signals
/*********************************************************
******************4.reg signals declaration***************
*********************************************************/
  reg [13:0] hcnt;  //synthesis keep  
  reg [13:0] vcnt;  //synthesis keep  
  // Qualify the native frame-start marker.  A start pulse arriving while a
  // frame is active must not reset hcnt/vcnt and create a mid-frame tuser.
  reg frame_lock;
  wire data_start_guarded = I_data_start && !frame_lock;
/*********************************************************
******************5.combination declaration***************
*********************************************************/
  assign axis_tdata  = I_data_valid ? I_data : 'b0;
  assign axis_tvalid = I_data_valid ? 1'b1 : 1'b0;
  assign axis_tlast  = hcnt == IMG_WIDTH_4X - 1 && axis_tvalid ? 1'b1 : 1'b0;
  assign axis_tuser  = vcnt == 'b0 && hcnt == 'b0 && axis_tvalid ? 1'b1 : 1'b0;
/*********************************************************
******************6.sequential declaration****************
*********************************************************/

  always @(posedge I_native_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
      frame_lock <= 1'b0;
    end else if (data_start_guarded) begin
      frame_lock <= 1'b1;
    end else if (I_data_end || (axis_tlast && vcnt == IMG_HEIGHT - 1)) begin
      frame_lock <= 1'b0;
    end
  end

  always @(posedge I_native_clk or negedge I_rst_n) begin
    if (!I_rst_n || data_start_guarded) begin
      hcnt <= 'b0;
    end else if (I_data_valid & hcnt < IMG_WIDTH_4X - 1) begin
      hcnt <= hcnt + 1'b1;
    end else if (I_data_valid & hcnt == IMG_WIDTH_4X - 1) begin
      hcnt <= 'b0;
    end else hcnt <= hcnt;
  end

  always @(posedge I_native_clk or negedge I_rst_n) begin
    if (!I_rst_n || data_start_guarded) begin
      vcnt <= 'b0;
    end else if (axis_tlast & vcnt == IMG_HEIGHT - 1) begin
      vcnt <= 'b0;
    end else if (axis_tlast & vcnt < IMG_HEIGHT - 1) begin
      vcnt <= vcnt + 1;
    end else vcnt <= vcnt;
  end

endmodule



