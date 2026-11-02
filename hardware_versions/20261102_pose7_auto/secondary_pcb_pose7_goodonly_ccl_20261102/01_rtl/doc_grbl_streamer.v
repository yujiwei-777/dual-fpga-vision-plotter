// Single-owner, stop-and-wait document transport. A transmitted motion line is
// never retried. Realtime cancel bytes bypass the normal UART ready guard.
module doc_grbl_streamer #(
    parameter integer CLK_HZ=125000000,
    parameter integer QUERY_MS=500, STATUS_MS=2000,
    parameter integer FINAL_MS=120000, PROGRESS_MS=30000, JOB_MS=1800000
)(
    input wire clk,rst_n,start,cancel,rearm,fault,reset_job,
    input wire [7:0] fault_code,
    input wire [511:0] line,input wire [6:0] length,
    input wire line_valid,finish,output wire line_ready,output reg line_done,
    output wire busy,output reg done,error,cancelled,recovery_required,
    output reg [7:0] error_code,output wire [2:0] job_state,
    output reg [31:0] acked_lines,
    output wire [7:0] tx_data,output wire tx_valid,input wire tx_ready,tx_done,
    output wire [7:0] rt_data,output wire rt_valid,input wire rt_ready,
    input wire [7:0] rx_data,input wire rx_valid,rx_error,link_ready
);
    localparam [4:0] IDLE=0,READY=1,SEND=2,BYTE_WAIT=3,ACK_WAIT=4,
        FINAL_QUERY=5,FINAL_QUERY_WAIT=6,FINAL_STATUS=7,
        C_DRAIN=8,C_BANG=9,C_BANG_WAIT=10,C_QUERY=11,C_QUERY_WAIT=12,
        C_STATUS=13,C_RESET=14,C_RESET_WAIT=15,R_QUERY=16,R_QUERY_WAIT=17,R_STATUS=18;
    localparam integer MS_DIV=(CLK_HZ/1000<1)?1:CLK_HZ/1000;
    reg [4:0] state;
    reg [511:0] saved_line;
    reg [6:0] saved_length,index;
    reg inflight,parser_clear,cancel_fault,status_pending;
    reg first_query,final_idle_seen,stop_seen,reset_pending;
    wire reset_request=(reset_job===1'b1);
    reg [2:0] terminal_state;
    reg [31:0] tick_count,job_ms,progress_ms,final_ms,query_ms,response_ms;
    wire tick=(tick_count==MS_DIV-1);
    wire p_ok,p_error,p_alarm,p_status,p_idle,p_hold0,p_overflow,p_reset;
    wire cancelling=(state>=C_DRAIN);
    wire final_phase=(state>=FINAL_QUERY && state<=FINAL_STATUS);
    wire rearm_phase=(state>=R_QUERY && state<=R_STATUS);
    // The motion-progress lease applies while streaming or preparing a line.
    // Once the final status poll is active, only the dedicated final/status
    // timers may fail the job; otherwise a long-but-valid GRBL Idle response
    // would be misreported as the generic progress timeout.
    wire normal_fault=busy && !cancelling &&
        (fault || rx_error || !link_ready || p_error || p_alarm || p_overflow || p_reset ||
         (tick && (job_ms>=JOB_MS-1 ||
          ((!final_phase) && progress_ms>=PROGRESS_MS-1) ||
          (final_phase && final_ms>=FINAL_MS-1) ||
          (status_pending && response_ms>=STATUS_MS-1))));
    assign busy=(state!=IDLE);
    assign job_state=cancelling ? (cancel_fault?3'd5:3'd6) :
                     final_phase?3'd1:busy?3'd2:terminal_state;
    assign line_ready=(state==READY && !cancel && !fault);
    assign tx_valid=(state==SEND && !cancel && !normal_fault);
    assign tx_data=(index==saved_length)?8'h0a:saved_line[index*8+:8];
    assign rt_valid=(state==FINAL_QUERY || state==C_BANG || state==C_QUERY || state==C_RESET || state==R_QUERY) &&
                    !(cancel && !cancelling);
    assign rt_data=(state==C_BANG)?8'h21:(state==C_RESET)?8'h18:8'h3f;
    doc_grbl_response_parser u_parser(.clk(clk),.rst_n(rst_n),.clear(parser_clear),
        .data(rx_data),.valid(rx_valid),.ok(p_ok),.error(p_error),.alarm(p_alarm),
        .status(p_status),.idle(p_idle),.hold0(p_hold0),.overflow(p_overflow),.reset_banner(p_reset));

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;saved_line<=0;saved_length<=0;index<=0;
            inflight<=0;parser_clear<=1;cancel_fault<=0;status_pending<=0;terminal_state<=0;
            first_query<=0;final_idle_seen<=0;stop_seen<=0;reset_pending<=0;
            tick_count<=0;job_ms<=0;progress_ms<=0;final_ms<=0;query_ms<=0;response_ms<=0;
            line_done<=0;done<=0;error<=0;cancelled<=0;recovery_required<=0;
            error_code<=0;acked_lines<=0;
        end else begin
            line_done<=0;done<=0;error<=0;cancelled<=0;parser_clear<=0;
            if(tick)tick_count<=0;else tick_count<=tick_count+1'b1;
            if(tx_done)inflight<=0;
            if((tx_valid&&tx_ready)||(rt_valid&&rt_ready))inflight<=1;
            if(busy && tick)begin
                job_ms<=job_ms+1'b1;progress_ms<=progress_ms+1'b1;
                if(final_phase || cancelling)final_ms<=final_ms+1'b1;
                if(final_phase || cancelling)query_ms<=query_ms+1'b1;
                if(status_pending)response_ms<=response_ms+1'b1;
            end
            // Only a complete response in the current query epoch refreshes
            // the status deadline; repeated '?' cannot keep it alive forever.
            if(p_status && status_pending)begin
                status_pending<=0;response_ms<=0;progress_ms<=0;
                if(final_phase && p_idle)final_idle_seen<=1;
                if(cancelling && (p_idle || p_hold0))stop_seen<=1;
            end
            if(rearm && state==IDLE && recovery_required)begin
                // A cached Idle from the old epoch is not proof of current
                // machine state. Require a fresh response before rearming.
                parser_clear<=1;status_pending<=0;response_ms<=0;query_ms<=0;
                state<=R_QUERY;recovery_required<=1;error_code<=0;
            end

            if(reset_request || (busy && !cancelling && (cancel || normal_fault)))begin
                state<=C_DRAIN;recovery_required<=1;parser_clear<=1;
                cancel_fault<=!cancel&&!reset_request;reset_pending<=reset_request;status_pending<=0;response_ms<=0;query_ms<=0;final_ms<=0;
                stop_seen<=0;final_idle_seen<=0;
                if(cancel||reset_request)error_code<=0;
                else if(fault)error_code<=fault_code;
                else if(rx_error)error_code<=8'h21;
                else if(!link_ready)error_code<=8'h22;
                else if(p_error)error_code<=8'h23;
                else if(p_alarm)error_code<=8'h24;
                else if(p_overflow)error_code<=8'h25;
                else if(p_reset)error_code<=8'h2d;
                else if(job_ms>=JOB_MS-1)error_code<=8'h26;
                else if(progress_ms>=PROGRESS_MS-1)error_code<=8'h27;
                else if(final_ms>=FINAL_MS-1)error_code<=8'h28;
                else error_code<=8'h29;
            end else if(cancelling && tick &&
                        ((status_pending && response_ms>=STATUS_MS-1) || final_ms>=FINAL_MS-1))begin
                // No proof of a stopped machine: do not send a queue reset or
                // claim pen-up. Operator recovery remains mandatory.
                state<=IDLE;error<=1;error_code<=8'h2a;recovery_required<=1;terminal_state<=5;
                parser_clear<=1;status_pending<=0;
            end else begin
                case(state)
                    IDLE:if(start && !recovery_required)begin
                        acked_lines<=0;job_ms<=0;progress_ms<=0;final_ms<=0;
                        query_ms<=0;response_ms<=0;status_pending<=0;parser_clear<=1;
                        error_code<=0;cancel_fault<=0;terminal_state<=2;
                        first_query<=1;final_idle_seen<=0;stop_seen<=0;
                        // The UART guard may describe an old Idle. A fresh
                        // query is mandatory before the first new G-code,
                        // especially after a Ctrl-X/rearm response epoch.
                        if(link_ready)state<=FINAL_QUERY;
                        else begin error<=1;error_code<=8'h20;terminal_state<=5;end
                    end
                    READY:begin
                        if(line_valid)begin
                            if(length==0 || length>64)begin
                                state<=C_DRAIN;cancel_fault<=1;recovery_required<=1;error_code<=8'h2b;
                            end else begin
                                saved_line<=line;saved_length<=length;index<=0;state<=SEND;
                            end
                        end else if(finish)begin
                            // Producer asserts finish only after the final
                            // line_done. Every line, including return/newline,
                            // has therefore received its own GRBL ok.
                            done<=1;state<=IDLE;terminal_state<=4;
                            recovery_required<=0;error_code<=0;
                            status_pending<=0;parser_clear<=1;
                        end
                    end
                    SEND:if(tx_ready)state<=BYTE_WAIT;
                    BYTE_WAIT:if(tx_done)begin
                        if(index==saved_length)begin state<=ACK_WAIT;parser_clear<=1;end
                        else begin index<=index+1'b1;state<=SEND;end
                    end
                    ACK_WAIT:if(p_ok)begin
                        acked_lines<=acked_lines+1'b1;line_done<=1;progress_ms<=0;state<=READY;
                    end
                    FINAL_QUERY:if(rt_ready)state<=FINAL_QUERY_WAIT;
                    FINAL_QUERY_WAIT:if(tx_done)begin
                        if(!status_pending)begin response_ms<=0;status_pending<=1;end
                        // A clear on the first query excludes pre-existing
                        // partial status. Subsequent polls preserve a response
                        // already arriving at the UART.
                        if(first_query)begin parser_clear<=1;first_query<=0;end
                        query_ms<=0;state<=FINAL_STATUS;
                    end
                    FINAL_STATUS:begin
                        if(!inflight && (final_idle_seen || (p_status && p_idle && status_pending)))begin
                            status_pending<=0;parser_clear<=1;final_idle_seen<=0;
                            // This query epoch is reachable only from start.
                            // Normal final-ok completion exits READY directly.
                            state<=READY;progress_ms<=0;
                        end else if(tick && query_ms>=QUERY_MS-1)state<=FINAL_QUERY;
                    end
                    C_DRAIN:if(!inflight)state<=C_BANG;
                    C_BANG:if(rt_ready)state<=C_BANG_WAIT;
                    C_BANG_WAIT:if(tx_done)begin
                        state<=C_QUERY;parser_clear<=1;query_ms<=0;
                    end
                    C_QUERY:if(rt_ready)state<=C_QUERY_WAIT;
                    C_QUERY_WAIT:if(tx_done)begin
                        if(!status_pending)begin
                            response_ms<=0;status_pending<=1;parser_clear<=1;
                        end
                        query_ms<=0;state<=C_STATUS;
                    end
                    C_STATUS:begin
                        if(!inflight && (stop_seen || (p_status && status_pending && (p_idle || p_hold0))))begin
                            state<=C_RESET;status_pending<=0;parser_clear<=1;
                        end else if(tick && query_ms>=QUERY_MS-1)state<=C_QUERY;
                    end
                    C_RESET:if(rt_ready)state<=C_RESET_WAIT;
                    C_RESET_WAIT:if(tx_done)begin
                        state<=IDLE;parser_clear<=1;status_pending<=0;
                        if(reset_pending)begin
                            // A task reset reuses the confirmed stop/reset
                            // sequence, then requires fresh post-reset Idle.
                            state<=R_QUERY;recovery_required<=1;query_ms<=0;response_ms<=0;
                        end else if(cancel_fault)begin error<=1;terminal_state<=5;end
                        else begin cancelled<=1;terminal_state<=6;end
                    end
                    R_QUERY:if(rt_ready)state<=R_QUERY_WAIT;
                    R_QUERY_WAIT:if(tx_done)begin
                        parser_clear<=1;status_pending<=1;response_ms<=0;query_ms<=0;state<=R_STATUS;
                    end
                    R_STATUS:begin
                        if(status_pending && p_status)begin
                            status_pending<=0;response_ms<=0;
                            if(p_idle)begin
                                recovery_required<=0;parser_clear<=1;state<=IDLE;error_code<=0;
                                if(reset_pending)begin cancelled<=1;terminal_state<=6;reset_pending<=0;end
                            end
                        end else if(tick && response_ms>=STATUS_MS-1)begin
                            state<=IDLE;error<=1;error_code<=8'h2c;recovery_required<=1;terminal_state<=5;parser_clear<=1;
                        end else if(tick)response_ms<=response_ms+1'b1;
                    end
                    default:begin state<=IDLE;error<=1;error_code<=8'h2f;recovery_required<=1;terminal_state<=5;end
                endcase
            end
        end
    end
endmodule
