# =====================================================
# FIGURE EXPORT - every figure in the format, size, resolution and font the
# user picks, and the static (print) drawing of the network
# =====================================================
#
# Revisao 3. One exporter for every chart of the app (Scenarios,
# Interpretation, Graph) and for the manuscript script
# (data-raw/manuscript_figures.R): PNG / TIFF at a chosen dpi, SVG or PDF
# (vector), at journal widths (single column 90 mm, 1.5 column 140 mm, full
# page 190 mm) or any width, with the base font size in points as printed.
# The drawing functions use cex relative to the device's point size, so the
# font option scales every label, axis and legend together.

FIGURE_WIDTHS_MM <- c("Single column (90 mm)" = 90, "1.5 column (140 mm)" = 140, "Full page (190 mm)" = 190)
FIGURE_DPI <- c(150, 300, 600)

# Formats this R can write (the browser-only build may lack cairo or tiff).
figure_export_formats <- function() {
  cap <- capabilities()
  f <- c("PNG (raster)" = "png", "PDF (vector)" = "pdf", "SVG (vector)" = "svg", "TIFF (raster, LZW)" = "tiff")
  keep <- c(png = isTRUE(cap[["png"]]) || isTRUE(cap[["cairo"]]), pdf = TRUE,
            svg = isTRUE(cap[["cairo"]]), tiff = isTRUE(cap[["tiff"]]) || isTRUE(cap[["cairo"]]))
  f[keep[f]]
}

figure_extension <- function(format) c(png = "png", pdf = "pdf", svg = "svg", tiff = "tif")[[format]]

# Writes draw_fn() to `path`. width/height in mm; dpi for raster formats;
# font_pt = the device's point size (cex 1 = font_pt in print).
export_figure <- function(draw_fn, path, format = c("png", "pdf", "svg", "tiff"), width_mm = 190, height_mm = 120,
                          dpi = 300, font_pt = 8) {
  format <- match.arg(format)
  w <- width_mm / 25.4; h <- height_mm / 25.4
  cairo <- isTRUE(capabilities("cairo"))
  switch(format,
    png = if (cairo) grDevices::png(path, width = w, height = h, units = "in", res = dpi, pointsize = font_pt, type = "cairo", bg = "white")
          else grDevices::png(path, width = w, height = h, units = "in", res = dpi, pointsize = font_pt, bg = "white"),
    tiff = if (cairo) grDevices::tiff(path, width = w, height = h, units = "in", res = dpi, pointsize = font_pt, type = "cairo",
                                      compression = "lzw", bg = "white")
           else grDevices::tiff(path, width = w, height = h, units = "in", res = dpi, pointsize = font_pt, compression = "lzw", bg = "white"),
    # cairo_pdf keeps the Greek letters and symbols (beta, rho, <=) the
    # labels use; plain pdf() is the fallback where cairo is missing.
    pdf = if (cairo) grDevices::cairo_pdf(path, width = w, height = h, pointsize = font_pt, bg = "white")
          else grDevices::pdf(path, width = w, height = h, pointsize = font_pt, bg = "white", useDingbats = FALSE),
    svg = grDevices::svg(path, width = w, height = h, pointsize = font_pt, bg = "white")
  )
  on.exit(grDevices::dev.off())
  draw_fn()
  invisible(path)
}

# ---------------------------------------------------------------------------
# Static network (DPSIR columns) - for print, the report and the manuscript
# ---------------------------------------------------------------------------
NETWORK_SIGN_COL <- c(positive = "#009E73", negative = "#D55E00")  # Okabe-Ito green / vermilion
NETWORK_INK <- "#1f2933"
NETWORK_NODE_LINES <- 1.5     # vertical room of a node marker, in label lines
NETWORK_PAD_LINES <- 0.9      # gap below each label

# One label line in print, in mm (labels at 0.875 of the base font).
network_line_mm <- function(font_pt = 8) 0.875 * font_pt * 1.2 * 25.4 / 72

# Characters per label line that fit a column of the given width.
network_label_wrap <- function(width_mm, n_cols, font_pt = 8) {
  col_mm <- width_mm / max(1, n_cols)
  char_mm <- 0.5 * 0.875 * font_pt * 25.4 / 72
  max(10, floor(0.72 * col_mm / char_mm))
}

# Columns by level (schema order); in each column the nodes are stacked with
# room for their wrapped label, so the vertical unit is one label line.
network_static_layout <- function(g, schema, wrap = 22) {
  cats <- igraph::V(g)$dpsir_category
  cat_order <- schema$name[order(schema$order)]
  cat_order <- cat_order[cat_order %in% cats]
  labs <- igraph::V(g)$label
  labs[is.na(labs) | !nzchar(labs)] <- igraph::V(g)$name[is.na(labs) | !nzchar(labs)]
  labs <- vapply(labs, function(s) paste(strwrap(s, wrap), collapse = "\n"), "", USE.NAMES = FALSE)
  nl <- lengths(regmatches(labs, gregexpr("\n", labs))) + 1
  block <- NETWORK_NODE_LINES + nl + NETWORK_PAD_LINES
  col_h <- tapply(block, factor(cats, levels = cat_order), sum)
  col_h[is.na(col_h)] <- 0
  H <- max(col_h, 1)
  x <- match(cats, cat_order)
  y <- numeric(length(cats))
  for (cc in cat_order) {
    k <- which(cats == cc)
    if (!length(k)) next
    top <- -(H - col_h[[cc]]) / 2
    y[k] <- top - c(0, cumsum(block[k]))[seq_along(k)] - NETWORK_NODE_LINES / 2
  }
  list(x = x, y = y, labs = labs, H = H, n_cols = length(cat_order), cat_order = cat_order,
       cols = setNames(schema$color, schema$name), cats = cats)
}

# Height (mm) the static network needs at a given width and font.
network_static_height_mm <- function(g, schema, width_mm = 190, font_pt = 8, legend = TRUE) {
  n_cols <- length(intersect(schema$name, igraph::V(g)$dpsir_category))
  lay <- network_static_layout(g, schema, wrap = network_label_wrap(width_mm, n_cols, font_pt))
  round(lay$H * network_line_mm(font_pt) + if (legend) 2.6 * network_line_mm(font_pt) else 0) + 2
}

draw_network_static_panel <- function(g, lay, node_cex = 2.1, label_cex = 0.875) {
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1)
  graphics::plot.new()
  graphics::plot.window(xlim = c(0.45, lay$n_cols + 0.55), ylim = c(-lay$H, 0), xaxs = "i", yaxs = "i")
  x <- lay$x; y <- lay$y
  el <- igraph::as_edgelist(g, names = FALSE)
  w <- abs(as.numeric(igraph::E(g)$weight))
  w[is.na(w)] <- 0.45
  sgn <- igraph::E(g)$interaction_type
  sgn[!sgn %in% names(NETWORK_SIGN_COL)] <- "positive"
  rad_x <- graphics::strwidth("O", cex = node_cex) * 0.5
  rad_y <- graphics::strheight("O", cex = node_cex) * 0.62
  for (e in seq_len(nrow(el))) {
    a <- el[e, 1]; b <- el[e, 2]
    if (is.na(x[a]) || is.na(x[b])) next
    x0 <- x[a]; y0 <- y[a]; x1 <- x[b]; y1 <- y[b]
    back <- x1 <= x0
    # Quadratic Bezier; links going back (from Responses) bow upwards more,
    # so they stay clear of the forward links.
    cxp <- (x0 + x1) / 2
    cyp <- (y0 + y1) / 2 + if (back) 0.10 * lay$H * (0.4 + abs(x1 - x0) / lay$n_cols) else 0.05 * (x1 - x0) * lay$H / 10
    t <- seq(0, 1, length.out = 60)
    bx <- (1 - t)^2 * x0 + 2 * (1 - t) * t * cxp + t^2 * x1
    by <- (1 - t)^2 * y0 + 2 * (1 - t) * t * cyp + t^2 * y1
    inside <- function(px, py, cx, cy) ((px - cx) / rad_x)^2 + ((py - cy) / rad_y)^2 < 1
    keep <- !inside(bx, by, x0, y0) & !inside(bx, by, x1, y1)
    bx <- bx[keep]; by <- by[keep]
    if (length(bx) < 3) next
    col <- grDevices::adjustcolor(NETWORK_SIGN_COL[[sgn[e]]], 0.9)
    lwd <- 0.5 + 1.8 * min(1, w[e])
    m <- length(bx)
    graphics::lines(bx[-m], by[-m], col = col, lwd = lwd)
    graphics::arrows(bx[m - 1], by[m - 1], bx[m], by[m], length = 0.045, angle = 25, col = col, lwd = lwd)
  }
  # Labels on a white ground, so the links never cross the text.
  ok <- !is.na(x)
  ly <- y - NETWORK_NODE_LINES / 2 - 0.05
  lw <- graphics::strwidth(lay$labs, cex = label_cex)
  lh <- graphics::strheight(lay$labs, cex = label_cex)
  graphics::rect((x - lw / 2 - 0.02)[ok], (ly - lh - 0.25)[ok], (x + lw / 2 + 0.02)[ok], (ly + 0.1)[ok],
                 col = grDevices::adjustcolor("white", 0.9), border = NA)
  graphics::points(x[ok], y[ok], pch = 21, bg = lay$cols[lay$cats[ok]], col = NETWORK_INK, cex = node_cex, lwd = 0.6)
  graphics::text(x[ok], ly[ok], lay$labs[ok], adj = c(0.5, 1), cex = label_cex, col = NETWORK_INK)
}

draw_network_static_legend <- function(schema, cats = NULL) {
  cat_order <- schema$name[order(schema$order)]
  if (!is.null(cats)) cat_order <- cat_order[cat_order %in% cats]
  cols <- setNames(schema$color, schema$name)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::legend("left", horiz = TRUE, bty = "n", legend = cat_order, pt.bg = cols[cat_order], pch = 21,
                   pt.cex = 1.5, col = NETWORK_INK, cex = 0.9, x.intersp = 0.8, text.col = NETWORK_INK, inset = 0.01)
  graphics::legend("right", horiz = TRUE, bty = "n", legend = c("increases its target", "decreases its target"),
                   col = NETWORK_SIGN_COL[c("positive", "negative")], lwd = 2, cex = 0.9, x.intersp = 0.6, seg.len = 1.6,
                   text.col = NETWORK_INK, inset = 0.01)
}

# The whole static network (panel + legend) on the current device; the
# label wrap follows the device width and point size.
draw_network_static <- function(g, schema, node_cex = 2.1) {
  if (is.null(g) || igraph::vcount(g) == 0) {
    graphics::plot.new(); graphics::text(0.5, 0.5, "No network built yet."); return(invisible())
  }
  din <- graphics::par("din"); ps <- graphics::par("ps")
  n_cols <- length(intersect(schema$name, igraph::V(g)$dpsir_category))
  lay <- network_static_layout(g, schema, wrap = network_label_wrap(din[1] * 25.4, n_cols, ps))
  leg <- min(0.3, (2.6 * network_line_mm(ps) / 25.4) / din[2])
  op <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(op))
  graphics::par(fig = c(0, 1, leg, 1))
  draw_network_static_panel(g, lay, node_cex = node_cex)
  graphics::par(fig = c(0, 1, 0, leg), new = TRUE)
  draw_network_static_legend(schema, cats = lay$cats)
}

# ---------------------------------------------------------------------------
# Shiny: "Download figure..." button and its dialog
# ---------------------------------------------------------------------------
figure_export_button <- function(ns, id, label = "Download figure…") {
  shiny::actionButton(ns(paste0("figexp_", id)), label, icon = shiny::icon("download"), class = "btn-sm btn-outline-secondary")
}

# Registers the dialog and the download for one figure.
#   draw():   draws the figure (may read reactives).
#   height(width_mm, font_pt): its natural height in mm.
register_figure_export <- function(input, output, session, id, draw, height, filename = id) {
  ns <- session$ns
  key <- function(x) paste0("figexp_", id, "_", x)
  shiny::observeEvent(input[[paste0("figexp_", id)]], {
    shiny::showModal(shiny::modalDialog(
      title = "Download figure", size = "m", easyClose = TRUE,
      shiny::fluidRow(
        shiny::column(6, shiny::selectInput(ns(key("format")), "Format", choices = figure_export_formats(), selected = "png")),
        shiny::column(6, shiny::selectInput(ns(key("dpi")), "Resolution (PNG, TIFF)", choices = setNames(FIGURE_DPI, paste(FIGURE_DPI, "dpi")), selected = 300))
      ),
      shiny::fluidRow(
        shiny::column(6, shiny::selectInput(ns(key("width")), "Width", choices = c(FIGURE_WIDTHS_MM, "Other (mm)" = 0), selected = 190)),
        shiny::column(6, shiny::conditionalPanel(sprintf("input['%s'] == '0'", ns(key("width"))),
                                                 shiny::numericInput(ns(key("width_mm")), "Width (mm)", value = 160, min = 40, max = 500)))
      ),
      shiny::fluidRow(
        shiny::column(6, shiny::numericInput(ns(key("font")), "Font size (pt, as printed)", value = 9, min = 5, max = 16, step = 0.5)),
        shiny::column(6, shiny::numericInput(ns(key("height_mm")), "Height (mm; empty = automatic)", value = NA, min = 30, max = 600))
      ),
      shiny::helpText("Journals usually ask for 7-9 pt text at the printed size and 300-600 dpi for raster images;",
                      "PDF and SVG are vector and print sharp at any size. Labels, axes and legends all scale with the font size",
                      "(legends are drawn a little smaller than the base size, so 9 pt keeps them above 7 pt)."),
      footer = shiny::tagList(shiny::modalButton("Cancel"),
                              shiny::downloadButton(ns(key("file")), "Download", class = "btn-primary"))
    ))
  })
  settings <- function() {
    fmt <- input[[key("format")]] %||% "png"
    w <- as.numeric(input[[key("width")]] %||% 190)
    if (is.na(w) || w == 0) w <- as.numeric(input[[key("width_mm")]] %||% 160)
    w <- min(500, max(40, w))
    font <- as.numeric(input[[key("font")]] %||% 9)
    if (is.na(font)) font <- 9
    h <- suppressWarnings(as.numeric(input[[key("height_mm")]]))
    if (length(h) == 0 || is.na(h)) h <- height(w, font)
    list(format = fmt, width = w, height = min(600, max(30, h)), dpi = as.numeric(input[[key("dpi")]] %||% 300), font = font)
  }
  output[[key("file")]] <- shiny::downloadHandler(
    filename = function() sprintf("%s_%s.%s", filename, Sys.Date(), figure_extension(settings()$format)),
    content = function(file) {
      s <- settings()
      export_figure(draw, file, s$format, s$width, s$height, s$dpi, s$font)
      shiny::removeModal()
    }
  )
}
