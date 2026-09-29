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

# Revisao 2, item 2.3: a pathway follows the D-P-S-I-R order of the schema.
# Its length is capped at the number of levels between the two categories
# (the full chain length when going "backwards" from a feedback level), a
# feedback (Response) node never sits in the middle of a pathway, and
# max_paths is applied during the enumeration, not after it.
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

  if (length(from_nodes) == 0 || length(to_nodes) == 0 || max_paths <= 0) {
    return(list())
  }

  ord <- setNames(schema$order, schema$name)
  n_levels <- length(ord)
  step <- ord[[to_category]] - ord[[from_category]]
  cutoff <- if (step > 0) step else n_levels - 1
  feedback_ids <- V(g)$name[has_role(g, "feedback")]

  out <- list()
  for (from_node in from_nodes) {
    found <- all_simple_paths(g, from = from_node, to = to_nodes, mode = mode, cutoff = cutoff)
    for (path in found) {
      ids <- V(g)$name[as.integer(path)]
      inner <- if (length(ids) > 2) ids[2:(length(ids) - 1)] else character()
      if (any(inner %in% feedback_ids)) next
      out[[length(out) + 1]] <- path
      if (length(out) >= max_paths) return(out)
    }
  }
  out
}

# Revisao 2, item 2.7: the effect of a pathway is the product of the signed
# betas along it - the exact indirect effect of that path in path analysis.
# The band is the product of the band limits (in absolute value), with the
# path's sign.
pathway_effect <- function(g, path) {
  edge_ids <- E(g, path = path)
  beta <- as.numeric(E(g)$weight[edge_ids])
  beta[is.na(beta)] <- 1
  sgn <- ifelse(E(g)$interaction_type[edge_ids] %in% "negative", -1, 1)
  low <- E(g)$weight_low; high <- E(g)$weight_high
  low <- if (is.null(low)) beta else as.numeric(low[edge_ids])
  high <- if (is.null(high)) beta else as.numeric(high[edge_ids])
  low[is.na(low)] <- beta[is.na(low)]
  high[is.na(high)] <- beta[is.na(high)]
  s <- prod(sgn)
  list(effect = s * prod(beta), sign = if (s > 0) "positive" else "negative",
       band_low = s * prod(abs(if (s > 0) low else high)), band_high = s * prod(abs(if (s > 0) high else low)))
}

# Kept for older callers: |effect| of the pathway.
score_pathway <- function(g, path) abs(pathway_effect(g, path)$effect)

compute_critical_pathways <- function(g, paths, top_n = 10) {
  stopifnot(inherits(g, "igraph"))

  if (length(paths) == 0) {
    return(
      data.frame(
        pathway_id = integer(),
        nodes = character(),
        path = character(),
        length = integer(),
        effect = numeric(),
        sign = character(),
        band_low = numeric(),
        band_high = numeric(),
        stringsAsFactors = FALSE
      )
    )
  }

  eff <- lapply(paths, function(path) pathway_effect(g, path))
  labels <- if (!is.null(V(g)$label)) V(g)$label else V(g)$name
  pathway_table <- data.frame(
    pathway_id = seq_along(paths),
    nodes = vapply(paths, function(path) paste(V(g)$name[as.integer(path)], collapse = " -> "), character(1)),
    path = vapply(paths, function(path) paste(labels[as.integer(path)], collapse = " -> "), character(1)),
    length = vapply(paths, function(path) length(path) - 1L, integer(1)),
    effect = vapply(eff, `[[`, numeric(1), "effect"),
    sign = vapply(eff, `[[`, character(1), "sign"),
    band_low = vapply(eff, `[[`, numeric(1), "band_low"),
    band_high = vapply(eff, `[[`, numeric(1), "band_high"),
    stringsAsFactors = FALSE
  )

  pathway_table <- pathway_table[order(-abs(pathway_table$effect)), , drop = FALSE]
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

  # Revisao 2, item 2.6: the driver and impact levels by role.
  driver_cat <- categories_with_role("driver", schema)
  impact_cat <- categories_with_role("impact", schema)
  if (length(driver_cat) == 0 || length(impact_cat) == 0) {
    return(list(available = FALSE, truncated = FALSE, table = compute_critical_pathways(g, list(), top_n = 0)))
  }

  paths <- find_dpsir_paths(g, driver_cat[1], impact_cat[1], schema = schema, max_paths = max_paths)

  list(
    available = TRUE,
    truncated = length(paths) >= max_paths,
    table = compute_critical_pathways(g, paths, top_n = max_paths)
  )
}

# Revisao 2, item 2.7: display table shared by the Metrics tab and the report.
format_pathways_table <- function(tbl) {
  data.frame(
    Pathway = tbl$path,
    Links = tbl$length,
    Effect = round(tbl$effect, 3),
    Sign = tbl$sign,
    Band = sprintf("%.3f to %.3f", tbl$band_low, tbl$band_high),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

PATHWAYS_CAPTION <- paste(
  "Every causal chain from a Driver to an Impact that follows the DPSIR order, ranked by its effect: the product of",
  "the signed strengths along the chain, i.e. the indirect effect of that path (path analysis). Band: product of the",
  "strengths' uncertainty limits."
)
