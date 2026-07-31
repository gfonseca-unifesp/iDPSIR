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
# window shown so panels are comparable to each other. `label_cex` is
# exposed (not hardcoded) so the on-screen slider in mod_responses.R can
# make node labels readable regardless of how many panels end up in the
# grid - a dense grid (many windows) needs smaller labels than a 2x2 one.
# A narrow extra column renders the same red/blue scale as a color bar
# (fast-follow requested after the storyboard shipped: the mapping was only
# explained in the help text above the plot, not on the figure itself).
draw_temporal_storyboard <- function(g, layout_df, hist_matrix, label_cex = 0.65) {
  idx <- match(igraph::V(g)$name, layout_df$id)
  layout_matrix <- as.matrix(layout_df[idx, c("x", "y")])

  n_panels <- nrow(hist_matrix)
  ncol_grid <- ceiling(sqrt(n_panels))
  nrow_grid <- ceiling(n_panels / ncol_grid)

  max_abs <- max(abs(hist_matrix), na.rm = TRUE)
  if (!is.finite(max_abs) || max_abs == 0) max_abs <- 1

  n_cells <- nrow_grid * ncol_grid
  panel_ids <- c(seq_len(n_panels), rep(0L, n_cells - n_panels))
  grid_mat <- matrix(panel_ids, nrow = nrow_grid, ncol = ncol_grid, byrow = TRUE)
  legend_id <- n_panels + 1L
  grid_mat <- cbind(grid_mat, rep(legend_id, nrow_grid))

  old_par <- graphics::par(mar = c(1, 0.5, 2, 0.5))
  on.exit(graphics::par(old_par))
  graphics::layout(grid_mat, widths = c(rep(1, ncol_grid), 0.35))

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
      vertex.label.cex = label_cex,
      vertex.label.color = "black",
      vertex.label.dist = 1.3,
      edge.arrow.size = 0.3,
      edge.color = "grey60",
      main = paste("Window", t)
    )
  }

  draw_storyboard_color_scale(max_abs)
}

# Vertical gradient bar for the storyboard's last grid cell: red at the top
# (increased from zero) through white (zero) to blue at the bottom
# (decreased from zero), the same rgb() mapping used per-node above, with
# axis ticks at -max_abs/0/max_abs so a reader can turn a panel's node color
# back into an approximate value instead of only a direction.
draw_storyboard_color_scale <- function(max_abs) {
  graphics::par(mar = c(3, 1, 3, 3.5))

  n_grad <- 100
  grad_vals <- seq(max_abs, -max_abs, length.out = n_grad)
  grad_intensity <- pmin(abs(grad_vals) / max_abs, 1)
  grad_colors <- ifelse(
    grad_vals >= 0,
    grDevices::rgb(1, 1 - grad_intensity, 1 - grad_intensity),
    grDevices::rgb(1 - grad_intensity, 1 - grad_intensity, 1)
  )

  graphics::plot(
    NA, xlim = c(0, 1), ylim = c(-max_abs, max_abs),
    xaxt = "n", yaxt = "n", xlab = "", ylab = "", bty = "n"
  )
  graphics::rasterImage(as.raster(matrix(grad_colors, ncol = 1)), 0, -max_abs, 1, max_abs)
  graphics::axis(4, at = c(-max_abs, 0, max_abs), labels = round(c(-max_abs, 0, max_abs), 2), las = 1, cex.axis = 0.7)
  graphics::mtext("increased", side = 3, line = 1, cex = 0.65, font = 2)
  graphics::mtext("decreased", side = 1, line = 1, cex = 0.65, font = 2)
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
