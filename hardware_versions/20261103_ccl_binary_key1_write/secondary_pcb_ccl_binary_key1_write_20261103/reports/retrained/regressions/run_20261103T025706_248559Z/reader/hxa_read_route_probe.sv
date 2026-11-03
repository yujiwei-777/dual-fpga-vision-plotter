module pose7_hxa_read_route_probe(
 input wire clk,rst_n,vision_active,v_drain_lock,scanning,scan_outstanding,crc_read_request,
 input wire [17:0] scan_word,
 input wire v_rd_req,input wire [20:0] v_rd_byte_addr,
 output wire v_rd_ready,v_rd_valid,output wire [127:0] v_rd_data,
 output wire rd_req,output wire [20:0] rd_byte_addr,
 input wire rd_ready,rd_valid,input wire [127:0] rd_data,
 output wire admission_safe,vision_pending
);
 localparam PRESERVE_VISION_DRAIN=1;
 reg vision_read_outstanding;
    wire vision_read_owner=vision_active||(PRESERVE_VISION_DRAIN!=0 && v_drain_lock);
    wire drain_admission_safe=(PRESERVE_VISION_DRAIN==0)||
        (!v_drain_lock&&!vision_read_outstanding&&!scan_outstanding);
    always @(posedge clk or negedge rst_n)begin
      if(!rst_n)vision_read_outstanding<=0;
      else if(!scanning&&vision_read_owner&&!scan_outstanding&&v_rd_req&&rd_ready)
        vision_read_outstanding<=!rd_valid;
      else if(rd_valid&&!scan_outstanding)vision_read_outstanding<=0;
    end

    assign rd_req=scanning?crc_read_request:
                  (vision_read_owner&&!scan_outstanding?v_rd_req:1'b0);
    assign rd_byte_addr=scanning?{scan_word[16:0],4'd0}:v_rd_byte_addr;
    assign v_rd_ready=vision_read_owner&&!scanning&&!scan_outstanding&&rd_ready;
    assign v_rd_valid=vision_read_owner&&!scan_outstanding&&rd_valid;
    assign v_rd_data=rd_data;
 assign admission_safe=drain_admission_safe;
 assign vision_pending=vision_read_outstanding;
endmodule
