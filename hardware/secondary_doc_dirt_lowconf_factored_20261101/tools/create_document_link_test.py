from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
text=(ROOT/'shared/tests/tb_hxa_pair.sv').read_text()
text=text[:text.index('\nmodule tb_hxa_pair_multibox;')]
text=text.replace('module tb_hxa_pair #(parameter integer MULTIBOX_TEST=0);','''module tb_hxa_document_pair;
 localparam MULTIBOX_TEST=0;
 localparam TEST_HZ=32000000;
 reg copy_mode=1,trigger=0;
 wire [2:0] copy_state;wire copy_toggle;
 reg job_valid=0;reg [95:0] job_data=0;wire job_ready;
 integer heartbeat_replies=0,terminal_packets=0,begin_packets=0;
 reg drop_terminal=0;wire copy_rearm;
''')
text=text.replace('hxa_main_link #(.HELLO_CAPABILITIES(EXPECT_MULTI?8\'h43:8\'h03))',
    "hxa_main_link #(.CLK_HZ(TEST_HZ),.PACKET_GAP_CYCLES(1280),.HELLO_CAPABILITIES(8'hC3))")
text=text.replace(".detect_enable(1'b1),.maze_mode", ".detect_enable(1'b0),.text_mode(copy_mode),.text_trigger(trigger),.report_request(1'b0),.maze_mode")
text=text.replace('.rx_valid(svalid),.rx_data(sd)', '.rx_valid(svalid&&!drop_terminal),.rx_data(sd)')
text=text.replace('.multi_job(mmulti_job));','.multi_job(mmulti_job),.copy_state(copy_state),.copy_toggle(copy_toggle));')
text=text.replace("hxa_secondary_link #(.CAPABILITIES(8'h41))", "hxa_secondary_link #(.CLK_HZ(TEST_HZ),.FRAME_CRC_BYTES_PER_CYCLE(4),.CAPABILITIES(8'hC1))")
text=text.replace(".job_status_valid(1'b0),.job_status_data(96'd0),.job_status_ready(),.job_busy(1'b0)",'.job_status_valid(job_valid),.job_status_data(job_data),.job_status_ready(job_ready),.job_busy(vbusy)')
text=text.replace('.good_frames(good),.bad_frames(bad));','.good_frames(good),.bad_frames(bad),.copy_rearm(copy_rearm));')
text=text.replace('if(mreq&&!mbusy)', 'if(job_valid&&job_ready)job_valid<=0;\n  if(mreq&&!mbusy)')
text=text.replace('if(mat==5&&md==4)packets=packets+1;', 'if(mat==5&&md==4)packets=packets+1;\n   if(mat==5&&md==3)begin_packets=begin_packets+1;')
text=text.replace('if(sreq&&!sbusy)begin sbusy<=1;sat=0;end', '''if(sreq&&!sbusy)begin
   sbusy<=1;sat=0;drop_terminal<=(secondary_dut.tx_type==15&&job_data[39:32]==4&&terminal_packets==0);
   if(secondary_dut.tx_type==15&&job_data[39:32]==4)terminal_packets=terminal_packets+1;
  end''')
text=text.replace('if(sat==slen-1)sbusy<=0;', 'if(sat==5&&sd==10)heartbeat_replies=heartbeat_replies+1;\n    if(sat==slen-1)sbusy<=0;')
start=text.index('  if(vstart)begin')
end=text.index('  if(mfailed!=0)',start)
text=text[:start]+'''  if(vstart)begin
   if(!widle||starts!=0||vframe!=77||vpurpose!=2)$fatal(1,"illegal copy admission");
   starts=starts+1;vbusy<=1;vdelay=TEST_HZ*3;
   job_data<={32'd0,16'd0,8'd0,8'd1,vjob};job_valid<=1;
  end else if(vdelay!=0)begin
   vdelay=vdelay-1;
   if(vdelay==TEST_HZ*2)begin job_data<={32'd1,16'd0,8'd0,8'd2,vjob};job_valid<=1;end
   if(vdelay==0)begin
    vbusy<=0;vdone<=1;job_data<={32'd10,16'd0,8'd0,8'd4,vjob};job_valid<=1;
   end
  end
  if(vbusy&&releases!=0)$fatal(1,"document snapshot released before terminal");
  if(secondary_dut.result_pending||secondary_dut.result_copy_pending)$fatal(1,"document emitted Type8/18");
''' + text[end:]
start=text.index('  if(EXPECT_MULTI&&secondary_dut.result_acked)')
end=text.index('\n end\n initial begin',start)
text=text[:start]+'''  if(copy_state==3&&releases==1)begin
   if(starts!=1||packets!=1280||good!=1||heartbeat_replies<8||terminal_packets<2||
      secondary_dut.received_count!=1280||secondary_dut.dropped!=0||!monline||!sonline)
    $fatal(1,"copy completion/replay: starts=%0d packets=%0d heartbeats=%0d terminals=%0d dropped=%0d",starts,packets,heartbeat_replies,terminal_packets,secondary_dut.dropped);
   $display("PASS document paired links: 1280 DATA, CRC, FRAME_ACK, snapshot retained, >2s task, heartbeat, lost terminal replay, no Type8/18");$finish;
  end
''' + text[end:]
start=text.index(' initial begin repeat(10)')
text=text[:start]+''' initial begin
  repeat(10)@(negedge clk);rst=1;
  wait(monline&&sonline);repeat(20)@(negedge clk);trigger=1;
  @(negedge clk);trigger=0;
 end
 initial begin #1800000000;$fatal(1,"document pair timeout packets=%0d state=%0d starts=%0d heartbeat=%0d",packets,main_dut.state,starts,heartbeat_replies);end
endmodule
'''
dest=ROOT/'02_sim/doc_integration/tb_hxa_document_pair.sv'
dest.parent.mkdir(exist_ok=True);dest.write_text(text)
print(dest)
