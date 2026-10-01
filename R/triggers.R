# =====================================================
# STATE TRIGGERS (Revisao 2, Fase C - decisions D7, D8, D11, D23)
# =====================================================
#
# A State with a threshold passes its effect on to the factors it feeds only
# once its deviation crosses that threshold (binary gate, D8: all its
# outgoing edges switch on or off together).
#
# Measurement layer (C0): the threshold is a LEVEL in the factor's own units
# (threshold_level); reference_value is the factor's initial level and sd its
# typical variation. In the engine's units (standard deviations; sd = 1 and
# reference = 1 when not given) the threshold is
#   z = (threshold_level - reference_value) / sd
# and the gate is open when the State's deviation x_S has crossed it in its
# direction: x_S <= z for a falling State (z < 0), x_S >= z for a rising one
# (z > 0), or |x_S| >= |z| for direction "both" (older files).
#
# Static reading (C1/C2): x_S is the deviation of the State under the
# scenario - the strength of each incoming edge times the total level of its
# source (push + effect), with Driver/Pressure levels clipped at >= 0 (D7). In
# the structural mode this is the State's own static deviation. With a
# feedback cycle the gates depend on themselves, so they are iterated until
# stable (at most 20 times); if they oscillate, all gates are opened
# (conservative) and `unstable` is flagged.

state_thresholds <- function(g) {
  ids <- V(g)$name
  cat <- V(g)$dpsir_category
  level <- suppressWarnings(as.numeric(V(g)$threshold_level))
  if (length(level) == 0) level <- rep(NA_real_, length(ids))
  keep <- !is.na(level) & has_role(g, "state")
  if (!any(keep)) {
    return(data.frame(id = character(), level = numeric(), reference = numeric(), sd = numeric(),
                      z = numeric(), direction = character(), stringsAsFactors = FALSE))
  }
  ref <- suppressWarnings(as.numeric(V(g)$reference_value)); if (length(ref) == 0) ref <- rep(NA_real_, length(ids))
  sd <- suppressWarnings(as.numeric(V(g)$sd)); if (length(sd) == 0) sd <- rep(NA_real_, length(ids))
  dirn <- V(g)$threshold_direction; if (is.null(dirn)) dirn <- rep("auto", length(ids))
  ref_eff <- ifelse(is.na(ref), 1, ref)
  sd_eff <- ifelse(is.na(sd), 1, sd)
  z <- (level - ref_eff) / sd_eff
  data.frame(
    id = ids[keep], level = level[keep], reference = ref[keep], sd = sd[keep],
    z = z[keep], direction = ifelse(is.na(dirn[keep]), "auto", dirn[keep]),
    stringsAsFactors = FALSE
  )
}

gate_is_open <- function(x, z, direction) {
  ifelse(direction == "both", abs(x) >= abs(z) - 1e-12,
         ifelse(z < 0, x <= z + 1e-12, ifelse(z > 0, x >= z - 1e-12, TRUE)))
}

# B with the outgoing edges (columns) of closed States zeroed.
apply_gates <- function(B, closed_ids) {
  if (length(closed_ids) > 0) B[, closed_ids] <- 0
  B
}

# Static deviation of each State under push p with gated matrix Bg.
static_state_deviation <- function(g, Bg, p, state_ids) {
  n <- nrow(Bg)
  levels <- tryCatch(solve(diag(n) - Bg, as.numeric(p)), error = function(e) rep(NA_real_, n))
  names(levels) <- rownames(Bg)
  dp <- node_roles(g)[match(rownames(Bg), V(g)$name)] %in% c("driver", "pressure")
  levels[dp] <- pmax(levels[dp], 0)
  vapply(state_ids, function(s) sum(Bg[s, ] * levels), numeric(1))
}

# Gate state of every thresholded State under push p (static reading).
state_gates <- function(g, p, B = effect_matrix(g), max_iter = 20) {
  th <- state_thresholds(g)
  if (nrow(th) == 0) {
    return(structure(
      data.frame(id = character(), z = numeric(), deviation = numeric(), open = logical(), stringsAsFactors = FALSE),
      unstable = FALSE
    ))
  }
  p <- align_press_vector(p, rownames(B), "scenario")
  closed <- character()
  seen <- list()
  unstable <- FALSE
  for (it in seq_len(max_iter)) {
    Bg <- apply_gates(B, closed)
    dev <- static_state_deviation(g, Bg, p, th$id)
    open <- gate_is_open(dev, th$z, th$direction)
    new_closed <- th$id[!open]
    if (setequal(new_closed, closed)) break
    key <- paste(sort(new_closed), collapse = "|")
    if (key %in% seen) { unstable <- TRUE; break }
    seen[[length(seen) + 1]] <- key
    closed <- new_closed
    if (it == max_iter) unstable <- TRUE
  }
  if (unstable) {
    dev <- static_state_deviation(g, B, p, th$id)
    open <- rep(TRUE, nrow(th))
  }
  out <- data.frame(id = th$id, level = th$level, z = th$z, direction = th$direction,
                    deviation = unname(dev), open = open, stringsAsFactors = FALSE)
  attr(out, "unstable") <- unstable
  out
}

# The effect matrix with the gates that push p produces applied.
gated_effect_matrix <- function(g, p, B = effect_matrix(g)) {
  gates <- state_gates(g, p, B)
  apply_gates(B, gates$id[!gates$open])
}

has_state_thresholds <- function(g) nrow(state_thresholds(g)) > 0

# Temporal gate (C3, D11): per window, per thresholded State.
#   "state_level" (default, P1): the State's accumulated deviation x_S(t);
#   "load": what arrives this window from its Pressure/Response sources,
#           sum_j B[S, j] * x_j(t).
temporal_gate_matrix <- function(W, x, th, g, gate_mode = c("state_level", "load")) {
  gate_mode <- match.arg(gate_mode)
  if (nrow(th) == 0) return(list(W = W, open = logical()))
  if (gate_mode == "state_level") {
    value <- x[th$id]
  } else {
    src <- node_roles(g)[match(names(x), V(g)$name)] %in% c("pressure", "feedback")
    value <- vapply(th$id, function(s) sum(W[s, src] * x[src]), numeric(1))
  }
  open <- gate_is_open(value, th$z, th$direction)
  # A closed State stops passing its effect on (its outgoing edges) but
  # keeps its own self-regulation (the diagonal).
  for (s in th$id[!open]) W[rownames(W) != s, s] <- 0
  list(W = W, open = setNames(open, th$id))
}

# Revisao 2, item C5 (D12): reach that does not cross closed triggers.
effective_response_reach <- function(g, active_ids, closed_ids) {
  if (length(closed_ids) == 0) {
    r <- response_reach(g, active_ids)
    return(list(total = r$total, closed = character(), closed_labels = character()))
  }
  drop <- igraph::E(g)[.from(closed_ids)]
  g2 <- igraph::delete_edges(g, drop)
  r <- response_reach(g2, active_ids)
  list(total = r$total, closed = closed_ids, closed_labels = V(g)$label[match(closed_ids, V(g)$name)])
}

# Revisao 2, item C4: one row per thresholded State.
format_triggers_table <- function(g, gates_pressure, gates_net) {
  th <- state_thresholds(g)
  idx <- match(gates_pressure$id, th$id)
  lab <- V(g)$label[match(gates_pressure$id, V(g)$name)]
  dir <- ifelse(th$direction[idx] == "both", "either way", ifelse(th$z[idx] < 0, "falling", "rising"))
  oc <- function(x) ifelse(x, "open", "closed")
  data.frame(
    State = lab,
    Threshold = sprintf("%s (%s)", signif(th$level[idx], 4), dir),
    `Threshold (SD)` = round(th$z[idx], 2),
    `Deviation, pressure only` = round(gates_pressure$deviation, 3),
    `Deviation, with response` = round(gates_net$deviation[match(gates_pressure$id, gates_net$id)], 3),
    Before = oc(gates_pressure$open),
    After = oc(gates_net$open[match(gates_pressure$id, gates_net$id)]),
    `Response closes it?` = ifelse(gates_pressure$open & !gates_net$open[match(gates_pressure$id, gates_net$id)], "Yes", "No"),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

# Revisao 2, item C0: levels in the factor's own units at the last window,
# for factors with an initial level (reference value).
temporal_level_table <- function(g, tr) {
  ids <- V(g)$name
  ref <- suppressWarnings(as.numeric(V(g)$reference_value))
  if (length(ref) == 0) ref <- rep(NA_real_, length(ids))
  sd <- suppressWarnings(as.numeric(V(g)$sd)); if (length(sd) == 0) sd <- rep(NA_real_, length(ids))
  # Older files stored reference_value = 1 as a placeholder for "not given";
  # with no typical variation and no threshold that is the model's own unit,
  # not a real initial level, so it is left out.
  placeholder <- !is.na(ref) & ref == 1 & is.na(sd) & !(ids %in% tr$thresholds$id)
  keep <- !is.na(ref) & !placeholder
  if (!any(keep)) return(data.frame())
  last <- nrow(tr$scenario)
  # Revisao 2, Fase D: the same scale the engine used for the trend.
  sd_eff <- unname(node_scale(g)[ids])
  lb <- ref + sd_eff * tr$baseline[last, ids]
  ls <- ref + sd_eff * tr$scenario[last, ids]
  crossed <- rep("", length(ids))
  if (nrow(tr$thresholds) > 0) {
    for (k in seq_len(nrow(tr$thresholds))) {
      i <- match(tr$thresholds$id[k], ids)
      # The gate of window w reads the level of window w - 1, so the level
      # crossed the threshold in window w - 1.
      w <- which(tr$gates_scenario[, k])[1]
      crossed[i] <- if (is.na(w)) "not crossed" else sprintf("window %d", w - 1)
    }
  }
  data.frame(
    Factor = V(g)$label[keep],
    `Initial level` = signif(ref[keep], 4),
    `Without response` = signif(lb[keep], 4),
    `Without response (%)` = sprintf("%+.1f%%", 100 * (lb[keep] - ref[keep]) / ref[keep]),
    `With response` = signif(ls[keep], 4),
    `With response (%)` = sprintf("%+.1f%%", 100 * (ls[keep] - ref[keep]) / ref[keep]),
    `Threshold crossed` = crossed[keep],
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

# Revisao 2, item C0: linear strengths extrapolate; warn beyond 3 SD for
# factors measured in their own units (typical variation given).
temporal_extrapolation_note <- function(g, tr) {
  sd <- suppressWarnings(as.numeric(V(g)$sd))
  if (length(sd) == 0 || all(is.na(sd))) return(NULL)
  ids <- V(g)$name[!is.na(sd)]
  big <- ids[apply(abs(tr$scenario[, ids, drop = FALSE]) > 3 | abs(tr$baseline[, ids, drop = FALSE]) > 3, 2, any)]
  if (length(big) == 0) return(NULL)
  sprintf(
    "%s move(s) beyond 3 typical variations: strengths are linear, and far outside the range of the data the real relationship may saturate or follow a dose-response curve.",
    paste(V(g)$label[match(big, V(g)$name)], collapse = ", ")
  )
}
