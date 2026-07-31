# =====================================================
# TESTS - R/sufficiency.R (Revisao 1: "two pushes" model)
# =====================================================
#
# Primary fixture: the Mangi et al. 2007 network (data/mangi2007_*.csv), a
# real, cited network - not a hand-built toy. Every expected number below
# was independently computed in scratchpad/test_sufficiency.R before being
# hardcoded here, and closely reproduces (within rounding) the worked
# example in the revision document itself (Section 4, Table 1: R1/AMP
# against pressure D1+D3) - not asserted from a guess.
#
# The single most important test here is the regression one: on the OLD
# equilibrium engine (press_perturbation(), R/loop_analysis.R), this exact
# network showed Gear restrictions (R2) with equilibrium +0.81 ("worsening")
# on Reef ecosystem degradation - a sign inversion, confirmed in
# manuscrito/idpsir_report_2026-07-28_GF.html. The whole point of this
# revision is that sufficiency()'s mitigation for that same scenario comes
# out negative (correctly "helps").

mangi_graph <- function() {
  nodes <- data.table::fread("../../data/mangi2007_nodes.csv", data.table = FALSE)
  edges <- data.table::fread("../../data/mangi2007_edges.csv", data.table = FALSE)
  nodes <- normalize_dpsir_nodes(nodes)
  edges <- normalize_dpsir_edges(edges)
  build_igraph(nodes, edges, get_default_dpsir_schema())
}

zero_press <- function(g) {
  setNames(rep(0, vcount(g)), V(g)$name)
}

test_that("build_signed_matrix always has a zero diagonal, even with a legacy self_regulation attribute", {
  g <- mangi_graph()
  A <- build_signed_matrix(g)
  expect_true(all(diag(A) == 0))

  # A savepoint from before this revision could still carry self_regulation
  # on the graph - build_signed_matrix() must ignore it silently, with no
  # special-case code, by zeroing the diagonal regardless of what
  # build_interaction_matrix() filled in.
  V(g)$self_regulation <- "high"
  A2 <- build_signed_matrix(g)
  expect_true(all(diag(A2) == 0))
})

test_that("spectral_radius returns 0 for a graph with no edges, not NaN or an error", {
  nodes <- data.frame(id = c("A", "B"), stringsAsFactors = FALSE)
  edges <- data.frame(from = character(), to = character(), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
  W <- build_signed_matrix(g)

  expect_equal(spectral_radius(W), 0)
})

test_that("propagate never fails - not even on the network already known to be singular for -A^-1", {
  # data/sample_nodes.csv + sample_edges.csv is documented elsewhere in this
  # project (Fase 5 Marco A) as producing a singular interaction matrix,
  # where press_perturbation() falls back to NA. propagate() must not.
  nodes <- data.table::fread("../../data/sample_nodes.csv", data.table = FALSE)
  edges <- data.table::fread("../../data/sample_edges.csv", data.table = FALSE)
  nodes <- normalize_dpsir_nodes(nodes)
  edges <- normalize_dpsir_edges(edges)
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())

  W <- build_signed_matrix(g)
  press <- build_press_vector(g, active_ids = V(g)$name[1], strengths = setNames(1, V(g)$name[1]))
  result <- propagate(W, press, c = 0.5)

  expect_false(any(is.na(result)))
})

test_that("sufficiency fixes the real sign-inversion bug: R2 (Gear restrictions) helps the Reef, not worsens it", {
  g <- mangi_graph()
  p_R2 <- build_press_vector(g, active_ids = "R2", strengths = c(R2 = 1))

  suff <- sufficiency(g, p_D = zero_press(g), p_R = p_R2, c = 0.5)
  reef <- suff[suff$id == "I2", ]

  expect_lt(reef$mitigation, 0) # negative = helps, the correct sign
})

test_that("sufficiency on the Mangi worked example (R1/AMP vs D1+D3 pressure) matches the revision's own Table 1", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R1 <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))

  suff <- sufficiency(g, p_D, p_R1, c = 0.5)
  rownames(suff) <- suff$id

  expect_equal(suff["I1", "worsening"], 0.1096, tolerance = 1e-3)
  expect_equal(suff["I1", "mitigation"], -0.1660, tolerance = 1e-3)
  expect_true(suff["I1", "neutralized"])
  expect_equal(suff["I1", "strength_to_neutralize"], 0.660, tolerance = 1e-2)

  expect_equal(suff["I2", "worsening"], 0.0301, tolerance = 1e-3)
  expect_equal(suff["I2", "mitigation"], -0.0929, tolerance = 1e-3)
  expect_true(suff["I2", "neutralized"])
  expect_equal(suff["I2", "strength_to_neutralize"], 0.324, tolerance = 1e-2)

  expect_equal(suff["I3", "worsening"], 0.0496, tolerance = 1e-3)
  expect_equal(suff["I3", "mitigation"], -0.1023, tolerance = 1e-3)
  expect_true(suff["I3", "neutralized"])
  expect_equal(suff["I3", "strength_to_neutralize"], 0.485, tolerance = 1e-2)
})

test_that("sufficiency reports NA strength_to_neutralize when the response doesn't help an Impact at all", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R2 <- build_press_vector(g, active_ids = "R2", strengths = c(R2 = 1))

  suff <- sufficiency(g, p_D, p_R2, c = 0.5)
  rownames(suff) <- suff$id

  # R2 only acts on P2, which doesn't feed I1 (Catch decline) at all in this
  # network - mitigation should be ~0 there and not neutralize.
  expect_false(suff["I1", "neutralized"])
  expect_true(is.na(suff["I1", "strength_to_neutralize"]))
})

test_that("sufficiency_confidence gives exactly 100% when every edge has confidence = 1", {
  g <- mangi_graph()
  E(g)$confidence <- 1
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R1 <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))

  sc <- sufficiency_confidence(g, p_D, p_R1, c = 0.5, n_simulations = 20)

  expect_true(all(sc$neutralized_pct == 100))
})

test_that("sufficiency_confidence reproduces the revision's Table 2 pattern: R1 neutralizes all three, R2/R3/R5 only the reef", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))

  check_one <- function(response_id) {
    p_r <- build_press_vector(g, active_ids = response_id, strengths = setNames(1, response_id))
    sc <- sufficiency_confidence(g, p_D, p_r, c = 0.5, n_simulations = 300)
    setNames(sc$neutralized_pct, sc$id)
  }

  r1 <- check_one("R1")
  expect_equal(unname(r1[c("I1", "I2", "I3")]), c(100, 100, 100))

  r2 <- check_one("R2")
  expect_equal(unname(r2["I2"]), 100)
  expect_equal(unname(r2[c("I1", "I3")]), c(0, 0))

  r5 <- check_one("R5")
  expect_equal(unname(r5["I2"]), 100)
  expect_equal(unname(r5[c("I1", "I3")]), c(0, 0))
})

test_that("sufficiency_confidence with the default seed is reproducible across repeated calls", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R4 <- build_press_vector(g, active_ids = "R4", strengths = c(R4 = 1))

  set.seed(999)
  a <- sufficiency_confidence(g, p_D, p_R4, c = 0.5, n_simulations = 100)
  set.seed(1)
  b <- sufficiency_confidence(g, p_D, p_R4, c = 0.5, n_simulations = 100)

  expect_identical(a, b)
})

test_that("sufficiency_reach_over_c flags no boundary cases when every verdict is unanimous", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R1 <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))

  src <- sufficiency_reach_over_c(g, p_D, p_R1)

  expect_false(any(src$flips))
})

test_that("sufficiency and sufficiency_confidence return an empty data.frame, not an error, when the graph has no Impact nodes", {
  nodes <- data.frame(id = c("D1", "P1"), label = c("D1", "P1"), dpsir_category = c("Driver", "Pressure"), stringsAsFactors = FALSE)
  edges <- data.frame(from = "D1", to = "P1", weight = 1, confidence = 0.8, interaction_type = "positive", stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
  press <- zero_press(g)

  expect_equal(nrow(sufficiency(g, press, press)), 0)
  expect_equal(nrow(sufficiency_confidence(g, press, press, n_simulations = 5)), 0)
})

test_that("format_sufficiency_table shows an absolute strength for a single response, a ratio for a combined one", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R1 <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))
  suff <- sufficiency(g, p_D, p_R1, c = 0.5)

  single <- format_sufficiency_table(suff, "R1", c(R1 = 66))
  i1_row <- single[single$Impact == "Catch decline (reduced CPUE)", ]
  # strength_to_neutralize (Table 1 of the review, ~0.660) * 66% strength ~= 44%
  expect_match(i1_row[["Strength needed"]], "^\\d+%$")

  combined <- format_sufficiency_table(suff, c("R1", "R2"), c(R1 = 66, R2 = 40))
  i1_row_combined <- combined[combined$Impact == "Catch decline (reduced CPUE)", ]
  expect_match(i1_row_combined[["Strength needed"]], "^x[0-9.]+$")
})

test_that("format_reach_over_c_table never produces an empty column name (the real DT crash found live)", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R1 <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))
  src <- sufficiency_reach_over_c(g, p_D, p_R1)

  display <- format_reach_over_c_table(src)

  expect_true(all(nzchar(names(display))))
  expect_equal(names(display)[1], "Impact")
  expect_equal(names(display)[length(names(display))], "Verdict")
  expect_equal(nrow(display), nrow(src))
})
