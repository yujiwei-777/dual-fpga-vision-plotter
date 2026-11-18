`timescale 1ns/1ps
// REPORTS-ONLY COMPLETE WARP CANDIDATE. No production source is replaced.
// One private128x16 RF, existing engine A/B/R/aux/carry, its ONE registered
// unsigned16x16 DSP and ONE32-bit ALU are the numerical resources.
// This sequencer contains control/address bits only, not a numeric value bank.
// R0=x R1=y R2=flags(fine/coarse/half), R4..11=fine signed32,
// R12..23=six sign-extended40-bit coarse coefficients in64-bit pairs.
// R24..27=source64 X/Y, R28/29=project32 X/Y, R30=fx/fy,
// R31=status/gray. R3=base X/Y. R32..63 are exclusive scratch.
// norm_q is synchronous data from the SHARED engine ROM at NORM_BASE+norm_addr;
// its288 exact32-bit words are appended after the ordinary constant region.
module pcb_warp_rf_uop_candidate #(
    parameter integer WAIT_TIMEOUT=4096
) (
    input wire clk,rst_n,start,cancel,
    output wire busy,
    output reg done,valid,
    output reg [3:0] error,
    output reg [7:0] O_gray,
    output reg O_sample_complete,
    output reg [3:0] O_tap_inside,
    output wire O_pixel_request,
    output reg [10:0] O_pixel_x,
    output reg [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,
    input wire [7:0] I_pixel_y8,
    output reg [8:0] norm_addr,
    input wire [31:0] norm_q,
    output reg [6:0] rf_a_addr,rf_b_addr,
    output reg rf_we,
    output reg [15:0] rf_wdata,
    input wire [15:0] rf_a_data,rf_b_data,
    input wire [31:0] a,b,r,product,
    input wire [15:0] aux,
    input wire carry,
    input wire [32:0] alu_sum,
    output reg a_we,b_we,r_we,aux_we,carry_we,
    output reg [31:0] a_data,b_data,r_data,
    output reg [15:0] aux_data,
    output reg carry_data,
    output reg [31:0] alu_a,alu_b,
    output reg alu_carry
);
    localparam IDLE=0,RUN=1,CLEAR_OUTPUT=2,
      PAIR_WAIT=3,PAIR_CAPTURE=4,A32_EXEC=5,WRITE_LOW=6,WRITE_HIGH=7,
      EXT_WAIT=8,EXT_CAPTURE=9,EXT_STORE=10,MOV_WAIT=11,MOV_CAPTURE=12,
      A64_PREP=13,A64_WAIT=14,A64_CAPTURE=15,A64_EXEC=16,A64_STORE=17,
      CONST_STORE=18,S_WAIT=19,S_CAPTURE=20,S_EXEC=21,S_STORE=22,
      M_CLEAR=23,M_WAIT=24,M_CAPTURE=25,M_PIPE=26,M_PRODUCT=27,
      M_ACC_WAIT=28,M_ACC_CAPTURE=29,M_ACC_EXEC=30,M_ACC_STORE=31,
      N_WAIT=32,N_CAPTURE=33,N_ROM_WAIT=34,N_ROM_CAPTURE=35,
      F_WAIT=36,P_WAIT=37,P_CAPTURE=38,SM_WAIT=39,SM_CAPTURE=40,
      SM_PIPE=41,SM_RESULT=42,S32_WAIT=43,S32_CAPTURE=44,
      PIXEL_ZERO=45,REQUEST=46,RESPONSE=47,DRAIN=48,LOCKED=49;
    localparam SH_PLUS16=0,SH_PLUS24=1,SH_MINUS16=2,SH_MINUS1=3,
      SH_PLUS12=4,SH_MINUS23=5;
    localparam [7:0] P_INPUT_READ=8'd0;
    localparam [7:0] P_INPUT_CHECK=8'd1;
    localparam [7:0] P_FLAGS_CHECK=8'd2;
    localparam [7:0] P_SLOPE_READ=8'd3;
    localparam [7:0] P_SLOPE_CHECK=8'd4;
    localparam [7:0] P_NORM_U=8'd5;
    localparam [7:0] P_NORM_V=8'd6;
    localparam [7:0] P_FINE_A_EXT=8'd7;
    localparam [7:0] P_FINE_U_EXT=8'd8;
    localparam [7:0] P_FINE_A_MUL=8'd9;
    localparam [7:0] P_FINE_B_EXT=8'd10;
    localparam [7:0] P_FINE_V_EXT=8'd11;
    localparam [7:0] P_FINE_B_MUL=8'd12;
    localparam [7:0] P_FINE_SUM=8'd13;
    localparam [7:0] P_FINE_SHIFT=8'd14;
    localparam [7:0] P_FINE_TRANS=8'd15;
    localparam [7:0] P_FINE_COMMIT=8'd16;
    localparam [7:0] P_FINE_NEXT=8'd17;
    localparam [7:0] P_DEN_READ=8'd18;
    localparam [7:0] P_DEN_CHECK=8'd19;
    localparam [7:0] P_FX_SHIFT=8'd20;
    localparam [7:0] P_FX_DIV=8'd21;
    localparam [7:0] P_FX_BIAS=8'd22;
    localparam [7:0] P_FX_ADD=8'd23;
    localparam [7:0] P_FY_SHIFT=8'd24;
    localparam [7:0] P_FY_DIV=8'd25;
    localparam [7:0] P_FY_BIAS=8'd26;
    localparam [7:0] P_FY_ADD=8'd27;
    localparam [7:0] P_DIRECT_X_EXT=8'd28;
    localparam [7:0] P_DIRECT_X_SHIFT=8'd29;
    localparam [7:0] P_DIRECT_Y_EXT=8'd30;
    localparam [7:0] P_DIRECT_Y_SHIFT=8'd31;
    localparam [7:0] P_PROJECT_X_COPY=8'd32;
    localparam [7:0] P_PROJECT_Y_COPY=8'd33;
    localparam [7:0] P_PROJECT_X_READ=8'd34;
    localparam [7:0] P_PROJECT_X_CHECK=8'd35;
    localparam [7:0] P_PROJECT_Y_CHECK=8'd36;
    localparam [7:0] P_COARSE_A_MUL=8'd37;
    localparam [7:0] P_COARSE_B_MUL=8'd38;
    localparam [7:0] P_COARSE_SUM=8'd39;
    localparam [7:0] P_COARSE_SHIFT=8'd40;
    localparam [7:0] P_COARSE_TRANS=8'd41;
    localparam [7:0] P_COARSE_NEXT=8'd42;
    localparam [7:0] P_HALF_CONST=8'd43;
    localparam [7:0] P_HALF_X_ADD=8'd44;
    localparam [7:0] P_HALF_X_DIV=8'd45;
    localparam [7:0] P_HALF_X_SHIFT=8'd46;
    localparam [7:0] P_HALF_Y_ADD=8'd47;
    localparam [7:0] P_HALF_Y_DIV=8'd48;
    localparam [7:0] P_HALF_Y_SHIFT=8'd49;
    localparam [7:0] P_PLAIN_X=8'd50;
    localparam [7:0] P_PLAIN_Y=8'd51;
    localparam [7:0] P_ROUND_START=8'd52;
    localparam [7:0] P_ROUND_SHIFT=8'd53;
    localparam [7:0] P_ROUND_READ=8'd54;
    localparam [7:0] P_ROUND_TEST=8'd55;
    localparam [7:0] P_ROUND_ADD=8'd56;
    localparam [7:0] P_ROUND_NEXT=8'd57;
    localparam [7:0] P_COORD_X_CHECK=8'd58;
    localparam [7:0] P_COORD_Y_CHECK=8'd59;
    localparam [7:0] P_PACK_BASE=8'd60;
    localparam [7:0] P_PACK_FRACTION=8'd61;
    localparam [7:0] P_TAPS_BEGIN=8'd62;
    localparam [7:0] P_TAP_READ=8'd63;
    localparam [7:0] P_TAP_X=8'd64;
    localparam [7:0] P_TAP_Y=8'd65;
    localparam [7:0] P_BLEND_ROW_BEGIN=8'd66;
    localparam [7:0] P_BLEND_RIGHT=8'd67;
    localparam [7:0] P_BLEND_LEFT=8'd68;
    localparam [7:0] P_BLEND_DIFF=8'd69;
    localparam [7:0] P_BLEND_MUL=8'd70;
    localparam [7:0] P_BLEND_BASE=8'd71;
    localparam [7:0] P_BLEND_ADD=8'd72;
    localparam [7:0] P_BLEND_NEXT=8'd73;
    localparam [7:0] P_BLEND_Y_DIFF=8'd74;
    localparam [7:0] P_BLEND_Y_MUL=8'd75;
    localparam [7:0] P_BLEND_Y_BASE=8'd76;
    localparam [7:0] P_BLEND_Y_ADD=8'd77;
    localparam [7:0] P_BLEND_ROUND=8'd78;
    localparam [7:0] P_BLEND_ROUND_ADD=8'd79;
    localparam [7:0] P_BLEND_FINAL_SHIFT=8'd80;
    localparam [7:0] P_BLEND_GRAY_READ=8'd81;
    localparam [7:0] P_BLEND_STATUS=8'd82;
    localparam [7:0] P_OUTSIDE_STATUS=8'd83;
    localparam [7:0] P_NORMAL_FINISH=8'd84;
    reg [5:0] state;
    reg [7:0] step,return_step;
    reg [5:0] dst,sa,sb;
    reg [1:0] limb,axis,mi,mj,mk,tap_index;
    reg [3:0] clear_index,const_code;
    reg [2:0] flags,shift_code;
    reg pair_high,pair_alu,op_sub,norm_v,small_y,small_negative,pixel_shift,shift32_right,inside_x;
    reg [6:0] physical_source;
    localparam integer WAIT_BITS=WAIT_TIMEOUT>1?$clog2(WAIT_TIMEOUT):1;
    reg [WAIT_BITS-1:0] wait_count;
    wire [2:0] slope_index=axis==0?3'd0:axis==1?3'd1:axis==2?3'd3:3'd4;
    wire [5:0] fine_first=axis==0?6'd4:axis==1?6'd7:6'd10;
    wire [5:0] coarse_first=axis==0?6'd12:6'd18;
    wire [31:0] width=flags[1]?32'd1280:flags[2]?32'd96:32'd192;
    wire [31:0] height=flags[1]?32'd720:flags[2]?32'd48:32'd96;
    wire [31:0] width_q5=width<<5,height_q5=height<<5;
    wire tap_zero=(tap_index[0] && b[4:0]==0)||(tap_index[1] && b[9:5]==0);
    wire tap_in_bounds=inside_x && !alu_sum[31] && alu_sum[31:0]<height;
    wire shift_left=shift_code==SH_PLUS16 || shift_code==SH_PLUS24 || shift_code==SH_PLUS12;
    wire shift_arithmetic=!shift_left;
    reg signed [3:0] shift_index;
    wire signed [3:0] shift_next_index=shift_index+4'sd1;
    wire [6:0] shift_lo_addr={sa,1'b0}+(shift_index<0?7'd0:shift_index>3?7'd3:{3'd0,shift_index});
    wire [6:0] shift_hi_addr={sa,1'b0}+(shift_next_index<0?7'd0:shift_next_index>3?7'd3:{3'd0,shift_next_index});
    wire [15:0] shift_lo=shift_index<0?16'd0:shift_index>3?(shift_arithmetic?{16{rf_a_data[15]}}:16'd0):rf_a_data;
    wire [15:0] shift_hi=shift_next_index<0?16'd0:shift_next_index>3?(shift_arithmetic?{16{rf_b_data[15]}}:16'd0):rf_b_data;
    wire [2:0] product_limb={1'b0,mi}+{1'b0,mj};
    assign busy=state!=IDLE;
    assign O_pixel_request=state==REQUEST && !cancel && !start;

    // The floor component contains only a control sequencer and uses the same
    // RF / ALU / A/B/R/aux/carry through the mux below.
    wire f_start=state==RUN && (step==P_FX_DIV || step==P_FY_DIV);
    wire f_active=state==F_WAIT;
    wire f_busy,f_done;wire [3:0] f_fault;
    wire [6:0] f_aa,f_ba;wire f_we;wire [15:0] f_wd;
    wire f_aw,f_bw,f_rw,f_xw,f_cw,f_cd,f_ac;
    wire [31:0] f_ad,f_bd,f_rd,f_alu_a,f_alu_b;wire [15:0] f_xd;
    pcb_warp_floor58_rf_uop_candidate floor58(
        .clk(clk),.rst_n(rst_n),.start(f_start),.cancel(cancel||(start&&busy)),
        .busy(f_busy),.done(f_done),.fault(f_fault),
        .rf_a_addr(f_aa),.rf_b_addr(f_ba),.rf_we(f_we),.rf_wdata(f_wd),
        .rf_a_data(rf_a_data),.rf_b_data(rf_b_data),.a(a),.b(b),.r(r),.aux(aux),.carry(carry),.alu_sum(alu_sum),
        .a_we(f_aw),.b_we(f_bw),.r_we(f_rw),.aux_we(f_xw),.carry_we(f_cw),
        .a_data(f_ad),.b_data(f_bd),.r_data(f_rd),.aux_data(f_xd),.carry_data(f_cd),
        .alu_a(f_alu_a),.alu_b(f_alu_b),.alu_carry(f_ac));

    function [15:0] constant_word;
        input [3:0] code;input [1:0] word_index;
        begin case(code)
            0:constant_word=0;
            1:constant_word=word_index==0?16'd1:16'd0;
            2:constant_word=word_index==1?16'h0100:16'd0;
            3:constant_word=word_index==1?16'd96:16'd0;
            4:constant_word=word_index==1?16'd48:16'd0;
            5:constant_word=word_index==0?16'h8000:16'hffff;
            6:constant_word=word_index==0?16'd512:16'd0;
            default:constant_word=0;
        endcase end
    endfunction
    task go;input [7:0] next_step;begin step<=next_step;state<=RUN;end endtask
    task fail;input [3:0] code;begin error<=code;O_sample_complete<=0;done<=1;valid<=0;state<=IDLE;end endtask
    task call_pair;
        input [5:0] left,right;input [7:0] next_step;
        begin sa<=left;sb<=right;pair_high<=0;pair_alu<=0;return_step<=next_step;state<=PAIR_WAIT;end
    endtask
    task call_store32;
        input [5:0] target;input [7:0] next_step;
        begin dst<=target;return_step<=next_step;state<=WRITE_LOW;end
    endtask
    task call_mov32;
        input [5:0] target,source;input [7:0] next_step;
        begin dst<=target;sa<=source;return_step<=next_step;state<=MOV_WAIT;end
    endtask
    task call_ext32;
        input [5:0] target,source;input [7:0] next_step;
        begin dst<=target;sa<=source;limb<=0;return_step<=next_step;state<=EXT_WAIT;end
    endtask
    task call_add64;
        input [5:0] target,left,right;input subtract;input [7:0] next_step;
        begin dst<=target;sa<=left;sb<=right;op_sub<=subtract;limb<=0;return_step<=next_step;state<=A64_PREP;end
    endtask
    task call_const64;
        input [5:0] target;input [3:0] code;input [7:0] next_step;
        begin dst<=target;const_code<=code;limb<=0;return_step<=next_step;state<=CONST_STORE;end
    endtask
    task call_shift64;
        input [5:0] target,source;input [2:0] code;input [7:0] next_step;
        begin dst<=target;sa<=source;shift_code<=code;return_step<=next_step;
            limb<=(code==SH_PLUS16||code==SH_PLUS24||code==SH_PLUS12)?2'd3:2'd0;state<=S_WAIT;end
    endtask
    task call_mul64;
        input [5:0] target,left,right;input [7:0] next_step;
        begin dst<=target;sa<=left;sb<=right;limb<=0;mi<=0;mj<=0;return_step<=next_step;state<=M_CLEAR;end
    endtask
    task call_norm;
        input [5:0] target,source;input vertical;input [7:0] next_step;
        begin dst<=target;sa<=source;norm_v<=vertical;return_step<=next_step;state<=N_WAIT;end
    endtask
    task call_pixel32;
        input [5:0] target;input [6:0] source;input times32;input [7:0] next_step;
        begin dst<=target;physical_source<=source;pixel_shift<=times32;return_step<=next_step;state<=P_WAIT;end
    endtask
    task call_add32;
        input [5:0] target,left,right;input subtract;input [7:0] next_step;
        begin dst<=target;sa<=left;sb<=right;op_sub<=subtract;pair_high<=0;pair_alu<=1;
            return_step<=next_step;state<=PAIR_WAIT;end
    endtask
    task call_small_mul;
        input [5:0] target,source;input vertical;input [7:0] next_step;
        begin dst<=target;sa<=source;small_y<=vertical;return_step<=next_step;state<=SM_WAIT;end
    endtask
    task call_shift32;
        input [5:0] target,source;input right_ten;input [7:0] next_step;
        begin dst<=target;sa<=source;shift32_right<=right_ten;return_step<=next_step;state<=S32_WAIT;end
    endtask
    task next_tap;
        begin if(tap_index==3)go(P_BLEND_ROW_BEGIN);
        else begin tap_index<=tap_index+1'b1;go(P_TAP_READ);end end
    endtask

    always @* begin
        case(shift_code)
            SH_PLUS16:shift_index=$signed({2'd0,limb})-4'sd1;
            SH_PLUS24:shift_index=$signed({2'd0,limb})-4'sd2;
            SH_MINUS16,SH_MINUS23:shift_index=$signed({2'd0,limb})+4'sd1;
            SH_PLUS12:shift_index=$signed({2'd0,limb})-4'sd1;
            default:shift_index=$signed({2'd0,limb});
        endcase
    end
    always @* begin
        rf_a_addr=0;rf_b_addr=0;rf_we=0;rf_wdata=0;
        a_we=0;b_we=0;r_we=0;aux_we=0;carry_we=0;
        a_data=a;b_data=b;r_data=r;aux_data=aux;carry_data=carry;
        alu_a=0;alu_b=0;alu_carry=0;
        case(state)
            CLEAR_OUTPUT:begin rf_a_addr=7'd48+{3'd0,clear_index};rf_we=1;end
            PAIR_WAIT,PAIR_CAPTURE:begin
                rf_a_addr={sa,1'b0}+{6'd0,pair_high};rf_b_addr={sb,1'b0}+{6'd0,pair_high};
                if(state==PAIR_CAPTURE)begin
                    a_we=1;b_we=1;
                    a_data=pair_high?{rf_a_data,a[15:0]}:{a[31:16],rf_a_data};
                    b_data=pair_high?{rf_b_data,b[15:0]}:{b[31:16],rf_b_data};
                end
            end
            A32_EXEC:begin alu_a=a;alu_b=op_sub?~b:b;alu_carry=op_sub;r_we=1;r_data=alu_sum[31:0];end
            WRITE_LOW,WRITE_HIGH:begin
                rf_a_addr={dst,1'b0}+{6'd0,(state==WRITE_HIGH)};rf_we=1;
                rf_wdata=state==WRITE_LOW?r[15:0]:r[31:16];
            end
            EXT_WAIT,EXT_CAPTURE,MOV_WAIT,MOV_CAPTURE,S32_WAIT,S32_CAPTURE:begin
                rf_a_addr={sa,1'b0};rf_b_addr={sa,1'b0}+7'd1;
                if(state==EXT_CAPTURE)begin a_we=1;a_data={rf_b_data,rf_a_data};end
                if(state==MOV_CAPTURE)begin r_we=1;r_data={rf_b_data,rf_a_data};end
                if(state==S32_CAPTURE)begin r_we=1;r_data=shift32_right?{10'd0,rf_b_data,rf_a_data[15:10]}:{rf_b_data[10:0],rf_a_data,5'd0};end
            end
            EXT_STORE:begin
                rf_a_addr={dst,1'b0}+{5'd0,limb};rf_we=1;
                rf_wdata=limb==0?a[15:0]:limb==1?a[31:16]:{16{a[31]}};
            end
            A64_PREP:begin carry_we=1;carry_data=op_sub;end
            A64_WAIT,A64_CAPTURE:begin
                rf_a_addr={sa,1'b0}+{5'd0,limb};rf_b_addr={sb,1'b0}+{5'd0,limb};
                if(state==A64_CAPTURE)begin a_we=1;a_data={16'd0,rf_a_data};b_we=1;b_data={16'd0,rf_b_data};end
            end
            A64_EXEC:begin
                alu_a={16'd0,a[15:0]};alu_b={16'd0,(op_sub?~b[15:0]:b[15:0])};alu_carry=carry;
                r_we=1;r_data=alu_sum[31:0];carry_we=1;carry_data=alu_sum[16];
            end
            A64_STORE:begin rf_a_addr={dst,1'b0}+{5'd0,limb};rf_we=1;rf_wdata=r[15:0];end
            CONST_STORE:begin rf_a_addr={dst,1'b0}+{5'd0,limb};rf_we=1;rf_wdata=constant_word(const_code,limb);end
            S_WAIT,S_CAPTURE:begin
                rf_a_addr=shift_lo_addr;rf_b_addr=shift_hi_addr;
                if(state==S_CAPTURE)begin a_we=1;a_data={shift_hi,shift_lo};end
            end
            S_EXEC:begin
                r_we=1;
                case(shift_code)
                    SH_PLUS16,SH_MINUS16:r_data={16'd0,a[15:0]};
                    SH_PLUS24:r_data={16'd0,a[23:8]};
                    SH_MINUS1:r_data={16'd0,a[16:1]};
                    SH_PLUS12:r_data={16'd0,a[19:4]};
                    SH_MINUS23:r_data={16'd0,a[22:7]};
                    default:r_data=0;
                endcase
            end
            S_STORE:begin rf_a_addr={dst,1'b0}+{5'd0,limb};rf_we=1;rf_wdata=r[15:0];end
            M_CLEAR:begin rf_a_addr={dst,1'b0}+{5'd0,limb};rf_we=1;end
            M_WAIT,M_CAPTURE:begin
                rf_a_addr={sa,1'b0}+{5'd0,mi};rf_b_addr={sb,1'b0}+{5'd0,mj};
                if(state==M_CAPTURE)begin a_we=1;a_data={16'd0,rf_a_data};b_we=1;b_data={16'd0,rf_b_data};end
            end
            M_PRODUCT:begin
                aux_we=1;aux_data=product[31:16];b_we=1;b_data={16'd0,product[15:0]};carry_we=1;carry_data=0;
            end
            M_ACC_WAIT,M_ACC_CAPTURE:begin
                rf_a_addr={dst,1'b0}+{5'd0,mk};
                if(state==M_ACC_CAPTURE)begin a_we=1;a_data={16'd0,rf_a_data};end
            end
            M_ACC_EXEC:begin
                alu_a={16'd0,a[15:0]};alu_b={16'd0,b[15:0]};alu_carry=carry;
                r_we=1;r_data=alu_sum[31:0];carry_we=1;carry_data=alu_sum[16];
            end
            M_ACC_STORE:begin
                rf_a_addr={dst,1'b0}+{5'd0,mk};rf_we=1;rf_wdata=r[15:0];
                b_we=1;b_data=mk==product_limb?{16'd0,aux}:32'd0;
            end
            N_WAIT,N_CAPTURE:rf_a_addr={sa,1'b0};
            N_ROM_CAPTURE:begin r_we=1;r_data=norm_q;end
            P_WAIT,P_CAPTURE:begin
                rf_a_addr=physical_source;
                if(state==P_CAPTURE)begin r_we=1;r_data=pixel_shift?{11'd0,rf_a_data,5'd0}:{16'd0,rf_a_data};end
            end
            SM_WAIT,SM_CAPTURE:begin
                rf_a_addr={sa,1'b0};rf_b_addr=7'd60;
                if(state==SM_CAPTURE)begin
                    a_we=1;a_data={16'd0,rf_a_data};b_we=1;b_data={27'd0,(small_y?rf_b_data[9:5]:rf_b_data[4:0])};
                end
            end
            SM_RESULT:begin
                alu_a=product;alu_b=~{b[15:0],16'd0};alu_carry=1;r_we=1;
                r_data=small_negative?alu_sum[31:0]:product;
            end
            PIXEL_ZERO:begin rf_a_addr=7'd108+{5'd0,tap_index};rf_we=1;end
            REQUEST,RESPONSE:begin
                if((state==RESPONSE && I_pixel_valid)||(state==REQUEST && I_pixel_ready && I_pixel_valid))begin
                    rf_a_addr=7'd108+{5'd0,tap_index};rf_we=1;rf_wdata={8'd0,I_pixel_y8};
                end
            end
            RUN:case(step)
                P_PACK_BASE:begin r_we=1;r_data={b[20:5],a[20:5]};end
                P_PACK_FRACTION:begin r_we=1;r_data={22'd0,b[4:0],a[4:0]};end
                P_TAP_X:begin alu_a={{16{a[15]}},a[15:0]};alu_b={31'd0,tap_index[0]};end
                P_TAP_Y:begin alu_a={{16{a[31]}},a[31:16]};alu_b={31'd0,tap_index[1]};end
                P_BLEND_STATUS:begin r_we=1;r_data={8'd0,a[7:0],4'd0,O_tap_inside,2'd0,O_sample_complete,1'b1,4'd0};end
                P_OUTSIDE_STATUS:begin r_we=1;r_data=32'h00000010;end
                default:begin end
            endcase
            default:begin end
        endcase
        if(f_active)begin
            rf_a_addr=f_aa;rf_b_addr=f_ba;rf_we=f_we;rf_wdata=f_wd;
            a_we=f_aw;b_we=f_bw;r_we=f_rw;aux_we=f_xw;carry_we=f_cw;
            a_data=f_ad;b_data=f_bd;r_data=f_rd;aux_data=f_xd;carry_data=f_cd;
            alu_a=f_alu_a;alu_b=f_alu_b;alu_carry=f_ac;
        end
        if(cancel || (start && busy))begin
            rf_we=0;a_we=0;b_we=0;r_we=0;aux_we=0;carry_we=0;
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;step<=0;return_step<=0;dst<=0;sa<=0;sb<=0;limb<=0;axis<=0;mi<=0;mj<=0;mk<=0;
            tap_index<=0;clear_index<=0;const_code<=0;flags<=0;shift_code<=0;pair_high<=0;pair_alu<=0;op_sub<=0;
            norm_v<=0;small_y<=0;small_negative<=0;pixel_shift<=0;shift32_right<=0;inside_x<=0;
            physical_source<=0;wait_count<=0;norm_addr<=0;done<=0;valid<=0;error<=0;
            O_gray<=0;O_sample_complete<=0;O_tap_inside<=0;O_pixel_x<=0;O_pixel_y<=0;
        end else begin
            done<=0;valid<=0;
            if(state!=IDLE && state!=LOCKED && state!=DRAIN && (cancel||start))begin
                error<=cancel?4'd4:4'd6;O_sample_complete<=0;
                if(state==RESPONSE && !I_pixel_valid)begin state<=DRAIN;wait_count<=0;end
                else begin state<=IDLE;done<=1;end
            end else case(state)
                IDLE:if(start && !cancel)begin
                    error<=0;O_gray<=0;O_tap_inside<=0;O_sample_complete<=1;
                    clear_index<=0;state<=CLEAR_OUTPUT;
                end
                CLEAR_OUTPUT:if(clear_index==15)go(P_INPUT_READ);else clear_index<=clear_index+1'b1;
                RUN:case(step)
                    P_INPUT_READ:begin call_pair(0,1,P_INPUT_CHECK); end
                    P_INPUT_CHECK:begin if(a>=192 || b>=96)fail(1);else call_pair(2,2,P_FLAGS_CHECK); end
                    P_FLAGS_CHECK:begin flags<=a[2:0];
    if(a[1] && a[2])fail(1);
    else if(a[1])begin axis<=0;go(P_SLOPE_READ);end
    else if(a[0])go(P_NORM_U);else go(P_DIRECT_X_EXT); end
                    P_SLOPE_READ:begin call_pair(12+{slope_index,1'b0},13+{slope_index,1'b0},P_SLOPE_CHECK); end
                    P_SLOPE_CHECK:begin if(!(b==0 || b==32'hffffffff || (b==1 && a==0)))fail(7);
    else if(axis==3)begin axis<=0;if(flags[0])go(P_NORM_U);else go(P_DIRECT_X_EXT);end
    else begin axis<=axis+1'b1;go(P_SLOPE_READ);end end
                    P_NORM_U:begin call_norm(32,0,0,P_NORM_V); end
                    P_NORM_V:begin axis<=0;call_norm(33,1,1,P_FINE_A_EXT); end
                    P_FINE_A_EXT:begin call_ext32(45,fine_first,P_FINE_U_EXT); end
                    P_FINE_U_EXT:begin call_ext32(47,32,P_FINE_A_MUL); end
                    P_FINE_A_MUL:begin call_mul64(39,45,47,P_FINE_B_EXT); end
                    P_FINE_B_EXT:begin call_ext32(45,fine_first+1,P_FINE_V_EXT); end
                    P_FINE_V_EXT:begin call_ext32(47,33,P_FINE_B_MUL); end
                    P_FINE_B_MUL:begin call_mul64(49,45,47,P_FINE_SUM); end
                    P_FINE_SUM:begin call_add64(39,39,49,1'b0,P_FINE_SHIFT); end
                    P_FINE_SHIFT:begin call_shift64(45,39,SH_MINUS16,P_FINE_TRANS); end
                    P_FINE_TRANS:begin if(axis==2)call_const64(62,2,P_FINE_COMMIT);
    else call_ext32(47,fine_first+2,P_FINE_COMMIT); end
                    P_FINE_COMMIT:begin if(axis==2)call_add64(45,45,62,0,P_DEN_READ);
    else call_add64(axis==0?34:36,45,47,0,P_FINE_NEXT); end
                    P_FINE_NEXT:begin axis<=axis+1'b1;go(P_FINE_A_EXT); end
                    P_DEN_READ:begin call_pair(45,46,P_DEN_CHECK); end
                    P_DEN_CHECK:begin if(b!=0 || a<8388608 || a>25165824)fail(2);
    else call_mov32(38,45,P_FX_SHIFT); end
                    P_FX_SHIFT:begin call_shift64(45,34,SH_PLUS24,P_FX_DIV); end
                    P_FX_DIV:begin return_step<=P_FX_BIAS;state<=F_WAIT; end
                    P_FX_BIAS:begin call_const64(62,3,P_FX_ADD); end
                    P_FX_ADD:begin call_add64(41,51,62,1'b0,P_FY_SHIFT); end
                    P_FY_SHIFT:begin call_shift64(45,36,SH_PLUS24,P_FY_DIV); end
                    P_FY_DIV:begin return_step<=P_FY_BIAS;state<=F_WAIT; end
                    P_FY_BIAS:begin call_const64(62,4,P_FY_ADD); end
                    P_FY_ADD:begin call_add64(43,51,62,1'b0,P_PROJECT_X_COPY); end
                    P_DIRECT_X_EXT:begin call_ext32(41,0,P_DIRECT_X_SHIFT); end
                    P_DIRECT_X_SHIFT:begin call_shift64(41,41,SH_PLUS16,P_DIRECT_Y_EXT); end
                    P_DIRECT_Y_EXT:begin call_ext32(43,1,P_DIRECT_Y_SHIFT); end
                    P_DIRECT_Y_SHIFT:begin call_shift64(43,43,SH_PLUS16,P_PROJECT_X_COPY); end
                    P_PROJECT_X_COPY:begin call_mov32(28,41,P_PROJECT_Y_COPY); end
                    P_PROJECT_Y_COPY:begin call_mov32(29,43,P_PROJECT_X_READ); end
                    P_PROJECT_X_READ:begin call_pair(41,42,P_PROJECT_X_CHECK); end
                    P_PROJECT_X_CHECK:begin if(!((b==0 && a<=33554432)||(b==32'hffffffff && a>=32'hfe000000)))fail(7);
    else call_pair(43,44,P_PROJECT_Y_CHECK); end
                    P_PROJECT_Y_CHECK:begin if(!((b==0 && a<=33554432)||(b==32'hffffffff && a>=32'hfe000000)))fail(7);
    else if(flags[1])begin axis<=0;go(P_COARSE_A_MUL);end
    else if(flags[2])go(P_HALF_CONST);else go(P_PLAIN_X); end
                    P_COARSE_A_MUL:begin call_mul64(39,coarse_first,41,P_COARSE_B_MUL); end
                    P_COARSE_B_MUL:begin call_mul64(49,coarse_first+2,43,P_COARSE_SUM); end
                    P_COARSE_SUM:begin call_add64(39,39,49,1'b0,P_COARSE_SHIFT); end
                    P_COARSE_SHIFT:begin call_shift64(45,39,SH_MINUS16,P_COARSE_TRANS); end
                    P_COARSE_TRANS:begin call_add64(axis==0?24:26,45,coarse_first+4,0,P_COARSE_NEXT); end
                    P_COARSE_NEXT:begin if(axis==0)begin axis<=1;go(P_COARSE_A_MUL);end else begin axis<=0;go(P_ROUND_SHIFT);end end
                    P_HALF_CONST:begin call_const64(62,5,P_HALF_X_ADD); end
                    P_HALF_X_ADD:begin call_add64(45,41,62,1'b0,P_HALF_X_DIV); end
                    P_HALF_X_DIV:begin call_shift64(45,45,SH_MINUS1,P_HALF_X_SHIFT); end
                    P_HALF_X_SHIFT:begin call_shift64(24,45,SH_PLUS12,P_HALF_Y_ADD); end
                    P_HALF_Y_ADD:begin call_add64(45,43,62,1'b0,P_HALF_Y_DIV); end
                    P_HALF_Y_DIV:begin call_shift64(45,45,SH_MINUS1,P_HALF_Y_SHIFT); end
                    P_HALF_Y_SHIFT:begin call_shift64(26,45,SH_PLUS12,P_ROUND_START); end
                    P_PLAIN_X:begin call_shift64(24,41,SH_PLUS12,P_PLAIN_Y); end
                    P_PLAIN_Y:begin call_shift64(26,43,SH_PLUS12,P_ROUND_START); end
                    P_ROUND_START:begin axis<=0;go(P_ROUND_SHIFT); end
                    P_ROUND_SHIFT:begin call_shift64(axis==0?45:47,axis==0?24:26,SH_MINUS23,P_ROUND_READ); end
                    P_ROUND_READ:begin call_pair(axis==0?24:26,axis==0?24:26,P_ROUND_TEST); end
                    P_ROUND_TEST:begin if(a[22:0]>23'd4194304 || (a[22:0]==23'd4194304 && a[23]))call_const64(62,1,P_ROUND_ADD);
    else go(P_ROUND_NEXT); end
                    P_ROUND_ADD:begin call_add64(axis==0?45:47,axis==0?45:47,62,0,P_ROUND_NEXT); end
                    P_ROUND_NEXT:begin if(axis==0)begin axis<=1;go(P_ROUND_SHIFT);end else call_pair(45,46,P_COORD_X_CHECK); end
                    P_COORD_X_CHECK:begin if(!((b==0 && a<width_q5)||(b==32'hffffffff && a>=32'hffffffe0)))begin O_sample_complete<=0;go(P_OUTSIDE_STATUS);end
    else call_pair(47,48,P_COORD_Y_CHECK); end
                    P_COORD_Y_CHECK:begin if(!((b==0 && a<height_q5)||(b==32'hffffffff && a>=32'hffffffe0)))begin O_sample_complete<=0;go(P_OUTSIDE_STATUS);end
    else call_pair(45,47,P_PACK_BASE); end
                    P_PACK_BASE:begin call_store32(3,P_PACK_FRACTION); end
                    P_PACK_FRACTION:begin call_store32(30,P_TAPS_BEGIN); end
                    P_TAPS_BEGIN:begin tap_index<=0;go(P_TAP_READ); end
                    P_TAP_READ:begin call_pair(3,30,P_TAP_X); end
                    P_TAP_X:begin inside_x<=!alu_sum[31] && alu_sum[31:0]<width;O_pixel_x<=alu_sum[10:0];go(P_TAP_Y); end
                    P_TAP_Y:begin O_pixel_y<=alu_sum[9:0];O_tap_inside[tap_index]<=tap_in_bounds;
    if(!tap_in_bounds && !tap_zero)O_sample_complete<=0;
    if(!tap_in_bounds || tap_zero)state<=PIXEL_ZERO;
    else begin wait_count<=0;state<=REQUEST;end end
                    P_BLEND_ROW_BEGIN:begin axis<=0;go(P_BLEND_RIGHT); end
                    P_BLEND_RIGHT:begin call_pixel32(45,axis==0?109:111,0,P_BLEND_LEFT); end
                    P_BLEND_LEFT:begin call_pixel32(47,axis==0?108:110,0,P_BLEND_DIFF); end
                    P_BLEND_DIFF:begin call_add32(45,45,47,1,P_BLEND_MUL); end
                    P_BLEND_MUL:begin call_small_mul(49,45,0,P_BLEND_BASE); end
                    P_BLEND_BASE:begin call_pixel32(47,axis==0?108:110,1,P_BLEND_ADD); end
                    P_BLEND_ADD:begin call_add32(axis==0?56:58,49,47,0,P_BLEND_NEXT); end
                    P_BLEND_NEXT:begin if(axis==0)begin axis<=1;go(P_BLEND_RIGHT);end else go(P_BLEND_Y_DIFF); end
                    P_BLEND_Y_DIFF:begin call_add32(45,58,56,1,P_BLEND_Y_MUL); end
                    P_BLEND_Y_MUL:begin call_small_mul(49,45,1,P_BLEND_Y_BASE); end
                    P_BLEND_Y_BASE:begin call_shift32(45,56,0,P_BLEND_Y_ADD); end
                    P_BLEND_Y_ADD:begin call_add32(60,45,49,0,P_BLEND_ROUND); end
                    P_BLEND_ROUND:begin call_const64(47,6,P_BLEND_ROUND_ADD); end
                    P_BLEND_ROUND_ADD:begin call_add32(60,60,47,0,P_BLEND_FINAL_SHIFT); end
                    P_BLEND_FINAL_SHIFT:begin call_shift32(60,60,1,P_BLEND_GRAY_READ); end
                    P_BLEND_GRAY_READ:begin call_pair(60,60,P_BLEND_STATUS); end
                    P_BLEND_STATUS:begin O_gray<=a[7:0];call_store32(31,P_NORMAL_FINISH); end
                    P_OUTSIDE_STATUS:begin O_gray<=0;call_store32(31,P_NORMAL_FINISH); end
                    P_NORMAL_FINISH:begin done<=1;valid<=1;state<=IDLE; end
                    default:fail(15);
                endcase
                PAIR_WAIT:state<=PAIR_CAPTURE;
                PAIR_CAPTURE:if(pair_high)begin if(pair_alu)state<=A32_EXEC;else go(return_step);end
                else begin pair_high<=1;state<=PAIR_WAIT;end
                A32_EXEC:state<=WRITE_LOW;
                WRITE_LOW:state<=WRITE_HIGH;
                WRITE_HIGH:go(return_step);
                EXT_WAIT:state<=EXT_CAPTURE;
                EXT_CAPTURE:begin limb<=0;state<=EXT_STORE;end
                EXT_STORE:if(limb==3)go(return_step);else limb<=limb+1'b1;
                MOV_WAIT:state<=MOV_CAPTURE;
                MOV_CAPTURE:state<=WRITE_LOW;
                A64_PREP:state<=A64_WAIT;
                A64_WAIT:state<=A64_CAPTURE;
                A64_CAPTURE:state<=A64_EXEC;
                A64_EXEC:state<=A64_STORE;
                A64_STORE:if(limb==3)go(return_step);else begin limb<=limb+1'b1;state<=A64_WAIT;end
                CONST_STORE:if(limb==3)go(return_step);else limb<=limb+1'b1;
                S_WAIT:state<=S_CAPTURE;
                S_CAPTURE:state<=S_EXEC;
                S_EXEC:state<=S_STORE;
                S_STORE:if((shift_left && limb==0)||(!shift_left && limb==3))go(return_step);
                else begin limb<=shift_left?limb-1'b1:limb+1'b1;state<=S_WAIT;end
                M_CLEAR:if(limb==3)begin mi<=0;mj<=0;state<=M_WAIT;end else limb<=limb+1'b1;
                M_WAIT:state<=M_CAPTURE;
                M_CAPTURE:state<=M_PIPE;
                M_PIPE:state<=M_PRODUCT;
                M_PRODUCT:begin mk<=product_limb[1:0];state<=M_ACC_WAIT;end
                M_ACC_WAIT:state<=M_ACC_CAPTURE;
                M_ACC_CAPTURE:state<=M_ACC_EXEC;
                M_ACC_EXEC:state<=M_ACC_STORE;
                M_ACC_STORE:if(mk!=3)begin mk<=mk+1'b1;state<=M_ACC_WAIT;end
                else if(mj!=3-mi)begin mj<=mj+1'b1;state<=M_WAIT;end
                else if(mi!=3)begin mi<=mi+1'b1;mj<=0;state<=M_WAIT;end
                else go(return_step);
                N_WAIT:state<=N_CAPTURE;
                N_CAPTURE:begin norm_addr<=norm_v?9'd192+{2'd0,rf_a_data[6:0]}:{1'b0,rf_a_data[7:0]};state<=N_ROM_WAIT;end
                N_ROM_WAIT:state<=N_ROM_CAPTURE;
                N_ROM_CAPTURE:state<=WRITE_LOW;
                F_WAIT:if(f_done)begin if(f_fault!=0)fail(7);else go(return_step);end
                P_WAIT:state<=P_CAPTURE;
                P_CAPTURE:state<=WRITE_LOW;
                SM_WAIT:state<=SM_CAPTURE;
                SM_CAPTURE:begin small_negative<=rf_a_data[15];state<=SM_PIPE;end
                SM_PIPE:state<=SM_RESULT;
                SM_RESULT:state<=WRITE_LOW;
                S32_WAIT:state<=S32_CAPTURE;
                S32_CAPTURE:state<=WRITE_LOW;
                PIXEL_ZERO:next_tap();
                REQUEST:begin
                    if(I_pixel_ready)begin wait_count<=0;if(I_pixel_valid)next_tap();else state<=RESPONSE;end
                    else if(wait_count>=WAIT_TIMEOUT-1)begin state<=LOCKED;error<=3;done<=1;O_sample_complete<=0;end
                    else wait_count<=wait_count+1'b1;
                end
                RESPONSE:begin
                    if(I_pixel_valid)next_tap();
                    else if(wait_count>=WAIT_TIMEOUT-1)begin state<=LOCKED;error<=3;done<=1;O_sample_complete<=0;end
                    else wait_count<=wait_count+1'b1;
                end
                DRAIN:begin
                    if(I_pixel_valid)begin state<=IDLE;done<=1;end
                    else if(wait_count>=WAIT_TIMEOUT-1)begin state<=LOCKED;done<=1;error<=3;end
                    else wait_count<=wait_count+1'b1;
                end
                LOCKED:begin end
                default:begin state<=LOCKED;done<=1;error<=15;O_sample_complete<=0;end
            endcase
        end
    end
endmodule
