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
// ignores it. Reset first establishes a clean controller command epoch using
// hold, fresh stopped status, Ctrl-X and a fresh post-reset Idle. An Idle alone
// cannot clear a runtime framing error or prove a stale G-code prefix absent.
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
    wire tx_ready,tx_done;
    wire [7:0] rx_data;
    wire rx_valid,rx_error;
    wire parser_ok,parser_error,parser_alarm,parser_status,parser_idle,parser_overflow,parser_hold0,parser_reset;
    reg parser_clear,guard_ready,rt_inflight;
    reg [31:0] probe_timer;
    // Preserve the released asynchronous-pin timing endpoint.
    (* keep = "true", dont_touch = "true" *) reg link_meta;
    localparam [3:0] U_HOLD=0,U_HOLD_WAIT=1,U_QUERY=2,U_QUERY_WAIT=3,
        U_STATUS=4,U_RESET=5,U_RESET_WAIT=6,U_READY=7,U_LOCK=8,
        U_EXT_RESET_WAIT=9,U_EXT_QUERY=10,U_EXT_QUERY_WAIT=11,U_EXT_STATUS=12;
    localparam integer GUARD_SEND_CYCLES=(CLK_HZ/10<1)?1:CLK_HZ/10;
    localparam integer GUARD_STATUS_CYCLES=CLK_HZ*2;
    localparam integer POLL_W=(PROBE_INTERVAL_CYCLES<2)?1:$clog2(PROBE_INTERVAL_CYCLES);
    reg [3:0] guard_state;
    reg bootstrap_mask,post_reset;
    reg [1:0] status_head;
    reg status_alarm_line;
    wire bootstrap_active=(guard_state<=U_RESET_WAIT);
    wire internal_valid=(guard_state==U_HOLD||guard_state==U_QUERY||guard_state==U_RESET);
    wire [7:0] internal_data=(guard_state==U_HOLD)?8'h21:(guard_state==U_RESET)?8'h18:8'h3f;
    wire external_rt=(I_rt_valid===1'b1)&&!bootstrap_active;
    wire normal_valid=I_tx_valid&&guard_ready&&!external_rt;
    wire tx_mux_valid=internal_valid||external_rt||normal_valid;
    wire [7:0] tx_mux_data=internal_valid?internal_data:external_rt?I_rt_data:I_tx_data;
    wire poll_due=&probe_timer[POLL_W-1:0];
    assign O_link_ready=guard_ready;
    assign O_tx_ready=tx_ready&&guard_ready&&!rx_error&&!external_rt;
    assign O_rt_ready=tx_ready&&!bootstrap_active;
    assign O_tx_done=tx_done;
    // Initial cleanup responses belong only to the bridge's bootstrap epoch.
    // Runtime Alarm/Reset and every explicit recovery response remain visible.
    assign O_rx_data=rx_data;
    assign O_rx_valid=rx_valid&&!bootstrap_mask;
    assign O_rx_error=rx_error&&!bootstrap_mask;
    assign O_idle_pulse=parser_idle&&!bootstrap_mask;
    assign O_rt_done=tx_done&&rt_inflight;
    grbl_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_tx(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_data(tx_mux_data),.I_valid(tx_mux_valid),
        .O_ready(tx_ready),.O_tx(O_uart_tx),.O_done(tx_done));
    grbl_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_rx(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_rx(I_uart_rx),.O_data(rx_data),.O_valid(rx_valid),.O_error(rx_error));
    grbl_response_parser u_parser(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(parser_clear),
        .I_data(rx_data),.I_valid(rx_valid),.O_ok(parser_ok),.O_error(parser_error),
        .O_alarm(parser_alarm),.O_status(parser_status),.O_idle(parser_idle),.O_overflow(parser_overflow),
        .O_hold0(parser_hold0),.O_reset(parser_reset));
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            parser_clear<=1;guard_ready<=0;rt_inflight<=0;probe_timer<=0;
            link_meta<=0;guard_state<=U_HOLD;bootstrap_mask<=1;post_reset<=0;
            status_head<=0;status_alarm_line<=0;
        end else begin
            parser_clear<=0;link_meta<=I_esp_link_ready;
            if(parser_clear)begin status_head<=0;status_alarm_line<=0;end
            else if(rx_valid)begin
                if(rx_data=="<")begin status_head<=1;status_alarm_line<=0;end
                else if(status_head==1)status_head<=(rx_data=="A")?2:0;
                else if(status_head==2)begin status_alarm_line<=(rx_data=="l");status_head<=0;end
            end
            if(tx_done)rt_inflight<=0;
            if(external_rt&&O_rt_ready)rt_inflight<=1;
            if(guard_state!=U_READY&&guard_state!=U_LOCK)begin
                if(probe_timer<GUARD_STATUS_CYCLES)probe_timer<=probe_timer+1'b1;
            end
            // Never repair a runtime half-line by accepting an unsolicited Idle.
            // Leave realtime available so the owning transport can stop, query,
            // clear the controller with Ctrl-X, then establish a fresh epoch.
            if(rx_error || (!bootstrap_active&&(parser_alarm||(parser_status&&status_alarm_line)||(parser_reset&&guard_state==U_READY))))begin
                guard_ready<=0;guard_state<=U_LOCK;bootstrap_mask<=0;
                probe_timer<=0;parser_clear<=1;
            end else if(external_rt&&O_rt_ready&&I_rt_data==8'h18)begin
                guard_ready<=0;guard_state<=U_EXT_RESET_WAIT;
                probe_timer<=0;parser_clear<=1;
            end else if((guard_state==U_EXT_QUERY||guard_state==U_EXT_STATUS)&&
                        external_rt&&O_rt_ready&&I_rt_data==8'h3f)begin
                guard_state<=U_EXT_QUERY_WAIT;
            end else begin
                case(guard_state)
                    U_HOLD:if(tx_ready)begin guard_state<=U_HOLD_WAIT;probe_timer<=0;end
                           else if(probe_timer>=GUARD_SEND_CYCLES-1)begin guard_state<=U_LOCK;bootstrap_mask<=0;end
                    U_HOLD_WAIT:if(tx_done)begin guard_state<=U_QUERY;probe_timer<=0;parser_clear<=1;end
                           else if(probe_timer>=GUARD_SEND_CYCLES-1)begin guard_state<=U_LOCK;bootstrap_mask<=0;end
                    U_QUERY:if(probe_timer>=GUARD_STATUS_CYCLES-1)begin guard_state<=U_LOCK;bootstrap_mask<=0;end
                            else if(tx_ready)guard_state<=U_QUERY_WAIT;
                    U_QUERY_WAIT:if(probe_timer>=GUARD_STATUS_CYCLES-1)begin guard_state<=U_LOCK;bootstrap_mask<=0;end
                            else if(tx_done)begin guard_state<=U_STATUS;parser_clear<=1;end
                    U_STATUS:begin
                        if(parser_alarm||(parser_status&&status_alarm_line)||parser_error||parser_overflow||probe_timer>=GUARD_STATUS_CYCLES-1)begin
                            guard_state<=U_LOCK;bootstrap_mask<=0;
                        end else if(parser_status&&((post_reset&&parser_idle)||(!post_reset&&(parser_idle||parser_hold0))))begin
                            probe_timer<=0;parser_clear<=1;
                            if(post_reset)begin guard_state<=U_READY;guard_ready<=1;bootstrap_mask<=0;end
                            else guard_state<=U_RESET;
                        end else if(poll_due)guard_state<=U_QUERY;
                    end
                    U_RESET:if(tx_ready)begin guard_state<=U_RESET_WAIT;probe_timer<=0;end
                            else if(probe_timer>=GUARD_SEND_CYCLES-1)begin guard_state<=U_LOCK;bootstrap_mask<=0;end
                    U_RESET_WAIT:if(tx_done)begin
                        guard_state<=U_QUERY;post_reset<=1;probe_timer<=0;parser_clear<=1;
                    end else if(probe_timer>=GUARD_SEND_CYCLES-1)begin guard_state<=U_LOCK;bootstrap_mask<=0;end
                    U_EXT_RESET_WAIT:if(tx_done)begin guard_state<=U_EXT_QUERY;parser_clear<=1;end
                        else if(probe_timer>=GUARD_STATUS_CYCLES-1)guard_state<=U_LOCK;
                    U_EXT_QUERY,U_EXT_QUERY_WAIT,U_EXT_STATUS:begin
                        if(probe_timer>=GUARD_STATUS_CYCLES-1)guard_state<=U_LOCK;
                        else if(guard_state==U_EXT_QUERY_WAIT&&tx_done)begin guard_state<=U_EXT_STATUS;parser_clear<=1;end
                        else if(guard_state==U_EXT_STATUS&&parser_idle)begin
                            guard_state<=U_READY;guard_ready<=1;probe_timer<=0;
                        end
                    end
                    U_READY:begin probe_timer<=0;end
                    U_LOCK:begin guard_ready<=0;probe_timer<=0;end
                    default:begin guard_state<=U_LOCK;guard_ready<=0;bootstrap_mask<=0;end
                endcase
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
    localparam integer DIVIDER_W=(DIV<2)?32:$clog2(DIV);
    reg [DIVIDER_W-1:0] divider;
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
