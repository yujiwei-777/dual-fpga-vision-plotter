"""Real top caches an inspection and KEY1 admits its immutable SUSPECT result.

Peripheral/vision/reporter leaves are controlled interfaces; actual report
glyph, coordinate and UART behavior is tested by the separate report suite.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, re, sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]

TAIL = r'''
    // Retain the legacy-peer snapshot contract. Capable-peer preview locking
    // is independently exercised by tb_operator_metadata on the same DUT.
    force dut.operator_preview_capable=1'b0;force dut.operator_snapshot_take=1'b0;

    repeat(4)step;rst_n=1;repeat(5)step;dut.key1_lock=0;
    purpose=1;repeat(4)step;
    source_boxes={192'd0,16'd42,16'd122,16'd39,16'd119};
    source_count=1;source_kinds=3;pcb_good_now=0;pcb_status_now=1;
    result(0,0,0,100,500,20,400,1);
    check(dut.pcb_report_cache_valid&&dut.pcb_report_cache_job==88&&
          dut.pcb_report_cache_judgement==2&&dut.pcb_report_cache_defect_count==1&&
          dut.pcb_report_cache_boxes=={16'd40,16'd120}&&dut.pcb_report_cache_kinds==3&&
          dut.vision_result[511:256]==source_boxes,
          "FAIL caches coherent original-frame SUSPECT centre without auto writing");
    check(!dut.report_pending&&!dut.key1_job_active,"inspection never auto writes");
    press_key1;
    check(!dut.report_cnn_mode&&dut.report_job==88&&dut.report_judgement==2&&
          dut.report_defect_count==1&&dut.report_defect_boxes=={224'd0,16'd40,16'd120}&&dut.report_defect_kinds==3&&
          dut.u_reporter.I_defect_boxes=={224'd0,16'd40,16'd120}&&dut.u_reporter.I_defect_kinds==3&&
          dut.u_reporter.PCB_SUSPECT_CENTER_INPUT==1,
          "KEY1 snapshot passes same centre and SUSPECT tag to reporter");
    check(!dut.pcb_report_cache_valid,"accepted cache is consumed once");
    @(negedge clk);rep_busy=1;source_boxes={192'd0,16'd500,16'd900,16'd400,16'd700};source_kinds=0;source_count=0;
    network_online=0;session=64'd124;cancel_frame=1;repeat(6)step;
    check(dut.report_defect_boxes=={224'd0,16'd40,16'd120}&&
          dut.report_defect_count==1&&dut.report_defect_kinds==3&&
          dut.key1_job_protected&&dut.u_reporter.I_abort===0,
          "accepted SUSPECT snapshot survives live changes Ethernet loss and frame cancel");
    @(negedge clk);network_online=1;cancel_frame=0;retire;
    press_key1;
    check(!dut.report_pending&&!dut.key1_job_active,"repeated KEY1 cannot replay consumed PCB result");
    retire;
    pcb_good_now=1;pcb_status_now=0;source_count=0;source_boxes=0;source_kinds=0;
    result(0,0,0,100,500,20,400,1);
    check(dut.pcb_report_cache_judgement==1&&dut.pcb_report_cache_defect_count==0&&
          dut.pcb_report_cache_boxes==0&&dut.pcb_report_cache_kinds==0,
          "PASS atomically clears old SUSPECT snapshot");
    press_key1;check(dut.report_judgement==1&&dut.report_defect_count==0&&
          dut.report_defect_boxes==0&&dut.report_defect_kinds==0,"PASS KEY1 never inherits old SUSPECT");retire;
    pcb_good_now=0;pcb_status_now=2;
    result(0,0,0,100,500,20,400,1);press_key1;
    check(dut.report_judgement==0&&dut.report_defect_count==0&&dut.report_defect_boxes==0,
          "REVIEW KEY1 has no suspect");retire;
    pcb_status_now=1;source_count=1;source_kinds=3;source_boxes={192'd0,16'd42,16'd122,16'd39,16'd119};
    result(0,0,0,100,500,20,400,1);
    @(negedge clk);new_job=1;step;@(negedge clk);new_job=0;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,
          "new image transaction clears cached old region before completion");
    press_key1;check(!dut.report_pending&&!dut.key1_job_active,"KEY1 before new completion cannot print stale region");retire;
    result(0,0,0,100,500,20,400,1);purpose=0;repeat(3)step;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"mode change clears cached PCB region");
    purpose=1;repeat(3)step;result(0,0,0,100,500,20,400,1);
    result(0,0,0,0,0,0,0,0);
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"no-target completion clears cached PCB region");
    for(integer invalid=0;invalid<3;invalid=invalid+1)begin
        case(invalid)
            0:source_boxes={192'd0,16'd721,16'd1281,16'd39,16'd119};
            1:source_boxes={192'd0,16'd39,16'd119,16'd42,16'd122};
            default:source_boxes={192'd0,16'd42,16'd122,16'd42,16'd122};
        endcase
        result(0,0,0,100,500,20,400,1);
        check(dut.pcb_report_cache_valid&&dut.pcb_report_cache_judgement==2&&
              dut.pcb_report_cache_defect_count==0&&dut.pcb_report_cache_boxes==0,
              "invalid/outside/zero-area source region never enters compressed centre cache");
        press_key1;
        check(dut.report_judgement==2&&dut.report_defect_count==0&&
              dut.report_defect_boxes==0&&dut.report_defect_kinds==0,
              "invalid region retains FAIL title but sends no suspect coordinate");retire;
    end
    source_boxes={192'd0,16'd42,16'd122,16'd39,16'd119};
    result(0,0,0,100,500,20,400,1);explicit_cancel=1;step;explicit_cancel=0;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"explicit job cancel clears cached region");
    result(0,0,0,100,500,20,400,1);task_reset=1;step;task_reset=0;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"KEY4 reset clears cached region");
    if(errors!=0)$fatal(1,"SUSPECT_KEY1_SNAPSHOT_FAIL checks=%0d errors=%0d",checks,errors);
    $display("SUSPECT_KEY1_SNAPSHOT_PASS checks=%0d",checks);$finish;
end
initial begin #200000;$fatal(1,"SUSPECT KEY1 metadata timeout");end
endmodule
'''


def main():
    helper = ROOT/'tools/run_retrained_preserved_regressions.py'
    spec = importlib.util.spec_from_file_location('current_regression', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    out = ROOT/'reports/suspect_trial_key1'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    run = module.Run(ROOT, out)
    run.pin(helper, Path(__file__))
    error = None
    try:
        original = ROOT/'tests/retained_inputs/tb_lowconf_top.sv'
        run.pin(original)
        text = original.read_text()
        text = text[:text.index('    repeat(4)step;rst_n=1;history_quiet;')]
        text = text.replace('module tb_cnn_named_top;', 'module tb_suspect_key1_snapshot;')
        # Use the current press/release controller with accelerated timing;
        # cache assertions still observe the real top-level short action.
        timing_anchor='task step; begin @(posedge clk); #1; end endtask'
        assert text.count(timing_anchor)==1
        text=text.replace(timing_anchor,'defparam dut.u_key1_action.DEBOUNCE_CYCLES=2;\ndefparam dut.u_key1_action.LONG_PRESS_CYCLES=40;\n'+timing_anchor)
        press_old='task press_key1;begin\n    @(negedge clk);key1_n=0;\n    repeat(6)step;\n    @(negedge clk);key1_n=1;\nend endtask'
        press_new='task press_key1;begin\n    @(negedge clk);key1_n=0;\n    repeat(8)step;\n    @(negedge clk);key1_n=1;\n    repeat(10)step;\nend endtask'
        assert text.count(press_old)==1
        text=text.replace(press_old,press_new)

        text = text.replace('reg done=0, valid=0, current=0;', '''reg done=0, valid=0, current=0;
reg [2:0] source_count=0;reg [255:0] source_boxes=0;reg [7:0] source_kinds=0;
reg pcb_good_now=0;reg [2:0] pcb_status_now=1;reg new_job=0,explicit_cancel=0;''')
        text = text.replace('force dut.report_ready=rep_ready;', "force dut.paper_confirm_armed=1'b0;force dut.paper_confirm_active=1'b0;force dut.copy_write_waiting=1'b0;force dut.copy_prepare_cancel=1'b0;force dut.report_page_maintenance=1'b0;force dut.report_ready=rep_ready;")
        text = text.replace('force dut.vision_job_cancel=0;', 'force dut.vision_job_cancel=explicit_cancel;')
        text = text.replace('force dut.vision_start=0;', 'force dut.vision_start=new_job;')
        text = text.replace('force dut.pcb_status=1;force dut.pcb_good=1;', 'force dut.pcb_status=pcb_status_now;force dut.pcb_good=pcb_good_now;')
        text = text.replace('force dut.defect_count=0;force dut.defect_boxes=0;force dut.defect_kinds=0;',
                            'force dut.defect_count=source_count;force dut.defect_boxes=source_boxes;force dut.defect_kinds=source_kinds;')
        bench = out/'tb_suspect_key1_snapshot.sv'
        bench.write_text(text+TAIL, encoding='utf-8', newline='\n')
        declarations = module.top_declarations(run)
        leafs = ['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack',
                 'vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link',
                 'grbl_uart_port','grbl_reporter_shared_candidate','grbl_shared_transport_candidate',
                 'doc_copy_pipeline_shared_candidate','rgmii_interface']
        stub = out/'current_controlled_interfaces.sv'
        stub.write_text('\n'.join(declarations[n]+'\nendmodule\n' for n in leafs)+
                        '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n',
                        encoding='utf-8', newline='\n')
        log = run.sim('snapshot', [stub, ROOT/'01_rtl/secondary_top.v', bench],
                      'tb_suspect_key1_snapshot', 'SUSPECT_KEY1_SNAPSHOT_PASS checks=21', novopt=True)
        run.scope.append({'test': 'actual top KEY1 PCB SUSPECT cache snapshot',
                          'checks': re.findall(r'PASS[^\r\n]*', log)})
        run.limits.append('Vision, reporter, network, DDR and UART leaves controlled. Actual report and packet data paths are separate suites.')
    except Exception as exc:
        error = str(exc)
    result = run.finish(error)
    print(json.dumps({'status': result['status'], 'report': str(out/'RESULTS.json'), 'error': error}))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
