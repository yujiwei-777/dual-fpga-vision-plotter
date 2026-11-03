`timescale 1ns/1ps
module tb_display_tone_regression;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [95:0] data = 0;
    reg valid = 0, user = 0, last = 0, enable = 0, ready = 1;
    wire in_ready, old_in_ready;
    wire [95:0] out_data, fixed_data, old_out_data, old_fixed_data;
    wire out_valid, out_user, out_last, fixed_valid, fixed_user, fixed_last;
    wire old_valid, old_user, old_last, old_fixed_valid, old_fixed_user, old_fixed_last;
    display_tone_96 dut(
        .I_clk(clk), .I_rst_n(rst_n), .I_tdata(data), .I_tvalid(valid),
        .I_tuser(user), .I_tlast(last), .I_tone_enable(enable),
        .I_tready(in_ready), .O_tready(ready), .O_tdata(out_data),
        .O_tvalid(out_valid), .O_tuser(out_user), .O_tlast(out_last),
        .O_fixed_tdata(fixed_data), .O_fixed_tvalid(fixed_valid),
        .O_fixed_tuser(fixed_user), .O_fixed_tlast(fixed_last));
    display_tone_96_frozen baseline(
        .I_clk(clk), .I_rst_n(rst_n), .I_tdata(data), .I_tvalid(valid),
        .I_tuser(user), .I_tlast(last), .I_tone_enable(enable),
        .I_tready(old_in_ready), .O_tready(ready), .O_tdata(old_out_data),
        .O_tvalid(old_valid), .O_tuser(old_user), .O_tlast(old_last),
        .O_fixed_tdata(old_fixed_data), .O_fixed_tvalid(old_fixed_valid),
        .O_fixed_tuser(old_fixed_user), .O_fixed_tlast(old_fixed_last));

    reg [7:0] fixed_curve[0:255], display_curve[0:255];
    reg [95:0] exp_data = 0, exp_fixed = 0;
    reg exp_valid = 0, exp_user = 0, exp_last = 0;
    reg frame_enable = 0, pending_user = 0;
    reg active_enable;
    reg [7:0] channel_value;
    integer lane, cycles = 0, accepted = 0, stalled = 0;
    integer isolated_sof = 0, bypassed = 0, toned = 0;
    integer simultaneous = 0, mode_midframe = 0, resets = 0;
    reg [255:0] seen_tone = 0, seen_raw = 0;
    reg [31:0] rng = 32'h195e902d;
    integer index;

    function [31:0] random_next(input [31:0] value);
        reg [31:0] r;
        begin
            r = value ^ (value << 13);
            r = r ^ (r >> 17);
            random_next = r ^ (r << 5);
        end
    endfunction
    function [95:0] pattern(input integer value);
        integer j;
        reg [7:0] v;
        begin
            for (j = 0; j < 12; j = j + 1) begin
                v = value + 17*j;
                pattern[95-j*8 -: 8] = v;
            end
        end
    endfunction

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (!rst_n) begin
            exp_data = 0; exp_fixed = 0;
            exp_valid = 0; exp_user = 0; exp_last = 0;
            frame_enable = 0; pending_user = 0;
            resets = resets + 1;
        end else if (!exp_valid || ready) begin
            if (valid) begin
                accepted = accepted + 1;
                if (exp_valid && ready) simultaneous = simultaneous + 1;
                active_enable = user ? enable : frame_enable;
                for (lane = 0; lane < 12; lane = lane + 1) begin
                    channel_value = data[95-lane*8 -: 8];
                    exp_fixed[95-lane*8 -: 8] = fixed_curve[channel_value];
                    exp_data[95-lane*8 -: 8] = active_enable
                        ? display_curve[channel_value] : channel_value;
                    if (active_enable) seen_tone[channel_value] = 1;
                    else seen_raw[channel_value] = 1;
                end
                exp_valid = 1;
                exp_user = user || pending_user;
                exp_last = last;
                if (active_enable) toned = toned + 1;
                else bypassed = bypassed + 1;
                if (!user && (enable != frame_enable)) mode_midframe = mode_midframe + 1;
                pending_user = 0;
            end else begin
                exp_valid = 0; exp_user = 0; exp_last = 0;
            end
            if (user) begin
                frame_enable = enable;
                if (!valid) begin
                    pending_user = 1;
                    isolated_sof = isolated_sof + 1;
                end
            end
        end else stalled = stalled + 1;
        #1;
        if ({in_ready, out_valid, out_user, out_last, fixed_valid, fixed_user, fixed_last}
          !== {old_in_ready, old_valid, old_user, old_last, old_fixed_valid, old_fixed_user, old_fixed_last})
            $fatal(1, "BASELINE_CONTROL_MISMATCH cycle=%0d", cycles);
        if (fixed_data !== old_fixed_data)
            $fatal(1, "FIXED_TAP_CHANGED cycle=%0d new=%h baseline=%h", cycles, fixed_data, old_fixed_data);
        if ({out_valid, out_user, out_last} !== {exp_valid, exp_user, exp_last})
            $fatal(1, "REFERENCE_CONTROL_MISMATCH cycle=%0d", cycles);
        if (out_data !== exp_data || fixed_data !== exp_fixed)
            $fatal(1, "REFERENCE_DATA_MISMATCH cycle=%0d actual=%h expected=%h fixed=%h expected_fixed=%h",
                   cycles, out_data, exp_data, fixed_data, exp_fixed);
    end

    initial begin
        $readmemh("fixed_curve.hex", fixed_curve);
        $readmemh("display_curve.hex", display_curve);
        repeat (3) @(negedge clk);
        rst_n = 1;
        // An idle SOF must latch the mode and be attached to the next pixel.
        user = 1; enable = 1; valid = 0;
        @(negedge clk);
        user = 0; valid = 1;
        for (index = 0; index < 256; index = index + 1) begin
            data = pattern(index); last = (index % 16) == 15;
            @(negedge clk);
        end
        // Every channel value also passes through the raw display mode.
        enable = 0; user = 1;
        for (index = 0; index < 256; index = index + 1) begin
            data = pattern(index); last = (index % 16) == 15;
            @(negedge clk); user = 0;
        end
        for (index = 0; index < 24000; index = index + 1) begin
            rng = random_next(rng);
            ready = (rng[4:2] != 3'b000) && (rng[4:2] != 3'b001);
            enable = rng[7];
            #1;
            // AXI payload and markers remain held while a valid beat stalls.
            if (!valid || in_ready) begin
                valid = rng[0] || rng[1];
                user = rng[12:8] == 5'b00101;
                last = rng[18:14] == 5'b10010;
                data = {rng, random_next(rng), random_next(random_next(rng))};
            end
            if (index == 10000) begin
                // Asynchronous reset while either side may be stalled.
                rst_n = 0;
                #1;
                if (out_valid !== 0 || fixed_data !== 0) $fatal(1, "RESET_NOT_FLUSHED");
            end
            if (index == 10002) rst_n = 1;
            @(negedge clk);
        end
        valid = 0; user = 0; last = 0; ready = 1;
        repeat (4) @(negedge clk);
        if (seen_tone !== {256{1'b1}} || seen_raw !== {256{1'b1}})
            $fatal(1, "SCALAR_COVERAGE_INCOMPLETE");
        if (stalled < 1000 || isolated_sof < 10 || simultaneous < 1000 || mode_midframe < 1000)
            $fatal(1, "CONTROL_COVERAGE_INCOMPLETE");
        $display("PASS display_tone frozen_tap_cycle_compare cycles=%0d accepted=%0d stalled=%0d tone=%0d raw=%0d isolated_sof=%0d simultaneous=%0d midframe_enable_ignored=%0d reset_cycles=%0d",
                 cycles, accepted, stalled, toned, bypassed, isolated_sof, simultaneous, mode_midframe, resets);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "WATCHDOG");
    end
endmodule
