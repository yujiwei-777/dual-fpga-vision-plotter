// Adapted for packed synchronous descriptor prefetch and CONTROL priority.
`timescale 1ns/1ps
module tb_pose7_fifo4;
  reg clk=0,rst_n=0,udp_valid=0,udp_error=0,packet_take=0,flush=0;
  always #4 clk=~clk;
  reg [7:0] udp_data=0;
  reg [15:0] udp_len=0;
  reg [10:0] payload_addr=0;
  wire packet_valid,packet_error;
  wire [7:0] msg_type,payload_data;
  wire [15:0] flags,packet_index,packet_count,payload_len;
  wire [63:0] session_id;
  wire [31:0] frame_id,dropped_packets;
  reg ctrl_take=0;
  wire ctrl_valid,ctrl_event;
  wire [7:0] ctrl_type;
  wire [63:0] ctrl_session,ctrl_body,ctrl_event_session;
  wire [31:0] ctrl_frame;
  wire [15:0] ctrl_payload_len;
  integer control_events=0;
  integer errors=0,checks=0,packet_errors=0;
  integer i,j,before_drop;
  reg [7:0] bytes[0:1471];
  hxa_packet_rx_fifo4 #(.PACKET_TIMEOUT(80)) dut(.*);

  always @(posedge clk) if(packet_error)packet_errors=packet_errors+1;
  always @(posedge clk) if(ctrl_event)control_events=control_events+1;
  function [31:0] crc_byte(input [31:0] c,input [7:0] d);
    reg [31:0] t; integer k;
    begin
      t=c^d;
      for(k=0;k<8;k=k+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);
      crc_byte=t;
    end
  endfunction
  function [7:0] value(input integer seq,input integer at);
    value=(seq*37+at+(at>>8))&255;
  endfunction
  task build(input integer seq,input integer len,input bit corrupt);
    reg [223:0] h;reg [31:0] crc;integer at;
    begin
      h={16'd0,16'(len),16'd1280,16'(seq),32'(100+seq),
         64'h0123456789abcdef,16'h1234,8'd4,8'd1,32'h31415848};
      crc=32'hffffffff;
      for(at=0;at<28;at=at+1)begin bytes[at]=h[at*8+:8];crc=crc_byte(crc,bytes[at]);end
      for(at=0;at<len;at=at+1)begin bytes[28+at]=value(seq,at);crc=crc_byte(crc,bytes[28+at]);end
      crc=~crc;
      if(corrupt)crc=crc^32'd1;
      for(at=0;at<4;at=at+1)bytes[28+len+at]=crc[at*8+:8];
    end
  endtask
  task send(input integer seq,input integer len,input bit corrupt,input integer gap_at);
    integer at;
    begin
      build(seq,len,corrupt);
      for(at=0;at<len+32;at=at+1)begin
        @(negedge clk);udp_valid=1;udp_data=bytes[at];udp_len=len+32;
        if(at==gap_at)begin
          @(negedge clk);udp_valid=0;
          repeat(7)@(negedge clk);
          udp_valid=1;udp_data=bytes[at+1];at=at+1;
        end
      end
      @(negedge clk);udp_valid=0;
      repeat(90)@(negedge clk);
    end
  endtask
  task control(input integer typ,input [63:0] sid,input [63:0] b,
               input integer idx,input integer cnt,input bit corrupt);
    reg [223:0] h;reg [31:0] crc;integer at,len;
    begin
      len=(typ==1)?8:0;
      h={16'd0,16'(len),16'(cnt),16'(idx),32'habcddcba,
         sid,16'd0,8'(typ),8'd1,32'h31415848};
      crc=32'hffffffff;
      for(at=0;at<28;at=at+1)begin bytes[at]=h[at*8+:8];crc=crc_byte(crc,bytes[at]);end
      for(at=0;at<len;at=at+1)begin bytes[at+28]=b[at*8+:8];crc=crc_byte(crc,bytes[at+28]);end
      crc=~crc;if(corrupt)crc=crc^1;
      for(at=0;at<4;at=at+1)bytes[at+28+len]=crc[at*8+:8];
      for(at=0;at<len+32;at=at+1)begin
        @(negedge clk);udp_valid=1;udp_data=bytes[at];udp_len=len+32;
      end
      @(negedge clk);udp_valid=0;repeat(90)@(negedge clk);
    end
  endtask
  task cancel_control(input [63:0] sid,input bit bad_version,input bit bad_crc);
    reg [223:0] h;reg [31:0] crc;integer at;
    begin
      h={16'd0,16'd28,16'd0,16'd0,32'habcddcba,
         sid,16'd0,8'd11,8'd1,32'h31415848};
      crc=32'hffffffff;
      for(at=0;at<28;at=at+1)begin bytes[at]=h[at*8+:8];crc=crc_byte(crc,bytes[at]);end
      bytes[28]=8'h48;bytes[29]=8'h58;bytes[30]=8'h44;bytes[31]=8'h31;
      bytes[32]=bad_version?8'd2:8'd1;bytes[33]=8'd6;
      for(at=34;at<56;at=at+1)bytes[at]=0;
      for(at=28;at<56;at=at+1)crc=crc_byte(crc,bytes[at]);
      crc=~crc;if(bad_crc)crc=crc^1;
      for(at=0;at<4;at=at+1)bytes[56+at]=crc[at*8+:8];
      for(at=0;at<60;at=at+1)begin
        @(negedge clk);udp_valid=1;udp_data=bytes[at];udp_len=60;
      end
      @(negedge clk);udp_valid=0;repeat(90)@(negedge clk);
    end
  endtask
  task control_verify(input integer typ,input [63:0] sid,input [63:0] b);
    begin
      if(!ctrl_valid||ctrl_type!==8'(typ)||ctrl_session!==sid||
         ctrl_frame!==32'habcddcba||(typ==1&&ctrl_body!==b))
        $fatal(1,"control mismatch typ=%0d sid=%016x got typ=%0d sid=%016x body=%016x",typ,sid,ctrl_type,ctrl_session,ctrl_body);
      checks=checks+1;
    end
  endtask
  task control_pop;
    integer t;
    begin
      @(negedge clk);ctrl_take=1;@(negedge clk);ctrl_take=0;t=0;
      while(dut.ctrl_count!=0&&!ctrl_valid&&t<90)begin @(negedge clk);t=t+1;end
      if(dut.ctrl_count!=0&&!ctrl_valid)$fatal(1,"control descriptor prefetch timeout");
    end
  endtask
  task verify(input integer seq,input integer len);
    integer at;
    begin
      if(!packet_valid||packet_index!==16'(seq)||frame_id!==32'(100+seq)||
         session_id!==64'h0123456789abcdef||flags!==16'h1234||
         payload_len!==16'(len)||msg_type!==8'd4||packet_count!==16'd1280)
        $fatal(1,"header mismatch seq=%0d valid=%0d idx=%0d",seq,packet_valid,packet_index);
      for(at=0;at<len;at=at+1)begin
        @(negedge clk);payload_addr=at;
        @(posedge clk);#1;
        if(payload_data!==value(seq,at))$fatal(1,"payload seq=%0d at=%0d got=%02x expected=%02x",seq,at,payload_data,value(seq,at));
      end
      checks=checks+1;
    end
  endtask
  task pop;
    integer t;
    begin
      @(negedge clk);packet_take=1;@(negedge clk);packet_take=0;t=0;
      while(dut.fifo_count!=0&&dut.ctrl_count==0&&!packet_valid&&t<90)begin @(negedge clk);t=t+1;end
      if(dut.fifo_count!=0&&dut.ctrl_count==0&&!packet_valid)$fatal(1,"DATA descriptor prefetch timeout");
    end
  endtask
  task reset_fifo;
    begin
      @(negedge clk);flush=1;
      @(negedge clk);flush=0;
      if(packet_valid)$fatal(1,"flush retained packet");
    end
  endtask
  initial begin
    repeat(4)@(negedge clk);rst_n=1;
    // Four maximum-sized packets must remain intact under backpressure.
    for(i=0;i<4;i=i+1)send(i,1440,0,-1);
    if(dut.fifo_count!==4)$fatal(1,"queue did not reach four");
    before_drop=dropped_packets;send(4,1440,0,-1);
    if(dropped_packets!==before_drop+1)$fatal(1,"full overflow not counted once");
    for(i=0;i<4;i=i+1)begin verify(i,1440);pop();end
    if(packet_valid)$fatal(1,"queue not empty");
    // A bad CRC must not publish or disturb already queued payloads.
    send(10,83,0,-1);before_drop=dropped_packets;send(11,1440,1,-1);
    if(dropped_packets!==before_drop+1||dut.fifo_count!==1)$fatal(1,"CRC rejection");
    verify(10,83);pop();
    // Real input stalls shorter than packet timeout preserve CRC and bytes.
    send(12,1440,0,711);verify(12,1440);pop();
    // Concurrent commit and retirement keeps occupancy and ordering intact.
    send(20,64,0,-1);send(21,64,0,-1);send(22,64,0,-1);
    fork
      send(23,1440,0,-1);
      begin
        wait(dut.state==1&&dut.count>=16'd64);
        verify(20,64);pop();
      end
    join
    if(dut.fifo_count!==3)$fatal(1,"push/pop occupancy %0d",dut.fifo_count);
    verify(21,64);pop();verify(22,64);pop();verify(23,1440);pop();
    // Full queue permits capture when its head retires at the first byte.
    for(i=30;i<34;i=i+1)send(i,32,0,-1);
    verify(30,32);
    build(34,32,0);
    @(negedge clk);packet_take=1;udp_valid=1;udp_data=bytes[0];udp_len=64;
    @(negedge clk);packet_take=0;
    for(j=1;j<64;j=j+1)begin udp_data=bytes[j];@(negedge clk);end
    udp_valid=0;repeat(90)@(negedge clk);
    if(dut.fifo_count!==4)$fatal(1,"full-to-pop capture occupancy");
    for(i=31;i<35;i=i+1)begin verify(i,32);pop();end
    // Late MAC error during SETTLE invalidates the packet.
    before_drop=dropped_packets;
    fork
      send(40,8,0,-1);
      begin
        wait(dut.state==2);repeat(6)@(negedge clk);udp_error=1;
        @(negedge clk);udp_error=0;
      end
    join
    if(packet_valid||dropped_packets!==before_drop+1)$fatal(1,"late MAC error");
    // Timeout abandons an incomplete packet and the next full packet works.
    before_drop=dropped_packets;build(41,32,0);
    for(j=0;j<12;j=j+1)begin @(negedge clk);udp_valid=1;udp_data=bytes[j];udp_len=64;end
    @(negedge clk);udp_valid=0;repeat(84)@(negedge clk);
    if(dropped_packets!==before_drop+1||packet_valid)$fatal(1,"packet timeout");
    send(42,0,0,-1);verify(42,0);pop();
    // Flush discards committed/in-flight packets; a fresh packet resynchronizes.
    send(50,64,0,-1);reset_fifo();send(51,64,0,-1);verify(51,64);pop();
    // A full DATA FIFO cannot block validated HELLO and heartbeat control.
    for(i=52;i<56;i=i+1)send(i,64,0,-1);
    control(1,64'hfeed,64'h1234567800004301,0,0,0);
    control(10,64'hfeed,0,0,0,0);
    if(dut.fifo_count!==4||dut.ctrl_count!==2||control_events!=2)
      $fatal(1,"control bypass blocked by full DATA");
    control_verify(1,64'hfeed,64'h1234567800004301);
    // A held control is not a stream of lease events.
    repeat(90)@(negedge clk);
    if(control_events!=2)$fatal(1,"control event repeated under backpressure");
    // Full control queue rejects/counts exactly one packet.
    before_drop=dropped_packets;control(10,64'hfeed,0,0,0,0);
    if(dropped_packets!==before_drop+1||control_events!=2)$fatal(1,"control overflow");
    // DATA flush preserves queued controls and queue order.
    reset_fifo();control_verify(1,64'hfeed,64'h1234567800004301);control_pop();
    control_verify(10,64'hfeed,0);control_pop();
    if(ctrl_valid)$fatal(1,"control queue did not drain");
    // A valid diagnostic CANCEL bypasses a full DATA queue but does not
    // generate a lease event. Bad HXD1 versions and packet CRCs are rejected.
    for(i=52;i<56;i=i+1)send(i,64,0,-1);
    cancel_control(64'hfeed,0,0);
    if(!ctrl_valid||ctrl_type!==8'd11||ctrl_session!==64'hfeed||
       dut.fifo_count!==4||control_events!=2)
      $fatal(1,"valid CANCEL was not independently queued or renewed lease");
    control_pop();
    before_drop=dropped_packets;cancel_control(64'hfeed,1,0);
    cancel_control(64'hfeed,0,1);
    if(ctrl_valid||dropped_packets!==before_drop+2||control_events!=2)
      $fatal(1,"invalid CANCEL was admitted");
    reset_fifo();
    // Wrong role/reserved/heartbeat index/CRC must not renew a lease.
    before_drop=dropped_packets;
    control(1,64'hfeed,64'h1234567800004303,0,0,0);
    control(1,64'hfeed,64'h1234567800014301,0,0,0);
    control(10,64'hfeed,0,1,0,0);
    control(1,64'hfeed,64'h1234567800004301,0,0,1);
    if(ctrl_valid||dropped_packets!==before_drop+4||control_events!=2)
      $fatal(1,"invalid control accepted");
    // Flush halfway through a new HELLO must retain its framing and CRC.
    fork
      control(1,64'hbeef,64'h8765432100004301,0,0,0);
      begin wait(dut.state==1&&dut.count==20);@(negedge clk);flush=1;
        @(negedge clk);flush=0;end
    join
    control_verify(1,64'hbeef,64'h8765432100004301);control_pop();
    if(control_events!=3)$fatal(1,"in-flight HELLO lost to flush");
    // Flush halfway through DATA must prevent partially overwritten payload
    // from becoming a visible packet; the next packet starts from slot zero.
    fork
      send(56,1440,0,-1);
      begin wait(dut.state==1&&dut.count==734);@(negedge clk);flush=1;
        @(negedge clk);flush=0;end
    join
    if(packet_valid)$fatal(1,"flushed in-flight DATA leaked");
    send(57,1440,0,-1);verify(57,1440);pop();
    // Full control queue supports simultaneous accepted push and pop.
    control(1,64'h6001,64'h0000000000004301,0,0,0);
    control(10,64'h6001,0,0,0,0);
    fork
      control(1,64'h6002,64'h0000000000004301,0,0,0);
      begin wait(dut.state==2&&dut.settle_count==31);
        @(negedge clk);ctrl_take=1;@(negedge clk);ctrl_take=0;end
    join
    if(dut.ctrl_count!==2)$fatal(1,"control push/pop occupancy");
    control_verify(10,64'h6001,0);control_pop();
    control_verify(1,64'h6002,64'h0000000000004301);control_pop();
    // 40 us start-to-start DATA cadence with concurrent DDR-style reads.
    fork
      begin
        for(integer n=60;n<76;n=n+1)begin
          send(n,1440,0,-1);repeat(3491)@(negedge clk);
        end
      end
      begin
        for(integer n=60;n<76;n=n+1)begin
          wait(packet_valid);@(negedge clk);verify(n,1440);repeat(80)@(negedge clk);pop();
        end
      end
    join
    if(packet_valid)$fatal(1,"cadence left queued packets");
    // CANCEL followed by the link's DATA flush must discard queued payloads;
    // the freed ERAM slots are immediately reusable by the next frame.
    send(80,64,0,-1);send(81,64,0,-1);
    cancel_control(64'hcafe,0,0);
    if(!ctrl_valid||ctrl_type!==8'd11||packet_valid||dut.fifo_count!==2)
      $fatal(1,"CANCEL control/data state mismatch");
    reset_fifo();
    if(packet_valid||dut.fifo_count!==0)$fatal(1,"CANCEL flush retained DATA");
    control_pop();
    send(82,64,0,-1);verify(82,64);pop();
    $display("POSE7_FIFO4_PASS: %0d payload/header/control checks, %0d expected rejected packets, %0d control events, 40us cadence",checks,packet_errors,control_events);
    $finish;
  end
  initial begin #3000000;$fatal(1,"watchdog");end
endmodule
