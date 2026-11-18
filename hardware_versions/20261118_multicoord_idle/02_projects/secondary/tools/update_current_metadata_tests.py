from pathlib import Path
root=Path(__file__).resolve().parents[1]
for rel in ('tests/paper_eject/tb_operator_metadata.sv','tests/operator_ui/tb_operator_metadata.sv'):
    p=root/rel;s=p.read_text()
    s=s.replace('task step;', 'defparam dut.u_key1_action.DEBOUNCE_CYCLES=2;\ndefparam dut.u_key1_action.LONG_PRESS_CYCLES=40;\ntask step;')
    s=s.replace('@(negedge clk);key1_n=1;\nend endtask','@(negedge clk);key1_n=1;\n    repeat(8)step;\nend endtask')
    # Progress tests drive real owner fields; default tie-offs keep the
    # original preview, snapshot, session and maintenance assertions intact.
    s=s.replace('force dut.copy_operator_acked=0;',
        'force dut.copy_operator_acked=0;force dut.copy_total_lines=0;force dut.copy_total_valid=0;force dut.copy_airwalk_active=0;')
    s=s.replace('force dut.report_lines=0;',
        'force dut.report_total_lines=0;force dut.report_total_valid=0;force dut.report_airwalk_active=0;force dut.report_lines=0;')
    s=s.replace('force dut.key1_report_pulse=1\'b1;','force dut.key1_report_pulse=1\'b1;force dut.key1_report_action=1\'b1;')
    s=s.replace('force dut.key1_report_pulse=1\'b0;','force dut.key1_report_pulse=1\'b0;force dut.key1_report_action=1\'b0;')
    p.write_text(s)
