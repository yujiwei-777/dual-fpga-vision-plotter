`timescale 1ns/1ps
// Actual byte packets traverse production packet CRC/FIFO/link logic. To
// isolate final-frame admission, the completed DATA staging count is deposited
// after FRAME_BEGIN. All 115200 DDR words are then really read for frame CRC.
// This does not verify reception/writes of all 1280 image DATA fragments.
module tb_pose7_hxa_crc_network;
    `include "pose7_hxa_constants.svh"
    localparam [63:0] SID_A=64'h1122334455667788,SID_B=64'h8877665544332211;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,phy_ready=1,rx_valid=0;
    reg [7:0] rx_data=0;reg [15:0] rx_len=0;
    reg udp_busy=0;
    wire udp_req,udp_valid,online,vision_start,vision_cancel,vision_job_cancel;
    wire grbl_test_start,grbl_current_start;
    wire [7:0] udp_data;wire [15:0] udp_len;
    wire [63:0] session_id;
    wire [31:0] vision_frame_id,vision_job_id,grbl_test_job_id;
    wire [31:0] good_frames,bad_frames;
    reg job_busy=0;
    wire rd_req;wire [20:0] rd_byte_addr;
    reg rd_valid=0,rd_pending=0;
    integer rd_delay=0,rd_words=0,tx_at=0,tx_drain=0;
    integer starts=0,cancels=0,job_cancels=0,test_starts=0,current_starts=0,cases=0;
    reg [7:0] bytes[0:1471],body[0:63];
    string case_name="initial";
    hxa_secondary_link #(.CLK_HZ(125000000),.CAPABILITIES(8'hdf),.FRAME_CRC_BYTES_PER_CYCLE(4),.PRESERVE_VISION_DRAIN(1)) dut(
        .clk(clk),.rst_n(rst_n),.enable(1'b1),.phy_ready(phy_ready),.board_mode(1'b0),
        .udp_req(udp_req),.udp_valid(udp_valid),.udp_data(udp_data),.udp_len(udp_len),.udp_busy(udp_busy),
        .rx_valid(rx_valid),.rx_data(rx_data),.rx_len(rx_len),.rx_error(1'b0),.stack_reset(),
        .wr_valid(),.wr_byte_addr(),.wr_data(),.wr_ready(1'b1),.wr_idle(1'b1),
        .rd_req(rd_req),.rd_byte_addr(rd_byte_addr),.rd_ready(1'b1),.rd_valid(rd_valid),.rd_data(128'd0),
        .vision_start(vision_start),.vision_cancel(vision_cancel),.vision_job_cancel(vision_job_cancel),
        .vision_frame_id(vision_frame_id),.vision_job_id(vision_job_id),.vision_purpose(),.vision_paper_width_px(),.vision_teach_good(),
        .grbl_test_start(grbl_test_start),.grbl_test_job_id(grbl_test_job_id),.grbl_current_start(grbl_current_start),.grbl_current_job_id(),
        .vision_busy(1'b0),.vision_done(1'b0),.vision_result(512'd0),.vision_result_type(8'd18),.vision_result_multibox(640'd0),.vision_maze_result(1792'd0),
        .v_rd_req(1'b0),.v_rd_byte_addr(21'd0),.v_drain_lock(1'b0),.v_rd_ready(),.v_rd_valid(),.v_rd_data(),
        .cfg_we(),.cfg_addr(),.cfg_data(),.cfg_commit(),.cfg_version(),.cfg_ready(1'b1),
        .cfg_begin(),.cfg_abort(),.cfg_total_bytes(),.cfg_pending_version(),.cfg_expected_crc32(),.cfg_good_count(),.cfg_bad_count(),
        .cfg_apply_ack(1'b0),.cfg_apply_error(1'b0),.station_header(256'd0),.station_valid(1'b0),.station_config_version(32'd0),
        .job_status_valid(1'b0),.job_status_data(96'd0),.job_status_ready(),.job_busy(job_busy),
        .session_id(session_id),.online(online),.good_frames(good_frames),.bad_frames(bad_frames),.copy_rearm());
    function [31:0] crc_byte(input [31:0] c,input [7:0] b);
        reg [31:0] q;integer j;
        begin q=c^b;for(j=0;j<8;j=j+1)q=q[0]?((q>>1)^32'hedb88320):(q>>1);crc_byte=q;end
    endfunction
    task fail(input string message);begin
        $display("HXA_FAIL case=%s state=%0d %s",case_name,dut.state,message);$fatal(1,"HXA CRC/network regression");end
    endtask
    task pass;begin cases=cases+1;$display("POSE7_HXA_CASE_PASS name=%s",case_name);end endtask
    task tick(input integer count);begin repeat(count)@(negedge clk);end endtask
    always @(posedge clk)begin
        if(!rst_n)begin
            udp_busy<=0;tx_at=0;tx_drain=0;rd_valid<=0;rd_pending<=0;rd_delay<=0;
            starts=0;cancels=0;job_cancels=0;test_starts=0;current_starts=0;rd_words=0;
        end else begin
            if(vision_start)starts=starts+1;
            if(vision_cancel)cancels=cancels+1;
            if(vision_job_cancel)job_cancels=job_cancels+1;
            if(grbl_test_start)test_starts=test_starts+1;
            if(grbl_current_start)current_starts=current_starts+1;
            if(udp_req&&!udp_busy)begin udp_busy<=1;tx_at=0;end
            if(udp_valid)begin
                if(tx_at==udp_len-1)tx_drain=2;else tx_at=tx_at+1;
            end else if(tx_drain>0)begin tx_drain=tx_drain-1;if(tx_drain==0)udp_busy<=0;end
            rd_valid<=0;
            if(rd_pending)begin
                if(rd_delay==0)begin rd_valid<=1;rd_pending<=0;end else rd_delay<=rd_delay-1;
            end
            if(rd_req)begin
                if(rd_pending||rd_valid)fail("overlapping DDR read transactions");
                if(rd_byte_addr[3:0]!=0||rd_byte_addr>=1843200)fail("DDR address out of frame");
                if(rd_byte_addr!==rd_words*16)fail("CRC word scan address/order mismatch");
                rd_words=rd_words+1;rd_pending<=1;rd_delay<=1;
            end
        end
    end
    task clear_body;begin for(integer j=0;j<64;j=j+1)body[j]=0;end endtask
    task inject(input integer typ,input [63:0] sid,input [31:0] frame,input integer len,input integer count,input bit corrupt);
        reg [223:0] header;reg [31:0] crc;integer j,n;
        begin
            header={16'd0,16'(len),16'(count),16'd0,frame,sid,16'd0,8'(typ),8'd1,32'h31415848};crc=32'hffffffff;
            for(j=0;j<28;j=j+1)begin bytes[j]=header[j*8+:8];crc=crc_byte(crc,bytes[j]);end
            for(j=0;j<len;j=j+1)begin bytes[j+28]=body[j];crc=crc_byte(crc,body[j]);end
            crc=~crc;if(corrupt)crc=crc^1;
            for(j=0;j<4;j=j+1)bytes[j+28+len]=crc[j*8+:8];
            for(j=0;j<len+32;j=j+1)begin @(negedge clk);rx_valid=1;rx_data=bytes[j];rx_len=len+32;end
            @(negedge clk);rx_valid=0;tick(100);n=0;
            while((dut.state!=dut.IDLE||dut.rx.fifo_count!=0||dut.rx.ctrl_count!=0||dut.tx_busy||udp_busy)&&n<1500000)begin tick(1);n=n+1;end
            if(n>=1500000)fail("packet processing failed to quiesce");tick(4);
        end
    endtask
    task hello(input [63:0] sid);begin
        clear_body();body[0]=1;body[1]=8'hdf;inject(1,sid,0,8,0,0);
        if(!online||session_id!==sid)fail("HELLO session not established");end
    endtask
    task reset_link;begin
        @(negedge clk);rst_n=0;phy_ready=1;job_busy=0;rx_valid=0;
        tick(5);rst_n=1;tick(5);hello(SID_A);end
    endtask
    task frame_begin(input [31:0] frame,input bit corrupt);
        reg [127:0] meta;begin
            clear_body();meta={frame,32'd1843200,16'd0,8'd1,8'd1,16'd720,16'd1280};
            for(integer j=0;j<16;j=j+1)body[j]=meta[j*8+:8];inject(3,SID_A,frame,16,1280,corrupt);
        end
    endtask
    task frame_end(input [31:0] frame,input [31:0] framecrc,input bit packet_corrupt);begin
        clear_body();for(integer j=0;j<4;j=j+1)body[j]=framecrc[j*8+:8];inject(5,SID_A,frame,4,0,packet_corrupt);end
    endtask
    task start_local_report(input [31:0] id);begin
        clear_body();body[0]=1;inject(20,SID_A,id,4,0,0);
        if(test_starts!=1||grbl_test_job_id!==id)fail("Type20 task not accepted exactly once");job_busy=1;tick(2);
        inject(20,SID_A,id,4,0,0);if(test_starts!=1)fail("duplicate Type20 replayed task");end
    endtask
    task cancel_packet(input [63:0] sid,input [31:0] frame,input integer reason,input integer len);begin
        clear_body();body[0]=8'h48;body[1]=8'h58;body[2]=8'h44;body[3]=8'h31;body[4]=1;body[5]=reason;
        inject(11,sid,frame,len,0,0);end
    endtask
    initial begin
        reset_link();case_name="bad_FRAME_BEGIN_packet_CRC";frame_begin(100,1);
        if(dut.frame_active||starts!=0)fail("bad packet CRC admitted frame");pass();
        case_name="bad_FRAME_END_packet_CRC";frame_begin(101,0);
        if(!dut.frame_active)fail("valid FRAME_BEGIN not accepted");
        // Isolate post-staging CRC admission without faking the CRC result.
        @(negedge clk);dut.received_count=1280;
        frame_end(101,ZERO_FRAME_CRC,1);if(starts!=0||rd_words!=0)fail("bad END packet CRC started scan/inference");pass();
        case_name="complete_DDR_frame_bad_CRC";frame_end(101,ZERO_FRAME_CRC^1,0);
        if(starts!=0||good_frames!=0||bad_frames==0||rd_words!=115200)fail("wrong full-frame CRC admitted inference or incomplete scan");pass();
        reset_link();case_name="complete_DDR_frame_correct_CRC";frame_begin(102,0);
        @(negedge clk);dut.received_count=1280;
        frame_end(102,ZERO_FRAME_CRC,0);
        if(starts!=1||good_frames!=1||rd_words!=115200)fail("CRC-correct full frame did not start once");pass();
        reset_link();start_local_report(501);case_name="ordinary_empty_Type11_busy_job_preserved";
        begin integer jc,c;jc=job_cancels;c=cancels;cancel_packet(SID_A,501,0,0);
            if(job_cancels!=jc||cancels!=c||!dut.grbl_test_active||test_starts!=1)fail("empty Type11 cancelled/replayed busy task");pass();end
        case_name="ordinary_HXD1_Type11_busy_job_preserved";
        begin integer jc,c;jc=job_cancels;c=cancels;cancel_packet(SID_A,501,4,28);
            if(job_cancels!=jc||cancels!=c||!dut.grbl_test_active)fail("transport Type11 cancelled busy task");pass();end
        case_name="PHY_drop_busy_job_preserved";
        begin integer jc,c;jc=job_cancels;c=cancels;phy_ready=0;tick(5);
            if(job_cancels!=jc||cancels!=c||!dut.grbl_test_active||test_starts!=1)fail("PHY loss cancelled/replayed task");
            phy_ready=1;tick(5);hello(SID_A);if(job_cancels!=jc||test_starts!=1)fail("PHY reopen replayed task");pass();end
        case_name="lease_expiry_busy_job_preserved";
        begin integer jc,c;jc=job_cancels;c=cancels;@(negedge clk);dut.lease_ms=3000;tick(3);
            if(online||job_cancels!=jc||cancels!=c||!dut.grbl_test_active)fail("lease expiry cancelled busy task");
            hello(SID_A);if(job_cancels!=jc||test_starts!=1)fail("lease reopen replayed task");pass();end
        case_name="HELLO_session_change_busy_job_preserved";
        begin integer jc,c;jc=job_cancels;c=cancels;hello(SID_B);
            if(job_cancels!=jc||cancels!=c||!dut.grbl_test_active||test_starts!=1)fail("new session cancelled/replayed task");pass();end
        case_name="wrong_session_Type11_rejected";
        begin integer jc;jc=job_cancels;cancel_packet(SID_A,501,128,28);
            if(job_cancels!=jc||!dut.grbl_test_active)fail("wrong-session cancel accepted");pass();end
        case_name="explicit_reason80_Type11_cancels";
        begin integer jc;jc=job_cancels;cancel_packet(SID_B,501,128,28);
            if(job_cancels!=jc+1||dut.grbl_test_active)fail("authenticated explicit cancel failed");pass();end
        reset_link();start_local_report(502);case_name="baseline_explicit_wrong_frameID_audit";
        begin integer jc;jc=job_cancels;cancel_packet(SID_A,32'hffff0050,128,28);
            // Existing wire contract has no task-ID match at this boundary.
            // Record its inherited limitation; do not label this a security/
            // task-ID-validation pass or silently change the protocol.
            if(job_cancels!=jc+1)fail("baseline explicit cancel behavior changed unexpectedly");
            $display("POSE7_HXA_BASELINE_LIMITATION explicit_reason80_authenticated_session_accepts_nonmatching_frame_ID=1");end
        $display("POSE7_HXA_CRC_NETWORK_PASS cases=%0d",cases);$finish;
    end
    initial begin #100000000;$fatal(1,"HXA global timeout");end
endmodule
