# =====================================================
# Template - testing an iDPSIR network against observed data
# (step 6 of the workflow, done outside the app; Supplement S7)
# =====================================================
#
# Three tasks the application does not perform, run here with the
# application's own engine on a network saved by it (.idpsir.json), so the
# network tested is exactly the one used for the decision:
#   1. calibration  - fit chosen link strengths (or node parameters) to an
#                     observed series of one factor, by least squares;
#   2. validation   - fit on part of the series, predict the rest, compare
#                     with persistence and the linear trend, 90% band,
#                     rolling origin;
#   3. comparison   - alternative networks (variants, rival explanations)
#                     by AIC / AICc / BIC and out of sample.
# A fitted value goes back into the app as an ordinary link strength, with
# evidence type "calibration".
#
# How to use it with your network: copy the example at the end of this file
# (vn_example_srilanka()), change the savepoint, the observed series, the
# factor, the parameters to fit and the periods, and run it from the
# repository root:
#   Rscript analysis/templates/validate_network.R
# The Sri Lanka scripts in analysis/validation_srilanka/ are exactly this
# template applied to that case.
#
# Inputs
#   savepoint:  an .idpsir.json with the scenario to simulate (its
#               scenario_state: pushes, modes, schedule), one window per
#               time step;
#   observed:   a CSV with a time column and a value column (the factor's own
#               units); the factor needs reference_value and sd;
#   params:     what to fit - links (from, to) or node attributes (id, attr),
#               each with lower/upper bounds;
#   fixed:      values set before fitting (e.g. links removed in a variant).

if (!exists("simulate_temporal_pair")) {
  old <- setwd("tests/testthat"); suppressMessages(source("helper-setup.R")); setwd(old)
}

# ---------------------------------------------------------------------------
# Data and parameters
# ---------------------------------------------------------------------------

# Loads the network and the observed series. `year0` = the time of window 0
# (default: the first time in the series).
vn_load <- function(savepoint, observed, factor, time_col = "year", value_col = "value", year0 = NULL) {
  sp <- read_savepoint(savepoint)
  g <- build_igraph(sp$nodes, sp$edges, sp$schema)
  obs <- if (is.data.frame(observed)) observed else utils::read.csv(observed)
  stopifnot(time_col %in% names(obs), value_col %in% names(obs), factor %in% igraph::V(g)$name)
  ref <- as.numeric(sp$nodes$reference_value[sp$nodes$id == factor])
  sdv <- as.numeric(sp$nodes$sd[sp$nodes$id == factor])
  if (is.na(ref) || is.na(sdv)) stop("The factor '", factor, "' needs reference_value and sd to be compared with observations.")
  list(sp = sp, g = g, obs = setNames(as.numeric(obs[[value_col]]), obs[[time_col]]), factor = factor,
       year0 = year0 %||% min(obs[[time_col]]), ref = ref, sd = sdv)
}

# One row per parameter to fit: a link (type "edge", from, to) or a node
# attribute (type "node", id, attr, e.g. growth_rate).
vn_param <- function(name, type = c("edge", "node"), from = NA, to = NA, id = NA, attr = NA,
                     lower = 0, upper = Inf, start = 0.3) {
  type <- match.arg(type)
  data.frame(name = name, type = type, from = from, to = to, id = id, attr = attr,
             lower = lower, upper = upper, start = start, stringsAsFactors = FALSE)
}
vn_params <- function(...) do.call(rbind, list(...))

# Sets parameter values on the graph (links: weight; nodes: the attribute).
vn_apply <- function(g, params, values) {
  if (is.null(params) || nrow(params) == 0) return(g)
  e <- igraph::ends(g, igraph::E(g), names = TRUE)
  for (i in seq_len(nrow(params))) {
    p <- params[i, ]
    if (p$type == "edge") {
      k <- which(e[, 1] == p$from & e[, 2] == p$to)
      if (length(k) != 1) stop("Link ", p$from, " -> ", p$to, " not found (or not unique).")
      igraph::E(g)$weight[k] <- values[[i]]
    } else {
      k <- which(igraph::V(g)$name == p$id)
      if (length(k) != 1) stop("Factor ", p$id, " not found.")
      g <- igraph::set_vertex_attr(g, p$attr, index = k, value = values[[i]])
    }
  }
  g
}

# ---------------------------------------------------------------------------
# Simulation in the factor's own units
# ---------------------------------------------------------------------------

# The factor's simulated level, window 0 .. last - year0, named by time.
# `values` = the fitted parameters; `fixed` = list(params, values) applied
# first; `weights` (optional) replaces every link weight first (for the band).
vn_simulate <- function(d, params = NULL, values = NULL, last = max(as.numeric(names(d$obs))), weights = NULL, fixed = NULL) {
  g <- d$g
  if (!is.null(weights)) igraph::E(g)$weight <- weights
  if (!is.null(fixed)) g <- vn_apply(g, fixed$params, fixed$values)
  if (!is.null(params) && nrow(params) > 0) g <- vn_apply(g, params, values)
  ss <- d$sp$scenario_state
  ids <- igraph::V(g)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  tr <- simulate_temporal_pair(
    g, pv(ss$pressure_strengths), pv(ss$response_strengths),
    windows = last - d$year0, stop_rule = "fixed",
    mode_D = ss$temporal_mode_pressure, mode_R = ss$temporal_mode_response, schedule = ss$temporal_schedule,
    trends_outside = !isFALSE(ss$temporal_trends_outside)
  )
  setNames(d$ref + d$sd * tr$scenario[, d$factor], d$year0 + seq_len(nrow(tr$scenario)) - 1)
}

# r2 (squared correlation), RMSE, mean bias and Nash-Sutcliffe efficiency.
vn_fit_stats <- function(obs, sim) {
  res <- obs - sim
  sst <- sum((obs - mean(obs))^2)
  c(r2 = if (length(obs) > 2 && stats::sd(sim) > 0) stats::cor(obs, sim)^2 else NA_real_,
    rmse = sqrt(mean(res^2)), bias = mean(sim - obs), nse = 1 - sum(res^2) / sst)
}

# ---------------------------------------------------------------------------
# 1. Calibration
# ---------------------------------------------------------------------------

# Least squares on `years`. Nelder-Mead from each start (values outside the
# bounds get a penalty of 1e30); the best start is kept and, with polish =
# TRUE, refined by L-BFGS-B within the bounds. Standard errors from the
# Gauss-Newton approximation of the Hessian (central differences, h = 1e-4).
vn_calibrate <- function(d, params, years, fixed = NULL, starts = if (is.null(params)) list() else list(params$start), polish = TRUE,
                         reltol = 1e-12, maxit = 2000) {
  yrs <- as.character(years)
  obs <- d$obs[yrs]
  k <- if (is.null(params)) 0L else nrow(params)
  if (k == 0) {
    sim <- vn_simulate(d, NULL, NULL, max(years), fixed = fixed)[yrs]
    return(list(beta = numeric(), se = numeric(), cov = matrix(numeric(), 0, 0), years = years, value = sum((obs - sim)^2),
                stats = vn_fit_stats(obs, sim), residuals = obs - sim))
  }
  sse <- function(b) {
    if (any(b < params$lower) || any(b > params$upper)) return(1e30)
    sum((obs - vn_simulate(d, params, b, max(years), fixed = fixed)[yrs])^2)
  }
  best <- NULL
  for (s in starts) {
    o <- stats::optim(s, sse, method = "Nelder-Mead", control = list(reltol = reltol, maxit = maxit))
    if (is.null(best) || o$value < best$value) best <- o
  }
  if (polish) {
    best <- stats::optim(best$par, sse, method = "L-BFGS-B", lower = params$lower,
                         upper = ifelse(is.finite(params$upper), params$upper, Inf))
  }
  b <- best$par
  h <- 1e-4
  J <- sapply(seq_len(k), function(j) {
    e <- rep(0, k); e[j] <- h
    (vn_simulate(d, params, b + e, max(years), fixed = fixed)[yrs] - vn_simulate(d, params, b - e, max(years), fixed = fixed)[yrs]) / (2 * h)
  })
  J <- matrix(J, ncol = k)
  sigma2 <- best$value / max(1, length(yrs) - k)
  cov <- tryCatch(solve(crossprod(J)) * sigma2, error = function(e) matrix(NA_real_, k, k))
  sim <- vn_simulate(d, params, b, max(years), fixed = fixed)[yrs]
  list(beta = setNames(b, params$name), se = setNames(sqrt(pmax(0, diag(cov))), params$name), cov = cov,
       years = years, value = best$value, stats = vn_fit_stats(obs, sim), residuals = obs - sim)
}

# ---------------------------------------------------------------------------
# 2. Out-of-sample validation
# ---------------------------------------------------------------------------

# Fit on fit_years, predict test_years with the fitted values frozen, against
# persistence of the last fitted value and the linear trend of the fit
# period. 90% band: n_band draws, each with the fitted parameters drawn from
# their fitted covariance (multivariate normal, truncated at the lower bound)
# and every other link drawn uniformly within its uncertainty band, as the
# app's confidence readings do (seed fixed). Rolling origin: fit from the
# first fit year to each origin, predict the rest.
vn_validate <- function(d, params, fit_years, test_years, origins = NULL, n_band = 500, seed = 42, fixed = NULL,
                        label = "Network") {
  cal <- vn_calibrate(d, params, fit_years, fixed = fixed)
  last <- max(test_years)
  sim <- vn_simulate(d, params, cal$beta, last, fixed = fixed)
  yt <- as.character(test_years); yf <- as.character(fit_years)
  obs_t <- d$obs[yt]
  persistence <- setNames(rep(d$obs[as.character(max(fit_years))], length(test_years)), yt)
  trend <- setNames(stats::predict(stats::lm(y ~ x, data = data.frame(x = fit_years, y = d$obs[yf])),
                                   data.frame(x = test_years)), yt)
  peak_year <- as.character(test_years[which.max(obs_t)])
  metrics_of <- function(pred, lab) {
    s <- vn_fit_stats(obs_t, pred[yt])
    data.frame(model = lab, r2 = s[["r2"]], rmse = s[["rmse"]], bias = s[["bias"]], nse = s[["nse"]],
               peak_year = as.integer(peak_year), peak_error = unname(pred[peak_year] - obs_t[peak_year]),
               stringsAsFactors = FALSE)
  }
  metrics <- rbind(metrics_of(sim, sprintf("%s (fitted %d-%d)", label, min(fit_years), max(fit_years))),
                   metrics_of(persistence, sprintf("Persistence (%d value)", max(fit_years))),
                   metrics_of(trend, sprintf("Linear trend %d-%d", min(fit_years), max(fit_years))))
  metrics$skill_vs_persistence <- 1 - metrics$rmse / metrics$rmse[2]
  metrics$fit_r2 <- c(cal$stats[["r2"]], NA, NA)
  for (nm in names(cal$beta)) {
    metrics[[paste0("beta_", nm)]] <- c(cal$beta[[nm]], NA, NA)
  }
  for (nm in names(cal$se)) {
    metrics[[paste0("se_", nm)]] <- c(cal$se[[nm]], NA, NA)
  }

  rolling <- if (length(origins)) do.call(rbind, lapply(origins, function(k) {
    fy <- min(fit_years):k
    ty <- as.character((k + 1):last)
    ck <- vn_calibrate(d, params, fy, fixed = fixed)
    sk <- vn_simulate(d, params, ck$beta, last, fixed = fixed)
    pk <- setNames(rep(d$obs[as.character(k)], length(ty)), ty)
    tk <- setNames(stats::predict(stats::lm(y ~ x, data = data.frame(x = fy, y = d$obs[as.character(fy)])),
                                  data.frame(x = as.numeric(ty))), ty)
    m <- function(pred) vn_fit_stats(d$obs[ty], pred[ty])
    out <- data.frame(origin = k, n_test = length(ty))
    for (nm in names(ck$beta)) out[[paste0("beta_", nm)]] <- ck$beta[[nm]]
    cbind(out, data.frame(rmse = m(sk)[["rmse"]], nse = m(sk)[["nse"]], bias = m(sk)[["bias"]],
                          rmse_persistence = m(pk)[["rmse"]], rmse_trend = m(tk)[["rmse"]]))
  })) else NULL

  g <- d$g
  w <- igraph::E(g)$weight
  lo <- igraph::E(g)$weight_low; hi <- igraph::E(g)$weight_high
  lo[is.na(lo)] <- w[is.na(lo)]; hi[is.na(hi)] <- w[is.na(hi)]
  n_out <- last - d$year0 + 1
  k <- length(cal$beta)
  draws <- with_local_seed(seed, {
    L <- tryCatch(chol(cal$cov), error = function(e) diag(cal$se, nrow = k))
    t(vapply(seq_len(n_band), function(i) {
      b <- pmax(params$lower, cal$beta + as.numeric(stats::rnorm(k) %*% L))
      ww <- stats::runif(length(w), lo, hi)
      tryCatch(vn_simulate(d, params, b, last, weights = ww, fixed = fixed), error = function(e) rep(NA_real_, n_out))
    }, numeric(n_out)))
  })
  colnames(draws) <- as.character(d$year0:last)
  band <- apply(draws, 2, stats::quantile, probs = c(0.05, 0.95), na.rm = TRUE)
  covered <- obs_t >= band[1, yt] & obs_t <= band[2, yt]
  metrics$band_coverage_90 <- c(mean(covered), NA, NA)
  metrics$band_draws_used <- c(sum(stats::complete.cases(draws)), NA, NA)

  tt <- d$year0:last
  forecast <- data.frame(year = tt, observed = unname(d$obs[as.character(tt)]), simulated = unname(sim[as.character(tt)]),
                         band_05 = unname(band[1, ]), band_95 = unname(band[2, ]),
                         period = ifelse(tt %in% fit_years, "fit", ifelse(tt %in% test_years, "test", "other")))
  list(metrics = metrics, rolling = rolling, forecast = forecast, calibration = cal,
       persistence = persistence, trend = trend)
}

# ---------------------------------------------------------------------------
# 3. Comparison of alternative networks
# ---------------------------------------------------------------------------

# models: named list, each list(d = vn_load(...), params = vn_params(...) or
# NULL, fixed = list(params, values) or NULL, starts = list(...),
# polish = TRUE/FALSE, description = "..."). Each is fitted on all_years (AIC,
# AICc, BIC from the residual sum of squares, Gaussian errors; lag-1
# autocorrelation of the residuals) and on fit_years to predict test_years.
vn_compare <- function(models, all_years, fit_years, test_years) {
  n <- length(all_years)
  rows <- lapply(names(models), function(nm) {
    m <- models[[nm]]
    p <- m$params
    k <- if (is.null(p)) 0L else nrow(p)
    starts <- m$starts %||% if (k) list(p$start) else list()
    polish <- m$polish %||% FALSE
    full <- vn_calibrate(m$d, p, all_years, fixed = m$fixed, starts = starts, polish = polish)
    part <- vn_calibrate(m$d, p, fit_years, fixed = m$fixed, starts = starts, polish = polish)
    yt <- as.character(test_years)
    st <- vn_fit_stats(m$d$obs[yt], vn_simulate(m$d, p, part$beta, max(test_years), fixed = m$fixed)[yt])
    sse <- full$value
    aic <- n * log(sse / n) + 2 * k
    r <- full$residuals
    data.frame(model = nm, description = m$description %||% nm, k = k,
               rmse_all = sqrt(sse / n), aic = aic,
               aicc = aic + if (n - k - 1 > 0) 2 * k * (k + 1) / (n - k - 1) else NA_real_,
               bic = n * log(sse / n) + k * log(n),
               residual_lag1_acf = if (length(r) > 2) stats::acf(r, lag.max = 1, plot = FALSE)$acf[2] else NA_real_,
               rmse_test = st[["rmse"]], nse_test = st[["nse"]], bias_test = st[["bias"]],
               params_all = if (k) paste(signif(full$beta, 3), collapse = "; ") else "-",
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$delta_aic <- out$aic - min(out$aic)
  out$delta_aicc <- out$aicc - min(out$aicc, na.rm = TRUE)
  out$delta_bic <- out$bic - min(out$bic)
  out
}

# ---------------------------------------------------------------------------
# Figure in the style of Fig. 5b of the paper
# ---------------------------------------------------------------------------
vn_plot_validation <- function(v, ylab = "Observed factor (own units)", xlab = "Year", ylim = NULL) {
  f <- v$forecast
  m <- v$metrics
  test <- f$period == "test"
  yt <- f$year[test]
  ylim <- ylim %||% range(0, f$observed, f$band_95, v$trend, na.rm = TRUE) * c(1, 1.08)
  graphics::par(mar = c(4.2, 4.8, 3, 1))
  graphics::plot(f$year, f$observed, type = "n", ylim = ylim, xlab = xlab, ylab = ylab, las = 1, bty = "l")
  graphics::rect(min(yt) - 0.5, -1e12, max(yt) + 0.5, 1e12, col = "#eef0f2", border = NA)
  graphics::polygon(c(yt, rev(yt)), c(f$band_05[test], rev(f$band_95[test])), col = grDevices::adjustcolor("#0072B2", 0.22), border = NA)
  graphics::lines(f$year, f$simulated, col = "#0072B2", lwd = 2)
  graphics::lines(yt, v$persistence, col = "#1f2933", lty = 3, lwd = 1.5)
  graphics::lines(yt, v$trend, col = "#D55E00", lty = 2, lwd = 1.5)
  graphics::points(f$year, f$observed, pch = 16, col = "#1f2933")
  graphics::legend("topleft", bty = "n", cex = 0.85,
                   legend = c("observed", "network: fitted, then predicted", "90% prediction band",
                              sprintf("persistence (RMSE %.0f)", m$rmse[2]), sprintf("trend (RMSE %.0f)", m$rmse[3])),
                   col = c("#1f2933", "#0072B2", grDevices::adjustcolor("#0072B2", 0.4), "#1f2933", "#D55E00"),
                   pch = c(16, NA, 15, NA, NA), lty = c(NA, 1, NA, 3, 2), lwd = c(NA, 2, NA, 1.5, 1.5), pt.cex = c(1, 1, 1.8, 1, 1))
  graphics::mtext(sprintf("Test period: RMSE %.0f, bias %+.0f, NSE %.2f; band covers %.0f%% of the observations",
                          m$rmse[1], m$bias[1], m$nse[1], 100 * m$band_coverage_90[1]), side = 3, line = 0.6, cex = 0.85)
}

# ---------------------------------------------------------------------------
# Example: the Sri Lankan fishery (copy and adapt for another network)
# ---------------------------------------------------------------------------
vn_example_srilanka <- function(root = ".") {
  d <- vn_load(file.path(root, "docs/example_gnanapragasam.idpsir.json"),
               file.path(root, "data/gnanapragasam2026_effort_observed.csv"),
               factor = "P1", time_col = "year", value_col = "total_effort_kwdays_1000", year0 = 2004)
  aid <- vn_params(vn_param("R1", "edge", from = "R1", to = "D3", lower = 0, start = 0.3),
                   vn_param("R2", "edge", from = "R2", to = "D3", lower = 0, start = 0.1))
  rival <- vn_params(vn_param("growth_D3", "node", id = "D3", attr = "growth_rate", lower = 0, upper = 0.5, start = 0.01),
                     vn_param("D2_P1", "edge", from = "D2", to = "P1", lower = 0, upper = 1.5, start = 0.45))
  no_aid <- list(params = aid, values = c(0, 0))
  list(
    d = d, params = aid, all_years = 2006:2021, fit_years = 2006:2014, test_years = 2015:2021, origins = 2012:2016,
    models = list(
      aid = list(d = d, params = aid, starts = list(c(0.3, 0.1)), polish = FALSE,
                 description = "Aid -> fleet (published, 2 aid betas fitted)"),
      no_aid = list(d = d, params = NULL, fixed = no_aid, description = "No aid -> fleet (nothing fitted)"),
      rival = list(d = d, params = rival, fixed = no_aid, polish = FALSE,
                   starts = list(c(0.01, 0.45), c(0.05, 0.45), c(0.1, 0.8), c(0.03, 1)),
                   description = "No aid -> fleet; fleet growth and demand -> effort fitted")
    )
  )
}

if (sys.nframe() == 0) {
  ex <- vn_example_srilanka()
  cal <- vn_calibrate(ex$d, ex$params, ex$all_years)
  cat("Calibration", min(ex$all_years), "-", max(ex$all_years), ":\n"); print(round(cal$beta, 4)); print(round(cal$stats, 3))
  v <- vn_validate(ex$d, ex$params, ex$fit_years, ex$test_years, ex$origins, label = "Network")
  print(v$metrics, digits = 4); print(v$rolling, digits = 4)
  print(vn_compare(ex$models, ex$all_years, ex$fit_years, ex$test_years), digits = 4)
}
