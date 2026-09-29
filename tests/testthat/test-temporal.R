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
    # Explicit 0 (no recovery): the hand-computed values below predate the
    # Revisao 2 default of 0.5 (item A8).
    self_regulation = 0,
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

# Revisao 2, item 2.5: the engine no longer rescales anything (the old
# stability_cap), so self_regulation acts exactly as written - 1 means no
# memory, 0.5 halves the deviation every window (D20).
test_that("self_regulation 1 wipes an impulse after one window, 0.5 halves it every window", {
  p_test <- function(g) build_press_vector(g, active_ids = "S1", strengths = c(S1 = -1))
  g1 <- build_test_network(self_regulation = c(D1 = 0, P1 = 0, S1 = 1, I1 = 0, R1 = 0))
  g05 <- build_test_network(self_regulation = c(D1 = 0, P1 = 0, S1 = 0.5, I1 = 0, R1 = 0))

  r1 <- simulate_temporal_pair(g1, p_test(g1), zero_press(g1), windows = 4, mode_D = "impulse", mode_R = "impulse")
  r05 <- simulate_temporal_pair(g05, p_test(g05), zero_press(g05), windows = 4, mode_D = "impulse", mode_R = "impulse")

  expect_equal(unname(r1$baseline[, "S1"]), c(0, -1, 0, 0, 0))
  expect_equal(unname(r05$baseline[, "S1"]), c(0, -1, -0.5, -0.25, -0.125))
})
test_that("self_regulation = 0 leaves an impulse permanently unchanged (ratchet, no natural recovery)", {
  g <- build_test_network(self_regulation = c(D1 = 0, P1 = 0, S1 = 0, I1 = 0, R1 = 0))
  p_test <- build_press_vector(g, active_ids = "S1", strengths = c(S1 = -1))
  zero_p <- zero_press(g)

  result <- simulate_temporal_pair(g, p_test, zero_p, windows = 5, mode_D = "impulse", mode_R = "impulse")

  expect_equal(unname(result$baseline[, "S1"]), c(0, rep(-1, 5)))
})

test_that("a network without a reinforcing loop is not flagged, and nothing is rescaled (lambda is always 1)", {
  g <- build_test_network()
  p_D <- build_press_vector(g, active_ids = "D1", strengths = c(D1 = 1))
  zero_p <- zero_press(g)

  result <- simulate_temporal_pair(g, p_D, zero_p, windows = 3, mode_D = "impulse", mode_R = "impulse")

  expect_equal(result$stability$rho_W, 0)
  expect_equal(result$stability$lambda, 1)
  expect_false(result$stability$unbounded)
  expect_null(temporal_stability_note(result$stability))
})
test_that("a genuine two-node reinforcing loop (A->B positive, B->A positive) is flagged as unbounded", {
  # Real finding (confirmed against a generated report, rede do Mangi):
  # scaling W by lambda=min(1, stability_cap/rho(W)) reduces the
  # per-window gain but cannot fully eliminate it for a genuine reinforcing
  # loop - here a minimal, hand-verifiable 2-node mutual-reinforcement
  # network (the simplest case of the same structural problem Mangi has -
  # a dominant eigenvalue with positive real part). W = [[0,1],[1,0]],
  # eigenvalues = +1 and -1: no positive lambda can bring |1+lambda*1|
  # below 1, so this network can never be fully stabilized by scaling
  # alone, exactly the algebraic proof behind this whole fix.
  # graph_from_data_frame() directly, not build_igraph() - A->B->A isn't a
  # schema-valid connection pair (only Response is allowed to loop
  # backward), same escape hatch already used by the "no Impact nodes"
  # test below for a graph that only needs to exercise the math, not the
  # DPSIR ordering.
  nodes <- data.frame(id = c("A", "B"), label = c("A", "B"), dpsir_category = c("Driver", "Pressure"), stringsAsFactors = FALSE)
  edges <- data.frame(
    from = c("A", "B"), to = c("B", "A"), weight = c(1, 1),
    interaction_type = c("positive", "positive"), stringsAsFactors = FALSE
  )
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
  press <- setNames(c(1, 0), c("A", "B"))
  zero_p <- setNames(c(0, 0), c("A", "B"))

  result <- simulate_temporal_pair(g, press, zero_p, windows = 2, mode_D = "impulse", mode_R = "impulse")

  expect_equal(result$stability$rho_W, 1)
  expect_equal(result$stability$lambda, 1)
  expect_true(result$stability$unbounded)

  note <- temporal_stability_note(result$stability)
  expect_true(is.character(note))
  expect_true(grepl("reinforcing feedback loop", note, fixed = TRUE))
})

test_that("format_temporal_table reports the response's benefit shrinking over windows, on the 'response becomes new pressure' network", {
  g <- build_test_network()
  p_D <- build_press_vector(g, active_ids = "D1", strengths = c(D1 = 1))
  p_R <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))

  result <- simulate_temporal_pair(g, p_D, p_R, windows = 8, mode_D = "permanent", mode_R = "permanent")
  tbl <- format_temporal_table(g, result)

  expect_equal(nrow(tbl), 9) # windows 0..8, one Impact node (I1)
  expect_true(all(c("id", "node", "window", "baseline_impact", "net_impact", "verdict") %in% names(tbl)))
  # Hard regression guard (Revisao 1, "Net" rename): the old column name
  # must never come back.
  expect_false("scenario_impact" %in% names(tbl))

  # R1's own feedback into D1 (the "response becomes new pressure" loop)
  # never fully reverses the benefit within these 8 windows in this toy
  # network, but its RELATIVE benefit erodes visibly - full neutralization
  # early (window 2), only partial mitigation by window 8, and the
  # net/baseline ratio grows from 0 to 0.6 - confirmed against
  # scratchpad/test_temporal.R's full run before writing this, not assumed.
  expect_equal(tbl$verdict[tbl$window == 2], "Neutralized")
  expect_equal(tbl$verdict[tbl$window == 8], "Partial")
  ratio_w7 <- tbl$net_impact[tbl$window == 7] / tbl$baseline_impact[tbl$window == 7]
  ratio_w8 <- tbl$net_impact[tbl$window == 8] / tbl$baseline_impact[tbl$window == 8]
  expect_true(ratio_w8 > ratio_w7) # mitigation getting weaker window over window
})

test_that("format_temporal_table judges the raw signed value, not a floor-to-zero clamp (real bug, confirmed against a generated report)", {
  # Real bug, confirmed against a generated report (rede do Mangi): an
  # earlier version showed max(0, x) instead of the raw value and called
  # anything that floored to zero "Neutralized" - a network that was
  # diverging and flipping sign every few windows got mislabeled
  # "Neutralized" every single window it happened to land negative,
  # a permanent illusion of success built on the same numeric artifact.
  # This test hand-crafts a temporal_result (bypassing the dynamics of
  # simulate_temporal_pair entirely) to isolate format_temporal_table's
  # display logic on its own.
  nodes <- data.frame(id = "I1", label = "I1", dpsir_category = "Impact", stringsAsFactors = FALSE)
  g <- graph_from_data_frame(data.frame(from = character(), to = character()), vertices = nodes, directed = TRUE)

  temporal_result <- list(
    windows = 4,
    baseline = matrix(c(0, 10, 10, 10, 10), ncol = 1, dimnames = list(NULL, "I1")),
    scenario = matrix(c(0, -50, 1e-12, 4, 15), ncol = 1, dimnames = list(NULL, "I1"))
  )
  tbl <- format_temporal_table(g, temporal_result)

  # Window 1: scenario overshot to -50, LARGER in magnitude than the
  # baseline's 10 - under the app's convention (Impact = the problem,
  # positive = worse, ver docs/tutorial.html), a negative Impact means the
  # response pushed the factor BETTER than the no-response baseline, never
  # "worse" just because it's large in magnitude. Second real bug, found
  # only when evaluating a plan the user brought reviewing this exact
  # table: an earlier version of this fix (see the floor-to-zero fix above)
  # judged the verdict by abs(s) vs abs(b), which still mislabeled this
  # exact case "Failure/worsened" - fixed to judge by SIGN, not magnitude.
  expect_equal(tbl$net_impact[tbl$window == 1], -50)
  expect_equal(tbl$verdict[tbl$window == 1], "Improved beyond neutral")

  # Window 2: scenario is genuinely ~0 (not just negative) - correctly
  # "Neutralized".
  expect_equal(tbl$verdict[tbl$window == 2], "Neutralized")

  # Window 3: scenario=4, baseline=10 - still positive (still a problem)
  # but smaller than the no-response baseline - "Partial".
  expect_equal(tbl$verdict[tbl$window == 3], "Partial")

  # Window 4: scenario=15 >= baseline=10 - genuinely at least as bad as no
  # response at all - "Failure/worsened".
  expect_equal(tbl$verdict[tbl$window == 4], "Failure/worsened")
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
  # S1 -> I1 gets an activation threshold on S1 itself (second round of
  # Revisao 1: threshold moved from edge to node): only contributes once
  # |S1| >= 2 (reference_value defaults to 1 pre-Fase-5, so this is an
  # absolute magnitude for now).
  V(g)[V(g)$name == "S1"]$activation_threshold <- 2

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

# Revisao 2, item 0.3: same name-based alignment in the temporal engine,
# which used to call as.numeric() and drop the names.
test_that("simulate_temporal_pair() aligns press vectors by name, not position", {
  g <- build_test_network()
  p_D <- zero_press(g); p_D["D1"] <- 1
  p_R <- zero_press(g); p_R["R1"] <- 1

  base <- simulate_temporal_pair(g, p_D, p_R, windows = 4)
  shuffled <- simulate_temporal_pair(g, rev(p_D), rev(p_R), windows = 4)
  partial <- simulate_temporal_pair(g, p_D["D1"], p_R["R1"], windows = 4)

  expect_equal(shuffled$scenario, base$scenario)
  expect_equal(partial$scenario, base$scenario)
  expect_error(simulate_temporal_pair(g, c(p_D, ghost = 1), p_R, windows = 2), "not in the network: ghost")
})

# =====================================================
# Revisao 2, Fase A - reference values (A6): chain P -> E -> I with R -> P,
# weights 1, confirmed with the real engine (prototipos_revisao2/confere_em_R.R).
# =====================================================

chain_network <- function(sr = NULL) {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("P", "E", "I", "R"), label = c("P", "E", "I", "R"),
    dpsir_category = c("Pressure", "State", "Impact", "Response"),
    self_regulation = 0, stringsAsFactors = FALSE
  ))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("P", "E", "R"), to = c("E", "I", "P"), weight = 1,
    interaction_type = "negative", stringsAsFactors = FALSE
  ))
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())
  if (!is.null(sr)) V(g)$self_regulation <- sr[V(g)$name]
  g
}
chain_run <- function(g, mode_D, mode_R, ...) {
  p_D <- build_press_vector(g, "P", c(P = 1))
  p_R <- build_press_vector(g, "R", c(R = 1))
  simulate_temporal_pair(g, p_D, p_R, mode_D = mode_D, mode_R = mode_R, ...)
}
sr03 <- c(P = 0.3, E = 0.3, I = 0.3, R = 0)

test_that("A6 fixed windows: impulse / permanent response reproduce the reference values", {
  imp <- chain_run(chain_network(), "permanent", "impulse", windows = 30)
  expect_equal(unname(imp$baseline[c(6, 11, 31), "I"]), c(10, 120, 4060), tolerance = 1e-6)
  expect_equal(unname(imp$scenario[c(6, 11, 31), "I"]), c(6, 36, 406), tolerance = 1e-6)

  per <- chain_run(chain_network(), "permanent", "permanent", windows = 10)
  expect_equal(unname(per$baseline[c(6, 9, 11), "I"]), c(10, 56, 120), tolerance = 1e-6)
  expect_equal(unname(per$scenario[c(6, 9, 11), "I"]), c(5, -14, -90), tolerance = 1e-6)

  damp <- chain_run(chain_network(sr03), "permanent", "impulse", windows = 30)
  expect_equal(unname(damp$baseline[c(11, 31), "I"]), c(22.8599, 36.9588), tolerance = 1e-6)
  expect_equal(unname(damp$scenario[c(11, 31), "I"]), c(2.9648, 0.0267), tolerance = 1e-3)
})

test_that("A6 until_neutralized: stop windows for the four mode combinations, with and without self-regulation", {
  stop_at <- function(sr, mD, mR) {
    r <- chain_run(chain_network(sr), mD, mR, stop_rule = "until_neutralized", max_windows = 50)
    unname(c(r$neutralized_at, if (is.na(r$neutralized_at)) NA else r$scenario[r$neutralized_at + 1, "I"]))
  }
  expect_equal(stop_at(NULL, "permanent", "permanent"), c(7, 0))
  expect_equal(stop_at(NULL, "permanent", "impulse")[1], NA_real_)
  expect_equal(stop_at(NULL, "impulse", "impulse"), c(6, 0))
  expect_equal(stop_at(NULL, "impulse", "permanent"), c(6, -5))
  expect_equal(stop_at(sr03, "permanent", "permanent"), c(6, -0.67), tolerance = 1e-2)
  expect_equal(stop_at(sr03, "permanent", "impulse")[1], NA_real_)
  expect_equal(stop_at(sr03, "impulse", "impulse"), c(5, -0.16), tolerance = 1e-2)
  expect_equal(stop_at(sr03, "impulse", "permanent"), c(5, -1.16), tolerance = 1e-2)
})

test_that("until_neutralized is the default stop rule, truncates the history at the stop window and reports it", {
  g <- chain_network()
  r <- simulate_temporal_pair(g, build_press_vector(g, "P", c(P = 1)), build_press_vector(g, "R", c(R = 1)))
  expect_equal(r$stop_rule, "until_neutralized")
  expect_equal(r$windows, 7)
  expect_equal(nrow(r$scenario), 8)
  expect_match(temporal_stop_note(r), "Neutralized at window 7")

  never <- chain_run(g, "permanent", "impulse", stop_rule = "until_neutralized", max_windows = 12)
  expect_equal(never$windows, 12)
  expect_equal(temporal_stop_note(never), "Not neutralized within 12 windows.")
})

test_that("A3: 'Neutralized (relative)' only when |net| is within 5% of the baseline AND not growing", {
  damp <- chain_run(chain_network(sr03), "permanent", "impulse", windows = 30)
  tbl <- format_temporal_table(chain_network(sr03), damp)
  expect_equal(tbl$verdict[tbl$window == 30], "Neutralized (relative)")

  # Counter-example: baseline grows faster than the scenario - from window
  # 61 on (exactly 5% at window 60) |net| is below 5% of the baseline, but
  # the Impact is still getting worse.
  grow <- chain_run(chain_network(), "permanent", "impulse", windows = 61)
  tbl_g <- format_temporal_table(chain_network(), grow)
  last <- tbl_g[tbl_g$window == 61, ]
  expect_lt(abs(last$net_impact), 0.05 * last$baseline_impact)
  expect_equal(last$verdict, "Partial")
})

test_that("A4: baseline_without_response ignores Impact -> Response links in the baseline round only", {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("P", "E", "I", "R"), label = c("P", "E", "I", "R"),
    dpsir_category = c("Pressure", "State", "Impact", "Response"), self_regulation = 0, stringsAsFactors = FALSE
  ))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("P", "E", "R", "I"), to = c("E", "I", "P", "R"), weight = c(0.5, 0.5, 0.5, 0.5),
    interaction_type = c("negative", "negative", "negative", "positive"), stringsAsFactors = FALSE
  ))
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())
  p_D <- build_press_vector(g, "P", c(P = 1))
  with_links <- simulate_temporal_pair(g, p_D, zero_press(g), windows = 6)
  without <- simulate_temporal_pair(g, p_D, zero_press(g), windows = 6, baseline_without_response = TRUE)

  expect_true(any(with_links$baseline[, "R"] != 0))
  expect_true(all(without$baseline[, "R"] == 0))
  expect_equal(without$scenario, with_links$scenario)
})
