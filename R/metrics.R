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

  # Revisao 2, item 2.4: Louvain is randomized - fixed seed, reproducible.
  with_local_seed(42, cluster_louvain(as_undirected(g)))
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

  g_analysis <- if (isTRUE(directed)) g else as_undirected(g)

  data.frame(
    id = V(g)$name,
    node = node_labels,
    degree = compute_degree(g_analysis, weighted = weighted),
    betweenness = compute_betweenness(g_analysis, directed = directed, normalized = normalized, weighted = weighted),
    # Audit: with "Directed" on, closeness follows the arrows (outgoing
    # paths) - it used mode = "all" either way. Degree stays total degree.
    closeness = compute_closeness(g_analysis, mode = if (isTRUE(directed)) "out" else "all", normalized = normalized, weighted = weighted),
    pagerank = compute_pagerank(g_analysis, weighted = weighted),
    eigenvector = compute_eigenvector(g_analysis, weighted = weighted),
    stringsAsFactors = FALSE
  )
}

# =====================================================
# DESCRITORES DPSIR
# =====================================================

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
  # Revisao 2, item 2.6: by role, not by category name.
  node_role <- roles_of(nodes$dpsir_category, schema)
  impact_ids <- nodes$id[node_role %in% "impact"]
  response_ids <- nodes$id[node_role %in% "feedback"]

  impacts_without_response <- if (length(impact_ids) == 0) {
    character()
  } else if (nrow(edges) == 0) {
    impact_ids
  } else {
    # Audit: a Response acting directly on the Impact (R -> I) also covers
    # it, not only an Impact -> Response link.
    covered <- unique(c(
      edges$from[edges$from %in% impact_ids & edges$to %in% response_ids],
      edges$to[edges$to %in% impact_ids & edges$from %in% response_ids]
    ))
    setdiff(impact_ids, covered)
  }

  # ---- pressoes nao cobertas por respostas ----
  pressure_ids <- nodes$id[node_role %in% "pressure"]

  pressures_without_response <- if (length(pressure_ids) == 0) {
    character()
  } else if (nrow(edges) == 0) {
    pressure_ids
  } else {
    covered <- unique(edges$to[edges$to %in% pressure_ids & edges$from %in% response_ids])
    setdiff(pressure_ids, covered)
  }

  list(
    count_by_category = count_by_category,
    transitions = transitions,
    transition_matrix = transition_matrix,
    impacts_without_response = impacts_without_response,
    pressures_without_response = pressures_without_response
  )
}

# =====================================================
# STRENGTH AND CONFIDENCE OF THE WHOLE NETWORK (Revisao 3)
# =====================================================
#
# Global reading of a parameterized network: how strong it is (link classes,
# explained variance, loop amplification, end-to-end transmission) and how
# well founded (where the strengths came from, width of their bands,
# evidence and references, expected absent links, sign determinacy of the
# Driver -> Impact effects). No composite score: each measure says one thing
# and where to look. Static reading, without State triggers.

# Where each strength came from: estimated from data (r2, calibrated, or a
# typed value backed by regression/calibration/definition evidence), typed
# in (given), a class, the default, or converted from an old file.
edge_strength_origin <- function(g) {
  m <- igraph::ecount(g)
  if (m == 0) return(character())
  src <- igraph::E(g)$weight_source
  if (is.null(src)) src <- rep(NA_character_, m)
  ev <- igraph::E(g)$evidence_type
  if (is.null(ev)) ev <- rep("", m)
  ev <- tolower(trimws(as.character(ev)))
  ev[is.na(ev)] <- ""
  src <- as.character(src)
  ifelse(src %in% c("r2", "calibrated"), "estimated",
  ifelse(src %in% "given", ifelse(ev %in% c("regression", "calibration", "definition"), "estimated", "given"),
  ifelse(src %in% "class", "class",
  ifelse(src %in% "converted", "converted", "default"))))
}

# Driver -> Impact total effects under the link bands (drawn as in the
# confidence readings; draws where the loops amplify are skipped): `share` =
# pairs whose sign holds in at least `level` of the draws (QPress-style sign
# determinacy - without loops and with bands that do not cross zero it is
# always 100%); `spread` = median over the pairs of the 90% interval of the
# effect divided by its value (how much the magnitude is pinned down).
sign_determinacy <- function(g, n = 200, seed = 42, level = 0.95) {
  none <- list(share = NA_real_, spread = NA_real_, pairs = 0L, used = 0L)
  ids <- igraph::V(g)$name
  d <- ids[has_role(g, "driver")]
  im <- ids[has_role(g, "impact")]
  if (length(d) == 0 || length(im) == 0 || igraph::ecount(g) == 0) return(none)
  B0 <- effect_matrix(g)
  if (spectral_radius(B0) >= 1) return(none)
  total <- function(B) {
    M <- solve(diag(length(ids)) - B)
    dimnames(M) <- list(ids, ids)
    M[im, d, drop = FALSE]
  }
  base <- total(B0)
  linked <- abs(base) > 1e-12
  if (!any(linked)) return(none)
  w <- igraph::E(g)$weight
  low <- igraph::E(g)$weight_low
  high <- igraph::E(g)$weight_high
  if (is.null(low)) low <- w
  if (is.null(high)) high <- w
  draws <- resample_edge_weights(g, w, low, high, n, seed)
  same <- matrix(0, nrow(base), ncol(base))
  vals <- matrix(NA_real_, n, sum(linked))
  used <- 0L
  gg <- g
  for (k in seq_len(n)) {
    igraph::E(gg)$weight <- draws[k, ]
    B <- effect_matrix(gg)
    if (spectral_radius(B) >= 1) next
    te <- total(B)
    same <- same + (sign(te) == sign(base))
    used <- used + 1L
    vals[k, ] <- te[linked]
  }
  if (used == 0) return(list(share = NA_real_, spread = NA_real_, pairs = sum(linked), used = 0L))
  q <- apply(vals, 2, stats::quantile, probs = c(0.05, 0.95), na.rm = TRUE)
  list(share = mean((same / used)[linked] >= level),
       spread = stats::median((q[2, ] - q[1, ]) / abs(base[linked])),
       pairs = sum(linked), used = used)
}

network_strength_confidence <- function(g, n_draws = 200, seed = 42) {
  m <- igraph::ecount(g)
  ids <- igraph::V(g)$name
  if (m == 0) {
    return(list(summary = data.frame(Aspect = character(), Measure = character(), Value = character(), Reading = character()),
                by_transition = data.frame()))
  }
  pct <- function(x) sprintf("%.0f%%", 100 * x)
  num <- function(x, d = 2) if (is.na(x)) "-" else formatC(x, format = "f", digits = d)
  lab <- function(x) { l <- igraph::V(g)$label[match(x, ids)]; ifelse(is.na(l) | !nzchar(l), x, l) }
  el <- igraph::as_edgelist(g, names = TRUE)
  cat_of <- igraph::V(g)$dpsir_category[match(el[, 1], ids)]
  cat_to <- igraph::V(g)$dpsir_category[match(el[, 2], ids)]
  from_resp <- roles_of(cat_of) %in% "feedback"
  w <- abs(as.numeric(igraph::E(g)$weight))
  cls <- classify_beta(w)
  conf <- igraph::E(g)$confidence
  if (is.null(conf)) conf <- rep(NA_real_, m)
  origin <- edge_strength_origin(g)
  assumed <- origin %in% c("class", "default", "converted")
  ev <- igraph::E(g)$evidence_type
  if (is.null(ev)) ev <- rep("", m)
  ref <- igraph::E(g)$reference
  if (is.null(ref)) ref <- rep("", m)
  has_ev <- !is.na(ev) & nzchar(trimws(as.character(ev)))
  has_ref <- !is.na(ref) & nzchar(trimws(as.character(ref)))
  p_abs <- edge_absence_probability(g)

  # Explained variance: sum of beta^2 arriving at each factor (responses
  # left out, as in the Review warning).
  s2 <- if (any(!from_resp)) tapply(w[!from_resp]^2, el[!from_resp, 2], sum) else numeric()
  B <- effect_matrix(g)
  rho <- spectral_radius(B)
  # End-to-end transmission: total effect of each Driver on each Impact.
  d <- ids[has_role(g, "driver")]
  im <- ids[has_role(g, "impact")]
  trans <- NA_real_
  trans_max <- NA_real_
  trans_pair <- ""
  if (rho < 1 && length(d) > 0 && length(im) > 0) {
    M <- solve(diag(length(ids)) - B)
    dimnames(M) <- list(ids, ids)
    te <- abs(M[im, d, drop = FALSE])
    if (any(te > 1e-12)) {
      trans <- mean(te[te > 1e-12])
      trans_max <- max(te)
      k <- which(te == trans_max, arr.ind = TRUE)[1, ]
      trans_pair <- sprintf("strongest: %s -> %s", lab(d[k[2]]), lab(im[k[1]]))
    }
  }
  det <- sign_determinacy(g, n = n_draws, seed = seed)
  states <- ids[has_role(g, "state")]
  thr <- igraph::V(g)$threshold_level
  n_thr <- if (is.null(thr) || length(states) == 0) 0L else sum(!is.na(thr[match(states, ids)]))

  rows <- list(
    c("Strength", "Links by class (weak / moderate / strong)",
      sprintf("%d / %d / %d", sum(cls == "weak", na.rm = TRUE), sum(cls == "moderate", na.rm = TRUE), sum(cls == "strong", na.rm = TRUE)),
      "weak |beta| < 0.3, moderate < 0.6, strong >= 0.6"),
    c("Strength", "Mean |beta| (median)", sprintf("%s (%s)", num(mean(w)), num(stats::median(w))),
      "standardized effect: SD of the target per SD of the source"),
    c("Strength", "Explained variance per factor (mean; max)",
      if (length(s2)) sprintf("%s; %s", pct(mean(s2)), pct(max(s2))) else "-",
      if (length(s2) && any(s2 > 1 + 1e-9)) sprintf("%d factor(s) above 100%% - review their incoming strengths", sum(s2 > 1 + 1e-9))
      else "sum of beta^2 arriving at each factor (links from responses left out)"),
    c("Strength", "Loop amplification rho(B)", num(rho),
      if (rho >= 1) "the loops amplify without bound - the static reading is not defined"
      else if (rho > 0.8) "strong loops: effects are amplified and slow to settle"
      else if (rho > 1e-9) "loops present; the effects settle" else "no feedback loops"),
    c("Strength", "Driver -> Impact total effect (mean |effect|; max)",
      if (is.na(trans)) "-" else sprintf("%s; %s", num(trans), num(trans_max)),
      if (is.na(trans)) "no Driver reaches an Impact, or rho >= 1" else paste0("SD of the Impact per SD of the Driver; ", trans_pair)),
    c("Confidence", "Strength from data / typed in / class / default",
      sprintf("%s / %s / %s / %s", pct(mean(origin == "estimated")), pct(mean(origin == "given")),
              pct(mean(origin == "class")), pct(mean(origin %in% c("default", "converted")))),
      if (mean(assumed) > 0.5) "most strengths are assumed - check the links behind tight verdicts first"
      else "share of links whose strength has a value behind it"),
    c("Confidence", "Mean link confidence (share >= 0.5)",
      if (all(is.na(conf))) "-" else sprintf("%s (%s)", num(mean(conf, na.rm = TRUE)), pct(mean(conf >= 0.5, na.rm = TRUE))),
      "1 - band width / beta: 1 = exact value, 0 = band as wide as the value"),
    c("Confidence", "Links with evidence type / with reference", sprintf("%s / %s", pct(mean(has_ev)), pct(mean(has_ref))),
      "traceability of the structure"),
    c("Confidence", "Links expected absent (structural uncertainty)", sprintf("%s of %d", num(sum(p_abs), 1), m),
      sprintf("from the evidence type; %s of the links are never absent", pct(mean(p_abs == 0)))),
    c("Confidence", "Driver -> Impact effects with a determinate sign",
      if (is.na(det$share)) "-" else pct(det$share),
      if (is.na(det$share)) "no Driver reaches an Impact, or the loops amplify"
      else sprintf("sign holds in >= 95%% of %d draws of the link bands (%d pairs)", det$used, det$pairs)),
    c("Confidence", "Driver -> Impact total effect: 90% interval / value (median)",
      if (is.na(det$spread)) "-" else pct(det$spread),
      if (is.na(det$spread)) "no Driver reaches an Impact, or the loops amplify"
      else if (det$spread > 1) "above 100%: the interval is wider than the effect itself - read verdicts with their confidence"
      else "how tightly the link bands pin down the end-to-end effects"),
    c("Confidence", "States with a threshold", if (length(states)) sprintf("%d of %d", n_thr, length(states)) else "-",
      "without a threshold, a State never switches its outgoing links")
  )
  summary <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(summary) <- c("Aspect", "Measure", "Value", "Reading")

  tr <- paste(cat_of, "->", cat_to)
  by <- do.call(rbind, lapply(unique(tr), function(t) {
    k <- tr == t
    data.frame(Transition = t, Links = sum(k), `Mean |beta|` = round(mean(w[k]), 2),
               `Mean confidence` = if (all(is.na(conf[k]))) NA_real_ else round(mean(conf[k], na.rm = TRUE), 2),
               `Assumed strength` = round(100 * mean(assumed[k])),
               `With reference` = round(100 * mean(has_ref[k])),
               `Expected absent` = round(sum(p_abs[k]), 1),
               check.names = FALSE, stringsAsFactors = FALSE)
  }))
  by <- by[order(-by$`Assumed strength`, by$`Mean confidence`), , drop = FALSE]
  names(by)[names(by) == "Assumed strength"] <- "Assumed strength (%)"
  names(by)[names(by) == "With reference"] <- "With reference (%)"
  rownames(by) <- NULL
  list(summary = summary, by_transition = by)
}
