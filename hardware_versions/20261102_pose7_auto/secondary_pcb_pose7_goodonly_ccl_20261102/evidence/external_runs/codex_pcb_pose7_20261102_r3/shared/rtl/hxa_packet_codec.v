// HXA1 packet framing. All ports are in clk domain. The payload RAM is never
// reset; complete length/CRC validation is the only way to publish a packet.
// UDP input/output uses the existing uiudp_stack byte-stream convention.
module hxa_packet_tx #(parameter integer REQUEST_TIMEOUT=12500000)(
    input wire clk,rst_n,
    input wire load_we, input wire [10:0] load_addr, input wire [7:0] load_data,
    input wire start, input wire [7:0] msg_type, input wire [15:0] flags,
    input wire [63:0] session_id, input wire [31:0] frame_id,
    input wire [15:0] packet_index,packet_count,payload_len,
    output wire busy, output reg done,error, output reg stack_reset,
    output wire udp_req, output wire udp_valid, output wire [7:0] udp_data,
    output wire [15:0] udp_len, input wire udp_busy
);
    localparam IDLE=0,HEADER=1,PRIME_CRC=2,SCAN=3,TAIL=4,
               REQUEST=5,PRIME_SEND=6,SEND=7,WAIT_DONE=8,ABORT=9;
    reg [3:0] state;
    (* ram_style="bram" *) reg [7:0] mem[0:2047];
    reg [7:0] rd_data;
    reg [10:0] rd_addr,wr_addr;
    reg [7:0] wr_data;
    reg wr_en;
    reg [223:0] header;
    reg [4:0] hdr_at;
    reg [1:0] tail_at;
    reg [10:0] count,data_length,total_length;
    reg [31:0] crc,crc_final;
    reg [31:0] timeout_count;
    reg [2:0] abort_count;
    function [31:0] crc_byte;
        input [31:0] c; input [7:0] d; integer j; reg [31:0] t;
        begin t=c^{24'd0,d}; for(j=0;j<8;j=j+1)
            t=t[0] ? ((t>>1)^32'hedb88320) : (t>>1); crc_byte=t; end
    endfunction
    assign busy=(state!=IDLE);
    assign udp_req=(state==REQUEST);
    assign udp_valid=(state==SEND);
    assign udp_data=rd_data;
    assign udp_len={5'd0,total_length};
    always @* begin
        wr_en=1'b0;wr_addr=0;wr_data=0;
        if(state==IDLE && load_we && load_addr<1440) begin
            wr_en=1'b1;wr_addr=11'd28+load_addr;wr_data=load_data;
        end else if(state==HEADER) begin
            wr_en=1'b1;wr_addr={6'd0,hdr_at};wr_data=header[7:0];
        end else if(state==TAIL) begin
            wr_en=1'b1;wr_addr=data_length+{9'd0,tail_at};wr_data=crc_final[7:0];
        end
    end
    always @(posedge clk) begin
        if(wr_en)mem[wr_addr]<=wr_data;
        rd_data<=mem[rd_addr];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;header<=0;hdr_at<=0;tail_at<=0;rd_addr<=0;
            count<=0;data_length<=0;total_length<=0;crc<=32'hffffffff;
            crc_final<=0;done<=0;error<=0;stack_reset<=0;timeout_count<=0;abort_count<=0;
        end else begin
            done<=0;error<=0;stack_reset<=0;
            case(state)
                IDLE: if(start) begin
                    if(payload_len>1440)error<=1;
                    else begin
                        header<={16'd0,payload_len,packet_count,packet_index,frame_id,
                                 session_id,flags,msg_type,8'd1,32'h31415848};
                        hdr_at<=0;data_length<=11'd28+payload_len[10:0];
                        total_length<=11'd32+payload_len[10:0];state<=HEADER;
                    end
                end
                HEADER: begin
                    header<={8'd0,header[223:8]};
                    if(hdr_at==27) begin rd_addr<=0;crc<=32'hffffffff;count<=0;state<=PRIME_CRC;end
                    else hdr_at<=hdr_at+1'b1;
                end
                PRIME_CRC:begin rd_addr<=1;state<=SCAN;end
                SCAN:begin
                    crc<=crc_byte(crc,rd_data);
                    if(count==data_length-1'b1)begin
                        crc_final<=~crc_byte(crc,rd_data);tail_at<=0;state<=TAIL;
                    end else begin count<=count+1'b1;rd_addr<=rd_addr+1'b1;end
                end
                TAIL:begin
                    crc_final<={8'd0,crc_final[31:8]};rd_addr<=0;
                    if(tail_at==3)begin state<=REQUEST;timeout_count<=0;end
                    else tail_at<=tail_at+1'b1;
                end
                REQUEST:begin
                    if(udp_busy)begin count<=0;state<=PRIME_SEND;end
                    else if(timeout_count==REQUEST_TIMEOUT-1)begin
                        error<=1;abort_count<=0;state<=ABORT;
                    end else timeout_count<=timeout_count+1'b1;
                end
                PRIME_SEND:begin rd_addr<=1;state<=SEND;end
                SEND:begin
                    if(count==total_length-1'b1)begin timeout_count<=0;state<=WAIT_DONE;end
                    else begin count<=count+1'b1;rd_addr<=rd_addr+1'b1;end
                end
                WAIT_DONE:begin
                    if(!udp_busy)begin done<=1;state<=IDLE;end
                    else if(timeout_count==REQUEST_TIMEOUT-1)begin error<=1;abort_count<=0;state<=ABORT;end
                    else timeout_count<=timeout_count+1'b1;
                end
                ABORT:begin
                    stack_reset<=1;
                    if(abort_count==3)state<=IDLE;else abort_count<=abort_count+1'b1;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule

module hxa_packet_rx #(parameter integer MAX_PAYLOAD=1440,parameter integer PACKET_TIMEOUT=125000)(
    input wire clk,rst_n,
    input wire udp_valid,input wire [7:0] udp_data,input wire [15:0] udp_len,
    input wire udp_error,
    output reg packet_valid,input wire packet_take,
    output wire [7:0] msg_type,output wire [15:0] flags,
    output wire [63:0] session_id,output wire [31:0] frame_id,
    output wire [15:0] packet_index,packet_count,payload_len,
    input wire [10:0] payload_addr,output reg [7:0] payload_data,
    output reg packet_error,output reg [31:0] dropped_packets
);
    localparam IDLE=0,RECEIVE=1,SETTLE=2,HOLD=3,DROP=4;
    reg [2:0] state;
    (* ram_style="bram" *) reg [7:0] mem[0:2047];
    reg [223:0] header;
    reg [15:0] count,length;
    reg [31:0] crc;
    reg bad;
    reg [5:0] settle_count;
    reg [31:0] timeout_count;
    function [31:0] crc_byte;
        input [31:0] c;input [7:0] d;integer j;reg [31:0] t;
        begin t=c^{24'd0,d};for(j=0;j<8;j=j+1)
            t=t[0]?((t>>1)^32'hedb88320):(t>>1);crc_byte=t;end
    endfunction
    assign msg_type=header[47:40];assign flags=header[63:48];
    assign session_id=header[127:64];assign frame_id=header[159:128];
    assign packet_index=header[175:160];assign packet_count=header[191:176];
    assign payload_len=header[207:192];
    always @(posedge clk) begin
        if(state==RECEIVE && udp_valid && count>=28 && count<length-4 && count<1472)
            mem[count[10:0]-11'd28]<=udp_data;
        payload_data<=mem[payload_addr];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;header<=0;count<=0;length<=0;crc<=32'hffffffff;
            bad<=0;packet_valid<=0;packet_error<=0;dropped_packets<=0;
            settle_count<=0;timeout_count<=0;
        end else begin
            packet_error<=0;
            case(state)
                IDLE:if(udp_valid)begin
                    header<={216'd0,udp_data};count<=1;length<=udp_len;
                    crc<=crc_byte(32'hffffffff,udp_data);timeout_count<=0;
                    bad<=udp_error || udp_len<32 || udp_len>MAX_PAYLOAD+32;
                    state<=RECEIVE;
                end
                RECEIVE:begin
                    if(udp_error)bad<=1;
                    if(udp_valid)begin
                        timeout_count<=0;
                        if(count<28)header[count*8+:8]<=udp_data;
                        crc<=crc_byte(crc,udp_data);
                        if(count==length-1'b1)begin
                            if(crc_byte(crc,udp_data)!=32'hdebb20e3)bad<=1;
                            settle_count<=0;state<=SETTLE;
                        end else if(count>=1471)begin bad<=1;state<=DROP;end
                        else count<=count+1'b1;
                    end else if(timeout_count==PACKET_TIMEOUT-1)begin
                        packet_error<=1;dropped_packets<=dropped_packets+1'b1;state<=IDLE;
                    end else timeout_count<=timeout_count+1'b1;
                end
                SETTLE:begin
                    if(udp_error)bad<=1;
                    if(settle_count==31)begin
                        if(!bad && !udp_error && header[31:0]==32'h31415848 &&
                           header[39:32]==1 && header[223:208]==0 &&
                           {1'b0,payload_len}+17'd32=={1'b0,length})begin
                            packet_valid<=1;state<=HOLD;
                        end else begin
                            packet_error<=1;dropped_packets<=dropped_packets+1'b1;state<=IDLE;
                        end
                    end else settle_count<=settle_count+1'b1;
                end
                HOLD:if(packet_take)begin
                    packet_valid<=0;
                    // Do not treat the tail of a concurrently arriving packet as a new header.
                    state<=udp_valid?DROP:IDLE;
                end
                DROP:if(!udp_valid)begin
                    dropped_packets<=dropped_packets+1'b1;packet_error<=1;state<=IDLE;
                end
                default:begin packet_valid<=0;state<=IDLE;end
            endcase
        end
    end
endmodule
