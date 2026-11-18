// Continuous-throughput RAW10 window generator for the four-lane BGGR path.
// The source has no ready signal, so line-end flush and next-line capture
// happen in the same cycle.  There is no line-boundary input bubble.
module raw_matrix_3x3_buffer10 #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720
) (
    input             I_clk,
    input             I_rst_n,
    input      [39:0] I_tdata,
    input             I_tlast,
    input             I_tuser,
    input             I_tvalid,
    output            I_tready,
    output            O_tlast,
    output            O_tuser,
    output            O_tvalid,
    input             O_tready,
    output     [119:0] matrix_last_line,
    output     [119:0] matrix_cur_line,
    output     [119:0] matrix_next_line,
    output            bayer_ypos
);
    localparam integer XW = (IMG_WIDTH <= 4) ? 2 : $clog2(IMG_WIDTH);
    localparam integer YW = (IMG_HEIGHT <= 2) ? 1 : $clog2(IMG_HEIGHT);

    (* ram_style = "block" *) reg [9:0] row_a [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [9:0] row_b [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [9:0] row_c [0:IMG_WIDTH-1];

    reg [9:0] pend0, pend1, pend2, pend3;
    reg [XW-1:0] pend_x;
    reg [YW-1:0] pend_y;
    reg pend_user, pend_last, pend_valid, flush_pending;
    reg [XW-1:0] beat_x;
    reg [YW-1:0] row_y;

    reg [119:0] matrix_last_r, matrix_cur_r, matrix_next_r;
    reg out_valid_r, out_last_r, out_user_r;

    wire slot_free = !out_valid_r || O_tready;
    assign I_tready = slot_free;
    wire accept = I_tvalid && I_tready;

    wire [9:0] cur0 = I_tdata[9:0];
    wire [9:0] cur1 = I_tdata[19:10];
    wire [9:0] cur2 = I_tdata[29:20];
    wire [9:0] cur3 = I_tdata[39:30];

    wire [YW-1:0] next_row =
        (row_y == IMG_HEIGHT-1) ? {YW{1'b0}} : row_y + 1'b1;
    wire [YW-1:0] accept_row =
        I_tuser ? {YW{1'b0}} : (flush_pending ? next_row : row_y);
    wire [XW-1:0] accept_x =
        (I_tuser || flush_pending || !pend_valid) ? {XW{1'b0}} : beat_x;

    function automatic [9:0] clip_buf_sample;
        input integer which;
        input integer addr;
        integer a;
        begin
            a = addr;
            if (a < 0) a = 0;
            if (a >= IMG_WIDTH) a = IMG_WIDTH-1;
            case (which)
                0: clip_buf_sample = row_a[a];
                1: clip_buf_sample = row_b[a];
                default: clip_buf_sample = row_c[a];
            endcase
        end
    endfunction

    function automatic [9:0] current_sample;
        input integer addr;
        integer a;
        begin
            a = addr;
            if (a < 0) a = 0;
            if (a >= IMG_WIDTH) a = IMG_WIDTH-1;
            if (pend_valid && (a >= pend_x) && (a <= pend_x+3)) begin
                case (a-pend_x)
                    0: current_sample = pend0;
                    1: current_sample = pend1;
                    2: current_sample = pend2;
                    default: current_sample = pend3;
                endcase
            end else if (accept && (a >= accept_x) && (a <= accept_x+3)) begin
                case (a-accept_x)
                    0: current_sample = cur0;
                    1: current_sample = cur1;
                    2: current_sample = cur2;
                    default: current_sample = cur3;
                endcase
            end else begin
                case (pend_y % 3)
                    0: current_sample = row_a[a];
                    1: current_sample = row_b[a];
                    default: current_sample = row_c[a];
                endcase
            end
        end
    endfunction

    function automatic [9:0] previous_sample;
        input integer addr;
        begin
            if (pend_y == 0)
                previous_sample = current_sample(addr);
            else
                previous_sample = clip_buf_sample((pend_y + 2) % 3, addr);
        end
    endfunction

    reg [9:0] u0,u1,u2,u3,u4,u5;
    reg [9:0] m0,m1,m2,m3,m4,m5;
    reg [9:0] d0,d1,d2,d3,d4,d5;
    always @* begin
        u0 = previous_sample(pend_x-1); u1 = previous_sample(pend_x);
        u2 = previous_sample(pend_x+1); u3 = previous_sample(pend_x+2);
        u4 = previous_sample(pend_x+3); u5 = previous_sample(pend_x+4);
        m0 = current_sample(pend_x-1); m1 = current_sample(pend_x);
        m2 = current_sample(pend_x+1); m3 = current_sample(pend_x+2);
        m4 = current_sample(pend_x+3); m5 = current_sample(pend_x+4);
        d0 = m0; d1 = m1; d2 = m2; d3 = m3; d4 = m4; d5 = m5;
    end

    assign O_tvalid = out_valid_r;
    assign O_tlast = out_last_r;
    assign O_tuser = out_user_r;
    assign matrix_last_line = matrix_last_r;
    assign matrix_cur_line = matrix_cur_r;
    assign matrix_next_line = matrix_next_r;
    assign bayer_ypos = ~pend_y[0];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pend0 <= 0; pend1 <= 0; pend2 <= 0; pend3 <= 0;
            pend_x <= 0; pend_y <= 0; pend_user <= 0; pend_last <= 0;
            pend_valid <= 0; flush_pending <= 0; beat_x <= 0; row_y <= 0;
            matrix_last_r <= 0; matrix_cur_r <= 0; matrix_next_r <= 0;
            out_valid_r <= 0; out_last_r <= 0; out_user_r <= 0;
        end else begin
            if (slot_free)
                out_valid_r <= 1'b0;

            if (flush_pending && !accept && slot_free) begin
                matrix_last_r <= {36'd0,u5,u4,u3,u2,u1,u0,24'd0};
                matrix_cur_r  <= {36'd0,m5,m4,m3,m2,m1,m0,24'd0};
                matrix_next_r <= {36'd0,d5,d4,d3,d2,d1,d0,24'd0};
                out_valid_r <= 1'b1;
                out_last_r <= 1'b1;
                out_user_r <= pend_user;
                flush_pending <= 1'b0;
                pend_valid <= 1'b0;
                beat_x <= 0;
                row_y <= next_row;
            end else if (accept) begin
                case (accept_row % 3)
                    0: begin
                        row_a[accept_x+0] <= cur0; row_a[accept_x+1] <= cur1;
                        row_a[accept_x+2] <= cur2; row_a[accept_x+3] <= cur3;
                    end
                    1: begin
                        row_b[accept_x+0] <= cur0; row_b[accept_x+1] <= cur1;
                        row_b[accept_x+2] <= cur2; row_b[accept_x+3] <= cur3;
                    end
                    default: begin
                        row_c[accept_x+0] <= cur0; row_c[accept_x+1] <= cur1;
                        row_c[accept_x+2] <= cur2; row_c[accept_x+3] <= cur3;
                    end
                endcase

                if (flush_pending) begin
                    matrix_last_r <= {36'd0,u5,u4,u3,u2,u1,u0,24'd0};
                    matrix_cur_r  <= {36'd0,m5,m4,m3,m2,m1,m0,24'd0};
                    matrix_next_r <= {36'd0,d5,d4,d3,d2,d1,d0,24'd0};
                    out_valid_r <= 1'b1;
                    out_last_r <= 1'b1;
                    out_user_r <= pend_user;
                    flush_pending <= 1'b0;
                    pend0 <= cur0; pend1 <= cur1; pend2 <= cur2; pend3 <= cur3;
                    pend_x <= accept_x; pend_y <= accept_row;
                    pend_user <= I_tuser; pend_last <= I_tlast; pend_valid <= 1'b1;
                    row_y <= accept_row;
                    beat_x <= I_tlast ? 0 : 4;
                end else if (!pend_valid) begin
                    pend0 <= cur0; pend1 <= cur1; pend2 <= cur2; pend3 <= cur3;
                    pend_x <= accept_x; pend_y <= accept_row;
                    pend_user <= I_tuser; pend_last <= I_tlast; pend_valid <= 1'b1;
                    row_y <= accept_row;
                    beat_x <= I_tlast ? 0 : 4;
                end else begin
                    matrix_last_r <= {36'd0,u5,u4,u3,u2,u1,u0,24'd0};
                    matrix_cur_r <= {36'd0,m5,m4,m3,m2,m1,m0,24'd0};
                    matrix_next_r <= {36'd0,d5,d4,d3,d2,d1,d0,24'd0};
                    out_valid_r <= 1'b1;
                    out_last_r <= pend_last;
                    out_user_r <= pend_user;
                    pend0 <= cur0; pend1 <= cur1; pend2 <= cur2; pend3 <= cur3;
                    pend_x <= accept_x; pend_y <= accept_row;
                    pend_user <= I_tuser; pend_last <= I_tlast; pend_valid <= 1'b1;
                    if (I_tlast) begin
                        flush_pending <= 1'b1;
                        row_y <= accept_row;
                        beat_x <= 0;
                    end else begin
                        beat_x <= accept_x + 4;
                    end
                end
            end
        end
    end
endmodule
