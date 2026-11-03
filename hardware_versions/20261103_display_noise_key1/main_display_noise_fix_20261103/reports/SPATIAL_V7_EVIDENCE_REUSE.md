# V7 reuse of identical V6 functional evidence

Result: PASS. This is an authorized byte-identical restoration of existing V6 simulation evidence, **not a new ModelSim or replay run**. V7 changes physical mapping strategy only; the reviewed product RTL, integer model and replay script are unchanged.

Restored 107 files from `02_sim/display_noise_attempt6_rtl_v6/` to `02_sim/display_noise/`. Every archived file first matched the original V6 archive manifest. All four preexisting canonical source files matched their archived SHA256 before copying; no different file was overwritten. After restoration, all 107 file names and hashes exactly matched the archived set. The canonical seven required source hashes also match current files.

The original V6 verification remains byte-identical and records 11 PASS cases, 1,859,523 cycles and 1,857,539 active pixels. Its original logs and timestamps are preserved. No evidence was regenerated or relabeled as a V7 simulator run. Both nocarry and prior combined equivalence proofs remain bound through the unchanged verification JSON.

The current 100-frame V6 historical replay remains valid for the identical product/model/script hashes and is retained without rerunning. It remains software replay with unknown historical capture-bit identity; board validation stays NOT_RUN. This reuse establishes no V7 physical resource or timing result.

| Bound item | SHA256 |
|---|---|
| Product RTL | `CD72245FA5CF73F16F35C2F655E5F13DD5F4949D14D258A7B99F9179AA219696` |
| Original V6 verification, restored unchanged | `57AE2143873C1D305C71278122368DFB38993FD394B5775DDF1F747B741B1DC7` |
| Current retained replay | `CD24F2C775CA388EA7484DD6565C309D31040F360C66E52876104C81D2E98D44` |
| Integer reference | `8C5BB22686DB26CFDB2F1C256038AEBC42C01E4FD01F652194700307FEAA5609` |
| Replay script | `8255C55F5FDA2DC589371E1838C620C561991CA7866376B8B3A7C42DA710C462` |
| V6 archive manifest | `4DF1FA2C560C115B2B78295CBEDBBEB96186F84C5ABD0CA64A8AE80C44F44CDE` |
| V7 restoration receipt | `FC0A197F03613E64079E2D663F0D0EC2E1A010A67BF84DBCFC43A2ED3627711D` |
