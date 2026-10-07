# The CSVs of factors and links in the supplement (S1-S3) load with
# Start -> Import CSV files, exactly as the app imports them (fread ->
# preflight_import() -> import_matrices()), and rebuild the same network as
# the published savepoint: same nodes, links, signs and strengths, and the
# same verdicts for a scenario.

source("../../data-raw/manuscript_supplement.R")

supp_dir <- file.path(tempdir(), "supp_csv_test")
supp <- manuscript_supplement(root = "../..", out_dir = supp_dir)

import_like_app <- function(prefix) {
  nodes_path <- file.path(supp_dir, paste0(prefix, "_factors.csv"))
  edges_path <- file.path(supp_dir, paste0(prefix, "_links.csv"))
  pf <- preflight_import(data.table::fread(nodes_path), data.table::fread(edges_path), get_default_dpsir_schema())
  imp <- import_matrices(nodes_path, edges_path)
  list(preflight = pf, g = build_igraph(imp$nodes, imp$edges, get_default_dpsir_schema()))
}

same_network <- function(g_csv, sp) {
  g_sp <- build_igraph(sp$nodes, sp$edges, sp$schema)
  expect_equal(igraph::vcount(g_csv), igraph::vcount(g_sp))
  expect_equal(igraph::ecount(g_csv), igraph::ecount(g_sp))
  key <- function(g) { e <- igraph::as_edgelist(g, names = TRUE); paste(e[, 1], e[, 2]) }
  k_csv <- key(g_csv); k_sp <- key(g_sp)
  expect_setequal(k_csv, k_sp)
  o <- match(k_sp, k_csv)
  for (a in c("interaction_type", "strength_class", "weight_source", "evidence_type")) {
    expect_equal(igraph::edge_attr(g_csv, a)[o], igraph::edge_attr(g_sp, a), info = a)
  }
  for (a in c("weight", "weight_low", "weight_high")) {
    expect_equal(as.numeric(igraph::edge_attr(g_csv, a)[o]), as.numeric(igraph::edge_attr(g_sp, a)), tolerance = 1e-9, info = a)
  }
  v <- match(igraph::V(g_sp)$name, igraph::V(g_csv)$name)
  for (a in c("label", "dpsir_category", "self_regulation", "growth_rate", "growth_cap", "reference_value", "sd",
              "threshold_level", "value_v")) {
    x <- igraph::vertex_attr(g_csv, a)[v]; y <- igraph::vertex_attr(g_sp, a)
    if (is.numeric(y)) expect_equal(as.numeric(x), y, tolerance = 1e-9, info = a) else expect_equal(x, y, info = a)
  }
  g_sp
}

same_verdicts <- function(g_csv, g_sp, pressure, response) {
  ids <- igraph::V(g_sp)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  a <- sufficiency(g_csv, pv(pressure), pv(response))
  b <- sufficiency(g_sp, pv(pressure), pv(response))
  expect_equal(a$neutralized[match(b$id, a$id)], b$neutralized)
  expect_equal(a$net[match(b$id, a$id)], b$net, tolerance = 1e-9)
}

test_that("S1 (port): the CSVs import without errors or warnings and rebuild the savepoint", {
  r <- import_like_app("S1_port")
  expect_length(r$preflight$blocking, 0)
  expect_length(r$preflight$warnings, 0)
  sp <- read_savepoint("../../docs/example_port.idpsir.json")
  g_sp <- same_network(r$g, sp)
  d <- sp$saved_scenarios[[2]]
  same_verdicts(r$g, g_sp, d$pressure_strengths[d$pressure_active], d$strengths[d$active])
})

test_that("S2 (Kenya): the CSVs import without errors or warnings and rebuild the savepoint", {
  r <- import_like_app("S2_kenya")
  expect_length(r$preflight$blocking, 0)
  expect_length(r$preflight$warnings, 0)
  sp <- read_savepoint("../../docs/example_mangi.idpsir.json")
  g_sp <- same_network(r$g, sp)
  d <- sp$saved_scenarios[[1]]
  same_verdicts(r$g, g_sp, d$pressure_strengths[d$pressure_active], d$strengths[d$active])
})

test_that("S3 (Sri Lanka): the CSVs import and rebuild the savepoint, including the temporal reading", {
  r <- import_like_app("S3_srilanka")
  expect_length(r$preflight$blocking, 0)
  expect_length(r$preflight$warnings, 0)
  sp <- read_savepoint("../../docs/example_gnanapragasam.idpsir.json")
  g_sp <- same_network(r$g, sp)
  ss <- sp$scenario_state
  same_verdicts(r$g, g_sp, ss$pressure_strengths, ss$response_strengths)
  ids <- igraph::V(g_sp)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  run <- function(g) simulate_temporal_pair(g, pv(ss$pressure_strengths), pv(ss$response_strengths), windows = 26,
                                            stop_rule = "fixed", mode_D = ss$temporal_mode_pressure,
                                            mode_R = ss$temporal_mode_response, schedule = ss$temporal_schedule)
  a <- run(r$g); b <- run(g_sp)
  expect_equal(a$scenario[, colnames(b$scenario)], b$scenario, tolerance = 1e-9)
})

test_that("import messages say which column to rename and that links need node ids", {
  nodes <- data.frame(id = c("D1", "P1"), factor = c("Dredging", "Runoff"), level = c("Driver", "Pressure"))
  pf <- preflight_import_nodes(nodes)
  expect_true(any(grepl("missing required column 'label'. Found column 'factor'; rename it to 'label'.", pf$blocking, fixed = TRUE)))
  expect_true(any(grepl("Found column 'level'; rename it to 'dpsir_category' with values Driver", pf$blocking, fixed = TRUE)))
  edges <- data.frame(from = "D1", to = "P1", sign = "+", class = "strong")
  pe <- preflight_import_edges(edges)
  expect_true(any(grepl("Found column 'sign'; rename it to 'interaction_type' with values positive/negative.", pe$blocking, fixed = TRUE)))
  expect_true(any(grepl("column 'class' is not a recognized field and was ignored. If it holds 'strength_class', rename it to 'strength_class'", pe$warnings, fixed = TRUE)))
  # Links written with the factors' names instead of their ids.
  ok_nodes <- data.frame(id = c("D1", "P1"), label = c("Dredging", "Runoff"), dpsir_category = c("Driver", "Pressure"))
  bad_edges <- data.frame(from = "Dredging", to = "Runoff", interaction_type = "positive")
  pb <- preflight_import(ok_nodes, bad_edges)
  expect_true(any(grepl("must hold node ids, not names - e.g. 'Dredging' is the label of node 'D1'", pb$blocking, fixed = TRUE)))
  expect_length(preflight_import(ok_nodes, data.frame(from = "D1", to = "P1", interaction_type = "positive"))$blocking, 0)
  # Also when the names are still in a column called 'factor'.
  pc <- preflight_import(nodes, bad_edges)
  expect_true(any(grepl("e.g. 'Dredging' is the label of node 'D1'", pc$blocking, fixed = TRUE)))
})
