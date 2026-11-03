import unittest
from strict_release_review import check_design, check_drc, check_simple_command, KNOWN_CAPACITY

CAP = 'RUN-1002 : start command "check_design"\nRUN-1001 : lslices exceed capacity\n' + KNOWN_CAPACITY + '\nRAW_CHECK_DESIGN_STATUS=1 REASON=\nRUN-1002 : start command "check_io"\n'
DRC = '''1. REPORT SUMMARY
 Violations found : 2
| SLATR-1036 | NOTE | slice attr check ... | 1 |
| SLATR-1038 | NOTE | slice attr check ... | 1 |
2. REPORT DETAILS
SLATR-1036#1 NOTE
slice attr check ...
Found mslice name connecting to no used ce.
SLATR-1038#1 NOTE
slice attr check ...
Found mslice name getting ce attributes.
'''


class StrictReviewTests(unittest.TestCase):
    def test_known_failure_only_with_site_proof(self):
        self.assertTrue(check_design(CAP, True)['passed'])
        self.assertFalse(check_design(CAP, False)['passed'])

    def test_second_error_rejected(self):
        bad = CAP.replace('RAW_CHECK', 'USR-9999 ERROR: another legality error\nRAW_CHECK')
        self.assertFalse(check_design(bad, True)['passed'])

    def test_other_capacity_text_rejected(self):
        self.assertFalse(check_design(CAP.replace('lslices exceed capacity', 'mslices exceed capacity'), True)['passed'])

    def test_success_with_error_rejected(self):
        log = 'RUN-1002 : start command "check_design"\nUSR-9999 ERROR: hidden\nRAW_CHECK_DESIGN_STATUS=0 REASON=\n'
        self.assertFalse(check_design(log, True)['passed'])

    def test_nonadjacent_known_error_rejected(self):
        self.assertFalse(check_design(CAP.replace(KNOWN_CAPACITY, 'RUN-1001 : something else\n' + KNOWN_CAPACITY), True)['passed'])

    def test_nonwhite_drc_rejected(self):
        self.assertTrue(check_drc(DRC)['passed'])
        self.assertFalse(check_drc(DRC.replace('SLATR-1038', 'USR-6113'))['passed'])

    def test_drc_counts_strict(self):
        self.assertFalse(check_drc(DRC.replace('Violations found : 2', 'Violations found : 3'))['passed'])
        self.assertFalse(check_drc(DRC.replace('SLATR-1036#1', 'SLATR-1036#2'))['passed'])
        self.assertFalse(check_drc(DRC.replace('slice attr check ... | 1', 'slice attr check ... | 2', 1))['passed'])

    def test_unparsed_adverse_drc_rejected(self):
        self.assertFalse(check_drc(DRC + 'Unexpected ERROR: hidden in free text\n')['passed'])
        self.assertFalse(check_drc(DRC + 'FOO-1234#oops ERROR\n')['passed'])

    def test_io_catch_zero_cannot_hide_critical_warning(self):
        good = 'RUN-1002 : start command "check_io"\nCHECK_IO_STATUS=0 REASON=\n'
        self.assertTrue(check_simple_command(good, 'check_io', 'CHECK_IO_STATUS')['passed'])
        bad = good.replace('CHECK_IO_STATUS', 'USR-8450 CRITICAL-WARNING: unconstraint IOs\nCHECK_IO_STATUS')
        self.assertFalse(check_simple_command(bad, 'check_io', 'CHECK_IO_STATUS')['passed'])


if __name__ == '__main__':
    unittest.main()
