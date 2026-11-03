`timescale 1ns/1ps
module tb_link_pcb_wait;
 localparam integer HZ=5000000;
 reg clk=0,rst_n=0,enable=1,phy=1,pcb=1,detect=1,trigger=0;
 always #5 clk=~clk;
 wire cap,capcancel,release_frame,background_capture,packet_req,packet_ready;
 wire [10:0] packet_index; wire udp_req,udp_valid;wire [7:0] udp_data,job_state;wire [15:0] udp_len;
 wire online,result_valid,result_toggle;wire [511:0] result_data;wire [31:0] result_frame,sent,failed;
 reg snapbusy=0,snapready=0,pbusy=0,pvalid=0,plast=0,ubusy=0;reg[31:0] sfid=0;
 reg[7:0] pdata=0;reg[10:0] pindex=0;integer pbyte=0;
 reg rxv=0;reg[7:0] rxd=0;reg[15:0] rxl=0;
 integer captures=0,begins=0,ends=0,acks=0,cancels=0,heartbeats=0,hellos=0,data_packets=0,last_cancel_reason=0;
 integer now_ms=0,wait_started=0,last_heartbeat_ms=0,max_heartbeat_gap=0;
 reg[63:0] active_sid=0;reg[31:0] active_fid=0,active_job=0,image_crc=0;
 integer active_purpose=0;reg drop_peer=0,manual_lock=0,worker_busy=0;
 integer qhead=0,qtail=0,qt[0:4095];reg[63:0] qs[0:4095];reg[31:0] qf[0:4095],qp[0:4095];
 reg[7:0] txbytes[0:1471];integer out_at=0;reg[31:0] txcrc=32'hffffffff;
 hxa_main_link #(.CLK_HZ(HZ),.PACKET_GAP_CYCLES(1),.PCB_KEY_ONESHOT(1),.PCB_RESULT_TIMEOUT_MS(30000)) dut(
  .clk(clk),.rst_n(rst_n),.enable(enable),.phy_ready(phy),.pcb_mode(pcb),.detect_enable(detect),
  .text_mode(1'b0),.text_trigger(1'b0),.maze_mode(1'b0),.maze_trigger(1'b0),.report_request(1'b0),
  .background_valid(1'b1),.pcb_trigger(trigger),.pcb_present(1'b1),.teach_good(1'b0),
  .capture_req(cap),.capture_cancel(capcancel),.capture_release(release_frame),.background_capture(background_capture),
  .snapshot_busy(snapbusy),.snapshot_ready(snapready),.snapshot_error(1'b0),.snapshot_frame_id(sfid),.snapshot_diag(128'd0),
  .packet_req(packet_req),.packet_index(packet_index),.packet_busy(pbusy),.packet_valid(pvalid),
  .packet_last(plast),.packet_error(1'b0),.packet_data(pdata),.packet_ready(packet_ready),
  .udp_req(udp_req),.udp_valid(udp_valid),.udp_data(udp_data),.udp_len(udp_len),.udp_busy(ubusy),
  .rx_valid(rxv),.rx_data(rxd),.rx_len(rxl),.rx_error(1'b0),.online(online),
  .result_valid(result_valid),.result_toggle(result_toggle),.result_data(result_data),.result_frame(result_frame),
  .sent_frames(sent),.failed_frames(failed),.station_ready(1'b1),.job_state(job_state),
  .stack_reset(),.station_header(),.station_commit(),.multi_valid(),.multi_toggle(),.multi_count(),
  .multi_data(),.multi_job(),.copy_state(),.copy_toggle());
 function automatic[31:0] crcbyte(input[31:0] crc,input[7:0] b);integer i;reg[31:0] c;begin
  c=crc^b;for(i=0;i<8;i=i+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crcbyte=c;end endfunction
 function[31:0] u32(input integer n);begin u32={txbytes[n+3],txbytes[n+2],txbytes[n+1],txbytes[n]};end endfunction
 task queue(input integer typ,input[63:0] sid,input[31:0] fid,input[31:0] value);begin
  if(qtail>=4096)$fatal(1,"queue overflow");qt[qtail]=typ;qs[qtail]=sid;qf[qtail]=fid;qp[qtail]=value;qtail=qtail+1;end endtask
 always@(posedge clk)begin
  if(!rst_n)begin snapbusy<=0;snapready<=0;pbusy<=0;pvalid<=0;plast<=0;ubusy<=0;out_at=0;end
  else begin
   if(dut.tick_ms)now_ms=now_ms+1;
   if(cap)begin if(snapbusy)$fatal(1,"capture while busy");captures=captures+1;snapbusy<=1;snapready<=1;sfid<=sfid+1;end
   if(capcancel||release_frame)begin snapbusy<=0;snapready<=0;pbusy<=0;pvalid<=0;end
   if(packet_req)begin if(!snapready||pbusy)$fatal(1,"bad packet request");pindex<=packet_index;pbyte<=0;pbusy<=1;pvalid<=1;plast<=0;pdata<=packet_index[7:0];end
   else if(pvalid&&packet_ready)begin
    if(pbyte==1439)begin pbusy<=0;pvalid<=0;plast<=0;end
    else begin pbyte<=pbyte+1;pdata<=(pindex+pbyte+1)&255;plast<=(pbyte==1438);end
   end
   if(udp_req&&!ubusy)begin ubusy<=1;out_at=0;txcrc=32'hffffffff;end
   if(udp_valid)begin
    txbytes[out_at]=udp_data;txcrc=crcbyte(txcrc,udp_data);
    if(out_at==udp_len-1)begin
     ubusy<=0;if(txcrc!==32'hdebb20e3||u32(0)!==32'h31415848)$fatal(1,"TX CRC/header");
     case(txbytes[5])
      1:begin hellos=hellos+1;queue(1,{u32(12),u32(8)},u32(16),0);end
      3:begin active_sid={u32(12),u32(8)};active_fid=u32(16);active_job=u32(40);active_purpose=txbytes[33];begins=begins+1;
       if(u32(36)!=1843200||{txbytes[29],txbytes[28]}!=1280||{txbytes[31],txbytes[30]}!=720)$fatal(1,"frame metadata changed");
       queue(2,active_sid,active_fid,0);end
      4:begin data_packets=data_packets+1;if(udp_len!=1472||{txbytes[23],txbytes[22]}!=1280)$fatal(1,"DATA metadata");end
      5:begin ends=ends+1;image_crc=u32(28);queue(7,{u32(12),u32(8)},u32(16),image_crc);end
      9:acks=acks+1;
      10:begin heartbeats=heartbeats+1;
       if(dut.pcb_result_wait_active)begin
        if({u32(12),u32(8)}!==active_sid||u32(16)!==active_fid||dut.job_id!==active_job)$fatal(1,"heartbeat changed task identity");
        if(last_heartbeat_ms!=0&&now_ms-last_heartbeat_ms>max_heartbeat_gap)max_heartbeat_gap=now_ms-last_heartbeat_ms;
        last_heartbeat_ms=now_ms;
       end
       queue(10,{u32(12),u32(8)},u32(16),0);end
      11:begin
       if(udp_len!=60||u32(28)!=32'h31445848||txbytes[32]!=1)$fatal(1,"CANCEL diagnostic framing");
       cancels=cancels+1;last_cancel_reason=txbytes[33];
       $display("CANCEL ms=%0d reason=%0d timer=%0d",now_ms,last_cancel_reason,dut.pcb_result_wait_ms);end
      default:;
     endcase
    end
    out_at=out_at+1;
   end
  end
 end
 task automatic inject(input integer typ,input[63:0] sid,input[31:0] fid,input integer len,input[511:0] payload);
  reg[7:0] bytes[0:95];reg[223:0] head;reg[31:0] crc;integer n;begin
   head={16'd0,16'(len),16'd0,16'd0,fid,sid,16'd0,8'(typ),8'd1,32'h31415848};crc=32'hffffffff;
   for(n=0;n<28;n=n+1)begin bytes[n]=head[n*8+:8];crc=crcbyte(crc,bytes[n]);end
   for(n=0;n<len;n=n+1)begin bytes[28+n]=payload[n*8+:8];crc=crcbyte(crc,bytes[28+n]);end
   crc=~crc;for(n=0;n<4;n=n+1)bytes[28+len+n]=crc[n*8+:8];
   for(n=0;n<len+32;n=n+1)begin @(negedge clk);rxv=1;rxd=bytes[n];rxl=len+32;end
   @(negedge clk);rxv=0;repeat(230)@(negedge clk);
  end endtask
 integer qkind;reg[63:0] qsid;reg[31:0] qfid,qvalue;
 initial forever begin
  @(negedge clk);
  if(rst_n&&!manual_lock&&qhead<qtail)begin
   worker_busy=1;qkind=qt[qhead];qsid=qs[qhead];qfid=qf[qhead];qvalue=qp[qhead];qhead=qhead+1;
   if(!drop_peer)case(qkind)
    1:inject(2,qsid,qfid,8,512'h1302);
    2:inject(2,qsid,qfid,0,0);
    7:inject(7,qsid,qfid,4,{480'd0,qvalue});
    10:inject(10,qsid,qfid,0,0);
   endcase
   worker_busy=0;
  end
 end
 task wait_ms(input integer n);integer target;begin target=now_ms+n;wait(now_ms>=target);@(negedge clk);end endtask
 task lock_rx;begin wait(!worker_busy&&qhead==qtail);@(negedge clk);manual_lock=1;end endtask
 task start_pcb;integer c;begin
  wait(online&&dut.state==2);c=captures;@(negedge clk);trigger=1;@(negedge clk);trigger=0;
  wait(captures==c+1);wait(dut.pcb_result_wait_active);@(negedge clk);
  if(dut.pcb_result_wait_ms!=30000)$fatal(1,"timer not started at FRAME_ACK");
  wait_started=now_ms;last_heartbeat_ms=0;
 end endtask
 function automatic[511:0] result_payload(input[31:0] job);reg[511:0] p;begin
  p=0;p[31:0]=job;p[103:96]=1;p[111:104]=1;p[119:112]=1;p[127:120]=90;
  p[143:128]=200;p[159:144]=160;p[175:160]=900;p[191:176]=500;p[231:224]=1;result_payload=p;
 end endfunction
 integer c0,b0,h0,a0,f0,t0;reg toggle0;reg[63:0] sid0;reg[31:0] fid0,job0;
 initial begin
  repeat(12)@(negedge clk);rst_n=1;start_pcb();
  c0=captures;b0=begins;h0=heartbeats;sid0=active_sid;fid0=active_fid;job0=active_job;toggle0=result_toggle;
  wait_ms(11000);
  if(!online||!dut.pcb_result_wait_active||dut.pcb_result_wait_ms!=19000||captures!=c0||begins!=b0||cancels!=0||heartbeats-h0<43)$fatal(1,"PCB long wait/heartbeat");
  if(dut.session!==sid0||dut.frame_id!==fid0||dut.job_id!==job0)$fatal(1,"long wait identity");
  lock_rx();inject(8,sid0+1,fid0,64,result_payload(job0));inject(8,sid0,fid0+1,64,result_payload(job0));inject(8,sid0,fid0,64,result_payload(job0+1));
  if(result_toggle!==toggle0||result_valid||dut.result_seen)$fatal(1,"foreign/stale result committed");
  a0=acks;inject(8,sid0,fid0,64,result_payload(job0));manual_lock=0;wait(acks==a0+1);
  if(!result_valid||result_frame!==fid0||dut.pcb_result_wait_active||dut.pcb_result_wait_ms!=0)$fatal(1,"valid result not committed");
  toggle0=result_toggle;lock_rx();inject(8,sid0,fid0,64,result_payload(job0));manual_lock=0;wait(acks==a0+2);
  if(result_toggle!==toggle0||captures!=c0||begins!=b0)$fatal(1,"duplicate result restarted task");
  if(max_heartbeat_gap>251)$fatal(1,"heartbeat period exceeded 250ms + serialization");
  $display("PASS long PCB wait 11s, identity, 250ms heartbeat, wrong session/frame/job, result commit, duplicate Type8 ACK; max_gap_ms=%0d",max_heartbeat_gap);
  start_pcb();f0=failed;c0=cancels;wait_ms(5000);t0=dut.pcb_result_wait_ms;a0=acks;toggle0=result_toggle;
  lock_rx();inject(8,sid0,fid0,64,result_payload(job0));manual_lock=0;wait(acks==a0+1);
  if(dut.pcb_result_wait_ms>t0||!dut.pcb_result_wait_active||result_toggle!==toggle0)
   $fatal(1,"cached prior-result ACK reset PCB timer or recommitted data");
  $display("PASS cached previous-task Type8 ACK during active PCB wait, timer preserved from %0d to %0d",t0,dut.pcb_result_wait_ms);
  wait(dut.pcb_result_wait_ms==1);@(negedge clk);
  if(cancels!=c0||failed!=f0)$fatal(1,"PCB cancelled before 30 seconds");
  wait(failed==f0+1);t0=now_ms-wait_started;wait(cancels==c0+1);
  if(t0<30000||t0>30001||last_cancel_reason!=12)$fatal(1,"PCB timeout bound elapsed=%0d wire_reason=%0d",t0,last_cancel_reason);
  if(!online||dut.session!==sid0||dut.pcb_result_wait_active)$fatal(1,"frame timeout reconnected");
  $display("PASS PCB 30 second timeout, no premature cancel, frame-only failure elapsed_ms=%0d",t0);
  start_pcb();f0=failed;c0=cancels;wait_ms(20);detect=0;pcb=0;wait(failed==f0+1);wait(cancels==c0+1);
  if(last_cancel_reason!=5||dut.pcb_result_wait_active||result_valid)$fatal(1,"mode cancellation");
  $display("PASS mode change cancels active PCB task");
  wait(dut.state==2);detect=1;wait(cap);wait(dut.state==8);detect=0;
  t0=now_ms;f0=failed;c0=cancels;
  if(dut.pcb_result_wait_active)$fatal(1,"ordinary timer uses PCB budget");
  wait(failed==f0+1);t0=now_ms-t0;wait(cancels==c0+1);
  if(t0<1999||t0>2001||last_cancel_reason!=12)$fatal(1,"ordinary timeout changed: %0d",t0);
  $display("PASS ordinary CNN original 2 second timeout elapsed_ms=%0d",t0);
  wait(dut.state==2);pcb=1;detect=1;wait(dut.state==2);repeat(20)@(negedge clk);start_pcb();
  wait(!worker_busy&&qhead==qtail);drop_peer=1;f0=failed;c0=cancels;wait(!online);
  if(dut.cancel_reason!=4||dut.lease_ms<3000)$fatal(1,"lease fault rule changed");
  wait(cancels==c0+1);if(last_cancel_reason!=4||failed!=f0+1||dut.pcb_result_wait_active)$fatal(1,"lease fault task cleanup");
  $display("PASS real 3 second peer loss cancels/reconnects");
  $display("PASS ALL packet-level PCB compatibility; captures=%0d begins=%0d full_frames=%0d DATA=%0d heartbeats=%0d ACK=%0d cancels=%0d",captures,begins,ends,data_packets,heartbeats,acks,cancels);$finish;
 end
 initial begin #(64'd4000000000);$fatal(1,"watchdog state=%0d ms=%0d captures=%0d data=%0d online=%0d timer=%0d queue=%0d/%0d",dut.state,now_ms,captures,data_packets,online,dut.pcb_result_wait_ms,qhead,qtail);end
endmodule
