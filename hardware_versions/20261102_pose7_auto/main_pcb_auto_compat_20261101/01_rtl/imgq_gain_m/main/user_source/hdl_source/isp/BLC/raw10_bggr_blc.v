// RAW10 black-level correction for the SC500 1280x720 BGGR stream.
//
// The RAW10 unpacker presents four pixels in one AXI4-Stream beat as
//   tdata[9:0]   = P0, tdata[19:10] = P1,
//   tdata[29:20] = P2, tdata[39:30] = P3.
//
// The measured phase is:
//   even line: P0=B,  P1=G, P2=B,  P3=G
//   odd  line: P0=G,  P1=R, P2=G,  P3=R
//
// This block is intentionally independent from the production ISP until the
// black-level capture and simulation results are reviewed.  It is an elastic
// one-beat AXI stream stage: input markers and corrected data are held while
// the downstream stage is stalled.  Row parity is advanced only on an
// accepted input beat carrying tlast, so a stalled beat cannot advance it.
`timescale 1ns/1ps

module raw10_bggr_blc #(
    // Initial measured candidate is 64 DN for all colors.  Keep independent
    // offsets for the two green Bayer phases: the even-row Gr samples and
    // odd-row Gb samples can have a small but real black-level difference.
    parameter [9:0] OFFSET_B  = 10'd64,
    parameter [9:0] OFFSET_GR = 10'd64,
    parameter [9:0] OFFSET_GB = 10'd64,
    parameter [9:0] OFFSET_R  = 10'd64
) (
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tvalid,
    output wire        I_tready,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [9:0]  I_tdest,
    input  wire [39:0] I_tdata,

    output wire        O_tvalid,
    input  wire        O_tready,
    output wire        O_tuser,
    output wire        O_tlast,
    output wire [9:0]  O_tdest,
    output wire [39:0] O_tdata
);

    reg         valid_r;
    reg         user_r;
    reg         last_r;
    reg [9:0]   dest_r;
    reg [39:0]  data_r;

    // 0 = even line (BGGR first row), 1 = odd line (GBRG second row).
    reg         row_parity_r;

    // The first beat of a frame is also the first (even) line.  tuser is
    // sampled only when the beat is accepted, but using it here is safe: an
    // upstream AXI source must hold tdata and sideband while !I_tready.
    wire row_parity_for_input = I_tuser ? 1'b0 : row_parity_r;

    wire [9:0] p0 = I_tdata[9:0];
    wire [9:0] p1 = I_tdata[19:10];
    wire [9:0] p2 = I_tdata[29:20];
    wire [9:0] p3 = I_tdata[39:30];

    function [9:0] subtract_sat;
        input [9:0] sample;
        input [9:0] offset;
        begin
            if (sample > offset)
                subtract_sat = sample - offset;
            else
                subtract_sat = 10'd0;
        end
    endfunction

    // BGGR phase mapping:
    //   even row: P0=B,  P1=Gr, P2=B,  P3=Gr
    //   odd  row: P0=Gb, P1=R,  P2=Gb, P3=R
    wire [9:0] p0_corr = subtract_sat(p0, row_parity_for_input ? OFFSET_GB : OFFSET_B);
    wire [9:0] p1_corr = subtract_sat(p1, row_parity_for_input ? OFFSET_R  : OFFSET_GR);
    wire [9:0] p2_corr = subtract_sat(p2, row_parity_for_input ? OFFSET_GB : OFFSET_B);
    wire [9:0] p3_corr = subtract_sat(p3, row_parity_for_input ? OFFSET_R  : OFFSET_GR);
    wire [39:0] corrected_word = {p3_corr, p2_corr, p1_corr, p0_corr};

    // Elastic one-entry stage.  When O_tready is high the current output is
    // consumed and a new input can be loaded in the same cycle.
    assign I_tready = ~valid_r | O_tready;
    assign O_tvalid = valid_r;
    assign O_tuser  = user_r;
    assign O_tlast  = last_r;
    assign O_tdest  = dest_r;
    assign O_tdata  = data_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_r      <= 1'b0;
            user_r       <= 1'b0;
            last_r       <= 1'b0;
            dest_r       <= 10'd0;
            data_r       <= 40'd0;
            row_parity_r <= 1'b0;
        end else begin
            if (I_tready) begin
                if (I_tvalid) begin
                    valid_r <= 1'b1;
                    user_r  <= I_tuser;
                    last_r  <= I_tlast;
                    dest_r  <= I_tdest;
                    data_r  <= corrected_word;

                    // A frame-start beat establishes line 0.  At a line end
                    // the next line has the opposite Bayer row phase.
                    if (I_tuser) begin
                        if (I_tlast)
                            row_parity_r <= 1'b1;
                        else
                            row_parity_r <= 1'b0;
                    end else if (I_tlast) begin
                        row_parity_r <= ~row_parity_r;
                    end
                end else begin
                    valid_r <= 1'b0;
                end
            end
            // !I_tready means the output register is stalled.  All output
            // fields and row parity remain unchanged until the beat is taken.
        end
    end

endmodule

// Continuous-stream variant for the active camera path.  The current
// uial2axis/frame_guard contract has no upstream back-pressure and the ISP
// boundary is tied always-ready, so a second full data register would only
// duplicate the RAW beat and consume slices.  This variant keeps the Bayer
// row state, but applies the same saturating correction combinationally to
// the already-registered frame_guard output.  Use raw10_bggr_blc (above) in
// standalone tests when a real ready/valid elastic stage is required.
module raw10_bggr_blc_comb #(
    parameter [9:0] OFFSET_B  = 10'd64,
    parameter [9:0] OFFSET_GR = 10'd64,
    parameter [9:0] OFFSET_GB = 10'd64,
    parameter [9:0] OFFSET_R  = 10'd64
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [39:0] I_tdata,
    output wire        O_tvalid,
    output wire        O_tuser,
    output wire        O_tlast,
    output wire [39:0] O_tdata
);
    reg row_parity_r;

    wire row_parity_for_input = I_tuser ? 1'b0 : row_parity_r;
    wire [9:0] p0 = I_tdata[9:0];
    wire [9:0] p1 = I_tdata[19:10];
    wire [9:0] p2 = I_tdata[29:20];
    wire [9:0] p3 = I_tdata[39:30];

    function [9:0] subtract_sat_comb;
        input [9:0] sample;
        input [9:0] offset;
        begin
            subtract_sat_comb = (sample > offset) ? (sample - offset) : 10'd0;
        end
    endfunction

    // Keep the same BGGR mapping as the elastic implementation above.
    wire [9:0] p0_corr = subtract_sat_comb(p0, row_parity_for_input ? OFFSET_GB : OFFSET_B);
    wire [9:0] p1_corr = subtract_sat_comb(p1, row_parity_for_input ? OFFSET_R  : OFFSET_GR);
    wire [9:0] p2_corr = subtract_sat_comb(p2, row_parity_for_input ? OFFSET_GB : OFFSET_B);
    wire [9:0] p3_corr = subtract_sat_comb(p3, row_parity_for_input ? OFFSET_R  : OFFSET_GR);

    assign O_tvalid = I_tvalid;
    assign O_tuser  = I_tuser;
    assign O_tlast  = I_tlast;
    assign O_tdata  = {p3_corr, p2_corr, p1_corr, p0_corr};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            row_parity_r <= 1'b0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                row_parity_r <= I_tlast ? 1'b1 : 1'b0;
            end else if (I_tlast) begin
                row_parity_r <= ~row_parity_r;
            end
        end
    end
endmodule
