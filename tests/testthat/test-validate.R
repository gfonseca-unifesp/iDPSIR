# =====================================================
# TESTS - R/validate.R
# =====================================================

test_that("validate_schema rejects duplicate level names and missing columns", {
  schema <- get_default_dpsir_schema()

  bad_schema <- schema
  bad_schema$name[2] <- bad_schema$name[1]
  expect_error(validate_schema(bad_schema), "unique")

  expect_error(validate_schema(schema[, -1]), "missing columns")
})

test_that("validate_schema rejects an empty schema", {
  schema <- get_default_dpsir_schema()
  expect_error(validate_schema(schema[0, ]), "at least one level")
})

test_that("validate_dpsir_categories rejects an unknown category", {
  schema <- get_default_dpsir_schema()
  nodes <- data.frame(id = "X1", dpsir_category = "NotACategory", stringsAsFactors = FALSE)

  expect_error(validate_dpsir_categories(nodes, schema), "Invalid DPSIR categories")
})

test_that("validate_unique_node_ids rejects duplicated ids", {
  nodes <- data.frame(id = c("A", "A"), stringsAsFactors = FALSE)
  expect_error(validate_unique_node_ids(nodes), "Duplicated node ids")
})

test_that("schema_allowed_connections matches the canonical DPSIR order plus Response feedback", {
  schema <- get_default_dpsir_schema()
  allowed <- schema_allowed_connections(schema)

  expect_equal(allowed[["Driver"]], "Pressure")
  expect_equal(allowed[["Pressure"]], "State")
  expect_equal(allowed[["State"]], "Impact")
  expect_equal(allowed[["Impact"]], "Response")
  expect_setequal(allowed[["Response"]], c("Driver", "Pressure", "State", "Impact"))
})

test_that("validate_dpsir_edge_logic flags an edge that skips a DPSIR category", {
  schema <- get_default_dpsir_schema()
  nodes <- data.frame(id = c("D1", "S1"), dpsir_category = c("Driver", "State"), stringsAsFactors = FALSE)
  edges <- data.frame(from = "D1", to = "S1", stringsAsFactors = FALSE) # Driver -> State skips Pressure

  expect_error(validate_dpsir_edge_logic(nodes, edges, schema), "Invalid DPSIR edge connections")
})

test_that("validate_dpsir_edge_logic allows a Response edge back to any earlier category", {
  schema <- get_default_dpsir_schema()
  nodes <- data.frame(id = c("D1", "R1"), dpsir_category = c("Driver", "Response"), stringsAsFactors = FALSE)
  edges <- data.frame(from = "R1", to = "D1", stringsAsFactors = FALSE)

  expect_true(validate_dpsir_edge_logic(nodes, edges, schema))
})

test_that("normalize_dpsir_edges defaults threshold to NA and reference to '' when the columns are absent", {
  edges <- data.frame(from = "A", to = "B", weight = 1, confidence = 0.5, stringsAsFactors = FALSE)
  normalized <- normalize_dpsir_edges(edges)

  expect_true(is.na(normalized$threshold))
  expect_identical(normalized$reference, "")
})

test_that("normalize_dpsir_edges preserves threshold/reference values when present", {
  edges <- data.frame(
    from = "A", to = "B", weight = 1, confidence = 0.5,
    threshold = 0.2, reference = "Some citation", stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_edges(edges)

  expect_equal(normalized$threshold, 0.2)
  expect_equal(normalized$reference, "Some citation")
})

test_that("normalize_dpsir_edges coerces weight/confidence to numeric and trims from/to", {
  edges <- data.frame(
    from = " A ", to = " B ", weight = "2.5", confidence = "0.9",
    stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_edges(edges)

  expect_equal(normalized$from, "A")
  expect_equal(normalized$to, "B")
  expect_equal(normalized$weight, 2.5)
  expect_equal(normalized$confidence, 0.9)
})

test_that("schemas_equivalent ignores cosmetic differences (color/shape) but not order or feedback role", {
  schema_a <- get_default_dpsir_schema()
  schema_b <- schema_a
  schema_b$color <- "#000000"
  expect_true(schemas_equivalent(schema_a, schema_b))

  schema_c <- schema_a
  schema_c$role[schema_c$name == "Response"] <- NA
  expect_false(schemas_equivalent(schema_a, schema_c))
})

test_that("normalize_dpsir_nodes defaults self_regulation/growth_rate/reference_value when the columns are entirely absent (Revisao 1, Fase 5)", {
  nodes <- data.frame(id = "A", label = "A", dpsir_category = "Driver", stringsAsFactors = FALSE)
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$self_regulation, 0)
  expect_equal(normalized$growth_rate, 0)
  expect_equal(normalized$reference_value, 1)
})

test_that("normalize_dpsir_nodes reads self_regulation/growth_rate/reference_value numbers straight through when present", {
  nodes <- data.frame(
    id = c("A", "B"), label = c("A", "B"), dpsir_category = "Driver",
    self_regulation = c(0.3, 0.7), growth_rate = c(0.02, -0.01), reference_value = c(100, 5),
    stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$self_regulation, c(0.3, 0.7))
  expect_equal(normalized$growth_rate, c(0.02, -0.01))
  expect_equal(normalized$reference_value, c(100, 5))
})

test_that("normalize_dpsir_nodes maps a legacy categorical self_regulation (none/low/medium/high) to a numeric equivalent, for backward compatibility with a pre-Fase-5 savepoint", {
  nodes <- data.frame(
    id = c("A", "B", "C", "D"), label = "x", dpsir_category = "Driver",
    self_regulation = c("none", "low", "medium", "high"),
    stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$self_regulation, c(0, 0.2, 0.4, 0.6))
})

test_that("normalize_dpsir_nodes treats reference_value = 0 the same as missing (falls back to 1, avoids a division by zero downstream)", {
  nodes <- data.frame(
    id = "A", label = "A", dpsir_category = "Driver", reference_value = 0,
    stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$reference_value, 1)
})

test_that("normalize_dpsir_nodes drops a retired temporal_scale column from an old savepoint/CSV, not just ignores it", {
  # Real bug, found only by testing live: leaving the column "just
  # ignored" (present but unread) made an old savepoint's node table have
  # a different column COUNT than a freshly-built row from the edit
  # form (which no longer asks for temporal_scale) - editing an existing
  # node then corrupted every column after subsystem, because
  # `rv$nodes[idx, ] <- new_row` (mod_data.R) assigns positionally when
  # column counts differ, not by name. Dropping the column here keeps
  # the node table's shape consistent regardless of the source data.
  nodes <- data.frame(
    id = "A", label = "A", dpsir_category = "Driver", temporal_scale = "medium",
    stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_nodes(nodes)

  expect_false("temporal_scale" %in% names(normalized))
  expect_equal(normalized$self_regulation, 0)
})
