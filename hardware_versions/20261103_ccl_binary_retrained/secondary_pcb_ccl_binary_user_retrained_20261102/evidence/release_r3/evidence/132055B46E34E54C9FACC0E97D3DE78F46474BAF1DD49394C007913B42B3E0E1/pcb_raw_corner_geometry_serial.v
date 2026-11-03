`timescale 1ns/1ps
// Exact strict convexity of four already-safe Q28 raw corners, in cyclic
// TL/TR/BR/BL order. Each record is {Y_unsigned39,X_unsigned40}, lowest first.
// Safety bounds are checked again; no truncated outside-frame coordinate can
// be admitted. Cross signs use exact signed79 products, no float or DSP array.
module pcb_raw_corner_geometry_serial(
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [315:0] I_corners,
    output wire O_busy,
    output reg O_done,O_valid,O_convex,O_inside,
    output reg [3:0] O_error
);
    localparam IDLE=0,SET_FIRST=1,MULTIPLY=2,PRODUCT=3,SET_SECOND=4,COMPARE=5,FINISH=6;
    reg [2:0] state;
    reg [1:0] corner;
    reg second,negative,have_sign,cross_sign,all_nonzero;
    reg [78:0] shifted_a,accumulator;
    reg [38:0] bits;
    reg signed [78:0] product,first_product;
    // Owner holds its corner packet throughout O_busy, as for sampler config.
    wire [1:0] next_corner=corner+2'd1,after_corner=corner+2'd2;
    wire [39:0] ax=I_corners[79*corner+:40];
    wire [38:0] ay=I_corners[79*corner+40+:39];
    wire [39:0] bx=I_corners[79*next_corner+:40];
    wire [38:0] by=I_corners[79*next_corner+40+:39];
    wire [39:0] cx=I_corners[79*after_corner+:40];
    wire [38:0] cy=I_corners[79*after_corner+40+:39];
    wire signed [39:0] dx1=$signed(bx)-$signed(ax),dx2=$signed(cx)-$signed(bx);
    wire signed [38:0] dy1=$signed(by)-$signed(ay),dy2=$signed(cy)-$signed(by);
    wire signed [39:0] factor_a=second?dx2:dx1;
    wire signed [38:0] factor_b=second?dy1:dy2;
    wire [39:0] magnitude_a=factor_a[39]?(~factor_a+40'd1):factor_a;
    wire [38:0] magnitude_b=factor_b[38]?(~factor_b+39'd1):factor_b;
    wire safe_a=ax>=40'd268435456&&ax<=40'd343060512768&&
                ay>=39'd268435456&&ay<=39'd192736657408;
    wire cross_nonzero=first_product!=product;
    wire this_cross_sign=first_product>product;
    assign O_busy=state!=IDLE;
    task launch_product;
        begin
            shifted_a<={39'd0,magnitude_a};bits<=magnitude_b;accumulator<=0;
            negative<=factor_a[39]^factor_b[38];state<=MULTIPLY;
        end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;corner<=0;second<=0;negative<=0;have_sign<=0;cross_sign<=0;all_nonzero<=0;
            shifted_a<=0;accumulator<=0;bits<=0;product<=0;first_product<=0;
            O_done<=0;O_valid<=0;O_convex<=0;O_inside<=0;O_error<=0;
        end else begin
            O_done<=0;
            if(state!=IDLE&&(I_cancel||I_start))begin
                O_done<=1;O_valid<=0;O_convex<=0;O_inside<=0;
                O_error<=I_cancel?4'd4:4'd6;state<=IDLE;
            end else case(state)
                IDLE:if(I_start&&!I_cancel)begin
                    corner<=0;second<=0;have_sign<=0;cross_sign<=0;all_nonzero<=1;
                    O_valid<=0;O_convex<=0;O_inside<=1;O_error<=0;state<=SET_FIRST;
                end
                SET_FIRST:begin
                    if(!safe_a)O_inside<=0;
                    launch_product();
                end
                MULTIPLY:begin
                    if(bits==0)begin product<=negative?-$signed(accumulator):$signed(accumulator);state<=PRODUCT;end
                    else begin
                        if(bits[0])accumulator<=accumulator+shifted_a;
                        shifted_a<=shifted_a<<1;bits<=bits>>1;
                    end
                end
                PRODUCT:if(!second)begin first_product<=product;second<=1;state<=SET_SECOND;end
                        else state<=COMPARE;
                SET_SECOND:launch_product();
                COMPARE:begin
                    if(!cross_nonzero||(have_sign&&this_cross_sign!=cross_sign))all_nonzero<=0;
                    if(!have_sign)begin have_sign<=1;cross_sign<=this_cross_sign;end
                    if(corner==3)state<=FINISH;
                    else begin corner<=corner+2'd1;second<=0;state<=SET_FIRST;end
                end
                FINISH:begin O_done<=1;O_valid<=1;O_convex<=all_nonzero;state<=IDLE;end
                default:begin O_done<=1;O_valid<=0;O_error<=15;state<=IDLE;end
            endcase
        end
    end
endmodule
