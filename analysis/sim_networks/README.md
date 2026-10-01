# Simulated DPSIR networks (Revisão 3, E5)

Does parameterizing a DPSIR network change its conclusions, how often, and why? The plan,
hypotheses H1–H5 and analyses are fixed in [`PREREGISTRO.md`](PREREGISTRO.md), committed
before any condition was run.

- `generate.R` (E5.2): random networks and parameter draws in the app's own formats, as
  specified in the pre-registration; tested in `tests/testthat/test-sim-generator.R` (kept in
  the main suite so CI checks it).
- `run.R` (E5.3): the conditions C0-C4 for each network; `analyze.R` (E5.5): section 6
  of the pre-registration; `run_all.R`: both, one command
  (`Rscript analysis/sim_networks/run_all.R 1000 20` - 1000 networks on 20 processes,
  about 90 min).
- `out/`: `results.csv.gz` (one row per network x draw x condition x Impact),
  `networks.csv`, `counts.csv`, `change_rates.csv`, `hypotheses.csv`, `glmer.csv`,
  `rf_importance.csv`, `summary.md` and figures (a)-(d) (SVG versioned; PNG regenerated).

## Results (1000 networks x 20 strength draws; see `out/summary.md`)

| Hypothesis | Result |
|---|---|
| H1: strengths alone change < 30% of verdicts | confirmed - 15.9% (95% CI 15.1-16.5) |
| H2: thresholds and growth change more than strengths | refuted - thresholds 18.9% (more), growth only 4.3% |
| H3: networks with feedback loops change more | refuted - fewer (odds ratio 0.79) |
| H4: changes concentrate near neutralization | confirmed - odds ratio 5.4 |
| H5: priority order more stable than verdicts (tau > 0.7) | refuted - mean tau 0.64; the top priority changes in 35% |

Also: switching the reading from static to temporal (C2 -> C2t) changes 17.8% of verdicts;
5.9% of the temporal runs diverge and are left out; strong loops (rho(B)) raise the chance
of a change.

Everything calls the app's engine (`R/`), sourced through `tests/testthat/helper-setup.R`;
nothing is reimplemented. This folder is not copied into the shinylive demo.
