# =====================================================
# VALIDACAO - NOS E ARESTAS (SCHEMA-DRIVEN)
# =====================================================

get_required_dpsir_node_fields <- function() {
  c("id", "label", "dpsir_category")
}

get_required_dpsir_edge_fields <- function() {
  c("from", "to")
}

normalize_dpsir_nodes <- function(nodes) {
  nodes <- as.data.frame(nodes, stringsAsFactors = FALSE)
  nodes$id <- trimws(as.character(nodes$id))
  nodes$label <- as.character(nodes$label)
  nodes$dpsir_category <- trimws(as.character(nodes$dpsir_category))
  nodes
}

normalize_dpsir_edges <- function(edges) {
  edges <- as.data.frame(edges, stringsAsFactors = FALSE)

  if (nrow(edges) == 0) {
    return(edges)
  }

  edges$from <- trimws(as.character(edges$from))
  edges$to <- trimws(as.character(edges$to))

  if ("weight" %in% names(edges)) {
    edges$weight <- as.numeric(edges$weight)
  }

  if ("confidence" %in% names(edges)) {
    edges$confidence <- as.numeric(edges$confidence)
  }

  edges
}

validate_required_fields <- function(data, required_fields, object_name) {
  missing_fields <- setdiff(required_fields, names(data))

  if (length(missing_fields) > 0) {
    stop(
      paste(
        object_name,
        "is missing required fields:",
        paste(missing_fields, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_categories <- function(nodes, schema) {
  valid_categories <- schema_categories(schema)

  invalid <- is.na(nodes$dpsir_category) |
    !nodes$dpsir_category %in% valid_categories

  if (any(invalid)) {
    stop(
      paste(
        "Invalid DPSIR categories:",
        paste(unique(nodes$dpsir_category[invalid]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_unique_node_ids <- function(nodes) {
  duplicated_ids <- unique(nodes$id[duplicated(nodes$id)])

  if (length(duplicated_ids) > 0) {
    stop(
      paste("Duplicated node ids:", paste(duplicated_ids, collapse = ", ")),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_nodes <- function(nodes, schema = get_default_dpsir_schema()) {
  validate_required_fields(
    nodes,
    get_required_dpsir_node_fields(),
    "Nodes table"
  )

  nodes <- normalize_dpsir_nodes(nodes)

  validate_unique_node_ids(nodes)
  validate_dpsir_categories(nodes, schema)

  invisible(TRUE)
}

validate_edge_node_existence <- function(nodes, edges) {
  invalid_from <- !edges$from %in% nodes$id
  invalid_to <- !edges$to %in% nodes$id

  if (any(invalid_from)) {
    stop(
      paste(
        "Edges contain invalid 'from' node ids:",
        paste(unique(edges$from[invalid_from]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (any(invalid_to)) {
    stop(
      paste(
        "Edges contain invalid 'to' node ids:",
        paste(unique(edges$to[invalid_to]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_edge_logic <- function(nodes, edges, schema) {
  allowed_connections <- schema_allowed_connections(schema)
  node_categories <- setNames(nodes$dpsir_category, nodes$id)
  invalid_edges <- character()

  for (i in seq_len(nrow(edges))) {
    from_id <- edges$from[i]
    to_id <- edges$to[i]

    from_category <- unname(node_categories[from_id])
    to_category <- unname(node_categories[to_id])
    allowed_targets <- allowed_connections[[from_category]]

    if (is.null(allowed_targets) || !to_category %in% allowed_targets) {
      invalid_edges <- c(
        invalid_edges,
        paste0(
          from_id,
          " (",
          from_category,
          ") -> ",
          to_id,
          " (",
          to_category,
          ")"
        )
      )
    }
  }

  if (length(invalid_edges) > 0) {
    stop(
      paste(
        "Invalid DPSIR edge connections:",
        paste(invalid_edges, collapse = "; ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_edges <- function(nodes, edges, schema = get_default_dpsir_schema()) {
  validate_required_fields(
    edges,
    get_required_dpsir_edge_fields(),
    "Edges table"
  )

  nodes <- normalize_dpsir_nodes(nodes)
  edges <- normalize_dpsir_edges(edges)

  if (nrow(edges) == 0) {
    return(invisible(TRUE))
  }

  validate_edge_node_existence(nodes, edges)
  validate_dpsir_edge_logic(nodes, edges, schema)

  invisible(TRUE)
}

is_valid_dpsir_network <- function(nodes, edges = NULL, schema = get_default_dpsir_schema()) {
  tryCatch(
    {
      validate_dpsir_nodes(nodes, schema)

      if (!is.null(edges)) {
        validate_dpsir_edges(nodes, edges, schema)
      }

      TRUE
    },
    error = function(e) {
      FALSE
    }
  )
}

# =====================================================
# VALIDACAO DE ENTRADA DO GRAFO
# =====================================================

validate_nodes <- function(nodes, schema = get_default_dpsir_schema()) {
  if (is.null(nodes) || !is.data.frame(nodes)) {
    stop("Nodes must be a data.frame.", call. = FALSE)
  }

  validate_dpsir_nodes(nodes, schema)
  invisible(TRUE)
}

validate_edges <- function(edges) {
  if (is.null(edges)) {
    return(invisible(TRUE))
  }

  if (!is.data.frame(edges)) {
    stop("Edges must be a data.frame.", call. = FALSE)
  }

  validate_required_fields(
    edges,
    get_required_dpsir_edge_fields(),
    "Edges table"
  )

  invisible(TRUE)
}

validate_graph_inputs <- function(nodes, edges = NULL, schema = get_default_dpsir_schema()) {
  validate_nodes(nodes, schema)

  if (!is.null(edges)) {
    validate_edges(edges)
    validate_dpsir_edges(nodes, edges, schema)
  }

  invisible(TRUE)
}
