from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
# Each inner list is one continuous pen-down polyline, on a 0..4 x 0..6
# centre-line grid. No filled pixels or row rasterisation is involved.
P = {
 '0': [[(1,0),(3,0),(4,1),(4,5),(3,6),(1,6),(0,5),(0,1),(1,0)]],
 '1': [[(1,1),(2,0),(2,6)],[(1,6),(3,6)]],
 '2': [[(0,1),(1,0),(3,0),(4,1),(4,2),(0,6),(4,6)]],
 '3': [[(0,0),(3,0),(4,1),(3,3),(1,3)],[(3,3),(4,5),(3,6),(0,6)]],
 '4': [[(3,6),(3,0),(0,4),(4,4)]],
 '5': [[(4,0),(0,0),(0,3),(3,3),(4,4),(4,5),(3,6),(0,6)]],
 '6': [[(4,0),(1,0),(0,1),(0,5),(1,6),(3,6),(4,5),(4,4),(3,3),(0,3)]],
 '7': [[(0,0),(4,0),(1,6)]],
 '8': [[(1,3),(0,2),(0,1),(1,0),(3,0),(4,1),(4,2),(3,3),(1,3),(0,4),(0,5),(1,6),(3,6),(4,5),(4,4),(3,3)]],
 '9': [[(4,3),(1,3),(0,2),(0,1),(1,0),(3,0),(4,1),(4,5),(3,6),(0,6)]],
 'A': [[(0,6),(2,0),(4,6)],[(1,3),(3,3)]],
 'B': [[(0,6),(0,0),(3,0),(4,1),(4,2),(3,3),(0,3)],[(3,3),(4,4),(4,5),(3,6),(0,6)]],
 'C': [[(4,1),(3,0),(1,0),(0,1),(0,5),(1,6),(3,6),(4,5)]],
 'D': [[(0,6),(0,0),(2,0),(4,2),(4,4),(2,6),(0,6)]],
 'E': [[(4,0),(0,0),(0,6),(4,6)],[(0,3),(3,3)]],
 'F': [[(0,6),(0,0),(4,0)],[(0,3),(3,3)]],
 'G': [[(4,1),(3,0),(1,0),(0,1),(0,5),(1,6),(3,6),(4,5),(4,3),(2,3)]],
 'H': [[(0,0),(0,6)],[(0,3),(4,3)],[(4,0),(4,6)]],
 'I': [[(0,0),(4,0)],[(2,0),(2,6)],[(0,6),(4,6)]],
 'J': [[(0,0),(4,0),(4,5),(3,6),(1,6),(0,5)]],
 'K': [[(0,0),(0,6)],[(4,0),(0,3),(4,6)]],
 'L': [[(0,0),(0,6),(4,6)]],
 'M': [[(0,6),(0,0),(2,3),(4,0),(4,6)]],
 'N': [[(0,6),(0,0),(4,6),(4,0)]],
 'O': [[(1,0),(3,0),(4,1),(4,5),(3,6),(1,6),(0,5),(0,1),(1,0)]],
 'P': [[(0,6),(0,0),(3,0),(4,1),(4,2),(3,3),(0,3)]],
 'Q': [[(1,0),(3,0),(4,1),(4,5),(3,6),(1,6),(0,5),(0,1),(1,0)],[(2,4),(4,6)]],
 'R': [[(0,6),(0,0),(3,0),(4,1),(4,2),(3,3),(0,3)],[(2,3),(4,6)]],
 'S': [[(4,1),(3,0),(1,0),(0,1),(0,2),(1,3),(3,3),(4,4),(4,5),(3,6),(1,6),(0,5)]],
 'T': [[(0,0),(4,0)],[(2,0),(2,6)]],
 'U': [[(0,0),(0,5),(1,6),(3,6),(4,5),(4,0)]],
 'V': [[(0,0),(2,6),(4,0)]],
 'W': [[(0,0),(1,6),(2,3),(3,6),(4,0)]],
 'X': [[(0,0),(4,6)],[(4,0),(0,6)]],
 'Y': [[(0,0),(2,3),(4,0)],[(2,3),(2,6)]],
 'Z': [[(0,0),(4,0),(0,6),(4,6)]],
 ':': [[(2,2),(2,2)],[(2,4),(2,4)]],
 '-': [[(0,3),(4,3)]],
 '.': [[(2,6),(2,6)]],
 ' ': [],
}

# The digit 8 is reduced to 14 segments to fit the shared 4-bit segment
# metadata. The middle bar is traversed once in each lobe only where needed.
P['8'] = [[(1,3),(0,1),(1,0),(3,0),(4,1),(3,3),(1,3),(0,5),(1,6),(3,6),(4,5),(3,3)]]

table = {}
for c, paths in P.items():
    seg = [(a,b) for path in paths for a,b in zip(path,path[1:])]
    assert len(seg) <= 15, (c,len(seg))
    table[c] = {'segments': [[*a,*b] for a,b in seg], 'strokes':len(paths), 'advance':6}

out = '''// True single-line plotter centre-line font. Each synchronous ROM word
// contains {segment_count,x0,y0,x1,y1}; coordinates use a 0..4 x 0..6
// integer cell. Contiguous segments stay pen-down in grbl_reporter.
module grbl_vector_font_rom #(
 parameter integer SYNC_ROM=1
)(input wire I_clk,input wire [7:0] I_char,input wire [2:0] I_row,
 output wire [4:0] O_pixels,output wire [3:0] O_segment_count,
 output wire [3:0] O_advance_width,input wire [3:0] I_segment,
 output wire [2:0] O_x0,O_y0,O_x1,O_y1);
 (* ram_style="bram" *) reg [15:0] segments[0:1023] /* synthesis syn_ramstyle="block_ram" */;
 reg [15:0] q; integer i;
 wire [9:0] address={I_char[5:0],I_segment};
 initial begin
   for(i=0;i<1024;i=i+1)segments[i]=16'd0;
'''
for c,desc in table.items():
    for i, (x0,y0,x1,y1) in enumerate(desc['segments']):
        word = len(desc['segments'])<<12 | x0<<9 | y0<<6 | x1<<3 | y1
        out += f"   segments[10'd{(ord(c)&63)*16+i}]=16'h{word:04x}; // {c} segment {i}\n"
out += ''' end
 generate if(SYNC_ROM!=0)begin:g_sync
   always @(posedge I_clk)q<=segments[address];
 end else begin:g_async
   always @*q=segments[address];
 end endgenerate
 assign O_segment_count=q[15:12];
 assign {O_x0,O_y0,O_x1,O_y1}=q[11:0];
 assign O_advance_width=4'd6;
 assign O_pixels=5'd0; // Compatibility port; no bitmap is consumed.
endmodule
'''
(ROOT/'01_rtl/grbl_vector_font_rom.v').write_text(out)
(ROOT/'02_sim/single_line_font_reference.json').write_text(json.dumps(table,indent=2))
print('wrote',len(table),'single-line glyphs',sum(len(v['segments']) for v in table.values()),'segments')
