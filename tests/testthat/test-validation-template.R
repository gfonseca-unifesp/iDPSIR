# analysis/templates/validate_network.R: the generic template of step 6
# (Supplement S7). Run on the Sri Lankan case, it reproduces the numbers the
# manuscript cites (val.* and var.* in fixtures/manuscript_numbers.json).

source("../../analysis/templates/validate_network.R")

frozen <- jsonlite::fromJSON("fixtures/manuscript_numbers.json")

test_that("template: calibration and out-of-sample validation reproduce the cited numbers", {
  ex <- vn_example_srilanka("../..")
  full <- vn_calibrate(ex$d, ex$params, ex$all_years)
  expect_equal(full$beta[["R1"]], frozen$val.full.beta_R1, tolerance = 1e-8)
  expect_equal(full$beta[["R2"]], frozen$val.full.beta_R2, tolerance = 1e-8)
  expect_equal(full$stats[["nse"]], frozen$val.full.nse, tolerance = 1e-8)
  v <- vn_validate(ex$d, ex$params, ex$fit_years, ex$test_years, origins = 2012, n_band = 20)
  m <- v$metrics
  expect_equal(m$rmse[1], frozen$val.rmse, tolerance = 1e-8)
  expect_equal(m$bias[1], frozen$val.bias, tolerance = 1e-8)
  expect_equal(m$nse[1], frozen$val.nse, tolerance = 1e-8)
  expect_equal(m$rmse[2], frozen$val.rmse_persistence, tolerance = 1e-8)
  expect_equal(m$rmse[3], frozen$val.rmse_trend, tolerance = 1e-8)
  expect_equal(v$rolling$rmse[1], frozen$val.rolling2012.rmse, tolerance = 1e-8)
  expect_equal(m$skill_vs_persistence[1], 1 - m$rmse[1] / m$rmse[2])
  expect_true(all(c("year", "observed", "simulated", "band_05", "band_95", "period") %in% names(v$forecast)))
})

test_that("template: the comparison of networks reproduces the cited numbers and adds AICc and residual autocorrelation", {
  ex <- vn_example_srilanka("../..")
  cmp <- vn_compare(ex$models, ex$all_years, ex$fit_years, ex$test_years)
  for (mm in c("aid", "no_aid", "rival")) {
    r <- cmp[cmp$model == mm, ]
    expect_equal(r$rmse_all, frozen[[sprintf("var.%s.rmse_all", mm)]], tolerance = 1e-8, info = mm)
    expect_equal(r$delta_aic, frozen[[sprintf("var.%s.delta_aic", mm)]], tolerance = 1e-8, info = mm)
    expect_equal(r$delta_bic, frozen[[sprintf("var.%s.delta_bic", mm)]], tolerance = 1e-8, info = mm)
    expect_equal(r$rmse_test, frozen[[sprintf("var.%s.rmse_test", mm)]], tolerance = 1e-8, info = mm)
  }
  # AICc = AIC + 2k(k+1)/(n-k-1); with k = 0 it equals AIC.
  n <- length(ex$all_years)
  expect_equal(cmp$aicc, cmp$aic + 2 * cmp$k * (cmp$k + 1) / (n - cmp$k - 1))
  expect_true(all(abs(cmp$residual_lag1_acf) <= 1))
})

test_that("template: parameters can be links or node attributes, and errors are clear", {
  ex <- vn_example_srilanka("../..")
  p <- vn_params(vn_param("g", "node", id = "D3", attr = "growth_rate"), vn_param("b", "edge", from = "D2", to = "P1"))
  g2 <- vn_apply(ex$d$g, p, c(0.07, 0.5))
  expect_equal(igraph::V(g2)$growth_rate[igraph::V(g2)$name == "D3"], 0.07)
  e <- igraph::ends(g2, igraph::E(g2), names = TRUE)
  expect_equal(igraph::E(g2)$weight[e[, 1] == "D2" & e[, 2] == "P1"], 0.5)
  expect_error(vn_apply(ex$d$g, vn_params(vn_param("x", "edge", from = "D1", to = "I1")), 0.1), "not found")
  expect_error(vn_load("../../docs/example_gnanapragasam.idpsir.json", data.frame(year = 2004, value = 1), factor = "I1"),
               "reference_value and sd")
})
