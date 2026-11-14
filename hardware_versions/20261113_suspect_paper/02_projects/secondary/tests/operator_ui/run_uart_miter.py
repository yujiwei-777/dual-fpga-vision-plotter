"""Compile current full production UART in cycle-exact miter against old RX."""
from pathlib import Path
from datetime import datetime, timezone
import difflib, hashlib, json, os, re, subprocess, sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path('E:/codex_pcb_operator_ui_secondary_20261111_r1/SOURCE_MANIFEST.json')
EXPECTED = json.loads((MANIFEST.parent/'BUILD_PLAN.json').read_text(encoding='utf-8-sig'))['source_manifest_sha256']
PRODUCTION = ROOT/'01_rtl/grbl_uart.v'
BASELINE_SEED=ROOT.parent/'secondary_pcb_runtime_fix_20261111/01_rtl/grbl_uart.v'
OUT=ROOT/'reports/robustness/uart_production_independent'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
SIM=Path('E:/model/win64')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
BENCH=r'''`timescale 1ns/1ps
module tb_uart_rx_width_miter;
 parameter integer CLK_HZ=125000000, BAUD=115200, CASE_ID=0;
 localparam integer DIV=(CLK_HZ+BAUD/2)/BAUD;
 localparam integer TICKS=(DIV>1)?DIV:2;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,rx=1;
 wire [7:0] old_data,new_data;
 wire old_valid,new_valid,old_error,new_error;
 grbl_uart_rx_reference #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) old_rx(.I_clk(clk),.I_rst_n(rst_n),.I_rx(rx),.O_data(old_data),.O_valid(old_valid),.O_error(old_error));
 grbl_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) new_rx(.I_clk(clk),.I_rst_n(rst_n),.I_rx(rx),.O_data(new_data),.O_valid(new_valid),.O_error(new_error));
 integer cycles=0,valids=0,errors=0,queue_at=0,queue_end=0,oracle_bytes=0;
 integer isolated=0,continuous=0,false_starts=0,bad_stops=0,mid_resets=0,random_segments=0,random_cycles=0,async_resets=0;
 reg [7:0] expected[0:2047];
 reg oracle=0;
 reg [31:0] rng=32'h9e3779b9;
 reg [8*48-1:0] phase="initial";
 always @(posedge clk)begin
  #1;cycles=cycles+1;
  if({old_data,old_valid,old_error} !== {new_data,new_valid,new_error})begin
   $display("MISMATCH phase=%0s cycle=%0d div=%0d rst=%b rx=%b old=%h/%b/%b new=%h/%b/%b",phase,cycles,DIV,rst_n,rx,old_data,old_valid,old_error,new_data,new_valid,new_error);
   $fatal(1,"UART_RX_OUTPUT_CYCLE_MISMATCH");
  end
  if({old_rx.state,old_rx.bit_index,old_rx.shift,old_rx.rx_meta,old_rx.rx_sync} !==
     {new_rx.state,new_rx.bit_index,new_rx.shift,new_rx.rx_meta,new_rx.rx_sync})$fatal(1,"UART_RX_INTERNAL_CONTROL_MISMATCH");
  if(old_rx.divider !== new_rx.divider)$fatal(1,"UART_RX_DIVIDER_VALUE_MISMATCH old=%h new=%h",old_rx.divider,new_rx.divider);
  if(old_valid)begin
   valids=valids+1;
   if(oracle)begin
    if(queue_at>=queue_end)$fatal(1,"UNEXPECTED_VALID_BYTE phase=%0s",phase);
    if(old_data !== expected[queue_at])$fatal(1,"BYTE_ORACLE_MISMATCH phase=%0s at=%0d expected=%h actual=%h",phase,queue_at,expected[queue_at],old_data);
    queue_at=queue_at+1;oracle_bytes=oracle_bytes+1;
   end
  end
  if(old_error)begin errors=errors+1;if(oracle)$fatal(1,"UNEXPECTED_FRAME_ERROR phase=%0s",phase);end
 end
 always @(negedge rst_n)begin
  #1;
  if({old_data,old_valid,old_error,new_data,new_valid,new_error}!==20'd0)$fatal(1,"ASYNC_RESET_OUTPUT_NOT_CLEAR");
 end
 task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
 task level(input reg value,input integer n);begin rx=value;tick(n);end endtask
 task enqueue(input [7:0] value);begin expected[queue_end]=value;queue_end=queue_end+1;end endtask
 task raw_frame(input [7:0] value,input reg stop_high);
  integer bitno;
  begin level(0,TICKS);for(bitno=0;bitno<8;bitno=bitno+1)level(value[bitno],TICKS);level(stop_high,TICKS);end
 endtask
 task assert_drain;
  begin tick(2*TICKS+8);if(queue_at!=queue_end)$fatal(1,"EXPECTED_BYTE_MISSING phase=%0s read=%0d tail=%0d",phase,queue_at,queue_end);end
 endtask
 task reset_now;
  begin
   #2;rst_n=0;async_resets=async_resets+1;tick(3);rx=1;#2;rst_n=1;tick(3*TICKS+8);
  end
 endtask
 task next_random;
  begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);end
 endtask
 integer i,j,vc,ec,pulse,limit;
 reg [7:0] value;
 initial begin
  rng=32'hc001c0de^CASE_ID;
  tick(5);#2;rst_n=1;tick(3*TICKS+8);
  if(DIV>=2)begin
   phase="all256_isolated_8N1";oracle=1;
   for(i=0;i<256;i=i+1)begin enqueue(i[7:0]);raw_frame(i[7:0],1);rx=1;tick(2*TICKS+8);isolated=isolated+1;end
   assert_drain();
   phase="all256_back_to_back_8N1";
   for(i=0;i<256;i=i+1)begin value=((i*197)+83)&255;enqueue(value);raw_frame(value,1);continuous=continuous+1;end
   rx=1;assert_drain();oracle=0;
   phase="short_false_start";
   for(i=0;i<8;i=i+1)begin
    vc=valids;ec=errors;limit=(DIV/2>2)?DIV/2-2:1;pulse=1+(i%limit);
    level(0,pulse);level(1,3*TICKS+8);
    if(valids!=vc || errors!=ec)$fatal(1,"FALSE_START_NOT_REJECTED div=%0d pulse=%0d",DIV,pulse);
    false_starts=false_starts+1;
   end
   phase="low_stop_framing_error";
   for(i=0;i<16;i=i+1)begin
    vc=valids;ec=errors;value=(i*37)^8'ha5;raw_frame(value,0);level(1,3*TICKS+8);
    if(valids!=vc || errors!=ec+1)$fatal(1,"LOW_STOP_ERROR_ORACLE div=%0d valid=%0d errors=%0d",DIV,valids-vc,errors-ec);
    bad_stops=bad_stops+1;
   end
   phase="reset_mid_start_data_stop";
   for(i=0;i<10;i=i+1)begin
    oracle=0;rx=0;
    for(j=0;j<i;j=j+1)begin tick(TICKS);rx=(j<8)?((8'h69>>j)&1'b1):1'b1;end
    tick((TICKS/2>0)?TICKS/2:1);reset_now();mid_resets=mid_resets+1;
    oracle=1;value=8'hc3^i;enqueue(value);raw_frame(value,1);rx=1;assert_drain();oracle=0;
   end
  end
  phase="random_rx_runs_and_async_resets";
  for(i=0;i<1500;i=i+1)begin
   next_random();rx=rng[0];pulse=1+(rng[30:1]%(3*TICKS+1));tick(pulse);random_segments=random_segments+1;
   if(i%53==17)reset_now();
  end
  phase="single_cycle_random_rx";
  for(i=0;i<10000;i=i+1)begin next_random();rx=rng[0];tick(1);random_cycles=random_cycles+1;end
  phase="final_recovery";reset_now();
  if(DIV>=2)begin oracle=1;enqueue(8'h5a);raw_frame(8'h5a,1);rx=1;assert_drain();oracle=0;end
  $display("UART_RX_MITER_PASS id=%0d clk=%0d baud=%0d div=%0d cycles=%0d valid=%0d errors=%0d oracle_bytes=%0d isolated=%0d continuous=%0d false_starts=%0d bad_stops=%0d mid_resets=%0d random_segments=%0d random_cycles=%0d async_resets=%0d width_old=%0d width_new=%0d",CASE_ID,CLK_HZ,BAUD,DIV,cycles,valids,errors,oracle_bytes,isolated,continuous,false_starts,bad_stops,mid_resets,random_segments,random_cycles,async_resets,$bits(old_rx.divider),$bits(new_rx.divider));
  $finish;
 end
 initial begin #2000000000;$fatal(1,"UART_RX_MITER_WATCHDOG");end
endmodule
'''
assert sha(MANIFEST)==EXPECTED
frozen=json.loads(MANIFEST.read_text(encoding='utf-8'))['files']
assert sha(PRODUCTION)==frozen['01_rtl/grbl_uart.v']['sha256']==sha(BASELINE_SEED)
assert BASELINE_SEED.is_file()
OUT.mkdir(parents=True,exist_ok=False)
baseline=OUT/'baseline_uart_frozen.v';baseline.write_bytes(BASELINE_SEED.read_bytes())
marker='module grbl_uart_rx #('
base=baseline.read_text(encoding='utf-8');production=PRODUCTION.read_text(encoding='utf-8')
before,old_rx=base.split(marker,1);new_before,new_rx=production.split(marker,1)
replacement='localparam integer DIVIDER_W=(DIV<2)?32:$clog2(DIV);\n    reg [DIVIDER_W-1:0] divider;'
assert before==new_before
assert new_rx==old_rx
reference=OUT/'rx_reference.v';bench=OUT/'tb_uart_production_miter.sv';diff=OUT/'SOURCE_DIFF.patch'
reference.write_text('module grbl_uart_rx_reference #('+old_rx,encoding='utf-8')
bench.write_text(BENCH,encoding='utf-8')
diff.write_text('\n'.join(difflib.unified_diff(base.splitlines(),production.splitlines(),fromfile='baseline_uart_frozen.v',tofile='current_production/grbl_uart.v'))+'\n',encoding='utf-8')
sources=[PRODUCTION,baseline,MANIFEST,Path(__file__),reference,bench,diff]
pins={str(p):sha(p) for p in sources}
result={'status':'INCOMPLETE','source_sha256':pins,'source_manifest_sha256':EXPECTED,
        'actual_full_production_uart_compiled':str(PRODUCTION),'baseline_input':str(baseline),'baseline_input_sha256':sha(baseline),
        'source_change_only':'UART is byte-identical to successful runtime-fix baseline; compare actual independent baseline RX and existing digital-byte oracle.',
        'commands':[],'cases':[],'hardware':'NOT_RUN',
        'scope':'Independent actual full production UART versus frozen baseline RX; no historical reports are dependencies.',
        'limitations':['Digital RTL does not validate analog UART signal quality, metastability, routing/timing or writing hardware.',
                       'DIV0/1 only compare preserved underflow behavior, not valid decoding.',
                       'GRBL protocol transport coverage resides in separate suites.']}
env=dict(os.environ,LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
def run(label,argv,marker=None):
    log=OUT/(label+'.log')
    with log.open('x',encoding='utf-8') as stream:
        cp=subprocess.run(list(map(str,argv)),cwd=OUT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=240)
    text=log.read_text(encoding='utf-8',errors='replace')
    passed=cp.returncode==0 and not re.search(r'\*\*\s+(?:Error|Fatal):|UART_RX_\w*MISMATCH|\$fatal',text) and (marker is None or marker in text)
    result['commands'].append({'label':label,'argv':list(map(str,argv)),'returncode':cp.returncode,'log':str(log),'sha256':sha(log),'passed':passed})
    if not passed:raise RuntimeError(label+' failed\n'+text[-2500:])
    print('PASS production_uart '+label,flush=True)
    return text
try:
    run('vlib',[SIM/'vlib.exe','miter_lib'])
    run('vlog',[SIM/'vlog.exe','-sv','-lint','-work','miter_lib',reference,PRODUCTION,bench])
    for index,(hz,baud) in enumerate([(125000000,115200),(50000000,115200),(128,1),(7,1),(2,1),(1,1),(1,4)]):
        text=run('case_'+str(index),[SIM/'vsim.exe','-batch','-quiet','-lib','miter_lib','tb_uart_rx_width_miter',
              f'-gCLK_HZ={hz}',f'-gBAUD={baud}',f'-gCASE_ID={index}','-do',
              'onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'UART_RX_MITER_PASS')
        fields={key:int(value) for key,value in re.findall(r'(\w+)=(\d+)',re.search(r'UART_RX_MITER_PASS (.+)',text)[1])}
        assert fields['clk']==hz and fields['baud']==baud
        if fields['div']>=2:
            assert all(fields[k]==v for k,v in {'isolated':256,'continuous':256,'false_starts':8,'bad_stops':16,'mid_resets':10,'oracle_bytes':523}.items())
        assert fields['random_segments']==1500 and fields['random_cycles']==10000
        result['cases'].append(fields)
    result['status']='PASS'
    result['total_compared_cycles']=sum(item['cycles'] for item in result['cases'])
except Exception as exc:
    result['status']='FAIL';result['error']=repr(exc)
finally:
    result['source_drift']=[p for p,h in pins.items() if sha(p)!=h]
    if result['source_drift']:result['status']='FAIL'
    report=OUT/'RESULT.json';report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':result['status'],'report':str(report),'sha256':sha(report)}),flush=True)
raise SystemExit(0 if result['status']=='PASS' else 1)
