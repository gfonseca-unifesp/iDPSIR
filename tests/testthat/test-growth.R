# Revisao 2, Fase D: growth as a trend of the base level (D9, D10, D24),
# windowed pushes, growth ceiling.

growth_pair <- function(sr_D, g_D, cap = NA, ref = NA) {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("D", "P"), label = c("D", "P"), dpsir_category = c("Driver", "Pressure"), subsystem = "",
    self_regulation = c(sr_D, 1), growth_rate = c(g_D, 0), growth_cap = c(cap, NA), reference_value = c(ref, NA),
    stringsAsFactors = FALSE
  ))
  edges <- normalize_dpsir_edges(data.frame(from = "D", to = "P", weight = 0.5, interaction_type = "positive", stringsAsFactors = FALSE))
  build_igraph(nodes, edges, get_default_dpsir_schema())
}
zero_of <- function(g) setNames(rep(0, vcount(g)), V(g)$name)
arriving_at_P <- function(tr) 0.5 * tr$scenario[-1, "D"]

test_that("D5 reference table: contribution arriving at P, windows 1-4", {
  g <- growth_pair(0.5, 0.10)
  tr <- simulate_temporal_pair(g, zero_of(g), zero_of(g), windows = 4, stop_rule = "fixed")
  expect_equal(unname(arriving_at_P(tr)), c(0.050, 0.105, 0.1655, 0.23205), tolerance = 1e-6)
  expect_equal(unname(tr$edge_intensity[, "D->P"]), c(0.050, 0.105, 0.1655, 0.23205), tolerance = 1e-6)

  g0 <- growth_pair(0, 0.10)
  tr0 <- simulate_temporal_pair(g0, zero_of(g0), zero_of(g0), windows = 4, stop_rule = "fixed")
  expect_equal(unname(arriving_at_P(tr0)), unname(arriving_at_P(tr)), tolerance = 1e-12)

  gi <- growth_pair(0.5, 0)
  p <- zero_of(gi); p["D"] <- 1
  tri <- simulate_temporal_pair(gi, p, zero_of(gi), windows = 4, stop_rule = "fixed", mode_D = "impulse")
  expect_equal(unname(arriving_at_P(tri)), c(0.5, 0.25, 0.125, 0.0625), tolerance = 1e-6)

  gg <- growth_pair(0.5, 0.10)
  trg <- simulate_temporal_pair(gg, p, zero_of(gg), windows = 4, stop_rule = "fixed", mode_D = "impulse")
  expect_equal(unname(arriving_at_P(trg)), c(0.55, 0.355, 0.2905, 0.29455), tolerance = 1e-6)
})

test_that("the trend grows in proportion (1 + g), never (1 + g)^2", {
  g <- growth_pair(0.5, 0.10)
  tr <- simulate_temporal_pair(g, zero_of(g), zero_of(g), windows = 5, stop_rule = "fixed")
  inc <- diff(tr$trend[, "D"])
  expect_equal(inc[-1] / inc[-length(inc)], rep(1.10, length(inc) - 1), tolerance = 1e-9)
})

test_that("the trend is the same in both rounds: net - baseline does not depend on g", {
  g1 <- growth_pair(0.5, 0.10)
  g0 <- growth_pair(0.5, 0)
  p <- zero_of(g1); p["D"] <- 1
  r1 <- simulate_temporal_pair(g1, zero_of(g1), p, windows = 6, stop_rule = "fixed")
  r0 <- simulate_temporal_pair(g0, zero_of(g0), p, windows = 6, stop_rule = "fixed")
  expect_equal(r1$scenario - r1$baseline, r0$scenario - r0$baseline, tolerance = 1e-12)
  none <- simulate_temporal_pair(g1, zero_of(g1), zero_of(g1), windows = 6, stop_rule = "fixed")
  expect_equal(none$scenario, none$baseline)
})

test_that("growth ceiling holds the base level; trends_outside = FALSE drops the trend", {
  g <- growth_pair(0.5, 0.10, cap = 12, ref = 10)
  tr <- simulate_temporal_pair(g, zero_of(g), zero_of(g), windows = 6, stop_rule = "fixed")
  # ref 10, no SD -> trend as a fraction of the base level; ceiling 12 = +0.2.
  expect_equal(max(tr$trend[, "D"]), 0.2, tolerance = 1e-12)
  expect_equal(unname(tr$trend[2, "D"]), 0.1, tolerance = 1e-12)
  off <- simulate_temporal_pair(g, zero_of(g), zero_of(g), windows = 6, stop_rule = "fixed", trends_outside = FALSE)
  expect_true(all(off$trend == 0))
})

test_that("'window' mode pushes only inside each factor's period", {
  g <- growth_pair(1, 0)
  p <- zero_of(g); p["D"] <- 1
  sched <- data.frame(id = "D", start = 2, duration = 3)
  tr <- simulate_temporal_pair(g, p, zero_of(g), windows = 6, stop_rule = "fixed", mode_D = "window", schedule = sched)
  # D has self-regulation 1, so its level is the push of each window.
  expect_equal(unname(tr$baseline[-1, "D"]), c(0, 1, 1, 1, 0, 0))
})

test_that("continue_after keeps running after neutralizing", {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("D", "P", "S", "I", "R"), label = c("D", "P", "S", "I", "R"),
    dpsir_category = c("Driver", "Pressure", "State", "Impact", "Response"), subsystem = "",
    self_regulation = 1, stringsAsFactors = FALSE
  ))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("D", "P", "S", "R"), to = c("P", "S", "I", "I"), weight = c(0.8, 0.8, 0.8, 1),
    interaction_type = c("positive", "negative", "negative", "negative"), stringsAsFactors = FALSE
  ))
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())
  p_D <- zero_of(g); p_D["D"] <- 1
  p_R <- zero_of(g); p_R["R"] <- 1
  a <- simulate_temporal_pair(g, p_D, p_R, max_windows = 30)
  expect_false(is.na(a$neutralized_at))
  b <- simulate_temporal_pair(g, p_D, p_R, max_windows = 30, continue_after = 4)
  expect_equal(b$neutralized_at, a$neutralized_at)
  expect_equal(b$windows, a$neutralized_at + 4)
})

test_that("growth validation: g <= -1 blocks, > 0.5 warns, bad ceiling blocks", {
  nodes <- data.frame(id = c("A", "B", "C"), label = c("A", "B", "C"), dpsir_category = "Driver",
                      growth_rate = c(-1, 0.6, 0.1), growth_cap = c("", "", "-3"), stringsAsFactors = FALSE)
  pf <- preflight_import_nodes(nodes)
  expect_true(any(grepl("growth_rate -1 must be greater than -1", pf$blocking)))
  expect_true(any(grepl("growth_cap '-3'", pf$blocking)))
  expect_true(any(grepl("above 0.5", pf$warnings)))
})

test_that("explained-variance check leaves out edges from a Response", {
  nodes <- data.frame(id = c("D", "R", "P"), label = c("D", "R", "P"), dpsir_category = c("Driver", "Response", "Pressure"), stringsAsFactors = FALSE)
  edges <- data.frame(from = c("D", "R"), to = c("P", "P"), weight = c(0.9, 1), stringsAsFactors = FALSE)
  expect_length(explained_variance_warnings(nodes, edges), 0)
})

test_that("Sri Lanka example: replay follows Fig. 4 and the article's benchmarks", {
  imp <- import_matrices("../../data/gnanapragasam2026_nodes.csv", "../../data/gnanapragasam2026_edges.csv", convert_legacy = FALSE)
  g <- build_igraph(imp$nodes, imp$edges, get_default_dpsir_schema())
  obs <- read.csv("../../data/gnanapragasam2026_effort_observed.csv")
  z <- zero_of(g)
  p_D <- z; p_D["D4"] <- 1
  sched <- data.frame(id = c("R1", "R2", "R3", "R4"), start = c(1, 6, 18, 18), duration = c(5, 3, 13, 13))
  run <- function(cut) {
    p_R <- z; p_R[c("R1", "R2")] <- 1; p_R["R3"] <- cut * 16531 / 4877; p_R["R4"] <- 1
    simulate_temporal_pair(g, p_D, p_R, windows = 26, stop_rule = "fixed", mode_R = "window", schedule = sched)
  }
  tr <- run(0.25)
  n <- setNames(imp$nodes$sd, imp$nodes$id); ref <- setNames(imp$nodes$reference_value, imp$nodes$id)
  effort <- ref["P1"] + n["P1"] * tr$scenario[, "P1"]
  sim <- effort[2:18]                       # 2005-2021
  o <- obs$total_effort_kwdays_1000[obs$year >= 2005]
  r2 <- 1 - sum((sim[-1] - o[-1])^2) / sum((o[-1] - mean(o[-1]))^2)
  expect_gt(r2, 0.9)
  stock <- ref["S1"] + n["S1"] * tr$scenario[, "S1"]
  expect_true(stock[8] > 345.2 && stock[9] < 345.2)    # below B_MSY from 2012 (article: catch above H_MSY in 2012)
  expect_gt(stock[27], 345.2)                           # 25% cut (MEY) takes it back above B_MSY by 2030
  expect_lt(abs(unname(effort[27]) - 12287) / 12287, 0.02)  # article: E_MEY = 12,287
  expect_false(tr$gates_scenario[26, 1])
})
