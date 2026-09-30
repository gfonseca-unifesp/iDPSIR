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

# Same trophic chain as stable_chain_matrix(), as a real igraph object (with
# weight/confidence edge attributes) for functions that need a graph, not
# just a bare matrix - e.g. global_sensitivity(). Values matched by
# construction: build_interaction_matrix(stable_chain_graph()) is identical
# to stable_chain_matrix().
stable_chain_graph <- function() {
  nodes <- data.frame(id = c("Resource", "Consumer", "Predator"), stringsAsFactors = FALSE)
  edges <- data.frame(
    from = c("Resource", "Consumer", "Resource", "Predator", "Consumer"),
    to   = c("Resource", "Resource", "Consumer", "Consumer", "Predator"),
    weight = c(1, 1, 1, 1, 1),
    confidence = c(0.9, 0.8, 0.8, 0.7, 0.8),
    interaction_type = c("negative", "negative", "positive", "negative", "positive"),
    stringsAsFactors = FALSE
  )
  graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
}

fisheries_graph <- function() {
  sp <- read_savepoint("fixtures/legacy_fisheries.idpsir.json", convert_legacy = FALSE)
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

test_that("build_interaction_matrix adds a diagonal term from self_regulation (roadmap item 9.1)", {
  # Revisao 1, Fase 5: self_regulation e numerico direto agora (nao mais
  # none/low/medium/high) - self_regulation_diagonal() so negativa o valor
  # (0.5 digitado vira -0.5 na diagonal), sem tabela de mapeamento.
  nodes <- data.frame(
    id = c("A", "B", "C", "D"),
    self_regulation = c(0, 0.5, 1, 2),
    stringsAsFactors = FALSE
  )
  edges <- data.frame(from = character(), to = character(), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  A <- build_interaction_matrix(g)

  expect_equal(unname(diag(A)), c(0, -0.5, -1, -2))
})

test_that("build_interaction_matrix treats a missing self_regulation attribute as none (backward compatibility)", {
  nodes <- data.frame(id = c("A", "B"), stringsAsFactors = FALSE) # no self_regulation column at all
  edges <- data.frame(from = "A", to = "B", weight = 1, interaction_type = "positive", stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  A <- build_interaction_matrix(g)

  expect_equal(unname(diag(A)), c(0, 0))
})
