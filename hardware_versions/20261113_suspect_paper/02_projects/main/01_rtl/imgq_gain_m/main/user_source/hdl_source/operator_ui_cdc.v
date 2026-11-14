// Type21 operator metadata: a compact, one-outstanding bundled-data mailbox.
// HDMI omits task/page hexadecimal IDs. Wire width stays153 for compatibility;
// their48 positions are zero, allowing both mailbox banks to synthesize smaller.
// Source data is held until the pixel domain commits it at vertical blanking.
// A periodic fresh Type21 update is required after either endpoint resets.
module operator_ui_cdc(
    input wire src_clk,src_rst_n,src_online,src_valid,src_toggle,
    input wire [1:0] src_mode,
    input wire [383:0] src_data,
    input wire px_clk,px_rst_n,frame_start,
    input wire [1:0] px_mode,
    output wire valid,
    output wire [152:0] data
);
    reg [1:0] source_mode_d;
    reg source_epoch_reset_n;
    always @(posedge src_clk or negedge src_rst_n)
        if(!src_rst_n)begin source_mode_d<=0;source_epoch_reset_n<=0;end
        else begin
            source_mode_d<=src_mode;
            source_epoch_reset_n<=(source_mode_d==src_mode);
        end
    // Assertion discards even an outstanding mailbox. Separate mode history
    // is deliberately outside this reset, so a mode change cannot deadlock.
    wire mailbox_rst_n=src_rst_n&&px_rst_n&&src_online&&src_valid&&
                       source_epoch_reset_n;
    wire source_reset_n,pixel_reset_n;
    reset_sync u_source_reset(.I_clk(src_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(source_reset_n));
    reset_sync u_pixel_reset(.I_clk(px_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(pixel_reset_n));
    reg req,ack,armed,seen;
    (* ASYNC_REG="TRUE" *) reg ack_s1,ack_s2,req_s1,req_s2;
    // Two physical slots, opposite request epochs. BRAM read output is the
    // displayed register bank: read only at a VSYNC publication, never while
    // active pixels consume it. Memory has no reset; published gates every
    // read until a fresh request has crossed both synchronizer stages.
    (* ram_style="bram" *) reg [155:0] held_bank[0:1];
    reg [155:0] staged;
    reg published;
    reg capture_wait,pending;
    wire kind_allowed=(src_data[50:48]==0)||(src_data[50:48]==4)||
        ((src_data[50:48]==1)&&(src_mode==0))||
        ((src_data[50:48]==2)&&(src_mode==1))||
        ((src_data[50:48]==3)&&(src_mode==2));
    wire [152:0] compact={src_data[362:360],src_data[359:352],
        16'd0,src_data[254:240],src_data[221:208],
        src_data[203:192],src_data[185:176],src_data[170:160],
        src_data[155:152],src_data[145:144],src_data[143:136],
        src_data[131:128],32'd0,
        src_data[58:56],src_data[50:48],src_data[47:40]};
    wire event_now=armed&&(src_toggle!=seen);
    always @(posedge src_clk)begin
        if(source_reset_n&&req==ack_s2&&event_now)
            held_bank[~req]<={kind_allowed,src_mode,compact};
    end
    // Both ports are clocked, with independent source/pixel clocks. The read
    // uses synchronized epoch, and occurs only after capture_wait and pending.
    always @(posedge px_clk)begin
        if(pixel_reset_n&&frame_start&&pending)
            staged<=held_bank[req_s2];
    end
    always @(posedge src_clk or negedge source_reset_n) begin
        if(!source_reset_n) begin
            req<=0;ack_s1<=0;ack_s2<=0;armed<=0;seen<=0;
        end else begin
            ack_s1<=ack;ack_s2<=ack_s1;armed<=1;seen<=src_toggle;
            // r_body is a short-lived packet bus. Copy only on the actual
            // Type21 event, never resample it later via a dirty indication.
            // If occupied, drop this status; the 250 ms refresh retries it.
            if(req==ack_s2&&event_now)begin
                req<=~req;
            end
        end
    end
    always @(posedge px_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n)begin
            req_s1<=0;req_s2<=0;ack<=0;capture_wait<=0;pending<=0;published<=0;
        end else begin
            req_s1<=req;req_s2<=req_s1;
            if(req_s2!=ack&&!capture_wait&&!pending)capture_wait<=1;
            if(capture_wait)begin pending<=1;capture_wait<=0;end
            if(frame_start)begin
                if(staged[154:153]!=px_mode)published<=0;
                if(pending)begin
                    published<=1;
                    ack<=req_s2;pending<=0;
                end
            end
        end
    end
    assign valid=pixel_reset_n&&published&&staged[155]&&(staged[154:153]==px_mode);
    // Memory output may be unknown before first publication or stale after reset.
    // Consumers must use valid, which is reset and mode-checked independently.
    assign data=staged[152:0];
endmodule
