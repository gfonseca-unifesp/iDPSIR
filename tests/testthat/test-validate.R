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

test_that("normalize_dpsir_edges defaults reference to '' when the column is absent", {
  edges <- data.frame(from = "A", to = "B", weight = 1, confidence = 0.5, stringsAsFactors = FALSE)
  normalized <- normalize_dpsir_edges(edges)

  expect_identical(normalized$reference, "")
})

test_that("normalize_dpsir_edges preserves reference when present and drops a legacy threshold column", {
  edges <- data.frame(
    from = "A", to = "B", weight = 1, confidence = 0.5,
    threshold = 0.2, reference = "Some citation", stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_edges(edges)

  expect_equal(normalized$reference, "Some citation")
  expect_null(normalized$threshold)
})

test_that("normalize_dpsir_nodes defaults activation_threshold to NA when the column is absent", {
  nodes <- data.frame(id = "S1", label = "S1", dpsir_category = "State", stringsAsFactors = FALSE)
  normalized <- normalize_dpsir_nodes(nodes)

  expect_true(is.na(normalized$activation_threshold))
})

test_that("normalize_dpsir_nodes preserves activation_threshold when present", {
  nodes <- data.frame(
    id = "S1", label = "S1", dpsir_category = "State",
    activation_threshold = 0.15, stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$activation_threshold, 0.15)
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

  expect_equal(normalized$self_regulation, 0.5) # Revisao 2, item A8: default 0.5
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

test_that("normalize_dpsir_nodes defaults uncertainty/controllability to 0.5 when the columns are entirely absent", {
  nodes <- data.frame(id = "A", label = "A", dpsir_category = "Driver", stringsAsFactors = FALSE)
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$uncertainty, 0.5)
  expect_equal(normalized$controllability, 0.5)
})

test_that("normalize_dpsir_nodes reads uncertainty/controllability numbers straight through when present", {
  nodes <- data.frame(
    id = c("A", "B"), label = c("A", "B"), dpsir_category = "Driver",
    uncertainty = c(0.1, 0.9), controllability = c(0.3, 0.7),
    stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$uncertainty, c(0.1, 0.9))
  expect_equal(normalized$controllability, c(0.3, 0.7))
})

test_that("normalize_dpsir_nodes maps a legacy categorical uncertainty/controllability (low/medium/high) to a numeric equivalent, for backward compatibility with a pre-Revisao-1 savepoint", {
  nodes <- data.frame(
    id = c("A", "B", "C"), label = "x", dpsir_category = "Driver",
    uncertainty = c("low", "medium", "high"), controllability = c("high", "low", "medium"),
    stringsAsFactors = FALSE
  )
  normalized <- normalize_dpsir_nodes(nodes)

  expect_equal(normalized$uncertainty, c(0.2, 0.5, 0.8))
  expect_equal(normalized$controllability, c(0.8, 0.2, 0.5))
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
  expect_equal(normalized$self_regulation, 0.5) # Revisao 2, item A8: default 0.5
})

# =====================================================
# preflight_import_nodes() / preflight_import_edges() (import-time
# format/vocabulary preflight, separate from validate_dpsir_nodes()/
# validate_dpsir_edges(), which run later at "Review and build")
# =====================================================

test_that("preflight_import_nodes finds nothing wrong with a well-formed table, including a real NA in an optional numeric column", {
  nodes <- data.frame(
    id = c("D1", "S1"), label = c("Driver 1", "State 1"),
    dpsir_category = c("Driver", "State"), subsystem = c("", ""),
    uncertainty = c("low", "medium"), controllability = c("high", "low"),
    self_regulation = c(0, 0.3), growth_rate = c(0, 0),
    reference_value = c(1, 1), activation_threshold = c(NA, 0.15),
    descriptor = c("", ""), stringsAsFactors = FALSE
  )

  result <- preflight_import_nodes(nodes)

  expect_length(result$blocking, 0)
  expect_length(result$warnings, 0)
})

test_that("preflight_import_nodes blocks on a missing required column", {
  nodes <- data.frame(id = "D1", label = "Driver 1", category = "Driver", stringsAsFactors = FALSE)

  result <- preflight_import_nodes(nodes)

  expect_true(any(grepl("missing required column 'dpsir_category'", result$blocking, fixed = TRUE)))
})

test_that("preflight_import_nodes blocks on out-of-vocabulary dpsir_category and a non-numeric uncertainty, with the right row number", {
  nodes <- data.frame(
    id = c("D1", "X1"), label = c("D1", "X1"),
    dpsir_category = c("Driver", "Pressures"), uncertainty = c("low", "very high"),
    stringsAsFactors = FALSE
  )

  result <- preflight_import_nodes(nodes)

  expect_true(any(grepl("row 3: dpsir_category 'Pressures'", result$blocking, fixed = TRUE)))
  expect_true(any(grepl("row 3: uncertainty 'very high' is not a number", result$blocking, fixed = TRUE)))
})

test_that("preflight_import_nodes blocks uncertainty/controllability outside [0,1] and non-numeric values separately, but accepts the legacy low/medium/high vocabulary", {
  nodes <- data.frame(
    id = c("A", "B", "C"), label = "x", dpsir_category = "Driver",
    uncertainty = c("1.5", "abc", "medium"), controllability = c("medium", "-0.2", "high"),
    stringsAsFactors = FALSE
  )

  result <- preflight_import_nodes(nodes)

  expect_true(any(grepl("row 2: uncertainty 1.5 is outside", result$blocking, fixed = TRUE)))
  expect_true(any(grepl("row 3: uncertainty 'abc' is not a number", result$blocking, fixed = TRUE)))
  expect_true(any(grepl("row 3: controllability -0.2 is outside", result$blocking, fixed = TRUE)))
  # row 4 (legacy strings "medium"/"high") never mentioned - not blocked.
  expect_false(any(grepl("row 4:", result$blocking, fixed = TRUE)))
})

test_that("preflight_import_nodes blocks activation_threshold set on a non-State node", {
  nodes <- data.frame(
    id = "D1", label = "D1", dpsir_category = "Driver", activation_threshold = 0.2,
    stringsAsFactors = FALSE
  )

  result <- preflight_import_nodes(nodes)

  expect_true(any(grepl("not a State factor", result$blocking, fixed = TRUE)))
})

test_that("preflight_import_nodes blocks self_regulation outside [0,1) and non-numeric values separately", {
  nodes <- data.frame(
    id = c("S1", "S2"), label = c("S1", "S2"), dpsir_category = "State",
    self_regulation = c("1.5", "abc"), stringsAsFactors = FALSE
  )

  result <- preflight_import_nodes(nodes)

  expect_true(any(grepl("self_regulation 1.5 is outside", result$blocking, fixed = TRUE)))
  expect_true(any(grepl("self_regulation 'abc' is not a number", result$blocking, fixed = TRUE)))
})

test_that("preflight_import_nodes warns (not blocks) on an unknown column and a missing optional column", {
  nodes <- data.frame(
    id = "D1", label = "D1", dpsir_category = "Driver", temporal_scale = "long",
    stringsAsFactors = FALSE
  )

  result <- preflight_import_nodes(nodes)

  expect_length(result$blocking, 0)
  expect_true(any(grepl("'temporal_scale' is not a recognized field", result$warnings, fixed = TRUE)))
  expect_true(any(grepl("'growth_rate' is missing", result$warnings, fixed = TRUE)))
})

test_that("preflight_import_edges blocks bad interaction_type, non-positive weight, and out-of-range confidence", {
  edges <- data.frame(
    from = c("D1", "D1"), to = c("S1", "S1"), weight = c(-1, 2), confidence = c(0.8, 1.5),
    interaction_type = c("increases", "positive"), stringsAsFactors = FALSE
  )

  result <- preflight_import_edges(edges)

  expect_true(any(grepl("interaction_type 'increases'", result$blocking, fixed = TRUE)))
  expect_true(any(grepl("weight -1 must be greater than 0", result$blocking, fixed = TRUE)))
  expect_true(any(grepl("confidence 1.5 is outside", result$blocking, fixed = TRUE)))
})

test_that("preflight_import_edges blocks on a missing required column", {
  edges <- data.frame(source = "D1", to = "S1", stringsAsFactors = FALSE)

  result <- preflight_import_edges(edges)

  expect_true(any(grepl("missing required column 'from'", result$blocking, fixed = TRUE)))
})

test_that("preflight_import combines node and edge results, and an empty edges table produces no edge findings", {
  nodes <- data.frame(id = "D1", label = "D1", dpsir_category = "Pressures", stringsAsFactors = FALSE)

  result <- preflight_import(nodes, NULL)

  expect_true(any(grepl("dpsir_category 'Pressures'", result$blocking, fixed = TRUE)))
})

# Revisao 2, item 0.7: the sign of an edge has no default.
test_that("preflight blocks a blank interaction_type cell and a missing interaction_type column", {
  nodes <- data.frame(id = c("D1", "P1"), label = c("a", "b"), dpsir_category = c("Driver", "Pressure"))
  blank_cell <- data.frame(from = "D1", to = "P1", weight = 1, interaction_type = NA)
  no_column <- data.frame(from = "D1", to = "P1", weight = 1)

  expect_true(any(grepl("row 2: interaction_type is empty", preflight_import(nodes, blank_cell)$blocking)))
  expect_true(any(grepl("missing column 'interaction_type'", preflight_import(nodes, no_column)$blocking)))
})

test_that("validate_dpsir_edges rejects an edge without a sign instead of treating it as positive", {
  nodes <- data.frame(id = c("D1", "P1"), label = c("a", "b"), dpsir_category = c("Driver", "Pressure"))
  edges <- data.frame(from = "D1", to = "P1", weight = 1, confidence = 1, interaction_type = "", stringsAsFactors = FALSE)
  expect_error(validate_dpsir_edges(nodes, edges), "Every edge needs a sign.*D1 -> P1")
})

# Revisao 2, Fase 1: a blank weight cell gets the default class value
# (moderate, 0.45); the band comes from a legacy confidence when there is
# one, else from the class the beta falls in.
test_that("normalize_dpsir_edges fills a blank weight with the default class and builds every edge's band", {
  edges <- data.frame(from = c("D1", "D1"), to = c("P1", "P2"), weight = c(NA, 0.5), confidence = c(0.4, NA),
                      interaction_type = "positive", stringsAsFactors = FALSE)
  out <- normalize_dpsir_edges(edges)
  expect_equal(out$weight, c(0.45, 0.5))
  expect_equal(out$weight_source, c("default", "given"))
  expect_equal(out$strength_class, c("moderate", "moderate"))
  # Legacy confidence 0.4 -> band 0.45 * [0.7, 1.3]; derived confidence gives 0.4 back.
  expect_equal(out$weight_low, c(0.45 * 0.7, 0.3))
  expect_equal(out$weight_high, c(0.45 * 1.3, 0.6))
  expect_equal(out$confidence, c(0.4, 0.4))
})

test_that("normalize_dpsir_edges uses the class value and band when only strength_class is given", {
  edges <- data.frame(from = c("D1", "D1"), to = c("P1", "P2"), weight = NA, strength_class = c("weak", "Strong"),
                      interaction_type = "negative", stringsAsFactors = FALSE)
  out <- normalize_dpsir_edges(edges)
  expect_equal(out$weight, c(0.15, 0.80))
  expect_equal(out$weight_low, c(0, 0.6))
  expect_equal(out$weight_high, c(0.3, 1.0))
  expect_equal(out$weight_source, c("class", "class"))
})

test_that("preflight warns on beta above 1, blocks a bad class and a band that does not contain the weight", {
  nodes <- data.frame(id = c("D1", "P1"), label = c("a", "b"), dpsir_category = c("Driver", "Pressure"))
  above <- data.frame(from = "D1", to = "P1", weight = 1.5, interaction_type = "positive")
  bad_class <- data.frame(from = "D1", to = "P1", strength_class = "huge", interaction_type = "positive")
  bad_band <- data.frame(from = "D1", to = "P1", weight = 0.5, weight_low = 0.6, weight_high = 0.9, interaction_type = "positive")

  expect_true(any(grepl("weight 1.5 is above 1", preflight_import(nodes, above)$warnings)))
  expect_length(preflight_import(nodes, above)$blocking, 0)
  expect_true(any(grepl("strength_class 'huge'", preflight_import(nodes, bad_class)$blocking)))
  expect_true(any(grepl("band .* must contain the weight", preflight_import(nodes, bad_band)$blocking)))
})

test_that("r squared shortcuts: |beta| = sqrt(r2), band from the standard error with n", {
  expect_equal(beta_from_r2(0.49), 0.7)
  band <- band_from_r2_n(0.49, 50)
  se <- sqrt(0.51 / 48)
  expect_equal(unname(band), c(0.7 - 1.96 * se, 0.7 + 1.96 * se))
})
