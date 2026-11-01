from pathlib import Path
import json,re,html,hashlib
ROOT=Path(__file__).resolve().parents[1]
font=json.loads((ROOT/'02_sim/single_line_font_reference.json').read_text())
records={}
for line in (ROOT/'vector_report_gcode.txt').read_text().splitlines():
    j,command=line.split('|',1)
    records.setdefault(int(j),[]).append(command)

def xy(command):
    m=re.fullmatch(r'G([01]) X(\d+)\.(\d+) Y(\d+)\.(\d+) F\d+',command)
    return None if not m else (int(m[1]),int(m[2])*100+int(m[3]),int(m[4])*100+int(m[5]))

offset=5000
results=[]
for job in range(3,16):
    if job<=11:texts=[f'CNN C{job-2}','DEFECTS 0'];height=1460
    elif job<=14:texts=[f'PCB {job:04d} '+{12:'PASS',13:'FAIL',14:'REVIEW'}[job],'DEFECTS 0'];height=1460
    else:texts=['PCB 0015 FAIL','DEFECTS 1','D1 0120 0040 0300 0180'];height=2060
    expected=[];strokes=0;segments=0
    for row,text in enumerate(texts):
        for col,c in enumerate(text):
            previous=None
            for x0,y0,x1,y1 in font[c]['segments']:
                a=(19000-(col*6+x0)*60,1000+offset+(row*10+y0)*60)
                b=(19000-(col*6+x1)*60,1000+offset+(row*10+y1)*60)
                if previous!=a:expected.append((0,*a));strokes+=1
                expected.append((1,*b));segments+=1;previous=b
    expected.append((0,19000,1000+offset+height))
    actual=[v for command in records[job] if (v:=xy(command)) is not None]
    assert actual==expected,(job,next(((i,a,b)for i,(a,b)in enumerate(zip(actual,expected))if a!=b),(len(actual),len(expected))))
    down=sum('Z+005.00' in c for c in records[job])
    assert down==strokes,(job,down,strokes)
    results.append({'job':job,'text':texts,'segments':segments,'pen_down_strokes':strokes,'gcode_lines':len(records[job]),'coordinates_exact':True})
    offset+=height

svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1000" viewBox="0 0 1200 1000">','<rect width="1200" height="1000" fill="white"/>']
def sample(text,x,y,scale=5):
    svg.append(f'<text x="{x}" y="{y-10}" font-family="monospace" font-size="14" fill="#666">{html.escape(text)}</text>')
    for i,c in enumerate(text):
        for x0,y0,x1,y1 in font[c]['segments']:
            svg.append(f'<path d="M {x+(i*6+x0)*scale} {y+y0*scale} L {x+(i*6+x1)*scale} {y+y1*scale}" stroke="#134d77" stroke-width="2" fill="none" stroke-linecap="round"/>')
sample('ABCDEFGHIJKLMNOPQRSTUVWXYZ',25,35,6)
sample('0123456789 :-.',25,110,8)
for i,text in enumerate(['CNN C1','CNN C2','CNN C3','CNN C4','CNN C5','CNN C6','CNN C7','CNN C8','CNN C9']):
    sample(text,25+(i%3)*350,210+(i//3)*100,7)
for i,text in enumerate(['PCB 0012 PASS','PCB 0013 FAIL','PCB 0014 REVIEW','DEFECTS 1','D1 0120 0040 0300 0180']):sample(text,25,550+i*90,6)
svg.append('</svg>')
out=ROOT/'02_sim/vector_reset_lint';out.mkdir(exist_ok=True)
(out/'single_line_font_preview.svg').write_text('\n'.join(svg))
(out/'VECTOR_REFERENCE.json').write_text(json.dumps({'status':'PASS','tests':results,'reference_glyphs':font},indent=2))
print('PASS exact machine-coordinate/G-code replay:',len(results),'reports; glyph segments/continuous strokes matched')
