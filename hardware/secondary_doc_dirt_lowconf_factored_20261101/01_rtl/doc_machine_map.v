`timescale 1ns/1ps
// Shared serial machine-coordinate mapper.
//
// The planner and GRBL plotter never need this service at the same time:
// planning (including route-cost measurements) completes before drawing
// starts.  One request is therefore sufficient and keeps the exact integer
// mapping in one implementation.  X uses 19000/319 and Y uses 10688/179,
// with the same round-to-nearest constants as the former two modules.
module doc_machine_map(
    input wire clk,input wire rst_n,input wire cancel,
    input wire map_start,input wire [8:0] map_x,input wire [8:0] map_y,
    output reg [15:0] map_x_cmm,map_y_cmm,output reg map_done,
    input wire dist_start,input wire [8:0] dist_ax,dist_ay,dist_bx,dist_by,
    input wire dist_a_origin,
    output wire dist_busy,output reg dist_done,
    output reg [31:0] dist_distance,output reg [32:0] dist_squared
);
    localparam [3:0] ST_IDLE=4'd0,ST_SCALE=4'd1,ST_DIV=4'd2,
                     ST_DIST_PREP=4'd3,ST_DIST_MUL=4'd4,
                     ST_DIST_SQ=4'd5,ST_DIST_ROOT=4'd6,ST_DIST_DONE=4'd7;
    reg [3:0] state;
    reg mode_dist;
    reg [2:0] coord_index;
    reg [3:0] scale_term;
    reg [23:0] scale_acc,scaled_num;
    reg [8:0] ax_q,ay_q,bx_q,by_q;
    reg origin_q;
    reg [23:0] dividend,quotient;
    reg [10:0] remainder;
    reg [5:0] div_count;
    reg [15:0] ax_m,ay_m,bx_m,by_m;
    reg signed [17:0] dx,dy;
    reg [35:0] xx,yy;
    reg [33:0] rad,root_rem;
    reg [16:0] root;
    reg [5:0] root_count;

    wire [8:0] scale_value = !mode_dist ?
                              (coord_index==0 ? ax_q : ay_q) :
                              (coord_index==0 ? ax_q :
                               coord_index==1 ? ay_q :
                               coord_index==2 ? bx_q : by_q);
    wire scale_y = !mode_dist ? (coord_index==1) : coord_index[0];
    // X=19000 = 2^14+2^11+2^9+2^5+2^4+2^3.
    // Y=10688 = 2^13+2^11+2^8+2^7+2^6.
    wire [3:0] scale_last_term = scale_y ? 4'd8 : 4'd6;
    wire [23:0] scale_sum = scale_acc + scale_term_value(scale_y,scale_term,scale_value);
    wire [10:0] divisor = scale_y ? 11'd179 : 11'd319;
    wire [11:0] div_next_remainder = {remainder,dividend[23]};
    wire div_subtract = div_next_remainder >= divisor;
    wire [23:0] div_next_quotient = {quotient[22:0],div_subtract};
    wire [33:0] root_next_remainder = {root_rem[31:0],rad[33:32]};
    wire [33:0] root_trial = {15'd0,root,2'b01};

    function [8:0] clamp_x;
        input [8:0] value;
        begin clamp_x=(value>9'd319)?9'd319:value; end
    endfunction
    function [8:0] clamp_y;
        input [8:0] value;
        begin
            if(value<9'd70) clamp_y=9'd0;
            else if(value>9'd249) clamp_y=9'd179;
            else clamp_y=value-9'd70;
        end
    endfunction
    function [23:0] scale_term_value;
        input y_axis; input [3:0] term; input [8:0] value;
        reg [23:0] value_ext;
        begin
            value_ext={15'd0,value};
            scale_term_value=24'd0;
            if(!y_axis) begin
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

    assign dist_busy=mode_dist && (state!=ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;mode_dist<=0;coord_index<=0;scale_term<=0;
            scale_acc<=0;scaled_num<=0;ax_q<=0;ay_q<=0;bx_q<=0;by_q<=0;
            origin_q<=0;dividend<=0;quotient<=0;remainder<=0;div_count<=0;
            ax_m<=0;ay_m<=0;bx_m<=0;by_m<=0;dx<=0;dy<=0;xx<=0;yy<=0;
            rad<=0;root_rem<=0;root<=0;root_count<=0;
            map_x_cmm<=0;map_y_cmm<=0;map_done<=0;dist_done<=0;
            dist_distance<=0;dist_squared<=0;
        end else begin
            map_done<=0;dist_done<=0;
            if(cancel) begin
                state<=ST_IDLE;mode_dist<=0;
            end else begin
                case(state)
                    ST_IDLE: begin
                        if(dist_start) begin
                            mode_dist<=1;coord_index<=0;scale_term<=0;scale_acc<=0;
                            ax_q<=clamp_x(dist_ax);ay_q<=clamp_y(dist_ay);
                            bx_q<=clamp_x(dist_bx);by_q<=clamp_y(dist_by);
                            origin_q<=dist_a_origin;state<=ST_SCALE;
                        end else if(map_start) begin
                            mode_dist<=0;coord_index<=0;scale_term<=0;scale_acc<=0;
                            ax_q<=clamp_x(map_x);ay_q<=clamp_y(map_y);state<=ST_SCALE;
                        end
                    end
                    ST_SCALE: begin
                        if(scale_term==scale_last_term) begin
                            scaled_num<=scale_sum;dividend<=scale_sum;quotient<=0;
                            remainder<=0;div_count<=0;scale_term<=0;scale_acc<=0;
                            state<=ST_DIV;
                        end else begin
                            scale_acc<=scale_sum;scale_term<=scale_term+1'b1;
                        end
                    end
                    ST_DIV: begin
                        dividend<=dividend<<1;quotient<=div_next_quotient;
                        if(div_subtract) remainder<=div_next_remainder-divisor;
                        else remainder<=div_next_remainder[10:0];
                        if(div_count==6'd23) begin
                            if(!mode_dist) begin
                                if(coord_index==0) begin
                                    map_x_cmm<=16'd1000+div_next_quotient[15:0];
                                    coord_index<=1;state<=ST_SCALE;
                                end else begin
                                    map_y_cmm<=16'd1000+div_next_quotient[15:0];
                                    map_done<=1;state<=ST_IDLE;
                                end
                            end else begin
                                case(coord_index)
                                    0:ax_m<=div_next_quotient[15:0];
                                    1:ay_m<=div_next_quotient[15:0];
                                    2:bx_m<=div_next_quotient[15:0];
                                    default:by_m<=div_next_quotient[15:0];
                                endcase
                                if(coord_index==3) state<=ST_DIST_PREP;
                                else begin coord_index<=coord_index+1'b1;state<=ST_SCALE;end
                            end
                        end else div_count<=div_count+1'b1;
                    end
                    ST_DIST_PREP: begin
                        dx<=$signed({1'b0,16'd1000+bx_m})-
                           (origin_q?18'sd0:$signed({1'b0,16'd1000+ax_m}));
                        dy<=$signed({1'b0,16'd1000+by_m})-
                           (origin_q?18'sd0:$signed({1'b0,16'd1000+ay_m}));
                        state<=ST_DIST_MUL;
                    end
                    ST_DIST_MUL: begin xx<=dx*dx;yy<=dy*dy;state<=ST_DIST_SQ;end
                    ST_DIST_SQ: begin
                        dist_squared<=xx+yy;rad<=xx+yy;root_rem<=0;root<=0;
                        root_count<=0;state<=ST_DIST_ROOT;
                    end
                    ST_DIST_ROOT: begin
                        rad<={rad[31:0],2'b00};
                        if(root_next_remainder>=root_trial) begin
                            root_rem<=root_next_remainder-root_trial;
                            root<={root[15:0],1'b1};
                        end else begin
                            root_rem<=root_next_remainder;root<={root[15:0],1'b0};
                        end
                        if(root_count==6'd16) state<=ST_DIST_DONE;
                        else root_count<=root_count+1'b1;
                    end
                    ST_DIST_DONE: begin
                        dist_distance<={15'd0,root};dist_done<=1;
                        state<=ST_IDLE;mode_dist<=0;
                    end
                    default: state<=ST_IDLE;
                endcase
            end
        end
    end
endmodule
