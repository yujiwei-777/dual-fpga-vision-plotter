"""Independent byte arithmetic check; does not run ModelSim or TD.

Proof: a=16*ah+al and b=16*bh+bl. If ah==bh, their absolute
difference is at most 15. If ah==bh+1, a-b=16+al-bl, which is
at most 16 exactly when al<=bl. The reverse case uses al>=bl.
Any high-nibble difference >=2 implies byte distance >=17.
The high-rise/fall formulas enumerate the position of the first zero
in the incremented nibble, excluding the overflow case 15->0.
"""
from pathlib import Path
import hashlib
import json


def close_byte_th16(a,b):
    ah,bh,al,bl=a>>4,b>>4,a&15,b&15
    he=(~(ah^bh))&15
    hr=ah&(~bh)&15
    hf=(~ah)&bh&15
    le=(~(al^bl))&15
    lr=al&(~bl)&15
    lf=(~al)&bl&15
    bit=lambda value,index:(value>>index)&1
    h=lambda index:bit(he,index)
    r=lambda index:bit(hr,index)
    f=lambda index:bit(hf,index)
    e=lambda index:bit(le,index)
    rise=(h(3)&h(2)&h(1)&r(0)) | (h(3)&h(2)&r(1)&f(0)) | (h(3)&r(2)&f(1)&f(0)) | (r(3)&f(2)&f(1)&f(0))
    fall=(h(3)&h(2)&h(1)&f(0)) | (h(3)&h(2)&f(1)&r(0)) | (h(3)&f(2)&r(1)&r(0)) | (f(3)&r(2)&r(1)&r(0))
    low_le=bit(lf,3) | (e(3)&bit(lf,2)) | (e(3)&e(2)&bit(lf,1)) | (e(3)&e(2)&e(1)&(((~a)&1)|(b&1)))
    low_ge=bit(lr,3) | (e(3)&bit(lr,2)) | (e(3)&e(2)&bit(lr,1)) | (e(3)&e(2)&e(1)&((a&1)|((~b)&1)))
    return bool(he==15 or rise&low_le or fall&low_ge)


def main():
    accepted=0
    for a in range(256):
        for b in range(256):
            got=close_byte_th16(a,b)
            expected=abs(a-b)<=16
            assert got==expected,(a,b,got,expected)
            accepted+=got
    root=Path(__file__).resolve().parent
    hashes={name:hashlib.sha256((root/name).read_bytes()).hexdigest().upper()
            for name in ('close_byte_th16.vh','check_close_byte.py')}
    result={'status':'PASS','byte_pairs':65536,'accepted':accepted,
            'source_sha256':hashes,'rtl_simulation':'NOT_RUN','td':'NOT_RUN',
            'scope':'Arithmetic formula verification; production RTL unchanged'}
    (root/'close_byte_check.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    main()
