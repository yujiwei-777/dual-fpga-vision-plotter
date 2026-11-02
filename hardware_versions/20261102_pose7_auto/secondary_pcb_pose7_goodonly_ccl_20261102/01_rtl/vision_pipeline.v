// 720p YUYV DDR -> ordinary RGB CNN or shared-CCL pose7 GOOD-only PCB.
// All interfaces are synchronous to clk (125 MHz in the board integration).
// Boxes are x0,y0,x1,y1 with exclusive right/bottom coordinates. Each 64-bit
// defect box packs x0 at [15:0], y0 [31:16], x1 [47:32], y1 [63:48].
module vision_pipeline #(
    parameter integer EXTERNAL_READER=0,
    // Ordinary colour/shape jobs can be delegated to secondary-board B.
    // Keeping the sampler and CCL in this module preserves the PCB/KEY3
    // paths, while this switch removes cnn_core itself from the A build.
    parameter integer LOCAL_CNN_ENABLE=1,
    parameter integer SHARED_WORKSPACE=1,
    // This diagnostic ordinary-CNN build can omit the legacy PCB classifier.
    // Purpose=1 then completes with an explicit unsupported status instead of
    // leaving an unimplemented request waiting in the PCB state machine.
    parameter integer PCB_ENABLE=1,
    // Independent GOOD-only PCB: shared CCL, strict ROI96, one encoder pass.
    parameter integer PCB_GOODONLY_AUTO=1,
    parameter PCB_POSE7_WEIGHTS_MEM="../model/pose7_96x96/weights.mem",
    parameter PCB_POSE7_BIASES_MEM="../model/pose7_96x96/biases.mem",
    parameter PCB_POSE7_CENTRE_MEM="../model/pose7_96x96/feature_centre.mem",
    parameter PCB_POSE7_TOLERANCE_MEM="../model/pose7_96x96/feature_tolerance.mem",
    parameter PCB_POSE7_ORIENTATION_MEM="../model/pose7_96x96/orientation_reference.mem",
    parameter PCB_GOODONLY_GEOMETRY_ROM="../model/goodonly/combined_geometry_warp_outline_rom_2048.mem",
    parameter PCB_GOODONLY_BANK0_INIT="",
    parameter PCB_GOODONLY_BANK1_INIT="",
    // The compact PCB variant preserves the MAC schedule and model values
    // while replacing the sparse linked-list tap ROM with its 80 reachable
    // entries.  Keep the default on the original core for source compatibility.
    parameter integer PCB_COMPACT_ROM=0,
    parameter PCB_WEIGHTS_MEM="../model/pcb_tinycnn_weights.mem",
    parameter PCB_BIASES_MEM="../model/pcb_tinycnn_bias.mem",
    parameter PCB_FIRST_MEM="../model/pcb_tinycnn_first.mem",
    parameter PCB_NEXT_MEM="../model/pcb_tinycnn_next.mem",
    parameter PCB_TAPS_MEM="../model/pcb_tinycnn_taps.mem",
    parameter integer PCB_TIMEOUT_CYCLES=4000000,
    parameter integer PCB_MARGIN_MIN=115,
    // The neighborhood REVIEW vote is diagnostic-only.  Keep it disabled in
    // the compact PCB build so the four-candidate result path does not carry
    // a 26-window history shift register and its compare fanout.
    parameter integer PCB_REVIEW_ENABLE=0,
    // Full-board diagnostic input contract for the current fixed camera mount.
    parameter integer PCB_FULLBOARD_SPATIAL96=0,
    // Full-board head selection.  The default remains the reviewed 3-class
    // model (GOOD/MISSING_CORNER/MISSING_PAD).  Binary builds use class 0 for
    // GOOD and class 1 for BAD, with no third output slot in the FC ROM.
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
    // Resource-bounded PCB diagnostic mode: evaluate one fixed 96x96
    // inspection window instead of the full-frame 26x14 window grid.
    parameter integer PCB_FIXED_WINDOW_ONLY=0,
    parameter integer PCB_FIXED_WINDOW_X=592,
    parameter integer PCB_FIXED_WINDOW_Y=312,
    parameter integer COLOR_MARGIN_MIN=0,
    parameter integer TRIANGLE_MARGIN_MIN=31,
    parameter integer CIRCLE_MARGIN_MIN=28,
    parameter integer SQUARE_MARGIN_MIN=77,
    // Preserve soft-margin diagnostics while optionally publishing real low scores.
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
    output wire busy,
    output reg done,
    output reg [31:0] result_job_id,config_version,
    output reg [1:0] color_id,shape_id,
    output reg [7:0] confidence,
    output reg valid,
    output reg [10:0] x0,x1,
    output reg [9:0] y0,y1,
    output reg [23:0] area,
    output reg pcb_checked,pcb_good,
    output reg [2:0] pcb_status, // 0 GOOD, 1 BAD, 2 REVIEW, 3 ERROR/overflow
    output wire [2:0] defect_count,
    output wire [255:0] defect_boxes,
    output wire [7:0] defect_kinds,
    // Ordinary jobs publish up to four CNN-classified CCL boxes.  A slot is
    // the little-endian 16-byte HXA1 box layout.
    output reg [2:0] multi_count,
    output reg [511:0] multi_boxes,
    output reg [7:0] multi_flags,
    output reg teach_success,teach_failed,output reg [15:0] teach_code,
    output wire teach_commit,output reg [255:0] taught_station_header,
    // When EXTERNAL_READER=1 the parent supplies the single shared DDR
    // reader.  These ports are appended so existing simulation instances
    // remain source-compatible.
    input wire ext_reader_ready,ext_reader_valid,
    input wire [23:0] ext_reader_rgb,
    input wire [7:0] ext_reader_luma,
    output wire ext_reader_request,ext_reader_invalidate,
    output wire [10:0] ext_pixel_x,
    output wire [9:0] ext_pixel_y,
    // Optional tap for a secondary-A external accelerator.  The tap mirrors
    // the existing 64x64 ROI sample stream and is deliberately unconnected
    // in legacy CNN/PCB instances, so adding it is source-compatible.
    output wire yolo_pixel_valid,
    output wire [23:0] yolo_pixel_rgb,
    output wire yolo_pixel_last,
    // During the ordinary CNN calculation this module owns the word port
    // for native-pixel colour statistics; the shared pixel reader is idle.
    output wire color_word_active,
    // Session/configuration/mode changes invalidate ordinary-CNN history.
    // An unconnected legacy input is treated as inactive by the synchronous
    // clear branch; production secondary_top always drives this input.
    input wire history_clear,
    output wire pcb_frame_lock
);
    // Ordinary color/shape confidence is a saturated margin, not a probability.
    localparam [6:0] IDLE=0,CC_START=3,SCAN_REQ=4,SCAN_WAIT=5,
        SCAN_SEND=6,CC_WAIT=7,BOX_MAP=8,ROI_PREP=9,CNN_REQ=10,CNN_WAIT=11,
        CNN_WRITE=12,CNN_START=13,CNN_DONE=14,FINISH=33,
        AREA_MUL_Y=35,AREA_DIV_INIT=36,AREA_DIV=37,
        ROI_MAX=38,ROI_SCALE=39,ROI_SIDE=40,ROI_CENTER=41,ROI_CLAMP=42,
        COORD_INIT=43,COORD_DIV=44,COORD_STORE=45,CONF_DIV=46,CONF_SCALE=47,
        MULTI_STORE=60,MULTI_INSERT=61,MULTI_NEXT=62,MULTI_PUBLISH=63,
        PCB_WINDOW_INIT=64,PCB_PIXEL_REQ=65,PCB_PIXEL_WAIT=66,PCB_PIXEL_WRITE=67,
        PCB_START=68,PCB_WAIT=69,PCB_NEXT=70,PCB_FINISH=71,
        PCB_CLUSTER_WAIT=72,PCB_ERROR=73,PCB_CONF_DIV=74,PCB_EMIT=75,
        CNN_COORD=76,
        // Keep the RGB-to-luma arithmetic off the DDR reader's capture path.
        // The extra state costs one scan cycle per sampled pixel but leaves
        // the reader/edge-ROI protocol unchanged and gives the adder tree a
        // complete eth125 cycle for timing closure.
        SCAN_LUMA=77,CNN_STABLE_START=78,CNN_STABLE_WAIT=79,
        PCB_AUTO_START=80,PCB_AUTO_WAIT=81,
        PCB_CCL_DRAIN=82,PCB_CCL_LOCKED=83,PCB_CCL_HANDOFF=84;
    reg [6:0] state;
    // Capture the HXA purpose at job admission.  The link-side purpose can
    // change while a frame is being processed; allowing it to fan directly
    // into the shared MAC and activation workspace creates a long 125 MHz
    // control cone.  All datapath ownership decisions use this local copy.
    reg [1:0] purpose_q;
    // Datapath ownership is only consumed after IDLE accepts start; using the
    // captured value directly avoids a busy-controlled mux on high-fanout
    // MAC/workspace controls.
    wire [1:0] purpose_active = purpose_q;
    reg [2:0] box_index,box_total,insert_index;
    reg [127:0] insert_box;
    // Only 2-bit slot identities move during ordinary confirmation insertion.
    // Payloads remain in physical acquisition order until serial publication.
    localparam integer USE_INDIRECT_SORT=(CNN_STABILITY_ENABLE!=0 && LOCAL_CNN_ENABLE!=0);
    reg [7:0] raw_slot_order;
    reg [1:0] insert_physical_slot;
    localparam [31:0] PCB_MODEL_VERSION=32'h50434231;
    // Retired configuration/teaching inputs have no storage or commit path.
    reg main_busy,auto_cancel_seen;
    wire auto_busy,auto_done,auto_valid,auto_no_target,auto_bbox_valid;
    wire [1:0] auto_status;
    wire [15:0] auto_error;
    wire [10:0] auto_xmin,auto_xmax,auto_pixel_x;
    wire [9:0] auto_ymin,auto_ymax,auto_pixel_y;
    wire [11:0] auto_detail_score;
    wire [15:0] auto_outline_support;
    wire auto_pixel_request;
    // PCB CCL reads through the ordinary scan interface before AUTO owns it.
    wire auto_owner=PCB_GOODONLY_AUTO!=0 && purpose_active==2'd1 &&
        (state==PCB_AUTO_START || state==PCB_AUTO_WAIT || auto_busy);
    // Frame ownership is raw-reset state. It must not depend on main_busy,
    // whose ordinary-job cancel reset is itself masked by this frame lock.
    // Keeping the owner outside processing_rst_n removes an asynchronous
    // Q -> reset -> Q loop and holds accepted reads until a safe drain.
    reg pcb_frame_owner_q;
    wire pcb_job_active=pcb_frame_owner_q;
    wire pcb_ccl_scan_owner=pcb_job_active && !auto_owner;
    assign busy=main_busy||auto_busy;
    // Lock the frame through CCL, candidate hold, AUTO and cancellation drain.
    assign pcb_frame_lock=auto_busy || pcb_job_active;
    // A network cancel must drain an accepted raw DDR read, not reset it away.
    wire processing_rst_n=rst_n && !(cancel && !pcb_frame_lock);
    reg pcb_reset;
    wire pcb_engine_rst_n=processing_rst_n && !pcb_reset;
    assign teach_commit=1'b0;

    reg reader_request,reader_invalidate;
    reg pcb_ccl_pending;
    reg [11:0] pcb_ccl_drain_count;
    // A same-cycle cancel must fence even a previously registered request.
    wire scan_reader_request=reader_request &&
        (!pcb_ccl_scan_owner || !(cancel || auto_cancel_seen));
    // Reset only the on-chip CCL on abort; the shared DDR reader must drain.
    wire ccl_rst_n=processing_rst_n && !(pcb_ccl_scan_owner &&
        (cancel || auto_cancel_seen || state==PCB_CCL_DRAIN || state==PCB_CCL_LOCKED));
    reg [10:0] sample_x;
    reg [9:0] sample_y;
    wire reader_ready,reader_valid;
    wire pcb_ccl_read_accept=pcb_ccl_scan_owner && scan_reader_request && reader_ready;
    wire pcb_ccl_read_response=pcb_ccl_scan_owner && reader_valid;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)pcb_frame_owner_q<=1'b0;
        else if(state==IDLE && start && !auto_busy && !cancel &&
            PCB_ENABLE!=0 && PCB_GOODONLY_AUTO!=0 && purpose==2'd1 && !teach_good)
            pcb_frame_owner_q<=1'b1;
        else if((state==FINISH && purpose_q==2'd1) ||
            (state==PCB_AUTO_WAIT && auto_done && (cancel || auto_cancel_seen)) ||
            (state==PCB_CCL_DRAIN && !pcb_ccl_pending && reader_ready && !reader_request))
            pcb_frame_owner_q<=1'b0;
    end
    wire [23:0] reader_rgb;
    wire [7:0] reader_luma;
    wire pixel_word_req;
    wire [20:0] pixel_byte_addr;
    wire stat_busy,stat_done,stat_word_req;
    wire [20:0] stat_byte_addr;
    wire [1:0] stat_color;
    wire [7:0] stat_conf;
    wire [19:0] stat_valid_samples;
    reg stat_start,shape_seen,color_seen;
    reg shape_reject_saved;
    reg [1:0] shape_saved,color_saved;
    reg [7:0] shape_margin_saved,color_margin_saved;
    reg [19:0] color_samples_saved;
    // The joint model computes colour directly from the same 4096 RGB8 ROI
    // pixels as the shape network.  The legacy bbox colour-statistics reader
    // remains instantiated for source compatibility but is never started.
    assign color_word_active=1'b0;
    assign word_req=color_word_active ? stat_word_req : pixel_word_req;
    assign byte_addr=color_word_active ? stat_byte_addr : pixel_byte_addr;
    vision_color_stats color_statistics(.clk(clk),.rst_n(rst_n),.cancel(cancel),.start(stat_start),
        .box_x0(x0),.box_y0(y0),.box_x1(x1),.box_y1(y1),.busy(stat_busy),.done(stat_done),
        .color_id(stat_color),.color_conf(stat_conf),.valid_samples(stat_valid_samples),
        .count_r(),.count_g(),.count_b(),.word_req(stat_word_req),.byte_addr(stat_byte_addr),
        .word_ready(word_ready && color_word_active),.word_valid(word_valid && color_word_active),.word_data(word_data));
    generate if(EXTERNAL_READER) begin : g_external_reader
        assign reader_ready=ext_reader_ready;
        assign reader_valid=ext_reader_valid;
        assign reader_rgb=ext_reader_rgb;
        assign reader_luma=ext_reader_luma;
        assign pixel_word_req=1'b0;
        assign pixel_byte_addr=21'd0;
    end else begin : g_internal_reader
        vision_pixel_reader reader(.clk(clk),.rst_n(processing_rst_n),.invalidate(reader_invalidate),
            .request(auto_owner?auto_pixel_request:scan_reader_request),.pixel_x(auto_owner?auto_pixel_x:sample_x),.pixel_y(auto_owner?auto_pixel_y:sample_y),.ready(reader_ready),
            .pixel_valid(reader_valid),.pixel_rgb(reader_rgb),.pixel_y8(reader_luma),
            .word_req(pixel_word_req),.byte_addr(pixel_byte_addr),
            .word_ready(word_ready && !color_word_active),.word_valid(word_valid && !color_word_active),.word_data(word_data));
    end endgenerate
    assign ext_reader_request=EXTERNAL_READER ? (auto_owner?auto_pixel_request:scan_reader_request) : 1'b0;
    assign ext_reader_invalidate=EXTERNAL_READER ? reader_invalidate : 1'b0;
    assign ext_pixel_x=auto_owner?auto_pixel_x:sample_x;
    assign ext_pixel_y=auto_owner?auto_pixel_y:sample_y;

    reg cc_start,cc_pixel_valid,cc_filter;
    reg [8:0] cc_width;
    reg [7:0] cc_height;
    reg [15:0] cc_min_area;
    reg [1:0] cc_color;
    wire cc_ready,cc_busy,cc_done,cc_overflow;
    wire [2:0] cc_count;
    wire [255:0] cc_boxes;
    wire [15:0] cc_area;
    wire [63:0] cc_areas;
    wire cc_truncated;
    wire [1:0] cc_largest_color;
    wire [63:0] selected_box = cc_boxes[{box_index[1:0],6'b0}+:64];
    wire [15:0] selected_area = cc_areas[{box_index[1:0],4'b0}+:16];
    wire ordinary_box_small = (selected_box[40:32] < selected_box[8:0] + 9'd4) ||
                               (selected_box[55:48] < selected_box[23:16] + 8'd4);
    // Ordinary CNN candidate generation uses the same edge-ROI contract as
    // the training data. The edge image is used only for CCL; RGB samples
    // continue to feed the CNN ROI memory below.
    reg [23:0] sampled_rgb;
    reg [7:0] sampled_luma;
    reg [7:0] sampled_source_y;
    function [7:0] rgb_luma8;
        input [23:0] rgb;
        reg [15:0] rr,gg,bb,yy;
        begin
            rr={8'd0,rgb[23:16]}; gg={8'd0,rgb[15:8]}; bb={8'd0,rgb[7:0]};
            yy=(rr<<6)+(rr<<3)+(rr<<2)+rr +
               (gg<<7)+(gg<<4)+(gg<<2)+(gg<<1) +
               (bb<<4)+(bb<<3)+(bb<<2)+bb + 16'd128;
            rgb_luma8=yy[15:8];
        end
    endfunction
    // Fast linkfix4 locator: 160x90 samples at (8x+4,8y+4).  The CCL
    // front end keeps four ranked components: ratio-8 RGB mask for ordinary
    // CNN, source-Y gray mask for PCB. CNN ROI sampling remains native RGB8.
    edge_roi_ccl_shared_pcb_candidate #(.WIDTH(160),.HEIGHT(90),.EDGE_THRESHOLD(32),.MIN_EDGE_AREA(12)) edge_components(
        .clk(clk),.rst_n(ccl_rst_n),.start(cc_start),.width(cc_width),.height(cc_height),
        .pcb_mode(PCB_GOODONLY_AUTO!=0 && purpose_active==2'd1),
        .min_area(cc_min_area),.filter_shape(cc_filter),.pixel_valid(cc_pixel_valid),
        .pixel_rgb(sampled_rgb),.pixel_luma(pcb_ccl_scan_owner?sampled_source_y:sampled_luma),.pixel_ready(cc_ready),.busy(cc_busy),
        .done(cc_done),.overflow(cc_overflow),.count(cc_count),.boxes(cc_boxes),
        .largest_area(cc_area),.largest_color(cc_largest_color),.areas(cc_areas),.truncated(cc_truncated));

    reg cnn_pixel_we,cnn_start;
    reg [11:0] cnn_pixel_addr;
    reg [23:0] cnn_pixel_rgb;
    wire cnn_busy,cnn_done,cnn_background_reject;
    wire [1:0] cnn_color,cnn_shape;
    wire [7:0] cnn_color_conf,cnn_shape_conf;
    wire ws_cnn_shape_we,ws_cnn_f1_we,ws_cnn_f2_we;
    wire [11:0] ws_cnn_shape_waddr,ws_cnn_f2_waddr;
    wire [12:0] ws_cnn_f1_waddr,ws_cnn_rd_addr;
    wire [15:0] ws_cnn_shape_wdata,ws_cnn_f1_wdata,ws_cnn_f2_wdata;
    wire [7:0] ws_cnn_rd_data;
    wire [1:0] ws_cnn_rd_sel;
    wire signed [15:0] cnn_mac_a;
    wire signed [7:0] cnn_mac_w;
    wire signed [15:0] pcb_mac_a;
    wire signed [7:0] pcb_mac_w;
    // The latched purpose owns one signed 9x8 DSP. Both cores retain their
    // own product capture/accumulate timing; switching ownership adds no
    // latency to the ordinary CNN's per-clock product stream.
    wire signed [23:0] shared_mac_product;
    wire signed [23:0] cnn_mac_product;
    wire signed [23:0] pcb_mac_product;
    generate
        if (LOCAL_CNN_ENABLE != 0) begin : g_local_cnn
            // Remote-detail deployment calibration: shape margin shift=8.
            // PCB has its own classifier and retains its original quantization.
            cnn_core #(.FC_CONF_SHIFT(8),.USE_SHARED_WORKSPACE(SHARED_WORKSPACE),.EXTERNAL_MAC(1)) classifier(.clk(clk),.rst_n(processing_rst_n),.pixel_we(cnn_pixel_we),.pixel_addr(cnn_pixel_addr),
                .pixel_rgb(cnn_pixel_rgb),.start(cnn_start),.busy(cnn_busy),.done(cnn_done),
                .color_id(cnn_color),.shape_id(cnn_shape),.color_conf(cnn_color_conf),.shape_conf(cnn_shape_conf),
                .background_reject(cnn_background_reject),.ws_shape_we(ws_cnn_shape_we),.ws_shape_waddr(ws_cnn_shape_waddr),.ws_shape_wdata(ws_cnn_shape_wdata),
                .ws_f1_we(ws_cnn_f1_we),.ws_f1_waddr(ws_cnn_f1_waddr),.ws_f1_wdata(ws_cnn_f1_wdata),.ws_f2_we(ws_cnn_f2_we),.ws_f2_waddr(ws_cnn_f2_waddr),.ws_f2_wdata(ws_cnn_f2_wdata),
                .ws_rd_sel(ws_cnn_rd_sel),.ws_rd_addr(ws_cnn_rd_addr),.ws_rd_data(ws_cnn_rd_data),
                .mac_a(cnn_mac_a),.mac_w(cnn_mac_w),.mac_product_ext(cnn_mac_product));
        end else begin : g_external_cnn
            // One-cycle completion stub. The 4096 sampled pixels are still
            // emitted on yolo_pixel_* for the external SPI bridge.
            reg cnn_done_q;
            always @(posedge clk or negedge processing_rst_n) begin
                if (!processing_rst_n) cnn_done_q <= 1'b0;
                else cnn_done_q <= cnn_start;
            end
            assign cnn_busy = 1'b0;
            assign cnn_done = cnn_done_q;
            assign cnn_color = 2'd0;
            assign cnn_shape = 2'd0;
            assign cnn_color_conf = 8'd0;
            assign cnn_shape_conf = 8'd0;
            assign cnn_background_reject = 1'b1;
            assign cnn_mac_a=16'sd0;
            assign cnn_mac_w=8'sd0;
        end
    endgenerate

    // Separate 96x96 grayscale PCB TinyCNN; purpose=0 keeps the RGB CNN.
    reg pcb_pixel_we,pcb_start;
    reg [13:0] pcb_pixel_addr;
    reg [7:0] pcb_pixel_gray;
    wire pcb_cnn_busy,pcb_cnn_done;
    wire [1:0] pcb_cnn_class;
    wire [7:0] pcb_cnn_score;
    wire [15:0] pcb_cnn_margin,pcb_cnn_sat;
    wire ws_pcb_we,ws_pcb_wbank,ws_pcb_rd_bank;
    wire [14:0] ws_pcb_waddr,ws_pcb_rd_addr;
    wire [15:0] ws_pcb_wdata,ws_pcb_rd_data;
    generate
        if (PCB_ENABLE != 0 && PCB_GOODONLY_AUTO != 0) begin : g_pcb_goodonly_auto
            pcb_pose7_core #(.WEIGHTS_MEM(PCB_POSE7_WEIGHTS_MEM),
                .BIASES_MEM(PCB_POSE7_BIASES_MEM),.CENTRE_MEM(PCB_POSE7_CENTRE_MEM),
                .TOLERANCE_MEM(PCB_POSE7_TOLERANCE_MEM),
                .ORIENTATION_MEM(PCB_POSE7_ORIENTATION_MEM)) pcb_auto(
                .clk(clk),.rst_n(rst_n),.start(state==PCB_AUTO_START&&!cancel&&!auto_cancel_seen),.cancel(cancel),
                .I_ccl_count(cc_count),.I_ccl_boxes(cc_boxes),
                .I_ccl_overflow(cc_overflow),.I_ccl_truncated(cc_truncated),
                .frame_valid(1'b1),.model_valid(1'b1),.job_id(result_job_id),
                .busy(auto_busy),.frame_lock(),.done(auto_done),.result_valid(auto_valid),.no_target(auto_no_target),
                .status(auto_status),.error(auto_error),.bbox_valid(auto_bbox_valid),
                .xmin(auto_xmin),.xmax(auto_xmax),.ymin(auto_ymin),.ymax(auto_ymax),
                .detail_score(auto_detail_score),.outline_support(auto_outline_support),
                .pixel_request(auto_pixel_request),.pixel_x(auto_pixel_x),.pixel_y(auto_pixel_y),
                .pixel_ready(reader_ready&&auto_owner),.pixel_valid(reader_valid&&auto_owner),.pixel_y8(reader_luma),
                .ws_we(ws_pcb_we),.ws_wbank(ws_pcb_wbank),.ws_waddr(ws_pcb_waddr),.ws_wdata(ws_pcb_wdata),
                .ws_rd_bank(ws_pcb_rd_bank),.ws_rd_addr(ws_pcb_rd_addr),.ws_rd_data(ws_pcb_rd_data),
                .mac_a(pcb_mac_a),.mac_w(pcb_mac_w),.mac_product_ext(pcb_mac_product),.phase(),.cycles());
            assign pcb_cnn_busy=1'b0;assign pcb_cnn_done=1'b0;assign pcb_cnn_class=2'd3;
            assign pcb_cnn_score=0;assign pcb_cnn_margin=0;assign pcb_cnn_sat=0;
        end else begin : g_no_pcb_classifier
            assign pcb_cnn_busy=1'b0;
            assign pcb_cnn_done=1'b0;
            assign pcb_cnn_class=2'd0;
            assign pcb_cnn_score=8'd0;
            assign pcb_cnn_margin=16'd0;
            assign pcb_cnn_sat=16'd0;
            assign pcb_mac_a=16'sd0;
            assign pcb_mac_w=8'sd0;
            assign ws_pcb_we=1'b0;assign ws_pcb_wbank=1'b0;assign ws_pcb_waddr=15'd0;assign ws_pcb_wdata=16'd0;
            assign ws_pcb_rd_bank=1'b0;assign ws_pcb_rd_addr=15'd0;
        end
    endgenerate

    generate if(PCB_ENABLE==0 || PCB_GOODONLY_AUTO==0)begin : g_no_pcb_auto
        assign auto_busy=0;assign auto_done=0;assign auto_valid=0;assign auto_no_target=0;
        assign auto_bbox_valid=0;assign auto_status=2;assign auto_error=0;
        assign auto_xmin=0;assign auto_xmax=0;assign auto_ymin=0;assign auto_ymax=0;
        assign auto_pixel_x=0;assign auto_pixel_y=0;assign auto_pixel_request=0;
        assign auto_detail_score=0;assign auto_outline_support=0;
    end endgenerate

    // Ordinary and PCB jobs cannot overlap. The shared multiplier is fed by
    // the locked purpose mux and both classifier cores retain their own
    // registered product/accumulator timing.
    vision_shared_mac shared_mac(.pcb_select(purpose_active==2'd1),
        .cnn_a(cnn_mac_a),.cnn_w(cnn_mac_w),.pcb_a(pcb_mac_a),.pcb_w(pcb_mac_w),
        .product(shared_mac_product),.cnn_product(cnn_mac_product),.pcb_product(pcb_mac_product));

    // The two classifiers are mutually exclusive by purpose.  A single
    // registered-read workspace therefore replaces the duplicated CNN and
    // PCB activation RAMs without changing either model's numerical format.
    generate if (SHARED_WORKSPACE != 0) begin : g_shared_workspace
        vision_workspace_goodonly #(.BANK0_INIT_FILE(PCB_GOODONLY_BANK0_INIT),
                .BANK1_INIT_FILE(PCB_GOODONLY_BANK1_INIT)) workspace(.clk(clk),.purpose(purpose_active),
            .cnn_shape_we(ws_cnn_shape_we),.cnn_shape_waddr(ws_cnn_shape_waddr),.cnn_shape_wdata(ws_cnn_shape_wdata),
            .cnn_f1_we(ws_cnn_f1_we),.cnn_f1_waddr(ws_cnn_f1_waddr),.cnn_f1_wdata(ws_cnn_f1_wdata),
            .cnn_f2_we(ws_cnn_f2_we),.cnn_f2_waddr(ws_cnn_f2_waddr),.cnn_f2_wdata(ws_cnn_f2_wdata),
            .cnn_rd_sel(ws_cnn_rd_sel),.cnn_rd_addr(ws_cnn_rd_addr),.cnn_rd_data(ws_cnn_rd_data),
            .pcb_we(ws_pcb_we),.pcb_wbank(ws_pcb_wbank),.pcb_waddr(ws_pcb_waddr),.pcb_wdata(ws_pcb_wdata),
            .pcb_rd_bank(ws_pcb_rd_bank),.pcb_rd_addr(ws_pcb_rd_addr),.pcb_rd_data(ws_pcb_rd_data));
    end else begin : g_no_shared_workspace
        assign ws_cnn_rd_data=8'd0; assign ws_pcb_rd_data=16'd0;
    end endgenerate

    reg [8:0] gx;
    reg [7:0] gy;
    reg [10:0] station_left,scan_width,roi_side;
    reg [9:0] station_top,scan_height;
    reg signed [12:0] roi_left,roi_top,cnn_sample_x,cnn_sample_y;
    reg [13:0] sample_index;
    // Widen operands before the multiply. Verilog sizes a multiply to the
    // widest operand; the previous 6-bit index * 11-bit side truncated the
    // upper product bits for normal (64..720 pixel) ROIs.
    wire [16:0] cnn_index_x_ext={11'd0,sample_index[5:0]};
    wire [16:0] cnn_index_y_ext={11'd0,sample_index[11:6]};
    wire [16:0] roi_side_ext={6'd0,roi_side};
    wire [16:0] roi_half_ext={6'd0,(roi_side>>1)};
    wire [16:0] cnn_offset_x=cnn_index_x_ext*roi_side_ext+roi_half_ext;
    wire [16:0] cnn_offset_y=cnn_index_y_ext*roi_side_ext+roi_half_ext;
    wire cnn_sample_inside=(cnn_sample_x>=0 && cnn_sample_x<1280 && cnn_sample_y>=0 && cnn_sample_y<720);
    reg [1:0] sampled_color;
    reg [10:0] pcb_wx;
    reg [9:0] pcb_wy;
    reg [6:0] pcb_px,pcb_py;
    reg [10:0] pcb_src_x;
    reg [9:0] pcb_src_y;
    reg [7:0] pcb_map_err_x,pcb_map_err_y;
    reg [4:0] pcb_column;
    reg [25:0] pcb_previous_low;
    reg pcb_left_low,pcb_upper_left_low,pcb_review;
    reg [31:0] pcb_wait_cycles;
    // The full-board classifier samples the fixed camera-mount rectangle,
    // while the legacy window path reports its 96x96 inspection window.
    // Keep the published defect box in the same coordinate contract as the
    // pixels sent to the classifier.
    wire [10:0] pcb_box_x0 = PCB_FULLBOARD_SPATIAL96 != 0 ? PCB_FULL_X[10:0] : pcb_wx;
    wire [9:0]  pcb_box_y0 = PCB_FULLBOARD_SPATIAL96 != 0 ? PCB_FULL_Y[9:0]  : pcb_wy;
    wire [10:0] pcb_box_x1 = PCB_FULLBOARD_SPATIAL96 != 0 ? PCB_FULL_X + PCB_FULL_W : pcb_wx + 11'd96;
    wire [9:0]  pcb_box_y1 = PCB_FULLBOARD_SPATIAL96 != 0 ? PCB_FULL_Y + PCB_FULL_H : pcb_wy + 10'd96;
    wire pcb_low_margin=pcb_cnn_margin < (PCB_BINARY_CLASSES != 0 ? PCB_BINARY_MARGIN_MIN : PCB_MARGIN_MIN);
    wire pcb_class_valid = PCB_BINARY_CLASSES != 0 ?
                           (pcb_cnn_class==2'd0 || pcb_cnn_class==2'd1) :
                           (pcb_cnn_class==2'd0 || pcb_cnn_class==2'd1 || pcb_cnn_class==2'd2);
    wire pcb_class_bad = PCB_BINARY_CLASSES != 0 ?
                         (pcb_cnn_class==2'd1) :
                         (pcb_cnn_class==2'd1 || pcb_cnn_class==2'd2);
    // Eight-connected neighboring windows vote REVIEW only when at least two
    // have low margins. One isolated low-margin window is ignored.
    // Windows are consumed in fixed left-to-right row order.  Keep the
    // previous-row flags aligned to the current column with shift registers;
    // this removes variable-index reads and writes from the PCB scan path.
    wire pcb_low_neighbor=(PCB_FIXED_WINDOW_ONLY != 0) ? pcb_low_margin :
        ((PCB_REVIEW_ENABLE != 0) && (pcb_left_low || ((pcb_wy!=0) &&
        (pcb_previous_low[0] || pcb_upper_left_low ||
         ((pcb_column<25)&&pcb_previous_low[1])))));
    reg cluster_start,cluster_candidate_valid,cluster_last;
    reg [63:0] cluster_candidate_box;
    reg [1:0] cluster_candidate_kind;
    reg [7:0] cluster_candidate_score;
    // The full-frame configuration uses the four-slot reducer below.  A
    // fixed-window PCB build can only produce one candidate, so keep that
    // result in a small register set and omit the reducer entirely.  This
    // removes the reducer's scan/sort state and its associated LUT fanout
    // from the fixed-window implementation without changing the published
    // defect interface.
    wire cluster_busy_legacy,cluster_done_legacy,cluster_review_legacy,cluster_ready_legacy;
    wire [2:0] cluster_count_legacy;
    wire [255:0] cluster_boxes_legacy;
    wire [7:0] cluster_kinds_legacy;
    wire [31:0] cluster_scores_legacy;
    reg fixed_candidate_valid;
    reg [63:0] fixed_candidate_box;
    reg [1:0] fixed_candidate_kind;
    wire cluster_busy=(PCB_FIXED_WINDOW_ONLY != 0) ? 1'b0 : cluster_busy_legacy;
    wire cluster_done=(PCB_FIXED_WINDOW_ONLY != 0) ? 1'b0 : cluster_done_legacy;
    wire cluster_review=(PCB_FIXED_WINDOW_ONLY != 0) ? 1'b0 : cluster_review_legacy;
    wire cluster_ready=(PCB_FIXED_WINDOW_ONLY != 0) ? 1'b1 : cluster_ready_legacy;
    wire [2:0] cluster_count=(PCB_FIXED_WINDOW_ONLY != 0) ? {2'b0,fixed_candidate_valid} : cluster_count_legacy;
    wire [255:0] cluster_boxes=(PCB_FIXED_WINDOW_ONLY != 0) ? {192'd0,fixed_candidate_box} : cluster_boxes_legacy;
    wire [7:0] cluster_kinds=(PCB_FIXED_WINDOW_ONLY != 0) ? {6'd0,fixed_candidate_kind} : cluster_kinds_legacy;
    // Pose7 has a board anomaly verdict, not verified defect localization.
    assign defect_count=3'd0;
    assign defect_boxes=256'd0;
    assign defect_kinds=8'd0;
    // PCB scan windows and their union bounds are 16-pixel aligned. Store
    // coordinates in 16-pixel units internally, then restore native pixels
    // on the published interface.
    assign cluster_busy_legacy=1'b0;assign cluster_done_legacy=1'b0;
    assign cluster_review_legacy=1'b0;assign cluster_ready_legacy=1'b1;
    assign cluster_count_legacy=3'd0;assign cluster_boxes_legacy=256'd0;
    assign cluster_kinds_legacy=8'd0;assign cluster_scores_legacy=32'd0;

    wire [7:0] minimum_cnn_margin=(color_margin_saved<shape_margin_saved) ? color_margin_saved : shape_margin_saved;
    // cnn_core emits one-based shape IDs: 1=triangle, 2=cylinder, 3=cube.
    // Threshold lookup must use that same protocol domain.
    wire [7:0] selected_shape_threshold=(shape_saved==1) ? TRIANGLE_MARGIN_MIN :
        (shape_saved==2) ? CIRCLE_MARGIN_MIN : SQUARE_MARGIN_MIN;
    // Hard rejection controls admission; a genuine zero margin remains a
    // publishable current candidate. Soft thresholds only set diagnostics.
    wire cnn_hard_reject=shape_reject_saved || color_samples_saved<8;
    wire cnn_soft_reject=color_margin_saved<COLOR_MARGIN_MIN ||
        shape_margin_saved<selected_shape_threshold;
    reg [1:0] cnn_color_work,cnn_shape_work;
    wire [15:0] candidate_class_id=({14'd0,cnn_color_work}-16'd1)*16'd3+{14'd0,cnn_shape_work};
    wire [127:0] packed_cnn_box={{8'd0,area},8'd0,confidence,candidate_class_id,{6'd0,y1},{5'd0,x1},{6'd0,y0},{5'd0,x0}};
    wire [1:0] stable_candidate_read_index;
    wire [1:0] previous_insert_index=insert_index[1:0]-2'd1;
    // Candidate input reads and raw insertion never execute in the same phase.
    // Reuse the existing wide bank read rather than introducing a second mux.
    wire [1:0] shared_candidate_read_index=(state==CNN_STABLE_WAIT) ?
        stable_candidate_read_index : previous_insert_index;
    wire [1:0] previous_slot_id=raw_slot_order[{previous_insert_index,1'b0}+:2];
    wire [1:0] physical_candidate_read_index=USE_INDIRECT_SORT ?
        raw_slot_order[{shared_candidate_read_index,1'b0}+:2] : shared_candidate_read_index;
    wire [127:0] previous_insert_box=multi_boxes[{physical_candidate_read_index,7'b0}+:128];
    reg stable_start;
    wire stable_busy,stable_done,stable_uncertain;
    wire [2:0] stable_count;
    wire stable_emit_begin,stable_emit_valid;
    wire [1:0] stable_emit_slot;
    wire [127:0] stable_emit_box;
    reg stable_raw_released;
    // Legacy unconnected simulation inputs are inactive; production drives it.
    wire stable_clear=(history_clear === 1'b1) || cfg_commit || (state==IDLE && purpose!=0);
    // Ordinary insertion and stable publication share one narrow write port.
    // The kernel has finished all raw reads before emit_begin reuses this bank.
    wire multi_insert_shift=insert_index!=0 && insert_box[87:80]>previous_insert_box[87:80];
    wire stable_slot_write=state==CNN_STABLE_WAIT && !stable_clear && stable_emit_valid;
    wire multi_slot_write=(USE_INDIRECT_SORT ? state==MULTI_STORE : state==MULTI_INSERT) || stable_slot_write;
    wire [1:0] multi_write_slot=stable_slot_write ? stable_emit_slot :
        (USE_INDIRECT_SORT ? multi_count[1:0] : insert_index[1:0]);
    wire [127:0] multi_write_box={8'd0,(stable_slot_write ? stable_emit_box[119:0] :
        (USE_INDIRECT_SORT ? packed_cnn_box[119:0] :
        (multi_insert_shift ? previous_insert_box[119:0] : insert_box[119:0])))};
    generate if(CNN_STABILITY_ENABLE != 0 && LOCAL_CNN_ENABLE != 0) begin : g_cnn_stability
        cnn_result_stabilizer #(.CONFIRM_RESULTS(CNN_CONFIRM_RESULTS),
            // Fixed160x90 CCL maps every raw endpoint exactly onto an 8px grid.
            // Store/match in that exact unit; emit restores original pixels.
            .HOLD_RESULTS(CNN_HOLD_RESULTS),.LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(22),.AREA_SHIFT(6),
            .EXTERNAL_CANDIDATE_READER(1),.COORD_SHIFT(3)) result_stability(
            .clk(clk),.rst_n(processing_rst_n),.clear(stable_clear),.start(stable_start),
            .input_count(multi_count),.input_boxes(multi_boxes),
            .input_candidate_box(previous_insert_box),.candidate_read_index(stable_candidate_read_index),
            .busy(stable_busy),.done(stable_done),
            .output_count(stable_count),.output_boxes(),.uncertain(stable_uncertain),
            .emit_begin(stable_emit_begin),.emit_valid(stable_emit_valid),
            .emit_slot(stable_emit_slot),.emit_box(stable_emit_box));
    end else begin : g_cnn_stability_bypass
        assign stable_busy=1'b0;
        assign stable_done=1'b0;
        assign stable_uncertain=1'b0;
        assign stable_count=3'd0;
        assign stable_emit_begin=1'b0;
        assign stable_emit_valid=1'b0;
        assign stable_emit_slot=2'd0;
        assign stable_emit_box=128'd0;
        assign stable_candidate_read_index=2'd0;
    end endgenerate
    // The tap is valid during the existing CNN_WRITE cycle.  Production
    // bridge integration should either use a one-word skid buffer or gate
    // CNN_WRITE with the bridge's ready signal; legacy users leave it open.
    assign yolo_pixel_valid=cnn_pixel_we;
    assign yolo_pixel_rgb=cnn_pixel_rgb;
    assign yolo_pixel_last=cnn_pixel_we && (sample_index==14'd4095);
    function [1:0] dominant_color;
        input [23:0] rgb;
        reg [8:0] r,g,b;
        begin
            r={1'b0,rgb[23:16]};g={1'b0,rgb[15:8]};b={1'b0,rgb[7:0]};
            if(r>=64 && r>g+24 && r>b+24 && ((r-g)*8>=r*3) && ((r-b)*8>=r*3))dominant_color=1;
            else if(g>=64 && g>r+24 && g>b+24 && ((g-r)*8>=g*3) && ((g-b)*8>=g*3))dominant_color=2;
            else if(b>=64 && b>r+24 && b>g+24 && ((b-r)*8>=b*3) && ((b-g)*8>=b*3))dominant_color=3;
            else dominant_color=0;
        end
    endfunction
    reg [10:0] roi_box_w,roi_span,roi_limit_x,roi_limit_y;
    reg [9:0] roi_box_h;
    reg [14:0] roi_scaled;
    reg signed [12:0] roi_center_x,roi_center_y;
    // Scratch fixed160x90 ->1280x720 specialization. Capture at the
    // original product-load edges, including the upper endpoint reload.
    // Low endpoint bits exactly reproduce the old stored quotient width.
    reg [7:0] fixed_map_x;
    reg [6:0] fixed_map_y;
    reg [15:0] fixed_area;
    // Keep original state/counter cadence and every public commit edge.
    reg [4:0] map_bits_left;
    reg [1:0] map_job;
    reg [14:0] confidence_numerator;
    // Separate the two-head minimum from the constant scale/add. Their
    // combined comparator -> mux -> DSP -> adder path exceeds 8 ns after
    // placement. This register adds one cycle per accepted ordinary ROI;
    // rounding, thresholds and all published confidence values are exact.
    reg [7:0] confidence_margin;
    // Keep all 37 original area wait clocks; exact area is sampled_area*64.
    reg [5:0] area_bits_left;

    always @(posedge clk or negedge processing_rst_n)begin
        if(!processing_rst_n)begin
            state<=IDLE;main_busy<=0;done<=0;pcb_reset<=0;result_job_id<=0;config_version<=0;color_id<=0;shape_id<=0;confidence<=0;valid<=0;
            x0<=0;y0<=0;x1<=0;y1<=0;area<=0;pcb_checked<=0;pcb_good<=0;pcb_status<=0;
            multi_count<=0;multi_boxes<=0;multi_flags<=0;box_index<=0;box_total<=0;insert_index<=0;insert_box<=0;cnn_color_work<=0;cnn_shape_work<=0;raw_slot_order<=0;insert_physical_slot<=0;
            teach_success<=0;teach_failed<=0;teach_code<=0;taught_station_header<=0;
            reader_request<=0;reader_invalidate<=0;sample_x<=0;sample_y<=0;cc_start<=0;cc_pixel_valid<=0;cc_filter<=1;
            cc_width<=160;cc_height<=90;cc_min_area<=12;cc_color<=0;
            sampled_rgb<=0;sampled_luma<=0;
            cnn_pixel_we<=0;cnn_start<=0;cnn_pixel_addr<=0;cnn_pixel_rgb<=0;
            stat_start<=0;shape_seen<=0;color_seen<=0;shape_reject_saved<=1;
            shape_saved<=0;color_saved<=0;shape_margin_saved<=0;color_margin_saved<=0;color_samples_saved<=0;
            cnn_sample_x<=0;cnn_sample_y<=0;
            pcb_pixel_we<=0;pcb_start<=0;pcb_pixel_addr<=0;pcb_pixel_gray<=0;
            pcb_wx<=0;pcb_wy<=0;pcb_px<=0;pcb_py<=0;pcb_column<=0;
            pcb_previous_low<=0;pcb_left_low<=0;pcb_upper_left_low<=0;pcb_review<=0;pcb_wait_cycles<=0;
            cluster_start<=0;cluster_candidate_valid<=0;cluster_last<=0;
            cluster_candidate_box<=0;cluster_candidate_kind<=0;cluster_candidate_score<=0;
            fixed_candidate_valid<=0;fixed_candidate_box<=0;fixed_candidate_kind<=0;
            gx<=0;gy<=0;station_left<=0;station_top<=0;scan_width<=1280;scan_height<=720;
            roi_left<=0;roi_top<=0;roi_side<=0;sampled_color<=0;sample_index<=0;
            fixed_area<=0;area_bits_left<=0;
            roi_box_w<=0;roi_box_h<=0;roi_span<=0;roi_scaled<=0;roi_center_x<=0;roi_center_y<=0;roi_limit_x<=0;roi_limit_y<=0;
            fixed_map_x<=0;fixed_map_y<=0;map_bits_left<=0;map_job<=0;confidence_numerator<=0;confidence_margin<=0;
            purpose_q<=2'd0;auto_cancel_seen<=1'b0;
            sampled_source_y<=0;pcb_ccl_pending<=0;pcb_ccl_drain_count<=0;
            stable_start<=1'b0;stable_raw_released<=1'b0;
        end else begin
            done<=0;reader_request<=0;reader_invalidate<=0;cc_start<=0;cc_pixel_valid<=0;cnn_pixel_we<=0;cnn_start<=0;stat_start<=0;pcb_pixel_we<=0;pcb_start<=0;
            cluster_start<=0;cluster_candidate_valid<=0;cluster_last<=0;
            stable_start<=1'b0;
            if(cancel&&pcb_frame_lock)auto_cancel_seen<=1'b1;
            // Include coincident acceptance/response; retain ownership until
            // the accepted pixel response and reader conversion have drained.
            if(pcb_ccl_read_response && (pcb_ccl_pending || pcb_ccl_read_accept))
                pcb_ccl_pending<=0;
            else if(pcb_ccl_read_accept)pcb_ccl_pending<=1;
            if(multi_slot_write)begin
                case(multi_write_slot)
                    0:multi_boxes[127:0]<=multi_write_box;
                    1:multi_boxes[255:128]<=multi_write_box;
                    2:multi_boxes[383:256]<=multi_write_box;
                    3:multi_boxes[511:384]<=multi_write_box;
                endcase
            end
            if(pcb_ccl_scan_owner && state!=PCB_CCL_DRAIN && state!=PCB_CCL_LOCKED &&
               (cancel || auto_cancel_seen))begin
                reader_request<=0;cc_start<=0;cc_pixel_valid<=0;
                valid<=0;pcb_checked<=0;pcb_good<=0;pcb_status<=3'd2;
                teach_code<=16'h0002;pcb_ccl_drain_count<=0;state<=PCB_CCL_DRAIN;
            end else case(state)
                IDLE:if(start&&!auto_busy)begin
                    pcb_reset<=0;main_busy<=1;result_job_id<=job_id;
                    config_version<=PCB_GOODONLY_AUTO!=0 ? 32'h50533731 : PCB_MODEL_VERSION;
                    purpose_q<=purpose;auto_cancel_seen<=1'b0;pcb_ccl_pending<=0;pcb_ccl_drain_count<=0;
                    teach_success<=0;teach_failed<=teach_good||purpose==2;
                    teach_code<=teach_good||purpose==2?16'd2:16'd0;taught_station_header<=0;
                    color_id<=0;shape_id<=0;confidence<=0;valid<=0;
                    x0<=0;y0<=0;x1<=0;y1<=0;area<=0;
                    pcb_checked<=0;pcb_good<=0;pcb_status<=0;
                    fixed_candidate_valid<=0;fixed_candidate_box<=0;fixed_candidate_kind<=0;
                    gx<=0;gy<=0;sample_index<=0;reader_invalidate<=1;
                    multi_count<=0;multi_boxes<=0;multi_flags<=0;box_index<=0;box_total<=0;stable_raw_released<=0;raw_slot_order<=0;insert_physical_slot<=0;
                    cc_width<=160;cc_height<=90;cc_min_area<=12;
                    // Ratio-8 is a filled colour mask, so enforce the CCL
                    // minimum dimensions and <=3:1 aspect filter. PCB reuses
                    // the same CCL with a source-Y mask and its latched
                    // mode-specific eligibility; teaching remains unsupported.
                    cc_filter<=1'b1;
                    station_left<=0;station_top<=0;scan_width<=1280;scan_height<=720;
                    if(purpose==2 || purpose==3 || teach_good)begin
                        pcb_status<=3'd3;state<=FINISH;
                    end else if(purpose==1)begin
                        if (PCB_ENABLE != 0 && PCB_GOODONLY_AUTO != 0) begin
                            state<=CC_START;
                        end else begin
                            // This variant contains pose7 only; the retired
                            // search, registration and TinyCNN paths are absent.
                            pcb_status<=3'd3;teach_failed<=1'b1;teach_code<=16'd3;
                            state<=FINISH;
                        end
                    end else state<=CC_START;
                end
                PCB_CCL_HANDOFF:begin
                    // Outputs remain in the CCL wrapper until whole-job completion.
                    // No owner transition while the shared reader is in flight.
                    if(!pcb_ccl_pending && reader_ready)state<=PCB_AUTO_START;
                end
                PCB_CCL_DRAIN:begin
                    reader_request<=0;cc_start<=0;cc_pixel_valid<=0;
                    valid<=0;pcb_checked<=0;pcb_good<=0;pcb_status<=3'd2;
                    if(!pcb_ccl_pending && reader_ready && !reader_request)begin
                        main_busy<=0;state<=IDLE;
                    end else if(pcb_ccl_drain_count==12'hfff)begin
                        // Timeout does not authorize releasing an unknown DDR response.
                        teach_code<=16'h0201;state<=PCB_CCL_LOCKED;
                    end else pcb_ccl_drain_count<=pcb_ccl_drain_count+1'b1;
                end
                PCB_CCL_LOCKED:begin
                    // Retain main_busy/frame lock until board reset. Never restart.
                    reader_request<=0;cc_start<=0;cc_pixel_valid<=0;valid<=0;
                end
                PCB_AUTO_START:begin
                    // Cancel may arrive after HANDOFF selected AUTO ownership,
                    // but before the core accepts start. Its start is fenced
                    // by both cancel signals above: no core done will follow.
                    if((cancel || auto_cancel_seen) && !auto_busy)begin
                        reader_request<=0;cc_start<=0;cc_pixel_valid<=0;
                        valid<=0;pcb_checked<=0;pcb_good<=0;pcb_status<=3'd2;
                        teach_code<=16'h0002;pcb_ccl_drain_count<=0;state<=PCB_CCL_DRAIN;
                    end else state<=PCB_AUTO_WAIT;
                end
                PCB_AUTO_WAIT:if(auto_done)begin
                    // Status is learned-normal anomaly judgement, not a CNN probability.
                    // Never relabel the entire detected PCB as a localized defect box.
                    // The paired main decodes {checked,good}, rather than the
                    // private status field. A valid REVIEW must leave checked
                    // clear or its HDMI status would be mislabelled FAIL.
                    pcb_checked<=auto_valid&&auto_bbox_valid&&
                        (auto_status==2'd0 || auto_status==2'd1);
                    pcb_good<=auto_valid&&auto_bbox_valid&&auto_status==0;
                    // A valid REVIEW may carry a geometry/registration reason.
                    // Keep the verdict separate from its diagnostic code.
                    pcb_status<=auto_status==2'd2 ? 3'd2 :
                        auto_valid ? {1'b0,auto_status} : 3'd3;
                    valid<=auto_valid&&auto_bbox_valid;
                    x0<=auto_bbox_valid?auto_xmin:11'd0;x1<=auto_bbox_valid?auto_xmax:11'd0;
                    y0<=auto_bbox_valid?auto_ymin:10'd0;y1<=auto_bbox_valid?auto_ymax:10'd0;
                    confidence<=0;area<=0;
                    teach_code<=auto_error;
                    if(auto_cancel_seen||cancel)begin
                        // Draining is not successful task completion. In
                        // particular it must never queue a cancelled PCB report.
                        main_busy<=0;state<=IDLE;valid<=0;pcb_checked<=0;pcb_good<=0;pcb_status<=3'd2;
                    end else state<=FINISH;
                end
                PCB_WINDOW_INIT:begin
                    sample_index<=0;pcb_px<=0;pcb_py<=0;pcb_wait_cycles<=0;
                    if (PCB_FULLBOARD_SPATIAL96 != 0) begin
                        pcb_src_x<=PCB_FULL_X+(PCB_FULL_W/192);
                        pcb_src_y<=PCB_FULL_Y+(PCB_FULL_H/192);
                        pcb_map_err_x<=(PCB_FULL_W/2)%96;
                        pcb_map_err_y<=(PCB_FULL_H/2)%96;
                    end
                    state<=PCB_PIXEL_REQ;
                end
                PCB_PIXEL_REQ:begin
                    if(reader_ready)begin
                        sample_x<=PCB_FULLBOARD_SPATIAL96 != 0 ? pcb_src_x : pcb_wx+pcb_px;
                        sample_y<=PCB_FULLBOARD_SPATIAL96 != 0 ? pcb_src_y : pcb_wy+pcb_py;
                        reader_request<=1;pcb_wait_cycles<=0;state<=PCB_PIXEL_WAIT;
                    end else if(pcb_wait_cycles>=PCB_TIMEOUT_CYCLES-1) state<=PCB_ERROR;
                    else pcb_wait_cycles<=pcb_wait_cycles+1'b1;
                end
                PCB_PIXEL_WAIT:begin
                    if(reader_valid)begin
                        pcb_pixel_gray<=reader_luma;pcb_pixel_addr<=sample_index;
                        pcb_wait_cycles<=0;state<=PCB_PIXEL_WRITE;
                    end else if(pcb_wait_cycles>=PCB_TIMEOUT_CYCLES-1) state<=PCB_ERROR;
                    else pcb_wait_cycles<=pcb_wait_cycles+1'b1;
                end
                PCB_PIXEL_WRITE:begin
                    pcb_pixel_we<=1;
                    if(sample_index==14'd9215)state<=PCB_START;
                    else begin
                        sample_index<=sample_index+1'b1;
                        if (PCB_FULLBOARD_SPATIAL96 != 0) begin
                            if(pcb_px==95) begin
                                pcb_px<=0;pcb_py<=pcb_py+1'b1;
                                pcb_src_x<=PCB_FULL_X+(PCB_FULL_W/192);
                                pcb_map_err_x<=(PCB_FULL_W/2)%96;
                                if ((pcb_map_err_y + (PCB_FULL_H%96)) >= 96) begin
                                    pcb_src_y<=pcb_src_y+(PCB_FULL_H/96)+1;
                                    pcb_map_err_y<=pcb_map_err_y+(PCB_FULL_H%96)-96;
                                end else begin
                                    pcb_src_y<=pcb_src_y+(PCB_FULL_H/96);
                                    pcb_map_err_y<=pcb_map_err_y+(PCB_FULL_H%96);
                                end
                            end else begin
                                pcb_px<=pcb_px+1'b1;
                                if ((pcb_map_err_x + (PCB_FULL_W%96)) >= 96) begin
                                    pcb_src_x<=pcb_src_x+(PCB_FULL_W/96)+1;
                                    pcb_map_err_x<=pcb_map_err_x+(PCB_FULL_W%96)-96;
                                end else begin
                                    pcb_src_x<=pcb_src_x+(PCB_FULL_W/96);
                                    pcb_map_err_x<=pcb_map_err_x+(PCB_FULL_W%96);
                                end
                            end
                        end else if(pcb_px==95)begin pcb_px<=0;pcb_py<=pcb_py+1'b1;end
                        else pcb_px<=pcb_px+1'b1;
                        state<=PCB_PIXEL_REQ;
                    end
                end
                PCB_START:begin pcb_start<=1;pcb_wait_cycles<=0;state<=PCB_WAIT;end
                PCB_WAIT:begin
                    if(pcb_cnn_done)begin
                        // Class 3 is reserved; unknown simulation results fail closed.
                        if(!pcb_class_valid || pcb_cnn_class==3 || (^pcb_cnn_class===1'bx) ||
                           (^pcb_cnn_score===1'bx) || (^pcb_cnn_margin===1'bx) ||
                           (^pcb_cnn_sat===1'bx)) state<=PCB_ERROR;
                        else begin
                            if(pcb_cnn_score>confidence)confidence<=pcb_cnn_score;
                            if((PCB_BINARY_CLASSES != 0 && pcb_low_margin) ||
                               (PCB_BINARY_CLASSES == 0 && pcb_low_margin && pcb_low_neighbor)) pcb_review<=1;
                            pcb_upper_left_low<=pcb_previous_low[0];
                            pcb_previous_low<={pcb_low_margin,pcb_previous_low[25:1]};
                            pcb_left_low<=pcb_low_margin;
                            if(!pcb_low_margin && pcb_class_bad)begin
                                cluster_candidate_box<={6'd0,pcb_box_y1,5'd0,pcb_box_x1,6'd0,pcb_box_y0,5'd0,pcb_box_x0};
                                cluster_candidate_kind<=pcb_cnn_class;cluster_candidate_score<=pcb_cnn_score;
                                if (PCB_FIXED_WINDOW_ONLY != 0) begin
                                    fixed_candidate_valid<=1'b1;
                                    fixed_candidate_box<={6'd0,pcb_box_y1,5'd0,pcb_box_x1,6'd0,pcb_box_y0,5'd0,pcb_box_x0};
                                    fixed_candidate_kind<=pcb_cnn_class;
                                end
                                pcb_wait_cycles<=0;state<=PCB_EMIT;
                            end else state<=PCB_NEXT;
                        end
                    end else if(pcb_wait_cycles>=PCB_TIMEOUT_CYCLES-1)state<=PCB_ERROR;
                    else pcb_wait_cycles<=pcb_wait_cycles+1'b1;
                end
                PCB_EMIT:begin
                    if (PCB_FIXED_WINDOW_ONLY != 0) begin
                        state<=PCB_NEXT;
                    end else if(cluster_ready)begin cluster_candidate_valid<=1;state<=PCB_NEXT;end
                    else if(pcb_wait_cycles>=PCB_TIMEOUT_CYCLES-1)state<=PCB_ERROR;
                    else pcb_wait_cycles<=pcb_wait_cycles+1'b1;
                end
                PCB_NEXT:begin
                    if (PCB_FIXED_WINDOW_ONLY != 0) begin
                        // The fixed-window variant emits at most one candidate.
                        // Close the candidate stream immediately after that
                        // inference; the single-slot reducer receives the
                        // terminating marker in PCB_FINISH.
                        state<=PCB_FINISH;
                    end else begin
                    // 26 columns: 0,48,...,1152,1184. Fourteen rows end at624.
                    // The final clamped window covers every right/bottom pixel.
                    if(pcb_wx==1184)begin
                        pcb_wx<=0;pcb_column<=0;pcb_left_low<=0;pcb_upper_left_low<=0;
                        if(pcb_wy==624)state<=PCB_FINISH;
                        else begin pcb_wy<=pcb_wy+10'd48;state<=PCB_WINDOW_INIT;end
                    end else begin
                        pcb_wx<=pcb_wx+11'd48>11'd1184 ? 11'd1184 : pcb_wx+11'd48;
                        pcb_column<=pcb_column+1'b1;state<=PCB_WINDOW_INIT;
                    end
                    end
                end
                PCB_FINISH:begin
                    if (PCB_FIXED_WINDOW_ONLY != 0) begin
                        // The fixed-window path has already captured its one
                        // candidate.  Publish directly and skip the generic
                        // reducer flush/sort sequence.
                        pcb_checked<=1;valid<=1;
                        x0<=0;y0<=0;x1<=1280;y1<=720;area<=24'd921600;
                        if(fixed_candidate_valid)begin pcb_good<=0;pcb_status<=1;end
                        else if(pcb_review)begin pcb_good<=0;pcb_status<=2;end
                        else begin pcb_good<=1;pcb_status<=0;end
                        confidence_numerator<=confidence*15'd100+15'd127;confidence<=0;
                        state<=PCB_CONF_DIV;
                    end else if(cluster_ready)begin cluster_last<=1;pcb_wait_cycles<=0;state<=PCB_CLUSTER_WAIT;end
                    else if(pcb_wait_cycles>=PCB_TIMEOUT_CYCLES-1)state<=PCB_ERROR;
                    else pcb_wait_cycles<=pcb_wait_cycles+1'b1;
                end
                PCB_CLUSTER_WAIT:begin
                    if(cluster_done)begin
                        pcb_checked<=1;valid<=1;
                        x0<=0;y0<=0;x1<=1280;y1<=720;area<=24'd921600;
                        if(cluster_count!=0)begin pcb_good<=0;pcb_status<=1;end
                        else if(pcb_review || cluster_review)begin pcb_good<=0;pcb_status<=2;end
                        else begin pcb_good<=1;pcb_status<=0;end
                        confidence_numerator<=confidence*15'd100+15'd127;confidence<=0;
                        state<=PCB_CONF_DIV;
                    end else if(pcb_wait_cycles>=PCB_TIMEOUT_CYCLES-1)state<=PCB_ERROR;
                    else pcb_wait_cycles<=pcb_wait_cycles+1'b1;
                end
                PCB_CONF_DIV:begin
                    if(confidence_numerator>=15'd255)begin
                        confidence_numerator<=confidence_numerator-15'd255;confidence<=confidence+1'b1;
                    end else state<=FINISH;
                end
                PCB_ERROR:begin
                    pcb_reset<=1;
                    valid<=0;pcb_checked<=0;pcb_good<=0;pcb_status<=3;
                    confidence<=0;x0<=0;y0<=0;x1<=0;y1<=0;area<=0;
                    state<=FINISH;
                end
                CC_START:begin cc_start<=1;state<=SCAN_REQ;end
                SCAN_REQ:if(reader_ready)begin
                    // Fast ordinary jobs scan a 160x90 grid at exact /8
                    // sample centres. The source RGB frame remains 1280x720.
                    sample_x<={gx,3'b000}+11'd4;
                    sample_y<={gy,3'b000}+10'd4;
                    reader_request<=1;state<=SCAN_WAIT;
                end
                SCAN_WAIT:if(reader_valid)begin sampled_rgb<=reader_rgb;sampled_source_y<=reader_luma;state<=SCAN_LUMA;end
                SCAN_LUMA:begin sampled_luma<=rgb_luma8(sampled_rgb);state<=SCAN_SEND;end
                SCAN_SEND:if(cc_ready && !cc_pixel_valid)begin
                    cc_color<=sampled_color;cc_pixel_valid<=1;
                    if(gx==159)begin gx<=0;if(gy==89)state<=CC_WAIT;else begin gy<=gy+1'b1;state<=SCAN_REQ;end end
                    else begin gx<=gx+1'b1;state<=SCAN_REQ;end
                end
                CC_WAIT:if(cc_done)begin
                    if(PCB_GOODONLY_AUTO!=0 && purpose_active==2'd1)begin
                        // The PCB core owns NO_TARGET/overflow/truncation verdicts.
                        // A CCL rectangle is never itself PASS or FAIL.
                        state<=PCB_CCL_HANDOFF;
                    end else if(cc_overflow || cc_count==0)begin
                        // Empty/overflow frames also age the target history.
                        multi_flags<=cc_overflow?8'h84:8'h80;state<=CNN_STABLE_START;
                    end else begin
                        // Label-table overflow is a fail-closed result above.
                        // More than four valid components is separately marked
                        // as truncated; the four largest remain usable.
                        box_index<=0;
                        box_total<=cc_count>4 ? 3'd4 : cc_count;
                        multi_flags<=cc_truncated ? 8'h04 : 8'h00;
                        state<=BOX_MAP;
                    end
                end
                BOX_MAP:begin
                    // Reject tiny fragmented color components before ROI/CNN.
                    if(ordinary_box_small) state<=MULTI_NEXT;
                    else begin
                    // Original lower-endpoint and area product capture edge.
                    // Native endpoints are exactly grid*8, area is grid_area*64.
                    fixed_map_x<=selected_box[7:0];
                    fixed_map_y<=selected_box[22:16];
                    fixed_area<=selected_area;
                    map_job<=1;state<=COORD_INIT;
                    end
                end
                COORD_INIT:begin
                    map_bits_left<=20;state<=COORD_DIV;
                end
                COORD_DIV:begin
                    if(map_bits_left==1)state<=COORD_STORE;else map_bits_left<=map_bits_left-1'b1;
                end
                COORD_STORE:begin
                    // map_job=0 has no reachable entry in the fixed scanner;
                    // preserve its legacy branch shape without a divider.
                    if(map_job==0)begin
                        sample_x<=station_left+{fixed_map_x,3'b000}+11'd2;
                        sample_y<=station_top+{fixed_map_y,3'b000}+10'd2;
                        reader_request<=1;state<=SCAN_WAIT;
                    end else if(map_job==1)begin
                        x0<=station_left+{fixed_map_x,3'b000};y0<=station_top+{fixed_map_y,3'b000};
                        // Original upper-endpoint product capture edge.
                        fixed_map_x<=selected_box[39:32];
                        fixed_map_y<=selected_box[54:48];
                        map_job<=2;state<=COORD_INIT;
                    end else begin
                        x1<=station_left+{fixed_map_x,3'b000};y1<=station_top+{fixed_map_y,3'b000};
                        valid<=1;state<=AREA_MUL_Y;
                    end
                end
                AREA_MUL_Y:begin state<=AREA_DIV_INIT;end
                AREA_DIV_INIT:begin area_bits_left<=37;state<=AREA_DIV;end
                AREA_DIV:begin
                    if(area_bits_left==1)begin area<={2'b00,fixed_area,6'b000000};state<=ROI_PREP;end
                    else area_bits_left<=area_bits_left-1'b1;
                end
                ROI_PREP:begin
                    sample_index<=0;
                    roi_box_w<=x1-x0;roi_box_h<=y1-y0;
                    state<=ROI_MAX;
                end
                // Frozen FC4 training uses ceil(span*5/4), with a 720 cap.
                // When span>720 keep the legacy clamp fallback. Otherwise
                // retain the signed centre and supply RGB128 outside frame.
                ROI_MAX:begin roi_span<=roi_box_w>{1'b0,roi_box_h} ? roi_box_w : {1'b0,roi_box_h};state<=ROI_SCALE;end
                ROI_SCALE:begin roi_scaled<={1'b0,roi_span,3'b000}+{3'b000,roi_span,1'b0}+15'd7;state<=ROI_SIDE;end
                ROI_SIDE:begin
                    roi_side<=roi_scaled[14:3]>12'd720 ? 11'd720 : roi_scaled[14:3]<12'd8 ? 11'd8 : roi_scaled[13:3];
                    state<=ROI_CENTER;
                end
                ROI_CENTER:begin
                    roi_center_x<=$signed({2'b00,x0})+$signed({2'b00,x1})-$signed({2'b00,roi_side});
                    roi_center_y<=$signed({3'b000,y0})+$signed({3'b000,y1})-$signed({2'b00,roi_side});
                    roi_limit_x<=11'd1280-roi_side;roi_limit_y<=11'd720-roi_side;state<=ROI_CLAMP;
                end
                ROI_CLAMP:begin
                    if(roi_span>720)begin
                        roi_left<=roi_center_x<0 ? 13'sd0 : roi_center_x[12:1]>{1'b0,roi_limit_x} ? $signed({2'b00,roi_limit_x}) : $signed({2'b00,roi_center_x[11:1]});
                        roi_top<=roi_center_y<0 ? 13'sd0 : roi_center_y[12:1]>{1'b0,roi_limit_y} ? $signed({2'b00,roi_limit_y}) : $signed({3'b000,roi_center_y[10:1]});
                    end else begin roi_left<=roi_center_x>>>1;roi_top<=roi_center_y>>>1;end
                    state<=CNN_COORD;
                end
                CNN_COORD:begin
                    cnn_sample_x<=roi_left+$signed({2'b00,cnn_offset_x[16:6]});
                    cnn_sample_y<=roi_top+$signed({2'b00,cnn_offset_y[16:6]});
                    state<=CNN_REQ;
                end
                CNN_REQ:begin
                    if(!cnn_sample_inside)begin
                        cnn_pixel_rgb<=24'h808080;cnn_pixel_addr<=sample_index[11:0];state<=CNN_WRITE;
                    end else if(reader_ready)begin
                        sample_x<=cnn_sample_x[10:0];sample_y<=cnn_sample_y[9:0];
                        reader_request<=1;state<=CNN_WAIT;
                    end
                end
                CNN_WAIT:if(reader_valid)begin cnn_pixel_rgb<=reader_rgb;cnn_pixel_addr<=sample_index[11:0];state<=CNN_WRITE;end
                CNN_WRITE:begin
                    cnn_pixel_we<=1;
                    if(sample_index==4095)state<=CNN_START;else begin sample_index<=sample_index+1'b1;state<=CNN_COORD;end
                end
                CNN_START:begin
                    cnn_start<=1;shape_seen<=0;color_seen<=0;state<=CNN_DONE;
                end
                CNN_DONE:begin
                    if(cnn_done)begin
                        shape_seen<=1;shape_saved<=cnn_shape;shape_margin_saved<=cnn_shape_conf;
                        shape_reject_saved<=cnn_background_reject;
                        color_seen<=1;color_saved<=cnn_color;color_margin_saved<=cnn_color_conf;
                        color_samples_saved<=20'd4096;
                    end
                    if(shape_seen && color_seen)begin
                        cnn_color_work<=color_saved;cnn_shape_work<=shape_saved;
                        // Preserve the existing thresholds and bit6 diagnostic.
                        // Hard background rejection never enters the candidate
                        // bank. A real zero score is distinct: it still reaches
                        // the stabilizer, which publishes current geometry while
                        // tracking class confirmation independently.
                        if(cnn_hard_reject || cnn_soft_reject)
                            multi_flags[6]<=1'b1;
                        if(CNN_LOWCONF_OUTPUT != 0)
                            confidence_margin<=cnn_hard_reject ? 8'd0 : minimum_cnn_margin;
                        else
                            confidence_margin<=(cnn_hard_reject || cnn_soft_reject) ?
                                8'd0 : minimum_cnn_margin;
                        confidence<=0;
                        state<=cnn_hard_reject ? MULTI_NEXT : CONF_SCALE;
                    end
                end
                CONF_SCALE:begin
                    confidence_numerator<=confidence_margin*15'd100+15'd127;
                    state<=CONF_DIV;
                end
                CONF_DIV:begin
                    if(confidence_numerator>=15'd255)begin confidence_numerator<=confidence_numerator-15'd255;confidence<=confidence+1'b1;end
                    else state<=MULTI_STORE;
                end
                MULTI_STORE:begin
                    insert_box<=packed_cnn_box;insert_index<=multi_count;
                    insert_physical_slot<=multi_count[1:0];state<=MULTI_INSERT;
                end
                MULTI_INSERT:begin
                    // Stable confidence insertion changes only slot identities.
                    // In bypass mode the exact old payload-moving path remains.
                    if(USE_INDIRECT_SORT)begin
                        case(insert_index[1:0])
                            0:raw_slot_order[1:0]<=multi_insert_shift?previous_slot_id:insert_physical_slot;
                            1:raw_slot_order[3:2]<=multi_insert_shift?previous_slot_id:insert_physical_slot;
                            2:raw_slot_order[5:4]<=multi_insert_shift?previous_slot_id:insert_physical_slot;
                            3:raw_slot_order[7:6]<=multi_insert_shift?previous_slot_id:insert_physical_slot;
                        endcase
                    end
                    if(multi_insert_shift)begin
                        insert_index<=insert_index-1'b1;
                    end else begin
                        multi_count<=multi_count+1'b1;state<=MULTI_NEXT;
                    end
                end
                MULTI_NEXT:begin
                    if(box_index+1'b1<box_total)begin box_index<=box_index+1'b1;state<=BOX_MAP;end
                    else state<=CNN_STABLE_START;
                end
                CNN_STABLE_START:begin
                    if(CNN_STABILITY_ENABLE == 0 || LOCAL_CNN_ENABLE == 0)state<=MULTI_PUBLISH;
                    else if(!stable_clear && !stable_busy)begin
                        stable_start<=1'b1;state<=CNN_STABLE_WAIT;
                    end
                end
                CNN_STABLE_WAIT:begin
                    // Before emit_begin, the raw bank still supports a clear
                    // restart. Once reused, clear completes empty; it cannot
                    // reinterpret partially committed output as fresh evidence.
                    if(stable_clear)begin
                        if(stable_raw_released)begin
                            multi_count<=0;multi_boxes<=0;
                            multi_flags<=(multi_flags|8'hc0)&8'hfe;
                            state<=MULTI_PUBLISH;
                        end else state<=CNN_STABLE_START;
                    end else begin
                        if(stable_emit_begin)begin
                            multi_boxes<=0;multi_count<=0;stable_raw_released<=1;
                        end
                        if(stable_done)begin
                            multi_count<=stable_count;
                            multi_flags[6]<=multi_flags[6] || stable_uncertain;
                            state<=MULTI_PUBLISH;
                        end
                    end
                end
                MULTI_PUBLISH:begin
                    // Publish the current valid candidates after every raw read
                    // and the serial stable emit have finished. Confirmation
                    // controls the name; it does not hide an unconfirmed box.
                    // Type18, Type8 compatibility and KEY1's cache all consume
                    // this result; raw confidence-sorted argmax stays internal.
                    if(stable_clear)begin
                        // Clear may arrive after the kernel's done handshake.
                        // Never republish its previous confirmed snapshot into
                        // a cache that the parent has just invalidated.
                        multi_count<=0;multi_boxes<=0;
                        multi_flags<=(multi_flags|8'hc0)&8'hfe;
                        valid<=0;color_id<=0;shape_id<=0;confidence<=0;
                        x0<=0;y0<=0;x1<=0;y1<=0;area<=0;
                    end else begin
                    multi_flags[0]<=multi_count!=0;multi_flags[7]<=multi_count==0;
                    valid<=multi_count!=0;
                    x0<=multi_boxes[10:0];y0<=multi_boxes[25:16];x1<=multi_boxes[42:32];y1<=multi_boxes[57:48];
                    confidence<=multi_boxes[87:80];area<=multi_boxes[119:96];
                    case(multi_boxes[79:64])
                        1:begin color_id<=1;shape_id<=1;end 2:begin color_id<=1;shape_id<=2;end 3:begin color_id<=1;shape_id<=3;end
                        4:begin color_id<=2;shape_id<=1;end 5:begin color_id<=2;shape_id<=2;end 6:begin color_id<=2;shape_id<=3;end
                        7:begin color_id<=3;shape_id<=1;end 8:begin color_id<=3;shape_id<=2;end 9:begin color_id<=3;shape_id<=3;end
                        default:begin color_id<=0;shape_id<=0;end
                    endcase
                    end
                    state<=FINISH;
                end
                FINISH:begin
                    // The final completion edge is another clear boundary.
                    // Publish an empty ordinary result instead of allowing
                    // an old confirmed class to re-enter the top cache.
                    if(purpose_active==0 && stable_clear)begin
                        multi_count<=0;multi_boxes<=0;
                        multi_flags<=(multi_flags|8'hc0)&8'hfe;
                        valid<=0;color_id<=0;shape_id<=0;confidence<=0;
                        x0<=0;y0<=0;x1<=0;y1<=0;area<=0;
                    end
                    main_busy<=0;done<=1;state<=IDLE;
                end
                default:state<=PCB_ERROR;
            endcase
        end
    end
endmodule
