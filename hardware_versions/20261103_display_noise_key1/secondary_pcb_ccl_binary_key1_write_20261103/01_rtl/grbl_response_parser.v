// GRBL response lines: exact "ok", error:/ALARM:, and complete <Idle|...>.
// Status prefixes, echoes such as "book", and unterminated lines never ACK.
module grbl_response_parser(
    input wire I_clk,input wire I_rst_n,input wire I_clear,
    input wire [7:0] I_data,input wire I_valid,
    output reg O_ok,output reg O_error,output reg O_alarm,
    output reg O_status,output reg O_idle,output reg O_overflow,
    output reg O_hold0,output reg O_reset
);
    reg [7:0] first0,first1,first2,first3,first4,first5,first6,first7,last;
    reg [7:0] length;
    reg overflow;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            first0<=0;first1<=0;first2<=0;first3<=0;first4<=0;first5<=0;first6<=0;first7<=0;last<=0;
            length<=0;overflow<=0;O_ok<=0;O_error<=0;O_alarm<=0;O_status<=0;O_idle<=0;O_overflow<=0;O_hold0<=0;O_reset<=0;
        end else begin
            O_ok<=0;O_error<=0;O_alarm<=0;O_status<=0;O_idle<=0;O_overflow<=0;O_hold0<=0;O_reset<=0;
            if(I_clear)begin length<=0;overflow<=0;last<=0;end
            else if(I_valid)begin
                if(I_data==8'h0a || I_data==8'h0d)begin
                    if(overflow)O_overflow<=1;
                    else if(length!=0)begin
                        // A GRBL startup banner invalidates an outstanding
                        // motion transaction. Match the line prefix only;
                        // echoes/substrings containing "Grbl" are ignored.
                        if(length>=5 && first0=="G" && first1=="r" && first2=="b" && first3=="l" && first4==" ")O_reset<=1;
                        if(length==2 && first0=="o" && first1=="k")O_ok<=1;
                        if(length>=6 && first0=="e" && first1=="r" && first2=="r" &&
                           first3=="o" && first4=="r" && first5==":")O_error<=1;
                        if(length>=6 && first0=="A" && first1=="L" && first2=="A" &&
                           first3=="R" && first4=="M" && first5==":")O_alarm<=1;
                        if(length>=3 && first0=="<" && last==">")begin
                            O_status<=1;
                            if(first1=="I" && first2=="d" && first3=="l" && first4=="e" &&
                               ((first5=="|" && length>=7)||(first5==">" && length==6)))O_idle<=1;
                            // Hold:1 is still decelerating; only complete Hold:0
                            // proves that the axes stopped before soft reset.
                            if(first1=="H" && first2=="o" && first3=="l" && first4=="d" &&
                               first5==":" && first6=="0" &&
                               ((first7=="|" && length>=9)||(first7==">" && length==8)))O_hold0<=1;
                        end
                    end
                    length<=0;overflow<=0;
                end else begin
                    if(length==0)first0<=I_data;
                    if(length==1)first1<=I_data;
                    if(length==2)first2<=I_data;
                    if(length==3)first3<=I_data;
                    if(length==4)first4<=I_data;
                    if(length==5)first5<=I_data;
                    if(length==6)first6<=I_data;
                    if(length==7)first7<=I_data;
                    last<=I_data;
                    if(length<8'd254)length<=length+1'b1;
                    else overflow<=1;
                end
            end
        end
    end
endmodule
