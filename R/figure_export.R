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
NETWORK_LAYOUT_CHOICES <- c("Columns by level" = "columns", "Circle (radial labels)" = "circle")
NETWORK_EDGE_CHOICES <- c("Colour (green increases, red decreases)" = "color",
                          "Line type (solid increases, dashed decreases; width = strength class)" = "linetype")
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
network_static_height_mm <- function(g, schema, width_mm = 190, font_pt = 8, legend = TRUE,
                                     layout = "columns", edge_style = "color") {
  leg_rows <- if (!legend) 0 else if (identical(edge_style, "linetype")) 2 else 1
  leg_mm <- leg_rows * 2.6 * network_line_mm(font_pt)
  if (identical(layout, "circle")) return(round(width_mm * 0.92 + leg_mm) + 2)
  n_cols <- length(intersect(schema$name, igraph::V(g)$dpsir_category))
  lay <- network_static_layout(g, schema, wrap = network_label_wrap(width_mm, n_cols, font_pt))
  round(lay$H * network_line_mm(font_pt) + leg_mm) + 2
}

# Edge styles: "color" (green increases / vermilion decreases, arrowheads,
# width proportional to |beta|) or "linetype" (dark grey, solid with an
# arrowhead = increases, dashed ending in a bar = decreases, width by the
# strength class weak / moderate / strong) - readable in black and white.
NETWORK_CLASS_LWD <- c(weak = 0.7, moderate = 1.5, strong = 2.6)
NETWORK_LINE_INK <- "#3a3f47"

network_edge_look <- function(sign, beta, edge_style = "color") {
  if (identical(edge_style, "linetype")) {
    cls <- classify_beta(beta)
    if (is.na(cls)) cls <- "moderate"
    list(col = NETWORK_LINE_INK, lty = if (sign == "negative") 2 else 1, lwd = NETWORK_CLASS_LWD[[cls]],
         head = if (sign == "negative") "bar" else "arrow")
  } else {
    list(col = grDevices::adjustcolor(NETWORK_SIGN_COL[[sign]], 0.9), lty = 1, lwd = 0.5 + 1.8 * min(1, beta), head = "arrow")
  }
}

# Draws one link along the points (bx, by), already trimmed at the nodes.
draw_network_edge <- function(bx, by, look) {
  m <- length(bx)
  if (m < 3) return(invisible())
  graphics::lines(bx[-m], by[-m], col = look$col, lwd = look$lwd, lty = look$lty)
  if (identical(look$head, "bar")) {
    graphics::lines(bx[(m - 1):m], by[(m - 1):m], col = look$col, lwd = look$lwd)
    dx <- bx[m] - bx[m - 1]; dy <- by[m] - by[m - 1]; L <- sqrt(dx^2 + dy^2)
    if (L > 0) {
      # A bar across the end, about as long as an arrowhead is wide.
      half <- 0.6 * graphics::strwidth("M", cex = 1)
      px <- -dy / L * half; py <- dx / L * half
      graphics::segments(bx[m] - px, by[m] - py, bx[m] + px, by[m] + py, col = look$col, lwd = look$lwd * 1.2, lend = 1)
    }
  } else {
    graphics::arrows(bx[m - 1], by[m - 1], bx[m], by[m], length = 0.045, angle = 25, col = look$col, lwd = look$lwd)
  }
}

network_edge_data <- function(g) {
  el <- igraph::as_edgelist(g, names = FALSE)
  w <- abs(as.numeric(igraph::E(g)$weight)); w[is.na(w)] <- 0.45
  sgn <- igraph::E(g)$interaction_type
  sgn[!sgn %in% names(NETWORK_SIGN_COL)] <- "positive"
  list(el = el, w = w, sgn = sgn)
}

draw_network_static_panel <- function(g, lay, node_cex = 2.1, label_cex = 0.875, edge_style = "color") {
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1)
  graphics::plot.new()
  graphics::plot.window(xlim = c(0.45, lay$n_cols + 0.55), ylim = c(-lay$H, 0), xaxs = "i", yaxs = "i")
  x <- lay$x; y <- lay$y
  ed <- network_edge_data(g)
  rad_x <- graphics::strwidth("O", cex = node_cex) * 0.5
  rad_y <- graphics::strheight("O", cex = node_cex) * 0.62
  for (e in seq_len(nrow(ed$el))) {
    a <- ed$el[e, 1]; b <- ed$el[e, 2]
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
    draw_network_edge(bx[keep], by[keep], network_edge_look(ed$sgn[e], ed$w[e], edge_style))
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

# Circular layout: the nodes on a circle, grouped by level in the schema's
# order and going clockwise from the upper left (Drivers, then Pressures at
# the top, States on the right, Impacts at the bottom, Responses on the
# left), one empty slot between levels; links bend gently towards the
# centre; labels radial, outside the circle.
network_circle_layout <- function(g, schema, wrap = 24) {
  cats <- igraph::V(g)$dpsir_category
  cat_order <- schema$name[order(schema$order)]
  cat_order <- cat_order[cat_order %in% cats]
  ord <- unlist(lapply(cat_order, function(cc) which(cats == cc)))
  slots <- integer(length(cats))
  pos <- 0L
  for (cc in cat_order) {
    k <- which(cats == cc)
    slots[k] <- pos + seq_along(k) - 1L
    pos <- pos + length(k) + 1L
  }
  n_slots <- pos
  # Centre the first level around 150 degrees, going clockwise.
  first_n <- sum(cats == cat_order[1])
  start <- 150 + (first_n - 1) / 2 * 360 / n_slots
  ang <- start - slots * 360 / n_slots
  labs <- igraph::V(g)$label
  labs[is.na(labs) | !nzchar(labs)] <- igraph::V(g)$name[is.na(labs) | !nzchar(labs)]
  labs <- vapply(labs, function(s) paste(strwrap(s, wrap), collapse = "\n"), "", USE.NAMES = FALSE)
  list(x = cos(ang * pi / 180), y = sin(ang * pi / 180), ang = ang, labs = labs, cats = cats,
       cat_order = cat_order, cols = setNames(schema$color, schema$name))
}

draw_network_circle_panel <- function(g, lay, node_cex = 2.1, label_cex = 0.875, edge_style = "color", bend = 0.45) {
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1)
  graphics::plot.new()
  # Room for the radial labels: their longest line, in units of the circle.
  graphics::plot.window(xlim = c(-1, 1), ylim = c(-1, 1), asp = 1)
  lab_w <- max(graphics::strwidth(lay$labs, cex = label_cex)) / diff(graphics::par("usr")[1:2]) * 2
  gap <- 0.10
  L <- (1 + gap) / max(0.25, 1 - lab_w) + 0.02
  graphics::plot.window(xlim = c(-L, L), ylim = c(-L, L), asp = 1)
  x <- lay$x; y <- lay$y
  ed <- network_edge_data(g)
  rad <- graphics::strwidth("O", cex = node_cex) * 0.5
  for (e in seq_len(nrow(ed$el))) {
    a <- ed$el[e, 1]; b <- ed$el[e, 2]
    x0 <- x[a]; y0 <- y[a]; x1 <- x[b]; y1 <- y[b]
    # Control point: the chord's midpoint pulled towards the centre.
    cxp <- (x0 + x1) / 2 * (1 - bend); cyp <- (y0 + y1) / 2 * (1 - bend)
    t <- seq(0, 1, length.out = 80)
    bx <- (1 - t)^2 * x0 + 2 * (1 - t) * t * cxp + t^2 * x1
    by <- (1 - t)^2 * y0 + 2 * (1 - t) * t * cyp + t^2 * y1
    keep <- ((bx - x0)^2 + (by - y0)^2 > rad^2) & ((bx - x1)^2 + (by - y1)^2 > (rad * 1.15)^2)
    draw_network_edge(bx[keep], by[keep], network_edge_look(ed$sgn[e], ed$w[e], edge_style))
  }
  graphics::points(x, y, pch = 21, bg = lay$cols[lay$cats], col = NETWORK_INK, cex = node_cex, lwd = 0.6)
  # Radial labels; on the left half they are turned 180 degrees so they never
  # read upside down.
  right <- cos(lay$ang * pi / 180) >= -1e-9
  for (i in seq_along(x)) {
    r <- 1 + gap * 0.75
    srt <- if (right[i]) lay$ang[i] else lay$ang[i] + 180
    graphics::text(r * x[i], r * y[i], lay$labs[i], srt = srt, adj = c(if (right[i]) 0 else 1, 0.5),
                   cex = label_cex, col = NETWORK_INK)
  }
}

draw_network_static_legend <- function(schema, cats = NULL, edge_style = "color") {
  cat_order <- schema$name[order(schema$order)]
  if (!is.null(cats)) cat_order <- cat_order[cat_order %in% cats]
  cols <- setNames(schema$color, schema$name)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  if (identical(edge_style, "linetype")) {
    graphics::legend("top", horiz = TRUE, bty = "n", legend = cat_order, pt.bg = cols[cat_order], pch = 21,
                     pt.cex = 1.5, col = NETWORK_INK, cex = 0.9, x.intersp = 0.8, text.col = NETWORK_INK, text.width = NA)
    graphics::legend("bottom", horiz = TRUE, bty = "n", text.col = NETWORK_INK, cex = 0.9, x.intersp = 0.6, seg.len = 2.2,
                     text.width = NA,
                     legend = c("→  increases its target", "-|  decreases its target", "weak", "moderate", "strong"),
                     col = NETWORK_LINE_INK, lty = c(1, 2, 1, 1, 1),
                     lwd = c(NETWORK_CLASS_LWD[["moderate"]], NETWORK_CLASS_LWD[["moderate"]], NETWORK_CLASS_LWD))
  } else {
    graphics::legend("left", horiz = TRUE, bty = "n", legend = cat_order, pt.bg = cols[cat_order], pch = 21,
                     pt.cex = 1.5, col = NETWORK_INK, cex = 0.9, x.intersp = 0.8, text.col = NETWORK_INK, inset = 0.01)
    graphics::legend("right", horiz = TRUE, bty = "n", legend = c("increases its target", "decreases its target"),
                     col = NETWORK_SIGN_COL[c("positive", "negative")], lwd = 2, cex = 0.9, x.intersp = 0.6, seg.len = 1.6,
                     text.col = NETWORK_INK, inset = 0.01)
  }
}

# The whole static network (panel + legend) on the current device; the
# label wrap follows the device width and point size.
#   layout:     "columns" (one column per level) or "circle".
#   edge_style: "color" or "linetype" (see network_edge_look()).
draw_network_static <- function(g, schema, node_cex = 2.1, layout = c("columns", "circle"),
                                edge_style = c("color", "linetype")) {
  layout <- match.arg(layout); edge_style <- match.arg(edge_style)
  if (is.null(g) || igraph::vcount(g) == 0) {
    graphics::plot.new(); graphics::text(0.5, 0.5, "No network built yet."); return(invisible())
  }
  din <- graphics::par("din"); ps <- graphics::par("ps")
  leg_rows <- if (edge_style == "linetype") 2 else 1
  leg <- min(0.3, (leg_rows * 2.6 * network_line_mm(ps) / 25.4) / din[2])
  op <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(op))
  graphics::par(fig = c(0, 1, leg, 1))
  if (layout == "circle") {
    lay <- network_circle_layout(g, schema)
    draw_network_circle_panel(g, lay, node_cex = node_cex, edge_style = edge_style)
  } else {
    n_cols <- length(intersect(schema$name, igraph::V(g)$dpsir_category))
    lay <- network_static_layout(g, schema, wrap = network_label_wrap(din[1] * 25.4, n_cols, ps))
    draw_network_static_panel(g, lay, node_cex = node_cex, edge_style = edge_style)
  }
  graphics::par(fig = c(0, 1, 0, leg), new = TRUE)
  draw_network_static_legend(schema, cats = lay$cats, edge_style = edge_style)
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
#   extra_ui(key): optional extra controls (ids built with key()), read by
#   draw()/height() through `input`.
register_figure_export <- function(input, output, session, id, draw, height, filename = id, extra_ui = NULL) {
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
      if (!is.null(extra_ui)) extra_ui(function(x) ns(key(x))),
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
