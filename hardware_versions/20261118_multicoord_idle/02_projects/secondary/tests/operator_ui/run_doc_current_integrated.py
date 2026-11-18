"""Captured source Y -> actual planner -> fresh KEY1 -> shared GRBL.

Run the selected read-only baseline as a control. No image, plan, point or
plotter boundary is forced. All output is written in a new report folder.
"""
from pathlib import Path
from datetime import datetime, timezone
import ast, hashlib, json, os, re, shutil, subprocess, sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT.parent / 'secondary_pcb_operator_ui_20261111'
TEMPLATE = ROOT / 'tests/retained_inputs/run_doc_preview_integrated.py'
FIXTURE = ROOT / 'tests/retained_inputs/secondary_doc_dirt_lowconf_factored_20261101/reports/dirt_qualification/fixtures/ink2358/source_y.mem'
SIM = Path('E:/model/win64')

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p): return Path(p).read_text(encoding='utf-8-sig', errors='replace')
def put(p, obj): Path(p).write_text(json.dumps(obj, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def bench(design, confirm):
    tree = ast.parse(read(TEMPLATE))
    node = next(n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'BENCH' for t in n.targets))
    text = ast.literal_eval(node.value)
    text = text.replace('tb_doc_preview_integrated', 'tb_doc_key1_integrated')
    text = text.replace('key1_release=0,preview_sent=0', 'write_start=0')
    text = text.replace('reg [8:0]preview_read_addr=0;wire [7:0]preview_read_data;\nwire preview_valid;wire [31:0]preview_job_id;', 'wire write_waiting;')
    text = text.replace('integer fh,points1,points2,bitmap_fh,', 'integer fh,points2,')
    text = text.replace('key1_release=1;tick(1);key1_release=0;', 'write_start=1;tick(1);write_start=0;')
    text = text.replace('fh=$fopen("gcode.txt","w");points1=$fopen("preview_points.txt","w");\n points2=$fopen("draw_points.txt","w");bitmap_fh=$fopen("preview_bitmap.mem","w");', 'fh=$fopen("gcode.txt","w");points2=$fopen("draw_points.txt","w");')
    sections = list(re.finditer(r'`ifdef PREVIEW\n.*?`endif', text, re.S))
    assert len(sections) == 3
    replacements = [r'''`ifdef CONFIRM
 press(); // During real source-image acquisition: never queue this press.
 wait(write_waiting||done);tick(4);
 if(done||!busy||dut.public_state!=7||!dut.u_planner.prepared||n2!=0||tx_bytes!=0)
   $fatal(1,"prepared document did not wait without emitting points or G-code");
 tick(1000);
 if(!write_waiting||tx_bytes||n2)$fatal(1,"early KEY1 caused automatic writing");
 press();tick(4);
`endif''', r'''`ifdef CONFIRM
 if(write_waiting)$fatal(1,"completed task still waiting");
 press();tick(20);if(busy)$fatal(1,"old document replayed after completion");
`endif''', '']
    for found, value in reversed(list(zip(sections, replacements))):
        text = text[:found.start()] + value + text[found.end():]
    text = text.replace('$fclose(fh);$fclose(points1);$fclose(points2);$fclose(bitmap_fh);', '$fclose(fh);$fclose(points2);')
    text = text.replace('DOC_PREVIEW_INTEGRATED_PASS', 'DOC_KEY1_INTEGRATED_PASS')
    header = read(design/'01_rtl/doc_copy_pipeline_shared_candidate.v').split(');', 1)[0]
    ports = re.findall(r'\b(input|output)\s+(?:wire|reg)\s+(\[[^\]]+\]\s*)?([SX]_\w+)\b', header)
    assert len(ports) == 38
    declarations = '\n'.join('wire '+(width or '')+name+';' for _, width, name in ports)
    connections = ['.'+('D_'+n[2:] if n.startswith('S_') else 'D_fmt_'+n[2:])+'('+n+')' for _, _, n in ports]
    transport_header = read(design/'01_rtl/grbl_shared_transport_candidate.v').split(');', 1)[0]
    for direction, width, name in re.findall(r'\b(input|output)\s+(?:wire|reg)\s+(\[[^\]]+\]\s*)?(R_\w+)\b', transport_header):
        connections.append('.'+name+("('0)" if direction == 'input' else '()'))
    text = text.replace('@DECLARATIONS@', declarations).replace('@PIPELINE_PORTS@', ','.join('.'+n+'('+n+')' for _, _, n in ports))
    text = text.replace('@TRANSPORT_PORTS@', ',\n '.join(connections))
    text = text.replace('@PREVIEW_PORTS@', '.write_start(write_start),.write_waiting(write_waiting),' if confirm else '')
    assert '@' not in text.replace('@(negedge clk)', '').replace('@(posedge clk)', '')
    assert 'preview' not in text.lower()
    return text

def main():
    out = ROOT/'reports/doc_key1/integrated'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'), MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    pins = {str(p): sha(p) for p in [Path(__file__).resolve(), TEMPLATE, FIXTURE]}
    commands = []
    try:
        for label, design, confirm in [('baseline', BASE, True), ('confirm', ROOT, True)]:
            run = out/label; run.mkdir(); shutil.copyfile(FIXTURE, run/'source_y.mem')
            tb = run/'tb_doc_key1_integrated.sv'; tb.write_text(bench(design, confirm), encoding='ascii')
            files = [design/'01_rtl'/n for n in ['doc_copy_pipeline_shared_candidate.v', 'doc_image_frontend.v', 'doc_stroke_planner.v', 'doc_stroke_bram.v', 'doc_machine_map.v', 'doc_grbl_plotter_shared_candidate.v', 'grbl_shared_transport_candidate.v', 'grbl_response_parser.v', 'grbl_line_formatter.v']]
            pins.update({str(p): sha(p) for p in files+[tb, run/'source_y.mem']})
            calls = [('vlib', [SIM/'vlib.exe', 'rtl_lib']), ('lint', [SIM/'vlog.exe', '-sv', '-lint', '-work', 'rtl_lib', '+define+DOC_BEHAVIORAL_RAM']+(['+define+CONFIRM'] if confirm else [])+files+[tb]), ('simulation', [SIM/'vsim.exe', '-batch', '-syncio', '-voptargs=+acc', '-lib', 'rtl_lib', 'tb_doc_key1_integrated', '-do', 'onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0'])]
            for phase, call in calls:
                log = run/(phase+'.log')
                with log.open('w') as stream: cp = subprocess.run(list(map(str, call)), cwd=run, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=1200)
                text = read(log)
                ok = cp.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):', text) and (phase != 'simulation' or 'DOC_KEY1_INTEGRATED_PASS' in text)
                commands.append(dict(test=label+'/'+phase, status='PASS' if ok else 'FAIL', log=str(log), log_sha256=sha(log)))
                put(out/'COMMANDS.json', commands)
                print(label+'/'+phase+': '+commands[-1]['status'], flush=True)
                if not ok: raise RuntimeError(text[-5000:])
        assert (out/'baseline/draw_points.txt').read_bytes() == (out/'confirm/draw_points.txt').read_bytes(), 'committed path stream changed'
        assert (out/'baseline/gcode.txt').read_bytes() == (out/'confirm/gcode.txt').read_bytes(), 'G-code changed'
        assert all(Path(p).is_file() and sha(p) == h for p, h in pins.items()), 'source drift'
        artifacts = {str(p): sha(p) for label in ['baseline', 'confirm'] for p in (out/label).glob('*.txt')}
        result = dict(status='PASS', source_sha256=pins, commands=commands, points=len(read(out/'confirm/draw_points.txt').splitlines()), gcode_lines=len(read(out/'confirm/gcode.txt').splitlines()), artifact_sha256=artifacts, assertions=['actual captured source Y and real frontend/planner; no forced image/planner boundary', 'early acquisition KEY1 discarded; completed plan remains waiting without UART or point emission', 'fresh KEY1 after preparation emits once', 'all points and complete G-code byte-identical to selected baseline', 'completed document cannot replay on another KEY1'], limitations=['Abstract pixel and UART interfaces; HXA/DDR physical behavior and actual mechanics require separate checks.', 'Existing captured fixture is a regression control, not a new handwriting-quality assessment.'], hardware='NOT_RUN')
    except Exception as error:
        result = dict(status='FAIL', error=str(error), source_sha256=pins, commands=commands, hardware='NOT_RUN')
    put(out/'RESULT.json', result)
    print(json.dumps(dict(status=result['status'], report=str(out/'RESULT.json'), error=result.get('error'), points=result.get('points'), lines=result.get('gcode_lines')), ensure_ascii=False), flush=True)
    return 0 if result['status'] == 'PASS' else 1

if __name__ == '__main__': raise SystemExit(main())
