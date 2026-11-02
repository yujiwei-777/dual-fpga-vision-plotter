module pose7_frame_owner_probe(
 input wire clk,rst_n,start,auto_busy,cancel,teach_good,auto_done,auto_cancel_seen,
 input wire [6:0] state,input wire [1:0] purpose,purpose_q,
 input wire pcb_ccl_pending,reader_ready,reader_request,
 output wire pcb_frame_lock,processing_rst_n
);
 localparam PCB_ENABLE=1,PCB_GOODONLY_AUTO=1;
 localparam [6:0] IDLE=0,FINISH=33,PCB_AUTO_WAIT=81,PCB_CCL_DRAIN=82;
 reg pcb_frame_owner_q;
 assign pcb_frame_lock=auto_busy||pcb_frame_owner_q;
 assign processing_rst_n=rst_n && !(cancel && !pcb_frame_lock);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)pcb_frame_owner_q<=1'b0;
        else if(state==IDLE && start && !auto_busy && !cancel &&
            PCB_ENABLE!=0 && PCB_GOODONLY_AUTO!=0 && purpose==2'd1 && !teach_good)
            pcb_frame_owner_q<=1'b1;
        else if((state==FINISH && purpose_q==2'd1) ||
            (state==PCB_AUTO_WAIT && auto_done && (cancel || auto_cancel_seen)) ||
            (state==PCB_CCL_DRAIN && !pcb_ccl_pending && reader_ready && !reader_request))
            pcb_frame_owner_q<=1'b0;
    end
endmodule
