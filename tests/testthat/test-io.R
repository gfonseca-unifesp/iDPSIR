# =====================================================
# TESTS - R/io.R
# =====================================================

test_that("build_savepoint / write_savepoint / read_savepoint round-trip nodes, edges and schema", {
  schema <- get_default_dpsir_schema()
  nodes <- data.frame(
    id = c("D1", "P1"), label = c("Driver test", "Pressure test"),
    dpsir_category = c("Driver", "Pressure"), subsystem = "",
    uncertainty = "medium", controllability = "medium", temporal_scale = "medium",
    stringsAsFactors = FALSE
  )
  edges <- data.frame(
    from = "D1", to = "P1", weight = 2, confidence = 0.8,
    interaction_type = "positive", evidence_type = "expert_assessment",
    threshold = NA_real_, reference = "Test reference", stringsAsFactors = FALSE
  )

  savepoint <- build_savepoint(schema, nodes, edges)
  expect_equal(savepoint$format_version, "1.0")

  tmp <- tempfile(fileext = ".idpsir.json")
  on.exit(unlink(tmp))
  write_savepoint(savepoint, tmp)

  reloaded <- read_savepoint(tmp)
  expect_equal(reloaded$nodes$id, nodes$id)
  expect_equal(reloaded$edges$from, edges$from)
  expect_equal(reloaded$edges$reference, "Test reference")
  expect_equal(reloaded$edges$weight, 2)
})

test_that("build_savepoint / read_savepoint round-trip scenario_state, and old savepoints without it read back as NULL", {
  schema <- get_default_dpsir_schema()
  nodes <- data.frame(
    id = c("D1", "R1"), label = c("Driver test", "Response test"),
    dpsir_category = c("Driver", "Response"), subsystem = "",
    uncertainty = "medium", controllability = "medium", temporal_scale = "medium",
    stringsAsFactors = FALSE
  )
  edges <- create_empty_graph_edges()

  scenario_state <- list(
    response_active = "R1",
    response_strengths = c(R1 = 80),
    pressure_active = "D1",
    pressure_strengths = c(D1 = 60),
    effect_horizon = 0.35
  )

  savepoint <- build_savepoint(schema, nodes, edges, scenario_state = scenario_state)

  tmp <- tempfile(fileext = ".idpsir.json")
  on.exit(unlink(tmp))
  write_savepoint(savepoint, tmp)

  reloaded <- read_savepoint(tmp)
  expect_equal(reloaded$scenario_state$response_active, "R1")
  expect_equal(unname(reloaded$scenario_state$response_strengths["R1"]), 80)
  expect_equal(reloaded$scenario_state$pressure_active, "D1")
  expect_equal(unname(reloaded$scenario_state$pressure_strengths["D1"]), 60)
  # Revisao 2, Fase 1: the reach factor c is gone, so it is no longer saved.
  expect_equal(reloaded$scenario_state$effect_horizon, 0.5)

  # A savepoint built without scenario_state (the pre-Revisao-1 shape) -
  # read back as NULL, not an error, same pattern already used for
  # `positions` on a savepoint from before that field existed.
  old_savepoint <- build_savepoint(schema, nodes, edges)
  tmp2 <- tempfile(fileext = ".idpsir.json")
  on.exit(unlink(tmp2), add = TRUE)
  write_savepoint(old_savepoint, tmp2)
  reloaded2 <- read_savepoint(tmp2)
  expect_null(reloaded2$scenario_state)
})

test_that("read_savepoint rejects an incompatible format_version", {
  tmp <- tempfile(fileext = ".idpsir.json")
  on.exit(unlink(tmp))
  jsonlite::write_json(
    list(format_version = "0.1", schema = list(), nodes = list(), edges = list()),
    tmp,
    auto_unbox = TRUE
  )

  expect_error(read_savepoint(tmp), "Incompatible savepoint format")
})

test_that("read_savepoint errors clearly when the file doesn't exist", {
  expect_error(read_savepoint(tempfile(fileext = ".idpsir.json")), "not found")
})

test_that("merge_savepoints rejects incompatible schemas", {
  schema_a <- get_default_dpsir_schema()

  # schema_categories() sorts by the `order` column, not row position - so
  # swapping two rows isn't enough to make schemas_equivalent() disagree.
  # Swapping the `order` VALUES of two categories genuinely changes the
  # resulting category sequence.
  schema_b <- schema_a
  driver_order <- schema_a$order[schema_a$name == "Driver"]
  pressure_order <- schema_a$order[schema_a$name == "Pressure"]
  schema_b$order[schema_b$name == "Driver"] <- pressure_order
  schema_b$order[schema_b$name == "Pressure"] <- driver_order

  sp_a <- list(schema = schema_a, nodes = data.frame(id = "X1", stringsAsFactors = FALSE), edges = create_empty_graph_edges())
  sp_b <- list(schema = schema_b, nodes = data.frame(id = "X2", stringsAsFactors = FALSE), edges = create_empty_graph_edges())

  expect_error(merge_savepoints(list(sp_a, sp_b), c("a", "b")), "different DPSIR schemas")
})

test_that("merge_savepoints prefixes only colliding node ids, and remaps their edges", {
  schema <- get_default_dpsir_schema()
  nodes_a <- data.frame(id = c("D1", "P1"), stringsAsFactors = FALSE)
  nodes_b <- data.frame(id = c("D1", "P2"), stringsAsFactors = FALSE) # D1 collides, P2 doesn't
  edges_b <- data.frame(from = "D1", to = "P2", stringsAsFactors = FALSE)

  sp_a <- list(schema = schema, nodes = nodes_a, edges = create_empty_graph_edges())
  sp_b <- list(schema = schema, nodes = nodes_b, edges = edges_b)

  merged <- merge_savepoints(list(sp_a, sp_b), c("siteA", "siteB"))

  expect_true("D1" %in% merged$nodes$id) # first occurrence unprefixed
  expect_true("siteB__D1" %in% merged$nodes$id) # second occurrence prefixed
  expect_true("P2" %in% merged$nodes$id) # no collision -> unprefixed
  expect_equal(merged$edges$from, "siteB__D1") # edge remapped to the prefixed id
  expect_equal(merged$edges$to, "P2")
})

# Revisao 2, item 0.6: a savepoint goes through the same preflight as an
# imported CSV. Built by writing the JSON directly, the way a hand-edited or
# shared file would arrive.
write_raw_savepoint <- function(edges) {
  nodes <- data.frame(
    id = c("D1", "P1"), label = c("Driver test", "Pressure test"),
    dpsir_category = c("Driver", "Pressure"), stringsAsFactors = FALSE
  )
  sp <- build_savepoint(get_default_dpsir_schema(), nodes, data.frame(
    from = "D1", to = "P1", weight = 1, confidence = 1, interaction_type = "positive",
    stringsAsFactors = FALSE
  ))
  sp$edges <- edges
  tmp <- tempfile(fileext = ".idpsir.json")
  write_savepoint(sp, tmp)
  tmp
}

test_that("read_savepoint blocks an out-of-range confidence instead of producing NaN later", {
  tmp <- write_raw_savepoint(data.frame(
    from = "D1", to = "P1", weight = 1, confidence = 3, interaction_type = "positive",
    stringsAsFactors = FALSE
  ))
  on.exit(unlink(tmp))
  expect_error(read_savepoint(tmp), "confidence 3 is outside the valid range")
})

test_that("read_savepoint blocks a negative weight (it would flip the sign on top of interaction_type)", {
  tmp <- write_raw_savepoint(data.frame(
    from = "D1", to = "P1", weight = -2, confidence = 1, interaction_type = "negative",
    stringsAsFactors = FALSE
  ))
  on.exit(unlink(tmp))
  expect_error(read_savepoint(tmp), "weight -2 must be greater than 0")
})

test_that("read_savepoint blocks an edge with no sign, and reports optional-column warnings for old savepoints", {
  tmp <- write_raw_savepoint(data.frame(
    from = "D1", to = "P1", weight = 1, confidence = 1, interaction_type = "",
    stringsAsFactors = FALSE
  ))
  on.exit(unlink(tmp))
  expect_error(read_savepoint(tmp), "interaction_type is empty")

  old <- read_savepoint("fixtures/legacy_fisheries.idpsir.json")
  expect_true(any(grepl("^Savepoint nodes: column 'temporal_scale'", old$warnings)))
})

# Revisao 2, item 1.5: an older savepoint (no metadata$weight_mode) is
# converted on load to beta = lambda * w, with the lambda the older static
# reading used - so its static numbers are exactly the same as before.
test_that("read_savepoint converts an older savepoint and reproduces the older static reading exactly", {
  path <- "fixtures/legacy_mangi.idpsir.json"
  raw <- jsonlite::read_json(path, simplifyVector = TRUE)
  converted <- read_savepoint(path)

  expect_equal(converted$metadata$weight_mode, "structural")
  expect_true(all(converted$edges$weight_source == "converted"))
  expect_true(any(grepl("converted from the older relative scale", converted$warnings)))

  # Older reading, computed here from the raw weights: (I - lambda W)^-1 p - p.
  g_old <- build_igraph(normalize_dpsir_nodes(raw$nodes), normalize_dpsir_edges(raw$edges), converted$schema)
  W <- effect_matrix(g_old)
  lambda <- 0.5 / spectral_radius(W)
  p <- setNames(rep(0, nrow(W)), rownames(W)); p[c("D1", "D3")] <- 1
  old <- solve(diag(nrow(W)) - lambda * W, p) - p

  g_new <- build_igraph(converted$nodes, converted$edges, converted$schema)
  new <- propagate(effect_matrix(g_new), p)

  expect_equal(unname(new[rownames(W)]), unname(old), tolerance = 1e-12)
  expect_equal(converted$metadata$converted_from$lambda, lambda, tolerance = 1e-12)
})

test_that("a structural savepoint is not converted again, and legacy confidence becomes the band", {
  converted <- read_savepoint("fixtures/legacy_mangi.idpsir.json")
  sp <- build_savepoint(converted$schema, converted$nodes, converted$edges)
  tmp <- tempfile(fileext = ".idpsir.json")
  on.exit(unlink(tmp))
  write_savepoint(sp, tmp)

  again <- read_savepoint(tmp)
  expect_equal(again$edges$weight, converted$edges$weight)
  expect_null(again$conversion)

  edges <- data.frame(from = c("A", "B"), to = c("B", "C"), weight = c(2, 1), confidence = c(0.6, 1),
                      interaction_type = "positive", stringsAsFactors = FALSE)
  nodes <- data.frame(id = c("A", "B", "C"), stringsAsFactors = FALSE)
  conv <- convert_legacy_weights(nodes, edges, c = 0.5)
  # Acyclic: lambda = c. Edge A->B: beta 1.0, band 1.0 * [0.8, 1.2]; above 1? no (exactly 1).
  expect_equal(conv$lambda, 0.5)
  expect_equal(conv$edges$weight, c(1, 0.5))
  expect_equal(conv$edges$weight_low, c(0.8, 0.5))
  expect_equal(conv$edges$weight_high, c(1.2, 0.5))
  expect_length(conv$review, 0)
  expect_equal(convert_legacy_weights(nodes, transform(edges, weight = c(3, 1)), c = 0.5)$review, "A -> B")
})

# Revisao 2, item A5: temporal settings round-trip; an older savepoint that
# already records a number of windows keeps a fixed-length run.
test_that("scenario_state round-trips the temporal settings, with defaults for older files", {
  schema <- get_default_dpsir_schema()
  nodes <- data.frame(id = c("D1", "R1"), label = c("D", "R"), dpsir_category = c("Driver", "Response"), stringsAsFactors = FALSE)
  edges <- data.frame(from = "R1", to = "D1", weight = 0.5, interaction_type = "negative", stringsAsFactors = FALSE)
  st <- list(
    response_active = "R1", response_strengths = c(R1 = 100), pressure_active = "D1", pressure_strengths = c(D1 = 50),
    temporal_mode_pressure = "impulse", temporal_mode_response = "permanent", temporal_stop_rule = "fixed",
    temporal_max_windows = 30, temporal_windows = 12, temporal_tol_rel = 10, baseline_without_response = TRUE,
    n_simulations = 1000
  )
  tmp <- tempfile(fileext = ".idpsir.json"); on.exit(unlink(tmp))
  write_savepoint(build_savepoint(schema, nodes, edges, scenario_state = st), tmp)
  back <- read_savepoint(tmp)$scenario_state
  for (k in names(st)[5:12]) expect_equal(back[[k]], st[[k]], info = k)

  st_min <- st[1:4]
  write_savepoint(build_savepoint(schema, nodes, edges, scenario_state = st_min), tmp)
  back_min <- read_savepoint(tmp)$scenario_state
  expect_equal(back_min$temporal_stop_rule, "until_neutralized")
  expect_equal(back_min$temporal_mode_response, "permanent")
  expect_false(back_min$baseline_without_response)

  st_old <- c(st_min, temporal_windows = 8)
  write_savepoint(build_savepoint(schema, nodes, edges, scenario_state = st_old), tmp)
  expect_equal(read_savepoint(tmp)$scenario_state$temporal_stop_rule, "fixed")
})

test_that("Revisao 2, item 3.13: saved scenarios (definitions) round-trip through the savepoint", {
  sp_in <- read_savepoint("../../docs/example_gnanapragasam.idpsir.json")
  saved <- list(
    "Aid only" = list(name = "Aid only", active = c("R1", "R2"), strengths = c(R1 = 100, R2 = 100),
                      pressure_active = "D4", pressure_strengths = c(D4 = 100), n_simulations = 100L,
                      temporal_mode_response = "window",
                      temporal_schedule = data.frame(id = c("R1", "R2"), start = c(1, 6), duration = c(5, 3))),
    "Quota" = list(name = "Quota", active = "R3", strengths = c(R3 = 85),
                   pressure_active = character(), pressure_strengths = setNames(numeric(), character()), n_simulations = 300L)
  )
  sp <- build_savepoint(sp_in$schema, sp_in$nodes, sp_in$edges, saved_scenarios = saved)
  f <- tempfile(fileext = ".idpsir.json")
  write_savepoint(sp, f)
  back <- read_savepoint(f)$saved_scenarios
  expect_length(back, 2)
  expect_equal(back[[1]]$name, "Aid only")
  expect_equal(back[[1]]$strengths, c(R1 = 100, R2 = 100))
  expect_equal(back[[1]]$pressure_strengths, c(D4 = 100))
  expect_equal(back[[1]]$temporal_mode_response, "window")
  expect_equal(back[[1]]$temporal_schedule$start, c(1, 6))
  expect_equal(back[[2]]$strengths, c(R3 = 85))
  expect_length(back[[2]]$pressure_active, 0)
  expect_null(read_savepoint("../../docs/example_mangi.idpsir.json")$saved_scenarios)
})

test_that("audit: merging savepoints with the same file name never creates duplicate ids", {
  sp <- read_savepoint("../../docs/example_fisheries.idpsir.json")
  m <- merge_savepoints(list(sp, sp, sp), c("a", "a", "a"))
  expect_false(any(duplicated(m$nodes$id)))
  expect_true(all(c(m$edges$from, m$edges$to) %in% m$nodes$id))
})

test_that("audit: a savepoint without weight_mode but with structural edge columns is not converted", {
  sp <- read_savepoint("../../docs/example_port.idpsir.json")
  raw <- jsonlite::read_json("../../docs/example_port.idpsir.json", simplifyVector = TRUE)
  raw$metadata$weight_mode <- NULL
  tmp <- tempfile(fileext = ".idpsir.json"); on.exit(unlink(tmp))
  jsonlite::write_json(raw, tmp, auto_unbox = TRUE, digits = NA, null = "null")
  back <- read_savepoint(tmp)
  expect_equal(back$edges$weight, sp$edges$weight)
  expect_null(back$metadata$converted_from)
})
