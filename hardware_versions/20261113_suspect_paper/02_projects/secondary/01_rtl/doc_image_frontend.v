// Experimental document-only frontend, not integrated in a delivered bit.
// Exact 4x4 cells preserve the baseline two-dark-sample decision outside a
// fixed dirt ROI. Inside that ROI only, 16 serial probes estimate background.
// The default ROI applies ONLY to the current 1280x720 SC500 camera position:
// raster x=288..319,y=112..179; camera x=1152..1279,y=448..719.
// Camera movement/readout changes require a new calibration and replay.
// No ROI is forced white: real dark strokes still use the contrast decision.
module doc_image_frontend #(
    parameter integer TIMEOUT_CYCLES = 1250000000,
    parameter integer FRAME_AS_A4_WIDTH = 1,
    parameter integer INK_THRESHOLD = 112,
    parameter integer LOCAL_CONTRAST_DELTA = 12,
    parameter integer FIXED_DIRT_ENABLE = 1,
    parameter integer DIRT_X_MIN = 288,
    parameter integer DIRT_X_MAX = 319,
    parameter integer DIRT_Y_MIN = 112,
    parameter integer DIRT_Y_MAX = 179
)(
    input wire clk, input wire rst_n, input wire start, input wire cancel,
    output reg busy, output reg done, output reg error,
    output reg [7:0] error_code,
    output reg pixel_request, output reg pixel_invalidate,
    output reg [10:0] pixel_x, output reg [9:0] pixel_y,
    input wire pixel_ready, input wire pixel_valid, input wire [7:0] pixel_luma,
    output wire ink_valid, output wire [16:0] ink_addr, output wire ink_bit,
    input wire ink_ready, output reg [127:0] corners
);
    localparam integer GRID_Y0 = FRAME_AS_A4_WIDTH ? 70 : 0;
    localparam integer GRID_Y1 = GRID_Y0 + 179;
    localparam [3:0] ST_IDLE=0, ST_ADDR=1, ST_PIXEL=2,
                     ST_PIXEL_WAIT=3, ST_EMIT=4, ST_FINISH=5, ST_DECIDE=6;
    reg [3:0] state;
    reg [30:0] timer;
    reg [8:0] out_x, out_y;
    reg [16:0] out_addr;
    reg [10:0] src_x;
    reg [9:0] src_y;
    reg [5:0] sample_index;
    reg [7:0] first_min, second_min;
    reg [11:0] background_sum;
    reg output_bit;
    reg [10:0] sample_x_q;
    reg [9:0] sample_y_q;
    wire active = (out_y >= GRID_Y0) && (out_y <= GRID_Y1);
    wire compensation_active = FIXED_DIRT_ENABLE && active &&
        (out_x >= DIRT_X_MIN) && (out_x <= DIRT_X_MAX) &&
        (out_y >= GRID_Y0+DIRT_Y_MIN) && (out_y <= GRID_Y0+DIRT_Y_MAX);

    function signed [5:0] probe_offset;
        input [1:0] index;
        begin
            case(index)
                2'd0: probe_offset=-6'sd10;
                2'd1: probe_offset=-6'sd2;
                2'd2: probe_offset=6'sd6;
                default: probe_offset=6'sd14;
            endcase
        end
    endfunction
    wire signed [12:0] sample_x_raw = $signed({2'b00,src_x}) +
        (sample_index[4] ? probe_offset(sample_index[1:0]) :
        $signed({4'b0000,sample_index[1:0]}));
    wire signed [11:0] sample_y_raw = $signed({2'b00,src_y}) +
        (sample_index[4] ? probe_offset(sample_index[3:2]) :
        $signed({4'b0000,sample_index[3:2]}));
    wire [10:0] sample_x = (sample_x_raw < 0) ? 11'd0 :
        (sample_x_raw > 1279) ? 11'd1279 : sample_x_raw[10:0];
    wire [9:0] sample_y = (sample_y_raw < 0) ? 10'd0 :
        (sample_y_raw > 719) ? 10'd719 : sample_y_raw[9:0];
    // Only registered samples feed this decision. In particular, sample 15
    // must update second_min before the outside-ROI branch evaluates it.
    wire [11:0] background_rounded = background_sum + 12'd8;
    wire [8:0] background_mean = {1'b0,background_rounded[11:4]};
    wire [8:0] contrast_required = {1'b0,second_min} + LOCAL_CONTRAST_DELTA;

    assign ink_valid = (state == ST_EMIT);
    assign ink_addr = out_addr;
    assign ink_bit = output_bit;
    always @* begin
        pixel_request=1'b0; pixel_x=11'd0; pixel_y=10'd0;
        if (state == ST_PIXEL) begin
            pixel_request=active; pixel_x=sample_x_q; pixel_y=sample_y_q;
        end else if (state == ST_PIXEL_WAIT) begin
            pixel_x=sample_x_q; pixel_y=sample_y_q;
        end
    end
    task automatic fail;
        input [7:0] code;
        begin error<=1'b1; error_code<=code; state<=ST_FINISH; end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=ST_IDLE; busy<=0; done<=0; error<=0; error_code<=0;
            timer<=0; out_x<=0; out_y<=0; out_addr<=0; src_x<=0; src_y<=0;
            sample_index<=0; first_min<=255; second_min<=255;
            background_sum<=0; output_bit<=0; sample_x_q<=0; sample_y_q<=0;
            pixel_invalidate<=0; corners<=0;
        end else begin
            done<=0; pixel_invalidate<=0;
            if (cancel) begin
                state<=ST_IDLE; busy<=0; error<=0; error_code<=0;
            end else if (busy && state!=ST_FINISH && timer>=TIMEOUT_CYCLES-1) begin
                fail(8'h01);
            end else begin
                if (busy) timer<=timer+1'b1;
                case(state)
                    ST_IDLE: if(start) begin
                        busy<=1; error<=0; error_code<=0; timer<=0;
                        out_x<=0; out_y<=0; out_addr<=0; src_x<=0; src_y<=0;
                        sample_index<=0; first_min<=255; second_min<=255;
                        background_sum<=0; output_bit<=0;
                        sample_x_q<=0; sample_y_q<=0; pixel_invalidate<=1;
                        corners<={{16'd719},{16'd0},{16'd719},{16'd1279},
                                  {16'd0},{16'd1279},{16'd0},{16'd0}};
                        state<=ST_ADDR;
                    end
                    ST_ADDR: begin
                        sample_x_q<=sample_x; sample_y_q<=sample_y;
                        state<=ST_PIXEL;
                    end
                    ST_PIXEL: begin
                        if(!active) begin output_bit<=0; state<=ST_EMIT; end
                        else if(pixel_ready) state<=ST_PIXEL_WAIT;
                    end
                    ST_PIXEL_WAIT: if(pixel_valid) begin
                        if(!sample_index[4]) begin
                            // Equal minima are separate source pixels and count twice.
                            if(pixel_luma<=first_min) begin
                                second_min<=first_min; first_min<=pixel_luma;
                            end else if(pixel_luma<second_min) second_min<=pixel_luma;
                        end else background_sum<=background_sum+{4'd0,pixel_luma};
                        if(sample_index==6'd31 ||
                            (sample_index==6'd15 && !compensation_active)) begin
                            state<=ST_DECIDE;
                        end else begin sample_index<=sample_index+1'b1; state<=ST_ADDR; end
                    end
                    ST_DECIDE: begin
                        output_bit <= (second_min<=INK_THRESHOLD) &&
                            (!compensation_active || (contrast_required<=background_mean));
                        state<=ST_EMIT;
                    end
                    ST_EMIT: if(ink_ready) begin
                        if(out_addr==17'd102399) state<=ST_FINISH;
                        else begin
                            out_addr<=out_addr+1'b1; sample_index<=0;
                            first_min<=255; second_min<=255; background_sum<=0;
                            if(out_x==319) begin
                                out_x<=0; out_y<=out_y+1'b1; src_x<=0;
                                if(out_y+1'b1==GRID_Y0) src_y<=0;
                                else if(out_y>=GRID_Y0 && out_y<GRID_Y1) src_y<=src_y+4;
                            end else begin out_x<=out_x+1'b1; src_x<=src_x+4; end
                            state<=ST_ADDR;
                        end
                    end
                    ST_FINISH: begin busy<=0; done<=1; state<=ST_IDLE; end
                    default: begin state<=ST_IDLE; busy<=0; end
                endcase
            end
        end
    end
endmodule
