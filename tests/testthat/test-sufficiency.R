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

# Revisao 2, item 1.6: data/mangi2007_edges.csv now holds standardized
# strengths (beta) - the older weights converted with beta = lambda * w
# (c = 0.5), rounded to 3 decimals. The numbers below, from the Revisao 1
# static reading, therefore still hold within the 1e-3 tolerance.
mangi_graph <- function() {
  nodes <- data.table::fread("../../data/mangi2007_nodes.csv", data.table = FALSE)
  edges <- data.table::fread("../../data/mangi2007_edges.csv", data.table = FALSE)
  build_igraph(normalize_dpsir_nodes(nodes), normalize_dpsir_edges(edges), get_default_dpsir_schema())
}

zero_press <- function(g) {
  setNames(rep(0, vcount(g)), V(g)$name)
}

test_that("build_signed_matrix always has a zero diagonal, even with a legacy self_regulation attribute", {
  g <- mangi_graph()
  A <- effect_matrix(g)
  expect_true(all(diag(A) == 0))

  # A savepoint from before this revision could still carry self_regulation
  # on the graph - effect_matrix() must ignore it silently, with no
  # special-case code, by zeroing the diagonal regardless of what
  # build_interaction_matrix() filled in.
  V(g)$self_regulation <- "high"
  A2 <- effect_matrix(g)
  expect_true(all(diag(A2) == 0))
})

test_that("spectral_radius returns 0 for a graph with no edges, not NaN or an error", {
  nodes <- data.frame(id = c("A", "B"), stringsAsFactors = FALSE)
  edges <- data.frame(from = character(), to = character(), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
  W <- effect_matrix(g)

  expect_equal(spectral_radius(W), 0)
})

test_that("propagate() gives a non-zero effect on a purely acyclic network, not the all-zero fallback meant for a truly edge-less graph (real bug, Fase 9)", {
  # Hand-built A->B->C chain, weight 1 each - a real, valid causal network
  # with zero eigenvalues (nilpotent W, no cycle anywhere), same as the
  # Gnanapragasam et al. 2026 example network (Fase 9) that surfaced this:
  # W has real edges but spectral_radius(W) == 0, same value a truly
  # edge-less matrix returns. The two were conflated before this fix,
  # discarding a well-defined, non-zero effect for every acyclic network -
  # verified against scratchpad/verify_propagate_fix.R before hardcoding.
  nodes <- data.frame(id = c("A", "B", "C"), dpsir_category = c("Driver", "Pressure", "State"), stringsAsFactors = FALSE)
  edges <- data.frame(
    from = c("A", "B"), to = c("B", "C"), weight = 0.5, confidence = 1,
    interaction_type = "positive", stringsAsFactors = FALSE
  )
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  W <- effect_matrix(g)
  expect_equal(spectral_radius(W), 0) # nilpotent, not edge-less
  expect_false(all(W == 0)) # confirms it's the nilpotent case, not the truly empty one

  press <- setNames(c(1, 0, 0), c("A", "B", "C"))
  effect <- propagate(W, press)

  expect_equal(unname(effect["A"]), 0)
  expect_equal(unname(effect["B"]), 0.5)
  expect_equal(unname(effect["C"]), 0.25)
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

  W <- effect_matrix(g)
  press <- build_press_vector(g, active_ids = V(g)$name[1], strengths = setNames(1, V(g)$name[1]))
  result <- propagate(W, press)

  expect_false(any(is.na(result)))
})

test_that("sufficiency fixes the real sign-inversion bug: R2 (Gear restrictions) helps the Reef, not worsens it", {
  g <- mangi_graph()
  p_R2 <- build_press_vector(g, active_ids = "R2", strengths = c(R2 = 1))

  suff <- sufficiency(g, p_D = zero_press(g), p_R = p_R2)
  reef <- suff[suff$id == "I2", ]

  expect_lt(reef$mitigation, 0) # negative = helps, the correct sign
})

test_that("sufficiency on the Mangi worked example (R1/AMP vs D1+D3 pressure) matches the revision's own Table 1", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R1 <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))

  suff <- sufficiency(g, p_D, p_R1)
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

  suff <- sufficiency(g, p_D, p_R2)
  rownames(suff) <- suff$id

  # R2 only acts on P2, which doesn't feed I1 (Catch decline) at all in this
  # network - mitigation should be ~0 there and not neutralize.
  expect_false(suff["I1", "neutralized"])
  expect_true(is.na(suff["I1", "strength_to_neutralize"]))
})

test_that("sufficiency_confidence gives exactly 100% when every edge's uncertainty band is a single value", {
  g <- mangi_graph()
  E(g)$weight_low <- E(g)$weight
  E(g)$weight_high <- E(g)$weight
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R1 <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 1))

  sc <- sufficiency_confidence(g, p_D, p_R1, n_simulations = 20)

  expect_true(all(sc$neutralized_pct == 100))
})

test_that("sufficiency_confidence reproduces the revision's Table 2 pattern: R1 neutralizes all three, R2/R3/R5 only the reef", {
  g <- mangi_graph()
  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))

  check_one <- function(response_id) {
    p_r <- build_press_vector(g, active_ids = response_id, strengths = setNames(1, response_id))
    sc <- sufficiency_confidence(g, p_D, p_r, n_simulations = 300)
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
  a <- sufficiency_confidence(g, p_D, p_R4, n_simulations = 100)
  set.seed(1)
  b <- sufficiency_confidence(g, p_D, p_R4, n_simulations = 100)

  expect_identical(a, b)
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
  suff <- sufficiency(g, p_D, p_R1)

  single <- format_sufficiency_table(suff, "R1", c(R1 = 66))
  i1_row <- single[single$Impact == "Catch decline (reduced CPUE)", ]
  # strength_to_neutralize (Table 1 of the review, ~0.660) * 66% strength ~= 44%
  expect_match(i1_row[["Strength needed"]], "^\\d+%$")

  combined <- format_sufficiency_table(suff, c("R1", "R2"), c(R1 = 66, R2 = 40))
  i1_row_combined <- combined[combined$Impact == "Catch decline (reduced CPUE)", ]
  expect_match(i1_row_combined[["Strength needed"]], "^x[0-9.]+$")
})

# Revisao 2, item 0.3: press vectors are aligned by factor name, never by
# position - a saved scenario whose vector is out of order, or that predates
# a node added later, must give the right numbers (or a clear error).
test_that("sufficiency() aligns press vectors by name: shuffled order gives identical results", {
  g <- mangi_graph()
  p_D <- zero_press(g); p_D[c("D1", "D3")] <- 1
  p_R <- zero_press(g); p_R["R1"] <- 1

  base <- sufficiency(g, p_D, p_R)
  shuffled <- sufficiency(g, rev(p_D), sample(p_R))

  expect_equal(shuffled, base)
})

test_that("sufficiency() treats factors missing from a named press vector as 0 (scenario saved before a node was added)", {
  g <- mangi_graph()
  p_D_full <- zero_press(g); p_D_full[c("D1", "D3")] <- 1
  p_R_full <- zero_press(g); p_R_full["R1"] <- 1

  expect_equal(
    sufficiency(g, p_D_full[c("D1", "D3")], p_R_full["R1"]),
    sufficiency(g, p_D_full, p_R_full)
  )
})

test_that("sufficiency() stops with a clear message when a press vector names a factor not in the network", {
  g <- mangi_graph()
  p_D <- zero_press(g); p_D["D1"] <- 1
  p_R <- c(p_D * 0, R_removed = 1)

  expect_error(sufficiency(g, p_D, p_R), "not in the network: R_removed")
})

test_that("align_press_vector() rejects an unnamed vector of the wrong length instead of recycling it", {
  expect_error(align_press_vector(c(1, 0), c("A", "B", "C")), "has 2 values but the network has 3")
  expect_equal(align_press_vector(c(1, 0, 0), c("A", "B", "C")), c(A = 1, B = 0, C = 0))
})

# Revisao 2, Fase 1 (structural mode): the total effect is the path-analysis
# product of betas, with no reach factor c - worked example of Anexo X2.4,
# verified in R (prototipos_revisao2/modo_estrutural.R).
structural_example <- function(beta_rp1 = 0.8) {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("P1", "P2", "S", "I", "R"), label = c("P1", "P2", "S", "I", "R"),
    dpsir_category = c("Pressure", "Pressure", "State", "Impact", "Response"), stringsAsFactors = FALSE
  ))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("P1", "P2", "S", "R"), to = c("S", "S", "I", "P1"),
    weight = c(0.7, 0.5, 0.6, beta_rp1), interaction_type = "negative", stringsAsFactors = FALSE
  ))
  build_igraph(nodes, edges, get_default_dpsir_schema())
}

test_that("structural total effect: P1 -> I is 0.42, R -> I is -0.336, 80% mitigation, 125% to neutralize", {
  g <- structural_example()
  p_D <- build_press_vector(g, "P1", c(P1 = 1))
  p_R <- build_press_vector(g, "R", c(R = 1))
  suff <- sufficiency(g, p_D, p_R)

  expect_equal(suff$worsening, 0.42, tolerance = 1e-9)
  expect_equal(suff$mitigation, -0.336, tolerance = 1e-9)
  expect_equal(suff$strength_to_neutralize, 1.25, tolerance = 1e-9)
  expect_false(suff$neutralized)
})

test_that("propagate() and check_effect_matrix() block a network whose loops amplify (rho(B) >= 1), naming the loop edges", {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("P", "S", "I", "R"), label = c("P", "S", "I", "R"),
    dpsir_category = c("Pressure", "State", "Impact", "Response"), stringsAsFactors = FALSE
  ))
  edges <- normalize_dpsir_edges(data.frame(
    from = c("P", "S", "I", "R"), to = c("S", "I", "R", "P"),
    weight = c(1.2, 1, 1, 1), interaction_type = "positive", stringsAsFactors = FALSE
  ))
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())

  expect_error(check_effect_matrix(g), "spectral radius 1.05.*P -> S")
  expect_error(propagate(effect_matrix(g), c(P = 1, S = 0, I = 0, R = 0)), "must be below 1")
})
