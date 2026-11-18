// 125 MHz clients -> vendor DDR user clock. One word per mailbox transaction.
// WR ack is returned after both command and data acceptance (not FIFO enqueue).
// Address input is bytes; vendor DDR address unit is 16 bits.
module hxa_ddr_store(
    input wire clk,rst_n,wr_valid,input wire [20:0] wr_byte_addr,
    input wire [127:0] wr_data,output wire wr_ready,wr_idle,
    input wire rd_req,input wire [20:0] rd_byte_addr,
    output wire rd_ready,output reg rd_valid,output reg [127:0] rd_data,
    input wire ddr_clk,ddr_rst_n,calibrated,
    output wire [24:0] app_addr,output wire [2:0] app_cmd,
    output wire app_en,output wire [127:0] app_wdf_data,
    output wire app_wdf_end,output wire [15:0] app_wdf_mask,output wire app_wdf_wren,
    input wire app_rdy,app_wdf_rdy,app_rd_data_valid,input wire [127:0] app_rd_data
);
    reg wreq,rreq,wack,rack;
    reg [1:0] wack_sync,rack_sync,wreq_sync,rreq_sync,cal_sync;
    reg [20:0] waddr_hold,raddr_hold;
    reg [127:0] wdata_hold,rdata_hold;
    reg rack_seen;
    assign wr_ready=(wreq==wack_sync[1])&&cal_sync[1];
    assign wr_idle=(wreq==wack_sync[1]);
    assign rd_ready=(rreq==rack_seen)&&cal_sync[1]&&wr_idle&&!wr_valid;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wreq<=0;rreq<=0;wack_sync<=0;rack_sync<=0;cal_sync<=0;rack_seen<=0;
            waddr_hold<=0;raddr_hold<=0;wdata_hold<=0;rd_data<=0;rd_valid<=0;
        end else begin
            wack_sync<={wack_sync[0],wack};rack_sync<={rack_sync[0],rack};
            cal_sync<={cal_sync[0],calibrated};rd_valid<=0;
            if(wr_valid&&wr_ready) begin waddr_hold<=wr_byte_addr;wdata_hold<=wr_data;wreq<=~wreq;end
            if(rd_req&&rd_ready) begin raddr_hold<=rd_byte_addr;rreq<=~rreq;end
            if(rack_seen!=rack_sync[1]) begin rd_data<=rdata_hold;rd_valid<=1;rack_seen<=rack_sync[1];end
        end
    end
    localparam IDLE=0,WRITE=1,READ=2,RESPONSE=3;
    reg [1:0] state;
    reg command_accepted,data_accepted;
    assign app_addr={5'd0,((state==WRITE)?waddr_hold[20:1]:raddr_hold[20:1])};
    assign app_cmd=(state==WRITE)?3'b000:3'b001;
    // Command/data are independent ready/valid channels. Holding valid until
    // each handshake also works when the controller only asserts ready after
    // seeing valid, and prevents replay if one channel accepts earlier.
    assign app_en=calibrated&&((state==WRITE&&!command_accepted)||(state==READ));
    assign app_wdf_wren=calibrated&&(state==WRITE)&&!data_accepted;
    assign app_wdf_end=app_wdf_wren;
    assign app_wdf_mask=16'd0;
    assign app_wdf_data=wdata_hold;
    always @(posedge ddr_clk or negedge ddr_rst_n) begin
        if(!ddr_rst_n) begin state<=IDLE;wack<=0;rack<=0;wreq_sync<=0;rreq_sync<=0;rdata_hold<=0;command_accepted<=0;data_accepted<=0;end
        else begin
            wreq_sync<={wreq_sync[0],wreq};rreq_sync<={rreq_sync[0],rreq};
            case(state)
                IDLE: if(calibrated) begin
                    if(wreq_sync[1]!=wack)begin state<=WRITE;command_accepted<=0;data_accepted<=0;end
                    else if(rreq_sync[1]!=rack)state<=READ;
                end
                WRITE:begin
                    if(app_en&&app_rdy)command_accepted<=1;
                    if(app_wdf_wren&&app_wdf_rdy)data_accepted<=1;
                    if((command_accepted||(app_en&&app_rdy)) && (data_accepted||(app_wdf_wren&&app_wdf_rdy)))begin wack<=wreq_sync[1];state<=IDLE;end
                end
                READ:if(app_en&&app_rdy)begin
                    if(app_rd_data_valid)begin rdata_hold<=app_rd_data;rack<=rreq_sync[1];state<=IDLE;end
                    else state<=RESPONSE;
                end
                RESPONSE: if(app_rd_data_valid)begin rdata_hold<=app_rd_data;rack<=rreq_sync[1];state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
