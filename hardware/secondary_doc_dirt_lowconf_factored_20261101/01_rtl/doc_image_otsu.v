// 256-bin histogram and integer Otsu. Histogram storage is external so its
// ERAM can be reused as the paper detector's line-label cache.
module doc_image_otsu(
 input wire clk,rst_n,start,finish,
 input wire sample_valid,input wire [7:0] sample_luma,output wire sample_ready,
 output reg busy,done,error,output reg [7:0] threshold,mean_low,mean_high,
 output reg [8:0] mem_addr,output reg mem_we,output reg [31:0] mem_data,
 input wire [31:0] mem_q
);
 localparam IDLE=0,CLEAR=1,READY=2,HIST_WRITE=3,SCAN_READ=4,SCAN_ADD=5,
 M0=6,W0=7,M1=8,W1=9,SUB=10,SUBW=11,SQUARE=12,SQUAREW=13,
 DEN=14,DENW=15,DIV=16,DIVW=17,NEXT=18,MEAN0=19,MEAN0W=20,
 MEAN1=21,MEAN1W=22,FINISH=23;
 reg [4:0] state;reg [7:0] at,saved_luma;
 reg [16:0] count,low_count,best_count;reg [31:0] sum,low_sum,best_sum;
 reg [63:0] product,difference,denominator,best_score;
 reg signed [127:0] square;
 reg launch;reg [1:0] operation;reg signed [127:0] a;reg signed [63:0] b;
 wire adone,aerror,abusy;wire signed [127:0] value;
 // The histogram bin index is only eight bits.  Expand the bin count once
 // and form count*index with a shift/add network so this diagnostic path does
 // not consume a DSP multiplier.  The largest product is 131071*255, which
 // fits in 25 bits.
 wire [24:0] hist_count_ext={8'd0,mem_q[16:0]};
 wire [24:0] hist_weight =
     (at[0]?hist_count_ext:25'd0) +
     (at[1]?(hist_count_ext<<1):25'd0) +
     (at[2]?(hist_count_ext<<2):25'd0) +
     (at[3]?(hist_count_ext<<3):25'd0) +
     (at[4]?(hist_count_ext<<4):25'd0) +
     (at[5]?(hist_count_ext<<5):25'd0) +
     (at[6]?(hist_count_ext<<6):25'd0) +
     (at[7]?(hist_count_ext<<7):25'd0);
 doc_arithmetic alu(.clk(clk),.rst_n(rst_n),.start(launch),.operation(operation),
 .a(a),.b(b),.busy(abusy),.done(adone),.error(aerror),.result(value));
 assign sample_ready=state==READY;
 always @*begin
  mem_addr={1'b0,at};mem_we=0;mem_data=0;
  if(state==CLEAR)mem_we=1;
  else if(state==READY)mem_addr={1'b0,sample_luma};
  else if(state==HIST_WRITE)begin mem_addr={1'b0,saved_luma};mem_we=1;mem_data=mem_q+1'b1;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;busy<=0;done<=0;error<=0;threshold<=0;mean_low<=0;mean_high<=0;
   at<=0;saved_luma<=0;count<=0;low_count<=0;best_count<=0;sum<=0;low_sum<=0;best_sum<=0;
   product<=0;difference<=0;denominator<=0;best_score<=0;square<=0;launch<=0;operation<=0;a<=0;b<=0;end
  else begin done<=0;launch<=0;case(state)
   IDLE:if(start)begin busy<=1;error<=0;at<=0;count<=0;sum<=0;best_score<=0;best_count<=0;
    best_sum<=0;low_count<=0;low_sum<=0;threshold<=0;state<=CLEAR;end
   CLEAR:if(at==255)begin at<=0;state<=READY;end else at<=at+1'b1;
   READY:if(sample_valid)begin saved_luma<=sample_luma;state<=HIST_WRITE;end
    else if(finish)begin at<=0;low_count<=0;low_sum<=0;state<=SCAN_READ;end
   HIST_WRITE:begin count<=count+1'b1;sum<=sum+saved_luma;state<=READY;end
   SCAN_READ:state<=SCAN_ADD;
   SCAN_ADD:begin low_count<=low_count+mem_q[16:0];low_sum<=low_sum+hist_weight;state<=M0;end
   M0:if(low_count!=0&&low_count<count)begin a<={96'd0,sum};b<={47'd0,low_count};operation<=0;launch<=1;state<=W0;end
    else state<=NEXT;
   W0:if(adone)begin product<=value[63:0];state<=M1;end
   M1:begin a<={96'd0,low_sum};b<={47'd0,count};operation<=0;launch<=1;state<=W1;end
   W1:if(adone)begin a<={64'd0,product};b<=value[63:0];operation<=3;state<=SUB;end
   SUB:begin launch<=1;state<=SUBW;end
   SUBW:if(adone)begin difference<=value[63:0];state<=SQUARE;end
   SQUARE:begin a<={64'd0,difference};b<=difference;operation<=0;launch<=1;state<=SQUAREW;end
   SQUAREW:if(adone)begin square<=value;state<=DEN;end
   DEN:begin a<={111'd0,low_count};b<=count-low_count;operation<=0;launch<=1;state<=DENW;end
   DENW:if(adone)begin denominator<=value[63:0];state<=DIV;end
   DIV:begin a<=square;b<=denominator;operation<=1;launch<=1;state<=DIVW;end
   DIVW:if(adone)begin
    if(aerror||value<0||value[127:64]!=0)begin error<=1;state<=FINISH;end
    else begin if(value[63:0]>best_score)begin best_score<=value[63:0];threshold<=at;best_count<=low_count;best_sum<=low_sum;end state<=NEXT;end
   end
   NEXT:if(at==254)begin if(best_count==0||best_count==count)begin error<=1;state<=FINISH;end else state<=MEAN0;end
    else begin at<=at+1'b1;state<=SCAN_READ;end
   MEAN0:begin a<={96'd0,best_sum};b<={47'd0,best_count};operation<=1;launch<=1;state<=MEAN0W;end
   MEAN0W:if(adone)begin mean_low<=value[7:0];state<=MEAN1;end
   MEAN1:begin a<={96'd0,(sum-best_sum)};b<=count-best_count;operation<=1;launch<=1;state<=MEAN1W;end
   MEAN1W:if(adone)begin mean_high<=value[7:0];state<=FINISH;end
   FINISH:begin busy<=0;done<=1;state<=IDLE;end
   default:state<=IDLE;
  endcase end
 end
endmodule
