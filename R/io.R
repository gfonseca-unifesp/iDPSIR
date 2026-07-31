# =====================================================
# IO - IMPORTACAO DE MATRIZES E SAVEPOINT (.idpsir.json)
# =====================================================

CURRENT_SAVEPOINT_VERSION <- "1.0"

# =====================================================
# IMPORTAR MATRIZES (CSV)
# =====================================================

import_matrices <- function(nodes_path, edges_path = NULL) {
  nodes <- data.table::fread(nodes_path)
  nodes <- normalize_dpsir_nodes(nodes)

  edges <- if (is.null(edges_path) || !nzchar(edges_path)) {
    create_empty_graph_edges()
  } else {
    edges_raw <- data.table::fread(edges_path)
    normalize_dpsir_edges(edges_raw)
  }

  list(nodes = nodes, edges = edges)
}

# =====================================================
# CONSTRUIR SAVEPOINT
# =====================================================

build_savepoint <- function(schema, nodes, edges, positions = NULL, metadata = list(), scenario_state = NULL) {
  validate_schema(schema)

  now <- as.character(Sys.time())

  default_metadata <- list(
    project_name = "Untitled project",
    author = unname(Sys.info()["user"]),
    created_at = now,
    notes = ""
  )

  metadata <- utils::modifyList(default_metadata, metadata)
  metadata$updated_at <- now

  # Revisao 1, Fase 3: `scenario_state` arrives as
  # list(pressure_active=<chr>, pressure_strengths=<named num>,
  # response_active=<chr>, response_strengths=<named num>, effect_horizon=)
  # (mod_responses.R's shape) but is stored here as id/strength ROWS - a
  # length-1 *named* numeric vector like c(D1 = 60) gets silently unboxed
  # by jsonlite's auto_unbox to a bare `60` (losing the "D1" key entirely,
  # confirmed empirically) - a data.frame of rows never does, the same
  # reason `positions` already uses one instead of named x/y vectors.
  scenario_state_json <- if (is.null(scenario_state)) {
    NULL
  } else {
    list(
      pressure = data.frame(
        id = scenario_state$pressure_active,
        strength = unname(scenario_state$pressure_strengths),
        stringsAsFactors = FALSE
      ),
      response = data.frame(
        id = scenario_state$response_active,
        strength = unname(scenario_state$response_strengths),
        stringsAsFactors = FALSE
      ),
      effect_horizon = if (is.null(scenario_state$effect_horizon)) 0.5 else scenario_state$effect_horizon
    )
  }

  list(
    format_version = CURRENT_SAVEPOINT_VERSION,
    metadata = metadata,
    schema = schema,
    nodes = nodes,
    edges = edges,
    positions = positions,
    # Same optional-key-added-to-an-existing-format pattern as `positions`
    # (Fase 5 fast-follow) - an old savepoint simply has no "scenario_state"
    # key, read back as NULL below, no version bump or migration needed.
    scenario_state = scenario_state_json
  )
}

# =====================================================
# SALVAR / CARREGAR SAVEPOINT
# =====================================================

write_savepoint <- function(savepoint, path) {
  jsonlite::write_json(
    savepoint,
    path,
    auto_unbox = TRUE,
    na = "null",
    pretty = TRUE
  )
  invisible(path)
}

merge_savepoints <- function(savepoints, source_names) {
  stopifnot(is.list(savepoints), length(savepoints) >= 2)
  stopifnot(length(source_names) == length(savepoints))

  base_schema <- savepoints[[1]]$schema

  for (i in seq_along(savepoints)[-1]) {
    if (!schemas_equivalent(base_schema, savepoints[[i]]$schema)) {
      stop(
        "Savepoints use different DPSIR schemas (levels, order or feedback role) and cannot be combined.",
        call. = FALSE
      )
    }
  }

  all_nodes <- vector("list", length(savepoints))
  all_edges <- vector("list", length(savepoints))
  seen_ids <- character()
  renamed <- character()

  for (i in seq_along(savepoints)) {
    nodes <- savepoints[[i]]$nodes
    edges <- savepoints[[i]]$edges
    prefix <- paste0(source_names[i], "__")

    needs_prefix <- nodes$id %in% seen_ids
    id_map <- setNames(nodes$id, nodes$id)
    id_map[needs_prefix] <- paste0(prefix, nodes$id[needs_prefix])

    if (any(needs_prefix)) {
      renamed <- c(renamed, paste0(nodes$id[needs_prefix], " -> ", id_map[needs_prefix]))
    }

    nodes$id <- unname(id_map[nodes$id])

    if (nrow(edges) > 0) {
      edges$from <- unname(id_map[edges$from])
      edges$to <- unname(id_map[edges$to])
    }

    all_nodes[[i]] <- nodes
    all_edges[[i]] <- edges
    seen_ids <- c(seen_ids, nodes$id)
  }

  combined_nodes <- do.call(rbind, all_nodes)
  combined_edges <- unique(do.call(rbind, all_edges))
  rownames(combined_nodes) <- NULL
  rownames(combined_edges) <- NULL

  list(
    schema = base_schema,
    nodes = combined_nodes,
    edges = combined_edges,
    renamed_ids = renamed
  )
}

read_savepoint <- function(path) {
  if (!file.exists(path)) {
    stop("Savepoint file not found: ", path, call. = FALSE)
  }

  raw <- jsonlite::read_json(path, simplifyVector = TRUE)

  found_version <- if (is.null(raw$format_version)) "unknown" else raw$format_version

  if (found_version != CURRENT_SAVEPOINT_VERSION) {
    stop(
      paste0(
        "Incompatible savepoint format (found '", found_version,
        "', expected '", CURRENT_SAVEPOINT_VERSION, "')."
      ),
      call. = FALSE
    )
  }

  schema <- as.data.frame(raw$schema, stringsAsFactors = FALSE)
  validate_schema(schema)

  nodes <- normalize_dpsir_nodes(as.data.frame(raw$nodes, stringsAsFactors = FALSE))

  edges <- if (is.null(raw$edges) || length(raw$edges) == 0) {
    create_empty_graph_edges()
  } else {
    normalize_dpsir_edges(as.data.frame(raw$edges, stringsAsFactors = FALSE))
  }

  positions <- if (is.null(raw$positions) || length(raw$positions) == 0) {
    NULL
  } else {
    as.data.frame(raw$positions, stringsAsFactors = FALSE)
  }

  # Revisao 1, Fase 3 - absent on any savepoint written before this
  # revision, read back as NULL exactly like `positions` above (same
  # `length(...) == 0` guard, not just is.null(): an R-side NULL passed to
  # build_savepoint() serializes to JSON as "{}", not "null", so a plain
  # is.null() check alone would miss it - confirmed empirically, same trap
  # `positions` already accounts for). mod_data.R treats a NULL
  # scenario_state as "nothing to restore", same as it already does for
  # NULL positions.
  scenario_state <- if (is.null(raw$scenario_state) || length(raw$scenario_state) == 0) {
    NULL
  } else {
    ss <- raw$scenario_state
    empty_rows <- data.frame(id = character(), strength = numeric(), stringsAsFactors = FALSE)
    pressure_df <- if (is.null(ss$pressure) || length(ss$pressure) == 0) empty_rows else as.data.frame(ss$pressure, stringsAsFactors = FALSE)
    response_df <- if (is.null(ss$response) || length(ss$response) == 0) empty_rows else as.data.frame(ss$response, stringsAsFactors = FALSE)

    list(
      response_active = as.character(response_df$id),
      response_strengths = setNames(as.numeric(response_df$strength), response_df$id),
      pressure_active = as.character(pressure_df$id),
      pressure_strengths = setNames(as.numeric(pressure_df$strength), pressure_df$id),
      effect_horizon = if (is.null(ss$effect_horizon)) 0.5 else as.numeric(ss$effect_horizon)
    )
  }

  list(
    format_version = raw$format_version,
    metadata = raw$metadata,
    schema = schema,
    nodes = nodes,
    edges = edges,
    positions = positions,
    scenario_state = scenario_state
  )
}
