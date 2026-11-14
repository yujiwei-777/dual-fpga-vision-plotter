`timescale 1ns/1ps
// Standalone sparse expected-ROM -> COMPLETE dense observed/expected join.
// No PCB locator, contrast frontend, physical ROM, or production integration.
// ROM request/response is synchronous, at most one request outstanding.
// Endpoint must echo O_rom_req_tag and reset/flush its outstanding response
// pipeline with I_rst_n. Cancel changes generation, so old replies are drained.
// A reply may start no earlier than the cycle AFTER request acceptance.
// Sparse words: bit23=0, bits22:8 linear address, bits7:0 NONZERO expected8.
// Entries must be strictly ascending and all addresses <18432.
// O_pixel_* exposes the NEXT input pixel before I_valid, for a future sparse
// query scheduler. If expected=0 it may supply observed=0 without a query.
// O_expected_valid remains stable until an input handshake (or abort).
// Existing scorer STILL receives all18432 dense pixels and last at18431.
// On O_fault, consumer MUST treat task as REVIEW/invalid, and must honor
// O_downstream_cancel. No downstream partial result can be accepted.
// O_done means final dense output transferred, NOT consumer arithmetic done.
module pcb_sparse_expected_join #(
    parameter integer ROM_TIMEOUT_CYCLES = 1024
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_start,
    input wire I_cancel,
    input wire [14:0] I_sparse_count,
    input wire I_valid,
    output wire O_ready,
    input wire [7:0] I_observed,
    input wire I_last,
    output wire O_valid,
    input wire I_ready,
    output wire [7:0] O_observed,
    output wire [7:0] O_expected,
    output wire O_last,
    output wire [14:0] O_pixel_address,
    output wire [7:0] O_pixel_expected,
    output wire O_expected_valid,
    output wire O_rom_req_valid,
    input wire I_rom_req_ready,
    output wire [14:0] O_rom_req_index,
    output wire [15:0] O_rom_req_tag,
    input wire I_rom_rsp_valid,
    output wire O_rom_rsp_ready,
    input wire [23:0] I_rom_rsp_data,
    input wire [15:0] I_rom_rsp_tag,
    output wire O_busy,
    output reg O_done,
    output reg O_fault,
    output reg [3:0] O_error,
    output reg O_downstream_start,
    output reg O_downstream_cancel,
    output reg [14:0] O_accepted,
    output reg [14:0] O_forwarded
);
    localparam IDLE=3'd0, FETCH_REQ=3'd1, FETCH_RSP=3'd2,
               STREAM=3'd3, DRAIN=3'd4;
    // Errorcodes:1count,2reserved,3address,4zeroexpected,5nonmonotonic,
    // 6unsolicitedcurrenttag,7earlylast,8missinglast,9busystart,10ROMtimeout.
    reg [2:0] state;
    reg [14:0] count_saved, entry_index, position;
    reg [15:0] generation;
    reg [31:0] rom_watchdog;
    reg current_valid, previous_valid;
    reg [14:0] current_address, previous_address;
    reg [7:0] current_expected;
    reg buffer_valid, buffer_last;
    reg [7:0] buffer_observed, buffer_expected;
    wire final_input = (position==15'd18431);
    wire matched = current_valid && current_address==position;
    wire input_transfer = I_valid && O_ready;
    wire output_transfer = O_valid && I_ready;
    wire request_transfer = O_rom_req_valid && I_rom_req_ready;
    wire matching_response = I_rom_rsp_valid && I_rom_rsp_tag==generation;
    wire [14:0] response_address = I_rom_rsp_data[22:8];
    wire [7:0] response_expected = I_rom_rsp_data[7:0];

    assign O_busy = state!=IDLE;
    assign O_pixel_address = position;
    assign O_pixel_expected = matched ? current_expected : 8'd0;
    assign O_expected_valid = state==STREAM && !O_fault && !I_start && !I_cancel;
    assign O_ready = O_expected_valid && (!buffer_valid || I_ready);
    assign O_valid = buffer_valid && !O_fault && !I_start && !I_cancel;
    assign O_observed = buffer_observed;
    assign O_expected = buffer_expected;
    assign O_last = buffer_last;
    assign O_rom_req_valid = state==FETCH_REQ && !I_start && !I_cancel && !O_fault;
    assign O_rom_req_index = entry_index;
    assign O_rom_req_tag = generation;
    // Stale generations must never block the single-outstanding channel.
    assign O_rom_rsp_ready = 1'b1;

    task fail;
        input [3:0] code;
        begin
            state<=IDLE; buffer_valid<=0; current_valid<=0;
            O_fault<=1; O_error<=code; O_done<=0;
            O_downstream_cancel<=1;
            generation<=generation+16'd1; rom_watchdog<=0;
        end
    endtask

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state<=IDLE; count_saved<=0; entry_index<=0; position<=0;
            generation<=0; rom_watchdog<=0; current_valid<=0;
            previous_valid<=0; current_address<=0; previous_address<=0;
            current_expected<=0; buffer_valid<=0; buffer_last<=0;
            buffer_observed<=0; buffer_expected<=0;
            O_done<=0; O_fault<=0; O_error<=0;
            O_downstream_start<=0; O_downstream_cancel<=0;
            O_accepted<=0; O_forwarded<=0;
        end else begin
            O_done<=0; O_downstream_start<=0; O_downstream_cancel<=0;
            if (I_cancel) begin
                state<=IDLE; buffer_valid<=0; current_valid<=0;
                previous_valid<=0; O_fault<=0; O_error<=0;
                O_accepted<=0; O_forwarded<=0;
                O_downstream_cancel<=1; generation<=generation+16'd1;
                rom_watchdog<=0;
            end else if (I_start && state!=IDLE) begin
                fail(4'd9);
            end else if (I_start) begin
                generation<=generation+16'd1; count_saved<=I_sparse_count;
                entry_index<=0; position<=0; current_valid<=0;
                previous_valid<=0; buffer_valid<=0; rom_watchdog<=0;
                O_accepted<=0; O_forwarded<=0; O_fault<=0; O_error<=0;
                if (I_sparse_count>15'd18432) begin
                    state<=IDLE; O_fault<=1; O_error<=4'd1;
                    O_downstream_cancel<=1;
                end else begin
                    state<=I_sparse_count==0 ? STREAM : FETCH_REQ;
                    O_downstream_start<=1;
                end
            end else if (state!=IDLE && matching_response && state!=FETCH_RSP) begin
                fail(4'd6);
            end else begin
                if (output_transfer) begin
                    buffer_valid<=0; O_forwarded<=O_forwarded+15'd1;
                    if (buffer_last) begin
                        state<=IDLE; O_done<=1;
                    end
                end
                case (state)
                    FETCH_REQ: begin
                        if (request_transfer) begin
                            state<=FETCH_RSP; rom_watchdog<=0;
                        end else if (rom_watchdog>=ROM_TIMEOUT_CYCLES-1) begin
                            fail(4'd10);
                        end else rom_watchdog<=rom_watchdog+32'd1;
                    end
                    FETCH_RSP: begin
                        if (matching_response) begin
                            rom_watchdog<=0;
                            if (I_rom_rsp_data[23]) fail(4'd2);
                            else if (response_address>=15'd18432) fail(4'd3);
                            else if (response_expected==0) fail(4'd4);
                            else if (previous_valid && response_address<=previous_address) fail(4'd5);
                            else begin
                                current_address<=response_address;
                                current_expected<=response_expected;
                                current_valid<=1; previous_address<=response_address;
                                previous_valid<=1; state<=STREAM;
                            end
                        end else if (rom_watchdog>=ROM_TIMEOUT_CYCLES-1) begin
                            fail(4'd10);
                        end else rom_watchdog<=rom_watchdog+32'd1;
                    end
                    STREAM: begin
                        if (input_transfer) begin
                            if (I_last && !final_input) fail(4'd7);
                            else if (!I_last && final_input) fail(4'd8);
                            // Address18431 cannot be followed by another valid
                            // strictlyascending in-range sparse entry. Never
                            // let an unvalidated trailing record escape at EOF.
                            else if (final_input && matched && entry_index+15'd1<count_saved) fail(4'd5);
                            else begin
                                buffer_observed<=I_observed;
                                buffer_expected<=O_pixel_expected;
                                buffer_last<=I_last; buffer_valid<=1;
                                O_accepted<=O_accepted+15'd1;
                                position<=position+15'd1;
                                if (matched) begin
                                    current_valid<=0; entry_index<=entry_index+15'd1;
                                    if (entry_index+15'd1<count_saved) begin
                                        state<=FETCH_REQ; rom_watchdog<=0;
                                    end
                                end
                                if (final_input) state<=DRAIN;
                            end
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
