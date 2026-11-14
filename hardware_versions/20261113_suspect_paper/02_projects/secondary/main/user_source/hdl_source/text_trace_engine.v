// Low-resource white-paper/black-ink tracing engine.
// The engine consumes one 320x180 luma sample per accepted pixel.  It keeps
// one horizontal centre line per non-empty row and one vertical centre line
// for the complete ink envelope.  This is deliberately a bounded shape
// tracer, rather than OCR or a character classifier.
module text_trace_engine(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire       cancel,
    input  wire       pixel_valid,
    input  wire [8:0] pixel_x,
    input  wire [7:0] pixel_y,
    input  wire [7:0] pixel_luma,
    output reg        busy,
    output reg        done,
    output reg        valid,
    output reg [8:0]  segment_count,
    input  wire [7:0] segment_index,
    output reg        segment_valid,
    output reg [5:0]  segment_x0,
    output reg [5:0]  segment_y0,
    output reg [5:0]  segment_x1,
    output reg [5:0]  segment_y1
);
    reg [8:0] row_min,row_max;
    reg [7:0] row_count;
    reg [8:0] ink_min_x,ink_max_x;
    reg [7:0] ink_min_y,ink_max_y;
    reg       ink_seen;
    reg [1:0] finish_state;
    localparam F_IDLE=0,F_VERTICAL=1,F_DONE=2;
    (* ram_style="block_ram" *) reg [5:0] sx0[0:255];
    (* ram_style="block_ram" *) reg [5:0] sy0[0:255];
    (* ram_style="block_ram" *) reg [5:0] sx1[0:255];
    (* ram_style="block_ram" *) reg [5:0] sy1[0:255];

    wire ink = pixel_luma < 8'd128;
    wire [7:0] row_count_eff = ink ? ((row_count==0) ? 8'd1 : row_count+1'b1) : row_count;
    wire [8:0] row_min_eff = ink ? ((row_count==0 || pixel_x<row_min) ? pixel_x : row_min) : row_min;
    wire [8:0] row_max_eff = ink ? ((row_count==0 || pixel_x>row_max) ? pixel_x : row_max) : row_max;
    wire [8:0] ink_min_x_eff = ink ? ((!ink_seen || pixel_x<ink_min_x) ? pixel_x : ink_min_x) : ink_min_x;
    wire [8:0] ink_max_x_eff = ink ? ((!ink_seen || pixel_x>ink_max_x) ? pixel_x : ink_max_x) : ink_max_x;
    wire [7:0] ink_min_y_eff = ink ? ((!ink_seen || pixel_y<ink_min_y) ? pixel_y : ink_min_y) : ink_min_y;
    wire [7:0] ink_max_y_eff = ink ? ((!ink_seen || pixel_y>ink_max_y) ? pixel_y : ink_max_y) : ink_max_y;

    function [5:0] map_x;
        input [8:0] v; reg [17:0] t;
        begin t=({9'd0,v}<<3)+({9'd0,v}<<2)+v; // ~= v*13, /64 ~= /4.92
            map_x=(t[17:6]>63)?6'd63:t[11:6]; end
    endfunction
    function [5:0] map_y;
        input [7:0] v; reg [15:0] t;
        begin t=({8'd0,v}<<5)+({8'd0,v}<<4)+({8'd0,v}<<1); // ~= v*50
            map_y=(t[15:8]>31)?6'd31:t[13:8]; end
    endfunction

    always @* begin
        segment_valid=1'b0;segment_x0=0;segment_y0=0;segment_x1=0;segment_y1=0;
        if(segment_index < segment_count) begin
            segment_valid=valid;
            segment_x0=sx0[segment_index];segment_y0=sy0[segment_index];
            segment_x1=sx1[segment_index];segment_y1=sy1[segment_index];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;valid<=0;segment_count<=0;row_min<=0;row_max<=0;row_count<=0;
            ink_min_x<=0;ink_max_x<=0;ink_min_y<=0;ink_max_y<=0;ink_seen<=0;finish_state<=F_IDLE;
        end else begin
            done<=0;
            if(cancel) begin busy<=0;valid<=0;segment_count<=0;finish_state<=F_IDLE;end
            else if(start && !busy) begin
                busy<=1;valid<=0;segment_count<=0;row_count<=0;ink_seen<=0;finish_state<=F_IDLE;
            end else if(busy && finish_state==F_IDLE && pixel_valid) begin
                row_min<=row_min_eff;row_max<=row_max_eff;row_count<=row_count_eff;
                if(ink) begin
                    ink_seen<=1;ink_min_x<=ink_min_x_eff;ink_max_x<=ink_max_x_eff;
                    ink_min_y<=ink_min_y_eff;ink_max_y<=ink_max_y_eff;
                end
                if(pixel_x==9'd319) begin
                    if(row_count_eff>=8'd2 && segment_count<9'd256) begin
                        sx0[segment_count[7:0]]<=map_x(row_min_eff);
                        sy0[segment_count[7:0]]<=map_y(pixel_y);
                        sx1[segment_count[7:0]]<=map_x(row_max_eff);
                        sy1[segment_count[7:0]]<=map_y(pixel_y);
                        segment_count<=segment_count+1'b1;
                    end
                    row_count<=0;row_min<=0;row_max<=0;
                    if(pixel_y==8'd179) begin
                        // Save final-pixel-inclusive envelope before adding
                        // the vertical centre line on the next clock.
                        if(ink) begin ink_min_x<=ink_min_x_eff;ink_max_x<=ink_max_x_eff;
                            ink_min_y<=ink_min_y_eff;ink_max_y<=ink_max_y_eff;ink_seen<=1;end
                        finish_state<=F_VERTICAL;
                    end
                end
            end else if(busy && finish_state==F_VERTICAL) begin
                if(ink_seen && segment_count<9'd256 && (ink_max_y-ink_min_y)>=8'd4) begin
                    sx0[segment_count[7:0]]<=map_x((ink_min_x+ink_max_x)>>1);
                    sx1[segment_count[7:0]]<=map_x((ink_min_x+ink_max_x)>>1);
                    sy0[segment_count[7:0]]<=map_y(ink_min_y);
                    sy1[segment_count[7:0]]<=map_y(ink_max_y);
                    segment_count<=segment_count+1'b1;
                end
                valid<=ink_seen && (segment_count!=0);finish_state<=F_DONE;
            end else if(busy && finish_state==F_DONE) begin
                busy<=0;done<=1;finish_state<=F_IDLE;
            end
        end
    end
endmodule
