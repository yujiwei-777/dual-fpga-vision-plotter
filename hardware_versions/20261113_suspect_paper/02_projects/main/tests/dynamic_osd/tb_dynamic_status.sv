`timescale 1ns/1ps
module tb_dynamic_status;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg [11:0] x=0,y=0;
  reg pcb_mode=0,pcb_suspect=0;
  reg [2:0] pcb_status=0;
  reg operator_valid=0;
  reg [152:0] operator_data=0;
  reg [3:0] operator_digit=0;
  wire [5:0] operator_digit_addr;
  wire panel_on,panel_border,text_on;
  wire [23:0] text_color;
  wire [7:0] font_glyph;
  wire [3:0] font_row;
  wire [15:0] font_row_bits;

  osd_compact_panel dut(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(pcb_suspect),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(operator_valid),.operator_data(operator_data),
    .operator_digit(operator_digit),.operator_digit_addr(operator_digit_addr),
    .panel_on(panel_on),.panel_border(panel_border),.text_on(text_on),
    .text_color(text_color),.font_glyph(font_glyph),.font_row(font_row),
    .font_row_bits(font_row_bits));
  osd_compact_font_rom font(.clk(clk),.glyph(font_glyph),.row(font_row),.row_bits(font_row_bits));

  task sample_panel;
    input expected;
    begin
      repeat(3) @(posedge clk);
      #1;
      if(panel_on !== expected) begin
        $display("DYNAMIC_OSD_FAIL expected=%0d got=%0d valid=%0d flags=%b",expected,panel_on,operator_valid,operator_data[1:0]);
        $fatal(1);
      end
    end
  endtask

  initial begin
    x=12'd800; y=12'd224;
    repeat(3) @(posedge clk); rst_n=1;
    operator_valid=1; operator_data=0;
    sample_panel(0);
    operator_data[0]=1;       // cached CNN/PCB result waiting for KEY1
    sample_panel(1);
    operator_data[0]=0; operator_data[1]=1; // accepted writing/maintenance task
    sample_panel(1);
    operator_data[1]=0;       // task finished, no pending result
    sample_panel(0);
    operator_data[2]=1;       // page full needs operator attention
    sample_panel(1);
    operator_data[2]=0; operator_data[3]=1; // recovery required
    sample_panel(1);
    operator_data[3]=0;
    sample_panel(0);
    operator_valid=0; operator_data[0]=1;
    sample_panel(0);
    $display("DYNAMIC_OSD_PASS pending_writing_fault_visible idle_hidden");
    $finish;
  end
endmodule
