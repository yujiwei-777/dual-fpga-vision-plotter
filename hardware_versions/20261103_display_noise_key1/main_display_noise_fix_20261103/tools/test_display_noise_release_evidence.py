"""Adversarial evidence-completeness tests. No real build files are changed."""
from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
import review_display_noise_release as audit

class EvidenceTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.inputs={}
        for rel in audit.REQUIRED_CURRENT_RTL:
            p=self.root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(rel); self.inputs[str(p)]=audit.sha(p)
        for rel in audit.REQUIRED_ALGORITHM_INPUTS:
            p=self.root/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(rel);self.inputs[str(p)]=audit.sha(p)
        self.logs=[]
        for rel,marker in audit.REQUIRED_REGRESSION_LOGS.items():
            p=self.root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(marker+'\nErrors: 0, Warnings: 0\n'); self.inputs[str(p)]=audit.sha(p); self.logs.append(str(p))
        self.reg={'passed':True,'checks':{k:True for k in audit.REQUIRED_REGRESSION_CHECKS},'input_hashes':self.inputs,'logs':self.logs}
        self.snapshot={'files':[{'path':p,'sha256':h} for p,h in self.inputs.items() if Path(p).suffix=='.v']}
    def verify(self,reg=None,snapshot=None):
        return audit.validate_regression(reg or self.reg,self.root,snapshot or self.snapshot)
    def test_complete_evidence_passes(self): self.assertTrue(self.verify()['passed'])
    def test_single_arbitrary_check_rejected(self):
        x=deepcopy(self.reg); x['checks']={'some_check':True}; self.assertFalse(self.verify(x)['passed'])
    def test_each_required_check_cannot_be_removed(self):
        for key in audit.REQUIRED_REGRESSION_CHECKS:
            x=deepcopy(self.reg); del x['checks'][key]; self.assertFalse(self.verify(x)['passed'],key)
    def test_check_truthy_string_rejected(self):
        x=deepcopy(self.reg); x['checks']['document_type15']='true'; self.assertFalse(self.verify(x)['passed'])
    def test_each_required_rtl_hash_cannot_be_removed(self):
        for rel in audit.REQUIRED_CURRENT_RTL:
            x=deepcopy(self.reg); del x['input_hashes'][str(self.root/rel)]; self.assertFalse(self.verify(x)['passed'],rel)
    def test_each_required_algorithm_hash_cannot_be_removed(self):
        for rel in audit.REQUIRED_ALGORITHM_INPUTS:
            x=deepcopy(self.reg);del x['input_hashes'][str(self.root/rel)]
            self.assertFalse(self.verify(x)['passed'],rel)
    def test_stale_current_rtl_hash_rejected(self):
        (self.root/audit.REQUIRED_CURRENT_RTL[0]).write_text('changed'); self.assertFalse(self.verify()['passed'])
    def test_each_required_log_cannot_be_removed(self):
        for path in self.logs:
            x=deepcopy(self.reg); x['logs'].remove(path); self.assertFalse(self.verify(x)['passed'],path)
    def test_unbound_log_rejected(self):
        x=deepcopy(self.reg); del x['input_hashes'][self.logs[0]]; self.assertFalse(self.verify(x)['passed'])
    def test_forged_success_flag_without_log_marker_rejected(self):
        p=Path(self.logs[0]); p.write_text('Errors: 0, Warnings: 0\n'); self.reg['input_hashes'][str(p)]=audit.sha(p); self.assertFalse(self.verify()['passed'])
    def test_final_clean_summary_cannot_hide_earlier_error(self):
        for adverse in ['** Error: earlier failure', '** Fatal: stopped',
                        'Errors: 1, Warnings: 0', 'Errors: 0, Warnings: 2']:
            p=Path(self.logs[0]);p.write_text(adverse+'\n'+audit.REQUIRED_REGRESSION_LOGS[next(iter(audit.REQUIRED_REGRESSION_LOGS))]+'\nErrors: 0, Warnings: 0\n')
            self.reg['input_hashes'][str(p)]=audit.sha(p)
            self.assertFalse(self.verify()['passed'],adverse)
    def test_contract_recomputed_value_must_match(self):
        old={'passed':True,'generated_utc':'old','dependencies':[{'path':'top.v','sha256':'A'}]}
        new=deepcopy(old);new['generated_utc']='new'
        self.assertTrue(audit.validate_contract_report(old,new)['passed'])
        new['dependencies'][0]['sha256']='B'
        self.assertFalse(audit.validate_contract_report(old,new)['passed'])
    def test_matching_failed_contract_is_rejected(self):
        self.assertFalse(audit.validate_contract_report({'passed':False},{'passed':False})['passed'])
    def test_tested_rtl_must_match_build_snapshot(self):
        x=deepcopy(self.snapshot); x['files'][0]['sha256']='0'*64; self.assertFalse(self.verify(snapshot=x)['passed'])
    def make_gate(self):
        run=self.root/'run'; run.mkdir(); name='main'
        gate={'passed':True,'bitgen_allowed':True,'failures':[],'run':str(run),'name':name,'snapshot':str(run/'source_snapshot.json'),'evidence':{}}
        names=[name+'_pr.timing',name+'_phy.area','route_flow.status','.opt_route.end.f','.read_design.begin.f',name+'_pr.db','synth.log','place.log','route.log']
        for value in names:
            p=run/value; p.write_text(value); gate['evidence'][value]={'sha256':audit.sha(p),'mtime_ns':p.stat().st_mtime_ns}
        return gate,run,name
    def test_complete_gate_evidence_passes(self):
        x,run,name=self.make_gate(); self.assertTrue(audit.validate_gate_evidence(x,run,name)['passed'])
    def test_gate_pass_flag_alone_rejected(self):
        x,run,name=self.make_gate(); x['evidence']={}; self.assertFalse(audit.validate_gate_evidence(x,run,name)['passed'])
    def test_each_gate_evidence_cannot_be_removed(self):
        x,run,name=self.make_gate()
        for key in x['evidence']:
            other=deepcopy(x); del other['evidence'][key]; self.assertFalse(audit.validate_gate_evidence(other,run,name)['passed'],key)
    def test_routed_db_drift_rejected(self):
        x,run,name=self.make_gate(); (run/(name+'_pr.db')).write_text('changed'); self.assertFalse(audit.validate_gate_evidence(x,run,name)['passed'])

if __name__=='__main__': unittest.main()
