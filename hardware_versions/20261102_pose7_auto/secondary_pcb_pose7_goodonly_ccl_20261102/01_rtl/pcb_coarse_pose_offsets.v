// Generates exactly one legal pose's 256 signed8(dx,dy) offsets in workspace.
// Q30 trig and integer half-rounding are frozen by integer_coarse_v1 reference.
// Small constant cases contain 140 bounding boxes and 40 unit coefficients;
// no expanded 136x256 pose ROM exists. All wide arithmetic is serial32.
module pcb_coarse_pose_offsets #(
    parameter [14:0] OFFSET_BASE=15'd12800
)(
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [3:0] I_width_index,I_angle_index,
    output wire O_busy,
    output reg O_done,O_valid,
    output reg [3:0] O_error,
    output reg [6:0] O_xmin,O_ymin,
    output wire O_we,
    output wire [14:0] O_waddr,
    output wire [15:0] O_wdata
);
    localparam [3:0] IDLE=0,MLAUNCH=1,MWAIT=2,DXSTART=3,DXWAIT=4,
                     DYSTART=5,DYWAIT=6,WRITE=7;
    reg [3:0] state;
    reg [4:0] operation;
    reg [7:0] width,index;
    reg [3:0] angle,column,row;
    reg signed [63:0] a,b,c,d,value,row_x,row_y,nx,ny,step_x,step_y,row_step_x,row_step_y;
    reg [7:0] dx,dy;
    reg [1:0] math_op;
    reg signed [63:0] math_a,math_b;
    reg [9:0] math_factor;
    wire math_start=state==MLAUNCH || state==DXSTART || state==DYSTART;
    wire math_busy,math_done,math_valid;
    wire signed [63:0] math_result;
    wire [3:0] math_error;
    wire [7:0] input_raw_index={I_width_index,3'b0}+{I_width_index,1'b0}+I_angle_index;
    wire [13:0] bounds=pose_bounds(input_raw_index);
    assign O_busy=state!=IDLE;
    assign O_we=state==WRITE && !I_cancel;
    assign O_waddr=OFFSET_BASE+index;
    assign O_wdata={dy,dx};

    function signed [63:0] unit_coefficient;
        input [3:0] ai;
        input [1:0] component;
        begin
            unit_coefficient=0;
            case(ai)
            4'd0:case(component)2'd0:unit_coefficient=64'sd124405192314; 2'd1:unit_coefficient=-64'sd7471798950; 2'd2:unit_coefficient=64'sd17484009543; 2'd3:unit_coefficient=64'sd53164612100;endcase
            4'd1:case(component)2'd0:unit_coefficient=64'sd125321770431; 2'd1:unit_coefficient=-64'sd3745022150; 2'd2:unit_coefficient=64'sd8763351831; 2'd3:unit_coefficient=64'sd53556312150;endcase
            4'd2:case(component)2'd0:unit_coefficient=64'sd125627793408; 2'd1:unit_coefficient=64'sd0; 2'd2:unit_coefficient=64'sd0; 2'd3:unit_coefficient=64'sd53687091200;endcase
            4'd3:case(component)2'd0:unit_coefficient=64'sd125321770431; 2'd1:unit_coefficient=64'sd3745022150; 2'd2:unit_coefficient=-64'sd8763351831; 2'd3:unit_coefficient=64'sd53556312150;endcase
            4'd4:case(component)2'd0:unit_coefficient=64'sd124405192314; 2'd1:unit_coefficient=64'sd7471798950; 2'd2:unit_coefficient=-64'sd17484009543; 2'd3:unit_coefficient=64'sd53164612100;endcase
            4'd5:case(component)2'd0:unit_coefficient=-64'sd124405192314; 2'd1:unit_coefficient=64'sd7471798950; 2'd2:unit_coefficient=-64'sd17484009543; 2'd3:unit_coefficient=-64'sd53164612100;endcase
            4'd6:case(component)2'd0:unit_coefficient=-64'sd125321770431; 2'd1:unit_coefficient=64'sd3745022150; 2'd2:unit_coefficient=-64'sd8763351831; 2'd3:unit_coefficient=-64'sd53556312150;endcase
            4'd7:case(component)2'd0:unit_coefficient=-64'sd125627793408; 2'd1:unit_coefficient=64'sd0; 2'd2:unit_coefficient=64'sd0; 2'd3:unit_coefficient=-64'sd53687091200;endcase
            4'd8:case(component)2'd0:unit_coefficient=-64'sd125321770431; 2'd1:unit_coefficient=-64'sd3745022150; 2'd2:unit_coefficient=64'sd8763351831; 2'd3:unit_coefficient=-64'sd53556312150;endcase
            4'd9:case(component)2'd0:unit_coefficient=-64'sd124405192314; 2'd1:unit_coefficient=-64'sd7471798950; 2'd2:unit_coefficient=64'sd17484009543; 2'd3:unit_coefficient=-64'sd53164612100;endcase
                default:unit_coefficient=0;
            endcase
        end
    endfunction
    function [13:0] pose_bounds;
        input [7:0] raw_index;
        begin
            case(raw_index)
            8'd0:pose_bounds={7'd24,7'd13};
            8'd1:pose_bounds={7'd23,7'd11};
            8'd2:pose_bounds={7'd22,7'd10};
            8'd3:pose_bounds={7'd23,7'd11};
            8'd4:pose_bounds={7'd24,7'd13};
            8'd5:pose_bounds={7'd24,7'd13};
            8'd6:pose_bounds={7'd23,7'd11};
            8'd7:pose_bounds={7'd22,7'd10};
            8'd8:pose_bounds={7'd23,7'd11};
            8'd9:pose_bounds={7'd24,7'd13};
            8'd10:pose_bounds={7'd27,7'd15};
            8'd11:pose_bounds={7'd26,7'd13};
            8'd12:pose_bounds={7'd25,7'd11};
            8'd13:pose_bounds={7'd26,7'd13};
            8'd14:pose_bounds={7'd27,7'd15};
            8'd15:pose_bounds={7'd27,7'd15};
            8'd16:pose_bounds={7'd26,7'd13};
            8'd17:pose_bounds={7'd25,7'd11};
            8'd18:pose_bounds={7'd26,7'd13};
            8'd19:pose_bounds={7'd27,7'd15};
            8'd20:pose_bounds={7'd30,7'd16};
            8'd21:pose_bounds={7'd29,7'd14};
            8'd22:pose_bounds={7'd28,7'd12};
            8'd23:pose_bounds={7'd29,7'd14};
            8'd24:pose_bounds={7'd30,7'd16};
            8'd25:pose_bounds={7'd30,7'd16};
            8'd26:pose_bounds={7'd29,7'd14};
            8'd27:pose_bounds={7'd28,7'd12};
            8'd28:pose_bounds={7'd29,7'd14};
            8'd29:pose_bounds={7'd30,7'd16};
            8'd30:pose_bounds={7'd33,7'd18};
            8'd31:pose_bounds={7'd32,7'd16};
            8'd32:pose_bounds={7'd31,7'd14};
            8'd33:pose_bounds={7'd32,7'd16};
            8'd34:pose_bounds={7'd33,7'd18};
            8'd35:pose_bounds={7'd33,7'd18};
            8'd36:pose_bounds={7'd32,7'd16};
            8'd37:pose_bounds={7'd31,7'd14};
            8'd38:pose_bounds={7'd32,7'd16};
            8'd39:pose_bounds={7'd33,7'd18};
            8'd40:pose_bounds={7'd36,7'd20};
            8'd41:pose_bounds={7'd35,7'd17};
            8'd42:pose_bounds={7'd34,7'd15};
            8'd43:pose_bounds={7'd35,7'd17};
            8'd44:pose_bounds={7'd36,7'd20};
            8'd45:pose_bounds={7'd36,7'd20};
            8'd46:pose_bounds={7'd35,7'd17};
            8'd47:pose_bounds={7'd34,7'd15};
            8'd48:pose_bounds={7'd35,7'd17};
            8'd49:pose_bounds={7'd36,7'd20};
            8'd50:pose_bounds={7'd39,7'd21};
            8'd51:pose_bounds={7'd39,7'd19};
            8'd52:pose_bounds={7'd37,7'd16};
            8'd53:pose_bounds={7'd39,7'd19};
            8'd54:pose_bounds={7'd39,7'd21};
            8'd55:pose_bounds={7'd39,7'd21};
            8'd56:pose_bounds={7'd39,7'd19};
            8'd57:pose_bounds={7'd37,7'd16};
            8'd58:pose_bounds={7'd39,7'd19};
            8'd59:pose_bounds={7'd39,7'd21};
            8'd60:pose_bounds={7'd42,7'd23};
            8'd61:pose_bounds={7'd42,7'd20};
            8'd62:pose_bounds={7'd40,7'd18};
            8'd63:pose_bounds={7'd42,7'd20};
            8'd64:pose_bounds={7'd42,7'd23};
            8'd65:pose_bounds={7'd42,7'd23};
            8'd66:pose_bounds={7'd42,7'd20};
            8'd67:pose_bounds={7'd40,7'd18};
            8'd68:pose_bounds={7'd42,7'd20};
            8'd69:pose_bounds={7'd42,7'd23};
            8'd70:pose_bounds={7'd46,7'd25};
            8'd71:pose_bounds={7'd45,7'd22};
            8'd72:pose_bounds={7'd43,7'd19};
            8'd73:pose_bounds={7'd45,7'd22};
            8'd74:pose_bounds={7'd46,7'd25};
            8'd75:pose_bounds={7'd46,7'd25};
            8'd76:pose_bounds={7'd45,7'd22};
            8'd77:pose_bounds={7'd43,7'd19};
            8'd78:pose_bounds={7'd45,7'd22};
            8'd79:pose_bounds={7'd46,7'd25};
            8'd80:pose_bounds={7'd49,7'd26};
            8'd81:pose_bounds={7'd48,7'd23};
            8'd82:pose_bounds={7'd46,7'd20};
            8'd83:pose_bounds={7'd48,7'd23};
            8'd84:pose_bounds={7'd49,7'd26};
            8'd85:pose_bounds={7'd49,7'd26};
            8'd86:pose_bounds={7'd48,7'd23};
            8'd87:pose_bounds={7'd46,7'd20};
            8'd88:pose_bounds={7'd48,7'd23};
            8'd89:pose_bounds={7'd49,7'd26};
            8'd90:pose_bounds={7'd52,7'd28};
            8'd91:pose_bounds={7'd51,7'd25};
            8'd92:pose_bounds={7'd49,7'd21};
            8'd93:pose_bounds={7'd51,7'd25};
            8'd94:pose_bounds={7'd52,7'd28};
            8'd95:pose_bounds={7'd52,7'd28};
            8'd96:pose_bounds={7'd51,7'd25};
            8'd97:pose_bounds={7'd49,7'd21};
            8'd98:pose_bounds={7'd51,7'd25};
            8'd99:pose_bounds={7'd52,7'd28};
            8'd100:pose_bounds={7'd55,7'd30};
            8'd101:pose_bounds={7'd54,7'd26};
            8'd102:pose_bounds={7'd52,7'd23};
            8'd103:pose_bounds={7'd54,7'd26};
            8'd104:pose_bounds={7'd55,7'd30};
            8'd105:pose_bounds={7'd55,7'd30};
            8'd106:pose_bounds={7'd54,7'd26};
            8'd107:pose_bounds={7'd52,7'd23};
            8'd108:pose_bounds={7'd54,7'd26};
            8'd109:pose_bounds={7'd55,7'd30};
            8'd110:pose_bounds={7'd58,7'd31};
            8'd111:pose_bounds={7'd57,7'd28};
            8'd112:pose_bounds={7'd55,7'd24};
            8'd113:pose_bounds={7'd57,7'd28};
            8'd114:pose_bounds={7'd58,7'd31};
            8'd115:pose_bounds={7'd58,7'd31};
            8'd116:pose_bounds={7'd57,7'd28};
            8'd117:pose_bounds={7'd55,7'd24};
            8'd118:pose_bounds={7'd57,7'd28};
            8'd119:pose_bounds={7'd58,7'd31};
            8'd120:pose_bounds={7'd61,7'd33};
            8'd121:pose_bounds={7'd60,7'd29};
            8'd122:pose_bounds={7'd58,7'd25};
            8'd123:pose_bounds={7'd60,7'd29};
            8'd124:pose_bounds={7'd61,7'd33};
            8'd125:pose_bounds={7'd61,7'd33};
            8'd126:pose_bounds={7'd60,7'd29};
            8'd127:pose_bounds={7'd58,7'd25};
            8'd128:pose_bounds={7'd60,7'd29};
            8'd129:pose_bounds={7'd61,7'd33};
            8'd130:pose_bounds={7'd65,7'd35};
            8'd131:pose_bounds={7'd63,7'd31};
            8'd132:pose_bounds={7'd61,7'd27};
            8'd133:pose_bounds={7'd63,7'd31};
            8'd134:pose_bounds={7'd65,7'd35};
            8'd135:pose_bounds={7'd65,7'd35};
            8'd136:pose_bounds={7'd63,7'd31};
            8'd137:pose_bounds={7'd61,7'd27};
            8'd138:pose_bounds={7'd63,7'd31};
            8'd139:pose_bounds={7'd65,7'd35};
                default:pose_bounds={7'd127,7'd127};
            endcase
        end
    endfunction
    always @* begin
        math_op=0;math_a=0;math_b=0;math_factor=0;
        if(state==DXSTART || state==DXWAIT) begin math_op=2;math_a=nx;end
        else if(state==DYSTART || state==DYWAIT) begin math_op=2;math_a=ny;end
        else case(operation)
            0,1,2,3:begin math_op=1;math_a=unit_coefficient(angle,operation[1:0]);math_factor={2'd0,width};end
            4:begin math_a=a;math_b=b;end
            5,8:begin math_op=1;math_a=value;math_factor=315;end
            6,9:begin math_a=~value;math_b=1;end
            7:begin math_a=c;math_b=d;end
            10:begin math_op=1;math_a=a;math_factor=42;end
            11:begin math_op=1;math_a=c;math_factor=42;end
            12:begin math_op=1;math_a=b;math_factor=42;end
            13:begin math_op=1;math_a=d;math_factor=42;end
            14:begin math_a=nx;math_b=step_x;end
            15:begin math_a=ny;math_b=step_y;end
            16:begin math_a=row_x;math_b=row_step_x;end
            17:begin math_a=row_y;math_b=row_step_y;end
            default:begin end
        endcase
    end
    wire math_cancel=I_cancel || (I_start && state!=IDLE);
    pcb_coarse_math_serial math(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(math_start),.I_cancel(math_cancel),
        .I_op(math_op),.I_a(math_a),.I_b(math_b),.I_factor(math_factor),
        .O_busy(math_busy),.O_done(math_done),.O_valid(math_valid),.O_result(math_result),.O_error(math_error));
    task fail;
        input [3:0] code;
        begin state<=IDLE;O_done<=1;O_valid<=0;O_error<=code;end
    endtask
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;operation<=0;width<=0;index<=0;angle<=0;column<=0;row<=0;
            a<=0;b<=0;c<=0;d<=0;value<=0;row_x<=0;row_y<=0;nx<=0;ny<=0;
            step_x<=0;step_y<=0;row_step_x<=0;row_step_y<=0;dx<=0;dy<=0;
            O_done<=0;O_valid<=0;O_error<=0;O_xmin<=0;O_ymin<=0;
        end else begin
            O_done<=0;
            if(I_cancel) begin state<=IDLE;O_valid<=0;O_error<=0;end
            else if(I_start && state!=IDLE) fail(4'd2);
            else case(state)
                IDLE:if(I_start) begin
                    O_valid<=0;O_error<=0;
                    O_xmin<=bounds[13:7];O_ymin<=bounds[6:0];
                    if(I_width_index>13 || I_angle_index>9) fail(4'd1);
                    else if(bounds[13:7]>63 || bounds[6:0]>35) begin O_done<=1;O_valid<=0;end
                    else begin
                        width<=8'd44+{I_width_index,2'b0}+{I_width_index,1'b0};angle<=I_angle_index;
                        operation<=0;index<=0;column<=0;row<=0;state<=MLAUNCH;
                    end
                end
                MLAUNCH:state<=MWAIT;
                MWAIT:if(math_done) begin
                    if(!math_valid) fail(4'd3);
                    else begin
                        case(operation)
                            0:a<=math_result;
                            1:b<=math_result;
                            2:c<=math_result;
                            3:d<=math_result;
                            4,5,7,8:value<=math_result;
                            6:row_x<=math_result;
                            9:row_y<=math_result;
                            10:step_x<=math_result;
                            11:step_y<=math_result;
                            12:row_step_x<=math_result;
                            13:begin row_step_y<=math_result;nx<=row_x;ny<=row_y;end
                            14:nx<=math_result;
                            15:ny<=math_result;
                            16:begin row_x<=math_result;nx<=math_result;end
                            17:begin row_y<=math_result;ny<=math_result;end
                            default:begin end
                        endcase
                        if(operation==13 || operation==15 || operation==17) state<=DXSTART;
                        else begin operation<=operation+5'd1;state<=MLAUNCH;end
                    end
                end
                DXSTART:state<=DXWAIT;
                DXWAIT:if(math_done) begin
                    if(!math_valid) fail(4'd3);
                    else begin dx<=math_result[7:0];state<=DYSTART;end
                end
                DYSTART:state<=DYWAIT;
                DYWAIT:if(math_done) begin
                    if(!math_valid) fail(4'd3);
                    else begin dy<=math_result[7:0];state<=WRITE;end
                end
                WRITE:begin
                    if(index==255) begin state<=IDLE;O_done<=1;O_valid<=1;end
                    else begin
                        index<=index+8'd1;
                        if(column==15) begin column<=0;row<=row+4'd1;operation<=16;end
                        else begin column<=column+4'd1;operation<=14;end
                        state<=MLAUNCH;
                    end
                end
                default:fail(4'd1);
            endcase
        end
    end
endmodule
