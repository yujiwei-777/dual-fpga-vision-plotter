from pathlib import Path
root=Path(__file__).resolve().parents[1]
rtl=root/'01_rtl/imgq_gain_m/main/user_source/hdl_source'
p=rtl/'hdmi_mixer.v'
s=p.read_text(encoding='utf-8')
start=s.index('    osd_char_lib u_osd_char_lib(')
end=s.index('    // Mode-number -> 4-letter name.',start)
s=s[:start]+'''    // Native 16x16 Chinese and 8x16 ASCII, one shared synchronous ROM.
    // Address stage + ROM read keep the original two-pixel alignment.
    wire S_compact_panel_on, S_compact_text_on, S_compact_border;
    wire [23:0] S_compact_color;
    wire [7:0] S_compact_glyph;
    wire [3:0] S_compact_row;
    wire [15:0] S_compact_bits;
    wire [19:0] S_frame_decimal;
    wire [15:0] S_x_decimal, S_y_decimal;
    wire [23:0] S_area_decimal;
    osd_decimal_snapshot u_osd_decimal(
        .clk(I_clk), .rst_n(I_rst_n), .frame_start(I_video_user),
        .frame_number((LATENCY_OSD_ENABLE!=0)?S_lat_frame:S_frame_cnt[15:0]),
        .target_x(I_ovl_cx), .target_y(I_ovl_cy), .target_area(I_ovl_area),
        .frame_bcd(S_frame_decimal), .target_x_bcd(S_x_decimal),
        .target_y_bcd(S_y_decimal), .area_bcd(S_area_decimal)
    );
    osd_compact_panel u_osd_compact_panel(
        .clk(I_clk), .rst_n(I_rst_n), .x(S_x), .y(S_y),
        .pcb_mode(I_ovl_pcb), .pcb_status(I_pcb_status),
        .algo_mode(I_algo_mode), .he_on(I_he_on),
        .lat_valid(S_lat_valid), .lat_overflow(S_lat_overflow),
        .frame_bcd(S_frame_decimal), .lat_bcd(S_lat_bcd),
        .target_x_bcd(S_x_decimal), .target_y_bcd(S_y_decimal),
        .area_bcd(S_area_decimal), .remote(I_ovl_remote),
        .ovl_valid(I_ovl_valid), .target_color(I_ovl_color),
        .shape3(I_ovl_shape3), .target_shape(I_ovl_shape),
        .motion_enable(I_motion_enable), .motion_bcd(S_motion_bcd),
        .panel_on(S_compact_panel_on), .panel_border(S_compact_border),
        .text_on(S_compact_text_on), .text_color(S_compact_color),
        .font_glyph(S_compact_glyph), .font_row(S_compact_row),
        .font_row_bits(S_compact_bits)
    );
    osd_compact_font_rom u_osd_compact_font(
        .clk(I_clk), .glyph(S_compact_glyph), .row(S_compact_row),
        .row_bits(S_compact_bits)
    );

'''+s[end:]
start=s.index('            if((!S_osd_hit) && !I_ovl_pcb &&')
end=s.index('\n        end\n    end\n\n    // ---- target overlay',start)
s=s[:start]+'''            // Preserve semantic text colors through the final priority stage.
            if(!S_osd_hit && S_compact_panel_on) begin
                S_osd_hit = 1'b1;
                S_osd_color = S_compact_text_on ? S_compact_color :
                              S_compact_border ? COLOR_DYN_BORDER : COLOR_DYN_PANEL;
            end
'''+s[end:]
s=s.replace("localparam DYN_OSD_H         = 12'd208;   // five 32-pixel rows with 8-pixel gaps","localparam DYN_OSD_H         = 12'd128;   // five native 16px rows, 8px gaps")
p.write_text(s,encoding='utf-8')
for name in ('result_overlay.v','hxa_multibox_overlay.v'):
    p=rtl/name
    s=p.read_text(encoding='utf-8')
    s=s.replace('badge_y0<272','badge_y0<192').replace('badge_y_below<272','badge_y_below<192')
    s=s.replace("py<12'd272","py<12'd192").replace('by<272','by<192')
    s=s.replace('enlarged five-row dynamic panel','compact Chinese status panel')
    p.write_text(s,encoding='utf-8')
print('Integrated compact panel; video/data-path latency unchanged.')

