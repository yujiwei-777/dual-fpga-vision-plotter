// KEY3/B9 is active low. Both press and release must settle for 5 ms;
// holding the button produces one request and never queues repeated shots.
module pcb_teach_key #(
    parameter integer DEBOUNCE_CYCLES=625000
)(
    input wire I_clk,I_rst_n,I_key_n,
    output reg O_press
);
    reg [1:0] key_sync;
    reg stable;
    reg [19:0] count;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin key_sync<=2'b11;stable<=1;count<=0;O_press<=0;end
        else begin
            key_sync<={key_sync[0],I_key_n};O_press<=0;
            if(key_sync[1]==stable)count<=0;
            else if(count==DEBOUNCE_CYCLES-1)begin
                stable<=key_sync[1];count<=0;
                if(stable&&!key_sync[1])O_press<=1;
            end else count<=count+1'b1;
        end
    end
endmodule
