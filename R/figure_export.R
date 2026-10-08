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
NETWORK_LAYOUT_CHOICES <- c("Columns by level" = "columns", "Circle (radial labels)" = "circle",
                            "As on screen (layered: spacing and dragged nodes)" = "screen")
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

# Links drawn dashed (dotted with edge_style "linetype"): confidence below
# dash_below, as on the Graph tab ("Dash edges below confidence"); confidence
# = 1 - band width / strength (R/structural.R). NA or 0 = none.
network_dash_flags <- function(g, dash_below = NA) {
  conf <- suppressWarnings(as.numeric(igraph::E(g)$confidence))
  if (length(conf) == 0 || is.null(dash_below) || is.na(dash_below) || dash_below <= 0) return(rep(FALSE, igraph::ecount(g)))
  !is.na(conf) & conf < dash_below
}

# What the figure shows besides the network itself, as on the Graph tab:
#   shapes:          node shapes by level (as set in the model) instead of circles.
#   dash_below:      links with confidence below this are dashed (NA = none).
#   highlight:       ids of the nodes to keep in colour (a pathway, or a
#                    selected node and its neighbours); the rest is greyed.
#   highlight_edges: which links stay in colour (logical, one per link);
#                    default = links between two highlighted nodes.
#   highlight_label: legend text for the greyed part.
#   node_colors:     fill per node id (e.g. communities) instead of the level's
#                    colour; color_legend = its legend (label -> colour).
network_view <- function(g, schema, shapes = FALSE, dash_below = NA, highlight = NULL, highlight_edges = NULL,
                         highlight_label = "outside the highlighted pathway", node_colors = NULL, color_legend = NULL) {
  ids <- igraph::V(g)$name
  cats <- igraph::V(g)$dpsir_category
  fill <- unname(setNames(schema$color, schema$name)[cats])
  if (!is.null(node_colors)) {
    nc <- unname(node_colors[ids])
    fill[!is.na(nc)] <- nc[!is.na(nc)]
  }
  fill[is.na(fill)] <- "#999999"
  hl <- length(highlight) > 0
  node_dim <- if (hl) !ids %in% highlight else rep(FALSE, length(ids))
  el <- igraph::as_edgelist(g, names = TRUE)
  edge_dim <- if (!hl) rep(FALSE, nrow(el))
              else if (!is.null(highlight_edges)) !as.logical(highlight_edges)
              else !(el[, 1] %in% highlight & el[, 2] %in% highlight)
  list(shapes = shapes, shape = network_node_shapes(cats, schema, shapes), fill = fill, node_dim = node_dim,
       dashed = network_dash_flags(g, dash_below), dash_below = dash_below, edge_dim = edge_dim,
       highlight = hl, highlight_label = highlight_label, color_legend = color_legend)
}

NETWORK_DIM_FILL <- "#e4e6e9"
NETWORK_DIM_INK <- "#a3a9b0"
NETWORK_DIM_LINE <- "#d3d7dc"

# Legend rows: levels (or communities) and signs - one row with colour, two
# with line type -, the levels' shapes when the nodes are coloured by
# community, and one for the notes (dashed links, greyed part).
network_legend_rows <- function(edge_style = "color", v = NULL) {
  notes <- !is.null(v) && (any(v$dashed) || isTRUE(v$highlight))
  shape_row <- !is.null(v) && !is.null(v$color_legend) && isTRUE(v$shapes)
  (if (identical(edge_style, "linetype")) 2 else 1) + shape_row + notes
}

# Layout "screen": the Graph tab's layered layout as it is on screen - its
# horizontal and vertical spacing and the nodes dragged by hand (positions
# in screen pixels, from compute_effective_layout()). Same proportions as
# on screen; labels below the nodes.
network_screen_layout <- function(g, schema, positions, width_mm = 190, font_pt = 8) {
  ids <- igraph::V(g)$name
  m <- match(ids, positions$id)
  x <- as.numeric(positions$x[m]); y <- -as.numeric(positions$y[m])
  x[is.na(x)] <- 0; y[is.na(y)] <- 0
  ux <- sort(unique(round(x)))
  dx <- if (length(ux) > 1) min(diff(ux)) else 200
  dx <- max(dx, diff(range(x)) / 12, 1)
  n_cols <- diff(range(x)) / dx + 1
  labs <- igraph::V(g)$label
  labs[is.na(labs) | !nzchar(labs)] <- ids[is.na(labs) | !nzchar(labs)]
  # Labels may take a little more than a column here (nothing sits beside them).
  labs <- vapply(labs, function(s) paste(strwrap(s, network_label_wrap(width_mm, 0.8 * n_cols, font_pt)), collapse = "\n"), "",
                 USE.NAMES = FALSE)
  nl <- lengths(regmatches(labs, gregexpr("\n", labs))) + 1
  list(x = x, y = y, labs = labs, nl = nl, dx = dx, cats = igraph::V(g)$dpsir_category)
}

# Room above and below the nodes in the "screen" layout, in mm.
network_screen_pads_mm <- function(lay, font_pt) {
  line <- network_line_mm(font_pt)
  c(top = 1.6 * line, bottom = (max(lay$nl) + 1.8) * line)
}

network_screen_height_mm <- function(lay, width_mm, font_pt) {
  s <- width_mm / (diff(range(lay$x)) + lay$dx)
  pads <- network_screen_pads_mm(lay, font_pt)
  diff(range(lay$y)) * s + sum(pads)
}

# Height (mm) the static network needs at a given width and font; `...` are
# the options of network_view().
network_static_height_mm <- function(g, schema, width_mm = 190, font_pt = 8, legend = TRUE,
                                     layout = "columns", edge_style = "color", positions = NULL, ...) {
  if (is.null(g) || igraph::vcount(g) == 0) return(60)
  v <- network_view(g, schema, ...)
  leg_rows <- if (!legend) 0 else network_legend_rows(edge_style, v)
  leg_mm <- leg_rows * 2.6 * network_line_mm(font_pt)
  if (identical(layout, "circle")) return(round(width_mm * 0.92 + leg_mm) + 2)
  if (identical(layout, "screen") && !is.null(positions)) {
    lay <- network_screen_layout(g, schema, positions, width_mm, font_pt)
    return(round(network_screen_height_mm(lay, width_mm, font_pt) + leg_mm) + 2)
  }
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

# A low-confidence link (dashed = TRUE) is dashed with colour and dotted
# with line type (where dashed already means "decreases"); a greyed link
# (dim = TRUE, outside a highlight) is light grey and thin.
network_edge_look <- function(sign, beta, edge_style = "color", dashed = FALSE, dim = FALSE) {
  look <- if (identical(edge_style, "linetype")) {
    cls <- classify_beta(beta)
    if (is.na(cls)) cls <- "moderate"
    list(col = NETWORK_LINE_INK, lty = if (isTRUE(dashed)) 3 else if (sign == "negative") 2 else 1,
         lwd = NETWORK_CLASS_LWD[[cls]], head = if (sign == "negative") "bar" else "arrow")
  } else {
    list(col = grDevices::adjustcolor(NETWORK_SIGN_COL[[sign]], 0.9), lty = if (isTRUE(dashed)) 2 else 1,
         lwd = 0.5 + 1.8 * min(1, beta), head = "arrow")
  }
  if (isTRUE(dim)) { look$col <- NETWORK_DIM_LINE; look$lwd <- min(look$lwd, 0.8) }
  look
}

# Node markers. With shapes = TRUE each level gets the shape set for it in
# the model (the Graph tab's "Use DPSIR shapes"): a base plotting symbol
# where one exists, a polygon for the star and the hexagon; otherwise all
# circles.
NETWORK_SHAPE_PCH <- c(dot = 21, ellipse = 21, square = 22, box = 22, diamond = 23, triangle = 24)

network_node_shapes <- function(cats, schema, shapes = FALSE) {
  if (!isTRUE(shapes)) return(rep("dot", length(cats)))
  s <- unname(setNames(schema$shape, schema$name)[cats])
  s[is.na(s)] <- "dot"
  s
}

# Polygon (in user coordinates) about the size of a plotting symbol at `cex`.
network_shape_polygon <- function(shape, x, y, cex) {
  r_in <- 0.375 * cex * graphics::par("cex") * graphics::par("cin")[2] * 0.5
  usr <- graphics::par("usr"); pin <- graphics::par("pin")
  ux <- diff(usr[1:2]) / pin[1]; uy <- diff(usr[3:4]) / pin[2]
  if (identical(shape, "star")) {
    a <- pi / 2 + seq(0, 9) * pi / 5
    r <- r_in * 1.45 * rep(c(1, 0.45), 5)
  } else if (identical(shape, "hexagon")) {
    a <- seq(0, 5) * pi / 3; r <- rep(r_in * 1.15, 6)
  } else {
    a <- seq(0, 2 * pi, length.out = 41)[-41]; r <- rep(r_in, 40)
  }
  list(x = x + r * cos(a) * ux, y = y + r * sin(a) * uy)
}

draw_network_nodes <- function(x, y, shape, bg, cex, border = NETWORK_INK) {
  border <- rep_len(border, length(x))
  pch <- unname(NETWORK_SHAPE_PCH[shape])
  sym <- !is.na(pch)
  if (any(sym)) graphics::points(x[sym], y[sym], pch = pch[sym], bg = bg[sym], col = border[sym], cex = cex, lwd = 0.6)
  for (i in which(!sym)) {
    p <- network_shape_polygon(shape[i], x[i], y[i], cex)
    graphics::polygon(p$x, p$y, col = bg[i], border = border[i], lwd = 0.6)
  }
}

# Nodes of a view: greyed ones in light grey.
draw_view_nodes <- function(x, y, v, idx, cex) {
  dim <- v$node_dim[idx]
  draw_network_nodes(x, y, v$shape[idx], ifelse(dim, NETWORK_DIM_FILL, v$fill[idx]), cex,
                     border = ifelse(dim, NETWORK_DIM_INK, NETWORK_INK))
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

# Draws every link with curve(x0, y0, x1, y1) -> list(bx, by) and keep(bx,
# by, a, b) -> which points lie outside the two nodes; greyed links first,
# so the highlighted ones stay on top.
draw_view_edges <- function(g, v, x, y, curve, keep, edge_style) {
  ed <- network_edge_data(g)
  for (e in order(!v$edge_dim)) {
    a <- ed$el[e, 1]; b <- ed$el[e, 2]
    if (is.na(x[a]) || is.na(x[b])) next
    bz <- curve(x[a], y[a], x[b], y[b])
    k <- keep(bz$bx, bz$by, a, b)
    draw_network_edge(bz$bx[k], bz$by[k], network_edge_look(ed$sgn[e], ed$w[e], edge_style, v$dashed[e], v$edge_dim[e]))
  }
}

bezier_points <- function(x0, y0, cx, cy, x1, y1, n = 60) {
  t <- seq(0, 1, length.out = n)
  list(bx = (1 - t)^2 * x0 + 2 * (1 - t) * t * cx + t^2 * x1, by = (1 - t)^2 * y0 + 2 * (1 - t) * t * cy + t^2 * y1)
}

# Labels below the nodes on a white ground, so the links never cross the text.
draw_labels_below <- function(x, y, labs, v, ok, gap, label_cex) {
  ly <- y - gap
  lw <- graphics::strwidth(labs, cex = label_cex)
  lh <- graphics::strheight(labs, cex = label_cex)
  ch <- graphics::strheight("M", cex = label_cex)
  graphics::rect((x - lw / 2 - 0.2 * ch)[ok], (ly - lh - 0.3 * ch)[ok], (x + lw / 2 + 0.2 * ch)[ok], (ly + 0.1 * ch)[ok],
                 col = grDevices::adjustcolor("white", 0.9), border = NA)
  graphics::text(x[ok], ly[ok], labs[ok], adj = c(0.5, 1), cex = label_cex,
                 col = ifelse(v$node_dim[ok], NETWORK_DIM_INK, NETWORK_INK))
}

draw_network_static_panel <- function(g, lay, v, node_cex = 2.1, label_cex = 0.875, edge_style = "color") {
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1)
  graphics::plot.new()
  graphics::plot.window(xlim = c(0.45, lay$n_cols + 0.55), ylim = c(-lay$H, 0), xaxs = "i", yaxs = "i")
  x <- lay$x; y <- lay$y
  rad_x <- graphics::strwidth("O", cex = node_cex) * 0.5
  rad_y <- graphics::strheight("O", cex = node_cex) * 0.62
  inside <- function(px, py, cx, cy) ((px - cx) / rad_x)^2 + ((py - cy) / rad_y)^2 < 1
  # Quadratic Bezier; links going back (from Responses) bow upwards more,
  # so they stay clear of the forward links.
  draw_view_edges(g, v, x, y, edge_style = edge_style,
    curve = function(x0, y0, x1, y1) {
      back <- x1 <= x0
      cyp <- (y0 + y1) / 2 + if (back) 0.10 * lay$H * (0.4 + abs(x1 - x0) / lay$n_cols) else 0.05 * (x1 - x0) * lay$H / 10
      bezier_points(x0, y0, (x0 + x1) / 2, cyp, x1, y1)
    },
    keep = function(bx, by, a, b) !inside(bx, by, x[a], y[a]) & !inside(bx, by, x[b], y[b]))
  ok <- !is.na(x)
  draw_labels_below(x, y, lay$labs, v, ok, NETWORK_NODE_LINES / 2 + 0.05, label_cex)
  draw_view_nodes(x[ok], y[ok], v, which(ok), node_cex)
}

# The "screen" layout panel: same geometry as on screen (asp = 1).
draw_network_screen_panel <- function(g, lay, v, node_cex = 2.1, label_cex = 0.875, edge_style = "color") {
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1)
  graphics::plot.new()
  pin_mm <- graphics::par("pin") * 25.4
  s <- pin_mm[1] / (diff(range(lay$x)) + lay$dx)
  pads <- network_screen_pads_mm(lay, graphics::par("ps")) / s
  graphics::plot.window(xlim = range(lay$x) + c(-1, 1) * lay$dx / 2,
                        ylim = c(min(lay$y) - pads[["bottom"]], max(lay$y) + pads[["top"]]), asp = 1, xaxs = "i", yaxs = "i")
  x <- lay$x; y <- lay$y
  rad <- graphics::strwidth("O", cex = node_cex) * 0.5
  draw_view_edges(g, v, x, y, edge_style = edge_style,
    curve = function(x0, y0, x1, y1) {
      dx <- x1 - x0; dy <- y1 - y0; L <- sqrt(dx^2 + dy^2)
      # Links going back (to the left) bow upwards, the others barely bend.
      if (x1 < x0 - 1e-9) bezier_points(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2 + 0.2 * L, x1, y1)
      else bezier_points(x0, y0, (x0 + x1) / 2 - 0.06 * dy, (y0 + y1) / 2 + 0.06 * dx, x1, y1)
    },
    keep = function(bx, by, a, b) ((bx - x[a])^2 + (by - y[a])^2 > rad^2) & ((bx - x[b])^2 + (by - y[b])^2 > (rad * 1.15)^2))
  ok <- !is.na(x)
  draw_labels_below(x, y, lay$labs, v, ok, rad * 1.2, label_cex)
  draw_view_nodes(x[ok], y[ok], v, which(ok), node_cex)
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

draw_network_circle_panel <- function(g, lay, v, node_cex = 2.1, label_cex = 0.875, edge_style = "color", bend = 0.45) {
  graphics::par(mar = c(0, 0, 0, 0), lheight = 1)
  graphics::plot.new()
  # Room for the radial labels: their longest line, in units of the circle.
  graphics::plot.window(xlim = c(-1, 1), ylim = c(-1, 1), asp = 1)
  lab_w <- max(graphics::strwidth(lay$labs, cex = label_cex)) / diff(graphics::par("usr")[1:2]) * 2
  gap <- 0.10
  L <- (1 + gap) / max(0.25, 1 - lab_w) + 0.02
  graphics::plot.window(xlim = c(-L, L), ylim = c(-L, L), asp = 1)
  x <- lay$x; y <- lay$y
  rad <- graphics::strwidth("O", cex = node_cex) * 0.5
  # Control point: the chord's midpoint pulled towards the centre.
  draw_view_edges(g, v, x, y, edge_style = edge_style,
    curve = function(x0, y0, x1, y1) bezier_points(x0, y0, (x0 + x1) / 2 * (1 - bend), (y0 + y1) / 2 * (1 - bend), x1, y1, 80),
    keep = function(bx, by, a, b) ((bx - x[a])^2 + (by - y[a])^2 > rad^2) & ((bx - x[b])^2 + (by - y[b])^2 > (rad * 1.15)^2))
  draw_view_nodes(x, y, v, seq_along(x), node_cex)
  # Radial labels; on the left half they are turned 180 degrees so they never
  # read upside down.
  right <- cos(lay$ang * pi / 180) >= -1e-9
  for (i in seq_along(x)) {
    r <- 1 + gap * 0.75
    srt <- if (right[i]) lay$ang[i] else lay$ang[i] + 180
    graphics::text(r * x[i], r * y[i], lay$labs[i], srt = srt, adj = c(if (right[i]) 0 else 1, 0.5),
                   cex = label_cex, col = if (v$node_dim[i]) NETWORK_DIM_INK else NETWORK_INK)
  }
}

# Legend of the levels (or communities) with the node markers the panel
# uses: legend() lays the row out with empty symbols, the markers are drawn
# where its symbols would be.
network_legend_levels <- function(x, y, xjust, labels, fill, shp, cex = 0.9, pt_cex = 1.5, x_intersp = 1.05) {
  r <- graphics::legend(x, y, xjust = xjust, yjust = 0.5, horiz = TRUE, bty = "n", legend = labels, pch = NA,
                        cex = cex, x.intersp = x_intersp, text.col = NETWORK_INK, text.width = NA)
  xchar <- cex * graphics::par("cex") * graphics::xinch(graphics::par("cin")[1])
  draw_network_nodes(r$text$x - x_intersp * xchar, r$text$y, shp, fill, pt_cex)
}

draw_network_static_legend <- function(schema, cats = NULL, edge_style = "color", v = NULL) {
  if (is.null(v)) v <- list(shapes = FALSE, dashed = FALSE, highlight = FALSE)
  cat_order <- schema$name[order(schema$order)]
  if (!is.null(cats)) cat_order <- cat_order[cat_order %in% cats]
  cols <- setNames(schema$color, schema$name)
  shp <- network_node_shapes(cat_order, schema, v$shapes)
  rows <- network_legend_rows(edge_style, v)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = c(0, rows), xaxs = "i", yaxs = "i")
  row_y <- function(i) rows - i + 0.5
  # First row: the levels, or the communities when the nodes are coloured
  # by community (then the levels' shapes, unfilled, get a row of their own).
  community <- !is.null(v$color_legend)
  first <- if (community) list(labels = names(v$color_legend), fill = unname(v$color_legend),
                               shp = rep("dot", length(v$color_legend)))
           else list(labels = cat_order, fill = cols[cat_order], shp = shp)
  if (identical(edge_style, "linetype")) {
    network_legend_levels(0.5, row_y(1), 0.5, first$labels, first$fill, first$shp)
    graphics::legend(0.5, row_y(2), xjust = 0.5, yjust = 0.5, horiz = TRUE, bty = "n", text.col = NETWORK_INK, cex = 0.9,
                     x.intersp = 0.6, seg.len = 2.2, text.width = NA,
                     legend = c("→  increases its target", "-|  decreases its target", "weak", "moderate", "strong"),
                     col = NETWORK_LINE_INK, lty = c(1, 2, 1, 1, 1),
                     lwd = c(NETWORK_CLASS_LWD[["moderate"]], NETWORK_CLASS_LWD[["moderate"]], NETWORK_CLASS_LWD))
    nxt <- 3
  } else {
    network_legend_levels(0.01, row_y(1), 0, first$labels, first$fill, first$shp)
    graphics::legend(0.99, row_y(1), xjust = 1, yjust = 0.5, horiz = TRUE, bty = "n",
                     legend = c("increases its target", "decreases its target"),
                     col = NETWORK_SIGN_COL[c("positive", "negative")], lwd = 2, cex = 0.9, x.intersp = 0.6, seg.len = 1.6,
                     text.col = NETWORK_INK)
    nxt <- 2
  }
  if (community && isTRUE(v$shapes)) {
    network_legend_levels(0.5, row_y(nxt), 0.5, cat_order, rep("white", length(cat_order)), shp)
    nxt <- nxt + 1
  }
  notes <- character(); lty <- numeric(); col <- character()
  if (any(v$dashed)) {
    notes <- c(notes, sprintf("wide uncertainty band (confidence < %s)", format(v$dash_below)))
    lty <- c(lty, if (identical(edge_style, "linetype")) 3 else 2); col <- c(col, NETWORK_LINE_INK)
  }
  if (isTRUE(v$highlight)) {
    notes <- c(notes, paste("grey:", v$highlight_label)); lty <- c(lty, 1); col <- c(col, NETWORK_DIM_LINE)
  }
  if (length(notes)) {
    graphics::legend(0.5, row_y(nxt), xjust = 0.5, yjust = 0.5, horiz = TRUE, bty = "n", text.col = NETWORK_INK, cex = 0.9,
                     x.intersp = 0.6, seg.len = 2.2, col = col, lty = lty, lwd = NETWORK_CLASS_LWD[["moderate"]],
                     legend = notes, text.width = NA)
  }
}

# The whole static network (panel + legend) on the current device; the
# label wrap follows the device width and point size.
#   layout:     "columns" (one column per level), "circle", or "screen" (the
#               Graph tab's layered layout with its spacing and dragged
#               nodes; needs `positions`, data.frame id/x/y in screen pixels).
#   edge_style: "color" or "linetype" (see network_edge_look()).
#   ...:        shapes, dash_below, highlight, node colours (network_view()).
draw_network_static <- function(g, schema, node_cex = 2.1, layout = c("columns", "circle", "screen"),
                                edge_style = c("color", "linetype"), positions = NULL, ...) {
  layout <- match.arg(layout); edge_style <- match.arg(edge_style)
  if (is.null(g) || igraph::vcount(g) == 0) {
    graphics::plot.new(); graphics::text(0.5, 0.5, "No network built yet."); return(invisible())
  }
  if (layout == "screen" && is.null(positions)) layout <- "columns"
  v <- network_view(g, schema, ...)
  din <- graphics::par("din"); ps <- graphics::par("ps")
  leg_rows <- network_legend_rows(edge_style, v)
  leg <- min(0.45, (leg_rows * 2.6 * network_line_mm(ps) / 25.4) / din[2])
  op <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(op))
  graphics::par(fig = c(0, 1, leg, 1))
  if (layout == "circle") {
    lay <- network_circle_layout(g, schema)
    draw_network_circle_panel(g, lay, v, node_cex = node_cex, edge_style = edge_style)
  } else if (layout == "screen") {
    lay <- network_screen_layout(g, schema, positions, din[1] * 25.4, ps)
    draw_network_screen_panel(g, lay, v, node_cex = node_cex, edge_style = edge_style)
  } else {
    n_cols <- length(intersect(schema$name, igraph::V(g)$dpsir_category))
    lay <- network_static_layout(g, schema, wrap = network_label_wrap(din[1] * 25.4, n_cols, ps))
    draw_network_static_panel(g, lay, v, node_cex = node_cex, edge_style = edge_style)
  }
  graphics::par(fig = c(0, 1, 0, leg), new = TRUE)
  draw_network_static_legend(schema, cats = lay$cats, edge_style = edge_style, v = v)
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
# The dialog shows a preview of the file: the same drawing at the chosen
# width, height and font, as PNG at screen resolution (so text, legend and
# proportions look as they will in print), redrawn when any option changes.
FIGURE_PREVIEW_PX <- 760

register_figure_export <- function(input, output, session, id, draw, height, filename = id, extra_ui = NULL) {
  ns <- session$ns
  key <- function(x) paste0("figexp_", id, "_", x)
  shiny::observeEvent(input[[paste0("figexp_", id)]], {
    shiny::showModal(shiny::modalDialog(
      title = "Download figure", size = "l", easyClose = TRUE,
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
      shiny::div(style = "border: 1px solid #dee2e6; border-radius: 4px; padding: 6px; max-height: 60vh; overflow-y: auto; background: #fff;",
                 shiny::uiOutput(ns(key("preview_info"))),
                 shiny::imageOutput(ns(key("preview")), height = "auto")),
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
  can_preview <- isTRUE(capabilities("png")) || isTRUE(capabilities("cairo"))
  # Options typed in a numeric field fire on every key: wait for a pause.
  preview_settings <- shiny::debounce(shiny::reactive(settings()), 500)
  output[[key("preview_info")]] <- shiny::renderUI({
    s <- preview_settings()
    shiny::div(class = "text-muted", style = "font-size: 12px; margin-bottom: 4px;",
               sprintf("Preview: %g x %g mm, %g pt%s", round(s$width), round(s$height), s$font,
                       if (s$format %in% c("png", "tiff")) sprintf(", file at %g dpi (%d x %d px)", s$dpi,
                                                                   round(s$width / 25.4 * s$dpi), round(s$height / 25.4 * s$dpi))
                       else sprintf(", %s (vector)", toupper(s$format))),
               if (!can_preview) " - preview not available in this version of R.")
  })
  output[[key("preview")]] <- shiny::renderImage({
    s <- preview_settings()
    shiny::req(can_preview)
    path <- tempfile(fileext = ".png")
    export_figure(draw, path, "png", s$width, s$height, dpi = FIGURE_PREVIEW_PX / (s$width / 25.4), font_pt = s$font)
    list(src = path, contentType = "image/png", alt = "Figure preview", style = "width: 100%; height: auto;")
  }, deleteFile = TRUE)
  output[[key("file")]] <- shiny::downloadHandler(
    filename = function() sprintf("%s_%s.%s", filename, Sys.Date(), figure_extension(settings()$format)),
    content = function(file) {
      s <- settings()
      export_figure(draw, file, s$format, s$width, s$height, s$dpi, s$font)
      shiny::removeModal()
    }
  )
}
