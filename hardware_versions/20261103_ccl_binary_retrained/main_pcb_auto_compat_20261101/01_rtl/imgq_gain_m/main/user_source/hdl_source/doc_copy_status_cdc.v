// Held-data request/ack mailbox; displayed status changes only in blanking.
module doc_copy_status_cdc(
    input wire src_clk,src_rst_n,input wire [2:0] src_state,
    input wire px_clk,px_rst_n,frame_start,output reg [2:0] staged
);
    wire mailbox_rst_n=src_rst_n&&px_rst_n;
    wire src_reset_n,px_reset_n;
    reset_sync u_src_reset(.I_clk(src_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(src_reset_n));
    reset_sync u_px_reset(.I_clk(px_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(px_reset_n));
    reg req,ack;
    (* ASYNC_REG="TRUE" *) reg ack_s1,ack_s2,req_s1,req_s2;
    reg [2:0] held,last_sent;
    reg primed,capture_wait,pending;
    always @(posedge src_clk or negedge src_reset_n)begin
        if(!src_reset_n)begin req<=0;ack_s1<=0;ack_s2<=0;held<=0;last_sent<=0;primed<=0;end
        else begin
            ack_s1<=ack;ack_s2<=ack_s1;
            if(req==ack_s2&&(!primed||src_state!=last_sent))begin
                held<=src_state;last_sent<=src_state;req<=~req;primed<=1;
            end
        end
    end
    always @(posedge px_clk or negedge px_reset_n)begin
        if(!px_reset_n)begin req_s1<=0;req_s2<=0;ack<=0;staged<=0;capture_wait<=0;pending<=0;end
        else begin
            req_s1<=req;req_s2<=req_s1;
            if(req_s2!=ack&&!capture_wait&&!pending)capture_wait<=1;
            if(capture_wait)begin capture_wait<=0;pending<=1;end
            if(frame_start&&pending)begin staged<=held;ack<=req_s2;pending<=0;end
        end
    end
endmodule
