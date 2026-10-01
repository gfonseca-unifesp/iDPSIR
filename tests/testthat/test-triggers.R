# =====================================================
# TESTS - R/triggers.R and gated sufficiency (Revisao 2, Fase C)
# =====================================================

# Reference network of the roadmap (C1): P1 -> S and P2 -> S (beta 0.3 each,
# negative), S -> I (0.8, negative), R -> P1 (0.5 or 0.8, negative).
# Threshold of S at z = -0.4: reference 1, sd 1, level 0.6 (a falling State).
trigger_network <- function(beta_rp1 = 0.5, level = 0.6, direction = "auto") {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("P1", "P2", "S", "I", "R"), label = c("P1", "P2", "S", "I", "R"),
    dpsir_category = c("Pressure", "Pressure", "State", "Impact", "Response"),
    reference_value = c(NA, NA, 1, NA, NA), sd = c(NA, NA, 1, NA, NA),
    threshold_level = c(NA, NA, level, NA, NA), threshold_direction = c(NA, NA, direction, NA, NA),
    stringsAsFactors = FALSE
  ))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("P1", "P2", "S", "R"), to = c("S", "S", "I", "P1"), weight = c(0.3, 0.3, 0.8, beta_rp1),
    interaction_type = "negative", stringsAsFactors = FALSE
  ))
  build_igraph(nodes, edges, get_default_dpsir_schema())
}
pv5 <- function(P1 = 0, P2 = 0, R = 0) c(P1 = P1, P2 = P2, S = 0, I = 0, R = R)
suff_I <- function(g, pD, pR) sufficiency(g, pD, pR)[1, ]

test_that("C1/C6: the six reference cases (sum of pressures, closing the trigger)", {
  g5 <- trigger_network(0.5); g8 <- trigger_network(0.8)

  expect_equal(state_gates(g5, pv5(P1 = 1))$deviation, -0.3, tolerance = 1e-9)
  expect_false(state_gates(g5, pv5(P1 = 1))$open)
  expect_equal(suff_I(g5, pv5(P1 = 1), pv5())$worsening, 0, tolerance = 1e-9)

  both <- suff_I(g5, pv5(1, 1), pv5())
  expect_equal(both$worsening, 0.48, tolerance = 1e-6)
  expect_true(state_gates(g5, pv5(1, 1))$open)

  r05 <- suff_I(g5, pv5(1, 1), pv5(R = 1))
  expect_equal(r05$worsening, 0.48, tolerance = 1e-6)
  expect_equal(r05$net, 0.36, tolerance = 1e-6)
  expect_equal(state_gates(g5, pv5(1, 1, 1))$deviation, -0.45, tolerance = 1e-9)

  r08 <- suff_I(g8, pv5(1, 1), pv5(R = 1))
  expect_equal(state_gates(g8, pv5(1, 1, 1))$deviation, -0.36, tolerance = 1e-9)
  expect_false(state_gates(g8, pv5(1, 1, 1))$open)
  expect_equal(r08$net, 0, tolerance = 1e-9)
  expect_true(r08$neutralized)
  expect_equal(r08$neutralized_by, "trigger")
  expect_equal(format_sufficiency_table(sufficiency(g8, pv5(1, 1), pv5(R = 1)), "R", c(R = 100))[["Neutralizes?"]], "Yes (below threshold)")

  expect_equal(suff_I(g8, pv5(0.7, 0.7), pv5())$worsening, 0.336, tolerance = 1e-6)
  expect_equal(suff_I(g8, pv5(0.6, 0.6), pv5())$worsening, 0, tolerance = 1e-9)
})

test_that("C2: strength to neutralize is found by bisection when a trigger is involved", {
  g <- trigger_network(0.8)
  s <- suff_I(g, pv5(1, 1), pv5(R = 1))
  # The gate closes once 0.3 * (1 - 0.8 s) + 0.3 < 0.4, i.e. s > 0.8333.
  expect_equal(s$strength_to_neutralize, 5 / 6, tolerance = 1e-6)
})

test_that("C0: direction - a rising threshold (contaminant) never opens with a falling deviation, 'both' opens either way", {
  up <- trigger_network(level = 9) # z = +8
  expect_false(state_gates(up, pv5(1, 1))$open)
  both <- trigger_network(level = 1.4, direction = "both") # |z| = 0.4
  expect_true(state_gates(both, pv5(1, 1))$open)
})

test_that("C6: an older fraction threshold (f of reference) reproduces the older rule |x| >= f * ref", {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = "S", label = "S", dpsir_category = "State", reference_value = 100, activation_threshold = 0.15
  ))
  g <- build_igraph(nodes, NULL, get_default_dpsir_schema())
  th <- state_thresholds(g)
  expect_equal(th$z, -15)
  expect_equal(th$direction, "both")
  expect_true(gate_is_open(15, th$z, th$direction))
  expect_true(gate_is_open(-15, th$z, th$direction))
  expect_false(gate_is_open(14.9, th$z, th$direction))
})

test_that("C6 regression: a network without thresholds gives exactly the ungated results", {
  g <- trigger_network(level = NA)
  s <- sufficiency(g, pv5(1, 1), pv5(R = 1))
  B <- effect_matrix(g)
  expect_equal(s$worsening, unname(propagate(B, pv5(1, 1))["I"]))
  expect_equal(s$mitigation, unname(propagate(B, pv5(R = 1))["I"]))
})

test_that("C3: temporal gate by accumulated level (default) versus by the load of the window", {
  g <- trigger_network(0.8)
  V(g)$self_regulation <- 0
  # P1 alone at 100%, impulse: the load (0.3) never reaches 0.4, but the
  # accumulated deviation of S does (roadmap reference q7.py: window 4).
  acc <- simulate_temporal_pair(g, pv5(P1 = 1), pv5(), windows = 6, mode_D = "impulse")
  load <- simulate_temporal_pair(g, pv5(P1 = 1), pv5(), windows = 6, mode_D = "impulse", gate_mode = "load")
  expect_true(all(load$baseline[, "I"] == 0))
  expect_equal(which(acc$gates_baseline[, "S"])[1], 4)
  expect_gt(acc$baseline[7, "I"], 0)
})
