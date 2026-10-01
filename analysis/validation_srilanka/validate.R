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
# band, as in sufficiency_confidence(); reports its coverage. The work is done
# by vn_validate() in analysis/templates/validate_network.R.
#
# Run from the repository root:
#   Rscript analysis/validation_srilanka/validate.R
# Writes analysis/validation_srilanka/out/{metrics.csv, rolling_origin.csv,
# forecast.csv, fig_validation.png, fig_validation.svg}.

run_validation <- function(root = ".", n_band = 500, seed = 42, fit_years = 2006:2014, test_years = 2015:2021,
                           origins = 2012:2016) {
  vn_validate(load_srilanka(root), SL_AID_PARAMS, fit_years, test_years, origins = origins, n_band = n_band, seed = seed,
              label = "iDPSIR, aid")
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
