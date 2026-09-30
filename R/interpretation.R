# =====================================================
# INTERPRETATION - plain-language reading of a scenario
# =====================================================
#
# Turns what "Apply scenario" computes (compute_scenario() in
# R/modules/mod_responses.R: sufficiency, confidence per response,
# prioritization, reach, State triggers) into a reading a manager can act
# on: one sentence per Impact, ordered by priority, plus the key messages of
# the scenario and a side-by-side comparison of scenarios. Pure functions -
# the Interpretation tab and the report call the same ones, so the text can
# never differ between screen and report.

INTERPRETATION_CONFIDENT <- 80  # % of simulations for "reliable" / "neutralizes it alone"
INTERPRETATION_FRAGILE <- c(20, 80)  # a verdict whose confidence falls here is fragile

.interp_label <- function(g, ids) {
  l <- igraph::V(g)$label[match(ids, igraph::V(g)$name)]
  ifelse(is.na(l) | !nzchar(l), ids, l)
}

.interp_num <- function(x, digits = 2) formatC(x, format = "f", digits = digits)

# One row per Impact, ordered: worsened Impacts by priority (highest first),
# then the others. `status`: neutralized, partial, not_covered,
# worsened_by_response, improved, not_affected.
interpret_scenario <- function(g, sc, threshold = 1e-9) {
  s <- sc$sufficiency_df
  if (is.null(s) || nrow(s) == 0) {
    return(list(impacts = data.frame(), headline = "The network has no Impact factors.", messages = character()))
  }
  pr <- sc$prioritization
  k <- if (!is.null(pr)) match(s$id, pr$id) else rep(NA_integer_, nrow(s))
  priority <- if (!is.null(pr)) pr$priority[k] else rep(NA_real_, nrow(s))
  relevance <- if (!is.null(pr)) pr$relevance[k] else rep(NA_real_, nrow(s))

  conf <- sc$sufficiency_confidence_matrix
  planned_row <- if (!is.null(conf) && "Response" %in% names(conf)) which(conf$Response == "Planned scenario (as set)") else integer()
  alone_rows <- if (!is.null(conf) && "Response" %in% names(conf)) setdiff(seq_len(nrow(conf)), planned_row) else integer()
  conf_of <- function(label) {
    if (length(planned_row) == 0 || !label %in% names(conf)) return(NA_real_)
    suppressWarnings(as.numeric(conf[[label]][planned_row]))
  }
  alone_text <- function(label) {
    if (length(alone_rows) == 0 || !label %in% names(conf)) return("")
    v <- suppressWarnings(as.numeric(conf[[label]][alone_rows]))
    names(v) <- conf$Response[alone_rows]
    v <- v[!is.na(v)]
    if (length(v) == 0) return("")
    good <- sort(v[v >= INTERPRETATION_CONFIDENT], decreasing = TRUE)
    if (length(good) > 0) {
      return(sprintf(" Alone at full strength, %s neutralize%s it.",
                     paste(sprintf("%s (%.0f%%)", names(good), good), collapse = ", "), if (length(good) == 1) "s" else ""))
    }
    best <- v[which.max(v)]
    if (best > 0) sprintf(" No single response neutralizes it reliably on its own (best: %s, %.0f%%).", names(best), best)
    else " No single response neutralizes it on its own."
  }

  w <- s$worsening; m <- s$mitigation; n <- s$net
  status <- ifelse(w <= threshold,
                   ifelse(m > threshold, "worsened_by_response", ifelse(m < -threshold, "improved", "not_affected")),
                   ifelse(s$neutralized, "neutralized",
                          ifelse(m < -threshold, "partial", ifelse(m > threshold, "worsened_by_response", "not_covered"))))
  coverage <- ifelse(w > threshold, pmax(0, -m) / w, NA_real_)
  confidence <- vapply(s$node, conf_of, numeric(1))

  text <- vapply(seq_len(nrow(s)), function(i) {
    base <- switch(status[i],
      not_affected = "Not affected by this pressure scenario.",
      improved = "Not worsened by the pressure; the response improves it further.",
      worsened_by_response = if (w[i] <= threshold)
        sprintf("Not worsened by the pressure, but the response scenario worsens it (+%s).", .interp_num(m[i]))
        else sprintf("Not covered: the response scenario makes it worse (+%s on top of the pressure's +%s).", .interp_num(m[i]), .interp_num(w[i])),
      not_covered = sprintf("Not covered: the pressure worsens it (+%s) and none of the active responses reaches it.", .interp_num(w[i])),
      neutralized = paste0(
        sprintf("Neutralized: the response offsets all of the pressure's worsening (+%s; net %s)", .interp_num(w[i]), .interp_num(n[i])),
        if (identical(s$neutralized_by[i], "trigger")) " - by closing a State trigger, not by direct mitigation." else "."),
      partial = paste0(
        sprintf("Partly covered: the response offsets %.0f%% of the worsening (+%s; net +%s)", 100 * min(1, coverage[i]), .interp_num(w[i]), .interp_num(n[i])),
        if (!is.na(s$strength_to_neutralize[i])) sprintf("; it would need x%s its strength to neutralize it.", .interp_num(s$strength_to_neutralize[i]))
        else "; no strength of this response scenario neutralizes it.")
    )
    c_txt <- if (status[i] %in% c("neutralized", "partial")) {
      ci <- confidence[i]
      if (is.nan(ci)) " Confidence not computable (the loops amplify in every resampled draw)."
      else if (is.na(ci)) ""
      else if (status[i] == "neutralized") sprintf(" Holds in %.0f%% of the simulations%s.", ci,
                   if (ci >= INTERPRETATION_FRAGILE[1] && ci <= INTERPRETATION_FRAGILE[2]) " - a fragile verdict" else "")
      else if (ci > 0) sprintf(" With the uncertain link strengths it is neutralized in %.0f%% of the simulations%s.", ci,
                   if (ci >= INTERPRETATION_FRAGILE[1] && ci <= INTERPRETATION_FRAGILE[2]) " - a fragile verdict" else "")
      else ""
    } else ""
    a_txt <- if (w[i] > threshold && !s$neutralized[i]) alone_text(s$node[i]) else ""
    paste0(base, c_txt, a_txt)
  }, character(1))

  df <- data.frame(
    id = s$id, node = s$node, status = status, worsening = w, mitigation = m, net = n,
    coverage = coverage, neutralized = s$neutralized, strength_needed = s$strength_to_neutralize,
    confidence = unname(confidence), relevance = relevance, priority = priority,
    text = text, stringsAsFactors = FALSE
  )
  worsened <- df$worsening > threshold
  ord <- order(!worsened, -ifelse(is.na(df$priority), -Inf, df$priority), -df$worsening)
  df <- df[ord, , drop = FALSE]
  rownames(df) <- NULL
  df$rank <- ifelse(df$worsening > threshold, cumsum(df$worsening > threshold), NA_integer_)

  n_w <- sum(worsened)
  n_ok <- sum(worsened & df$neutralized[match(s$id, df$id)])
  headline <- if (n_w == 0) "The pressure scenario worsens no Impact."
    else if (n_ok == n_w) sprintf("The response scenario neutralizes all %d worsened Impact%s.", n_w, if (n_w == 1) "" else "s")
    else sprintf("The response scenario neutralizes %d of %d worsened Impacts.", n_ok, n_w)

  msgs <- character()
  open <- df[df$worsening > threshold & !df$neutralized, , drop = FALSE]
  if (nrow(open) > 0 && any(!is.na(open$priority))) {
    top <- open[which.max(ifelse(is.na(open$priority), -Inf, open$priority)), ]
    msgs <- c(msgs, sprintf("Act first on %s: the highest priority left (%s = relevance %s x uncovered share %s).",
                            top$node, .interp_num(top$priority), .interp_num(top$relevance),
                            .interp_num(if (is.na(top$coverage)) 1 else 1 - min(1, top$coverage))))
  }
  worse <- df$node[df$status == "worsened_by_response"]
  if (length(worse) > 0) msgs <- c(msgs, sprintf("The response scenario itself worsens: %s - a side effect to weigh.", paste(worse, collapse = ", ")))
  nc <- df$node[df$status == "not_covered"]
  if (length(nc) > 0) msgs <- c(msgs, sprintf("No active response reaches: %s.", paste(nc, collapse = ", ")))
  fr <- df$node[!is.na(df$confidence) & !is.nan(df$confidence) & df$status %in% c("neutralized", "partial") &
                  df$confidence >= INTERPRETATION_FRAGILE[1] & df$confidence <= INTERPRETATION_FRAGILE[2]]
  if (length(fr) > 0) msgs <- c(msgs, sprintf("Fragile verdicts (confidence between %d%% and %d%%): %s - narrowing the uncertainty of the links involved would settle them.",
                                             INTERPRETATION_FRAGILE[1], INTERPRETATION_FRAGILE[2], paste(fr, collapse = ", ")))
  rob <- sc$priority_robustness
  if (!is.null(rob) && nrow(rob) >= 2 && !is.null(attr(rob, "top_stable")) && attr(rob, "top_stable") < 0.8) {
    msgs <- c(msgs, sprintf("The top priority depends on the values v and on how the index is combined: it stays first in only %.0f%% of the variations tested.",
                            100 * attr(rob, "top_stable")))
  }
  closed <- sc$gates_net
  if (!is.null(closed) && nrow(closed) > 0 && any(!closed$open)) {
    msgs <- c(msgs, sprintf("State trigger%s closed with the response: %s - nothing passes beyond %s.",
                            if (sum(!closed$open) == 1) "" else "s", paste(.interp_label(g, closed$id[!closed$open]), collapse = ", "),
                            if (sum(!closed$open) == 1) "it" else "them"))
  }
  list(impacts = df, headline = headline, messages = msgs)
}

# Scenario x Impact comparison: in each cell "Neutralized", "NN% covered",
# "worsened by the response", "not covered" or "-" (not worsened).
compare_scenario_interpretations <- function(g, scenarios) {
  if (length(scenarios) == 0) return(data.frame())
  rows <- lapply(names(scenarios), function(nm) {
    it <- interpret_scenario(g, scenarios[[nm]])$impacts
    if (nrow(it) == 0) return(NULL)
    cell <- ifelse(it$status == "neutralized", "Neutralized",
            ifelse(it$status == "partial", sprintf("%.0f%% covered", 100 * pmin(1, it$coverage)),
            ifelse(it$status == "worsened_by_response", "worsened by the response",
            ifelse(it$status == "not_covered", "not covered", "-"))))
    worsened <- it$worsening > 1e-9
    open <- it[worsened & !it$neutralized & !is.na(it$priority), , drop = FALSE]
    top <- if (nrow(open) > 0) open$node[which.max(open$priority)] else "-"
    sc <- scenarios[[nm]]
    out <- data.frame(Scenario = nm,
                      Responses = if (length(sc$active) == 0) "none" else paste(sprintf("%s %d%%", .interp_label(g, sc$active), round(sc$strengths[sc$active])), collapse = ", "),
                      Neutralized = sprintf("%d of %d", sum(worsened & it$neutralized), sum(worsened)),
                      `Top priority left` = top, check.names = FALSE, stringsAsFactors = FALSE)
    for (j in seq_len(nrow(it))) out[[it$node[j]]] <- cell[j]
    out
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0) return(data.frame())
  cols <- unique(unlist(lapply(rows, names)))
  do.call(rbind, lapply(rows, function(r) { r[setdiff(cols, names(r))] <- "-"; r[cols] }))
}

# Coverage chart: for each Impact, the pressure's worsening (red bar), what
# the response offsets (green bar) and the net (black diamond; at or left
# of zero = neutralized). Impacts in priority order, top = first.
draw_sufficiency_plot <- function(interp_df) {
  df <- interp_df[interp_df$worsening > 1e-9 | abs(interp_df$mitigation) > 1e-9, , drop = FALSE]
  if (nrow(df) == 0) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "No Impact is moved by this scenario.")
    return(invisible())
  }
  df <- df[rev(seq_len(nrow(df))), , drop = FALSE]
  offset <- pmax(0, -df$mitigation)
  extra <- pmax(0, df$mitigation)
  xr <- range(0, df$worsening + extra, offset, df$net)
  xr <- xr + c(-0.05, 0.05) * diff(xr)
  old <- graphics::par(mar = c(4, max(8, max(nchar(df$node)) * 0.55), 1.5, 1))
  on.exit(graphics::par(old))
  y <- seq_len(nrow(df))
  graphics::plot(NA, xlim = xr, ylim = c(0.4, nrow(df) + 1.4), yaxt = "n", ylab = "",
                 xlab = "effect on the Impact (+ worse, - better)", bty = "n")
  graphics::axis(2, at = y, labels = df$node, las = 1, tick = FALSE, cex.axis = 0.85)
  graphics::abline(v = 0, col = "grey50")
  graphics::rect(0, y + 0.04, df$worsening, y + 0.34, col = "#e8a0a0", border = NA)
  graphics::rect(df$worsening, y + 0.04, df$worsening + extra, y + 0.34, col = "#b03030", border = NA)
  graphics::rect(0, y - 0.34, offset, y - 0.04, col = "#8fcf9f", border = NA)
  graphics::points(df$net, y, pch = 23, bg = ifelse(df$neutralized, "#1b8a3a", "#1f2937"), col = "#1f2937", cex = 1.4)
  # Only what is drawn gets a legend entry (the dark red segment exists only
  # when the response itself worsens an Impact).
  items <- data.frame(
    label = c("worsening by the pressure", "worsening added by the response", "offset by the response",
              "net: neutralized (<= 0)", "net: not neutralized"),
    pch = c(15, 15, 15, 23, 23),
    col = c("#e8a0a0", "#b03030", "#8fcf9f", "#1f2937", "#1f2937"),
    bg = c(NA, NA, NA, "#1b8a3a", "#1f2937"),
    shown = c(any(df$worsening > 1e-9), any(extra > 1e-9), any(offset > 1e-9), any(df$neutralized), any(!df$neutralized)),
    stringsAsFactors = FALSE)
  items <- items[items$shown, , drop = FALSE]
  graphics::legend("top", bty = "n", cex = 0.8, ncol = 2, pch = items$pch, col = items$col, pt.bg = items$bg,
                   legend = items$label)
}
