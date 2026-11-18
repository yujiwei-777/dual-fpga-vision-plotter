`timescale 1ns/1ps
// One-outstanding Y8 endpoint on the actual synchronous workspace read port.
// Request address/config is captured; valid appears after addr+registered RAM.
// No private RAM, cache, or reads of persistent model ROM locations.
// I_cancel flushes this endpoint: use only with a matching consumer flush.
// A serial warp waiting for this endpoint must cancel/drain by itself while
// this endpoint completes accepted reads (tie I_cancel low in that pairing).
module pcb_workspace_gray_adapter(
    input wire I_clk,I_rst_n,I_cancel,
    input wire I_request,I_half,I_canonical_valid,I_half_valid,
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    output wire O_ready,
    output wire O_idle,
    output reg O_pixel_valid,
    output reg [7:0] O_pixel_y8,
    output reg O_fault,
    output reg [3:0] O_error,
    output reg O_ws_rd_bank,
    output reg [14:0] O_ws_rd_addr,
    input wire [15:0] I_ws_rd_data
);
    localparam IDLE=0,WAIT_RAM=1,RETURN_DATA=2;
    reg [1:0] state;
    reg byte_high;
    wire [14:0] canonical_word=({5'd0,I_y}<<6)+({5'd0,I_y}<<5)+{5'd0,I_x[10:1]};
    wire [14:0] half_word=({5'd0,I_y}<<5)+({5'd0,I_y}<<4)+{5'd0,I_x[10:1]};
    assign O_ready=state==IDLE&&!I_cancel;
    assign O_idle=state==IDLE;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;byte_high<=0;O_pixel_valid<=0;O_pixel_y8<=0;
            O_fault<=0;O_error<=0;O_ws_rd_bank<=0;O_ws_rd_addr<=8192;
        end else begin
            O_pixel_valid<=0;
            if(I_cancel)begin state<=IDLE;O_fault<=0;O_error<=0;end
            else case(state)
                IDLE:if(I_request)begin
                    O_fault<=0;O_error<=0;byte_high<=I_x[0];
                    if((I_half&&!I_half_valid)||(!I_half&&!I_canonical_valid))begin
                        O_fault<=1;O_error<=1;O_pixel_y8<=0;O_pixel_valid<=1;
                    end else if((I_half&&(I_x>=96||I_y>=48))||(!I_half&&(I_x>=192||I_y>=96)))begin
                        O_fault<=1;O_error<=2;O_pixel_y8<=0;O_pixel_valid<=1;
                    end else begin
                        if(!I_half)begin O_ws_rd_bank<=0;O_ws_rd_addr<=15'd8192+canonical_word;end
                        else if(half_word<1024)begin O_ws_rd_bank<=0;O_ws_rd_addr<=15'd17408+half_word;end
                        else begin O_ws_rd_bank<=1;O_ws_rd_addr<=15'd5004+half_word-15'd1024;end
                        state<=WAIT_RAM;
                    end
                end
                WAIT_RAM:state<=RETURN_DATA;
                RETURN_DATA:begin O_pixel_y8<=byte_high?I_ws_rd_data[15:8]:I_ws_rd_data[7:0];O_pixel_valid<=1;state<=IDLE;end
                default:begin O_fault<=1;O_error<=15;state<=IDLE;end
            endcase
        end
    end
endmodule
