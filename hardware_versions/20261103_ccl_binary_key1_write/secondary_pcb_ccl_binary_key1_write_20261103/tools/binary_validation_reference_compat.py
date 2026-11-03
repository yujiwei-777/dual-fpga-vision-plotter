"""Frozen GOOD/BAD integer reference; shared grayscale CCL and original x1.00 ROI.
No fitting, threshold adjustment, writes to previous projects, or rotation.
"""
from collections import Counter,deque
import hashlib, json, sys, zlib
from pathlib import Path
import cv2
import numpy as np
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent
OUT=ROOT/'reports/retrained/binary_validation_compat';MODEL=ROOT/'model/experiments/conv4_4'
EXPECTED={'weights.mem':'92A3BBFD2192CC3D74A5BD3A893A34FCC3D45AE727DBEB8DEFAC56033634874B','biases.mem':'88F1FC576BB24DC35FA58B5620F09CFBA7B61E600B5E92DE2CAD40DA2080B2D0'}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
def mem(p,a,bits):Path(p).write_text(''.join(f'{int(v)&((1<<bits)-1):0{bits//4}x}\n' for v in np.asarray(a).ravel()),encoding='ascii')
def ccl(y):
    f=np.ascontiguousarray(y[4::8,4::8]<=112,dtype=np.uint8)
    left=np.zeros_like(f);left[:,1:]=f[:,:-1];up=np.zeros_like(f);up[1:]=f[:-1]
    provisional=int(((f!=0)&(left==0)&(up==0)).sum())
    ans={'provisional_labels':provisional,'overflow':provisional>510,'count':0,'bbox':None,'border_touch':False}
    if ans['overflow']:return ans
    n,labels,stats,_=cv2.connectedComponentsWithStats(f,connectivity=4,ltype=cv2.CV_32S);found=[]
    for k in range(1,n):
        x,yy,w,h,area=map(int,stats[k])
        if area>=64 and w>=8 and h>=4 and w<=5*h and h<=5*w and area*12>=w*h:
            found.append((-area,int(np.flatnonzero(labels.ravel()==k)[0]),[x*8,yy*8,(x+w)*8,(yy+h)*8]))
    found.sort();ans['count']=min(4,len(found))
    if found:
        ans['bbox']=found[0][2];x0,y0,x1,y1=ans['bbox'];ans['border_touch']=x0==0 or y0==0 or x1==1280 or y1==720
    return ans
def expand(box):
    # Compatibility name; this round's trained contract uses the CCL box unchanged.
    x0,y0,x1,y1=map(int,box)
    if not(0<=x0<x1<=1280 and 0<=y0<y1<=720):return {'valid':False,'reason':'invalid_original_box'}
    return {'box':[x0,y0,x1,y1],'width':x1-x0,'height':y1-y0,'valid':True,'reason':None}
def sample(y,box):
    x0,y0,x1,y1=map(int,box);assert 0<=x0<x1<=1280 and 0<=y0<y1<=720
    xx=x0+((2*np.arange(96,dtype=np.int64)+1)*(x1-x0))//192
    yy=y0+((2*np.arange(96,dtype=np.int64)+1)*(y1-y0))//192
    return y[yy[:,None],xx[None,:]].copy(),xx,yy
def load_y(path):
    meta=read(path);assert(meta['width'],meta['height'],meta['pixel_format'])==(1280,720,'YUYV')
    raw_path=Path(path).parent/meta['raw_file'];raw=raw_path.read_bytes();assert len(raw)==1280*720*2
    assert hashlib.sha256(raw).hexdigest().upper()==meta['raw_sha256'].upper()
    assert f'{zlib.crc32(raw)&0xffffffff:08x}'==meta['crc32'].lower()
    assert all(meta.get('transport_counters',{}).get(k,0)==0 for k in ('invalid_packets','packet_crc_errors','frame_crc_errors'))
    return np.frombuffer(raw,np.uint8).reshape(720,1280,2)[:,:,0].copy(),raw,raw_path
def load_model():
    assert all(sha(MODEL/k)==v for k,v in EXPECTED.items())
    w=np.array([int(v,16) for v in(MODEL/'weights.mem').read_text().split()],np.uint8).view(np.int8)
    b=np.array([int(v,16) for v in(MODEL/'biases.mem').read_text().split()],np.uint32).view(np.int32);assert(len(w),len(b))==(308,10)
    return {'w1':w[:36].reshape(4,1,3,3),'w2':w[36:180].reshape(4,4,3,3),'w3':w[180:].reshape(2,64),'b1':b[:4],'b2':b[4:8],'b3':b[8:]}
def conv(x,w,b):
    ic,h,width=x.shape;oh,ow=(h+1)//2,(width+1)//2;p=np.pad(x.astype(np.int64),((0,0),(1,1),(1,1)))
    acc=np.broadcast_to(b[:,None,None].astype(np.int64),(4,oh,ow)).copy()
    for ci in range(ic):
        for ky in range(3):
            for kx in range(3):acc+=p[ci,ky:ky+2*oh:2,kx:kx+2*ow:2][None]*w[:,ci,ky,kx,None,None].astype(np.int64)
    assert acc.min()>=-(1<<26) and acc.max()<(1<<26)
    out=np.clip(acc>>7,0,32767).astype(np.int16)
    for oc in range(4):
        for oy,ox in((0,0),(0,ow-1),(oh-1,0),(oh-1,ow-1),(1,1),(oh//2,ow//2)):
            val=int(b[oc])
            for ci in range(ic):
                for ky in range(3):
                    for kx in range(3):
                        sy,sx=2*oy+ky-1,2*ox+kx-1
                        if 0<=sy<h and 0<=sx<width:val+=int(x[ci,sy,sx])*int(w[oc,ci,ky,kx])
            assert val==acc[oc,oy,ox] and min(32767,max(0,val>>7))==int(out[oc,oy,ox])
    return out,acc
def infer(roi,m):
    f1,a1=conv(roi[None].astype(np.int16),m['w1'],m['b1']);f2,a2=conv(f1,m['w2'],m['b2'])
    pool=(f2.astype(np.int64).reshape(4,4,6,4,6).sum((2,4))>>5).reshape(64);assert int(pool.max())<32768
    for i in range(64):
        ch,by,bx=i//16,(i//4)%4,i%4
        assert sum(int(f2[ch,6*by+dy,6*bx+dx]) for dy in range(6) for dx in range(6))>>5==pool[i]
    head=m['w3'].astype(np.int64)@pool+m['b3'].astype(np.int64);assert head.min()>=-(1<<26) and head.max()<(1<<26)
    logits=head>>8;assert logits.min()>=-(1<<19) and logits.max()<(1<<19)
    for c in range(2):assert sum(int(pool[i])*int(m['w3'][c,i]) for i in range(64))+int(m['b3'][c])==head[c]
    cls=int(logits[1]>logits[0]);best=int(logits[cls]);margin=min(65535,abs(int(logits[0])-int(logits[1])))
    result={'class_id':cls,'class':'GOOD' if cls==0 else 'BAD','logits':logits.tolist(),'score':max(0,min(255,best)),'margin':margin,'status':'REVIEW' if margin<32 else 'PASS' if cls==0 else 'FAIL','activation_saturations':int(((a1>>7)>32767).sum()+((a2>>7)>32767).sum()),'max_abs_accumulators':[int(np.abs(a1).max()),int(np.abs(a2).max()),int(np.abs(head).max())]}
    return result,{'roi':roi,'conv1':f1,'conv2':f2,'pool':pool,'logits':logits}
def check_addresses():
    cases=[[100,100,200,200],[100,100,101,101],[0,100,100,200],[1180,100,1280,200],[100,0,200,100],[100,620,200,720],[64,64,1216,656],[100,200,1060,544],[0,0,1280,720]]
    records=[];y=np.arange(720,dtype=np.uint32)[:,None]*1280+np.arange(1280,dtype=np.uint32)[None,:]
    for original in cases:
        e=expand(original);assert e['box']==original and e['valid']
        pixels,xx,yy=sample(y,e['box'])
        for v in range(96):
            for u in range(96):
                sx=original[0]+((2*u+1)*e['width'])//192;sy=original[1]+((2*v+1)*e['height'])//192
                assert int(pixels[v,u])==sy*1280+sx
        assert np.all(np.diff(xx)>=0) and np.all(np.diff(yy)>=0)
        records.append({'original':original,**e})
    invalid=[[0,0,0,10],[1,1,0,10],[-1,10,100,100],[10,10,1281,100],[10,10,100,721]]
    for box in invalid:assert not expand(box)['valid']
    exhaustive=0
    for limit in(1280,720):
        for span in range(1,limit+1):
            for lo in set((0,(limit-span)//2,limit-span)):
                for u in range(96):assert lo<=lo+((2*u+1)*span)//192<lo+span
                exhaustive+=1
    return {'status':'PASS','directed_cases':records,'invalid_boxes':invalid,'axis_span_centres':exhaustive,'pixels_checked_per_directed_case':9216,'note':'Source-border rejection is a separate adapter gate, not a sampler arithmetic condition.'}
def selected_sources():
    manifest=read(BASE/'pcb_ccl_binary_user_retrain_20261102/data/MANIFEST.json')['frames']
    groups=[('current_good','current20261102','GOOD'),('older_good','new20261029','GOOD'),('missing_corner','new20261029','MISSING_CORNER'),('older_missing_pad','new20261029','MISSING_PAD'),('current_missing_pad','new_missing_pad_20261102','MISSING_PAD')]
    chosen=[]
    for label,domain,group in groups:
        rows=[r for r in manifest if r['domain']==domain and r['group']==group and r['gate']=='VALID']
        for index in(0,len(rows)//2,len(rows)-1):chosen.append({'selection_group':label,'selection_index':index,**rows[index]})
    assert len(chosen)==15 and len({r['source_json'] for r in chosen})==15
    return chosen
def independent_ccl(source):
    """Flood fill, independent of the RTL union/statistic implementation."""
    mask = [int(source[(8*y+4)*1280+8*x+4] <= 112) for y in range(90) for x in range(160)]
    provisional = sum(mask[i] and (i % 160 == 0 or not mask[i-1]) and
                      (i < 160 or not mask[i-160]) for i in range(14400))
    seen = bytearray(14400)
    eligible = []
    for first in range(14400):
        if not mask[first] or seen[first]:
            continue
        seen[first] = 1
        queue = deque([first])
        area = 0
        x0 = x1 = first % 160
        y0 = y1 = first // 160
        while queue:
            i = queue.popleft()
            x, y = i % 160, i // 160
            area += 1
            x0, x1 = min(x0, x), max(x1, x)
            y0, y1 = min(y0, y), max(y1, y)
            neighbors = []
            if x: neighbors.append(i-1)
            if x < 159: neighbors.append(i+1)
            if y: neighbors.append(i-160)
            if y < 89: neighbors.append(i+160)
            for j in neighbors:
                if mask[j] and not seen[j]:
                    seen[j] = 1
                    queue.append(j)
        w, h = x1-x0+1, y1-y0+1
        if area >= 64 and w >= 8 and h >= 4 and w <= 5*h and h <= 5*w and area*12 >= w*h:
            eligible.append({'area': area, 'first': first, 'grid_box': [x0, y0, x1+1, y1+1]})
    eligible.sort(key=lambda c: (-c['area'], c['first']))
    overflow = provisional > 510
    top4 = eligible[:4] if not overflow else []
    return mask, {'provisional_labels': provisional, 'overflow': overflow,
                  'truncated': len(eligible) > 4, 'count': len(top4),
                  'eligible_components': eligible, 'top4': top4}

def prepare():
    OUT.mkdir(parents=True,exist_ok=True);vector=OUT/'fixtures';vector.mkdir(exist_ok=False)
    save(OUT/'ADDRESS_CHECKS.json',check_addresses());m=load_model();cases=[];arrays=[];raws=[];summaries=[];chosen=selected_sources()
    save(OUT/'SELECTION_BEFORE_INFERENCE.json',{'policy':'first/middle/last from each frozen metadata group, no selection on score','rows':chosen,'model_sha256':EXPECTED})
    for n,row in enumerate(chosen):
        y,raw,raw_path=load_y(row['source_json']);cc=ccl(y);assert sha(row['source_json'])==row['source_json_sha256'];assert cc==row['ccl'],(row['source_json'],cc,row['ccl'])
        record={'name':f'real_{n:02d}_'+row['selection_group'],'group':row['group'],'domain':row['domain'],'source_json':row['source_json'],'source_json_sha256':sha(row['source_json']),'raw_path':str(raw_path),'raw_sha256':sha(raw_path),'ccl':cc};gates=[]
        if cc['overflow']:gates.append('ccl_overflow')
        if cc['bbox'] is None:gates.append('no_candidate')
        if cc['border_touch']:gates.append('source_border')
        ex=expand(cc['bbox']) if cc['bbox'] else {'valid':False,'reason':'no_candidate'};record['expanded']=ex
        if not ex['valid']:gates.append(ex['reason'])
        record['gate_reasons']=gates
        if gates:record['status']='REVIEW';summaries.append(record);continue
        roi,xx,yy=sample(y,ex['box']);assert hashlib.sha256(roi.tobytes()).hexdigest().upper()==row['roi_sha256'];result,features=infer(roi,m);record.update(result)
        record.update({'x_addresses':xx.tolist(),'y_addresses':yy.tolist(),'core_case':len(cases),'roi_sha256':hashlib.sha256(roi.tobytes()).hexdigest().upper()})
        raws.append(raw);cases.append(record);arrays.append(features);summaries.append(record);cv2.imwrite(str(vector/(record['name']+'.png')),roi)
    real_count=len(cases)
    for label,value in[('black',0),('gray128',128),('white',255)]:
        result,features=infer(np.full((96,96),value,np.uint8),m);cases.append({'name':'synthetic_'+label,'group':'SYNTHETIC','core_case':len(cases),**result});arrays.append(features)
    names={'roi':'input_pixels','conv1':'expected_f1','conv2':'expected_f2','pool':'expected_pool','logits':'expected_logits'}
    for key,bits in[('roi',8),('conv1',16),('conv2',16),('pool',16),('logits',32)]:
        a=np.stack([r[key] for r in arrays]);a=a.transpose(0,2,3,1) if key in('conv1','conv2') else a;mem(vector/(names[key]+'.mem'),a,bits)
    with(vector/'raw_frames.bin').open('wb') as stream:
        for raw in raws:stream.write(raw)
    np.savez_compressed(vector/'ARRAYS.npz',**{key:np.stack([r[key] for r in arrays]) for key in arrays[0]})
    save(vector/'INDEX.json',{'real_cases':real_count,'core_cases':len(cases),'cases':cases,'selected_source_results':summaries,'model_sha256':EXPECTED,'contract':{'roi_expansion':'x1.00, original CCL half-open box unchanged','sample':'origin+floor((2*u+1)*span/192)','input':'unsigned Y8; no subtraction, no rotation','margin_min':32},'limitations':['Selected real frames are diagnostic examples, not accuracy estimation.','This retrained model uses exactly the original CCL box; this is not the older x1.2 contract.','These source frames were observed in previous development; not blind tests.','RTL and hardware need separate verification.']})
    save(vector/'SHA256.json',{p.name:sha(p) for p in vector.iterdir() if p.is_file()})
    report={'status':'PASS_INTEGER_CHECKS','selected_frames':len(chosen),'real_core_cases':real_count,'synthetic_core_cases':3,'selected_result_counts':{g:dict(Counter(r['status'] for r in summaries if r['group']==g)) for g in sorted(set(r['group'] for r in summaries))},'hardware':'NOT_RUN','RTL':'NOT_RUN','fixture_index':str(vector/'INDEX.json')};save(OUT/'SOFTWARE_REPLAY.json',report);print(json.dumps(report,indent=2))
if __name__=='__main__':prepare()
