// Nearest-neighbour 64x64 ROI sampler for secondary-A.
// It drives the existing vision_pixel_reader request/valid handshake and
// exposes a back-pressured RGB888 stream for secondary_a_yolo_bridge.
module secondary_a_roi_sampler(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [10:0] roi_x0,
    input  wire [10:0] roi_x1,
    input  wire [9:0]  roi_y0,
    input  wire [9:0]  roi_y1,
    output reg         busy,
    output reg         done,
    output reg         reader_request,
    output reg [10:0]  reader_x,
    output reg [9:0]   reader_y,
    input  wire        reader_ready,
    input  wire        reader_valid,
    input  wire [23:0] reader_rgb,
    output reg         pixel_valid,
    input  wire        pixel_ready,
    output reg [23:0]  pixel_rgb,
    output reg         pixel_last
);
    localparam [2:0] ST_IDLE=3'd0,ST_REQ=3'd1,ST_WAIT=3'd2,ST_HOLD=3'd3;
    reg [2:0] state;
    reg [5:0] sx,sy;
    reg [10:0] x0_q,xspan_q;
    reg [9:0] y0_q,yspan_q;
    reg [17:0] xprod,yprod;

    always @* begin
        xprod = sx * xspan_q;
        yprod = sy * yspan_q;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;busy<=0;done<=0;reader_request<=0;
            reader_x<=0;reader_y<=0;sx<=0;sy<=0;x0_q<=0;xspan_q<=0;
            y0_q<=0;yspan_q<=0;pixel_valid<=0;pixel_rgb<=0;pixel_last<=0;
        end else begin
            done<=0;reader_request<=0;
            case(state)
                ST_IDLE: begin
                    busy<=0;pixel_valid<=0;pixel_last<=0;
                    if(start) begin
                        busy<=1;sx<=0;sy<=0;x0_q<=roi_x0;y0_q<=roi_y0;
                        xspan_q <= (roi_x1>roi_x0) ? roi_x1-roi_x0 : 11'd1;
                        yspan_q <= (roi_y1>roi_y0) ? roi_y1-roi_y0 : 10'd1;
                        state<=ST_REQ;
                    end
                end
                ST_REQ: begin
                    reader_x<=x0_q + xprod/64;
                    reader_y<=y0_q + yprod/64;
                    if(reader_ready) begin reader_request<=1;state<=ST_WAIT;end
                end
                ST_WAIT: begin
                    if(reader_valid) begin
                        pixel_rgb<=reader_rgb;pixel_valid<=1;
                        pixel_last<=(sx==63 && sy==63);state<=ST_HOLD;
                    end
                end
                ST_HOLD: if(pixel_ready) begin
                    pixel_valid<=0;pixel_last<=0;
                    if(sx==63) begin
                        sx<=0;
                        if(sy==63) begin busy<=0;done<=1;state<=ST_IDLE;end
                        else begin sy<=sy+1'b1;state<=ST_REQ;end
                    end else begin sx<=sx+1'b1;state<=ST_REQ;end
                end
                default: state<=ST_IDLE;
            endcase
        end
    end
endmodule
