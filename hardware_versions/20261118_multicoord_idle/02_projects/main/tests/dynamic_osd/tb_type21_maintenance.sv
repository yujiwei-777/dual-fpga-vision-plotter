`timescale 1ns/1ps
// Actual main link and CRC packet RX/TX. Only public byte-stream ports are
// driven; the peer session is learned from the emitted HELLO packet.
module tb_type21_maintenance;
  reg clk=0; always #4 clk=~clk;
  reg rst_n=0, rx_valid=0, udp_busy=0;
  reg [7:0] rx_data=0;
  reg [15:0] rx_len=0;
  wire udp_req,udp_valid,online,operator_valid,operator_toggle;
  wire [7:0] udp_data;
  wire [15:0] udp_len;
  wire [383:0] operator_data;
  hxa_main_link #(.CLK_HZ(100000),.HELLO_CAPABILITIES(8'hd3),
    .OPERATOR_UI_ENABLE(1),.PACKET_GAP_CYCLES(16)) dut(
    .clk(clk),.rst_n(rst_n),.enable(1'b1),.phy_ready(1'b1),
    .pcb_mode(1'b0),.session_epoch(8'd0),.detect_enable(1'b0),
    .text_mode(1'b0),.text_trigger(1'b0),.maze_mode(1'b0),.maze_trigger(1'b0),
    .report_request(1'b0),.background_valid(1'b1),.pcb_trigger(1'b0),
    .pcb_present(1'b0),.teach_good(1'b0),.capture_req(),.capture_cancel(),
    .capture_release(),.background_capture(),.snapshot_busy(1'b0),
    .snapshot_ready(1'b0),.snapshot_error(1'b0),.snapshot_frame_id(32'd0),
    .snapshot_diag(128'd0),.packet_req(),.packet_index(),.packet_busy(1'b0),
    .packet_valid(1'b0),.packet_last(1'b0),.packet_error(1'b0),
    .packet_data(8'd0),.packet_ready(),.udp_req(udp_req),.udp_valid(udp_valid),
    .udp_data(udp_data),.udp_len(udp_len),.udp_busy(udp_busy),
    .rx_valid(rx_valid),.rx_data(rx_data),.rx_len(rx_len),.rx_error(1'b0),
    .stack_reset(),.online(online),.result_valid(),.result_toggle(),
    .result_data(),.result_frame(),.sent_frames(),.failed_frames(),
    .station_header(),.station_commit(),.station_ready(1'b1),.job_state(),
    .multi_valid(),.multi_toggle(),.multi_count(),.multi_data(),.multi_job(),
    .copy_state(),.copy_toggle(),.operator_valid(operator_valid),
    .operator_toggle(operator_toggle),.operator_data(operator_data));

  reg [7:0] txbytes[0:1471],packet[0:111];
  reg [63:0] peer_session=0;
  integer tx_at=0,publications=0;
  reg hello_seen=0,seen=0;
  reg [383:0] published=0;
  always @(posedge clk) begin
    if(!rst_n)begin udp_busy<=0;tx_at=0;hello_seen=0;end
    else begin
      if(udp_req&&!udp_busy)begin udp_busy<=1;tx_at=0;end
      if(udp_valid)begin
        txbytes[tx_at]=udp_data;
        if(tx_at==udp_len-1)begin
          udp_busy<=0;
          if(txbytes[5]==1)begin
            peer_session={txbytes[15],txbytes[14],txbytes[13],txbytes[12],
                          txbytes[11],txbytes[10],txbytes[9],txbytes[8]};
            hello_seen=1;
          end
        end
        tx_at=tx_at+1;
      end
    end
  end
  always @(negedge clk)begin
    if(!rst_n)seen=operator_toggle;
    else if(seen!=operator_toggle)begin
      if(!operator_valid)$fatal(1,"Type21 toggled without valid");
      seen=operator_toggle;published=operator_data;publications=publications+1;
    end
  end
  function automatic [31:0] crcbyte(input [31:0] cc,input [7:0] b);
    reg [31:0] c;integer j;
    begin c=cc^b;for(j=0;j<8;j=j+1)c=c[0]?((c>>1)^32'hedb88320):(c>>1);crcbyte=c;end
  endfunction
  task step;begin @(posedge clk);#1;end endtask
  task inject(input [7:0] typ,input [383:0] body,input integer len);
    reg [223:0] header;reg [31:0] crc;integer k;
    begin
      header={16'd0,16'(len),16'd0,16'd0,32'd0,peer_session,16'd0,typ,8'd1,32'h31415848};
      for(k=0;k<28;k=k+1)packet[k]=header[k*8+:8];
      for(k=0;k<len;k=k+1)packet[28+k]=body[k*8+:8];
      crc=32'hffffffff;
      for(k=0;k<28+len;k=k+1)crc=crcbyte(crc,packet[k]);
      crc=~crc;for(k=0;k<4;k=k+1)packet[28+len+k]=crc[k*8+:8];
      rx_len=len+32;
      for(k=0;k<len+32;k=k+1)begin @(negedge clk);rx_valid=1;rx_data=packet[k];end
      @(negedge clk);rx_valid=0;repeat(180)step;
    end
  endtask
  reg [383:0] status;
  integer n,prior,reason;
  initial begin
    repeat(6)step;rst_n=1;
    n=0;while(!hello_seen&&n<5000)begin step;n=n+1;end
    if(!hello_seen)$fatal(1,"No public HELLO session");
    inject(8'd2,384'h000000000000d302,8);
    if(!online)$fatal(1,"READY did not establish session");
    status=0;status[31:0]=32'h3152504f;status[39:32]=1;
    status[47:40]=8'h82;status[55:48]=1;status[63:56]=2;
    status[135:128]=4;status[143:136]=17;status[175:160]=120;
    status[191:176]=40;status[255:240]=28000;
    for(reason=0;reason<=7;reason=reason+1)begin
      status[367:360]=reason;prior=publications;inject(8'd21,status,48);
      if(publications!=prior+1||published!==status)
        $fatal(1,"legal Type21 maintenance=%0d rejected/torn",reason);
      $display("TYPE21_VALID maintenance=%0d",reason);
    end
    prior=publications;status[367:360]=8;inject(8'd21,status,48);
    if(publications!=prior||published[367:360]!=7)$fatal(1,"illegal maintenance 8 published");
    status[367:360]=255;inject(8'd21,status,48);
    if(publications!=prior)$fatal(1,"illegal maintenance 255 published");
    status[367:360]=0;inject(8'd21,status,48);
    if(publications!=prior+1||published!==status)$fatal(1,"valid status after reject failed");
    $display("TYPE21_MAINTENANCE_PASS valid_0_to_7 reject_8_and_255 real_crc_session");
    $finish;
  end
  initial begin #1000000;$fatal(1,"Type21 maintenance test timeout");end
endmodule
