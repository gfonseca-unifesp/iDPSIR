# Revisao 3, E5.2: the simulated-network generator
# (analysis/sim_networks/generate.R) produces networks the app accepts, is
# deterministic in its seed and never draws an edge the schema forbids.
# Kept in the main suite (not under analysis/) so CI checks it.

source("../../analysis/sim_networks/generate.R")

test_that("every generated network passes the app's validation and schema rules", {
  schema <- get_default_dpsir_schema()
  allowed <- schema_allowed_connections(schema)
  for (i in 1:60) {
    net <- generate_dpsir_network(1000 + i)
    n <- nrow(net$nodes)
    expect_true(n >= 10 && n <= 25, info = i)
    expect_true(validate_dpsir_nodes(net$nodes, schema), info = i)
    expect_true(validate_dpsir_edges(net$nodes, raw_edges(net), schema), info = i)
    cat_of <- setNames(net$nodes$dpsir_category, net$nodes$id)
    ok <- mapply(function(f, t) cat_of[[t]] %in% allowed[[cat_of[[f]]]], net$edges$from, net$edges$to)
    expect_true(all(ok), info = i)
    expect_false(any(cat_of[net$edges$from] == cat_of[net$edges$to]), info = i)  # no State -> State etc.
    # Every Impact reachable from some Driver; every Response acts on something.
    g <- sim_graph(net$nodes, raw_edges(net))
    reach <- unique(unlist(lapply(net$nodes$id[cat_of == "Driver"], function(d) names(igraph::subcomponent(g, d, mode = "out")))))
    expect_true(all(net$nodes$id[cat_of == "Impact"] %in% reach), info = i)
    expect_true(all(net$nodes$id[cat_of == "Response"] %in% net$edges$from), info = i)
    # Only States carry thresholds, only Drivers grow.
    expect_true(all(cat_of[net$nodes$id[!is.na(net$nodes$threshold_level)]] == "State"), info = i)
    expect_true(all(cat_of[net$nodes$id[net$nodes$growth_rate != 0]] == "Driver"), info = i)
  }
})

test_that("the same seed gives the same network and the same strength draw", {
  a <- generate_dpsir_network(1234); b <- generate_dpsir_network(1234)
  expect_identical(a, b)
  expect_false(identical(a$edges, generate_dpsir_network(1235)$edges))
  expect_identical(draw_strength_edges(a, 99), draw_strength_edges(b, 99))
})

test_that("signs follow the convention, with harm-oriented States flipped consistently", {
  for (i in 1:40) {
    net <- generate_dpsir_network(2000 + i)
    e <- net$edges
    key <- paste0(substr(e$from, 1, 1), ">", substr(e$to, 1, 1))
    flip <- ifelse(e$from %in% net$harm | e$to %in% net$harm, -1, 1)
    expect_equal(ifelse(e$interaction_type == "positive", 1, -1), unname(SIM_SIGNS[key] * flip), info = i)
  }
})

test_that("a strength draw respects the explained-variance rule and rho(B) < 1", {
  for (i in 1:30) {
    net <- generate_dpsir_network(3000 + i)
    e <- draw_strength_edges(net, 7 + i)
    if (is.null(e)) next
    resp <- net$nodes$dpsir_category[match(e$from, net$nodes$id)] == "Response"
    s2 <- tapply(e$weight[!resp]^2, e$to[!resp], sum)
    expect_true(all(s2 <= 0.95 + 1e-9), info = i)
    expect_true(all(e$weight_low <= e$weight & e$weight <= e$weight_high), info = i)
    expect_lt(spectral_radius(effect_matrix(sim_graph(net$nodes, e))), 1)
  }
})

test_that("feedback loops exist only through I -> R: with q = 0 every network is acyclic", {
  for (i in 1:80) {
    net <- generate_dpsir_network(4000 + i)
    g <- sim_graph(net$nodes, raw_edges(net))
    has_ir <- any(substr(net$edges$from, 1, 1) == "I" & substr(net$edges$to, 1, 1) == "R")
    if (net$q == 0) expect_false(has_ir, info = i)
    if (!has_ir) expect_true(igraph::is_dag(g), info = i)
  }
})
