`timescale 1ns/1ps
// Exact machine-coordinate mapping, followed by floor(sqrt(dx*dx+dy*dy)).
// The divider and square root are serial; this is a distance in 0.01 mm,
// never a sum of squared distances used as a substitute for route length.
module doc_path_distance(
    input wire clk,input wire rst_n,input wire start,input wire cancel,
    input wire [8:0] ax,ay,bx,by,input wire a_origin,
    output reg busy,output reg done,output reg [31:0] distance,
    output reg [32:0] squared
);
    reg [2:0] state;
    reg [5:0] count;
    reg [23:0] anum,bnum,aynum,bynum;
    reg [8:0] arem,brem,ayrem,byrem;
    reg [23:0] aquot,bquot,ayquot,byquot;
    reg origin_q;
    reg signed [17:0] dx,dy;
    reg [35:0] xx,yy;
    reg [33:0] rad,rem;
    reg [16:0] root;
    reg [1:0] scale_coord;
    reg [3:0] scale_term;
    reg [23:0] scale_acc;
    reg [8:0] ax_q,bx_q,ay_q,by_q;
    wire [9:0] anext={arem,anum[23]};
    wire [9:0] bnext={brem,bnum[23]};
    wire [9:0] aynext={ayrem,aynum[23]};
    wire [9:0] bynext={byrem,bynum[23]};
    wire [33:0] rnext={rem[31:0],rad[33:32]};
    wire [33:0] trial={15'd0,root,2'b01};
    // Exact machine mapping for the denser 320x180 raster. The four fixed
    // products share one adder over several cycles to reduce slice use.
    wire [8:0] ax_span=ax > 9'd319 ? 9'd319 : ax;
    wire [8:0] bx_span=bx > 9'd319 ? 9'd319 : bx;
    wire [8:0] ay_span=ay < 9'd70 ? 9'd0 : (ay > 9'd249 ? 9'd179 : ay-9'd70);
    wire [8:0] by_span=by < 9'd70 ? 9'd0 : (by > 9'd249 ? 9'd179 : by-9'd70);
    wire [8:0] scale_value=scale_coord==0?ax_q:
                           scale_coord==1?bx_q:
                           scale_coord==2?ay_q:by_q;
    wire scale_last=(scale_coord<2)?(scale_term==6):(scale_term==8);
    reg [23:0] scale_sum;
    function [23:0] scale_term_value;
        input [1:0] coord;
        input [3:0] term;
        input [8:0] value;
        reg [23:0] value_ext;
        begin
            value_ext={15'd0,value};
            scale_term_value=24'd0;
            if(coord<2) begin
                case(term)
                    0:scale_term_value=value_ext<<14;
                    1:scale_term_value=value_ext<<11;
                    2:scale_term_value=value_ext<<9;
                    3:scale_term_value=value_ext<<5;
                    4:scale_term_value=value_ext<<4;
                    5:scale_term_value=value_ext<<3;
                    default:scale_term_value=24'd159;
                endcase
            end else begin
                case(term)
                    0:scale_term_value=value_ext<<13;
                    1:scale_term_value=value_ext<<11;
                    2:scale_term_value=value_ext<<8;
                    3:scale_term_value=value_ext<<7;
                    4:scale_term_value=value_ext<<6;
                    5:scale_term_value=24'd0;
                    6:scale_term_value=24'd0;
                    7:scale_term_value=24'd0;
                    default:scale_term_value=24'd89;
                endcase
            end
        end
    endfunction
    always @* scale_sum=scale_acc+scale_term_value(scale_coord,scale_term,scale_value);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0;busy<=0;done<=0;distance<=0;squared<=0;
            count<=0;anum<=0;bnum<=0;aynum<=0;bynum<=0;
            scale_coord<=0;scale_term<=0;scale_acc<=0;
            ax_q<=0;bx_q<=0;ay_q<=0;by_q<=0;
            arem<=0;brem<=0;ayrem<=0;byrem<=0;
            aquot<=0;bquot<=0;ayquot<=0;byquot<=0;
            origin_q<=0;dx<=0;dy<=0;xx<=0;yy<=0;
            rad<=0;rem<=0;root<=0;
        end else begin
            done<=0;
            if(cancel) begin state<=0;busy<=0;end
            else case(state)
                0: if(start) begin
                    ax_q<=ax_span;bx_q<=bx_span;ay_q<=ay_span;by_q<=by_span;
                    scale_coord<=0;scale_term<=0;scale_acc<=0;
                    origin_q<=a_origin;busy<=1;state<=7;
                end
                7: begin
                    if(scale_last) begin
                        case(scale_coord)
                            0:anum<=scale_sum;
                            1:bnum<=scale_sum;
                            2:aynum<=scale_sum;
                            default:bynum<=scale_sum;
                        endcase
                        scale_acc<=0;scale_term<=0;
                        if(scale_coord==3) begin
                            arem<=0;brem<=0;ayrem<=0;byrem<=0;
                            aquot<=0;bquot<=0;ayquot<=0;byquot<=0;count<=24;state<=1;
                        end else scale_coord<=scale_coord+1'b1;
                    end else begin
                        scale_acc<=scale_sum;scale_term<=scale_term+1'b1;
                    end
                end
                1: begin
                    anum<={anum[22:0],1'b0};bnum<={bnum[22:0],1'b0};
                    aynum<={aynum[22:0],1'b0};bynum<={bynum[22:0],1'b0};
                    if(anext>=319) begin arem<=anext-10'd319;aquot<={aquot[22:0],1'b1};end
                    else begin arem<=anext[8:0];aquot<={aquot[22:0],1'b0};end
                    if(bnext>=319) begin brem<=bnext-10'd319;bquot<={bquot[22:0],1'b1};end
                    else begin brem<=bnext[8:0];bquot<={bquot[22:0],1'b0};end
                    if(aynext>=179) begin ayrem<=aynext-9'd179;ayquot<={ayquot[22:0],1'b1};end
                    else begin ayrem<=aynext[7:0];ayquot<={ayquot[22:0],1'b0};end
                    if(bynext>=179) begin byrem<=bynext-9'd179;byquot<={byquot[22:0],1'b1};end
                    else begin byrem<=bynext[7:0];byquot<={byquot[22:0],1'b0};end
                    if(count==1) state<=2;else count<=count-1'b1;
                end
                2: begin
                    dx<=$signed({1'b0,16'd1000+bquot[15:0]})-
                        (origin_q?18'sd0:$signed({1'b0,16'd1000+aquot[15:0]}));
                    dy<=$signed({1'b0,16'd1000+byquot[15:0]})-
                        (origin_q?18'sd0:$signed({1'b0,16'd1000+ayquot[15:0]}));
                    state<=3;
                end
                3: begin xx<=dx*dx;yy<=dy*dy;state<=4;end
                4: begin
                    squared<=xx+yy;rad<=xx+yy;rem<=0;root<=0;count<=17;state<=5;
                end
                5: begin
                    rad<={rad[31:0],2'b00};
                    if(rnext>=trial) begin rem<=rnext-trial;root<={root[15:0],1'b1};end
                    else begin rem<=rnext;root<={root[15:0],1'b0};end
                    if(count==1) state<=6;else count<=count-1'b1;
                end
                6: begin distance<={15'd0,root};done<=1;busy<=0;state<=0;end
                default: state<=0;
            endcase
        end
    end
endmodule
