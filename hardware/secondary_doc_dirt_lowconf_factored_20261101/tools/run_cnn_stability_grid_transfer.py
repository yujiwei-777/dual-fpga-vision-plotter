"""Production grid transfer regression, adapted from the reviewed scratch helper.

The candidate is compiled directly from 01_rtl; baseline/old evidence are read
only. Generated benches and simulator work files stay in the new suite.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

from cnn_stability_grid_common import ROOT, prepare_out, replace_exact
COMMON = ROOT / "tools/cnn_stability_grid_common.py"


def main():
    HERE = ROOT / "reports/coordinate_grid_review"
    OUT = prepare_out("transfer")
    SOURCE = ROOT / "01_rtl/cnn_result_stabilizer.v"
    BASE = HERE / "scratch/cnn_result_stabilizer_baseline.v"
    MITER = HERE / "scratch/tb_coordinate_grid_equivalence.sv"
    SIM = Path("E:/model/win64")
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"), LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"))
    body = r'''
    function [511:0] four_boxes;
     integer i;reg [15:0] x0,x1,y0,y1,cls;reg[31:0] area;
     begin
      four_boxes=0;
      for(i=0;i<4;i=i+1)begin
       x0=96+256*i;x1=x0+96;y0=208;y1=304;cls=2+2*i;area=1000+i;
       four_boxes[128*i+:128]={area,8'd0,8'd72,cls,y1,x1,y0,x0};
      end
     end
    endfunction
    integer target_kind,reset_kind,transfer_boundaries=0,fresh_frames=0;
    task acquire_fresh;integer j;begin
     for(j=0;j<CONFIRM_RESULTS;j=j+1)begin
      frame(4,four_boxes(),0);
      if(output_count[0]!==((j==CONFIRM_RESULTS-1)?3'd4:3'd0)||
         output_count[1]!==((j==CONFIRM_RESULTS-1)?3'd4:3'd0))
       $fatal(1,"stale history survived transfer abort j%0d",j);
      fresh_frames=fresh_frames+1;
     end
    end endtask
    task launch_four;begin
     @(negedge clk);compare_enable=1;input_count=4;source_boxes=four_boxes();start=1;
     @(negedge clk);start=0;
     if(busy!==2'b11)$fatal(1,"transfer frame not accepted");
    end endtask
    task wait_target(input integer kind);begin
     cycles=0;
     if(kind==0)begin
      while(baseline.state!=baseline.S_PAIR_WAIT)begin @(negedge clk);cycles=cycles+1;end
     end else if(kind==1||kind==2)begin
      while(!emit_begin[0])begin @(negedge clk);cycles=cycles+1;end
      if(kind==2)begin
       @(negedge clk);
       if(bank[0]!==0||bank[1]!==0)$fatal(1,"emit_begin failed to destroy raw input bank");
      end
     end else if(kind==3||kind==4||kind==5)begin
      while(!(emit_valid[0]&&emit_slot[0]==(kind==3?0:3)))begin @(negedge clk);cycles=cycles+1;end
      if(kind==5)begin
       @(negedge clk);
       if(received_mask[0]!==4'hf||received_mask[1]!==4'hf)
        $fatal(1,"last serial slot was not committed before abort");
      end
     end else if(kind==6)begin
      while(baseline.state!=baseline.S_FINISH)begin @(negedge clk);cycles=cycles+1;end
     end else begin
      while(!done[0])begin @(negedge clk);cycles=cycles+1;end
     end
     if(cycles>=2000)$fatal(1,"transfer target missing kind%0d",kind);
    end endtask
    task abort_here(input integer reset_it);begin
     // Called on a negative edge at the selected pre/post commit boundary.
     compare_enable=0;start=1;if(reset_it)rst_n=0;else clear=1;
     #1;
     if(baseline.payload_we||candidate.payload_we||baseline.metadata_we||candidate.metadata_we||emit_begin||emit_valid)
      $fatal(1,"transfer abort leaked RAM or serial side effect");
     repeat(3)@(negedge clk);
     if(busy||done||output_count[0]||output_count[1]||output_boxes[0]||output_boxes[1]||
        baseline.track_used||candidate.track_used)
      $fatal(1,"held transfer abort did not invalidate output/history");
     rst_n=1;clear=0;start=0;
     repeat(5)begin
      @(negedge clk);
      if(busy||done||emit_begin||emit_valid||output_count[0]||output_count[1]||output_boxes[0]||output_boxes[1])
       $fatal(1,"late replay after transfer abort");
     end
     transfer_boundaries=transfer_boundaries+1;
    end endtask
    initial begin
     repeat(4)@(negedge clk);rst_n=1;
     for(target_kind=0;target_kind<8;target_kind=target_kind+1)begin
      for(reset_kind=0;reset_kind<2;reset_kind=reset_kind+1)begin
       clear_history(0);acquire_fresh;launch_four;wait_target(target_kind);
       abort_here(reset_kind);acquire_fresh;
      end
     end
     $display("PASS GRID_TRANSFER_EQUIVALENCE area_bits=%0d external=%0d boundaries=%0d fresh_frames=%0d cycle_checks=%0d serial=%0d bank_reuses=%0d",AREA_BITS,EXTERNAL_CANDIDATE_READER,transfer_boundaries,fresh_frames,cycle_checks,serial_checks,bank_reuses);
     $finish;
    end
    initial begin #100000000;$fatal(1,"grid transfer timeout");end
    endmodule
    '''
    text = MITER.read_text()
    marker = "initial begin\n repeat(4)@(negedge clk);rst_n=1;"
    assert text.count(marker) == 1
    text = text[:text.index(marker)] + body
    text = text.replace("module tb_coordinate_grid_equivalence;", "module tb_coordinate_grid_transfer;")
    bench = OUT / "tb_coordinate_grid_transfer.sv"
    bench.write_text(text)
    old_copy = OUT / "cnn_result_stabilizer_baseline.sv"
    old_copy.write_text(BASE.read_text().replace("module cnn_result_stabilizer #(", "module cnn_result_stabilizer_baseline #(", 1))


    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest().upper()


    inputs = {str(path): sha(path) for path in (SOURCE, BASE, MITER, bench, old_copy, Path(__file__))}

    inputs[str(COMMON)] = sha(COMMON)


    def run(label, args):
        proc = subprocess.run([str(x) for x in args], cwd=OUT, env=env,
                              stdin=subprocess.DEVNULL, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
        (OUT / (label + ".log")).write_text(proc.stdout)
        assert not proc.returncode and not re.search(r"\*\*\s+(?:Error|Fatal):", proc.stdout), proc.stdout[-6000:]
        return proc.stdout


    run("vlib", [SIM / "vlib.exe", "work"])
    run("compile", [SIM / "vlog.exe", "-sv", "-lint", "-work", "work", old_copy, SOURCE, bench])
    checks = []
    for area_bits in (24, 32):
        for external in (0, 1):
            text = run(f"transfer_a{area_bits}_e{external}", [SIM / "vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                "-lib", "work", "tb_coordinate_grid_transfer", f"-gAREA_BITS={area_bits}",
                f"-gEXTERNAL_CANDIDATE_READER={external}", "-do", "onerror {quit -code 1}; run -all; quit -f"])
            match = re.search(r"PASS GRID_TRANSFER_EQUIVALENCE.*", text)
            assert match
            checks.append(match[0]); print(match[0], flush=True)
    assert all(sha(Path(path)) == digest for path, digest in inputs.items())
    (OUT / "RESULTS.json").write_text(json.dumps({"status": "PASS", "scope": __doc__,
        "hardware_status": "NOT_RUN", "production_modified": False, "production_candidate_applied": True, "coord_shift": 3,
        "input_hashes": inputs, "parameter_modes": 4, "boundaries_per_mode": 16,
        "targets": ["pre-emit S_PAIR_WAIT", "pending emit_begin", "consumed emit_begin",
            "pending first serial slot", "pending final serial slot", "committed final serial slot",
            "pending done in S_FINISH", "observed done"],
        "abort_types": ["held synchronous clear", "held processing reset"],
        "checks": checks, "evidence_hashes": {path.name: sha(path) for path in OUT.glob("*.log")}}, indent=2))


if __name__ == "__main__":
    main()
