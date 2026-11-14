`timescale 1ns/1ps
// Two tagged DETAIL endpoints multiplexed onto one existing workspace read
// port. Canonical linear Y8 in bank0[8192..17407], sparse24 in bank1[0..3851].
// No address division, cache or private memory. Sparse records are three
// little-endian bytes, two records per three 16-bit words.
// Round-robin admission when both request; backpressure holds ROM payload.
// I_cancel is a COMMON consumer+adapter flush, not a graceful sampler drain.
module pcb_workspace_detail_adapter #(
    parameter integer SPARSE_COUNT=2568
) (
    input wire I_clk,I_rst_n,I_cancel,I_canonical_valid,I_model_valid,
    input wire I_gray_req_valid,
    output wire O_gray_req_ready,
    input wire [14:0] I_gray_req_addr,
    input wire [40:0] I_gray_req_tag,
    output reg O_gray_rsp_valid,
    output reg [7:0] O_gray_rsp_data,
    output reg [40:0] O_gray_rsp_tag,
    input wire I_rom_req_valid,
    output wire O_rom_req_ready,
    input wire [14:0] I_rom_req_index,
    input wire [15:0] I_rom_req_tag,
    output reg O_rom_rsp_valid,
    input wire I_rom_rsp_ready,
    output reg [23:0] O_rom_rsp_data,
    output reg [15:0] O_rom_rsp_tag,
    output wire O_idle,
    output reg O_fault,
    output reg [3:0] O_error,
    output reg O_ws_rd_bank,
    output reg [14:0] O_ws_rd_addr,
    input wire [15:0] I_ws_rd_data
);
    localparam IDLE=0,WAIT_FIRST=1,DATA_FIRST=2,WAIT_SECOND=3,DATA_SECOND=4,HOLD_ROM=5;
    reg [2:0] state;
    reg owner_rom,byte_high,prefer_gray;
    reg [15:0] first_word;
    wire [14:0] sparse_first=I_rom_req_index+(I_rom_req_index>>1);
    assign O_idle=state==IDLE;
    wire choose_rom=I_rom_req_valid&&(!I_gray_req_valid||!prefer_gray);
    assign O_rom_req_ready=O_idle&&!I_cancel&&(!I_gray_req_valid||!prefer_gray);
    assign O_gray_req_ready=O_idle&&!I_cancel&&(!I_rom_req_valid||prefer_gray);
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;owner_rom<=0;byte_high<=0;prefer_gray<=0;first_word<=0;
            O_gray_rsp_valid<=0;O_gray_rsp_data<=0;O_gray_rsp_tag<=0;
            O_rom_rsp_valid<=0;O_rom_rsp_data<=0;O_rom_rsp_tag<=0;
            O_fault<=0;O_error<=0;O_ws_rd_bank<=0;O_ws_rd_addr<=8192;
        end else begin
            O_gray_rsp_valid<=0;
            if(I_cancel)begin
                state<=IDLE;O_gray_rsp_valid<=0;O_rom_rsp_valid<=0;
                O_fault<=0;O_error<=0;
            end else case(state)
                IDLE:begin
                    if(choose_rom)begin
                        prefer_gray<=1;
                        O_rom_rsp_tag<=I_rom_req_tag;owner_rom<=1;byte_high<=I_rom_req_index[0];
                        if(!I_model_valid||I_rom_req_index>=SPARSE_COUNT)begin
                            O_fault<=1;O_error<=!I_model_valid?4'd1:4'd2;
                            O_rom_rsp_data<=0;O_rom_rsp_valid<=1;state<=HOLD_ROM;
                        end else begin
                            O_ws_rd_bank<=1;O_ws_rd_addr<=sparse_first;state<=WAIT_FIRST;
                        end
                    end else if(I_gray_req_valid)begin
                        prefer_gray<=0;
                        O_gray_rsp_tag<=I_gray_req_tag;owner_rom<=0;byte_high<=I_gray_req_addr[0];
                        if(!I_canonical_valid||I_gray_req_addr>=18432)begin
                            O_fault<=1;O_error<=!I_canonical_valid?4'd1:4'd2;
                            O_gray_rsp_data<=0;O_gray_rsp_valid<=1;
                        end else begin
                            O_ws_rd_bank<=0;O_ws_rd_addr<=15'd8192+{1'b0,I_gray_req_addr[14:1]};state<=WAIT_FIRST;
                        end
                    end
                end
                WAIT_FIRST:state<=DATA_FIRST;
                DATA_FIRST:begin
                    if(owner_rom)begin
                        first_word<=I_ws_rd_data;O_ws_rd_addr<=O_ws_rd_addr+1'b1;state<=WAIT_SECOND;
                    end else begin
                        O_gray_rsp_data<=byte_high?I_ws_rd_data[15:8]:I_ws_rd_data[7:0];
                        O_gray_rsp_valid<=1;state<=IDLE;
                    end
                end
                WAIT_SECOND:state<=DATA_SECOND;
                DATA_SECOND:begin
                    O_rom_rsp_data<=byte_high?{I_ws_rd_data,first_word[15:8]}:{I_ws_rd_data[7:0],first_word};
                    O_rom_rsp_valid<=1;state<=HOLD_ROM;
                end
                HOLD_ROM:if(O_rom_rsp_valid&&I_rom_rsp_ready)begin O_rom_rsp_valid<=0;state<=IDLE;end
                default:begin O_fault<=1;O_error<=15;state<=IDLE;O_rom_rsp_valid<=0;end
            endcase
        end
    end
endmodule
