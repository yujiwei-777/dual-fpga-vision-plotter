// Unit-square -> camera quadrilateral projective transform, Q12 coefficients.
// Corners TL,TR,BR,BL are packed {y[15:0],x[15:0]}, TL in the low word.
// All matrix setup and mapping operations share one serial arithmetic unit.
// Intermediate coordinates live in one synchronous 32x40 single-port RAM;
// the extra operand-fetch cycles replace wide per-coefficient flop/mux banks.
// configure/request are accepted while ready; u/v cover the inclusive 0..64.
module maze_homography(
    input wire clk,rst_n,configure,input wire [127:0] corners,
    input wire request,input wire [6:0] u,v,
    output wire ready,output reg configured,valid,error,
    output reg [10:0] x,output reg [9:0] y
);
    localparam IDLE=0,LOAD_CORNERS=1,LOAD_U=2,LOAD_V=3,
               READ_A=4,FETCH_A=5,FETCH_B=6,START_OP=7,WAIT_OP=8;
    localparam MUL=0,DIV=1,ADD=2,SUB=3;
    localparam X0=0,Y0=1,X1=2,Y1=3,X2=4,Y2=5,X3=6,Y3=7,
               DX1=8,DX2=9,DX3=10,DY1=11,DY2=12,DY3=13,
               DET=14,P=15,NG=16,NH=17,G=18,H=19,AA=20,BB=21,
               DD=22,EE=23,NX=24,NY=25,DEN=26,PX=27,SU=28,SV=29;
    reg [3:0] state;
    reg [5:0] step;
    reg [2:0] load_at;
    reg [127:0] saved_corners;
    reg [6:0] saved_u,saved_v;
    reg [10:0] candidate_x;
    reg candidate_bad;
    (* ram_style="bram" *) reg [39:0] values[0:31] /* synthesis syn_ramstyle="block_ram" */;
    reg [39:0] ram_q;
    reg [4:0] ram_addr,src_a,src_b,dest;
    reg [39:0] ram_data;
    reg ram_write;
    reg [1:0] operation,shift_a;
    reg immediate_b;
    reg [39:0] oa,ob;
    reg op_start;
    wire op_done,op_error,op_busy;
    wire signed [39:0] value;
    maze_arithmetic alu(.clk(clk),.rst_n(rst_n),.start(op_start),
        .divide(operation==DIV),.sum_mode(operation==ADD||operation==SUB),
        .subtract(operation==SUB),.a(oa),.b(ob),.busy(op_busy),
        .done(op_done),.error(op_error),.result(value));
    assign ready=state==IDLE;
    // One shared instruction decoder. Only addresses, shifts and operation
    // selection are decoded here; no matrix arithmetic is combinational.
    always @*begin
        src_a=0;src_b=0;dest=0;operation=MUL;shift_a=0;immediate_b=0;
        case(step)
            0:begin src_a=X1;src_b=X2;dest=DX1;operation=SUB;end
            1:begin src_a=X3;src_b=X2;dest=DX2;operation=SUB;end
            2:begin src_a=X0;src_b=X1;dest=DX3;operation=SUB;end
            3:begin src_a=DX3;src_b=X2;dest=DX3;operation=ADD;end
            4:begin src_a=DX3;src_b=X3;dest=DX3;operation=SUB;end
            5:begin src_a=Y1;src_b=Y2;dest=DY1;operation=SUB;end
            6:begin src_a=Y3;src_b=Y2;dest=DY2;operation=SUB;end
            7:begin src_a=Y0;src_b=Y1;dest=DY3;operation=SUB;end
            8:begin src_a=DY3;src_b=Y2;dest=DY3;operation=ADD;end
            9:begin src_a=DY3;src_b=Y3;dest=DY3;operation=SUB;end
            10:begin src_a=DX1;src_b=DY2;dest=P;end
            11:begin src_a=DX2;src_b=DY1;dest=DET;end
            12:begin src_a=P;src_b=DET;dest=DET;operation=SUB;end
            13:begin src_a=DX3;src_b=DY2;dest=P;end
            14:begin src_a=DX2;src_b=DY3;dest=NG;end
            15:begin src_a=P;src_b=NG;dest=NG;operation=SUB;end
            16:begin src_a=DX1;src_b=DY3;dest=P;end
            17:begin src_a=DX3;src_b=DY1;dest=NH;end
            18:begin src_a=P;src_b=NH;dest=NH;operation=SUB;end
            19:begin src_a=NG;src_b=DET;dest=G;operation=DIV;shift_a=1;end
            20:begin src_a=NH;src_b=DET;dest=H;operation=DIV;shift_a=1;end
            21:begin src_a=G;src_b=X1;dest=P;end
            22:begin src_a=X1;src_b=X0;dest=AA;operation=SUB;end
            23:begin src_a=AA;src_b=P;dest=AA;operation=ADD;shift_a=1;end
            24:begin src_a=H;src_b=X3;dest=P;end
            25:begin src_a=X3;src_b=X0;dest=BB;operation=SUB;end
            26:begin src_a=BB;src_b=P;dest=BB;operation=ADD;shift_a=1;end
            27:begin src_a=G;src_b=Y1;dest=P;end
            28:begin src_a=Y1;src_b=Y0;dest=DD;operation=SUB;end
            29:begin src_a=DD;src_b=P;dest=DD;operation=ADD;shift_a=1;end
            30:begin src_a=H;src_b=Y3;dest=P;end
            31:begin src_a=Y3;src_b=Y0;dest=EE;operation=SUB;end
            32:begin src_a=EE;src_b=P;dest=EE;operation=ADD;shift_a=1;end
            33:begin src_a=AA;src_b=SU;dest=P;end
            34:begin src_a=X0;src_b=P;dest=NX;operation=ADD;shift_a=2;end
            35:begin src_a=BB;src_b=SV;dest=P;end
            36:begin src_a=NX;src_b=P;dest=NX;operation=ADD;end
            37:begin src_a=DD;src_b=SU;dest=P;end
            38:begin src_a=Y0;src_b=P;dest=NY;operation=ADD;shift_a=2;end
            39:begin src_a=EE;src_b=SV;dest=P;end
            40:begin src_a=NY;src_b=P;dest=NY;operation=ADD;end
            41:begin src_a=G;src_b=SU;dest=P;end
            42:begin src_a=P;dest=DEN;operation=ADD;immediate_b=1;end
            43:begin src_a=H;src_b=SV;dest=P;end
            44:begin src_a=DEN;src_b=P;dest=DEN;operation=ADD;end
            45:begin src_a=NX;src_b=DEN;dest=PX;operation=DIV;end
            46:begin src_a=NY;src_b=DEN;dest=P;operation=DIV;end
            default:;
        endcase
        ram_addr=src_a;ram_data=value;ram_write=0;
        if(state==FETCH_A)ram_addr=src_b;
        if(state==LOAD_CORNERS)begin
            ram_addr={2'b00,load_at};ram_data={24'd0,saved_corners[15:0]};ram_write=1;
        end else if(state==LOAD_U)begin ram_addr=SU;ram_data={33'd0,saved_u};ram_write=1;end
        else if(state==LOAD_V)begin ram_addr=SV;ram_data={33'd0,saved_v};ram_write=1;end
        else if(state==WAIT_OP&&op_done&&!op_error)begin ram_addr=dest;ram_write=1;end
    end
    // Unreset synchronous single-port BRAM: configure initializes all corner
    // sources, then each instruction writes its destination before any use.
    always @(posedge clk)begin
        if(ram_write)values[ram_addr]<=ram_data;
        else ram_q<=values[ram_addr];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;step<=0;load_at<=0;saved_corners<=0;saved_u<=0;saved_v<=0;
            oa<=0;ob<=0;op_start<=0;configured<=0;valid<=0;error<=0;
            x<=0;y<=0;candidate_x<=0;candidate_bad<=0;
        end else begin
            valid<=0;op_start<=0;
            case(state)
                IDLE:if(configure)begin
                    saved_corners<=corners;configured<=0;error<=0;
                    load_at<=0;step<=0;state<=LOAD_CORNERS;
                end else if(request&&configured)begin
                    error<=0;candidate_bad<=0;saved_u<=u;saved_v<=v;step<=33;
                    if(u>64||v>64)begin error<=1;valid<=1;x<=0;y<=0;end
                    else state<=LOAD_U;
                end
                LOAD_CORNERS:begin
                    saved_corners<={16'd0,saved_corners[127:16]};
                    if(load_at==7)state<=READ_A;else load_at<=load_at+1'b1;
                end
                LOAD_U:state<=LOAD_V;
                LOAD_V:state<=READ_A;
                READ_A:state<=FETCH_A;
                FETCH_A:begin
                    case(shift_a)
                        1:oa<=ram_q<<12;
                        2:oa<=ram_q<<18;
                        default:oa<=ram_q;
                    endcase
                    state<=FETCH_B;
                end
                FETCH_B:begin ob<=immediate_b?40'd262144:ram_q;state<=START_OP;end
                START_OP:begin op_start<=1;state<=WAIT_OP;end
                WAIT_OP:if(op_done)begin
                    if(op_error)begin error<=1;valid<=step>=33;state<=IDLE;end
                    else if(step==32)begin configured<=1;state<=IDLE;end
                    else if(step==44&&value<40'sd32768)begin error<=1;valid<=1;state<=IDLE;x<=0;y<=0;end
                    else if(step==46)begin
                        valid<=1;state<=IDLE;
                        if(candidate_bad||value<0||value>719)begin x<=0;y<=0;error<=1;end
                        else begin x<=candidate_x;y<=value[9:0];end
                    end else begin
                        if(step==45)begin candidate_x<=value[10:0];candidate_bad<=value<0||value>1279;end
                        step<=step+1'b1;state<=READ_A;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
