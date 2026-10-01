# =====================================================
# Sri Lanka example - calibration of the two aid strengths
# =====================================================
#
# Revisao 3, E2.1. The strengths of post-tsunami aid -> fleet capacity
# (R1 -> D3) and post-war aid -> fleet capacity (R2 -> D3) are fitted by least
# squares to the observed fishing effort (article, Fig. 4). Everything else is
# the published example (docs/example_gnanapragasam.idpsir.json), run by the
# app's own engine. This file is the generic template
# (analysis/templates/validate_network.R) configured for the case: the
# functions below keep the names the rest of the repository uses.
#
# Sourced from the repository root after the app's R/ core, e.g. through
# tests/testthat/helper-setup.R (see validate.R).

if (!exists("vn_load")) {
  for (vn_path in c("analysis/templates/validate_network.R", "../../analysis/templates/validate_network.R")) {
    if (file.exists(vn_path)) { source(vn_path, local = TRUE); break }
  }
}

VAL_EXAMPLE <- "docs/example_gnanapragasam.idpsir.json"
VAL_OBSERVED <- "data/gnanapragasam2026_effort_observed.csv"
VAL_YEAR0 <- 2004  # window 0

# The two aid strengths, both >= 0; Nelder-Mead from (0.3, 0.1), then
# L-BFGS-B within the bounds (vn_calibrate()).
SL_AID_PARAMS <- vn_params(vn_param("R1", "edge", from = "R1", to = "D3", lower = 0, start = 0.3),
                           vn_param("R2", "edge", from = "R2", to = "D3", lower = 0, start = 0.1))

load_srilanka <- function(root = ".") vn_example_srilanka(root)$d

# Simulated fishing effort (thousand kW-days), named by year, with the two aid
# strengths set to `beta` (and, optionally, every link weight replaced by
# `weights`, for the uncertainty band).
simulate_effort <- function(d, beta, last_year = 2021, weights = NULL) {
  vn_simulate(d, SL_AID_PARAMS, beta, last_year, weights = weights)
}

fit_stats <- function(obs, sim) vn_fit_stats(obs, sim)

calibrate_aid <- function(d, years, start = c(0.3, 0.1)) {
  p <- SL_AID_PARAMS
  p$start <- start
  vn_calibrate(d, p, years)
}
