module key4_hold_debounce #(
    parameter integer DEBOUNCE_CYCLES = 2500000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  pressed
);
    localparam integer COUNT_WIDTH = (DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1;

    (* ASYNC_REG = "TRUE" *) reg key_meta;
    (* ASYNC_REG = "TRUE" *) reg key_sync;
    reg [COUNT_WIDTH-1:0] stable_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b1;
            key_sync <= 1'b1;
            stable_count <= {COUNT_WIDTH{1'b0}};
            pressed <= 1'b0;
        end else begin
            key_meta <= key_n;
            key_sync <= key_meta;

            if ((~key_sync) == pressed) begin
                stable_count <= {COUNT_WIDTH{1'b0}};
            end else if (stable_count == DEBOUNCE_CYCLES - 1) begin
                pressed <= ~key_sync;
                stable_count <= {COUNT_WIDTH{1'b0}};
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end
endmodule

// PCB one-shot key. Keep this module in the already-listed KEY4 source file
// so the project cannot accidentally omit its implementation. Both press
// and release require 20ms at 125MHz. Entry/reset always requires a fresh
// qualified release: an already-held key never becomes an automatic job.
module key4_pcb_oneshot #(
    parameter integer DEBOUNCE_CYCLES=2500000
)(
    input wire clk,rst_n,key_n,mode_active,
    output reg press_pulse,
    output wire pressed,armed
);
    localparam integer COUNT_WIDTH=(DEBOUNCE_CYCLES>1)?$clog2(DEBOUNCE_CYCLES):1;
    localparam [1:0] WAIT_RELEASE=2'd0,READY=2'd1,HELD=2'd2;
    (* ASYNC_REG="TRUE" *) reg key_meta;
    (* ASYNC_REG="TRUE" *) reg key_sync;
    reg [1:0] mode_settle;
    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] stable_count;
    wire want_transition=(state==READY)?!key_sync:key_sync;
    assign pressed=(state==HELD)&&mode_active;
    assign armed=(state==READY)&&mode_active;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            key_meta<=1'b1;key_sync<=1'b1;mode_settle<=0;
            state<=WAIT_RELEASE;stable_count<=0;press_pulse<=0;
        end else begin
            key_meta<=key_n;key_sync<=key_meta;press_pulse<=0;
            if(!mode_active)begin
                mode_settle<=0;state<=WAIT_RELEASE;stable_count<=0;
            end else if(mode_settle!=2'd3)begin
                // Flush reset/default synchronizer values before observing
                // release, including small debounce settings in simulation.
                mode_settle<=mode_settle+1'b1;state<=WAIT_RELEASE;stable_count<=0;
            end else if(!want_transition)stable_count<=0;
            else if(stable_count==DEBOUNCE_CYCLES-1)begin
                stable_count<=0;
                if(state==READY)begin
                    state<=HELD;press_pulse<=1;
                end else state<=READY;
            end else stable_count<=stable_count+1'b1;
        end
    end
endmodule


// Presentation-only PCB task status. No HXA1 fields or task controls change.
// A terminal result survives release, link loss and result invalidation;
// only a new press or operating-mode exit removes the displayed result.
module key4_pcb_status(
    input wire clk,rst_n,mode_active,key_press,
    input wire phy_ready,online,capture_req,capture_cancel,
    input wire result_toggle,result_valid,target_valid,result_checked,result_good,
    output reg [2:0] status
);
    localparam READY=3'd0,SCANNING=3'd1,PASS=3'd2,FAIL=3'd3,
               REVIEW=3'd4,NO_TARGET=3'd5,WAIT_READY=3'd6,LINK_ERROR=3'd7;
    reg result_seen,had_online;
    wire terminal_result=((status>=PASS)&&(status<=NO_TARGET))||(status==LINK_ERROR);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin status<=WAIT_READY;result_seen<=0;had_online<=0;end
        else begin
            result_seen<=result_toggle;
            if(!mode_active)begin status<=WAIT_READY;had_online<=0;end
            else begin
                if(online&&phy_ready)had_online<=1;
                if(capture_req)status<=SCANNING;
                else if(key_press&&status!=SCANNING)status<=(!online||!phy_ready)?
                    (had_online?LINK_ERROR:WAIT_READY):READY;
                else if(status==SCANNING)begin
                    if(!online||!phy_ready||capture_cancel)status<=LINK_ERROR;
                    else if(result_toggle!=result_seen)begin
                        if(!target_valid||!result_valid)status<=NO_TARGET;
                        else if(!result_checked)status<=REVIEW;
                        else status<=result_good?PASS:FAIL;
                    end
                end else if(!terminal_result)begin
                    if(online&&phy_ready)status<=READY;
                    else status<=had_online?LINK_ERROR:WAIT_READY;
                end
            end
        end
    end
endmodule
