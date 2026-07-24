# =====================================================
# GRAPH INPUT VALIDATION
# =====================================================

validate_nodes <- function(nodes) {
  if (is.null(nodes) || !is.data.frame(nodes)) {
    stop("Nodes must be a data.frame.", call. = FALSE)
  }

  validate_dpsir_nodes(nodes)
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

validate_graph_inputs <- function(nodes, edges = NULL) {
  validate_nodes(nodes)

  if (!is.null(edges)) {
    validate_edges(edges)
    validate_dpsir_edges(nodes, edges)
  }

  invisible(TRUE)
}
