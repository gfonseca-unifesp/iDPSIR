# =====================================================
# Simulated DPSIR networks - analysis (Revisao 3, E5.5)
# =====================================================
#
# Implements section 6 of PREREGISTRO.md on out/results.csv.gz,
# out/networks.csv and out/counts.csv (written by run.R); reads nothing else.
# Writes out/change_rates.csv, out/hypotheses.csv, out/glmer.csv,
# out/rf_importance.csv, out/fig_{a,b,c,d}.png/.svg and out/summary.md.

SIM_PAIRS <- list(c("C0", "C1"), c("C1", "C2"), c("C2", "C2t"), c("C2t", "C3"), c("C0", "C3"))
SIM_BOOT <- 2000
SIM_SEED <- 42

load_sim_outputs <- function(out_dir = "analysis/sim_networks/out") {
  list(
    results = utils::read.csv(gzfile(file.path(out_dir, "results.csv.gz")), stringsAsFactors = FALSE),
    networks = utils::read.csv(file.path(out_dir, "networks.csv"), stringsAsFactors = FALSE),
    counts = utils::read.csv(file.path(out_dir, "counts.csv"), stringsAsFactors = FALSE)
  )
}

# One row per network x draw x Impact with the 3-level verdict of `a` and `b`
# (C0 has draw 0 and is matched to every draw). Temporal draws that diverged
# are left out of the pairs that use them (section 7).
verdict_pairs <- function(res, a, b) {
  pick <- function(cond) {
    d <- res[res$condition == cond, c("network", "draw", "impact", "verdict3", "diverges", "worsening", "net")]
    d[!(d$diverges %in% TRUE), , drop = FALSE]
  }
  A <- pick(a); B <- pick(b)
  key_cols <- if (a == "C0") c("network", "impact") else c("network", "draw", "impact")
  m <- merge(A, B, by = key_cols, suffixes = c("_a", "_b"))
  if (a == "C0") m$draw <- m$draw_b
  m$changed <- m$verdict3_a != m$verdict3_b
  m
}

boot_by_network <- function(df, stat, n = SIM_BOOT, seed = SIM_SEED) {
  nets <- unique(df$network)
  idx <- split(seq_len(nrow(df)), df$network)
  with_local_seed(seed, vapply(seq_len(n), function(k) {
    s <- sample(nets, length(nets), replace = TRUE)
    stat(df[unlist(idx[as.character(s)], use.names = FALSE), , drop = FALSE])
  }, numeric(1)))
}

ci <- function(x) stats::quantile(x, c(0.025, 0.975), na.rm = TRUE, names = FALSE)

change_rates <- function(res) {
  do.call(rbind, lapply(SIM_PAIRS, function(p) {
    m <- verdict_pairs(res, p[1], p[2])
    b <- boot_by_network(m, function(d) mean(d$changed))
    data.frame(pair = paste(p, collapse = "->"), n = nrow(m), rate = mean(m$changed),
               lo = ci(b)[1], hi = ci(b)[2], stringsAsFactors = FALSE)
  }))
}

# Paired bootstrap of rate(pair2) - rate(pair1) over the same networks.
paired_difference <- function(res, pair1, pair2) {
  m1 <- verdict_pairs(res, pair1[1], pair1[2]); m2 <- verdict_pairs(res, pair2[1], pair2[2])
  nets <- intersect(unique(m1$network), unique(m2$network))
  i1 <- split(seq_len(nrow(m1)), m1$network); i2 <- split(seq_len(nrow(m2)), m2$network)
  b <- with_local_seed(SIM_SEED, vapply(seq_len(SIM_BOOT), function(k) {
    s <- as.character(sample(nets, length(nets), replace = TRUE))
    mean(m2$changed[unlist(i2[s], use.names = FALSE)]) - mean(m1$changed[unlist(i1[s], use.names = FALSE)])
  }, numeric(1)))
  c(diff = mean(m2$changed[m2$network %in% nets]) - mean(m1$changed[m1$network %in% nets]), lo = ci(b)[1], hi = ci(b)[2])
}

decide <- function(lo, hi, threshold = 0, direction = c("above", "below")) {
  direction <- match.arg(direction)
  if (direction == "above") {
    if (lo > threshold) "confirmed" else if (hi < threshold) "refuted" else "inconclusive"
  } else {
    if (hi < threshold) "confirmed" else if (lo > threshold) "refuted" else "inconclusive"
  }
}

# Kendall's tau between C0 and C1 priority orders, per network x draw
# (worsened Impacts in both; at least 3).
kendall_c0_c1 <- function(res) {
  c0 <- res[res$condition == "C0" & !is.na(res$priority), c("network", "impact", "priority")]
  c1 <- res[res$condition == "C1" & !is.na(res$priority), c("network", "draw", "impact", "priority")]
  m <- merge(c0, c1, by = c("network", "impact"), suffixes = c("_0", "_1"))
  sp <- split(m, list(m$network, m$draw), drop = TRUE)
  out <- do.call(rbind, lapply(sp, function(d) {
    if (nrow(d) < 3 || stats::sd(d$priority_0) == 0 || stats::sd(d$priority_1) == 0) return(NULL)
    top0 <- d$impact[which.max(d$priority_0)]; top1 <- d$impact[which.max(d$priority_1)]
    data.frame(network = d$network[1], draw = d$draw_1[1] %||% d$draw[1],
               tau = suppressWarnings(stats::cor(d$priority_0, d$priority_1, method = "kendall")),
               top_changed = top0 != top1)
  }))
  out
}

regression_data <- function(res, nets) {
  m <- verdict_pairs(res, "C0", "C1")
  m <- m[m$worsening_a > 1e-9, , drop = FALSE]                  # c defined only when worsened in C0
  m$near <- abs(m$net_a) / m$worsening_a < 0.2
  rho <- res[res$condition == "C1", c("network", "draw", "rho_B", "draw_mode")]
  rho <- rho[!duplicated(rho[, c("network", "draw")]), ]
  m <- merge(m, rho, by = c("network", "draw"))
  m <- merge(m, nets, by = "network")
  z <- function(x) (x - mean(x, na.rm = TRUE)) / stats::sd(x, na.rm = TRUE)
  m$z_nodes <- z(m$n_nodes); m$z_density <- z(m$density); m$z_rho <- z(m$rho_B)
  m$z_path <- z(m$mean_path_DI); m$z_reached <- z(m$share_reached)
  m
}

fit_glmer <- function(d) {
  f <- changed ~ has_cycle + near + z_nodes + z_density + z_rho + z_path + z_reached + (1 | network)
  fit <- lme4::glmer(f, data = d, family = stats::binomial(), control = lme4::glmerControl(optimizer = "bobyqa"))
  co <- summary(fit)$coefficients
  data.frame(term = rownames(co), estimate = co[, 1], se = co[, 2],
             lo = co[, 1] - 1.96 * co[, 2], hi = co[, 1] + 1.96 * co[, 2], p = co[, 4], row.names = NULL)
}

rf_importance <- function(d) {
  d$changed_f <- factor(d$changed)
  d$draw_mode <- factor(d$draw_mode)
  rf <- ranger::ranger(changed_f ~ has_cycle + near + n_nodes + density + rho_B + mean_path_DI + share_reached +
                         n_thresholds + n_growing + draw_mode, data = d, num.trees = 500, importance = "permutation",
                       seed = SIM_SEED)
  imp <- sort(rf$variable.importance, decreasing = TRUE)
  data.frame(variable = names(imp), importance = unname(imp))
}

analyze_all <- function(out_dir = "analysis/sim_networks/out") {
  o <- load_sim_outputs(out_dir)
  res <- o$results; nets <- o$networks
  rates <- change_rates(res)
  h2a <- paired_difference(res, c("C0", "C1"), c("C1", "C2"))
  h2b <- paired_difference(res, c("C0", "C1"), c("C2t", "C3"))
  kt <- kendall_c0_c1(res)
  kt_b <- boot_by_network(kt, function(d) mean(d$tau, na.rm = TRUE))
  reg <- regression_data(res, nets)
  gl <- tryCatch(fit_glmer(reg), error = function(e) { message("glmer failed: ", conditionMessage(e)); NULL })
  rf <- tryCatch(rf_importance(reg), error = function(e) NULL)

  r01 <- rates[rates$pair == "C0->C1", ]
  term <- function(t) if (is.null(gl)) c(NA, NA) else unlist(gl[gl$term == t, c("lo", "hi")])
  h3 <- term("has_cycleTRUE"); h4 <- term("nearTRUE")
  hyp <- data.frame(
    hypothesis = c("H1", "H2 (thresholds)", "H2 (growth)", "H2", "H3", "H4", "H5"),
    statistic = c("change rate C0->C1", "rate(C1->C2) - rate(C0->C1)", "rate(C2t->C3) - rate(C0->C1)", "both H2 differences",
                  "glmer coef has_cycle", "glmer coef near (c < 0.2)", "mean Kendall tau C0 vs C1"),
    estimate = c(r01$rate, h2a[["diff"]], h2b[["diff"]], NA, if (is.null(gl)) NA else gl$estimate[gl$term == "has_cycleTRUE"],
                 if (is.null(gl)) NA else gl$estimate[gl$term == "nearTRUE"], mean(kt$tau, na.rm = TRUE)),
    lo = c(r01$lo, h2a[["lo"]], h2b[["lo"]], NA, h3[1], h4[1], ci(kt_b)[1]),
    hi = c(r01$hi, h2a[["hi"]], h2b[["hi"]], NA, h3[2], h4[2], ci(kt_b)[2]),
    stringsAsFactors = FALSE
  )
  hyp$result <- c(
    decide(r01$lo, r01$hi, 0.30, "below"),
    decide(h2a[["lo"]], h2a[["hi"]]), decide(h2b[["lo"]], h2b[["hi"]]), NA,
    if (anyNA(h3)) "not estimated" else decide(h3[1], h3[2]),
    if (anyNA(h4)) "not estimated" else decide(h4[1], h4[2]),
    decide(ci(kt_b)[1], ci(kt_b)[2], 0.7)
  )
  hyp$result[4] <- if (hyp$result[2] == "confirmed" && hyp$result[3] == "confirmed") "confirmed" else
    if (hyp$result[2] == "refuted" || hyp$result[3] == "refuted") "refuted" else "inconclusive"

  utils::write.csv(rates, file.path(out_dir, "change_rates.csv"), row.names = FALSE)
  utils::write.csv(hyp, file.path(out_dir, "hypotheses.csv"), row.names = FALSE)
  if (!is.null(gl)) utils::write.csv(gl, file.path(out_dir, "glmer.csv"), row.names = FALSE)
  if (!is.null(rf)) utils::write.csv(rf, file.path(out_dir, "rf_importance.csv"), row.names = FALSE)

  figs <- list(
    a = function() {
      k <- rates[rates$pair %in% c("C0->C1", "C1->C2", "C2t->C3"), ]
      y <- graphics::barplot(k$rate * 100, names.arg = c("strengths\nC0->C1", "thresholds\nC1->C2", "growth\nC2t->C3"),
                             ylim = c(0, max(k$hi * 100, 10) * 1.15), col = "#9ecae1", border = NA,
                             ylab = "% of Impact verdicts that change", main = "(a) What changes the verdict")
      graphics::arrows(y, k$lo * 100, y, k$hi * 100, angle = 90, code = 3, length = 0.05)
    },
    b = function() {
      d <- reg; d$bin <- cut(abs(d$net_a) / d$worsening_a, c(0, 0.1, 0.2, 0.4, 0.8, Inf), include.lowest = TRUE)
      r <- tapply(d$changed, d$bin, mean)
      graphics::barplot(r * 100, col = "#fdae6b", border = NA, ylab = "% changed C0->C1",
                        xlab = "closeness to neutralization in the raw network, |net| / worsening", main = "(b) Changes near the threshold")
    },
    c = function() {
      if (is.null(rf)) { graphics::plot.new(); return(invisible()) }
      rr <- rf[order(rf$importance), ]
      graphics::par(mar = c(4, 9, 3, 1))
      graphics::barplot(rr$importance, names.arg = rr$variable, horiz = TRUE, las = 1, col = "#a1d99b", border = NA,
                        xlab = "permutation importance", main = "(c) What explains a change (random forest)")
    },
    d = function() {
      graphics::hist(kt$tau, breaks = seq(-1, 1, 0.1), col = "#bcbddc", border = "white", xlab = "Kendall's tau, C0 vs C1",
                     main = sprintf("(d) Priority order: mean tau %.2f; top changes in %.0f%%", mean(kt$tau, na.rm = TRUE),
                                    100 * mean(kt$top_changed, na.rm = TRUE)))
      graphics::abline(v = 0.7, lty = 2)
    }
  )
  for (nm in names(figs)) {
    render_plot_png(figs[[nm]], file.path(out_dir, sprintf("fig_%s.png", nm)), width = 1000, height = 650)
    render_plot_svg(figs[[nm]], file.path(out_dir, sprintf("fig_%s.svg", nm)), width = 8, height = 5.2)
  }

  cnt <- o$counts
  fmt <- function(x) if (is.na(x)) "-" else sprintf("%.3f", x)
  lines <- c(
    "# Simulated DPSIR networks - results against the pre-registration", "",
    sprintf("Networks: %d generated, %d excluded (raw rho(B) >= 1), %d errors. Strength draws rejected: %d. Temporal runs diverged: %d.",
            nrow(cnt), sum(cnt$raw_excluded %in% TRUE), sum(!is.na(cnt$error %||% NA)), sum(cnt$draws_rejected, na.rm = TRUE),
            sum(cnt$temporal_diverged, na.rm = TRUE)), "",
    "## Hypotheses", "",
    "| Hypothesis | Statistic | Estimate | 95% CI | Result |", "|---|---|---|---|---|",
    sprintf("| %s | %s | %s | %s - %s | **%s** |", hyp$hypothesis, hyp$statistic, vapply(hyp$estimate, fmt, ""),
            vapply(hyp$lo, fmt, ""), vapply(hyp$hi, fmt, ""), hyp$result), "",
    "## Verdict change rates (3 levels)", "",
    "| Pair | n | Rate | 95% CI |", "|---|---|---|---|",
    sprintf("| %s | %d | %.3f | %.3f - %.3f |", rates$pair, rates$n, rates$rate, rates$lo, rates$hi), "",
    sprintf("Top-priority change C0->C1: %.1f%% of network x draw pairs with >= 3 worsened Impacts.", 100 * mean(kt$top_changed, na.rm = TRUE))
  )
  writeLines(lines, file.path(out_dir, "summary.md"))
  invisible(list(rates = rates, hypotheses = hyp, glmer = gl, rf = rf, kendall = kt))
}
