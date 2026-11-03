"""Check actual placed resource counts, never preliminary Slice*."""
import re
from display_noise_paths import *
def main():
    errors=[];resources={}
    if not (RUN/'.opt_place.end.f').is_file():errors.append('Placement completion marker missing')
    for key,limit in [('slice',95),('eram',90),('dsp',95)]:
        found=re.findall(r'^#'+key+r'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%',read(RUN/(NAME+'_phy.area')),re.M|re.I)
        if len(found)!=1:errors.append('Missing/duplicate actual '+key);continue
        used,total=int(found[0][0]),int(found[0][1]);resources[key]={'used':used,'total':total,'percent':100*used/total,'strict_limit_percent':limit}
        if used*100>=total*limit:errors.append(key+' resource threshold failed')
        if key=='dsp' and used!=37:errors.append('DSP count must remain exactly baseline 37')
    result={'passed':not errors,'resources':resources,'errors':errors,'hardware_status':'NOT_RUN'}
    put(ROOT/'reports/placement_resource_gate.json',result);print(result);return int(bool(errors))
if __name__=='__main__':raise SystemExit(main())
