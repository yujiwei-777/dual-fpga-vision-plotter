// Simulation-only leaves. Never included by the FPGA project.
module pll
(
  input                         refclk,
  input                         reset,
  output                        clk0_out,
  output                        clk1_out,
  output                        clk2_out,
  output                        lock
);
assign clk0_out=refclk&&!reset; assign clk1_out=refclk&&!reset; assign lock=!reset;
endmodule

module PLL
(
  input                         refclk,
  output                        clk0_out,
  output                        clk1_out,
  output                        clk4_out,
  output                        clk5_out,
  output                        lock,
  input                         reset
);
assign clk0_out=refclk&&!reset; assign lock=!reset;
endmodule

module secondary_ddr_wrapper (
    input wire         I_sys_clk,
    input wire         I_sys_rst_n,

    output wire        O_ddr_clk,
    output  wire       O_init_calib_complete,
    input  wire[24:0]  I_mc_app_addr,
    input  wire[2:0]   I_mc_app_cmd,
    input  wire        I_mc_app_en,
    input  wire[127:0] I_mc_app_wdf_data,
    input  wire        I_mc_app_wdf_end,
    input  wire[15:0]  I_mc_app_wdf_mask,
    input  wire        I_mc_app_wdf_wren,
    output wire[127:0] O_mc_app_rd_data,
    output wire        O_mc_app_rd_data_end,
    output wire        O_mc_app_rd_data_valid,
    output wire        O_mc_app_rdy,
    output wire        O_mc_app_wdf_rdy,


    output wire[12:0]  ddr_addr,
    output wire[1:0]   ddr_ba,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_cs_n,
    output wire        ddr_ras_n,
    output wire        ddr_cas_n,
    output wire        ddr_we_n,
    output wire        ddr_ck_p,
    output wire        ddr_ck_n,
    inout wire[1:0]    ddr_dm,
    inout wire[15:0]   ddr_dq,
    inout wire[1:0]    ddr_dqs_p,
    inout wire[1:0]    ddr_dqs_n   

);
assign O_ddr_clk=I_sys_clk; assign O_init_calib_complete=I_sys_rst_n;
endmodule

module hxa_ddr_store(
    input wire clk,rst_n,wr_valid,input wire [20:0] wr_byte_addr,
    input wire [127:0] wr_data,output wire wr_ready,wr_idle,
    input wire rd_req,input wire [20:0] rd_byte_addr,
    output wire rd_ready,output reg rd_valid,output reg [127:0] rd_data,
    input wire ddr_clk,ddr_rst_n,calibrated,
    output wire [24:0] app_addr,output wire [2:0] app_cmd,
    output wire app_en,output wire [127:0] app_wdf_data,
    output wire app_wdf_end,output wire [15:0] app_wdf_mask,output wire app_wdf_wren,
    input wire app_rdy,app_wdf_rdy,app_rd_data_valid,input wire [127:0] app_rd_data
);

endmodule

module uiudp_stack #
(
parameter               CRC_GEN_EN        = 1'b1,          
parameter               INTER_FRAME_GAP   = 4'd12          
)
(   
input  wire             I_uclk,                 
input  wire             I_reset,                
input  wire[47:0]       I_mac_local_addr,       
input  wire[15:0]       I_udp_local_port,       
input  wire[31:0]       I_ip_local_addr,        

input  wire[15:0]		I_udp_dest_port,        
input  wire[31:0]		I_ip_dest_addr,         

output wire             O_W_udp_busy,		    
input  wire             I_W_udp_req,            
input  wire             I_W_udp_valid,          
input  wire[7:0]        I_W_udp_data,           
input  wire[15:0]		I_W_udp_len,            
			
output wire             O_R_udp_valid,          
output wire [7:0]       O_R_udp_data,           
output wire [15:0]      O_R_udp_len,             
output wire [15:0]      O_R_udp_src_port,       

input                   I_gmii_rclk,            
input                   I_gmii_rvalid,          
input [7:0]        		I_gmii_rdata,	        

input                   I_gmii_tclk,	        
output wire             O_gmii_tvalid,          
output wire [7:0]       O_gmii_tdata,           
		
output wire             O_ip_rerror,            
output wire 			O_mac_rerror            
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

module vision_pipeline #(
    parameter integer EXTERNAL_READER=0,
    
    
    
    parameter integer LOCAL_CNN_ENABLE=1,
    parameter integer SHARED_WORKSPACE=1,
    
    
    
    parameter integer PCB_ENABLE=1,
    
    
    
    parameter integer PCB_COMPACT_ROM=0,
    parameter PCB_WEIGHTS_MEM="../model/pcb_tinycnn_weights.mem",
    parameter PCB_BIASES_MEM="../model/pcb_tinycnn_bias.mem",
    parameter PCB_FIRST_MEM="../model/pcb_tinycnn_first.mem",
    parameter PCB_NEXT_MEM="../model/pcb_tinycnn_next.mem",
    parameter PCB_TAPS_MEM="../model/pcb_tinycnn_taps.mem",
    parameter integer PCB_TIMEOUT_CYCLES=4000000,
    parameter integer PCB_MARGIN_MIN=115,
    
    
    
    parameter integer PCB_REVIEW_ENABLE=0,
    
    parameter integer PCB_FULLBOARD_SPATIAL96=0,
    
    
    
    parameter integer PCB_BINARY_CLASSES=0,
    parameter integer PCB_BINARY_MARGIN_MIN=32,
    parameter integer PCB_FULLBOARD_C1_CHANNELS=8,
    parameter integer PCB_FULLBOARD_C2_CHANNELS=12,
    parameter integer PCB_FULLBOARD_C1_SHIFT=7,
    parameter integer PCB_FULLBOARD_C2_SHIFT=6,
    parameter integer PCB_FULLBOARD_HEAD_SHIFT=7,
    parameter PCB_FULLBOARD_WEIGHTS_MEM="../model/fullboard/weights.mem",
    parameter PCB_FULLBOARD_BIASES_MEM="../model/fullboard/biases.mem",
    parameter integer PCB_FULL_X=160,
    parameter integer PCB_FULL_Y=140,
    parameter integer PCB_FULL_W=960,
    parameter integer PCB_FULL_H=410,
    
    
    parameter integer PCB_FIXED_WINDOW_ONLY=0,
    parameter integer PCB_FIXED_WINDOW_X=592,
    parameter integer PCB_FIXED_WINDOW_Y=312,
    parameter integer COLOR_MARGIN_MIN=0,
    parameter integer TRIANGLE_MARGIN_MIN=31,
    parameter integer CIRCLE_MARGIN_MIN=28,
    parameter integer SQUARE_MARGIN_MIN=77,
    
    parameter integer CNN_LOWCONF_OUTPUT=0,
    parameter integer CNN_STABILITY_ENABLE=1,
    parameter integer CNN_CONFIRM_RESULTS=3,
    parameter integer CNN_HOLD_RESULTS=2,
    parameter integer CNN_LOST_RESULTS=3
)(
    input wire clk,rst_n,start,
    input wire [1:0] purpose,
    input wire teach_good,cancel,
    input wire [31:0] job_id,
    output wire word_req,
    output wire [20:0] byte_addr,
    input wire word_ready,word_valid,
    input wire [127:0] word_data,
    input wire cfg_we,
    input wire [14:0] cfg_addr,
    input wire [7:0] cfg_data,
    input wire cfg_commit,
    output reg busy,done,
    output reg [31:0] result_job_id,config_version,
    output reg [1:0] color_id,shape_id,
    output reg [7:0] confidence,
    output reg valid,
    output reg [10:0] x0,x1,
    output reg [9:0] y0,y1,
    output reg [23:0] area,
    output reg pcb_checked,pcb_good,
    output reg [2:0] pcb_status, 
    output wire [2:0] defect_count,
    output wire [255:0] defect_boxes,
    output wire [7:0] defect_kinds,
    
    
    output reg [2:0] multi_count,
    output reg [511:0] multi_boxes,
    output reg [7:0] multi_flags,
    output reg teach_success,teach_failed,output reg [15:0] teach_code,
    output wire teach_commit,output reg [255:0] taught_station_header,
    
    
    
    input wire ext_reader_ready,ext_reader_valid,
    input wire [23:0] ext_reader_rgb,
    input wire [7:0] ext_reader_luma,
    output wire ext_reader_request,ext_reader_invalidate,
    output wire [10:0] ext_pixel_x,
    output wire [9:0] ext_pixel_y,
    
    
    
    output wire yolo_pixel_valid,
    output wire [23:0] yolo_pixel_rgb,
    output wire yolo_pixel_last,
    
    
    output wire color_word_active,
    
    
    
    input wire history_clear
);

endmodule

module hxa_config_store #(
    parameter integer MAX_BYTES=16520
)(
    input wire I_clk,input wire I_rst_n,input wire I_begin,input wire I_abort,
    input wire I_local_apply,input wire [255:0] I_local_header,
    input wire [14:0] I_total_bytes,input wire [31:0] I_version,
    input wire [2:0] I_good_count,input wire [2:0] I_bad_count,
    input wire [31:0] I_expected_crc32,
    input wire I_byte_valid,input wire [14:0] I_byte_addr,input wire [7:0] I_byte_data,
    output wire O_byte_ready,input wire I_commit,input wire I_job_idle,
    output wire O_cfg_ready,output reg O_commit_ack,output reg O_commit_error,output reg O_apply,
    output reg [255:0] O_station_header,output reg O_station_valid,
    output reg O_profile_valid,output reg O_profile_pwm_mode,output reg [7:0] O_profile_step_cmm,
    output reg [15:0] O_origin_x_cmm,output reg [15:0] O_origin_y_cmm,
    output reg [15:0] O_work_x_cmm,output reg [15:0] O_work_y_cmm,
    output reg signed [15:0] O_pen_up_cmm,output reg signed [15:0] O_pen_down_cmm,
    output reg [15:0] O_pen_up_pwm,output reg [15:0] O_pen_down_pwm,
    output reg [15:0] O_travel_feed,output reg [15:0] O_draw_feed,output reg [15:0] O_pen_feed,
    output reg [31:0] O_profile_id
);

endmodule

module doc_copy_pipeline #(
    parameter integer CLK_HZ=125000000,
    parameter integer PREP_TIMEOUT_MS=30000,
    parameter integer PLANNER_OPT_PASSES=2,
    
    
    
    parameter integer FRAME_AS_A4_WIDTH=1,
    
    
    parameter integer EXTERNAL_ADMISSION_GUARD=0
)(
    input wire clk,rst_n,start,cancel,rearm,reset_job,
    input wire admission_inhibit,
    input wire [31:0] job_id,
    
    
    
    input wire [15:0] paper_width_px,
    output wire busy,output reg done,
    output wire recovery_required,
    output reg status_valid,output reg [95:0] status_data,input wire status_ready,
    output wire pixel_request,pixel_invalidate,
    output wire [10:0] pixel_x,output wire [9:0] pixel_y,
    input wire pixel_ready,pixel_valid,input wire [7:0] pixel_luma,
    output wire [7:0] tx_data,output wire tx_valid,
    input wire tx_ready,tx_done,
    input wire [7:0] rx_data,input wire rx_valid,rx_error,link_ready,
    output wire [7:0] rt_data,output wire rt_valid,input wire rt_ready,
    output wire uart_owner,
    output wire [127:0] paper_corners,
    output wire [15:0] edge_count,output wire [11:0] path_count,
    output wire [13:0] point_count,
    output wire [63:0] baseline_distance,planned_distance
);

endmodule

module rgmii_interface #(
    parameter RGMII_ID = 1'b0,   
    parameter TXC_USE_90 = 1'b1, 
    parameter TXC_DELAY_ENABLE = 1'b0,
    parameter [4:0] TXC_DELAY_VALUE = 5'd0,
    parameter RX_DELAY_ENABLE = 1'b1,
    parameter [4:0] RX_DELAY_VALUE = 5'd31,
    
    
    parameter RXC_USE_IOCLK = 1'b0
) (

input            speed_10_100,   

input			     gmii_tx_clk_d,    
input			     gmii_tx_reset_d,   

output     [3:0] rgmii_txd,
output           rgmii_tx_ctl,
output           rgmii_txc,

input      [3:0] rgmii_rxd,
input            rgmii_rx_ctl,
input            rgmii_rxc,

input            gmii_tx_reset,
input            gmii_tx_clk,      
input      [7:0] gmii_txd,
input            gmii_tx_en,
input            gmii_tx_er,

input            gmii_rx_reset,
output               gmii_rx_clk,    
output reg    [7:0] gmii_rxd,
output reg          gmii_rx_dv,
output reg          gmii_rx_er,

output           gmii_crs,
output           gmii_col,

output reg       link_status,
output reg [1:0] clock_speed,
output reg       duplex_status
);

endmodule

module PH1P_LOGIC_BUFG(input i,output o); assign o=i; endmodule
