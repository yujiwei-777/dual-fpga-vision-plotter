"""Exhaust reachable small-geometry control states for unmasked RAM collisions.

This is an independent control-level invariant check, not a replacement for RTL
simulation. Inputs enumerate arbitrary de/user/last, including malformed frames.
"""
from collections import deque
from itertools import product
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent

def search(width,height,expect_collision=False):
    # x,y,frame_started,sof_pending,previous_row_valid,p_valid,p_x
    initial=(0,0,0,0,0,0,0)
    seen={initial}
    pending=deque([initial])
    transitions=0
    collisions=0
    while pending:
        state=pending.popleft()
        x,y,frame,sof,previous,pvalid,px=state
        for de,user,last in product(range(2),repeat=3):
            transitions+=1
            start=user or sof
            ix=0 if start else x
            iy=0 if start else y
            upvalid=de and not start and frame and previous
            forwarding=pvalid and de and px==ix
            if forwarding and upvalid:
                collisions+=1
                assert expect_collision,(width,height,state,(de,user,last))
            nx,ny,nframe,nsof,nprevious=x,y,frame,sof,previous
            if user and not de:
                nx,ny,nsof,nframe,nprevious=0,0,1,1,0
            elif de:
                nsof=0
                if last or ix==width-1:
                    nx=0
                    nprevious=int(bool(last and ix==width-1 and iy!=height-1 and (start or frame)))
                    if iy==height-1:
                        ny,nframe=0,0
                    else:
                        ny=iy+1
                        if start:nframe=1
                else:
                    nx,ny=ix+1,iy
                    if start:nframe,nprevious=1,0
            out=(nx,ny,nframe,nsof,nprevious,de,ix)
            if out not in seen:
                seen.add(out)
                pending.append(out)
    if expect_collision:assert collisions>0
    return dict(width=width,height=height,reachable_states=len(seen),
                transitions=transitions,unmasked_collisions=collisions,
                explicit_forwarding_required=expect_collision)

def main():
    results=[search(w,h,w==1) for w,h in ((1,2),(1,7),(2,1),(2,2),(2,5),(3,3),(7,1),(7,5),(16,6))]
    output=dict(status='PASS',check='Exhaust all reachable x/y/frame/row/pipeline control states and arbitrary de/user/last combinations; reset returns to the included initial state.',cases=results)
    (HERE/'control_invariant.json').write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps(output))

if __name__=='__main__':main()
