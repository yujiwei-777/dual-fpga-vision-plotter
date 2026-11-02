"""Additional r5 tap/first/last/drain/reset/idle-purpose differential checks.

New external-MAC/shared-workspace core versus frozen r4 local-MAC core plus
the freshly generated integer vectors. This does not elaborate full top.
"""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os,re,subprocess
HERE=Path(__file__).resolve().parent
R5=Path('E:/codex_pcb_pose7_20261102_r5')
R4=Path('E:/codex_pcb_pose7_20261102_r4')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
manifest=R5/'SOURCE_MANIFEST.json'
frozen=json.loads(manifest.read_text())['files']
assert sha(manifest)=='3D847C5B889CEEF42A5CACAD22412145447AB4BC510463722DD0CDC852FC74FE'
assert all(sha(R5/name)==row['sha256'] for name,row in frozen.items())
prior=json.loads((HERE/'RESULTS.json').read_text())
assert prior['status']=='PASS' and prior['simulation_cases_passed']==27
assert sha(R5/'01_rtl/cnn_core.v')=='15262A8F5EA85739C5F9271A92B6A0143C88255F9A9F804975CCE4BAAB2621D8'
assert sha(R4/'01_rtl/cnn_core.v')=='CD3C6128836B816D5CA211722E22090E4676173CA52DB462592224E18C3E5ED3'
for file in ['weights.mem','biases.mem']:
    assert sha(R4/'model/export'/file)==sha(R5/'model/export'/file)
run=HERE/('edges_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
run.mkdir()
for name in ['pixels.mem','shape.mem','feature1.mem','feature2.mem','results.mem']:
    # Relative paths retain the already verified original integer fixtures.
    (run/name).write_bytes((HERE/name).read_bytes())
old=(R4/'01_rtl/cnn_core.v').read_text()
(run/'cnn_core_reference.v').write_text(old.replace('module cnn_core #(','module cnn_core_reference #(',1))
bench=(HERE/'tb_remote_detail.sv').read_text().replace('module tb_remote_detail;','module tb_remote_detail;')
bench=bench.replace('.purpose(2\'d0)', '.purpose(purpose)')
bench=bench.replace(".pcb_we(1'b0),.pcb_wbank(1'b0),.pcb_waddr(15'd0),.pcb_wdata(16'd0),.pcb_rd_bank(1'b0),.pcb_rd_addr(15'd0),.pcb_rd_data()",
                    '.pcb_we(pcb_we),.pcb_wbank(pcb_wbank),.pcb_waddr(pcb_waddr),.pcb_wdata(pcb_wdata),.pcb_rd_bank(pcb_rd_bank),.pcb_rd_addr(pcb_rd_addr),.pcb_rd_data(pcb_rd_data)')
bench=bench.replace(".pcb_select(1'b0)", ".pcb_select(purpose==2'd1)")
bench=bench.replace(".pcb_a(16'sd0),.pcb_w(8'sd0)", '.pcb_a(pcb_a),.pcb_w(pcb_w)')
bench=bench.replace('.product(),.cnn_product(mp),.pcb_product()', '.product(),.cnn_product(mp),.pcb_product(pcb_product)')
declarations=r'''
    reg [1:0] purpose=0;
    reg pcb_we=0,pcb_wbank=0,pcb_rd_bank=0;
    reg [14:0] pcb_waddr=0,pcb_rd_addr=0;
    reg [15:0] pcb_wdata=0;
    wire [15:0] pcb_rd_data;
    reg signed [15:0] pcb_a=0;reg signed [7:0] pcb_w=0;
    wire signed [23:0] pcb_product;
    wire reference_busy,reference_done,reference_bg;
    wire [1:0] reference_color,reference_shape;
    wire [7:0] reference_cc,reference_sc;
    cnn_core_reference #(.WEIGHTS_MEM("@W@"),.BIASES_MEM("@B@"),.FC_CONF_SHIFT(8),
      .USE_SHARED_WORKSPACE(0),.EXTERNAL_MAC(0)) reference_core(
      .clk(clk),.rst_n(rst_n),.pixel_we(pixel_we),.pixel_addr(pixel_addr),.pixel_rgb(pixel_rgb),.start(start),
      .busy(reference_busy),.done(reference_done),.color_id(reference_color),.shape_id(reference_shape),
      .color_conf(reference_cc),.shape_conf(reference_sc),.background_reject(reference_bg),
      .ws_shape_we(),.ws_shape_waddr(),.ws_shape_wdata(),.ws_f1_we(),.ws_f1_waddr(),.ws_f1_wdata(),
      .ws_f2_we(),.ws_f2_waddr(),.ws_f2_wdata(),.ws_rd_sel(),.ws_rd_addr(),.ws_rd_data(8'd0),
      .mac_a(),.mac_w(),.mac_product_ext(24'sd0));
    reg reference_seen=0;
    integer reference_f1=0,reference_f2=0,complete_runs=0,reset_cases=0,purpose_cases=0;
    reg signed [7:0] weight_ref[0:13511];
    reg signed [15:0] product_expect[0:15];
    reg last_expect[0:15],first_expect[0:15],pad_expect[0:15],fc_expect[0:15];
    integer issue_count=0,consume_count=0,first_count=0,last_count=0,padding_count=0,c_drains=0,f_drains=0;
    integer a_value,w_value,slot;
    always @(posedge clk)begin
      if(!rst_n)begin
        issue_count=0;consume_count=0;first_count=0;last_count=0;padding_count=0;c_drains=0;f_drains=0;
        reference_seen=0;reference_f1=0;reference_f2=0;
      end else begin
        if(reference_done)reference_seen=1;
        if(reference_core.state==reference_core.C_STORE&&reference_core.subpixel==3)begin
          if(!reference_core.layer)begin
            if(reference_core.pooled_activation_q!==f1_ref[c*8192+reference_core.output_addr])$fatal(1,"R4 local Conv1 mismatch");
            reference_f1++;
          end else begin
            if(reference_core.pooled_activation_q!==f2_ref[c*4096+reference_core.output_addr])$fatal(1,"R4 local Conv2 mismatch");
            reference_f2++;
          end
        end
        if(dut.state==dut.C_READ||dut.state==dut.F_READ)begin
          if(issue_count-consume_count>=16)$fatal(1,"tap scoreboard overflow");
          slot=issue_count%16;
          if(dut.state==dut.F_READ)begin
            a_value=f2_ref[c*4096+dut.fc_index];
            first_expect[slot]=(dut.fc_index==0);last_expect[slot]=(dut.fc_index==4095);pad_expect[slot]=0;fc_expect[slot]=1;
          end else begin
            a_value=dut.padding?0:(dut.layer?f1_ref[c*8192+dut.activation_addr]:shape_ref[c*4096+dut.activation_addr]);
            first_expect[slot]=(dut.kx==0&&dut.ky==0&&dut.ic==0);
            last_expect[slot]=(dut.kx==2&&dut.ky==2&&dut.ic==(dut.layer?7:0));
            pad_expect[slot]=dut.padding;fc_expect[slot]=0;
          end
          w_value=$signed(weight_ref[dut.weight_addr]);product_expect[slot]=a_value*w_value;issue_count++;
        end
        if(dut.product_valid)begin
          if(consume_count>=issue_count)$fatal(1,"product without issued tap");
          slot=consume_count%16;
          if(dut.product_q!==product_expect[slot]||dut.product_last!==last_expect[slot])
            $fatal(1,"PAIRED TAP mismatch tap=%0d product=%0d want=%0d last=%b wantlast=%b",consume_count,$signed(dut.product_q),$signed(product_expect[slot]),dut.product_last,last_expect[slot]);
          if(first_expect[slot])first_count++;
          if(pad_expect[slot])padding_count++;
          if(last_expect[slot])begin
            last_count++;
            if(fc_expect[slot])begin if(dut.state!=dut.F_DRAIN)$fatal(1,"FC last product escaped drain");f_drains++;end
            else begin if(dut.state!=dut.C_DRAIN)$fatal(1,"Conv last product escaped drain");c_drains++;end
          end
          consume_count++;
        end
      end
    end
'''.replace('@W@',(R5/'model/export/weights.mem').as_posix()).replace('@B@',(R5/'model/export/biases.mem').as_posix())
data_a=bench.index('    reg [23:0] pixels[0:CASES*4096-1];')
data_b=bench.index('    initial begin',data_a)
data_declarations=bench[data_a:data_b]
bench=bench[:data_a]+bench[data_b:]
# Declare controlled purpose ports and oracle arrays before instance use;
# ModelSim otherwise creates implicit nets for the purpose/write controls.
bench=bench.replace('    cnn_core #(',data_declarations+declarations+'\n    cnn_core #(',1)
a=bench.index('    initial begin\n      $readmemh("pixels.mem"')
b=bench.index('    always @(posedge clk) if(rst_n) begin',a)
body=r'''
    task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
    task raw_reset;
      begin rst_n=0;pixel_we=0;start=0;tick(3);rst_n=1;tick(8);
        if(busy||done||dut.product_valid||dut.read_valid_d1||dut.read_valid_d2||f1w||f2w)$fatal(1,"reset left tap valid/output active");
      end
    endtask
    task load_frame;
      begin
        c=0;f1count=0;f2count=0;
        for(i=0;i<4096;i++)begin @(negedge clk);pixel_we=1;pixel_addr=i;pixel_rgb=pixels[i];end
        @(negedge clk);pixel_we=0;tick(1);
      end
    endtask
    task launch;
      begin start=1;tick(1);start=0;end
    endtask
    task complete_case;
      begin
        load_frame;launch;cycles=0;
        while(!done&&cycles<3000000)begin tick(1);cycles++;end
        if(!done||!reference_seen)$fatal(1,"miter completion watchdog");
        if(cycles!=1880088)$fatal(1,"r5 latency mismatch %0d",cycles);
        if(issue_count!=1486848||consume_count!=issue_count||first_count!=49155||last_count!=49155||padding_count!=54752||c_drains!=49152||f_drains!=3)
          $fatal(1,"tap coverage issue=%0d consume=%0d first=%0d last=%0d pad=%0d Cd=%0d Fd=%0d",issue_count,consume_count,first_count,last_count,padding_count,c_drains,f_drains);
        if(f1count!=4096||f2count!=2048||reference_f1!=8192||reference_f2!=4096)$fatal(1,"miter feature counts");
        for(i=0;i<3;i++)begin
          if(dut.scores[i]!==results[i]||reference_core.scores[i]!==results[i])$fatal(1,"miter logits mismatch");
          if(dut.color_sum[i]!==results[3+i][18:0]||reference_core.color_sum[i]!==results[3+i][18:0])$fatal(1,"miter color sum mismatch");
        end
        if(color_id!==reference_color||shape_id!==reference_shape||cc!==reference_cc||sc!==reference_sc||bg!==0||reference_bg!==0)$fatal(1,"miter class/conf mismatch");
        if(color_id!==results[6][1:0]||shape_id!==results[7][1:0]||cc!==results[8][7:0]||sc!==results[9][7:0])$fatal(1,"integer class/conf mismatch");
        complete_runs++;
        $display("CNN_R5_EDGE_COMPLETE_PASS run=%0d products=%0d first=%0d last=%0d padding=%0d c_drains=%0d f_drains=%0d cycles=%0d",complete_runs,consume_count,first_count,last_count,padding_count,c_drains,f_drains,cycles);
        tick(4);
      end
    endtask
    task purpose_reuse;
      begin
        if(busy||reference_busy)$fatal(1,"purpose changed while active");
        purpose=1;pcb_a=-117;pcb_w=7;#1;
        if(pcb_product!==-24'sd819)$fatal(1,"shared DSP PCB-owner operands");
        for(integer bank=0;bank<2;bank++)begin
          pcb_wbank=bank;
          for(integer j=0;j<8;j++)begin pcb_we=1;pcb_waddr=j;pcb_wdata=16'hc000+bank*256+j;tick(1);end
        end
        pcb_we=0;
        for(integer bank=0;bank<2;bank++)begin
          pcb_rd_bank=bank;
          for(integer j=0;j<8;j++)begin pcb_rd_addr=j;tick(2);if(pcb_rd_data!==(16'hc000+bank*256+j))$fatal(1,"shared workspace PCB-owner read");end
        end
        if(dut.product_valid||f1w||f2w)$fatal(1,"idle CNN consumed PCB workspace/MAC product");
        purpose=0;tick(3);purpose_cases++;
        $display("CNN_R5_PURPOSE_PASS case=%0d",purpose_cases);
      end
    endtask
    task reset_at(input integer boundary);
      begin
        raw_reset;load_frame;launch;
        case(boundary)
          0:wait(dut.state==dut.C_READ&&!dut.layer&&dut.kx==0&&dut.ky==0);
          1:wait(dut.state==dut.C_DRAIN&&!dut.layer);
          2:wait(dut.state==dut.C_DRAIN&&dut.layer);
          3:wait(dut.state==dut.F_READ&&dut.fc_index==0);
          4:wait(dut.state==dut.F_DRAIN);
          5:wait(dut.read_valid_d2);
        endcase
        @(negedge clk);raw_reset;reset_cases++;
        $display("CNN_R5_RESET_PASS boundary=%0d",boundary);
        purpose_reuse;raw_reset;complete_case;
      end
    endtask
    initial begin
      $readmemh("pixels.mem",pixels);$readmemh("shape.mem",shape_ref);$readmemh("feature1.mem",f1_ref);$readmemh("feature2.mem",f2_ref);$readmemh("results.mem",results);
      $readmemh("@W@",weight_ref);
      raw_reset;complete_case;
      for(integer boundary=0;boundary<6;boundary++)reset_at(boundary);
      $display("CNN_R5_PIPELINE_EDGES_PASS complete_runs=%0d reset_cases=%0d purpose_cases=%0d",complete_runs,reset_cases,purpose_cases);$finish;
    end
    initial begin #2000000000;$fatal(1,"r5 edge global watchdog");end
'''.replace('@W@',(R5/'model/export/weights.mem').as_posix())
bench=bench[:a]+body+bench[b:]
(run/'tb_remote_detail.sv').write_text(bench)
sources=[R5/'01_rtl'/name for name in ['cnn_core.v','vision_workspace_goodonly.v','vision_shared_mac.v']]+[run/'cnn_core_reference.v',run/'tb_remote_detail.sv']
files=[*sources,Path(__file__),manifest,R4/'01_rtl/cnn_core.v',HERE/'REFERENCE_REPORT.json',HERE/'RESULTS.json',*list(run.glob('*.mem'))]
pins={str(p):sha(p) for p in files}
(run/'SOURCE_SHA256.json').write_text(json.dumps(pins,indent=2)+'\n')
do=['onerror {quit -code 2}','onbreak {quit -code 3}','vlib simlib','vlog -sv -lint -work simlib '+' '.join('"'+p.as_posix()+'"' for p in sources),'vsim -voptargs=+acc simlib.tb_remote_detail','run -all','quit -code 0','']
(run/'run.do').write_text('\n'.join(do))
env=dict(os.environ);env.update(LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
with (run/'SIM.log').open('w') as log:
    cp=subprocess.run(['E:/model/win64/vsim.exe','-batch','-syncio','-do','run.do'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
log=(run/'SIM.log').read_text(errors='replace')
passed=cp.returncode==0 and 'CNN_R5_PIPELINE_EDGES_PASS complete_runs=7 reset_cases=6 purpose_cases=6' in log and not re.search(r'\*\*\s+(Error|Fatal):',log)
result={'status':'PASS' if passed else 'FAIL','design':str(R5),'run_directory':str(run),
        'source_manifest_sha256':sha(manifest),'returncode':cp.returncode,
        'new_external_MAC':1,'new_shared_workspace':1,'reference':'Frozen r4 local-MAC/local-workspace core plus newly generated integer vector0',
        'sources_unchanged':all(sha(Path(p))==v for p,v in pins.items()),
        'frozen_sources_unchanged':all(sha(R5/name)==row['sha256'] for name,row in frozen.items()),
        'complete_records':re.findall(r'CNN_R5_EDGE_COMPLETE_PASS[^\r\n]*',log),
        'reset_records':re.findall(r'CNN_R5_RESET_PASS[^\r\n]*',log),
        'purpose_records':re.findall(r'CNN_R5_PURPOSE_PASS[^\r\n]*',log),
        'hardware':'NOT_RUN','limitations':['This bench tests core/workspace/MAC and idle owner reuse, not full HXA/DDR/top task admission.','Reset tests use core raw reset; top safety authorization is separately tested.','Per-tap addresses/padding indices observe current core issue state; independent integer full feature maps/logits are the separate arithmetic oracle.']}
if not(result['sources_unchanged'] and result['frozen_sources_unchanged']):result['status']='FAIL_SOURCE_DRIFT'
(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(result['status']!='PASS')
