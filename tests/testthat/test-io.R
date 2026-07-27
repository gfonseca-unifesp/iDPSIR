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
