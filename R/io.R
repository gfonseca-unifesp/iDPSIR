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
