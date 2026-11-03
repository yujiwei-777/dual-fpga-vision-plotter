"""Reject unapproved Tcl changes and unproved actual synthesis parameters."""
from pathlib import Path
import json
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

    def readback_fixture(self):
        """Synthetic fixture only: no execution or claim about actual TD output."""
        folder = self.root / 'readback'
        folder.mkdir()
        self.receipt = folder / 'actual_readback_run_v2.json'
        self.db = self.run / (audit.NAME + '_gate.db')
        self.db.write_bytes(b'synthetic completed gate DB for a unit test')
        self.query_script = folder / 'read_v8_parameters.tcl'
        self.query_script.write_text('set input_db {%s}\n# synthetic hash-pinned fixture; not executed\n' % self.db.as_posix())
        patcher = patch.object(audit, 'READBACK_TCL_SHA256', audit.sha(self.query_script))
        patcher.start()
        self.addCleanup(patcher.stop)
        self.query_log = folder / 'console_readback_v2.log'
        device = 'import_device ph1_35p.db -package PH1P35MDG324 -speed 3'
        imported = 'import_db ' + self.db.as_posix()
        self.query_goodlog = ('PARAM_READBACK_INPUT_DB=%s\nPARAM_READBACK_INPUT_BYTES=%d\n'
                              'RUN-1002 : start command "%s"\nRUN-1003 : finish command "%s"\n'
                              'RUN-1002 : start command "%s"\n'
                              'RUN-1002 : start command "set_param gate opt_area high"\n'
                              'RUN-1003 : finish command "%s"\n') % (
                                  self.db.as_posix(), self.db.stat().st_size, device, device, imported, imported)
        for stage, name, value, _ in audit.PARAMETERS:
            self.query_goodlog += ('RUN-1002 : start command "get_param %s %s"\n'
                                   'PARAM_READBACK_VALUE|%s|%s|%s\n') % (stage, name, stage, name, value)
        self.query_goodlog += ('PARAM_READBACK_QUERY_MATCHES=6\n'
                               'PARAM_READBACK_SCOPE=DB settings queried after import; this is not a new synthesis run or a physical acceptance gate\n')
        self.query_log.write_text(self.query_goodlog)
        self.rebind_readback()
        # Public rows remain; only four missing advanced rows need the query.
        self.hidden_log = ''.join(line for line in self.goodlog.splitlines(keepends=True)
                                  if not any(line.startswith('RUN-1001 : ' + name + ' |')
                                             for _, name, _, default in audit.PARAMETERS if default is None))
        (self.run / 'synth.log').write_text(self.hidden_log)

    def rebind_readback(self, **mutations):
        receipt = {'db': str(self.db), 'db_sha256_before': audit.sha(self.db),
                   'db_sha256_after': audit.sha(self.db), 'db_unchanged': True,
                   'script': str(self.query_script), 'script_sha256': audit.sha(self.query_script),
                   'script_unchanged': True, 'log': str(self.query_log),
                   'log_sha256': audit.sha(self.query_log), 'process_exit_code': 0,
                   'readback_query_pass_marker': True}
        receipt.update(mutations)
        self.receipt.write_text(json.dumps(receipt))

    def readback_check(self):
        return audit.validate(self.run, self.base, require_log=True, readback_receipt=self.receipt)

    def test_real_bound_readback_can_replace_only_missing_hidden_rows(self):
        self.readback_fixture()
        result = self.readback_check()
        self.assertTrue(result['passed'], result['errors'])
        self.assertEqual(len(result['actual_synthesis_log_review']['advanced_rows_proved_by_readback']), 4)
        self.assertEqual(result['independent_parameter_readback']['receipt_sha256'], audit.sha(self.receipt))

    def test_readback_does_not_replace_public_or_wrong_existing_rows(self):
        self.readback_fixture()
        p = self.run / 'synth.log'
        for name in ('map_mode', 'pack_effort'):
            row = next(line for line in self.hidden_log.splitlines(keepends=True)
                       if line.startswith('RUN-1001 : ' + name + ' |'))
            p.write_text(self.hidden_log.replace(row, ''))
            self.assertFalse(self.readback_check()['passed'], name)
        p.write_text(self.hidden_log + 'RUN-1001 : shifter_style | wrong | auto | *\n')
        self.assertFalse(self.readback_check()['passed'])

    def test_readback_rejects_wrong_missing_duplicate_or_reordered_actual_values(self):
        self.readback_fixture()
        first = 'PARAM_READBACK_VALUE|gate|add_map_lut_struct|high\n'
        second = 'PARAM_READBACK_VALUE|gate|map_mode|area_prior\n'
        for text in (self.query_goodlog.replace(first, first.replace('|high', '|off')),
                     self.query_goodlog.replace(first, ''), self.query_goodlog + first,
                     self.query_goodlog.replace(first, '__FIRST__\n').replace(second, first).replace('__FIRST__\n', second),
                     self.query_goodlog + 'PARAM_READBACK_VALUE|gate|unknown|high\n'):
            self.query_log.write_text(text)
            self.rebind_readback()  # New hashes/true flags cannot certify false content.
            self.assertFalse(self.readback_check()['passed'], text)

    def test_readback_rejects_missing_duplicate_or_late_queries(self):
        self.readback_fixture()
        command = 'RUN-1002 : start command "get_param gate add_map_lut_struct"\n'
        value = 'PARAM_READBACK_VALUE|gate|add_map_lut_struct|high\n'
        for text in (self.query_goodlog.replace(command, ''), self.query_goodlog + command,
                     value + self.query_goodlog.replace(value, ''),
                     self.query_goodlog.replace(command, '') + command,
                     self.query_goodlog.replace(command, command.replace('get_param gate', 'get_param rtl'))):
            self.query_log.write_text(text)
            self.rebind_readback()
            self.assertFalse(self.readback_check()['passed'])

    def test_readback_exact_final_markers_and_diagnostics_are_checked(self):
        self.readback_fixture()
        marker = 'PARAM_READBACK_QUERY_MATCHES=6\n'
        for text in (self.query_goodlog.replace(marker, ''), self.query_goodlog + marker,
                     self.query_goodlog.replace(marker, 'PARAM_READBACK_QUERY_MATCHES=5\n'),
                     marker + self.query_goodlog.replace(marker, ''),
                     self.query_goodlog.replace('PARAM_READBACK_SCOPE=', 'missing-scope='),
                     self.query_goodlog + 'PARAM_READBACK_MISMATCH|gate|map_mode|auto\n',
                     self.query_goodlog + 'SYN-9999 ERROR: real failure\n',
                     self.query_goodlog + 'PARAM_READBACK_API_UNAVAILABLE=get_param\n'):
            self.query_log.write_text(text)
            self.rebind_readback()
            self.assertFalse(self.readback_check()['passed'])

    def test_readback_database_paths_sizes_and_current_hash_are_bound(self):
        self.readback_fixture()
        for mutations in ({'db': str(self.root / 'another_gate.db')},
                          {'db_sha256_before': '0' * 64}, {'db_sha256_after': '0' * 64}):
            self.rebind_readback(**mutations)
            self.assertFalse(self.readback_check()['passed'])
        self.rebind_readback()
        self.db.write_bytes(self.db.read_bytes() + b'drift')
        self.assertFalse(self.readback_check()['passed'])
        self.rebind_readback()
        self.assertFalse(self.readback_check()['passed'])  # Original log's size still differs.

    def test_readback_script_is_pinned_not_just_receipt_hash(self):
        self.readback_fixture()
        self.query_script.write_text(self.query_script.read_text() + '\nputs PARAM_READBACK_QUERY_MATCHES=6\n')
        self.rebind_readback()
        self.assertFalse(self.readback_check()['passed'])

    def test_readback_raw_log_hash_and_expected_file_paths_are_bound(self):
        self.readback_fixture()
        self.query_log.write_text(self.query_goodlog + '\n')
        self.assertFalse(self.readback_check()['passed'])
        for mutations in ({'log': str(self.root / 'foreign.log')},
                          {'script': str(self.root / 'foreign.tcl')}, {'log_sha256': '0' * 64}):
            self.rebind_readback(**mutations)
            self.assertFalse(self.readback_check()['passed'])

    def test_readback_passed_flag_or_claimed_success_cannot_substitute_evidence(self):
        self.readback_fixture()
        self.receipt.write_text(json.dumps({'passed': True}))
        self.assertFalse(self.readback_check()['passed'])
        for mutations in ({'process_exit_code': 1}, {'process_exit_code': False},
                          {'db_unchanged': False}, {'script_unchanged': False},
                          {'readback_query_pass_marker': False}):
            self.rebind_readback(**mutations)
            self.assertFalse(self.readback_check()['passed'])

    def test_readback_import_must_be_exact_successful_once_and_before_queries(self):
        self.readback_fixture()
        end = 'RUN-1003 : finish command "import_db ' + self.db.as_posix() + '"\n'
        for text in (self.query_goodlog.replace(end, ''), self.query_goodlog + end,
                     self.query_goodlog.replace('import_db ' + self.db.as_posix(), 'import_db other.db'),
                     self.query_goodlog.replace(end, '') + end):
            self.query_log.write_text(text)
            self.rebind_readback()
            self.assertFalse(self.readback_check()['passed'])

    def test_readback_no_mutation_reload_or_nested_parameter_override(self):
        self.readback_fixture()
        for command in ('set_param gate map_mode area_prior', 'set_param gate opt_area high',
                        'reset_params', 'load_run_param -run syn_1', 'export_db changed.db', 'optimize_gate'):
            self.query_log.write_text(self.query_goodlog + 'RUN-1002 : start command "' + command + '"\n')
            self.rebind_readback()
            self.assertFalse(self.readback_check()['passed'], command)
        nested = 'RUN-1002 : start command "set_param gate opt_area high"\n'
        self.query_log.write_text(self.query_goodlog.replace(nested, nested + nested))
        self.rebind_readback()
        self.assertFalse(self.readback_check()['passed'])

    def test_readback_does_not_relax_synth_setting_order_or_stage_completion(self):
        self.readback_fixture()
        p = self.run / 'synth.log'
        setting = 'RUN-1002 : start command "set_param rtl shifter_style shifter_reg"\n'
        for text in (self.hidden_log.replace(setting, '') + setting,
                     self.hidden_log.replace('finish command "optimize_rtl"', 'missing-completion'),
                     self.hidden_log + 'RUN-1002 : start command "reset_params"\n'):
            p.write_text(text)
            self.assertFalse(self.readback_check()['passed'])


if __name__ == '__main__':
    unittest.main()
