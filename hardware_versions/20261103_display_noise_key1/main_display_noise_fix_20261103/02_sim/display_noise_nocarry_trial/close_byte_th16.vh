// Exact unsigned-byte |a-b| <= 16 using Boolean logic only.
// High-nibble increment relations are explicit and do not wrap 15->0.
// No +, -, ordered comparisons or inferred arithmetic are written here.
function close_byte_th16;
    input [7:0] a,b;
    reg [3:0] he,hr,hf,le,lr,lf;
    reg high_same,high_rise,high_fall,low_le,low_ge;
    begin
        he=~(a[7:4]^b[7:4]);
        hr=a[7:4]&~b[7:4];
        hf=~a[7:4]&b[7:4];
        le=~(a[3:0]^b[3:0]);
        lr=a[3:0]&~b[3:0];
        lf=~a[3:0]&b[3:0];
        high_same=&he;
        high_rise=(he[3]&he[2]&he[1]&hr[0]) |
                  (he[3]&he[2]&hr[1]&hf[0]) |
                  (he[3]&hr[2]&hf[1]&hf[0]) |
                  (hr[3]&hf[2]&hf[1]&hf[0]);
        high_fall=(he[3]&he[2]&he[1]&hf[0]) |
                  (he[3]&he[2]&hf[1]&hr[0]) |
                  (he[3]&hf[2]&hr[1]&hr[0]) |
                  (hf[3]&hr[2]&hr[1]&hr[0]);
        low_le=lf[3] |
               (le[3]&lf[2]) |
               (le[3]&le[2]&lf[1]) |
               (le[3]&le[2]&le[1]&(~a[0]|b[0]));
        low_ge=lr[3] |
               (le[3]&lr[2]) |
               (le[3]&le[2]&lr[1]) |
               (le[3]&le[2]&le[1]&(a[0]|~b[0]));
        close_byte_th16=high_same | (high_rise&low_le) | (high_fall&low_ge);
    end
endfunction
