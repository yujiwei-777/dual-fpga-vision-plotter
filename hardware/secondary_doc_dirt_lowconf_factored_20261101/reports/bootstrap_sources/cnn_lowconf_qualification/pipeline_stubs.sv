// Controlled test leaves, excluded from every synthesis project.
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

module vision_pixel_reader(
    input wire clk,rst_n,invalidate,
    input wire request,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    output wire ready,
    output reg pixel_valid,
    output reg [23:0] pixel_rgb,
    output reg [7:0] pixel_y8,
    output wire word_req,
    output reg [20:0] byte_addr,
    input wire word_ready,word_valid,
    input wire [127:0] word_data
);
endmodule

module edge_roi_ccl #(
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

module vision_workspace(
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

module pcb_fullboard_spatial96 #(
    parameter WEIGHTS_MEM = "../model/fullboard/weights.mem",
    parameter BIASES_MEM = "../model/fullboard/biases.mem",
    parameter integer USE_SHARED_WORKSPACE = 1,
    parameter integer EXTERNAL_MAC = 0,
    
    
    
    
    parameter integer HEAD_CLASSES = 3,
    
    
    parameter integer C1_CHANNELS = 8,
    parameter integer C2_CHANNELS = 12,
    
    
    parameter integer C1_SHIFT = 7,
    parameter integer C2_SHIFT = 6,
    parameter integer HEAD_SHIFT = 7
)(
    input wire clk,input wire rst_n,input wire start,
    input wire pixel_we,input wire [13:0] pixel_addr,input wire [7:0] pixel_gray,
    output reg busy,output reg done,output reg [1:0] class_id,
    output reg [7:0] score,output reg [15:0] margin,output wire [15:0] saturation_count,
    output wire ws_we, output wire ws_wbank, output wire [14:0] ws_waddr,
    output wire [15:0] ws_wdata,
    output wire ws_rd_bank, output wire [14:0] ws_rd_addr,
    input wire [15:0] ws_rd_data,
    output wire signed [15:0] mac_a, output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext
);
endmodule

module pcb_tinycnn_core #(
    
    
    parameter WEIGHTS_MEM="../td_project/model/pcb_tinycnn_weights.mem",
    parameter BIASES_MEM="../td_project/model/pcb_tinycnn_bias.mem",
    parameter FIRST_MEM="../td_project/model/pcb_tinycnn_first.mem",
    parameter NEXT_MEM="../td_project/model/pcb_tinycnn_next.mem",
    parameter TAPS_MEM="../td_project/model/pcb_tinycnn_taps.mem",
    parameter integer USE_SHARED_WORKSPACE=0,
    parameter integer EXTERNAL_MAC=0
)(
    input wire clk,input wire rst_n,input wire start,
    input wire pixel_we,input wire [13:0] pixel_addr,input wire [7:0] pixel_gray,
    output reg busy,output reg done,output reg [1:0] class_id,
    output reg [7:0] score,output reg [15:0] margin,output wire [15:0] saturation_count,
    output wire ws_we, output wire ws_wbank, output wire [14:0] ws_waddr, output wire [15:0] ws_wdata,
    output wire ws_rd_bank, output wire [14:0] ws_rd_addr, input wire [15:0] ws_rd_data,
    output wire signed [15:0] mac_a, output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext
);
endmodule

module pcb_tinycnn_core_compact #(
    
    
    parameter WEIGHTS_MEM="../../model/compact/pcb_tinycnn_weights_compact.mem",
    parameter BIASES_MEM="../../model/compact/pcb_tinycnn_bias_compact.mem",
    parameter FIRST_MEM="../../model/compact/pcb_tinycnn_first_compact.mem",
    parameter NEXT_MEM="../../model/compact/pcb_tinycnn_next_compact.mem",
    parameter TAPS_MEM="../../model/compact/pcb_tinycnn_taps_compact.mem",
    parameter integer USE_SHARED_WORKSPACE=0,
    parameter integer EXTERNAL_MAC=0
)(
    input wire clk,input wire rst_n,input wire start,
    input wire pixel_we,input wire [13:0] pixel_addr,input wire [7:0] pixel_gray,
    output reg busy,output reg done,output reg [1:0] class_id,
    output reg [7:0] score,output reg [15:0] margin,output wire [15:0] saturation_count,
    output wire ws_we, output wire ws_wbank, output wire [14:0] ws_waddr, output wire [15:0] ws_wdata,
    output wire ws_rd_bank, output wire [14:0] ws_rd_addr, input wire [15:0] ws_rd_data,
    output wire signed [15:0] mac_a, output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext
);
endmodule

module pcb_defect_cluster #(
    parameter integer MAX_CLUSTERS=4,
    parameter integer DIST_SAME=48,
    parameter integer DIST_MIXED=24,
    parameter integer X_BITS=7,
    parameter integer Y_BITS=6,
    parameter integer COORD_SHIFT=4,
    parameter integer FIXED_WINDOW_GEOMETRY=1,
    parameter integer ENABLE_MIXED_REVIEW=0,
    parameter integer MERGE_UNION_BOUND_ONLY=1,
    parameter integer CLEAR_VALID_ONLY=1
)(
    input wire clk,input wire rst_n,input wire start,
    input wire candidate_valid,input wire candidate_last,
    input wire [63:0] candidate_box,
    input wire [1:0] candidate_kind,input wire [7:0] candidate_score,
    output wire candidate_ready,
    output reg busy,output reg done,output wire [2:0] cluster_count,
    output wire [255:0] cluster_boxes,output wire [7:0] cluster_kinds,
    output wire [31:0] cluster_scores,output wire review_present
);
endmodule
