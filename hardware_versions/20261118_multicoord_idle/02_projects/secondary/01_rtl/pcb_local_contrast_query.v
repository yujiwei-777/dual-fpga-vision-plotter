`timescale 1ns/1ps
// Standalone v5 observed() query for one registered 192x96 Y8 position.
// No registration, image buffer, DDR integration, or whole-PCB decision.
// The caller MUST choose a query_id not reused while ANY old response with
// that ID might arrive. Across module reset, preserve caller epoch or drain
// the complete external read path first. Reset alone cannot prevent ID reuse.
// Request tag={query_id,read_index[8:0]}; the responder echoes it unchanged.
// One request is outstanding. req_ready and rsp_valid are independent;
// matching same-cycle responses are supported. Unmatched responses are ignored.
module pcb_local_contrast_query #(
    parameter integer READ_TIMEOUT_CYCLES = 1024
) (
    input  wire         I_clk,
    input  wire         I_rst_n,
    input  wire         I_start,
    input  wire         I_cancel,
    input  wire [31:0]  I_query_id,
    input  wire [7:0]   I_x,
    input  wire [6:0]   I_y,
    output wire        O_rd_req_valid,
    input  wire         I_rd_req_ready,
    output wire [14:0] O_rd_req_addr,
    output wire [40:0] O_rd_req_tag,
    input  wire         I_rd_rsp_valid,
    input  wire [40:0] I_rd_rsp_tag,
    input  wire [7:0]  I_rd_rsp_data,
    output wire        O_busy,
    output reg         O_done,
    output reg         O_result_valid,
    output reg [3:0]   O_error, // 0 none,1 invalid xy,2 busy start,
                              // 3 request timeout,4 response timeout
    output reg [7:0]   O_observed,
    output reg [8:0]   O_read_count,
    output reg [31:0]  O_cycles
);
    localparam IDLE=3'd0, REQUEST=3'd1, RESPONSE=3'd2,
               EVALUATE=3'd3, DIVIDE=3'd4, ADVANCE=3'd5;
    reg [2:0] state;
    reg [31:0] query_id;
    reg [7:0] query_x;
    reg [6:0] query_y;
    reg [1:0] candidate_x,candidate_y;
    reg [2:0] window_x,window_y;
    reg [8:0] read_index,read_count;
    reg [13:0] sum7;
    reg [11:0] sum3;
    reg [7:0] maximum,candidate_value;
    reg [31:0] watchdog,cycles;
    reg [16:0] dividend,quotient;
    reg [8:0] remainder;
    reg [4:0] division_left;

    // Outer neighborhood uses replicated contrast borders: clamp its center
    // BEFORE applying the inner 7x7 replicated gray border. These clamps do
    // not commute near image edges.
    wire [7:0] center_x = candidate_x==0 ? (query_x==0 ? 8'd0 : query_x-8'd1) :
                          candidate_x==2 ? (query_x==191 ? 8'd191 : query_x+8'd1) : query_x;
    wire [6:0] center_y = candidate_y==0 ? (query_y==0 ? 7'd0 : query_y-7'd1) :
                          candidate_y==2 ? (query_y==95 ? 7'd95 : query_y+7'd1) : query_y;
    wire signed [9:0] raw_x = $signed({2'b00,center_x}) +
                              $signed({7'd0,window_x}) - 10'sd3;
    wire signed [8:0] raw_y = $signed({2'b00,center_y}) +
                              $signed({6'd0,window_y}) - 9'sd3;
    wire [7:0] source_x = raw_x<0 ? 8'd0 : raw_x>10'sd191 ? 8'd191 : raw_x[7:0];
    wire [6:0] source_y = raw_y<0 ? 7'd0 : raw_y>9'sd95 ? 7'd95 : raw_y[6:0];
    assign O_rd_req_addr = {1'b0,source_y,7'd0} + {2'b0,source_y,6'd0} +
                           {7'd0,source_x};
    assign O_rd_req_tag = {query_id,read_index};
    assign O_rd_req_valid = state==REQUEST && !I_cancel && !I_start;
    assign O_busy = state!=IDLE;
    wire matching_response = I_rd_rsp_valid && I_rd_rsp_tag==O_rd_req_tag;
    wire [13:0] next_sum7 = sum7+{6'd0,I_rd_rsp_data};
    wire inner3 = window_x>=2 && window_x<=4 && window_y>=2 && window_y<=4;
    wire [11:0] next_sum3 = sum3+(inner3 ? {4'd0,I_rd_rsp_data} : 12'd0);
    // Explicit extensions keep all shifted terms at the required width.
    wire [16:0] term3 = ({5'd0,sum3}<<5)+({5'd0,sum3}<<4)+{5'd0,sum3};
    wire [16:0] term7 = ({3'd0,sum7}<<3)+{3'd0,sum7};
    wire [9:0] shifted_remainder = {remainder,dividend[16]};
    wire quotient_bit = shifted_remainder>=10'd360;
    wire [9:0] subtracted_remainder = shifted_remainder-10'd360;
    wire [16:0] next_quotient = {quotient[15:0],quotient_bit};

    task finish_error;
        input [3:0] code;
        begin
            state<=IDLE; O_done<=1'b1; O_result_valid<=1'b1;
            O_error<=code; O_observed<=0;
            O_read_count<=read_count; O_cycles<=cycles+32'd1;
        end
    endtask

    task accept_response;
        begin
            watchdog<=0;
            sum7<=next_sum7; sum3<=next_sum3;
            read_count<=read_count+9'd1;
            read_index<=read_index+9'd1;
            if (window_x==6 && window_y==6) begin
                state<=EVALUATE;
            end else begin
                state<=REQUEST;
                if (window_x==6) begin window_x<=0; window_y<=window_y+3'd1; end
                else window_x<=window_x+3'd1;
            end
        end
    endtask

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state<=IDLE; query_id<=0; query_x<=0; query_y<=0;
            candidate_x<=0; candidate_y<=0; window_x<=0; window_y<=0;
            read_index<=0; read_count<=0; sum7<=0; sum3<=0;
            maximum<=0; candidate_value<=0; watchdog<=0; cycles<=0;
            dividend<=0; quotient<=0; remainder<=0; division_left<=0;
            O_done<=0; O_result_valid<=0; O_error<=0; O_observed<=0;
            O_read_count<=0; O_cycles<=0;
        end else begin
            O_done<=1'b0;
            if (state!=IDLE) cycles<=cycles+32'd1;
            if (I_cancel) begin
                state<=IDLE; O_result_valid<=0; O_error<=0;
                O_observed<=0; O_read_count<=0; O_cycles<=0;
            end else if (I_start && state!=IDLE) begin
                finish_error(4'd2);
            end else if (I_start) begin
                O_result_valid<=0; O_error<=0; O_observed<=0;
                O_read_count<=0; O_cycles<=0;
                if (I_x>191 || I_y>95) begin
                    state<=IDLE; O_done<=1; O_result_valid<=1;
                    O_error<=4'd1;
                end else begin
                    state<=REQUEST; query_id<=I_query_id;
                    query_x<=I_x; query_y<=I_y;
                    candidate_x<=0; candidate_y<=0; window_x<=0; window_y<=0;
                    read_index<=0; read_count<=0; sum7<=0; sum3<=0;
                    maximum<=0; candidate_value<=0; watchdog<=0; cycles<=0;
                end
            end else begin
                case (state)
                    REQUEST: begin
                        if (I_rd_req_ready) begin
                            watchdog<=0;
                            if (matching_response) accept_response();
                            else state<=RESPONSE;
                        end else if (watchdog>=READ_TIMEOUT_CYCLES-1) begin
                            finish_error(4'd3);
                        end else watchdog<=watchdog+32'd1;
                    end
                    RESPONSE: begin
                        if (matching_response) accept_response();
                        else if (watchdog>=READ_TIMEOUT_CYCLES-1) finish_error(4'd4);
                        else watchdog<=watchdog+32'd1;
                    end
                    EVALUATE: begin
                        // Max(max(signed contrast),0) equals max of positive
                        // contrasts with zero. Negative numerators therefore
                        // need no division; no signed-rounding approximation.
                        if (term3<=term7) begin candidate_value<=0; state<=ADVANCE; end
                        else begin
                            dividend<=term3-term7; quotient<=0; remainder<=0;
                            division_left<=17; state<=DIVIDE;
                        end
                    end
                    DIVIDE: begin
                        remainder<=quotient_bit ? subtracted_remainder[8:0] : shifted_remainder[8:0];
                        dividend<={dividend[15:0],1'b0}; quotient<=next_quotient;
                        division_left<=division_left-5'd1;
                        if (division_left==1) begin
                            candidate_value<=|next_quotient[16:8] ? 8'd255 : next_quotient[7:0];
                            state<=ADVANCE;
                        end
                    end
                    ADVANCE: begin
                        if (candidate_value>maximum) maximum<=candidate_value;
                        if (candidate_x==2 && candidate_y==2) begin
                            state<=IDLE; O_done<=1; O_result_valid<=1; O_error<=0;
                            O_observed<=candidate_value>maximum ? candidate_value : maximum;
                            O_read_count<=read_count; O_cycles<=cycles+32'd1;
                        end else begin
                            if (candidate_x==2) begin candidate_x<=0; candidate_y<=candidate_y+2'd1; end
                            else candidate_x<=candidate_x+2'd1;
                            window_x<=0; window_y<=0; sum7<=0; sum3<=0;
                            watchdog<=0; state<=REQUEST;
                        end
                    end
                    default: state<=IDLE;
                endcase
            end
        end
    end
endmodule
