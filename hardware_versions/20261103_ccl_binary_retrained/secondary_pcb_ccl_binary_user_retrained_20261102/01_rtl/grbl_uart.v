// Single-clock UART PHY. 115200 8N1, idle high, LSB first.
module grbl_uart_tx #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire I_clk, input wire I_rst_n,
    input wire [7:0] I_data, input wire I_valid,
    output wire O_ready, output reg O_tx,
    output reg O_done
);
    localparam integer DIV=(CLK_HZ+BAUD/2)/BAUD;
    reg [31:0] divider;
    reg [3:0] bits_left;
    reg [8:0] shift;
    assign O_ready=(bits_left==0);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            divider<=0; bits_left<=0; shift<=9'h1ff; O_tx<=1; O_done<=0;
        end else begin
            O_done<=0;
            if(bits_left==0) begin
                O_tx<=1;
                if(I_valid) begin
                    O_tx<=0;
                    shift<={1'b1,I_data};
                    bits_left<=10;
                    divider<=DIV-1;
                end
            end else if(divider==0) begin
                divider<=DIV-1;
                if(bits_left==1) begin
                    bits_left<=0; O_tx<=1; O_done<=1;
                end else begin
                    O_tx<=shift[0]; shift<={1'b1,shift[8:1]}; bits_left<=bits_left-1'b1;
                end
            end else divider<=divider-1'b1;
        end
    end
endmodule

// Board-facing byte bridge.  The legacy LINK_READY pin remains in the port
// list for pin/project compatibility, but UART-only operation deliberately
// ignores it.  After reset the bridge probes GRBL with '?' every 200 ms and
// exposes link-ready only after a complete <Idle|...> status line is parsed.
module grbl_uart_port #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200,
    // Production default is 200 ms; the parameter also permits a short
    // interval in the self-checking UART simulation without changing RTL.
    parameter integer PROBE_INTERVAL_CYCLES=(CLK_HZ/5)
)(
    input wire I_clk,input wire I_rst_n,
    input wire I_uart_rx,output wire O_uart_tx,input wire I_esp_link_ready,
    output wire O_link_ready,
    input wire [7:0] I_tx_data,input wire I_tx_valid,
    output wire O_tx_ready,output wire O_tx_done,
    output wire [7:0] O_rx_data,output wire O_rx_valid,output wire O_rx_error,
    // Optional byte-boundary realtime channel. Legacy named-port callers
    // leave I_rt_valid unconnected; Z/X must never request a realtime byte.
    input wire [7:0] I_rt_data,input wire I_rt_valid,output wire O_rt_ready,
    output wire O_idle_pulse,output wire O_rt_done
);
    wire tx_ready;
    wire tx_done;
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_error;
    wire parser_ok,parser_error,parser_alarm,parser_status,parser_idle,parser_overflow;
    reg parser_clear;
    reg guard_ready;
    reg probe_pending;
    reg probe_inflight;
    reg rt_inflight;
    reg [31:0] probe_timer;
    // Retained solely for the known-good CDC/SDC path.  The value is not
    // used to qualify the UART link in this build.
    (* keep = "true", dont_touch = "true" *) reg link_meta;
    wire tx_probe_valid = probe_pending && !guard_ready;
    wire tx_normal_valid = I_tx_valid && guard_ready;
    wire tx_rt_valid = (I_rt_valid === 1'b1);
    wire tx_mux_valid = tx_rt_valid || tx_probe_valid || tx_normal_valid;
    wire [7:0] tx_mux_data = tx_rt_valid ? I_rt_data :
                                   (tx_probe_valid ? 8'h3f : I_tx_data);

    // I_esp_link_ready is intentionally unused for link qualification. Keep
    // the named signal in the interface so the known-good top level, E12 pin
    // assignment, and its first-stage timing exception stay unchanged.
    assign O_link_ready = guard_ready;
    assign O_tx_ready = tx_ready && guard_ready && !rx_error && !tx_rt_valid;
    assign O_rt_ready = tx_ready;
    assign O_tx_done = tx_done;
    assign O_rx_data = rx_data;
    assign O_rx_valid = rx_valid;
    assign O_rx_error = rx_error;
    assign O_idle_pulse = parser_idle;
    assign O_rt_done = tx_done && rt_inflight;

    grbl_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_tx(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_data(tx_mux_data),.I_valid(tx_mux_valid),
        .O_ready(tx_ready),.O_tx(O_uart_tx),.O_done(tx_done));
    grbl_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_rx(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_rx(I_uart_rx),.O_data(rx_data),
        .O_valid(rx_valid),.O_error(rx_error));
    grbl_response_parser u_parser(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(parser_clear),
        .I_data(rx_data),.I_valid(rx_valid),.O_ok(parser_ok),
        .O_error(parser_error),.O_alarm(parser_alarm),.O_status(parser_status),
        .O_idle(parser_idle),.O_overflow(parser_overflow),.O_reset());

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            parser_clear<=1'b1;
            link_meta<=1'b0;
            guard_ready<=1'b0;
            probe_pending<=1'b0;
            probe_inflight<=1'b0;
            rt_inflight<=1'b0;
            probe_timer<=32'd0;
        end else begin
            parser_clear<=1'b0;
            link_meta<=I_esp_link_ready;
            if(tx_rt_valid && tx_ready)rt_inflight<=1'b1;
            else if(tx_done && rt_inflight)rt_inflight<=1'b0;

            // A complete GRBL Idle response is the only event that opens the
            // normal streamer gate.  A framing error closes it again and
            // restarts the probe sequence from a clean parser boundary.
            if(rx_error) begin
                guard_ready<=1'b0;
                probe_pending<=1'b0;
                probe_inflight<=1'b0;
                probe_timer<=32'd0;
                parser_clear<=1'b1;
            end else if(!guard_ready) begin
                if(parser_idle) begin
                    guard_ready<=1'b1;
                    probe_pending<=1'b0;
                    probe_inflight<=1'b0;
                    probe_timer<=32'd0;
                end else if(probe_pending) begin
                    // Hold the request until the shared UART transmitter is
                    // idle; this makes the '?' byte lossless under any baud.
                    if(tx_ready && !tx_rt_valid) begin
                        probe_pending<=1'b0;
                        probe_inflight<=1'b1;
                    end
                end else if(probe_inflight) begin
                    if(tx_done) begin
                        probe_inflight<=1'b0;
                        probe_timer<=32'd0;
                    end
                end else if(probe_timer >= PROBE_INTERVAL_CYCLES-1) begin
                    probe_pending<=1'b1;
                end else begin
                    probe_timer<=probe_timer+1'b1;
                end
            end else begin
                // Normal G-code traffic is owned by grbl_streamer.  No
                // periodic probe is generated after the first valid Idle.
                probe_pending<=1'b0;
                probe_inflight<=1'b0;
                probe_timer<=32'd0;
            end
        end
    end
endmodule

module grbl_uart_rx #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire I_clk, input wire I_rst_n, input wire I_rx,
    output reg [7:0] O_data, output reg O_valid, output reg O_error
);
    localparam integer DIV=(CLK_HZ+BAUD/2)/BAUD;
    localparam [1:0] IDLE=0,START=1,DATA=2,STOP=3;
    reg rx_meta,rx_sync;
    reg [1:0] state;
    reg [31:0] divider;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin rx_meta<=1;rx_sync<=1;end
        else begin rx_meta<=I_rx;rx_sync<=rx_meta;end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;divider<=0;bit_index<=0;shift<=0;O_data<=0;O_valid<=0;O_error<=0;
        end else begin
            O_valid<=0;O_error<=0;
            case(state)
                IDLE:if(!rx_sync) begin state<=START;divider<=DIV/2-1;end
                START:if(divider!=0) divider<=divider-1'b1;
                      else if(rx_sync) state<=IDLE;
                      else begin state<=DATA;divider<=DIV-1;bit_index<=0;end
                DATA:if(divider!=0)divider<=divider-1'b1;
                     else begin
                         shift[bit_index]<=rx_sync;divider<=DIV-1;
                         if(bit_index==7)state<=STOP;
                         else bit_index<=bit_index+1'b1;
                     end
                STOP:if(divider!=0)divider<=divider-1'b1;
                     else begin
                         if(rx_sync) begin O_data<=shift;O_valid<=1;end
                         else O_error<=1;
                         state<=IDLE;
                     end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
