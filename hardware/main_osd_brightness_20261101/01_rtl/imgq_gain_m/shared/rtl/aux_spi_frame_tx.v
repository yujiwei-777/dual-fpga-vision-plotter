// 64x64 RGB frame formatter for aux_spi_frame_master.
// Frame format (little-endian fields):
//   A5 5A | version | job_id[31:0] | purpose | width | height |
//   payload_len[15:0] | RGB payload | CRC32(payload) | 5A A5
module aux_spi_frame_tx #(
    parameter integer SPI_CLK_DIV = 3,
    parameter [7:0] PROTOCOL_VERSION = 8'd1,
    parameter [15:0] PAYLOAD_LENGTH = 16'd12288
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [31:0] job_id,
    input  wire [7:0] purpose,
    input  wire [7:0] payload_data,
    input  wire       payload_valid,
    input  wire       payload_last,
    output wire       payload_ready,
    output reg        busy,
    output reg        done,
    output reg        frame_error,
    output wire       spi_sclk,
    output wire       spi_cs_n,
    output wire       spi_mosi,
    input  wire       spi_miso
);
    localparam [2:0] ST_IDLE=3'd0, ST_HEADER=3'd1, ST_PAYLOAD=3'd2,
                     ST_CRC=3'd3, ST_TRAILER=3'd4, ST_WAIT=3'd5;
    reg [2:0] state;
    reg [3:0] header_at;
    reg [1:0] crc_at;
    reg       trailer_at;
    reg [31:0] job_q;
    reg [7:0] purpose_q;
    reg [15:0] payload_count;
    reg [31:0] crc;
    reg master_start;
    wire master_busy,master_done,master_tx_ready,master_rx_valid;
    wire [7:0] master_rx_data;
    reg [7:0] tx_data;
    reg tx_valid,tx_last;
    wire tx_accept=tx_valid&&master_tx_ready;

    function [31:0] crc_byte;
        input [31:0] c;
        input [7:0] d;
        reg [31:0] t;
        integer i;
        begin
            t=c^{24'd0,d};
            for(i=0;i<8;i=i+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);
            crc_byte=t;
        end
    endfunction

    function [7:0] header_byte;
        input [3:0] a;
        begin
            case(a)
                0:header_byte=8'ha5; 1:header_byte=8'h5a;
                2:header_byte=PROTOCOL_VERSION;
                3:header_byte=job_q[7:0]; 4:header_byte=job_q[15:8];
                5:header_byte=job_q[23:16]; 6:header_byte=job_q[31:24];
                7:header_byte=purpose_q;
                8:header_byte=8'd64; 9:header_byte=8'd64;
                10:header_byte=PAYLOAD_LENGTH[7:0];
                11:header_byte=PAYLOAD_LENGTH[15:8];
                default:header_byte=8'd0;
            endcase
        end
    endfunction

    always @* begin
        tx_data=8'd0; tx_valid=1'b0; tx_last=1'b0;
        case(state)
            ST_HEADER: begin tx_data=header_byte(header_at);tx_valid=1'b1; end
            ST_PAYLOAD: begin tx_data=payload_data;tx_valid=payload_valid; end
            ST_CRC: begin
                tx_valid=1'b1;
                case(crc_at)
                    0:tx_data=~crc[7:0]; 1:tx_data=~crc[15:8];
                    2:tx_data=~crc[23:16]; default:tx_data=~crc[31:24];
                endcase
            end
            ST_TRAILER: begin
                tx_valid=1'b1;tx_data=trailer_at?8'ha5:8'h5a;
                tx_last=trailer_at;
            end
            default:;
        endcase
    end

    assign payload_ready=(state==ST_PAYLOAD)&&master_tx_ready;

    aux_spi_frame_master #(.CLK_DIV(SPI_CLK_DIV)) u_master(
        .clk(clk),.rst_n(rst_n),.start(master_start),.busy(master_busy),.done(master_done),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_last(tx_last),.tx_ready(master_tx_ready),
        .rx_data(master_rx_data),.rx_valid(master_rx_valid),
        .spi_sclk(spi_sclk),.spi_cs_n(spi_cs_n),.spi_mosi(spi_mosi),.spi_miso(spi_miso));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;header_at<=0;crc_at<=0;trailer_at<=0;
            job_q<=0;purpose_q<=0;payload_count<=0;crc<=32'hffffffff;
            master_start<=0;busy<=0;done<=0;frame_error<=0;
        end else begin
            master_start<=0;done<=0;frame_error<=0;
            case(state)
                ST_IDLE: if(start) begin
                    job_q<=job_id;purpose_q<=purpose;payload_count<=0;
                    crc<=32'hffffffff;header_at<=0;busy<=1;master_start<=1;state<=ST_HEADER;
                end
                ST_HEADER: if(tx_accept) begin
                    if(header_at==11) state<=ST_PAYLOAD;
                    else header_at<=header_at+1'b1;
                end
                ST_PAYLOAD: if(tx_accept) begin
                    crc<=crc_byte(crc,payload_data);
                    payload_count<=payload_count+1'b1;
                    if(payload_last || payload_count==PAYLOAD_LENGTH-1) begin
                        if((payload_last && payload_count!=PAYLOAD_LENGTH-1) ||
                           (!payload_last && payload_count==PAYLOAD_LENGTH-1)) frame_error<=1;
                        crc_at<=0;state<=ST_CRC;
                    end
                end
                ST_CRC: if(tx_accept) begin
                    if(crc_at==3) begin trailer_at<=0;state<=ST_TRAILER;end
                    else crc_at<=crc_at+1'b1;
                end
                ST_TRAILER: if(tx_accept) begin
                    if(trailer_at) state<=ST_WAIT;
                    else trailer_at<=1'b1;
                end
                ST_WAIT: if(master_done) begin busy<=0;done<=1;state<=ST_IDLE;end
                default: state<=ST_IDLE;
            endcase
        end
    end
endmodule
