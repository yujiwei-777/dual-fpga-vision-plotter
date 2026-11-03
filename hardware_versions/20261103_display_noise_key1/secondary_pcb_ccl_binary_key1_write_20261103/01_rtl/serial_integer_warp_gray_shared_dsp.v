`timescale 1ns/1ps
// Independent exact DSP area candidate derived from the qualified shared32
// sampler. One registered signed34x35 product replaces bit-serial multiplication;
// one32bit carry ALU still handles all wide additions and floor division.
// Division widths follow the full signed32 fine contract, not typical samples.
// Source, projection, Q5 nearest-even rounding, bilinear interpolation, and
// cancel/drain/timeout behavior remain unchanged. Not production-qualified.
module serial_integer_warp_gray_shared_dsp #(
    parameter integer WAIT_TIMEOUT=4096
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [7:0] I_x,input wire [6:0] I_y,
    input wire I_use_fine,I_apply_coarse,I_half_image,
    input wire [255:0] I_fine,input wire [239:0] I_coarse,
    output wire O_busy,output reg O_done,O_valid,output reg [3:0] O_error,
    output reg [7:0] O_gray,output reg O_sample_complete,
    output reg [3:0] O_tap_inside,output wire O_pixel_request,
    output reg [10:0] O_pixel_x,output reg [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,input wire [7:0] I_pixel_y8,
    output reg signed [31:0] O_project_x_q16,O_project_y_q16,
    output reg signed [63:0] O_source_x_q28,O_source_y_q28
);
    localparam IDLE=0,NORM_U=1,NORM_U_DONE=2,NORM_V_DONE=3,
      F_AX_DONE=4,F_BX_DONE=5,F_XSUM=6,F_NX=7,F_AY_DONE=8,F_BY_DONE=9,
      F_YSUM=10,F_NY=11,F_GP_DONE=12,F_HP_DONE=13,F_DSUM=14,F_DEN=15,
      PROJECT_X_DONE=16,PROJECT_XADD=17,PROJECT_Y_DONE=18,PROJECT_YADD=19,
      AFFINE=20,HALF_X=21,HALF_Y=22,C_AX_DONE=23,C_BX_DONE=24,C_XSUM=25,C_XFINAL=26,
      C_AY_DONE=27,C_BY_DONE=28,C_YSUM=29,C_YFINAL=30,
      ROUND_COORD=31,ROUND_X=32,ROUND_X_DONE=33,ROUND_Y=34,ROUND_Y_DONE=35,
      CHECK_COORD=36,TAP=37,REQUEST=38,RESPONSE=39,
      BLEND_X_INIT=40,BLEND_X=41,BLEND_Y_INIT=42,BLEND_Y=43,FINISH=44,
      MUL_ABSA=45,MUL_ABSA_DONE=46,MUL_ABSB=47,MUL_ABSB_DONE=48,
      MUL_LOOP=49,MUL_SUM=50,MUL_END=51,MUL_END_DONE=52,
      DIV_ABS=53,DIV_ABS_DONE=54,DIV_LOOP=55,DIV_STEP=56,DIV_END=57,DIV_END_DONE=58,
      ALU_LOW=59,ALU_HIGH=60,ARITH_RETURN=61,DRAIN=62,LOCKED=63;
    reg [5:0] state,return_state,alu_return;
    reg use_fine,apply_coarse,half_image;
    reg [7:0] point_x;reg [6:0] point_y;
    reg signed [16:0] u,v;
    reg signed [33:0] nx,ny;
    reg [24:0] den;
    reg signed [58:0] term;
    reg signed [34:0] xq,yq;
    reg signed [43:0] sx,sy;
    reg signed [20:0] x5,y5;
    // Fine numerator is strictly between +/-3*2^55, hence signed58.
    // Positive denominator is at most3*2^23; remainder<denominator.
    // The resulting positive quotient is below3*2^32, hence35 bits.
    reg [33:0] work_a;
    reg [57:0] work_bits;
    reg [25:0] work_acc;
    reg [34:0] work_q;
    reg div_negative;
    // Coarse slopes are admitted only within +/-2^32, requiring34
    // signed bits. Every second product operand is signed35 or less.
    // The DSP pipeline has no asynchronous reset. MUL_LOOP settles it
    // before MUL_END consumes the product, so stale data is never used.
    wire signed [33:0] dsp_a = $signed(work_a);
    wire signed [34:0] dsp_b = $signed(work_bits[34:0]);
    reg signed [68:0] dsp_product;
    always @(posedge I_clk) dsp_product <= dsp_a * dsp_b;
    reg [6:0] div_count;
    reg [63:0] alu_operand_a,alu_operand_b;
    reg [31:0] alu_low;
    reg alu_sub,alu_carry;
    reg signed [63:0] arith_result;
    wire [31:0] alu_a=state==ALU_LOW?alu_operand_a[31:0]:alu_operand_a[63:32];
    wire [31:0] alu_b_raw=state==ALU_LOW?alu_operand_b[31:0]:alu_operand_b[63:32];
    wire [31:0] alu_b=alu_sub?~alu_b_raw:alu_b_raw;
    wire [32:0] alu_sum={1'b0,alu_a}+{1'b0,alu_b}+alu_carry;
    wire [25:0] div_trial={work_acc[24:0],work_bits[57]};
    wire [34:0] div_next_q={work_q[33:0],alu_carry};
    reg signed [15:0] base_x,base_y;
    reg [4:0] fx,fy;reg [1:0] tap_index;
    reg [7:0] p00,p10,p01,p11;
    wire signed [16:0] tap_x=$signed(base_x)+(tap_index[0]?17'sd1:17'sd0);
    wire signed [16:0] tap_y=$signed(base_y)+(tap_index[1]?17'sd1:17'sd0);
    wire [10:0] width=apply_coarse?11'd1280:(half_image?11'd96:11'd192);
    wire [9:0] height=apply_coarse?10'd720:(half_image?10'd48:10'd96);
    wire tap_in_bounds=tap_x>=0&&tap_y>=0&&tap_x<$signed({1'b0,width})&&tap_y<$signed({1'b0,height});
    wire tap_zero=(tap_index[0]&&fx==0)||(tap_index[1]&&fy==0);
    wire round_x_up=sx[22:0]>23'd4194304||(sx[22:0]==23'd4194304&&sx[23]);
    wire round_y_up=sy[22:0]>23'd4194304||(sy[22:0]==23'd4194304&&sy[23]);
    wire signed [8:0] norm_x=$signed({1'b0,point_x})-9'sd96;
    wire signed [7:0] norm_y=$signed({1'b0,point_y})-8'sd48;
    localparam integer WAIT_BITS=WAIT_TIMEOUT>1?$clog2(WAIT_TIMEOUT):1;
    reg [WAIT_BITS-1:0] wait_count;reg [4:0] fraction;reg [2:0] blend_count;
    reg signed [14:0] top,bottom,dx_top,dx_bottom;
    reg signed [19:0] total,dy;
    wire transfer=O_pixel_request&&I_pixel_ready;
    wire response=(state==RESPONSE&&I_pixel_valid)||(transfer&&I_pixel_valid);
    assign O_busy=state!=IDLE;
    assign O_pixel_request=state==REQUEST&&!I_cancel&&!I_start;
    function signed [63:0] wide32;
        input [31:0] value;begin wide32={{32{value[31]}},value};end
    endfunction
    function signed [63:0] wide40;
        input [39:0] value;begin wide40={{24{value[39]}},value};end
    endfunction
    function legal_slope;
        input signed [39:0] value;
        begin legal_slope=value>=-40'sd4294967296&&value<=40'sd4294967296;end
    endfunction
    task alu;
        input signed [63:0] a,b;input subtract,initial_carry;input [5:0] next_state;
        begin
            alu_operand_a<=a;alu_operand_b<=b;alu_sub<=subtract;alu_carry<=initial_carry;
            alu_return<=next_state;state<=ALU_LOW;
        end
    endtask
    task multiply;
        input signed [63:0] a,b;input [5:0] next_state;
        begin
            work_a<=a[33:0];work_bits<=b[57:0];
            return_state<=next_state;state<=MUL_LOOP;
        end
    endtask
    task divide_floor;
        input signed [63:0] numerator;input [63:0] denominator;input [5:0] next_state;
        begin
            work_bits<=numerator;work_a<=denominator;work_acc<=0;work_q<=0;
            div_negative<=numerator[63];div_count<=58;return_state<=next_state;state<=DIV_ABS;
        end
    endtask
    task next_tap;
        begin if(tap_index==3)state<=BLEND_X_INIT;else begin tap_index<=tap_index+1'b1;state<=TAP;end end
    endtask
    task accept_pixel;
        begin
            case(tap_index)0:p00<=I_pixel_y8;1:p10<=I_pixel_y8;2:p01<=I_pixel_y8;3:p11<=I_pixel_y8;endcase
            next_tap();
        end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;return_state<=IDLE;alu_return<=IDLE;
            use_fine<=0;apply_coarse<=0;half_image<=0;point_x<=0;point_y<=0;
            u<=0;v<=0;nx<=0;ny<=0;den<=0;term<=0;xq<=0;yq<=0;sx<=0;sy<=0;x5<=0;y5<=0;
            work_a<=0;work_bits<=0;work_acc<=0;work_q<=0;div_negative<=0;div_count<=0;
            alu_operand_a<=0;alu_operand_b<=0;alu_low<=0;alu_sub<=0;alu_carry<=0;arith_result<=0;
            base_x<=0;base_y<=0;fx<=0;fy<=0;tap_index<=0;p00<=0;p10<=0;p01<=0;p11<=0;
            wait_count<=0;fraction<=0;blend_count<=0;top<=0;bottom<=0;dx_top<=0;dx_bottom<=0;total<=0;dy<=0;
            O_done<=0;O_valid<=0;O_error<=0;O_gray<=0;O_sample_complete<=0;O_tap_inside<=0;
            O_pixel_x<=0;O_pixel_y<=0;O_project_x_q16<=0;O_project_y_q16<=0;O_source_x_q28<=0;O_source_y_q28<=0;
        end else begin
            O_done<=0;O_valid<=0;
            if(state!=IDLE&&state!=LOCKED&&state!=DRAIN&&(I_cancel||I_start))begin
                O_error<=I_cancel?4'd4:4'd6;O_sample_complete<=0;
                if(state==RESPONSE&&!I_pixel_valid)begin state<=DRAIN;wait_count<=0;end
                else begin state<=IDLE;O_done<=1;end
            end else case(state)
                IDLE:if(I_start&&!I_cancel)begin
                    O_error<=0;O_gray<=0;O_tap_inside<=0;O_sample_complete<=1;
                    p00<=0;p10<=0;p01<=0;p11<=0;tap_index<=0;
                    use_fine<=I_use_fine;apply_coarse<=I_apply_coarse;half_image<=I_half_image;point_x<=I_x;point_y<=I_y;
                    if(I_x>=192||I_y>=96||(I_apply_coarse&&I_half_image))begin O_error<=1;O_sample_complete<=0;O_done<=1;end
                    else if(I_apply_coarse&&(!legal_slope(I_coarse[39:0])||!legal_slope(I_coarse[79:40])||
                        !legal_slope(I_coarse[159:120])||!legal_slope(I_coarse[199:160])))begin O_error<=7;O_sample_complete<=0;O_done<=1;end
                    else if(I_use_fine)state<=NORM_U;
                    else begin xq<=$signed({1'b0,I_x,16'd0});yq<=$signed({1'b0,I_y,16'd0});state<=AFFINE;end
                end
                NORM_U:divide_floor($signed({{39{norm_x[8]}},norm_x,16'd0}),64'd96,NORM_U_DONE);
                NORM_U_DONE:begin u<=arith_result[16:0];divide_floor($signed({{40{norm_y[7]}},norm_y,16'd0}),64'd48,NORM_V_DONE);end
                NORM_V_DONE:begin v<=arith_result[16:0];multiply(wide32(I_fine[31:0]),u,F_AX_DONE);end
                F_AX_DONE:begin term<=arith_result[58:0];multiply(wide32(I_fine[63:32]),v,F_BX_DONE);end
                F_BX_DONE:alu(term,arith_result,0,0,F_XSUM);
                F_XSUM:alu(arith_result>>>16,wide32(I_fine[95:64]),0,0,F_NX);
                F_NX:begin nx<=arith_result[33:0];multiply(wide32(I_fine[127:96]),u,F_AY_DONE);end
                F_AY_DONE:begin term<=arith_result[58:0];multiply(wide32(I_fine[159:128]),v,F_BY_DONE);end
                F_BY_DONE:alu(term,arith_result,0,0,F_YSUM);
                F_YSUM:alu(arith_result>>>16,wide32(I_fine[191:160]),0,0,F_NY);
                F_NY:begin ny<=arith_result[33:0];multiply(wide32(I_fine[223:192]),u,F_GP_DONE);end
                F_GP_DONE:begin term<=arith_result[58:0];multiply(wide32(I_fine[255:224]),v,F_HP_DONE);end
                F_HP_DONE:alu(term,arith_result,0,0,F_DSUM);
                F_DSUM:alu(64'sd16777216,arith_result>>>16,0,0,F_DEN);
                F_DEN:begin
                    if(arith_result<64'sd8388608||arith_result>64'sd25165824)begin O_error<=2;O_done<=1;O_sample_complete<=0;state<=IDLE;end
                    else begin den<=arith_result[24:0];divide_floor($signed({{30{nx[33]}},nx})<<<24,arith_result,PROJECT_X_DONE);end
                end
                PROJECT_X_DONE:alu(64'sd6291456,arith_result,0,0,PROJECT_XADD);
                PROJECT_XADD:begin xq<=arith_result[34:0];divide_floor($signed({{30{ny[33]}},ny})<<<24,{39'd0,den},PROJECT_Y_DONE);end
                PROJECT_Y_DONE:alu(64'sd3145728,arith_result,0,0,PROJECT_YADD);
                PROJECT_YADD:begin yq<=arith_result[34:0];state<=AFFINE;end
                AFFINE:begin
                    O_project_x_q16<=xq[31:0];O_project_y_q16<=yq[31:0];
                    if(xq<-35'sd33554432||xq>35'sd33554432||yq<-35'sd33554432||yq>35'sd33554432)begin
                        O_error<=7;O_done<=1;O_sample_complete<=0;state<=IDLE;
                    end else if(apply_coarse)multiply(wide40(I_coarse[39:0]),xq,C_AX_DONE);
                    else if(half_image)alu(xq,64'sd32768,1,1,HALF_X);
                    else begin sx<=xq<<<12;sy<=yq<<<12;state<=ROUND_COORD;end
                end
                HALF_X:begin sx<=(arith_result>>>1)<<<12;alu(yq,64'sd32768,1,1,HALF_Y);end
                HALF_Y:begin sy<=(arith_result>>>1)<<<12;state<=ROUND_COORD;end
                C_AX_DONE:begin term<=arith_result[58:0];multiply(wide40(I_coarse[79:40]),yq,C_BX_DONE);end
                C_BX_DONE:alu(term,arith_result,0,0,C_XSUM);
                C_XSUM:alu(arith_result>>>16,wide40(I_coarse[119:80]),0,0,C_XFINAL);
                C_XFINAL:begin sx<=arith_result[43:0];multiply(wide40(I_coarse[159:120]),xq,C_AY_DONE);end
                C_AY_DONE:begin term<=arith_result[58:0];multiply(wide40(I_coarse[199:160]),yq,C_BY_DONE);end
                C_BY_DONE:alu(term,arith_result,0,0,C_YSUM);
                C_YSUM:alu(arith_result>>>16,wide40(I_coarse[239:200]),0,0,C_YFINAL);
                C_YFINAL:begin sy<=arith_result[43:0];state<=ROUND_COORD;end
                ROUND_COORD:begin O_source_x_q28<=sx;O_source_y_q28<=sy;state<=ROUND_X;end
                ROUND_X:begin
                    if(round_x_up)alu(sx>>>23,64'd1,0,0,ROUND_X_DONE);
                    else begin x5<=sx>>>23;state<=ROUND_Y;end
                end
                ROUND_X_DONE:begin x5<=arith_result[20:0];state<=ROUND_Y;end
                ROUND_Y:begin
                    if(round_y_up)alu(sy>>>23,64'd1,0,0,ROUND_Y_DONE);
                    else begin y5<=sy>>>23;state<=CHECK_COORD;end
                end
                ROUND_Y_DONE:begin y5<=arith_result[20:0];state<=CHECK_COORD;end
                CHECK_COORD:begin
                    base_x<=x5>>>5;base_y<=y5>>>5;fx<=x5[4:0];fy<=y5[4:0];
                    if(x5<-21'sd32||y5<-21'sd32||x5>=($signed({1'b0,width})<<<5)||y5>=($signed({1'b0,height})<<<5))begin
                        O_gray<=0;O_sample_complete<=0;state<=FINISH;
                    end else state<=TAP;
                end
                TAP:begin
                    O_tap_inside[tap_index]<=tap_in_bounds;if(!tap_in_bounds&&!tap_zero)O_sample_complete<=0;
                    if(tap_zero||!tap_in_bounds)next_tap();
                    else begin O_pixel_x<=tap_x[10:0];O_pixel_y<=tap_y[9:0];wait_count<=0;state<=REQUEST;end
                end
                REQUEST:begin
                    if(transfer)begin wait_count<=0;if(response)accept_pixel();else state<=RESPONSE;end
                    else if(wait_count>=WAIT_TIMEOUT-1)begin state<=LOCKED;O_error<=3;O_done<=1;O_sample_complete<=0;end
                    else wait_count<=wait_count+1'b1;
                end
                RESPONSE:begin
                    if(response)accept_pixel();
                    else if(wait_count>=WAIT_TIMEOUT-1)begin state<=LOCKED;O_error<=3;O_done<=1;O_sample_complete<=0;end
                    else wait_count<=wait_count+1'b1;
                end
                BLEND_X_INIT:begin
                    top<=$signed({1'b0,p00,5'b0});bottom<=$signed({1'b0,p01,5'b0});
                    dx_top<=$signed({1'b0,p10})-$signed({1'b0,p00});dx_bottom<=$signed({1'b0,p11})-$signed({1'b0,p01});
                    fraction<=fx;blend_count<=0;state<=BLEND_X;
                end
                BLEND_X:begin
                    if(fraction[0])begin top<=top+dx_top;bottom<=bottom+dx_bottom;end
                    dx_top<=dx_top<<<1;dx_bottom<=dx_bottom<<<1;fraction<=fraction>>1;
                    if(blend_count==4)state<=BLEND_Y_INIT;else blend_count<=blend_count+1'b1;
                end
                BLEND_Y_INIT:begin total<=$signed(top)<<<5;dy<=bottom-top;fraction<=fy;blend_count<=0;state<=BLEND_Y;end
                BLEND_Y:begin
                    if(fraction[0])total<=total+dy;dy<=dy<<<1;fraction<=fraction>>1;
                    if(blend_count==4)begin O_gray<=((total+(fraction[0]?dy:20'sd0)+20'sd512)>>>10);state<=FINISH;end
                    else blend_count<=blend_count+1'b1;
                end
                FINISH:begin O_done<=1;O_valid<=1;state<=IDLE;end
                MUL_LOOP:state<=MUL_END;
                MUL_END:begin
                    arith_result<=dsp_product[63:0];state<=ARITH_RETURN;
                end
                DIV_ABS:begin if(div_negative)alu(0,work_bits,1,1,DIV_ABS_DONE);else state<=DIV_LOOP;end
                DIV_ABS_DONE:begin work_bits<=arith_result;state<=DIV_LOOP;end
                DIV_LOOP:alu(div_trial,work_a,1,1,DIV_STEP);
                DIV_STEP:begin
                    work_acc<=alu_carry?arith_result:div_trial;work_q<=div_next_q;work_bits<=work_bits<<1;
                    if(div_count==1)state<=DIV_END;else begin div_count<=div_count-1'b1;state<=DIV_LOOP;end
                end
                DIV_END:begin
                    if(div_negative)alu(0,work_q,1,work_acc==0,DIV_END_DONE);
                    else begin arith_result<=work_q;state<=ARITH_RETURN;end
                end
                DIV_END_DONE:state<=ARITH_RETURN;
                ALU_LOW:begin alu_low<=alu_sum[31:0];alu_carry<=alu_sum[32];state<=ALU_HIGH;end
                ALU_HIGH:begin arith_result<={alu_sum[31:0],alu_low};alu_carry<=alu_sum[32];state<=alu_return;end
                ARITH_RETURN:state<=return_state;
                DRAIN:begin
                    if(I_pixel_valid)begin state<=IDLE;O_done<=1;end
                    else if(wait_count>=WAIT_TIMEOUT-1)begin state<=LOCKED;O_done<=1;O_error<=3;end
                    else wait_count<=wait_count+1'b1;
                end
                LOCKED:begin end
                default:begin O_error<=15;O_done<=1;state<=LOCKED;end
            endcase
        end
    end
endmodule
