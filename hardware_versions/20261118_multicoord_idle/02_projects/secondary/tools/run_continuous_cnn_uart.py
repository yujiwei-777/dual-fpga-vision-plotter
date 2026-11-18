"""Real report and UART handshake while CNN starts and finishes new frames."""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, re, shutil, sys, json
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
helper=ROOT/'tools/run_retrained_preserved_regressions.py'
spec=importlib.util.spec_from_file_location('live_uart_helper',helper)
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
out=ROOT/'reports/continuous_cnn_uart'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);error=None
try:
 r.pin(Path(__file__),helper)
 declarations=h.top_declarations(r)
 names=['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack',
   'vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link',
   'doc_copy_pipeline_shared_candidate','rgmii_interface']
 stub=out/'controlled_inference_interfaces.sv'
 stub.write_text('\n'.join(declarations[n]+'\nendmodule\n' for n in names)+
  '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n',encoding='utf-8')
 rom=ROOT/'model/suspect/report_text_tokens.mem';r.pin(rom)
 staged=out.parent/'model/suspect/report_text_tokens.mem';staged.parent.mkdir(parents=True,exist_ok=True)
 if staged.exists():assert h.sha(staged)==h.sha(rom)
 else:shutil.copyfile(rom,staged)
 for name in ('tb_common_write_completion','tb_common_write_uart'):
  original=ROOT/'tests/paper_eject'/(name+'.sv');r.pin(original)
  text=h.read(original)
  text=text.replace('reg infer_done=0;', '''reg infer_done=0;
reg vision_running=0,vision_frame_start=0,preview_take=0;
integer live_frame_cycles=0;
always @(posedge clk)if(rst_n&&purpose==0&&vision_running)live_frame_cycles=live_frame_cycles+1;
''')
  text=text.replace('force dut.vision_start=0;force dut.vision_busy=0;',
    'force dut.vision_start=vision_frame_start;force dut.vision_busy=vision_running;')
  text=text.replace('force dut.operator_snapshot_take=0;force dut.operator_preview_capable=0;',
    'force dut.operator_snapshot_take=preview_take;force dut.operator_preview_capable=1;')
  anchor='@(negedge clk);infer_done=0;tick(5);'
  assert text.count(anchor)==1
  text=text.replace(anchor,'''@(negedge clk);infer_done=0;tick(5);
 preview_take=1;step;preview_take=0;tick(3);''')
  anchor='@(negedge clk);key1_n=0;tick(6);'
  assert text.count(anchor)==1
  text=text.replace(anchor,'''if(purpose==0)vision_running=1;
 @(negedge clk);key1_n=0;tick(6);
 if(purpose==0)begin
  @(negedge clk);vision_frame_start=1;step;
  @(negedge clk);vision_frame_start=0;
 end''')
  anchor='tick(15);case_count++;'
  assert text.count(anchor)==1
  text=text.replace(anchor,'''tick(15);case_count++;
 if(purpose==0)begin
  check(live_frame_cycles>100,"CNN inference remains active through UART report completion");
  check(dut.report_cnn_class==1&&dut.report_cnn_confidence==37&&
    dut.report_center=={10'd110,11'd210},"CNN live inference cannot corrupt accepted report snapshot");
 end''')
  anchor='press1;complete("CNN first");'
  assert text.count(anchor)==1
  text=text.replace(anchor,anchor+'\n result(101);')
  text=text.replace('purpose=1;tick(6);', 'vision_running=0;purpose=1;tick(6);')
  text=text.replace('COMMON_WRITE_COMPLETION_PASS','CONTINUOUS_CNN_ACK_CHAIN_PASS')
  text=text.replace('COMMON_WRITE_UART_PASS','CONTINUOUS_CNN_PHYSICAL_UART_PASS')
  bench=out/(name+'_live.sv');bench.write_text(text,encoding='utf-8')
  files=[ROOT/'01_rtl'/n for n in ('secondary_top.v','grbl_uart.v','grbl_reporter_shared_candidate.v',
   'grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v','grbl_vector_font_rom.v')]
  marker='CONTINUOUS_CNN_PHYSICAL_UART_PASS' if name.endswith('uart') else 'CONTINUOUS_CNN_ACK_CHAIN_PASS'
  log=r.sim(name,[stub,*files,bench],name,marker,novopt=True)
  r.scope.append(dict(test=name,records=re.findall(r'(?:PASS CHAIN|CONTINUOUS_CNN_)[^\r\n]*',log)))
 r.limits=['Inference/DDR/network use controlled interfaces; real top admission and snapshot registers unforced.',
  'Real production UART/parser/transport/reporter in the second test; normal GRBL ok model and shortened debounce timings.',
  'CNN activity overlaps physical button press, frame-start edge, UART G-code emission and final ACK; hardware NOT_RUN.']
except Exception as exc:error=repr(exc)
result=r.finish(error)
print(json.dumps(dict(status=result['status'],report=str(out/'RESULTS.json'),error=error)),flush=True)
raise SystemExit(0 if result['status']=='PASS' else 1)
