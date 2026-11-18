`timescale 1ns/1ps
module tb_suspect_center;
  reg nclk=0,pclk=0;always #3 nclk=~nclk;always #5 pclk=~pclk;
  reg rst_n=0,remote_enable=1,remote_online=1,remote_pcb=1;
  reg remote_toggle=0,remote_valid=0,remote_clear=0,frame_start=0,overlay_enable=1;
  reg [511:0] data=0;reg [2:0] status=3;
  wire sv;wire [10:0] sx0,sx1,scx;wire [9:0] sy0,sy1,scy;
  wire [162:0] original_a,original_b;
  wire ov,rs,tg,pm,pc,pg;wire [2:0] ps;
  wire [10:0] x0,x1,cx;wire [9:0] y0,y1,cy;wire [23:0] area;
  wire [1:0] color,shape;wire [3:0] cid,ct,co;wire [7:0] conf;
  wire bsv;wire [10:0] bsx0,bsx1;wire [9:0] bsy0,bsy1;
  wire bov,brs,btg,bpm,bpc,bpg;wire [2:0] bps;
  wire [10:0] bx0,bx1,bcx;wire [9:0] by0,by1,bcy;wire [23:0] ba;
  wire [1:0] bc,bs;wire [3:0] bi,bct,bco;wire [7:0] bconf;
  hx_result_select sel(
    .net_clk(nclk),.net_rst_n(rst_n),.remote_enable(remote_enable),.remote_online(remote_online),.remote_pcb(remote_pcb),
    .remote_toggle(remote_toggle),.remote_valid(remote_valid),.remote_clear(remote_clear),.remote_data(data),.remote_status(status),
    .px_clk(pclk),.px_rst_n(rst_n),.frame_start(frame_start),.overlay_enable(overlay_enable),
    .local_valid(1'b0),.local_x0(11'd0),.local_x1(11'd0),.local_cx(11'd0),
    .local_y0(10'd0),.local_y1(10'd0),.local_cy(10'd0),.local_area(24'd0),
    .local_color(2'd0),.local_shape(2'd0),.local_class(4'd0),.local_confidence(8'd0),.local_tens(4'd0),.local_ones(4'd0),
    .valid(ov),.remote_source(rs),.toggle(tg),.pcb_mode(pm),.pcb_checked(pc),.pcb_good(pg),.pcb_status(ps),
    .suspect_valid(sv),.suspect_x0(sx0),.suspect_x1(sx1),.suspect_y0(sy0),.suspect_y1(sy1),.suspect_cx(scx),.suspect_cy(scy),
    .x0(x0),.x1(x1),.cx(cx),.y0(y0),.y1(y1),.cy(cy),.area(area),.color(color),.shape(shape),
    .class_id(cid),.conf_tens(ct),.conf_ones(co),.confidence(conf));
  hx_result_select_control base_sel(
    .net_clk(nclk),.net_rst_n(rst_n),.remote_enable(remote_enable),.remote_online(remote_online),.remote_pcb(remote_pcb),
    .remote_toggle(remote_toggle),.remote_valid(remote_valid),.remote_clear(remote_clear),.remote_data(data),.remote_status(status),
    .px_clk(pclk),.px_rst_n(rst_n),.frame_start(frame_start),.overlay_enable(overlay_enable),
    .local_valid(1'b0),.local_x0(11'd0),.local_x1(11'd0),.local_cx(11'd0),
    .local_y0(10'd0),.local_y1(10'd0),.local_cy(10'd0),.local_area(24'd0),
    .local_color(2'd0),.local_shape(2'd0),.local_class(4'd0),.local_confidence(8'd0),.local_tens(4'd0),.local_ones(4'd0),
    .valid(bov),.remote_source(brs),.toggle(btg),.pcb_mode(bpm),.pcb_checked(bpc),.pcb_good(bpg),.pcb_status(bps),
    .suspect_valid(bsv),.suspect_x0(bsx0),.suspect_x1(bsx1),.suspect_y0(bsy0),.suspect_y1(bsy1),
    .x0(bx0),.x1(bx1),.cx(bcx),.y0(by0),.y1(by1),.cy(bcy),.area(ba),.color(bc),.shape(bs),
    .class_id(bi),.conf_tens(bct),.conf_ones(bco),.confidence(bconf));
  assign original_a={ov,rs,tg,pm,pc,pg,ps,sv,sx0,sx1,sy0,sy1,x0,x1,cx,y0,y1,cy,area,color,shape,cid,ct,co,conf};
  assign original_b={bov,brs,btg,bpm,bpc,bpg,bps,bsv,bsx0,bsx1,bsy0,bsy1,bx0,bx1,bcx,by0,by1,bcy,ba,bc,bs,bi,bct,bco,bconf};
  integer original_compares=0;
  always @(posedge pclk)begin
    #1;if(rst_n)begin
      if(original_a!==original_b)$fatal(1,"original result metadata or region changed");
      if(!sv && (scx!==0||scy!==0))$fatal(1,"centre survives invalid region");
      original_compares=original_compares+1;
    end
  end
  reg [11:0] px=0,py=0;
  reg gate=1,pcb_gate=1,prio_osd=0,prio_motion=0,prio_multi=0,prio_corner=0;
  wire [23:0] rgb,rgb_base;
    hdmi_mixer #(.LOGO_ENABLE(0)) mix(
    .I_clk(pclk),
    .I_rst_n(rst_n),
    .I_video_vsync('0),
    .I_video_hsync('0),
    .I_video_de(1'b1),
    .I_video_user('0),
    .I_video_last('0),
    .I_video_rd_req('0),
    .I_debug_status('0),
    .I_algo_mode('0),
    .I_he_on('0),
    .I_latency_valid('0),
    .I_latency_frame('0),
    .I_latency_tenth_ms('0),
    .I_latency_toggle('0),
    .I_ovl_on(gate),
    .I_ovl_valid('0),
    .I_ovl_x0('0),
    .I_ovl_y0('0),
    .I_ovl_x1('0),
    .I_ovl_y1('0),
    .I_ovl_cx('0),
    .I_ovl_cy('0),
    .I_ovl_color('0),
    .I_ovl_pcb(pcb_gate),
    .I_pcb_checked('0),
    .I_pcb_good('0),
    .I_pcb_status('0),
    .I_pcb_suspect(sv),
    .I_suspect_x0(sx0),
    .I_suspect_x1(sx1),
    .I_suspect_y0(sy0),
    .I_suspect_y1(sy1),
    .I_suspect_cx(scx),
    .I_suspect_cy(scy),
    .I_ovl_remote('0),
    .I_ovl_shape3('0),
    .I_ovl_shape('0),
    .I_ovl_area('0),
    .I_ovl_confidence('0),
    .I_ovl_conf_tens('0),
    .I_ovl_conf_ones('0),
    .I_multi_valid('0),
    .I_multi_count('0),
    .I_multi_boxes('0),
    .I_multi_toggle('0),
    .I_aux_online('0),
    .I_copy_mode('0),
    .I_copy_state('0),
    .I_operator_valid('0),
    .I_operator_data('0),
    .I_mot_on('0),
    .I_mot_x0('0),
    .I_mot_y0('0),
    .I_mot_x1('0),
    .I_mot_y1('0),
    .I_motion_count('0),
    .I_motion_enable('0),
    .O_video_rd_en(),
    .I_video_rd_data(24'h123456),
    .O_hdmi_vsync(),
    .O_hdmi_hsync(),
    .O_hdmi_de(),
    .O_hdmi_data(rgb));
  hdmi_mixer_control #(.LOGO_ENABLE(0)) base_mix(
    .I_clk(pclk),
    .I_rst_n(rst_n),
    .I_video_vsync('0),
    .I_video_hsync('0),
    .I_video_de(1'b1),
    .I_video_user('0),
    .I_video_last('0),
    .I_video_rd_req('0),
    .I_debug_status('0),
    .I_algo_mode('0),
    .I_he_on('0),
    .I_latency_valid('0),
    .I_latency_frame('0),
    .I_latency_tenth_ms('0),
    .I_latency_toggle('0),
    .I_ovl_on(gate),
    .I_ovl_valid('0),
    .I_ovl_x0('0),
    .I_ovl_y0('0),
    .I_ovl_x1('0),
    .I_ovl_y1('0),
    .I_ovl_cx('0),
    .I_ovl_cy('0),
    .I_ovl_color('0),
    .I_ovl_pcb(pcb_gate),
    .I_pcb_checked('0),
    .I_pcb_good('0),
    .I_pcb_status('0),
    .I_pcb_suspect(sv),
    .I_suspect_x0(sx0),
    .I_suspect_x1(sx1),
    .I_suspect_y0(sy0),
    .I_suspect_y1(sy1),
    .I_ovl_remote('0),
    .I_ovl_shape3('0),
    .I_ovl_shape('0),
    .I_ovl_area('0),
    .I_ovl_confidence('0),
    .I_ovl_conf_tens('0),
    .I_ovl_conf_ones('0),
    .I_multi_valid('0),
    .I_multi_count('0),
    .I_multi_boxes('0),
    .I_multi_toggle('0),
    .I_aux_online('0),
    .I_copy_mode('0),
    .I_copy_state('0),
    .I_operator_valid('0),
    .I_operator_data('0),
    .I_mot_on('0),
    .I_mot_x0('0),
    .I_mot_y0('0),
    .I_mot_x1('0),
    .I_mot_y1('0),
    .I_motion_count('0),
    .I_motion_enable('0),
    .O_video_rd_en(),
    .I_video_rd_data(24'h123456),
    .O_hdmi_vsync(),
    .O_hdmi_hsync(),
    .O_hdmi_de(),
    .O_hdmi_data(rgb_base));

  integer checks=0,pixels=0,changed=0,cases=0;
  task commit;
    reg [21:0] old_centre;
    begin
      old_centre={sv,scy,scx};
      repeat(60)@(posedge pclk);
      #1;if({sv,scy,scx}!==old_centre)$fatal(1,"centre changed outside frame commit");
      @(negedge pclk);frame_start=1;
      @(negedge pclk);frame_start=0;
      #2;
    end
  endtask
  task publish;
    input integer ax,ay,bx,by,checked,good,count;
    begin
      @(negedge nclk);data=0;data[96]=1;data[98]=checked;data[97]=good;
      data[120+:8]=75;data[128+:16]=0;data[144+:16]=0;data[160+:16]=1280;data[176+:16]=720;
      data[240+:8]=count;data[256+:16]=ax;data[272+:16]=ay;data[288+:16]=bx;data[304+:16]=by;
      remote_valid=1;remote_toggle=~remote_toggle;
      commit();
    end
  endtask
  task check_region;
    input integer ax,ay,bx,by,expected;
    begin
      if(sv!==expected[0])$fatal(1,"valid expected %0d got %0d",expected,sv);
      if(expected)begin
        if(sx0!==ax||sy0!==ay||sx1!==bx-1||sy1!==by-1)$fatal(1,"inclusive region mismatch");
        if(scx!==(ax+bx)/2||scy!==(ay+by)/2)$fatal(1,"half-open KEY1 centre mismatch expected %0d %0d got %0d %0d",(ax+bx)/2,(ay+by)/2,scx,scy);
      end else if(scx!==0||scy!==0)$fatal(1,"invalid centre not zero");
      checks=checks+1;
    end
  endtask
  task scan_region;
    input integer ax,ay,bx,by;
    integer ix,iy,inregion,edgehit,crosshit,expecthit;
    begin
      for(iy=(ay>6?ay-6:0);iy<(by+6<720?by+6:720);iy=iy+1)
      for(ix=(ax>6?ax-6:0);ix<(bx+6<1280?bx+6:1280);ix=ix+1)begin
        px=ix;py=iy;#1;
        inregion=ix>=ax&&ix<bx&&iy>=ay&&iy<by;
        edgehit=inregion&&(ix<=ax+2||ix+2>=bx-1||iy<=ay+2||iy+2>=by-1);
        // Independent mathematical oracle: signed integer modulo, not RTL low-bit equality.
        crosshit=inregion&&((ix==((ax+bx)/2)&&((iy-((ay+by)/2))%8)==0)||
                           (iy==((ay+by)/2)&&((ix-((ax+bx)/2))%8)==0));
        expecthit=0; // Suspect border and cross are both retired.
        if(mix.S_suspect_hit!==expecthit[0])$fatal(1,"candidate pixel mismatch %0d %0d",ix,iy);
        if(base_mix.S_suspect_hit!==edgehit[0])$fatal(1,"control border mismatch %0d %0d",ix,iy);
        if(mix.S_suspect_hit!==base_mix.S_suspect_hit)begin
          if(!edgehit)$fatal(1,"unrelated overlay pixel changed");
          changed=changed+1;
        end
        pixels=pixels+1;
      end
      cases=cases+1;
    end
  endtask
  task colour;
    input [23:0] expected;
    begin
      repeat(5)@(posedge pclk);#1;
      if(rgb!==expected)$fatal(1,"priority/RGB expected %h got %h",expected,rgb);
      checks=checks+1;
    end
  endtask
  initial begin
    if($bits({ov,rs,tg,pm,pc,pg,ps,sv,sx0,sx1,sy0,sy1,x0,x1,cx,y0,y1,cy,area,color,shape,cid,ct,co,conf})!=163)
      $fatal(1,"metadata scoreboard width drift");
    force mix.S_x_2d=px;force mix.S_y_2d=py;
    force base_mix.S_x_2d=px;force base_mix.S_y_2d=py;
    force mix.S_osd_hit=prio_osd;force base_mix.S_osd_hit=prio_osd;
    force mix.S_osd_color=24'h112233;force base_mix.S_osd_color=24'h112233;
    force mix.S_mot_edge=prio_motion;force base_mix.S_mot_edge=prio_motion;
    force mix.S_multi_edge=prio_multi;force base_mix.S_multi_edge=prio_multi;
    force mix.S_copy_edge=1'b0;force base_mix.S_copy_edge=1'b0;
    force mix.S_multi_color=24'h445566;force base_mix.S_multi_color=24'h445566;
    force mix.S_corner_c=prio_corner;force base_mix.S_corner_c=prio_corner;
    force mix.S_stat_col_c=24'h778899;force base_mix.S_stat_col_c=24'h778899;
    repeat(6)@(posedge pclk);@(negedge pclk);rst_n=1;
    commit();check_region(0,0,0,0,0);
    publish(100,50,124,82,1,0,1);check_region(100,50,124,82,1);scan_region(100,50,124,82);
    publish(100,50,125,83,1,0,1);check_region(100,50,125,83,1);scan_region(100,50,125,83);
    publish(100,50,124,83,1,0,1);check_region(100,50,124,83,1);scan_region(100,50,124,83);
    publish(100,50,125,82,1,0,1);check_region(100,50,125,82,1);scan_region(100,50,125,82);
    publish(0,0,16,16,1,0,1);check_region(0,0,16,16,1);scan_region(0,0,16,16);
    publish(1264,0,1280,16,1,0,1);check_region(1264,0,1280,16,1);scan_region(1264,0,1280,16);
    publish(0,704,16,720,1,0,1);check_region(0,704,16,720,1);scan_region(0,704,16,720);
    publish(1264,704,1280,720,1,0,1);check_region(1264,704,1280,720,1);scan_region(1264,704,1280,720);
    publish(1,1,2,2,1,0,1);check_region(1,1,2,2,1);scan_region(1,1,2,2);
    publish(240,160,560,340,1,0,1);check_region(240,160,560,340,1);scan_region(240,160,560,340);
    px=scx;py=scy;colour(24'h123456);
    force mix.S_ovl_hit=1'b1;force mix.S_ovl_color=24'h00ff00;
    colour(24'h00ff00);release mix.S_ovl_hit;release mix.S_ovl_color;
    colour(24'h123456);
    prio_multi=1;colour(24'h445566);
    prio_motion=1;colour(24'hff00ff);
    prio_osd=1;colour(24'h112233);
    prio_corner=1;colour(24'h778899);
    prio_multi=0;prio_motion=0;prio_osd=0;prio_corner=0;
    gate=0;#2;if(mix.S_suspect_hit!==0)$fatal(1,"overlay switch bypass");gate=1;
    pcb_gate=0;#2;if(mix.S_suspect_hit!==0)$fatal(1,"PCB mode bypass");pcb_gate=1;
    publish(10,10,10,30,1,0,1);check_region(0,0,0,0,0);
    publish(10,10,1281,30,1,0,1);check_region(0,0,0,0,0);
    publish(10,10,30,721,1,0,1);check_region(0,0,0,0,0);
    publish(10,10,30,30,1,1,1);check_region(0,0,0,0,0); // PASS
    publish(10,10,30,30,0,0,1);check_region(0,0,0,0,0); // REVIEW
    publish(10,10,30,30,1,0,0);check_region(0,0,0,0,0); // no positive region
    publish(10,10,30,30,1,0,1);check_region(10,10,30,30,1);
    @(negedge nclk);remote_clear=1;commit();check_region(0,0,0,0,0);remote_clear=0;
    publish(10,10,30,30,1,0,1);check_region(10,10,30,30,1);
    @(negedge nclk);remote_pcb=0;commit();check_region(0,0,0,0,0);
    @(negedge nclk);remote_pcb=1;commit();publish(10,10,30,30,1,0,1);
    @(negedge nclk);remote_online=0;commit();check_region(0,0,0,0,0);
    @(negedge nclk);remote_online=1;commit();publish(10,10,30,30,1,0,1);
    overlay_enable=0;commit();check_region(0,0,0,0,0);overlay_enable=1;
    publish(10,10,30,30,1,0,1);check_region(10,10,30,30,1);
    @(negedge nclk);remote_valid=0;remote_toggle=~remote_toggle;commit();check_region(0,0,0,0,0);
    if(changed==0)$fatal(1,"no removed border pixels checked");
    $display("SUSPECT_CENTER_PASS checks=%0d pixel_checks=%0d scan_cases=%0d added_cross_pixels=%0d original_metadata_cycles=%0d",checks,pixels,cases,changed,original_compares);
    $finish;
  end
  initial begin #5000000;$fatal(1,"timeout");end
endmodule
