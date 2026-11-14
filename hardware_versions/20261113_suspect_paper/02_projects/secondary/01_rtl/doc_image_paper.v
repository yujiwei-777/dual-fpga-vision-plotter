// Bright-paper segmentation, genuine 4-connected component labelling, replay
// of labels to isolate the largest component, Moore outer-contour tracing,
// and a four-vertex split of the closed contour. No x+y corner shortcut.
// The shared workspace is a synchronous 512x32 RAM; only its first 320
// entries are line labels here. It becomes the histogram RAM afterwards.
module doc_image_paper(
 input wire clk,rst_n,start,input wire [7:0] threshold,
 output reg busy,done,error,output reg [7:0] error_code,
 output reg [127:0] corners,
 output reg pixel_request,pixel_invalidate,output reg [10:0] pixel_x,
 output reg [9:0] pixel_y,input wire pixel_ready,pixel_valid,input wire [7:0] pixel_luma,
 output reg [8:0] work_addr,output reg work_we,output reg [31:0] work_data,
 input wire [31:0] work_q
);
 localparam IDLE=0,REQ=1,WAIT_PIXEL=2,PROCESS=3,NEW_LABEL=4,
 FIND_L_R=5,FIND_L_C=6,FIND_U_R=7,FIND_U_C=8,MERGE=9,MERGE_LOSER=10,
 PIX_END=11,ADVANCE=12,BEST_R=13,BEST_C=14,REPLAY_R=15,REPLAY_C=16,
 REPLAY_FIND_R=17,REPLAY_FIND_C=18,REPLAY_WRITE=19,REPLAY_NEXT=20,
 TRACE_R=21,TRACE_C=22,FAR_R=23,FAR_C=24,ARC_R=25,ARC_C=26,
 CANONICAL=27,FINISH=28;
 reg [4:0] state;reg [8:0] cx;reg [7:0] cy;reg [15:0] index;
 reg white,selected;reg [8:0] left_label,up_label,raw_label,next_label,query;
 reg [8:0] root_l,root_u,winner,loser,best_root,best_at;
 reg [15:0] area_l,area_u,best_area,merged_area;reg [9:0] hops;
 // Packed parent+area keeps the entire finite component table in one ERAM.
 (* ram_style="bram" *)reg [24:0] components[0:511] /* synthesis syn_ramstyle="block_ram" */;
 reg [24:0] component_q;reg [8:0] table_addr;reg table_we;reg [24:0] table_data;
 (* ram_style="bram" *)reg mask[0:57599] /* synthesis syn_ramstyle="block_ram" */;
 reg mask_q;reg [15:0] mask_addr;reg mask_we,mask_data;
 (* ram_style="bram" *)reg [17:0] contour[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 reg [17:0] contour_q;reg [9:0] contour_addr;reg contour_we;reg [17:0] contour_data;
 reg found;reg [8:0] first_x,tx,nx;reg [7:0] first_y,ty,ny;
 reg [2:0] direction;reg [3:0] probes;reg neighbor_out;
 reg [10:0] contour_count;reg [9:0] scan_at,far_at;
 reg [17:0] p0,pfar,pa,pb;reg [19:0] max_distance;reg [20:0] max_cross;
 reg second_arc;
 reg signed [10:0] dx,dy,edge_dx,edge_dy;
 reg signed [21:0] cross_value;reg [20:0] abs_cross;
 reg [19:0] distance;
 reg [17:0] s0,s1,s2,s3,swap;
 wire [8:0] incoming_up=cy==0?9'd0:work_q[8:0];
 wire [8:0] incoming_raw=left_label!=0?left_label:incoming_up;
 always @*begin
  pixel_request=state==REQ;pixel_x={cx,2'b10};pixel_y={cy,2'b10};
  nx=tx;ny=ty;neighbor_out=0;
  case(direction)
   0:begin if(tx==319)neighbor_out=1;else nx=tx+1'b1;end
   1:begin if(tx==319||ty==179)neighbor_out=1;else begin nx=tx+1'b1;ny=ty+1'b1;end end
   2:begin if(ty==179)neighbor_out=1;else ny=ty+1'b1;end
   3:begin if(tx==0||ty==179)neighbor_out=1;else begin nx=tx-1'b1;ny=ty+1'b1;end end
   4:begin if(tx==0)neighbor_out=1;else nx=tx-1'b1;end
   5:begin if(tx==0||ty==0)neighbor_out=1;else begin nx=tx-1'b1;ny=ty-1'b1;end end
   6:begin if(ty==0)neighbor_out=1;else ny=ty-1'b1;end
   7:begin if(tx==319||ty==0)neighbor_out=1;else begin nx=tx+1'b1;ny=ty-1'b1;end end
  endcase
  dx=$signed({2'b0,contour_q[8:0]})-$signed({2'b0,p0[8:0]});
  dy=$signed({3'b0,contour_q[16:9]})-$signed({3'b0,p0[16:9]});
  edge_dx=$signed({2'b0,pfar[8:0]})-$signed({2'b0,p0[8:0]});
  edge_dy=$signed({3'b0,pfar[16:9]})-$signed({3'b0,p0[16:9]});
  distance=dx*dx+dy*dy;cross_value=edge_dx*dy-edge_dy*dx;
  abs_cross=cross_value[21]?-cross_value:cross_value;
  work_addr=cx;work_we=0;work_data=0;
  if(state==PIX_END)begin work_we=1;work_data={23'd0,white?raw_label:9'd0};end
  if(state==REPLAY_WRITE)begin work_we=1;work_data={23'd0,white?raw_label:9'd0};end
  table_addr=query;table_we=0;table_data=0;
  if(state==NEW_LABEL)begin table_addr=next_label;table_we=1;table_data={next_label,16'd1};end
  if(state==MERGE)begin table_addr=winner;table_we=1;table_data={winner,merged_area};end
  if(state==MERGE_LOSER)begin table_addr=loser;table_we=1;table_data={winner,16'd0};end
  if(state==BEST_R||state==BEST_C)table_addr=best_at;
  mask_addr=index;mask_we=0;mask_data=0;
  if(state==WAIT_PIXEL&&pixel_valid)begin mask_we=1;mask_data=pixel_luma>threshold;end
  if(state==REPLAY_WRITE)begin mask_we=1;mask_data=selected;end
  if(state==TRACE_R||state==TRACE_C)mask_addr=ny*16'd320+nx;
  contour_addr=scan_at;contour_we=0;contour_data=0;
  if(state==REPLAY_NEXT&&index==57599)begin contour_addr=0;contour_we=1;contour_data={1'b0,first_y,first_x};end
  if(state==TRACE_C&&!neighbor_out&&mask_q&&!(nx==first_x&&ny==first_y))begin
   contour_addr=contour_count[9:0];contour_we=1;contour_data={1'b0,ny,nx};end
 end
 always @(posedge clk)begin
  if(table_we)components[table_addr]<=table_data;else component_q<=components[table_addr];
  if(mask_we)mask[mask_addr]<=mask_data;else mask_q<=mask[mask_addr];
  if(contour_we)contour[contour_addr]<=contour_data;else contour_q<=contour[contour_addr];
 end
 task fail;input [7:0] code;begin error<=1;error_code<=code;state<=FINISH;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;busy<=0;done<=0;error<=0;error_code<=0;corners<=0;
   pixel_invalidate<=0;cx<=0;cy<=0;index<=0;
   white<=0;selected<=0;left_label<=0;up_label<=0;raw_label<=0;next_label<=1;query<=0;
   root_l<=0;root_u<=0;winner<=0;loser<=0;best_root<=0;best_at<=1;
   area_l<=0;area_u<=0;best_area<=0;merged_area<=0;hops<=0;found<=0;
   first_x<=0;first_y<=0;tx<=0;ty<=0;direction<=4;probes<=0;contour_count<=0;
   scan_at<=0;far_at<=0;p0<=0;pfar<=0;pa<=0;pb<=0;max_distance<=0;max_cross<=0;second_arc<=0;
   s0<=0;s1<=0;s2<=0;s3<=0;swap<=0;
  end else begin done<=0;pixel_invalidate<=0;case(state)
   IDLE:if(start)begin busy<=1;error<=0;error_code<=0;corners<=0;cx<=0;cy<=0;index<=0;
    left_label<=0;next_label<=1;best_area<=0;best_root<=0;found<=0;pixel_invalidate<=1;state<=REQ;end
   REQ:if(pixel_ready)state<=WAIT_PIXEL;
   WAIT_PIXEL:if(pixel_valid)begin white<=pixel_luma>threshold;state<=PROCESS;end
   PROCESS:begin up_label<=incoming_up;raw_label<=incoming_raw;hops<=0;
    if(!white)state<=PIX_END;
    else if(incoming_raw==0)begin if(next_label==511)fail(8'h12);else state<=NEW_LABEL;end
    else begin query<=left_label!=0?left_label:incoming_up;state<=FIND_L_R;end
   end
   NEW_LABEL:begin raw_label<=next_label;next_label<=next_label+1'b1;state<=PIX_END;end
   FIND_L_R:state<=FIND_L_C;
   FIND_L_C:if(hops==511)fail(8'h12);
    else if(component_q[24:16]!=query)begin query<=component_q[24:16];hops<=hops+1'b1;state<=FIND_L_R;end
    else begin root_l<=query;area_l<=component_q[15:0];
     if(left_label!=0&&up_label!=0&&up_label!=left_label)begin query<=up_label;hops<=0;state<=FIND_U_R;end
     else begin winner<=query;loser<=0;merged_area<=component_q[15:0]+1'b1;state<=MERGE;end end
   FIND_U_R:state<=FIND_U_C;
   FIND_U_C:if(hops==511)fail(8'h12);
    else if(component_q[24:16]!=query)begin query<=component_q[24:16];hops<=hops+1'b1;state<=FIND_U_R;end
    else begin
     root_u<=query;area_u<=component_q[15:0];winner<=root_l<query?root_l:query;
     loser<=root_l==query?9'd0:(root_l<query?query:root_l);
     merged_area<=root_l==query?area_l+1'b1:area_l+component_q[15:0]+1'b1;state<=MERGE;
    end
   MERGE:if(loser!=0)state<=MERGE_LOSER;else state<=PIX_END;
   MERGE_LOSER:state<=PIX_END;
   PIX_END:begin left_label<=white?raw_label:9'd0;state<=ADVANCE;end
   ADVANCE:if(index==57599)begin best_at<=1;state<=BEST_R;end
    else begin index<=index+1'b1;if(cx==319)begin cx<=0;cy<=cy+1'b1;left_label<=0;end else cx<=cx+1'b1;state<=REQ;end
   BEST_R:state<=BEST_C;
   BEST_C:begin
    if(component_q[24:16]==best_at&&component_q[15:0]>best_area)begin best_area<=component_q[15:0];best_root<=best_at;end
    if(best_at+1'b1==next_label)begin cx<=0;cy<=0;index<=0;left_label<=0;next_label<=1;state<=REPLAY_R;end
    else begin best_at<=best_at+1'b1;state<=BEST_R;end
   end
   REPLAY_R:state<=REPLAY_C;
   REPLAY_C:begin white<=mask_q;selected<=0;raw_label<=incoming_raw;
    if(!mask_q)state<=REPLAY_WRITE;
    else begin
     if(incoming_raw==0)begin raw_label<=next_label;query<=next_label;next_label<=next_label+1'b1;end
     else query<=incoming_raw;
     hops<=0;state<=REPLAY_FIND_R;
    end
   end
   REPLAY_FIND_R:state<=REPLAY_FIND_C;
   REPLAY_FIND_C:if(hops==511)fail(8'h12);
    else if(component_q[24:16]!=query)begin query<=component_q[24:16];hops<=hops+1'b1;state<=REPLAY_FIND_R;end
    else begin selected<=query==best_root;state<=REPLAY_WRITE;end
   REPLAY_WRITE:begin left_label<=white?raw_label:9'd0;
    if(selected)begin
     if(cx==0||cx==319||cy==0||cy==179)fail(8'h13);
     else begin if(!found)begin found<=1;first_x<=cx;first_y<=cy;end state<=REPLAY_NEXT;end
    end else state<=REPLAY_NEXT;
   end
   REPLAY_NEXT:if(index==57599)begin
    if(!found||best_area<3000)fail(8'h11);
    else begin tx<=first_x;ty<=first_y;direction<=4;probes<=0;contour_count<=1;
     p0<={1'b0,first_y,first_x};state<=TRACE_R;end
   end else begin index<=index+1'b1;if(cx==319)begin cx<=0;cy<=cy+1'b1;left_label<=0;end else cx<=cx+1'b1;state<=REPLAY_R;end
   TRACE_R:state<=TRACE_C;
   TRACE_C:if(!neighbor_out&&mask_q)begin
    if(nx==first_x&&ny==first_y)begin if(contour_count<16)fail(8'h14);
     else begin scan_at<=1;max_distance<=0;far_at<=0;state<=FAR_R;end end
    else if(contour_count==1024)fail(8'h14);
    else begin tx<=nx;ty<=ny;contour_count<=contour_count+1'b1;probes<=0;
     case(direction)0,1:direction<=6;2,3:direction<=0;4,5:direction<=2;default:direction<=4;endcase state<=TRACE_R;end
   end else if(probes==7)fail(8'h14);
    else begin direction<=direction+1'b1;probes<=probes+1'b1;state<=TRACE_R;end
   FAR_R:state<=FAR_C;
   FAR_C:begin if(distance>max_distance)begin max_distance<=distance;pfar<=contour_q;far_at<=scan_at;end
    if({1'b0,scan_at}+1'b1==contour_count)begin scan_at<=1;max_cross<=0;second_arc<=0;state<=ARC_R;end
    else begin scan_at<=scan_at+1'b1;state<=FAR_R;end end
   ARC_R:state<=ARC_C;
   ARC_C:begin
    if(abs_cross>max_cross)begin max_cross<=abs_cross;if(second_arc)pb<=contour_q;else pa<=contour_q;end
    if(!second_arc&&scan_at+1'b1==far_at)begin
     if(max_cross<32)fail(8'h15);else begin second_arc<=1;scan_at<=far_at+1'b1;max_cross<=0;state<=ARC_R;end
    end else if(second_arc&&{1'b0,scan_at}+1'b1==contour_count)begin
     if(max_cross<32)fail(8'h15);else state<=CANONICAL;
    end else begin scan_at<=scan_at+1'b1;state<=ARC_R;end
   end
   CANONICAL:begin
    // Four-element sorting network by y, then x within the top/bottom pairs.
    // Blocking temporaries are confined to this one sequential transition.
    s0=p0;s1=pa;s2=pfar;s3=pb;
    if(s0[16:9]>s1[16:9])begin swap=s0;s0=s1;s1=swap;end
    if(s2[16:9]>s3[16:9])begin swap=s2;s2=s3;s3=swap;end
    if(s0[16:9]>s2[16:9])begin swap=s0;s0=s2;s2=swap;end
    if(s1[16:9]>s3[16:9])begin swap=s1;s1=s3;s3=swap;end
    if(s1[16:9]>s2[16:9])begin swap=s1;s1=s2;s2=swap;end
    if(s0[8:0]>s1[8:0])begin swap=s0;s0=s1;s1=swap;end
    if(s2[8:0]>s3[8:0])begin swap=s2;s2=s3;s3=swap;end
    corners<={{6'd0,s2[16:9],2'b10},{5'd0,s2[8:0],2'b10},
               {6'd0,s3[16:9],2'b10},{5'd0,s3[8:0],2'b10},
               {6'd0,s1[16:9],2'b10},{5'd0,s1[8:0],2'b10},
               {6'd0,s0[16:9],2'b10},{5'd0,s0[8:0],2'b10}};
    state<=FINISH;
   end
   FINISH:begin busy<=0;done<=1;state<=IDLE;end
   default:state<=IDLE;
  endcase end
 end
endmodule
