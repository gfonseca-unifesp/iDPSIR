# =====================================================
# TESTS - R/loop_analysis.R (the scientific core)
# =====================================================
#
# Two families of fixtures, both hand/independently verified before being
# written here (never asserted from a guess):
#
# 1. A classic 3-species trophic chain (Resource -[-]-> self, Resource <-[-]-
#    Consumer, Resource -[+]-> Consumer, Consumer <-[-]- Predator, Consumer
#    -[+]-> Predator) built directly as a plain matrix, bypassing
#    build_igraph()/the DPSIR schema entirely - this is deliberate: the
#    schema forbids a node acting on itself, so no graph built through the
#    app can ever have this matrix's self-regulating diagonal term, and
#    verifying check_stability() against a genuinely stable case requires
#    one. Confirmed independently via `eigen()` before being hardcoded here
#    (see scratchpad note in CLAUDE.md's Fase 5 evaluation).
#
# 2. docs/example_fisheries.idpsir.json, the tutorial's worked example - a
#    real DPSIR network built the normal way (schema + build_igraph()), and
#    every number below was already independently verified multiple times
#    this session (standalone script + live app), not invented for this test.

stable_chain_matrix <- function() {
  matrix(
    c(
      -1, -1, 0,
      1, 0, -1,
      0, 1, 0
    ),
    nrow = 3, byrow = TRUE,
    dimnames = list(
      c("Resource", "Consumer", "Predator"),
      c("Resource", "Consumer", "Predator")
    )
  )
}

fisheries_graph <- function() {
  sp <- read_savepoint("../../docs/example_fisheries.idpsir.json")
  build_igraph(sp$nodes, sp$edges, get_default_dpsir_schema())
}

test_that("build_interaction_matrix extracts sign and weight from interaction_type/weight", {
  nodes <- data.frame(id = c("A", "B", "C"), stringsAsFactors = FALSE)
  edges <- data.frame(
    from = c("A", "B"), to = c("B", "C"), weight = c(2, 3),
    interaction_type = c("positive", "negative"), stringsAsFactors = FALSE
  )
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  A <- build_interaction_matrix(g)

  expect_equal(A["B", "A"], 2)
  expect_equal(A["C", "B"], -3)
  expect_equal(A["A", "B"], 0)
  expect_equal(sum(diag(A)), 0)
})

test_that("build_interaction_matrix returns a zero matrix for a graph with no edges", {
  nodes <- data.frame(id = c("A", "B"), stringsAsFactors = FALSE)
  edges <- data.frame(from = character(), to = character(), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  A <- build_interaction_matrix(g)

  expect_equal(dim(A), c(2, 2))
  expect_true(all(A == 0))
})

test_that("check_stability recognizes the classic stable trophic chain", {
  stab <- check_stability(stable_chain_matrix())

  expect_true(stab$stable)
  expect_true(all(Re(stab$eigenvalues) < 0))
})

test_that("press_perturbation matches hand-verified immediate/equilibrium on the stable chain", {
  A <- stable_chain_matrix()
  press <- c(Resource = 0, Consumer = 0, Predator = 1)

  result <- press_perturbation(A, press)

  expect_equal(unname(result$immediate), c(0, -1, 0))
  expect_equal(unname(result$equilibrium), c(1, -1, 1))
})

test_that("press_perturbation returns NA with a warning for a singular interaction matrix", {
  # D1 has no incoming edge at all -> its row in A is all zero -> A is
  # singular regardless of what the rest of the matrix looks like.
  A <- matrix(
    c(0, 0, 1, 0),
    nrow = 2, byrow = TRUE,
    dimnames = list(c("D1", "P1"), c("D1", "P1"))
  )
  press <- c(D1 = 0, P1 = 1)

  expect_warning(result <- press_perturbation(A, press), "singular")
  expect_true(all(is.na(result$equilibrium)))
  expect_false(any(is.na(result$immediate)))
})

test_that("simulate_trajectory converges to -A^-1 * press for a stable network", {
  A <- stable_chain_matrix()
  press <- c(0, 0, 1)

  traj <- simulate_trajectory(A, press, steps = 40, step_size = 0.5)
  final_state <- traj[40, ]

  expect_equal(unname(final_state), c(1, -1, 1), tolerance = 1e-3)
})

test_that("simulate_trajectory diverges for the fisheries example (documented as unstable)", {
  g <- fisheries_graph()
  A <- build_interaction_matrix(g)
  press <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 0.7))

  expect_false(check_stability(A)$stable)

  traj <- simulate_trajectory(A, press, steps = 30, step_size = 0.5)
  magnitude_early <- sum(abs(traj[3, ]))
  magnitude_late <- sum(abs(traj[30, ]))

  expect_gt(magnitude_late, magnitude_early * 100)
})

test_that("simulate_trajectory_thresholded with Th = NULL is identical to simulate_trajectory (regression)", {
  A <- stable_chain_matrix()
  press <- c(0, 0, 1)

  traj_plain <- simulate_trajectory(A, press, steps = 10)
  traj_explicit <- simulate_trajectory_thresholded(A, press, Th = NULL, steps = 10)

  expect_equal(traj_plain, traj_explicit)
})

test_that("simulate_trajectory_thresholded gates an edge off until its source crosses the threshold", {
  A <- stable_chain_matrix()
  press <- c(0, 0, 1)

  Th <- matrix(NA_real_, nrow = 3, ncol = 3, dimnames = dimnames(A))
  Th["Consumer", "Resource"] <- 1e6 # never crossed in 10 small steps

  traj_gated <- simulate_trajectory_thresholded(A, press, Th = Th, steps = 10)
  traj_ungated <- simulate_trajectory(A, press, steps = 10)

  expect_false(isTRUE(all.equal(traj_gated, traj_ungated)))
})

test_that("robustness_check gives exactly 100% agreement when every edge has confidence = 1", {
  g <- fisheries_graph()
  E(g)$confidence <- 1
  press <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 0.7))

  robustness_df <- robustness_check(g, press, n_simulations = 5, spread = 0.9)

  expect_true(all(robustness_df$agreement_pct == 100))
})

test_that("robustness_check on the fisheries example matches the previously verified 100% agreement", {
  g <- fisheries_graph()
  press <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 0.7))

  set.seed(42)
  robustness_df <- robustness_check(g, press, n_simulations = 100, spread = 0.5)

  expect_true(all(robustness_df$agreement_pct == 100))
})

test_that("find_neutralization_step matches the previously verified step count on the fisheries example", {
  g <- fisheries_graph()
  A <- build_interaction_matrix(g)
  press <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 0.7))

  step <- find_neutralization_step(A, press, "I1")

  expect_equal(step, 2)
})

test_that("summarize_neutralization reports the fisheries Impact's equilibrium and step, and no other nodes", {
  g <- fisheries_graph()
  press <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 0.7))

  summary_df <- summarize_neutralization(g, press)

  expect_equal(nrow(summary_df), 1)
  expect_equal(summary_df$id, "I1")
  expect_equal(summary_df$equilibrium_effect, -0.7 / 1.5, tolerance = 1e-6)
  expect_equal(summary_df$steps_to_neutralize, 2)
})

test_that("press_perturbation on the fisheries example matches previously verified immediate/equilibrium", {
  g <- fisheries_graph()
  A <- build_interaction_matrix(g)
  press <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 0.7))

  result <- press_perturbation(A, press)

  expect_equal(unname(result$immediate["D1"]), -0.35, tolerance = 1e-9)
  expect_equal(unname(result$equilibrium["I1"]), -0.7 / 1.5, tolerance = 1e-9)
  expect_equal(unname(result$immediate[c("P1", "S1", "I1", "R1")]), c(0, 0, 0, 0))
  expect_equal(unname(result$equilibrium[c("D1", "P1", "S1", "R1")]), c(0, 0, 0, 0))
})
