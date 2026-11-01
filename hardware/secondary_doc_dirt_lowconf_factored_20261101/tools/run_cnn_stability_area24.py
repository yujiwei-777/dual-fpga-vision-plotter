"""Compare active AREA24 production configuration with frozen full-width R3."""
from pathlib import Path
import hashlib
import json
import os
import random
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/cnn_stability_area24"
OUT.mkdir(parents=True, exist_ok=True)
OLD = ROOT / "cnn_stability_r3_Runs_20261031/frozen_build_inputs/01_rtl/cnn_result_stabilizer.v"
NEW = ROOT / "01_rtl/cnn_result_stabilizer.v"
SIM = Path("E:/model/win64")
PARAMS = [(1, 0, 1), (2, 1, 2), (3, 2, 3), (4, 0, 4), (15, 15, 15)]
# R10 retains the generic COORD_SHIFT=0 contract for this AREA24/R3 comparison.
# The separate production-grid suite verifies the exact COORD_SHIFT=3 mode.
assert hashlib.sha256(NEW.read_bytes()).hexdigest().upper() == "8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36"
inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in (OLD, NEW)}
old_copy = OUT / "cnn_result_stabilizer_R1.sv"
old_copy.write_text(OLD.read_text().replace("module cnn_result_stabilizer #(", "module cnn_result_stabilizer_R1 #(", 1))


def box(x=100, y=100, cls=2, conf=70, area=10000):
    return x | (y << 16) | ((x+100) << 32) | ((y+100) << 48) | (cls << 64) | (conf << 80) | (area << 96)


events = []
raw_trace = ROOT / "02_sim/cnn_stability/reference_trace.jsonl"
real_count = 0
for line in raw_trace.read_text(encoding="utf-8").splitlines():
    row = json.loads(line)
    if row["group"] != "raw_replay":
        continue
    packed = int(row["input"], 16)
    for index in range(min(row["count"], 4)):
        assert ((packed >> (128*index+96)) & 0xffffffff) < (1<<24)
    events.append((row["op"], row["count"], packed))
    real_count += row["op"] == 0
assert real_count == 1170
for cls, conf, n in [(2, 70, 20), (3, 71, 20), (3, 0, 20), (3, 71, 20)]:
    events.extend((0, 1, box(cls=cls, conf=conf)) for _ in range(n))
events.extend((0, 0, 0) for _ in range(20))
events.extend((0, 1, box(cls=9)) for _ in range(20))
events.append((1, 0, 0))
events.extend((0, 4, sum(box(x=50+i*250, cls=i+1, conf=30+i*10, area=(1<<24)-1-i) << (128*i) for i in range(4))) for _ in range(20))
rng = random.Random(20261031)
for i in range(300):
    count = rng.randrange(5)
    candidates = [box(x=50+j*250+rng.randrange(6), cls=rng.randrange(1,10), conf=rng.choice([0,50,80]), area=rng.randrange(1<<24)) for j in range(count)]
    rng.shuffle(candidates)
    events.append((1 if i%41==0 else 0, count, sum(v << (128*j) for j,v in enumerate(candidates))))
(OUT / "parameter_vectors.txt").write_text("\n".join(f"{op} {count} {packed:0128x}" for op,count,packed in events)+"\n")

inst = []
for i,(confirm,hold,lost) in enumerate(PARAMS):
    for kind,mod in [("old", "cnn_result_stabilizer_R1"),("new", "cnn_result_stabilizer")]:
        inst.append(f"{mod} #(.CONFIRM_RESULTS({confirm}),.HOLD_RESULTS({hold}),.LOST_RESULTS({lost})" + (",.AREA_BITS(24)" if kind=="new" else "") + f") {kind}_{i}("
                    f".clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.input_count(input_count),.input_boxes(input_boxes),"
                    f".busy({kind}_busy[{i}]),.done({kind}_done[{i}]),.output_count({kind}_count[{i}]),"
                    f".output_boxes({kind}_boxes[{i}]),.uncertain({kind}_uncertain[{i}]));")
bench = OUT / "tb_parameter_equivalence.sv"
bench.write_text(r'''`timescale 1ns/1ps
module tb_parameter_equivalence;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,clear=0,start=0;
reg [2:0] input_count=0;
reg [511:0] input_boxes=0;
wire [4:0] old_busy,old_done,old_uncertain,new_busy,new_done,new_uncertain;
wire [2:0] old_count[0:4],new_count[0:4];
wire [511:0] old_boxes[0:4],new_boxes[0:4];
reg [4:0] old_seen,new_seen;
reg [2:0] old_saved_count[0:4],new_saved_count[0:4];
reg [511:0] old_saved_boxes[0:4],new_saved_boxes[0:4];
reg old_saved_uncertain[0:4],new_saved_uncertain[0:4];
integer fd,ret,op,n,count,cycles,j,checks=0;
reg [511:0] packed_input;
''' + "\n".join(inst) + r'''
initial begin
 repeat(3)@(negedge clk);rst_n=1;
 fd=$fopen("parameter_vectors.txt","r");if(!fd)$fatal(1,"no vectors");
 while(!$feof(fd))begin
  ret=$fscanf(fd,"%d %d %h\n",op,count,packed_input);
  if(ret==3)begin
   @(negedge clk);input_count=count;input_boxes=packed_input;
   if(op==1)begin
    clear=1;start=1;@(negedge clk);clear=0;start=0;
    if(old_busy||new_busy||old_done||new_done)$fatal(1,"clear control mismatch");
    for(j=0;j<5;j=j+1)
     if(old_count[j]!==0||new_count[j]!==0||old_boxes[j]!==0||new_boxes[j]!==0)$fatal(1,"clear payload mismatch");
   end else begin
    start=1;@(negedge clk);start=0;
    old_seen=0;new_seen=0;cycles=0;
    while((old_seen!=5'b11111||new_seen!=5'b11111)&&cycles<2000)begin
     @(negedge clk);cycles=cycles+1;
     for(j=0;j<5;j=j+1)begin
      if(old_done[j])begin old_seen[j]=1;old_saved_count[j]=old_count[j];old_saved_boxes[j]=old_boxes[j];old_saved_uncertain[j]=old_uncertain[j];end
      if(new_done[j])begin new_seen[j]=1;new_saved_count[j]=new_count[j];new_saved_boxes[j]=new_boxes[j];new_saved_uncertain[j]=new_uncertain[j];end
     end
    end
    if(cycles>=2000)$fatal(1,"latency timeout");
    for(j=0;j<5;j=j+1)begin
     if(old_saved_count[j]!==new_saved_count[j]||old_saved_boxes[j]!==new_saved_boxes[j]||old_saved_uncertain[j]!==new_saved_uncertain[j])
      $fatal(1,"R1/R2 mismatch vector=%0d parameter_set=%0d old=%h/%h/%b new=%h/%h/%b",checks,j,old_saved_count[j],old_saved_boxes[j],old_saved_uncertain[j],new_saved_count[j],new_saved_boxes[j],new_saved_uncertain[j]);
     checks=checks+1;
    end
   end
  end
 end
 $display("PASS R3_COMPACT_AREA24_EQUIVALENCE checks=%0d",checks);$finish;
end
endmodule
''')
closure_inputs = [OLD, NEW, old_copy, raw_trace, Path(__file__), bench, OUT/"parameter_vectors.txt"]
frozen_closure = {str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in closure_inputs}
env = os.environ.copy()
env.update(MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"), LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"))
for name,args in [("param_vlib",[SIM/"vlib.exe",OUT/"paramwork"]),
                  ("param_compile",[SIM/"vlog.exe","-sv","-lint","-work",OUT/"paramwork",old_copy,NEW,bench]),
                  ("param_simulate",[SIM/"vsim.exe","-batch","-syncio","-quiet","-novopt","-suppress","12110","-lib",OUT/"paramwork","tb_parameter_equivalence","-do","onerror {quit -code 1}; run -all; quit -f"])]:
    proc = subprocess.run([str(a) for a in args],cwd=OUT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    (OUT/(name+".log")).write_text(proc.stdout)
    if proc.returncode or re.search(r"\*\* (?:Error|Fatal):",proc.stdout):
        raise RuntimeError(proc.stdout[-6000:])
assert inputs == {str(p): hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in (OLD,NEW)}
assert frozen_closure == {str(p):hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in closure_inputs}
summary={"status":"PASS","input_hashes":frozen_closure,"parameters":PARAMS,"events":len(events),
         "checks":re.search(r"PASS R3_COMPACT_AREA24_EQUIVALENCE checks=(\d+)",proc.stdout).group(1),
         "hardware_status":"NOT_RUN", "area_bits":24,"real_frames":real_count,"production_candidate_applied":True}
(OUT/"RESULTS.json").write_text(json.dumps(summary,indent=2))
print(json.dumps(summary))
