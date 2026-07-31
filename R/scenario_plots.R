# =====================================================
# SCENARIO CHARTS (trajectory / edge sensitivity)
# =====================================================
#
# Pure base-R plotting functions, no Shiny/UI dependency - shared between
# mod_responses.R's on-screen renderPlot()/downloadHandler()s and
# report.R's embedded report images, so the exact same drawing code
# produces the on-screen chart, the downloaded file, and the report
# figure, instead of three implementations that could drift apart.

draw_trajectory_plot <- function(traj, labels) {
  if (all(is.na(traj))) {
    plot.new()
    text(0.5, 0.5, "Trajectory could not be computed for this network.")
    return(invisible())
  }

  colors <- scales::hue_pal()(ncol(traj))

  matplot(
    seq_len(nrow(traj)), traj, type = "l", lty = 1, lwd = 2, col = colors,
    xlab = "Steps", ylab = "Effect on each factor",
    main = "How the effect changes as the response takes hold"
  )
  abline(h = 0, col = "grey70", lty = 2)
  legend("topright", legend = labels, col = colors, lty = 1, lwd = 2, cex = 0.8, bty = "n")
}

draw_sensitivity_plot <- function(sensitivity, top_n = 10) {
  if (all(sensitivity$influence < 1e-9)) {
    plot.new()
    text(0.5, 0.5, "No single edge's weight noticeably changes this scenario's effect.")
    return(invisible())
  }

  top <- head(sensitivity[order(sensitivity$influence), ], top_n) # ascending so barplot draws highest on top
  barplot(
    top$influence, names.arg = top$link, horiz = TRUE, las = 1,
    col = "#4E79A7", border = NA, cex.names = 0.8,
    xlab = "Change in total equilibrium effect (+10% weight)",
    main = "Which edges matter most for this scenario"
  )
}

# Revisao 1, Fase 6: one panel per discrete time window, so the user sees
# the network "evolve" instead of only reading numbers in a table. Every
# panel reuses the SAME layout (computed once, passed in) - only node
# color/size change between panels, so the sequence reads as fixed-frame
# animation rather than a layout reshuffling every window. Diverging
# color (not a "good/worse" judgement - that depends on what each factor
# means) shows sign: redder = increased from zero, bluer = decreased;
# size shows magnitude, both scaled to the largest |value| across every
# window shown so panels are comparable to each other.
draw_temporal_storyboard <- function(g, layout_df, hist_matrix) {
  idx <- match(igraph::V(g)$name, layout_df$id)
  layout_matrix <- as.matrix(layout_df[idx, c("x", "y")])

  n_panels <- nrow(hist_matrix)
  ncol_grid <- ceiling(sqrt(n_panels))
  nrow_grid <- ceiling(n_panels / ncol_grid)

  max_abs <- max(abs(hist_matrix), na.rm = TRUE)
  if (!is.finite(max_abs) || max_abs == 0) max_abs <- 1

  old_par <- graphics::par(mfrow = c(nrow_grid, ncol_grid), mar = c(1, 0.5, 2, 0.5))
  on.exit(graphics::par(old_par))

  node_order <- match(igraph::V(g)$name, colnames(hist_matrix))
  labels <- igraph::V(g)$label

  for (t in seq_len(n_panels) - 1) {
    x <- hist_matrix[t + 1, node_order]
    intensity <- pmin(abs(x) / max_abs, 1)
    node_color <- ifelse(
      x >= 0,
      grDevices::rgb(1, 1 - intensity, 1 - intensity),
      grDevices::rgb(1 - intensity, 1 - intensity, 1)
    )
    node_size <- 10 + 15 * intensity

    igraph::plot.igraph(
      g,
      layout = layout_matrix,
      # `g`'s own vertex "shape" attribute holds vis-network shape names
      # (square/triangle/dot/diamond/star, set by apply_schema_visual_mapping()
      # for the interactive JS graph widget) - igraph::plot.igraph() picks up
      # any vertex attribute of that name automatically, and none of those
      # names are valid igraph plotting shapes ("Bad vertex shape(s)" error,
      # found live testing this storyboard). Explicit vertex.shape overrides it.
      vertex.shape = "circle",
      vertex.color = node_color,
      vertex.size = node_size,
      vertex.label = labels,
      vertex.label.cex = 0.65,
      vertex.label.color = "black",
      vertex.label.dist = 1.3,
      edge.arrow.size = 0.3,
      edge.color = "grey60",
      main = paste("Window", t)
    )
  }
}

# Renders `draw_fn()` to a PNG/SVG file at `path` - used both by
# downloadHandler()s (which write straight to the download's `file`
# path) and by report.R's embedded <img> (rendered to a tempfile, then
# base64-encoded via jsonlite - already a dependency - instead of
# pulling in a new package like base64enc just for this).
render_plot_png <- function(draw_fn, path, width = 800, height = 450) {
  grDevices::png(path, width = width, height = height, res = 96)
  on.exit(grDevices::dev.off())
  draw_fn()
}

render_plot_svg <- function(draw_fn, path, width = 8.33, height = 4.69) {
  grDevices::svg(path, width = width, height = height)
  on.exit(grDevices::dev.off())
  draw_fn()
}

# Shared by report.R for both charts - render to a tempfile, read back as
# a base64 data URI, clean up. Kept here (not duplicated in report.R)
# since it's presentation plumbing, not report-assembly logic.
plot_to_data_uri <- function(draw_fn, width = 800, height = 450) {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  render_plot_png(draw_fn, tmp, width = width, height = height)
  paste0("data:image/png;base64,", jsonlite::base64_enc(readBin(tmp, "raw", file.info(tmp)$size)))
}
