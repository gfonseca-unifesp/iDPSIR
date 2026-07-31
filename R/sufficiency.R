# =====================================================
# RESPONSE SUFFICIENCY - "TWO PUSHES" MODEL (Revisao 1)
# =====================================================
#
# Replaces -A^-1*press (R/loop_analysis.R's press_perturbation(), the
# primary Scenarios output through Fase 5-9) as the main reading of a
# scenario's effect. That equilibrium reading requires the network to be
# "stable" in the eigenvalue sense - something no network this app can
# build ever is by default (the schema forbids a node acting on itself, so
# the interaction matrix's diagonal, and therefore its trace/eigenvalue
# sum, is always zero) - and, worse, in a genuinely unstable network it can
# silently INVERT the sign of a prediction. Confirmed on a real network,
# not hypothetically: running the Mangi et al. 2007 network
# (manuscrito/mangi2007_*.csv) through the equilibrium engine shows Gear
# restrictions (R2) producing +0.81 ("worsening") on Reef ecosystem
# degradation, when gear restrictions should intuitively reduce reef
# pressure - see manuscrito/idpsir_report_2026-07-28_GF.html.
#
# DPSIR is a static, structural model - what matters is whether a planned
# response's effect covers a pressure's effect, not the transient path a
# dynamical system would take to get there (that framing fits a
# predator-prey system, not a management scenario). This file replaces the
# dynamic-equilibrium reading with a static one: a *discounted, dominated-
# by-short-paths* propagated effect that is provably well-defined for any
# signed weighted network, regardless of stability.
#
# Phi(p) = (I - lambda*W)^-1 * p - p = lambda*W*p + lambda^2*W^2*p + ...
#
# W is the signed interaction matrix WITHOUT a self-regulation diagonal
# (build_signed_matrix() below) - unlike build_interaction_matrix() in
# R/loop_analysis.R, there is no per-node self-regulation term here at all;
# instead, lambda = c/rho(W) (c in (0,1), default 0.5) is a single global
# "reach" factor. Since lambda*rho(W) = c < 1 by construction, (I -
# lambda*W) is *never* singular, for any W - this is what eliminates both
# the stability requirement and the sign-inversion failure mode. The
# Neumann-series form above also makes explicit that the effect is
# dominated by short causal paths (lambda^k shrinks geometrically), whose
# sign is always the intuitive one - long, indirect loops can't flip it.
#
# Two independent perturbation vectors (both user-controlled, built with
# build_press_vector() from R/loop_analysis.R, unchanged): p_D (a "pressure
# scenario" - Drivers/Pressures pushed) and p_R (a "response scenario" -
# Responses activated at a strength). Because propagate() is linear in p,
# Phi(p_D + p_R) = Phi(p_D) + Phi(p_R) - the two are always computed
# separately and summed, never re-run combined.
#
# Special case, found building the Gnanapragasam et al. 2026 example
# network (Fase 9): a purely ACYCLIC causal network (no loop anywhere - a
# real, valid DPSIR network, not a degenerate one) has rho(W) = 0 too,
# since a DAG's matrix is nilpotent (every eigenvalue exactly 0) - same
# value spectral_radius() returns for a truly edge-less W. propagate()
# tells the two apart explicitly (see its own comments) rather than
# treating "no cycle" the same as "no edges at all".

# Signed interaction matrix with NO diagonal term - deliberately reuses
# build_interaction_matrix() (R/loop_analysis.R) for the sign/weight
# extraction logic, then zeroes the diagonal explicitly. This is also what
# makes an old self_regulation value on a loaded savepoint harmlessly
# inert without any special-case "ignore it" code: even if
# V(g)$self_regulation still exists and build_interaction_matrix() fills a
# non-zero diagonal from it, this function discards that diagonal anyway.
build_signed_matrix <- function(g) {
  A <- build_interaction_matrix(g)
  diag(A) <- 0
  A
}

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

# c in (0,1) is the "reach" the UI exposes (plain-language slider, no
# mention of lambda/spectral radius on screen) - lambda is derived from it
# fresh each call, never a user-facing number itself.
propagate <- function(W, p, c = 0.5) {
  stopifnot(is.matrix(W), nrow(W) == ncol(W))
  stopifnot(c > 0, c < 1)

  n <- nrow(W)

  if (all(W == 0)) {
    # Truly no edges - nothing to propagate through, so the effect beyond
    # the direct push itself is exactly zero everywhere.
    return(setNames(rep(0, n), rownames(W)))
  }

  rho <- spectral_radius(W)

  # Real bug, found building the Gnanapragasam et al. 2026 example network
  # (Revisao 1, Fase 9): a purely acyclic causal network (a DAG - e.g. one
  # where a Response's edges never loop back through an Impact) has a
  # NILPOTENT W - every eigenvalue is exactly 0, same as spectral_radius()
  # returns for a truly edge-less matrix, but the two cases are NOT the
  # same. The old code treated both as "nothing to propagate through" and
  # returned all-zero here - silently discarding a real, well-defined
  # effect for every acyclic network (confirmed against a hand-built 3-node
  # A->B->C chain: propagate() returned all-zero when it should have shown
  # a nonzero effect at B and C). A nilpotent W has NO eigenvalue to divide
  # by (so `c / rho` is undefined), but (I - lambda*W) is invertible for
  # ANY lambda in this case (its eigenvalues are all exactly 1 regardless
  # of lambda) - so `c` is used directly as lambda instead. The Neumann
  # series lambda*W*p + lambda^2*W^2*p + ... still terminates after
  # finitely many terms (the DAG's longest path length) and is generally
  # non-zero: an effect propagates through a DAG exactly like it does
  # through a network with cycles, it just can't loop back and compound.
  lambda <- if (rho == 0) c else c / rho
  M <- diag(n) - lambda * W
  solved <- tryCatch(solve(M, p), error = function(e) NULL)

  if (is.null(solved)) {
    # Should not happen - (I - lambda*W) is invertible either way: when
    # rho > 0, lambda*rho(W) = c < 1 guarantees it directly; when rho == 0
    # (a DAG), its eigenvalues are all exactly 1 regardless of lambda.
    # Kept as a defensive fallback, not an expected code path, matching
    # press_perturbation()'s own singular-matrix handling in R/loop_analysis.R.
    warning("Propagation matrix is unexpectedly singular even at c < 1.", call. = FALSE)
    return(setNames(rep(NA_real_, n), rownames(W)))
  }

  setNames(as.numeric(solved) - p, rownames(W))
}

# One row per Impact node. `strength_to_neutralize` is a dimensionless
# RATIO on whatever p_R currently represents (propagate() is linear in p,
# so this is exact, not an approximation): >1 means the planned response
# needs to be stronger to fully neutralize the worsening, <1 means it's
# already more than enough. For a scenario built from a single active
# response at a given strength, the caller multiplies this ratio by that
# strength to show an absolute "how strong would it need to be" number -
# sufficiency() itself stays agnostic to what p_R is made of (one response
# or several combined), since only the ratio composes cleanly in that case.
sufficiency <- function(g, p_D, p_R, c = 0.5, threshold = 1e-9) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  categories <- V(g)$dpsir_category
  is_impact <- !is.null(categories) & categories == "Impact"
  impact_ids <- node_names[is_impact]

  empty <- data.frame(
    id = character(), node = character(),
    worsening = numeric(), mitigation = numeric(), net = numeric(),
    neutralized = logical(), strength_to_neutralize = numeric(),
    stringsAsFactors = FALSE
  )
  if (length(impact_ids) == 0) {
    return(empty)
  }

  W <- build_signed_matrix(g)
  worsening <- propagate(W, p_D, c)[impact_ids]
  mitigation <- propagate(W, p_R, c)[impact_ids]
  net <- worsening + mitigation

  strength_to_neutralize <- ifelse(
    mitigation < 0,
    worsening / (-mitigation),
    NA_real_ # response doesn't help this Impact at all - no finite strength neutralizes it
  )

  data.frame(
    id = impact_ids,
    node = if (!is.null(V(g)$label)) V(g)$label[is_impact] else impact_ids,
    worsening = unname(worsening),
    mitigation = unname(mitigation),
    net = unname(net),
    neutralized = unname(net) <= threshold,
    strength_to_neutralize = unname(strength_to_neutralize),
    stringsAsFactors = FALSE
  )
}

# Same resampling philosophy as robustness_check() (R/loop_analysis.R,
# Marco D of Fase 5): each edge's weight is resampled within a range set by
# its confidence, `net` is recomputed under the resampled network, and the
# result reports the % of simulations in which the Impact was still
# neutralized. This is what makes the edges' `confidence` field decide
# something concrete: whether a "yes, this response covers it" verdict
# actually holds up once you account for how uncertain the underlying
# links are.
sufficiency_confidence <- function(g, p_D, p_R, c = 0.5, n_simulations = 300, spread = 0.5, seed = 42, threshold = 1e-9) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(n_simulations >= 1)

  node_names <- V(g)$name
  categories <- V(g)$dpsir_category
  is_impact <- !is.null(categories) & categories == "Impact"
  impact_ids <- node_names[is_impact]

  if (length(impact_ids) == 0) {
    return(data.frame(id = character(), node = character(), neutralized_pct = numeric(), stringsAsFactors = FALSE))
  }

  confidence <- E(g)$confidence
  confidence[is.na(confidence)] <- 0.5
  base_weight <- E(g)$weight
  variation <- (1 - confidence) * spread

  matches <- matrix(0L, nrow = n_simulations, ncol = length(impact_ids), dimnames = list(NULL, impact_ids))
  g_sim <- g

  set.seed(seed)
  for (sim in seq_len(n_simulations)) {
    multiplier <- runif(length(base_weight), 1 - variation, 1 + variation)
    E(g_sim)$weight <- base_weight * multiplier

    W_sim <- build_signed_matrix(g_sim)
    worsening_sim <- propagate(W_sim, p_D, c)[impact_ids]
    mitigation_sim <- propagate(W_sim, p_R, c)[impact_ids]
    net_sim <- worsening_sim + mitigation_sim

    matches[sim, ] <- as.integer(net_sim <= threshold)
  }

  data.frame(
    id = impact_ids,
    node = if (!is.null(V(g)$label)) V(g)$label[is_impact] else impact_ids,
    neutralized_pct = unname(colMeans(matches)[impact_ids]) * 100,
    stringsAsFactors = FALSE
  )
}

# Recomputes the neutralization verdict (net <= threshold) across a grid of
# reach values `cs` and flags any Impact whose verdict flips somewhere in
# that grid - a boundary case, worth surfacing rather than hiding behind
# whichever single `c` the scenario happened to use.
sufficiency_reach_over_c <- function(g, p_D, p_R, cs = c(0.2, 0.35, 0.5, 0.65, 0.8), threshold = 1e-9) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  categories <- V(g)$dpsir_category
  is_impact <- !is.null(categories) & categories == "Impact"
  impact_ids <- node_names[is_impact]

  if (length(impact_ids) == 0) {
    return(data.frame(id = character(), node = character(), flips = logical(), stringsAsFactors = FALSE))
  }

  W <- build_signed_matrix(g)

  verdicts <- vapply(cs, function(c_val) {
    worsening <- propagate(W, p_D, c_val)[impact_ids]
    mitigation <- propagate(W, p_R, c_val)[impact_ids]
    (worsening + mitigation) <= threshold
  }, logical(length(impact_ids)))

  if (length(impact_ids) == 1) {
    verdicts <- matrix(verdicts, nrow = 1, dimnames = list(impact_ids, NULL))
  }
  colnames(verdicts) <- paste0("c_", cs)

  df <- data.frame(
    id = impact_ids,
    node = if (!is.null(V(g)$label)) V(g)$label[is_impact] else impact_ids,
    stringsAsFactors = FALSE
  )
  df <- cbind(df, as.data.frame(verdicts))
  df$flips <- apply(verdicts, 1, function(row) length(unique(row)) > 1)
  df
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
    `Neutralizes?` = ifelse(suff_df$neutralized, "Yes", "No"),
    `Strength needed` = strength_display,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

format_reach_over_c_table <- function(reach_df) {
  c_cols <- grep("^c_", names(reach_df), value = TRUE)

  display <- reach_df[, c("node", c_cols, "flips"), drop = FALSE]
  for (col in c_cols) {
    display[[col]] <- ifelse(display[[col]], "Yes", "No")
  }
  display$flips <- ifelse(display$flips, "Borderline", "")
  # DT's server-side processing errors on an empty-string column name
  # (confirmed live - "argumento tem comprimento zero" - see mod_responses.R
  # Fase 2 notes in CLAUDE.md), so this stays a real header, not "".
  names(display) <- c("Impact", gsub("^c_", "c=", c_cols), "Verdict")
  display
}
