# legacy/

Code that the app no longer uses, moved out of `R/` in Revisao 2, Fase 4 (30/09/2026).
Nothing here is sourced by `global.R`, run by the tests or shipped in the shinylive demo.
It is kept only as a readable record of how earlier versions worked; the git history has
the full context.

| File | What it was | Replaced by |
|---|---|---|
| `R/loop_analysis_legacy.R` | Equilibrium engine (Levins loop analysis): stability, press perturbation, trajectory, robustness, sign determinacy, sensitivities, neutralization step | `R/sufficiency.R` (static reading) and `R/temporal.R` (windows) |
| `R/responses_legacy.R` | First scenario engine: edited the graph's weights (`apply_response`) and compared topologies | `R/sufficiency.R` |
| `R/scenario_plots_legacy.R` | Trajectory and sensitivity charts, the network storyboard | `plot_temporal_storyboard()` (per-Impact line chart) |
| `R/sufficiency_legacy.R` | `build_signed_matrix()` | `effect_matrix()` (`R/structural.R`) |
| `R/dpsir/` | The original fixed-category pathway and response code | `R/pathways.R`, `R/sufficiency.R` |
| `R/modules/mod_communities.R` | Separate communities tab | "Color nodes by: Community" in the Graph tab |
| `R/modules/mod_data_ui_legacy.R` | Unused UI function of the data module | the wizard steps rendered by `mod_data_server()` |
| `tests/test-loop_analysis.R` | Tests of the equilibrium engine | `tests/testthat/test-interaction_matrix.R` keeps the tests of the functions still in use |
