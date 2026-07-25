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

build_savepoint <- function(schema, nodes, edges, positions = NULL, metadata = list()) {
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

  list(
    format_version = CURRENT_SAVEPOINT_VERSION,
    metadata = metadata,
    schema = schema,
    nodes = nodes,
    edges = edges,
    positions = positions
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

  list(
    format_version = raw$format_version,
    metadata = raw$metadata,
    schema = schema,
    nodes = nodes,
    edges = edges,
    positions = positions
  )
}
