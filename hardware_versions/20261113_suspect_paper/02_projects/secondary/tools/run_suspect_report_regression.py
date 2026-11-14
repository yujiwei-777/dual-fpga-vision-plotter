"""Actual trial reporter/shared UART engine; immutable source centre and text.

Creates a bench from retained transport wiring. All new output stays in trial.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, os, re, subprocess, sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SIM = Path('E:/model/win64')

TAIL = r'''
task complete_report;integer n,q0;begin
 n=0;q0=queries;
 while(done_events==0 && n<300000)begin
  if(tx_lines>read_line)begin ack_line();n++;end
  else begin tick(1);n++;end
 end
 tick(8);
 if(done_events!=1||error||recovery||busy)fail("report did not finish after final ok");
 if(queries!=q0)fail("normal completion polled Idle");
 if(paper_mark_moves!=0)fail("suspect produced a paper defect marker");
end endtask
task clear_history;begin
 clear=1;tick(1);clear=0;tick(5);
 printed[0]="";printed[1]="";printed[2]="";done_events=0;paper_mark_moves=0;
end endtask
task suspect_input;begin
 judgement=2;input_count=1;input_kinds=3;
 input_boxes={192'd0,16'd42,16'd122,16'd39,16'd119};
end endtask
initial begin
 case_name="FAIL_source_centre_snapshot_and_final_ACK";reset_case();suspect_input();start_job(0,0);
 input_boxes={192'd0,16'd700,16'd1270,16'd650,16'd1200};input_count=0;input_kinds=0;judgement=1;
 complete_report();
 if(printed[0]!="PCB 0001 FAIL"||printed[1]!="SUSPECT"||printed[2]!="X0120 Y0040")
  fail({"wrong text: ",printed[0]," / ",printed[1]," / ",printed[2]});
 if(reporter.newline_offset_cmm!=3100)fail("three-line extent must be31mm only");pass();
 case_name="second_FAIL_report_newline_and_new_snapshot";clear_history();suspect_input();
 input_boxes={192'd0,16'd121,16'd242,16'd100,16'd220};start_job(0,0);complete_report();
 if(printed[0]!="PCB 0002 FAIL"||printed[1]!="SUSPECT"||printed[2]!="X0231 Y0110")fail("second snapshot text changed");
 if(reporter.newline_offset_cmm!=6200||error_code!=0)fail("second report consumed frame-sized height");pass();
 case_name="PASS_clears_old_suspect";clear_history();suspect_input();judgement=1;start_job(0,0);complete_report();
 if(printed[0]!="PCB 0003 PASS"||printed[1]!=""||printed[2]!="")fail("PASS reused SUSPECT/DEFECTS");
 if(reporter.newline_offset_cmm!=7300)fail("PASS reserves title height only");pass();
 case_name="REVIEW_clears_old_suspect";clear_history();suspect_input();judgement=0;start_job(0,0);complete_report();
 if(printed[0]!="PCB 0004 REVIEW"||printed[1]!=""||printed[2]!="")fail("REVIEW reused SUSPECT");
 if(reporter.newline_offset_cmm!=8400)fail("REVIEW reserves title height only");pass();
 case_name="FAIL_no_positive_region_title_only";clear_history();suspect_input();input_count=0;start_job(0,0);complete_report();
 if(printed[1]!=""||printed[2]!=""||reporter.suspect_job)fail("no-positive region emitted SUSPECT");pass();
 case_name="legacy_kind_not_treated_as_suspect";clear_history();suspect_input();input_kinds=1;start_job(0,0);complete_report();
 if(printed[1]!=""||printed[2]!=""||paper_mark_moves!=0)fail("legacy defect emitted text or paper marker");pass();
 case_name="invalid_source_box_rejected";clear_history();suspect_input();input_boxes={192'd0,16'd721,16'd1281,16'd0,16'd0};start_job(0,0);complete_report();
 if(printed[1]!=""||printed[2]!=""||reporter.suspect_job)fail("out-of-range source coordinates accepted");pass();
 case_name="source_boundary_centre_not_machine_mirrored";reset_case();suspect_input();input_boxes={192'd0,16'd720,16'd1280,16'd717,16'd1277};start_job(0,0);complete_report();
 if(printed[2]!="X1278 Y0718")fail("source centre mirrored or rounded up");pass();
 case_name="CNN_low_actual_confidence_name_centre_unchanged";reset_case();judgement=2;input_count=1;input_boxes={224'd0,16'd240,16'd640};input_kinds=3;start_job(0,1);complete_report();
 if(printed[0]!="GREEN CIRCLE  "||printed[1]!="X0640 Y0240"||printed[2]!="CONF 003")
  fail({"ordinary CNN changed: ",printed[0]," / ",printed[1]," / ",printed[2]});pass();
 case_name="abort_no_automatic_replay";reset_case();suspect_input();start_job(0,0);wait_line();
 abort_job=1;tick(1);abort_job=0;tick(30);send_rx("<Idle|MPos:0,0,0>\n");tick(200);
 if(done_events!=0||!recovery||!error||tx_lines!=1)fail("abort completed or replayed a report");pass();
 case_name="KEY4_stop_no_new_segments";reset_case();suspect_input();start_job(0,0);wait_line();
 stop=1;tick(1);stop=0;tick(30);send_rx("<Hold:0|MPos:0,0,0>\n");tick(200);
 if(done_events!=0||!recovery||tx_lines!=1||holds==0)fail("KEY4 stop sent new segments");pass();
 case_name="Alarm_locks_report_without_done";reset_case();suspect_input();start_job(0,0);wait_line();send_rx("ALARM:1\n");tick(30);
 if(!error||!recovery||done_events!=0||tx_lines!=1)fail("Alarm completed or replayed");pass();
 $display("SUSPECT_REPORT_REGRESSION_PASS cases=%0d",scenarios);$finish;
end
initial begin #1000000000;$fatal(1,"global timeout");end
endmodule
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def make_bench(path, center_input=False):
    source = (ROOT/'02_sim/key2_zero/tb_key2_zero.sv').read_text()
    source = source[:source.index('task wait_done;')]
    source = source.replace('module tb_key2_zero;', 'module tb_suspect_report;')
    source = source.replace('KEY2_ZERO_FAIL', 'SUSPECT_REPORT_FAIL').replace('KEY2_ZERO_CASE_PASS', 'SUSPECT_REPORT_CASE_PASS')
    declaration='reg frame_reset=0,paper_confirm=0;'
    assert source.count(declaration)==1,'retained bench frame-reset declaration drift'
    source = source.replace(declaration, '''reg [2:0] input_count=1;reg [255:0] input_boxes=0;reg [7:0] input_kinds=3;
reg [7:0] cnn_conf=3;reg [15:0] cnn_class=5;
string printed[0:2];integer paper_mark_moves=0;
reg frame_reset=0,paper_confirm=0;''')
    source = source.replace('local_test=1,cnn=0', 'local_test=0,cnn=0')
    # The current reporter keeps paper-loading parameters after KEY2_REZERO;
    # insert the suspect trial parameter without assuming an exact parameter
    # list or trailing delimiter.
    source,n = re.subn(r'(\.KEY2_REZERO\(1\))(?!,\.PCB_SUSPECT_ENABLE\(1\))', r'\1,.PCB_SUSPECT_ENABLE(1)', source, count=1)
    assert n == 1, 'suspect trial parameter insertion drift'
    replacements = {".I_defect_count(3'd0)": '.I_defect_count(input_count)',
                    ".I_defect_boxes(256'd0)": '.I_defect_boxes(input_boxes)',
                    ".I_defect_kinds(8'd0)": '.I_defect_kinds(input_kinds)',
                    ".I_cnn_class(16'd1)": '.I_cnn_class(cnn_class)',
                    ".I_cnn_confidence(8'd37)": '.I_cnn_confidence(cnn_conf)'}
    for old, new in replacements.items():
        assert source.count(old) == 1
        source = source.replace(old, new)
    source = source.replace('if(done)done_events++;', '''if(done)done_events++;
  if(reporter.state==62 && reporter.report_line<=2)
   printed[reporter.report_line]={printed[reporter.report_line],string'(reporter.decoded_char)};
  if(reporter.state==43)paper_mark_moves++;''')
    source = source.replace('resets=0;rst_n=1;', 'resets=0;printed[0]="";printed[1]="";printed[2]="";paper_mark_moves=0;rst_n=1;')
    source=source+TAIL
    if center_input:
        source,n = re.subn(r'(\.PCB_SUSPECT_ENABLE\(1\))(?!,\.PCB_SUSPECT_CENTER_INPUT\(1\))',
                           r'\1,.PCB_SUSPECT_CENTER_INPUT(1)', source, count=1)
        assert n == 1, 'suspect centre-input parameter insertion drift'
        replacements={
            "{192'd0,16'd42,16'd122,16'd39,16'd119}":"{224'd0,16'd40,16'd120}",
            "{192'd0,16'd121,16'd242,16'd100,16'd220}":"{224'd0,16'd110,16'd231}",
            "{192'd0,16'd721,16'd1281,16'd0,16'd0}":"{224'd0,16'd720,16'd1280}",
            "{192'd0,16'd720,16'd1280,16'd717,16'd1277}":"{224'd0,16'd718,16'd1278}"}
        for old,new in replacements.items():
            assert old in source,old
            source=source.replace(old,new)
    path.write_text(source, encoding='utf-8', newline='\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--center-input',action='store_true',help='Integrated top already provides source-image centres')
    args=parser.parse_args()
    directory='suspect_trial_report_center' if args.center_input else 'suspect_trial_report'
    out = ROOT/'reports'/directory/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out.mkdir(parents=True, exist_ok=False)
    bench = out/'tb_suspect_report.sv'
    make_bench(bench,args.center_input)
    sources = [ROOT/'01_rtl'/name for name in ('grbl_reporter_shared_candidate.v',
               'grbl_shared_transport_candidate.v', 'grbl_line_formatter.v',
               'grbl_response_parser.v', 'grbl_vector_font_rom.v')]+[bench]
    # The production report decoder reads ../model/suspect relative to the
    # isolated simulation cwd. Stage exact ROM bytes and bind both copies.
    rom=ROOT/'model/suspect/report_text_tokens.mem'
    staged_rom=out.parent/'model/suspect/report_text_tokens.mem'
    staged_rom.parent.mkdir(parents=True,exist_ok=True)
    if staged_rom.exists():
        assert digest(staged_rom)==digest(rom),'Existing staged report ROM differs'
    else:
        staged_rom.write_bytes(rom.read_bytes())
    bound_sources=sources+[Path(__file__).resolve(),rom,staged_rom]
    actual_top_parameters=None
    if args.center_input:
        top=ROOT/'01_rtl/secondary_top.v'
        declaration=re.search(r'grbl_reporter_shared_candidate\s*#\((.*?)\)\s*u_reporter\s*\(',top.read_text(encoding='utf-8-sig'),re.S)
        assert declaration and re.search(r'\.PCB_SUSPECT_ENABLE\(1\)',declaration[1])
        assert re.search(r'\.PCB_SUSPECT_CENTER_INPUT\(1\)',declaration[1])
        actual_top_parameters=declaration[1]
        bound_sources.append(top)
    pins = {str(p): digest(p) for p in bound_sources}
    env = dict(os.environ, LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'), MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    rows = []
    error = None
    cases = 0
    try:
        for label, cmd in [('vlib', [SIM/'vlib.exe', 'rtl_lib']),
                           ('lint', [SIM/'vlog.exe', '-sv', '-lint', '-work', 'rtl_lib', *sources]),
                           ('simulation', [SIM/'vsim.exe', '-batch', '-syncio', '-voptargs=+acc',
                            '-lib', 'rtl_lib', 'tb_suspect_report', '-do',
                            'onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -code 0'])]:
            log = out/(label+'.log')
            with log.open('w', encoding='utf-8') as stream:
                result = subprocess.run(list(map(str, cmd)), cwd=out, env=env,
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=300)
            text = log.read_text(encoding='utf-8', errors='replace')
            ok = result.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):', text)
            rows.append({'phase': label, 'passed': ok, 'exit_code': result.returncode,
                         'log': str(log), 'sha256': digest(log)})
            if not ok:
                raise RuntimeError(str(log)+'\n'+text[-5000:])
        cases = len(re.findall('SUSPECT_REPORT_CASE_PASS', text))
        if 'SUSPECT_REPORT_REGRESSION_PASS cases=12' not in text or cases != 12:
            raise RuntimeError('Missing12case completion\n'+text[-5000:])
    except Exception as exc:
        error = str(exc)
    drift = [name for name, h in pins.items() if digest(Path(name)) != h]
    gcode=[dict(case=m[1],line=int(m[2]),text=m[3]) for m in re.finditer(r'^# GCODE case=(.*?) line=(\d+) text=([^\r\n]*)',text,re.M)]
    (out/'GCODE.json').write_text(json.dumps(gcode,indent=2)+'\n',encoding='utf-8')
    result = {'status': 'PASS' if error is None and not drift else 'FAIL', 'cases': cases,
              'actual_top_reporter_parameters':actual_top_parameters,'gcode_lines':len(gcode),'gcode_file':str(out/'GCODE.json'),'gcode_sha256':digest(out/'GCODE.json'),
              'input_contract':'original_frame_centre' if args.center_input else 'full_source_region_compatibility',
              'source_sha256': pins, 'commands': rows, 'error': error, 'source_drift': drift,
              'hardware': 'NOT_RUN',
              'scope': 'Actual trial report glyphs, source centre, serial G-code, parser, ACK engine, newline, abort/stop/Alarm; input inspection metadata controlled.',
              'limitations': ['GRBL ok confirms acceptance, not mechanical standstill.',
                              'Approximate PCB localization accuracy is not tested by this report suite.']}
    report = out/'RESULT.json'
    report.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'status': result['status'], 'cases': cases, 'report': str(report)}))
    if error:
        print(error)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
