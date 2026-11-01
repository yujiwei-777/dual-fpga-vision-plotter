// Parser for the secondary-B -> secondary-A result transaction.
//
// Response format (MSB-first SPI bytes):
//   A5 5A | 80-byte type18 payload | CRC32(payload) | 5A A5
// The 80-byte payload is exactly the HXA1 type18 payload, allowing A to pass
// it on without a second packing format:
//   job_id[4], inference_us[4], config_version[4], flags[1], count[1],
//   reserved[2], four 16-byte boxes.
// byte_valid and all outputs use the caller's system clock domain.
module aux_spi_result_parser(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    input  wire        transaction_end,
    output reg         result_valid,
    output reg         frame_error,
    output reg [31:0]  job_id,
    output reg [31:0]  inference_us,
    output reg [31:0]  config_version,
    output reg [7:0]   flags,
    output reg [7:0]   box_count,
    output reg [511:0] boxes
);
    localparam ST_SYNC2=3'd0, ST_PAYLOAD=3'd1, ST_CRC=3'd2,
                 ST_TRAILER=3'd3, ST_DROP=3'd4;
    reg [2:0] state;
    reg [6:0] payload_at;
    reg [1:0] crc_at,trailer_at;
    reg [31:0] crc,rx_crc;
    reg bad_frame;
    reg [7:0] payload_mem [0:79];
    integer i;
    function [31:0] crc_byte;
        input [31:0] c; input [7:0] d;
        reg [31:0] t; integer k;
        begin
            t=c^{24'd0,d};
            for(k=0;k<8;k=k+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);
            crc_byte=t;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_SYNC2;payload_at<=0;crc_at<=0;trailer_at<=0;
            crc<=32'hffffffff;rx_crc<=0;bad_frame<=0;
            result_valid<=0;frame_error<=0;job_id<=0;inference_us<=0;
            config_version<=0;flags<=0;box_count<=0;boxes<=0;
            for(i=0;i<80;i=i+1)payload_mem[i]<=0;
        end else begin
            result_valid<=0;frame_error<=0;
            if(transaction_end && state!=ST_SYNC2) begin
                frame_error<=1;state<=ST_SYNC2;bad_frame<=0;
            end
            if(byte_valid) begin
                case(state)
                    ST_SYNC2: begin
                        if(byte_data==8'ha5) state<=ST_PAYLOAD;
                        else if(byte_data!=8'h5a) begin state<=ST_DROP;frame_error<=1;end
                        payload_at<=0;crc<=32'hffffffff;bad_frame<=0;
                    end
                    ST_PAYLOAD: begin
                        // First sync byte is accepted in ST_SYNC2; the
                        // second one is checked here before payload starts.
                        if(payload_at==0 && byte_data!=8'h5a) begin
                            frame_error<=1;bad_frame<=1;state<=ST_DROP;
                        end else if(payload_at==0) begin
                            payload_at<=1;
                        end else begin
                            payload_mem[payload_at-1'b1]<=byte_data;
                            crc<=crc_byte(crc,byte_data);
                            if(payload_at==80) begin
                                crc_at<=0;rx_crc<=0;state<=ST_CRC;
                            end else payload_at<=payload_at+1'b1;
                        end
                    end
                    ST_CRC: begin
                        case(crc_at)
                            0:rx_crc[7:0]<=byte_data;
                            1:rx_crc[15:8]<=byte_data;
                            2:rx_crc[23:16]<=byte_data;
                            default: begin
                                rx_crc[31:24]<=byte_data;
                                if({byte_data,rx_crc[23:0]}!=~crc) begin frame_error<=1;bad_frame<=1;end
                                trailer_at<=0;state<=ST_TRAILER;
                            end
                        endcase
                        if(crc_at!=3)crc_at<=crc_at+1'b1;
                    end
                    ST_TRAILER: begin
                        if((trailer_at==0 && byte_data!=8'h5a) ||
                           (trailer_at==1 && byte_data!=8'ha5)) begin
                            frame_error<=1;bad_frame<=1;
                        end
                        if(trailer_at==1) begin
                            if(!bad_frame && byte_data==8'ha5) begin
                                job_id<={payload_mem[3],payload_mem[2],payload_mem[1],payload_mem[0]};
                                inference_us<={payload_mem[7],payload_mem[6],payload_mem[5],payload_mem[4]};
                                config_version<={payload_mem[11],payload_mem[10],payload_mem[9],payload_mem[8]};
                                flags<=payload_mem[12];box_count<=payload_mem[13];
                                for(i=0;i<64;i=i+1)boxes[i*8 +: 8]<=payload_mem[16+i];
                                result_valid<=1;
                            end
                            state<=ST_SYNC2;
                        end else trailer_at<=1;
                    end
                    default: begin
                        if(byte_data==8'ha5) begin state<=ST_PAYLOAD;payload_at<=0;bad_frame<=0;end
                    end
                endcase
            end
        end
    end
endmodule
