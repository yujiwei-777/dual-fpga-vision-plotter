// Fixed production configuration stub for the PCB TinyCNN secondary.
// Network template/profile writes are retired.  Ports remain source-compatible
// with the HXA1 link and legacy wrappers, but no TPL1/MPF1 data is stored.
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
    localparam [31:0] PCB_MODEL_VERSION=32'h50434231; // "PCB1"
    assign O_cfg_ready=1'b1;
    assign O_byte_ready=1'b0;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            // HXA1 station header, little-endian field layout:
            // TPL1 tag, model version, full 1280x720 ROI and legacy metadata.
            O_station_header<=256'd0;
            O_station_header[31:0]<=32'h314c5054;
            O_station_header[63:32]<=PCB_MODEL_VERSION;
            O_station_header[71:64]<=8'd0;
            O_station_header[79:72]<=8'd0;
            O_station_header[87:80]<=8'd75;
            O_station_header[111:96]<=16'd128;
            O_station_header[127:112]<=16'd128;
            O_station_header[175:160]<=16'd1280;
            O_station_header[191:176]<=16'd720;
            O_station_header[223:208]<=16'd1;
            O_station_header[239:232]<=8'd24;
            O_station_valid<=1'b1;
            O_commit_ack<=1'b0; O_commit_error<=1'b0; O_apply<=1'b0;
            O_profile_valid<=1'b1; O_profile_pwm_mode<=1'b0; O_profile_step_cmm<=8'd60;
            O_origin_x_cmm<=16'd1000; O_origin_y_cmm<=16'd1000;
            O_work_x_cmm<=16'd21000; O_work_y_cmm<=16'd29700;
            O_pen_up_cmm<=-16'sd120; O_pen_down_cmm<=16'sd500;
            O_pen_up_pwm<=16'd0; O_pen_down_pwm<=16'd0;
            O_travel_feed<=16'd7000; O_draw_feed<=16'd3000; O_pen_feed<=16'd1200;
            O_profile_id<=32'h50434231;
        end else begin
            // All external configuration data is intentionally ignored.  A
            // stale host begin/commit receives a one-cycle compatibility error
            // and can never alter the station, model or plotter parameters.
            O_commit_ack<=1'b0; O_commit_error<=I_begin||I_commit; O_apply<=1'b0;
            O_station_valid<=1'b1; O_profile_valid<=1'b1;
        end
    end
endmodule
