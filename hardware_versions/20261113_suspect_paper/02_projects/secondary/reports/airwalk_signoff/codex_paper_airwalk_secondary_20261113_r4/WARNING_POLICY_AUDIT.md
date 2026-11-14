# Read-only warning policy audit

Observed diagnostics are retained; current physical acceptance has not been independently established by this audit. No TD command, read-only DB import or bitgen was invoked.

The current place log contains identical `PHY-7027 CRITICAL-WARNING: Base field: model type (SLICEL) execeed the design limits.` messages at lines 33945 and 33980, during GP Phase 3/4. The r3_seed2 place log has the same messages. The current `legal = 38420 / 38420` and `There are no illegal insts` intermediate messages are useful flow observations but do not establish final resource/site legality.

The review found that the generic `td_release_audit.py` tracked-warning regex omitted PHY-7027, while the final legacy physical review already demanded complete Slice enumeration, exact area-count correspondence and independent compatible unique site/capacity validation. The wrapper now explicitly binds each exact PHY-7027 message to that current proof. It keeps each phase, log, line number and original message. Unknown PHY-7027 variants, any PHY-9002, and other unreviewed critical warnings block signoff. Before physical proof, these two messages remain pending even when route exits zero.

The capacity proof checks every expected L/M Slice name/model, placed status, valid device tile/offset, allowed LSLICE/MSLICE tile compatibility, unique physical slot, missing/extra cells and per-tile-class capacity. It derives 21216 physical slots from named device topology and current TD tile queries. The exact known logical LSLICE `check_design` discrepancy is accepted only after that complete current proof. Other resource types remain subject to raw IO/PLB checks, both timing corners and final route/readonly DRC.

The current warning inventory records 104 warning messages and three critical messages: the two pending PHY-7027 messages, plus unchanged RGMII ODDR SYN-6024 at synthesis line 1084. The latter is retained only with exact control-message and unchanged RGMII source-byte checks. Raw warnings are preserved in physical, implementation and bitgen receipts; these reports must not be described as warning-free.

The final preparation checks passed 20 cases, including rejection of unknown PHY-7027, PHY-9002, duplicate/unplaced/missing Slice evidence, forged gate source coverage and an old FAIL receipt. An earlier 21-case pre-route run additionally verified that prebitgen rejects missing route evidence before reaching TD. Historical physical files used by these negative checks are parser fixtures only, not current acceptance evidence.

Evidence: `PRE_ROUTE_WARNING_POLICY.json`, `TOOL_SELF_CHECK.json`, and the current `tools/signoff_airwalk.py` (SHA256 `6B2CBF3EC5DB7F925F2F1CFBA7CAB322A5842AA00E62CD3A7FF52F53E8F52FB5`). Await the coordinating agent's actual signoff, then independently recheck the final current DB/source/capacity/CDC/timing/DRC evidence.
