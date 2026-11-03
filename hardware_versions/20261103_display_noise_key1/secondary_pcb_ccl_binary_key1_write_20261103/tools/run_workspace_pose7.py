"""Compare reachable workspace accesses against the frozen control implementation."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent/'secondary_pcb_goodonly_ccl_affine6_joint_shared_r3_20261102'
SIM = Path('E:/model/win64')

BENCH = r'''
`timescale 1ns/1ps
module tb_workspace_pose7;
reg clk=0; always #4 clk=~clk;
reg [1:0] purpose=0,rs=0;
reg sw=0,fw=0,tw=0,pw=0,wb=0,rb=0;
reg [11:0] sa=0,ta=0;
reg [12:0] fa=0,ra=0;
reg [14:0] pa=0,pr=0;
reg [15:0] sd=0,fd=0,td=0,pd=0;
wire [7:0] nc,oc;wire [15:0] np,op;
vision_workspace_goodonly candidate(
 .clk(clk),.purpose(purpose),.cnn_shape_we(sw),.cnn_shape_waddr(sa),.cnn_shape_wdata(sd),
 .cnn_f1_we(fw),.cnn_f1_waddr(fa),.cnn_f1_wdata(fd),.cnn_f2_we(tw),.cnn_f2_waddr(ta),.cnn_f2_wdata(td),
 .cnn_rd_sel(rs),.cnn_rd_addr(ra),.cnn_rd_data(nc),.pcb_we(pw),.pcb_wbank(wb),.pcb_waddr(pa),.pcb_wdata(pd),
 .pcb_rd_bank(rb),.pcb_rd_addr(pr),.pcb_rd_data(np));
workspace_control #(.BANK0_INIT_FILE(""),.BANK1_INIT_FILE("")) control(
 .clk(clk),.purpose(purpose),.cnn_shape_we(sw),.cnn_shape_waddr(sa),.cnn_shape_wdata(sd),
 .cnn_f1_we(fw),.cnn_f1_waddr(fa),.cnn_f1_wdata(fd),.cnn_f2_we(tw),.cnn_f2_waddr(ta),.cnn_f2_wdata(td),
 .cnn_rd_sel(rs),.cnn_rd_addr(ra),.cnn_rd_data(oc),.pcb_we(pw),.pcb_wbank(wb),.pcb_waddr(pa),.pcb_wdata(pd),
 .pcb_rd_bank(rb),.pcb_rd_addr(pr),.pcb_rd_data(op));
integer i,j,checks=0;reg compare=0;
always @(posedge clk) begin
 #1;if(compare)begin
  if(purpose==1)begin if(np!==op)$fatal(1,"PCB read differs addr=%0d bank=%0d new=%h old=%h",pr,rb,np,op);end
  else if(nc!==oc)$fatal(1,"CNN read differs addr=%0d sel=%0d",ra,rs);
  checks=checks+1;
 end
end
initial begin
 for(j=0;j<3;j=j+1)begin
  purpose=0;compare=0;
  for(i=0;i<2048;i=i+1)begin @(negedge clk);sw=1;sa=2*i+1;sd=i^16'hAB41;end
  @(negedge clk);sw=0;
  for(i=0;i<4096;i=i+1)begin @(negedge clk);fw=1;fa=2*i+1;fd=i^16'h5B97;end
  @(negedge clk);fw=0;
  for(i=0;i<2048;i=i+1)begin @(negedge clk);tw=1;ta=2*i+1;td=i^16'hF371;end
  @(negedge clk);tw=0;compare=1;
  for(i=0;i<4096;i=i+1)begin @(negedge clk);rs=0;ra=i;end
  for(i=0;i<8192;i=i+1)begin @(negedge clk);rs=1;ra=i;end
  for(i=0;i<4096;i=i+1)begin @(negedge clk);rs=2;ra=i;end
  @(negedge clk);compare=0;purpose=1;
  for(i=0;i<6048;i=i+1)begin @(negedge clk);pw=1;wb=0;pa=i;pd=i^16'h4E31;end
  for(i=0;i<6048;i=i+1)begin @(negedge clk);pw=1;wb=1;pa=i;pd=i^16'h6F2B;end
  @(negedge clk);pw=0;compare=1;
  for(i=0;i<12096;i=i+1)begin @(negedge clk);rb=i[0];pr=i>>1;end
  @(negedge clk);compare=0;
 end
 $display("PASS WORKSPACE checks=%0d purpose_reentries=3",checks);$finish;
end
endmodule
'''


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()


def main():
    out=Path('E:/')/('codex_pose7_workspace_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    out.mkdir()
    source=BASE/'01_rtl/vision_workspace_goodonly.v'
    (out/'workspace_control.v').write_text(source.read_text().replace('module vision_workspace_goodonly','module workspace_control'))
    (out/'tb_workspace_pose7.sv').write_text(BENCH)
    inputs=[ROOT/'01_rtl/vision_workspace_goodonly.v',source,out/'workspace_control.v',out/'tb_workspace_pose7.sv']
    hashes={str(p):sha(p) for p in inputs}
    env=os.environ.copy()
    env.update(LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    commands=[('vlib',[str(SIM/'vlib.exe'),'rtl_lib']),
              ('lint',[str(SIM/'vlog.exe'),'-sv','-lint','-work','rtl_lib',str(inputs[0]),str(inputs[2]),str(inputs[3])]),
              ('simulation',[str(SIM/'vsim.exe'),'-batch','-syncio','-lib','rtl_lib','tb_workspace_pose7','-do','onerror {quit -code 1}; run -all; quit -code 0'])]
    for name,cmd in commands:
        with (out/(name+'.log')).open('w') as f:
            r=subprocess.run(cmd,cwd=out,env=env,stdout=f,stderr=subprocess.STDOUT)
        text=(out/(name+'.log')).read_text(errors='replace')
        assert r.returncode==0 and not re.search(r'\*\*\s+(Error|Fatal):',text),(name,out)
        if name=='simulation': assert 'PASS WORKSPACE' in text
    assert all(sha(p)==h for p,h in hashes.items())
    report={'status':'PASS','output':str(out),'input_hashes':hashes,
            'scope':'Full ordinary address range and both live PCB bank ranges (0..6047), three purpose reentries; synchronous read/write timing against frozen RTL.',
            'hardware':'NOT_RUN'}
    (out/'RESULTS.json').write_text(json.dumps(report,indent=2))
    (ROOT/'reports/pose7/WORKSPACE_REGRESSION.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
