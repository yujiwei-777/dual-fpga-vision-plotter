// Fixed HXA1 type18 payload packer.
// Byte layout: job_id, inference_us, config_version, flags, box_count,
// reserved, then four 16-byte wire-order box slots.
module hxa_yolo_result_codec(
    input  wire [31:0]  job_id,
    input  wire [31:0]  inference_us,
    input  wire [31:0]  config_version,
    input  wire [7:0]   flags,
    input  wire [2:0]   box_count,
    input  wire [127:0] box0,
    input  wire [127:0] box1,
    input  wire [127:0] box2,
    input  wire [127:0] box3,
    output wire [639:0] payload
);
    wire [7:0] count_clamped = (box_count > 3'd4) ? 8'd4 : {5'd0, box_count};
    wire [511:0] slots = {
        (count_clamped > 8'd3) ? box3 : 128'd0,
        (count_clamped > 8'd2) ? box2 : 128'd0,
        (count_clamped > 8'd1) ? box1 : 128'd0,
        (count_clamped > 8'd0) ? box0 : 128'd0
    };
    assign payload = {slots, 16'd0, count_clamped, flags,
                      config_version, inference_us, job_id};
endmodule
