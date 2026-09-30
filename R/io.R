# =====================================================
# IO - IMPORTACAO DE MATRIZES E SAVEPOINT (.idpsir.json)
# =====================================================

CURRENT_SAVEPOINT_VERSION <- "1.0"

# =====================================================
# IMPORTAR MATRIZES (CSV)
# =====================================================

# Revisao 2, item 1.5: a CSV's `weight` column is read as |beta| (the
# structural mode, D17). `convert_legacy = TRUE` treats it instead as an
# older relative weight and converts it with convert_legacy_weights() (the
# user ticks this on the Import card); `conversion` then reports lambda and
# the edges whose converted |beta| exceeds 1.
import_matrices <- function(nodes_path, edges_path = NULL, convert_legacy = FALSE, legacy_c = 0.5) {
  nodes <- data.table::fread(nodes_path)
  nodes <- normalize_dpsir_nodes(nodes)
  conversion <- NULL

  edges <- if (is.null(edges_path) || !nzchar(edges_path)) {
    create_empty_graph_edges()
  } else {
    edges_raw <- as.data.frame(data.table::fread(edges_path), stringsAsFactors = FALSE)
    if (isTRUE(convert_legacy) && nrow(edges_raw) > 0) {
      edges_raw$from <- trimws(as.character(edges_raw$from))
      edges_raw$to <- trimws(as.character(edges_raw$to))
      conversion <- convert_legacy_weights(nodes, edges_raw, legacy_c)
      edges_raw <- conversion$edges
    }
    normalize_dpsir_edges(edges_raw)
  }

  list(nodes = nodes, edges = edges, conversion = conversion)
}

# Plain-language notes about a legacy conversion, shown on the Start step.
legacy_conversion_notes <- function(conversion) {
  if (is.null(conversion)) return(character())
  notes <- sprintf(
    paste(
      "Edge weights were converted from the older relative scale to standardized strengths (beta = %.3f x weight,",
      "the reach factor the older version used with c = %.2f), so the static results are the same as before.",
      "Review each edge's strength."
    ),
    conversion$lambda, conversion$c
  )
  if (length(conversion$review) > 0) {
    notes <- c(notes, sprintf(
      "After conversion these edges have a strength above 1 and are marked for review: %s.",
      paste(conversion$review, collapse = ", ")
    ))
  }
  notes
}

# =====================================================
# CONSTRUIR SAVEPOINT
# =====================================================

# Revisao 2, item 3.13: the definitions of saved scenarios (not their
# results, which are recomputed on load) - rows for the strengths, like
# scenario_state, so jsonlite never unboxes a single-entry named vector.
saved_scenarios_to_json <- function(saved) {
  if (is.null(saved) || length(saved) == 0) return(NULL)
  temporal_keys <- c("temporal_mode_pressure", "temporal_mode_response", "temporal_stop_rule", "temporal_max_windows",
                     "temporal_windows", "temporal_tol_rel", "baseline_without_response", "temporal_gate_mode",
                     "temporal_trends_outside", "temporal_continue_after")
  unname(lapply(saved, function(sc) {
    out <- list(
      name = sc$name,
      response = data.frame(id = as.character(sc$active), strength = unname(as.numeric(sc$strengths[sc$active])), stringsAsFactors = FALSE),
      pressure = data.frame(id = as.character(sc$pressure_active), strength = unname(as.numeric(sc$pressure_strengths[sc$pressure_active])), stringsAsFactors = FALSE),
      n_simulations = sc$n_simulations %||% 300
    )
    for (k in temporal_keys) if (!is.null(sc[[k]])) out[[k]] <- sc[[k]]
    if (is.data.frame(sc$temporal_schedule) && nrow(sc$temporal_schedule) > 0) out$temporal_schedule <- sc$temporal_schedule
    out
  }))
}

saved_scenarios_from_json <- function(raw) {
  if (is.null(raw) || length(raw) == 0) return(NULL)
  items <- if (is.data.frame(raw)) lapply(seq_len(nrow(raw)), function(i) lapply(raw, `[[`, i)) else raw
  lapply(items, function(it) {
    rows <- function(x) {
      if (is.null(x) || length(x) == 0) return(data.frame(id = character(), strength = numeric()))
      as.data.frame(x, stringsAsFactors = FALSE)
    }
    r <- rows(it$response); p <- rows(it$pressure)
    out <- list(
      name = as.character(it$name),
      active = as.character(r$id), strengths = setNames(as.numeric(r$strength), r$id),
      pressure_active = as.character(p$id), pressure_strengths = setNames(as.numeric(p$strength), p$id),
      n_simulations = as.integer(it$n_simulations %||% 300)
    )
    for (k in setdiff(names(it), c("name", "response", "pressure", "n_simulations", "temporal_schedule"))) out[[k]] <- it[[k]]
    if (!is.null(it$temporal_schedule) && length(it$temporal_schedule) > 0) out$temporal_schedule <- as.data.frame(it$temporal_schedule, stringsAsFactors = FALSE)
    out
  })
}

build_savepoint <- function(schema, nodes, edges, positions = NULL, metadata = list(), scenario_state = NULL, saved_scenarios = NULL) {
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
  # Revisao 2, Fase 1: marks the file as using standardized strengths
  # (beta); a savepoint without it is converted on load (read_savepoint()).
  metadata$weight_mode <- "structural"

  # Revisao 1, Fase 3: `scenario_state` arrives as
  # list(pressure_active=<chr>, pressure_strengths=<named num>,
  # response_active=<chr>, response_strengths=<named num>)
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
      # Revisao 2, item A5: the temporal simulation settings (NULL ones are
      # dropped below, so jsonlite never writes them as "{}").
      temporal_mode_pressure = scenario_state$temporal_mode_pressure,
      temporal_mode_response = scenario_state$temporal_mode_response,
      temporal_stop_rule = scenario_state$temporal_stop_rule,
      temporal_max_windows = scenario_state$temporal_max_windows,
      temporal_windows = scenario_state$temporal_windows,
      temporal_tol_rel = scenario_state$temporal_tol_rel,
      baseline_without_response = scenario_state$baseline_without_response,
      temporal_gate_mode = scenario_state$temporal_gate_mode,
      # Revisao 2, Fase D.
      temporal_trends_outside = scenario_state$temporal_trends_outside,
      temporal_continue_after = scenario_state$temporal_continue_after,
      # Audit: the number of simulations of the confidence readings.
      n_simulations = scenario_state$n_simulations,
      temporal_schedule = if (is.data.frame(scenario_state$temporal_schedule) && nrow(scenario_state$temporal_schedule) > 0) scenario_state$temporal_schedule else NULL
    )
  }
  if (!is.null(scenario_state_json)) scenario_state_json <- Filter(Negate(is.null), scenario_state_json)

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
    scenario_state = scenario_state_json,
    saved_scenarios = saved_scenarios_to_json(saved_scenarios)
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
    pretty = TRUE,
    # Revisao 2, Fase 1: jsonlite rounds to 4 decimals by default - harmless
    # for the older integer weights, but a converted beta (e.g. 0.3657532)
    # would lose precision on every save. digits = NA keeps full precision.
    digits = NA
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
    # Audit: files with the same name (or a prefixed id that already
    # exists) gave duplicate ids - add the file's position until unique.
    for (k in which(needs_prefix)) {
      candidate <- paste0(prefix, nodes$id[k])
      if (candidate %in% c(seen_ids, nodes$id, id_map[-k])) candidate <- paste0(source_names[i], "_", i, "__", nodes$id[k])
      j <- 2
      while (candidate %in% c(seen_ids, nodes$id, id_map[-k])) {
        candidate <- paste0(source_names[i], "_", i, "_", j, "__", nodes$id[k]); j <- j + 1
      }
      id_map[k] <- candidate
    }

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

# `convert_legacy = FALSE` keeps an older file's relative weights as they
# are - only for the legacy equilibrium engine's tests (R/loop_analysis.R).
read_savepoint <- function(path, convert_legacy = TRUE) {
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

  # Revisao 2, item 0.6: a savepoint is checked exactly like an imported
  # CSV before normalize_dpsir_*() fills in defaults. A hand-edited or
  # shared file with confidence 3 used to reach runif(min > max) (NaN), and
  # a negative weight flipped an edge's sign on top of interaction_type.
  raw_nodes <- if (is.null(raw$nodes) || length(raw$nodes) == 0) NULL else as.data.frame(raw$nodes, stringsAsFactors = FALSE)
  raw_edges <- if (is.null(raw$edges) || length(raw$edges) == 0) NULL else as.data.frame(raw$edges, stringsAsFactors = FALSE)
  preflight <- if (is.null(raw_nodes)) {
    list(blocking = character(), warnings = character())
  } else {
    preflight_import(raw_nodes, raw_edges, schema)
  }
  if (length(preflight$blocking) > 0) {
    stop(
      paste0(
        "This savepoint has values the app cannot use: ",
        paste(sub("^Edges file", "Edges", sub("^Nodes file", "Nodes", preflight$blocking)), collapse = " ")
      ),
      call. = FALSE
    )
  }

  raw_nodes_df <- as.data.frame(raw$nodes, stringsAsFactors = FALSE)
  # Revisao 2, item A8: an older savepoint without self_regulation keeps the
  # behaviour it was saved with (0), not the new default 0.5.
  # Audit: a file without metadata$weight_mode but with the structural
  # edge columns (e.g. edited by hand or by another tool) is NOT legacy.
  structural_cols <- !is.null(raw_edges) && any(c("strength_class", "weight_low", "weight_high", "weight_source") %in% names(raw_edges))
  is_legacy_file <- (is.null(raw$metadata$weight_mode) || !identical(raw$metadata$weight_mode, "structural")) && !structural_cols
  if (is_legacy_file && nrow(raw_nodes_df) > 0 && !"self_regulation" %in% names(raw_nodes_df)) {
    raw_nodes_df$self_regulation <- 0
  }
  nodes <- normalize_dpsir_nodes(raw_nodes_df, schema)

  # Revisao 2, item 1.5: a savepoint written before the structural mode
  # (no metadata$weight_mode) holds relative weights plus a global reach c.
  # Convert them to beta = lambda * w with the c it was saved with, which
  # keeps its static numbers exactly.
  metadata <- raw$metadata
  conversion <- NULL
  is_legacy <- is_legacy_file
  if (isTRUE(convert_legacy) && is_legacy && !is.null(raw_edges) && nrow(raw_edges) > 0) {
    legacy_c <- suppressWarnings(as.numeric(raw$scenario_state$effect_horizon))
    if (length(legacy_c) != 1 || is.na(legacy_c)) legacy_c <- 0.5
    raw_edges$from <- trimws(as.character(raw_edges$from))
    raw_edges$to <- trimws(as.character(raw_edges$to))
    conversion <- convert_legacy_weights(nodes, raw_edges, legacy_c)
    raw_edges <- conversion$edges
    if (is.null(metadata)) metadata <- list()
    metadata$weight_mode <- "structural"
    metadata$converted_from <- list(lambda = conversion$lambda, c = conversion$c)
  }

  edges <- if (is.null(raw_edges) || nrow(raw_edges) == 0) {
    create_empty_graph_edges()
  } else {
    normalize_dpsir_edges(raw_edges)
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
    ss_val <- function(x) if (is.null(x) || length(x) == 0) NULL else x
    empty_rows <- data.frame(id = character(), strength = numeric(), stringsAsFactors = FALSE)
    pressure_df <- if (is.null(ss$pressure) || length(ss$pressure) == 0) empty_rows else as.data.frame(ss$pressure, stringsAsFactors = FALSE)
    response_df <- if (is.null(ss$response) || length(ss$response) == 0) empty_rows else as.data.frame(ss$response, stringsAsFactors = FALSE)

    list(
      response_active = as.character(response_df$id),
      response_strengths = setNames(as.numeric(response_df$strength), response_df$id),
      pressure_active = as.character(pressure_df$id),
      pressure_strengths = setNames(as.numeric(pressure_df$strength), pressure_df$id),
      effect_horizon = if (is.null(ss$effect_horizon)) 0.5 else as.numeric(ss$effect_horizon),
      # Revisao 2, item A5: temporal settings. An older savepoint without
      # them gets the new defaults - except the stop rule, which stays
      # "fixed" when the file already records a number of windows, so the
      # saved result is reproduced.
      temporal_mode_pressure = ss_val(ss$temporal_mode_pressure) %||% "permanent",
      temporal_mode_response = ss_val(ss$temporal_mode_response) %||% "permanent",
      temporal_stop_rule = ss_val(ss$temporal_stop_rule) %||% (if (!is.null(ss_val(ss$temporal_windows))) "fixed" else "until_neutralized"),
      temporal_max_windows = ss_val(ss$temporal_max_windows) %||% 50,
      temporal_windows = ss_val(ss$temporal_windows) %||% 5,
      temporal_tol_rel = ss_val(ss$temporal_tol_rel) %||% 5,
      baseline_without_response = isTRUE(ss$baseline_without_response),
      temporal_gate_mode = ss_val(ss$temporal_gate_mode) %||% "state_level",
      # Revisao 2, Fase D.
      temporal_trends_outside = if (is.null(ss_val(ss$temporal_trends_outside))) TRUE else isTRUE(ss$temporal_trends_outside),
      temporal_continue_after = ss_val(ss$temporal_continue_after) %||% 0,
      n_simulations = ss_val(ss$n_simulations) %||% 300,
      temporal_schedule = if (is.null(ss$temporal_schedule) || length(ss$temporal_schedule) == 0) NULL else as.data.frame(ss$temporal_schedule, stringsAsFactors = FALSE)
    )
  }

  list(
    format_version = raw$format_version,
    metadata = metadata,
    schema = schema,
    nodes = nodes,
    edges = edges,
    positions = positions,
    scenario_state = scenario_state,
    saved_scenarios = saved_scenarios_from_json(raw$saved_scenarios),
    warnings = c(
      sub("^Edges file", "Savepoint edges", sub("^Nodes file", "Savepoint nodes",
        # An older file's weights above 1 are expected - they are converted.
        # (The CSV-only "tick Convert..." hint does not apply to a savepoint.)
        if (is.null(conversion)) {
          sub(" If this is an older file with relative weights, tick 'Convert from older relative weights'.", "", preflight$warnings, fixed = TRUE)
        } else {
          preflight$warnings[!grepl("is above 1 - unusual", preflight$warnings)]
        }
      )),
      legacy_conversion_notes(conversion)
    ),
    conversion = conversion
  )
}
