# =====================================================
# Manuscript v7 - figures in print resolution (Revisao 3, E8)
# =====================================================
#
# One script for the six figures of manuscrito_v7/MANUSCRIPT_full_7.md, each
# as PNG (600 dpi), TIFF (600 dpi, LZW) and vector PDF, at Elsevier widths
# (single column 90 mm, 1.5 column 140 mm, full page 190 mm), sans-serif text
# at 7-9 pt in print, Okabe-Ito colours.
#   Fig. 1  workflow cycle (7 steps)              - drawn here (was fig_workflow.py)
#   Fig. 2  software: guided workflow + layers   - drawn here (was manuscrito_v6/fig1.py)
#   Fig. 3  port: (a) network, (b) temporal, scenario 4 (runoff treatment late)
#   Fig. 4  Kenya: (a) network, (b) temporal, scenario 4 over 30 years
#   Fig. 5  Sri Lanka: (a) network, (b) out-of-sample test of the effort
#   Fig. 6  simulated networks (a)-(d), read from analysis/sim_networks/out (never rerun)
# Figures 1 and 2 were matplotlib scripts written elsewhere; they are redrawn
# in base R so that one script, on any machine with R, makes every figure.
#
# Run from the repository root:
#   Rscript data-raw/manuscript_figures.R [out_dir]   (default manuscrito_v7/fig_hr)

MS_PT <- 8                        # device point size: cex 1 = 8 pt in print
MS_DPI <- 600
MS_WIDTH <- c(single = 90, onehalf = 140, full = 190)
OI <- c(black = "#000000", orange = "#E69F00", sky = "#56B4E9", green = "#009E73", yellow = "#F0E442",
        blue = "#0072B2", vermilion = "#D55E00", purple = "#CC79A7")
INK <- "#1f2933"
MUTED <- "#3e4c59"   # secondary text: dark enough to read in print (no light grey text)
EDGE_BOX <- "#7b8794"
SIGN_COL <- c(positive = OI[["green"]], negative = OI[["vermilion"]])
VERDICT_COL <- c("Improved beyond neutral" = OI[["green"]], "Neutralized" = OI[["green"]],
                 "Neutralized (relative)" = OI[["sky"]], "Partial" = OI[["orange"]],
                 "Failure/worsened" = OI[["vermilion"]], "Not affected" = "#ffffff", "—" = "#ffffff")

# Writes `draw()` to <out_dir>/<stem>.png / .tif / .pdf at width_mm x height_mm.
ms_save <- function(stem, draw, width_mm, height_mm, out_dir) {
  w <- width_mm / 25.4; h <- height_mm / 25.4
  files <- file.path(out_dir, paste0(stem, c(".png", ".tif", ".pdf")))
  grDevices::png(files[1], width = w, height = h, units = "in", res = MS_DPI, pointsize = MS_PT, type = "cairo", bg = "white")
  tryCatch(draw(), finally = grDevices::dev.off())
  grDevices::tiff(files[2], width = w, height = h, units = "in", res = MS_DPI, pointsize = MS_PT, type = "cairo",
                  compression = "lzw", bg = "white")
  tryCatch(draw(), finally = grDevices::dev.off())
  grDevices::cairo_pdf(files[3], width = w, height = h, pointsize = MS_PT, bg = "white")
  tryCatch(draw(), finally = grDevices::dev.off())
  invisible(files)
}

# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------

# Rounded rectangle in user coordinates (needs asp = 1 for round corners).
ms_rrect <- function(x0, y0, x1, y1, r = 0.3, col = "white", border = EDGE_BOX, lwd = 0.8, lty = 1) {
  r <- min(r, (x1 - x0) / 2, (y1 - y0) / 2)
  arc <- function(cx, cy, a0, a1) { t <- seq(a0, a1, length.out = 10); cbind(cx + r * cos(t), cy + r * sin(t)) }
  p <- rbind(arc(x1 - r, y1 - r, 0, pi / 2), arc(x0 + r, y1 - r, pi / 2, pi),
             arc(x0 + r, y0 + r, pi, 3 * pi / 2), arc(x1 - r, y0 + r, 3 * pi / 2, 2 * pi))
  graphics::polygon(p[, 1], p[, 2], col = col, border = border, lwd = lwd, lty = lty)
}

# Panel letter, bold, at the top-left corner of the current figure region.
ms_letter <- function(letter) {
  op <- graphics::par(mar = c(0, 0, 0, 0))
  on.exit(graphics::par(op))
  graphics::plot.new()
  graphics::text(0, 1, sprintf("(%s)", letter), adj = c(0, 1), font = 2, cex = 1.125, col = INK, xpd = NA)
}

# Region of the device (fractions) for par(fig = ...): x0, x1, y0, y1.
ms_region <- function(x0, x1, y0, y1) c(x0, x1, y0, y1)

# ---------------------------------------------------------------------------
# Fig. 1 - workflow cycle
# ---------------------------------------------------------------------------
fig1_workflow <- function() {
  fill <- c("#dbe7f3", "#dbe7f3", "#e3f1e7", "#e3f1e7", "#f6e3c6", "#f6e3c6", "#f3e4ea")
  steps <- list(
    c("1  Frame the question", "Which Impacts, responses,\ntime unit and values?", "defines 'sufficient'"),
    c("2  Draw structure & signs", "How does the problem work,\nand on what evidence?", "source and evidence per link"),
    c("3  Read the first run", "What does the structure\nalone already decide?", "reach, gaps, tight verdicts"),
    c("4  Build alternatives", "What if a contested\nlink is wrong?", "variants; weak links absent"),
    c("5  Search for data", "Where would data change\nthe decision?", "thresholds; links behind\ntight verdicts"),
    c("6  Parameterize & test", "Does the network reproduce\nwhat was observed?", "out of sample; rival\nexplanations"),
    c("7  Decide, monitor, return", "Which response, how strong,\nwhich Impact first, when?", "limits become the next\nmonitoring programme"))
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1.1)
  graphics::plot.new()
  graphics::plot.window(xlim = c(-10.6, 10.6), ylim = c(-8.7, 8.7), asp = 1)
  rx <- 7.6; ry <- 6.35
  n <- length(steps)
  ang <- (90 - (seq_len(n) - 1) * 360 / n) * pi / 180
  cx <- rx * cos(ang); cy <- ry * sin(ang)
  bw <- 5.3; bh <- 3.0
  # Arrows along the ellipse, between the boxes: the arc from one box to
  # the next, trimmed where it runs under either box.
  in_box <- function(px, py, k, m = 0.12) abs(px - cx[k]) < bw / 2 + m & abs(py - cy[k]) < bh / 2 + m
  arcs <- lapply(seq_len(n), function(k) {
    k2 <- (k %% n) + 1
    a2 <- ang[k2]; if (a2 > ang[k]) a2 <- a2 - 2 * pi
    t <- seq(ang[k], a2, length.out = 200)
    x <- rx * cos(t); y <- ry * sin(t)
    keep <- !in_box(x, y, k) & !in_box(x, y, k2)
    list(x = x[keep], y = y[keep])
  })
  # Centre: every limitation becomes a monitoring or data need.
  tt <- seq(0, 2 * pi, length.out = 200)
  graphics::polygon(3.25 * cos(tt), 3.25 * sin(tt), col = "#fbfbfb", border = EDGE_BOX, lty = 2, lwd = 0.8)
  graphics::text(0, 1.55, "Every limitation found", font = 2, cex = 1.05, col = INK)
  graphics::text(0, 0.05, "a link without evidence\nan Impact no response reaches\na verdict close to neutralization\na threshold crossed by accumulation",
                 cex = 0.95, col = INK)
  graphics::text(0, -1.5, "becomes a monitoring\nor data need", font = 2, cex = 0.95, col = INK)
  for (a in arcs) {
    m <- length(a$x)
    if (m < 4) next
    graphics::lines(a$x[-m], a$y[-m], col = MUTED, lwd = 1.1)
    graphics::arrows(a$x[m - 3], a$y[m - 3], a$x[m], a$y[m], length = 0.07, angle = 22, col = MUTED, lwd = 1.1)
  }
  for (k in seq_len(n)) {
    ms_rrect(cx[k] - bw / 2, cy[k] - bh / 2, cx[k] + bw / 2, cy[k] + bh / 2, r = 0.35, col = fill[k])
    graphics::text(cx[k], cy[k] + bh / 2 - 0.45, steps[[k]][1], font = 2, cex = 1.05, col = INK)
    graphics::text(cx[k], cy[k] + 0.05, steps[[k]][2], cex = 0.95, col = INK)
    graphics::text(cx[k], cy[k] - bh / 2 + 0.55, steps[[k]][3], font = 3, cex = 0.9, col = MUTED)
  }
}

# ---------------------------------------------------------------------------
# Fig. 2 - software: guided workflow and layered architecture
# ---------------------------------------------------------------------------
fig2_architecture <- function() {
  C_STEP <- "#dbe7f3"; C_EXPL <- "#f6e3c6"; C_UI <- "#e4ecf7"; C_CORE <- "#e3f1e7"; C_PERS <- "#f3e4ea"
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1.1)
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 100), ylim = c(0, 81), asp = 1, xaxs = "i", yaxs = "i")
  box_t <- function(x, y, w, h, title, body, fill, body_family = "sans", body_col = MUTED) {
    ms_rrect(x, y, x + w, y + h, r = 1.1, col = fill)
    graphics::text(x + w / 2, y + h - 2.4, title, font = 2, cex = 1.0, col = INK)
    graphics::text(x + w / 2, y + (h - 4) / 2, body, cex = 0.9, col = body_col, family = body_family)
  }
  arrow <- function(x1, y1, x2, y2) graphics::arrows(x1, y1, x2, y2, length = 0.05, angle = 22, col = MUTED, lwd = 0.9)

  graphics::text(0.5, 79.3, "(a) Guided workflow", adj = c(0, 0.5), font = 2, cex = 1.125, col = INK)
  steps <- list(c("1  Start", "new project,\nCSV import, load\nor merge\nsavepoints"),
                c("2  Model", "levels, order,\nroles; custom\nlevels (e.g.\nsub-drivers)"),
                c("3  Nodes", "attributes by\ncategory;\nthreshold on\nStates, value v\non Impacts"),
                c("4  Edges", "sign; strength\nas class, β or\nr² with n;\nband; evidence"),
                c("5  Review", "blocks if\nρ(B) ≥ 1; warns\nif Σβ² ≥ 1\nat a factor"),
                c("6  Explore", "five analysis\ntabs (below)"))
  w <- 15.0; h <- 17; gap <- 1.9; y0 <- 59.6
  for (i in seq_along(steps)) {
    x <- 0.5 + (i - 1) * (w + gap)
    box_t(x, y0, w, h, steps[[i]][1], steps[[i]][2], if (i < 6) C_STEP else C_EXPL)
    if (i < 6) arrow(x + w + 0.2, y0 + h / 2, x + w + gap - 0.2, y0 + h / 2)
  }
  tabs <- list(c("Graph", "layouts, filters,\npathways,\nsnapshots"),
               c("Scenarios", "sufficiency,\nconfidence, triggers,\npriority, reach,\ntemporal simulation"),
               c("Interpretation", "plain-language\nstatus, tight\nverdicts, data needs,\nscenario comparison"),
               c("Metrics", "centralities, DPSIR\ndescriptors,\nstrength and\nconfidence"),
               c("Report", "self-contained\nHTML (seed,\nsession info,\nreferences)"))
  tw <- 18.9; th <- 17; ty <- 39.0
  xe <- 0.5 + 5 * (w + gap) + w / 2
  graphics::segments(xe, y0, xe, ty + th + 1.6, col = MUTED, lwd = 0.8, lty = 3)
  graphics::segments(10, ty + th + 1.6, xe, ty + th + 1.6, col = MUTED, lwd = 0.8, lty = 3)
  for (i in seq_along(tabs)) box_t(0.5 + (i - 1) * (tw + 1.35), ty, tw, th, tabs[[i]][1], tabs[[i]][2], C_EXPL)

  graphics::text(0.5, 36.0, "(b) Layered architecture", adj = c(0, 0.5), font = 2, cex = 1.125, col = INK)
  ms_rrect(0.5, 27.6, 99.5, 33.3, r = 1.1, col = C_UI)
  graphics::text(50, 30.45, "Shiny UI modules:  mod_wizard · mod_data (Start–Review) · mod_graph · mod_responses (Scenarios, Interpretation)\n· mod_metrics · mod_report",
                 cex = 0.9, col = INK)
  arrow(50, 27.5, 50, 24.9)
  groups <- list(c("Structure", "schema.R · validate.R\nstructural.R", "roles, rules, β and\nbands, ρ(B) check"),
                 c("Static reading", "sufficiency.R\ntriggers.R · relevance.R\nreach.R · data_needs.R", "total effects,\nconfidence, gates,\npriority, data needs"),
                 c("Time", "temporal.R", "windows, modes,\ngrowth, stop rule"),
                 c("Reading", "interpretation.R\nmetrics.R · pathways.R\ngraph.R", "status rules,\nmetrics, paths"))
  gw <- 24.0; gy <- 9.0; gh <- 15.6
  graphics::text(99.5, gy + gh + 1.4, "R scientific core (UI-independent, tested with testthat)", adj = c(1, 0.5), font = 3, cex = 0.875, col = MUTED)
  for (i in seq_along(groups)) {
    x <- 0.5 + (i - 1) * (gw + 1.0)
    ms_rrect(x, gy, x + gw, gy + gh, r = 1.1, col = C_CORE)
    graphics::text(x + gw / 2, gy + gh - 1.8, groups[[i]][1], font = 2, cex = 1.0, col = INK)
    graphics::text(x + gw / 2, gy + gh / 2 + 1.6, groups[[i]][2], cex = 0.875, col = INK, family = "mono")
    graphics::text(x + gw / 2, gy + 3.2, groups[[i]][3], cex = 0.875, col = MUTED)
  }
  arrow(50, gy - 0.1, 50, gy - 1.6)
  pers <- list(c("Savepoint (.idpsir.json)", "network, per-link evidence, scenario, saved\nscenarios, temporal settings (io.R)"),
               c("HTML report", "results, seed, session info,\nlink references (report.R)"),
               c("Deployment", "local R/Shiny or browser-only\nWebAssembly build (shinylive); CI"))
  pw <- 32.33; ph <- 7.0
  for (i in seq_along(pers)) {
    x <- 0.5 + (i - 1) * (pw + 1.0)
    ms_rrect(x, 0.3, x + pw, 0.3 + ph, r = 1.1, col = C_PERS)
    graphics::text(x + pw / 2, 0.3 + ph - 1.7, pers[[i]][1], font = 2, cex = 1.0, col = INK)
    graphics::text(x + pw / 2, 0.3 + 2.2, pers[[i]][2], cex = 0.875, col = MUTED)
  }
}

# ---------------------------------------------------------------------------
# Networks (Figs. 3a, 4a, 5a)
# ---------------------------------------------------------------------------
# Columns by DPSIR level (schema order); in each column the nodes are stacked
# with room for their wrapped label, so the vertical unit is one text line of
# the labels (MS_LINE_MM in print) and the panel height follows the content.
MS_LINE_MM <- 3.0        # one label line at 7 pt, in mm
MS_NODE_LINES <- 1.5     # vertical room of a node marker, in label lines
MS_PAD_LINES <- 0.9      # gap below each label

ms_network_layout <- function(g, schema, wrap = 22) {
  cats <- igraph::V(g)$dpsir_category
  cat_order <- schema$name[order(schema$order)]
  labs <- vapply(igraph::V(g)$label, function(s) paste(strwrap(s, wrap), collapse = "\n"), "")
  nl <- lengths(regmatches(labs, gregexpr("\n", labs))) + 1
  block <- MS_NODE_LINES + nl + MS_PAD_LINES
  col_h <- tapply(block, factor(cats, levels = cat_order), sum)
  col_h[is.na(col_h)] <- 0
  H <- max(col_h)
  x <- match(cats, cat_order)
  y <- numeric(length(cats))
  for (cc in cat_order) {
    k <- which(cats == cc)
    if (!length(k)) next
    top <- -(H - col_h[[cc]]) / 2
    cum <- c(0, cumsum(block[k]))[seq_along(k)]
    y[k] <- top - cum - MS_NODE_LINES / 2
  }
  list(x = x, y = y, labs = labs, H = H, n_cols = length(cat_order), cat_order = cat_order,
       cols = setNames(schema$color, schema$name), cats = cats)
}

ms_network_panel <- function(g, lay, node_cex = 2.1, label_cex = 0.875) {
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1)
  graphics::plot.new()
  graphics::plot.window(xlim = c(0.45, lay$n_cols + 0.55), ylim = c(-lay$H, 0), xaxs = "i", yaxs = "i")
  x <- lay$x; y <- lay$y
  el <- igraph::as_edgelist(g, names = FALSE)
  w <- abs(igraph::E(g)$weight)
  sgn <- igraph::E(g)$interaction_type
  rad_x <- graphics::strwidth("O", cex = node_cex) * 0.5
  rad_y <- graphics::strheight("O", cex = node_cex) * 0.62
  for (e in seq_len(nrow(el))) {
    a <- el[e, 1]; b <- el[e, 2]
    x0 <- x[a]; y0 <- y[a]; x1 <- x[b]; y1 <- y[b]
    back <- x1 <= x0
    # Quadratic Bezier; links going back (from Responses) bow upwards more,
    # so they stay clear of the forward links.
    mx <- (x0 + x1) / 2; my <- (y0 + y1) / 2
    cxp <- mx; cyp <- my + if (back) 0.10 * lay$H * (0.4 + abs(x1 - x0) / lay$n_cols) else 0.05 * (x1 - x0) * lay$H / 10
    t <- seq(0, 1, length.out = 60)
    bx <- (1 - t)^2 * x0 + 2 * (1 - t) * t * cxp + t^2 * x1
    by <- (1 - t)^2 * y0 + 2 * (1 - t) * t * cyp + t^2 * y1
    inside <- function(px, py, cx, cy) ((px - cx) / rad_x)^2 + ((py - cy) / rad_y)^2 < 1
    keep <- !inside(bx, by, x0, y0) & !inside(bx, by, x1, y1)
    bx <- bx[keep]; by <- by[keep]
    if (length(bx) < 3) next
    col <- grDevices::adjustcolor(SIGN_COL[[sgn[e]]], 0.9)
    lwd <- 0.5 + 1.8 * w[e]
    m <- length(bx)
    graphics::lines(bx[-m], by[-m], col = col, lwd = lwd)
    graphics::arrows(bx[m - 1], by[m - 1], bx[m], by[m], length = 0.045, angle = 25, col = col, lwd = lwd)
  }
  # Labels on a white ground, so the links never cross the text.
  ly <- y - MS_NODE_LINES / 2 - 0.05
  lw <- graphics::strwidth(lay$labs, cex = label_cex)
  lh <- graphics::strheight(lay$labs, cex = label_cex)
  graphics::rect(x - lw / 2 - 0.02, ly - lh - 0.25, x + lw / 2 + 0.02, ly + 0.1,
                 col = grDevices::adjustcolor("white", 0.9), border = NA)
  graphics::points(x, y, pch = 21, bg = lay$cols[lay$cats], col = INK, cex = node_cex, lwd = 0.6)
  graphics::text(x, ly, lay$labs, adj = c(0.5, 1), cex = label_cex, col = INK)
}

ms_network_legend <- function(schema) {
  cat_order <- schema$name[order(schema$order)]
  cols <- setNames(schema$color, schema$name)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::legend("left", horiz = TRUE, bty = "n", legend = cat_order, pt.bg = cols[cat_order], pch = 21,
                   pt.cex = 1.5, col = INK, cex = 0.9, x.intersp = 0.8, text.col = INK, text.width = 0.09, inset = 0.01)
  graphics::legend("right", horiz = TRUE, bty = "n", legend = c("increases its target", "decreases its target"),
                   col = SIGN_COL[c("positive", "negative")], lwd = 2, cex = 0.9, x.intersp = 0.6, seg.len = 1.6, text.col = INK, inset = 0.01)
}

# ---------------------------------------------------------------------------
# Temporal panels (Figs. 3b, 4b) - same data as the app's chart
# (format_temporal_table()), one small panel per Impact, one shared legend.
# ---------------------------------------------------------------------------
ms_temporal_panels <- function(tb, region, xlab, ncol = NULL, legend_frac = 0.09) {
  impacts <- unique(tb$node)
  n <- length(impacts)
  ncol <- ncol %||% n
  nrow <- ceiling(n / ncol)
  x0 <- region[1]; x1 <- region[2]; y0 <- region[3]; y1 <- region[4]
  leg_h <- (y1 - y0) * legend_frac
  cw <- (x1 - x0) / ncol; ch <- (y1 - y0 - leg_h) / nrow
  for (i in seq_len(n)) {
    r <- (i - 1) %/% ncol; c <- (i - 1) %% ncol
    graphics::par(fig = c(x0 + c * cw, x0 + (c + 1) * cw, y1 - (r + 1) * ch, y1 - r * ch), new = TRUE,
                  mar = c(3.0, if (c == 0) 3.8 else 2.6, 2.4, 0.6), mgp = c(1.8, 0.45, 0), tcl = -0.25)
    sub <- tb[tb$node == impacts[i], ]
    sub <- sub[order(sub$window), ]
    yr <- range(c(sub$baseline_impact, sub$net_impact, 0), na.rm = TRUE)
    pad <- diff(yr) * 0.08; if (!is.finite(pad) || pad == 0) pad <- 0.1
    graphics::plot(sub$window, sub$net_impact, type = "n", ylim = c(yr[1] - pad, yr[2] + pad), xlab = xlab,
                   ylab = if (c == 0) "Change (SD of the Impact)" else "", cex.axis = 0.875, cex.lab = 0.9,
                   col.axis = INK, col.lab = INK, bty = "l", las = 1)
    u <- graphics::par("usr")
    graphics::rect(u[1], u[3], u[2], min(0, u[4]), col = "#e3f1e7", border = NA)
    graphics::abline(h = 0, col = MUTED, lwd = 0.8)
    graphics::box(bty = "l", col = INK)
    graphics::lines(sub$window, sub$baseline_impact, lty = 2, col = MUTED, lwd = 1.2)
    graphics::lines(sub$window, sub$net_impact, col = INK, lwd = 1.2)
    graphics::points(sub$window, sub$net_impact, pch = 21, bg = unname(VERDICT_COL[sub$verdict]), col = INK, cex = 0.8, lwd = 0.5)
    graphics::mtext(paste(strwrap(impacts[i], 30), collapse = "\n"), side = 3, line = 0.3, cex = 0.9, font = 2, col = INK)
  }
  graphics::par(fig = c(x0, x1, y0, y0 + leg_h), new = TRUE, mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::legend("center", horiz = TRUE, bty = "n", cex = 0.875, x.intersp = 0.4, seg.len = 1.4, text.col = INK,
                   text.width = NA,
                   legend = c("pressure alone", "with responses:", "neutralized", "within tolerance", "partial",
                              "failure (no gain)", "neutralized zone"),
                   lty = c(2, 1, NA, NA, NA, NA, NA), lwd = c(1.2, 1.2, NA, NA, NA, NA, NA),
                   col = c(MUTED, INK, INK, INK, INK, INK, "#c9e4d1"),
                   pch = c(NA, NA, 21, 21, 21, 21, 22),
                   pt.bg = c(NA, NA, OI[["green"]], OI[["sky"]], OI[["orange"]], OI[["vermilion"]], "#e3f1e7"),
                   pt.cex = c(1, 1, 1.1, 1.1, 1.1, 1.1, 2.0))
}

# A case figure: network (a) with its legend, then panel (b). Heights in mm:
# the network's from its content, (b) as given. Returns the drawing function
# and the total height.
ms_case_figure <- function(g, schema, lay, draw_b, b_mm, width_mm = 190, node_cex = 2.1) {
  letter_mm <- 5; net_mm <- lay$H * MS_LINE_MM; legend_mm <- 7; gap_mm <- 3
  total <- letter_mm + net_mm + legend_mm + gap_mm + letter_mm + b_mm
  f <- function(mm) mm / total
  draw <- function() {
    top <- 1
    graphics::par(fig = c(0, 1, top - f(letter_mm), top), mar = c(0, 0, 0, 0))
    ms_letter("a")   # first drawing on the page: no new = TRUE
    top <- top - f(letter_mm)
    graphics::par(fig = c(0, 1, top - f(net_mm), top), new = TRUE)
    ms_network_panel(g, lay, node_cex = node_cex)
    top <- top - f(net_mm)
    graphics::par(fig = c(0, 1, top - f(legend_mm), top), new = TRUE)
    ms_network_legend(schema)
    top <- top - f(legend_mm) - f(gap_mm)
    graphics::par(fig = c(0, 1, top - f(letter_mm), top), new = TRUE)
    ms_letter("b")
    top <- top - f(letter_mm)
    draw_b(c(0, 1, 0, top))
  }
  list(draw = draw, height_mm = round(total))
}

# Fig. 3 - port; (b) scenario 4, runoff treatment starting late.
fig3_port <- function(root = ".") {
  x <- ms_load("example_port", root)
  d <- x$sp$saved_scenarios[[4]]
  tr <- simulate_temporal_pair(x$g, x$pv(d$pressure_strengths), x$pv(d$strengths), windows = 12, stop_rule = "fixed",
                               mode_D = "window", mode_R = "window", schedule = d$temporal_schedule)
  tb <- format_temporal_table(x$g, tr)
  lay <- ms_network_layout(x$g, x$sp$schema, wrap = 22)
  ms_case_figure(x$g, x$sp$schema, lay, function(region) ms_temporal_panels(tb, region, "Window (season)", ncol = 4), b_mm = 62)
}

# Fig. 4 - Kenya; (b) scenario 4, all measures fully complied, 30 years.
fig4_kenya <- function(root = ".") {
  x <- ms_load("example_mangi", root)
  d <- x$sp$saved_scenarios[[4]]
  tr <- simulate_temporal_pair(x$g, build_press_vector(x$g, d$pressure_active, d$pressure_strengths / 100),
                               build_press_vector(x$g, d$active, d$strengths / 100), windows = 30, stop_rule = "fixed")
  tb <- format_temporal_table(x$g, tr)
  lay <- ms_network_layout(x$g, x$sp$schema, wrap = 22)
  ms_case_figure(x$g, x$sp$schema, lay, function(region) ms_temporal_panels(tb, region, "Window (year)", ncol = 3), b_mm = 62,
                 node_cex = 1.9)
}

# Fig. 5 - Sri Lanka; (b) out-of-sample test of the effort.
ms_validation_panel <- function(region, root = ".") {
  f <- utils::read.csv(file.path(root, "analysis/validation_srilanka/out/forecast.csv"), stringsAsFactors = FALSE)
  m <- utils::read.csv(file.path(root, "analysis/validation_srilanka/out/metrics.csv"), stringsAsFactors = FALSE)
  obs <- setNames(f$observed, f$year)
  test <- f$period == "test"
  yt <- f$year[test]
  persist <- rep(obs[["2014"]], length(yt))
  fit_yrs <- 2006:2014
  lm_t <- stats::lm(y ~ x, data.frame(x = fit_yrs, y = obs[as.character(fit_yrs)]))
  trend <- stats::predict(lm_t, data.frame(x = yt))
  graphics::par(fig = region, new = TRUE, mar = c(3.4, 4.8, 1.6, 0.8), mgp = c(2.0, 0.5, 0), tcl = -0.25)
  graphics::plot(f$year, f$observed, type = "n", ylim = c(0, 22000), xlab = "Year", ylab = "",
                 las = 1, bty = "l", cex.axis = 0.875, cex.lab = 0.9, col.axis = INK, col.lab = INK)
  graphics::mtext("Fishing effort (thousand kW-days)", side = 2, line = 3.4, cex = 0.9, col = INK)
  graphics::rect(2014.5, -1e6, 2021.5, 1e6, col = "#eef0f2", border = NA)
  graphics::text(2009.5, 21300, "calibration (2006-2014)", cex = 0.875, col = INK)
  graphics::text(2018, 14300, "test (2015-2021)", cex = 0.875, col = INK)
  graphics::polygon(c(yt, rev(yt)), c(f$band_05[test], rev(f$band_95[test])), col = grDevices::adjustcolor(OI[["blue"]], 0.22), border = NA)
  graphics::lines(f$year, f$simulated, col = OI[["blue"]], lwd = 1.8)
  graphics::lines(yt, persist, col = INK, lty = 3, lwd = 1.4)
  graphics::lines(yt, trend, col = OI[["vermilion"]], lty = 2, lwd = 1.4)
  graphics::points(f$year, f$observed, pch = 16, col = INK, cex = 0.8)
  graphics::box(bty = "l", col = INK)
  graphics::legend(2013.2, 12500, bty = "n", cex = 0.875, text.col = INK, seg.len = 1.8, yjust = 1,
                   legend = c("observed effort", "network: fitted 2006-2014, then predicted", "90% prediction band",
                              sprintf("persistence of 2014 (RMSE %.0f)", m$rmse[2]), sprintf("trend 2006-2014 (RMSE %.0f)", m$rmse[3])),
                   col = c(INK, OI[["blue"]], grDevices::adjustcolor(OI[["blue"]], 0.4), INK, OI[["vermilion"]]),
                   pch = c(16, NA, 15, NA, NA), lty = c(NA, 1, NA, 3, 2), lwd = c(NA, 1.8, NA, 1.4, 1.4), pt.cex = c(0.8, 1, 1.8, 1, 1))
  graphics::mtext(sprintf("Network, 2015-2021: RMSE %.0f, bias %+.0f; the band covers %.0f%% of the years",
                          m$rmse[1], m$bias[1], 100 * m$band_coverage_90[1]), side = 3, line = 0.3, cex = 0.875, col = INK)
}

fig5_srilanka <- function(root = ".") {
  x <- ms_load("example_gnanapragasam", root)
  lay <- ms_network_layout(x$g, x$sp$schema, wrap = 22)
  ms_case_figure(x$g, x$sp$schema, lay, function(region) ms_validation_panel(region, root), b_mm = 75)
}

# ---------------------------------------------------------------------------
# Fig. 6 - simulated networks, read from analysis/sim_networks/out
# ---------------------------------------------------------------------------
fig6_data <- function(root = ".") {
  out <- file.path(root, "analysis/sim_networks/out")
  o <- load_sim_outputs(out)
  rates <- utils::read.csv(file.path(out, "change_rates.csv"), stringsAsFactors = FALSE)
  rf <- utils::read.csv(file.path(out, "rf_importance.csv"), stringsAsFactors = FALSE)
  reg <- regression_data(o$results, o$networks)
  kt <- kendall_c0_c1(o$results)
  bins <- cut(abs(reg$net_a) / reg$worsening_a, c(0, 0.1, 0.2, 0.4, 0.8, Inf), include.lowest = TRUE)
  near <- data.frame(bin = levels(bins), rate = as.numeric(tapply(reg$changed, bins, mean)),
                     n = as.integer(table(bins)), stringsAsFactors = FALSE)
  list(rates = rates, rf = rf, near = near, kt = kt)
}

fig6_simulated <- function(dat) {
  function() {
    graphics::par(mfrow = c(2, 2), mar = c(3.6, 4.2, 2.2, 0.8), mgp = c(2.3, 0.5, 0), tcl = -0.25, las = 1,
                  col.axis = INK, col.lab = INK, cex.axis = 0.875, cex.lab = 0.9)
    # (a)
    k <- dat$rates[match(c("C0->C1", "C1->C2", "C2t->C3"), dat$rates$pair), ]
    yb <- graphics::barplot(k$rate * 100, names.arg = c("Link strengths", "State thresholds", "Growth trends"),
                            ylim = c(0, 25), col = OI[["blue"]], border = NA, ylab = "Verdicts that change (%)", cex.names = 0.875)
    graphics::arrows(yb, k$lo * 100, yb, k$hi * 100, angle = 90, code = 3, length = 0.04, col = INK, lwd = 1)
    graphics::text(yb, k$hi * 100, sprintf("%.1f%%", k$rate * 100), pos = 3, cex = 0.875, col = INK, offset = 0.3)
    graphics::mtext("(a) What changes the verdict", side = 3, line = 0.6, adj = 0, font = 2, cex = 1.0, col = INK)
    # (b)
    nb <- dat$near
    yb <- graphics::barplot(nb$rate * 100, names.arg = c("< 0.1", "0.1-0.2", "0.2-0.4", "0.4-0.8", "> 0.8"),
                            ylim = c(0, 55), col = OI[["orange"]], border = NA, ylab = "Verdicts changed by strengths (%)",
                            xlab = "Closeness to neutralization, |net| / worsening", cex.names = 0.875)
    graphics::text(yb, nb$rate * 100, sprintf("%.0f%%", nb$rate * 100), pos = 3, cex = 0.875, col = INK, offset = 0.3)
    graphics::mtext("(b) Changes near neutralization", side = 3, line = 0.6, adj = 0, font = 2, cex = 1.0, col = INK)
    # (c)
    nice <- c(near = "closeness to neutralization", rho_B = "loop amplification ρ(B)", has_cycle = "has a loop",
              density = "density", n_nodes = "number of factors", mean_path_DI = "mean D→I path length",
              n_thresholds = "number of thresholds", n_growing = "number of growing Drivers",
              draw_mode = "strength draw mode", share_reached = "share of Impacts reached")
    rr <- dat$rf[order(dat$rf$importance), ]
    graphics::par(mar = c(3.6, 10.5, 2.2, 0.8))
    graphics::barplot(rr$importance, names.arg = nice[rr$variable], horiz = TRUE, col = OI[["green"]], border = NA,
                      xlab = "Permutation importance", cex.names = 0.875)
    graphics::mtext("(c) What explains a change", side = 3, line = 0.6, adj = 0, font = 2, cex = 1.0, col = INK,
                    at = graphics::grconvertX(0.02, "nfc", "user"))
    # (d)
    graphics::par(mar = c(3.6, 4.2, 2.2, 0.8))
    tau <- dat$kt$tau[!is.na(dat$kt$tau)]
    h <- graphics::hist(tau, breaks = seq(-1, 1, 0.1), plot = FALSE)
    graphics::plot(h, col = OI[["purple"]], border = "white", main = "", xlab = "Kendall τ, bare structure vs drawn strengths",
                   ylab = "Network × draw pairs", xlim = c(-1, 1))
    graphics::abline(v = 0.7, lty = 2, col = INK, lwd = 1.2)
    graphics::text(0.7, max(h$counts) * 0.97, "pre-registered 0.7", pos = 2, cex = 0.875, col = INK)
    graphics::mtext(sprintf("(d) Priority order: mean τ %.2f; top changes in %.0f%%", mean(tau),
                            100 * mean(dat$kt$top_changed, na.rm = TRUE)), side = 3, line = 0.6, adj = 0, font = 2, cex = 1.0, col = INK)
  }
}

# ---------------------------------------------------------------------------
# All figures
# ---------------------------------------------------------------------------
MS_FIGURES <- data.frame(
  stem = c("fig1_workflow", "fig2_architecture", "fig3_port", "fig4_kenya", "fig5_srilanka", "fig6_simulated"),
  width_mm = 190,
  height_mm = c(156, 154, NA, NA, NA, 150),   # NA: from the network's content
  content = c("Workflow cycle (7 steps)", "Software: guided workflow and layered architecture",
              "Port: (a) network; (b) temporal, scenario 4 (runoff treatment late)",
              "Kenya: (a) network; (b) temporal, scenario 4, 30 years",
              "Sri Lanka: (a) network; (b) out-of-sample test of the effort",
              "Simulated networks (a)-(d)"),
  stringsAsFactors = FALSE)

manuscript_figures <- function(root = ".", out_dir = "manuscrito_v7/fig_hr", which = MS_FIGURES$stem) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  draws <- list(
    fig1_workflow = function() list(draw = fig1_workflow),
    fig2_architecture = function() list(draw = fig2_architecture),
    fig3_port = function() fig3_port(root),
    fig4_kenya = function() fig4_kenya(root),
    fig5_srilanka = function() fig5_srilanka(root),
    fig6_simulated = function() list(draw = fig6_simulated(fig6_data(root))))
  done <- MS_FIGURES
  for (s in which) {
    k <- which(MS_FIGURES$stem == s)
    d <- draws[[s]]()
    h <- if (is.na(MS_FIGURES$height_mm[k])) d$height_mm else MS_FIGURES$height_mm[k]
    done$height_mm[k] <- h
    ms_save(s, d$draw, MS_FIGURES$width_mm[k], h, out_dir)
    message(sprintf("Written: %s/%s.{png,tif,pdf} (%d x %d mm)", out_dir, s, MS_FIGURES$width_mm[k], h))
  }
  invisible(done[done$stem %in% which, ])
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  out_dir <- if (length(args) >= 1 && !startsWith(args[1], "--")) args[1] else "manuscrito_v7/fig_hr"
  only <- sub("^--only=", "", grep("^--only=", args, value = TRUE))
  setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
  suppressMessages({ library(shiny); source("R/modules/mod_responses.R") })
  source("data-raw/manuscript_build.R")
  source("analysis/sim_networks/analyze.R")
  manuscript_figures(out_dir = out_dir, which = if (length(only)) strsplit(only, ",")[[1]] else MS_FIGURES$stem)
}
