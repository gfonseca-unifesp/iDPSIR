# Revisao 2, Fase 2: method consistency.

chain_net <- function(schema = get_default_dpsir_schema(), extra_edges = NULL) {
  cats <- schema_categories(schema)
  nodes <- data.frame(id = c("D", "P", "S", "I", "J", "R"), label = c("D", "P", "S", "I", "J", "R"),
                      dpsir_category = cats[c(1, 2, 3, 4, 4, 5)], subsystem = "", stringsAsFactors = FALSE)
  edges <- data.frame(
    from = c("D", "P", "S", "R", "I"), to = c("P", "S", "I", "S", "R"), weight = c(0.8, 0.5, 0.6, 0.4, 0.3),
    interaction_type = c("positive", "negative", "negative", "positive", "positive"), stringsAsFactors = FALSE
  )
  if (!is.null(extra_edges)) edges <- rbind(edges, extra_edges)
  build_igraph(normalize_dpsir_nodes(nodes, schema), normalize_dpsir_edges(edges), schema)
}
zeros <- function(g) setNames(rep(0, vcount(g)), V(g)$name)

test_that("2.6: roles come from the schema, so renamed levels keep working", {
  s <- get_default_dpsir_schema()
  s$name <- c("Cause", "Stress", "Condition", "Outcome", "Action")
  expect_equal(unname(schema_roles(s)), DPSIR_ROLES)
  g <- chain_net(s)
  expect_equal(V(g)$dpsir_role, c("driver", "pressure", "state", "impact", "impact", "feedback"))
  pD <- zeros(g); pD["D"] <- 1
  pR <- zeros(g); pR["R"] <- 1
  suff <- sufficiency(g, pD, pR)
  expect_equal(suff$id, c("I", "J"))
  expect_equal(response_reach(g, "R")$impacts, 1L)
  n <- normalize_dpsir_nodes(data.frame(id = "I", label = "I", dpsir_category = "Outcome", stringsAsFactors = FALSE), s)
  expect_equal(n$endpoint_class, "ecological")
  # Shorter schema: first = driver, last non-feedback = impact.
  s3 <- s[c(1, 4, 5), ]; s3$order <- 1:3
  expect_equal(unname(schema_roles(s3)), c("driver", "impact", "feedback"))
})

test_that("2.1: an Impact the pressure does not reach is 'Not affected'", {
  g <- chain_net()
  pD <- zeros(g); pD["D"] <- 1
  pR <- zeros(g); pR["R"] <- 1
  suff <- sufficiency(g, pD, pR)
  expect_equal(suff$affected, c(TRUE, FALSE))
  tbl <- format_sufficiency_table(suff, "R", c(R = 100))
  expect_equal(tbl$`Neutralizes?`[2], "Not affected")
  conf <- sufficiency_confidence(g, pD, pR, n_simulations = 20)
  expect_true(is.na(conf$neutralized_pct[2]))
  expect_false(is.na(conf$neutralized_pct[1]))
  expect_equal(format_confidence_matrix(data.frame(Response = "R", I = conf$neutralized_pct[1], J = NA_real_))$J, "—")
})

test_that("2.3: pathways follow the DPSIR order and never pass through a Response", {
  # R -> D closes a loop: D -> P -> S -> I -> R -> D ... must not be listed.
  g <- chain_net(extra_edges = data.frame(from = "R", to = "D", weight = 0.2, interaction_type = "negative"))
  paths <- find_dpsir_paths(g, "Driver", "Impact")
  ids <- vapply(paths, function(p) paste(V(g)$name[as.integer(p)], collapse = ">"), character(1))
  expect_equal(ids, "D>P>S>I")
  back <- find_dpsir_paths(g, "Response", "State")
  ids_back <- vapply(back, function(p) paste(V(g)$name[as.integer(p)], collapse = ">"), character(1))
  expect_true("R>S" %in% ids_back)
  expect_true(all(lengths(back) <= 5))
  expect_length(find_dpsir_paths(g, "Driver", "Impact", max_paths = 0), 0)
})

test_that("2.7: a pathway's effect is the product of its signed betas, with a band", {
  g <- chain_net()
  paths <- find_dpsir_paths(g, "Driver", "Impact")
  tbl <- compute_critical_pathways(g, paths)
  expect_equal(tbl$effect, 0.8 * -0.5 * -0.6)
  expect_equal(tbl$sign, "positive")
  expect_true(tbl$band_low <= tbl$effect && tbl$effect <= tbl$band_high)
  expect_equal(tbl$length, 3L)
})

test_that("2.4: resampling and community detection leave the caller's RNG untouched and are reproducible", {
  g <- chain_net()
  pD <- zeros(g); pD["D"] <- 1
  pR <- zeros(g); pR["R"] <- 1
  set.seed(7); before <- runif(1); set.seed(7)
  a <- sufficiency_confidence(g, pD, pR, n_simulations = 30)
  after <- runif(1)
  expect_equal(after, before)
  b <- sufficiency_confidence(g, pD, pR, n_simulations = 30)
  expect_identical(a, b)
  expect_identical(membership(compute_communities(g)), membership(compute_communities(g)))
})

test_that("audit: add a level with a role at a position, and remove an unused one", {
  s <- get_default_dpsir_schema()
  s2 <- schema_add_level(s, "Sub-driver", 2, "sub-driver")
  expect_equal(schema_categories(s2), c("Driver", "Sub-driver", "Pressure", "State", "Impact", "Response"))
  expect_equal(s2$order, 1:6)
  # A custom role stays outside the five; the default roles do not shift.
  r <- schema_roles(s2)
  expect_true(is.na(r[["Sub-driver"]]))
  expect_equal(unname(r[c("Driver", "Pressure", "State", "Impact", "Response")]), DPSIR_ROLES)
  # The chain respects the new order.
  conn <- schema_allowed_connections(s2)
  expect_equal(conn[["Driver"]], "Sub-driver")
  expect_equal(conn[["Sub-driver"]], "Pressure")
  expect_setequal(conn[["Response"]], c("Driver", "Sub-driver", "Pressure", "State", "Impact"))
  # A new, distinct color (not a repeat, not grey).
  expect_false(toupper(s2$color[s2$name == "Sub-driver"]) %in% toupper(s$color))

  # A second driver-role level is allowed and plays the driver role.
  s3 <- schema_add_level(s, "Global driver", 1, "driver")
  expect_equal(categories_with_role("driver", s3), c("Global driver", "Driver"))

  expect_error(schema_add_level(s, "driver", 1, "driver"), "already exists")
  expect_error(schema_add_level(s, "X", 9, "driver"), "Position")
  expect_error(schema_add_level(s, "X", 1.5, "driver"), "Position")

  expect_error(schema_remove_level(s2, "Pressure", used_categories = "Pressure"), "still has factors")
  s4 <- schema_remove_level(s2, "Sub-driver")
  expect_equal(schema_categories(s4), schema_categories(s))
  expect_equal(s4$order, 1:5)
  expect_equal(schema_missing_roles(schema_remove_level(s, "State")), "state")
})

test_that("audit: schemas with inferred and explicit roles are equivalent", {
  old <- get_default_dpsir_schema()
  old$role <- c(NA, NA, NA, NA, "feedback")
  expect_true(schemas_equivalent(old, get_default_dpsir_schema()))
  expect_error(validate_schema(transform(old, order = as.character(order))), "order")
})

test_that("audit: adding a level to an older schema (inferred roles) keeps every role", {
  old <- get_default_dpsir_schema()
  old$role <- c(NA, NA, NA, NA, "feedback")
  s <- schema_add_level(old, "Sub-driver", 2, "sub-driver")
  r <- schema_roles(s)
  expect_equal(unname(r[c("Driver", "Pressure", "State", "Impact", "Response")]), DPSIR_ROLES)
  expect_length(schema_missing_roles(s), 0)
  expect_equal(unname(schema_roles(schema_remove_level(s, "Sub-driver"))), DPSIR_ROLES)
})
