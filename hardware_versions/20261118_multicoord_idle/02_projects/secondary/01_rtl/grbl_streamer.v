// GRBL stop-and-wait transport. Producer supplies one complete ASCII line
// without LF, byte zero in bits [7:0]. No line is replayed on any fault.
// Character TX ready accepts one byte; TX done marks its complete stop bit.
module grbl_streamer #(
    parameter integer CLK_HZ=50000000,
    parameter integer ACK_TIMEOUT_CYCLES=CLK_HZ*5,
    parameter integer STATUS_TIMEOUT_CYCLES=CLK_HZ*2,
    // Kept for source compatibility with existing instantiations. Normal
    // completion no longer has a status-query/retry phase; safety queries
    // retain their separate realtime stop/rearm channel.
    parameter integer QUERY_INTERVAL_CYCLES=CLK_HZ/5,
    parameter integer STATUS_RETRY_INTERVAL_CYCLES=CLK_HZ/2,
    parameter integer STATUS_MAX_RETRIES=3
)(
    input wire I_clk,input wire I_rst_n,
    input wire I_start,input wire I_clear,input wire I_abort,input wire I_stop,input wire I_rearm,
    input wire I_profile_valid,input wire I_link_ready,
    input wire [511:0] I_line_data,input wire [6:0] I_line_length,
    input wire I_line_valid,input wire I_line_last,
    output wire O_line_ready,output reg O_line_acked,
    output reg [7:0] O_tx_data,output reg O_tx_valid,
    input wire I_tx_ready,input wire I_tx_done,
    input wire [7:0] I_rx_data,input wire I_rx_valid,input wire I_rx_error,
    output wire O_busy,output reg O_done,output reg O_error,
    output reg [7:0] O_error_code,output reg [31:0] O_acked_lines,
    output wire [2:0] O_job_state,
    output wire [7:0] O_rt_data,output wire O_rt_valid,input wire I_rt_ready,
    output wire O_rt_done,output wire O_recovery_required
);
    localparam [4:0] IDLE=0,LINE=1,SEND=2,DRAIN=3,ACK=4,FAULT=9,
                     STOP_DRAIN=11,STOP_BANG=12,STOP_BANG_WAIT=13,
                     STOP_QUERY=14,STOP_QUERY_WAIT=15,STOP_STATUS=16,STOP_RESET=17,
                     STOP_RESET_WAIT=18,REARM_QUERY=19,REARM_WAIT=20,REARM_STATUS=21,DONE_PENDING=22;
    localparam [7:0] ERR_PROFILE=1,ERR_LINK=2,ERR_ACK_TIMEOUT=3,
                     ERR_STATUS_TIMEOUT=4,ERR_RESPONSE=5,ERR_UART=6,
                     ERR_LINE=7,ERR_ABORT=8,ERR_RESET=9;
    reg [4:0] state;
    reg [511:0] line_buffer;
    reg [6:0] line_length,send_index;
    reg last_line;
    localparam integer ACK_TIMER_W=(ACK_TIMEOUT_CYCLES<2)?1:$clog2(ACK_TIMEOUT_CYCLES+1);
    localparam integer STATUS_TIMER_W=(STATUS_TIMEOUT_CYCLES<2)?1:$clog2(STATUS_TIMEOUT_CYCLES+1);
    // ACK and stop/rearm status waits are mutually exclusive epochs.
    // Preserve the original procedural write priority for the shared counter.
    localparam integer RESPONSE_TIMER_W =
        (ACK_TIMER_W > STATUS_TIMER_W) ? ACK_TIMER_W : STATUS_TIMER_W;
    reg [RESPONSE_TIMER_W-1:0] response_timer;
    wire [ACK_TIMER_W-1:0] ack_timer = response_timer[ACK_TIMER_W-1:0];
    wire [STATUS_TIMER_W-1:0] status_timer = response_timer[STATUS_TIMER_W-1:0];
    reg tx_inflight,rt_inflight,recovery_required,stop_fault;
    reg parser_clear;
    wire rx_ok,rx_error,rx_alarm,rx_status,rx_idle,rx_overflow,rx_hold0,rx_reset;
    grbl_response_parser u_parser(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(parser_clear),
        .I_data(I_rx_data),.I_valid(I_rx_valid),.O_ok(rx_ok),.O_error(rx_error),
        .O_alarm(rx_alarm),.O_status(rx_status),.O_idle(rx_idle),.O_overflow(rx_overflow),.O_hold0(rx_hold0),.O_reset(rx_reset));
    assign O_busy=(state!=IDLE && state!=FAULT);
    assign O_line_ready=(state==LINE && I_link_ready && I_profile_valid);
    assign O_job_state=(state==FAULT)?3'd5:(state==IDLE)?3'd0:
                       (state>=STOP_DRAIN)?3'd3:3'd2;
    assign O_recovery_required=recovery_required;
    assign O_rt_valid=(state==STOP_BANG||state==STOP_QUERY||state==STOP_RESET||
                       state==REARM_QUERY);
    assign O_rt_data=(state==STOP_BANG)?8'h21:(state==STOP_RESET)?8'h18:8'h3f;
    assign O_rt_done=rt_inflight && I_tx_done;
    always @* begin
        O_tx_valid=0;O_tx_data=0;
        if(I_link_ready && I_profile_valid && !I_abort && !I_stop)begin
            if(state==SEND)begin
                O_tx_valid=1;
                O_tx_data=(send_index==line_length)?8'h0a:line_buffer[7:0];
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;line_buffer<=0;line_length<=0;send_index<=0;last_line<=0;
            response_timer<=0;
            parser_clear<=1;O_done<=0;O_error<=0;O_error_code<=0;
            O_acked_lines<=0;O_line_acked<=0;
            tx_inflight<=0;rt_inflight<=0;recovery_required<=0;stop_fault<=0;
        end else begin
            parser_clear<=0;O_done<=0;O_line_acked<=0;
            if(O_tx_valid && I_tx_ready)tx_inflight<=1;
            if(I_tx_done)begin tx_inflight<=0; if(rt_inflight)rt_inflight<=0; end
            if(rx_reset && !I_stop && (state<=FAULT || state==DONE_PENDING))begin
                // An external Reset may have discarded queued motion and
                // modal coordinates. Never continue or replay the old job.
                // The expected banner in KEY4 stop/reset/rearm is outside
                // these states and remains gated by a fresh Idle response.
                state<=FAULT;O_error<=1;O_error_code<=ERR_RESET;recovery_required<=1;parser_clear<=1;
            end else if(I_clear && !O_busy && !I_stop)begin
                state<=IDLE;O_error<=0;O_error_code<=0;parser_clear<=1;
                response_timer<=0;
            end else if(I_rearm && !I_stop && (state==IDLE || state==FAULT) && recovery_required && I_link_ready && I_profile_valid)begin
                // A rearm is a fresh status epoch; a cached Idle is not
                // sufficient proof that the machine is currently safe.
                O_error<=0;O_error_code<=0;
                parser_clear<=1;response_timer<=0;
                recovery_required<=1;state<=REARM_QUERY;
            end else if(I_stop && (state<STOP_DRAIN || state==DONE_PENDING))begin
                // Stop requests never replay a motion line. Drain the one
                // byte already accepted by the UART, then use the realtime
                // GRBL hold/status/reset sequence.
                state<=STOP_DRAIN;stop_fault<=0;parser_clear<=1;recovery_required<=1;O_error<=0;O_error_code<=0;
                response_timer<=0;
            end else if(O_busy && (I_abort || !I_link_ready || !I_profile_valid ||
                         I_rx_error || rx_error || rx_alarm || rx_overflow))begin
                state<=FAULT;O_error<=1;recovery_required<=1;
                if(I_abort)O_error_code<=ERR_ABORT;
                else if(I_rx_error)O_error_code<=ERR_UART;
                else if(rx_error || rx_alarm || rx_overflow)O_error_code<=ERR_RESPONSE;
                else if(!I_link_ready)O_error_code<=ERR_LINK;
                else if(!I_profile_valid)O_error_code<=ERR_PROFILE;
                else O_error_code<=ERR_STATUS_TIMEOUT;
            end else begin
                // Reachable wait states override this clear with their own
                // counter update below. The retired normal-final query chain
                // had no incoming edge after last-ok completion was enabled.
                if(O_busy)response_timer<=0;
                case(state)
                    IDLE:if(I_start && !recovery_required)begin
                        if(!I_profile_valid || !I_link_ready)begin
                            state<=FAULT;O_error<=1;recovery_required<=1;
                            O_error_code<=!I_profile_valid?ERR_PROFILE:ERR_LINK;
                        end else begin
                            state<=LINE;O_error<=0;O_error_code<=0;O_acked_lines<=0;
                            response_timer<=0;
                            parser_clear<=1;
                        end
                    end
                    LINE:if(I_line_valid)begin
                        if(I_line_length==0 || I_line_length>63)begin
                            state<=FAULT;O_error<=1;O_error_code<=ERR_LINE;recovery_required<=1;
                        end else begin
                            line_buffer<=I_line_data;line_length<=I_line_length;
                            last_line<=I_line_last;send_index<=0;state<=SEND;response_timer<=0;
                        end
                    end
                    SEND:if(O_tx_valid && I_tx_ready)begin
                        if(send_index==line_length)state<=DRAIN;
                        else begin line_buffer<={8'd0,line_buffer[511:8]};send_index<=send_index+1'b1;end
                    end
                    DRAIN:if(I_tx_done)begin state<=ACK;response_timer<=0;end
                    ACK:begin
                        if(rx_ok)begin
                            O_acked_lines<=O_acked_lines+1'b1;O_line_acked<=1;response_timer<=0;
                            if(last_line)begin
                                // All normal report paths complete on the
                                // last line ACK. The extra state exposes the
                                // updated ACK counter before O_done pulses.
                                state<=DONE_PENDING;recovery_required<=0;
                            end else state<=LINE;
                        end else if(ack_timer>=ACK_TIMEOUT_CYCLES-1)begin
                            state<=FAULT;O_error<=1;O_error_code<=ERR_ACK_TIMEOUT;recovery_required<=1;
                        end else response_timer<=ack_timer+1'b1;
                    end
                    DONE_PENDING:begin
                        O_done<=1;state<=IDLE;recovery_required<=0;O_error<=0;O_error_code<=0;
                        parser_clear<=1;
                    end
                    STOP_DRAIN:if(!tx_inflight)state<=STOP_BANG;
                    STOP_BANG:if(O_rt_valid && I_rt_ready)begin rt_inflight<=1;state<=STOP_BANG_WAIT;end
                    STOP_BANG_WAIT:if(I_tx_done)begin parser_clear<=1;state<=STOP_QUERY;end
                    STOP_QUERY:if(O_rt_valid && I_rt_ready)begin rt_inflight<=1;state<=STOP_QUERY_WAIT;end
                    STOP_QUERY_WAIT:if(I_tx_done)begin parser_clear<=1;response_timer<=0;state<=STOP_STATUS;end
                    STOP_STATUS:begin
                        if(rx_hold0 || rx_idle)begin
                            state<=STOP_RESET;parser_clear<=1;
                        end else if(status_timer>=STATUS_TIMEOUT_CYCLES-1)begin
                            state<=FAULT;O_error<=1;O_error_code<=ERR_STATUS_TIMEOUT;recovery_required<=1;
                        end else response_timer<=status_timer+1'b1;
                    end
                    STOP_RESET:if(O_rt_valid && I_rt_ready)begin rt_inflight<=1;state<=STOP_RESET_WAIT;end
                    STOP_RESET_WAIT:if(I_tx_done)begin
                        // KEY4 is a safe task reset, not a raw FPGA/POR
                        // reset. Clear/rearm only after a new post-Ctrl-X
                        // Idle status; unknown or Alarm remains locked.
                        state<=REARM_QUERY;recovery_required<=1;O_done<=0;
                        parser_clear<=1;response_timer<=0;
                    end
                    REARM_QUERY:if(O_rt_valid && I_rt_ready)begin rt_inflight<=1;state<=REARM_WAIT;end
                    REARM_WAIT:if(I_tx_done)begin parser_clear<=1;response_timer<=0;state<=REARM_STATUS;end
                    REARM_STATUS:begin
                        if(rx_idle)begin recovery_required<=0;parser_clear<=1;state<=IDLE;end
                        else if(status_timer>=STATUS_TIMEOUT_CYCLES-1)begin
                            state<=FAULT;O_error<=1;O_error_code<=ERR_STATUS_TIMEOUT;recovery_required<=1;
                        end else response_timer<=status_timer+1'b1;
                    end
                    FAULT:begin end
                    default:begin state<=FAULT;O_error<=1;O_error_code<=ERR_LINE;end
                endcase
            end
        end
    end
endmodule
