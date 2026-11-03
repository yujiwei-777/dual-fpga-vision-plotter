`timescale 1ns/1ps
module tb_display_spatial;
    parameter integer WIDTH=1280, HEIGHT=720, COUNT=1;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,vs=0,hs=0,de=0,user=0,last=0;
    reg [23:0] data=0;
    wire ov,oh,od,ou,ol,bv,bh,bd,bu,bl;
    wire [23:0] output_data,bypass_data;
    a4_display_spatial_h1 #(.EDGE_TH(16),.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_vsync(vs),.I_hsync(hs),.I_de(de),
        .I_user(user),.I_last(last),.I_data(data),.O_vsync(ov),.O_hsync(oh),
        .O_de(od),.O_user(ou),.O_last(ol),.O_data(output_data));
    a4_display_spatial_h1 #(.ENABLE(0),.EDGE_TH(16),.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) bypass(
        .I_clk(clk),.I_rst_n(rst_n),.I_vsync(vs),.I_hsync(hs),.I_de(de),
        .I_user(user),.I_last(last),.I_data(data),.O_vsync(bv),.O_hsync(bh),
        .O_de(bd),.O_user(bu),.O_last(bl),.O_data(bypass_data));
    wire fv,fh,fd,fu,fl;
    wire [23:0] frozen_data;
    a4_display_spatial_frozen #(.EDGE_TH(16),.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) frozen(
        .I_clk(clk),.I_rst_n(rst_n),.I_vsync(vs),.I_hsync(hs),.I_de(de),
        .I_user(user),.I_last(last),.I_data(data),.O_vsync(fv),.O_hsync(fh),
        .O_de(fd),.O_user(fu),.O_last(fl),.O_data(frozen_data));
    integer aa,bb;
    initial begin
        for(aa=0;aa<256;aa=aa+1)begin
            for(bb=0;bb<256;bb=bb+1)begin
                if(dut.avg2(aa[7:0],bb[7:0])!==frozen.avg2(aa[7:0],bb[7:0]))
                    $fatal(1,"avg2 exhaustive mismatch a=%0d b=%0d",aa,bb);
            end
        end
        $display("PASS exhaustive RTL avg2 pairs=65536");
    end
    reg [31:0] stimulus[0:COUNT-1],golden[0:COUNT-1],source_golden[0:COUNT-1];
    integer i,valid_pixels=0,starts=0,ends=0;
    string stimulus_path, golden_path, source_path;
    initial begin
        if(!$value$plusargs("STIM=%s",stimulus_path))$fatal(1,"Missing STIM");
        if(!$value$plusargs("GOLD=%s",golden_path))$fatal(1,"Missing GOLD");
        if(!$value$plusargs("SOURCE=%s",source_path))$fatal(1,"Missing SOURCE");
        $readmemh(stimulus_path,stimulus);
        $readmemh(golden_path,golden);
        $readmemh(source_path,source_golden);
        for(i=0;i<COUNT;i=i+1)begin
            @(negedge clk);
            {rst_n,vs,hs,de,user,last}=stimulus[i][31:26];
            data=stimulus[i][23:0];
            @(posedge clk); #1;
            if({ov,oh,od,ou,ol,output_data}!=={fv,fh,fd,fu,fl,frozen_data})
                $fatal(1,"frozen all-cycle output mismatch cycle=%0d de=%b got=%h expected=%h",i,od,output_data,frozen_data);
            if($isunknown(output_data))$fatal(1,"unknown output_data cycle=%0d de=%b",i,od);
            if({ov,oh,od,ou,ol}!==golden[i][28:24])
                $fatal(1,"marker mismatch cycle=%0d got=%b expected=%b",i,{ov,oh,od,ou,ol},golden[i][28:24]);
            if({bv,bh,bd,bu,bl}!==source_golden[i][28:24])
                $fatal(1,"bypass marker mismatch cycle=%0d",i);
            if(od)begin
                valid_pixels=valid_pixels+1;
                if(output_data!==golden[i][23:0])
                    $fatal(1,"pixel mismatch cycle=%0d got=%h expected=%h",i,output_data,golden[i][23:0]);
                if(bypass_data!==source_golden[i][23:0])
                    $fatal(1,"ENABLE=0 changed pixel cycle=%0d",i);
            end
            if(ou)starts=starts+1;
            if(ol)ends=ends+1;
        end
        $display("PASS pixel oracle WIDTH=%0d HEIGHT=%0d cycles=%0d valid=%0d sof=%0d eol=%0d all_markers_and_ENABLE0_checked frozen_all_cycles_including_invalid_data_equal",WIDTH,HEIGHT,COUNT,valid_pixels,starts,ends);
        $finish;
    end
endmodule
