// Test-only interfaces. Never synthesis inputs.
module vision_color_stats(
    input wire clk,rst_n,start,cancel,
    input wire [10:0] box_x0,box_x1,
    input wire [9:0] box_y0,box_y1,
    output reg busy,done,
    output reg [1:0] color_id,
    output reg [7:0] color_conf,
    output reg [19:0] valid_samples,count_r,count_g,count_b,
    output wire word_req,
    output reg [20:0] byte_addr,
    input wire word_ready,word_valid,
    input wire [127:0] word_data
);
endmodule

module edge_roi_ccl_shared_pcb_candidate #(
    parameter integer WIDTH=160,
    parameter integer HEIGHT=90,
    parameter integer EDGE_THRESHOLD=32,
    parameter integer MIN_EDGE_AREA=12
)(
    input wire clk,rst_n,start,
    input wire [8:0] width,
    input wire [7:0] height,
    input wire [15:0] min_area,
    input wire filter_shape,
    input wire pcb_mode,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    input wire [7:0] pixel_luma,
    output wire pixel_ready,
    output reg busy,done,overflow,
    output reg [2:0] count,
    output reg [255:0] boxes,
    output reg [15:0] largest_area,
    output reg [1:0] largest_color,
    output reg [63:0] areas,
    output reg truncated
);
endmodule

module cnn_core #(
    parameter WEIGHTS_MEM = "model/export/weights.mem",
    parameter BIASES_MEM = "model/export/biases.mem",
    parameter integer C1_SHIFT = 10,
    parameter integer C2_SHIFT = 8,
    parameter integer FC_CONF_SHIFT = 7,
    parameter integer USE_SHARED_WORKSPACE = 0,
    parameter integer EXTERNAL_MAC = 0
)(
    input wire clk,input wire rst_n,input wire pixel_we,input wire [11:0] pixel_addr,
    input wire [23:0] pixel_rgb,input wire start,
    output reg busy,output reg done,output reg [1:0] color_id,output reg [1:0] shape_id,
    output reg [7:0] color_conf,output reg [7:0] shape_conf,output reg background_reject,
    output wire ws_shape_we, output wire [11:0] ws_shape_waddr, output wire [15:0] ws_shape_wdata,
    output wire ws_f1_we, output wire [12:0] ws_f1_waddr, output wire [15:0] ws_f1_wdata,
    output wire ws_f2_we, output wire [11:0] ws_f2_waddr, output wire [15:0] ws_f2_wdata,
    output wire [1:0] ws_rd_sel, output wire [12:0] ws_rd_addr, input wire [7:0] ws_rd_data,
    output wire signed [15:0] mac_a, output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext
);
endmodule

module pcb_pose7_core #(
    parameter WEIGHTS_MEM="../model/pose7_96x96/weights.mem",
    parameter BIASES_MEM="../model/pose7_96x96/biases.mem",
    parameter CENTRE_MEM="../model/pose7_96x96/feature_centre.mem",
    parameter TOLERANCE_MEM="../model/pose7_96x96/feature_tolerance.mem",
    parameter ORIENTATION_MEM="../model/pose7_96x96/orientation_reference.mem",
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer ABORT_TIMEOUT=8192,
    parameter integer PASS_THRESHOLD=106,
    parameter integer FAIL_THRESHOLD=205
)(
    input wire clk,rst_n,start,cancel,frame_valid,model_valid,
    input wire [31:0] job_id,
    input wire [2:0] I_ccl_count,
    input wire [255:0] I_ccl_boxes,
    input wire I_ccl_overflow,I_ccl_truncated,
    output wire busy,frame_lock,
    output reg done,result_valid,no_target,
    output reg [1:0] status,
    output reg [15:0] error,
    output reg bbox_valid,
    output reg [10:0] xmin,xmax,
    output reg [9:0] ymin,ymax,
    output reg [11:0] detail_score,
    output wire [15:0] outline_support,
    output wire pixel_request,
    output wire [10:0] pixel_x,
    output wire [9:0] pixel_y,
    input wire pixel_ready,pixel_valid,
    input wire [7:0] pixel_y8,
    output reg ws_we,ws_wbank,
    output reg [14:0] ws_waddr,
    output reg [15:0] ws_wdata,
    output reg ws_rd_bank,
    output reg [14:0] ws_rd_addr,
    input wire [15:0] ws_rd_data,
    output reg signed [15:0] mac_a,
    output reg signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext,
    output wire [7:0] phase,
    output reg [47:0] cycles
);
endmodule

module vision_shared_mac(
    input  wire               pcb_select,
    input  wire signed [15:0] cnn_a,
    input  wire signed [7:0]  cnn_w,
    input  wire signed [15:0] pcb_a,
    input  wire signed [7:0]  pcb_w,
    output wire signed [23:0] product,
    output wire signed [23:0] cnn_product,
    output wire signed [23:0] pcb_product
);
endmodule

module vision_workspace_goodonly #(
    parameter BANK0_INIT_FILE="",
    parameter BANK1_INIT_FILE=""
) (
    input wire clk,
    input wire [1:0] purpose,
    input wire cnn_shape_we,
    input wire [11:0] cnn_shape_waddr,
    input wire [15:0] cnn_shape_wdata,
    input wire cnn_f1_we,
    input wire [12:0] cnn_f1_waddr,
    input wire [15:0] cnn_f1_wdata,
    input wire cnn_f2_we,
    input wire [11:0] cnn_f2_waddr,
    input wire [15:0] cnn_f2_wdata,
    input wire [1:0] cnn_rd_sel,
    input wire [12:0] cnn_rd_addr,
    output wire [7:0] cnn_rd_data,
    input wire pcb_we,
    input wire pcb_wbank,
    input wire [14:0] pcb_waddr,
    input wire [15:0] pcb_wdata,
    input wire pcb_rd_bank,
    input wire [14:0] pcb_rd_addr,
    output wire [15:0] pcb_rd_data
);
endmodule
