"""Prepare/run packed FIFO and actual-packet HXA CRC/network tests, no TD.

The DATA staging counter is deposited only to isolate final-frame admission.
Frame CRC really scans all 115200 zero DDR words; packet CRC runs normally.
"""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import hashlib,json,os,re
from pathlib import Path
import subprocess,sys,zlib
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',action='store_true')
    parser.add_argument('--sim',type=Path,default=Path('E:/model/win64/vsim.exe'))
    parser.add_argument('--design',type=Path,default=ROOT,help='production/frozen design root')
    args=parser.parse_args();design=args.design.resolve()
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
    manifest=design/'SOURCE_MANIFEST.json'
    frozen=None
    if manifest.is_file():
        frozen=json.loads(manifest.read_text(encoding='utf-8'))['files']
        assert all(digest(design/name)==row['sha256'] for name,row in frozen.items()),'Frozen source manifest drift'
    run=ROOT/'reports/pose7/hxa_regression'/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    run.mkdir(parents=True,exist_ok=False)
    benches=ROOT/'reports/pose7/hxa_tests'
    sources=[design/'shared/rtl'/name for name in ['hxa_packet_codec.v','hxa_packet_rx_fifo4.v','hxa_secondary_link.v']]
    sources += [benches/'ph1p_logic_eram_stub.sv',benches/'tb_pose7_fifo4.sv',benches/'tb_pose7_hxa_crc_network.sv']
    pins={str(p):digest(p) for p in [*sources,Path(__file__)]}
    (run/'SOURCE_SHA256.json').write_text(json.dumps(pins,indent=2)+'\n',encoding='utf-8')
    crc=zlib.crc32(bytes(1843200))&0xffffffff
    (run/'pose7_hxa_constants.svh').write_text(f"localparam [31:0] ZERO_FRAME_CRC=32'h{crc:08x};\n",encoding='ascii')
    # Each bench uses $finish. In batch mode this ends vsim, so run the two
    # processes sequentially rather than silently skipping the second bench.
    commands=[]
    for i,bench in enumerate(['tb_pose7_fifo4','tb_pose7_hxa_crc_network']):
        lines=['onerror {quit -code 2}','onbreak {quit -code 3}']
        if i==0:
            lines+=['vlib work',f'vlog -sv +incdir+{run.as_posix()} '+' '.join('"'+p.as_posix()+'"' for p in sources)]
        lines += ['vsim -voptargs=+acc work.'+bench,'run -all','quit -code 0','']
        name=bench+'.do'
        (run/name).write_text('\n'.join(lines),encoding='ascii')
        commands.append([str(args.sim),'-batch','-syncio','-do',name])
    result={'status':'PREPARED','commands':commands,
        'working_directory':str(run),'design':str(design),'zero_frame_crc32':f'{crc:08X}',
        'source_manifest_sha256':digest(manifest) if manifest.is_file() else None,
        'limitations':['Frame DATA staging count is deposited; no claim of complete 1280-fragment DMA/write validation.',
                       'Actual frame CRC reads all115200 DDR words; actual HXA bytes and packet CRC run.',
                       'Existing explicit Type11 reason80 authenticates session but does not compare task/frame ID.',
                       'Physical DDR PHY/CDC and hardware are not tested by behavioral RAM/read model.'],
        'hardware':'NOT_RUN'}
    if args.run:
        env=dict(os.environ);env['LM_LICENSE_FILE']='E:/model/win64/LICENSE.TXT';env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']
        codes=[]
        with (run/'SIM.log').open('w',encoding='utf-8') as log:
            for command in commands:
                codes.append(subprocess.run(command,cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT).returncode)
                if codes[-1]!=0:break
        log=(run/'SIM.log').read_text(encoding='utf-8',errors='replace')
        passed=len(codes)==2 and all(code==0 for code in codes) and 'POSE7_FIFO4_PASS:' in log and 'POSE7_HXA_CRC_NETWORK_PASS' in log and 'HXA_FAIL' not in log and not re.search(r'\*\*\s+(Error|Fatal):',log)
        result.update({'status':'PASS' if passed else 'FAIL','returncodes':codes,
            'HXA_cases_passed':log.count('POSE7_HXA_CASE_PASS'),
            'explicit_wrong_ID_baseline_limitation_observed':'POSE7_HXA_BASELINE_LIMITATION' in log,
            'sources_unchanged':all(digest(Path(p))==h for p,h in pins.items())})
        if not result['sources_unchanged']:result['status']='FAIL_SOURCE_DRIFT'
        if frozen is not None:
            result['frozen_sources_unchanged']=all(digest(design/name)==row['sha256'] for name,row in frozen.items())
            if not result['frozen_sources_unchanged']:result['status']='FAIL_SOURCE_DRIFT'
    (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
    if result['status'].startswith('FAIL'):raise SystemExit(1)


if __name__=='__main__':main()
