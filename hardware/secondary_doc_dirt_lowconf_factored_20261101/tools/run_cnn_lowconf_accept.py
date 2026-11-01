"""Fresh low-score configuration qualification; production RTL is never rewritten.

Prepare freezes generated component benches and integer expectations. Run compiles
the production pipeline/kernel, top metadata controller, and writer separately.
Inference/CCL, PHY/DDR and UART peers are controlled leaves, so this is neither
model accuracy evidence nor physical HDMI/plotter acceptance.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
QUAL = ROOT / 'reports/cnn_lowconf_qualification'
OUT = ROOT / '02_sim/cnn_lowconf_accept'
SIM = Path('E:/model/win64')
PARAMS = ('TRIANGLE_MARGIN_MIN', 'CIRCLE_MARGIN_MIN', 'SQUARE_MARGIN_MIN')
PIPELINE_FILES = ('vision_pipeline.v', 'cnn_result_stabilizer.v')
REPORT_FILES = ('grbl_line_formatter.v', 'grbl_response_parser.v', 'grbl_streamer.v',
                'grbl_vector_font_rom.v', 'grbl_reporter.v')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def put_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def config():
    top = (ROOT / '01_rtl/secondary_top.v').read_text()
    match = re.search(r'vision_pipeline\s*#\((.*?)\)\s*u_vision\s*\(', top, re.S)
    require(match, 'Production u_vision instance missing')
    values = re.findall(r'\.CNN_LOWCONF_OUTPUT\s*\(\s*([^()]*)\s*\)', match[1])
    require(values == ['1'], 'Production low-score publishing must be explicitly enabled')
    defaults = dict(zip(PARAMS, (31, 28, 77)))
    pipeline = (ROOT / '01_rtl/vision_pipeline.v').read_text()
    for name, value in {**defaults, 'COLOR_MARGIN_MIN': 0, 'CNN_LOWCONF_OUTPUT': 0}.items():
        require(not re.findall(r'\.' + name + r'\s*\(', match[1]) or name == 'CNN_LOWCONF_OUTPUT',
                'Production threshold must retain the original default: ' + name)
        require(re.search(r'parameter\s+integer\s+' + name + r'\s*=\s*' + str(value) + r'\s*[,\n]', pipeline),
                'Production default changed: ' + name)
    return {**defaults, 'COLOR_MARGIN_MIN': 0, 'CNN_LOWCONF_OUTPUT': 1}


def bench_text(path):
    tree = ast.parse(Path(path).read_text())
    matches = [node.args[0].value for node in ast.walk(tree)
               if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
               and node.func.attr == 'write_text' and isinstance(node.func.value, ast.Name)
               and node.func.value.id == 'bench' and node.args
               and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)]
    require(len(matches) == 1, 'Bench origin must contain one literal bench')
    return matches[0]


def replace_once(text, before, after):
    require(text.count(before) == 1, 'Test fixture origin changed: ' + before[:90])
    return text.replace(before, after, 1)


def interfaces():
    modules, source_paths = {}, []
    for line in (ROOT / 'lint_full.f').read_text().splitlines():
        if not line.strip():
            continue
        path = (ROOT / line.strip()).resolve()
        require(path.is_relative_to(ROOT), 'Production source escapes new root')
        source_paths.append(path)
        source = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(errors='replace'), flags=re.S)
        for match in re.finditer(r'\bmodule\s+(\w+)\b', source):
            modules[match[1]] = source[match.start():source.index(';', match.end()) + 1] + '\nendmodule\n'
    return modules, source_paths


def prepare():
    require(not (QUAL / 'PREPARED_INPUTS.json').exists(), 'Qualification is already frozen')
    margins = config()
    QUAL.mkdir(parents=True, exist_ok=True)
    modules, source_paths = interfaces()
    pipeline_leaves = ('vision_color_stats', 'vision_pixel_reader', 'edge_roi_ccl', 'vision_workspace',
                       'vision_shared_mac', 'cnn_core', 'pcb_fullboard_spatial96', 'pcb_tinycnn_core',
                       'pcb_tinycnn_core_compact', 'pcb_defect_cluster')
    top_leaves = ('pll', 'PLL', 'secondary_ddr_wrapper', 'reset_sync', 'hxa_ddr_store', 'uiudp_stack',
                  'vision_pixel_reader', 'vision_pipeline', 'hxa_config_store', 'doc_copy_pipeline',
                  'hxa_secondary_link', 'grbl_uart_port', 'grbl_reporter', 'rgmii_interface')
    for name, leaves in [('pipeline', pipeline_leaves), ('top_metadata', top_leaves)]:
        text = '// Controlled test leaves, excluded from every synthesis project.\n'
        text += '\n'.join(modules[leaf] for leaf in leaves if leaf in modules)
        if name == 'top_metadata':
            text += '\nmodule PH1P_LOGIC_BUFG(input i, output o); assign o=i; endmodule\n'
        (QUAL / (name + '_stubs.sv')).write_text(text)

    original = ROOT / 'tools/run_cnn_stability_pipeline.py'
    pipeline = bench_text(original)
    pipeline = replace_once(pipeline, 'vision_pipeline #(.EXTERNAL_READER(1),.SHARED_WORKSPACE(0),',
        'vision_pipeline #(.CNN_LOWCONF_OUTPUT(1),\n .EXTERNAL_READER(1),.SHARED_WORKSPACE(0),')
    pipeline = replace_once(pipeline, 'reg [7:0] score=200;',
        'reg [7:0] score=200;\nreg background_reject=0;\ninteger low_shape;')
    pipeline = replace_once(pipeline, "force dut.cnn_background_reject=1'b0;", 'force dut.cnn_background_reject=background_reject;')
    pipeline = replace_once(pipeline,
        'check(!valid,"low-margin raw argmax cannot establish new class");',
        'check(valid&&count==1&&shape_id==3&&confidence==7&&flags[6],"three low nonzero scores confirm real class and score7");')
    extra_pipeline = r'''
 // Configuration-specific additions, after the unchanged lifecycle program.
 @(negedge clk);multi_case=0;color=1;candidate_count=1;overflow=0;purpose=0;
 candidate_boxes={192'd0,16'd60,16'd80,16'd20,16'd40};
 for(low_shape=1;low_shape<=3;low_shape=low_shape+1)begin
  clear_history;
  ordinary(low_shape,19);check(!valid&&count==0,"low nonzero first observation remains unconfirmed");
  ordinary(low_shape,19);check(!valid&&count==0,"low nonzero second observation remains unconfirmed");
  ordinary(low_shape,19);
  check(valid&&count==1&&shape_id==low_shape&&confidence==7&&flags[6],
        "LOWCONF_NONZERO_THREE_CONFIRM class score7 Type18");
  check(boxes[79:64]==low_shape&&boxes[87:80]==7&&boxes[95:88]==0,
        "LOWCONF_TYPE18_REAL_SCORE_AND_CLASS");
 end
 clear_history;ordinary(2,1);ordinary(2,1);ordinary(2,1);
 check(!valid&&count==0&&confidence==0&&flags[6],"LOWCONF_RAW1_ROUNDS_TO_ZERO_NO_CLASS");
 clear_history;ordinary(2,2);ordinary(2,2);ordinary(2,2);
 check(valid&&shape_id==2&&confidence==1&&flags[6],"LOWCONF_RAW2_REAL_SCORE1");
 ordinary(3,0);check(valid&&shape_id==2&&confidence==0&&flags[6],"LOWCONF_ZERO_HOLDS_PRIOR_FIRST");
 ordinary(3,0);check(valid&&shape_id==2&&confidence==0&&flags[6],"LOWCONF_ZERO_HOLDS_PRIOR_SECOND");
 ordinary(3,0);check(!valid&&count==0&&shape_id==0,"LOWCONF_ZERO_THIRD_CLEARS");
 clear_history;@(negedge clk);background_reject=1;
 ordinary(2,200);ordinary(2,200);ordinary(2,200);
 check(!valid&&count==0&&flags[6],"LOWCONF_HARD_BACKGROUND_REJECT_PRESERVED");
 @(negedge clk);background_reject=0;
 clear_history;ordinary(2,255);ordinary(2,255);ordinary(2,255);
 check(valid&&shape_id==2&&confidence==100&&!flags[6],"LOWCONF_HIGH_SCORE100_UNCHANGED");
 empty_frame(0);check(!valid&&count==0,"LOWCONF_EMPTY_NEVER_INVENTS_CLASS");
 empty_frame(1);check(!valid&&count==0&&flags[2],"LOWCONF_OVERFLOW_FAILS_CLOSED");
 $display("PASS LOWCONF_CONFIGURED_PIPELINE_DIRECTED");
'''
    pipeline = replace_once(pipeline, ' check(errors==0,"all real pipeline/stabilizer integration assertions");',
        extra_pipeline + '\n check(errors==0,"all real pipeline/stabilizer integration assertions");')
    (QUAL / 'tb_lowconf_pipeline.sv').write_text(pipeline)

    top = bench_text(ROOT / 'tools/run_cnn_top_regression.py')
    extra_top = r'''
    // These values are the configured pipeline's exact published score domain.
    result(2,2,7,501,800,101,402,1);
    check(dut.cnn_cache_valid&&dut.cnn_cache_class==5&&dut.cnn_cache_confidence==7,
          "LOWCONF_TOP_CACHE_RETAINS_REAL_SCORE7");
    press_key1;
    check(dut.report_cnn_mode&&dut.report_cnn_class==5&&dut.report_cnn_confidence==7&&
          dut.report_judgement==2&&dut.report_defect_boxes=={224'd0,16'd251,16'd650}&&
          dut.u_reporter.I_cnn_confidence==7,
          "LOWCONF_KEY1_CLASS_CENTER_CONF7_SNAPSHOT");
    @(negedge clk);rep_busy=1;
    result(3,3,1,120,300,40,180,1);
    check(dut.report_cnn_class==5&&dut.report_cnn_confidence==7&&
          dut.report_defect_boxes=={224'd0,16'd251,16'd650},
          "LOWCONF_ACTIVE_REPORT_CANNOT_CHANGE_TO_NEW_RESULT");
    retire;press_key1;
    check(dut.report_cnn_class==9&&dut.report_cnn_confidence==1&&dut.report_judgement==2&&
          dut.report_defect_boxes=={224'd0,16'd110,16'd210},
          "LOWCONF_KEY1_CLASS_CENTER_CONF1_SNAPSHOT");
    retire;
    result(3,3,0,120,300,40,180,1);press_key1;
    check(dut.report_cnn_class==9&&dut.report_cnn_confidence==0&&dut.report_judgement==2,
          "LOWCONF_HELD_IDENTITY_CONF0_IS_NOT_UPGRADED");
    retire;
    result(0,0,0,0,0,0,0,0);press_key1;
    check(dut.report_judgement==0&&dut.report_defect_count==0,
          "LOWCONF_KEY1_NO_TARGET_IS_NOT_A_CLASS");
    retire;
    $display("PASS LOWCONF_TOP_METADATA_DIRECTED");
'''
    top = replace_once(top, '    if(errors!=0)$fatal(1,"TOP_METADATA_FAIL checks=%0d errors=%0d",checks,errors);',
        extra_top + '\n    if(errors!=0)$fatal(1,"TOP_METADATA_FAIL checks=%0d errors=%0d",checks,errors);')
    (QUAL / 'tb_lowconf_top.sv').write_text(top)

    report_origin = ROOT / '02_sim/cnn_named_report/tb_cnn_named_report.sv'
    report = report_origin.read_text()
    begin = report.index('        for(c=1;c<=9;c=c+1)begin reset_dut;run_job(')
    end = report.index('        $fclose(trace_fd);', begin)
    jobs = [{'job': 400 + cls, 'class_id': cls, 'score': 7} for cls in range(1, 10)]
    jobs += [{'job': 410, 'class_id': 5, 'score': 1}, {'job': 411, 'class_id': 5, 'score': 0},
             {'job': 412, 'class_id': 5, 'score': 100}]
    report = report[:begin] + ''.join('        reset_dut;run_job({job},{class_id},{score},2,1,0,0);\n'.format(**job) for job in jobs) + report[end:]
    report = replace_once(report, 'PASS CNN_NAMED_REPORT_ALL 33 jobs plus capacity and safety', 'PASS LOWCONF_NAMED_REPORT_12')
    (QUAL / 'tb_lowconf_report.sv').write_text(report)
    put_json(QUAL / 'report_jobs.json', jobs)

    production = [ROOT / '01_rtl' / name for name in (*PIPELINE_FILES, *REPORT_FILES, 'secondary_top.v')]
    inputs = [Path(__file__), ROOT / 'lint_full.f', original, ROOT / 'tools/run_cnn_top_regression.py',
              ROOT / 'tools/cnn_named_report_reference.py', report_origin, *source_paths, *production,
              *[path for path in QUAL.rglob('*') if path.is_file()]]
    manifest = {'project_root': str(ROOT), 'status': 'PREPARED', 'hardware_status': 'NOT_RUN',
        'production_margin_config': margins,
        'input_sha256': {str(path.relative_to(ROOT)): sha(path) for path in dict.fromkeys(inputs)},
        'scope': __doc__.strip()}
    put_json(QUAL / 'PREPARED_INPUTS.json', manifest)
    print('PREPARED ' + str(QUAL / 'PREPARED_INPUTS.json'), flush=True)


def run():
    marker = QUAL / 'PREPARED_INPUTS.json'
    manifest = json.loads(marker.read_text())
    def verify():
        require(config() == manifest['production_margin_config'], 'Production configuration drift')
        for name, digest in manifest['input_sha256'].items():
            require(sha(ROOT / name) == digest, 'Frozen qualification input drift: ' + name)
    verify()
    require((SIM / 'LICENSE.TXT').is_file(), 'File license is missing')
    output = OUT / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    output.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))
    def command(cwd, label, args, expected=None):
        began = time.time()
        proc = subprocess.run(list(map(str, args)), cwd=cwd, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=360)
        log = cwd / (label + '.log')
        log.write_text(proc.stdout, encoding='utf-8', errors='replace')
        put_json(cwd / (label + '_command.json'), {'argv': list(map(str, args)), 'returncode': proc.returncode,
            'elapsed_seconds': round(time.time() - began, 3), 'log_sha256': sha(log)})
        require(proc.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):', proc.stdout), proc.stdout[-6000:])
        if expected:
            require(expected in proc.stdout, 'Missing completion: ' + expected + '\n' + proc.stdout[-2000:])
        return proc.stdout
    tests = {}
    for name, top, sources, bench, expected in [
        ('pipeline', 'tb_cnn_stability_pipeline', [QUAL / 'pipeline_stubs.sv', *[ROOT / '01_rtl' / n for n in PIPELINE_FILES]],
         QUAL / 'tb_lowconf_pipeline.sv', 'PASS LOWCONF_CONFIGURED_PIPELINE_DIRECTED'),
        ('top_metadata', 'tb_cnn_named_top', [QUAL / 'top_metadata_stubs.sv', ROOT / '01_rtl/secondary_top.v'],
         QUAL / 'tb_lowconf_top.sv', 'PASS LOWCONF_TOP_METADATA_DIRECTED'),
        ('report', 'tb_cnn_named_report', [ROOT / '01_rtl' / n for n in REPORT_FILES],
         QUAL / 'tb_lowconf_report.sv', 'PASS LOWCONF_NAMED_REPORT_12')]:
        cwd = output / name
        cwd.mkdir()
        command(cwd, 'vlib', [SIM / 'vlib.exe', 'work'])
        command(cwd, 'compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', 'work', *sources, bench])
        text = command(cwd, 'simulate', [SIM / 'vsim.exe', '-batch', '-syncio', '-quiet', '-novopt', '-suppress', '12110',
            '-lib', 'work', top, '-do', 'onerror {quit -code 1}; run -all; quit -f'], expected)
        tests[name] = {'status': 'PASS', 'compiled_production_sources': [str(p) for p in sources if p.is_relative_to(ROOT / '01_rtl')],
            'completion_marker': expected, 'checks': [line.strip('# ') for line in text.splitlines() if 'PASS' in line]}
        put_json(cwd / 'RESULTS.json', tests[name])
        print(name.upper() + ': PASS', flush=True)

    spec = importlib.util.spec_from_file_location('lowconf_report_reference', ROOT / 'tools/cnn_named_report_reference.py')
    reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reference)
    font = reference.font_segments(ROOT / '01_rtl/grbl_vector_font_rom.v')
    report = output / 'report'
    glyphs, commands, actual_jobs = {}, {}, []
    for row in (report / 'glyph_trace.txt').read_text().splitlines():
        ident, line, col, char = map(int, row.split('|'))
        glyphs.setdefault(ident, {}).setdefault(line, []).append((col, chr(char)))
    for row in (report / 'gcode.txt').read_text().splitlines():
        ident, text = row.split('|', 1)
        commands.setdefault(int(ident), []).append(text)
    expected_jobs = json.loads((QUAL / 'report_jobs.json').read_text())
    for row, expected_job in zip((report / 'jobmeta.txt').read_text().splitlines(), expected_jobs, strict=True):
        ident, cls, score, judgement, cnn, square, old_offset, new_offset, count = map(int, row.split('|'))
        require((ident, cls, score, judgement, cnn, square, old_offset, new_offset) ==
                (expected_job['job'], expected_job['class_id'], expected_job['score'], 2, 1, 0, 0, 2060), 'Reporter metadata mismatch')
        expected_text = reference.report_text(cls, score, 2, True, ident, (210, 110))
        actual_text = []
        for line in sorted(glyphs[ident]):
            cells = glyphs[ident][line]
            require([col for col, _ in cells] == list(range(len(cells))), 'Glyph order mismatch')
            actual_text.append(''.join(char for _, char in cells))
        require([text.rstrip() for text in actual_text] == [text.rstrip() for text in expected_text], 'Name/center/CONF text mismatch')
        expected_commands = reference.machine_commands(expected_text, font, 0, 2060, False)
        require(commands[ident] == expected_commands and count == len(expected_commands), 'Exact G-code mismatch')
        actual_jobs.append({**expected_job, 'text': actual_text, 'gcode_lines': count, 'all_gcode_commands_exact': True})
    tests['report']['jobs'] = actual_jobs
    tests['report']['name_center_conf_exact'] = True
    put_json(report / 'RESULTS.json', tests['report'])
    verify()
    result = {'status': 'PASS', 'hardware_status': 'NOT_RUN', 'project_root': str(ROOT),
        'production_top_sha256': sha(ROOT / '01_rtl/secondary_top.v'),
        'production_pipeline_sha256': sha(ROOT / '01_rtl/vision_pipeline.v'),
        'production_kernel_sha256': sha(ROOT / '01_rtl/cnn_result_stabilizer.v'),
        'production_margin_config': config(), 'prepared_manifest_sha256': sha(marker),
        'input_sha256': {**manifest['input_sha256'], str(marker.relative_to(ROOT)): sha(marker)},
        'tests': tests, 'confidence_contract': 'round(min(color_margin,shape_margin)*100/255); genuine zero remains uncertain; nonzero confirms after three results; original soft-margin flag6 retained',
        'scope': __doc__.strip(), 'limitations': ['No real inference accuracy or physical HDMI/plotter validation.',
            'Main Type18/OSD acceptance is additionally documented in the independent read-only source audit.']}
    result['output_sha256'] = {str(path.relative_to(ROOT)): sha(path) for path in output.rglob('*')
        if path.is_file() and path.suffix in ('.json', '.log', '.txt') and 'work' not in path.parts}
    put_json(output / 'RESULTS.json', result)
    put_json(OUT / 'RESULTS.json', result)
    put_json(OUT / 'LATEST.json', {'status': 'PASS', 'results': str(output / 'RESULTS.json'),
        'results_sha256': sha(output / 'RESULTS.json')})
    print('PASS CNN LOWCONF ACCEPT ' + str(output / 'RESULTS.json'), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--run', action='store_true')
    args = parser.parse_args()
    prepare() if args.prepare else run()
