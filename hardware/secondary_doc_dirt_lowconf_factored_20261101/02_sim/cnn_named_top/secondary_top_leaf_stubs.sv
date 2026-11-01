// Test-only leaf interfaces; excluded from synthesis.
module pll
(
  input                         refclk,
  input                         reset,
  output                        clk0_out,
  output                        clk1_out,
  output                        clk2_out,
  output                        lock
);
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
endmodule

module reset_sync (
    input  wire I_clk,
    input  wire I_async_rst_n,
    output wire O_rst_n
);
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

module hxa_secondary_link #(
    parameter integer CLK_HZ=125000000,
    parameter [7:0] CAPABILITIES=8'h01,
    parameter integer FRAME_CRC_BYTES_PER_CYCLE=1
)(
    input wire clk,rst_n,enable,phy_ready,board_mode,
    output wire udp_req,udp_valid,output wire [7:0] udp_data,
    output wire [15:0] udp_len,input wire udp_busy,
    input wire rx_valid,input wire [7:0] rx_data,input wire [15:0] rx_len,
    input wire rx_error,output wire stack_reset,
    output wire wr_valid,output wire [20:0] wr_byte_addr,output wire [127:0] wr_data,
    input wire wr_ready,wr_idle,
    output wire rd_req,output wire [20:0] rd_byte_addr,
    input wire rd_ready,rd_valid,input wire [127:0] rd_data,
    output reg vision_start,vision_cancel,vision_job_cancel,
    output reg [31:0] vision_frame_id,vision_job_id,output reg [1:0] vision_purpose,
    output reg [15:0] vision_paper_width_px,output wire vision_teach_good,
    
    
    
    
    output reg grbl_test_start,output reg [31:0] grbl_test_job_id,
    output reg grbl_current_start,output reg [31:0] grbl_current_job_id,
    input wire vision_busy,vision_done,input wire [511:0] vision_result,
    
    
    input wire [7:0] vision_result_type,
    input wire [639:0] vision_result_multibox,
    input wire [1791:0] vision_maze_result,
    input wire v_rd_req,input wire [20:0] v_rd_byte_addr,
    output wire v_rd_ready,v_rd_valid,output wire [127:0] v_rd_data,
    output wire cfg_we,output wire [14:0] cfg_addr,output wire [7:0] cfg_data,
    output wire cfg_commit,output wire [31:0] cfg_version,input wire cfg_ready,
    output wire cfg_begin,output wire cfg_abort,output wire [14:0] cfg_total_bytes,
    output wire [31:0] cfg_pending_version,cfg_expected_crc32,
    output wire [2:0] cfg_good_count,cfg_bad_count,
    input wire cfg_apply_ack,cfg_apply_error,
    input wire [255:0] station_header,input wire station_valid,
    input wire [31:0] station_config_version,
    input wire job_status_valid,input wire [95:0] job_status_data,
    output wire job_status_ready,input wire job_busy,
    output reg [63:0] session_id,output reg online,
    output reg [31:0] good_frames,bad_frames,
    output reg copy_rearm
);
endmodule

module grbl_uart_port #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    
    
    parameter integer PROBE_INTERVAL_CYCLES=(CLK_HZ/5)
)(
    input wire I_clk,input wire I_rst_n,
    input wire I_uart_rx,output wire O_uart_tx,input wire I_esp_link_ready,
    output wire O_link_ready,
    input wire [7:0] I_tx_data,input wire I_tx_valid,
    output wire O_tx_ready,output wire O_tx_done,
    output wire [7:0] O_rx_data,output wire O_rx_valid,output wire O_rx_error,
    
    
    input wire [7:0] I_rt_data,input wire I_rt_valid,output wire O_rt_ready,
    output wire O_idle_pulse,output wire O_rt_done
);
endmodule

module grbl_reporter #(
    parameter integer CLK_HZ=50000000,
    parameter integer ACK_TIMEOUT_CYCLES=CLK_HZ*5,
    parameter integer STATUS_TIMEOUT_CYCLES=CLK_HZ*2,
    parameter integer QUERY_INTERVAL_CYCLES=CLK_HZ/5,
    parameter integer STATUS_RETRY_INTERVAL_CYCLES=CLK_HZ/2,
    parameter integer STATUS_MAX_RETRIES=3,
    parameter integer MAZE_ENABLE=1,
    parameter integer AUTO_NEWLINE=0
)(
    input wire I_clk,input wire I_rst_n,input wire I_clear,input wire I_abort,input wire I_stop,input wire I_rearm,
    input wire I_job_valid,input wire [31:0] I_job_id,input wire [63:0] I_session_id,
    
    input wire [2:0] I_job_source,
    input wire [1:0] I_judgement, 
    input wire [2:0] I_defect_count,input wire [255:0] I_defect_boxes,
    
    
    input wire I_maze_mode,input wire [1:0] I_maze_status,
    input wire [8:0] I_maze_steps,input wire [7:0] I_maze_start,I_maze_goal,I_maze_endpoint,
    input wire [511:0] I_maze_directions,input wire [1023:0] I_maze_walls,
    output wire O_job_ready,output wire O_busy,output wire O_done,output wire O_error,
    output wire [7:0] O_error_code,output wire [31:0] O_acked_lines,output wire [2:0] O_job_state,
    output wire O_recovery_required,
    output wire [7:0] O_rt_data,output wire O_rt_valid,input wire I_rt_ready,output wire O_rt_done,
    input wire I_link_ready,input wire I_profile_valid,input wire I_pen_pwm_mode,
    input wire [15:0] I_origin_x_cmm,input wire [15:0] I_origin_y_cmm,
    input wire [15:0] I_work_x_cmm,input wire [15:0] I_work_y_cmm,input wire [7:0] I_step_cmm,
    input wire signed [15:0] I_pen_up_cmm,input wire signed [15:0] I_pen_down_cmm,
    input wire [15:0] I_pen_up_pwm,input wire [15:0] I_pen_down_pwm,
    input wire [15:0] I_travel_feed,input wire [15:0] I_draw_feed,input wire [15:0] I_pen_feed,
    output wire [7:0] O_tx_data,output wire O_tx_valid,input wire I_tx_ready,input wire I_tx_done,
    input wire [7:0] I_rx_data,input wire I_rx_valid,input wire I_rx_error,
    
    input wire [7:0] I_defect_kinds,
    
    
    input wire I_cnn_mode,input wire [15:0] I_cnn_class,
    input wire [7:0] I_cnn_confidence,
    input wire I_local_test
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

module PH1P_LOGIC_BUFG(input i, output o); assign o=i; endmodule
