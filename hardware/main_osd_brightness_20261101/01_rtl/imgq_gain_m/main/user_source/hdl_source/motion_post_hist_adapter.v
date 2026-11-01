// Motion-only 1280x720 -> 320x180 box average. HDMI/ROI pixels are unchanged.
// All logic uses I_clk; there is no new clock or CDC. Input RGB becomes
// floor((77R+150G+29B)/256); output is round(sum_of_16_luminances/16).
// Source (4bx+3,4by+3) completes a block. Data/valid/USER/LAST appear together
// two clocks later. USER marks the first complete block, LAST each block row.
module motion_post_hist_adapter(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    input  wire [23:0] I_data,
    output reg         O_vld,
    output reg         O_user,
    output reg         O_last,
    output reg  [23:0] O_pix,
    output reg         O_frame_error
);
    function [7:0] F_gray;
        input [23:0] rgb;
        reg [15:0] r, g, b, total;
        begin
            r={8'd0,rgb[23:16]}; g={8'd0,rgb[15:8]}; b={8'd0,rgb[7:0]};
            total=(r<<6)+(r<<3)+(r<<2)+r
                +(g<<7)+(g<<4)+(g<<2)+(g<<1)
                +(b<<4)+(b<<3)+(b<<2)+b;
            F_gray=total[15:8];
        end
    endfunction

    reg [10:0] x;
    reg [9:0] y;
    reg active, bad, de_d;
    wire start = I_de && I_user;
    wire [10:0] px = start ? 11'd0 : x;
    wire [9:0] py = start ? 10'd0 : y;
    wire accepted = I_de && (start || (active && !bad));
    wire wrong_last = accepted && (I_last != (px == 11'd1279));
    wire short_row = !start && active && !bad && de_d && !I_de && (x != 0);
    wire outside_frame = !start && I_de && !active;
    wire stream_error = start ? (active || I_last) :
                               (wrong_last || short_row || outside_frame);
    wire pixel_good = accepted && !wrong_last;

    reg valid0;
    reg [7:0] gray0;
    reg [10:0] x0;
    reg [9:0] y0;
    reg [9:0] horizontal_sum;
    wire [9:0] horizontal_total = horizontal_sum + {2'd0,gray0};
    wire horizontal_done = valid0 && (x0[1:0] == 2'd3);

    // One single-write, synchronous-read 512x12 RAM (columns 0..319).
    // The first row of EVERY four-row group replaces old RAM contents.
    // No reset loop is needed and discarded-frame contents cannot leak.
    (* ram_style="bram" *) reg [11:0] row_sum_mem[0:511];
    reg [11:0] row_sum_q;
    reg valid1;
    reg [9:0] horizontal1;
    reg [8:0] column1;
    reg [9:0] row1;
    wire [11:0] block_sum = (row1[1:0] == 2'd0) ?
        {2'd0,horizontal1} : row_sum_q + {2'd0,horizontal1};
    wire [12:0] rounded_sum = {1'b0,block_sum} + 13'd8;
    wire [7:0] block_mean = rounded_sum[11:4];

    always @(posedge I_clk) begin
        if (I_rst_n && !stream_error && horizontal_done)
            row_sum_q <= row_sum_mem[x0[10:2]];
        if (I_rst_n && !stream_error && valid1)
            row_sum_mem[column1] <= block_sum;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 0; y <= 0; active <= 0; bad <= 0; de_d <= 0;
            valid0<=0; gray0<=0; x0<=0; y0<=0; horizontal_sum<=0;
            valid1<=0; horizontal1<=0; column1<=0; row1<=0;
            O_vld <= 0; O_user <= 0; O_last <= 0; O_pix <= 0;
            O_frame_error <= 0;
        end else begin
            de_d <= I_de;
            O_frame_error<=stream_error;
            // Drain normal complete frames even with no inter-frame blank.
            // On interrupted USER discard old tokens, retain the new pixel.
            valid0<=pixel_good;
            if (pixel_good) begin gray0<=F_gray(I_data); x0<=px; y0<=py; end
            valid1<=horizontal_done && !stream_error;
            if (horizontal_done && !stream_error) begin
                horizontal1<=horizontal_total;
                column1<=x0[10:2]; row1<=y0;
            end
            if (stream_error) begin
                horizontal_sum<=0;
                valid0<=start && !I_last;
            end else if (valid0) begin
                if (x0[1:0] == 2'd0) horizontal_sum<={2'd0,gray0};
                else horizontal_sum<=horizontal_total;
            end

            O_vld<=valid1 && (row1[1:0] == 2'd3) && !stream_error;
            O_user<=valid1 && (row1 == 10'd3) && (column1 == 9'd0) && !stream_error;
            O_last<=valid1 && (row1[1:0] == 2'd3) && (column1 == 9'd319) && !stream_error;
            if (valid1 && (row1[1:0] == 2'd3) && !stream_error)
                O_pix<={block_mean,block_mean,block_mean};

            if (start) begin
                // Error belongs to the previous frame; USER starts a fresh one.
                x <= 11'd1; y <= 0; active <= 1; bad <= 0;
                if (I_last) begin
                    bad <= 1;
                end
            end else if (accepted) begin
                if (wrong_last) begin
                    bad <= 1;
                end
                if (I_last) begin
                    x <= 0;
                    if (y == 10'd719) active <= 0;
                    else y <= y + 1'b1;
                end else x <= x + 1'b1;
            end
            // A missing LAST must not silently concatenate two source rows.
            // This also catches errors in the three non-sampled trailing rows.
            if (short_row) bad <= 1;
        end
    end
endmodule
