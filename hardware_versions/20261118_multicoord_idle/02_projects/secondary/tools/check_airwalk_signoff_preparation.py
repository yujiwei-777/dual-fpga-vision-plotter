"""Read-only preparation checks; does not invoke TD or create release PASS."""
from pathlib import Path
from unittest.mock import patch
import argparse, copy, math
import signoff_airwalk as s

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, default=Path(s.CONFIG['build']))
    args = parser.parse_args()
    run = args.run.resolve()
    out = s.report_dir(run)
    rows = []
    def accept(name, function):
        function()
        rows.append(dict(check=name, result='PASS_CHECK'))
    def reject(name, function):
        try:
            function()
        except (RuntimeError,ValueError,AssertionError) as exc:
            rows.append(dict(check=name, result='EXPECTED_REJECTION', reason=str(exc)))
        else:
            raise AssertionError(name+' was not rejected')
    # Preparing against the real freeze must not reach any subprocess call.
    with patch.object(s.subprocess,'run', side_effect=AssertionError('Preparation attempted subprocess')):
        accept('prepare_does_not_run_TD', lambda:s.prepare(run))
    control = Path(s.CONFIG['frozen'])
    actual = s.read(control/'logs/route.log')
    parsed = s.route_drc(actual)
    accept('historical_final_named_eight_checkers_parse_only', lambda:s.route_drc(actual))
    final = parsed['checkers'][-1]['stage']
    reject('missing_final_checker_end', lambda:s.route_drc(actual.replace('End Stage '+final+' | Run Bound Checker;', 'REMOVED_END_BOUND;')))
    reject('adverse_final_checker', lambda:s.route_drc(actual.replace('Stage '+final+' | Run Bound Checker\n', 'Stage '+final+' | Run Bound Checker\nERROR: injected negative test\n')))
    # Use current-format device report text as parser input; thresholds are
    # independently moved to the exact forbidden boundary in memory only.
    area = s.read(control/'signoff/readonly/readonly.area')
    for resource,limit in [('slice',95),('eram',90),('dsp',95)]:
        changed = s.re.sub(r'(^#'+resource+r'\s+)\d+(\s+out of\s+)(\d+)',
            lambda m:m[1]+str(math.ceil(int(m[3])*limit/100))+m[2]+m[3],area,flags=s.re.M|s.re.I)
        assert not s.legacy.strict.check_area(changed)['passed']
        rows.append(dict(check='strict_'+resource+'_threshold_rejects_boundary', result='EXPECTED_REJECTION'))
    timing = s.read(control/'signoff/readonly/readonly.timing')
    for key in ['SWNS','HWNS','STNS','HTNS']:
        changed = s.re.sub(r'\b'+key+r':\s*[-+\d.]+ns',key+': -0.001ns',timing)
        assert not s.legacy.strict.check_timing(changed)['passed']
        rows.append(dict(check='negative_'+key+'_rejects', result='EXPECTED_REJECTION'))
    gate_path = out/'FUNCTIONAL_GATE.json'
    accept('actual_receipt_tree_and_changed_source_coverage',lambda:s.functional_gate(run,gate_path))
    gate = s.load(gate_path)
    original_load = s.load
    changed = copy.deepcopy(gate)
    manifest = s.load(run/'SOURCE_MANIFEST.json')['files']
    group = changed['groups']['doc_total_ack']['source_sha256']
    extra = next(rel for rel in manifest if rel.startswith('01_rtl/') and rel not in group)
    group[extra] = manifest[extra]['sha256']
    with patch.object(s,'load',side_effect=lambda p:changed if Path(p).resolve()==gate_path.resolve() else original_load(p)):
        reject('gate_cannot_invent_current_source_coverage',lambda:s.functional_gate(run,gate_path))
    failed = sorted((s.ROOT/'reports/preserved_airwalk_r4').glob('*/RESULTS.json'))
    failed = [p for p in failed if original_load(p).get('status')=='FAIL']
    assert failed, 'Retained historical failed suite needed for negative selection test'
    reject('old_FAILED_preserved_receipt_rejected',lambda:s.receipt_evidence(run,failed[0]))
    warning_review=s.implementation_warnings(run)
    assert len(warning_review['pending_site_proof'])==2 and not warning_review['passed']
    rows.append(dict(check='two_PHY7027_retained_and_require_current_site_proof',result='EXPECTED_REJECTION'))
    original_read=s.read
    place=run/'logs/place.log'
    with patch.object(s,'read',side_effect=lambda p:original_read(p).replace('(SLICEL)','(UNKNOWN_MODEL)') if Path(p)==place else original_read(p)):
        assert s.implementation_warnings(run)['policy_blockers']
        rows.append(dict(check='unknown_PHY7027_variant_blocks',result='EXPECTED_REJECTION'))
    with patch.object(s,'read',side_effect=lambda p:original_read(p)+'\nPHY-9002 ERROR: injected negative test\n' if Path(p)==place else original_read(p)):
        assert s.implementation_warnings(run)['policy_blockers']
        rows.append(dict(check='PHY9002_never_waived',result='EXPECTED_REJECTION'))
    # Exercise the independent site validator with historical placement data
    # solely as a parser/rejection fixture; no current placement PASS is issued.
    cap=s.module('capacity_negative_fixture',run/'tools/physical_capacity/validate_device_capacity.py')
    static=run/'tools/physical_capacity'
    audit=control/'signoff/readonly'
    tiles,slots,compatibility,expected,resource=cap.load_evidence(
        static/'ph1_35p_device_dump.txt_chip',static/'ph1_35p_device_dump.txt_connmngr',
        audit/'console_readonly.log',static/'DS1300_logic_and_dram_excerpt.txt',
        audit/'expected_slice_cells.tsv',audit/'console_readonly.log',static/'physical_device_resources.txt')
    site_rows=cap.read_tsv(audit/'readonly.sites.tsv',('cell','ref_name','is_placed','col','row','offset'))
    indices=[i for i,row in enumerate(site_rows) if row['ref_name'] in cap.MODELS]
    for label in ['duplicate','unplaced','missing']:
        changed=copy.deepcopy(site_rows)
        if label=='duplicate':
            for key in ['col','row','offset']:
                changed[indices[0]][key]=changed[indices[1]][key]
            code='DUPLICATE_SLOT'
        elif label=='unplaced':
            changed[indices[0]]['is_placed']='0';code='UNPLACED'
        else:
            changed.pop(indices[0]);code='MISSING_CELLS'
        result,_=cap.validate_placement(changed,tiles,expected,compatibility)
        assert not result['passed'] and any(row['code']==code for row in result['errors'])
        rows.append(dict(check='capacity_rejects_'+label+'_slice',result='EXPECTED_REJECTION'))
    if not (run/'runs/phy_1/.opt_route.end.f').is_file():
        with patch.object(s.subprocess,'run',side_effect=AssertionError('Pre-route gate attempted TD')):
            reject('pre_route_prebitgen_rejected_without_TD',lambda:s.prebitgen(run,gate_path))
    s.put(out/'TOOL_SELF_CHECK.json',dict(status='PASS_PREPARATION_CHECKS_ONLY', checks=rows,
        tool=s.evidence(Path(s.__file__)), self_check=s.evidence(Path(__file__)),
        bitgen_invoked=False, TD_invoked=False, bitgen_allowed=False, hardware_status='NOT_RUN',
        scope='Preparation/source binding and rejection checks only. Historical logs are parser fixtures, not current route acceptance.'))
    print('PREPARATION_CHECKS_PASS count='+str(len(rows)))

if __name__=='__main__':
    main()
