`timescale 1ns/1ps
// 10-bit bilinear Bayer interpolation.  Matrix lines contain six samples
// x-1..x+4 for a four-pixel output beat, packed by raw_matrix_3x3_buffer10.
// BGGR is the production sensor phase (P0=B); bayer_ypos=1 denotes an even
// B/G row, matching the legacy demosaic block.
module bilinear_interpolation10_edge #(
    parameter BAYER_MODE = "BGGR"
) (
    input              I_clk,
    input              I_rst_n,
    input              I_tlast,
    input              I_tuser,
    input              I_tvalid,
    output             I_tready,
    input              bayer_ypos,
    input      [119:0] matrix_last_line,
    input      [119:0] matrix_cur_line,
    input      [119:0] matrix_next_line,
    output             O_tlast,
    output             O_tuser,
    output     [119:0] O_tdata,
    output             O_tvalid,
    input              O_tready
);
    reg [9:0] top [0:5];
    reg [9:0] mid [0:5];
    reg [9:0] bot [0:5];
    reg [9:0] out_r [0:3];
    reg [9:0] out_g [0:3];
    reg [9:0] out_b [0:3];
    integer i;

    function automatic [9:0] avg2;
        input [9:0] a;
        input [9:0] b;
        reg [10:0] s;
        begin
            s = a + b + 1'b1;
            avg2 = s[10:1];
        end
    endfunction
    function automatic [9:0] avg4;
        input [9:0] a;
        input [9:0] b;
        input [9:0] c;
        input [9:0] d;
        reg [11:0] s;
        begin
            s = a + b + c + d + 2'd2;
            avg4 = s[11:2];
        end
    endfunction
    function automatic [9:0] abs10;
        input [9:0] a;
        input [9:0] b;
        begin
            abs10 = (a >= b) ? a-b : b-a;
        end
    endfunction

    // 10-bit samples are kept until the downstream rgb10_to_rgb8 block.
    always @* begin
        for (i=0; i<6; i=i+1) begin
            top[i] = matrix_last_line[24 + i*10 +: 10];
            mid[i] = matrix_cur_line [24 + i*10 +: 10];
            bot[i] = matrix_next_line[24 + i*10 +: 10];
        end
        for (i=0; i<4; i=i+1) begin : INTERP_LANE
            // Defaults keep every combinational branch covered.
            out_r[i] = mid[i+1];
            out_g[i] = mid[i+1];
            out_b[i] = mid[i+1];
            if (BAYER_MODE == "BGGR") begin
                if (bayer_ypos && ((i & 1) == 0)) begin
                    // Blue site on an even BGGR row.
                    out_b[i] = mid[i+1];
                    out_g[i] = (abs10(mid[i],mid[i+2]) <= abs10(top[i+1],bot[i+1])) ?
                               avg2(mid[i],mid[i+2]) : avg2(top[i+1],bot[i+1]);
                    out_r[i] = avg4(top[i],top[i+2],bot[i],bot[i+2]);
                end else if (!bayer_ypos && ((i & 1) == 1)) begin
                    // Red site on an odd BGGR row.
                    out_r[i] = mid[i+1];
                    out_g[i] = (abs10(mid[i],mid[i+2]) <= abs10(top[i+1],bot[i+1])) ?
                               avg2(mid[i],mid[i+2]) : avg2(top[i+1],bot[i+1]);
                    out_b[i] = avg4(top[i],top[i+2],bot[i],bot[i+2]);
                end else begin
                    // Green site.  The row/column phase selects which colour
                    // is horizontal and which is vertical.
                    out_g[i] = mid[i+1];
                    if (bayer_ypos) begin
                        // B G / R G: horizontal B, vertical R.
                        out_b[i] = avg2(mid[i],mid[i+2]);
                        out_r[i] = avg2(top[i+1],bot[i+1]);
                    end else begin
                        // G B / G R: horizontal R, vertical B.
                        out_r[i] = avg2(mid[i],mid[i+2]);
                        out_b[i] = avg2(top[i+1],bot[i+1]);
                    end
                end
            end
        end
    end

    assign I_tready = O_tready;
    assign O_tvalid = I_tvalid;
    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;
    assign O_tdata  = {out_r[3],out_g[3],out_b[3],
                       out_r[2],out_g[2],out_b[2],
                       out_r[1],out_g[1],out_b[1],
                       out_r[0],out_g[0],out_b[0]};
endmodule
