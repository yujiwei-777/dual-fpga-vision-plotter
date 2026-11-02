`timescale 1ns/1ps
// Standalone DETAIL backend on an ALREADY registered 192x96 Y8 random RAM.
// No raw-frame DDR adapter, warp, automatic registration or PCB acceptance.
// Sparse-ROM endpoint must echo join tags and flush together with I_rst_n.
// Gray tags={job_id17,dense_address15,window_read_index9}; caller job_id must
// not be reused while ANY older gray response carrying it might arrive,
// including across module reset. Preserve caller epoch or drain all gray IO.
module pcb_missing_feature_backend #(
    parameter integer GRAY_TIMEOUT_CYCLES=1024,
    parameter integer ROM_TIMEOUT_CYCLES=1024
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_start,
    input wire I_cancel,
    input wire [16:0] I_job_id,
    input wire [14:0] I_sparse_count,
    input wire [15:0] I_threshold,
    input wire I_frame_valid,
    input wire I_registration_valid,
    output wire O_gray_req_valid,
    input wire I_gray_req_ready,
    output wire [14:0] O_gray_req_addr,
    output wire [40:0] O_gray_req_tag,
    input wire I_gray_rsp_valid,
    input wire [40:0] I_gray_rsp_tag,
    input wire [7:0] I_gray_rsp_data,
    output wire O_rom_req_valid,
    input wire I_rom_req_ready,
    output wire [14:0] O_rom_req_index,
    output wire [15:0] O_rom_req_tag,
    input wire I_rom_rsp_valid,
    output wire O_rom_rsp_ready,
    input wire [23:0] I_rom_rsp_data,
    input wire [15:0] I_rom_rsp_tag,
    output wire O_busy,
    output reg O_done,
    output reg O_result_valid,
    output reg [1:0] O_status, //0 DETAIL_PASS,1 DETAIL_FAIL,2 DETAIL_REVIEW
    output reg [7:0] O_error, //01 busy start;1x join;2x query;3x scorer;40 invariant
    output reg [11:0] O_score,
    output reg [10:0] O_peak_tile,
    output reg [22:0] O_total_loss,
    output reg [14:0] O_changed_pixels,
    output reg [14:0] O_samples,
    output reg [31:0] O_gray_read_requests,
    output reg [14:0] O_feature_queries
);
    reg active,join_start,abort_pending;
    reg [16:0] job_id;
    reg [14:0] sparse_count,position;
    reg [15:0] threshold;
    reg frame_valid,registration_valid;
    reg [7:0] x;
    reg [6:0] y;
    reg query_in_flight,observed_valid;
    reg [7:0] observed_saved;
    wire join_ready,join_valid,join_last,join_busy,join_done,join_fault;
    wire [3:0] join_error;
    wire join_downstream_start,join_downstream_cancel;
    wire [7:0] join_observed,join_expected,pixel_expected;
    wire [14:0] pixel_address,join_accepted,join_forwarded;
    wire expected_valid;
    wire query_busy,query_done,query_result_valid;
    wire [3:0] query_error;
    wire [7:0] query_observed;
    wire [8:0] query_reads;
    wire [31:0] query_cycles;
    wire scorer_ready,scorer_busy,scorer_done,scorer_result_valid;
    wire [1:0] scorer_status;
    wire [2:0] scorer_error;
    wire [11:0] scorer_score;
    wire [10:0] scorer_peak;
    wire [22:0] scorer_total;
    wire [14:0] scorer_changed,scorer_samples;
    wire invalid_query_result = query_done && (!query_result_valid || query_error!=0 || query_reads!=441);
    wire invalid_scorer_result = scorer_done && (!scorer_result_valid || scorer_error!=0);
    wire position_fault = active && expected_valid && pixel_address!=position;
    // expected_valid is combinationally suppressed by the join's I_cancel.
    // Do not feed position_fault straight back to that cancel input: it would
    // form expected_valid -> fault -> cancel -> expected_valid. A mismatch
    // blocks both submissions immediately, cancels query/scorer immediately,
    // and finish_fault registers abort_pending to flush the join next cycle.
    wire abort_now = I_cancel || abort_pending || (active && I_start) ||
                     (active && (join_fault || invalid_query_result || invalid_scorer_result));
    wire query_start = active && expected_valid && pixel_expected!=0 &&
                       !query_in_flight && !observed_valid && !query_busy &&
                       !abort_now && !position_fault && !I_start;
    wire input_valid = active && expected_valid && !abort_now && !position_fault && !I_start &&
                       (pixel_expected==0 || observed_valid);
    wire input_transfer = input_valid && join_ready;
    assign O_busy=active;

    pcb_sparse_expected_join #(.ROM_TIMEOUT_CYCLES(ROM_TIMEOUT_CYCLES)) u_join(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(join_start && !abort_now),
        .I_cancel(abort_now),.I_sparse_count(sparse_count),
        .I_valid(input_valid),.O_ready(join_ready),
        .I_observed(pixel_expected==0 ? 8'd0 : observed_saved),
        .I_last(position==15'd18431),
        .O_valid(join_valid),.I_ready(scorer_ready),
        .O_observed(join_observed),.O_expected(join_expected),.O_last(join_last),
        .O_pixel_address(pixel_address),.O_pixel_expected(pixel_expected),
        .O_expected_valid(expected_valid),
        .O_rom_req_valid(O_rom_req_valid),.I_rom_req_ready(I_rom_req_ready),
        .O_rom_req_index(O_rom_req_index),.O_rom_req_tag(O_rom_req_tag),
        .I_rom_rsp_valid(I_rom_rsp_valid),.O_rom_rsp_ready(O_rom_rsp_ready),
        .I_rom_rsp_data(I_rom_rsp_data),.I_rom_rsp_tag(I_rom_rsp_tag),
        .O_busy(join_busy),.O_done(join_done),.O_fault(join_fault),.O_error(join_error),
        .O_downstream_start(join_downstream_start),.O_downstream_cancel(join_downstream_cancel),
        .O_accepted(join_accepted),.O_forwarded(join_forwarded));

    pcb_local_contrast_query #(.READ_TIMEOUT_CYCLES(GRAY_TIMEOUT_CYCLES)) u_query(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(query_start),.I_cancel(abort_now || position_fault),
        .I_query_id({job_id,pixel_address}),.I_x(x),.I_y(y),
        .O_rd_req_valid(O_gray_req_valid),.I_rd_req_ready(I_gray_req_ready),
        .O_rd_req_addr(O_gray_req_addr),.O_rd_req_tag(O_gray_req_tag),
        .I_rd_rsp_valid(I_gray_rsp_valid),.I_rd_rsp_tag(I_gray_rsp_tag),
        .I_rd_rsp_data(I_gray_rsp_data),.O_busy(query_busy),.O_done(query_done),
        .O_result_valid(query_result_valid),.O_error(query_error),
        .O_observed(query_observed),.O_read_count(query_reads),.O_cycles(query_cycles));

    pcb_missing_feature_scorer u_scorer(
        .I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_start(join_downstream_start && active && !abort_now),
        .I_cancel(abort_now || join_downstream_cancel || position_fault),
        .I_threshold(threshold),.I_frame_valid(frame_valid),
        .I_registration_valid(registration_valid),.I_valid(join_valid),.O_ready(scorer_ready),
        .I_observed_contrast(join_observed),.I_expected_contrast(join_expected),.I_last(join_last),
        .O_busy(scorer_busy),.O_done(scorer_done),.O_result_valid(scorer_result_valid),
        .O_status(scorer_status),.O_error(scorer_error),.O_score(scorer_score),
        .O_peak_tile(scorer_peak),.O_total_loss(scorer_total),
        .O_changed_pixels(scorer_changed),.O_samples(scorer_samples));

    task finish_fault;
        input [7:0] code;
        begin
            active<=0; abort_pending<=1; query_in_flight<=0; observed_valid<=0;
            O_done<=1; O_result_valid<=1; O_status<=2; O_error<=code;
            O_score<=0; O_peak_tile<=0; O_total_loss<=0;
            O_changed_pixels<=0; O_samples<=0;
        end
    endtask

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            active<=0; join_start<=0; abort_pending<=0;
            job_id<=0; sparse_count<=0; threshold<=0; frame_valid<=0; registration_valid<=0;
            position<=0; x<=0; y<=0; query_in_flight<=0; observed_valid<=0; observed_saved<=0;
            O_done<=0; O_result_valid<=0; O_status<=2; O_error<=0;
            O_score<=0; O_peak_tile<=0; O_total_loss<=0; O_changed_pixels<=0; O_samples<=0;
            O_gray_read_requests<=0; O_feature_queries<=0;
        end else begin
            O_done<=0; join_start<=0; abort_pending<=0;
            if (I_cancel) begin
                active<=0; query_in_flight<=0; observed_valid<=0; abort_pending<=1;
                O_result_valid<=0; O_status<=2; O_error<=0;
                O_score<=0; O_peak_tile<=0; O_total_loss<=0; O_changed_pixels<=0; O_samples<=0;
                O_gray_read_requests<=0; O_feature_queries<=0;
            end else if (active && join_fault) begin
                finish_fault({4'h1,join_error});
            end else if (active && invalid_query_result) begin
                finish_fault(query_error!=0 ? {4'h2,query_error} : 8'h40);
            end else if (position_fault) begin
                finish_fault(8'h40);
            end else if (active && invalid_scorer_result) begin
                finish_fault({5'b00110,scorer_error});
            end else if (active && I_start) begin
                finish_fault(8'h01);
            end else if (I_start) begin
                active<=1; join_start<=1;
                job_id<=I_job_id; sparse_count<=I_sparse_count; threshold<=I_threshold;
                frame_valid<=I_frame_valid; registration_valid<=I_registration_valid;
                position<=0; x<=0; y<=0; query_in_flight<=0; observed_valid<=0;
                O_result_valid<=0; O_status<=2; O_error<=0;
                O_score<=0; O_peak_tile<=0; O_total_loss<=0; O_changed_pixels<=0; O_samples<=0;
                O_gray_read_requests<=0; O_feature_queries<=0;
            end else if (active) begin
                if (O_gray_req_valid && I_gray_req_ready)
                    O_gray_read_requests<=O_gray_read_requests+32'd1;
                if (query_start) begin
                    query_in_flight<=1; O_feature_queries<=O_feature_queries+15'd1;
                end
                if (query_done) begin
                    query_in_flight<=0; observed_saved<=query_observed; observed_valid<=1;
                end
                if (input_transfer) begin
                    observed_valid<=0; position<=position+15'd1;
                    if (x==191) begin x<=0; y<=y+7'd1; end else x<=x+8'd1;
                end
                // Join done only indicates final forwarding. Completion waits
                // for the scorer's last accumulator commit and done pulse.
                if (scorer_done) begin
                    if (!scorer_result_valid || scorer_error!=0)
                        finish_fault({5'b00110,scorer_error});
                    else if (scorer_samples!=18432 || join_accepted!=18432 ||
                             join_forwarded!=18432 || O_feature_queries!=sparse_count)
                        finish_fault(8'h40);
                    else begin
                        active<=0; O_done<=1; O_result_valid<=1;
                        O_status<=scorer_status; O_error<=0;
                        O_score<=scorer_score; O_peak_tile<=scorer_peak;
                        O_total_loss<=scorer_total; O_changed_pixels<=scorer_changed;
                        O_samples<=scorer_samples;
                    end
                end
            end
        end
    end
endmodule
