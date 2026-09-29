# =====================================================
# TESTS - R/graph.R (Revisao 2, item 0.8: tooltips escape HTML)
# =====================================================

test_that("build_node_tooltip escapes HTML in label, descriptor and subsystem", {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = "S1", label = "<script>alert(1)</script>", dpsir_category = "State",
    subsystem = "<b>x</b>", descriptor = "<img src=x onerror=alert(2)>",
    stringsAsFactors = FALSE
  ))
  tip <- as.character(build_node_tooltip(nodes))

  expect_false(grepl("<script>", tip, fixed = TRUE))
  expect_false(grepl("<img", tip, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;alert(1)&lt;/script&gt;", tip, fixed = TRUE))
  expect_true(grepl("&lt;img src=x onerror=alert(2)&gt;", tip, fixed = TRUE))
  # The tooltip's own markup survives.
  expect_true(grepl("<b>&lt;script&gt;", tip, fixed = TRUE))
})

test_that("build_edge_tooltip escapes HTML in reference and evidence, and shows '-' for blanks", {
  edges <- data.frame(
    from = "D1", to = "P1", weight = 0.5, confidence = NA, interaction_type = "positive",
    evidence_type = "", reference = "<a href='javascript:x'>paper</a>", stringsAsFactors = FALSE
  )
  tip <- as.character(build_edge_tooltip(edges))

  expect_false(grepl("<a href", tip, fixed = TRUE))
  expect_true(grepl("&lt;a href='javascript:x'&gt;paper&lt;/a&gt;", tip, fixed = TRUE))
  expect_true(grepl("Confidence: -", tip, fixed = TRUE))
  expect_true(grepl("Evidence: -", tip, fixed = TRUE))
})
