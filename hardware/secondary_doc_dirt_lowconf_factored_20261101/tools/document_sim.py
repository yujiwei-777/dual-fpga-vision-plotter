"""Run an isolated ModelSim library; preserve commands, return codes and logs."""
import argparse,json,os,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MAIN=ROOT.parent/'main_document_copy_20261020'
TOOLS=Path('E:/model/win64')
def run(args,cwd,log):
    env=os.environ.copy()
    env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']=str(TOOLS/'LICENSE.TXT')
    result=subprocess.run([str(TOOLS/args[0]),*args[1:]],cwd=cwd,env=env,
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    log.write_text(result.stdout,encoding='utf-8')
    print(json.dumps({'command':args,'rc':result.returncode,'log':str(log)}))
    if result.returncode or '** Error' in result.stdout or '** Fatal' in result.stdout:
        print(result.stdout[-10000:]);raise SystemExit(1)
    return result.stdout
def main():
    p=argparse.ArgumentParser();p.add_argument('--test');p.add_argument('--bench');a=p.parse_args()
    dest=ROOT/'02_sim'/'doc_integration';dest.mkdir(exist_ok=True)
    lib=dest/'msim';ini=dest/'modelsim.ini'
    ini.write_text('[Library]\ndoclib = '+lib.as_posix()+'\n',encoding='ascii')
    if not lib.exists():run(['vlib',str(lib)],dest,dest/'vlib.log')
    hdl=MAIN/'01_rtl/imgq_gain_m/main/user_source/hdl_source'
    files=[MAIN/'01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v',
           ROOT/'shared/rtl/hxa_packet_codec.v',ROOT/'shared/rtl/hxa_packet_rx_fifo4.v',
           ROOT/'shared/rtl/hxa_secondary_link.v',ROOT/'01_rtl/secondary_top.v',
           ROOT/'01_rtl/grbl_uart.v',ROOT/'01_rtl/grbl_line_formatter.v',hdl/'reset_sync.v']
    files += sorted((ROOT/'01_rtl').glob('doc_*.v'))
    files += sorted(hdl.glob('doc_*.v'))
    files += [Path('E:/model/anlogic/src/ph1p/ph1p_phy_gsr.v'),Path('E:/model/anlogic/src/ph1p/ph1p_logic_eram.v')]
    if a.bench:files.append(Path(a.bench).resolve())
    run(['vlog','-sv','-work',str(lib),*[str(f) for f in files]],dest,dest/'compile.log')
    if a.test:
        output=run(['vsim','-c','doclib.PH1P_PHY_GSR','doclib.'+a.test,'-do','run -all; quit -f'],dest,dest/(a.test+'.log'))
        if 'PASS ' not in output:raise SystemExit('no self-check PASS marker')
if __name__=='__main__':main()
