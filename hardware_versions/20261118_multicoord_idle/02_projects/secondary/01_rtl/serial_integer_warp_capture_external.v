`timescale 1ns/1ps
// Independent external-sampler canonical capture controller.
// Writes exactly18432 Y8 pixels into bank0[8192..17407], packed even/odd.
// Only O_commit authorizes consumption. Incomplete or aborted generations
// may contain partial writes but can never commit.
//
// Ownership contract:
// * O_sample_claim requests exclusive ownership until it falls. Before a
//   point starts, the controller waits a bounded time for grant and idle.
// * The arbiter must hold sampler/DDR ownership through cancellation/drain,
//   including a grant-loss error. Never cancel the reader's accepted read.
// * LOCKED keeps the claim asserted until a common endpoint/reader reset.
// * Fine/coarse packets must remain stable while O_busy, as in the original
//   inline capture. The top-level job owner already holds these packets.
// No sampler, reader, DSP, image storage, or coefficient copy is instantiated.
module serial_integer_warp_capture_external #(
    parameter integer WAIT_TIMEOUT=4096
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,I_frame_valid,I_use_fine,
    input wire [255:0] I_fine,
    input wire [239:0] I_coarse,
    output wire O_sample_claim,
    input wire I_sample_grant,
    output wire O_sample_start,O_sample_cancel,
    output wire [7:0] O_sample_x,
    output wire [6:0] O_sample_y,
    output wire O_sample_use_fine,O_sample_apply_coarse,O_sample_half_image,
    output wire [255:0] O_sample_fine,
    output wire [239:0] O_sample_coarse,
    input wire I_sample_busy,I_sample_done,I_sample_valid,I_sample_complete,
    input wire [3:0] I_sample_error,
    input wire [7:0] I_sample_gray,
    output wire O_busy,
    output reg O_done,O_commit,O_fault,
    output reg [3:0] O_error,
    output reg O_ws_we,
    output reg [14:0] O_ws_waddr,
    output reg [15:0] O_ws_wdata,
    output reg [14:0] O_pixels,
    output reg O_all_samples_complete
);
    localparam IDLE=0,LAUNCH=1,WAIT_POINT=2,STORE=3,FENCE=4,DRAIN=5,LOCKED=6;
    localparam integer WAIT_BITS=WAIT_TIMEOUT>1?$clog2(WAIT_TIMEOUT):1;
    reg [2:0] state;
    reg [7:0] x,even_pixel;
    reg [6:0] y;
    reg [14:0] index;
    reg [WAIT_BITS-1:0] wait_count;
    wire abort_request=I_cancel||(I_start&&state!=IDLE);
    wire granted_idle=I_sample_grant&&!I_sample_busy&&!I_sample_done;
    assign O_busy=state!=IDLE;
    assign O_sample_claim=state!=IDLE;
    // A combinational pulse is accepted by both FSMs on the same edge.
    // Do not consume a stale done pulse from the previous sampler owner.
    assign O_sample_start=state==LAUNCH&&granted_idle&&!abort_request;
    assign O_sample_cancel=(state==WAIT_POINT&&(abort_request||!I_sample_grant))||state==DRAIN;
    assign O_sample_x=x;
    assign O_sample_y=y;
    assign O_sample_use_fine=I_use_fine;
    assign O_sample_apply_coarse=1'b1;
    assign O_sample_half_image=1'b0;
    assign O_sample_fine=I_fine;
    assign O_sample_coarse=I_coarse;
    task fail_idle;
        input [3:0] code;
        begin
            O_done<=1;O_fault<=1;O_error<=code;
            O_all_samples_complete<=0;state<=IDLE;
        end
    endtask
    task begin_drain;
        input [3:0] code;
        begin
            O_fault<=1;O_error<=code;O_all_samples_complete<=0;
            wait_count<=0;state<=DRAIN;
        end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;x<=0;y<=0;index<=0;even_pixel<=0;wait_count<=0;
            O_done<=0;O_commit<=0;O_fault<=0;O_error<=0;O_ws_we<=0;
            O_ws_waddr<=8192;O_ws_wdata<=0;O_pixels<=0;O_all_samples_complete<=0;
        end else begin
            O_done<=0;O_commit<=0;O_ws_we<=0;
            if(abort_request&&state!=IDLE&&state!=DRAIN&&state!=LOCKED)begin
                // WAIT_POINT is the only state that has launched a sample.
                // The sampler must drain accepted reads before ownership ends.
                if(state==WAIT_POINT)begin_drain(I_cancel?4'd4:4'd6);
                else fail_idle(I_cancel?4'd4:4'd6);
            end else case(state)
                IDLE:if(I_start&&!I_cancel)begin
                    O_fault<=0;O_error<=0;O_pixels<=0;
                    O_all_samples_complete<=1;x<=0;y<=0;index<=0;wait_count<=0;
                    if(!I_frame_valid)fail_idle(4'd1);
                    else state<=LAUNCH;
                end
                LAUNCH:begin
                    if(O_sample_start)begin state<=WAIT_POINT;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT-1)fail_idle(4'd9);
                    else wait_count<=wait_count+1'b1;
                end
                WAIT_POINT:begin
                    if(!I_sample_grant)begin_drain(4'd10);
                    else if(I_sample_done)begin
                        if(!I_sample_valid||I_sample_error!=0)begin
                            O_done<=1;O_fault<=1;
                            O_error<=I_sample_error!=0?I_sample_error:4'd4;
                            O_all_samples_complete<=0;
                            state<=I_sample_busy?LOCKED:IDLE;
                        end else if(I_sample_busy)begin_drain(4'd11);
                        else begin
                            O_pixels<=O_pixels+1'b1;
                            O_all_samples_complete<=O_all_samples_complete&&I_sample_complete;
                            if(!index[0])even_pixel<=I_sample_gray;
                            else begin
                                O_ws_we<=1;
                                O_ws_waddr<=15'd8192+{1'b0,index[14:1]};
                                O_ws_wdata<={I_sample_gray,even_pixel};
                            end
                            state<=STORE;
                        end
                    end
                end
                STORE:begin
                    if(index==18431)state<=FENCE;
                    else begin
                        index<=index+1'b1;
                        if(x==191)begin x<=0;y<=y+1'b1;end
                        else x<=x+1'b1;
                        state<=LAUNCH;wait_count<=0;
                    end
                end
                FENCE:begin
                    O_done<=1;
                    O_commit<=O_pixels==18432&&O_all_samples_complete;
                    O_fault<=O_pixels!=18432||!O_all_samples_complete;
                    if(O_pixels!=18432||!O_all_samples_complete)O_error<=8;
                    state<=IDLE;
                end
                DRAIN:begin
                    // O_sample_cancel stays asserted even after grant loss;
                    // the arbiter must keep the outstanding owner's routing.
                    if(!I_sample_busy)begin O_done<=1;state<=IDLE;end
                    else if(wait_count>=WAIT_TIMEOUT-1)begin
                        O_done<=1;O_fault<=1;O_error<=3;state<=LOCKED;
                    end else wait_count<=wait_count+1'b1;
                end
                LOCKED:begin end
                default:begin
                    O_done<=1;O_fault<=1;O_error<=15;
                    O_all_samples_complete<=0;state<=LOCKED;
                end
            endcase
        end
    end
endmodule
