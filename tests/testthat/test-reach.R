# =====================================================
# TESTS - R/reach.R (roadmap Fase 9 item 9.2)
# =====================================================
#
# Two fixtures: docs/example_fisheries.idpsir.json (the tutorial's closed
# feedback loop, already used as fixture elsewhere in this suite) and a
# small hand-built acyclic tree with two responses - one acting near the
# root (Pressure) and one acting at the end of the chain (Impact) - to
# demonstrate the root-vs-end-of-chain contrast this feature exists for.
# Every number below was checked against scratchpad/test_reach.R before
# being hardcoded here, not asserted from a guess.

fisheries_graph <- function() {
  sp <- read_savepoint("../../docs/example_fisheries.idpsir.json")
  build_igraph(sp$nodes, sp$edges, get_default_dpsir_schema())
}

root_vs_end_graph <- function() {
  nodes <- data.frame(
    id = c("D1", "P1", "S1", "I1", "R1", "R2"),
    label = c("D1", "P1", "S1", "I1", "R1", "R2"),
    dpsir_category = c("Driver", "Pressure", "State", "Impact", "Response", "Response"),
    stringsAsFactors = FALSE
  )
  edges <- data.frame(
    from = c("D1", "P1", "S1", "R1", "R2"),
    to   = c("P1", "S1", "I1", "P1", "I1"),
    weight = 1, confidence = 0.8, interaction_type = "positive",
    stringsAsFactors = FALSE
  )
  graph_from_data_frame(edges, vertices = nodes, directed = TRUE)
}

test_that("response_reach on the fisheries closed loop reaches every other node in the cycle", {
  g <- fisheries_graph()

  result <- response_reach(g, "R1")

  expect_equal(result$total, 4)
  expect_setequal(result$reached_ids, c("D1", "P1", "S1", "I1"))
  expect_equal(count_impacts_in_graph(g), 1)
})

test_that("response_reach distinguishes a root response from an end-of-chain response", {
  g <- root_vs_end_graph()

  root_result <- response_reach(g, "R1") # acts on P1, near the root
  expect_equal(root_result$total, 3)
  expect_setequal(root_result$reached_ids, c("P1", "S1", "I1"))

  end_result <- response_reach(g, "R2") # acts directly on the Impact
  expect_equal(end_result$total, 1)
  expect_setequal(end_result$reached_ids, "I1")

  expect_gt(root_result$total, end_result$total)
})

test_that("response_reach returns an empty result for no active responses", {
  g <- root_vs_end_graph()

  result <- response_reach(g, character())

  expect_equal(result$total, 0)
  expect_length(result$reached_ids, 0)
  expect_equal(nrow(result$by_category), 0)
})

test_that("response_reach returns an empty result for a response with no outgoing edges", {
  nodes <- data.frame(id = c("R3", "D1"), label = c("R3", "D1"), dpsir_category = c("Response", "Driver"), stringsAsFactors = FALSE)
  edges <- data.frame(from = character(), to = character(), weight = numeric(), confidence = numeric(), interaction_type = character(), stringsAsFactors = FALSE)
  g <- graph_from_data_frame(edges, vertices = nodes, directed = TRUE)

  result <- response_reach(g, "R3")

  expect_equal(result$total, 0)
})

test_that("response_reach ignores active_ids that aren't in the graph", {
  g <- root_vs_end_graph()

  result <- response_reach(g, c("R1", "not_a_real_id"))

  expect_equal(result$total, 3)
})

test_that("response_reach with multiple active responses unions their reach", {
  g <- root_vs_end_graph()

  result <- response_reach(g, c("R1", "R2"))

  expect_equal(result$total, 3) # union of {P1,S1,I1} and {I1} is still 3
  expect_setequal(result$reached_ids, c("P1", "S1", "I1"))
})
