// Document-only response parser. A clear starts a new response epoch, so a
// partial status/ack from an earlier command can never complete the new one.
// No substring matches: only an entire "ok" line acknowledges motion.
module doc_grbl_response_parser(
    input wire clk,rst_n,clear,
    input wire [7:0] data,input wire valid,
    output reg ok,error,alarm,status,idle,hold0,overflow,reset_banner
);
    reg [7:0] prefix[0:7];
    reg [7:0] length,last;
    reg too_long;
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            length<=0;last<=0;too_long<=0;
            ok<=0;error<=0;alarm<=0;status<=0;idle<=0;hold0<=0;overflow<=0;reset_banner<=0;
            for(i=0;i<8;i=i+1) prefix[i]<=0;
        end else begin
            ok<=0;error<=0;alarm<=0;status<=0;idle<=0;hold0<=0;overflow<=0;reset_banner<=0;
            if(clear) begin length<=0;last<=0;too_long<=0;end
            else if(valid) begin
                if(data==8'h0a || data==8'h0d) begin
                    if(too_long) overflow<=1;
                    else if(length!=0) begin
                        if(length>=5 && prefix[0]=="G" && prefix[1]=="r" && prefix[2]=="b" && prefix[3]=="l" && prefix[4]==" ")reset_banner<=1;
                        if(length==2 && prefix[0]=="o" && prefix[1]=="k")ok<=1;
                        if(length>=6 && prefix[0]=="e" && prefix[1]=="r" &&
                           prefix[2]=="r" && prefix[3]=="o" && prefix[4]=="r" && prefix[5]==":")error<=1;
                        if(length>=6 && prefix[0]=="A" && prefix[1]=="L" &&
                           prefix[2]=="A" && prefix[3]=="R" && prefix[4]=="M" && prefix[5]==":")alarm<=1;
                        if(length>=3 && prefix[0]=="<" && last==">")begin
                            status<=1;
                            if(prefix[1]=="I" && prefix[2]=="d" && prefix[3]=="l" && prefix[4]=="e" &&
                               ((length==6 && prefix[5]==">") || (length>=7 && prefix[5]=="|")))idle<=1;
                            if(prefix[1]=="H" && prefix[2]=="o" && prefix[3]=="l" && prefix[4]=="d" &&
                               prefix[5]==":" && prefix[6]=="0" &&
                               ((length==8 && prefix[7]==">") || (length>=9 && prefix[7]=="|")))hold0<=1;
                        end
                    end
                    length<=0;last<=0;too_long<=0;
                end else begin
                    if(length<8)prefix[length[2:0]]<=data;
                    last<=data;
                    if(length<254)length<=length+1'b1;
                    else too_long<=1;
                end
            end
        end
    end
endmodule
