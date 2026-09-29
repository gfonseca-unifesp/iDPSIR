# =====================================================
# TESTS - R/relevance.R (Revisao 2, Fase B)
# =====================================================

# Section 4 example of the relevance specification v1.0: P, S, I1
# (ecological), I2 (welfare), with the community matrix A (diagonal -0.5,
# -0.6, -0.7, -0.7). In standardized form beta_ij = a_ij / |a_ii| and the
# press on P is 1 / |a_PP| = 2 - then the app's total effect equals Levins'
# -A^-1 u exactly (prototipos_revisao2/modo_estrutural.R). The P -> I2 edge
# is not allowed by the default schema, so the graph is built directly.
pdf_example <- function() {
  nodes <- data.frame(
    id = c("P", "S", "I1", "I2"), label = c("P", "S", "I1", "I2"),
    dpsir_category = c("Pressure", "State", "Impact", "Impact"),
    endpoint_class = c(NA, NA, "ecological", "welfare"), value_v = c(NA, NA, 1, 0.6),
    stringsAsFactors = FALSE
  )
  beta <- c(-0.8 / 0.6, 0.9 / 0.7, -0.5 / 0.7, 0.4 / 0.7)
  edges <- data.frame(
    from = c("P", "S", "P", "S"), to = c("S", "I1", "I2", "I2"),
    weight = abs(beta), weight_low = abs(beta), weight_high = abs(beta),
    interaction_type = ifelse(beta < 0, "negative", "positive"), stringsAsFactors = FALSE
  )
  graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
}

test_that("B3: dynamic importance D reproduces the specification's section 4 (Levins, standardized): D(I1) = 1.00, D(I2) = 0.86", {
  g <- pdf_example()
  di <- dynamic_importance(g, c(P = 2, S = 0, I1 = 0, I2 = 0))
  expect_equal(di$delta, c(-3.43, -2.95), tolerance = 1e-2)
  expect_equal(di$D, c(1.00, 0.86), tolerance = 1e-2)
})

test_that("B4: reliability is 1 when every band is a single value, NA for an Impact the pressure does not reach", {
  g <- pdf_example()
  rel <- prediction_reliability(g, c(P = 2, S = 0, I1 = 0, I2 = 0), n_simulations = 20)
  expect_equal(rel$rho, c(1, 1))

  g0 <- pdf_example()
  rel0 <- prediction_reliability(g0, c(P = 0, S = 0, I1 = 0, I2 = 0), n_simulations = 5)
  expect_true(all(is.na(rel0$rho)))
})

test_that("B4: reliability drops below 1 when two opposite paths compete within wide bands", {
  g <- pdf_example()
  # I2 gets a direct negative path (P -> I2) and an indirect positive-times-
  # negative path (P -> S -> I2, net negative too); flip S -> I2 to positive
  # effect of opposite overall sign so the two paths compete.
  E(g)$interaction_type[4] <- "negative"
  E(g)$weight_low <- E(g)$weight * 0.2
  E(g)$weight_high <- E(g)$weight * 1.8
  rel <- prediction_reliability(g, c(P = 2, S = 0, I1 = 0, I2 = 0), n_simulations = 200)
  expect_equal(rel$rho[1], 1)
  expect_lt(rel$rho[2], 1)
})

test_that("B5: gap is the uncovered share of the worsening; 0 when neutralized; NA when not worsened", {
  suff <- data.frame(id = c("A", "B", "C", "D"), worsening = c(0.42, 0.30, 0, 0.2), net = c(0.084, -0.05, 0, 0.5))
  expect_equal(unname(impact_gap(suff)), c(0.2, 0, NA, 1))
})

test_that("B7: relevance = v x D x rho and priority = relevance x gap, ordered by priority", {
  g <- pdf_example()
  p_D <- c(P = 2, S = 0, I1 = 0, I2 = 0)
  suff <- data.frame(id = c("I1", "I2"), worsening = c(0.5, 0.4), net = c(0.1, 0.4))
  pr <- impact_prioritization(g, p_D, suff, n_simulations = 10)

  i1 <- pr[pr$id == "I1", ]; i2 <- pr[pr$id == "I2", ]
  expect_equal(i1$relevance, 1 * 1 * 1)
  expect_equal(i2$relevance, 0.6 * 0.86 * 1, tolerance = 1e-2)
  expect_equal(i1$priority, 1 * 0.2)
  expect_equal(i2$priority, i2$relevance * 1, tolerance = 1e-9)
  expect_equal(pr$id, c("I2", "I1")) # I2 is less relevant but fully uncovered
  expect_equal(format_prioritization_table(pr)$Gap, c("1.00", "0.20"))
})

test_that("B1: endpoint_class / value_v - defaults, ecological forced to 1, Impact-only", {
  nodes <- data.frame(
    id = c("P", "I1", "I2", "I3"), label = c("P", "I1", "I2", "I3"),
    dpsir_category = c("Pressure", "Impact", "Impact", "Impact"),
    endpoint_class = c(NA, NA, "Welfare", "ecological"), value_v = c(NA, 0.3, 0.6, 0.4),
    stringsAsFactors = FALSE
  )
  out <- normalize_dpsir_nodes(nodes)
  expect_equal(out$endpoint_class, c(NA, "ecological", "welfare", "ecological"))
  expect_equal(out$value_v, c(NA, 1, 0.6, 1))

  bad <- data.frame(id = c("P", "I"), label = c("P", "I"), dpsir_category = c("Pressure", "Impact"),
                    endpoint_class = c("service", "social"), value_v = c(0.5, 2))
  pf <- preflight_import_nodes(bad)
  expect_true(any(grepl("row 2: endpoint_class is only for Impact", pf$blocking)))
  expect_true(any(grepl("endpoint_class 'social'", pf$blocking)))
  expect_true(any(grepl("row 3: value_v '2'", pf$blocking)))
})

test_that("B6: sign aliases of the specification are mapped to positive/negative, with a preflight note", {
  nodes <- data.frame(id = c("D1", "P1", "S1"), label = c("a", "b", "c"), dpsir_category = c("Driver", "Pressure", "State"))
  edges <- data.frame(from = c("D1", "P1"), to = c("P1", "S1"), interaction_type = c("increases", "Mitigates"))
  pf <- preflight_import(nodes, edges)
  expect_length(pf$blocking, 0)
  expect_true(any(grepl("2 interaction_type value\\(s\\) mapped", pf$warnings)))
  expect_equal(normalize_dpsir_edges(edges)$interaction_type, c("positive", "negative"))
})
