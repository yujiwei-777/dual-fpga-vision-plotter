# Independent arithmetic and selection audit

The selected model passes this software audit. No model, training script, dataset, previous FPGA project, mainboard, bitstream, or work/ backup was modified. Hardware status remains NOT_RUN. The prepared core bench in this directory was not executed; the parent assigned RTL verification to a separate agent under reports/rtl_core.

## Selected-model serialization and arithmetic

- Seed selected by validation: 20261103.
- weights.mem: 308 signed INT8 values, SHA256 92A3BBFD2192CC3D74A5BD3A893A34FCC3D45AE727DBEB8DEFAC56033634874B.
- biases.mem: 10 signed INT32 values, SHA256 88F1FC576BB24DC35FA58B5620F09CFBA7B61E600B5E92DE2CAD40DA2080B2D0.
- MEM values, QUANTIZED.npz, and re-quantized selected checkpoint match exactly.
- Fifteen real cases were chosen as first/middle/last in each of five domain/subtype groups, plus black/gray/white and three fixed-seed random images. All 21 cases match exactly at Conv1, Conv2, spatial pool, and logits across checkpoint float64 QAT, MEM-decoded independent int64, and batch reference.
- A separate independent int64 pass reproduces every one of the 1,450 eligible-image logits from the recorded full replay. Every ROI hash, label, split, dataset index, and permitted source root matches the dataset manifest.

The forward contract is unsigned Y8/128 in training, dyadic quantized parameters, Conv1/2 accumulator floor-shift 7 and clamp 0..32767, 6x6 regional sum shifted 5, then FC shift 8. There is no +64 convolution rounding, mean subtraction, RGB conversion, or orientation correction. Bias integer scales are 16384/16384/32768; weight scales are 128/128/256. Pool flatten order is C,Y,X. Class ties select GOOD, margin below 32 is REVIEW.

Independent conservative absolute-prefix bounds prove that all legal unsigned Y8 inputs fit the 27-bit accumulation registers, every pooled operand fits signed16, and shifted logits fit signed20. These bounds cover intermediate MAC prefixes, not just final observed sums. INDEPENDENT_BOUNDS.json records the values. Saturation/wrap assumptions are therefore not inferred solely from training examples.

## Selection and data boundaries

Actual training script SHA256 matches TRAINING_POLICY_BEFORE_RUN.json, as do dataset and manifest hashes. Both candidate FROZEN.json records state no test selection. Code inspection confirms optimization and checkpoint selection use train and validation only; seed selection uses the frozen validation keys, writes SELECTION_BEFORE_TEST.json, and only then performs the full test replay. The selected model files still match that pre-test freeze.

Recomputed roles: 713 train, 286 validation, 231 test, 220 guard. Recomputed test: 222/231 top-class predictions correct; GOOD 132 PASS, 2 REVIEW, 1 FAIL out of 135; BAD 7 PASS, 1 REVIEW, 88 FAIL out of 96. REVIEW is retained separately. The seven BAD false-PASS results remain a quality limitation despite numerical correctness. These are blocks from previously observed capture sessions, not independent new-board or new-background evidence.

## Earlier old-model scale sweep, read-only review

The old-model sweep contains 1,814 unique captures: 990 GOOD, 309 missing-corner, 515 missing-pad. Independent recomputation of SUMMARY and COMMON_COVERAGE_SUBSETS from FRAMES_ALL_SCALES matched 1,297 aggregate entries. The fixed control is half-open [158,140,1114,552], width956/height412. Each scale samples directly from source Y; cached 96x96 ROIs are not resized.

At both 1.80 and 2.00, every one of 824 BAD frames is EXPANDED_OUTSIDE_SOURCE REVIEW: zero BAD frames enter inference. The apparent zero false-PASS at those scales does not measure defect discrimination. Common geometry-valid coverage is 1,005 for scales1.00..1.30, 1,168 for the1.00/1.20 pair, and only2 for all12 scales. Population-level rates cannot be compared as if their inference subsets were identical. REAL_PARITY_0..5 in that sweep are six crop cases from two real source frames, rather than six independent source frames.

## Evidence

SELECTED_MODEL_PARITY.json records the 21-case three-way layer parity. FULL_REPLAY_AUDIT.json records all1,450 logits and policy/selection checks. SOURCE_SHA256.json binds selected model, checkpoint, dataset, training script and prepared RTL inputs. No synthesis, place/route, actual DDR, board quality, or bitgen pass is asserted by this audit.
