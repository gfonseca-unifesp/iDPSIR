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
