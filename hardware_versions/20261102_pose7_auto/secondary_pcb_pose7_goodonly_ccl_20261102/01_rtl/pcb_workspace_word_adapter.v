`timescale 1ns/1ps
// One-outstanding16-bit word endpoint on the existing registered workspace.
// Private synchronous reads can be flushed only together with their consumer;
// this endpoint is never used for rawDDR requests.
module pcb_workspace_word_adapter(
    input wire I_clk,I_rst_n,I_cancel,I_request,I_bank,
    input wire [14:0] I_addr,
    output wire O_ready,O_idle,
    output reg O_valid,O_fault,
    output reg [3:0] O_error,
    output reg [15:0] O_data,
    output reg O_ws_rd_bank,
    output reg [14:0] O_ws_rd_addr,
    input wire [15:0] I_ws_rd_data
);
    localparam IDLE=0,WAIT_RAM=1,RETURN_DATA=2;
    reg [1:0] state;
    assign O_idle=state==IDLE;
    assign O_ready=O_idle&&!I_cancel;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;O_valid<=0;O_fault<=0;O_error<=0;O_data<=0;
            O_ws_rd_bank<=0;O_ws_rd_addr<=0;
        end else begin
            O_valid<=0;
            if(I_cancel)begin state<=IDLE;O_fault<=0;O_error<=0;end
            else case(state)
                IDLE:if(I_request)begin
                    O_fault<=0;O_error<=0;
                    if((I_bank&&I_addr>=6912)||(!I_bank&&I_addr>=18432))begin
                        O_fault<=1;O_error<=1;O_data<=0;O_valid<=1;
                    end else begin
                        O_ws_rd_bank<=I_bank;O_ws_rd_addr<=I_addr;state<=WAIT_RAM;
                    end
                end
                WAIT_RAM:state<=RETURN_DATA;
                RETURN_DATA:begin O_data<=I_ws_rd_data;O_valid<=1;state<=IDLE;end
                default:begin O_fault<=1;O_error<=15;state<=IDLE;end
            endcase
        end
    end
endmodule
