from pathlib import Path
import hashlib,json,os,re,subprocess
ROOT=Path(__file__).resolve().parents[2];MAIN=ROOT.parent/'main_pcb_auto_compat_20261101'
OUT=ROOT/'reports/retrained/main_protocol_compat_v3';OUT.mkdir(exist_ok=False)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
files=[MAIN/'01_rtl/imgq_gain_m/shared/rtl'/n for n in ['hxa_packet_codec.v','hxa_main_link.v']]
release=load(MAIN/'reports/PCB_COMPAT_DELIVERY_MANIFEST.json');bit=Path(release['artifact']['path']);assert sha(bit)==release['artifact']['sha256']
for f in files:
 rows=[x for x in release['frozen_dependencies'] if Path(x['path']).resolve()==f.resolve()];assert len(rows)==1 and rows[0]['sha256']==sha(f),f
s=(MAIN/'02_sim/link_pcb_wait_v2/tb_link_pcb_wait.sv').read_text()
a=s.index(' initial begin\n  repeat(12)');b=s.index(' initial begin #(64',a)
body=''' integer trial,raw_score,wire_score;reg[511:0] payload;
 initial begin
 repeat(12)@(negedge clk);rst_n=1;
 for(trial=0;trial<4;trial=trial+1)begin
  start_pcb();sid0=active_sid;fid0=active_fid;job0=active_job;toggle0=result_toggle;lock_rx();
  raw_score=255-trial*70;wire_score=(raw_score*100+127)/255;
  payload=result_payload(job0);payload[103:96]=trial==0?7:trial==1?5:trial==2?1:0;
  payload[119:104]=0;payload[239:224]=trial;
  if(trial==0)begin payload[127:120]=255;inject(8,sid0,fid0,64,payload);if(result_toggle!==toggle0||dut.result_seen)$fatal(1,"illegal255 unexpectedly accepted");end
  payload[127:120]=wire_score;a0=acks;inject(8,sid0,fid0,64,payload);manual_lock=0;wait(acks==a0+1);
  if(result_valid!==(trial<3)||result_frame!==fid0||result_data!==payload||dut.pcb_result_wait_active)$fatal(1,"scaled result did not commit");
  $display("TYPE8_COMPAT_PASS status=%0d raw=%0d wire=%0d checked=%0d good=%0d",trial,raw_score,wire_score,result_data[98],result_data[97]);
 end
 $display("TYPE8_COMPAT_ALL_PASS cases=4 malformed255_rejected=1");$finish;
 end
'''
s=s[:a]+body+s[b:];bench=OUT/'tb_link_pcb_wait.sv';bench.write_text(s)
pins={str(p):sha(p) for p in files+[bit,bench,Path(__file__),MAIN/'reports/PCB_COMPAT_DELIVERY_MANIFEST.json']}
(OUT/'SOURCE_SHA256.json').write_text(json.dumps(pins,indent=2)+'\n')
do='onerror {quit -code 1}\nonbreak {quit -code 2}\nvlib simlib\nvlog -sv -work simlib '+ ' '.join('"'+p.as_posix()+'"' for p in files+[bench])+'\nvsim -voptargs=+acc simlib.tb_link_pcb_wait\nrun -all\nquit -code 0\n'
(OUT/'run.do').write_text(do)
env=dict(os.environ);env['LM_LICENSE_FILE']=env['MGLS_LICENSE_FILE']='E:/model/win64/LICENSE.TXT'
with (OUT/'SIM.log').open('w') as log:r=subprocess.run(['E:/model/win64/vsim.exe','-batch','-syncio','-do','run.do'],cwd=OUT,env=env,stdout=log,stderr=subprocess.STDOUT)
log=(OUT/'SIM.log').read_text(errors='replace');assert r.returncode==0 and 'TYPE8_COMPAT_ALL_PASS' in log and not re.search(r'\*\*\s+(Error|Fatal):',log),log[-3000:]
assert all(sha(p)==h for p,h in pins.items())
report=dict(status='PASS_PACKET_LEVEL_MAIN_COMPATIBILITY',source_hashes=pins,main_bit_sha256=sha(bit),result_records=re.findall('TYPE8_COMPAT_PASS[^\r\n]*',log),log_sha256=sha(OUT/'SIM.log'),transport_scale='floor((raw_score*100+127)/255),0..100,not calibrated probability',all256_scale_range=all(0<=(x*100+127)//255<=100 for x in range(256)),scope='Actual main packet/CRC/result decoder, synthetic peripheral/frame service; secondary numeric integration tested separately; no main source writes.',hardware='NOT_RUN')
(OUT/'RESULTS.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
