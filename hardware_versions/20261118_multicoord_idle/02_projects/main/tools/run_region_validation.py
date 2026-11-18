"""Run current-variant RTL regressions without editing frozen build inputs."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
FREEZE = Path('E:/codex_main_cnn_multicoord_20261118_r1')
BASELINE = ROOT.parent/'main_pcb_operator_ui_cn_font_shift1_dynamic_osd_20261113'
HDL_REL = Path('01_rtl/imgq_gain_m/main/user_source/hdl_source')
SHARED_REL = Path('01_rtl/imgq_gain_m/shared/rtl')
HDL, DEP = ROOT/HDL_REL, FREEZE/HDL_REL
STAMP = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
ENV = dict(os.environ, LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',
           MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
VLIB, VLOG, VSIM = [f'E:/model/win64/{tool}.exe' for tool in ('vlib','vlog','vsim')]
INPUTS = {}

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()

def add_input(p):
    p=Path(p).resolve()
    INPUTS[str(p)]={'sha256':sha(p),'bytes':p.stat().st_size}
    return p

def paired(relative):
    variant, frozen = add_input(ROOT/relative), add_input(FREEZE/relative)
    assert sha(variant)==sha(frozen), f'Variant/freeze differs: {relative}'
    return variant

def put(p, obj):
    p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def run(out, label, cmd):
    cp=subprocess.run(cmd,cwd=out,env=ENV,stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT,text=True,encoding='utf-8',
                      errors='replace',timeout=300)
    log=out/(label+'.log');log.write_text(cp.stdout,encoding='utf-8')
    row={'step':label,'returncode':cp.returncode,'command':cmd,
         'log':str(log),'log_sha256':sha(log)}
    put(out/(label+'.json'),row)
    print(label,cp.returncode,flush=True)
    if cp.returncode:
        raise RuntimeError(json.dumps(row)+'\n'+cp.stdout[-4000:])
    return row

def simulate(out, name, sources, marker, incdir=None):
    out.mkdir(parents=True)
    rows=[run(out,'vlib',[VLIB,'rtl_lib'])]
    cmd=[VLOG,'-sv','-work','rtl_lib']
    if incdir:cmd+=['+incdir+'+str(incdir)]
    rows.append(run(out,'compile',cmd+[str(p) for p in sources]))
    rows.append(run(out,'simulation',[VSIM,'-batch','-syncio','-quiet',
       '-voptargs=+acc','-lib','rtl_lib',name,'-do',
       'onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f']))
    log=(out/'simulation.log').read_text(encoding='utf-8')
    assert marker in log, f'Missing PASS marker: {marker}'
    assert not re.search(r'\*\* (?:Error|Fatal):',log), 'Simulation diagnostics'
    return {'status':'PASS','marker':marker,'steps':rows}

def verify_inputs():
    mismatch=[p for p,row in INPUTS.items() if sha(p)!=row['sha256']]
    assert not mismatch, 'Input drift: '+str(mismatch)

def main():
    manifest=add_input(FREEZE/'SOURCE_MANIFEST.json')
    add_input(__file__)
    controls=ROOT/'reports/regression_controls'/STAMP
    controls.mkdir(parents=True)
    paired(Path('tests/dynamic_osd/tb_dynamic_status.sv'))
    paired(Path('tests/dynamic_osd/tb_type21_maintenance.sv'))
    panel=paired(HDL_REL/'osd_compact_panel.v')
    font=paired(HDL_REL/'osd_compact_font_rom.v')
    glyph=paired(HDL_REL/'osd_compact_glyphs.vh')
    operator_text=paired(HDL_REL/'operator_ui_text.v')
    link=paired(SHARED_REL/'hxa_main_link.v')
    codec=paired(SHARED_REL/'hxa_packet_codec.v')
    results={}
    results['dynamic_status']=simulate(controls/'dynamic_status','tb_dynamic_status',
      [panel,font,operator_text,ROOT/'tests/dynamic_osd/tb_dynamic_status.sv'],
      'DYNAMIC_OSD_PASS pending_writing_fault_visible idle_hidden',HDL)
    results['type21_maintenance']=simulate(controls/'type21_maintenance','tb_type21_maintenance',
      [codec,link,ROOT/'tests/dynamic_osd/tb_type21_maintenance.sv'],
      'TYPE21_MAINTENANCE_PASS valid_0_to_7 reject_8_and_255 real_crc_session')
    verify_inputs()
    put(controls/'RESULT.json',{'status':'PASS','tests':results,
      'frozen_manifest_sha256':sha(manifest),'inputs':dict(INPUTS),
      'scope':'Actual new-variant dynamic panel/font and HXA main link/packet codec; real CRC/session byte-stream Type21 maintenance 0..7 accepted, 8/255 rejected. All design/test bytes match frozen build. No whole-board simulation or hardware acceptance.',
      'input_drift':[],'hardware_status':'NOT_RUN'})

    out=ROOT/'reports/center_integration'/STAMP
    out.mkdir(parents=True)
    for n in ('hx_result_select.v','hdmi_mixer.v','design_top_wrapper.v'):
        paired(HDL_REL/n)
    top=(HDL/'design_top_wrapper.v').read_text(encoding='utf-8')
    assert top.count('.suspect_cx(S_show_suspect_cx),.suspect_cy(S_show_suspect_cy)')==1
    assert top.count('.I_suspect_cx(S_show_suspect_cx),.I_suspect_cy(S_show_suspect_cy)')==1
    assert top.count('wire [10:0] S_show_suspect_cx;wire [9:0] S_show_suspect_cy;')==1
    for n,m in [('hx_result_select.v','hx_result_select'),('hdmi_mixer.v','hdmi_mixer')]:
        original=add_input(BASELINE/HDL_REL/n)
        t=original.read_text(encoding='utf-8');assert t.count('module '+m)==1
        (out/('control_'+n)).write_text(t.replace('module '+m,'module '+m+'_control',1),encoding='utf-8')

    def mixer_instance(module,inst,control):
        t=(HDL/'hdmi_mixer.v').read_text(encoding='utf-8')
        header=re.sub(r'//[^\n]*','',t[:t.index(');')])
        names=list(dict.fromkeys(re.findall(r'\b[IO]_[A-Za-z0-9_]+',header)))
        values={'I_clk':'pclk','I_rst_n':'rst_n','I_video_de':"1'b1",'I_video_rd_data':"24'h123456",
          'I_ovl_on':'gate','I_ovl_pcb':'pcb_gate','I_pcb_suspect':'sv',
          'I_suspect_x0':'sx0','I_suspect_x1':'sx1','I_suspect_y0':'sy0','I_suspect_y1':'sy1',
          'I_suspect_cx':'scx','I_suspect_cy':'scy','O_hdmi_data':'rgb_base' if control else 'rgb'}
        ports=[]
        for n in names:
            if control and n in ('I_suspect_cx','I_suspect_cy'):continue
            v=values.get(n,'' if n.startswith('O_') else "'0")
            ports.append(f'.{n}({v})')
        return f'  {module} #(.LOGO_ENABLE(0)) {inst}(\n    '+',\n    '.join(ports)+');\n'

    bench_source=paired(Path('tests/suspect_center_dotted/tb_suspect_center.sv'))
    bench=bench_source.read_text(encoding='utf-8')
    assert bench.count('// MIXER_INSTANCES_INSERT')==1
    bench=bench.replace('// MIXER_INSTANCES_INSERT',mixer_instance('hdmi_mixer','mix',False)+
                        mixer_instance('hdmi_mixer_control','base_mix',True))
    generated=out/'tb_suspect_center.sv';generated.write_text(bench,encoding='utf-8')
    dependencies=[]
    for n in ('reset_sync.v','doc_copy_overlay.v','hxa_multibox_overlay.v',
              'osd_operator_decimal_snapshot.v','osd_compact_panel.v',
              'osd_compact_font_rom.v','operator_ui_text.v','osd_compact_glyphs.vh'):
        paired(HDL_REL/n)
        if n.endswith('.v'):dependencies.append(DEP/n)
    sources=dependencies+[HDL/'hx_result_select.v',HDL/'hdmi_mixer.v',
      out/'control_hx_result_select.v',out/'control_hdmi_mixer.v',
      HDL/'design_top_wrapper.v',generated]
    result=simulate(out/'simulation','tb_suspect_center',sources,'SUSPECT_CENTER_PASS ',DEP)
    verify_inputs()
    marker=next(line for line in (out/'simulation/simulation.log').read_text(encoding='utf-8').splitlines() if 'SUSPECT_CENTER_PASS ' in line)
    put(out/'RESULT.json',{'status':'PASS','result':result,'marker':marker,
       'frozen_manifest_sha256':sha(manifest),'inputs':dict(INPUTS),
       'generated_test_sha256':sha(generated),
       'generated_control_sha256':{n:sha(out/('control_'+n)) for n in ('hx_result_select.v','hdmi_mixer.v')},
       'scope':'Actual new-variant hx_result_select/hdmi_mixer plus byte-equal frozen real dependencies elaborated/simulated against successful baseline miter; 163-bit original metadata and pixel checks. Full new-variant top syntax compiled and center named-port wiring checked; no whole-board IP elaboration, synthesis/place/route or localization-accuracy/hardware claim.',
       'inputs_unchanged':True,'hardware_status':'NOT_RUN'})
    print(json.dumps({'status':'PASS','controls':str(controls/'RESULT.json'),
                      'center':str(out/'RESULT.json')},ensure_ascii=False))

if __name__=='__main__':main()
