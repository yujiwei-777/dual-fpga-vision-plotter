// Ordinary-CNN candidate publication with four spatially matched identities.
//
// This block receives one NEW inference result per start, including count=0.
// The caller holds input_count/input_boxes until emit_begin. From that
// boundary all raw candidate reads are finished, allowing one caller bank
// to receive the serial result. The compatibility output_boxes remains
// available for golden comparison; production can leave it disconnected
// so its separate result register bank is removed by synthesis. It does not
// count video refreshes, retried packets or retained result mailboxes.
//
// HXA box: {area32,reserved8,confidence8,class16,y1,x1,y0,x0}.
// Right/bottom are exclusive. The model's existing confidence=0 means
// ambiguous; this block never upgrades that score or changes model logits.
// Every legal current candidate is visible immediately. Confirmation changes
// only the class name: during a short class change, geometry and confidence
// always come from the current candidate, never an old observation.
//
// Geometry uses overlapping boxes, width/height ratios no greater than 2,
// and centre displacement no greater than half the larger dimension on
// each axis. Doubled centres avoid fractions. Existing tracks are paired
// globally by minimum centre L1 distance, one pair per serial search; only
// after all existing-track matching are unmatched candidates allocated.
// Packed-table candidate: one 16-bit x 32 synchronous RAM holds four
// exact payload/metadata records, at fixed eight-word track strides.
// A record is read serially into one active cache. Full-record writes
// finish before track validity/visibility commits or emission begins.
// The input/emission protocol and class/geometry decisions are unchanged.
// No reset/clear on RAM, its read output, or cache; validity guards stale data.
module cnn_result_stabilizer #(
    parameter integer CONFIRM_RESULTS=3, // Supported: 1..15.
    parameter integer HOLD_RESULTS=2,    // Supported: 0..15.
    parameter integer LOST_RESULTS=3,    // Supported: 1..15.
    parameter integer AREA_BITS=32,      // Supported:20..32; production uses24.
    parameter integer EXTERNAL_CANDIDATE_READER=0, // Combinational addressed slot; no extra read latency.
    // Lossless coordinate-grid specialization. Default accepts every pixel.
    // Nonzero modes reject nonaligned candidates instead of rounding.
    parameter integer COORD_SHIFT=0, // Supported:0..3; production=3.
    // Lossless area-grid specialization. Default keeps the full legacy domain.
    // Nonzero modes reject nonaligned/out-of-range areas instead of rounding.
    parameter integer AREA_SHIFT=0 // Supported:0..AREA_BITS-1; production=6 with AREA_BITS=22.
)(
    input wire clk,rst_n,
    input wire clear,start,
    input wire [2:0] input_count,
    input wire [511:0] input_boxes,
    output reg busy,done,
    output reg [2:0] output_count,
    output reg [511:0] output_boxes,
    output reg uncertain,
    output wire emit_begin,emit_valid,
    output wire [1:0] emit_slot,
    output wire [127:0] emit_box,
    // Optional caller-owned shared read mux. The caller must present this
    // address's raw slot combinationally until emit_begin transfers ownership.
    input wire [127:0] input_candidate_box,
    output wire [1:0] candidate_read_index
);
`ifndef SYNTHESIS
    initial begin
        if(CONFIRM_RESULTS<1 || CONFIRM_RESULTS>15 ||
           HOLD_RESULTS<0 || HOLD_RESULTS>15 ||
           LOST_RESULTS<1 || LOST_RESULTS>15 || AREA_BITS<20 || AREA_BITS>32 ||
           COORD_SHIFT<0 || COORD_SHIFT>3 || AREA_SHIFT<0 || AREA_SHIFT>=AREA_BITS) begin
            $display("ERROR cnn_result_stabilizer: confirmation/lost must be 1..15, hold 0..15, area 20..32, coordinate shift 0..3, area shift 0..AREA_BITS-1");
            $finish;
        end
    end
`endif
    localparam integer X_BITS=11-COORD_SHIFT;
    localparam integer Y_BITS=10-COORD_SHIFT;
    localparam integer COORD_BITS=2*X_BITS+2*Y_BITS;
    localparam integer AREA_CODE_BITS=AREA_BITS-AREA_SHIFT;
    localparam integer X1_LSB=X_BITS,Y0_LSB=2*X_BITS,Y1_LSB=2*X_BITS+Y_BITS;
    // Doubled centres fit this lane; its reused confidence byte also fits.
    localparam integer LANE_BITS=12-COORD_SHIFT;
    localparam integer DISTANCE_BITS=LANE_BITS+1;
    // Distance and area-code comparisons share one register in disjoint phases.
    // Geometry stays in the existing coordinate units, not area-code units.
    localparam integer METRIC_BITS=(AREA_CODE_BITS>DISTANCE_BITS)?AREA_CODE_BITS:DISTANCE_BITS;
    localparam [31:0] AREA_LOW_MASK=(32'h00000001<<AREA_SHIFT)-32'h00000001;
    localparam [31:0] AREA_HIGH_MASK=32'hffffffff<<AREA_BITS;
    localparam [15:0] GRID_MASK=(16'h0001<<COORD_SHIFT)-16'h0001;
    localparam integer CONFIRM_BITS=(CONFIRM_RESULTS<2)?1:$clog2(CONFIRM_RESULTS+1);
    localparam integer HOLD_BITS=(HOLD_RESULTS<2)?1:$clog2(HOLD_RESULTS+1);
    localparam integer LOST_BITS=(LOST_RESULTS<2)?1:$clog2(LOST_RESULTS+1);
    localparam [CONFIRM_BITS-1:0] CONFIRM_LIMIT=CONFIRM_RESULTS;
    localparam [HOLD_BITS-1:0] HOLD_LIMIT=HOLD_RESULTS;
    localparam [LOST_BITS-1:0] LOST_LIMIT=LOST_RESULTS;

    localparam [5:0] S_IDLE=0,S_VALIDATE=1,S_MATCH_INIT=2,
        S_PAIR_LOAD=3,S_PAIR_DIMS=4,S_PAIR_DIFF=5,S_PAIR_GEOM=6,
        S_PAIR_COMPARE=7,S_MATCH_COMMIT=8,S_UPDATE_SELECT=9,
        S_UPDATE_LOAD=10,S_UPDATE_APPLY=11,S_ALLOC_INIT=12,
        S_ALLOC_SCAN=13,S_ALLOC_CHOOSE=14,S_ALLOC_FREE=15,
        S_PRIMARY_INIT=16,S_PRIMARY_SCAN=17,S_PRIMARY_CHOOSE=18,
        S_OUTPUT_PRIMARY=19,S_OUTPUT_OTHER=20,S_FINISH=21,S_PAIR_Y_LOAD=22,
        S_PAIR_WAIT=23,S_PRIMARY_WAIT=24,S_EMIT_WAIT=25,S_OUTPUT_OTHER_WAIT=26,
        S_UPDATE_PRELOAD=27,S_RAM_READ_ISSUE=28,S_RAM_READ_CAPTURE=29,
        S_RAM_WRITE=30,S_UPDATE_COMMIT=31,S_UPDATE_AGE_COMMIT=32;
    reg [5:0] state,ram_resume_state;
    reg [2:0] ram_word;
    reg write_uncertain,age_expire;
    reg [2:0] count_limit;
    reg [3:0] candidate_valid,candidate_matched,track_matched,visible;
    reg [3:0] track_used;
    reg primary_valid;
    reg [1:0] primary_track;
    reg [1:0] candidate_index,track_index;
    assign candidate_read_index=candidate_index;
    wire [127:0] candidate_box=(EXTERNAL_CANDIDATE_READER!=0)?
        input_candidate_box:input_boxes[{candidate_index,7'b0}+:128];

    // Exact legacy payload layout; only its physical table encoding changes.
    localparam integer PAYLOAD_BITS=AREA_CODE_BITS+COORD_BITS;
    wire [PAYLOAD_BITS-1:0] payload_q;
    wire [PAYLOAD_BITS-1:0] payload_wdata={candidate_box[96+AREA_SHIFT+:AREA_CODE_BITS],
        candidate_box[48+COORD_SHIFT+:Y_BITS],candidate_box[16+COORD_SHIFT+:Y_BITS],
        candidate_box[32+COORD_SHIFT+:X_BITS],candidate_box[COORD_SHIFT+:X_BITS]};
    // One atomic control word per track. Only validity and candidate mapping
    // remain flip-flops. No reset/clear is applied to this RAM or read output.
    localparam integer META_COUNT_LSB=8;
    localparam integer META_BAD_LSB=META_COUNT_LSB+CONFIRM_BITS;
    localparam integer META_LOST_LSB=META_BAD_LSB+HOLD_BITS;
    localparam integer META_CONFIDENCE_LSB=META_LOST_LSB+LOST_BITS;
    localparam integer META_BITS=META_CONFIDENCE_LSB+8;
    wire [META_BITS-1:0] metadata_q;
    wire [3:0] meta_confirmed=metadata_q[3:0];
    wire [3:0] meta_pending=metadata_q[7:4];
    wire [CONFIRM_BITS-1:0] meta_count=metadata_q[META_COUNT_LSB+:CONFIRM_BITS];
    wire [HOLD_BITS-1:0] meta_bad=metadata_q[META_BAD_LSB+:HOLD_BITS];
    wire [LOST_BITS-1:0] meta_lost=metadata_q[META_LOST_LSB+:LOST_BITS];
    wire [7:0] meta_confidence=metadata_q[META_CONFIDENCE_LSB+:8];
    reg [3:0] next_confirmed,next_pending;
    reg [CONFIRM_BITS-1:0] next_count;
    reg [HOLD_BITS-1:0] next_bad;
    reg [LOST_BITS-1:0] next_lost;
    reg [7:0] next_confidence;
    reg update_visible,update_uncertain;
    wire [META_BITS-1:0] metadata_wdata={next_confidence,next_lost,next_bad,
        next_count,next_pending,next_confirmed};
    // At production settings: payload46 + metadata22 = 68 bits, five
    // 16-bit words per track. Generic legal parameters require at most seven.
    // Fixed stride avoids an address multiplier; unused words are not read.
    localparam integer TABLE_BITS=PAYLOAD_BITS+META_BITS;
    localparam integer TABLE_WORDS=(TABLE_BITS+15)/16;
    localparam integer CACHE_BITS=TABLE_WORDS*16;
    (* ram_style="bram" *) reg [15:0] track_table[0:31];
    reg [15:0] table_q;
    reg [CACHE_BITS-1:0] table_cache;
    assign payload_q=table_cache[0+:PAYLOAD_BITS];
    assign metadata_q=table_cache[PAYLOAD_BITS+:META_BITS];
    wire [4:0] table_address={track_index,ram_word};
    wire table_active=rst_n && busy && !clear;
    wire table_we=table_active && state==S_RAM_WRITE;
    wire cache_new_record=table_active && state==S_UPDATE_APPLY;
    wire cache_age_record=table_active && state==S_UPDATE_SELECT &&
        track_used[track_index] && !track_matched[track_index];
    always @(posedge clk)begin
        if(table_we)track_table[table_address]<=table_cache[ram_word*16+:16];
        table_q<=track_table[table_address];
    end
    // This is one working record, never a second publication bank. Clear and
    // reset suppress every write and abandon partial work through the FSM.
    always @(posedge clk)begin
        if(cache_new_record)
            table_cache<={{(CACHE_BITS-TABLE_BITS){1'b0}},metadata_wdata,payload_wdata};
        else if(cache_age_record)
            table_cache<={{(CACHE_BITS-TABLE_BITS){1'b0}},metadata_wdata,payload_q};
        else if(table_active && state==S_RAM_READ_CAPTURE)
            table_cache[ram_word*16+:16]<=table_q;
    end
    reg [1:0] candidate_for_track[0:3];

    reg [1:0] best_candidate,best_track;
    reg best_found;
    // Matching, allocation and primary selection are disjoint phases. Reuse
    // their best metric, valid flag and candidate index instead of retaining
    // three register banks. Matching uses only DISTANCE_BITS low metric bits.
    reg [METRIC_BITS-1:0] best_metric;
    // Reading one input slot per clock keeps the input mux shared.
    wire candidate_grid_aligned=(((candidate_box[15:0] | candidate_box[31:16] |
        candidate_box[47:32] | candidate_box[63:48]) & GRID_MASK)==16'd0);
    // AREA_SHIFT=0 deliberately preserves the original high-bit truncation.
    // Only the specialized modes enforce an exact finite area encoding.
    wire candidate_area_aligned=(AREA_SHIFT==0) ||
        ((candidate_box[127:96] & (AREA_LOW_MASK|AREA_HIGH_MASK))==32'd0);
    wire candidate_sane=candidate_area_aligned && candidate_grid_aligned && (candidate_box[15:0]<candidate_box[47:32]) &&
        (candidate_box[31:16]<candidate_box[63:48]) &&
        (candidate_box[47:32]<=16'd1280) &&
        (candidate_box[63:48]<=16'd720) &&
        (candidate_box[79:64]>=16'd1) && (candidate_box[79:64]<=16'd9);

    // One registered geometry lane evaluates X, then Y. In DIMS the two
    // endpoint pairs are overwritten with width and doubled centre, so no
    // separate coordinate/dimension/sum banks are needed. The pair order and
    // exact integer geometry remain unchanged; only internal latency grows.
    reg [LANE_BITS-1:0] lane_c0,lane_c1,lane_t0,lane_t1;
    reg pair_axis_y,pair_eligible,pair_x_ok;
    reg [LANE_BITS-1:0] pair_delta,pair_max;
    reg pair_ratio_ok,pair_geometry_ok;
    reg [DISTANCE_BITS-1:0] pair_distance;

    reg update_is_new;
    // The geometry lane is dead during identity updates. Its low bits hold
    // the small class/confidence working word; coordinates/area are read
    // directly from the caller's still-stable candidate bank at APPLY.
    wire [3:0] update_class=lane_c0[3:0];
    wire [7:0] update_confidence=lane_c1[7:0];

    // A confirmation streak saturates at CONFIRM_LIMIT, never wraps.
    wire same_pending=!update_is_new &&
        meta_pending==update_class && meta_count!=0;
    wire [CONFIRM_BITS-1:0] next_pending_count=same_pending ?
        ((meta_count<CONFIRM_LIMIT)?meta_count+1'b1:CONFIRM_LIMIT) : {{(CONFIRM_BITS-1){1'b0}},1'b1};
    // A legal zero-score candidate is still a real observation. It can count
    // toward class consistency, but remains uncertain and keeps score zero.
    wire confirm_now=next_pending_count>=CONFIRM_LIMIT;
    // bad_age is at most HOLD_LIMIT while a confirmed class exists.
    wire may_hold=!update_is_new && meta_bad<HOLD_LIMIT;

    // Mutually exclusive accept/retain cases share their predicates across
    // every metadata field; no duplicated nested class/streak decisions.
    wire update_has_confirmed=!update_is_new && meta_confirmed!=0;
    wire update_accept=confirm_now ||
        (update_has_confirmed && update_class==meta_confirmed);
    wire update_hold=update_has_confirmed && may_hold;

    // Combinational next-word calculation. No second metadata cache is kept.
    // New allocation initializes every field regardless of old RAM contents.
    always @* begin
        next_confirmed=meta_confirmed;next_pending=meta_pending;next_count=meta_count;
        next_bad=meta_bad;next_lost=meta_lost;next_confidence=meta_confidence;
        update_visible=0;update_uncertain=0;
        if(state==S_UPDATE_APPLY)begin
            next_lost=0;next_confidence=update_confidence;
            // The existing pending nibble also preserves this frame's raw
            // class. No extra payload bank or protocol field is required.
            next_pending=update_class;next_count=next_pending_count;next_bad=0;
            next_confirmed=update_accept?update_class:
                (update_hold?meta_confirmed:4'd0);
            update_visible=1;
            update_uncertain=(update_confidence==0) || !update_accept;
            if(!update_accept && update_hold)next_bad=meta_bad+1'b1;
        end else if(state==S_UPDATE_SELECT && track_used[track_index] && !track_matched[track_index])begin
            // Missing observations never emit ghost geometry. The SELECT
            // preload state ensures this word belongs to the current track.
            next_pending=0;next_count=0;next_confidence=0;
            if(meta_lost>=LOST_LIMIT-1'b1)begin next_confirmed=0;next_lost=0;next_bad=0;end
            else next_lost=meta_lost+1'b1;
        end
    end


    // Every phase uses the same track read pointer. In particular emission
    // does not instantiate a second wide coordinate/area/class read port.
    wire [AREA_CODE_BITS-1:0] scanned_area=(state==S_ALLOC_SCAN)?
        candidate_box[96+AREA_SHIFT+:AREA_CODE_BITS]:payload_q[COORD_BITS+:AREA_CODE_BITS];
    wire area_better=!best_found || scanned_area>best_metric;
    // At the begin edge the caller may invalidate/overwrite raw input.
    // S_PRIMARY_INIT and every subsequent state use track metadata only.
    // emit_box is meaningful only with emit_valid; no invalid-period data mask.
    // Clear masks both serial strobes so a simultaneous abort cannot write
    // an old output into the caller's cleared result bank.
    assign emit_begin=busy && !clear && (state==S_PRIMARY_INIT);
    assign emit_valid=busy && !clear && ((state==S_OUTPUT_PRIMARY) ||
        (state==S_OUTPUT_OTHER && visible[track_index] && track_index!=primary_track));
    assign emit_slot=emit_valid ? ((state==S_OUTPUT_PRIMARY)?2'd0:output_count[1:0]) : 2'd0;
    assign emit_box={{(32-AREA_BITS){1'b0}},payload_q[COORD_BITS+:AREA_CODE_BITS],{AREA_SHIFT{1'b0}},8'd0,
        meta_confidence,12'd0,(meta_confirmed!=0 ? meta_confirmed : meta_pending),
        6'd0,payload_q[Y1_LSB+:Y_BITS],{COORD_SHIFT{1'b0}},
        5'd0,payload_q[X1_LSB+:X_BITS],{COORD_SHIFT{1'b0}},
        6'd0,payload_q[Y0_LSB+:Y_BITS],{COORD_SHIFT{1'b0}},
        5'd0,payload_q[0+:X_BITS],{COORD_SHIFT{1'b0}}};
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE;busy<=0;done<=0;output_count<=0;output_boxes<=0;uncertain<=0;
            count_limit<=0;candidate_valid<=0;candidate_matched<=0;track_matched<=0;visible<=0;track_used<=0;
            primary_valid<=0;primary_track<=0;candidate_index<=0;track_index<=0;
            best_candidate<=0;best_track<=0;best_found<=0;best_metric<=0;
            lane_c0<=0;lane_c1<=0;lane_t0<=0;lane_t1<=0;
            pair_axis_y<=0;pair_eligible<=0;pair_x_ok<=0;
            pair_delta<=0;pair_max<=0;pair_ratio_ok<=0;pair_geometry_ok<=0;pair_distance<=0;
            update_is_new<=0;ram_resume_state<=S_IDLE;ram_word<=0;
            write_uncertain<=0;age_expire<=0;
            for(i=0;i<4;i=i+1)candidate_for_track[i]<=0;
        end else if(clear) begin
            // Synchronous clear wins over start and every busy operation.
            // In-flight work is aborted without a done pulse. Caller may
            // submit a fresh snapshot after clear is released.
            state<=S_IDLE;busy<=0;done<=0;output_count<=0;output_boxes<=0;uncertain<=0;
            count_limit<=0;candidate_valid<=0;candidate_matched<=0;track_matched<=0;visible<=0;track_used<=0;
            primary_valid<=0;primary_track<=0;candidate_index<=0;track_index<=0;
            best_found<=0;ram_resume_state<=S_IDLE;ram_word<=0;
            write_uncertain<=0;age_expire<=0;
            // Only identity validity is cleared. Every new allocation writes
            // all payload and streak fields before any result can be emitted.
            // Invalid old bank words therefore need no synchronous clear mux.
        end else begin
            done<=0;
            case(state)
                S_IDLE:if(start) begin
                    busy<=1;output_count<=0;output_boxes<=0;
                    uncertain<=input_count>3'd4;
                    // Malformed counts fail closed as an empty observation,
                    // still ageing tracks exactly once; never wrap to0..3.
                    count_limit<=input_count>3'd4 ? 3'd0 : input_count;
                    candidate_valid<=0;candidate_matched<=0;track_matched<=0;visible<=0;
                    candidate_index<=0;track_index<=0;
                    state<=S_VALIDATE;
                end
                S_VALIDATE:begin
                    if({1'b0,candidate_index}<count_limit) begin
                        candidate_valid[candidate_index]<=candidate_sane;
                        if(!candidate_sane)uncertain<=1;
                    end
                    if(candidate_index==3)state<=S_MATCH_INIT;
                    else candidate_index<=candidate_index+1'b1;
                end
                S_MATCH_INIT:begin
                    best_found<=0;best_metric<=32'h1fff;
                    candidate_index<=0;track_index<=0;state<=S_PAIR_LOAD;
                end
                S_PAIR_LOAD:begin
                    pair_eligible<=track_used[track_index] && !track_matched[track_index] &&
                        candidate_valid[candidate_index] && !candidate_matched[candidate_index];
                    pair_axis_y<=0;
                    lane_c0<={1'b0,candidate_box[COORD_SHIFT+:X_BITS]};
                    lane_c1<={1'b0,candidate_box[32+COORD_SHIFT+:X_BITS]};
                    ram_word<=0;ram_resume_state<=S_PAIR_WAIT;state<=S_RAM_READ_ISSUE;
                end
                S_PAIR_WAIT:begin
                    // track_index is stable for a complete synchronous read.
                    lane_t0<={1'b0,payload_q[0+:X_BITS]};lane_t1<={1'b0,payload_q[X1_LSB+:X_BITS]};
                    state<=S_PAIR_DIMS;
                end
                S_PAIR_Y_LOAD:begin
                    pair_axis_y<=1;
                    lane_c0<={2'b00,candidate_box[16+COORD_SHIFT+:Y_BITS]};
                    lane_c1<={2'b00,candidate_box[48+COORD_SHIFT+:Y_BITS]};
                    lane_t0<={2'b00,payload_q[Y0_LSB+:Y_BITS]};lane_t1<={2'b00,payload_q[Y1_LSB+:Y_BITS]};
                    state<=S_PAIR_DIMS;
                end
                S_PAIR_DIMS:begin
                    lane_c0<=lane_c1-lane_c0;lane_t0<=lane_t1-lane_t0;
                    lane_c1<=lane_c0+lane_c1;lane_t1<=lane_t0+lane_t1;
                    state<=S_PAIR_DIFF;
                end
                S_PAIR_DIFF:begin
                    pair_delta<=lane_c1>=lane_t1 ? lane_c1-lane_t1 : lane_t1-lane_c1;
                    pair_max<=lane_c0>lane_t0 ? lane_c0 : lane_t0;
                    pair_ratio_ok<=({1'b0,lane_c0}<={lane_t0,1'b0}) &&
                        ({1'b0,lane_t0}<={lane_c0,1'b0});
                    state<=S_PAIR_GEOM;
                end
                S_PAIR_GEOM:begin
                    if(!pair_axis_y)begin
                        pair_x_ok<=pair_ratio_ok && pair_delta<=pair_max;
                        pair_distance<={1'b0,pair_delta};state<=S_PAIR_Y_LOAD;
                    end else begin
                        pair_geometry_ok<=pair_eligible && pair_x_ok &&
                            pair_ratio_ok && pair_delta<=pair_max;
                        pair_distance<=pair_distance+{1'b0,pair_delta};state<=S_PAIR_COMPARE;
                    end
                end
                S_PAIR_COMPARE:begin
                    // Equal distances preserve track-major/candidate-major
                    // search order; each candidate/track is consumed once.
                    if(pair_geometry_ok && (!best_found || pair_distance<best_metric[DISTANCE_BITS-1:0])) begin
                        best_found<=1;best_metric<={{(METRIC_BITS-DISTANCE_BITS){1'b0}},pair_distance};
                        best_track<=track_index;best_candidate<=candidate_index;
                    end
                    if(candidate_index==3) begin
                        candidate_index<=0;
                        if(track_index==3)state<=S_MATCH_COMMIT;
                        else begin track_index<=track_index+1'b1;state<=S_PAIR_LOAD;end
                    end else begin candidate_index<=candidate_index+1'b1;state<=S_PAIR_LOAD;end
                end
                S_MATCH_COMMIT:begin
                    if(best_found) begin
                        track_matched[best_track]<=1;candidate_matched[best_candidate]<=1;
                        candidate_for_track[best_track]<=best_candidate;
                        state<=S_MATCH_INIT;
                    end else begin track_index<=0;update_is_new<=0;state<=S_UPDATE_PRELOAD;end
                end
                S_UPDATE_PRELOAD:begin
                    ram_word<=0;ram_resume_state<=S_UPDATE_SELECT;state<=S_RAM_READ_ISSUE;
                end
                S_UPDATE_SELECT:begin
                    if(track_used[track_index] && track_matched[track_index]) begin
                        candidate_index<=candidate_for_track[track_index];state<=S_UPDATE_LOAD;
                    end else if(track_used[track_index])begin
                        // Cache the exact next age word, then commit validity
                        // only after its final narrow word has reached RAM.
                        age_expire<=meta_lost>=LOST_LIMIT-1'b1;
                        ram_word<=0;ram_resume_state<=S_UPDATE_AGE_COMMIT;state<=S_RAM_WRITE;
                    end else begin
                        if(track_index==3)state<=S_ALLOC_INIT;
                        else begin track_index<=track_index+1'b1;state<=S_UPDATE_PRELOAD;end
                    end
                end
                S_UPDATE_AGE_COMMIT:begin
                    if(age_expire)track_used[track_index]<=0;
                    else uncertain<=1;
                    if(track_index==3)state<=S_ALLOC_INIT;
                    else begin track_index<=track_index+1'b1;state<=S_UPDATE_PRELOAD;end
                end
                S_UPDATE_LOAD:begin
                    lane_c0<={{(LANE_BITS-4){1'b0}},candidate_box[67:64]};
                    lane_c1<={{(LANE_BITS-8){1'b0}},candidate_box[87:80]};
                    state<=S_UPDATE_APPLY;
                end
                S_UPDATE_APPLY:begin
                    // The unchanged combinational update builds one complete
                    // cache record on this edge. Inputs stay caller-owned.
                    write_uncertain<=update_uncertain;
                    ram_word<=0;ram_resume_state<=S_UPDATE_COMMIT;state<=S_RAM_WRITE;
                end
                S_UPDATE_COMMIT:begin
                    track_used[track_index]<=1;visible[track_index]<=1;
                    if(write_uncertain)uncertain<=1;
                    if(update_is_new)state<=S_ALLOC_INIT;
                    else if(track_index==3)state<=S_ALLOC_INIT;
                    else begin track_index<=track_index+1'b1;state<=S_UPDATE_PRELOAD;end
                end
                S_ALLOC_INIT:begin
                    best_found<=0;best_metric<=0;candidate_index<=0;state<=S_ALLOC_SCAN;
                end
                S_ALLOC_SCAN:begin
                    if(candidate_valid[candidate_index] && !candidate_matched[candidate_index] &&
                       area_better) begin
                        best_found<=1;best_metric<=scanned_area;best_candidate<=candidate_index;
                    end
                    if(candidate_index==3)state<=S_ALLOC_CHOOSE;
                    else candidate_index<=candidate_index+1'b1;
                end
                S_ALLOC_CHOOSE:begin
                    if(!best_found)state<=S_PRIMARY_INIT;
                    else if(&track_used)begin uncertain<=1;state<=S_PRIMARY_INIT;end
                    else begin track_index<=0;state<=S_ALLOC_FREE;end
                end
                S_ALLOC_FREE:begin
                    if(!track_used[track_index]) begin
                        candidate_index<=best_candidate;candidate_matched[best_candidate]<=1;
                        update_is_new<=1;state<=S_UPDATE_LOAD;
                    end else track_index<=track_index+1'b1;
                end
                S_PRIMARY_INIT:begin
                    best_found<=0;best_metric<=0;track_index<=0;state<=S_PRIMARY_SCAN;
                end
                S_PRIMARY_SCAN:begin
                    ram_word<=0;ram_resume_state<=S_PRIMARY_WAIT;state<=S_RAM_READ_ISSUE;
                end
                S_PRIMARY_WAIT:begin
                    if(visible[track_index] && area_better) begin
                        best_found<=1;best_metric<=scanned_area;best_candidate<=track_index;
                    end
                    if(track_index==3)state<=S_PRIMARY_CHOOSE;
                    else begin track_index<=track_index+1'b1;state<=S_PRIMARY_SCAN;end
                end
                S_PRIMARY_CHOOSE:begin
                    if(primary_valid && visible[primary_track]) begin
                        track_index<=primary_track;state<=S_EMIT_WAIT;
                    end else if(best_found) begin
                        primary_valid<=1;primary_track<=best_candidate;
                        track_index<=best_candidate;state<=S_EMIT_WAIT;
                    end else begin primary_valid<=0;state<=S_FINISH;end
                end
                S_EMIT_WAIT:begin
                    ram_word<=0;ram_resume_state<=S_OUTPUT_PRIMARY;state<=S_RAM_READ_ISSUE;
                end
                S_OUTPUT_PRIMARY:begin
                    output_boxes[127:0]<=emit_box;output_count<=1;
                    track_index<=0;state<=S_OUTPUT_OTHER_WAIT;
                end
                S_OUTPUT_OTHER_WAIT:begin
                    ram_word<=0;ram_resume_state<=S_OUTPUT_OTHER;state<=S_RAM_READ_ISSUE;
                end
                S_OUTPUT_OTHER:begin
                    if(visible[track_index] && track_index!=primary_track) begin
                        // Explicit fixed slices avoid a general variable
                        // shift/write network on the 512-bit result mailbox.
                        case(output_count[1:0])
                            0:output_boxes[127:0]<=emit_box;
                            1:output_boxes[255:128]<=emit_box;
                            2:output_boxes[383:256]<=emit_box;
                            3:output_boxes[511:384]<=emit_box;
                        endcase
                        output_count<=output_count+1'b1;
                    end
                    if(track_index==3)state<=S_FINISH;
                    else begin track_index<=track_index+1'b1;state<=S_OUTPUT_OTHER_WAIT;end
                end
                // ISSUE guarantees a full clock at each address. CAPTURE
                // consumes the registered synchronous RAM output, never a
                // combinational read. Track/index/candidate ownership stalls.
                S_RAM_READ_ISSUE:state<=S_RAM_READ_CAPTURE;
                S_RAM_READ_CAPTURE:begin
                    if(ram_word==TABLE_WORDS-1)state<=ram_resume_state;
                    else begin ram_word<=ram_word+1'b1;state<=S_RAM_READ_ISSUE;end
                end
                S_RAM_WRITE:begin
                    if(ram_word==TABLE_WORDS-1)state<=ram_resume_state;
                    else ram_word<=ram_word+1'b1;
                end
                S_FINISH:begin busy<=0;done<=1;state<=S_IDLE;end
                default:begin
                    // Illegal FSM state fails closed. Synchronous clear/reset
                    // is the normal route to remove all retained identities.
                    busy<=0;done<=0;output_count<=0;output_boxes<=0;uncertain<=1;
                    track_used<=0;visible<=0;primary_valid<=0;state<=S_IDLE;
                end
            endcase
        end
    end
endmodule
