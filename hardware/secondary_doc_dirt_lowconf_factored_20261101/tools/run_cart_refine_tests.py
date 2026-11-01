"""Run pixel-exact CART, compact-style and KEY3 regressions in an isolated dir."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess
from cart_reference import vectors

ROOT = Path(__file__).resolve().parents[1]

def run(out):
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    isp = ROOT / 'main/user_source/hdl_source/isp'
    files = [isp/n for n in ('cartoon_96.v', 'style_transfer_96.v', 'denoise_96.v',
                            'style_input_fifo.v', 'style_video_96.v', 'display_tone_96.v')]
    files += [ROOT/'main/user_source/hdl_source'/n for n in ('style_controls.v','pcb_teach_key.v')]
    files += [ROOT/'main/02_sim'/n for n in ('tb_cart_stream.sv','tb_style_transfer_96.v',
                                         'tb_style_light_modes.sv','tb_key3_video.sv',
                                         'tb_style_controls.sv','tb_display_tone_96.sv')]
    # Simulation only: synthesis resolves this documented PH1P hard primitive.
    files += [ROOT/'main/02_sim/vendor/ph1p_logic_mult.v']
    recorded = files + [Path(__file__), ROOT/'tools/cart_reference.py']
    hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in recorded}
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT', LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
    results = {}
    def command(name, args, marker=None):
        with (out/(name+'.log')).open('w') as log:
            r = subprocess.run(args, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT)
        text = (out/(name+'.log')).read_text(errors='replace')
        assert r.returncode == 0 and not re.search(r'\*\* (?:Error|Fatal):',text), name
        if marker: assert marker in text, name
        results[name] = 'PASS'
    command('vlib', ['E:/model/win64/vlib.exe','sim'])
    command('lint', ['E:/model/win64/vlog.exe','-sv','-lint','-work','sim',*map(str,files)])
    def sim(name, top, params=(), marker='PASS'):
        command(name, ['E:/model/win64/vsim.exe','-c','-quiet','-lib','sim',top,*params,
                       '-do','onerror {quit -code 1}; run -all; quit -code 0'], marker)
    # The production ``cartoon_96`` path is the one-group, one-output-per-
    # input implementation.  It intentionally cannot drain a full 3x3
    # window because the camera-side stream has no backpressure.  Generate
    # its golden data with the matching causal reference; the complete 3x3
    # model is exercised separately by the diagnostic candidate.
    vectors(out, full_sobel=False)
    sim('cart_direct','tb_cart_stream',['-gDIRECT=1'])
    sim('cart_integrated','tb_cart_stream')
    vectors(out,prefilter=True,full_sobel=False)
    sim('cart_denoise','tb_cart_stream',['-gDENOISE=1'])
    sim('reset_recovery','tb_cart_stream',['-gDENOISE=2','-gRESET_MID_FRAME=1'])
    vectors(out,width=1280,height=720,count=3,prefilter=True,
            image=Path('C:/Users/38401/Pictures/1222.jpg'),full_sobel=False)
    sim('production_720p','tb_cart_stream',['-gDENOISE=2','-gW=1280','-gH=720','-gN=3'])
    sim('production_burst_stalls','tb_cart_stream',['-gDENOISE=2','-gW=1280','-gH=720','-gN=3','-gSTALL_BURST=48'])
    sim('style_alignment','tb_style_transfer_96')
    sim('style_light_modes','tb_style_light_modes')
    sim('key3_controls','tb_style_controls')
    sim('key3_video','tb_key3_video')
    sim('display_tone','tb_display_tone_96')
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in hashes.items()), 'RTL changed during tests'
    (out/'INPUTS.json').write_text(json.dumps(hashes,indent=2))
    (out/'REGRESSIONS.json').write_text(json.dumps(results,indent=2))
    print(json.dumps(results,indent=2))

if __name__ == '__main__':
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,required=True)
    run(p.parse_args().output)
