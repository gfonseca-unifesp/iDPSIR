# =====================================================
# DPSIR PATHWAY ANALYSIS
# =====================================================

get_vertices_by_dpsir_category <- function(g, category) {
  stopifnot(inherits(g, "igraph"))
  validate_dpsir_category(category)

  V(g)$name[V(g)$dpsir_category == category]
}

path_vertices_to_labels <- function(g, path) {
  ids <- V(g)$name[as.integer(path)]
  labels <- V(g)$label[match(ids, V(g)$name)]

  labels[is.na(labels)] <- ids[is.na(labels)]

  data.frame(
    id = ids,
    label = labels,
    dpsir_category = V(g)$dpsir_category[match(ids, V(g)$name)],
    stringsAsFactors = FALSE
  )
}

find_dpsir_paths <- function(
    g,
    from_category = "Driver",
    to_category = "Impact",
    mode = "out",
    max_paths = 100
) {
  stopifnot(inherits(g, "igraph"))
  validate_dpsir_category(c(from_category, to_category))

  from_nodes <- get_vertices_by_dpsir_category(g, from_category)
  to_nodes <- get_vertices_by_dpsir_category(g, to_category)

  if (length(from_nodes) == 0 || length(to_nodes) == 0) {
    return(list())
  }

  paths <- unlist(
    lapply(from_nodes, function(from_node) {
      all_simple_paths(
        g,
        from = from_node,
        to = to_nodes,
        mode = mode
      )
    }),
    recursive = FALSE
  )

  paths[seq_len(min(length(paths), max_paths))]
}

find_driver_impact_paths <- function(g, max_paths = 100) {
  find_dpsir_paths(
    g,
    from_category = "Driver",
    to_category = "Impact",
    max_paths = max_paths
  )
}

find_response_targets <- function(g, response_id = NULL) {
  stopifnot(inherits(g, "igraph"))

  response_nodes <- get_vertices_by_dpsir_category(g, "Response")

  if (!is.null(response_id)) {
    response_nodes <- intersect(response_nodes, response_id)
  }

  if (length(response_nodes) == 0) {
    return(data.frame())
  }

  do.call(
    rbind,
    lapply(response_nodes, function(node_id) {
      neighbors_out <- neighbors(g, node_id, mode = "out")
      target_ids <- V(g)$name[as.integer(neighbors_out)]

      if (length(target_ids) == 0) {
        return(NULL)
      }

      data.frame(
        response_id = node_id,
        target_id = target_ids,
        target_category = V(g)$dpsir_category[match(target_ids, V(g)$name)],
        stringsAsFactors = FALSE
      )
    })
  )
}

score_pathway <- function(g, path) {
  edge_ids <- E(g, path = path)
  weights <- E(g)$weight[edge_ids]
  confidence <- E(g)$confidence[edge_ids]

  if (length(weights) == 0 || all(is.na(weights))) {
    weights <- rep(1, length(edge_ids))
  }

  if (length(confidence) == 0 || all(is.na(confidence))) {
    confidence <- rep(1, length(edge_ids))
  }

  mean(as.numeric(weights), na.rm = TRUE) *
    mean(as.numeric(confidence), na.rm = TRUE) *
    length(edge_ids)
}

compute_critical_pathways <- function(g, paths = NULL, top_n = 10) {
  stopifnot(inherits(g, "igraph"))

  if (is.null(paths)) {
    paths <- find_driver_impact_paths(g)
  }

  if (length(paths) == 0) {
    return(data.frame())
  }

  pathway_table <- data.frame(
    pathway_id = seq_along(paths),
    nodes = vapply(
      paths,
      function(path) {
        paste(V(g)$name[as.integer(path)], collapse = " -> ")
      },
      character(1)
    ),
    length = vapply(paths, length, integer(1)),
    score = vapply(paths, function(path) score_pathway(g, path), numeric(1)),
    stringsAsFactors = FALSE
  )

  pathway_table <- pathway_table[order(-pathway_table$score), , drop = FALSE]
  head(pathway_table, top_n)
}

highlight_pathway <- function(nodes, edges, pathway_nodes) {
  pathway_nodes <- as.character(pathway_nodes)

  nodes$highlighted <- nodes$id %in% pathway_nodes

  if (!is.null(edges) && nrow(edges) > 0) {
    edges$highlighted <- edges$from %in% pathway_nodes &
      edges$to %in% pathway_nodes
  }

  list(nodes = nodes, edges = edges)
}
