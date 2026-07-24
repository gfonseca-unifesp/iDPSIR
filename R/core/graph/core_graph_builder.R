# =====================================================
# GRAPH BUILDER
# =====================================================

create_empty_graph_edges <- function() {
  data.frame(
    from = character(),
    to = character(),
    weight = numeric(),
    confidence = numeric(),
    arrows = character(),
    width = numeric(),
    stringsAsFactors = FALSE
  )
}

prepare_nodes_for_graph <- function(nodes) {
  nodes <- normalize_dpsir_nodes(nodes)
  nodes <- apply_dpsir_visual_mapping(nodes)

  nodes$name <- nodes$id
  nodes
}

prepare_edges_for_graph <- function(edges) {
  if (is.null(edges) || nrow(edges) == 0) {
    edges <- create_empty_graph_edges()
  }

  edges <- normalize_dpsir_edges(edges)

  if (!"weight" %in% names(edges)) {
    edges$weight <- if (nrow(edges) == 0) numeric() else 1
  }

  if (!"confidence" %in% names(edges)) {
    edges$confidence <- if (nrow(edges) == 0) numeric() else 1
  }

  if (!"arrows" %in% names(edges)) {
    edges$arrows <- if (nrow(edges) == 0) character() else "to"
  }

  if (!"width" %in% names(edges)) {
    edges$width <- if (nrow(edges) == 0) {
      numeric()
    } else {
      pmax(as.numeric(edges$weight), 1)
    }
  }

  edges
}

build_igraph <- function(nodes, edges = NULL, verbose = FALSE) {
  validate_graph_inputs(nodes, edges)

  nodes <- prepare_nodes_for_graph(nodes)
  edges <- prepare_edges_for_graph(edges)

  if (verbose) {
    message("Building DPSIR graph with ", nrow(nodes), " nodes and ", nrow(edges), " edges.")
  }

  g <- graph_from_data_frame(
    d = edges,
    vertices = nodes,
    directed = TRUE
  )

  graph_attr(g, "network_type") <- "DPSIR"
  graph_attr(g, "directed") <- TRUE
  graph_attr(g, "created_at") <- Sys.time()

  g
}

graph_to_nodes <- function(g) {
  stopifnot(inherits(g, "igraph"))
  igraph::as_data_frame(g, what = "vertices")
}

graph_to_edges <- function(g) {
  stopifnot(inherits(g, "igraph"))
  igraph::as_data_frame(g, what = "edges")
}
