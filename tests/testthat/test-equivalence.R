# Revisao 3, E1.2/E1.4: the static reading is the temporal equilibrium with
# self-regulation 1 on every node; with other self-regulation the
# equilibrium is (S - B)^-1 p, and self_regulation_sensitivity() reports
# whether a verdict depends on it.

example_graph <- function(name) {
  sp <- read_savepoint(sprintf("../../docs/%s.idpsir.json", name))
  list(g = build_igraph(sp$nodes, sp$edges, sp$schema), ss = sp$scenario_state)
}
pushes <- function(x) {
  list(pD = build_press_vector(x$g, x$ss$pressure_active, x$ss$pressure_strengths / 100),
       pR = build_press_vector(x$g, x$ss$response_active, x$ss$response_strengths / 100))
}

test_that("E1.2: with s = 1 the temporal equilibrium equals the static reading (Mangi, port, Sri Lanka)", {
  for (nm in c("example_mangi", "example_port", "example_gnanapragasam")) {
    x <- example_graph(nm); p <- pushes(x)
    se <- static_equivalent_windows(x$g, p$pD, s = 1)
    expect_true(se$converged, info = nm)
    expect_equal(se$equilibrium, propagate(effect_matrix(x$g), p$pD) + p$pD, tolerance = 1e-6, info = nm)
  }
})

test_that("E1.2: with s = 0.5 the equilibrium is solve(0.5 I - B, p)", {
  for (nm in c("example_mangi", "example_port", "example_gnanapragasam")) {
    x <- example_graph(nm); p <- pushes(x)
    B <- effect_matrix(x$g)
    se <- static_equivalent_windows(x$g, p$pD, s = 0.5)
    expect_true(se$converged, info = nm)
    expect_equal(se$equilibrium, setNames(as.numeric(solve(0.5 * diag(nrow(B)) - B, p$pD)), rownames(B)), tolerance = 1e-6, info = nm)
    expect_equal(temporal_equilibrium(x$g, p$pD, 0.5)$equilibrium, se$equilibrium, tolerance = 1e-6, info = nm)
  }
})

chain <- function() {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("D", "P", "S", "I", "R"), label = c("D", "P", "S", "I", "R"),
    dpsir_category = c("Driver", "Pressure", "State", "Impact", "Response"), stringsAsFactors = FALSE))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("D", "P", "S", "R"), to = c("P", "S", "I", "S"), weight = 0.6,
    interaction_type = c("positive", "negative", "negative", "positive"), stringsAsFactors = FALSE))
  build_igraph(nodes, edges, get_default_dpsir_schema())
}

test_that("E1.2/E1.4: a divergent self-regulation is detected, not simulated", {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("P", "S", "I", "R"), label = c("P", "S", "I", "R"),
    dpsir_category = c("Pressure", "State", "Impact", "Response"), stringsAsFactors = FALSE))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("P", "S", "I", "R"), to = c("S", "I", "R", "P"), weight = 0.9,
    interaction_type = c("negative", "negative", "positive", "negative"), stringsAsFactors = FALSE))
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())
  p <- build_press_vector(g, "P", c(P = 1))
  # rho(B) = 0.9^(4/4) < 1: the static reading exists...
  expect_lt(spectral_radius(effect_matrix(g)), 1)
  # ...but with s = 0.1 the temporal update amplifies.
  se <- static_equivalent_windows(g, p, s = 0.1)
  expect_false(se$converged)
  expect_false(temporal_equilibrium(g, p, 0.1)$converges)
  sens <- self_regulation_sensitivity(g, p, build_press_vector(g, "R", c(R = 1)), s_grid = c(0.1, 1))
  expect_equal(sens[["s=0.1"]], "Diverges")
  expect_true(sens$diverges)
})

test_that("E1.4: in an acyclic network paths of different length are rescaled by 1/s^(k+1), so a verdict can depend on s", {
  g <- chain()
  B <- effect_matrix(g)
  p <- build_press_vector(g, "D", c(D = 1))
  # Impact reached by the path D -> P -> S -> I (signs + - -): +0.6^3 / s^4.
  for (s in c(0.5, 1)) {
    expect_equal(unname(temporal_equilibrium(g, p, s)$equilibrium["I"]), 0.6^3 / s^4, tolerance = 1e-12)
  }
  # Response path R -> S -> I (+ -) has length 2: -0.36 r / s^3, one power of
  # s less than the pressure's. With r = 1 the net 0.216/s^4 - 0.36/s^3 is
  # <= 0 only for s >= 0.6, so a lower s favours the pressure.
  sens <- self_regulation_sensitivity(g, p, build_press_vector(g, "R", c(R = 1)), s_grid = c(0.25, 0.5, 1))
  expect_true(sens$depends_on_s)
  expect_equal(sens[["s=1"]], "Neutralized")
  expect_equal(sens[["s=0.5"]], "Not neutralized")
  expect_equal(sens[["s=0.25"]], "Not neutralized")
  expect_match(format_sr_sensitivity(sens), "^no: ")
})

test_that("E1.4: the s = 1 column always matches sufficiency(), with or without State triggers", {
  for (nm in c("example_mangi", "example_port", "example_gnanapragasam")) {
    x <- example_graph(nm); p <- pushes(x)
    sens <- self_regulation_sensitivity(x$g, p$pD, p$pR)
    suff <- sufficiency(x$g, p$pD, p$pR)
    k <- match(sens$id, suff$id)
    expected <- ifelse(suff$worsening[k] <= 1e-9, "Not affected", ifelse(suff$neutralized[k], "Neutralized", "Not neutralized"))
    expect_equal(sens[["s=1"]], expected, info = nm)
  }
})

test_that("E1.1: 100% is a push of 1 SD, and 5 units with SD 10 is 0.5", {
  g <- chain()
  igraph::V(g)$sd <- c(10, NA, NA, NA, NA)
  note <- press_units_note(g, build_press_vector(g, "D", c(D = 5 / 10)))
  expect_equal(note$push_sd, 0.5)
  expect_equal(note$push_units, 5)
  expect_equal(press_units_note(g, build_press_vector(g, "D", c(D = 100 / 100)))$push_sd, 1)
})
