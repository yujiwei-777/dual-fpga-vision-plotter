// Destination (u=0..225,v=0..319) -> source Q20 camera coordinate.
// Every coefficient is signed 64 bit. All products and shifted division
// numerators are 128 bit, checked before narrowing. Serial arithmetic only.
module doc_homography(
 input wire clk,rst_n,configure,input wire [127:0] corners,
 input wire request,input wire [7:0] u,input wire [8:0] v,
 output wire ready,output reg configured,valid,error,
 output reg [10:0] x,output reg [9:0] y,output reg [19:0] fx,fy
);
 localparam IDLE=0,LOAD=1,DECODE=2,FETCH_A=3,FETCH_B=4,ISSUE=5,WAIT_OP=6,SET_V=7;
 localparam X0=0,Y0=1,X1=2,Y1=3,X2=4,Y2=5,X3=6,Y3=7,
 DX1=8,DX2=9,DX3=10,DY1=11,DY2=12,DY3=13,DET=14,P=15,
 NG=16,NH=17,G=18,H=19,AA=20,BB=21,DD=22,EE=23,
 NX=24,NY=25,DEN=26,SU=27,SV=28,CC=29,FF=30;
 reg [3:0] state;reg [6:0] step;reg [2:0] load_at;
 reg [127:0] corner_shift;reg [7:0] saved_u;reg [8:0] saved_v;
 // Only 2 kbit: keep in logic; the image workspace has a strict ERAM budget.
 (* ram_style="distributed" *)reg signed [63:0] values[0:31] /* synthesis syn_ramstyle="registers" */;
 reg signed [63:0] ram_q;reg [4:0] address,sa,sb,destination;
 reg [1:0] operation;reg [5:0] shift_a;reg immediate;
 reg signed [63:0] imm;reg signed [127:0] operand_a;reg signed [63:0] operand_b;
 reg launch;wire alu_done,alu_error,alu_busy;wire signed [127:0] alu_value;
 wire fits64=alu_value[127:64]=={64{alu_value[63]}};
 doc_arithmetic alu(.clk(clk),.rst_n(rst_n),.start(launch),.operation(operation),
  .a(operand_a),.b(operand_b),.busy(alu_busy),.done(alu_done),.error(alu_error),.result(alu_value));
 assign ready=state==IDLE;
 always @*begin
  sa=0;sb=0;destination=0;operation=0;shift_a=0;immediate=0;imm=0;
  case(step)
   0:begin sa=X1;sb=X2;destination=DX1;operation=3;end
   1:begin sa=X3;sb=X2;destination=DX2;operation=3;end
   2:begin sa=X0;sb=X1;destination=DX3;operation=3;end
   3:begin sa=DX3;sb=X2;destination=DX3;operation=2;end
   4:begin sa=DX3;sb=X3;destination=DX3;operation=3;end
   5:begin sa=Y1;sb=Y2;destination=DY1;operation=3;end
   6:begin sa=Y3;sb=Y2;destination=DY2;operation=3;end
   7:begin sa=Y0;sb=Y1;destination=DY3;operation=3;end
   8:begin sa=DY3;sb=Y2;destination=DY3;operation=2;end
   9:begin sa=DY3;sb=Y3;destination=DY3;operation=3;end
   10:begin sa=DX1;sb=DY2;destination=P;end
   11:begin sa=DX2;sb=DY1;destination=DET;end
   12:begin sa=P;sb=DET;destination=DET;operation=3;end
   13:begin sa=DX3;sb=DY2;destination=P;end
   14:begin sa=DX2;sb=DY3;destination=NG;end
   15:begin sa=P;sb=NG;destination=NG;operation=3;end
   16:begin sa=DX1;sb=DY3;destination=P;end
   17:begin sa=DX3;sb=DY1;destination=NH;end
   18:begin sa=P;sb=NH;destination=NH;operation=3;end
   19:begin sa=NG;sb=DET;destination=G;operation=1;shift_a=20;end
   20:begin sa=NH;sb=DET;destination=H;operation=1;shift_a=20;end
   21:begin sa=G;sb=X1;destination=P;end
   22:begin sa=X1;sb=X0;destination=AA;operation=3;end
   23:begin sa=AA;sb=P;destination=AA;operation=2;shift_a=20;end
   24:begin sa=H;sb=X3;destination=P;end
   25:begin sa=X3;sb=X0;destination=BB;operation=3;end
   26:begin sa=BB;sb=P;destination=BB;operation=2;shift_a=20;end
   27:begin sa=G;sb=Y1;destination=P;end
   28:begin sa=Y1;sb=Y0;destination=DD;operation=3;end
   29:begin sa=DD;sb=P;destination=DD;operation=2;shift_a=20;end
   30:begin sa=H;sb=Y3;destination=P;end
   31:begin sa=Y3;sb=Y0;destination=EE;operation=3;end
   32:begin sa=EE;sb=P;destination=EE;operation=2;shift_a=20;end
   33:begin sa=AA;immediate=1;imm=319;destination=AA;end
   34:begin sa=BB;immediate=1;imm=225;destination=BB;end
   35:begin sa=DD;immediate=1;imm=319;destination=DD;end
   36:begin sa=EE;immediate=1;imm=225;destination=EE;end
   37:begin sa=G;immediate=1;imm=319;destination=G;end
   38:begin sa=H;immediate=1;imm=225;destination=H;end
   39:begin sa=X0;shift_a=20;immediate=1;imm=71775;destination=CC;end
   40:begin sa=Y0;shift_a=20;immediate=1;imm=71775;destination=FF;end
   41:begin sa=AA;sb=SU;destination=P;end
   42:begin sa=P;sb=CC;destination=NX;operation=2;end
   43:begin sa=BB;sb=SV;destination=P;end
   44:begin sa=NX;sb=P;destination=NX;operation=2;end
   45:begin sa=DD;sb=SU;destination=P;end
   46:begin sa=P;sb=FF;destination=NY;operation=2;end
   47:begin sa=EE;sb=SV;destination=P;end
   48:begin sa=NY;sb=P;destination=NY;operation=2;end
   49:begin sa=G;sb=SU;destination=P;end
   50:begin sa=P;immediate=1;imm=64'sd75261542400;destination=DEN;operation=2;end
   51:begin sa=H;sb=SV;destination=P;end
   52:begin sa=DEN;sb=P;destination=DEN;operation=2;end
   53:begin sa=NX;sb=DEN;destination=NX;operation=1;shift_a=20;end
   54:begin sa=NY;sb=DEN;destination=NY;operation=1;shift_a=20;end
   default:;
  endcase
  address=sa;
  if(state==FETCH_A)address=sb;
  if(state==LOAD)address={2'b0,load_at};
  if(state==WAIT_OP&&alu_done)address=destination;
 end
 always @(posedge clk)begin
  if(state==LOAD)values[address]<={48'd0,corner_shift[15:0]};
  else if(state==WAIT_OP&&alu_done&&!alu_error&&fits64)values[address]<=alu_value[63:0];
  else if(state==IDLE&&request&&configured)begin values[SU]<={56'd0,u};end
  else if(state==SET_V)values[SV]<={55'd0,saved_v};
  else ram_q<=values[address];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;step<=0;load_at<=0;corner_shift<=0;saved_u<=0;saved_v<=0;
   operand_a<=0;operand_b<=0;launch<=0;configured<=0;valid<=0;error<=0;x<=0;y<=0;fx<=0;fy<=0;end
  else begin launch<=0;valid<=0;case(state)
   IDLE:if(configure)begin corner_shift<=corners;configured<=0;error<=0;load_at<=0;step<=0;state<=LOAD;end
    else if(request&&configured)begin saved_u<=u;saved_v<=v;error<=0;
     if(u>225||v>319)begin valid<=1;error<=1;end else begin step<=41;state<=SET_V;end end
   SET_V:state<=DECODE;
   LOAD:begin corner_shift<=corner_shift>>16;if(load_at==7)state<=DECODE;else load_at<=load_at+1'b1;end
   DECODE:state<=FETCH_A;
   FETCH_A:begin operand_a<=$signed({{64{ram_q[63]}},ram_q})<<<shift_a;state<=FETCH_B;end
   FETCH_B:begin operand_b<=immediate?imm:ram_q;state<=ISSUE;end
   ISSUE:begin launch<=1;state<=WAIT_OP;end
   WAIT_OP:if(alu_done)begin
    if(alu_error||!fits64||(step==52&&alu_value<128'sd7526154240))begin error<=1;valid<=step>=41;state<=IDLE;end
    else if(step==40)begin configured<=1;state<=IDLE;end
    else if(step==54)begin valid<=1;state<=IDLE;
     if(alu_value<0||alu_value>(128'sd719<<<20))error<=1;
     else begin y<=alu_value[29:20];fy<=alu_value[19:0];end
    end else begin
     if(step==53)begin
      if(alu_value<0||alu_value>(128'sd1279<<<20))begin error<=1;valid<=1;state<=IDLE;end
      else begin x<=alu_value[30:20];fx<=alu_value[19:0];step<=step+1'b1;state<=DECODE;end
     end else begin step<=step+1'b1;state<=DECODE;end
    end
   end
   default:state<=IDLE;
  endcase end
 end
endmodule
