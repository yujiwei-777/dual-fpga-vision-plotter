"""Fresh real-secondary_top KEY1 tests; controlled peripheral outputs only."""
from pathlib import Path
from datetime import datetime, timezone
import argparse,importlib.util,json,sys
sys.dont_write_bytecode=True
BASE=Path(__file__).resolve().parent.parent
p=argparse.ArgumentParser()
p.add_argument('--design',type=Path,required=True)
p.add_argument('--expect-fixed',action='store_true')
args=p.parse_args();DESIGN=args.design.resolve()
spec=importlib.util.spec_from_file_location('continuous_key1_helper',DESIGN/'tools/run_retrained_preserved_regressions.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
out=DESIGN/'reports/continuous_cnn_key1'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(DESIGN,out);error=None
try:
    r.pin(Path(__file__))
    declarations=h.top_declarations(r)
    names=['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack',
      'vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link',
      'grbl_uart_port','grbl_reporter_shared_candidate','grbl_shared_transport_candidate',
      'doc_copy_pipeline_shared_candidate','rgmii_interface']
    stubs=out/'controlled_peripheral_interfaces.sv'
    stubs.write_text('\n'.join(declarations[n]+'\nendmodule\n' for n in names)+
        '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n')
    src=DESIGN/'tests/paper_eject/tb_operator_metadata.sv';r.pin(src)
    text=h.read(src).split('    repeat(4)step;rst_n=1;history_quiet;dut.key1_lock=0;')[0]
    text=text.replace('module tb_operator_metadata;','module tb_continuous_cnn_key1;')
    inserted=r'''
reg take=0,new_job=0,explicit_cancel=0,capable=1,vision_running=0,recovery=0;
integer accepts=0,timeout_count=0;
localparam FIXED=@@FIXED@@;
always @(posedge clk) if(!rst_n)accepts<=0; else if(dut.key1_local_job_accept)accepts<=accepts+1;
task seed;begin
 rst_n=0;key1_n=1;new_job=0;vision_running=0;take=0;done=0;purpose=0;
 network_online=1;explicit_cancel=0;config_apply=0;task_reset=0;recovery=0;
 session=123;capable=1;rep_busy=0;rep_done=0;valid=0;
 repeat(4)step;rst_n=1;history_quiet;
 result(1,1,88,120,300,40,180,1);step;take=1;step;take=0;
 repeat(5)step;check(dut.preview_locked&&dut.key1_can_start,"seeded locked CNN result can start");
end endtask
task down;begin @(negedge clk);key1_n=0;repeat(6)step;end endtask
task up;begin @(negedge clk);key1_n=1;repeat(8)step;end endtask
task expect_snapshot;begin
 check(dut.report_cnn_mode&&dut.report_cnn_class==1&&dut.report_cnn_confidence==88&&
 dut.report_center_valid&&dut.report_center=={10'd110,11'd210},"accepted CNN snapshot contains original name confidence centre");
end endtask
task release_to_pulse;begin
 @(negedge clk);key1_n=1;timeout_count=0;
 while(!dut.key1_short_pulse&&timeout_count<20)begin step;timeout_count=timeout_count+1;end
 check(dut.key1_short_pulse,"physical release generated one short pulse");
end endtask
'''.replace('@@FIXED@@',str(int(args.expect_fixed)))
    extra_decl,tasks=inserted.split('task seed;',1)
    text=text.replace('reg take=0,new_job=0,explicit_cancel=0,capable=1;',extra_decl)
    text=text.replace('initial begin', 'task seed;'+tasks+'\ninitial begin',1)
    text=text.replace('force dut.vision_busy=0;','force dut.vision_busy=vision_running;')
    text=text.replace('force dut.report_recovery_required=0;','force dut.report_recovery_required=recovery;')
    text+=r'''
    seed;press_key1;check(accepts==1,"idle short press accepts CNN write");expect_snapshot;
    seed;vision_running=1;press_key1;
    check(accepts==FIXED,"CNN inference already busy at press begins");if(FIXED)expect_snapshot;
    seed;down;vision_running=1;repeat(2)step;vision_running=0;repeat(2)step;up;
    check(accepts==FIXED,"new CNN busy interval during held KEY1");if(FIXED)expect_snapshot;
    seed;down;new_job=1;step;new_job=0;repeat(2)step;up;
    check(accepts==FIXED,"new ordinary frame during held KEY1");if(FIXED)expect_snapshot;
    seed;down;result_id=89;result(3,3,11,600,900,400,600,1);up;
    check(accepts==1,"valid new result during held key preserves admission");expect_snapshot;
    seed;down;release_to_pulse;
    @(negedge clk);done=1;step;@(negedge clk);done=0;repeat(5)step;
    check(accepts==FIXED,"valid completion coincident with short pulse");if(FIXED)expect_snapshot;
    seed;down;result(0,0,0,0,0,0,0,0);up;
    check(accepts==0&&!dut.cnn_cache_valid,"no-target while held cancels write and clears cache");
    seed;down;release_to_pulse;
    @(negedge clk);done=1;valid=0;step;@(negedge clk);done=0;repeat(5)step;
    check(accepts==0&&!dut.cnn_cache_valid,"no-target simultaneous with release cannot print stale result");
    seed;down;purpose=1;repeat(3)step;purpose=0;up;
    check(accepts==0,"mode change while held cannot defer CNN write");
    seed;down;explicit_cancel=1;step;explicit_cancel=0;up;
    check(accepts==0,"explicit cancel during held KEY1 cannot write");
    seed;down;session=124;repeat(3)step;up;
    check(accepts==0,"session change during held KEY1 clears stale result");
    seed;down;recovery=1;repeat(3)step;recovery=0;up;
    check(accepts==0,"real recovery interval during held KEY1 cancels eligibility");
    seed;down;rep_busy=1;repeat(3)step;rep_busy=0;up;
    check(accepts==0,"another report during held KEY1 cancels eligibility");
    seed;take=0;result(0,0,0,0,0,0,0,0);result(1,1,88,120,300,40,180,1);step;
    check(!dut.preview_locked,"fresh unsampled preview not falsely frozen");press_key1;
    check(accepts==0,"capable UI requires coherent sampled preview");
    seed;down;repeat(45)step;up;
    check(accepts==0&&!dut.paper_confirm_active,"long report KEY1 does not print or start paper load");
    if(errors)$fatal(1,"Continuous CNN KEY1 validation failed errors=%0d",errors);
    $display("CONTINUOUS_CNN_KEY1_VALIDATED fixed=%0d checks=%0d",FIXED,checks);$finish;
end
endmodule
'''
    bench=out/'tb_continuous_cnn_key1.sv';bench.write_text(text)
    log=r.sim('continuous_key1',[stubs,DESIGN/'01_rtl/secondary_top.v',bench],
        'tb_continuous_cnn_key1','CONTINUOUS_CNN_KEY1_VALIDATED',novopt=True)
    r.scope.append(dict(test='Physical KEY1 through actual top with valid cache and concurrent inference',
        records=[x.strip('# ') for x in log.splitlines() if 'PASS ' in x or 'CONTINUOUS_CNN' in x]))
    r.limits=['Clock/reset and peripheral interfaces are controlled; no admission/cache/guard/KEY1 state is forced.',
      'Debounce and long-press durations shortened; FPGA/GRBL hardware NOT_RUN.']
except Exception as exc:error=repr(exc)
result=r.finish(error)
h.dump(Path(__file__).resolve().parent/(DESIGN.name+'_LATEST.json'),result)
print(json.dumps(dict(status=result['status'],output=str(out),error=error),ensure_ascii=False))
raise SystemExit(0 if result['status']=='PASS' else 1)
