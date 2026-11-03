// Source-from-192x96 canonical affine, six signed40 Q28 coefficients.
// Exactly matches source_affine() Fraction/nearest-even contract; no float.
// Decompose each unit-width rational as q+r/L with Euclidean remainder.
// q fits signed32; r<549362067696. Multiplying by width<=122 needs only64bits,
// even though multiplying the unreduced whole numerator needs77bits.
module pcb_coarse_affine_packet (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [3:0] I_width_index,I_angle_index,
    input wire [6:0] I_center_x,I_center_y,
    output wire O_busy,
    output reg O_done,O_valid,
    output reg [3:0] O_error,
    output reg signed [39:0] O_ax,O_bx,O_tx,O_ay,O_by,O_ty
);
    localparam [3:0] IDLE=0,QSTART=1,QWAIT=2,RSTART=3,RWAIT=4,
                     DSTART=5,DWAIT=6,ASTART=7,AWAIT=8,CSTART=9,CWAIT=10;
    reg [3:0] state,angle;
    reg [2:0] coefficient;
    reg [7:0] width;
    reg [6:0] cx,cy;
    reg signed [63:0] integer_part,fraction_numerator,increment,value;
    wire [5:0] unit_index={angle,2'b0}+{angle,1'b0}+coefficient;
    wire [70:0] unit_data=unit_fraction(unit_index);
    wire signed [31:0] unit_integer=unit_data[70:39];
    wire [38:0] unit_remainder=unit_data[38:0];
    wire [6:0] center=coefficient==2?cx:cy;
    wire [11:0] center_twice={center,4'b0}+{center,2'b0}+12'd9;
    wire [63:0] center_q28={25'd0,center_twice,27'd0};
    reg [1:0] math_op;
    reg signed [63:0] math_a,math_b;
    reg [9:0] math_factor;
    wire math_start=state==QSTART || state==RSTART || state==DSTART || state==ASTART || state==CSTART;
    wire math_done,math_valid,math_busy;
    wire signed [63:0] math_result;
    wire [3:0] math_error;
    wire abort_request=I_cancel || (I_start && state!=IDLE);
    assign O_busy=state!=IDLE;
    function [70:0] unit_fraction;
        input [5:0] index;
        begin
            case(index)
                6'd0:unit_fraction=71'h006c8233244db62c30;
                6'd1:unit_fraction=71'h7ff15b75e1437a0200;
                6'd2:unit_fraction=71'h5a3cf58ca32b1d6ca0;
                6'd3:unit_fraction=71'h000f3ff8ac1e6e7448;
                6'd4:unit_fraction=71'h0068303ea5cdc665f0;
                6'd5:unit_fraction=71'h66faaf1c02a86f792c;
                6'd6:unit_fraction=71'h006d4edc5b058dbd78;
                6'd7:unit_fraction=71'h7ff8a9274964875430;
                6'd8:unit_fraction=71'h5895b201e4797b0cd4;
                6'd9:unit_fraction=71'h0007a4c092524dd3c8;
                6'd10:unit_fraction=71'h0068f4c1e3c036d860;
                6'd11:unit_fraction=71'h69aca02fa374ddc0e4;
                6'd12:unit_fraction=71'h006d93312a8a153420;
                6'd13:unit_fraction=71'h000000000000000000;
                6'd14:unit_fraction=71'h571f97289e8e142c10;
                6'd15:unit_fraction=71'h000000000000000000;
                6'd16:unit_fraction=71'h0069365e3ed10bafc0;
                6'd17:unit_fraction=71'h6c7a6983560312ba60;
                6'd18:unit_fraction=71'h006d4edc5b058dbd78;
                6'd19:unit_fraction=71'h000756d8b6840094c0;
                6'd20:unit_fraction=71'h55dc779625d2803f14;
                6'd21:unit_fraction=71'h7ff85b3f6d963a1528;
                6'd22:unit_fraction=71'h0068f4c1e3c036d860;
                6'd23:unit_fraction=71'h6f608bdcd1569931cc;
                6'd24:unit_fraction=71'h006c8233244db62c30;
                6'd25:unit_fraction=71'h000ea48a1ea50de6f0;
                6'd26:unit_fraction=71'h54cde64b41cf2aa720;
                6'd27:unit_fraction=71'h7ff0c00753ca1974a8;
                6'd28:unit_fraction=71'h0068303ea5cdc665f0;
                6'd29:unit_fraction=71'h725b69a473525615f4;
                6'd30:unit_fraction=71'h7f937dccdb9ad1bcc0;
                6'd31:unit_fraction=71'h000ea48a1ea50de6f0;
                6'd32:unit_fraction=71'h25c30a735cbd6a7c50;
                6'd33:unit_fraction=71'h7ff0c00753ca1974a8;
                6'd34:unit_fraction=71'h7f97cfc15a1ac18300;
                6'd35:unit_fraction=71'h190550e3fd40186fc4;
                6'd36:unit_fraction=71'h7f92b123a4e2fa2b78;
                6'd37:unit_fraction=71'h000756d8b6840094c0;
                6'd38:unit_fraction=71'h276a4dfe1b6f0cdc1c;
                6'd39:unit_fraction=71'h7ff85b3f6d963a1528;
                6'd40:unit_fraction=71'h7f970b3e1c28511090;
                6'd41:unit_fraction=71'h16535fd05c73aa280c;
                6'd42:unit_fraction=71'h7f926cced55e72b4d0;
                6'd43:unit_fraction=71'h000000000000000000;
                6'd44:unit_fraction=71'h28e068d7615a73bce0;
                6'd45:unit_fraction=71'h000000000000000000;
                6'd46:unit_fraction=71'h7f96c9a1c1177c3930;
                6'd47:unit_fraction=71'h1385967ca9e5752e90;
                6'd48:unit_fraction=71'h7f92b123a4e2fa2b78;
                6'd49:unit_fraction=71'h7ff8a9274964875430;
                6'd50:unit_fraction=71'h2a238869da1607a9dc;
                6'd51:unit_fraction=71'h0007a4c092524dd3c8;
                6'd52:unit_fraction=71'h7f970b3e1c28511090;
                6'd53:unit_fraction=71'h109f74232e91eeb724;
                6'd54:unit_fraction=71'h7f937dccdb9ad1bcc0;
                6'd55:unit_fraction=71'h7ff15b75e1437a0200;
                6'd56:unit_fraction=71'h2b3219b4be195d41d0;
                6'd57:unit_fraction=71'h000f3ff8ac1e6e7448;
                6'd58:unit_fraction=71'h7f97cfc15a1ac18300;
                6'd59:unit_fraction=71'h0da4965b8c9631d2fc;
                default:unit_fraction=0;
            endcase
        end
    endfunction
    always @* begin
        math_op=0;math_a=0;math_b=0;math_factor=0;
        case(state)
            QSTART,QWAIT:begin math_op=1;math_a={{32{unit_integer[31]}},unit_integer};math_factor={2'd0,width};end
            RSTART,RWAIT:begin math_op=1;math_a={25'd0,unit_remainder};math_factor={2'd0,width};end
            DSTART,DWAIT:begin math_op=3;math_a=fraction_numerator;math_b={63'd0,integer_part[0]};end
            ASTART,AWAIT:begin math_a=integer_part;math_b=increment;end
            CSTART,CWAIT:begin math_a=value;math_b=center_q28;end
            default:begin end
        endcase
    end
    pcb_coarse_math_serial math(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(math_start && !abort_request),.I_cancel(abort_request),
        .I_op(math_op),.I_a(math_a),.I_b(math_b),.I_factor(math_factor),.O_busy(math_busy),.O_done(math_done),
        .O_valid(math_valid),.O_result(math_result),.O_error(math_error));
    task fail;
        input [3:0] code;
        begin state<=IDLE;O_done<=1;O_valid<=0;O_error<=code;end
    endtask
    task save_coefficient;
        input signed [63:0] result;
        begin
            if(result[63:40]!={24{result[39]}})fail(4'd3);
            else begin
                case(coefficient)
                    0:O_ax<=result[39:0];1:O_bx<=result[39:0];2:O_tx<=result[39:0];
                    3:O_ay<=result[39:0];4:O_by<=result[39:0];5:O_ty<=result[39:0];
                    default:begin end
                endcase
                if(coefficient==5)begin state<=IDLE;O_done<=1;O_valid<=1;end
                else begin coefficient<=coefficient+3'd1;state<=QSTART;end
            end
        end
    endtask
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;angle<=0;coefficient<=0;width<=0;cx<=0;cy<=0;integer_part<=0;
            fraction_numerator<=0;increment<=0;value<=0;O_done<=0;O_valid<=0;O_error<=0;
            O_ax<=0;O_bx<=0;O_tx<=0;O_ay<=0;O_by<=0;O_ty<=0;
        end else begin
            O_done<=0;
            if(I_cancel) begin state<=IDLE;O_valid<=0;O_error<=0;end
            else if(I_start && state!=IDLE)fail(4'd2);
            else case(state)
                IDLE:if(I_start)begin
                    O_valid<=0;O_error<=0;
                    if(I_width_index>13 || I_angle_index>9 || I_center_y>71)fail(4'd1);
                    else begin
                        angle<=I_angle_index;width<=8'd44+{I_width_index,2'b0}+{I_width_index,1'b0};
                        cx<=I_center_x;cy<=I_center_y;coefficient<=0;state<=QSTART;
                    end
                end
                QSTART:state<=QWAIT;
                QWAIT:if(math_done)begin if(!math_valid)fail(4'd4);else begin integer_part<=math_result;state<=RSTART;end end
                RSTART:state<=RWAIT;
                RWAIT:if(math_done)begin if(!math_valid)fail(4'd4);else begin fraction_numerator<=math_result;state<=DSTART;end end
                DSTART:state<=DWAIT;
                DWAIT:if(math_done)begin if(!math_valid)fail(4'd4);else begin increment<=math_result;state<=ASTART;end end
                ASTART:state<=AWAIT;
                AWAIT:if(math_done)begin
                    if(!math_valid)fail(4'd4);
                    else if(coefficient==2 || coefficient==5)begin value<=math_result;state<=CSTART;end
                    else save_coefficient(math_result);
                end
                CSTART:state<=CWAIT;
                CWAIT:if(math_done)begin if(!math_valid)fail(4'd4);else save_coefficient(math_result);end
                default:fail(4'd1);
            endcase
        end
    end
endmodule
