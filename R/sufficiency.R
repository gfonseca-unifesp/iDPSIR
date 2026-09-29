# =====================================================
# RESPONSE SUFFICIENCY - "TWO PUSHES" MODEL
# =====================================================
#
# Revisao 1 introduced this reading in place of the old equilibrium engine
# (-A^-1 press, R/loop_analysis.R), which needed a "stable" network and, on
# the Mangi et al. 2007 network, silently inverted a sign (gear restrictions
# "worsening" the reef). See CLAUDE.md for that history.
#
# Revisao 2, Fase 1 (structural mode, decisions D17-D21): every edge is a
# standardized path coefficient beta (R/structural.R), and the effect of a
# push p is the path-analysis total effect
#
#   Phi(p) = (I - B)^-1 p - p = B p + B^2 p + ...
#
# - products of beta along each path, summed over paths. There is no longer a
# global reach factor c: a response far from an Impact is attenuated by the
# product of the betas (< 1) on its path. The series converges, and (I - B) is
# invertible, whenever rho(B) < 1 - checked when the graph is built
# (check_effect_matrix()) and again here as a guard. For an acyclic network B
# is nilpotent (rho = 0) and the series simply stops at the longest path.
#
# In a DAG this equals the old reading with beta = c * weight; with cycles
# the old lambda = c / rho(W) is reproduced by converting an older file with
# beta = lambda * weight (convert_legacy_weights()), so older savepoints keep
# their static numbers exactly.
#
# Two independent pushes (built with build_press_vector()): p_D, the pressure
# scenario, and p_R, the response scenario. Phi is linear in p, so the two are
# computed separately and summed.

# Kept as an alias while callers move to effect_matrix() (Fase 4 removes it).
build_signed_matrix <- function(g) effect_matrix(g)

# Spectral radius = max modulus of the eigenvalues, NOT max real part -
# eigenvalues of a network with cycles are routinely complex (documented
# repeatedly elsewhere in this codebase), and it's the modulus that bounds
# how much a perturbation can amplify per matrix application, which is
# what convergence of the Neumann series actually depends on.
spectral_radius <- function(W) {
  stopifnot(is.matrix(W), nrow(W) == ncol(W))
  if (all(W == 0)) {
    return(0)
  }
  max(Mod(eigen(W, only.values = TRUE)$values))
}

propagate <- function(B, p) {
  stopifnot(is.matrix(B), nrow(B) == ncol(B))

  n <- nrow(B)
  if (all(B == 0)) {
    return(setNames(rep(0, n), rownames(B)))
  }

  rho <- spectral_radius(B)
  if (rho >= 1 - 1e-9) {
    stop(sprintf(
      "The network's feedback loops amplify without bound (spectral radius %.2f, it must be below 1). Lower the strength of the edges on the loop.",
      rho
    ), call. = FALSE)
  }

  solved <- solve(diag(n) - B, as.numeric(p))
  setNames(as.numeric(solved) - as.numeric(p), rownames(B))
}

# Revisao 2, item 0.3: press vectors are aligned to the network BY NAME,
# never by position. A scenario saved before a node was added used to be
# silently recycled by as.numeric() (wrong numbers, no error). A named vector
# is reordered to `node_names` (missing names = 0); a name that is not in the
# network is an error. An unnamed vector is accepted only when its length
# matches exactly (legacy callers/tests that build vectors in node order).
align_press_vector <- function(p, node_names, what = "scenario") {
  if (is.null(p)) {
    return(setNames(rep(0, length(node_names)), node_names))
  }
  if (is.null(names(p))) {
    if (length(p) != length(node_names)) {
      stop(sprintf(
        "The %s vector has %d values but the network has %d factors, and it has no factor names to align by.",
        what, length(p), length(node_names)
      ), call. = FALSE)
    }
    return(setNames(as.numeric(p), node_names))
  }
  unknown <- setdiff(names(p), node_names)
  if (length(unknown) > 0) {
    stop(sprintf(
      "The %s refers to factor(s) that are not in the network: %s. Apply the scenario again.",
      what, paste(unknown, collapse = ", ")
    ), call. = FALSE)
  }
  out <- setNames(as.numeric(p[node_names]), node_names)
  out[is.na(out)] <- 0
  out
}

# One row per Impact. `strength_to_neutralize` is a dimensionless ratio on
# whatever p_R represents (Phi is linear in p): > 1 means the planned
# response must be stronger to cover the worsening, < 1 means it already
# more than covers it. The screen multiplies it by the strength of a single
# active response (format_sufficiency_table()).
sufficiency <- function(g, p_D, p_R, threshold = 1e-9) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  p_D <- align_press_vector(p_D, node_names, "pressure scenario")
  p_R <- align_press_vector(p_R, node_names, "response scenario")
  categories <- V(g)$dpsir_category
  is_impact <- !is.null(categories) & categories == "Impact"
  impact_ids <- node_names[is_impact]

  empty <- data.frame(
    id = character(), node = character(),
    worsening = numeric(), mitigation = numeric(), net = numeric(),
    neutralized = logical(), strength_to_neutralize = numeric(),
    neutralized_by = character(),
    stringsAsFactors = FALSE
  )
  if (length(impact_ids) == 0) {
    return(empty)
  }

  B <- effect_matrix(g)

  if (!has_state_thresholds(g)) {
    worsening <- propagate(B, p_D)[impact_ids]
    mitigation <- propagate(B, p_R)[impact_ids]
    net <- worsening + mitigation
    strength_to_neutralize <- ifelse(
      mitigation < 0,
      worsening / (-mitigation),
      NA_real_ # response doesn't help this Impact at all - no finite strength neutralizes it
    )
    neutralized_by <- ifelse(net <= threshold, "mitigation", NA_character_)
  } else {
    # Revisao 2, item C2: a State trigger breaks linearity - the net effect
    # is computed with both pushes together, each scenario with the gates it
    # produces. A response can neutralize an Impact by CLOSING a trigger
    # (bringing the State back under its threshold) even when its linear
    # mitigation alone would only be partial.
    p_net <- p_D + p_R
    worsening <- propagate(gated_effect_matrix(g, p_D, B), p_D)[impact_ids]
    net <- propagate(gated_effect_matrix(g, p_net, B), p_net)[impact_ids]
    mitigation <- net - worsening
    linear_net <- propagate(gated_effect_matrix(g, p_D, B), p_net)[impact_ids]
    neutralized_by <- ifelse(net <= threshold, ifelse(linear_net > threshold, "trigger", "mitigation"), NA_character_)
    # Strength to neutralize by bisection on the response's scale s in [0, 10].
    net_at <- function(s) {
      p <- p_D + s * p_R
      propagate(gated_effect_matrix(g, p, B), p)[impact_ids]
    }
    strength_to_neutralize <- vapply(seq_along(impact_ids), function(k) {
      if (all(p_R == 0) || net_at(10)[k] > threshold) return(NA_real_)
      if (net_at(0)[k] <= threshold) return(0)
      lo <- 0; hi <- 10
      for (i in 1:40) {
        mid <- (lo + hi) / 2
        if (net_at(mid)[k] <= threshold) hi <- mid else lo <- mid
      }
      hi
    }, numeric(1))
  }

  # No strength is "needed" for an Impact the pressure does not worsen.
  strength_to_neutralize[worsening <= threshold] <- NA_real_

  data.frame(
    id = impact_ids,
    node = if (!is.null(V(g)$label)) V(g)$label[is_impact] else impact_ids,
    worsening = unname(worsening),
    mitigation = unname(mitigation),
    net = unname(net),
    neutralized = unname(net) <= threshold,
    strength_to_neutralize = unname(strength_to_neutralize),
    neutralized_by = unname(neutralized_by),
    stringsAsFactors = FALSE
  )
}

# Runs `expr` with a fixed RNG seed and restores the caller's RNG state
# afterwards, so resampling is reproducible without touching the global
# stream (base-R stand-in for withr::with_seed(), roadmap item 2.4).
with_local_seed <- function(seed, expr) {
  had_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had_seed) old <- get(".Random.seed", envir = globalenv())
  on.exit({
    if (had_seed) assign(".Random.seed", old, envir = globalenv())
    else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
  })
  set.seed(seed)
  expr
}

# Revisao 2, item 1.4 (D15/D21): each edge's beta is resampled uniformly
# within its uncertainty band [weight_low, weight_high]; `net` is recomputed
# and the result is the % of simulations in which the Impact is still
# neutralized. Draws that would make the loops amplify (rho(B) >= 1) are
# skipped and counted in the `skipped` attribute.
sufficiency_confidence <- function(g, p_D, p_R, n_simulations = 300, seed = 42, threshold = 1e-9) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(n_simulations >= 1)

  node_names <- V(g)$name
  p_D <- align_press_vector(p_D, node_names, "pressure scenario")
  p_R <- align_press_vector(p_R, node_names, "response scenario")
  categories <- V(g)$dpsir_category
  is_impact <- !is.null(categories) & categories == "Impact"
  impact_ids <- node_names[is_impact]

  if (length(impact_ids) == 0) {
    return(data.frame(id = character(), node = character(), neutralized_pct = numeric(), stringsAsFactors = FALSE))
  }

  base_weight <- E(g)$weight
  low <- E(g)$weight_low
  high <- E(g)$weight_high
  if (is.null(low)) low <- base_weight
  if (is.null(high)) high <- base_weight
  low[is.na(low)] <- base_weight[is.na(low)]
  high[is.na(high)] <- base_weight[is.na(high)]

  matches <- matrix(NA_integer_, nrow = n_simulations, ncol = length(impact_ids), dimnames = list(NULL, impact_ids))
  g_sim <- g

  gated <- has_state_thresholds(g)
  p_net <- p_D + p_R
  with_local_seed(seed, {
    for (sim in seq_len(n_simulations)) {
      E(g_sim)$weight <- runif(length(base_weight), low, high)
      B_sim <- effect_matrix(g_sim)
      if (spectral_radius(B_sim) >= 1 - 1e-9) next
      # Revisao 2, item C2: the gates are re-evaluated in every draw.
      net_sim <- if (gated) {
        propagate(gated_effect_matrix(g_sim, p_net, B_sim), p_net)[impact_ids]
      } else {
        propagate(B_sim, p_D)[impact_ids] + propagate(B_sim, p_R)[impact_ids]
      }
      matches[sim, ] <- as.integer(net_sim <= threshold)
    }
  })

  skipped <- sum(is.na(matches[, 1]))
  out <- data.frame(
    id = impact_ids,
    node = if (!is.null(V(g)$label)) V(g)$label[is_impact] else impact_ids,
    neutralized_pct = unname(colMeans(matches, na.rm = TRUE)[impact_ids]) * 100,
    stringsAsFactors = FALSE
  )
  attr(out, "skipped") <- skipped
  out
}

# =====================================================
# DISPLAY FORMATTING (Revisao 1, Fase 3)
# =====================================================
#
# Shared between mod_responses.R's on-screen renderers and R/report.R's
# exported HTML, so a scenario's numbers can never drift between what the
# user saw live and what ends up in the downloaded report - same reasoning
# that already keeps R/scenario_plots.R's draw_*_plot() functions shared
# across screen/download/report for the trajectory and sensitivity charts.

# `strength_to_neutralize` is a ratio (see sufficiency() above) - only
# converted to an absolute "X% would be enough" when the response scenario
# is a single response (multiplying a ratio by "the" current strength only
# makes sense when there's one number to multiply by); a combined scenario
# shows the ratio itself as a multiplier instead.
format_sufficiency_table <- function(suff_df, active_ids, strengths_pct) {
  single_response <- length(active_ids) == 1

  strength_display <- if (single_response && nrow(suff_df) > 0) {
    active_strength_pct <- strengths_pct[[active_ids]]
    ifelse(
      is.na(suff_df$strength_to_neutralize), "-",
      sprintf("%.0f%%", suff_df$strength_to_neutralize * active_strength_pct)
    )
  } else if (nrow(suff_df) > 0) {
    ifelse(is.na(suff_df$strength_to_neutralize), "-", sprintf("x%.2f", suff_df$strength_to_neutralize))
  } else {
    character()
  }

  data.frame(
    Impact = suff_df$node,
    `Worsening (pressure)` = round(suff_df$worsening, 3),
    `Mitigation (response)` = round(suff_df$mitigation, 3),
    Net = round(suff_df$net, 3),
    `Neutralizes?` = ifelse(
      suff_df$neutralized,
      ifelse(!is.null(suff_df$neutralized_by) & suff_df$neutralized_by %in% "trigger", "Yes (below threshold)", "Yes"),
      "No"
    ),
    `Strength needed` = strength_display,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}
