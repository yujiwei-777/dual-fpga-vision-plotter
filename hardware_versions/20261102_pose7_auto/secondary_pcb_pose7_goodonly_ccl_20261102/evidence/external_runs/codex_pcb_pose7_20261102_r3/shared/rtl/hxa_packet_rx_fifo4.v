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
    // Queue capacity stays DATA=4 / CONTROL=2. A three-slot physical
    // control ring leaves one uncommitted staging slot, so SETTLE can write
    // its descriptor even while the two committed control entries are full.
    reg [1:0] ctrl_read_slot,ctrl_write_slot;
    reg [1:0] ctrl_count;
    reg [223:0] data_head,control_head;
    reg [63:0] control_body_head;
    reg data_head_ready,control_head_ready;
    reg descriptor_fetch,fetch_control,fetch_capture;
    reg [2:0] fetch_slot;
    reg [4:0] fetch_word;
    wire [15:0] descriptor_q;
    function [1:0] next_ctrl_slot;
        input [1:0] slot;
        begin next_ctrl_slot=(slot==2)?2'd0:slot+1'b1; end
    endfunction

    wire queue_full=(fifo_count==3'd4);
    wire queue_empty=(fifo_count==3'd0);
    wire pop_event=packet_take&&!queue_empty&&data_head_ready&&!flush;
    wire ctrl_pop=ctrl_take&&ctrl_valid;
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

    // Valid is asserted only after all fields of a single committed head
    // have been prefetched. Never expose a mixed old/new descriptor. Waiting
    // controls block NEW DATA admission just as ready controls take priority
    // in hxa_secondary_link. Retirement of an already accepted DATA head is
    // independent of this admission gate; a flush affects DATA only.
    assign packet_valid=!queue_empty&&data_head_ready&&(ctrl_count==0);
    always @(*) begin
        case(read_slot)
            2'd0:payload_data=mem0_q;
            2'd1:payload_data=mem1_q;
            2'd2:payload_data=mem2_q;
            default:payload_data=mem3_q;
        endcase
    end
    assign msg_type=data_head[47:40];
    assign flags=data_head[63:48];
    assign session_id=data_head[127:64];
    assign frame_id=data_head[159:128];
    assign packet_index=data_head[175:160];
    assign packet_count=data_head[191:176];
    assign payload_len=data_head[207:192];
    assign ctrl_valid=(ctrl_count!=0)&&control_head_ready;
    assign ctrl_type=control_head[47:40];
    assign ctrl_session=control_head[127:64];
    assign ctrl_frame=control_head[159:128];
    assign ctrl_payload_len=control_head[207:192];
    assign ctrl_body=control_body_head;

    // The existing 32-clock SETTLE window serializes an 18-word descriptor.
    // Physical slots 0..3 are DATA, 4..6 CONTROL. Slot 7 is unused. The live
    // parser's header/small_body remain stable during this entire window.
    // Only the unoccupied DATA capture slot or CONTROL staging slot is
    // written; a rejected packet can never modify a committed descriptor.
    wire [2:0] descriptor_write_slot=control_type?
                              {1'b1,ctrl_write_slot}:{1'b0,capture_slot};
    wire descriptor_write=(state==SETTLE)&&(settle_count<18)&&
                   (control_type||(capture_payload_ok&&!capture_flushed&&!flush));
    wire [287:0] descriptor_image={small_body,header};
    wire [15:0] descriptor_d=descriptor_image[{settle_count[4:0],4'b0000}+:16];
    wire [9:0] descriptor_write_addr={2'b00,descriptor_write_slot,settle_count[4:0]};
    wire [9:0] descriptor_read_addr={2'b00,fetch_slot,fetch_word};
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(16),.DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),.OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC")
    ) descriptor_ram (
        .dia(descriptor_d),.addra(descriptor_write_addr),.cea(1'b1),.ocea(1'b0),
        .clka(clk),.wea(descriptor_write),.rsta(1'b0),.bea(1'b0),
        .dib(16'd0),.addrb(descriptor_read_addr),.ceb(descriptor_fetch),.oceb(1'b0),
        .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
        .dob(descriptor_q),.doa(),.ecc_sbiterr(),.ecc_dbiterr(),
        .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
    );

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            data_head<=0;control_head<=0;control_body_head<=0;
            data_head_ready<=0;control_head_ready<=0;
            descriptor_fetch<=0;fetch_control<=0;fetch_capture<=0;
            fetch_slot<=0;fetch_word<=0;
        end else begin
            if(pop_event) data_head_ready<=0;
            if(ctrl_pop) control_head_ready<=0;
            if(!descriptor_fetch) begin
                if(ctrl_count!=0&&!control_head_ready) begin
                    descriptor_fetch<=1;fetch_control<=1;fetch_capture<=0;
                    fetch_slot<={1'b1,ctrl_read_slot};fetch_word<=2;
                end else if(!queue_empty&&!data_head_ready&&!flush) begin
                    descriptor_fetch<=1;fetch_control<=0;fetch_capture<=0;
                    fetch_slot<={1'b0,read_slot};fetch_word<=2;
                end
            end else if(!fetch_capture) begin
                // One clock for the synchronous RAM output to settle.
                fetch_capture<=1;
            end else begin
                if(fetch_control) begin
                    if(fetch_word<14)control_head[{fetch_word,4'b0000}+:16]<=descriptor_q;
                    else control_body_head[{fetch_word[1:0]-2'd2,4'b0000}+:16]<=descriptor_q;
                end else data_head[{fetch_word,4'b0000}+:16]<=descriptor_q;
                fetch_capture<=0;
                if((fetch_control&&fetch_word==17)||(!fetch_control&&fetch_word==12)) begin
                    descriptor_fetch<=0;
                    if(fetch_control)control_head_ready<=1;
                    else data_head_ready<=1;
                end else fetch_word<=fetch_word+1'b1;
            end
            if(flush) begin
                data_head_ready<=0;
                if(descriptor_fetch&&!fetch_control) begin
                    descriptor_fetch<=0;fetch_capture<=0;
                end
            end
        end
    end

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
            ctrl_read_slot<=0;ctrl_write_slot<=0;ctrl_count<=0;
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
                ctrl_write_slot<=next_ctrl_slot(ctrl_write_slot);
                if(header[47:40]!=8'd11)begin
                    ctrl_event<=1;ctrl_event_session<=header[127:64];
                end
            end
            if(ctrl_pop)ctrl_read_slot<=next_ctrl_slot(ctrl_read_slot);

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
