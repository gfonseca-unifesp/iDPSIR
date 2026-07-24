# =====================================================
# METRICAS - CENTRALIDADES, GERAIS E DESCRITORES DPSIR
# =====================================================

# =====================================================
# CENTRALIDADES
# =====================================================
#
# `weighted = TRUE` usa o atributo `weight` da aresta (forca do elo).
# Para betweenness/closeness, que sao medidas de caminho mais curto, o
# igraph trata `weight` como DISTANCIA por padrao — inverteria a semantica
# (elo mais forte pareceria mais "longe"). Por isso convertemos para
# distancia = 1/forca antes de passar para essas duas funcoes. Degree,
# eigenvector e pagerank ja tratam `weight` como intensidade/fluxo, entao
# usam o atributo diretamente.

edge_weights_as_distance <- function(g, weighted) {
  if (!isTRUE(weighted) || is.null(igraph::edge_attr(g, "weight"))) {
    return(NA)
  }

  1 / igraph::E(g)$weight
}

edge_weights_as_strength <- function(g, weighted) {
  if (!isTRUE(weighted) || is.null(igraph::edge_attr(g, "weight"))) {
    return(NA)
  }

  igraph::E(g)$weight
}

compute_degree <- function(g, mode = "all", weighted = FALSE) {
  if (is.null(g) || vcount(g) == 0) {
    return(NULL)
  }

  if (isTRUE(weighted) && !is.null(igraph::edge_attr(g, "weight"))) {
    return(strength(g, mode = mode, weights = E(g)$weight))
  }

  degree(g, mode = mode)
}

compute_betweenness <- function(g, directed = TRUE, normalized = TRUE, weighted = FALSE) {
  if (is.null(g) || vcount(g) == 0) {
    return(NULL)
  }

  betweenness(
    g,
    directed = directed,
    normalized = normalized,
    weights = edge_weights_as_distance(g, weighted)
  )
}

compute_closeness <- function(g, mode = "all", normalized = TRUE, weighted = FALSE) {
  if (is.null(g) || vcount(g) == 0) {
    return(NULL)
  }

  closeness(
    g,
    mode = mode,
    normalized = normalized,
    weights = edge_weights_as_distance(g, weighted)
  )
}

compute_pagerank <- function(g, weighted = FALSE) {
  if (is.null(g) || vcount(g) == 0) {
    return(NULL)
  }

  page_rank(g, weights = edge_weights_as_strength(g, weighted))$vector
}

compute_eigenvector <- function(g, weighted = FALSE) {
  if (is.null(g) || vcount(g) == 0) {
    return(NULL)
  }

  eigen_centrality(g, weights = edge_weights_as_strength(g, weighted))$vector
}

# =====================================================
# METRICAS GERAIS DO GRAFO
# =====================================================

compute_communities <- function(g) {
  if (is.null(g) || vcount(g) == 0) {
    return(NULL)
  }

  cluster_louvain(as.undirected(g))
}

compute_density <- function(g) {
  if (is.null(g) || vcount(g) == 0) return(NA)
  edge_density(g)
}

compute_diameter <- function(g) {
  if (is.null(g) || vcount(g) == 0) return(NA)
  diameter(g, directed = TRUE, weights = NA)
}

compute_transitivity <- function(g) {
  if (is.null(g) || vcount(g) == 0) return(NA)
  transitivity(g, type = "global")
}

compute_modularity <- function(g) {
  communities <- compute_communities(g)
  if (is.null(communities)) return(NA)
  modularity(communities)
}

compute_component_count <- function(g) {
  if (is.null(g) || vcount(g) == 0) return(NA)
  components(g, mode = "weak")$no
}

compute_general_metrics <- function(g) {
  data.frame(
    metric = c(
      "Nodes", "Edges", "Density", "Diameter",
      "Transitivity", "Modularity", "Components"
    ),
    value = c(
      vcount(g),
      ecount(g),
      compute_density(g),
      compute_diameter(g),
      compute_transitivity(g),
      compute_modularity(g),
      compute_component_count(g)
    ),
    stringsAsFactors = FALSE
  )
}

# =====================================================
# TABELA DE CENTRALIDADES
# =====================================================

compute_all_metrics <- function(g, directed = TRUE, normalized = TRUE, weighted = FALSE) {
  node_labels <- vertex_attr(g, "label")
  if (is.null(node_labels)) {
    node_labels <- V(g)$name
  }

  g_analysis <- if (isTRUE(directed)) g else as.undirected(g)

  data.frame(
    id = V(g)$name,
    node = node_labels,
    degree = compute_degree(g_analysis, weighted = weighted),
    betweenness = compute_betweenness(g_analysis, directed = directed, normalized = normalized, weighted = weighted),
    closeness = compute_closeness(g_analysis, normalized = normalized, weighted = weighted),
    pagerank = compute_pagerank(g_analysis, weighted = weighted),
    eigenvector = compute_eigenvector(g_analysis, weighted = weighted),
    stringsAsFactors = FALSE
  )
}

# =====================================================
# DESCRITORES DPSIR
# =====================================================

ordinal_score <- function(x, levels = c("low", "medium", "high")) {
  match(x, levels)
}

compute_dpsir_descriptors <- function(g, schema) {
  categories <- schema_categories(schema)

  nodes <- graph_to_nodes(g)
  edges <- graph_to_edges(g)

  # ---- contagem de nos por categoria ----
  count_by_category <- data.frame(
    dpsir_category = categories,
    n_nodes = as.integer(table(factor(nodes$dpsir_category, levels = categories))),
    stringsAsFactors = FALSE
  )

  # ---- contagem de arestas por transicao + matriz categoria x categoria ----
  transition_matrix <- matrix(
    0L,
    nrow = length(categories),
    ncol = length(categories),
    dimnames = list(categories, categories)
  )

  transitions <- data.frame(from_category = character(), to_category = character(), n_edges = integer())

  if (nrow(edges) > 0) {
    category_by_id <- setNames(nodes$dpsir_category, nodes$id)
    from_category <- unname(category_by_id[edges$from])
    to_category <- unname(category_by_id[edges$to])

    for (i in seq_along(from_category)) {
      if (!is.na(from_category[i]) && !is.na(to_category[i])) {
        transition_matrix[from_category[i], to_category[i]] <-
          transition_matrix[from_category[i], to_category[i]] + 1
      }
    }

    transitions <- as.data.frame(
      table(from_category = from_category, to_category = to_category),
      stringsAsFactors = FALSE
    )
    names(transitions) <- c("from_category", "to_category", "n_edges")
    transitions <- transitions[transitions$n_edges > 0, ]
  }

  # ---- impactos sem resposta ----
  impact_ids <- nodes$id[nodes$dpsir_category == "Impact"]
  response_ids <- nodes$id[nodes$dpsir_category == "Response"]

  impacts_without_response <- if (length(impact_ids) == 0) {
    character()
  } else if (nrow(edges) == 0) {
    impact_ids
  } else {
    covered <- unique(edges$from[edges$from %in% impact_ids & edges$to %in% response_ids])
    setdiff(impact_ids, covered)
  }

  # ---- pressoes nao cobertas por respostas ----
  pressure_ids <- nodes$id[nodes$dpsir_category == "Pressure"]

  pressures_without_response <- if (length(pressure_ids) == 0) {
    character()
  } else if (nrow(edges) == 0) {
    pressure_ids
  } else {
    covered <- unique(edges$to[edges$to %in% pressure_ids & edges$from %in% response_ids])
    setdiff(pressure_ids, covered)
  }

  # ---- medias de incerteza/controlabilidade por categoria ----
  nodes$.uncertainty_score <- ordinal_score(nodes$uncertainty)
  nodes$.controllability_score <- ordinal_score(nodes$controllability)

  averages_by_category <- do.call(rbind, lapply(categories, function(cat) {
    subset_nodes <- nodes[nodes$dpsir_category == cat, ]
    data.frame(
      dpsir_category = cat,
      avg_uncertainty = mean(subset_nodes$.uncertainty_score, na.rm = TRUE),
      avg_controllability = mean(subset_nodes$.controllability_score, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))

  list(
    count_by_category = count_by_category,
    transitions = transitions,
    transition_matrix = transition_matrix,
    impacts_without_response = impacts_without_response,
    pressures_without_response = pressures_without_response,
    averages_by_category = averages_by_category
  )
}
