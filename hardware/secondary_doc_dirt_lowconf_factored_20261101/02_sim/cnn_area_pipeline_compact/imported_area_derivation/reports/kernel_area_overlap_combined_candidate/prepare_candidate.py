"""Prepare a new combined scratch candidate; preserve every prior source/log."""
from pathlib import Path
import difflib
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
AREA=HERE.parent/'kernel_area_grid_candidate'
OVERLAP=HERE.parent/'kernel_overlap_redundancy_candidate'
R11_SHA='8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36'
AREA_SHA='FBC68868447A38D7695F94A86D66DB3E5D36A3A9EEC5743B944998B8F5574005'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def replace_once(text,old,new):
    assert text.count(old)==1,repr(old)
    return text.replace(old,new)


def write_new(path,text):
    with Path(path).open('x',newline='\n') as stream:
        stream.write(text)


def main():
    assert sha(ROOT/'01_rtl/cnn_result_stabilizer.v')==sha(AREA/'cnn_result_stabilizer_r11.v')==R11_SHA
    assert sha(AREA/'cnn_result_stabilizer.v')==AREA_SHA
    area_text=(AREA/'cnn_result_stabilizer.v').read_text()
    text=replace_once(area_text,'reg pair_axis_y,pair_eligible,pair_overlap,pair_x_ok;',
                      'reg pair_axis_y,pair_eligible,pair_x_ok;')
    text=replace_once(text,'pair_axis_y<=0;pair_eligible<=0;pair_overlap<=0;pair_x_ok<=0;',
                      'pair_axis_y<=0;pair_eligible<=0;pair_x_ok<=0;')
    text=replace_once(text,'                    pair_overlap<=lane_c0<lane_t1 && lane_t0<lane_c1;\n','')
    text=replace_once(text,'pair_x_ok<=pair_overlap && pair_ratio_ok && pair_delta<=pair_max;',
                      'pair_x_ok<=pair_ratio_ok && pair_delta<=pair_max;')
    text=replace_once(text,'pair_geometry_ok<=pair_eligible && pair_x_ok && pair_overlap &&',
                      'pair_geometry_ok<=pair_eligible && pair_x_ok &&')
    assert 'pair_overlap' not in text
    write_new(HERE/'cnn_result_stabilizer.v',text)
    for source,name in [(AREA/'cnn_result_stabilizer_r11.v','cnn_result_stabilizer_r11.v'),
                        (AREA/'cnn_result_stabilizer.v','cnn_result_stabilizer_area_control.v')]:
        with (HERE/name).open('xb') as stream:stream.write(source.read_bytes())
    write_new(HERE/'OVERLAP_ON_AREA_DIFF.patch',''.join(difflib.unified_diff(
        area_text.splitlines(True),text.splitlines(True),fromfile='validated_area',tofile='combined')))
    write_new(HERE/'COMBINED_VS_R11.patch',''.join(difflib.unified_diff(
        (AREA/'cnn_result_stabilizer_r11.v').read_text().splitlines(True),text.splitlines(True),
        fromfile='R11',tofile='combined')))
    out=HERE/'verification'
    out.mkdir(exist_ok=False)
    corrected=AREA/'verification_extreme_fix'
    copied={}
    for source in sorted(corrected.iterdir()):
        if source.suffix in ('.sv','.txt'):
            with (out/source.name).open('xb') as stream:stream.write(source.read_bytes())
            copied[str(source)]=sha(source)
    candidate_sha=sha(HERE/'cnn_result_stabilizer.v')
    runner=(AREA/'run_verification.py').read_text()
    runner=replace_once(runner,AREA_SHA,candidate_sha)
    runner=replace_once(runner,'HERE/"prepare_candidate.py",HERE/"prepare_verification.py",Path(__file__)',
                        'HERE/"prepare_candidate.py",HERE/"PREPARATION.json",Path(__file__)')
    write_new(HERE/'run_verification.py',runner)
    production=(AREA/'run_production_reference.py').read_text()
    production=replace_once(production,AREA_SHA,candidate_sha)
    write_new(HERE/'run_production_reference.py',production)
    record={'status':'PREPARED_NOT_RUN','production_modified':False,'hardware_status':'NOT_RUN',
        'candidate_sha256':candidate_sha,'r11_sha256':R11_SHA,'area_source_sha256':AREA_SHA,
        'changes':'Validated area-grid source plus exactly five redundant-overlap removals; no state/cadence changes',
        'copied_verification_inputs':copied,
        'input_hashes':{str(p):sha(p) for p in [ROOT/'01_rtl/cnn_result_stabilizer.v',
            ROOT/'01_rtl/vision_pipeline.v',ROOT/'01_rtl/secondary_top.v',ROOT/'01_rtl/cnn_core.v',
            AREA/'cnn_result_stabilizer.v',AREA/'cnn_result_stabilizer_r11.v',
            AREA/'run_verification.py',AREA/'run_production_reference.py',Path(__file__)]},
        'scope':'New scratch kernel only. No TD/full-board build and no bitgen.'}
    write_new(HERE/'PREPARATION.json',json.dumps(record,indent=2)+'\n')
    print(json.dumps({'status':record['status'],'candidate_sha256':candidate_sha,
                      'copied_inputs':len(copied),'directory':str(HERE)},indent=2))


if __name__=='__main__':main()
