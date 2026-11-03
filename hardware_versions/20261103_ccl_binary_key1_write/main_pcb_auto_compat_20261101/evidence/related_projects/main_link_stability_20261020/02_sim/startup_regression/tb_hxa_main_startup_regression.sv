`timescale 1ns/1ps
// Actual main link and packet codec, with deterministic snapshot/MAC/peer
// endpoint models. No DUT internal register is driven or forced by this TB.
module tb_hxa_main_startup_regression;
    parameter integer FAULT_KIND=0;
    localparam integer TEST_CLK_HZ=10000000;
    reg clk=0,rst_n=0,enable=1,phy_ready=1,pcb_mode=0,detect_enable=1;
    reg snapshot_error=0,packet_error=0,rx_error=0;
    reg allow_capture=1,stall_snapshot=0,snapshot_active=0,snapshot_ready=0;
    wire snapshot_busy=snapshot_active || !allow_capture;
    reg [31:0] snapshot_frame_id=0;
    wire capture_req,capture_cancel,capture_release,background_capture;
    wire packet_req,packet_ready; wire [10:0] packet_index;
    reg packet_busy=0,packet_valid=0,packet_last=0;
    reg [7:0] packet_data=0; integer payload_at=0;
    reg [10:0] model_packet_index=0;
    wire udp_req,udp_valid,stack_reset; wire [7:0] udp_data;
    wire [15:0] udp_len; reg udp_busy=0,rx_valid=0,accept_udp=1;
    reg [7:0] rx_data=0; reg [15:0] rx_len=0;
    wire online,result_valid,result_toggle,multi_valid,multi_toggle;
    wire [2:0] multi_count; wire [511:0] result_data,multi_data;
    wire [31:0] result_frame,sent_frames,failed_frames,multi_job;
    wire [255:0] station_header;wire station_commit;wire [7:0] job_state;
    hxa_main_link #(.CLK_HZ(TEST_CLK_HZ),.PACKET_GAP_CYCLES(400),
        .ORDINARY_MIN_INTERVAL_MS(0),.HELLO_CAPABILITIES(8'h43)) dut(
        .clk(clk),.rst_n(rst_n),.enable(enable),.phy_ready(phy_ready),
        .pcb_mode(pcb_mode),.detect_enable(detect_enable),
        .text_mode(1'b0),.text_trigger(1'b0),.maze_mode(1'b0),.maze_trigger(1'b0),
        .report_request(1'b0),.background_valid(1'b1),.pcb_trigger(1'b0),
        .pcb_present(1'b0),.teach_good(1'b0),
        .capture_req(capture_req),.capture_cancel(capture_cancel),
        .capture_release(capture_release),.background_capture(background_capture),
        .snapshot_busy(snapshot_busy),.snapshot_ready(snapshot_ready),
        .snapshot_error(snapshot_error),.snapshot_frame_id(snapshot_frame_id),
        .snapshot_diag(128'd0),.packet_req(packet_req),.packet_index(packet_index),
        .packet_busy(packet_busy),.packet_valid(packet_valid),.packet_last(packet_last),
        .packet_error(packet_error),.packet_data(packet_data),.packet_ready(packet_ready),
        .udp_req(udp_req),.udp_valid(udp_valid),.udp_data(udp_data),.udp_len(udp_len),
        .udp_busy(udp_busy),.rx_valid(rx_valid),.rx_data(rx_data),.rx_len(rx_len),
        .rx_error(rx_error),.stack_reset(stack_reset),.online(online),
        .result_valid(result_valid),.result_toggle(result_toggle),.result_data(result_data),
        .result_frame(result_frame),.sent_frames(sent_frames),.failed_frames(failed_frames),
        .station_header(station_header),.station_commit(station_commit),.station_ready(1'b1),
        .job_state(job_state),.multi_valid(multi_valid),.multi_toggle(multi_toggle),
        .multi_count(multi_count),.multi_data(multi_data),.multi_job(multi_job));
    // Accelerate only the codec's external MAC-request watchdog. Its actual
    // timeout/error/stack-reset FSM is still exercised without forcing it.
    defparam dut.tx.REQUEST_TIMEOUT=50000;
    always #4 clk=~clk;
    function automatic [31:0] crc_byte(input [31:0] c0,input [7:0] b);
        reg [31:0] c;integer j;
        begin c=c0^b;for(j=0;j<8;j=j+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc_byte=c;end
    endfunction
    reg [7:0] txbytes[0:1471],body[0:223],wirebytes[0:1471];
    integer out_at=0,data_packets=0,frame_begins=0,frame_ends=0,acks=0;
    integer cancels=0,heartbeats=0,invalid_flag_checks=0,hello_packets=0;
    reg [31:0] packet_crc=32'hffffffff,frame_crc=32'hffffffff;
    reg [63:0] peer_session=0;reg [31:0] peer_frame=0,peer_job=0;
    reg [31:0] queue_crc[0:1023],queue_job[0:1023];
    integer queue_type[0:1023],qhead=0,qtail=0;
    reg [63:0] queue_session[0:1023];reg [31:0] queue_frame[0:1023];
    reg drop_peer=0,bad_frame_ack_pending=0;integer result_kind=1;
    integer bad_frame_ack_checks=0;
    reg [31:0] last_ack_job=0,last_ack_frame=0;
    function automatic [31:0] u32(input integer at);
        begin u32={txbytes[at+3],txbytes[at+2],txbytes[at+1],txbytes[at]};end
    endfunction
    task automatic queue(input integer typ,input [63:0] sid,input [31:0] fid);
        begin
            queue_type[qtail]=typ;queue_session[qtail]=sid;queue_frame[qtail]=fid;
            queue_crc[qtail]=~frame_crc;queue_job[qtail]=peer_job;qtail=qtail+1;
        end
    endtask
    integer i;
    always @(posedge clk)begin
        if(!rst_n)begin
            snapshot_active<=0;snapshot_ready<=0;snapshot_frame_id<=0;
            packet_busy<=0;packet_valid<=0;packet_last<=0;payload_at<=0;
            udp_busy<=0;out_at=0;
        end else begin
            if(capture_req)begin
                if(snapshot_busy)$fatal(1,"capture requested while snapshot held");
                snapshot_active<=1;snapshot_ready<=!stall_snapshot;
                snapshot_frame_id<=snapshot_frame_id+1'b1;
            end
            if(capture_cancel||capture_release)begin
                snapshot_active<=0;snapshot_ready<=0;packet_busy<=0;packet_valid<=0;
            end
            if(packet_req)begin
                if(!snapshot_ready||packet_busy)$fatal(1,"bad snapshot packet request");
                packet_busy<=1;packet_valid<=1;packet_last<=0;payload_at<=0;
                model_packet_index<=packet_index;packet_data<=packet_index[7:0];
            end else if(packet_valid&&packet_ready)begin
                if(payload_at==1439)begin packet_valid<=0;packet_busy<=0;packet_last<=0;end
                else begin
                    payload_at<=payload_at+1;packet_data<=(model_packet_index+payload_at+1)&255;
                    packet_last<=payload_at==1438;
                end
            end
            if(udp_req&&!udp_busy&&accept_udp)begin udp_busy<=1;out_at=0;packet_crc=32'hffffffff;end
            if(udp_valid)begin
                txbytes[out_at]=udp_data;packet_crc=crc_byte(packet_crc,udp_data);
                if(out_at==udp_len-1)begin
                    udp_busy<=0;
                    if(packet_crc!==32'hdebb20e3||u32(0)!==32'h31415848)
                        $fatal(1,"outgoing packet framing/CRC");
                    peer_session={u32(12),u32(8)};peer_frame=u32(16);
                    case(txbytes[5])
                        1:begin hello_packets=hello_packets+1;queue(1,peer_session,peer_frame);end
                        3:begin
                            frame_begins=frame_begins+1;peer_job=u32(40);
                            frame_crc=32'hffffffff;queue(2,peer_session,peer_frame);
                        end
                        4:begin
                            if({txbytes[23],txbytes[22]}!=1280||udp_len!=1472)
                                $fatal(1,"DATA format changed");
                            for(i=0;i<1440;i=i+1)frame_crc=crc_byte(frame_crc,txbytes[28+i]);
                            data_packets=data_packets+1;
                        end
                        5:begin
                            if(u32(28)!==~frame_crc)$fatal(1,"FRAME_END CRC mismatch");
                            frame_ends=frame_ends+1;allow_capture=0;queue(7,peer_session,peer_frame);
                        end
                        10:begin heartbeats=heartbeats+1;queue(10,peer_session,peer_frame);end
                        11:cancels=cancels+1;
                        19:begin acks=acks+1;last_ack_job=u32(28);last_ack_frame=peer_frame;end
                        default:;
                    endcase
                end
                out_at=out_at+1;
            end
        end
    end
    task automatic clear_body;
        integer n;begin for(n=0;n<224;n=n+1)body[n]=0;end
    endtask
    task automatic put32(input integer at,input [31:0] value);
        integer n;begin for(n=0;n<4;n=n+1)body[at+n]=value[n*8+:8];end
    endtask
    task automatic inject(input integer typ,input [63:0] sid,input [31:0] fid,
                          input integer len,input bit bad_crc=0);
        reg [223:0] head;reg [31:0] crc;integer n;
        begin
            head={16'd0,16'(len),16'd0,16'd0,fid,sid,16'd0,8'(typ),8'd1,32'h31415848};
            crc=32'hffffffff;
            for(n=0;n<28;n=n+1)begin wirebytes[n]=head[n*8+:8];crc=crc_byte(crc,wirebytes[n]);end
            for(n=0;n<len;n=n+1)begin wirebytes[28+n]=body[n];crc=crc_byte(crc,body[n]);end
            crc=~crc;if(bad_crc)crc=crc^1;
            for(n=0;n<4;n=n+1)wirebytes[28+len+n]=crc[n*8+:8];
            for(n=0;n<len+32;n=n+1)begin @(negedge clk);rx_valid=1;rx_data=wirebytes[n];rx_len=len+32;end
            @(negedge clk);rx_valid=0;repeat(230)@(negedge clk);
        end
    endtask
    task automatic make_multibox(input [31:0] jid,input [7:0] flags,input integer count);
        begin
            clear_body();put32(0,jid);body[12]=flags;body[13]=count;
            if(count!=0)begin
                body[16]=100;body[18]=120;body[20]=44;body[21]=1;
                body[22]=144;body[23]=1;body[24]=8;body[26]=25;
                put32(28,56000);
            end
        end
    endtask
    integer qt;reg [63:0] qs;reg [31:0] qf,qc,qj;
    initial forever begin
        @(negedge clk);
        if(rst_n&&qhead<qtail)begin
            qt=queue_type[qhead];qs=queue_session[qhead];qf=queue_frame[qhead];
            qc=queue_crc[qhead];qj=queue_job[qhead];qhead=qhead+1;
            if(!drop_peer)begin
                clear_body();
                case(qt)
                    1:begin body[0]=2;body[1]=8'h4d;inject(2,qs,qf,8);end
                    2:inject(2,qs,qf,0);
                    10:inject(10,qs,qf,0);
                    18:begin make_multibox(qj,8'h41,1);inject(18,qs,qf,80);end
                    7:begin
                        if(bad_frame_ack_pending)begin
                            put32(0,qc^1);inject(7,qs,qf,4);
                            if(!snapshot_active||dut.ack_seen||dut.state!=7)
                                $fatal(1,"bad whole-frame CRC ACK released snapshot or left WAIT_ACK");
                            bad_frame_ack_pending=0;bad_frame_ack_checks=bad_frame_ack_checks+1;
                        end else begin
                          put32(0,qc);inject(7,qs,qf,4);
                          if(result_kind==2)begin
                            if(!multi_valid)$fatal(1,"old box absent before malformed-result test");
                            make_multibox(qj,8'h49,1);inject(18,qs,qf,80);
                            if(!multi_valid||1'b0)
                                $fatal(1,"illegal flags accepted or old box cleared immediately");
                            invalid_flag_checks=invalid_flag_checks+1;
                            make_multibox(qj,8'h80,0);inject(18,qs,qf,80);
                          end else begin make_multibox(qj,8'h41,1);inject(18,qs,qf,80);end
                        end
                    end
                    default:;
                endcase
            end
        end
    end
    task automatic wait_ms(input integer n);
        integer x;begin for(x=0;x<n;x=x+1)begin @(negedge clk);wait(dut.tick_ms);@(negedge clk);end end
    endtask
    integer hello_before;
    initial begin
        // Deliberately delay/drop the first READY: real startup may overlap
        // mode synchronization or a MAC request failure before discovery.
        detect_enable=0;allow_capture=0;drop_peer=1;
        if(FAULT_KIND==2)accept_udp=0;
        repeat(10)@(negedge clk);rst_n=1;
        if(FAULT_KIND==2)begin
            wait(stack_reset);@(negedge clk);accept_udp=1;
            $display("INJECT first HELLO MAC request timeout state=%0d online=%0d",dut.state,online);
        end else begin
            wait(hello_packets==1);repeat(20)@(negedge clk);
            if(FAULT_KIND==0)begin
                @(negedge clk);pcb_mode=1;
                $display("INJECT mode sync after first HELLO before READY state=%0d online=%0d",dut.state,online);
            end else begin
                @(negedge clk);snapshot_error=1;
                $display("INJECT offline snapshot_error pulse state=%0d online=%0d",dut.state,online);
                @(negedge clk);snapshot_error=0;
            end
        end
        wait(cancels>=1);repeat(50)@(negedge clk);
        hello_before=hello_packets;drop_peer=0;
        $display("PEER available after CANCEL state=%0d online=%0d HELLO=%0d",dut.state,online,hello_packets);
        wait_ms(400);
        $display("OBSERVED state=%0d online=%0d HELLO=%0d heartbeats=%0d cancels=%0d session=%h",dut.state,online,hello_packets,heartbeats,cancels,dut.session);
        if(!online||hello_packets<=hello_before)
            $fatal(1,"STARTUP RECOVERY FAILURE: no rediscovery after offline CANCEL; fault_kind=%0d state=%0d HELLO=%0d",FAULT_KIND,dut.state,hello_packets);
        $display("PASS tb_hxa_main_startup_regression FAULT_KIND=%0d recovery HELLO=%0d",FAULT_KIND,hello_packets);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"watchdog state=%0d online=%0d HELLO=%0d cancels=%0d",dut.state,online,hello_packets,cancels);
    end
endmodule
