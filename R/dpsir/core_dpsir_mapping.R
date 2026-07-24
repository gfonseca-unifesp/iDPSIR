# =====================================================
# DPSIR VISUAL MAPPING
# =====================================================

get_dpsir_color_palettes <- function() {
  list(
    default = c(
      Driver = "#1f77b4",
      Pressure = "#d62728",
      State = "#2ca02c",
      Impact = "#ff7f0e",
      Response = "#9467bd"
    ),
    colorblind = c(
      Driver = "#0072B2",
      Pressure = "#D55E00",
      State = "#009E73",
      Impact = "#E69F00",
      Response = "#CC79A7"
    ),
    muted = c(
      Driver = "#4E79A7",
      Pressure = "#E15759",
      State = "#59A14F",
      Impact = "#F28E2B",
      Response = "#B07AA1"
    ),
    high_contrast = c(
      Driver = "#0050A4",
      Pressure = "#B00020",
      State = "#00843D",
      Impact = "#C75B12",
      Response = "#6A1B9A"
    )
  )
}

get_dpsir_palette_choices <- function() {
  c(
    "Default" = "default",
    "Colorblind safe" = "colorblind",
    "Muted" = "muted",
    "High contrast" = "high_contrast"
  )
}

get_dpsir_colors <- function(palette = "default") {
  palettes <- get_dpsir_color_palettes()

  if (!palette %in% names(palettes)) {
    stop("Unknown DPSIR color palette.", call. = FALSE)
  }

  palettes[[palette]]
}

get_dpsir_shapes <- function() {
  c(
    Driver = "square",
    Pressure = "triangle",
    State = "dot",
    Impact = "diamond",
    Response = "star"
  )
}

validate_dpsir_category <- function(category) {
  invalid <- is.na(category) | !category %in% get_valid_dpsir_categories()

  if (any(invalid)) {
    stop(
      paste(
        "Invalid DPSIR categories:",
        paste(unique(category[invalid]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

assign_dpsir_colors <- function(nodes, palette = "default") {
  validate_required_fields(nodes, "dpsir_category", "Nodes table")
  validate_dpsir_category(nodes$dpsir_category)

  colors <- get_dpsir_colors(palette)
  nodes$color <- unname(colors[nodes$dpsir_category])

  nodes
}

assign_dpsir_shapes <- function(nodes, use_shapes = TRUE) {
  validate_required_fields(nodes, "dpsir_category", "Nodes table")
  validate_dpsir_category(nodes$dpsir_category)

  if (isTRUE(use_shapes)) {
    shapes <- get_dpsir_shapes()
    nodes$shape <- unname(shapes[nodes$dpsir_category])
  } else {
    nodes$shape <- "dot"
  }

  nodes
}

assign_dpsir_groups <- function(nodes) {
  validate_required_fields(nodes, "dpsir_category", "Nodes table")
  validate_dpsir_category(nodes$dpsir_category)

  nodes$group <- nodes$dpsir_category
  nodes
}

apply_dpsir_visual_mapping <- function(
    nodes,
    palette = "default",
    use_shapes = TRUE
) {
  nodes <- assign_dpsir_groups(nodes)
  nodes <- assign_dpsir_colors(nodes, palette = palette)
  nodes <- assign_dpsir_shapes(nodes, use_shapes = use_shapes)
  nodes
}

build_dpsir_legend <- function(
    palette = "default",
    use_shapes = TRUE
) {
  categories <- get_valid_dpsir_categories()
  shapes <- if (isTRUE(use_shapes)) {
    unname(get_dpsir_shapes()[categories])
  } else {
    rep("dot", length(categories))
  }

  data.frame(
    label = categories,
    color = unname(get_dpsir_colors(palette)[categories]),
    shape = shapes,
    stringsAsFactors = FALSE
  )
}
