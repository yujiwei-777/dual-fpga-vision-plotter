# Compact Chinese OSD v2 independent read-only review

Review date: 2026-10-30. No RTL was changed during this review. This is a static integration review supported by the completed panel/decimal unit tests; actual HDMI/baseline replay remains a separate integration result.

## Snapshot and metadata consistency

The display snapshot trigger is `I_video_de && !I_video_user && S_y==0 && S_x==4`. The pixel counter advances each active cycle, so this is one trigger near the start of each ordinary complete frame. This samples the top-level frame-latched target metadata after the frame-start edge. Four 24-cycle decimal conversions commit together after 96 cycles. At 1280 active pixels per line, the commit precedes the first OSD row at y=64 by a large margin.

The latency mailbox commits `S_lat_frame`, `S_lat_bcd`, `S_lat_valid`, and `S_lat_overflow` together, and only while `I_video_vsync && !I_video_de`. The converter can finish work in active video, but its result cannot commit until blanking. Consequently, by y=0/x=4 the mailbox has either committed the complete new tuple or retained the complete previous tuple. The frame-number decimal snapshot and directly displayed latency BCD therefore refer to the same committed tuple during that active frame. A too-short preceding blank can defer an update to a later frame; it does not split frame number from latency. This relies on the existing valid video contract: vsync denotes vertical blanking and user denotes frame start.

The active-video trigger also avoids sampling the pre-commit frame number on the same edge as a late blanking commit, and avoids target metadata captured on the same frame-start edge. The converter only drives OSD numerical fields and has no path to video read enables, pixel data, detection, communication, or camera controls.

## Pixel and color alignment

Panel stage 1 captures glyph/row/column/valid/color from S_x/S_y. The synchronous font ROM then reads that registered address; panel stage 2 captures the corresponding column/valid/color. This aligns the pixel with S_x_2d/S_y_2d. There is no third register of font bits. The color path is preserved through S_compact_color, S_osd_color, S_osd_color_a, S_disp_col, and O_hdmi_data. OSD composition remains gated by the existing video-data-enable pipeline. The video/overlay priority and non-OSD fallback data pipeline remain unchanged.

## Font initialization and size

All 3664 font words are initialized exactly once, covering addresses 0..3663. The input glyph is bounded to at most 228 and the row is four bits, giving a maximum address of 228*16+15=3663. Invalid larger glyph IDs map to ASCII space.

Measured bitmap bounds for ASCII digits 0/1/2 and letters A/M/X are 14 pixels high, y=1..14. Representative Chinese glyphs are 14..16 pixels high, so v2 ASCII and Chinese have comparable visual heights while retaining the intended narrow ASCII widths. ASCII occupies approximately x=4..11 inside each 16-pixel cell; Chinese generally occupies x=0..14 or x=1..14.

## Layout and semantic checks

Right panel bounds remain [864,1200) by [64,192), shortened to [64,168) when motion monitoring is disabled. Text begins at x=872, giving eight pixels of left padding. The longest 20-cell coordinate line occupies x=872..1191 and has eight pixels of remaining panel width before its right border; no character is clipped. PCB text begins at x=32 in the unchanged [24,312) by [584,680) panel. The right panel is disabled in PCB mode, preserving baseline visibility.

The fixed PCB rectangle has inclusive y=140..551, so it does not intersect the PCB panel beginning at y=584. Motion-disabled mode hides both the count text and the extra panel height. X/Y retain all four decimal places, area retains six decimal places with saturation to 999999, and frame number has five decimal places. Remote triangle/circle/square, local rectangle/blob, and red/green/blue mappings retain their existing input encodings. Algorithm mode numbers 0..18 are unchanged.

## Evidence and limits

Panel v2 simulation: reports/panel_unit/transcript_v2.log; 74,170 checks, zero errors/warnings. Decimal simulation: 02_sim/decimal_snapshot.log; 634 checks, zero errors/warnings. v1 evidence is preserved under reports/panel_unit_v1. This review does not substitute for routed timing, physical implementation checks, or board validation. No blocking correctness issue was found.

Reviewed SHA256:

- osd_compact_panel.v: BE43004C5DE76568CD5C686984E4933EA958106D31860AE2B68A060B8B5B02F7
- osd_compact_font_rom.v: 2E358E2E47B5A5AA7FF95634CCC75825988A761BAA1393E60EC20B1ECFFF0C3A
- osd_decimal_snapshot.v: 03A8E984F417D868BB564A84D46B8C577A1385C86BA9F5156C1CAF7FCF7930A4
- hdmi_mixer.v: BE5C6576DAA38D5D05325673D35C57BDB80CE3536B2C98E223A19E126A16B7F5
