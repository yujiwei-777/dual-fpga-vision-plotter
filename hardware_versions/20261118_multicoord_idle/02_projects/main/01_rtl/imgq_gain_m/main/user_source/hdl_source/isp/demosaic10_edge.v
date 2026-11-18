`timescale 1ns/1ps
// Stable compatibility wrapper used by both A/B variants.
// The production SC500 path intentionally uses the previously validated
// 8-bit Bayer demosaic. The RGB10 interface is retained for the A/B AWB
// blocks by zero extending each RGB8 sample to 10 bits.
module demosaic10_edge #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer DATA_COMPLETE_DELAY = 50,
    parameter BAYER_MODE = "BGGR"
) (
    input              I_clk,
    input              I_rst_n,
    input      [39:0]  I_tdata,
    input      [9:0]   I_tdest,
    input              I_tlast,
    input              I_tuser,
    input              I_tvalid,
    output             I_tready,
    output     [119:0] O_tdata,
    output             O_tlast,
    output             O_tuser,
    output             O_tvalid,
    input              O_tready
);
    wire [127:0] legacy_data;
    wire         legacy_last;
    wire         legacy_user;
    wire         legacy_valid;
    wire         legacy_ready;

    demosaic #(
        .IMG_HEIGHT(IMG_HEIGHT),
        .IMG_WIDTH(IMG_WIDTH),
        .data_complete_delay(DATA_COMPLETE_DELAY),
        .BAYER_MODE(BAYER_MODE)
    ) u_legacy_demosaic (
        .I_clk(I_clk),
        .I_rst_n(I_rst_n),
        .axi4s_video_tdata(I_tdata),
        .axi4s_video_tdest(I_tdest),
        .axi4s_video_tlast(I_tlast),
        .axi4s_video_tvalid(I_tvalid),
        .axi4s_video_tuser(I_tuser),
        .axi4s_video_tready(legacy_ready),
        .O_tlast(legacy_last),
        .O_tuser(legacy_user),
        .O_tdata(legacy_data),
        .O_tvalid(legacy_valid),
        .O_tready(O_tready)
    );

    assign I_tready = legacy_ready;
    assign O_tvalid = legacy_valid;
    assign O_tlast  = legacy_last;
    assign O_tuser  = legacy_user;

    // Legacy lane format (low lane first): {0,R8,G8,B8}.
    // A/B format (low lane first): {R10,G10,B10}.
    wire [31:0] l0 = legacy_data[31:0];
    wire [31:0] l1 = legacy_data[63:32];
    wire [31:0] l2 = legacy_data[95:64];
    wire [31:0] l3 = legacy_data[127:96];
    assign O_tdata = {
        2'b0,l3[23:16], 2'b0,l3[15:8],  2'b0,l3[7:0],
        2'b0,l2[23:16], 2'b0,l2[15:8],  2'b0,l2[7:0],
        2'b0,l1[23:16], 2'b0,l1[15:8],  2'b0,l1[7:0],
        2'b0,l0[23:16], 2'b0,l0[15:8],  2'b0,l0[7:0]
    };
endmodule
