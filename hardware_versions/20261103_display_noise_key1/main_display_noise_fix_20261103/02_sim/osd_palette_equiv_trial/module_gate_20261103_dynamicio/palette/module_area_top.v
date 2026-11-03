module module_area_top(
    input wire clk, rst_n,
    input wire [11:0] x, y,
    input wire pcb_mode,
    input wire [2:0] pcb_status,
    input wire [4:0] algo_mode,
    input wire he_on, lat_valid, lat_overflow,
    input wire [31:0] metadata_word,
    input wire remote, ovl_valid,
    input wire [1:0] target_color, shape3,
    input wire target_shape, motion_enable,
    input wire [15:0] font_row_bits,
    output wire panel_on, panel_border, text_on,
    output wire [23:0] text_color,
    output wire [7:0] font_glyph,
    output wire [3:0] font_row
);
    reg [111:0] dynamic_bcd_metadata;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dynamic_bcd_metadata <= 112'd0;
        else dynamic_bcd_metadata <= {dynamic_bcd_metadata[79:0], metadata_word};
    end
    osd_compact_panel_area_dut dut(
        .clk(clk), .rst_n(rst_n), .x(x), .y(y),
        .pcb_mode(pcb_mode), .pcb_status(pcb_status), .algo_mode(algo_mode),
        .he_on(he_on), .lat_valid(lat_valid), .lat_overflow(lat_overflow),
        .frame_bcd(dynamic_bcd_metadata[111:92]),
        .lat_bcd(dynamic_bcd_metadata[91:76]),
        .target_x_bcd(dynamic_bcd_metadata[75:60]),
        .target_y_bcd(dynamic_bcd_metadata[59:44]),
        .area_bcd(dynamic_bcd_metadata[43:20]),
        .remote(remote), .ovl_valid(ovl_valid),
        .target_color(target_color), .shape3(shape3),
        .target_shape(target_shape), .motion_enable(motion_enable),
        .motion_bcd(dynamic_bcd_metadata[19:0]),
        .panel_on(panel_on), .panel_border(panel_border), .text_on(text_on),
        .text_color(text_color), .font_glyph(font_glyph), .font_row(font_row),
        .font_row_bits(font_row_bits)
    );
endmodule
