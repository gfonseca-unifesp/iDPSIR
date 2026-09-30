# Simulated DPSIR networks (Revisão 3, E5)

Does parameterizing a DPSIR network change its conclusions, how often, and why? The plan,
hypotheses H1–H5 and analyses are fixed in [`PREREGISTRO.md`](PREREGISTRO.md), committed
before any condition was run.

- `generate.R` (E5.2): random networks and parameter draws in the app's own formats, as
  specified in the pre-registration; tested in `tests/testthat/test-sim-generator.R` (kept in
  the main suite so CI checks it).
- `run.R` (E5.3), `analyze.R` (E5.5), `run_all.R`: to come.

Everything calls the app's engine (`R/`), sourced through `tests/testthat/helper-setup.R`;
nothing is reimplemented. This folder is not copied into the shinylive demo.
