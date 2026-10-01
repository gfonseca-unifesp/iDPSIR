# Revisao 3, E2: the Sri Lanka calibration (analysis/validation_srilanka/)
# reproduces the published aid strengths, and the out-of-sample test
# (fit 2006-2014, predict 2015-2021) keeps its numbers.

source("../../analysis/validation_srilanka/calibrate.R")
source("../../analysis/validation_srilanka/validate.R")

test_that("E2.1: calibrating on 2006-2021 reproduces the aid strengths fixed in the build", {
  d <- load_srilanka("../..")
  full <- calibrate_aid(d, 2006:2021)
  expect_equal(unname(full$beta), c(0.345, 0.085), tolerance = 0.01)
  expect_equal(full$stats[["nse"]], 0.93, tolerance = 0.005)
})

test_that("E2.1/E2.2: out of sample the model beats both naive references, with the documented numbers", {
  v <- run_validation("../..", n_band = 50, origins = c(2012, 2014))
  m <- v$metrics
  expect_equal(m$rmse[1], 558.9, tolerance = 1e-3)
  expect_equal(m$bias[1], 351, tolerance = 2e-3)
  expect_equal(m$nse[1], -0.484, tolerance = 1e-2)
  expect_lt(m$rmse[1], m$rmse[2])   # persistence of 2014
  expect_lt(m$rmse[2], m$rmse[3])   # linear trend
  # Rolling origin: loses to persistence when fitted on 2006-2012 only.
  r <- v$rolling
  expect_gt(r$rmse[r$origin == 2012], r$rmse_persistence[r$origin == 2012])
  expect_lt(r$rmse[r$origin == 2014], r$rmse_persistence[r$origin == 2014])
  expect_true(m$band_coverage_90[1] >= 0 && m$band_coverage_90[1] <= 1)
})

test_that("E3.2: without aid -> fleet the aid reaches only income loss and the effort misses the data", {
  load_g <- function(f) {
    sp <- read_savepoint(sprintf("../../docs/%s.idpsir.json", f))
    list(sp = sp, g = build_igraph(sp$nodes, sp$edges, sp$schema))
  }
  full <- load_g("example_gnanapragasam"); var <- load_g("example_gnanapragasam_noaidfleet")
  expect_equal(nrow(var$sp$edges), nrow(full$sp$edges) - 2)
  expect_equal(response_reach(full$g, c("R1", "R2"))$impacts, 5)
  expect_equal(response_reach(var$g, c("R1", "R2"))$impacts, 1)
  effort <- function(x) {
    ss <- x$sp$scenario_state; ids <- igraph::V(x$g)$name
    pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
    tr <- simulate_temporal_pair(x$g, pv(ss$pressure_strengths), pv(ss$response_strengths), windows = 17, stop_rule = "fixed",
                                 mode_D = ss$temporal_mode_pressure, mode_R = ss$temporal_mode_response, schedule = ss$temporal_schedule)
    n <- x$sp$nodes
    setNames(n$reference_value[n$id == "P1"] + n$sd[n$id == "P1"] * tr$scenario[, "P1"], 2004:2021)[as.character(2006:2021)]
  }
  obs <- load_srilanka("../..")$obs[as.character(2006:2021)]
  expect_gt(fit_stats(obs, effort(full))[["nse"]], 0.9)
  expect_lt(fit_stats(obs, effort(var))[["nse"]], 0)
})
