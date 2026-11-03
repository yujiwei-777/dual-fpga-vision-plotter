// Third-board Tiny-YOLO endpoint.
//
// This board is intentionally independent from the Ethernet/DDR secondary A
// design.  A sends one framed 64x64 RGB image over the J1 SPI pins; this top
// stores the payload in BRAM, runs the resource-bounded 64x64 detector, and
// returns a compact result frame on the following SPI transaction.
//
// B->A response frame (mode 0, MSB first):
//   A5 5A | 80-byte type18 payload | CRC32(payload) | A5 5A
// The payload is job_id, inference_us, config_version, flags, box_count,
// reserved and four 16-byte boxes.  Each box is x0,y0,x1,y1,class_id
// (little-endian u16), confidence, reserved, area (little-endian u32).  The
// response is 88 bytes total.  A keeps CS_N
// asserted while reading the response; a later frame transaction replaces it.
module secondary_top_b(
    input  wire       I_sys_clk,
    input  wire       I_spi_sclk,
    input  wire       I_spi_mosi,
    input  wire       I_spi_cs_n,
    input  wire       I_spi_frame_valid,
    output wire       O_spi_miso,
    output wire       O_spi_ready,
    output wire [3:0] O_led
);
    localparam integer FRAME_BYTES = 12288;
    localparam integer PIXELS = 4096;

    reg rst_n = 1'b0;
    reg [15:0] por_count = 16'd0;
    always @(posedge I_sys_clk) begin
        if (!por_count[15]) por_count <= por_count + 1'b1;
        rst_n <= por_count[15];
    end

    // Input framing lives in the external SPI clock domain.  The payload
    // memory is written there and read after a synchronized completion toggle.
    wire [7:0] spi_byte;
    wire spi_byte_valid,spi_frame_active,spi_frame_start,spi_frame_end;
    aux_spi_frame_slave u_slave(
        .rst_n(rst_n),.spi_sclk(I_spi_sclk),.spi_cs_n(I_spi_cs_n),.spi_mosi(I_spi_mosi),
        .byte_data(spi_byte),.byte_valid(spi_byte_valid),.frame_active(spi_frame_active),
        .frame_start(spi_frame_start),.frame_end(spi_frame_end));
    wire payload_valid,frame_valid,frame_error;
    wire [7:0] payload_data,purpose;
    wire [31:0] input_job_id;
    aux_spi_frame_parser u_parser(
        .clk(I_spi_sclk),.rst_n(rst_n),.byte_valid(spi_byte_valid),.byte_data(spi_byte),
        .payload_valid(payload_valid),.payload_data(payload_data),.frame_valid(frame_valid),
        .frame_error(frame_error),.job_id(input_job_id),.purpose(purpose));

    reg [7:0] frame_mem [0:FRAME_BYTES-1];
    reg [13:0] payload_wr_addr;
    reg frame_toggle_spi;
    reg [31:0] frame_job_spi;
    reg frame_error_spi;
    always @(posedge I_spi_sclk or negedge rst_n) begin
        if (!rst_n) begin
            payload_wr_addr<=0; frame_toggle_spi<=0; frame_job_spi<=0; frame_error_spi<=0;
        end else begin
            if (payload_valid) begin
                if (payload_wr_addr < FRAME_BYTES) frame_mem[payload_wr_addr] <= payload_data;
                payload_wr_addr <= payload_wr_addr + 1'b1;
            end
            if (spi_frame_start) begin payload_wr_addr<=0; frame_error_spi<=0; end
            if (frame_error) frame_error_spi<=1'b1;
            if (frame_valid && !frame_error_spi) begin
                frame_toggle_spi<=~frame_toggle_spi; frame_job_spi<=input_job_id;
            end
        end
    end

    reg frame_toggle_meta,frame_toggle_sync,frame_toggle_seen;
    reg [31:0] pending_job;
    reg result_done_meta,result_done_sync,result_done_seen;
    reg [1:0] feed_state;
    localparam [1:0] FEED_IDLE=2'd0,FEED_PIXELS=2'd1,FEED_WAIT=2'd2;
    reg [11:0] feed_addr;
    reg [13:0] feed_base;
    reg core_pixel_we,core_start;
    wire [23:0] core_pixel_rgb = {frame_mem[feed_base],frame_mem[feed_base+1'b1],frame_mem[feed_base+2'd2]};
    wire core_busy,core_done;
    wire [2:0] core_det_count;
    wire [43:0] core_det_x0,core_det_x1;
    wire [39:0] core_det_y0,core_det_y1;
    wire [15:0] core_det_class;
    wire [31:0] core_det_conf;

    tiny_yolo_core u_yolo(
        .clk(I_sys_clk),.rst_n(rst_n),.pixel_we(core_pixel_we),.pixel_addr(feed_addr),
        .pixel_rgb(core_pixel_rgb),.start(core_start),.busy(core_busy),.done(core_done),
        .det_count(core_det_count),.det_x0(core_det_x0),.det_y0(core_det_y0),
        .det_x1(core_det_x1),.det_y1(core_det_y1),.det_class(core_det_class),.det_conf(core_det_conf));

    // B->A response storage and CRC.  The response is loaded atomically when
    // the detector finishes; SPI can only observe it on a subsequent CS_N.
    reg [7:0] response_mem [0:87];
    // A SPI-domain shadow removes the sys_clk_50m -> spi_sclk output path.
    // The complete response is copied on the first falling edge after CS_N
    // goes low; the master samples the first bit on the following rising edge.
    reg [7:0] response_spi_mem [0:87];
    reg response_pending;
    reg [9:0] response_bit_index;
    reg response_done_toggle_spi;
    wire [31:0] response_crc;
    integer ci;

    function [10:0] x0_at; input integer s; begin case(s) 0:x0_at=core_det_x0[10:0];1:x0_at=core_det_x0[21:11];2:x0_at=core_det_x0[32:22];default:x0_at=core_det_x0[43:33]; endcase end endfunction
    function [10:0] x1_at; input integer s; begin case(s) 0:x1_at=core_det_x1[10:0];1:x1_at=core_det_x1[21:11];2:x1_at=core_det_x1[32:22];default:x1_at=core_det_x1[43:33]; endcase end endfunction
    function [9:0] y0_at; input integer s; begin case(s) 0:y0_at=core_det_y0[9:0];1:y0_at=core_det_y0[19:10];2:y0_at=core_det_y0[29:20];default:y0_at=core_det_y0[39:30]; endcase end endfunction
    function [9:0] y1_at; input integer s; begin case(s) 0:y1_at=core_det_y1[9:0];1:y1_at=core_det_y1[19:10];2:y1_at=core_det_y1[29:20];default:y1_at=core_det_y1[39:30]; endcase end endfunction
    function [3:0] cls_at; input integer s; begin case(s) 0:cls_at=core_det_class[3:0];1:cls_at=core_det_class[7:4];2:cls_at=core_det_class[11:8];default:cls_at=core_det_class[15:12]; endcase end endfunction
    function [7:0] conf_at; input integer s; begin case(s) 0:conf_at=core_det_conf[7:0];1:conf_at=core_det_conf[15:8];2:conf_at=core_det_conf[23:16];default:conf_at=core_det_conf[31:24]; endcase end endfunction
    function [31:0] area_at; input integer s; reg [10:0] dx; reg [9:0] dy; begin dx=x1_at(s)-x0_at(s);dy=y1_at(s)-y0_at(s);area_at=dx*dy; end endfunction
    function [7:0] box_byte; input integer slot; input integer off; reg [31:0] ar; begin
        ar=area_at(slot);
        case(off)
            0:box_byte=x0_at(slot)[7:0]; 1:box_byte={5'd0,x0_at(slot)[10:8]};
            2:box_byte=y0_at(slot)[7:0]; 3:box_byte={6'd0,y0_at(slot)[9:8]};
            4:box_byte=x1_at(slot)[7:0]; 5:box_byte={5'd0,x1_at(slot)[10:8]};
            6:box_byte=y1_at(slot)[7:0]; 7:box_byte={6'd0,y1_at(slot)[9:8]};
            8:box_byte={4'd0,cls_at(slot)}; 9:box_byte=8'd0;
            10:box_byte=conf_at(slot); 11:box_byte=8'd0;
            12:box_byte=ar[7:0];13:box_byte=ar[15:8];14:box_byte=ar[23:16];default:box_byte=ar[31:24];
        endcase
    end endfunction
    function [31:0] crc_byte; input [31:0] c; input [7:0] d; reg [31:0] t; integer j; begin
        t=c^{24'd0,d}; for(j=0;j<8;j=j+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1); crc_byte=t;
    end endfunction
    function [7:0] response_data; input integer idx; integer slot,off; begin
        if(idx==0)response_data=8'ha5; else if(idx==1)response_data=8'h5a;
        else if(idx>=2&&idx<=5)response_data=pending_job[(idx-2)*8 +: 8];
        else if(idx>=6&&idx<=9)response_data=8'd0; // inference_us
        else if(idx>=10&&idx<=13)response_data=8'd0; // config_version
        else if(idx==14)response_data=(core_det_count!=0)?8'h03:8'h80;
        else if(idx==15)response_data=core_det_count;
        else if(idx==16||idx==17)response_data=8'd0;
        else if(idx>=18&&idx<82)begin slot=(idx-18)/16;off=(idx-18)%16;response_data=box_byte(slot,off);end
        else response_data=8'd0;
    end endfunction
    reg [31:0] crc_work;
    always @* begin
        crc_work=32'hffffffff;
        for(ci=2;ci<82;ci=ci+1)crc_work=crc_byte(crc_work,response_data(ci));
    end
    assign response_crc=~crc_work;

    integer ri,rs,ro;
    always @(posedge I_sys_clk or negedge rst_n) begin
        if(!rst_n) begin
            frame_toggle_meta<=0;frame_toggle_sync<=0;frame_toggle_seen<=0;pending_job<=0;
            feed_state<=FEED_IDLE;feed_addr<=0;feed_base<=0;core_pixel_we<=0;core_start<=0;response_pending<=0;
            result_done_meta<=0;result_done_sync<=0;result_done_seen<=0;
            for(ri=0;ri<88;ri=ri+1) response_mem[ri]<=0;
        end else begin
            frame_toggle_meta<=frame_toggle_spi;frame_toggle_sync<=frame_toggle_meta;
            result_done_meta<=response_done_toggle_spi;result_done_sync<=result_done_meta;
            core_pixel_we<=0;core_start<=0;
            if(result_done_sync!=result_done_seen)begin
                result_done_seen<=result_done_sync;
                response_pending<=1'b0;
            end
            if(frame_toggle_sync!=frame_toggle_seen && feed_state==FEED_IDLE && !response_pending)begin
                frame_toggle_seen<=frame_toggle_sync;pending_job<=frame_job_spi;feed_addr<=0;feed_base<=0;feed_state<=FEED_PIXELS;
            end
            if(feed_state==FEED_PIXELS)begin
                core_pixel_we<=1'b1;
                if(feed_addr==PIXELS-1)begin feed_state<=FEED_WAIT; core_start<=1'b1; end
                else begin feed_addr<=feed_addr+1'b1;feed_base<=feed_base+3'd3;end
            end else if(feed_state==FEED_WAIT && core_done)begin
                feed_state<=FEED_IDLE;response_pending<=1'b1;
                for(ri=0;ri<82;ri=ri+1) response_mem[ri]<=response_data(ri);
                response_mem[82]<=response_crc[7:0];response_mem[83]<=response_crc[15:8];response_mem[84]<=response_crc[23:16];response_mem[85]<=response_crc[31:24];
                response_mem[86]<=8'h5a;response_mem[87]<=8'ha5;
            end
        end
    end

    // Mode-0 response shifter.  Data is combinationally presented before the
    // master's rising edge and the bit index advances on each falling edge.
    integer spi_copy_i;
    always @(negedge I_spi_sclk or posedge I_spi_cs_n or negedge rst_n) begin
        if(!rst_n)begin response_bit_index<=0;response_done_toggle_spi<=0;end
        else if(I_spi_cs_n)begin
            if(response_bit_index>=10'd703) response_done_toggle_spi<=~response_done_toggle_spi;
            response_bit_index<=0;
        end else begin
            if(response_bit_index==0 && response_pending)
                for(spi_copy_i=0;spi_copy_i<88;spi_copy_i=spi_copy_i+1)
                    response_spi_mem[spi_copy_i]<=response_mem[spi_copy_i];
            if(response_pending && response_bit_index<10'd704)
                response_bit_index<=response_bit_index+1'b1;
        end
    end
    assign O_spi_miso = (!I_spi_cs_n && response_pending && response_bit_index<10'd704) ?
                        response_spi_mem[response_bit_index[9:3]][7-response_bit_index[2:0]] : 1'b0;

    reg [25:0] heartbeat;
    always @(posedge I_sys_clk or negedge rst_n)begin
        if(!rst_n)heartbeat<=0; else heartbeat<=heartbeat+1'b1;
    end
    assign O_spi_ready = !(feed_state!=FEED_IDLE || core_busy);
    assign O_led[0]=heartbeat[25];
    assign O_led[1]=spi_frame_active;
    assign O_led[2]=core_busy||feed_state!=FEED_IDLE;
    assign O_led[3]=response_pending;
endmodule
