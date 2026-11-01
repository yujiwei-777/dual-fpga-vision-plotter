"""Integer golden for doc_stroke_planner; no OCR, fill or lossy simplification.

Distances are sums of floor Euclidean lengths in actual machine 0.01 mm units.
The baseline is retained independently and wins if the planned route is worse.
"""
from __future__ import annotations
from dataclasses import dataclass
from math import isqrt
from pathlib import Path
import argparse
import json
import numpy as np

DIRS=((1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1))
REFERENCE_SOURCE={
    'path':'D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_cnn_named_coords_conf_20261030/model/doc_stroke_reference.py',
    'sha256':'6D98BA7A9F370D3E9B38537C7E024E869AA30973D49D06E412AC8D401CA6139C',
    'method':'Exact file copy before endpoint/branch policy changes; source kept unchanged.',
}

class CapacityError(ValueError):
    def __init__(self, code, text):
        self.code=code
        super().__init__(text)

@dataclass(frozen=True)
class Stroke:
    points: tuple[tuple[int,int], ...]
    closed: bool=False

def thin(image, max_pairs=64):
    a=np.asarray(image,dtype=np.uint8).copy()
    assert a.shape==(320,320)
    a[:70,:]=0;a[250:,:]=0
    for pair in range(max_pairs):
        changed=False
        for phase in range(2):
            p=np.pad(a,1)
            n=(p[:-2,1:-1],p[:-2,2:],p[1:-1,2:],p[2:,2:],
               p[2:,1:-1],p[2:,:-2],p[1:-1,:-2],p[:-2,:-2])
            b=sum(n)
            t=sum(((n[k]==0)&(n[(k+1)%8]!=0)).astype(np.uint8) for k in range(8))
            if phase==0:
                keep=((n[0]*n[2]*n[4])==0)&((n[2]*n[4]*n[6])==0)
            else:
                keep=((n[0]*n[2]*n[6])==0)&((n[0]*n[4]*n[6])==0)
            remove=(a!=0)&(b>=2)&(b<=6)&(t==1)&keep
            changed|=bool(remove.any())
            a[remove]=0
        if not changed:
            return a,pair+1
    raise CapacityError(1,'thinning did not converge within complete iteration pairs')

def graph_edges(skeleton):
    s=np.asarray(skeleton,dtype=bool)
    edges=set()
    for y,x in zip(*np.nonzero(s)):
        x=int(x);y=int(y)
        for dx,dy in ((1,0),(0,1),(1,1),(-1,1)):
            xx=x+dx;yy=y+dy
            if not(0<=xx<320 and 0<=yy<320 and s[yy,xx]):continue
            if dx and dy and (s[y,xx] or s[yy,x]):continue
            edges.add(tuple(sorted(((x,y),(xx,yy)))))
    return edges

def extract(skeleton,max_edges=32768,max_paths=2048,max_points=8192,
            policy='endpoint_branch45'):
    if policy not in ('endpoint_branch45','legacy'):
        raise ValueError('unknown stroke extraction policy: '+str(policy))
    edges=graph_edges(skeleton)
    if len(edges)>max_edges:raise CapacityError(2,'edge capacity')
    original=edges.copy()
    neighbours={}
    for a,b in edges:
        neighbours.setdefault(a,set()).add(b)
        neighbours.setdefault(b,set()).add(a)
    # Branch identity never changes when other paths consume incident edges.
    original_degree={p:len(adj) for p,adj in neighbours.items()}
    dots={(int(x),int(y)) for y,x in zip(*np.nonzero(skeleton)) if (int(x),int(y)) not in neighbours}
    strokes=[]
    def publish(points,closed):
        if len(strokes)>=max_paths:raise CapacityError(3,'path capacity')
        if sum(len(s.points)+s.closed for s in strokes)+len(points)+closed>max_points:
            raise CapacityError(4,'point capacity')
        strokes.append(Stroke(tuple(points),closed))
    for first_pass in (True,False):
        for y in range(320):
            for x in range(320):
                origin=(x,y)
                while True:
                    adj=neighbours.get(origin,set())
                    eligible=(not first_pass) or (len(adj)%2 if policy=='legacy'
                                                  else original_degree.get(origin,0)==1)
                    if adj and eligible:
                        points=[origin];cur=origin;prev=0;steps=0
                        while True:
                            choices=neighbours.get(cur,set())
                            if not choices:
                                if points[-1]!=cur:points.append(cur)
                                closed=False;break
                            direction=next((prev+d)%8 for d in (0,1,7,2,6,3,5,4)
                                if (cur[0]+DIRS[(prev+d)%8][0],cur[1]+DIRS[(prev+d)%8][1]) in choices)
                            turn=min((direction-prev)%8,(prev-direction)%8)
                            if policy=='endpoint_branch45' and steps and original_degree[cur]>=3 and turn>1:
                                # End at the branch without consuming its next
                                # edge. A later path owns all remaining edges.
                                # Degree-two bends retain arbitrary angles.
                                if points[-1]!=cur:points.append(cur)
                                closed=False;break
                            nxt=(cur[0]+DIRS[direction][0],cur[1]+DIRS[direction][1])
                            if steps and direction!=prev:points.append(cur)
                            neighbours[cur].remove(nxt);neighbours[nxt].remove(cur)
                            edges.remove(tuple(sorted((cur,nxt))))
                            cur=nxt;prev=direction;steps+=1
                            if cur==origin:closed=True;break
                        publish(points,closed)
                    elif not adj and origin in dots:
                        dots.remove(origin);publish([origin],False)
                    else:break
    assert not edges
    return strokes,original

def machine(p):
    x,y=p
    x=max(0,min(319,x)); y=max(70,min(249,y))
    # Preserve the camera's 16:9 aspect on the A4 sheet.  The logical
    # drawing rectangle is 190.00 x 106.88 mm, starting at (10,10) mm.
    return 1000+(x*19000+159)//319,1000+((y-70)*10688+89)//179

def distance(a,b):
    aa=(0,0) if a is None else machine(a)
    bb=machine(b)
    return isqrt((aa[0]-bb[0])**2+(aa[1]-bb[1])**2)

def squared(a,b):
    aa=(0,0) if a is None else machine(a)
    bb=machine(b)
    return (aa[0]-bb[0])**2+(aa[1]-bb[1])**2

def endpoints(strokes,entry):
    i,rev,seam=entry;s=strokes[i]
    if s.closed:return s.points[seam],s.points[seam]
    return (s.points[-1],s.points[0]) if rev else (s.points[0],s.points[-1])

def route_cost(strokes,route):
    prev=None;cost=0
    for e in route:
        a,b=endpoints(strokes,e);cost+=distance(prev,a);prev=b
    return cost

def plan(strokes,passes=2,window=32):
    baseline=[(i,False,0) for i in range(len(strokes))]
    route=[];used=set();prev=None
    for _ in strokes:
        best=None
        for i,s in enumerate(strokes):
            if i in used:continue
            candidates=[(squared(prev,s.points[0]),i,False)]
            if not s.closed and len(s.points)>1:
                candidates.append((squared(prev,s.points[-1]),i,True))
            for c in candidates:
                if best is None or c[0]<best[0]:best=c
        _,i,rev=best;used.add(i);route.append((i,rev,0));prev=endpoints(strokes,route[-1])[1]
    for _ in range(passes):
        for i in range(max(0,len(route)-1)):
            for j in range(i+1,min(i+window+1,len(route))):
                p=None if i==0 else endpoints(strokes,route[i-1])[1]
                a=endpoints(strokes,route[i])[0];b=endpoints(strokes,route[j])[1]
                n=None if j+1==len(route) else endpoints(strokes,route[j+1])[0]
                old=distance(p,a)+(distance(b,n) if n is not None else 0)
                new=distance(p,b)+(distance(a,n) if n is not None else 0)
                if old-new>=10:
                    route[i:j+1]=[(k,not r,s) for k,r,s in reversed(route[i:j+1])]
    for pos,(i,rev,seam) in enumerate(route):
        s=strokes[i]
        if not s.closed:continue
        p=None if pos==0 else endpoints(strokes,route[pos-1])[1]
        n=None if pos+1==len(route) else endpoints(strokes,route[pos+1])[0]
        best=min(range(len(s.points)),key=lambda q:distance(p,s.points[q])+
                 (distance(s.points[q],n) if n is not None else 0))
        route[pos]=(i,rev,best)
    bcost=route_cost(strokes,baseline);pcost=route_cost(strokes,route)
    fallback=pcost>bcost
    return (baseline if fallback else route),bcost,min(bcost,pcost),fallback

def point_stream(strokes,route):
    stream=[]
    for i,rev,seam in route:
        s=strokes[i];p=list(s.points)
        if s.closed:
            p=[p[(seam+(-k if rev else k))%len(p)] for k in range(len(p))]
            p.append(p[0])
        elif rev:p.reverse()
        for k,(x,y) in enumerate(p):
            stream.append((x,y,int(k==0),int(k==len(p)-1),int(len(p)==1)))
    return stream

def expand_stream(stream):
    """Recover every pen-down unit edge; asserts no edge is duplicated."""
    found=set();prev=None;dots=[]
    for x,y,start,end,dot in stream:
        p=(x,y)
        if start:prev=p
        else:
            dx=x-prev[0];dy=y-prev[1]
            assert dx==0 or dy==0 or abs(dx)==abs(dy),'lossy non-collinear merge'
            steps=max(abs(dx),abs(dy));assert steps
            ddx=(dx>0)-(dx<0);ddy=(dy>0)-(dy<0)
            for _ in range(steps):
                q=(prev[0]+ddx,prev[1]+ddy);e=tuple(sorted((prev,q)))
                assert e not in found,'edge traversed twice'
                found.add(e);prev=q
        if dot:dots.append(p)
        if end:prev=None
    return found,dots

def prepare(image,plan_passes=2,plan_window=32,**limits):
    sk,pairs=thin(image,limits.pop('max_pairs',64))
    strokes,edges=extract(sk,**limits)
    route,base,planned,fallback=plan(strokes,passes=plan_passes,window=plan_window)
    stream=point_stream(strokes,route)
    recovered,dots=expand_stream(stream)
    assert recovered==edges
    return dict(skeleton=sk,strokes=strokes,route=route,stream=stream,
                edge_count=len(edges),path_count=len(strokes),point_count=len(stream),
                thinning_pairs=pairs,baseline_distance=base,planned_distance=planned,
                use_baseline=fallback,dots=dots)

def fixture():
    a=np.zeros((320,320),dtype=np.uint8)
    # Isolated Chinese dot / punctuation, a branch, a loop, diagonals, and
    # a thick cross requiring multiple complete thinning pairs.
    a[12,50]=1;a[14,55]=1
    a[25,65:91]=1;a[20:36,77]=1
    a[45,120:141]=1;a[65,120:141]=1;a[45:66,120]=1;a[45:66,140]=1
    for k in range(16):a[85+k,170+k]=1
    for k in range(10):a[110+k,205+k:207+k]=1
    a[140:147,75:112]=1;a[127:163,90:97]=1
    # Active raster bounds and separated routes make reversal observable.
    a[210,47:65]=1;a[249,260:273]=1;a[235:249,319]=1
    a[190,220:245]=1;a[200,210:227]=1
    return a

def write_fixture(out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    image=fixture();r=prepare(image)
    (out/'input.mem').write_text(''.join(f'{v:x}\n' for v in image.ravel()),encoding='ascii')
    (out/'expected.mem').write_text(''.join(f'{x|(y<<9)|(s<<18)|(e<<19)|(d<<20):06x}\n'
        for x,y,s,e,d in r['stream']),encoding='ascii')
    report={k:v for k,v in r.items() if k not in ('skeleton','strokes')}
    report['strokes']=[dict(points=s.points,closed=s.closed) for s in r['strokes']]
    (out/'golden.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (out/'expected.vh').write_text(''.join(f'localparam {key.upper()}={int(r[key])};\n'
        for key in ('edge_count','path_count','point_count','baseline_distance','planned_distance')),
        encoding='ascii')
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path)
    args=p.parse_args()
    if args.fixture:
        r=write_fixture(args.fixture)
        print(json.dumps({k:v for k,v in r.items() if k not in ('stream','route','strokes','dots')},indent=2))
