# =====================================================
# TESTS - R/metrics.R
# =====================================================

test_that("compute_general_metrics reports correct node/edge counts and density on a small graph", {
  nodes <- data.frame(id = c("A", "B", "C"), stringsAsFactors = FALSE)
  edges <- data.frame(from = c("A", "B"), to = c("B", "C"), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  m <- compute_general_metrics(g)

  expect_equal(m$value[m$metric == "Nodes"], 3)
  expect_equal(m$value[m$metric == "Edges"], 2)
  expect_equal(m$value[m$metric == "Density"], 2 / (3 * 2), tolerance = 1e-9)
})

test_that("compute_diameter uses hop count, not summed weight, as distance", {
  nodes <- data.frame(id = c("A", "B", "C"), stringsAsFactors = FALSE)
  edges <- data.frame(from = c("A", "B"), to = c("B", "C"), weight = c(100, 100), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  expect_equal(compute_diameter(g), 2) # hops, would be 200 if weight were used as distance
})

test_that("compute_all_metrics computes total degree correctly on a simple directed path", {
  nodes <- data.frame(id = c("A", "B", "C"), label = c("A", "B", "C"), stringsAsFactors = FALSE)
  edges <- data.frame(from = c("A", "B"), to = c("B", "C"), weight = c(1, 1), confidence = c(1, 1), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  m <- compute_all_metrics(g, directed = TRUE, normalized = FALSE, weighted = FALSE)

  expect_equal(m$degree[m$id == "A"], 1)
  expect_equal(m$degree[m$id == "B"], 2)
  expect_equal(m$degree[m$id == "C"], 1)
})

test_that("compute_dpsir_descriptors flags impacts without a response and pressures not covered, matching the fisheries example", {
  sp <- read_savepoint("../../docs/example_fisheries.idpsir.json")
  schema <- get_default_dpsir_schema()
  g <- build_igraph(sp$nodes, sp$edges, schema)

  d <- compute_dpsir_descriptors(g, schema)

  expect_equal(d$impacts_without_response, character(0)) # I1 -> R1 exists
  expect_equal(d$pressures_without_response, "P1") # no Response -> Pressure edge in this example
  expect_equal(sum(d$count_by_category$n_nodes), 5)
})

test_that("compute_dpsir_descriptors' transition_matrix counts each source->target category edge once", {
  sp <- read_savepoint("../../docs/example_fisheries.idpsir.json")
  schema <- get_default_dpsir_schema()
  g <- build_igraph(sp$nodes, sp$edges, schema)

  d <- compute_dpsir_descriptors(g, schema)

  expect_equal(d$transition_matrix["Driver", "Pressure"], 1L)
  expect_equal(d$transition_matrix["Response", "Driver"], 1L)
  expect_equal(sum(d$transition_matrix), 5L)
})
