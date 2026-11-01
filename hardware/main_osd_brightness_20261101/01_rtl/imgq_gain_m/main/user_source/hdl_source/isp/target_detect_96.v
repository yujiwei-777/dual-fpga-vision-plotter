// Colour target detector with frame-synchronous tracking.
module target_detect_96 #(
 // More permissive 720p profile for dim and partially saturated targets.
 // Geometric and fill-rate checks below remain enabled to reject noise.
 parameter [7:0] DOM_MIN=8'd48,
 parameter [7:0] DOM_OTH=8'd40,
 parameter [7:0] DOM_DELTA=8'd16,
 parameter [23:0] MIN_AREA=24'd180,
 // A colour cloud spanning most of the image is almost always background
 // leakage.  Keep the detector focused on compact, reasonably sized objects.
 parameter [10:0] MAX_BOX_W=11'd900,
 parameter [9:0]  MAX_BOX_H=10'd680
)(
 input wire I_clk,input wire I_rst_n,input wire I_en,input wire I_vld,
 input wire I_tuser,input wire I_tlast,input wire [95:0] I_tdata,
 output reg O_valid,output reg [10:0] O_x_min,output reg [9:0] O_y_min,
 output reg [10:0] O_x_max,output reg [9:0] O_y_max,output reg [10:0] O_cx,
 output reg [9:0] O_cy,output reg [23:0] O_area,output reg [1:0] O_color,
 output reg [1:0] O_shape,output reg O_toggle
);
 wire [7:0] r0=I_tdata[23:16],g0=I_tdata[15:8],b0=I_tdata[7:0];
 wire [7:0] r1=I_tdata[47:40],g1=I_tdata[39:32],b1=I_tdata[31:24];
 wire [7:0] r2=I_tdata[71:64],g2=I_tdata[63:56],b2=I_tdata[55:48];
 wire [7:0] r3=I_tdata[95:88],g3=I_tdata[87:80],b3=I_tdata[79:72];
 wire m0r=({1'b0,r0}>={1'b0,DOM_MIN})&&({1'b0,r0}>={1'b0,g0}+{1'b0,DOM_DELTA})&&({1'b0,r0}>={1'b0,b0}+{1'b0,DOM_DELTA});
 wire m1r=({1'b0,r1}>={1'b0,DOM_MIN})&&({1'b0,r1}>={1'b0,g1}+{1'b0,DOM_DELTA})&&({1'b0,r1}>={1'b0,b1}+{1'b0,DOM_DELTA});
 wire m2r=({1'b0,r2}>={1'b0,DOM_MIN})&&({1'b0,r2}>={1'b0,g2}+{1'b0,DOM_DELTA})&&({1'b0,r2}>={1'b0,b2}+{1'b0,DOM_DELTA});
 wire m3r=({1'b0,r3}>={1'b0,DOM_MIN})&&({1'b0,r3}>={1'b0,g3}+{1'b0,DOM_DELTA})&&({1'b0,r3}>={1'b0,b3}+{1'b0,DOM_DELTA});
 wire m0g=({1'b0,g0}>={1'b0,DOM_MIN})&&({1'b0,g0}>={1'b0,r0}+{1'b0,DOM_DELTA})&&({1'b0,g0}>={1'b0,b0}+{1'b0,DOM_DELTA});
 wire m1g=({1'b0,g1}>={1'b0,DOM_MIN})&&({1'b0,g1}>={1'b0,r1}+{1'b0,DOM_DELTA})&&({1'b0,g1}>={1'b0,b1}+{1'b0,DOM_DELTA});
 wire m2g=({1'b0,g2}>={1'b0,DOM_MIN})&&({1'b0,g2}>={1'b0,r2}+{1'b0,DOM_DELTA})&&({1'b0,g2}>={1'b0,b2}+{1'b0,DOM_DELTA});
 wire m3g=({1'b0,g3}>={1'b0,DOM_MIN})&&({1'b0,g3}>={1'b0,r3}+{1'b0,DOM_DELTA})&&({1'b0,g3}>={1'b0,b3}+{1'b0,DOM_DELTA});
 wire m0b=({1'b0,b0}>={1'b0,DOM_MIN})&&({1'b0,b0}>={1'b0,r0}+{1'b0,DOM_DELTA})&&({1'b0,b0}>={1'b0,g0}+{1'b0,DOM_DELTA});
 wire m1b=({1'b0,b1}>={1'b0,DOM_MIN})&&({1'b0,b1}>={1'b0,r1}+{1'b0,DOM_DELTA})&&({1'b0,b1}>={1'b0,g1}+{1'b0,DOM_DELTA});
 wire m2b=({1'b0,b2}>={1'b0,DOM_MIN})&&({1'b0,b2}>={1'b0,r2}+{1'b0,DOM_DELTA})&&({1'b0,b2}>={1'b0,g2}+{1'b0,DOM_DELTA});
 wire m3b=({1'b0,b3}>={1'b0,DOM_MIN})&&({1'b0,b3}>={1'b0,r3}+{1'b0,DOM_DELTA})&&({1'b0,b3}>={1'b0,g3}+{1'b0,DOM_DELTA});
 wire any_r=m0r|m1r|m2r|m3r, any_g=m0g|m1g|m2g|m3g, any_b=m0b|m1b|m2b|m3b;
 wire [2:0] cnt_r={2'd0,m0r}+{2'd0,m1r}+{2'd0,m2r}+{2'd0,m3r};
 wire [2:0] cnt_g={2'd0,m0g}+{2'd0,m1g}+{2'd0,m2g}+{2'd0,m3g};
 wire [2:0] cnt_b={2'd0,m0b}+{2'd0,m1b}+{2'd0,m2b}+{2'd0,m3b};
 reg [8:0] S_xb; reg [9:0] S_y;
 wire [10:0] S_px0={S_xb,2'b00}; wire [10:0] S_px1=S_px0+11'd3;
 reg [10:0] R_xmin,R_xmax,G_xmin,G_xmax,B_xmin,B_xmax;
 reg [9:0] R_ymin,R_ymax,G_ymin,G_ymax,B_ymin,B_ymax;
 reg [23:0] R_area,G_area,B_area;
 wire [23:0] area_max=(R_area>=B_area&&R_area>=G_area)?R_area:((B_area>=G_area)?B_area:G_area);
 wire win_r=(area_max==R_area); wire win_b=!win_r&&(area_max==B_area);
 wire [10:0] w_xmin=win_r?R_xmin:(win_b?B_xmin:G_xmin), w_xmax=win_r?R_xmax:(win_b?B_xmax:G_xmax);
 wire [9:0] w_ymin=win_r?R_ymin:(win_b?B_ymin:G_ymin), w_ymax=win_r?R_ymax:(win_b?B_ymax:G_ymax);
 wire [12:0] w_bw=(w_xmax>=w_xmin)?({2'd0,w_xmax}-{2'd0,w_xmin}+13'd1):13'd0;
 wire [11:0] w_bh=(w_ymax>=w_ymin)?({2'd0,w_ymax}-{2'd0,w_ymin}+12'd1):12'd0;
 wire [24:0] w_box_area=w_bw*w_bh;
 // Reject very elongated regions and loose colour clouds.  In addition to the
 // aspect ratio check, cap the candidate dimensions so a few scattered colour
 // pixels cannot create a box covering most of the video frame.  The camera
 // stream is often dark while AE settles, so use a one-eighth occupancy gate;
 // this keeps a real coloured object detectable even when its edge is noisy.
 // Permit moderately elongated signs/objects while rejecting scanline noise.
 wire w_aspect_ok=(w_bw!=0)&&(w_bh!=0)&&(w_bw<=(w_bh*4))&&(w_bh<=(w_bw*4));
 wire w_size_ok=(w_bw<=MAX_BOX_W)&&(w_bh<=MAX_BOX_H);
 // A 1/16 occupancy floor accepts antialiased/partially occluded targets;
 // the aspect and maximum-box checks still reject broad colour leakage.
 wire [26:0] area_x8 = ({3'b000,area_max}<<3);
 wire [28:0] area_x16=({5'b00000,area_max}<<4);
 wire w_fill_ok=(area_x16>={4'b0,w_box_area});
 wire w_candidate=I_en&&(area_max>=MIN_AREA)&&w_aspect_ok&&w_size_ok&&w_fill_ok;
 // The local classifier is deliberately rule based.  Use the measured
 // occupancy of the candidate box as a compact geometric proxy:
 //   TRI  (1): sparse/pointed silhouette, 1/8..4/8 fill;
 //   CIRC (2): rounded silhouette, 4/8..7/8 fill;
 //   SQR  (3): dense, filled silhouette, >=7/8 fill.
 // The detector already enforces the 1/8 lower bound, so this classification
 // is tolerant of antialiasing and dim edges without a CNN or frame buffer.
 wire [26:0] box_area_ext={2'b0,w_box_area};
 wire w_shape_sqr  = area_x8 >= (box_area_ext + (box_area_ext<<1) +
                                  (box_area_ext<<2)); // 7/8
 wire w_shape_circ = area_x8 >= (box_area_ext<<2);    // 4/8
 wire [1:0] w_shape=w_shape_sqr?2'd3:(w_shape_circ?2'd2:2'd1);
 wire [1:0] w_color=win_r?2'd1:(win_b?2'd3:2'd2);
 reg [1:0] miss_count; reg [10:0] tr_xmin,tr_xmax,tr_cx; reg [9:0] tr_ymin,tr_ymax,tr_cy;
 wire [10:0] cand_cx=(w_xmin+w_xmax)>>1; wire [9:0] cand_cy=(w_ymin+w_ymax)>>1;
 // Signed-safe one-quarter step updates (coordinates are unsigned).
 wire signed [12:0] dxmin=$signed({1'b0,w_xmin})-$signed({1'b0,tr_xmin});
 wire signed [12:0] dxmax=$signed({1'b0,w_xmax})-$signed({1'b0,tr_xmax});
 wire signed [11:0] dymin=$signed({1'b0,w_ymin})-$signed({1'b0,tr_ymin});
 wire signed [11:0] dymax=$signed({1'b0,w_ymax})-$signed({1'b0,tr_ymax});
 wire signed [12:0] dcx=$signed({1'b0,cand_cx})-$signed({1'b0,tr_cx});
 wire signed [11:0] dcy=$signed({1'b0,cand_cy})-$signed({1'b0,tr_cy});
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   S_xb<=0;S_y<=0;R_xmin<=11'h7ff;R_xmax<=0;R_ymin<=10'h3ff;R_ymax<=0;R_area<=0;
   G_xmin<=11'h7ff;G_xmax<=0;G_ymin<=10'h3ff;G_ymax<=0;G_area<=0;B_xmin<=11'h7ff;B_xmax<=0;B_ymin<=10'h3ff;B_ymax<=0;B_area<=0;
   O_valid<=0;O_x_min<=0;O_y_min<=0;O_x_max<=0;O_y_max<=0;O_cx<=0;O_cy<=0;O_area<=0;O_color<=0;O_shape<=0;O_toggle<=0;
   miss_count<=0;tr_xmin<=0;tr_xmax<=0;tr_ymin<=0;tr_ymax<=0;tr_cx<=0;tr_cy<=0;
  // tuser is the frame delimiter and must be consumed even if the upstream
  // formatter inserts a one-cycle valid bubble around the marker.  The
  // previous I_vld&&I_tuser gate could miss that delimiter, leaving the
  // accumulated colour region uncommitted forever (TGT:NONE and no box).
  // Pixel accumulation remains gated by I_vld in the branch below.
  end else if(I_tuser) begin
   O_toggle<=~O_toggle; O_area<=area_max; O_color<=w_color; O_shape<=w_candidate?w_shape:2'd0;
   if(w_candidate) begin
    miss_count<=0;
    if(!O_valid) begin
      tr_xmin<=w_xmin;tr_xmax<=w_xmax;tr_ymin<=w_ymin;tr_ymax<=w_ymax;tr_cx<=cand_cx;tr_cy<=cand_cy;
      O_x_min<=w_xmin; O_x_max<=w_xmax; O_y_min<=w_ymin; O_y_max<=w_ymax; O_cx<=cand_cx; O_cy<=cand_cy;
    end else begin
      tr_xmin<=tr_xmin+(dxmin>>>2);tr_xmax<=tr_xmax+(dxmax>>>2);tr_ymin<=tr_ymin+(dymin>>>2);tr_ymax<=tr_ymax+(dymax>>>2);tr_cx<=tr_cx+(dcx>>>2);tr_cy<=tr_cy+(dcy>>>2);
      O_x_min<=tr_xmin+(dxmin>>>2); O_x_max<=tr_xmax+(dxmax>>>2); O_y_min<=tr_ymin+(dymin>>>2); O_y_max<=tr_ymax+(dymax>>>2); O_cx<=tr_cx+(dcx>>>2); O_cy<=tr_cy+(dcy>>>2);
    end
    O_valid<=1'b1;
   end else if(O_valid) begin
     O_x_min<=tr_xmin; O_x_max<=tr_xmax; O_y_min<=tr_ymin; O_y_max<=tr_ymax; O_cx<=tr_cx; O_cy<=tr_cy;
     if(miss_count>=2) begin O_valid<=0;miss_count<=0;end else miss_count<=miss_count+1'b1;
   end else begin O_valid<=0; end
   S_xb<=0;S_y<=0;R_xmin<=11'h7ff;R_xmax<=0;R_ymin<=10'h3ff;R_ymax<=0;R_area<=0;G_xmin<=11'h7ff;G_xmax<=0;G_ymin<=10'h3ff;G_ymax<=0;G_area<=0;B_xmin<=11'h7ff;B_xmax<=0;B_ymin<=10'h3ff;B_ymax<=0;B_area<=0;
  end else if(I_vld) begin
   S_xb<=I_tlast?0:S_xb+1'b1; if(I_tlast)S_y<=S_y+1'b1;
   if(I_en) begin
    if(any_r)begin if(S_px0<R_xmin)R_xmin<=S_px0;if(S_px1>R_xmax)R_xmax<=S_px1;if(S_y<R_ymin)R_ymin<=S_y;if(S_y>R_ymax)R_ymax<=S_y;end
    if(any_g)begin if(S_px0<G_xmin)G_xmin<=S_px0;if(S_px1>G_xmax)G_xmax<=S_px1;if(S_y<G_ymin)G_ymin<=S_y;if(S_y>G_ymax)G_ymax<=S_y;end
    if(any_b)begin if(S_px0<B_xmin)B_xmin<=S_px0;if(S_px1>B_xmax)B_xmax<=S_px1;if(S_y<B_ymin)B_ymin<=S_y;if(S_y>B_ymax)B_ymax<=S_y;end
    R_area<=R_area+{21'd0,cnt_r};G_area<=G_area+{21'd0,cnt_g};B_area<=B_area+{21'd0,cnt_b};
   end
  end
 end
endmodule

