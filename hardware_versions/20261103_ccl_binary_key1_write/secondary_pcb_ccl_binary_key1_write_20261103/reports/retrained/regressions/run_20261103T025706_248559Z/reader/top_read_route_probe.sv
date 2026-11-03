module pose7_read_route_probe(
 input wire clk125,rst125_n,vision_start,vision_cancel,vision_done,vision_job_cancel,
 input wire [1:0] vision_purpose,
 input wire normal_busy,copy_busy,copy_image_lock,pcb_frame_lock,key4_copy_reset,
 input wire copy_reader_request,copy_reader_invalidate,normal_reader_request,normal_reader_invalidate,
 input wire [10:0] copy_pixel_x,normal_pixel_x,
 input wire [9:0] copy_pixel_y,normal_pixel_y,
 input wire color_word_active,normal_rd_req,
 input wire [20:0] normal_rd_addr,
 output wire v_rd_req,output wire [20:0] v_rd_addr,
 input wire v_rd_ready,v_rd_valid,input wire [127:0] v_rd_data,
 output wire pixel_ready,pixel_valid,output wire [23:0] pixel_rgb,output wire [7:0] pixel_y8,
 output wire owner_copy,frame_locked,pixel_pending,vision_busy
);
 wire copy_task=(vision_purpose==2'd2);
    reg copy_pixel_pending;
    wire shared_frame_lock=pcb_frame_lock||copy_image_lock||copy_pixel_pending;
    // A cancelled document may retire its controller before a DDR response
    // arrives. That drain remains busy and cannot admit a new frame or job.
    assign vision_busy=normal_busy||copy_busy||shared_frame_lock;
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
    wire [1:0] vision_purpose_locked=vision_busy ? vision_purpose_q : vision_purpose;
    // A document is already a full CRC-validated frame at start. Network
    // cancellation cannot change its owner; explicit cancellation fences new
    // pixel reads while any already accepted response drains under the lock.
    wire copy_read_fenced=copy_reader_request&&!vision_job_cancel&&!key4_copy_reset;
    wire shared_reader_request=copy_reader_select?copy_read_fenced:normal_reader_request;
    wire shared_reader_invalidate=copy_reader_select?copy_reader_invalidate:normal_reader_invalidate;
    wire [10:0] shared_pixel_x=copy_reader_select?copy_pixel_x:normal_pixel_x;
    wire [9:0] shared_pixel_y=copy_reader_select?copy_pixel_y:normal_pixel_y;
    wire shared_reader_ready,shared_reader_valid;
    wire shared_word_req;
    wire [20:0] shared_byte_addr;
    wire [23:0] shared_reader_rgb;
    wire [7:0] shared_reader_luma;
    always @(posedge clk125 or negedge rst125_n)begin
        if(!rst125_n)copy_pixel_pending<=1'b0;
        else if(copy_reader_select)begin
            if(shared_reader_valid && (copy_pixel_pending || (copy_read_fenced&&shared_reader_ready)))
                copy_pixel_pending<=1'b0;
            else if(copy_read_fenced&&shared_reader_ready)copy_pixel_pending<=1'b1;
        end
    end
    vision_pixel_reader u_shared_reader(.clk(clk125),.rst_n(rst125_n&&(!vision_cancel||shared_frame_lock||copy_busy)),
        .invalidate(shared_reader_invalidate),.request(shared_reader_request),
        .pixel_x(shared_pixel_x),.pixel_y(shared_pixel_y),
        .ready(shared_reader_ready),.pixel_valid(shared_reader_valid),.pixel_rgb(shared_reader_rgb),
        .pixel_y8(shared_reader_luma),.word_req(shared_word_req),.byte_addr(shared_byte_addr),
        .word_ready(v_rd_ready&&(copy_reader_select||!color_word_active)),.word_valid(v_rd_valid&&(copy_reader_select||!color_word_active)),.word_data(v_rd_data));
    // The ordinary CNN reads only on-chip RAM while colour statistics own
    // the DDR word port. Ownership switches only with no pixel read pending.
    assign v_rd_req=(!copy_reader_select&&color_word_active) ? normal_rd_req : shared_word_req;
    assign v_rd_addr=(!copy_reader_select&&color_word_active) ? normal_rd_addr : shared_byte_addr;

 assign pixel_ready=shared_reader_ready;
 assign pixel_valid=shared_reader_valid;
 assign pixel_rgb=shared_reader_rgb;
 assign pixel_y8=shared_reader_luma;
 assign owner_copy=copy_reader_select;
 assign frame_locked=shared_frame_lock;
 assign pixel_pending=copy_pixel_pending;
endmodule
