"""Read actual placed resource usage; do not confuse preliminary Slice*."""
import json
from pathlib import Path
import re
import shutil
ROOT=Path(__file__).resolve().parents[1]
RUN=ROOT/'01_rtl/imgq_gain_m/main/td_project_compact_v2'
NAME='camera_to_dsi_display_720p60_cnn_multibox'
def main():
    errors=[]
    area=RUN/(NAME+'_phy.area')
    text=area.read_text(encoding='utf-8-sig')
    resources={}
    if not (RUN/'.opt_place.end.f').is_file(): errors.append('Placement completion marker missing')
    for key,limit in [('slice',95),('eram',90),('dsp',95)]:
        m=re.search(r'^#'+key+r'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%',text,re.M|re.I)
        if not m: errors.append('Missing actual '+key); continue
        used,total=int(m[1]),int(m[2])
        resources[key]={'used':used,'total':total,'percent':100*used/total,'limit_strict_percent':limit}
        if used*100>=total*limit: errors.append(key+' at/over strict threshold')
    result={'passed':not errors,'stage':'placed','resources':resources,'errors':errors}
    (ROOT/'reports').mkdir(exist_ok=True)
    shutil.copyfile(area,ROOT/'reports/compact_placed.area')
    shutil.copyfile(RUN/(NAME+'_place.timing'),ROOT/'reports/compact_placed.timing')
    (ROOT/'reports/placement_resource_gate.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))
    return int(bool(errors))
if __name__=='__main__': raise SystemExit(main())
