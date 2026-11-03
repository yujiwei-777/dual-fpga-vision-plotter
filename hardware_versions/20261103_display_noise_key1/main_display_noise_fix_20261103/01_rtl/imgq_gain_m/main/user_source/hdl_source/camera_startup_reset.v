// SC500CS startup sequencing in the camera MCLK domain.
// At 24 MHz: XSHUTDN high for 1 ms, low for 10 ms, then high for
// 20 ms before releasing the I2C configuration engine.  This observes the
// sensor's T4/T5/T6 startup sequence; PLL lock loss repeats all three waits.
module camera_startup_reset #(
    parameter integer PRE_RESET_CYCLES = 24000,
    parameter integer PWDN_HOLD_CYCLES = 240000,
    parameter integer CFG_WAIT_CYCLES = 480000
)(
    input wire I_clk,
    input wire I_rst_n,
    output reg O_cam_pwdn_n = 1'b1,
    output reg O_cfg_rst_n = 1'b0
);
    // Zero/negative overrides are clamped to one clock.  This keeps every
    // counter representable and preserves reset-before-configuration order.
    localparam integer PRE_CYCLES = (PRE_RESET_CYCLES < 1) ? 1 : PRE_RESET_CYCLES;
    localparam integer HOLD_CYCLES = (PWDN_HOLD_CYCLES < 1) ? 1 : PWDN_HOLD_CYCLES;
    localparam integer WAIT_CYCLES = (CFG_WAIT_CYCLES < 1) ? 1 : CFG_WAIT_CYCLES;

    function integer counter_width;
        input integer cycles;
        integer value;
        begin
            value = cycles - 1;
            counter_width = 0;
            while (value > 0) begin
                counter_width = counter_width + 1;
                value = value >> 1;
            end
            if (counter_width == 0)
                counter_width = 1;
        end
    endfunction

    localparam integer PRE_WIDTH = counter_width(PRE_CYCLES);
    localparam integer HOLD_WIDTH = counter_width(HOLD_CYCLES);
    localparam integer WAIT_WIDTH = counter_width(WAIT_CYCLES);
    localparam [PRE_WIDTH-1:0] PRE_LAST = PRE_CYCLES - 1;
    localparam [HOLD_WIDTH-1:0] HOLD_LAST = HOLD_CYCLES - 1;
    localparam [WAIT_WIDTH-1:0] WAIT_LAST = WAIT_CYCLES - 1;
    localparam [1:0] PH_PRE = 2'd0, PH_HOLD = 2'd1, PH_WAIT = 2'd2, PH_DONE = 2'd3;
    reg [1:0] startup_phase = PH_PRE;
    reg [PRE_WIDTH-1:0] pre_count = {PRE_WIDTH{1'b0}};
    reg [HOLD_WIDTH-1:0] hold_count = {HOLD_WIDTH{1'b0}};
    reg [WAIT_WIDTH-1:0] wait_count = {WAIT_WIDTH{1'b0}};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_cam_pwdn_n <= 1'b1;
            O_cfg_rst_n <= 1'b0;
            startup_phase <= PH_PRE;
            pre_count <= {PRE_WIDTH{1'b0}};
            hold_count <= {HOLD_WIDTH{1'b0}};
            wait_count <= {WAIT_WIDTH{1'b0}};
        end else begin
            case (startup_phase)
                PH_PRE: begin
                    if (pre_count == PRE_LAST) begin
                        O_cam_pwdn_n <= 1'b0;
                        startup_phase <= PH_HOLD;
                    end else
                        pre_count <= pre_count + 1'b1;
                end
                PH_HOLD: begin
                    if (hold_count == HOLD_LAST) begin
                        O_cam_pwdn_n <= 1'b1;
                        startup_phase <= PH_WAIT;
                    end else
                        hold_count <= hold_count + 1'b1;
                end
                PH_WAIT: begin
                    if (wait_count == WAIT_LAST) begin
                        O_cfg_rst_n <= 1'b1;
                        startup_phase <= PH_DONE;
                    end else
                        wait_count <= wait_count + 1'b1;
                end
                PH_DONE: begin end
            endcase
        end
        // After completion all counters saturate at their terminal count;
        // they cannot wrap and accidentally retrigger either reset output.
    end
endmodule

// Reset the main PLL once after each FPGA configuration.  This counter uses
// the board oscillator directly, so it can run while the PLL is in reset.
// The default interval is 1 ms at 50 MHz.
module power_on_reset #(
    parameter integer HOLD_CYCLES = 50000
)(
    input wire I_clk,
    output reg O_rst = 1'b1
);
    localparam integer ACTIVE_CYCLES = (HOLD_CYCLES < 1) ? 1 : HOLD_CYCLES;
    function integer counter_width;
        input integer cycles;
        integer value;
        begin
            value = cycles - 1;
            counter_width = 0;
            while (value > 0) begin
                counter_width = counter_width + 1;
                value = value >> 1;
            end
            if (counter_width == 0)
                counter_width = 1;
        end
    endfunction
    localparam integer COUNT_WIDTH = counter_width(ACTIVE_CYCLES);
    localparam [COUNT_WIDTH-1:0] COUNT_LAST = ACTIVE_CYCLES - 1;
    reg [COUNT_WIDTH-1:0] count = {COUNT_WIDTH{1'b0}};
    always @(posedge I_clk) begin
        if (O_rst) begin
            if (count == COUNT_LAST)
                O_rst <= 1'b0;
            else
                count <= count + 1'b1;
        end
    end
endmodule
