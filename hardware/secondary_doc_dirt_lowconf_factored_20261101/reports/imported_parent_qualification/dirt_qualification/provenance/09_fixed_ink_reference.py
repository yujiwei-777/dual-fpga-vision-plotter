"""Fixed camera dirt: local contrast only within measured sensor coordinates.

This is document-path input compensation. It neither blanks the ROI nor
changes camera/HDMI/CNN/PCB pixels. Existing experimental models are read-only.
"""
from pathlib import Path
import sys
sys.dont_write_bytecode=True
import numpy as np

ROOT=Path(__file__).resolve().parent
PRIOR=ROOT.parent/'doc_ink_noise_diagnostic_20261101'
sys.path.insert(0,str(PRIOR))
import ink_reference as original

X0,X1,Y0,Y1=288,319,112,179
ROI=np.zeros((180,320),bool)
ROI[Y0:Y1+1,X0:X1+1]=True
REQUESTS=320*180*16+int(ROI.sum())*16

def mask(y):
    blocks=original.blocks(y)
    second=np.partition(blocks.reshape(180,320,16),1,axis=-1)[...,1].astype(np.int16)
    xx=np.clip(np.arange(320)[:,None]*4+np.array([-10,-2,6,14]),0,1279)
    yy=np.clip(np.arange(180)[:,None]*4+np.array([-10,-2,6,14]),0,719)
    probes=y[yy[:,None,:,None],xx[None,:,None,:]].astype(np.int32)
    background=(probes.sum(axis=(-1,-2))+8)//16
    exact=second<=112
    return exact & (~ROI | (second+12<=background))

def controls(y):
    return {
        'released':(original.blocks(y,legacy=True)<=112).sum(axis=(-1,-2))>=2,
        'exact_4x4':(original.blocks(y)<=112).sum(axis=(-1,-2))>=2,
        'fixed_region':mask(y),
    }
