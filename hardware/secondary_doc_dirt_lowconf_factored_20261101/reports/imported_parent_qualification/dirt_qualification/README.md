# Frozen document dirt qualification inputs

These inputs belong to `secondary_doc_dirt_lowconf_area_20261101`. The regression compiles
`01_rtl/doc_image_frontend.v` and every backend from this root. Earlier
diagnostic source/evidence is retained under `provenance/` for origin only;
it is never an RTL compilation input.

The independent count model and min2 model agree on every fixture. Captured
Y comes from two read-only 1280x720 YUYV files; no RGB-luma conversion is used.
The production integer stroke reference generates skeleton, raw paths,
planned points, mirrored A4 machine coordinates and expected G-code.

Run `python tools/run_doc_dirt_regression.py --run` after these files have
been frozen. Commands, source/fixture/output hashes and RESULTS are written
only under `02_sim/doc_dirt_frontend`. The peer simulates GRBL responses;
physical camera/plotter acceptance remains NOT_RUN. No accuracy claim is
made without pixel labels; broad dark interiors inside the calibrated ROI
may be suppressed and strong shade boundaries may remain. No TD build is
started by this regression.
