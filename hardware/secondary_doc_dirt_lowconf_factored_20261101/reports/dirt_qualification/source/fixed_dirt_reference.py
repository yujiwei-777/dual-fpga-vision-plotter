"""Integer decision for the fixed camera dirt ROI; no morphology or masking."""
from pathlib import Path
import numpy as np

X0,X1,Y0,Y1=288,319,112,179
THRESHOLD=112
DELTA=12
OFFSETS=np.array([-10,-2,6,14])
EXPECTED_READS=320*180*16+(X1-X0+1)*(Y1-Y0+1)*16

def load_y(path):
    values=np.fromfile(Path(path),np.uint8)
    if values.size!=1280*720*2:raise ValueError('Expected 1280x720 YUYV')
    return values[::2].reshape(720,1280)

def mask(y):
    cells=y.reshape(180,4,320,4).transpose(0,2,1,3).reshape(180,320,16)
    second=np.partition(cells,1,axis=-1)[...,1].astype(np.int32)
    result=second<=THRESHOLD
    xx=np.clip(4*np.arange(X0,X1+1)[:,None]+OFFSETS,0,1279)
    yy=np.clip(4*np.arange(Y0,Y1+1)[:,None]+OFFSETS,0,719)
    bg=(y[yy[:,None,:,None],xx[None,:,None,:]].astype(np.int32).sum(axis=(-1,-2))+8)>>4
    result[Y0:Y1+1,X0:X1+1]&=second[Y0:Y1+1,X0:X1+1]+DELTA<=bg
    return result

def canvas(y):
    result=np.zeros((320,320),np.uint8)
    result[70:250]=mask(y)
    return result
