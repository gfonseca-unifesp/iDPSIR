# =====================================================
# Sri Lanka example - out-of-sample validation (Revisao 3, E2.1-E2.2)
# =====================================================
#
# Calibrates the two aid strengths on 2006-2014 and predicts fishing effort
# for 2015-2021 with the strengths frozen, against two naive references
# (persistence of the 2014 value; the linear trend of 2006-2014). Repeats it
# with a rolling origin (fit 2006..k, predict k+1..2021, k = 2012..2016).
# E2.2: a 90% band for 2015-2021 from the calibrated betas (their fitted
# covariance) and every other edge resampled uniformly within its uncertainty
# band, as in sufficiency_confidence(); reports its coverage.
#
# Run from the repository root:
#   Rscript analysis/validation_srilanka/validate.R
# Writes analysis/validation_srilanka/out/{metrics.csv, rolling_origin.csv,
# forecast.csv, fig_validation.png, fig_validation.svg}.

run_validation <- function(root = ".", n_band = 500, seed = 42, fit_years = 2006:2014, test_years = 2015:2021,
                           origins = 2012:2016) {
  d <- load_srilanka(root)
  cal <- calibrate_aid(d, fit_years)
  sim <- simulate_effort(d, cal$beta, max(test_years))
  yt <- as.character(test_years)
  yf <- as.character(fit_years)
  obs_t <- d$obs[yt]

  persistence <- setNames(rep(d$obs[as.character(max(fit_years))], length(test_years)), yt)
  trend_fit <- stats::lm(y ~ x, data = data.frame(x = fit_years, y = d$obs[yf]))
  trend <- setNames(stats::predict(trend_fit, data.frame(x = test_years)), yt)

  peak_year <- as.character(test_years[which.max(obs_t)])
  metrics_of <- function(pred, label) {
    s <- fit_stats(obs_t, pred[yt])
    data.frame(model = label, r2 = s[["r2"]], rmse = s[["rmse"]], bias = s[["bias"]], nse = s[["nse"]],
               peak_year = as.integer(peak_year), peak_error = unname(pred[peak_year] - obs_t[peak_year]),
               stringsAsFactors = FALSE)
  }
  metrics <- rbind(
    metrics_of(sim, "iDPSIR (aid calibrated 2006-2014)"),
    metrics_of(persistence, "Persistence (2014 value)"),
    metrics_of(trend, "Linear trend 2006-2014")
  )
  metrics$fit_r2 <- c(cal$stats[["r2"]], NA, NA)
  metrics$beta_R1 <- c(cal$beta[["R1"]], NA, NA)
  metrics$beta_R2 <- c(cal$beta[["R2"]], NA, NA)
  metrics$se_R1 <- c(cal$se[["R1"]], NA, NA)
  metrics$se_R2 <- c(cal$se[["R2"]], NA, NA)

  # Rolling origin.
  rolling <- do.call(rbind, lapply(origins, function(k) {
    fy <- 2006:k
    ty <- as.character((k + 1):max(test_years))
    ck <- calibrate_aid(d, fy)
    sk <- simulate_effort(d, ck$beta, max(test_years))
    pk <- setNames(rep(d$obs[as.character(k)], length(ty)), ty)
    tk <- setNames(stats::predict(stats::lm(y ~ x, data = data.frame(x = fy, y = d$obs[as.character(fy)])),
                                  data.frame(x = as.numeric(ty))), ty)
    m <- function(pred) fit_stats(d$obs[ty], pred[ty])
    data.frame(origin = k, n_test = length(ty), beta_R1 = ck$beta[["R1"]], beta_R2 = ck$beta[["R2"]],
               rmse = m(sk)[["rmse"]], nse = m(sk)[["nse"]], bias = m(sk)[["bias"]],
               rmse_persistence = m(pk)[["rmse"]], rmse_trend = m(tk)[["rmse"]])
  }))

  # E2.2: uncertainty band of the forecast.
  g <- d$g
  w <- igraph::E(g)$weight
  lo <- igraph::E(g)$weight_low; hi <- igraph::E(g)$weight_high
  lo[is.na(lo)] <- w[is.na(lo)]; hi[is.na(hi)] <- w[is.na(hi)]
  draws <- with_local_seed(seed, {
    L <- tryCatch(chol(cal$cov), error = function(e) diag(cal$se))
    t(vapply(seq_len(n_band), function(i) {
      b <- pmax(0, cal$beta + as.numeric(stats::rnorm(2) %*% L))
      ww <- stats::runif(length(w), lo, hi)
      out <- tryCatch(simulate_effort(d, b, max(test_years), weights = ww), error = function(e) rep(NA_real_, max(test_years) - VAL_YEAR0 + 1))
      out
    }, numeric(max(test_years) - VAL_YEAR0 + 1)))
  })
  colnames(draws) <- as.character(VAL_YEAR0:max(test_years))
  band <- apply(draws, 2, stats::quantile, probs = c(0.05, 0.95), na.rm = TRUE)
  covered <- obs_t >= band[1, yt] & obs_t <= band[2, yt]
  metrics$band_coverage_90 <- c(mean(covered), NA, NA)
  metrics$band_draws_used <- c(sum(stats::complete.cases(draws)), NA, NA)

  forecast <- data.frame(
    year = VAL_YEAR0:max(test_years),
    observed = unname(d$obs[as.character(VAL_YEAR0:max(test_years))]),
    simulated = unname(sim[as.character(VAL_YEAR0:max(test_years))]),
    band_05 = unname(band[1, ]), band_95 = unname(band[2, ]),
    period = ifelse(VAL_YEAR0:max(test_years) %in% fit_years, "fit", ifelse(VAL_YEAR0:max(test_years) %in% test_years, "test", "other"))
  )
  list(metrics = metrics, rolling = rolling, forecast = forecast, calibration = cal,
       persistence = persistence, trend = trend)
}

plot_validation <- function(v) {
  f <- v$forecast
  graphics::par(mar = c(4.2, 4.8, 4, 1))
  graphics::plot(f$year, f$observed, type = "n", ylim = c(0, 22000),
                 xlab = "Year", ylab = "Fishing effort (thousand kW-days)")
  graphics::title("Sri Lanka: aid calibrated on 2006-2014, effort predicted for 2015-2021", line = 2.2)
  graphics::rect(2014.5, -1e6, 2021.5, 1e6, col = grDevices::adjustcolor("grey80", 0.35), border = NA)
  test <- f$period == "test"
  graphics::polygon(c(f$year[test], rev(f$year[test])), c(f$band_05[test], rev(f$band_95[test])),
                    col = grDevices::adjustcolor("#1f77b4", 0.2), border = NA)
  graphics::lines(f$year, f$simulated, col = "#1f77b4", lwd = 2.5)
  yt <- as.integer(names(v$persistence))
  graphics::lines(yt, v$persistence, col = "grey40", lty = 3, lwd = 1.8)
  graphics::lines(yt, v$trend, col = "#d62728", lty = 2, lwd = 1.8)
  graphics::points(f$year, f$observed, pch = 16, col = "grey20")
  m <- v$metrics
  graphics::legend("bottomright", bty = "n", cex = 0.8,
                   legend = c("Observed (article, Fig. 4)", "iDPSIR (fit 2006-2014, then predicted)", "90% band (2015-2021)",
                              sprintf("Persistence of 2014 (RMSE %.0f)", m$rmse[2]), sprintf("Linear trend 2006-2014 (RMSE %.0f)", m$rmse[3])),
                   col = c("grey20", "#1f77b4", grDevices::adjustcolor("#1f77b4", 0.4), "grey40", "#d62728"),
                   pch = c(16, NA, 15, NA, NA), lty = c(NA, 1, NA, 3, 2), lwd = c(NA, 2.5, NA, 1.8, 1.8), pt.cex = c(1, 1, 2, 1, 1))
  graphics::mtext(sprintf("Test period: RMSE %.0f, NSE %.2f, bias %+.0f; band coverage %.0f%%",
                          m$rmse[1], m$nse[1], m$bias[1], 100 * m$band_coverage_90[1]), side = 3, line = 0.6, cex = 0.85)
}

if (sys.nframe() == 0) {
  setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
  source("analysis/validation_srilanka/calibrate.R")
  v <- run_validation()
  out <- "analysis/validation_srilanka/out"
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(v$metrics, file.path(out, "metrics.csv"), row.names = FALSE)
  utils::write.csv(v$rolling, file.path(out, "rolling_origin.csv"), row.names = FALSE)
  utils::write.csv(v$forecast, file.path(out, "forecast.csv"), row.names = FALSE)
  render_plot_png(function() plot_validation(v), file.path(out, "fig_validation.png"), width = 1400, height = 820)
  render_plot_svg(function() plot_validation(v), file.path(out, "fig_validation.svg"), width = 10, height = 6)
  print(v$metrics, digits = 3)
  print(v$rolling, digits = 3)
}
