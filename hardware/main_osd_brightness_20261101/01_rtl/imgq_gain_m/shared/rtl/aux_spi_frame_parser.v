// Parser for aux_spi_frame_tx. Input and outputs are in the SPI byte clock
// domain. Payload bytes are released only after the fixed header is accepted.
module aux_spi_frame_parser(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       byte_valid,
    input  wire [7:0] byte_data,
    output reg        payload_valid,
    output reg  [7:0] payload_data,
    output reg        frame_valid,
    output reg        frame_error,
    output reg [31:0] job_id,
    output reg  [7:0] purpose
);
    localparam ST_SYNC2=0,ST_HEADER=1,ST_PAYLOAD=2,ST_CRC=3,ST_TRAILER=4;
    reg [2:0] state;
    reg [3:0] header_at;
    reg [1:0] crc_at,trailer_at;
    reg [15:0] payload_count,payload_length;
    reg [31:0] crc,rx_crc;
    reg [7:0] width_q,height_q;
    reg bad_frame;

    function [31:0] crc_byte;
        input [31:0] c; input [7:0] d; reg [31:0] t; integer i;
        begin t=c^{24'd0,d};for(i=0;i<8;i=i+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);crc_byte=t;end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_SYNC2;header_at<=0;crc_at<=0;trailer_at<=0;
            payload_count<=0;payload_length<=0;crc<=32'hffffffff;rx_crc<=0;
            width_q<=0;height_q<=0;job_id<=0;purpose<=0;
            bad_frame<=0;
            payload_valid<=0;payload_data<=0;frame_valid<=0;frame_error<=0;
        end else begin
            payload_valid<=0;frame_valid<=0;frame_error<=0;
            if(byte_valid) begin
                case(state)
                    ST_SYNC2: begin
                        if(byte_data==8'ha5) begin state<=ST_HEADER;bad_frame<=0;end
                        else if(byte_data!=8'h5a) begin frame_error<=1'b1;bad_frame<=1'b1;end
                        header_at<=0;
                    end
                    ST_HEADER: begin
                        case(header_at)
                            0: if(byte_data!=8'h5a) begin frame_error<=1'b1;bad_frame<=1'b1;end
                            1: if(byte_data!=8'd1) begin frame_error<=1'b1;bad_frame<=1'b1;end
                            2: job_id[7:0]<=byte_data;
                            3: job_id[15:8]<=byte_data;
                            4: job_id[23:16]<=byte_data;
                            5: job_id[31:24]<=byte_data;
                            6: purpose<=byte_data;
                            7: width_q<=byte_data;
                            8: height_q<=byte_data;
                            9: payload_length[7:0]<=byte_data;
                            10: payload_length[15:8]<=byte_data;
                            default:;
                        endcase
                        if(header_at==10) begin
                            // payload_length[15:8] is being captured on this
                            // clock; include the current byte in the check
                            // rather than comparing the previous register
                            // value (which made every 12,288-byte frame fail
                            // validation).
                            if(width_q!=64 || height_q!=64 ||
                               {byte_data,payload_length[7:0]}!=16'd12288) begin frame_error<=1'b1;bad_frame<=1'b1;end
                            payload_count<=0;crc<=32'hffffffff;state<=ST_PAYLOAD;
                        end else header_at<=header_at+1'b1;
                    end
                    ST_PAYLOAD: begin
                        payload_data<=byte_data;payload_valid<=1'b1;
                        crc<=crc_byte(crc,byte_data);payload_count<=payload_count+1'b1;
                        if(payload_count==payload_length-1) begin crc_at<=0;state<=ST_CRC;end
                    end
                    ST_CRC: begin
                        case(crc_at)
                            0:rx_crc[7:0]<=byte_data;
                            1:rx_crc[15:8]<=byte_data;
                            2:rx_crc[23:16]<=byte_data;
                            default:begin
                                rx_crc[31:24]<=byte_data;
                                if({byte_data,rx_crc[23:0]}!=~crc) begin frame_error<=1'b1;bad_frame<=1'b1;end
                                trailer_at<=0;state<=ST_TRAILER;
                            end
                        endcase
                        if(crc_at!=3)crc_at<=crc_at+1'b1;
                    end
                    ST_TRAILER: begin
                        if((trailer_at==0 && byte_data!=8'h5a) ||
                           (trailer_at==1 && byte_data!=8'ha5)) begin frame_error<=1'b1;bad_frame<=1'b1;end
                        if(trailer_at==1) begin
                            if(!bad_frame && byte_data==8'ha5) frame_valid<=1'b1;
                            state<=ST_SYNC2;
                        end else trailer_at<=1'b1;
                    end
                    default:state<=ST_SYNC2;
                endcase
            end
        end
    end
endmodule
