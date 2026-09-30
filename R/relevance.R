# =====================================================
# RELEVANCE AND PRIORITY OF IMPACTS (Revisao 2, Fase B)
# =====================================================
#
# Implements the specification "Categorizacao dos nos de impacto &
# relevancia por analise de loop" v1.0 (decisions V1-V5, D6, D14, D15):
#
#   relevance_I = v_I * D_I * rho_I   (stable: how much the Impact matters)
#   priority_I  = relevance_I * gap_I (moves with the response scenario)
#
# - v   social value of the Impact (node field value_v, V1): 1 for an
#       ecological endpoint, elicited (swing weights) for service/welfare.
# - D   dynamic importance (V2, D14): the total effect of the pressure
#       scenario on each Impact, delta = propagate(B, p_D), max-normalized
#       over the Impacts. With standardized strengths (Fase 1) this IS the
#       Levins equilibrium of the specification in standardized form
#       (beta_ij = a_ij / |a_ii|) - checked in R on the specification's own
#       section 4 example (prototipos_revisao2/modo_estrutural.R).
# - rho reliability of that prediction (V4): share of simulations, with every
#       edge strength resampled within its uncertainty band, in which the sign
#       of delta_I matches the base case.
# - gap how much of the worsening the response scenario leaves uncovered
#       (D15: the response's efficacy is its coverage - the strength slider;
#       uncertainty only enters rho and the confidence readings).
#
# Why a product (Revisao 3, E4.1). Priority reads as an expected avoidable
# loss: value (v) x size of the change (D) x probability that its direction
# is right (rho) x share left uncovered (gap). A zero in any factor cancels
# on purpose - an Impact the pressure does not move, or one whose sign is
# unreliable, or one fully covered, has no priority. The additive form
# (relevance = w_v v + w_D D + w_rho rho, equal weights by default) is
# offered as an alternative (`aggregation = "additive"`) and used in
# priority_robustness() to show whether the order depends on the choice.

dynamic_importance <- function(g, p_D, threshold = 1e-9) {
  stopifnot(inherits(g, "igraph"))
  node_names <- V(g)$name
  impact_ids <- node_names[has_role(g, "impact")]
  if (length(impact_ids) == 0) {
    return(data.frame(id = character(), delta = numeric(), D = numeric(), stringsAsFactors = FALSE))
  }
  p_D <- align_press_vector(p_D, node_names, "pressure scenario")
  # Revisao 2, Fase C: with State thresholds, the gates of the pressure
  # scenario apply.
  delta <- propagate(gated_effect_matrix(g, p_D), p_D)[impact_ids]
  top <- max(abs(delta))
  D <- if (top <= threshold) rep(0, length(delta)) else abs(delta) / top
  out <- data.frame(id = impact_ids, delta = unname(delta), D = unname(D), stringsAsFactors = FALSE)
  attr(out, "all_zero") <- top <= threshold
  out
}

# Share of simulations in which sign(delta_I) matches the base case, with
# every beta resampled uniformly within its band (same draws as
# sufficiency_confidence()). Draws that make the loops amplify (rho(B) >= 1)
# are skipped. An Impact the pressure does not reach (delta = 0) gets NA.
prediction_reliability <- function(g, p_D, n_simulations = 300, seed = 42, threshold = 1e-9,
                                   structural = FALSE, absence = NULL) {
  stopifnot(inherits(g, "igraph"))
  node_names <- V(g)$name
  impact_ids <- node_names[has_role(g, "impact")]
  if (length(impact_ids) == 0) {
    return(data.frame(id = character(), rho = numeric(), stringsAsFactors = FALSE))
  }
  p_D <- align_press_vector(p_D, node_names, "pressure scenario")
  base <- propagate(gated_effect_matrix(g, p_D), p_D)[impact_ids]
  base_sign <- ifelse(abs(base) <= threshold, 0, sign(base))

  w <- E(g)$weight
  low <- E(g)$weight_low
  high <- E(g)$weight_high
  if (is.null(low)) low <- w
  if (is.null(high)) high <- w
  low[is.na(low)] <- w[is.na(low)]
  high[is.na(high)] <- w[is.na(high)]

  matches <- matrix(NA_integer_, n_simulations, length(impact_ids), dimnames = list(NULL, impact_ids))
  g_sim <- g
  draws <- resample_edge_weights(g, w, low, high, n_simulations, seed, structural, absence)
  with_local_seed(seed, {
    for (sim in seq_len(n_simulations)) {
      E(g_sim)$weight <- draws[sim, ]
      B <- effect_matrix(g_sim)
      if (spectral_radius(B) >= 1 - 1e-9) next
      d <- propagate(gated_effect_matrix(g_sim, p_D, B), p_D)[impact_ids]
      s <- ifelse(abs(d) <= threshold, 0, sign(d))
      matches[sim, ] <- as.integer(s == base_sign)
    }
  })
  rho <- colMeans(matches, na.rm = TRUE)[impact_ids]
  rho[base_sign == 0] <- NA_real_
  out <- data.frame(id = impact_ids, rho = unname(rho), stringsAsFactors = FALSE)
  attr(out, "skipped") <- sum(is.na(matches[, 1]))
  out
}

# gap_I = share of the worsening still uncovered by the response scenario,
# in [0, 1]: 0 = neutralized (or improved beyond neutral), 1 = the response
# does nothing for it. With the sign convention "Impact positive = worse",
# gap = max(0, net) / worsening. An Impact the pressure does not worsen
# (worsening <= threshold) has no gap: NA, shown as "Not affected".
impact_gap <- function(suff_df, threshold = 1e-9) {
  w <- suff_df$worsening
  n <- suff_df$net
  gap <- ifelse(w <= threshold, NA_real_, pmin(1, pmax(0, n) / w))
  setNames(gap, suff_df$id)
}

impact_prioritization <- function(g, p_D, suff_df, n_simulations = 300, seed = 42, structural = FALSE,
                                  aggregation = c("multiplicative", "additive"), weights = c(v = 1, D = 1, rho = 1) / 3) {
  aggregation <- match.arg(aggregation)
  stopifnot(inherits(g, "igraph"))
  impact_ids <- V(g)$name[has_role(g, "impact")]
  empty <- data.frame(
    id = character(), node = character(), endpoint_class = character(),
    value_v = numeric(), D = numeric(), rho = numeric(), relevance = numeric(),
    gap = numeric(), priority = numeric(), affected = logical(), stringsAsFactors = FALSE
  )
  if (length(impact_ids) == 0) return(empty)

  di <- dynamic_importance(g, p_D)
  rel <- prediction_reliability(g, p_D, n_simulations = n_simulations, seed = seed, structural = structural)
  gap <- impact_gap(suff_df)[impact_ids]

  idx <- match(impact_ids, V(g)$name)
  v <- suppressWarnings(as.numeric(V(g)$value_v[idx]))
  if (length(v) == 0) v <- rep(NA_real_, length(impact_ids))
  v[is.na(v)] <- 1
  ec <- V(g)$endpoint_class[idx]
  if (is.null(ec)) ec <- rep("ecological", length(impact_ids))
  ec[is.na(ec)] <- "ecological"

  w <- weights / sum(weights)
  relevance <- if (aggregation == "additive") w[["v"]] * v + w[["D"]] * di$D + w[["rho"]] * rel$rho else v * di$D * rel$rho
  affected <- !is.na(gap)
  out <- data.frame(
    id = impact_ids,
    node = if (!is.null(V(g)$label)) V(g)$label[idx] else impact_ids,
    endpoint_class = ec, value_v = v, D = di$D, rho = rel$rho,
    relevance = ifelse(affected, relevance, NA_real_),
    gap = unname(gap),
    priority = ifelse(affected, relevance * gap, NA_real_),
    affected = affected,
    # Audit: only worsened Impacts are prioritized; one the pressure
    # improves is labelled as such instead of "Not affected".
    improved = unname(suff_df$worsening[match(impact_ids, suff_df$id)] < -1e-9),
    stringsAsFactors = FALSE
  )
  out <- out[order(-ifelse(is.na(out$priority), -Inf, out$priority), -ifelse(is.na(out$relevance), -Inf, out$relevance)), ]
  rownames(out) <- NULL
  attr(out, "all_zero") <- attr(di, "all_zero")
  attr(out, "skipped") <- attr(rel, "skipped")
  attr(out, "aggregation") <- aggregation
  attr(out, "structural") <- structural
  out
}

# Display table shared by the Scenarios tab, the CSV download and the report.
format_prioritization_table <- function(df, robustness = NULL) {
  out <- format_prioritization_table_base(df)
  # Revisao 3, E4.2.
  if (!is.null(robustness) && nrow(robustness) > 0) {
    k <- match(df$id, robustness$id)
    out[["Rank stability"]] <- ifelse(is.na(k), "-", sprintf("%.0f%%", 100 * robustness$keeps_rank[k]))
  }
  out
}

format_prioritization_table_base <- function(df) {
  data.frame(
    Impact = df$node,
    Class = df$endpoint_class,
    `Importance D` = round(df$D, 2),
    # Audit: NaN rho = every draw skipped (loops amplify) - not computable.
    `Reliability rho` = ifelse(is.nan(df$rho), "not computable", ifelse(is.na(df$rho), "-", sprintf("%.0f%%", 100 * df$rho))),
    `Value v` = round(df$value_v, 2),
    Relevance = ifelse(df$affected & is.nan(df$relevance), "not computable", ifelse(df$affected, sprintf("%.2f", df$relevance), "-")),
    Gap = ifelse(df$affected, sprintf("%.2f", df$gap),
                 ifelse(df$improved %in% TRUE, "Improved by the pressure", "Not affected")),
    Priority = ifelse(df$affected & is.nan(df$priority), "not computable", ifelse(df$affected, sprintf("%.2f", df$priority), "-")),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

PRIORITIZATION_METHOD_NOTE <- paste(
  "D is the total effect of the pressure scenario on each Impact (path analysis of the edge strengths),",
  "which equals the Levins equilibrium of the relevance specification v1.0 when coefficients are standardized.",
  "Reliability is the share of simulations, with every edge strength resampled within its uncertainty range,",
  "in which that effect keeps its sign. Priority = relevance x the share of the worsening the response leaves uncovered."
)

# =====================================================
# Revisao 3, E4.2 - robustness of the priority order
# =====================================================
# Perturbs the values v by +/-20% (uniform, truncated to [0, 1]) and draws the
# aggregation (multiplicative or additive, equal probability) in each of `n`
# draws, keeping D, rho and the gap of `prio` (impact_prioritization()'s
# output). Over the worsened Impacts it reports, per Impact, the share of
# draws in which it keeps its base rank and in which it is first, and, as
# attributes, the mean Kendall tau against the base order and the share of
# draws with the same top Impact.
priority_robustness <- function(prio, n = 500, seed = 42, spread = 0.2, weights = c(v = 1, D = 1, rho = 1) / 3) {
  df <- prio[prio$affected & !is.na(prio$priority), , drop = FALSE]
  empty <- data.frame(id = character(), node = character(), keeps_rank = numeric(), first = numeric(), stringsAsFactors = FALSE)
  if (nrow(df) == 0) return(empty)
  rho <- ifelse(is.na(df$rho), 0, df$rho)
  base_rank <- rank(-df$priority, ties.method = "min")
  w <- weights / sum(weights)
  ranks <- matrix(NA_real_, n, nrow(df))
  taus <- numeric(n)
  with_local_seed(seed, {
    for (k in seq_len(n)) {
      v <- pmin(1, pmax(0, df$value_v * (1 + stats::runif(nrow(df), -spread, spread))))
      additive <- stats::runif(1) < 0.5
      rel <- if (additive) w[["v"]] * v + w[["D"]] * df$D + w[["rho"]] * rho else v * df$D * rho
      pr <- rel * df$gap
      ranks[k, ] <- rank(-pr, ties.method = "min")
      taus[k] <- if (nrow(df) >= 2 && stats::sd(pr) > 0 && stats::sd(df$priority) > 0)
        suppressWarnings(stats::cor(df$priority, pr, method = "kendall")) else NA_real_
    }
  })
  out <- data.frame(
    id = df$id, node = df$node,
    keeps_rank = colMeans(sweep(ranks, 2, base_rank, `==`)),
    first = colMeans(ranks == 1),
    stringsAsFactors = FALSE
  )
  base_top <- which(base_rank == 1)
  # Share of draws at each rank, per Impact (rows in `out` order), for the
  # rank-stability figure (draw_rank_stability_plot()).
  share <- t(vapply(seq_len(nrow(df)), function(j) tabulate(ranks[, j], nbins = nrow(df)) / n, numeric(nrow(df))))
  dimnames(share) <- list(df$id, seq_len(nrow(df)))
  attr(out, "rank_share") <- share
  attr(out, "base_rank") <- setNames(base_rank, df$id)
  attr(out, "kendall_tau") <- mean(taus, na.rm = TRUE)
  attr(out, "top_stable") <- mean(apply(ranks, 1, function(r) all(which(r == 1) %in% base_top)))
  attr(out, "n") <- n
  out
}

# Plain-language line under the prioritization table (screen and report).
# `wrap` is helpText on screen, a <p> in the report.
priority_robustness_note <- function(rob, wrap = function(x) x) {
  if (is.null(rob) || nrow(rob) == 0) return(NULL)
  wrap(sprintf(paste(
    "Rank stability: share of %d variations - every value v changed by up to 20%% and the index computed as a product or",
    "as a weighted sum - in which each Impact keeps its rank. The top priority stays the same in %.0f%% of them; mean",
    "Kendall's tau against this order: %.2f."),
    attr(rob, "n"), 100 * attr(rob, "top_stable"), attr(rob, "kendall_tau")))
}
