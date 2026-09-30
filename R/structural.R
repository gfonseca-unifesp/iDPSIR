# =====================================================
# MODO ESTRUTURAL (Revisao 2, Fase 1 - decisoes D17-D21)
# =====================================================
#
# Each edge is a standardized path coefficient beta: how many standard
# deviations the target moves when the source moves one. The sign comes from
# `interaction_type`; `weight` holds |beta|. The second field is an
# uncertainty band [weight_low, weight_high], used only to resample beta in
# the confidence readings (D15/D21) - never to shrink the effect itself.
#
# The static effect of a push p is the path-analysis total effect
#   Phi(p) = (I - B)^-1 p - p
# (products of beta along each path, summed over paths), with no global
# discount c: a distant response is attenuated by the product of beta < 1
# along its path. It is well defined whenever rho(B) < 1, which is checked
# when the graph is built. See ROADMAP_REVISAO2_iDPSIR.md, Fase 1 and Anexo X2.

# Qualitative classes for users without data (D18). `low`/`high` are the
# default uncertainty band of an edge in that class.
strength_classes <- function() {
  data.frame(
    class = c("weak", "moderate", "strong"),
    label = c("Weak", "Moderate", "Strong"),
    value = c(0.15, 0.45, 0.80),
    low = c(0, 0.30, 0.60),
    high = c(0.30, 0.60, 1.00),
    stringsAsFactors = FALSE
  )
}

DEFAULT_STRENGTH_CLASS <- "moderate"

# Class a given |beta| falls in (weak < 0.3 <= moderate < 0.6 <= strong).
classify_beta <- function(beta) {
  b <- abs(as.numeric(beta))
  ifelse(is.na(b), NA_character_, ifelse(b < 0.3, "weak", ifelse(b < 0.6, "moderate", "strong")))
}

# Form shortcuts (1.2) - converted into beta and band, never stored.
beta_from_r2 <- function(r2) sqrt(as.numeric(r2))

band_from_r2_n <- function(r2, n) {
  r2 <- as.numeric(r2); n <- as.numeric(n)
  beta <- sqrt(r2)
  se <- sqrt((1 - r2) / (n - 2))
  c(low = max(0, beta - 1.96 * se), high = beta + 1.96 * se)
}

# Fills weight / weight_low / weight_high / strength_class / weight_source for
# every edge, following the substitute-group priorities of Anexo X6:
#   value:  weight given > class > default (moderate)
#   band:   weight_low/high given > legacy confidence > band of the class
#           (of the given class, or of the class |beta| falls in)
# Also derives `confidence` (used only by the graph's dashed-edge display) as
# 1 - min(1, band width / beta) - the exact inverse of the legacy
# confidence -> band rule, so a converted edge keeps its old confidence.
normalize_edge_strength <- function(edges) {
  n <- nrow(edges)
  if (n == 0) {
    for (col in c("weight_low", "weight_high")) edges[[col]] <- numeric()
    edges$strength_class <- character()
    edges$weight_source <- character()
    edges$confidence <- numeric()
    return(edges)
  }

  classes <- strength_classes()
  rownames(classes) <- classes$class

  cls <- if ("strength_class" %in% names(edges)) tolower(trimws(as.character(edges$strength_class))) else rep(NA_character_, n)
  cls[!is.na(cls) & cls == ""] <- NA_character_

  weight <- if ("weight" %in% names(edges)) suppressWarnings(as.numeric(edges$weight)) else rep(NA_real_, n)
  source <- if ("weight_source" %in% names(edges)) as.character(edges$weight_source) else rep(NA_character_, n)

  given <- !is.na(weight)
  from_class <- !given & !is.na(cls)
  by_default <- !given & is.na(cls)

  weight[from_class] <- classes[cls[from_class], "value"]
  weight[by_default] <- classes[DEFAULT_STRENGTH_CLASS, "value"]

  source[is.na(source) & given] <- "given"
  source[is.na(source) & from_class] <- "class"
  source[is.na(source) & by_default] <- "default"
  cls[is.na(cls)] <- classify_beta(weight[is.na(cls)])

  low <- if ("weight_low" %in% names(edges)) suppressWarnings(as.numeric(edges$weight_low)) else rep(NA_real_, n)
  high <- if ("weight_high" %in% names(edges)) suppressWarnings(as.numeric(edges$weight_high)) else rep(NA_real_, n)

  legacy_conf <- if ("confidence" %in% names(edges) && !"weight_low" %in% names(edges)) {
    suppressWarnings(as.numeric(edges$confidence))
  } else {
    rep(NA_real_, n)
  }
  use_conf <- is.na(low) & is.na(high) & !is.na(legacy_conf)
  half <- 0.5 * (1 - legacy_conf[use_conf])
  low[use_conf] <- weight[use_conf] * (1 - half)
  high[use_conf] <- weight[use_conf] * (1 + half)

  need_band <- is.na(low) | is.na(high)
  low[need_band & is.na(low)] <- classes[cls[need_band & is.na(low)], "low"]
  high[need_band & is.na(high)] <- classes[cls[need_band & is.na(high)], "high"]
  # A class band always contains the edge's own value.
  low <- pmin(low, weight)
  high <- pmax(high, weight)

  edges$weight <- weight
  edges$weight_low <- low
  edges$weight_high <- high
  edges$strength_class <- cls
  edges$weight_source <- source
  edges$confidence <- round(1 - pmin(1, (high - low) / weight), 4)
  edges
}

# B[to, from] = sign * |beta|, zero diagonal (self-regulation lives only in
# the temporal engine, D20). Replaces build_signed_matrix().
effect_matrix <- function(g) {
  A <- build_interaction_matrix(g)
  diag(A) <- 0
  A
}

# Edges that sit on a feedback cycle (inside a strongly connected component
# with more than one node) - named in the rho(B) >= 1 message so the user
# knows which betas to lower.
feedback_cycle_edges <- function(g) {
  comp <- igraph::components(g, mode = "strong")
  big <- which(comp$csize > 1)
  if (length(big) == 0) return(character())
  ends_mat <- igraph::ends(g, igraph::E(g), names = TRUE)
  memb <- comp$membership[ends_mat[, 1]]
  on_cycle <- memb %in% big & memb == comp$membership[ends_mat[, 2]]
  sprintf("%s -> %s", ends_mat[on_cycle, 1], ends_mat[on_cycle, 2])
}

# Blocking check (1.3): the total effect exists only when rho(B) < 1.
check_effect_matrix <- function(g) {
  B <- effect_matrix(g)
  rho <- spectral_radius(B)
  if (rho >= 1 - 1e-9) {
    stop(sprintf(paste(
      "The network's feedback loops amplify without bound (spectral radius %.2f, it must be below 1).",
      "Lower the strength of the edges on the loop - for example set them to 'Weak': %s."
    ), rho, paste(feedback_cycle_edges(g), collapse = ", ")), call. = FALSE)
  }
  invisible(rho)
}

# Warning (1.1): sum of beta^2 arriving at a node above 1 means the network
# would explain more than 100% of that factor's variation.
# Revisao 2, Fase D: edges leaving a Response are left out - a response is a
# policy lever set by the scenario, not part of the factor's observed
# variation (e.g. a quota that cuts effort one-to-one).
explained_variance_warnings <- function(nodes, edges) {
  if (nrow(edges) == 0) return(character())
  from_cat <- nodes$dpsir_category[match(edges$from, nodes$id)]
  edges <- edges[!roles_of(from_cat) %in% "feedback", , drop = FALSE]
  if (nrow(edges) == 0) return(character())
  s <- tapply(as.numeric(edges$weight)^2, edges$to, sum)
  over <- s[s > 1 + 1e-9]
  if (length(over) == 0) return(character())
  labels <- nodes$label[match(names(over), nodes$id)]
  sprintf(
    "The edges arriving at '%s' would explain %.0f%% of its variation (sum of squared strengths = %.2f). Review their strengths.",
    labels, 100 * over, over
  )
}

# 1.5: an older file (relative weights + global reach c) is converted to
# beta = lambda * w, with the lambda the old static reading used (c / rho(W)
# with cycles, c without). This reproduces the old static numbers exactly,
# because the old reading was already (I - lambda W)^-1 p - p. The old
# confidence becomes the uncertainty band (D21).
convert_legacy_weights <- function(nodes, edges, c = 0.5) {
  if (is.null(edges) || nrow(edges) == 0) {
    return(list(edges = edges, lambda = NA_real_, c = c, review = character()))
  }
  if (is.null(c) || is.na(c)) c <- 0.5

  w <- suppressWarnings(as.numeric(edges$weight))
  w[is.na(w)] <- 1
  sign <- ifelse(trimws(as.character(edges$interaction_type)) == "negative", -1, 1)

  ids <- unique(c(as.character(nodes$id), as.character(edges$from), as.character(edges$to)))
  W <- matrix(0, length(ids), length(ids), dimnames = list(ids, ids))
  for (k in seq_along(w)) {
    W[edges$to[k], edges$from[k]] <- W[edges$to[k], edges$from[k]] + sign[k] * w[k]
  }
  diag(W) <- 0
  rho <- if (all(W == 0)) 0 else spectral_radius(W)
  lambda <- if (rho == 0) c else c / rho

  conf <- if ("confidence" %in% names(edges)) suppressWarnings(as.numeric(edges$confidence)) else rep(1, length(w))
  conf[is.na(conf)] <- 1

  beta <- lambda * w
  half <- 0.5 * (1 - conf)
  edges$weight <- beta
  edges$weight_low <- beta * (1 - half)
  edges$weight_high <- beta * (1 + half)
  edges$strength_class <- classify_beta(beta)
  edges$weight_source <- "converted"
  edges$confidence <- NULL

  review <- sprintf("%s -> %s", edges$from, edges$to)[beta > 1]
  list(edges = edges, lambda = lambda, c = c, review = review)
}

# Revisao 2, item A8: self-regulation notes for the Review step.
self_regulation_warnings <- function(nodes) {
  if (nrow(nodes) == 0) return(character())
  sr <- as.numeric(nodes$self_regulation)
  out <- character()
  if (all(!is.na(sr) & sr == 0)) {
    out <- c(out, "Nothing in this network recovers on its own (self-regulation 0 everywhere): in the temporal simulation every effect accumulates window after window.")
  }
  th <- if ("threshold_level" %in% names(nodes)) suppressWarnings(as.numeric(nodes$threshold_level)) else rep(NA_real_, nrow(nodes))
  stuck <- !is.na(th) & !is.na(sr) & sr == 0 & roles_of(nodes$dpsir_category) %in% "state"
  if (any(stuck)) {
    out <- c(out, sprintf(
      "'%s' has an activation threshold and self-regulation 0: its accumulated deviation never fades on its own, so once its trigger opens it only closes if a response pushes it back.",
      nodes$label[stuck]
    ))
  }
  out
}

# Revisao 2, Fase D: growth notes for the Review step.
growth_warnings <- function(nodes) {
  if (nrow(nodes) == 0 || !"growth_rate" %in% names(nodes)) return(character())
  gr <- suppressWarnings(as.numeric(nodes$growth_rate)); gr[is.na(gr)] <- 0
  ref <- if ("reference_value" %in% names(nodes)) suppressWarnings(as.numeric(nodes$reference_value)) else rep(NA_real_, nrow(nodes))
  sd <- if ("sd" %in% names(nodes)) suppressWarnings(as.numeric(nodes$sd)) else rep(NA_real_, nrow(nodes))
  cap <- if ("growth_cap" %in% names(nodes)) suppressWarnings(as.numeric(nodes$growth_cap)) else rep(NA_real_, nrow(nodes))
  out <- character()
  frac <- gr != 0 & (is.na(sd))
  if (any(frac)) {
    out <- c(out, sprintf(
      "'%s' grows %+.1f%% per window but has no typical variation (SD): its trend is measured as a fraction of its initial level (1 = the whole base level), so compare it with pushes in the same terms.",
      nodes$label[frac], 100 * gr[frac]
    ))
  }
  # Audit: growth with an SD but no initial level is measured against a
  # base level of 1 in SD units - say so.
  sd_noref <- gr != 0 & !is.na(sd) & is.na(ref)
  if (any(sd_noref)) {
    out <- c(out, sprintf("'%s' grows %+.1f%% per window and has an SD but no initial level: the growth is applied to a base level of 1 (in the factor's own units). Enter the initial level to grow from it.",
                          nodes$label[sd_noref], 100 * gr[sd_noref]))
  }
  nocap_ref <- !is.na(cap) & is.na(ref)
  if (any(nocap_ref)) {
    out <- c(out, sprintf("'%s' has a growth ceiling but no initial level: the ceiling is read against a base level of 1.", nodes$label[nocap_ref]))
  }
  reached <- !is.na(cap) & !is.na(ref) & gr > 0 & cap <= ref
  if (any(reached)) {
    out <- c(out, sprintf("'%s' already starts at or above its growth ceiling, so its trend stays at zero.", nodes$label[reached]))
  }
  # Audit: a decline with a floor at or above the initial level never moves.
  floor_reached <- !is.na(cap) & !is.na(ref) & gr < 0 & cap >= ref
  if (any(floor_reached)) {
    out <- c(out, sprintf("'%s' declines but already starts at or below its floor, so its trend stays at zero.", nodes$label[floor_reached]))
  }
  out
}

# Revisao 2, item C5: threshold notes for the Review step.
threshold_warnings <- function(g) {
  th <- state_thresholds(g)
  if (nrow(th) == 0) return(character())
  out <- character()
  labels <- V(g)$label[match(th$id, V(g)$name)]
  no_sd <- is.na(th$sd)
  if (any(no_sd)) {
    out <- c(out, sprintf(
      "'%s' has a threshold but no typical variation (SD): it is measured in the model's own units, not in the factor's.",
      labels[no_sd]
    ))
  }
  # Largest static deviation reachable with every Driver/Pressure at 100%.
  role <- node_roles(g)
  p_all <- setNames(as.numeric(role %in% c("driver", "pressure")), V(g)$name)
  B <- effect_matrix(g)
  dev <- tryCatch(static_state_deviation(g, B, p_all, th$id), error = function(e) rep(NA_real_, nrow(th)))
  # Audit: z = 0 (the threshold equals the initial level) means the trigger
  # is open from the start.
  at_start <- abs(th$z) < 1e-12 & th$direction != "both"
  if (any(at_start)) {
    out <- c(out, sprintf("'%s': the threshold equals the initial level, so the trigger is open from the start.", labels[at_start]))
  }
  # Audit: the pressures move the State away from the threshold, so the
  # trigger never opens this way (it used to be reported only when the
  # deviation went the right way but not far enough).
  opposite <- !at_start & th$direction != "both" & !is.na(dev) & abs(dev) > 1e-9 & sign(dev) != sign(th$z)
  if (any(opposite)) {
    out <- c(out, sprintf(
      "'%s': with every pressure at 100%% it moves %s (%.2f SD), away from the threshold (%.2f SD) - check the threshold level or the signs of the edges arriving at it.",
      labels[opposite], ifelse(dev[opposite] > 0, "up", "down"), dev[opposite], th$z[opposite]
    ))
  }
  never <- !at_start & !opposite & !is.na(dev) & !gate_is_open(dev, th$z, th$direction) & abs(dev) < abs(th$z)
  if (any(never)) {
    out <- c(out, sprintf(
      "'%s': with every pressure at 100%% its deviation in a single instant (%.2f SD) does not reach the threshold (%.2f SD) - the static reading keeps this trigger closed; it can still open over time by accumulation.",
      labels[never], dev[never], th$z[never]
    ))
  }
  incoming_p <- vapply(th$id, function(s) {
    src <- igraph::neighbors(g, s, mode = "in")$name
    any(role[match(src, V(g)$name)] %in% "pressure")
  }, logical(1))
  if (any(!incoming_p)) {
    out <- c(out, sprintf("'%s' has a threshold but no Pressure edge arriving at it.", labels[!incoming_p]))
  }
  out
}
