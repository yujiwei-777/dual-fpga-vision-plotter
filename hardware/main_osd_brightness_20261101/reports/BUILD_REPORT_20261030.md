# 主板中文紧凑 OSD v2 构建报告

{
  "bit": "D:\\program\\fpga\\lab_ex3_osd_SC500_720P\\main_osd_chinese_compact_20261030\\artifacts\\dual_fpga_main_20261030_osd_chinese_compact_diagnostic.bit",
  "sha256": "7733B6D65811E01C6A07CBA90C54884053B5872B090CCA26ED1B18990321DB06",
  "bytes": 1789547,
  "hardware_status": "NOT_RUN",
  "release_review": "D:\\program\\fpga\\lab_ex3_osd_SC500_720P\\main_osd_chinese_compact_20261030\\reports\\release_decision.json",
  "baseline_bit_unchanged": true,
  "functional_scope": "Display-only OSD/font/layout changes; camera/ISP, motion/CNN/PCB/document-copy/HXA1/DDR/protocol and secondary board unchanged.",
  "timing": {
    "setup_WNS_ns": 0.306,
    "setup_TNS_ns": 0.0,
    "hold_WNS_ns": 0.02,
    "hold_TNS_ns": 0.0
  },
  "resources": {
    "slice": "19741/21216 (93.05%)",
    "ERAM": "90/108 (83.33%)",
    "DSP": "37/40 (92.50%)"
  },
  "simulation": "PASS: 7 frames, 6,451,200 pixels, 5,619,034 outside OSD regions equal, 5,076 metadata checks, 0 errors/warnings",
  "notes": [
    "Raw generic check_design RUN-8007/lslices exceed capacity retained; same diagnostic exists in successful baseline and physical Slice inventory/PLB/routing DRC/standard bitgen passed.",
    "Raw standalone check_io USR-8450 10/39 retained; unchanged standard project context, all 30 ordinary ADC assignments and 79 physical IO entries independently match, standard bitgen succeeded without unconstr_io override.",
    "DRC contains only SLATR-1036 NOTE x24 and SLATR-1038 NOTE x80.",
    "RTCLK-5078 and USR-6113 absent.",
    "No board validation performed."
  ]
}
