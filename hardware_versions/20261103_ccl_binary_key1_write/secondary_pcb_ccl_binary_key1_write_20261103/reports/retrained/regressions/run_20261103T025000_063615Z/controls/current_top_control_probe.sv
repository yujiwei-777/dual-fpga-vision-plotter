module pose7_top_control_probe(
 input wire clk125,rst125_n,vision_start,vision_cancel,vision_done,vision_job_cancel,
 input wire [1:0] vision_purpose,
 input wire copy_busy,copy_image_lock,pcb_frame_lock,
 input wire copy_reader_request,shared_reader_ready,shared_reader_valid,key4_copy_reset,
 input wire report_pending,key2_report_pending,report_busy,key1_job_protected,key2_local_active,
 input wire key4_press,key4_reset_active,key4_report_reset,
 output wire owner_copy,frame_locked,pixel_pending,reader_reset_n,report_abort,
 output wire report_clear_pending,report_stop,copy_cancel,read_allowed,
 output wire [1:0] locked_purpose
);
 wire copy_task=(vision_purpose==2'd2);
 reg copy_pixel_pending;
    wire shared_frame_lock=pcb_frame_lock||copy_image_lock||copy_pixel_pending;
    wire copy_read_fenced=copy_reader_request&&!vision_job_cancel&&!key4_copy_reset;
    wire report_network_protected=report_pending||key2_report_pending||report_busy||
        key1_job_protected||key2_local_active;
    reg copy_reader_select;
    reg [1:0] vision_purpose_q;
    always @(posedge clk125 or negedge rst125_n) begin
        if(!rst125_n) begin
            copy_reader_select<=1'b0;
            vision_purpose_q<=2'd0;
        end else if((vision_done || (vision_cancel&&!copy_busy) ||
            (copy_reader_select&&!copy_busy)) && !shared_frame_lock) begin
            copy_reader_select<=1'b0;
            vision_purpose_q<=2'd0;
        end else if(vision_start && !shared_frame_lock) begin
            copy_reader_select<=copy_task;
            vision_purpose_q<=vision_purpose;
        end
    end
    always @(posedge clk125 or negedge rst125_n)begin
        if(!rst125_n)copy_pixel_pending<=1'b0;
        else if(copy_reader_select)begin
            if(shared_reader_valid && (copy_pixel_pending || (copy_read_fenced&&shared_reader_ready)))
                copy_pixel_pending<=1'b0;
            else if(copy_read_fenced&&shared_reader_ready)copy_pixel_pending<=1'b1;
        end
    end

assign owner_copy=copy_reader_select;assign locked_purpose=vision_purpose_q;assign frame_locked=shared_frame_lock;assign pixel_pending=copy_pixel_pending;assign read_allowed=copy_read_fenced;
assign reader_reset_n=rst125_n&&(!vision_cancel||shared_frame_lock||copy_busy);
assign report_abort=vision_job_cancel||(!report_network_protected&&vision_cancel);
assign report_stop=key4_report_reset;
assign report_clear_pending=key4_press||key4_reset_active||vision_job_cancel||(vision_cancel&&!report_network_protected);
assign copy_cancel=vision_job_cancel;
endmodule
