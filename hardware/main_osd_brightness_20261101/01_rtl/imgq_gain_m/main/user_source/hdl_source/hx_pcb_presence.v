// Presence/stability only: all semantic classification remains on the peer.
// 40x23 samples for 720p, background+previous luma in one 1024x16 BRAM.
module hx_pcb_presence #(
    parameter integer FRAME_W=1280,FRAME_H=720,
    parameter integer PRESENT_MIN=12,STABLE_MAX=4,CONFIRM_FRAMES=30,
    parameter integer BACKGROUND_TH=24,STABLE_TH=8
)(
    input wire I_clk,I_rst_n,I_teach,
    input wire [95:0] I_rgb,input wire I_valid,I_user,I_last,I_frame_error,
    input wire I_cfg_apply,
    input wire [10:0] I_roi_x0,I_roi_x1,input wire [9:0] I_roi_y0,I_roi_y1,
    input wire [7:0] I_background_th,I_stable_th,I_stable_frames,I_clear_frames,
    input wire [15:0] I_present_min,input wire [7:0] I_stable_max,
    output reg O_background_valid,O_present,O_stable,O_trigger
);
    localparam GROUPS=FRAME_W/4;
    reg [15:0] history[0:1023] /* synthesis syn_ramstyle="block_ram" */;
    reg [15:0] history_q;
    reg [8:0] x;
    reg [9:0] y,index,sample_index;
    reg active,teach_pending,teaching,bad,armed;
    reg [9:0] changed_background,changed_previous;
    reg [7:0] stable_frames,empty_frames;
    reg [10:0] roi_x0,roi_x1;
    reg [9:0] roi_y0,roi_y1;
    reg [7:0] background_th,stable_th,stable_needed,clear_needed,stable_max;
    reg [15:0] present_min;
    reg roi_sample_d;
    reg sample_d,teach_d;
    reg [7:0] luma_d;
    wire [8:0] cx=I_user?9'd0:x;
    wire [9:0] cy=I_user?10'd0:y;
    wire sample=I_valid&&(active||I_user)&&(cx[2:0]==0)&&(cy[4:0]==0);
    wire [9:0] sample_addr=I_user?10'd0:index;
    wire teach_next=teach_pending||I_teach;
    wire [10:0] px={cx,2'b00};
    wire sample_inside=(px>=roi_x0)&&(px<roi_x1)&&(cy>=roi_y0)&&(cy<roi_y1);
    wire [9:0] luma_sum={2'b0,I_rgb[95:88]}+{1'b0,I_rgb[87:80],1'b0}+{2'b0,I_rgb[79:72]};
    wire [7:0] bg_diff=(luma_d>history_q[15:8])?luma_d-history_q[15:8]:history_q[15:8]-luma_d;
    wire [7:0] prev_diff=(luma_d>history_q[7:0])?luma_d-history_q[7:0]:history_q[7:0]-luma_d;
    // No array reset: teaching establishes every valid entry. Both RAM
    // accesses are clocked, separated by >=8 camera beats during sampling.
    always @(posedge I_clk) begin
      if(sample) history_q<=history[sample_addr];
      if(sample_d) history[sample_index]<={teach_d?luma_d:history_q[15:8],luma_d};
    end
    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n) begin
        x<=0;y<=0;index<=0;sample_index<=0;active<=0;teach_pending<=0;teaching<=0;
        bad<=0;armed<=1;changed_background<=0;changed_previous<=0;
        stable_frames<=0;empty_frames<=0;sample_d<=0;teach_d<=0;luma_d<=0;
        roi_x0<=0;roi_y0<=0;roi_x1<=FRAME_W;roi_y1<=FRAME_H;
        background_th<=BACKGROUND_TH;stable_th<=STABLE_TH;
        stable_needed<=CONFIRM_FRAMES;clear_needed<=CONFIRM_FRAMES;
        present_min<=PRESENT_MIN;stable_max<=STABLE_MAX;roi_sample_d<=0;
        O_background_valid<=0;O_present<=0;O_stable<=0;O_trigger<=0;
      end else begin
        O_trigger<=0;sample_d<=sample;
        if(I_cfg_apply) begin
          roi_x0<=I_roi_x0;roi_y0<=I_roi_y0;roi_x1<=I_roi_x1;roi_y1<=I_roi_y1;
          background_th<=I_background_th;stable_th<=I_stable_th;
          stable_needed<=(I_stable_frames==0)?8'd1:I_stable_frames;
          clear_needed<=(I_clear_frames==0)?8'd1:I_clear_frames;
          present_min<=I_present_min;stable_max<=I_stable_max;
          stable_frames<=0;empty_frames<=0;O_stable<=0;
        end
        if(sample) begin
          sample_index<=sample_addr;luma_d<=luma_sum[9:2];
          teach_d<=I_user?teach_next:teaching;index<=sample_addr+1'b1;
          roi_sample_d<=I_cfg_apply?((px>=I_roi_x0)&&(px<I_roi_x1)&&(cy>=I_roi_y0)&&(cy<I_roi_y1)):sample_inside;
        end
        if(sample_d&&roi_sample_d&&!teach_d&&O_background_valid) begin
          if(bg_diff>=background_th) changed_background<=changed_background+1'b1;
          if(prev_diff>=stable_th) changed_previous<=changed_previous+1'b1;
        end
        if(I_valid) begin
          if(I_user) begin
            // Keep the request pending until a complete, good teaching
            // frame finishes. A malformed/interrupted frame retries at SOF.
            active<=1;teaching<=teach_next;
            bad<=0;changed_background<=0;changed_previous<=0;
            if(active) begin stable_frames<=0;O_stable<=0;end
          end
          if(active||I_user) begin
            if(I_frame_error || (I_last!=(cx==GROUPS-1))) bad<=1;
            if(I_last) begin
              x<=0;y<=cy+1'b1;
              if(cy==FRAME_H-1) begin
                active<=0;y<=0;
                if(bad||I_frame_error||(cx!=GROUPS-1)) begin
                  stable_frames<=0;empty_frames<=0;O_stable<=0;
                end else if(teaching) begin
                  O_background_valid<=1;O_present<=0;O_stable<=0;
                  stable_frames<=0;empty_frames<=0;armed<=1;teach_pending<=0;
                end else if(O_background_valid) begin
                  O_present<=changed_background>=present_min;
                  if(changed_background<present_min) begin
                    stable_frames<=0;O_stable<=0;
                    if(empty_frames<clear_needed) empty_frames<=empty_frames+1'b1;
                    if(empty_frames>=clear_needed-1) armed<=1;
                  end else begin
                    empty_frames<=0;
                    if(changed_previous<=stable_max) begin
                      if(stable_frames<stable_needed) stable_frames<=stable_frames+1'b1;
                      if(stable_frames>=stable_needed-1) begin
                        O_stable<=1;
                        if(armed) begin O_trigger<=1;armed<=0;end
                      end
                    end else begin stable_frames<=0;O_stable<=0;end
                  end
                end
              end
            end else x<=cx+1'b1;
          end
        end
        // A new request wins over an old frame's completion, including the
        // final pixel of a previous teaching frame. Mid-frame requests wait
        // for the next SOF; a request exactly at SOF may teach that frame.
        if(I_teach) begin
          teach_pending<=1;teaching<=I_valid&&I_user;
          O_background_valid<=0;O_present<=0;O_stable<=0;O_trigger<=0;
          stable_frames<=0;empty_frames<=0;armed<=1;
          changed_background<=0;changed_previous<=0;
        end
      end
    end
endmodule
