# Sri Lanka example: calibration and out-of-sample validation

Revisão 3, E2. Code outside the app: it sources the app's engine (`R/`) and the
published example (`docs/example_gnanapragasam.idpsir.json`) and reimplements nothing.
It is not copied into the shinylive demo.

- `calibrate.R`: least-squares fit of the two aid strengths (post-tsunami and post-war aid
  → fleet capacity) to the observed fishing effort (article, Fig. 4). On 2006–2021 it
  reproduces the values fixed in `data-raw/gnanapragasam2026_build.R` (0.342 / 0.089 →
  0.345 / 0.085, R² = 0.93).
- `validate.R`: fit on 2006–2014, predict 2015–2021; compare with holding the 2014 value
  and with the 2006–2014 linear trend; rolling origin (2012–2016); 90% band from the
  strengths' uncertainty (E2.2).

Run from the repository root: `Rscript analysis/validation_srilanka/validate.R`.
Outputs in `out/`: `metrics.csv`, `rolling_origin.csv`, `forecast.csv`,
`fig_validation.png` / `.svg`. The numbers are pinned by
`tests/testthat/test-example-gnanapragasam.R`.
