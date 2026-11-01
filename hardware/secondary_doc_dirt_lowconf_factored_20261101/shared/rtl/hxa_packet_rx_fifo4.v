// Four-slot packet-level receive queue for the HXA1 secondary link.
//
// The UDP stack presents one byte stream at a time.  This module captures a
// complete, CRC-checked HXA packet into one of four BRAM payload slots and
// exposes the oldest packet through the same interface as hxa_packet_rx.
// Packet capture is therefore independent from DDR/vision consumption.  The
// wire packet format is unchanged; packet_take only retires the queue head.
// CRC-validated HELLO and heartbeat packets use a separate two-entry queue,
// even when all DATA slots are occupied. Flush clears DATA traffic only.
module hxa_packet_rx_fifo4 #(
    parameter integer MAX_PAYLOAD=1440,
    parameter integer PACKET_TIMEOUT=125000
)(
    input wire clk,rst_n,
    input wire udp_valid,input wire [7:0] udp_data,input wire [15:0] udp_len,
    input wire udp_error,
    input wire flush,
    output wire packet_valid,input wire packet_take,
    output wire [7:0] msg_type,output wire [15:0] flags,
    output wire [63:0] session_id,output wire [31:0] frame_id,
    output wire [15:0] packet_index,packet_count,payload_len,
    input wire [10:0] payload_addr,output reg [7:0] payload_data,
    output reg packet_error,output reg [31:0] dropped_packets,
    output wire ctrl_valid,input wire ctrl_take,
    output wire [7:0] ctrl_type,output wire [63:0] ctrl_session,
    output wire [31:0] ctrl_frame,output wire [15:0] ctrl_payload_len,
    output wire [63:0] ctrl_body,
    output reg ctrl_event,output reg [63:0] ctrl_event_session
);
    localparam IDLE=0,RECEIVE=1,SETTLE=2,DROP=3;
    reg [1:0] state;
    reg [1:0] capture_slot,read_slot,write_slot;
    reg [2:0] fifo_count;
    reg [223:0] header;
    reg [63:0] small_body;
    reg [15:0] count,length;
    reg [31:0] crc;
    reg bad,capture_payload_ok,capture_flushed;
    reg [5:0] settle_count;
    reg [31:0] timeout_count;
    reg drop_report;

    wire [7:0] mem0_q,mem1_q,mem2_q,mem3_q;
    reg [223:0] header_mem0,header_mem1,header_mem2,header_mem3;
    (* keep = "true", dont_touch = "true" *) reg [3:0] ctrl_read_sel;
    reg ctrl_write_slot;
    reg [1:0] ctrl_count;
    reg [223:0] ctrl_header0,ctrl_header1;
    reg [63:0] ctrl_body0,ctrl_body1;

    wire queue_full=(fifo_count==3'd4);
    wire queue_empty=(fifo_count==3'd0);
    wire pop_event=packet_take&&!queue_empty&&!flush;
    wire ctrl_pop=ctrl_take&&(ctrl_count!=0);
    // A completed packet can use a slot freed on the same clock as a pop.
    wire push_candidate=(state==SETTLE&&settle_count==6'd31);
    wire packet_header_ok=(header[31:0]==32'h31415848 &&
                           header[39:32]==8'd1 && header[223:208]==16'd0 &&
                           ({1'b0,header[207:192]}+17'd32)=={1'b0,length});
    wire packet_good=push_candidate&&!bad&&!udp_error&&packet_header_ok;
    wire control_type=(header[47:40]==8'd1||header[47:40]==8'd10||
                       header[47:40]==8'd11);
    wire hello_ok=(header[47:40]==8'd1&&header[63:48]==0&&
                   header[207:192]==8&&header[127:64]!=0&&
                   header[175:160]==0&&header[191:176]==0&&
                   small_body[7:0]==8'd1&&small_body[31:16]==0);
    wire heartbeat_ok=(header[47:40]==8'd10&&header[63:48]==0&&
                       header[207:192]==0&&header[191:160]==0);
    wire cancel_ok=(header[47:40]==8'd11&&header[63:48]==0&&
                    header[175:160]==0&&header[191:176]==0&&
                    (header[207:192]==0||
                     (header[207:192]==28&&small_body[31:0]==32'h31445848&&
                      small_body[39:32]==8'd1)));
    wire ctrl_accept=packet_good&&(hello_ok||heartbeat_ok||cancel_ok)&&
                     (ctrl_count!=2||ctrl_pop);
    wire packet_accept=packet_good&&!control_type&&capture_payload_ok&&!flush&&
                       (!queue_full||pop_event);
    wire payload_write=state==RECEIVE&&udp_valid&&capture_payload_ok&&!flush&&
                       count>=16'd28&&count<length-16'd4&&count<16'd1472;
    wire [10:0] payload_write_addr=count[10:0]-11'd28;
    wire [2:0] small_body_addr=count[2:0]-3'd4;

    function [31:0] crc_byte;
        input [31:0] c; input [7:0] d; integer j; reg [31:0] t;
        begin
            t=c^{24'd0,d};
            for(j=0;j<8;j=j+1)
                t=t[0]?((t>>1)^32'hedb88320):(t>>1);
            crc_byte=t;
        end
    endfunction

    assign packet_valid=!queue_empty;
    reg [223:0] selected_header;
    wire [7:0] selected_ctrl_type=ctrl_read_sel[0]?ctrl_header1[47:40]:ctrl_header0[47:40];
    wire [63:0] selected_ctrl_session=ctrl_read_sel[1]?ctrl_header1[127:64]:ctrl_header0[127:64];
    wire [31:0] selected_ctrl_frame=ctrl_read_sel[2]?ctrl_header1[159:128]:ctrl_header0[159:128];
    wire [15:0] selected_ctrl_payload_len=ctrl_read_sel[3]?ctrl_header1[207:192]:ctrl_header0[207:192];
    always @(*) begin
        case(read_slot)
            2'd0:begin selected_header=header_mem0;payload_data=mem0_q;end
            2'd1:begin selected_header=header_mem1;payload_data=mem1_q;end
            2'd2:begin selected_header=header_mem2;payload_data=mem2_q;end
            default:begin selected_header=header_mem3;payload_data=mem3_q;end
        endcase
    end
    assign msg_type=selected_header[47:40];
    assign flags=selected_header[63:48];
    assign session_id=selected_header[127:64];
    assign frame_id=selected_header[159:128];
    assign packet_index=selected_header[175:160];
    assign packet_count=selected_header[191:176];
    assign payload_len=selected_header[207:192];
    assign ctrl_valid=(ctrl_count!=0);
    assign ctrl_type=selected_ctrl_type;
    assign ctrl_session=selected_ctrl_session;
    assign ctrl_frame=selected_ctrl_frame;
    assign ctrl_payload_len=selected_ctrl_payload_len;
    assign ctrl_body=ctrl_read_sel[3]?ctrl_body1:ctrl_body0;

    // Explicit dual-port ERAMs avoid failed inference of the byte-wide
    // payload arrays. Port B retains the one-clock read contract used by the
    // DDR consumer; same-address read/write data is ignored until publish.
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),.OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC")
    ) payload_ram0 (
        .dia(udp_data),.addra(payload_write_addr),.cea(1'b1),.ocea(1'b0),
        .clka(clk),.wea(payload_write&&capture_slot==0),.rsta(1'b0),.bea(1'b0),
        .dib(8'd0),.addrb(payload_addr),.ceb(1'b1),.oceb(1'b0),
        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
        .dob(mem0_q),.doa(),.ecc_sbiterr(),.ecc_dbiterr(),
        .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
    );
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),.OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC")
    ) payload_ram1 (
        .dia(udp_data),.addra(payload_write_addr),.cea(1'b1),.ocea(1'b0),
        .clka(clk),.wea(payload_write&&capture_slot==1),.rsta(1'b0),.bea(1'b0),
        .dib(8'd0),.addrb(payload_addr),.ceb(1'b1),.oceb(1'b0),
        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
        .dob(mem1_q),.doa(),.ecc_sbiterr(),.ecc_dbiterr(),
        .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
    );
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),.OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC")
    ) payload_ram2 (
        .dia(udp_data),.addra(payload_write_addr),.cea(1'b1),.ocea(1'b0),
        .clka(clk),.wea(payload_write&&capture_slot==2),.rsta(1'b0),.bea(1'b0),
        .dib(8'd0),.addrb(payload_addr),.ceb(1'b1),.oceb(1'b0),
        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
        .dob(mem2_q),.doa(),.ecc_sbiterr(),.ecc_dbiterr(),
        .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
    );
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"),
        .ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),.OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC")
    ) payload_ram3 (
        .dia(udp_data),.addra(payload_write_addr),.cea(1'b1),.ocea(1'b0),
        .clka(clk),.wea(payload_write&&capture_slot==3),.rsta(1'b0),.bea(1'b0),
        .dib(8'd0),.addrb(payload_addr),.ceb(1'b1),.oceb(1'b0),
        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
        .dob(mem3_q),.doa(),.ecc_sbiterr(),.ecc_dbiterr(),
        .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
    );

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;capture_slot<=0;read_slot<=0;write_slot<=0;fifo_count<=0;
            header<=0;small_body<=0;count<=0;length<=0;crc<=32'hffffffff;bad<=0;
            capture_payload_ok<=0;capture_flushed<=0;
            settle_count<=0;timeout_count<=0;drop_report<=0;
            packet_error<=0;dropped_packets<=0;
            header_mem0<=0;header_mem1<=0;header_mem2<=0;header_mem3<=0;
            ctrl_read_sel<=4'b0000;ctrl_write_slot<=0;ctrl_count<=0;
            ctrl_header0<=0;ctrl_header1<=0;ctrl_body0<=0;ctrl_body1<=0;
            ctrl_event<=0;ctrl_event_session<=0;
        end else begin
            packet_error<=0;ctrl_event<=0;

            // Queue pointer accounting is independent of capture state.  A
            // simultaneous push/pop keeps the count stable and rotates both
            // pointers, allowing DDR to consume while UDP is receiving.
            if(flush)begin
                // Preserve queued/in-flight HELLO and heartbeats. Keep the
                // byte parser synchronized; only DATA state is invalidated.
                read_slot<=0;write_slot<=0;fifo_count<=0;
                capture_payload_ok<=0;capture_flushed<=1;
            end else begin
              case({packet_accept,pop_event})
                2'b10:fifo_count<=fifo_count+1'b1;
                2'b01:fifo_count<=fifo_count-1'b1;
                default:;
              endcase
              if(packet_accept)begin
                case(capture_slot)
                    2'd0:header_mem0<=header;
                    2'd1:header_mem1<=header;
                    2'd2:header_mem2<=header;
                    default:header_mem3<=header;
                endcase
                write_slot<=write_slot+1'b1;
              end
              if(pop_event)read_slot<=read_slot+1'b1;
            end
            case({ctrl_accept,ctrl_pop})
                2'b10:ctrl_count<=ctrl_count+1'b1;
                2'b01:ctrl_count<=ctrl_count-1'b1;
                default:;
            endcase
            if(ctrl_accept)begin
                if(ctrl_write_slot)begin ctrl_header1<=header;ctrl_body1<=small_body;end
                else begin ctrl_header0<=header;ctrl_body0<=small_body;end
                ctrl_write_slot<=!ctrl_write_slot;
                if(header[47:40]!=8'd11)begin
                    ctrl_event<=1;ctrl_event_session<=header[127:64];
                end
            end
            if(ctrl_pop)ctrl_read_sel<=~ctrl_read_sel;

            case(state)
                IDLE:begin
                    if(udp_valid)begin
                            // A full DATA queue still parses CRC/header and
                            // the small control body, without writing RAM.
                            capture_slot<=write_slot;
                            capture_payload_ok<=(!queue_full||pop_event)&&!flush;
                            capture_flushed<=flush;
                            small_body<=0;
                            header<={216'd0,udp_data};count<=16'd1;length<=udp_len;
                            crc<=crc_byte(32'hffffffff,udp_data);timeout_count<=0;
                            bad<=udp_error||udp_len<16'd32||udp_len>MAX_PAYLOAD+16'd32;
                            state<=RECEIVE;
                    end
                end
                RECEIVE:begin
                    if(udp_error)bad<=1;
                    if(udp_valid)begin
                        timeout_count<=0;
                        if(count<16'd28)header[count*8+:8]<=udp_data;
                        if(count>=16'd28&&count<16'd36&&count<length-16'd4)
                            small_body[{small_body_addr,3'b000}+:8]<=udp_data;
                        crc<=crc_byte(crc,udp_data);
                        if(count==length-1'b1)begin
                            if(crc_byte(crc,udp_data)!=32'hdebb20e3)bad<=1;
                            settle_count<=0;state<=SETTLE;
                        end else if(count>=16'd1471)begin
                            bad<=1;drop_report<=1;state<=DROP;
                        end else count<=count+1'b1;
                    end else if(timeout_count==PACKET_TIMEOUT-1)begin
                        packet_error<=1;dropped_packets<=dropped_packets+1'b1;state<=IDLE;
                    end else timeout_count<=timeout_count+1'b1;
                end
                SETTLE:begin
                    if(udp_error)bad<=1;
                    if(settle_count==6'd31)begin
                        if(!packet_accept&&!ctrl_accept&&
                           !((flush||capture_flushed)&&!control_type))begin
                            packet_error<=1;dropped_packets<=dropped_packets+1'b1;
                        end
                        state<=IDLE;
                    end else settle_count<=settle_count+1'b1;
                end
                DROP:begin
                    if(!udp_valid)begin
                        if(drop_report)begin
                            packet_error<=1;dropped_packets<=dropped_packets+1'b1;
                        end
                        drop_report<=0;state<=IDLE;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
