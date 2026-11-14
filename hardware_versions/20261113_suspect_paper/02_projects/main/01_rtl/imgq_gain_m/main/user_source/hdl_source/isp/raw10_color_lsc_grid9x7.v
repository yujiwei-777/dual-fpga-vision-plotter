`timescale 1ns/1ps
// Low resource continuous cell-centre colour LSC prototype.
// C(x,y) = Xbase(x) + Ybase(y) + Xcross(x)*Ycross(y).
// ROMs are fitted to the original frozen R/B 9x7 cell-centre field.
// Stage 0: synchronous dual-read horizontal ROM + single-read vertical ROM.
// Stage 1: signed cross product and coefficient summation.
// Stage 2: RAW10 product, rounding and saturation. All stages are elastic.
module raw10_color_lsc_grid9x7 #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer LSC_ENABLE=1,
    // TD resolves initialization filenames relative to this RTL source.
    // Keep the ROM beside the module so independent build directories work.
    parameter HROM_FILE="horizontal.mem",
    parameter VROM_FILE="vertical.mem"
)(
    input wire I_clk,I_rst_n,
    input wire I_tvalid,
    output wire I_tready,
    input wire I_tuser,I_tlast,
    input wire [39:0] I_tdata,
    input wire [3:0] I_sat_mask,
    output wire O_tvalid,
    input wire O_tready,
    output wire O_tuser,O_tlast,
    output wire [39:0] O_tdata,
    output wire [3:0] O_sat_mask
);
    // Upper word: signed coefficient-DN Q4 baseline; lower: signed factor.
    // Horizontal cross factor is Q14; vertical cross factor is DN Q8.
    // Address B={0,x}; R={1,x}; X is padded to 2048 addresses per colour.
    (* ram_style="bram" *) reg [31:0] horizontal_rom[0:4095];
    // Only active BGGR colour is stored at each absolute y: even B / odd R.
    (* ram_style="bram" *) reg [31:0] vertical_rom[0:1023];
    initial begin
        $readmemh(HROM_FILE,horizontal_rom);
        $readmemh(VROM_FILE,vertical_rom);
    end
    reg [10:0] x_r; reg [9:0] y_r;
    reg frame_bad_r,frame_started_r;
    reg p0_valid,p0_user,p0_last,p0_odd,p0_lsc;
    reg [39:0] p0_data; reg [3:0] p0_sat;
    reg [31:0] p0_h0,p0_h1,p0_v;
    reg p1_valid,p1_user,p1_last,p1_odd,p1_lsc;
    reg [39:0] p1_data; reg [3:0] p1_sat;
    reg [11:0] p1_coeff0,p1_coeff1;
    reg out_valid,out_user,out_last;
    reg [39:0] out_data; reg [3:0] out_sat;
    wire out_ready=!out_valid || O_tready;
    wire p1_ready=!p1_valid || out_ready;
    wire p0_ready=!p0_valid || p1_ready;
    assign I_tready=p0_ready;
    assign O_tvalid=out_valid;assign O_tuser=out_user;assign O_tlast=out_last;
    assign O_tdata=out_data;assign O_sat_mask=out_sat;
    wire fire=I_tvalid && I_tready;
    wire [10:0] x_now=I_tuser?11'd0:x_r;
    wire [9:0] y_now=I_tuser?10'd0:y_r;
    wire odd_now=y_now[0];
    wire shape_ok=(I_tlast==(x_now==IMG_WIDTH-4));
    wire bad_now=(!I_tuser && (!frame_started_r || frame_bad_r)) ||
                 !shape_ok || (y_now>=IMG_HEIGHT);
    wire [10:0] cx0=x_now+(odd_now?11'd1:11'd0);
    wire [10:0] cx1=x_now+(odd_now?11'd3:11'd2);
    wire [11:0] ha0={odd_now,cx0},ha1={odd_now,cx1};
    // ROM output registers intentionally have no asynchronous reset to retain
    // synchronous ERAM inference. Their content is ignored while p0_valid=0.
    always @(posedge I_clk) begin
        if(p0_ready && I_tvalid) begin
            p0_h0<=horizontal_rom[ha0];p0_h1<=horizontal_rom[ha1];
            p0_v<=vertical_rom[y_now];
        end
    end
    (* use_dsp="yes" *) wire signed [31:0] cross0=
        $signed(p0_h0[15:0])*$signed(p0_v[15:0]);
    (* use_dsp="yes" *) wire signed [31:0] cross1=
        $signed(p0_h1[15:0])*$signed(p0_v[15:0]);
    // Product is coefficient-DN Q22; round to Q4, then add baselines in Q4.
    wire signed [31:0] cross0_q4=(cross0+32'sd131072)>>>18;
    wire signed [31:0] cross1_q4=(cross1+32'sd131072)>>>18;
    wire signed [17:0] xb0={{2{p0_h0[31]}},p0_h0[31:16]};
    wire signed [17:0] xb1={{2{p0_h1[31]}},p0_h1[31:16]};
    wire signed [17:0] yb={{2{p0_v[31]}},p0_v[31:16]};
    wire signed [17:0] sum0_q4=xb0+yb+$signed(cross0_q4[17:0]);
    wire signed [17:0] sum1_q4=xb1+yb+$signed(cross1_q4[17:0]);
    wire signed [17:0] coeff0_int=(sum0_q4+18'sd8)>>>4;
    wire signed [17:0] coeff1_int=(sum1_q4+18'sd8)>>>4;
    wire [11:0] coeff0=(coeff0_int<0)?12'd0:
        ((coeff0_int>1024)?12'd1024:coeff0_int[11:0]);
    wire [11:0] coeff1=(coeff1_int<0)?12'd0:
        ((coeff1_int>1024)?12'd1024:coeff1_int[11:0]);
    wire [9:0] pixel0=p1_odd?p1_data[19:10]:p1_data[9:0];
    wire [9:0] pixel1=p1_odd?p1_data[39:30]:p1_data[29:20];
    (* use_dsp="yes" *) wire [21:0] product0=pixel0*p1_coeff0;
    (* use_dsp="yes" *) wire [21:0] product1=pixel1*p1_coeff1;
    wire [22:0] rounded0={1'b0,product0}+23'd512;
    wire [22:0] rounded1={1'b0,product1}+23'd512;
    wire [12:0] scaled0=rounded0[22:10],scaled1=rounded1[22:10];
    wire [9:0] corrected0=(scaled0>1023)?10'd1023:scaled0[9:0];
    wire [9:0] corrected1=(scaled1>1023)?10'd1023:scaled1[9:0];
    wire [39:0] corrected_word=!p1_lsc?p1_data:
        (p1_odd?{corrected1,p1_data[29:20],corrected0,p1_data[9:0]}:
                {p1_data[39:30],corrected1,p1_data[19:10],corrected0});
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x_r<=0;y_r<=0;frame_bad_r<=0;frame_started_r<=0;
            p0_valid<=0;p0_user<=0;p0_last<=0;p0_odd<=0;p0_lsc<=0;p0_data<=0;p0_sat<=0;
            p1_valid<=0;p1_user<=0;p1_last<=0;p1_odd<=0;p1_lsc<=0;p1_data<=0;p1_sat<=0;
            p1_coeff0<=1024;p1_coeff1<=1024;
            out_valid<=0;out_user<=0;out_last<=0;out_data<=0;out_sat<=0;
        end else begin
            if(out_ready) begin
                out_valid<=p1_valid;
                if(p1_valid) begin out_user<=p1_user;out_last<=p1_last;
                    out_data<=corrected_word;out_sat<=p1_sat;end
            end
            if(p1_ready) begin
                p1_valid<=p0_valid;
                if(p0_valid) begin p1_user<=p0_user;p1_last<=p0_last;p1_odd<=p0_odd;
                    p1_lsc<=p0_lsc;p1_data<=p0_data;p1_sat<=p0_sat;
                    p1_coeff0<=coeff0;p1_coeff1<=coeff1;end
            end
            if(p0_ready) begin
                p0_valid<=I_tvalid;
                if(I_tvalid) begin p0_user<=I_tuser;p0_last<=I_tlast;p0_odd<=odd_now;
                    p0_lsc<=(LSC_ENABLE!=0)&&!bad_now;p0_data<=I_tdata;p0_sat<=I_sat_mask;end
            end
            if(fire) begin
                if(I_tuser) begin frame_started_r<=1;frame_bad_r<=!shape_ok;end
                else if(bad_now) frame_bad_r<=1;
                if(I_tlast) begin x_r<=0;y_r<=(y_now<IMG_HEIGHT-1)?y_now+1'b1:10'd0;
                    if(y_now==IMG_HEIGHT-1) frame_started_r<=0;end
                else begin x_r<=(x_now<IMG_WIDTH-4)?x_now+11'd4:11'd0;y_r<=y_now;end
            end
        end
    end
endmodule
