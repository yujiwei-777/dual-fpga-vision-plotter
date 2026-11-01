`timescale 1ns/1ps
module tb_mixer_regression;
    `include "signals.vh"
    `include "instances.vh"
    integer phase=-1,stream_pixels=0,compared=0,green_edges=0;
    integer total_pixels=0,total_compared=0,frames=0,hidden_pixels=0;
    integer out_x,out_y,x,y,i,k,mode,st;
    integer capture_n=0,capture_b=0;
    integer width=1280,height=720;
    reg capture=0,monitor=0,dark=0,static_render=0;
    reg [11:0] forced_x=0,forced_y=0;
    reg [4:0] de_pipe=0,hs_pipe=0,vs_pipe=0;
    reg [23:0] expected;
    reg masked;
    integer metadata_checks=0;
    reg [15:0] expected_frame=16'd65535,expected_latency=16'h1234;
    reg expected_lat_valid=1;
    always #5 I_clk=~I_clk;

    function [23:0] background(input integer px,py,input bit lowlight);
        reg [7:0] r,g,b;
        begin
            if(lowlight)begin r=20+px/64;g=24+py/36;b=32+(px+py)/80;end
            else begin r=150+px/32;g=158+py/24;b=176+(px+py)/48;end
            background={r,g,b};
        end
    endfunction

    function [19:0] decimal5(input integer value);
        integer digit,j;
        begin
            decimal5=0;
            for(j=0;j<5;j=j+1)begin digit=value%10;decimal5[j*4+:4]=digit;value=value/10;end
        end
    endfunction

    task check_metadata(input bit decimal_ready);
        begin
            if(dut_N.S_lat_frame!==expected_frame||dut_N.S_lat_bcd!==expected_latency||dut_N.S_lat_valid!==expected_lat_valid)
                $fatal(1,"LATENCY_MAILBOX_MISMATCH phase=%0d frame=%0d latency=%h valid=%b expected=%0d/%h/%b",phase,dut_N.S_lat_frame,dut_N.S_lat_bcd,dut_N.S_lat_valid,expected_frame,expected_latency,expected_lat_valid);
            if(decimal_ready&&dut_N.S_frame_decimal!==decimal5(expected_frame))
                $fatal(1,"FRAME_DECIMAL_STALE phase=%0d got=%h expected=%h",phase,dut_N.S_frame_decimal,decimal5(expected_frame));
            metadata_checks=metadata_checks+1;
        end
    endtask

    function bit changed_region(input integer px,py);
        begin changed_region=((px>=862&&px<=1202&&py>=62&&py<=274)||
                              (px>=22&&px<=346&&py>=558&&py<=698));end
    endfunction

    task idle(input integer clocks);
        begin
            @(negedge I_clk);I_video_de=0;I_video_user=0;I_video_last=0;I_video_rd_req=0;
            repeat(clocks) @(negedge I_clk);
        end
    endtask

    task defaults;
        begin
            I_video_vsync=0;I_video_hsync=0;I_video_de=0;I_video_user=0;I_video_last=0;I_video_rd_req=0;
            I_debug_status=0;I_algo_mode=18;I_he_on=1;
            I_latency_valid=1;I_latency_frame=16'd65535;I_latency_tenth_ms=16'd1234;
            I_ovl_on=1;I_ovl_valid=1;I_ovl_x0=480;I_ovl_y0=230;I_ovl_x1=800;I_ovl_y1=450;
            I_ovl_cx=640;I_ovl_cy=340;I_ovl_color=1;I_ovl_pcb=0;I_pcb_checked=0;I_pcb_good=0;
            I_pcb_status=0;I_ovl_remote=1;I_ovl_shape3=2;I_ovl_shape=0;I_ovl_area=24'd70400;
            I_ovl_confidence=97;I_ovl_conf_tens=9;I_ovl_conf_ones=7;
            I_multi_valid=0;I_multi_count=0;I_multi_boxes=0;I_aux_online=0;I_multi_toggle=~I_multi_toggle;
            I_copy_mode=0;I_copy_state=0;I_mot_on=0;I_mot_x0=100;I_mot_y0=300;I_mot_x1=260;I_mot_y1=480;
            I_motion_count=16'd12345;I_motion_enable=1;
        end
    endtask

    task start_frame;
        begin
            idle(12);I_video_vsync=1;I_video_user=1;
            @(negedge I_clk);I_video_user=0;
            repeat(128)@(negedge I_clk);
            I_video_vsync=0;repeat(8)@(negedge I_clk);
        end
    endtask

    task run_stream(input integer id,input bit save_images);
        begin
            phase=id;stream_pixels=0;compared=0;green_edges=0;hidden_pixels=0;static_render=0;
            if(save_images)begin
                capture_n=$fopen($sformatf("new_frame_%0d.rgb",id),"w");
                capture_b=$fopen($sformatf("baseline_frame_%0d.rgb",id),"w");capture=1;
            end
            start_frame();check_metadata(0);monitor=1;
            for(y=0;y<720;y=y+1)begin
                if(id==5&&y==350)begin
                    I_ovl_pcb=1;I_pcb_status=7;
                    I_latency_frame=31415;I_latency_tenth_ms=42;I_latency_toggle=~I_latency_toggle;
                end
                for(x=0;x<1280;x=x+1)begin
                    @(negedge I_clk);I_video_de=1;I_video_rd_req=1;
                    I_video_last=(x==1279);I_video_rd_data=background(x,y,dark);
                end
                @(negedge I_clk);I_video_de=0;I_video_rd_req=0;I_video_last=0;I_video_hsync=1;
                repeat(12)@(negedge I_clk);I_video_hsync=0;
            end
            idle(12);monitor=0;
            if(stream_pixels!=921600)$fatal(1,"STREAM_PIXEL_COUNT phase=%0d got=%0d",phase,stream_pixels);
            if(compared<700000)$fatal(1,"INSUFFICIENT_BASELINE_COMPARISON phase=%0d got=%0d",phase,compared);
            if(id==1&&hidden_pixels!=8064)$fatal(1,"MOTION_HIDE_COVERAGE got=%0d",hidden_pixels);
            if(id==2&&green_edges<8000)$fatal(1,"PCB_FIXED_FRAME_COVERAGE got=%0d",green_edges);
            if(capture)begin $fclose(capture_n);$fclose(capture_b);capture=0;end
            total_pixels=total_pixels+stream_pixels;total_compared=total_compared+compared;frames=frames+1;
            $display("MIXER_FRAME_PASS id=%0d pixels=%0d baseline_equal=%0d pcb_edges=%0d hidden_motion=%0d",id,stream_pixels,compared,green_edges,hidden_pixels);
        end
    endtask

    task render_window(input integer kind,index,xx,yy,ww,hh);
        begin
            monitor=0;static_render=1;phase=100+kind;width=ww;height=hh;stream_pixels=0;
            start_frame();
            // Exercise the real first-line snapshot before forced crop coordinates.
            for(i=0;i<120;i=i+1)begin
                @(negedge I_clk);I_video_de=1;I_video_rd_req=1;I_video_rd_data=background(i,0,dark);
            end
            idle(12);check_metadata(1);
            capture_n=$fopen($sformatf("crop_%0d_%0d.rgb",kind,index),"w");capture_b=0;capture=1;monitor=1;
            force dut_N.S_x=forced_x;force dut_N.S_y=forced_y;
            force dut_B.S_x=forced_x;force dut_B.S_y=forced_y;
            for(y=0;y<hh;y=y+1)begin
                for(x=0;x<ww;x=x+1)begin
                    @(negedge I_clk);forced_x=xx+x;forced_y=yy+y;I_video_de=1;I_video_rd_req=1;
                    I_video_rd_data=background(xx+x,yy+y,dark);
                end
            end
            idle(12);monitor=0;capture=0;$fclose(capture_n);
            release dut_N.S_x;release dut_N.S_y;release dut_B.S_x;release dut_B.S_y;
            if(stream_pixels!=ww*hh)$fatal(1,"STATIC_PIXEL_COUNT kind=%0d id=%0d got=%0d",kind,index,stream_pixels);
            $display("MIXER_CROP_PASS kind=%0d id=%0d pixels=%0d",kind,index,stream_pixels);
        end
    endtask

    always @(posedge I_clk)begin
        if(!I_rst_n)begin de_pipe=0;hs_pipe=0;vs_pipe=0;end
        else begin
            de_pipe={de_pipe[3:0],I_video_de};hs_pipe={hs_pipe[3:0],I_video_hsync};vs_pipe={vs_pipe[3:0],I_video_vsync};
            #1;
            if(monitor)begin
                if({N_O_hdmi_de,N_O_hdmi_hsync,N_O_hdmi_vsync}!=={B_O_hdmi_de,B_O_hdmi_hsync,B_O_hdmi_vsync})
                    $fatal(1,"NEW_BASELINE_SYNC_MISMATCH phase=%0d",phase);
                if({N_O_hdmi_de,N_O_hdmi_hsync,N_O_hdmi_vsync}!=={de_pipe[4],hs_pipe[4],vs_pipe[4]})
                    $fatal(1,"VIDEO_LATENCY_MISMATCH phase=%0d",phase);
                if(N_O_video_rd_en!==I_video_rd_req||N_O_video_rd_en!==B_O_video_rd_en)
                    $fatal(1,"READ_REQUEST_CHANGED phase=%0d",phase);
                if(N_O_hdmi_de)begin
                    out_x=stream_pixels%width;out_y=stream_pixels/width;
                    if(capture)begin
                        $fdisplay(capture_n,"%06h",N_O_hdmi_data);
                        if(capture_b!=0)$fdisplay(capture_b,"%06h",B_O_hdmi_data);
                    end
                    if(!static_render)begin
                        if(out_x==120)check_metadata(1);
                        masked=changed_region(out_x,out_y);
                        if(phase==4)begin
                            for(k=0;k<4;k=k+1)begin
                                if(dut_N.u_multi_overlay.badge_y[k]!=dut_B.u_multi_overlay.badge_y[k])begin
                                    if(out_x>=dut_N.u_multi_overlay.badge_x[k]-2&&out_x<dut_N.u_multi_overlay.badge_x[k]+146&&
                                        ((out_y>=dut_N.u_multi_overlay.badge_y[k]-2&&out_y<dut_N.u_multi_overlay.badge_y[k]+18)||
                                         (out_y>=dut_B.u_multi_overlay.badge_y[k]-2&&out_y<dut_B.u_multi_overlay.badge_y[k]+18)))masked=1;
                                end
                            end
                        end
                        if(!masked)begin
                            if(N_O_hdmi_data!==B_O_hdmi_data)$fatal(1,"OSD_OUTSIDE_RGB_MISMATCH phase=%0d x=%0d y=%0d new=%h old=%h",phase,out_x,out_y,N_O_hdmi_data,B_O_hdmi_data);
                            compared=compared+1;
                        end
                        if(phase==0&&out_x<400&&out_y>170&&out_y<290)begin
                            expected=background(out_x,out_y,dark);
                            if(N_O_hdmi_data!==expected)$fatal(1,"VIDEO_DATA_MISALIGN x=%0d y=%0d got=%h expected=%h",out_x,out_y,N_O_hdmi_data,expected);
                        end
                        if(phase==1&&out_x>=864&&out_x<1200&&out_y>=168&&out_y<192)begin
                            expected=background(out_x,out_y,dark);
                            if(N_O_hdmi_data!==expected)$fatal(1,"MOTION_ROW_NOT_HIDDEN x=%0d y=%0d got=%h",out_x,out_y,N_O_hdmi_data);
                            hidden_pixels=hidden_pixels+1;
                        end
                        if(phase==2&&out_x>=158&&out_x<=1113&&out_y>=140&&out_y<=551&&
                           (out_x<=161||out_x>=1110||out_y<=143||out_y>=548))begin
                            if(N_O_hdmi_data!==24'h00ff00)$fatal(1,"PCB_FIXED_FRAME_CHANGED x=%0d y=%0d got=%h",out_x,out_y,N_O_hdmi_data);
                            green_edges=green_edges+1;
                        end
                    end
                    stream_pixels=stream_pixels+1;
                end
            end
        end
    end

    initial begin
        I_rst_n=0;defaults();repeat(8)@(negedge I_clk);I_rst_n=1;idle(12);
        I_latency_toggle=1;idle(160);
        dark=0;run_stream(0,1);
        defaults();dark=1;I_ovl_valid=0;I_ovl_on=0;I_motion_enable=0;I_latency_valid=0;I_latency_toggle=~I_latency_toggle;expected_lat_valid=0;run_stream(1,1);
        defaults();I_latency_frame=12;I_latency_tenth_ms=9876;I_latency_toggle=~I_latency_toggle;expected_frame=12;expected_latency=16'h9876;expected_lat_valid=1;I_ovl_pcb=1;I_pcb_status=2;I_pcb_checked=1;I_pcb_good=1;I_ovl_x0=158;I_ovl_x1=1113;I_ovl_y0=140;I_ovl_y1=551;I_ovl_cx=635;I_ovl_cy=345;run_stream(2,0);
        defaults();I_ovl_valid=0;I_ovl_on=0;I_copy_mode=1;I_copy_state=2;run_stream(3,0);
        defaults();I_multi_valid=1;I_multi_count=4;I_ovl_valid=0;
        I_multi_boxes[0+:128]={32'd10000,8'd0,8'd99,16'd2,16'd300,16'd1100,16'd230,16'd900};
        I_multi_boxes[128+:128]={32'd10000,8'd0,8'd87,16'd6,16'd400,16'd400,16'd200,16'd200};
        I_multi_boxes[256+:128]={32'd10000,8'd0,8'd75,16'd7,16'd650,16'd780,16'd500,16'd600};
        I_multi_boxes[384+:128]={32'd10000,8'd0,8'd61,16'd1,16'd710,16'd1279,16'd600,16'd1120};
        idle(16);
        if(dut_N.u_multi_overlay.badge_y[0]!=214||dut_B.u_multi_overlay.badge_y[0]!=300)$fatal(1,"MULTIBOX_COMPACT_AVOIDANCE_MISSING");
        run_stream(4,0);
        defaults();I_ovl_valid=0;I_ovl_on=0;run_stream(5,0);
        defaults();I_ovl_on=0;I_ovl_cx=1280;I_ovl_cy=720;I_ovl_area=921600;I_motion_count=65535;I_latency_valid=1;I_latency_frame=31415;I_latency_tenth_ms=42;expected_frame=31415;expected_latency=16'h0042;run_stream(6,0);
        defaults();I_ovl_on=0;I_ovl_valid=0;dark=1;I_latency_valid=1;I_latency_toggle=~I_latency_toggle;expected_frame=65535;expected_latency=16'h1234;
        for(mode=0;mode<19;mode=mode+1)begin I_algo_mode=mode;render_window(0,mode,864,64,336,128);end
        defaults();I_ovl_pcb=1;I_ovl_on=0;
        for(st=0;st<8;st=st+1)begin I_pcb_status=st;render_window(1,st,24,584,288,96);end
        defaults();I_ovl_on=0;I_motion_enable=0;render_window(2,0,864,64,336,128);
        I_motion_enable=1;render_window(2,1,864,64,336,128);
        $display("TB_MIXER_REGRESSION_PASS frames=%0d stream_pixels=%0d outside_rgb_compared=%0d crops=29 metadata_checks=%0d",frames,total_pixels,total_compared,metadata_checks);
        $finish;
    end
    initial begin #250000000;$fatal(1,"TIMEOUT");end
endmodule
