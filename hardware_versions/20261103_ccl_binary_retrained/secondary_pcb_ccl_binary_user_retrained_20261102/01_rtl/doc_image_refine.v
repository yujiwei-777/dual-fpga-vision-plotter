// Refine each coarse paper edge using 32 evenly spaced points. At every
// point search -8..+8 original-camera pixels along its unit L-infinity
// Euclidean unit normal (integer norm rounded up), using central gradients.
// Fit the four edge lines by least squares,
// intersect adjacent lines, then validate convexity, area and corner angles.
module doc_image_refine(
 input wire clk,rst_n,start,input wire [127:0] coarse_corners,
 output reg busy,done,error,output reg [7:0] error_code,output reg [127:0] corners,
 output reg pixel_request,output reg [10:0] pixel_x,output reg [9:0] pixel_y,
 input wire pixel_ready,pixel_valid,input wire [7:0] pixel_luma
);
 localparam IDLE=0,EDGE=1,NX=2,NXW=3,NY=4,NYW=5,BASEX=6,BASEXW=7,
 BASEXD=8,BASEXDW=9,BASEY=10,BASEYW=11,BASEYD=12,BASEYDW=13,
 SAMPLE_INIT=14,REQ=15,WAIT_PIXEL=16,POINT=17,FIT0=18,FIT0W=19,
 FIT1=20,FIT1W=21,FITS=22,FITSW=23,FITB=24,FITBW=25,STORE=26,
 INTER_INIT=27,INTER_MUL=28,INTER_WAIT=29,INTER_DX=30,INTER_DXW=31,
 INTER_DY=32,INTER_DYW=33,VALID_INIT=34,VALID_MUL=35,VALID_WAIT=36,
 VALID_END=37,FINISH=38,NORM_INIT=39,NORM_STEP=40;
 reg [5:0] state;reg [1:0] edge_at,corner_at;reg [5:0] point_at;
 reg [127:0] saved;reg signed [12:0] x0,y0,dx,dy;
 reg [12:0] normal_div;reg horizontal;
 reg [25:0] norm_square;reg [11:0] norm_root,norm_bit;
 wire [11:0] norm_trial=norm_root|norm_bit;
 wire [23:0] trial_square=norm_trial*norm_trial;
 reg signed [63:0] normal_x,normal_y,base_x,base_y,sample_xq,sample_yq;
 reg [4:0] offset_at;reg [7:0] prev1,prev2,best_gradient;
 reg [10:0] prev_x,best_x;reg [9:0] prev_y,best_y;
 reg [15:0] sum_x,sum_y;reg [26:0] sum_xx,sum_xy,sum_yy;
 reg signed [63:0] p0,p1,slope,intercept,fit_num,fit_den;
 reg signed [63:0] line_a[0:3],line_b[0:3],line_c[0:3];
 reg [3:0] mul_at;reg signed [63:0] products[0:5];
 reg signed [63:0] determinant,x_numerator,y_numerator;
 reg signed [63:0] vx0,vy0,vx1,vy1,cross_value,dot_value,cross_square,area;
 reg [15:0] ax,ay,bx,by;
 reg launch;reg [1:0] operation;reg signed [127:0] a;reg signed [63:0] b;
 wire adone,aerror,abusy;wire signed [127:0] value;
 wire fits=value[127:64]=={64{value[63]}};
 wire [1:0] next_edge=edge_at+1'b1;
 wire [1:0] prev_edge=corner_at-1'b1;
 wire [1:0] next_corner=corner_at+1'b1,next2_corner=corner_at+2'd2;
 wire signed [8:0] gradient=$signed({1'b0,pixel_luma})-$signed({1'b0,prev2});
 wire [15:0] fit_u=horizontal?sum_x:sum_y;
 wire [15:0] fit_v=horizontal?sum_y:sum_x;
 wire [26:0] fit_uu=horizontal?sum_xx:sum_yy;
 doc_arithmetic alu(.clk(clk),.rst_n(rst_n),.start(launch),.operation(operation),.a(a),.b(b),
  .busy(abusy),.done(adone),.error(aerror),.result(value));
 always @*begin pixel_request=state==REQ;pixel_x=sample_xq[30:20];pixel_y=sample_yq[29:20];end
 task fail;input [7:0] code;begin error<=1;error_code<=code;state<=FINISH;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;busy<=0;done<=0;error<=0;error_code<=0;corners<=0;
   edge_at<=0;corner_at<=0;point_at<=0;saved<=0;x0<=0;y0<=0;dx<=0;dy<=0;normal_div<=0;horizontal<=0;
   norm_square<=0;norm_root<=0;norm_bit<=0;
   normal_x<=0;normal_y<=0;base_x<=0;base_y<=0;sample_xq<=0;sample_yq<=0;offset_at<=0;
   prev1<=0;prev2<=0;best_gradient<=0;prev_x<=0;best_x<=0;prev_y<=0;best_y<=0;
   sum_x<=0;sum_y<=0;sum_xx<=0;sum_xy<=0;sum_yy<=0;p0<=0;p1<=0;slope<=0;intercept<=0;fit_num<=0;fit_den<=0;
   mul_at<=0;determinant<=0;x_numerator<=0;y_numerator<=0;vx0<=0;vy0<=0;vx1<=0;vy1<=0;
   cross_value<=0;dot_value<=0;cross_square<=0;area<=0;ax<=0;ay<=0;bx<=0;by<=0;
   launch<=0;operation<=0;a<=0;b<=0;
  end else begin done<=0;launch<=0;case(state)
   IDLE:if(start)begin saved<=coarse_corners;edge_at<=0;busy<=1;error<=0;error_code<=0;corners<=0;state<=EDGE;end
   EDGE:begin
    x0<=$signed({1'b0,saved[edge_at*32+:16]});y0<=$signed({1'b0,saved[edge_at*32+16+:16]});
    dx<=$signed({1'b0,saved[next_edge*32+:16]})-$signed({1'b0,saved[edge_at*32+:16]});
    dy<=$signed({1'b0,saved[next_edge*32+16+:16]})-$signed({1'b0,saved[edge_at*32+16+:16]});
    point_at<=1;sum_x<=0;sum_y<=0;sum_xx<=0;sum_xy<=0;sum_yy<=0;state<=NORM_INIT;
   end
   NORM_INIT:begin norm_square<=dx*dx+dy*dy;norm_root<=0;norm_bit<=12'd2048;state<=NORM_STEP;end
   NORM_STEP:begin
    if(trial_square<=norm_square)norm_root<=norm_trial;
    if(norm_bit==1)begin normal_div<=(trial_square<=norm_square?norm_trial:norm_root)+1'b1;state<=NX;end
    else norm_bit<=norm_bit>>1;
   end
   NX:begin
    horizontal<=(dx[12]?-dx:dx)>=(dy[12]?-dy:dy);
    a<=-($signed({{115{dy[12]}},dy})<<<20);
    b<=normal_div;
    operation<=1;launch<=1;state<=NXW;
   end
   NXW:if(adone)begin if(aerror||!fits)fail(8'h21);else begin normal_x<=value[63:0];state<=NY;end end
   NY:begin a<=$signed({{115{dx[12]}},dx})<<<20;b<=normal_div;operation<=1;launch<=1;state<=NYW;end
   NYW:if(adone)begin if(aerror||!fits)fail(8'h21);else begin normal_y<=value[63:0];state<=BASEX;end end
   BASEX:begin a<={{115{dx[12]}},dx};b<=point_at;operation<=0;launch<=1;state<=BASEXW;end
   BASEXW:if(adone)begin p0<=value[63:0];state<=BASEXD;end
   BASEXD:begin a<={{64{p0[63]}},p0};b<=33;operation<=1;launch<=1;state<=BASEXDW;end
   BASEXDW:if(adone)begin base_x<=x0+value[63:0];state<=BASEY;end
   BASEY:begin a<={{115{dy[12]}},dy};b<=point_at;operation<=0;launch<=1;state<=BASEYW;end
   BASEYW:if(adone)begin p0<=value[63:0];state<=BASEYD;end
   BASEYD:begin a<={{64{p0[63]}},p0};b<=33;operation<=1;launch<=1;state<=BASEYDW;end
   BASEYDW:if(adone)begin base_y<=y0+value[63:0];state<=SAMPLE_INIT;end
   SAMPLE_INIT:begin
    sample_xq<=(base_x<<<20)-(normal_x<<<3)-normal_x;
    sample_yq<=(base_y<<<20)-(normal_y<<<3)-normal_y;
    offset_at<=0;prev1<=0;prev2<=0;best_gradient<=0;state<=REQ;
   end
   REQ:if(sample_xq<0||sample_yq<0||sample_xq>(64'sd1279<<<20)||sample_yq>(64'sd719<<<20))fail(8'h22);
    else if(pixel_ready)state<=WAIT_PIXEL;
   WAIT_PIXEL:if(pixel_valid)begin
    if(offset_at>=2&&gradient>$signed({1'b0,best_gradient}))begin best_gradient<=gradient[7:0];best_x<=prev_x;best_y<=prev_y;end
    prev2<=prev1;prev1<=pixel_luma;prev_x<=pixel_x;prev_y<=pixel_y;
    if(offset_at==18)state<=POINT;
    else begin sample_xq<=sample_xq+normal_x;sample_yq<=sample_yq+normal_y;offset_at<=offset_at+1'b1;state<=REQ;end
   end
   POINT:if(best_gradient<32)fail(8'h23);
    else begin sum_x<=sum_x+best_x;sum_y<=sum_y+best_y;
     sum_xx<=sum_xx+best_x*best_x;sum_xy<=sum_xy+best_x*best_y;sum_yy<=sum_yy+best_y*best_y;
     if(point_at==32)state<=FIT0;else begin point_at<=point_at+1'b1;state<=BASEX;end end
   FIT0:begin a<={112'd0,fit_u};b<={48'd0,fit_v};operation<=0;launch<=1;state<=FIT0W;end
   FIT0W:if(adone)begin p0<=value[63:0];state<=FIT1;end
   FIT1:begin a<={112'd0,fit_u};b<={48'd0,fit_u};operation<=0;launch<=1;state<=FIT1W;end
   FIT1W:if(adone)begin p1<=value[63:0];fit_den<=$signed({32'd0,fit_uu,5'd0})-$signed(value[63:0]);
    fit_num<=$signed({32'd0,sum_xy,5'd0})-p0;state<=FITS;end
   FITS:if(fit_den<=0)fail(8'h24);else begin a<=$signed({{64{fit_num[63]}},fit_num})<<<20;b<=fit_den;operation<=1;launch<=1;state<=FITSW;end
   FITSW:if(adone)begin if(aerror||!fits||value>2097152||value< -2097152)fail(8'h24);
    else begin slope<=value[63:0];state<=FITB;end end
   FITB:begin a<={{64{slope[63]}},slope};b<={48'd0,fit_u};operation<=0;launch<=1;state<=FITBW;end
   FITBW:if(adone)begin if(!fits)fail(8'h24);
    else begin intercept<=(($signed({48'd0,fit_v})<<<20)-value[63:0])>>>5;state<=STORE;end end
   STORE:begin
    line_a[edge_at]<=horizontal?-slope:64'sd1048576;
    line_b[edge_at]<=horizontal?64'sd1048576:-slope;line_c[edge_at]<=intercept;
    if(edge_at==3)begin corner_at<=0;state<=INTER_INIT;end else begin edge_at<=edge_at+1'b1;state<=EDGE;end
   end
   INTER_INIT:begin mul_at<=0;state<=INTER_MUL;end
   INTER_MUL:begin operation<=0;launch<=1;state<=INTER_WAIT;
    case(mul_at)
     0:begin a<={{64{line_a[prev_edge][63]}},line_a[prev_edge]};b<=line_b[corner_at];end
     1:begin a<={{64{line_a[corner_at][63]}},line_a[corner_at]};b<=line_b[prev_edge];end
     2:begin a<={{64{line_c[prev_edge][63]}},line_c[prev_edge]};b<=line_b[corner_at];end
     3:begin a<={{64{line_c[corner_at][63]}},line_c[corner_at]};b<=line_b[prev_edge];end
     4:begin a<={{64{line_a[prev_edge][63]}},line_a[prev_edge]};b<=line_c[corner_at];end
     default:begin a<={{64{line_a[corner_at][63]}},line_a[corner_at]};b<=line_c[prev_edge];end
    endcase
   end
   INTER_WAIT:if(adone)begin
    if(aerror||!fits)fail(8'h25);else begin products[mul_at]<=value[63:0];
     if(mul_at==5)begin determinant<=products[0]-products[1];x_numerator<=products[2]-products[3];
      y_numerator<=products[4]-value[63:0];state<=INTER_DX;end
     else begin mul_at<=mul_at+1'b1;state<=INTER_MUL;end end
   end
   INTER_DX:begin a<={{64{x_numerator[63]}},x_numerator};b<=determinant;operation<=1;launch<=1;state<=INTER_DXW;end
   INTER_DXW:if(adone)begin if(aerror||value<4||value>1275)fail(8'h26);
    else begin corners[corner_at*32+:16]<=value[15:0];state<=INTER_DY;end end
   INTER_DY:begin a<={{64{y_numerator[63]}},y_numerator};b<=determinant;operation<=1;launch<=1;state<=INTER_DYW;end
   INTER_DYW:if(adone)begin if(aerror||value<4||value>715)fail(8'h26);
    else begin corners[corner_at*32+16+:16]<=value[15:0];
     if(corner_at==3)begin corner_at<=0;area<=0;state<=VALID_INIT;end
     else begin corner_at<=corner_at+1'b1;state<=INTER_INIT;end end
   end
   VALID_INIT:begin
    ax<=corners[corner_at*32+:16];ay<=corners[corner_at*32+16+:16];
    bx<=corners[next_corner*32+:16];by<=corners[next_corner*32+16+:16];
    vx0<=$signed({1'b0,corners[next_corner*32+:16]})-$signed({1'b0,corners[corner_at*32+:16]});
    vy0<=$signed({1'b0,corners[next_corner*32+16+:16]})-$signed({1'b0,corners[corner_at*32+16+:16]});
    vx1<=$signed({1'b0,corners[next2_corner*32+:16]})-$signed({1'b0,corners[next_corner*32+:16]});
    vy1<=$signed({1'b0,corners[next2_corner*32+16+:16]})-$signed({1'b0,corners[next_corner*32+16+:16]});
    mul_at<=0;state<=VALID_MUL;
   end
   VALID_MUL:begin operation<=0;launch<=1;state<=VALID_WAIT;
    case(mul_at)
     0:begin a<={{64{vx0[63]}},vx0};b<=vy1;end
     1:begin a<={{64{vy0[63]}},vy0};b<=vx1;end
     2:begin a<={{64{vx0[63]}},vx0};b<=vx1;end
     3:begin a<={{64{vy0[63]}},vy0};b<=vy1;end
     4:begin a<={{64{cross_value[63]}},cross_value};b<=cross_value;end
     5:begin a<={{64{dot_value[63]}},dot_value};b<=dot_value;end
     6:begin a<={112'd0,ax};b<={48'd0,by};end
     default:begin a<={112'd0,ay};b<={48'd0,bx};end
    endcase
   end
   VALID_WAIT:if(adone)begin
    if(aerror||!fits)fail(8'h27);
    else if(mul_at==1&&p0-value[63:0]<=0)fail(8'h27);
    else if(mul_at==5&&cross_square+(cross_square<<<1)<value[63:0])fail(8'h28);
    else begin
     case(mul_at)
      0,2,6:p0<=value[63:0];
      1:cross_value<=p0-value[63:0];
      3:dot_value<=p0+value[63:0];
      4:cross_square<=value[63:0];
      7:area<=area+p0-value[63:0];
      default:;
     endcase
     if(mul_at==7)begin if(corner_at==3)state<=VALID_END;else begin corner_at<=corner_at+1'b1;state<=VALID_INIT;end end
     else begin mul_at<=mul_at+1'b1;state<=VALID_MUL;end
    end
   end
   VALID_END:if(area<184320||area>1474560)fail(8'h29);else state<=FINISH;
   FINISH:begin busy<=0;done<=1;state<=IDLE;end
   default:state<=IDLE;
  endcase end
 end
endmodule
