"""Reject unapproved Tcl changes and unproved actual synthesis parameters."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import verify_display_noise_build_strategy as audit


class BuildStrategyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base, self.run = self.root / 'base', self.root / 'run'
        self.run.mkdir()
        self.originals, self.current, hashes = {}, {}, {}
        for stage in ('synth', 'place', 'route'):
            original = self.base / audit.BASE_RUN / ('run_compact_' + stage + '.tcl')
            original.parent.mkdir(parents=True, exist_ok=True)
            raw = b'set area_option -packarea\r\nset device_name ph1_35p.db\r\n'
            raw += b'load_run_param -run syn_1\r\n# immutable vendor body\r\n'
            original.write_bytes(raw)
            hashes[stage] = audit.sha(original)
            current = self.run / ('run_display_noise_' + stage + '.tcl')
            if stage == 'synth':
                raw = raw.replace(b'set area_option -packarea\r\n',
                                  b'set area_option -packarea\r\n' + audit.AUTHORIZED_LINE + b'\r\n')
            current.write_bytes(raw)
            self.originals[stage], self.current[stage] = original, current
        patcher = patch.object(audit, 'BASE_SCRIPT_HASHES', hashes)
        patcher.start()
        self.addCleanup(patcher.stop)
        # Synthetic fixture, not a claim about which advanced rows TD exposes.
        self.goodlog = ''.join('RUN-1002 : start command "set_param %s %s %s"\n' % (step, name, value)
                               for step, name, value, _ in audit.PARAMETERS)
        for stage in ('rtl', 'gate'):
            self.goodlog += ('RUN-1002 : start command "commit_param -step %s"\n'
                             'RUN-1001 : Print %s Property\n') % (stage, stage.title())
            for step, name, value, default in audit.PARAMETERS:
                if step == stage:
                    default = default or 'auto'
                    self.goodlog += 'RUN-1001 : %s | %s | %s | %s\n' % (name, value, default, '*' if value != default else '')
            command = 'optimize_rtl' if stage == 'rtl' else 'optimize_gate -packarea out.area'
            self.goodlog += ('RUN-1002 : start command "%s"\n'
                             'RUN-1003 : finish command "%s" in 0s\n') % (command, command)
        (self.run / 'synth.log').write_text(self.goodlog, encoding='utf-8')
        (self.run / '.opt_gate.end.f').touch()

    def check(self, **kw):
        return audit.validate(self.run, self.base, **kw)['passed']

    def test_exact_authorized_change_passes(self):
        self.assertTrue(self.check())

    def test_missing_line_fails(self):
        self.current['synth'].write_bytes(self.originals['synth'].read_bytes())
        self.assertFalse(self.check())

    def test_duplicate_line_fails(self):
        p = self.current['synth']
        p.write_bytes(p.read_bytes() + audit.AUTHORIZED_LINE + b'\r\n')
        self.assertFalse(self.check())

    def test_extra_tcl_change_fails_for_every_stage(self):
        for p in self.current.values():
            raw = p.read_bytes()
            p.write_bytes(raw + b'set_param place anything on\r\n')
            self.assertFalse(self.check(), p.name)
            p.write_bytes(raw)

    def test_moved_authorized_line_fails(self):
        p = self.current['synth']
        p.write_bytes(self.originals['synth'].read_bytes() + audit.AUTHORIZED_LINE + b'\r\n')
        self.assertFalse(self.check())

    def test_line_whitespace_or_newline_changes_fail(self):
        p = self.current['synth']
        raw = p.read_bytes()
        for mutation in (raw.replace(audit.AUTHORIZED_LINE, b' ' + audit.AUTHORIZED_LINE),
                         raw.replace(b'\r\n', b'\n')):
            p.write_bytes(mutation)
            self.assertFalse(self.check())
        p.write_bytes(raw)

    def test_baseline_script_drift_fails(self):
        p = self.originals['place']
        p.write_bytes(p.read_bytes() + b'# changed\r\n')
        self.assertFalse(self.check())

    def test_snapshot_must_bind_all_actual_scripts(self):
        snapshot = {'files': [{'path': str(p), 'sha256': audit.sha(p)} for p in self.current.values()]}
        self.assertTrue(self.check(snapshot=snapshot))
        snapshot['files'].pop()
        self.assertFalse(self.check(snapshot=snapshot))

    def test_actual_successful_high_log_passes(self):
        self.assertTrue(self.check(require_log=True))

    def test_actual_log_setting_and_success_order_required(self):
        p = self.run / 'synth.log'
        optimize = self.goodlog.splitlines(keepends=True)[-2]
        for text in (self.goodlog.replace('high', 'medium'),
                     self.goodlog.replace('RUN-1003 : finish command', 'missing-success'),
                     self.goodlog + self.goodlog.splitlines(keepends=True)[0],
                     optimize + self.goodlog,
                     self.goodlog.replace('commit_param -step gate', 'commit_param -step rtl'),
                     self.goodlog.replace('Print Gate Property', 'Print RTL Property'),
                     self.goodlog.replace('pack_effort | high | medium | *', 'pack_effort | medium | medium |'),
                     self.goodlog.replace('pack_effort | high | medium | *', 'pack_effort | high | low | *'),
                     self.goodlog.replace('pack_effort | high | medium | *', 'pack_effort | high | medium |'),
                     self.goodlog + 'RUN-1001 : pack_effort | medium | medium |\n',
                     self.goodlog + 'RUN-1002 : start command "set_param -run syn_1 gate pack_effort medium"\n',
                     self.goodlog + 'RUN-1002 : start command "reset_params"\n',
                     self.goodlog + 'RUN-1002 : start command "load_run_param -run syn_1"\n',
                     self.goodlog + 'SYN-9999 ERROR: failure\n'):
            p.write_text(text, encoding='utf-8')
            self.assertFalse(self.check(require_log=True), text)

    def test_gate_table_order_cannot_be_forged(self):
        p = self.run / 'synth.log'
        commit = 'RUN-1002 : start command "commit_param -step gate"\n'
        row = 'RUN-1001 : map_mode | area_prior | auto | *\n'
        header = 'RUN-1001 : Print Gate Property\n'
        for text in (commit + self.goodlog.replace(commit, ''),
                     self.goodlog.replace(row, '') + row,
                     header + self.goodlog.replace(header, '')):
            p.write_text(text, encoding='utf-8')
            self.assertFalse(self.check(require_log=True))

    def test_area_mode_is_unique_exact_committed_and_not_overridden(self):
        p = self.run / 'synth.log'
        setting = 'RUN-1002 : start command "set_param gate map_mode area_prior"\n'
        row = 'RUN-1001 : map_mode | area_prior | auto | *\n'
        for text in (self.goodlog.replace(setting, ''), self.goodlog.replace(row, ''),
                     self.goodlog.replace('map_mode area_prior', 'map_mode area'),
                     self.goodlog.replace(row, 'RUN-1001 : map_mode | auto | auto |\n'),
                     self.goodlog.replace(row, 'RUN-1001 : map_mode | area_prior | auto |\n'),
                     self.goodlog + setting,
                     self.goodlog + 'RUN-1002 : start command "set_param -run syn_1 gate map_mode auto"\n',
                     self.goodlog.replace(setting, '') + setting,
                     self.goodlog.replace(setting, 'RUN-1002 : start command "set_param gate mode area"\n')):
            p.write_text(text, encoding='utf-8')
            self.assertFalse(self.check(require_log=True), text)

    def test_every_tuple_needs_one_exact_call(self):
        for step, name, value, _ in audit.PARAMETERS:
            line = 'RUN-1002 : start command "set_param %s %s %s"\n' % (step, name, value)
            for text in (self.goodlog.replace(line, ''), self.goodlog + line,
                         self.goodlog + 'RUN-1002 : start command "set_param %s %s wrong"\n' % (step, name)):
                self.assertFalse(audit.validate_log(text)['passed'], name)

    def test_advanced_rows_require_genuine_committed_evidence(self):
        for name in ('add_map_lut_struct', 'multi_thread_mapping', 'resource_sharing', 'shifter_style'):
            row = next(line for line in self.goodlog.splitlines(keepends=True) if line.startswith('RUN-1001 : ' + name + ' |'))
            self.assertFalse(audit.validate_log(self.goodlog.replace(row, ''))['passed'], name)

    def test_rtl_optimization_and_table_required(self):
        for text in (self.goodlog.replace('commit_param -step rtl', 'commit_param -step wrong'),
                     self.goodlog.replace('Print Rtl Property', 'Print Wrong Property'),
                     self.goodlog.replace('finish command "optimize_rtl"', 'missing rtl finish'),
                     self.goodlog.replace('set_param rtl shifter_style', 'set_param gate shifter_style')):
            self.assertFalse(audit.validate_log(text)['passed'])

    def test_official_strategy_document_is_hash_bound(self):
        with patch.object(audit, 'OFFICIAL_SHA256', '0' * 64):
            self.assertFalse(self.check())

    def test_completion_markers_are_required(self):
        (self.run / '.opt_gate.end.f').unlink()
        self.assertFalse(self.check(require_log=True))
        (self.run / '.opt_gate.end.f').touch()
        (self.run / '.opt_gate.error.f').touch()
        self.assertFalse(self.check(require_log=True))


if __name__ == '__main__':
    unittest.main()
