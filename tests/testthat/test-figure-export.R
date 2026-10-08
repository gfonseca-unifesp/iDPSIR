# R/figure_export.R: every figure in the format, size, resolution and font
# the user picks; the static network; the report's figure quality.

fx_png_size <- function(path) {
  con <- file(path, "rb"); on.exit(close(con))
  h <- readBin(con, "raw", 24)
  be <- function(b) sum(as.integer(b) * 256^(3:0))
  c(width = be(h[17:20]), height = be(h[21:24]))
}
fx_graph <- function(f = "example_port") {
  sp <- read_savepoint(file.path("../../docs", paste0(f, ".idpsir.json")))
  list(g = build_igraph(sp$nodes, sp$edges, sp$schema), schema = sp$schema)
}

test_that("export_figure: width, height and dpi set the pixels; PDF and SVG are written", {
  draw <- function() { plot(1:10, main = "test"); legend("topleft", legend = "a", pch = 1) }
  f <- tempfile(fileext = ".png")
  export_figure(draw, f, "png", width_mm = 90, height_mm = 60, dpi = 300, font_pt = 8)
  expect_equal(unname(fx_png_size(f)), c(round(90 / 25.4 * 300), round(60 / 25.4 * 300)), tolerance = 1)
  f6 <- tempfile(fileext = ".png")
  export_figure(draw, f6, "png", width_mm = 190, height_mm = 100, dpi = 600, font_pt = 8)
  expect_equal(fx_png_size(f6)[["width"]], round(190 / 25.4 * 600), tolerance = 1)
  fp <- tempfile(fileext = ".pdf")
  export_figure(draw, fp, "pdf", 140, 90)
  expect_identical(readChar(fp, 5, useBytes = TRUE), "%PDF-")
  if ("svg" %in% figure_export_formats()) {
    fs <- tempfile(fileext = ".svg")
    export_figure(draw, fs, "svg", 140, 90)
    expect_true(any(grepl("<svg", readLines(fs, n = 5, warn = FALSE))))
  }
  if ("tiff" %in% figure_export_formats()) {
    ft <- tempfile(fileext = ".tif")
    export_figure(draw, ft, "tiff", 90, 60, dpi = 300)
    expect_true(file.size(ft) > 0)
  }
  expect_equal(figure_extension("tiff"), "tif")
})

test_that("export_figure: the font size changes the text, not the canvas", {
  draw <- function() { plot.new(); text(0.5, 0.5, "Label", cex = 1) }
  w <- function(pt) { e <- new.env(); export_figure(function() { draw(); e$w <- strwidth("Label", units = "inches") },
                                                       tempfile(fileext = ".png"), "png", 90, 60, 150, pt); e$w }
  expect_gt(w(12), w(7))
})

test_that("static network: every app figure function runs; height follows labels and font", {
  x <- fx_graph("example_mangi")
  h8 <- network_static_height_mm(x$g, x$schema, 190, 8)
  h10 <- network_static_height_mm(x$g, x$schema, 190, 10)
  expect_gt(h10, h8)
  expect_gt(network_static_height_mm(x$g, x$schema, 90, 8), h8)  # narrower columns wrap the labels more
  f <- tempfile(fileext = ".png")
  expect_silent(export_figure(function() draw_network_static(x$g, x$schema), f, "png", 190, h8, 150, 8))
  lay <- network_static_layout(x$g, x$schema)
  expect_equal(sort(unique(lay$x)), seq_len(lay$n_cols))
  # Every node sits inside the drawing area.
  expect_true(all(lay$y < 0 & lay$y > -lay$H))
})

test_that("report: print quality gives more pixels, and the static network is included", {
  x <- fx_graph("example_port")
  uri_px <- function(uri) {
    f <- tempfile(fileext = ".png")
    writeBin(jsonlite::base64_dec(sub("^data:image/png;base64,", "", uri)), f)
    fx_png_size(f)[["width"]]
  }
  draw <- function() plot(1:3)
  expect_equal(uri_px(plot_to_data_uri(draw, 800, 400)), 800)
  expect_equal(uri_px(plot_to_data_uri(draw, 800, 400, res = 300)), 2500)
  html <- as.character(htmltools::renderTags(build_full_report_html(x$schema, x$g, include_static_network = TRUE, figure_res = 300))$html)
  expect_true(grepl("<h3>Network</h3>", html, fixed = TRUE))
  html0 <- as.character(htmltools::renderTags(build_full_report_html(x$schema, x$g))$html)
  expect_false(grepl("<h3>Network</h3>", html0, fixed = TRUE))
})

test_that("static network: circle layout and line-type links", {
  x <- fx_graph("example_mangi")
  lay <- network_circle_layout(x$g, x$schema)
  # Every node on the unit circle, grouped by level (one level per arc).
  expect_equal(lay$x^2 + lay$y^2, rep(1, length(lay$x)), tolerance = 1e-9)
  ord <- order(-lay$ang)   # the angles decrease clockwise from the first level
  expect_false(is.unsorted(match(lay$cats, lay$cat_order)[ord]))
  for (st in c("color", "linetype")) {
    h <- network_static_height_mm(x$g, x$schema, 190, 9, layout = "circle", edge_style = st)
    expect_gt(h, 150)
    f <- tempfile(fileext = ".png")
    expect_silent(export_figure(function() draw_network_static(x$g, x$schema, layout = "circle", edge_style = st), f, "png", 190, h, 100, 9))
    f2 <- tempfile(fileext = ".png")
    expect_silent(export_figure(function() draw_network_static(x$g, x$schema, layout = "columns", edge_style = st), f2, "png", 190, 120, 100, 9))
  }
  # Line type: dashed + bar for a decrease, solid + arrow for an increase; width by class.
  neg <- network_edge_look("negative", 0.15, "linetype"); pos <- network_edge_look("positive", 0.8, "linetype")
  expect_equal(c(neg$lty, neg$head), c(2, "bar")); expect_equal(c(pos$lty, pos$head), c(1, "arrow"))
  expect_lt(neg$lwd, pos$lwd)
  html <- as.character(htmltools::renderTags(build_full_report_html(x$schema, x$g, include_static_network = TRUE,
                                                                      network_layout = "circle", network_edge_style = "linetype"))$html)
  expect_true(grepl("on a circle", html, fixed = TRUE))
})

test_that("static network: DPSIR shapes and dashed low-confidence links, as on the Graph tab", {
  x <- fx_graph()
  # Shapes come from the model's levels (square, triangle, dot, diamond, star).
  cats <- igraph::V(x$g)$dpsir_category
  expect_true(all(network_node_shapes(cats, x$schema, FALSE) == "dot"))
  shp <- network_node_shapes(cats, x$schema, TRUE)
  expect_equal(unique(shp[cats == "Response"]), "star")
  expect_equal(unique(shp[cats == "Driver"]), "square")
  # Dashed = confidence below the threshold; 0 or NA = none.
  conf <- igraph::E(x$g)$confidence
  expect_equal(sum(network_dash_flags(x$g, 0.5)), sum(conf < 0.5))
  expect_false(any(network_dash_flags(x$g, 0)))
  expect_false(any(network_dash_flags(x$g, NA)))
  expect_identical(network_edge_look("positive", 0.45, "color", dashed = TRUE)$lty, 2)
  expect_identical(network_edge_look("negative", 0.45, "linetype", dashed = TRUE)$lty, 3)
  expect_identical(network_edge_look("negative", 0.45, "linetype", dashed = TRUE)$head, "bar")
  # The dashed links get a legend row, so the figure is a little taller.
  expect_gt(network_static_height_mm(x$g, x$schema, 190, 9, dash_below = 0.5),
            network_static_height_mm(x$g, x$schema, 190, 9))
  for (lay in c("columns", "circle")) for (es in c("color", "linetype")) {
    f <- tempfile(fileext = ".png")
    expect_silent(export_figure(function() draw_network_static(x$g, x$schema, layout = lay, edge_style = es, shapes = TRUE,
                                                               dash_below = 0.5), f, "png", 190, 150, 100, 9))
    expect_true(file.size(f) > 1000)
  }
})

test_that("the interactive graph has no 'Export as png' button (the download dialog replaces it)", {
  expect_false(any(grepl("visExport", deparse(build_network_visual))))
  expect_false(any(grepl("visExport", deparse(build_community_visual))))
  expect_true(file.exists(file.path(html2canvas_dependency()$src$file, "html2canvas.js")))
})

test_that("static network: highlight, community colours and the on-screen layout", {
  x <- fx_graph()
  g <- x$g; el <- igraph::as_edgelist(g)
  # Pathway highlight: only links between highlighted nodes stay in colour.
  v <- network_view(g, x$schema, highlight = c("D1", "P2", "S1"))
  expect_equal(sum(!v$node_dim), 3)
  expect_equal(sum(!v$edge_dim), sum(el[, 1] %in% c("D1", "P2", "S1") & el[, 2] %in% c("D1", "P2", "S1")))
  expect_true(network_edge_look("positive", 0.8, "color", dim = TRUE)$col == NETWORK_DIM_LINE)
  # Selected node: its own links, given explicitly.
  own <- el[, 1] == "S1" | el[, 2] == "S1"
  v2 <- network_view(g, x$schema, highlight = c("S1", "P1"), highlight_edges = own)
  expect_equal(sum(!v2$edge_dim), sum(own))
  # The greyed part gets a legend row; communities with shapes add the levels' row.
  expect_equal(network_legend_rows("color", v), 2)
  vc <- network_view(g, x$schema, shapes = TRUE, node_colors = c(D1 = "#ff0000"), color_legend = c("Community 1" = "#ff0000"))
  expect_equal(vc$fill[igraph::V(g)$name == "D1"], "#ff0000")
  expect_equal(network_legend_rows("color", vc), 2)
  # "As on screen": the layered layout with its spacing and a dragged node.
  pos <- compute_effective_layout(graph_to_nodes(g), x$schema, "layered", 200, 80, data.frame(id = "R5", x = 700, y = -260))
  lay <- network_screen_layout(g, x$schema, pos, 190, 9)
  expect_equal(lay$y[igraph::V(g)$name == "R5"], 260)
  wide <- compute_effective_layout(graph_to_nodes(g), x$schema, "layered", 200, 160)
  expect_gt(network_static_height_mm(g, x$schema, 190, 9, layout = "screen", positions = wide),
            network_static_height_mm(g, x$schema, 190, 9, layout = "screen", positions = pos))
  for (a in list(list(layout = "screen", positions = pos, highlight = c("D1", "P2")),
                 list(layout = "columns", node_colors = c(D1 = "#ff0000"), color_legend = c("Community 1" = "#ff0000"), shapes = TRUE),
                 list(layout = "circle", highlight = c("S1", "P1"), highlight_edges = own, edge_style = "linetype"))) {
    f <- tempfile(fileext = ".png")
    expect_silent(export_figure(function() do.call(draw_network_static, c(list(g = g, schema = x$schema), a)), f, "png", 190, 150, 100, 9))
    expect_true(file.size(f) > 1000)
  }
  # Without positions the "screen" layout falls back to the columns.
  expect_silent(export_figure(function() draw_network_static(g, x$schema, layout = "screen"), tempfile(fileext = ".png"), "png", 190, 120, 100, 9))
})
