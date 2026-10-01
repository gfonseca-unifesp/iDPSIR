# Revisao 3, E3.1 (structural uncertainty) and E4 (priority: additive form
# and robustness of the order).

e3_chain <- function(evidence = "definition", source = NULL) {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("D", "P", "S", "I", "R"), label = c("D", "P", "S", "I", "R"),
    dpsir_category = c("Driver", "Pressure", "State", "Impact", "Response"), stringsAsFactors = FALSE))
  edges <- data.frame(from = c("D", "P", "S", "R"), to = c("P", "S", "I", "P"),
                      weight = c(0.6, 0.6, 0.6, 0.9), weight_low = c(0.5, 0.5, 0.5, 0.8), weight_high = c(0.7, 0.7, 0.7, 1),
                      interaction_type = c("positive", "negative", "negative", "negative"),
                      evidence_type = evidence, stringsAsFactors = FALSE)
  build_igraph(nodes, normalize_dpsir_edges(edges), get_default_dpsir_schema())
}
pv <- function(g, v) { p <- setNames(rep(0, igraph::vcount(g)), igraph::V(g)$name); p[names(v)] <- v; p }

test_that("E3.1: absence probabilities follow the evidence, and estimated strengths are never absent", {
  g <- e3_chain(c("definition", "literature", "expert_assessment", ""))
  expect_equal(edge_absence_probability(g), c(0, 0.1, 0.2, 0.2))
  igraph::E(g)$weight_source <- c("given", "calibrated", "r2", "class")
  expect_equal(edge_absence_probability(g), c(0, 0, 0, 0.2))
})

test_that("E3.1: with every link 'definition' structural = TRUE changes nothing", {
  g <- e3_chain("definition")
  a <- sufficiency_confidence(g, pv(g, c(D = 1)), pv(g, c(R = 1)), n_simulations = 200)
  b <- sufficiency_confidence(g, pv(g, c(D = 1)), pv(g, c(R = 1)), n_simulations = 200, structural = TRUE)
  expect_equal(a$neutralized_pct, b$neutralized_pct)
  expect_true(isTRUE(attr(b, "structural")))
})

test_that("E3.1: one critical 'expert' link (the response's own) brings confidence down to about 80%", {
  g <- e3_chain(c("definition", "definition", "definition", "expert_assessment"))
  a <- sufficiency_confidence(g, pv(g, c(D = 1)), pv(g, c(R = 1)), n_simulations = 1000)
  b <- sufficiency_confidence(g, pv(g, c(D = 1)), pv(g, c(R = 1)), n_simulations = 1000, structural = TRUE)
  expect_equal(a$neutralized_pct, 100)
  expect_equal(b$neutralized_pct, 80, tolerance = 0.05)
})

test_that("E3.1: structural = FALSE reproduces the earlier confidence numbers on Mangi", {
  sp <- read_savepoint("../../docs/example_mangi.idpsir.json")
  g <- build_igraph(sp$nodes, sp$edges, sp$schema)
  pD <- pv(g, c(D1 = 1, D2 = 1, D3 = 1, D6 = 1)); pR <- pv(g, c(R1 = 1, R2 = 1, R3 = 1))
  a <- sufficiency_confidence(g, pD, pR, n_simulations = 300)
  b <- sufficiency_confidence(g, pD, pR, n_simulations = 300, structural = TRUE)
  expect_equal(a$neutralized_pct[a$id == "I1"], 11, tolerance = 0.2)   # documented in the tutorial
  expect_false(isTRUE(all.equal(a$neutralized_pct, b$neutralized_pct)))
})

test_that("E4.1: additive and multiplicative forms give the same order when v, D and rho are equal", {
  prio <- data.frame(id = c("a", "b", "c"), node = c("a", "b", "c"), value_v = 1, D = 0.8, rho = 0.9,
                     gap = c(0.2, 0.9, 0.5), affected = TRUE, stringsAsFactors = FALSE)
  mult <- prio$value_v * prio$D * prio$rho * prio$gap
  add <- (prio$value_v + prio$D + prio$rho) / 3 * prio$gap
  expect_equal(order(-mult), order(-add))
  # And through impact_prioritization() on a real network.
  sp <- read_savepoint("../../docs/example_port.idpsir.json")
  g <- build_igraph(sp$nodes, sp$edges, sp$schema)
  pD <- pv(g, c(D1 = 1, D2 = 1, D3 = 1))
  s <- sufficiency(g, pD, pv(g, c(R5 = 1)))
  pm <- impact_prioritization(g, pD, s, n_simulations = 100)
  pa <- impact_prioritization(g, pD, s, n_simulations = 100, aggregation = "additive")
  expect_equal(attr(pa, "aggregation"), "additive")
  expect_equal(pa$gap[match(pm$id, pa$id)], pm$gap)
  expect_true(all(pa$relevance[pa$affected] >= 0 & pa$relevance[pa$affected] <= 1))
})

test_that("E4.2: priority robustness - a clear order is stable, a near tie is not", {
  clear <- data.frame(id = c("a", "b"), node = c("a", "b"), value_v = c(1, 0.3), D = c(1, 0.3), rho = 1,
                      gap = c(1, 0.3), priority = c(1, 0.027), affected = TRUE, stringsAsFactors = FALSE)
  r <- priority_robustness(clear, n = 300)
  expect_equal(r$keeps_rank, c(1, 1))
  expect_equal(attr(r, "top_stable"), 1)
  tie <- data.frame(id = c("a", "b"), node = c("a", "b"), value_v = c(0.5, 0.5), D = c(1, 0.99), rho = 1,
                    gap = 1, priority = c(0.5, 0.495), affected = TRUE, stringsAsFactors = FALSE)
  rt <- priority_robustness(tie, n = 300)
  expect_lt(attr(rt, "top_stable"), 0.9)
  expect_identical(priority_robustness(clear, n = 50, seed = 1), priority_robustness(clear, n = 50, seed = 1))
})

test_that("E4.2: the rank distribution behind the figure sums to 1 per Impact and matches keeps_rank", {
  prio <- data.frame(id = c("a", "b", "c"), node = c("a", "b", "c"), value_v = c(1, 0.6, 0.4), D = c(1, 0.9, 0.9), rho = 1,
                     gap = c(0.9, 0.8, 0.8), affected = TRUE, stringsAsFactors = FALSE)
  prio$priority <- prio$value_v * prio$D * prio$rho * prio$gap
  r <- priority_robustness(prio, n = 200)
  share <- attr(r, "rank_share")
  expect_equal(unname(rowSums(share)), rep(1, 3))
  base <- attr(r, "base_rank")
  expect_equal(unname(share[cbind(1:3, base[rownames(share)])]), r$keeps_rank)
  f <- tempfile(fileext = ".png"); on.exit(unlink(f))
  render_plot_png(function() draw_rank_stability_plot(r), f)
  expect_gt(file.size(f), 1000)
})

test_that("a draw whose triggers raise rho above 1 is skipped, not an error (found by the simulated networks)", {
  source("../../analysis/sim_networks/generate.R")
  net <- generate_dpsir_network(1036)
  found <- FALSE
  for (r in 1:20) {
    e <- draw_strength_edges(net, 100000 * 36 + r)
    g2 <- sim_graph(net$nodes, e, keep = "thresholds")
    ids <- igraph::V(g2)$name
    pD <- setNames(rep(0, length(ids)), ids); pD[names(net$pressure)] <- 1
    out <- expect_no_error(prediction_reliability(g2, pD, n_simulations = 300))
    if (!is.null(attr(out, "skipped")) && attr(out, "skipped") > 0) found <- TRUE
  }
  expect_true(found)
})

test_that("E3: a draw where the pressure no longer worsens the Impact is not a neutralization", {
  nodes <- normalize_dpsir_nodes(data.frame(
    id = c("D", "P", "S", "I", "R"), label = c("D", "P", "S", "I", "R"),
    dpsir_category = c("Driver", "Pressure", "State", "Impact", "Response"), stringsAsFactors = FALSE))
  # D -> P rests on expert judgement (absent in ~20% of the draws); the rest
  # is by definition (never absent). The response is as strong as the push,
  # so it neutralizes in part of the draws.
  edges <- normalize_dpsir_edges(data.frame(
    from = c("D", "P", "S", "R"), to = c("P", "S", "I", "P"), weight = c(0.8, 0.6, 0.6, 0.8),
    interaction_type = c("positive", "negative", "negative", "negative"),
    evidence_type = c("expert_assessment", "definition", "definition", "definition"), stringsAsFactors = FALSE))
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())
  pv <- function(v) { p <- setNames(rep(0, 5), V(g)$name); p[names(v)] <- v; p }
  a <- sufficiency_confidence(g, pv(c(D = 1)), pv(c(R = 1)), n_simulations = 300)
  b <- sufficiency_confidence(g, pv(c(D = 1)), pv(c(R = 1)), n_simulations = 300, structural = TRUE)
  expect_equal(a$not_worsened_pct[a$id == "I"], 0)
  nw <- b$not_worsened_pct[b$id == "I"]
  expect_gt(nw, 10); expect_lt(nw, 30)
  # Without D -> P the net is the response alone (< 0): before the fix those
  # draws counted as neutralized; now they are counted apart, so the
  # structural confidence cannot exceed the plain one here.
  na <- a$neutralized_pct[a$id == "I"]; nb <- b$neutralized_pct[b$id == "I"]
  expect_gt(na, 10); expect_lt(na, 90)
  expect_lt(nb, na)
  expect_lte(nb + nw, 100)
})
