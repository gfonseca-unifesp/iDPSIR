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
#
# Units (Revisao 3, E1.1). Every factor is measured in its own standard
# deviations (SD): a strength of 100% is a push of 1 SD, so p = strength / 100
# (mod_responses.R, compute_scenario()); a push given in the factor's own
# units is converted with p = units / sd (effective_strength()). Worsening,
# mitigation and net are therefore in SD of each Impact, and "neutralized"
# (net <= 0) compares the two pushes' effects in the same unit.
# press_units_note() reports each push in SD and, when the factor has an sd,
# in its own units (shown in the report).
#
# Convergence and stability (E1.3). The path-sum expansion converges when
# rho(B) < 1, and (I - B) is then invertible. That implies -(I - B) - the
# Levins community matrix with self-regulation 1 on every node - is stable;
# the converse does not hold.
#
# Static and temporal readings (E1.2). The temporal simulation (R/temporal.R)
# settles, without growth or triggers, at dev* = (S - B)^-1 p with
# S = diag(self_regulation). With S = I this is (I - B)^-1 p = Phi(p) + p: the
# static reading is the temporal equilibrium with self-regulation 1 on every
# node (tested in test-equivalence.R). With other self-regulation the two
# differ; self_regulation_sensitivity() reports whether a verdict depends on
# it. The equilibrium is reached only if rho((I - S) + B) < 1; otherwise the
# simulation diverges and no equilibrium is reported.

# Kept as an alias while callers move to effect_matrix() (Fase 4 removes it).

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
  is_impact <- has_role(g, "impact")
  impact_ids <- node_names[is_impact]

  empty <- data.frame(
    id = character(), node = character(),
    worsening = numeric(), mitigation = numeric(), net = numeric(),
    neutralized = logical(), strength_to_neutralize = numeric(),
    neutralized_by = character(), affected = logical(),
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
    # Strength to neutralize by bisection on the response's scale s. Audit:
    # the upper bound doubles from 10 up to 10^4 (it was fixed at 10, so a
    # response needing more than x10 was reported as never neutralizing).
    net_at <- function(s) {
      p <- p_D + s * p_R
      propagate(gated_effect_matrix(g, p, B), p)[impact_ids]
    }
    strength_to_neutralize <- vapply(seq_along(impact_ids), function(k) {
      if (all(p_R == 0)) return(NA_real_)
      if (net_at(0)[k] <= threshold) return(0)
      hi <- 10
      while (net_at(hi)[k] > threshold && hi < 1e4) hi <- hi * 2
      if (net_at(hi)[k] > threshold) return(NA_real_)
      lo <- 0
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
    # Revisao 2, item 2.1: an Impact the pressure does not reach is "Not
    # affected", not "neutralized" - it stays out of the confidence and the
    # prioritization.
    affected = abs(unname(worsening)) > threshold,
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

# Revisao 2, item 2.4: same, for a whole function body - sets the seed and
# restores the caller's RNG state when the calling function exits.
local_seed <- function(seed, frame = parent.frame()) {
  had_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had_seed) get(".Random.seed", envir = globalenv()) else NULL
  restore <- function() {
    if (had_seed) assign(".Random.seed", old, envir = globalenv())
    else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
  }
  do.call(on.exit, list(substitute(f(), list(f = restore)), add = TRUE), envir = frame)
  set.seed(seed)
  invisible(NULL)
}

# Revisao 2, item 1.4 (D15/D21): each edge's beta is resampled uniformly
# within its uncertainty band [weight_low, weight_high]; `net` is recomputed
# and the result is the % of simulations in which the Impact is still
# neutralized. Draws that would make the loops amplify (rho(B) >= 1) are
# skipped and counted in the `skipped` attribute.
# Revisao 3, E3.1: `structural = TRUE` also drops each link from a draw with
# the probability edge_absence_probability() gives it (weaker evidence,
# more often absent). The strength draws are made first, for every
# simulation, so structural = FALSE reproduces the earlier numbers exactly
# and structural = TRUE only adds the absences on top of the same draws.
sufficiency_confidence <- function(g, p_D, p_R, n_simulations = 300, seed = 42, threshold = 1e-9,
                                   structural = FALSE, absence = NULL) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(n_simulations >= 1)

  node_names <- V(g)$name
  p_D <- align_press_vector(p_D, node_names, "pressure scenario")
  p_R <- align_press_vector(p_R, node_names, "response scenario")
  is_impact <- has_role(g, "impact")
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
  # Revisao 2, item 2.1: Impacts the pressure does not reach (with the base
  # strengths) get no percentage.
  B0 <- effect_matrix(g)
  worsening0 <- if (gated) propagate(gated_effect_matrix(g, p_D, B0), p_D)[impact_ids] else propagate(B0, p_D)[impact_ids]
  affected <- abs(worsening0) > threshold
  draws <- resample_edge_weights(g, base_weight, low, high, n_simulations, seed, structural, absence)
  attr_structural <- structural
  with_local_seed(seed, {
    for (sim in seq_len(n_simulations)) {
      E(g_sim)$weight <- draws[sim, ]
      B_sim <- effect_matrix(g_sim)
      if (spectral_radius(B_sim) >= 1 - 1e-9) next
      # Revisao 2, item C2: the gates are re-evaluated in every draw.
      net_sim <- if (gated) {
        # Closing a trigger can raise rho in a signed matrix (see
        # prediction_reliability()); such a draw is skipped.
        tryCatch(propagate(gated_effect_matrix(g_sim, p_net, B_sim), p_net)[impact_ids], error = function(e) NULL)
      } else {
        propagate(B_sim, p_D)[impact_ids] + propagate(B_sim, p_R)[impact_ids]
      }
      if (is.null(net_sim)) next
      matches[sim, ] <- as.integer(net_sim <= threshold)
    }
  })

  skipped <- sum(is.na(matches[, 1]))
  out <- data.frame(
    id = impact_ids,
    node = if (!is.null(V(g)$label)) V(g)$label[is_impact] else impact_ids,
    neutralized_pct = ifelse(affected, unname(colMeans(matches, na.rm = TRUE)[impact_ids]) * 100, NA_real_),
    affected = unname(affected),
    stringsAsFactors = FALSE
  )
  attr(out, "skipped") <- skipped
  attr(out, "structural") <- attr_structural
  out
}

# The n x m matrix of resampled strengths used by the confidence readings:
# row = simulation. Uniform within each band, drawn exactly as before
# (simulation by simulation, one value per edge); with `structural`, a
# second matrix of uniforms, drawn after all the strengths, sets absent links
# to 0.
resample_edge_weights <- function(g, w, low, high, n, seed, structural = FALSE, absence = NULL) {
  m <- length(w)
  with_local_seed(seed, {
    draws <- matrix(stats::runif(n * m, low, high), nrow = n, ncol = m, byrow = TRUE)
    if (isTRUE(structural) && m > 0) {
      p_abs <- if (is.null(absence)) edge_absence_probability(g) else absence
      gone <- matrix(stats::runif(n * m), nrow = n, ncol = m, byrow = TRUE) < matrix(p_abs, n, m, byrow = TRUE)
      draws[gone] <- 0
    }
    draws
  })
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
format_sufficiency_table <- function(suff_df, active_ids, strengths_pct, sr_sensitivity = NULL) {
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
      !is.null(suff_df$affected) & suff_df$affected %in% FALSE,
      # Revisao 2, item 2.1.
      ifelse(suff_df$neutralized, "Not affected", "No (worsened by the response)"),
      ifelse(
        suff_df$neutralized,
        ifelse(!is.null(suff_df$neutralized_by) & suff_df$neutralized_by %in% "trigger", "Yes (below threshold)", "Yes"),
        "No"
      )
    ),
    `Strength needed` = strength_display,
    check.names = FALSE,
    stringsAsFactors = FALSE
  ) -> out
  # Revisao 3, E1.4: does the verdict hold for self-regulation 0.25-1?
  if (!is.null(sr_sensitivity) && nrow(sr_sensitivity) > 0) {
    txt <- format_sr_sensitivity(sr_sensitivity)
    rng <- range(attr(sr_sensitivity, "s_grid"))
    out[[sprintf("Holds for self-regulation %s-%s", rng[1], rng[2])]] <- txt[match(suff_df$id, sr_sensitivity$id)]
  }
  out
}

# Revisao 2, items 2.1/2.2: the confidence matrix for display - percentages
# rounded, "-" where the pressure does not reach the Impact.
format_confidence_matrix <- function(df) {
  cols <- setdiff(names(df), "Response")
  for (col in cols) {
    v <- suppressWarnings(as.numeric(df[[col]]))
    # Audit: NaN = every resampled draw made the loops amplify, so there is
    # no percentage - not the same as an Impact the pressure does not reach.
    df[[col]] <- ifelse(is.nan(v), "not computable", ifelse(is.na(v), "\u2014", sprintf("%.0f", v)))
  }
  df
}

# Audit: a plain-language note when resampled draws had to be skipped
# (rho(B) >= 1: the loops would amplify), NULL when none were.
skipped_draws_note <- function(skipped, n_simulations) {
  if (is.null(skipped) || is.na(skipped) || skipped == 0) return(NULL)
  if (skipped >= n_simulations) {
    return(sprintf("All %d resampled draws made the feedback loops amplify (effect matrix spectral radius >= 1), so the percentages cannot be computed - narrow the uncertainty ranges of the edges in the loops.", n_simulations))
  }
  sprintf("%d of %d resampled draws were skipped because the feedback loops would amplify (spectral radius >= 1); the percentages use the remaining %d.",
          skipped, n_simulations, n_simulations - skipped)
}

# =====================================================
# Revisao 3, E1.1 - each push in SD and in its own units
# =====================================================
# One row per pushed factor: the push in standard deviations (what the
# engine uses) and, when the factor has a typical variation (sd), in its own
# units (push x sd).
press_units_note <- function(g, p) {
  ids <- igraph::V(g)$name
  p <- align_press_vector(p, ids, "push")
  on <- which(p != 0)
  if (length(on) == 0) {
    return(data.frame(id = character(), factor = character(), push_sd = numeric(), push_units = numeric(),
                      stringsAsFactors = FALSE))
  }
  lab <- igraph::V(g)$label
  if (is.null(lab)) lab <- ids
  sd <- suppressWarnings(as.numeric(igraph::vertex_attr(g, "sd")))
  if (length(sd) == 0) sd <- rep(NA_real_, length(ids))
  data.frame(id = ids[on], factor = lab[on], push_sd = unname(p[on]),
             push_units = ifelse(is.na(sd[on]), NA_real_, unname(p[on]) * sd[on]),
             stringsAsFactors = FALSE)
}

# Plain text for the report: "Coastal population: 1 SD (= 2.5 million)".
format_press_units_note <- function(g, p) {
  d <- press_units_note(g, p)
  if (nrow(d) == 0) return("none")
  num <- function(x) trimws(format(signif(x, 4), big.mark = ",", scientific = FALSE, drop0trailing = TRUE))
  paste(sprintf("%s: %s SD%s", d$factor, vapply(d$push_sd, num, ""),
                ifelse(is.na(d$push_units), "", sprintf(" (= %s in its own units)", vapply(d$push_units, function(u) if (is.na(u)) "" else num(u), "")))),
        collapse = "; ")
}

# =====================================================
# Revisao 3, E1.2/E1.4 - equilibrium with self-regulation S
# =====================================================
# The temporal update without growth or triggers,
#   dev(t+1) = (I - S) dev(t) + B dev(t) + p,
# settles at dev* = (S - B)^-1 p when rho((I - S) + B) < 1; otherwise it
# diverges and there is no equilibrium (converges = FALSE). `s`: one value
# for every node (a uniform S), or NULL for each node's own self-regulation.
temporal_equilibrium <- function(g, p, s = NULL, B = effect_matrix(g)) {
  ids <- rownames(B)
  n <- length(ids)
  p <- align_press_vector(p, ids, "push")
  sr <- if (is.null(s)) -self_regulation_diagonal(g)[ids] else rep(s, n)
  S <- diag(as.numeric(sr), n)
  rho <- spectral_radius(diag(n) - S + B)
  if (rho >= 1 - 1e-9) {
    return(list(converges = FALSE, rho = rho, equilibrium = setNames(rep(NA_real_, n), ids)))
  }
  list(converges = TRUE, rho = rho, equilibrium = setNames(as.numeric(solve(S - B, p)), ids))
}

# Verdict of each Impact at equilibrium for a grid of uniform
# self-regulation values and for the self-regulation set on the nodes. The
# static reading is the s = 1 column (Phi(p) + p, and Impacts are never
# pushed). State triggers are kept open or closed as in the static reading
# (gated_effect_matrix() of each push), so the s = 1 column always matches
# sufficiency(); only the self-regulation varies.
#   verdict: "Neutralized", "Not neutralized", "Not affected", or
#   "Diverges" (no equilibrium for that s).
self_regulation_sensitivity <- function(g, p_D, p_R, s_grid = c(0.25, 0.5, 0.75, 1), threshold = 1e-9) {
  ids <- igraph::V(g)$name
  p_D <- align_press_vector(p_D, ids, "pressure scenario")
  p_R <- align_press_vector(p_R, ids, "response scenario")
  impact_ids <- ids[has_role(g, "impact")]
  lab <- igraph::V(g)$label[match(impact_ids, ids)]
  if (length(impact_ids) == 0) return(data.frame())
  B <- effect_matrix(g)
  gated <- has_state_thresholds(g)
  B_D <- if (gated) gated_effect_matrix(g, p_D, B) else B
  B_N <- if (gated) gated_effect_matrix(g, p_D + p_R, B) else B
  verdict_for <- function(s) {
    eD <- temporal_equilibrium(g, p_D, s, B_D)
    if (!eD$converges) return(rep("Diverges", length(impact_ids)))
    eN <- temporal_equilibrium(g, p_D + p_R, s, B_N)
    if (!eN$converges) return(rep("Diverges", length(impact_ids)))
    w <- eD$equilibrium[impact_ids]
    n <- eN$equilibrium[impact_ids]
    ifelse(w <= threshold, "Not affected", ifelse(n <= threshold, "Neutralized", "Not neutralized"))
  }
  out <- data.frame(id = impact_ids, node = lab, stringsAsFactors = FALSE)
  for (s in s_grid) out[[paste0("s=", s)]] <- verdict_for(s)
  out$configured <- verdict_for(NULL)
  cols <- c(paste0("s=", s_grid), "configured")
  out$depends_on_s <- apply(out[, cols, drop = FALSE], 1, function(v) length(unique(v[v != "Diverges"])) > 1)
  out$diverges <- apply(out[, cols, drop = FALSE], 1, function(v) any(v == "Diverges"))
  attr(out, "s_grid") <- s_grid
  attr(out, "note") <- if (gated) "State triggers are kept as in the reading above." else NULL
  out
}

# One word per Impact for the sufficiency table: does the verdict hold for
# every self-regulation in the grid?
format_sr_sensitivity <- function(sens) {
  if (is.null(sens) || nrow(sens) == 0) return(character())
  g <- attr(sens, "s_grid")
  cols <- paste0("s=", g)
  vapply(seq_len(nrow(sens)), function(i) {
    v <- unlist(sens[i, cols])
    ok <- v[v != "Diverges"]
    if (length(ok) == 0) return("diverges")
    if (length(unique(ok)) == 1) return(if (any(v == "Diverges")) "yes (some s diverge)" else "yes")
    groups <- split(g, factor(v, levels = unique(v)))
    paste0("no: ", paste(sprintf("%s at s = %s", tolower(names(groups)), vapply(groups, paste, "", collapse = ", ")), collapse = "; "))
  }, character(1))
}
