// Fast 160x90 ratio-8 color-mask locator for ordinary CNN jobs.
// vision_pipeline supplies the exact (8*x+4,8*y+4) RGB samples, so this
// module stores one mask bit per accepted sample and runs one four-connected
// CCL pass.  Coordinates remain in the 160x90 contract and are mapped by
// vision_pipeline back to 1280x720.
module edge_roi_ccl #(
    parameter integer WIDTH=160,
    parameter integer HEIGHT=90,
    parameter integer EDGE_THRESHOLD=32,
    parameter integer MIN_EDGE_AREA=12
)(
    input wire clk,rst_n,start,
    input wire [8:0] width,
    input wire [7:0] height,
    input wire [15:0] min_area,
    input wire filter_shape,
    input wire pixel_valid,
    input wire [23:0] pixel_rgb,
    input wire [7:0] pixel_luma,
    output wire pixel_ready,
    output reg busy,done,overflow,
    output reg [2:0] count,
    output reg [255:0] boxes,
    output reg [15:0] largest_area,
    output reg [1:0] largest_color,
    output reg [63:0] areas,
    output reg truncated
);
    localparam integer N=WIDTH*HEIGHT;
    localparam [4:0] S_IDLE=0,S_STORE=1,S_STREAM_INIT=2,S_STREAM_REQ=3,
                     S_STREAM_WAIT=4,S_STREAM_CAPTURE=5,S_STREAM_SEND=6,
                     S_CCL_WAIT=7,S_FINISH=8;
    reg [4:0] state;
    reg [7:0] in_x;
    reg [6:0] in_y;
    reg [13:0] in_addr,stream_addr,mask_addr;
    reg mask_q,mask_pending;
    (* ram_style="bram" *) reg mask_mem [0:N-1] /* synthesis syn_ramstyle="block_ram" */;

    reg ccl_start,ccl_pixel_valid;
    wire ccl_ready,ccl_busy,ccl_done,ccl_overflow,ccl_truncated;
    wire [2:0] ccl_count;
    wire [255:0] ccl_boxes;
    wire [15:0] ccl_largest_area;
    wire [1:0] ccl_largest_color;
    wire [63:0] ccl_areas;

    vision_ccl #(.MIN_WIDTH(4),.MIN_HEIGHT(4)) ccl(
        .clk(clk),.rst_n(rst_n),.start(ccl_start),
        .width(9'd160),.height(8'd90),.min_area(16'd12),
        .filter_shape(1'b1),.pixel_valid(ccl_pixel_valid),
        .pixel_color({1'b0,mask_pending}),.pixel_ready(ccl_ready),
        .busy(ccl_busy),.done(ccl_done),.overflow(ccl_overflow),
        .count(ccl_count),.boxes(ccl_boxes),
        .largest_area(ccl_largest_area),.largest_color(ccl_largest_color),
        .areas(ccl_areas),.truncated(ccl_truncated));

    assign pixel_ready=(state==S_STORE);

    function [7:0] max3;
        input [7:0] r,g,b;
        begin max3=(r>g)?((r>b)?r:b):((g>b)?g:b); end
    endfunction
    function [7:0] min3;
        input [7:0] r,g,b;
        begin min3=(r<g)?((r<b)?r:b):((g<b)?g:b); end
    endfunction
    function color_ok;
        input [23:0] rgb;
        reg [7:0] r,g,b,mx,mn,diff;
        reg [10:0] ratio;
        begin
            r=rgb[23:16];g=rgb[15:8];b=rgb[7:0];
            mx=max3(r,g,b);mn=min3(r,g,b);diff=mx-mn;
            ratio={3'b000,diff}<<3;
            color_ok=(mx>=8'd18)&&(ratio>={3'b000,mx});
        end
    endfunction

    // Synchronous mask read.  The address is deliberately outside the async
    // reset process so PH1P can infer one ERAM for the 160x90 bitmap.
    always @(posedge clk) begin
        mask_q<=mask_mem[mask_addr];
        if(rst_n && state==S_STORE && pixel_valid && pixel_ready)
            mask_mem[in_addr]<=color_ok(pixel_rgb);
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE;busy<=0;done<=0;overflow<=0;count<=0;boxes<=0;
            largest_area<=0;largest_color<=0;areas<=0;truncated<=0;
            in_x<=0;in_y<=0;in_addr<=0;stream_addr<=0;mask_addr<=0;
            mask_pending<=0;ccl_start<=0;ccl_pixel_valid<=0;
        end else begin
            done<=0;ccl_start<=0;ccl_pixel_valid<=0;
            case(state)
                S_IDLE: if(start) begin
                    busy<=1;overflow<=0;count<=0;boxes<=0;largest_area<=0;
                    largest_color<=0;areas<=0;truncated<=0;
                    in_x<=0;in_y<=0;in_addr<=0;stream_addr<=0;mask_addr<=0;
                    state<=S_STORE;
                end
                S_STORE: if(pixel_valid && pixel_ready) begin
                    if(in_addr==N-1) begin
                        stream_addr<=0;mask_addr<=0;state<=S_STREAM_INIT;
                    end else begin
                        in_addr<=in_addr+1'b1;
                        if(in_x==WIDTH-1) begin in_x<=0;in_y<=in_y+1'b1;end
                        else in_x<=in_x+1'b1;
                    end
                end
                S_STREAM_INIT: begin
                    mask_pending<=0;ccl_start<=1;state<=S_STREAM_REQ;
                end
                S_STREAM_REQ: begin
                    mask_addr<=stream_addr;state<=S_STREAM_WAIT;
                end
                S_STREAM_WAIT: state<=S_STREAM_CAPTURE;
                S_STREAM_CAPTURE: begin
                    mask_pending<=mask_q;state<=S_STREAM_SEND;
                end
                S_STREAM_SEND: if(ccl_ready) begin
                    ccl_pixel_valid<=1;
                    if(stream_addr==N-1) state<=S_CCL_WAIT;
                    else begin stream_addr<=stream_addr+1'b1;state<=S_STREAM_REQ;end
                end
                S_CCL_WAIT: if(ccl_done) begin
                    // Preserve the four ranked components from vision_ccl.
                    // The downstream CNN scheduler already consumes up to
                    // four slots; dropping slots here caused valid secondary
                    // targets to disappear before classification.
                    overflow<=ccl_overflow;count<=ccl_count;
                    boxes<=ccl_boxes;
                    largest_area<=ccl_largest_area;
                    largest_color<=ccl_largest_color;
                    areas<=ccl_areas;
                    truncated<=ccl_truncated;state<=S_FINISH;
                end
                S_FINISH: begin busy<=0;done<=1;state<=S_IDLE;end
                default: begin busy<=0;state<=S_IDLE;end
            endcase
        end
    end
endmodule

