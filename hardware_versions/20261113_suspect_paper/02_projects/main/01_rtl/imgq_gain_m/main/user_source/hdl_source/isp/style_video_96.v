// Display-only branch. The input is the non-stallable post-AWB camera stream.
// Recognition continues to tap the original post-AWB data in the parent.
module style_video_96 #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer CART_DENOISE_ENABLE=1,
    parameter integer CART_EDGE_THRESHOLD=48,
    // CART emits a final replicated row after the last camera row.  The
    // camera/AWB stream cannot be backpressured, so the queue must hold that
    // whole row plus the normal pipeline margin.  The previous 64-entry
    // queue was sufficient for the small RTL tests but overflowed on the
    // 1280-wide live stream and caused the display to restart mid-frame.
    parameter integer CART_FIFO_DEPTH=512
)(
    input wire I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,
    input wire [95:0] I_tdata,
    input wire [4:0] I_style_mode,
    input wire [7:0] I_den_strength,
    input wire O_tready,
    output wire [95:0] O_tdata,
    output wire O_tvalid,O_tuser,O_tlast,O_overflow
);
      wire [95:0] den_data;
      wire den_valid,den_user,den_last,den_ready;
      wire style_ready;
      wire [102:0] queued;
      wire queued_valid,queue_ready;
      wire [7:0] cart_strength = (I_den_strength < 8'd32) ? 8'd32 : I_den_strength;
      reg [4:0] capture_mode,mode_d0,mode_d1;
      reg sof_pending;
      wire [4:0] input_mode=I_tuser?I_style_mode:capture_mode;
      always @(posedge I_clk or negedge I_rst_n)begin
          if(!I_rst_n)begin capture_mode<=0;sof_pending<=0;end
          else begin
              if(I_tuser)begin capture_mode<=I_style_mode;sof_pending<=1;end
              if(I_tvalid && (I_tuser||sof_pending))sof_pending<=0;
          end
      end
      // The production ISP output is permanently ready. Camera vertical
      // blanking provides the last-row drain (WIDTH/4 + pipeline cycles).
      // A short distributed FIFO absorbs transient simulation/downstream
      // stalls without dedicating an ERAM to the video queue.
      // The camera side cannot be backpressured.  Keep one complete 320-group
      // row plus margin while CART drains its replicated bottom row.  The
      // Map this queue to ERAM rather than distributed RAM.  A full row is
      // 320 groups at 1280 pixels; the remaining entries absorb the live
      // stream while CART drains its replicated bottom row.
      style_input_fifo #(.DEPTH(CART_FIFO_DEPTH),.RAM_STYLE("bram")) u_style_queue(
          .clk(I_clk),.rst_n(I_rst_n),
          .in_data({input_mode,(I_tuser||sof_pending),I_tlast,I_tdata}),.in_valid(I_tvalid),
          .out_ready(queue_ready),.out_data(queued),.out_valid(queued_valid),.overflow(O_overflow));
      always @(posedge I_clk or negedge I_rst_n)begin
          if(!I_rst_n)begin mode_d0<=0;mode_d1<=0;end
          else if(style_ready)begin mode_d0<=queued[102:98];mode_d1<=mode_d0;end
      end
      // Denoise only CART. Strength zero is bit-exact passthrough for 0..17.
      generate if (CART_DENOISE_ENABLE != 0) begin : g_cart_denoise
        denoise_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_cart_denoise(
            .I_clk(I_clk),.I_rst_n(I_rst_n),
            .I_tdata(queued[95:0]),.I_tvalid(queued_valid),.I_tuser(queued_valid&&queued[97]),.I_tlast(queued[96]),
            .I_strength(queued[102:98]==18?cart_strength:8'd0),
            .O_tready(style_ready),.I_tready(queue_ready),
            .O_tdata(den_data),.O_tvalid(den_valid),.O_tuser(den_user),.O_tlast(den_last));
      end else begin : g_cart_no_denoise
        assign queue_ready=style_ready;
        assign den_data=queued[95:0];
        assign den_valid=queued_valid;
        assign den_user=queued_valid&&queued[97];
        assign den_last=queued[96];
      end endgenerate
      style_transfer_96 #(
          .IMG_WIDTH  (IMG_WIDTH),
          .IMG_HEIGHT (IMG_HEIGHT),
          .CART_EDGE_THRESHOLD(CART_EDGE_THRESHOLD),
          .NUM_STYLES (19),
          .SIMPLE_BYPASS(1'b0),
          .FIXED_STYLE_MODE(-1)
      ) u_style_transfer_96 (
          .I_clk        (I_clk),
          .I_rst_n      (I_rst_n),
          .I_style_mode (mode_d1),
          .I_tlast      (den_last),
          .I_tuser      (den_user),
          .I_tdata      (den_data),
          .I_tvalid      (den_valid),
          .O_tready     (O_tready),
          .I_tready     (style_ready),
          .O_tlast      (O_tlast),
          .O_tuser      (O_tuser),
          .O_tdata      (O_tdata),
          .O_tvalid     (O_tvalid)
      );
endmodule
