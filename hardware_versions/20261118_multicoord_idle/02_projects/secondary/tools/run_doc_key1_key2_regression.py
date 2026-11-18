"""Recheck retained KEY2/G54/G92 behavior on this independent source tree."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
SIM = Path('E:/model/win64')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suspect-center',action='store_true',help='Use actual integrated PCB SUSPECT centre parameters')
    args=parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out = ROOT / ('reports/doc_key1/key2_center' if args.suspect_center else 'reports/doc_key1/key2') / stamp
    out.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / '01_rtl' / name for name in (
        'grbl_reporter_shared_candidate.v', 'grbl_shared_transport_candidate.v',
        'grbl_line_formatter.v', 'grbl_response_parser.v', 'grbl_vector_font_rom.v')]
    original=ROOT / '02_sim/key2_zero/tb_key2_zero.sv'
    bench=original
    if args.suspect_center:
        bench=out/'tb_key2_zero.sv'
        text=original.read_text(encoding='utf-8-sig')
        text,n=re.subn(r'(\.KEY2_REZERO\(1\))(?!,\.PCB_SUSPECT_ENABLE\(1\))',r'\1,.PCB_SUSPECT_ENABLE(1),.PCB_SUSPECT_CENTER_INPUT(1)',text,count=1)
        assert n==1,'KEY2 production parameter insertion drift'
        bench.write_text(text,encoding='utf-8')
    sources.append(bench)
    rom=ROOT/'model/suspect/report_text_tokens.mem'
    staged_rom=out.parent/'model/suspect/report_text_tokens.mem'
    staged_rom.parent.mkdir(parents=True,exist_ok=True)
    if staged_rom.exists():
        assert digest(staged_rom)==digest(rom),'Existing staged report ROM differs'
    else:
        staged_rom.write_bytes(rom.read_bytes())
    bound_sources=sources+[original,Path(__file__).resolve(),rom,staged_rom]
    actual_top_parameters=None
    if args.suspect_center:
        top=ROOT/'01_rtl/secondary_top.v'
        declaration=re.search(r'grbl_reporter_shared_candidate\s*#\((.*?)\)\s*u_reporter\s*\(',top.read_text(encoding='utf-8-sig'),re.S)
        assert declaration and re.search(r'\.PCB_SUSPECT_ENABLE\(1\)',declaration[1])
        assert re.search(r'\.PCB_SUSPECT_CENTER_INPUT\(1\)',declaration[1])
        actual_top_parameters=declaration[1]
        bound_sources.append(top)
    pins = {str(p.relative_to(ROOT)): digest(p) for p in bound_sources}
    env = dict(os.environ, LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),
               MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    rows = []
    for label, command in [
        ('vlib', [SIM/'vlib.exe', 'rtl_lib']),
        ('compile', [SIM/'vlog.exe', '-sv', '-lint', '-work', 'rtl_lib', *sources]),
        ('simulation', [SIM/'vsim.exe', '-batch', '-syncio', '-voptargs=+acc',
          '-lib', 'rtl_lib', 'tb_key2_zero', '-do',
          'onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -code 0'])]:
        log = out/(label+'.log')
        with log.open('w', encoding='utf-8') as stream:
            cp = subprocess.run(list(map(str, command)), cwd=out, env=env,
                                stdout=stream, stderr=subprocess.STDOUT, timeout=300)
        text = log.read_text(encoding='utf-8', errors='replace')
        ok = cp.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):', text)
        rows.append(dict(phase=label, exit_code=cp.returncode, passed=ok,
                         log=str(log), sha256=digest(log)))
        if not ok:
            raise RuntimeError(str(log)+'\n'+text[-2500:])
    marker = re.search(r'KEY2_ZERO_REGRESSION_PASS cases=(\d+)', text)
    cases = len(re.findall('KEY2_ZERO_CASE_PASS', text))
    passed = bool(marker) and int(marker[1]) == cases and cases >= 15
    passed = passed and 'KEY2_ZERO_FAIL' not in text
    passed = passed and all(digest(ROOT/p) == h for p,h in pins.items())
    gcode=[dict(case=m[1],line=int(m[2]),text=m[3]) for m in re.finditer(r'^# GCODE case=(.*?) line=(\d+) text=([^\r\n]*)',text,re.M)]
    (out/'GCODE.json').write_text(json.dumps(gcode,indent=2)+'\n',encoding='utf-8')
    result = dict(status='PASS' if passed else 'FAIL', cases=cases,
                  reporter_parameters='PCB_SUSPECT_ENABLE=1,PCB_SUSPECT_CENTER_INPUT=1' if args.suspect_center else 'legacy_default',
                  actual_top_reporter_parameters=actual_top_parameters,gcode_lines=len(gcode),gcode_file=str(out/'GCODE.json'),gcode_sha256=digest(out/'GCODE.json'),
                  source_root=str(ROOT), source_sha256=pins, commands=rows,
                  hardware='NOT_RUN', scope='Retained KEY2 actual reporter/transport/parser/formatter; not document KEY1 confirmation')
    report = out/'RESULT.json'
    report.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(dict(status=result['status'], cases=cases, report=str(report))))
    return 0 if passed else 1

if __name__ == '__main__':
    sys.exit(main())
