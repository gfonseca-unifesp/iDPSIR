# Revisao 2, Fase 4: tests that were missing - report (incl. escaping),
# CSV import, empty network, NA sign/weight, out-of-range savepoint values,
# misaligned push vectors.

small_nodes <- function(label_s = "State") {
  data.frame(id = c("D", "P", "S", "I", "R"), label = c("D", "P", label_s, "I", "R"),
             dpsir_category = c("Driver", "Pressure", "State", "Impact", "Response"),
             subsystem = "", stringsAsFactors = FALSE)
}
small_edges <- function() {
  data.frame(from = c("D", "P", "S", "R"), to = c("P", "S", "I", "S"), weight = c(0.8, 0.5, 0.6, 0.4),
             interaction_type = c("positive", "negative", "negative", "positive"), stringsAsFactors = FALSE)
}
small_graph <- function(label_s = "State") {
  build_igraph(normalize_dpsir_nodes(small_nodes(label_s)), normalize_dpsir_edges(small_edges()), get_default_dpsir_schema())
}

test_that("the report escapes HTML in user text and builds every optional section", {
  g <- small_graph("<script>alert(1)</script>")
  html <- as.character(htmltools::renderTags(build_full_report_html(
    get_default_dpsir_schema(), g,
    include_general = TRUE, include_centralities = TRUE, include_descriptors = TRUE, include_references = TRUE
  ))$html)
  expect_false(grepl("<script>alert(1)</script>", html, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
  expect_true(grepl("Table 1.", html, fixed = TRUE))
  expect_true(grepl("Driver-to-Impact pathways", html, fixed = TRUE))
  expect_true(grepl("Strength and confidence of the network", html, fixed = TRUE))
})

test_that("import_matrices reads CSV files and keeps the structure", {
  dir <- tempfile(); dir.create(dir)
  utils::write.csv(small_nodes(), file.path(dir, "n.csv"), row.names = FALSE)
  utils::write.csv(small_edges(), file.path(dir, "e.csv"), row.names = FALSE)
  imp <- import_matrices(file.path(dir, "n.csv"), file.path(dir, "e.csv"))
  expect_equal(nrow(imp$nodes), 5)
  expect_equal(nrow(imp$edges), 4)
  expect_equal(imp$edges$weight, c(0.8, 0.5, 0.6, 0.4))
})

test_that("an empty network (no edges) runs every reading without error", {
  g <- build_igraph(normalize_dpsir_nodes(small_nodes()), NULL, get_default_dpsir_schema())
  z <- setNames(rep(0, vcount(g)), V(g)$name)
  pD <- z; pD["D"] <- 1
  pR <- z; pR["R"] <- 1
  s <- sufficiency(g, pD, pR)
  expect_equal(s$worsening, 0)
  expect_false(s$affected)
  tr <- simulate_temporal_pair(g, pD, pR, windows = 3, stop_rule = "fixed")
  expect_equal(nrow(tr$scenario), 4)
  expect_length(find_dpsir_paths(g, "Driver", "Impact"), 0)
  expect_equal(response_reach(g, "R")$total, 0)
})

test_that("a blank sign blocks the import; a blank weight falls back to the default class", {
  e <- small_edges(); e$interaction_type[2] <- ""
  pf <- preflight_import_edges(e)
  expect_true(length(pf$blocking) > 0)
  e2 <- small_edges(); e2$weight[2] <- NA
  n2 <- normalize_dpsir_edges(e2)
  expect_equal(n2$weight[2], 0.45)
  expect_equal(n2$weight_source[2], "default")
})

test_that("out-of-range values in a savepoint are reported, not silently used", {
  sp <- read_savepoint("../../docs/example_gnanapragasam.idpsir.json")
  raw <- jsonlite::read_json("../../docs/example_gnanapragasam.idpsir.json", simplifyVector = TRUE)
  raw$nodes$self_regulation[1] <- 2
  raw$nodes$growth_rate[2] <- -1.5
  f <- tempfile(fileext = ".idpsir.json")
  jsonlite::write_json(raw, f, auto_unbox = TRUE, na = "null", digits = NA)
  expect_error(read_savepoint(f), "self_regulation|growth_rate")
})

test_that("push vectors are aligned by name, and a misaligned one is refused", {
  g <- small_graph()
  shuffled <- c(R = 1, D = 1) # names in a different order than the graph
  s1 <- sufficiency(g, c(D = 1), c(R = 1))
  s2 <- sufficiency(g, shuffled[c("D")], shuffled[c("R")])
  expect_equal(s1, s2)
  expect_error(sufficiency(g, c(X = 1), c(R = 1)), "not in the network")
  expect_error(sufficiency(g, c(1, 0), c(R = 1)), "no factor names")
})
