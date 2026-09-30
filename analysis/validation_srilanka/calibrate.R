# =====================================================
# Sri Lanka example - calibration of the two aid strengths
# =====================================================
#
# Revisao 3, E2.1. Rewrites the fit that data-raw/gnanapragasam2026_build.R
# only keeps as fixed values (BETA_R1_D3 = 0.345, BETA_R2_D3 = 0.085): the
# betas of post-tsunami aid -> fleet capacity (R1 -> D3) and post-war aid ->
# fleet capacity (R2 -> D3) are fitted by least squares to the observed
# fishing effort (article, Fig. 4). Everything else is the published example
# (docs/example_gnanapragasam.idpsir.json) and runs through the app's own
# engine (simulate_temporal_pair()); nothing is reimplemented.
#
# Sourced from the repository root after the app's R/ core, e.g. through
# tests/testthat/helper-setup.R (see validate.R).

VAL_EXAMPLE <- "docs/example_gnanapragasam.idpsir.json"
VAL_OBSERVED <- "data/gnanapragasam2026_effort_observed.csv"
VAL_YEAR0 <- 2004  # window 0

load_srilanka <- function(root = ".") {
  sp <- read_savepoint(file.path(root, VAL_EXAMPLE))
  g <- build_igraph(sp$nodes, sp$edges, sp$schema)
  obs <- utils::read.csv(file.path(root, VAL_OBSERVED))
  list(sp = sp, g = g, obs = setNames(obs$total_effort_kwdays_1000, obs$year))
}

aid_edges <- function(g) {
  e <- igraph::ends(g, igraph::E(g), names = TRUE)
  c(R1 = which(e[, 1] == "R1" & e[, 2] == "D3"), R2 = which(e[, 1] == "R2" & e[, 2] == "D3"))
}

# Simulated fishing effort (thousand kW-days) for window 0 .. max(years) - 2004,
# named by year, with the two aid betas set to `beta` (and, optionally, every
# other edge's weight replaced by `weights`, for the uncertainty band).
simulate_effort <- function(d, beta, last_year = 2021, weights = NULL) {
  g <- d$g
  if (!is.null(weights)) igraph::E(g)$weight <- weights
  k <- aid_edges(g)
  igraph::E(g)$weight[k["R1"]] <- beta[1]
  igraph::E(g)$weight[k["R2"]] <- beta[2]
  ss <- d$sp$scenario_state
  ids <- igraph::V(g)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  tr <- simulate_temporal_pair(
    g, pv(ss$pressure_strengths), pv(ss$response_strengths),
    windows = last_year - VAL_YEAR0, stop_rule = "fixed",
    mode_D = ss$temporal_mode_pressure, mode_R = ss$temporal_mode_response, schedule = ss$temporal_schedule,
    trends_outside = !isFALSE(ss$temporal_trends_outside)
  )
  ref <- as.numeric(d$sp$nodes$reference_value[d$sp$nodes$id == "P1"])
  sdv <- as.numeric(d$sp$nodes$sd[d$sp$nodes$id == "P1"])
  setNames(ref + sdv * tr$scenario[, "P1"], VAL_YEAR0 + seq_len(nrow(tr$scenario)) - 1)
}

fit_stats <- function(obs, sim) {
  res <- obs - sim
  sst <- sum((obs - mean(obs))^2)
  # r2: squared correlation; nse: Nash-Sutcliffe (1 - SSE/SST), which also
  # penalizes bias and can be negative (worse than the observed mean).
  c(r2 = if (length(obs) > 2 && stats::sd(sim) > 0) stats::cor(obs, sim)^2 else NA_real_,
    rmse = sqrt(mean(res^2)), bias = mean(sim - obs), nse = 1 - sum(res^2) / sst)
}

# Least-squares fit of the two aid betas on `years` (both >= 0). Returns the
# betas, their standard errors (from the Gauss-Newton approximation of the
# Hessian at the optimum) and the in-sample statistics.
calibrate_aid <- function(d, years, start = c(0.3, 0.1)) {
  yrs <- as.character(years)
  obs <- d$obs[yrs]
  sse <- function(b) {
    if (any(b < 0)) return(1e30)
    sum((obs - simulate_effort(d, b, max(years))[yrs])^2)
  }
  opt <- stats::optim(start, sse, method = "Nelder-Mead", control = list(reltol = 1e-12, maxit = 2000))
  opt <- stats::optim(opt$par, sse, method = "L-BFGS-B", lower = c(0, 0))
  b <- opt$par
  # Jacobian of the simulated effort w.r.t. the betas (central differences).
  h <- 1e-4
  J <- sapply(1:2, function(j) {
    e <- c(0, 0); e[j] <- h
    (simulate_effort(d, b + e, max(years))[yrs] - simulate_effort(d, b - e, max(years))[yrs]) / (2 * h)
  })
  sigma2 <- opt$value / max(1, length(yrs) - 2)
  cov <- tryCatch(solve(crossprod(J)) * sigma2, error = function(e) matrix(NA_real_, 2, 2))
  sim <- simulate_effort(d, b, max(years))[yrs]
  list(beta = setNames(b, c("R1", "R2")), se = setNames(sqrt(pmax(0, diag(cov))), c("R1", "R2")),
       cov = cov, years = years, stats = fit_stats(obs, sim))
}
