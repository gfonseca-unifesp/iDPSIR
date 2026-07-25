# =====================================================
# DPSIR RESPONSE SIMULATION (schema-aware)
# =====================================================
#
# Adaptado de R/dpsir/core_dpsir_responses.R (preservado, nao sourceado)
# mais find_response_targets, que vivia em R/dpsir/core_dpsir_pathways.R
# (superado por R/pathways.R na Fase 2, mas essa funcao especifica de
# Response nao foi migrada la). Categoria "Response" fixa vira
# get_feedback_categories(schema) (role == "feedback"), no mesmo padrao
# ja usado em R/pathways.R.

get_feedback_categories <- function(schema) {
  validate_schema(schema)
  schema$name[!is.na(schema$role) & schema$role == "feedback"]
}

empty_response_targets <- function() {
  data.frame(
    response_id = character(),
    target_id = character(),
    target_category = character(),
    stringsAsFactors = FALSE
  )
}

find_response_targets <- function(g, schema, response_id = NULL) {
  stopifnot(inherits(g, "igraph"))

  feedback_categories <- get_feedback_categories(schema)

  response_nodes <- unique(unlist(lapply(
    feedback_categories,
    function(category) get_vertices_by_dpsir_category(g, category, schema)
  )))

  if (!is.null(response_id)) {
    response_nodes <- intersect(response_nodes, response_id)
  }

  if (length(response_nodes) == 0) {
    return(empty_response_targets())
  }

  rows <- lapply(response_nodes, function(node_id) {
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

  result <- do.call(rbind, rows)
  if (is.null(result)) empty_response_targets() else result
}

# =====================================================
# EDGE HELPERS
# =====================================================

get_edge_selector <- function(g, from = NULL, to = NULL) {
  stopifnot(inherits(g, "igraph"))

  edge_ids <- seq_len(ecount(g))
  edge_ends <- ends(g, E(g))

  if (!is.null(from)) {
    edge_ids <- edge_ids[edge_ends[edge_ids, 1] %in% from]
  }

  if (!is.null(to)) {
    edge_ids <- edge_ids[edge_ends[edge_ids, 2] %in% to]
  }

  edge_ids
}

modify_edge_weight <- function(g, from, to, multiplier = 1) {
  stopifnot(inherits(g, "igraph"))

  edge_ids <- get_edge_selector(g, from = from, to = to)

  if (length(edge_ids) == 0) {
    return(g)
  }

  if (is.null(E(g)$weight)) {
    E(g)$weight <- 1
  }

  E(g)$weight[edge_ids] <- E(g)$weight[edge_ids] * multiplier
  g
}

disable_edge <- function(g, from, to) {
  stopifnot(inherits(g, "igraph"))

  edge_ids <- get_edge_selector(g, from = from, to = to)

  if (length(edge_ids) == 0) {
    return(g)
  }

  delete_edges(g, edge_ids)
}

# =====================================================
# APPLY RESPONSE (motor superado pela Fase 5 Marco B)
# =====================================================
#
# `apply_response`, `compute_node_impact_score`, `summarize_response_impact`,
# `compare_states` e `compare_multiple_states` abaixo foram o motor da aba
# Scenarios ate a Fase 5. Substituidas por `press_perturbation` e as
# funcoes de cenario em `R/loop_analysis.R` (mod_responses.R ja nao chama
# nenhuma destas) porque o metodo antigo so alterava um passo de peso de
# aresta e ignorava o peso da propria aresta da Resposta; o de loop usa o
# grafo inteiro (incluindo o loop de feedback) e o peso real da Resposta.
# Mantidas no arquivo (nao removidas) porque `get_feedback_categories` e
# `find_response_targets` acima continuam em uso.

apply_response <- function(
    g,
    schema,
    response_id,
    strength = 0.5,
    mode = c("mitigate", "amplify"),
    target_categories = NULL
) {
  stopifnot(inherits(g, "igraph"))

  mode <- match.arg(mode)

  if (!response_id %in% V(g)$name) {
    stop("Response node not found in graph.", call. = FALSE)
  }

  node_category <- V(g)$dpsir_category[match(response_id, V(g)$name)]
  if (!node_category %in% get_feedback_categories(schema)) {
    stop("Selected node is not a feedback/Response category.", call. = FALSE)
  }

  if (is.null(target_categories)) {
    target_categories <- setdiff(schema_categories(schema), get_feedback_categories(schema))
  }

  response_targets <- find_response_targets(g, schema, response_id)

  if (nrow(response_targets) == 0) {
    return(g)
  }

  response_targets <- response_targets[
    response_targets$target_category %in% target_categories,
    ,
    drop = FALSE
  ]

  if (nrow(response_targets) == 0) {
    return(g)
  }

  multiplier <- if (mode == "mitigate") {
    1 - strength
  } else {
    1 + strength
  }

  if (is.null(E(g)$weight)) {
    E(g)$weight <- 1
  }

  target_ids <- response_targets$target_id
  affected_edges <- get_edge_selector(g, to = target_ids)

  E(g)$weight[affected_edges] <- E(g)$weight[affected_edges] * multiplier

  graph_attr(g, "last_response") <- response_id
  graph_attr(g, "last_response_mode") <- mode
  graph_attr(g, "last_response_strength") <- strength

  g
}

# =====================================================
# IMPACT SCORING AND COMPARISON
# =====================================================

compute_node_impact_score <- function(g) {
  stopifnot(inherits(g, "igraph"))

  if (vcount(g) == 0) {
    return(numeric(0))
  }

  degree_score <- as.numeric(degree(g, mode = "all"))
  pagerank_score <- as.numeric(page_rank(g)$vector)

  uncertainty_score <- rep(0, vcount(g))
  controllability_score <- rep(0, vcount(g))

  ordinal_map <- c(low = 1, medium = 2, high = 3)

  if (!is.null(V(g)$uncertainty)) {
    uncertainty_values <- tolower(trimws(as.character(V(g)$uncertainty)))
    uncertainty_score <- vapply(
      uncertainty_values,
      function(x) if (x %in% names(ordinal_map)) ordinal_map[[x]] else 0,
      numeric(1)
    )
  }

  if (!is.null(V(g)$controllability)) {
    controllability_values <- tolower(trimws(as.character(V(g)$controllability)))
    controllability_score <- vapply(
      controllability_values,
      function(x) if (x %in% names(ordinal_map)) ordinal_map[[x]] else 0,
      numeric(1)
    )
  }

  score <- degree_score +
    (pagerank_score * max(vcount(g), 1) * 10) +
    uncertainty_score +
    controllability_score

  setNames(score, V(g)$name)
}

summarize_response_impact <- function(before, after) {
  stopifnot(inherits(before, "igraph"))
  stopifnot(inherits(after, "igraph"))

  if (vcount(before) == 0 || vcount(after) == 0) {
    return(
      data.frame(
        id = character(),
        node = character(),
        category = character(),
        before_score = numeric(),
        after_score = numeric(),
        delta = numeric(),
        direction = character(),
        stringsAsFactors = FALSE
      )
    )
  }

  before_scores <- compute_node_impact_score(before)
  after_scores <- compute_node_impact_score(after)

  node_ids <- intersect(names(before_scores), names(after_scores))

  impact <- data.frame(
    id = node_ids,
    node = if (!is.null(V(before)$label)) {
      V(before)$label[match(node_ids, V(before)$name)]
    } else {
      node_ids
    },
    category = if (!is.null(V(before)$dpsir_category)) {
      V(before)$dpsir_category[match(node_ids, V(before)$name)]
    } else {
      rep("", length(node_ids))
    },
    before_score = before_scores[node_ids],
    after_score = after_scores[node_ids],
    delta = after_scores[node_ids] - before_scores[node_ids],
    stringsAsFactors = FALSE
  )

  impact$direction <- ifelse(
    impact$delta < 0,
    "Improves",
    ifelse(impact$delta > 0, "Worsens", "Stable")
  )

  impact[order(-abs(impact$delta)), ]
}

compare_states <- function(before, after) {
  stopifnot(inherits(before, "igraph"))
  stopifnot(inherits(after, "igraph"))

  before_weights <- E(before)$weight
  after_weights <- E(after)$weight

  if (is.null(before_weights)) before_weights <- rep(1, ecount(before))
  if (is.null(after_weights)) after_weights <- rep(1, ecount(after))

  data.frame(
    metric = c("nodes", "edges", "total_edge_weight", "density"),
    before = c(
      vcount(before),
      ecount(before),
      sum(before_weights, na.rm = TRUE),
      edge_density(before)
    ),
    after = c(
      vcount(after),
      ecount(after),
      sum(after_weights, na.rm = TRUE),
      edge_density(after)
    ),
    stringsAsFactors = FALSE
  )
}

compare_multiple_states <- function(baseline, scenario_graphs) {
  stopifnot(inherits(baseline, "igraph"))
  stopifnot(is.list(scenario_graphs))

  baseline_weights <- E(baseline)$weight
  if (is.null(baseline_weights)) baseline_weights <- rep(1, ecount(baseline))

  metrics <- c("nodes", "edges", "total_edge_weight", "density")
  values <- function(g) {
    w <- E(g)$weight
    if (is.null(w)) w <- rep(1, ecount(g))
    c(vcount(g), ecount(g), sum(w, na.rm = TRUE), edge_density(g))
  }

  result <- data.frame(metric = metrics, Baseline = values(baseline), stringsAsFactors = FALSE)

  for (scenario_name in names(scenario_graphs)) {
    result[[scenario_name]] <- values(scenario_graphs[[scenario_name]])
  }

  result
}
