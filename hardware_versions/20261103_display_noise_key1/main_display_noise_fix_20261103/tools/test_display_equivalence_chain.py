"""Small adversarial fixtures; never alter real trial/build evidence."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import validate_display_equivalence_chain as audit
from display_noise_paths import obj, put, sha


class ChainTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.cases = {'tiny': (1, 1, 3, 1)}
        self.rtl = {}
        for number in (4, 5, 6):
            data = ('module a4_display_spatial_h1 #(parameter V=%d) (); endmodule\n' % number).encode()
            relative = ('01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v'
                        if number == 6 else 'reports/attempt%d_rtl/a4_display_spatial_h1.v' % number)
            p = self.write(relative, data)
            self.rtl[number] = (data, sha(p))
        reference = self.write('model/display_spatial_reference.py', b'# tiny reference\n')
        for stage, old, new, candidate in (
            ('combined', 4, 5, 'a4_display_spatial_combined.v'),
            ('nocarry', 5, 6, 'a4_display_spatial_nocarry.v'),
        ):
            folder = self.folder(stage)
            for name in audit.SOURCES[stage]:
                self.write(folder / name, ('# fixture ' + name + '\n').encode())
            self.write(folder / candidate, self.rtl[new][0])
            self.write(folder / 'a4_display_spatial_frozen.v', self.rtl[old][0].replace(
                b'module a4_display_spatial_h1 #(', b'module a4_display_spatial_frozen #('))
            compile_log = self.write(folder / 'compile.log', b'Top level modules:\nErrors: 0, Warnings: 0\n')
            inputs = {}
            for name in ('stim.mem', 'expected.mem', 'source.mem'):
                inputs[name] = sha(self.write(folder / 'tiny' / name, b'00\n'))
            exhaustive = ('PASS exhaustive RTL avg2 pairs=65536' if stage == 'combined' else
                          'PASS exhaustive RTL avg2 pairs=65536 TH16_byte_pairs=65536 TH16_rgb_channel_pairs=196608')
            transcript = self.write(folder / 'tiny/transcript.log', (
                exhaustive + '\nPASS pixel oracle WIDTH=1 HEIGHT=1 cycles=3 valid=1 sof=1 eol=1 '
                'all_markers_and_ENABLE0_checked frozen_all_cycles_including_invalid_data_equal\n'
                'Errors: 0, Warnings: 0\n').encode())
            put(folder / 'vectors_manifest.json', {
                'rtl_sha256': self.rtl[old][1], 'reference_sha256': sha(reference), 'edge_threshold': 16,
                'cases': [{'name': 'tiny', 'width': 1, 'height': 1, 'cycles': 3, 'source_pixels': 1, 'inputs': inputs}],
            })
            report = {
                'status': 'PASS', 'board_validation': 'NOT_RUN', 'candidate_sha256': self.rtl[new][1],
                'frozen_product_sha256': self.rtl[old][1], 'frozen_only_change': 'module name',
                'reference_sha256': sha(reference), 'compile_sha256': sha(compile_log),
                'total_cycles': 3, 'total_valid_pixels': 1,
                'cases': [{'name': 'tiny', 'width': 1, 'height': 1, 'cycles': 3, 'valid_pixels': 1,
                           'sof': 1, 'eol': 1, 'status': 'PASS', 'transcript_sha256': sha(transcript)}],
            }
            if stage == 'combined':
                control = {'status': 'PASS', 'cases': [
                    {'width': w, 'height': h, 'reachable_states': 1, 'transitions': 8,
                     'explicit_forwarding_required': w == 1, 'unmasked_collisions': int(w == 1)}
                    for w, h in ((1, 2), (1, 7), (2, 1), (2, 2), (2, 5), (3, 3), (7, 1), (7, 5), (16, 6))]}
                put(folder / 'control_invariant.json', control)
                report.update(rtl_avg2_exhaustive_pairs_per_case=65536, control_invariant=control)
            else:
                arithmetic = {'status': 'PASS', 'byte_pairs': 65536, 'accepted': 8176,
                              'source_sha256': {name: sha(folder / name) for name in ('close_byte_th16.vh', 'check_close_byte.py')}}
                put(folder / 'close_byte_check.json', arithmetic)
                report.update(independent_python_byte_pairs=65536, accepted_byte_pairs=8176,
                              per_case_exhaustive_rtl={'avg2_byte_pairs': 65536, 'th16_byte_pairs': 65536,
                                                       'th16_rgb_channel_pairs': 196608})
            report['source_sha256'] = {name: sha(folder / name) for name in audit.SOURCES[stage]}
            put(folder / 'verification.json', report)
        for key, value in [('CASES', self.cases)] + [('V%d' % number, self.rtl[number][1]) for number in (4, 5, 6)]:
            handle = patch.object(audit, key, value)
            handle.start()
            self.addCleanup(handle.stop)

    def write(self, path, data):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def folder(self, stage):
        return self.root / ('02_sim/display_noise_' + stage + '_trial')

    def update_report(self, change, stage='nocarry'):
        path = self.folder(stage) / 'verification.json'
        report = obj(path)
        change(report)
        put(path, report)

    def validate(self):
        return audit.validate(self.root)

    def test_complete_chain_and_binding(self):
        result = self.validate()
        self.assertTrue(result['passed'], result['errors'])
        self.assertTrue(audit.validate_binding({'input_hashes': result['evidence']}, result)['passed'])

    def test_broken_chain_rejected(self):
        self.update_report(lambda report: report.update(frozen_product_sha256=self.rtl[4][1]))
        self.assertFalse(self.validate()['passed'])

    def test_missing_expected_hash_rejected(self):
        self.update_report(lambda report: report.update(compile_sha256=None))
        self.assertFalse(self.validate()['passed'])

    def test_missing_and_stale_source_rejected(self):
        source = self.folder('nocarry') / 'close_byte_th16.vh'
        source.unlink()
        self.assertFalse(self.validate()['passed'])
        source.write_text('changed')
        self.assertFalse(self.validate()['passed'])

    def test_incomplete_cases_rejected(self):
        self.update_report(lambda report: report.update(cases=[]))
        self.assertFalse(self.validate()['passed'])

    def test_final_clean_summary_does_not_hide_errors(self):
        transcript = self.folder('nocarry') / 'tiny/transcript.log'
        transcript.write_bytes(b'** Error: earlier failure\n' + transcript.read_bytes())
        self.update_report(lambda report: report['cases'][0].update(transcript_sha256=sha(transcript)))
        self.assertFalse(self.validate()['passed'])

    def test_missing_exhaustive_marker_rejected(self):
        transcript = self.folder('nocarry') / 'tiny/transcript.log'
        transcript.write_bytes(b'\n'.join(transcript.read_bytes().split(b'\n')[1:]))
        self.update_report(lambda report: report['cases'][0].update(transcript_sha256=sha(transcript)))
        self.assertFalse(self.validate()['passed'])

    def test_missing_or_stale_binding_rejected(self):
        result = self.validate()
        self.assertTrue(result['passed'], result['errors'])
        regression = {'input_hashes': deepcopy(result['evidence'])}
        key = next(iter(regression['input_hashes']))
        del regression['input_hashes'][key]
        self.assertFalse(audit.validate_binding(regression, result)['passed'])
        regression['input_hashes'][key] = '0' * 64
        self.assertFalse(audit.validate_binding(regression, result)['passed'])
        result['passed'] = False
        self.assertFalse(audit.validate_binding({'input_hashes': result['evidence']}, result)['passed'])


if __name__ == '__main__':
    unittest.main()
