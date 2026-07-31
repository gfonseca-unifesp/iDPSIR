# =====================================================
# TESTS - R/temporal.R (Revisao 1, Fase 4: motor temporal)
# =====================================================
#
# Fixture principal: uma rede minima de 5 nos construida a mao
# (D1->P1->S1->I1, R1->S1 mitiga, R1->D1 fecha o ciclo "resposta vira
# nova pressao") - o mesmo padrao ja usado no projeto pra provar uma
# propriedade matematica especifica (cadeia trofica do Marco A da Fase 5,
# rede sinal-oposto do Marco D) em vez de depender de uma rede de exemplo
# externa. Cada numero abaixo foi conferido rodando
# scratchpad/test_temporal.R e scratchpad/test_temporal2.R antes de virar
# teste permanente, nao assumido.

build_test_network <- function(self_regulation = NULL) {
  nodes <- data.frame(
    id = c("D1", "P1", "S1", "I1", "R1"),
    label = c("D1", "P1", "S1", "I1", "R1"),
    dpsir_category = c("Driver", "Pressure", "State", "Impact", "Response"),
    subsystem = "", uncertainty = "medium", controllability = "medium",
    stringsAsFactors = FALSE
  )
  edges <- data.frame(
    from = c("D1", "P1", "S1", "R1", "R1"),
    to   = c("P1", "S1", "I1", "S1", "D1"),
    weight = c(1, 1, 1, 1, 0.5),
    confidence = 1,
    interaction_type = c("positive", "negative", "negative", "positive", "positive"),
    evidence_type = "expert_assessment",
    stringsAsFactors = FALSE
  )
  nodes <- normalize_dpsir_nodes(nodes)
  edges <- normalize_dpsir_edges(edges)
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())

  if (!is.null(self_regulation)) {
    V(g)$self_regulation <- self_regulation[V(g)$name]
  }

  g
}

zero_press <- function(g) {
  setNames(rep(0, vcount(g)), V(g)$name)
}

test_that("build_test_network's normalize_dpsir_nodes() already fills growth_rate/reference_value with defaults (Fase 5)", {
  g <- build_test_network()
  expect_true(all(build_growth_rate_vector(g) == 0))
  expect_true(all(build_reference_values(g) == 1))
})

test_that("build_growth_rate_vector/build_reference_values fall back to 0/1 on a graph built without normalize_dpsir_nodes() at all", {
  # A graph assembled directly via graph_from_data_frame() (same pattern
  # already used elsewhere in this project's tests for pure structural
  # checks) never went through normalize_dpsir_nodes() - growth_rate/
  # reference_value are genuinely absent vertex attributes here, the
  # actual scenario these fallbacks exist for.
  nodes <- data.frame(id = c("A", "B"), stringsAsFactors = FALSE)
  edges <- data.frame(from = "A", to = "B", weight = 1, interaction_type = "positive", stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  expect_null(V(g)$growth_rate)
  expect_null(V(g)$reference_value)
  expect_true(all(build_growth_rate_vector(g) == 0))
  expect_true(all(build_reference_values(g) == 1))
})

test_that("temporal_step matches a hand-computed single window", {
  g <- build_test_network()
  W <- build_interaction_matrix(g)
  growth_rate <- build_growth_rate_vector(g)
  reference_values <- build_reference_values(g)
  Th <- build_threshold_matrix(g)

  x0 <- zero_press(g)
  p <- build_press_vector(g, active_ids = "D1", strengths = c(D1 = 1))

  x1 <- temporal_step(x0, W, growth_rate, Th, reference_values, p)

  # x=0 everywhere, so W %*% x contributes nothing on the first step - only
  # the direct external push on D1 shows up.
  expect_equal(unname(x1["D1"]), 1)
  expect_equal(unname(x1["P1"]), 0)
})

test_that("simulate_temporal_pair: permanent pressure alone matches hand-computed values over several windows", {
  g <- build_test_network()
  p_D <- build_press_vector(g, active_ids = "D1", strengths = c(D1 = 1))
  zero_p <- zero_press(g)

  result <- simulate_temporal_pair(g, p_D, zero_p, windows = 4, mode_D = "permanent", mode_R = "impulse")

  # D1(t+1) = D1(t) + 1 (permanent push, no incoming edges without R1 active)
  expect_equal(unname(result$baseline[, "D1"]), c(0, 1, 2, 3, 4))
  # P1(t+1) = P1(t) + D1(t) (D1->P1 positive weight 1)
  expect_equal(unname(result$baseline[, "P1"]), c(0, 0, 1, 3, 6))
  # S1(t+1) = S1(t) - P1(t) (P1->S1 negative weight 1)
  expect_equal(unname(result$baseline[, "S1"]), c(0, 0, 0, -1, -4))
})

test_that("impulse mode only pushes on window 1; permanent mode keeps pushing every window", {
  g <- build_test_network()
  p_R <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))
  zero_p <- zero_press(g)

  impulse <- simulate_temporal_pair(g, zero_p, p_R, windows = 5, mode_D = "impulse", mode_R = "impulse")
  permanent <- simulate_temporal_pair(g, zero_p, p_R, windows = 5, mode_D = "impulse", mode_R = "permanent")

  # R1 has no self-regulation and no incoming edges in this network - an
  # impulse push has nothing to decay it, so it flatlines at the injected
  # value (a "permanent structural consequence of a one-time event", the
  # exact nuance the user described for aid -> permanently larger fleet).
  expect_equal(unname(impulse$scenario[, "R1"]), c(0, rep(1, 5)))
  # Permanent mode keeps re-injecting every window - R1 grows linearly.
  expect_equal(unname(permanent$scenario[, "R1"]), 0:5)
})

test_that("real finding: a self_regulation magnitude of 2 (outside the intended [0,1) range) oscillates in this discrete difference equation instead of decaying", {
  # self_regulation is numeric directly since Fase 5 - a raw value of 2
  # reproduces the exact magnitude the OLD categorical "high" used to map
  # to (self_regulation_magnitudes()["high"] = -2, before that function was
  # removed), reachable today only by bypassing the form's 0-1 validation
  # (e.g. a hand-edited CSV) - still worth guaranteeing the engine doesn't
  # silently misbehave if that happens.
  g <- build_test_network(self_regulation = c(D1 = 0, P1 = 0, S1 = 2, I1 = 0, R1 = 0))
  p_test <- build_press_vector(g, active_ids = "S1", strengths = c(S1 = -1))
  zero_p <- zero_press(g)

  result <- simulate_temporal_pair(g, p_test, zero_p, windows = 6, mode_D = "impulse", mode_R = "impulse")

  # self_regulation = 2 -> diagonal = -2 (negated) -> (1 + (-2)) = -1: the
  # state flips sign every window at the SAME magnitude forever, never
  # actually decaying toward 0. This is the real, tested motivation for
  # Fase 5 constraining self_regulation to [0,1) in the form (mod_data.R)
  # instead of allowing magnitudes this large.
  expect_equal(unname(result$baseline[, "S1"]), c(0, -1, 1, -1, 1, -1, 1))
})

test_that("self_regulation = 0 leaves an impulse permanently unchanged (ratchet, no natural recovery)", {
  g <- build_test_network(self_regulation = c(D1 = 0, P1 = 0, S1 = 0, I1 = 0, R1 = 0))
  p_test <- build_press_vector(g, active_ids = "S1", strengths = c(S1 = -1))
  zero_p <- zero_press(g)

  result <- simulate_temporal_pair(g, p_test, zero_p, windows = 5, mode_D = "impulse", mode_R = "impulse")

  expect_equal(unname(result$baseline[, "S1"]), c(0, rep(-1, 5)))
})

test_that("format_temporal_table reports the response's benefit shrinking over windows, on the 'response becomes new pressure' network", {
  g <- build_test_network()
  p_D <- build_press_vector(g, active_ids = "D1", strengths = c(D1 = 1))
  p_R <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))

  result <- simulate_temporal_pair(g, p_D, p_R, windows = 8, mode_D = "permanent", mode_R = "permanent")
  tbl <- format_temporal_table(g, result)

  expect_equal(nrow(tbl), 9) # windows 0..8, one Impact node (I1)
  expect_true(all(c("id", "node", "window", "baseline_impact", "scenario_impact", "verdict") %in% names(tbl)))

  # R1's own feedback into D1 (the "response becomes new pressure" loop)
  # never fully reverses the benefit within these 8 windows in this toy
  # network, but its RELATIVE benefit erodes visibly - full neutralization
  # early (window 2), only partial mitigation by window 8, and the
  # scenario/baseline ratio grows from 0 to 0.6 - confirmed against
  # scratchpad/test_temporal.R's full run before writing this, not assumed.
  expect_equal(tbl$verdict[tbl$window == 2], "Neutralized")
  expect_equal(tbl$verdict[tbl$window == 8], "Partial")
  ratio_w7 <- tbl$scenario_impact[tbl$window == 7] / tbl$baseline_impact[tbl$window == 7]
  ratio_w8 <- tbl$scenario_impact[tbl$window == 8] / tbl$baseline_impact[tbl$window == 8]
  expect_true(ratio_w8 > ratio_w7) # mitigation getting weaker window over window
})

test_that("format_temporal_table returns an empty data.frame, not an error, when the graph has no Impact nodes", {
  nodes <- data.frame(id = c("D1", "P1"), label = c("D1", "P1"), dpsir_category = c("Driver", "Pressure"), stringsAsFactors = FALSE)
  edges <- data.frame(from = "D1", to = "P1", weight = 1, confidence = 0.8, interaction_type = "positive", stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
  press <- zero_press(g)

  result <- simulate_temporal_pair(g, press, press, windows = 3)
  expect_equal(nrow(format_temporal_table(g, result)), 0)
})

test_that("on_step callback fires once per window with (t, windows), for the progress indicator (Revisao 1, Fase 6)", {
  g <- build_test_network()
  p_D <- build_press_vector(g, active_ids = "D1", strengths = c(D1 = 1))
  zero_p <- zero_press(g)

  calls <- list()
  result <- simulate_temporal_pair(
    g, p_D, zero_p, windows = 4, mode_D = "permanent", mode_R = "impulse",
    on_step = function(t, windows) calls[[length(calls) + 1]] <<- c(t, windows)
  )

  expect_equal(length(calls), 4)
  expect_equal(calls, list(c(1, 4), c(2, 4), c(3, 4), c(4, 4)))
  # on_step is purely a side effect - the simulation result itself must be
  # unaffected, same numbers already verified in the hand-computed test above.
  expect_equal(unname(result$baseline[, "D1"]), c(0, 1, 2, 3, 4))
})

test_that("threshold gating (relative to reference_value) blocks an edge until the source crosses it, then it stays on", {
  g <- build_test_network()
  # S1 -> I1 gets a threshold: only contributes once |S1| >= 2 (reference_value
  # defaults to 1 pre-Fase-5, so this is an absolute magnitude for now).
  E(g)[which(tail_of(g, E(g))$name == "S1" & head_of(g, E(g))$name == "I1")]$threshold <- 2

  p_D <- build_press_vector(g, active_ids = "D1", strengths = c(D1 = 1))
  zero_p <- zero_press(g)

  result <- simulate_temporal_pair(g, p_D, zero_p, windows = 6, mode_D = "permanent", mode_R = "impulse")

  # S1 magnitudes from the hand-computed test above: 0,0,0,-1,-4,-10,-20 -
  # |S1| first reaches >= 2 at window 4 (|-4|=4). The gate looks at the
  # state ENTERING a step (same look-back convention already used by
  # simulate_trajectory_thresholded(), R/loop_analysis.R), so the edge only
  # actually contributes starting the step OUT of window 4, first visible
  # in I1's value at window 5 (row 6) - I1 stays exactly 0 through window 4
  # (rows 1-5).
  expect_true(all(result$baseline[1:5, "I1"] == 0))
  expect_false(result$baseline[6, "I1"] == 0)
})
