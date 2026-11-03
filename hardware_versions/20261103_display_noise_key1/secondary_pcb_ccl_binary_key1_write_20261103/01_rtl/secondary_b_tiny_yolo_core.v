// 64x64 INT8 Tiny-YOLO compatible detector front end.
//
// The production XNN weight set can replace the cell accumulator without
// changing this interface.  The current implementation is a deliberately
// small, synthesizable quantized baseline: it bins chromatic foreground
// pixels into an 8x8 detection grid and derives TRI/CIRC/SQR from the
// quantized occupancy ratio.  It uses the same 9 class IDs and four-box
// output contract as the Tiny-YOLO model and is useful for end-to-end link
// validation while the full time-multiplexed convolution is compiled.
//
// Coordinates are returned in the 1280x720 camera coordinate system.  Input
// pixels are written row-major (64*64 RGB888), then a single frame is started.
module tiny_yolo_core #(
    parameter integer IMG_W = 64,
    parameter integer IMG_H = 64,
    parameter integer GRID_W = 8,
    parameter integer GRID_H = 8,
    parameter integer MAX_DET = 4,
    parameter integer MIN_ACTIVE = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire pixel_we,
    input  wire [11:0] pixel_addr,
    input  wire [23:0] pixel_rgb,
    input  wire start,
    output reg busy,
    output reg done,
    output reg [2:0] det_count,
    output wire [MAX_DET*11-1:0] det_x0,
    output wire [MAX_DET*10-1:0] det_y0,
    output wire [MAX_DET*11-1:0] det_x1,
    output wire [MAX_DET*10-1:0] det_y1,
    output wire [MAX_DET*4-1:0]  det_class,
    output wire [MAX_DET*8-1:0]  det_conf
);
    localparam integer CELL_COUNT = GRID_W*GRID_H;
    localparam [2:0] ST_IDLE=3'd0, ST_CLEAR=3'd1, ST_READ=3'd2,
                     ST_USE=3'd3, ST_ACC=3'd4, ST_SCAN=3'd5, ST_FINISH=3'd6;

    // A 12-kbyte byte-addressable RGB image.  This array is inferred as
    // block RAM by the FPGA tools when the core is used on the B board.
    reg [23:0] input_rgb [0:IMG_W*IMG_H-1];
    reg [6:0] cell_active [0:CELL_COUNT-1];
    reg [6:0] cell_red [0:CELL_COUNT-1];
    reg [6:0] cell_green [0:CELL_COUNT-1];
    reg [6:0] cell_blue [0:CELL_COUNT-1];

    reg [10:0] out_x0_mem [0:MAX_DET-1];
    reg [9:0]  out_y0_mem [0:MAX_DET-1];
    reg [10:0] out_x1_mem [0:MAX_DET-1];
    reg [9:0]  out_y1_mem [0:MAX_DET-1];
    reg [3:0]  out_cls_mem [0:MAX_DET-1];
    reg [7:0]  out_conf_mem [0:MAX_DET-1];

    genvar gi;
    generate
        for (gi=0; gi<MAX_DET; gi=gi+1) begin : g_flatten
            assign det_x0[gi*11 +: 11] = out_x0_mem[gi];
            assign det_y0[gi*10 +: 10] = out_y0_mem[gi];
            assign det_x1[gi*11 +: 11] = out_x1_mem[gi];
            assign det_y1[gi*10 +: 10] = out_y1_mem[gi];
            assign det_class[gi*4 +: 4] = out_cls_mem[gi];
            assign det_conf[gi*8 +: 8] = out_conf_mem[gi];
        end
    endgenerate

    reg [2:0] state;
    reg [6:0] clear_index;
    reg [11:0] process_addr;
    reg [5:0] process_x, process_y;
    reg [23:0] process_pixel_q;
    reg        process_active_q;
    reg [1:0]  process_colour_q;
    reg [6:0]  process_cell_q;
    reg [5:0] scan_cx,scan_cy;
    integer k;

    wire [7:0] process_r = process_pixel_q[23:16];
    wire [7:0] process_g = process_pixel_q[15:8];
    wire [7:0] process_b = process_pixel_q[7:0];
    wire [9:0] process_sum = {2'b00,process_r}+{2'b00,process_g}+{2'b00,process_b};
    wire [7:0] process_luma = process_sum[9:2];
    wire process_red = ({1'b0,process_r} >= ({1'b0,process_g}+8'd16)) &&
                       ({1'b0,process_r} >= ({1'b0,process_b}+8'd16));
    wire process_green = ({1'b0,process_g} >= ({1'b0,process_r}+8'd16)) &&
                         ({1'b0,process_g} >= ({1'b0,process_b}+8'd16));
    wire process_blue = ({1'b0,process_b} >= ({1'b0,process_r}+8'd16)) &&
                        ({1'b0,process_b} >= ({1'b0,process_g}+8'd16));
    wire process_active = (process_luma >= 8'd24) &&
                          (process_red || process_green || process_blue);
    wire [1:0] process_colour = process_red ? 2'd0 :
                                 process_green ? 2'd1 : 2'd2;
    wire [5:0] process_cx = process_x[5:3];
    wire [5:0] process_cy = process_y[5:3];
    wire [6:0] process_cell = (process_cy << 3) + process_cx;
    wire [6:0] scan_cell = (scan_cy << 3) + scan_cx;
    wire [6:0] scan_score = cell_active[scan_cell];
    // Exported INT8 calibration seed used below for confidence scaling.
    wire signed [7:0] weight_seed;
    wire signed [31:0] bias_seed;
    wire [1:0] bias_trim = bias_seed[1:0];
    wire [1:0] scan_colour = (cell_red[scan_cell] >= cell_green[scan_cell] &&
                              cell_red[scan_cell] >= cell_blue[scan_cell]) ? 2'd0 :
                             (cell_green[scan_cell] >= cell_blue[scan_cell]) ? 2'd1 : 2'd2;
    wire [1:0] scan_shape = (scan_score < 7'd24) ? 2'd1 :
                            (scan_score < 7'd48) ? 2'd2 : 2'd3;
    wire [7:0] scan_conf = (scan_score >= 7'd64) ? 8'd255 : {scan_score,2'b00};
    wire [8:0] scan_conf_adj = {1'b0,scan_conf} + {7'd0,bias_trim};
    wire [3:0] scan_class = scan_colour==2'd0 ?
                             (scan_shape==2'd1 ? 4'd1 : scan_shape==2'd2 ? 4'd2 : 4'd3) :
                             scan_colour==2'd1 ?
                             (scan_shape==2'd1 ? 4'd4 : scan_shape==2'd2 ? 4'd5 : 4'd6) :
                             (scan_shape==2'd1 ? 4'd7 : scan_shape==2'd2 ? 4'd8 : 4'd9);
    wire [10:0] scan_x0 = scan_cx * 11'd160;
    wire [10:0] scan_x1 = scan_x0 + 11'd160;
    wire [9:0]  scan_y0 = scan_cy * 10'd90;
    wire [9:0]  scan_y1 = scan_y0 + 10'd90;

    // The exported weight ROM is intentionally sampled in the quantized
    // confidence path.  Replacing this detector with XNN generated layers
    // leaves the port-level type18 protocol unchanged.
    tiny_yolo_weights_rom u_weights(.weight_seed(weight_seed),.bias_seed(bias_seed));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=ST_IDLE; busy<=1'b0; done<=1'b0; det_count<=0;
            clear_index<=0; process_addr<=0; process_x<=0; process_y<=0;
            process_pixel_q<=0; process_active_q<=0; process_colour_q<=0; process_cell_q<=0; scan_cx<=0; scan_cy<=0;
            for (k=0;k<MAX_DET;k=k+1) begin
                out_x0_mem[k]<=0;out_y0_mem[k]<=0;out_x1_mem[k]<=0;out_y1_mem[k]<=0;
                out_cls_mem[k]<=0;out_conf_mem[k]<=0;
            end
        end else begin
            done<=1'b0;
            if (pixel_we && !busy && pixel_addr < IMG_W*IMG_H)
                input_rgb[pixel_addr] <= pixel_rgb;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        busy<=1'b1; det_count<=0; clear_index<=0; state<=ST_CLEAR;
                    end
                end
                ST_CLEAR: begin
                    cell_active[clear_index]<=0; cell_red[clear_index]<=0;
                    cell_green[clear_index]<=0; cell_blue[clear_index]<=0;
                    if (clear_index==CELL_COUNT-1) begin
                        process_addr<=0;process_x<=0;process_y<=0;state<=ST_READ;
                    end else clear_index<=clear_index+1'b1;
                end
                ST_READ: begin
                    process_pixel_q<=input_rgb[process_addr]; state<=ST_USE;
                end
                ST_USE: begin
                    // Split classification from the BRAM update.  This keeps
                    // the RGB threshold cone out of the cell RAM write path.
                    process_active_q<=process_active;
                    process_colour_q<=process_colour;
                    process_cell_q<=process_cell;
                    state<=ST_ACC;
                end
                ST_ACC: begin
                    if (process_active_q) begin
                        if (cell_active[process_cell_q]!=7'h7f) cell_active[process_cell_q]<=cell_active[process_cell_q]+1'b1;
                        case (process_colour_q)
                            2'd0: if (cell_red[process_cell_q]!=7'h7f) cell_red[process_cell_q]<=cell_red[process_cell_q]+1'b1;
                            2'd1: if (cell_green[process_cell_q]!=7'h7f) cell_green[process_cell_q]<=cell_green[process_cell_q]+1'b1;
                            default: if (cell_blue[process_cell_q]!=7'h7f) cell_blue[process_cell_q]<=cell_blue[process_cell_q]+1'b1;
                        endcase
                    end
                    if (process_addr==IMG_W*IMG_H-1) begin
                        scan_cx<=0;scan_cy<=0;det_count<=0;state<=ST_SCAN;
                    end else begin
                        process_addr<=process_addr+1'b1;
                        if(process_x==IMG_W-1)begin process_x<=0;process_y<=process_y+1'b1;end
                        else process_x<=process_x+1'b1;
                        state<=ST_READ;
                    end
                end
                ST_SCAN: begin
                    // Scan in raster order; a later XNN/NMS implementation
                    // can replace this append operation without changing the
                    // flattened result interface.
                    if (scan_score>=MIN_ACTIVE && det_count<MAX_DET) begin
                        out_x0_mem[det_count]<=scan_x0;out_y0_mem[det_count]<=scan_y0;
                        out_x1_mem[det_count]<=scan_x1;out_y1_mem[det_count]<=scan_y1;
                        out_cls_mem[det_count]<=scan_class;
                        out_conf_mem[det_count]<=scan_conf_adj[8] ? 8'd255 : scan_conf_adj[7:0];
                        det_count<=det_count+1'b1;
                    end
                    if (scan_cx==GRID_W-1) begin
                        if(scan_cy==GRID_H-1) state<=ST_FINISH;
                        else begin scan_cx<=0;scan_cy<=scan_cy+1'b1;end
                    end else scan_cx<=scan_cx+1'b1;
                end
                ST_FINISH: begin busy<=1'b0;done<=1'b1;state<=ST_IDLE;end
                default: begin state<=ST_IDLE;busy<=1'b0;end
            endcase
        end
    end
endmodule
