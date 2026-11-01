# Compact Chinese OSD font and mixer verification, v2

Status: PASS for the RTL simulation scope below. Hardware and camera appearance remain NOT_RUN. This report does not certify synthesis, timing, place/route, CDC, or bitgen.

## Frozen font

- ROM: `01_rtl/imgq_gain_m/main/user_source/hdl_source/osd_compact_font_rom.v`
- ROM SHA256: `2E358E2E47B5A5AA7FF95634CCC75825988A761BAA1393E60EC20B1ECFFF0C3A`
- Manifest: `model/font_glyphs.json`, SHA256 `5821D35A05C0DF85E4FB86846CC73BCE8EBFC681E61B6A7CC08D1E5D2E0425B2`
- 101 Chinese glyphs retain IDs 0x80 through 0xE4, native SimSun 16x16 raster. ASCII remains at its existing IDs.
- ASCII uses complete Consolas 17px raster bounding boxes, fitted to an 8x16 centered source. Capitals and digits have a 14px body, close to the Chinese 15px body. Overwide M/W and other glyphs use binary nearest-neighbour compression to at most 8px; no bounding-box ink is cropped. Lowercase and punctuation preserve relative size subject to the 14px fit. This is explicit ASCII bitmap resampling, not a change to Chinese glyphs or panel pitch.
- All 3,664 emitted 16-bit ROM words were independently parsed and compared with the generator output; duplicate/missing addresses are zero. All 101 Chinese glyphs are nonempty and unclipped. ASCII bounds are checked before/after fitting.
- The ROM has one synchronous read, no reset and no runtime font/readmem dependency. No interface or glyph-ID change.
- Native/2x comparison: `previews/compact_font_native_2x_mixed.png`; full atlas: `previews/compact_font_atlas.png`.

## Actual mixer regression

`02_sim/mixer_regression/run_mixer.ps1` compiles the frozen current hdmi_mixer and actual ROM, alongside a renamed read-only baseline mixer from main_osd_large_font_20261030. Both use LOGO_ENABLE=0 and LATENCY_OSD_ENABLE=1. ModelSim uses the existing file license at E:/model/win64/LICENSE.TXT through both license environment variables.

- Seven complete 1280x720 streaming frames: 6,451,200 active pixels.
- 5,619,034 pixels outside intentionally changed panel/label regions exactly match the baseline. The comparison masks include both old/new panel bounds, and case 4 additionally permits the intended multibox label relocation. This does not claim all image pixels are unchanged.
- DE, HS and VS match baseline and the existing five-clock mixer pipeline. Read requests are unchanged. A clear background region checks RGB pixel alignment.
- Scenarios: bright scene, dark invalid target/motion disabled, PCB fixed window, document DRAW overlay, four multiboxes with compact-panel label avoidance, active-frame mode switch, maximum coordinates/area/motion count.
- Fixed PCB window: 10,880 green border pixels verified. Motion-disabled row: all 8,064 tested pixels equal the unmodified background.
- 29 further actual-RTL crop windows cover 19 algorithm modes, eight PCB states and both motion enable values. Crop galleries force only internal raster coordinates; before each crop, the real first line runs for 120 active clocks to exercise the decimal capture and conversion.
- 5,076 metadata checks cover mailbox frame/latency/valid and converted decimal frame consistency. First frame shows 65535 with 123.4ms, rather than stale 00000. Later tests cover frame 12 / 987.6ms, no-toggle retention, and an active-frame update to 31415 / 4.2ms that commits only in the next vertical blank.
- Final transcript: `02_sim/mixer_regression/simulation_final_v2.log`. Compile and simulation report zero errors and zero warnings. Input SHA256 manifest: `02_sim/mixer_regression/input_hashes.json`. Machine summary: `02_sim/mixer_regression/verification.json`.

## Screenshot provenance

`previews/osd_before_after_rtl.png`, `osd_19_modes_rtl.png`, `osd_8_pcb_states_rtl.png` and `osd_motion_gate_rtl.png` contain actual O_hdmi_data RGB pixels and actual font-ROM glyphs on synthetic backgrounds. They are not camera photographs. Baseline/new full frames are streamed without coordinate forcing; mode/state atlases use coordinate-forced crop scans as stated above. All four galleries were generated from the final v2 run; before/after and all eight PCB states were visually inspected.

## Earlier failures and correction

Version 1 exposed a real integration bug: decimal frame capture occurred before the latency mailbox committed during blanking, so the first screen could pair frame 00000 with 123.4ms. The main agent moved snapshot capture to active first-line pixel x=4. Version 2 adds explicit assertions and demonstrates the correction. Font body height and panel left inset also changed for v2.

The v1 source/output test evidence is archived in `02_sim/mixer_regression_v1_archive/`; earlier screenshots are in `previews/v1_rtl_archive/`. Failure chronology is in `02_sim/mixer_regression/FAILURE_HISTORY.md`. The initial private-RPC simulator crash and one testbench-failure transcript were overwritten before preservation was requested. Their tool-output reconstructions are explicitly marked as reconstructions. The original crash stack and original stale-mailbox failure transcript are retained where available; no reconstructed file is represented as an original log.

This simulation does not validate physical HDMI quality, camera scenes, sensor image processing, CNN accuracy, DDR stress or board-level network behavior. Final release still requires the independent build/resource/timing checks and actual-board verification.
