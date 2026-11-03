// Dual-bank 720p ROI sampler: capture and 32x32 output run concurrently.
module roi_sampler_720p #(parameter integer FRAME_W=1280,FRAME_H=720,ROI_W=32,ROI_H=32)(
 input wire I_clk,I_rst_n,I_enable,I_valid,I_tuser,I_tlast,input wire [95:0] I_tdata,
 input wire I_target_valid,input wire [10:0] I_x0,I_x1,input wire [9:0] I_y0,I_y1,
 output reg O_roi_valid,O_roi_start,O_roi_last,output reg [23:0] O_roi_data,
 output reg O_frame_toggle,O_busy);
 localparam integer N=ROI_W*ROI_H;
 reg [23:0] mem0[0:N-1],mem1[0:N-1]; reg cap_bank,out_bank,out_active;
 reg [8:0] xb; reg [9:0] yl; reg [5:0] sc,sr,oc,orr;
 reg [10:0] bx0,bx1,bw; reg [9:0] by0,by1,bh; reg target_latched;
 reg [10:0] sx; reg [9:0] sy; reg [23:0] pix; reg [5:0] cw,rw; integer p,idx;
 wire frame_target=(I_tuser&&I_valid)?(I_enable&&I_target_valid):target_latched;
 wire [10:0] fx0=(I_tuser&&I_valid)?I_x0:bx0, fx1=(I_tuser&&I_valid)?I_x1:bx1;
 wire [9:0] fy0=(I_tuser&&I_valid)?I_y0:by0, fy1=(I_tuser&&I_valid)?I_y1:by1;
 wire [10:0] fw=(I_tuser&&I_valid)?((I_x1>=I_x0)?I_x1-I_x0+1:11'd1):bw;
 wire [9:0] fh=(I_tuser&&I_valid)?((I_y1>=I_y0)?I_y1-I_y0+1:10'd1):bh;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   xb<=0;yl<=0;sc<=0;sr<=0;oc<=0;orr<=0;bx0<=0;bx1<=0;by0<=0;by1<=0;bw<=1;bh<=1;target_latched<=0;
   cap_bank<=0;out_bank<=1;out_active<=0;O_roi_valid<=0;O_roi_start<=0;O_roi_last<=0;O_roi_data<=0;O_frame_toggle<=0;O_busy<=0;
  end else begin
   O_roi_valid<=0;O_roi_start<=0;O_roi_last<=0;O_busy<=out_active;
   if(I_valid&&I_tuser) begin bx0<=I_x0;bx1<=I_x1;by0<=I_y0;by1<=I_y1;bw<=fw;bh<=fh;target_latched<=I_enable&&I_target_valid;sc<=0;sr<=0;xb<=0;yl<=0;end
   if(I_valid) begin
    cw=sc;rw=sr;
    for(p=0;p<4;p=p+1) begin
     sx=xb*4+p;sy=yl;pix=I_tdata[p*24 +: 24];
     if(frame_target&&(cw<ROI_W)&&(rw<ROI_H)&&(sx>=fx0)&&(sx<=fx1)&&(sy>=fy0)&&(sy<=fy1)&&(sx==(fx0+((cw*fw)>>5)))&&(sy==(fy0+((rw*fh)>>5)))) begin
      idx=rw*ROI_W+cw;if(!cap_bank) mem0[idx]<=pix;else mem1[idx]<=pix;
      if(cw==ROI_W-1) begin cw=0;rw=rw+1;end else cw=cw+1;
     end
    end
    sc<=cw;sr<=rw;
    if(I_tlast) begin xb<=0;if(yl==FRAME_H-1) begin yl<=0;
      if(frame_target&&(cw==0)&&(rw==ROI_H)) begin out_bank<=cap_bank;cap_bank<=~cap_bank;out_active<=1;oc<=0;orr<=0;end
     end else yl<=yl+1;end else xb<=xb+1;
   end
   if(out_active) begin
    O_roi_valid<=1;O_roi_start<=(oc==0&&orr==0);O_roi_last<=(oc==ROI_W-1&&orr==ROI_H-1);
    if(!out_bank) O_roi_data<=mem0[orr*ROI_W+oc]; else O_roi_data<=mem1[orr*ROI_W+oc];
    if(oc==ROI_W-1) begin oc<=0;if(orr==ROI_H-1) begin orr<=0;out_active<=0;O_frame_toggle<=~O_frame_toggle;end else orr<=orr+1;end else oc<=oc+1;
   end
  end
 end
endmodule