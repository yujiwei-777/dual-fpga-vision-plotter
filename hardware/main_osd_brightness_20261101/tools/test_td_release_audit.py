"""Safety regression for release-gate acceptance/rejection using TD report fixtures."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import time
import unittest

import td_release_audit as audit


class GateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.run = self.root / "run"
        self.run.mkdir()
        (self.root / "top.v").write_text("module top(input clk); endmodule\n")
        (self.run / "dut.al").write_text('''<Project><Source_Files><Verilog>
<File Path="../top.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/></FileInfo></File>
</Verilog></Source_Files></Project>''')
        self.args = type("Args", (), dict(root=self.root, run=self.run, name="dut", al=None,
            config=None, extra=None, snapshot=None, log=None, output=None, syn_run=None))()
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(audit.snapshot(self.args), 0)
        start = time.time_ns() + 1_000_000
        p = self.run / ".read_design.begin.f"
        p.touch()
        os.utime(p, ns=(start, start))
        (self.run / "dut_pr.timing").write_text('''Confidence : Routed
Check Corner : Both (Slow and Fast)
Slow | yes yes
Fast | yes yes
SWNS: 0.020ns, STNS: 0.000ns
HWNS: 0.020ns, HTNS: 0.000ns
''')
        (self.run / "dut_phy.area").write_text('''#slice 80 out of 100 80.00%
#eram 10 out of 100 10.00%
#dsp 94 out of 100 94.00%
''')
        (self.run / "route_flow.status").write_text("Timing Mode : final\n route | 1 | 1s\n")
        (self.run / "dut_pr.db").write_bytes(b"fixture database")
        (self.run / "td_fixture.log").write_text("RUN-1003 : finish command route\n")
        for name in ("dut_pr.timing", "dut_phy.area", "route_flow.status", "dut_pr.db"):
            os.utime(self.run / name, ns=(start + 1_000_000, start + 1_000_000))
        p = self.run / ".opt_route.end.f"
        p.touch()
        os.utime(p, ns=(start + 2_000_000, start + 2_000_000))

    def tearDown(self):
        self.tmp.cleanup()

    def gate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            value = audit.gate(self.args)
        return value, json.loads((self.run / "release_gate.json").read_text())

    def test_valid_dual_corner_result_passes(self):
        self.assertEqual(self.gate()[0], 0)

    def test_exact_resource_limit_rejected(self):
        p = self.run / "dut_phy.area"
        p.write_text(p.read_text().replace("94 out", "95 out"))
        code, result = self.gate()
        self.assertEqual(code, 1)
        self.assertTrue(any("requires <95%" in x for x in result["failures"]))

    def test_missing_rom_warning_rejected(self):
        (self.run / "td_fixture.log").write_text('HDL-5105 : Failed to open memory initialization file "x.mem"\n')
        self.assertEqual(self.gate()[0], 1)

    def test_source_changed_after_snapshot_rejected(self):
        (self.root / "top.v").write_text("module top; wire changed; endmodule\n")
        code, result = self.gate()
        self.assertEqual(code, 1)
        self.assertTrue(any("hashes differ" in x for x in result["failures"]))

    def test_single_corner_report_rejected(self):
        p = self.run / "dut_pr.timing"
        p.write_text(p.read_text().replace("Fast | yes yes", "Fast | no no"))
        self.assertEqual(self.gate()[0], 1)

    def test_old_route_marker_rejected(self):
        p = self.run / "dut_pr.db"
        old = (self.run / ".read_design.begin.f").stat().st_mtime_ns - 10_000_000
        os.utime(p, ns=(old, old))
        self.assertEqual(self.gate()[0], 1)

    def test_negative_hold_rejected(self):
        p = self.run / "dut_pr.timing"
        p.write_text(p.read_text().replace("HWNS: 0.020ns", "HWNS: -0.001ns"))
        self.assertEqual(self.gate()[0], 1)

    def test_retrospective_snapshot_rejected(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(audit.snapshot(self.args), 0)
        # Explicit future generation time guarantees evidence is retrospective.
        p = self.run / "source_snapshot.json"
        data = json.loads(p.read_text())
        data["generated_ns"] = (self.run / ".read_design.begin.f").stat().st_mtime_ns + 1
        p.write_text(json.dumps(data))
        self.assertEqual(self.gate()[0], 1)


if __name__ == "__main__":
    unittest.main()
