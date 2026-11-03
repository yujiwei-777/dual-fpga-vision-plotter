// Display-only shadow/highlight tone mapping for the 4-pixel RGB stream.
//
// The module is deliberately a one-entry ready/valid stage.  The camera and
// the existing style pipeline keep their original frame markers.  In addition
// to the mode-dependent display output, O_fixed_tdata exposes the fixed tone
// curve for the recognition path.  I_tone_enable is sampled only with tuser,
// so a mode change cannot alter a display frame halfway through the line
// buffers.
module display_tone_96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [95:0] I_tdata,
    input  wire         I_tvalid,
    input  wire         I_tuser,
    input  wire         I_tlast,
    input  wire         I_tone_enable,
    output wire         I_tready,
    input  wire         O_tready,
    output reg  [95:0] O_tdata,
    output reg          O_tvalid,
    output reg          O_tuser,
    output reg          O_tlast,
    output reg  [95:0]  O_fixed_tdata,
    output wire         O_fixed_tvalid,
    output wire         O_fixed_tuser,
    output wire         O_fixed_tlast
);
    reg frame_tone, user_pending;
    wire out_free = !O_tvalid || O_tready;
    assign I_tready = out_free;
    // The fixed-tone tap shares the display stage transaction and markers.
    // The CNN branch only consumes it when the display-side entry is accepted,
    // so a downstream stall cannot duplicate a CNN pixel.
    assign O_fixed_tvalid = O_tvalid;
    assign O_fixed_tuser  = O_tuser;
    assign O_fixed_tlast  = O_tlast;

    function [7:0] tone8;
        input [7:0] value;
        reg [5:0] offset_bits;
        reg signed [8:0] adjusted;
        begin
            // Frozen signed6 correction [-12,28] used by recognition.
            if (value < 8'd32)
                offset_bits = value >> 1;
            else if (value < 8'd96)
                offset_bits = (value >> 3) + 6'd12;
            else
                offset_bits = 6'd52 - value[7:2] - ((&value[7:6]) && (&value[1:0]));
            adjusted = $signed({1'b0,value}) + $signed({{3{offset_bits[5]}},offset_bits});
            // All 256 inputs produce 0..243; saturation is unreachable.
            tone8 = adjusted[7:0];
        end
    endfunction

    function [95:0] display_group;
        input [95:0] source_group;
        input [95:0] fixed_group;
        integer i;
        reg [7:0] source_channel;
        begin
            display_group = fixed_group;
            for (i = 0; i < 12; i = i + 1) begin
                source_channel = source_group[95-i*8 -: 8];
                // Join 95->118 to 100->127 without the old 96->124 step.
                // Only the display changes: 96..99 map to 120,122,124,126.
                // This constant/bit selection adds no adder or multiplier.
                if (source_channel[7:2] == 6'd24)
                    display_group[95-i*8 -: 8] =
                        {5'b01111, source_channel[1:0], 1'b0};
            end
        end
    endfunction

    // Share the original curve.  Recognition keeps its exact frozen mapping.
    wire [95:0] fixed_tone_group_w = tone_group(I_tdata);

    function [95:0] tone_group;
        input [95:0] group;
        integer i;
        reg [23:0] p;
        begin
            tone_group = 96'd0;
            for (i = 0; i < 4; i = i + 1) begin
                p = group[95-i*24 -: 24];
                tone_group[95-i*24 -: 24] = {
                    tone8(p[23:16]), tone8(p[15:8]), tone8(p[7:0])
                };
            end
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            frame_tone  <= 1'b0;
            user_pending<= 1'b0;
            O_tdata   <= 96'd0;
            O_tvalid  <= 1'b0;
            O_tuser   <= 1'b0;
            O_tlast   <= 1'b0;
            O_fixed_tdata <= 96'd0;
        end else if (out_free) begin
            // Some AXI camera paths present tuser on an otherwise idle beat.
            // Capture the frame mode independently of tvalid so the first
            // real pixel of that frame receives the correct curve.
            if (I_tuser) begin
                frame_tone <= I_tone_enable;
                user_pending <= 1'b1;
            end
            if (I_tvalid) begin
                O_tdata  <= ((I_tuser ? I_tone_enable : frame_tone) != 1'b0)
                            ? display_group(I_tdata, fixed_tone_group_w) : I_tdata;
                O_fixed_tdata <= fixed_tone_group_w;
                O_tvalid <= 1'b1;
                O_tuser  <= I_tuser || user_pending;
                O_tlast  <= I_tlast;
                user_pending <= 1'b0;
            end else begin
                O_tvalid <= 1'b0;
                O_tuser  <= 1'b0;
                O_tlast  <= 1'b0;
            end
        end
    end
endmodule
