# =====================================================
# DPSIR PATHWAY ANALYSIS (schema-aware)
# =====================================================
#
# Adaptado de R/dpsir/core_dpsir_pathways.R (preservado, nao sourceado) para
# usar o schema configuravel em vez das categorias fixas do DPSIR canonico.
# `find_driver_impact_paths` e `highlight_pathway` nao foram migradas: a
# primeira e redundante (a UI sempre informa from/to explicitos) e a
# segunda foi substituida pelo parametro generico `highlighted_nodes` em
# `build_network_visual` (R/graph.R), mais reaproveitavel.

get_vertices_by_dpsir_category <- function(g, category, schema = get_default_dpsir_schema()) {
  stopifnot(inherits(g, "igraph"))

  if (!category %in% schema_categories(schema)) {
    stop("Unknown DPSIR category: ", category, call. = FALSE)
  }

  V(g)$name[V(g)$dpsir_category == category]
}

find_dpsir_paths <- function(
    g,
    from_category,
    to_category,
    mode = "out",
    max_paths = 100,
    schema = get_default_dpsir_schema()
) {
  stopifnot(inherits(g, "igraph"))

  from_nodes <- get_vertices_by_dpsir_category(g, from_category, schema)
  to_nodes <- get_vertices_by_dpsir_category(g, to_category, schema)

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

compute_critical_pathways <- function(g, paths, top_n = 10) {
  stopifnot(inherits(g, "igraph"))

  if (length(paths) == 0) {
    return(
      data.frame(
        pathway_id = integer(),
        nodes = character(),
        length = integer(),
        score = numeric(),
        stringsAsFactors = FALSE
      )
    )
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

# Todos os caminhos causais de Driver a Impact (a cadeia classica do DPSIR,
# nao um par de categoria escolhido caso a caso como o dropdown "Highlight
# pathway" do Graph tab) - usado pela nova subsecao de Descriptors.
# `max_paths` fica documentado, nao "sem limite algum": uma rede densa
# poderia ter um numero combinatorialmente grande de caminhos simples, e um
# limite explicito com aviso na UI e melhor que travar o app. `$truncated`
# sinaliza quando o limite foi de fato atingido, pra tela/relatorio avisarem
# em vez de mostrar uma lista silenciosamente incompleta como se fosse tudo.
compute_all_driver_impact_pathways <- function(g, schema, max_paths = 500) {
  stopifnot(inherits(g, "igraph"))

  cats <- schema_categories(schema)
  if (!("Driver" %in% cats) || !("Impact" %in% cats)) {
    return(list(available = FALSE, truncated = FALSE, table = compute_critical_pathways(g, list(), top_n = 0)))
  }

  paths <- find_dpsir_paths(g, "Driver", "Impact", schema = schema, max_paths = max_paths)

  list(
    available = TRUE,
    truncated = length(paths) >= max_paths,
    table = compute_critical_pathways(g, paths, top_n = max_paths)
  )
}
