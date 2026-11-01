// Lightweight A4 width measurement for the main-board distance OSD.
//
// The camera stream is four RGB888 pixels per accepted beat.  A capture
// request arms the next complete frame.  The frame is sampled at
// (4*x+2,4*y+2) on a 320x180 grid; the largest connected component is
// approximated by its streaming bounding box.  This module deliberately uses
// no RAM, DSP, or combinational divider.  A serial restoring divider computes
// 1786*210 / paper_width_px, and a 16-cycle double-dabble formatter produces
// four millimetres BCD digits for the HDMI overlay.
module a4_distance_measure #(
    parameter integer FX_PX = 1786,
    parameter integer A4_WIDTH_MM = 210,
    parameter integer MIN_AREA = 256
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        capture_pulse,
    input  wire        frame_valid,
    input  wire        frame_user,
    input  wire        frame_last,
    input  wire [95:0] rgb4,
    output reg         result_valid,
    output reg [15:0]  distance_mm,
    output reg [15:0]  distance_bcd,
    output reg [15:0]  paper_width_px,
    output reg         result_toggle,
    output reg         busy
);
    localparam integer NUMERATOR = FX_PX * A4_WIDTH_MM;

    reg [8:0] x_word;
    reg [9:0] y_line;
    reg [8:0] xmin,xmax;
    reg [7:0] ymin,ymax;
    reg [17:0] area;
    reg frame_seen, capture_armed, scan_active;

    // The 96-bit RGB bus is four pixels in descending lane order:
    //   [95:72] = pixel 0, [71:48] = pixel 1,
    //   [47:24] = pixel 2, [23:0] = pixel 3.
    // The 320x180 reference grid samples (4*x+2, 4*y+2), therefore lane 2
    // must be used here.  The previous implementation read lane 1, which
    // introduced a one-pixel horizontal phase error relative to the stated
    // camera sampling contract.
    wire [7:0] r2 = rgb4[47:40];
    wire [7:0] g2 = rgb4[39:32];
    wire [7:0] b2 = rgb4[31:24];
    // The distance stream only needs a bright neutral-paper reject.  Testing
    // all three channels directly is equivalent to a conservative Y/chroma
    // test for the white sheet and avoids the wide RGB max/min and weighted-Y
    // adders that made the previous diagnostic version overflow the SLICEL
    // field during placement.
    wire white_sample = (r2 >= 8'd180) && (g2 >= 8'd180) && (b2 >= 8'd180);
    wire sample_line = (y_line[1:0] == 2'd2);
    wire [7:0] sample_y = y_line[9:2];

    // A complete paper must have a margin from all four image edges and an
    // A4-like portrait aspect.  The bounds intentionally tolerate moderate
    // perspective while rejecting a white wall or a clipped sheet.
    wire [9:0] box_w_s = (xmax>=xmin) ? (xmax-xmin+1'b1) : 10'd0;
    wire [8:0] box_h_s = (ymax>=ymin) ? (ymax-ymin+1'b1) : 9'd0;
    wire [15:0] box_w_px = {4'd0,box_w_s,2'b00};
    wire [16:0] box_area = area;
    // Keep the stream-side reject multiplier-free.  The software reference
    // applies the exact connected-component fill and A4 aspect tests.  This
    // hardware diagnostic path has only a sampled bounding box, so the
    // minimum area and coarse portrait bounds below are the useful checks;
    // implementing bbox-area and *10/*11/*19 here would infer DSPs that the
    // main board does not have spare.
    wire [9:0] box_w_dbl = {box_w_s[8:0],1'b0};
    wire box_ok = (box_area >= MIN_AREA) && (box_w_s >= 10'd20) &&
                  (box_h_s >= 9'd28) && (xmin > 0) && (xmax < 9'd319) &&
                  (ymin > 0) && (ymax < 8'd179) &&
                  (box_h_s >= box_w_s[8:0]) &&
                  (box_h_s <= box_w_dbl[8:0]);

    // Serial restoring division: NUMERATOR / box_w_px, 20 iterations.
    reg [19:0] div_num,div_quot;
    reg [20:0] div_rem;
    reg [15:0] div_den;
    reg [5:0] div_count;
    reg div_busy;
    wire [20:0] div_rem_shift = {div_rem[19:0],div_num[19]};
    wire div_take = (div_den!=0) && (div_rem_shift >= {5'd0,div_den});
    wire [20:0] div_rem_next = div_take ? div_rem_shift-{5'd0,div_den} : div_rem_shift;
    wire [19:0] div_quot_next = {div_quot[18:0],div_take};

    // Double dabble converts distance in millimetres to four BCD digits.
    reg [15:0] bcd_bin;
    reg [19:0] bcd_work;
    reg [4:0] bcd_count;
    reg bcd_busy;
    function [19:0] bcd_add3;
        input [19:0] v;
        reg [19:0] t;
        begin
            t=v;
            if(t[3:0]>=5)   t[3:0]=t[3:0]+3;
            if(t[7:4]>=5)   t[7:4]=t[7:4]+3;
            if(t[11:8]>=5)  t[11:8]=t[11:8]+3;
            if(t[15:12]>=5) t[15:12]=t[15:12]+3;
            bcd_add3=t;
        end
    endfunction
    wire [19:0] bcd_adj = bcd_add3(bcd_work);
    wire [19:0] bcd_shift = {bcd_adj[18:0],bcd_bin[15]};

    task commit_frame;
        begin
            if(box_ok && box_w_px!=0) begin
                paper_width_px <= box_w_px;
                div_num <= NUMERATOR[19:0];
                div_den <= box_w_px;
                div_rem <= 0;
                div_quot <= 0;
                div_count <= 0;
                div_busy <= 1'b1;
                busy <= 1'b1;
            end else begin
                // Keep the last valid value in distance_bcd, but mark this
                // measurement invalid so the OSD can say NO TARGET.
                result_valid <= 1'b0;
                paper_width_px <= 0;
                result_toggle <= ~result_toggle;
                busy <= 1'b0;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x_word<=0; y_line<=0; xmin<=9'h1ff; xmax<=0; ymin<=8'hff; ymax<=0;
            area<=0; frame_seen<=0; capture_armed<=0; scan_active<=0;
            result_valid<=0; distance_mm<=0; distance_bcd<=0; paper_width_px<=0;
            result_toggle<=0; busy<=0;
            div_num<=0;div_quot<=0;div_rem<=0;div_den<=0;div_count<=0;div_busy<=0;
            bcd_bin<=0;bcd_work<=0;bcd_count<=0;bcd_busy<=0;
        end else begin
            if(!enable) begin
                capture_armed <= 1'b0;
                scan_active <= 1'b0;
            end
            if(capture_pulse && enable)
                capture_armed <= 1'b1;

            if(div_busy) begin
                div_num <= {div_num[18:0],1'b0};
                div_rem <= div_rem_next;
                div_quot <= div_quot_next;
                if(div_count==6'd19) begin
                    distance_mm <= div_quot_next[15:0];
                    bcd_bin <= div_quot_next[15:0];
                    bcd_work <= 0;
                    bcd_count <= 0;
                    bcd_busy <= 1'b1;
                    div_busy <= 1'b0;
                end else begin
                    div_count <= div_count+1'b1;
                end
            end
            if(bcd_busy) begin
                bcd_bin <= {bcd_bin[14:0],1'b0};
                bcd_work <= bcd_shift;
                if(bcd_count==5'd15) begin
                    distance_bcd <= bcd_shift[15:0];
                    result_valid <= 1'b1;
                    result_toggle <= ~result_toggle;
                    bcd_busy <= 1'b0;
                    busy <= 1'b0;
                end else begin
                    bcd_count <= bcd_count+1'b1;
                end
            end

            if(frame_user) begin
                if(frame_seen && scan_active) commit_frame();
                frame_seen <= 1'b1;
                scan_active <= capture_armed;
                capture_armed <= 1'b0;
                x_word<=0; y_line<=0; xmin<=9'h1ff; xmax<=0; ymin<=8'hff; ymax<=0; area<=0;
            end else if(enable && frame_valid) begin
                if(scan_active && sample_line && white_sample) begin
                    if(x_word<xmin) xmin<=x_word;
                    if(x_word>xmax) xmax<=x_word;
                    if(sample_y<ymin) ymin<=sample_y;
                    if(sample_y>ymax) ymax<=sample_y;
                    area<=area+1'b1;
                end
                if(frame_last) begin x_word<=0; y_line<=y_line+1'b1; end
                else x_word<=x_word+1'b1;
            end
        end
    end
endmodule
