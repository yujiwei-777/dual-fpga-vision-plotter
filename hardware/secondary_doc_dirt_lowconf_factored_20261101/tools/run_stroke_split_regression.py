"""Integer/RTL topology and real document G-code checks, in a fresh library.

The full cases run the production thinning, synchronous banked graph storage,
path extraction, ordering, shared mapper, plotter and GRBL parser/streamer.
The UART peer is a deterministic simulated GRBL peer; no physical machine is
controlled. Reduced-capacity cases and cancel/reset checks are separate tests.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model"))
import doc_stroke_reference as ref

SIM = Path("E:/model/win64")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def fixture():
    a = np.zeros((320, 320), dtype=np.uint8)
    def line(p, q, thickness=1):
        x, y = p
        dx, dy = q[0] - x, q[1] - y
        n = max(abs(dx), abs(dy))
        assert not n or not dx or not dy or abs(dx) == abs(dy)
        for k in range(n + 1):
            xx = x + (0 if dx == 0 else (1 if dx > 0 else -1) * k)
            yy = y + (0 if dy == 0 else (1 if dy > 0 else -1) * k)
            a[yy:yy + thickness, xx:xx + thickness] = 1
    # Junction earlier in raster scan than either endpoint: old odd-degree
    # priority can start in the middle. Two true endpoints are on the bottom.
    for p, q in [((20, 85), (30, 85)), ((20, 85), (20, 100)),
                 ((30, 85), (30, 100)), ((20, 85), (10, 95))]:
        line(p, q)
    # Cross, tee, Y, diagonal X and several original degree-three junctions.
    for ox in (70, 110):
        line((ox - 9, 91), (ox + 9, 91))
        line((ox, 82), (ox, 100 if ox == 70 else 91))
    line((150, 82), (150, 90)); line((150, 90), (140, 100)); line((150, 90), (160, 100))
    line((190, 82), (208, 100)); line((208, 82), (190, 100))
    # A chain of T junctions leaves branches behind after earlier edges have
    # been consumed. The original degree must still control later traversal.
    line((235, 90), (275, 90))
    for x in (240, 250, 260, 270): line((x, 90), (x, 100))
    # Degree-two sharp corners must NOT be split. Closed loop and dot survive.
    line((10, 125), (30, 125)); line((30, 125), (30, 145))
    for p, q in [((60, 125), (80, 125)), ((80, 125), (80, 145)),
                 ((80, 145), (60, 145)), ((60, 145), (60, 125))]: line(p, q)
    a[133, 100] = 1; a[135, 105] = 1
    # Synthetic connected strokes with a triangle/cycle, not a real Qi sample.
    for p, q in [((130, 125), (140, 135)), ((140, 135), (150, 125)),
                 ((130, 125), (150, 125)), ((140, 135), (130, 145)),
                 ((140, 135), (150, 145))]: line(p, q)
    line((185, 128), (210, 128), 3); line((197, 118), (197, 143), 3)
    # Active raster edges and diagonal/corner wrap directions.
    line((0, 70), (8, 78)); line((311, 241), (319, 249))
    line((0, 178), (10, 178)); line((0, 178), (0, 188))
    line((305, 200), (319, 200)); line((319, 200), (319, 216))
    return a


def gcode(stream):
    lines = ["G21", "G90", "G1 Z-001.20 F01200"]
    def formatted(kind, x, y, feed):
        # grbl_line_formatter's single mirror, A4 10..200 mm range.
        x = 21000 - x
        return f"G{kind} X{x//100:03d}.{x%100:02d} Y{y//100:03d}.{y%100:02d} F{feed:05d}"
    for x, y, start, end, dot in stream:
        mx, my = ref.machine((x, y))
        if start:
            lines += [formatted(0, mx, my, 7000), "G1 Z+005.00 F01200"]
            if dot:
                dx = 10 if mx <= 18990 else -10
                lines.append(formatted(1, mx + dx, my, 3000))
        else:
            lines.append(formatted(1, mx, my, 3000))
        if end:
            lines.append("G1 Z-001.20 F01200")
    lines.append("G0 X010.00 Y010.00 F07000")
    return lines


BENCH = r'''`timescale 1ns/1ps
module tb_stroke_split;
reg clk=0; always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0,load_valid=0,load_bit=0,emit_start=0;
reg [16:0] load_addr=0;
wire load_ready,busy,prepared,done,error,point_valid,point_start,point_end,point_dot,point_ready;
wire [8:0] point_x,point_y;
wire [7:0] error_code;
wire [15:0] edge_count; wire [11:0] path_count; wire [13:0] point_count;
wire [63:0] baseline_distance,planned_distance;
wire metric_start,metric_busy,metric_done,metric_a_origin;
wire [8:0] metric_ax,metric_ay,metric_bx,metric_by;
wire [31:0] metric_distance; wire [32:0] metric_squared;
`include "expected.vh"
doc_stroke_planner #(.OPT_PASSES(OPT_PASSES),.EXTERNAL_METRIC(1),.METRIC_DISTANCE_BOUND(32'd23164),
  .MAX_EDGES(LIMIT_EDGES),.MAX_PATHS(LIMIT_PATHS),.MAX_POINTS(LIMIT_POINTS)) dut(.*);
wire mapper_start,mapper_done;
wire [8:0] mapper_x,mapper_y;
wire [15:0] mapper_x_cmm,mapper_y_cmm;
doc_machine_map map(.clk(clk),.rst_n(rst_n),.cancel(cancel),
 .map_start(mapper_start),.map_x(mapper_x),.map_y(mapper_y),
 .map_x_cmm(mapper_x_cmm),.map_y_cmm(mapper_y_cmm),.map_done(mapper_done),
 .dist_start(metric_start),.dist_ax(metric_ax),.dist_ay(metric_ay),.dist_bx(metric_bx),.dist_by(metric_by),
 .dist_a_origin(metric_a_origin),.dist_busy(metric_busy),.dist_done(metric_done),
 .dist_distance(metric_distance),.dist_squared(metric_squared));
reg plot_start=0;
wire plot_busy,plot_done,plot_error,plot_cancelled,recovery_required;
wire [7:0] plot_error_code;wire [2:0] job_state;wire [31:0] acked_lines;
wire [7:0] tx_data,rt_data;wire tx_valid,rt_valid;
reg tx_done=0,rx_valid=0;reg [7:0] rx_data=0;
integer clocks=0;
wire tx_ready=(clocks%7!=1)&&(clocks%11!=2);
wire rt_ready=(clocks%7!=3);
doc_grbl_plotter #(.EXTERNAL_MAPPER(1)) plot(
 .clk(clk),.rst_n(rst_n),.start(plot_start),.cancel(cancel),.rearm(1'b0),.reset_job(1'b0),
 .point_valid(point_valid),.point_x(point_x),.point_y(point_y),.point_start(point_start),
 .point_end(point_end),.point_dot(point_dot),.points_done(done),.point_ready(point_ready),
 .busy(plot_busy),.done(plot_done),.error(plot_error),.cancelled(plot_cancelled),
 .recovery_required(recovery_required),.error_code(plot_error_code),.job_state(job_state),.acked_lines(acked_lines),
 .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.tx_done(tx_done),
 .rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),.link_ready(1'b1),
 .rt_data(rt_data),.rt_valid(rt_valid),.rt_ready(rt_ready),
 .mapper_start(mapper_start),.mapper_x(mapper_x),.mapper_y(mapper_y),
 .mapper_x_cmm(mapper_x_cmm),.mapper_y_cmm(mapper_y_cmm),.mapper_done(mapper_done));
reg image[0:102399],skeleton[0:102399];reg [20:0] expected[0:8191];
integer i,n=0,cycles=0,fh,rawfh,sk_checks=0;
integer reply_delay=0,reply_i=0,reply_len=0,queries=0;
reg [255:0] reply;
reg [20:0] got,held;reg stalled=0;
initial begin
 $readmemh("input.mem",image);$readmemh("skeleton.mem",skeleton);
 if(EXPECT_ERROR==0&&POINT_COUNT>0)$readmemh("expected.mem",expected,0,POINT_COUNT-1);
 fh=$fopen("gcode.txt","w");rawfh=$fopen("raw_paths.txt","w");
 repeat(5)@(negedge clk);rst_n=1;
 for(i=22400;i<80000;i=i+1)begin
   @(negedge clk);if(!load_ready)$fatal(1,"load while not ready");
   load_valid=1;load_addr=i;load_bit=image[i];
 end
 @(negedge clk);load_valid=0;start=1;
 @(negedge clk);start=0;
 while(!prepared&&!error)begin
   @(negedge clk);cycles=cycles+1;
   if(cycles%10000000==0)$display("PROGRESS prep cycles=%0d state=%0d",cycles,dut.state);
   if(cycles>140000000)$fatal(1,"prep watchdog state=%0d",dut.state);
 end
 if(EXPECT_ERROR!=0)begin
   if(!error||error_code!=EXPECT_ERROR||prepared||point_valid)$fatal(1,"capacity release/error mismatch");
   if(n||queries)$fatal(1,"capacity failure released motion");
   $display("PASS capacity error=%0d before motion",error_code);$finish;
 end
 if(error)$fatal(1,"prepare error %0d",error_code);
 if(sk_checks!=57600)$fatal(1,"skeleton checks %0d",sk_checks);
 if(edge_count!=EDGE_COUNT||path_count!=PATH_COUNT||point_count!=POINT_COUNT)
   $fatal(1,"counts %0d/%0d/%0d expected %0d/%0d/%0d",edge_count,path_count,point_count,EDGE_COUNT,PATH_COUNT,POINT_COUNT);
 if(baseline_distance!=BASELINE_DISTANCE||planned_distance!=PLANNED_DISTANCE||planned_distance>baseline_distance)
   $fatal(1,"distance mismatch %0d/%0d expected %0d/%0d",baseline_distance,planned_distance,BASELINE_DISTANCE,PLANNED_DISTANCE);
 repeat(8)begin @(negedge clk);if(!prepared)$fatal(1,"prepared not retained");end
 plot_start=1;emit_start=1;
 @(negedge clk);plot_start=0;emit_start=0;
 while(!plot_done&&!plot_error)begin
   @(negedge clk);cycles=cycles+1;
   if(cycles>145000000)$fatal(1,"plot watchdog");
 end
 if(plot_error||recovery_required)$fatal(1,"plot error %0d",plot_error_code);
 if(n!=POINT_COUNT||acked_lines!=GCODE_LINES||queries!=1)$fatal(1,"emit/ACK/query counts %0d/%0d/%0d",n,acked_lines,queries);
 $fclose(fh);$fclose(rawfh);
 $display("PASS STROKE_SPLIT full thin graph paths mapper Gcode cycles=%0d edges=%0d paths=%0d points=%0d acked=%0d",cycles,edge_count,path_count,point_count,acked_lines);$finish;
end
always @(posedge clk)begin
 clocks<=clocks+1;
 if(rst_n)begin
   if(dut.state==25)begin
     if(dut.nb[8]!==skeleton[(dut.sy+70)*320+dut.sx])$fatal(1,"skeleton mismatch %0d %0d",dut.sx,dut.sy);
     sk_checks=sk_checks+1;
   end
   if(dut.state==58)$fdisplay(rawfh,"POINT %0d %0d",dut.append_x,dut.append_y+70);
   if(dut.state==56)$fdisplay(rawfh,"END %0d %0d",dut.closed_path,dut.path_len);
   got={point_dot,point_end,point_start,point_y,point_x};
   if(stalled&&(!point_valid||got!==held))$fatal(1,"point changed under backpressure");
   stalled=point_valid&&!point_ready;held=got;
   if(point_valid&&point_ready)begin
     if(n>=POINT_COUNT||got!==expected[n])$fatal(1,"point %0d mismatch %06h expected %06h",n,got,expected[n]);
     if(point_x>319||point_y<70||point_y>249)$fatal(1,"outside raster");
     n=n+1;
   end
 end
end
// Simulated stop-and-wait GRBL peer. Responses start well after the UART
// completion edge/response-parser clear. There is no end-of-job Idle reply.
always @(posedge clk)begin
 tx_done<=0;rx_valid<=0;
 if(rst_n)begin
   if(tx_valid&&tx_ready)begin
     tx_done<=1;
     if(tx_data==10)begin
       $fwrite(fh,"\n");
       if(reply_len)$fatal(1,"more than one command in flight");
       reply="";reply[7:0]="o";reply[15:8]="k";reply[23:16]=10;
       reply_i=0;reply_len=3;reply_delay=8;
     end else $fwrite(fh,"%c",tx_data);
   end
   if(rt_valid&&rt_ready)begin
     tx_done<=1;queries=queries+1;
     if(rt_data!=8'h3f||reply_len)$fatal(1,"unexpected realtime command");
     reply="";reply[7:0]="<";reply[15:8]="I";reply[23:16]="d";reply[31:24]="l";reply[39:32]="e";
     reply[47:40]="|";reply[55:48]=">";reply[63:56]=10;
     reply_i=0;reply_len=8;reply_delay=8;
   end
   if(reply_delay>0)reply_delay=reply_delay-1;
   else if(reply_len>0)begin
     rx_valid<=1;rx_data<=reply[reply_i*8+:8];reply_i=reply_i+1;reply_len=reply_len-1;reply_delay=2;
   end
 end
end
endmodule
'''


LIFECYCLE = r'''`timescale 1ns/1ps
module tb_stroke_lifecycle;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0;wire busy,prepared,point_valid,error;
doc_stroke_planner dut(.clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),
 .load_valid(1'b0),.load_addr(17'd0),.load_bit(1'b0),.load_ready(),.emit_start(1'b0),
 .busy(busy),.prepared(prepared),.done(),.error(error),.error_code(),.point_valid(point_valid),
 .point_x(),.point_y(),.point_start(),.point_end(),.point_dot(),.point_ready(1'b0),
 .edge_count(),.path_count(),.point_count(),.baseline_distance(),.planned_distance(),
 .metric_start(),.metric_ax(),.metric_ay(),.metric_bx(),.metric_by(),.metric_a_origin(),
 .metric_busy(1'b0),.metric_done(1'b0),.metric_distance(32'd0),.metric_squared(33'd0));
integer states[0:8];integer i,k,checks=0;
initial begin
 states[0]=40;states[1]=43;states[2]=52;states[3]=59;states[4]=53;
 states[5]=54;states[6]=56;states[7]=171;states[8]=186;
 repeat(3)@(negedge clk);rst_n=1;
 for(k=0;k<2;k=k+1)for(i=0;i<9;i=i+1)begin
   @(negedge clk);dut.state=states[i];dut.busy=1;dut.prepared=1;dut.point_valid=1;
   if(k==0)cancel=1;else rst_n=0;
   @(negedge clk);
   if(busy||prepared||point_valid||dut.state!=0)$fatal(1,"abort failed %0d %0d",k,states[i]);
   if(dut.gwe||dut.pwe||dut.dwe)$fatal(1,"abort left writes pending");
   checks=checks+1;cancel=0;rst_n=1;
   @(negedge clk);if(busy||point_valid)$fatal(1,"abort auto-restarted old task");
 end
 $display("PASS STROKE_LIFECYCLE cancel/reset priority and no replay checks=%0d",checks);$finish;
end
endmodule
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    output = (args.output or ROOT / "02_sim" / ("stroke_split_" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ"))).resolve()
    assert output.is_relative_to(ROOT / "02_sim") and not output.exists()
    output.mkdir(parents=True)
    license_file = SIM / "LICENSE.TXT"
    assert license_file.is_file()
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(license_file), LM_LICENSE_FILE=str(license_file))
    rtl = [ROOT / "01_rtl" / name for name in (
        "doc_stroke_planner.v", "doc_stroke_bram.v", "doc_path_distance.v", "doc_machine_map.v",
        "doc_grbl_plotter.v", "doc_grbl_map.v", "doc_grbl_streamer.v", "doc_grbl_response_parser.v", "grbl_line_formatter.v")]
    inputs = [*rtl, ROOT / "01_rtl/doc_copy_pipeline.v", ROOT / "model/doc_stroke_reference.py", Path(__file__)]
    hashes = {str(p): sha(p) for p in inputs}
    results = {}
    def run(label, cmd, cwd, marker=None):
        process = subprocess.run([str(v) for v in cmd], cwd=cwd, env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (cwd / (label + ".log")).write_text(process.stdout, encoding="utf-8", errors="replace")
        (cwd / (label + "_command.json")).write_text(json.dumps({"command":list(map(str,cmd)),
            "returncode":process.returncode,"log_sha256":sha(cwd/(label+".log"))},indent=2),encoding="utf-8")
        assert process.returncode == 0 and not re.search(r"\*\*\s+(?:Error|Fatal):", process.stdout), process.stdout[-5000:]
        if marker:
            assert marker in process.stdout, process.stdout[-5000:]
        return process.stdout
    images = {"mixed_nn": (fixture(), 0, 32768, 2048, 8192, 0),
              "mixed_two_opt": (fixture(), 2, 32768, 2048, 8192, 0),
              "blank": (np.zeros((320, 320), dtype=np.uint8), 0, 32768, 2048, 8192, 0),
              "edge_capacity": (fixture(), 0, 8, 2048, 8192, 2),
              "path_capacity": (fixture(), 0, 32768, 1, 8192, 3),
              "point_capacity": (fixture(), 0, 32768, 2048, 2, 4)}
    for name, (image, passes, max_e, max_p, max_pt, expect_error) in images.items():
        cwd = output / name; cwd.mkdir()
        golden = ref.prepare(image, plan_passes=passes)
        for file, values in (("input.mem", image.ravel()), ("skeleton.mem", golden["skeleton"].ravel())):
            (cwd / file).write_text("".join(f"{int(v):x}\n" for v in values), encoding="ascii")
        stream = golden["stream"]
        (cwd / "expected.mem").write_text("".join(f"{x|(y<<9)|(s<<18)|(e<<19)|(d<<20):06x}\n" for x,y,s,e,d in stream), encoding="ascii")
        expected_gcode = gcode(stream)
        (cwd / "expected_gcode.txt").write_text("\n".join(expected_gcode)+"\n", encoding="ascii")
        constants = {key.upper(): golden[key] for key in ("edge_count", "path_count", "point_count", "baseline_distance", "planned_distance")}
        constants.update(OPT_PASSES=passes, LIMIT_EDGES=max_e, LIMIT_PATHS=max_p, LIMIT_POINTS=max_pt, EXPECT_ERROR=expect_error, GCODE_LINES=len(expected_gcode))
        (cwd / "expected.vh").write_text("\n".join(f"localparam {key}={value};" for key, value in constants.items())+"\n", encoding="ascii")
        bench = cwd / "tb_stroke_split.sv"; bench.write_text(BENCH, encoding="ascii")
        run("vlib", [SIM / "vlib.exe", "work"], cwd)
        run("compile", [SIM / "vlog.exe", "-sv", "-lint", "+define+DOC_BEHAVIORAL_RAM", "-work", "work", *rtl, bench], cwd)
        log = run("simulate", [SIM / "vsim.exe", "-batch", "-quiet", "-lib", "work", "tb_stroke_split", "-do", "onerror {quit -code 1}; run -all; quit -f"], cwd, "PASS ")
        checks = re.findall(r"PASS[^\r\n]*", log)
        if not expect_error:
            got = (cwd / "gcode.txt").read_text().splitlines()
            assert got == expected_gcode, f"G-code mismatch: {name}"
            raw = []; points = []
            for row in (cwd / "raw_paths.txt").read_text().splitlines():
                tag, v1, v2 = row.split()
                if tag == "POINT": points.append((int(v1), int(v2)))
                else:
                    assert len(points) == int(v2)
                    raw.append(ref.Stroke(tuple(points), bool(int(v1)))); points = []
            assert not points and raw == golden["strokes"], f"raw descriptor paths mismatch: {name}"
            recovered, dots = ref.expand_stream(stream)
            assert recovered == ref.graph_edges(golden["skeleton"])
            results[name] = {"status":"PASS", "checks": checks, "edges":golden["edge_count"],
                             "paths":golden["path_count"], "points":golden["point_count"], "gcode_lines":len(got),
                             "baseline_distance_cmm":golden["baseline_distance"], "planned_distance_cmm":golden["planned_distance"]}
        else: results[name] = {"status":"PASS", "expected_error":expect_error, "checks":checks}
        print(name + ": " + checks[-1], flush=True)
    cwd=output/"lifecycle";cwd.mkdir()
    bench=cwd/"tb_stroke_lifecycle.sv";bench.write_text(LIFECYCLE,encoding="ascii")
    run("vlib",[SIM/"vlib.exe","work"],cwd)
    run("compile",[SIM/"vlog.exe","-sv","-lint","+define+DOC_BEHAVIORAL_RAM","-work","work",*rtl,bench],cwd)
    log=run("simulate",[SIM/"vsim.exe","-batch","-quiet","-lib","work","tb_stroke_lifecycle","-do","onerror {quit -code 1}; run -all; quit -f"],cwd,"PASS STROKE_LIFECYCLE")
    results["lifecycle"]={"status":"PASS","checks":re.findall(r"PASS[^\r\n]*",log),
                          "scope":"priority checks by state injection; full cases exercise live traversal separately"}
    assert all(sha(Path(p))==digest for p,digest in hashes.items()), "test input drift"
    (output/"RESULTS.json").write_text(json.dumps({"status":"PASS","hardware_status":"NOT_RUN",
        "input_sha256":hashes,"tests":results,"scope":__doc__.strip()},indent=2),encoding="utf-8")
    print("PASS stroke split regression: " + str(output),flush=True)


if __name__ == "__main__":
    main()
