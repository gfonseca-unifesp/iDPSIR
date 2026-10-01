# =====================================================
# DATA NEEDS - what to measure or look up first (step 5 of the workflow)
# =====================================================
#
# One ranked, exportable table that joins what the app already flags in
# three places: the links behind tight verdicts (Interpretation), the least
# founded links (Metrics -> Strength & confidence) and the States without a
# threshold. Each row is something to measure or look up; the source found
# goes into that link's or State's record.
#
# Order - from the simulated-network experiment (Revisao 3, E5;
# analysis/sim_networks/): State thresholds and link strengths change
# verdicts in similar proportions (18.9% and 15.9%), growth trends rarely
# (4.3%), and changes concentrate near neutralization (odds ratio 5.4). So:
#   1. link_tight and threshold_missing, alternated (links by how much they
#      move the net, States by how many worsened Impacts they reach);
#   2. threshold_unanchored (the threshold's z rests on a default reference
#      or SD);
#   3. link_assumed_reaching (assumed strength, no reference, on a path from
#      an active pressure or response to a worsened Impact), by the product
#      of strengths along the strongest path through the link;
#   4. response_strength (how strongly each active response is actually
#      applied - a monitoring item);
#   5. growth_missing (only when the temporal simulation is on: growth
#      changes when a response stops being enough, rarely whether it is).
# Without a scenario only the structural items are returned (States without
# a threshold that reach an Impact; assumed links on a Driver -> Impact
# path, unranked).

DATA_NEEDS_COLUMNS <- c("priority_rank", "type", "item", "affects", "why", "current_source", "suggested_source", "effect")

DATA_NEEDS_SOURCES <- c(
  link_tight = "regression on monitoring data (r2 with n), a published effect size, or calibration against an observed series",
  threshold_missing = "monitoring series, legal/quality standard, literature",
  threshold_unanchored = "baseline monitoring: typical level (reference) and its SD",
  link_assumed_reaching = "literature or monitoring data; record the reference",
  response_strength = "implementation and compliance records, enforcement reports",
  growth_missing = "trend in official statistics or a monitoring series"
)

# Strength origin as the table names it: data / entered / class / default.
.data_needs_origin <- function(g) {
  o <- edge_strength_origin(g)
  c(estimated = "data", given = "entered", class = "class", default = "default", converted = "default")[o]
}

# Largest product of |beta| along any path from each of `from` to each of
# `to` (Inf distance = no path -> 0). Path products are found as shortest
# paths on -log|beta| (|beta| >= 1 counts as 1).
.data_needs_best_product <- function(g, from, to) {
  w <- pmin(1, abs(as.numeric(igraph::E(g)$weight)))
  len <- ifelse(w > 0, -log(w), Inf)
  len[!is.finite(len)] <- 1e6
  d <- igraph::distances(g, v = from, to = to, mode = "out", weights = len)
  out <- exp(-d)
  out[d >= 1e6] <- 0
  out
}

data_needs <- function(g, sc = NULL, temporal = FALSE, threshold = 1e-9, n_links = 5) {
  stopifnot(inherits(g, "igraph"))
  ids <- igraph::V(g)$name
  lab <- function(x) .interp_label(g, x)
  el <- igraph::as_edgelist(g, names = TRUE)
  origin <- .data_needs_origin(g)
  ref <- igraph::E(g)$reference
  if (is.null(ref)) ref <- rep("", nrow(el))
  has_ref <- !is.na(ref) & nzchar(trimws(as.character(ref)))
  assumed <- origin %in% c("class", "default")
  link_label <- function(k) sprintf("%s -> %s", lab(el[k, 1]), lab(el[k, 2]))
  impacts <- ids[has_role(g, "impact")]
  states <- ids[has_role(g, "state")]
  reach <- function(from, to) is.finite(igraph::distances(g, v = from, to = to, mode = "out"))

  p_D <- if (!is.null(sc$p_D)) align_press_vector(sc$p_D, ids, "pressure scenario") else NULL
  p_R <- if (!is.null(sc$press)) align_press_vector(sc$press, ids, "response scenario") else NULL
  has_scenario <- !is.null(p_D) && any(p_D != 0)
  if (has_scenario && is.null(p_R)) p_R <- setNames(rep(0, length(ids)), ids)

  rows <- list()
  add <- function(type, item, affects, why, current_source, effect = NA_real_, key = NA_real_) {
    rows[[length(rows) + 1]] <<- data.frame(type = type, item = item, affects = affects, why = why,
                                            current_source = current_source, suggested_source = DATA_NEEDS_SOURCES[[type]],
                                            effect = effect, key = key, stringsAsFactors = FALSE)
  }

  if (has_scenario) {
    s <- sc$sufficiency_df
    if (is.null(s) || nrow(s) == 0) s <- sufficiency(g, p_D, p_R)
    worsened <- s$id[s$worsening > threshold]
    tight <- s$id[s$worsening > threshold & abs(s$net) < INTERPRETATION_TIGHT * s$worsening]
    pushed <- unique(c(names(p_D)[p_D != 0], names(p_R)[p_R != 0]))

    # 1a. Links behind tight verdicts (the n_links that move each net most).
    tl <- do.call(rbind, lapply(tight, function(i) {
      lk <- tight_verdict_links(g, i, pushed, p_D, p_R)
      if (nrow(lk) == 0) return(NULL)
      lk <- lk[!is.na(lk$influence) & lk$influence > 1e-9, , drop = FALSE]
      if (nrow(lk) == 0) return(NULL)
      lk <- utils::head(lk, n_links)
      lk$impact <- i
      lk
    }))
    tight_keys <- character()
    if (!is.null(tl) && nrow(tl) > 0) {
      tl$k <- paste(tl$from, tl$to, sep = "|")
      for (k in unique(tl$k)) {
        sub <- tl[tl$k == k, , drop = FALSE]
        e <- which(el[, 1] == sub$from[1] & el[, 2] == sub$to[1])[1]
        eff <- sum(abs(sub$influence))
        add("link_tight", link_label(e), paste(lab(sub$impact), collapse = "; "),
            sprintf("Behind a tight verdict: beta +10%% moves the net by %.3f SD", eff),
            origin[e], effect = eff, key = eff)
        tight_keys <- c(tight_keys, k)
      }
    }

    # 1b. States reaching a worsened Impact without a threshold.
    thr <- igraph::V(g)$threshold_level
    if (is.null(thr)) thr <- rep(NA_real_, length(ids))
    for (st in states) {
      if (!is.na(thr[ids == st]) || length(worsened) == 0) next
      hit <- worsened[reach(st, worsened)[1, ]]
      if (length(hit) == 0) next
      add("threshold_missing", lab(st), paste(lab(hit), collapse = "; "),
          "No threshold: the State never switches its links; thresholds change verdicts as often as strengths",
          "none", effect = NA_real_, key = length(hit))
    }

    # 3. Assumed links without a reference on a path from a push to a
    # worsened Impact, by the strongest path product through the link.
    if (length(worsened) > 0) {
      to_imp <- .data_needs_best_product(g, ids, worsened)
      from_push <- .data_needs_best_product(g, pushed, ids)
      for (e in which(assumed & !has_ref)) {
        if (paste(el[e, 1], el[e, 2], sep = "|") %in% tight_keys) next
        a <- max(from_push[, el[e, 1]])
        b <- max(to_imp[el[e, 2], ])
        if (a <= 0 || b <= 0) next
        hit <- worsened[to_imp[el[e, 2], ] > 0]
        prod <- a * abs(igraph::E(g)$weight[e]) * b
        add("link_assumed_reaching", link_label(e), paste(lab(hit), collapse = "; "),
            sprintf("Assumed strength, no reference, on a path to a worsened Impact (path product %.3f)", prod),
            origin[e], effect = prod, key = prod)
      }
    }

    # 4. Active responses: how strongly they are actually applied.
    for (r in names(p_R)[p_R != 0]) {
      pct <- 100 * p_R[[r]]
      hit <- if (length(worsened)) worsened[reach(r, worsened)[1, ]] else character()
      add("response_strength", lab(r), if (length(hit)) paste(lab(hit), collapse = "; ") else "-",
          if (abs(pct - 100) > 1e-6) sprintf("Set at %.0f%%: measure actual implementation and compliance", pct)
          else "Assumed fully applied: monitor implementation and compliance",
          "entered", effect = NA_real_, key = NA_real_)
    }

    # 5. Growth of the pressure's Drivers (temporal reading only).
    if (isTRUE(temporal)) {
      gr <- igraph::V(g)$growth_rate
      if (is.null(gr)) gr <- rep(NA_real_, length(ids))
      for (d in names(p_D)[p_D != 0]) {
        if (!has_role(g, "driver")[ids == d]) next
        if (!is.na(gr[ids == d]) && gr[ids == d] != 0) next
        add("growth_missing", lab(d), "-",
            "No growth trend: it changes when a response stops being enough, rarely whether it is",
            "none", effect = NA_real_, key = NA_real_)
      }
    }
  } else {
    # Without a scenario: structural items only, unranked.
    thr <- igraph::V(g)$threshold_level
    if (is.null(thr)) thr <- rep(NA_real_, length(ids))
    for (st in states) {
      if (!is.na(thr[ids == st]) || length(impacts) == 0) next
      hit <- impacts[reach(st, impacts)[1, ]]
      if (length(hit) == 0) next
      add("threshold_missing", lab(st), paste(lab(hit), collapse = "; "),
          "No threshold: the State never switches its links", "none", key = length(hit))
    }
    drivers <- ids[has_role(g, "driver") | has_role(g, "pressure")]
    if (length(drivers) > 0 && length(impacts) > 0) {
      on_path_from <- apply(reach(drivers, ids), 2, any)
      on_path_to <- apply(reach(ids, impacts), 1, any)
      names(on_path_from) <- ids; names(on_path_to) <- ids
      for (e in which(assumed & !has_ref)) {
        if (!on_path_from[[el[e, 1]]] || !on_path_to[[el[e, 2]]]) next
        add("link_assumed_reaching", link_label(e), "-",
            "Assumed strength, no reference, on a Driver -> Impact path", origin[e])
      }
    }
  }

  # 2. States with a threshold whose z rests on a default reference or SD
  # (with or without a scenario).
  thr <- igraph::V(g)$threshold_level
  refv <- igraph::V(g)$reference_value
  sdv <- igraph::V(g)$sd
  for (st in states) {
    k <- which(ids == st)
    if (is.null(thr) || is.na(thr[k])) next
    if (!is.null(refv) && !is.na(refv[k]) && !is.null(sdv) && !is.na(sdv[k])) next
    add("threshold_unanchored", lab(st), "-",
        "Threshold set, but its z uses a default reference or SD", "default")
  }

  if (length(rows) == 0) {
    out <- as.data.frame(setNames(replicate(length(DATA_NEEDS_COLUMNS), character(), simplify = FALSE), DATA_NEEDS_COLUMNS))
    out$priority_rank <- integer(); out$effect <- numeric()
    attr(out, "note") <- if (!has_scenario) "No scenario applied: structural items only." else NULL
    return(out)
  }
  df <- do.call(rbind, rows)

  # Ordering: block 1 alternates tight links (by effect) and missing
  # thresholds (by Impacts reached); then the other blocks.
  ord_within <- function(d) d[order(-ifelse(is.na(d$key), -Inf, d$key)), , drop = FALSE]
  lt <- ord_within(df[df$type == "link_tight", , drop = FALSE])
  tm <- ord_within(df[df$type == "threshold_missing", , drop = FALSE])
  n1 <- max(nrow(lt), nrow(tm))
  block1 <- do.call(rbind, lapply(seq_len(n1), function(i) rbind(if (i <= nrow(lt)) lt[i, ], if (i <= nrow(tm)) tm[i, ])))
  rest <- lapply(c("threshold_unanchored", "link_assumed_reaching", "response_strength", "growth_missing"),
                 function(t) ord_within(df[df$type == t, , drop = FALSE]))
  df <- do.call(rbind, c(list(block1), rest))
  df$priority_rank <- seq_len(nrow(df))
  df$effect <- round(df$effect, 4)
  rownames(df) <- NULL
  out <- df[, DATA_NEEDS_COLUMNS]
  attr(out, "note") <- if (!has_scenario) "No scenario applied: structural items only (States without a threshold that reach an Impact; assumed links without a reference on a Driver -> Impact path), not ranked by effect." else NULL
  out
}

DATA_NEEDS_INTRO <- paste(
  "Ranked by how likely the data are to change a verdict (thresholds and links behind tight verdicts first; growth last).",
  "Each source you find goes into the link's or State's record."
)

# Labels for display (UI and report).
format_data_needs <- function(df) {
  if (nrow(df) == 0) return(df)
  type_label <- c(link_tight = "Link behind a tight verdict", threshold_missing = "State without threshold",
                  threshold_unanchored = "Threshold without reference/SD", link_assumed_reaching = "Assumed link on a path",
                  response_strength = "Response strength actually applied", growth_missing = "Driver without growth trend")
  data.frame(`#` = df$priority_rank, Type = unname(type_label[df$type]), Item = df$item, Affects = df$affects,
             Why = df$why, `Current source` = df$current_source, `Suggested source` = df$suggested_source,
             Effect = ifelse(is.na(df$effect), "", formatC(df$effect, format = "f", digits = 3)),
             check.names = FALSE, stringsAsFactors = FALSE)
}
