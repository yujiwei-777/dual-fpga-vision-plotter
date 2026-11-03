"""Negative evidence tests for the independent PH1P35 Slice capacity validator."""
import copy
import json
from pathlib import Path

import validate_device_capacity as v

HERE = Path(__file__).resolve().parent
DATASHEET = HERE / 'DS1300_logic_and_dram_excerpt.txt'
PLACEMENTS = HERE.parents[1] / 'readonly_pcb_window_20261027/readonly.sites.tsv'


def main():
    tiles, slots, compatible, expected, resource_proof = v.load_evidence(
        HERE / 'ph1_35p_device_dump.txt_chip', HERE / 'ph1_35p_device_dump.txt_connmngr',
        HERE / 'report_named_tiles.log', DATASHEET,
        HERE / 'expected_slice_cells.tsv', HERE / 'export_expected_slices.log', HERE / 'physical_device_resources.txt')
    rows = v.read_tsv(PLACEMENTS, ('cell', 'ref_name', 'is_placed', 'col', 'row', 'offset'))
    slice_indices = [i for i, row in enumerate(rows) if row['ref_name'] in v.MODELS]
    lidx = next(i for i in slice_indices if rows[i]['ref_name'] == v.L)
    midx = next(i for i in slice_indices if rows[i]['ref_name'] == v.M)
    second = next(i for i in slice_indices if i != lidx)
    result = []

    def check(name, changed, required_code=None, accepted=False):
        got, _ = v.validate_placement(changed, tiles, expected, compatible)
        codes = {e['code'] for e in got['errors']}
        passed = got['passed'] == accepted and (required_code is None or required_code in codes)
        result.append(dict(test=name, passed=passed, validator_passed=got['passed'], error_codes=sorted(codes)))
        if not passed:
            raise AssertionError(result[-1])

    check('current_complete_compatible_placement', rows, accepted=True)
    changed = copy.deepcopy(rows)
    changed[lidx].update(col='0', row='0')
    check('reject_non_logic_tile', changed, 'INVALID_SLOT')
    changed = copy.deepcopy(rows)
    changed[lidx]['offset'] = '8'
    check('reject_offset_8', changed, 'INVALID_SLOT')
    changed = copy.deepcopy(rows)
    changed[lidx]['offset'] = '-1'
    check('reject_negative_offset', changed, 'INVALID_SLOT')
    changed = copy.deepcopy(rows)
    changed[lidx]['col'] = 'not_a_coordinate'
    check('reject_non_integer_coordinate', changed, 'BAD_COORDINATE')
    changed = copy.deepcopy(rows)
    for key in ('col', 'row', 'offset'):
        changed[second][key] = changed[lidx][key]
    check('reject_duplicate_physical_slot', changed, 'DUPLICATE_SLOT')
    changed = copy.deepcopy(rows)
    pure = next(key for key, tile in tiles.items() if tile['tile_name'] == 'Plb')
    changed[midx].update(col=str(pure[0]), row=str(pure[1]), offset='0')
    check('reject_memory_model_in_pure_logic_tile', changed, 'INCOMPATIBLE_SLOT')
    changed = copy.deepcopy(rows)
    changed[lidx]['is_placed'] = '0'
    check('reject_unplaced_cell', changed, 'UNPLACED')
    changed = copy.deepcopy(rows)
    del changed[lidx]
    check('reject_missing_cell', changed, 'MISSING_CELLS')
    changed = copy.deepcopy(rows)
    changed.append(copy.deepcopy(changed[lidx]))
    check('reject_duplicate_cell_name', changed, 'DUPLICATE_CELL_NAME')
    changed = copy.deepcopy(rows)
    changed[lidx]['cell'] = 'unexpected_extra_cell'
    check('reject_replaced_netlist_identity', changed, 'MISSING_CELLS')
    changed = copy.deepcopy(rows)
    changed[lidx]['ref_name'] = v.M
    check('reject_model_substitution', changed, 'UNEXPECTED_CELL_OR_MODEL')
    changed = copy.deepcopy(rows)
    changed[lidx]['ref_name'] = 'unknown_model'
    check('reject_slice_disguised_as_other_model', changed, 'MISSING_CELLS')

    def bad_evidence(name, fn):
        try:
            fn()
        except v.EvidenceError as err:
            result.append(dict(test=name, passed=True, rejected_reason=str(err)))
        else:
            raise AssertionError(name + ' did not reject corrupt evidence')

    expected_rows = v.read_tsv(HERE / 'expected_slice_cells.tsv', ('cell', 'ref_name'))
    expected_log = (HERE / 'export_expected_slices.log').read_text()
    bad_evidence('reject_truncated_independent_netlist', lambda: v.parse_expected(expected_rows[:-1], expected_log))
    bad_evidence('reject_unfinished_independent_export', lambda: v.parse_expected(expected_rows, ''))
    bad_evidence('reject_other_device', lambda: v.parse_chip((HERE / 'ph1_35p_device_dump.txt_chip').read_text().replace('f0:ph1_35p ', 'f0:ph1_50p ', 1)))
    routing = (HERE / 'ph1_35p_device_dump.txt_connmngr').read_text()
    bad_evidence('reject_wrong_named_device_class', lambda: v.prove_named_routing_tiles(routing.replace('0:Plb ', '0:Pmb '), tiles))
    log = (HERE / 'report_named_tiles.log').read_text()
    bad_evidence('reject_missing_slot_evidence', lambda: v.prove_eight_slots(log.replace('Slot[8]', 'NotASlot[8]'), tiles))
    bad_evidence('reject_wrong_slot_type', lambda: v.prove_eight_slots(log.replace('type=157', 'type=158'), tiles))
    bad_evidence('reject_unproved_memory_compatibility', lambda: v.prove_model_compatibility(''))
    resource_text = (HERE / 'physical_device_resources.txt').read_text()
    bad_evidence('reject_wrong_official_lut_total', lambda: v.prove_resource_totals(resource_text.replace('21216', '5304'), tiles))
    bad_evidence('reject_wrong_distributed_ram_total', lambda: v.prove_resource_totals(resource_text.replace('2160,507', '2160,500'), tiles))

    report = dict(passed=all(t['passed'] for t in result), tests=len(result),
                  validator_sha256=v.sha(v.__file__), test_script_sha256=v.sha(__file__), results=result)
    (HERE / 'validator_negative_tests.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
