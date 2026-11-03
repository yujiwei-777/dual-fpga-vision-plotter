// HDMI-only, nonrecursive, edge-preserving causal 2x2 RGB8 spatial filter.
//
// Store source pixels, not filtered pixels. Reject each L/U/UL neighbour
// whose RGB difference from C exceeds EDGE_TH, substituting C for it.
// Interior: round((C+L'+U'+UL')/4). First row/column: two-sample average.
// Data and all five timing markers share two register stages. The row RAM
// is never reset; complete-row/column flags mask stale/uninitialized data.
module a4_display_spatial_h1 #(
    parameter integer ENABLE = 1,
    parameter integer EDGE_TH = 16,
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    input  wire [23:0] I_data,
    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg         O_user,
    output reg         O_last,
    output reg  [23:0] O_data
);
    localparam integer XW = (IMG_WIDTH < 2) ? 1 : $clog2(IMG_WIDTH);
    localparam integer YW = (IMG_HEIGHT < 2) ? 1 : $clog2(IMG_HEIGHT);
    (* ram_style="bram" *) reg [23:0] source_row [0:IMG_WIDTH-1]
        /* synthesis syn_ramstyle="block_ram" */;
    reg [23:0] row_read, row_forward_data;
    reg row_forward;
    wire [23:0] up_data = row_forward ? row_forward_data : row_read;
    reg [XW-1:0] x;
    reg [YW-1:0] y;
    reg frame_started, sof_pending, previous_row_valid, left_valid;
    reg [23:0] left_data, up_left_data;
    wire start_pixel = I_user || sof_pending;
    wire [XW-1:0] input_x = start_pixel ? {XW{1'b0}} : x;
    wire [YW-1:0] input_y = start_pixel ? {YW{1'b0}} : y;
    wire end_row = I_last || (input_x == IMG_WIDTH-1);
    reg p_vsync, p_hsync, p_valid, p_user, p_last;
    reg p_left_valid, p_up_valid;
    reg [XW-1:0] p_x;
    reg [23:0] p_data, p_left;

    // Canonical synchronous simple-dual-port RAM. Retire the preceding
    // source write while reading the new column. Forwarding also defines
    // IMG_WIDTH=1 and abrupt SOF collisions. No async reset on RAM outputs.
    always @(posedge I_clk) begin
        if (I_rst_n) begin
            if (I_de) row_read <= source_row[input_x];
            row_forward <= p_valid && I_de && (p_x == input_x);
            row_forward_data <= p_data;
            if (p_valid) source_row[p_x] <= p_data;
        end
    end
    function close_rgb;
        input [23:0] a,b;
        reg signed [8:0] dr,dg,db;
        begin
            dr=$signed({1'b0,a[23:16]})-$signed({1'b0,b[23:16]});
            dg=$signed({1'b0,a[15:8]})-$signed({1'b0,b[15:8]});
            db=$signed({1'b0,a[7:0]})-$signed({1'b0,b[7:0]});
            close_rgb=(dr>=-EDGE_TH)&&(dr<=EDGE_TH)&&
                      (dg>=-EDGE_TH)&&(dg<=EDGE_TH)&&
                      (db>=-EDGE_TH)&&(db<=EDGE_TH);
        end
    endfunction
    wire use_left = p_left_valid && close_rgb(p_data,p_left);
    wire use_up = p_up_valid && close_rgb(p_data,up_data);
    wire use_up_left = p_left_valid && p_up_valid && close_rgb(p_data,up_left_data);
    wire [23:0] guarded_left = use_left ? p_left : p_data;
    wire [23:0] guarded_up = use_up ? up_data : p_data;
    wire [23:0] guarded_up_left = use_up_left ? up_left_data : p_data;
    function [7:0] avg2;
        input [7:0] a,b;
        reg [8:0] total;
        begin total={1'b0,a}+{1'b0,b}+9'd1;avg2=total[8:1];end
    endfunction
    function [7:0] avg4;
        input [7:0] a,b,c,d;
        reg [8:0] pair0,pair1;
        reg [9:0] total;
        begin
            pair0={1'b0,a}+{1'b0,b};pair1={1'b0,c}+{1'b0,d};
            total={1'b0,pair0}+{1'b0,pair1}+10'd2;avg4=total[9:2];
        end
    endfunction
    genvar channel;
    generate for(channel=0;channel<3;channel=channel+1) begin : g_channel
        wire [7:0] c=p_data[8*channel +:8];
        wire [7:0] l=guarded_left[8*channel +:8];
        wire [7:0] u=guarded_up[8*channel +:8];
        wire [7:0] ul=guarded_up_left[8*channel +:8];
        wire [7:0] filtered=p_up_valid ?
            (p_left_valid?avg4(c,l,u,ul):avg2(c,u)) :
            (p_left_valid?avg2(c,l):c);
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) O_data[8*channel +:8]<=0;
            else O_data[8*channel +:8]<=((ENABLE!=0)&&p_valid)?filtered:c;
        end
    end endgenerate
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;frame_started<=0;sof_pending<=0;
            previous_row_valid<=0;left_valid<=0;left_data<=0;up_left_data<=0;
            p_vsync<=0;p_hsync<=0;p_valid<=0;p_user<=0;p_last<=0;
            p_left_valid<=0;p_up_valid<=0;p_x<=0;p_data<=0;p_left<=0;
            O_vsync<=0;O_hsync<=0;O_de<=0;O_user<=0;O_last<=0;
        end else begin
            // All markers advance through blanking/DE holes. Coordinates
            // and neighbour state advance only on a valid source pixel.
            p_vsync<=I_vsync;p_hsync<=I_hsync;
            p_valid<=I_de;p_user<=I_user;p_last<=I_last;
            p_data<=I_data;p_x<=input_x;p_left<=left_data;
            p_left_valid<=I_de&&!start_pixel&&left_valid;
            p_up_valid<=I_de&&!start_pixel&&frame_started&&previous_row_valid;
            O_vsync<=p_vsync;O_hsync<=p_hsync;
            O_de<=p_valid;O_user<=p_user;O_last<=p_last;
            if(p_valid) up_left_data<=up_data;
            // Isolated blanking SOF does not invent a valid pixel.
            if(I_user&&!I_de) begin
                x<=0;y<=0;sof_pending<=1;frame_started<=1;
                previous_row_valid<=0;left_valid<=0;
            end else if(I_de) begin
                sof_pending<=0;left_data<=I_data;
                if(end_row) begin
                    x<=0;left_valid<=0;
                    // Incomplete or missing-EOL rows never expose stale RAM.
                    previous_row_valid<=I_last&&(input_x==IMG_WIDTH-1)&&
                        (input_y!=IMG_HEIGHT-1)&&(start_pixel||frame_started);
                    if(input_y==IMG_HEIGHT-1) begin y<=0;frame_started<=0;end
                    else begin y<=input_y+1'b1;if(start_pixel)frame_started<=1;end
                end else begin
                    x<=input_x+1'b1;y<=input_y;left_valid<=1;
                    if(start_pixel)begin frame_started<=1;previous_row_valid<=0;end
                end
            end
        end
    end
endmodule
