# =====================================================
# GRAFO - CONSTRUCAO, LAYOUT EM CAMADAS E VISUAL
# =====================================================

# =====================================================
# BUILD IGRAPH
# =====================================================

create_empty_graph_edges <- function() {
  data.frame(
    from = character(),
    to = character(),
    weight = numeric(),
    confidence = numeric(),
    threshold = numeric(),
    arrows = character(),
    width = numeric(),
    stringsAsFactors = FALSE
  )
}

prepare_nodes_for_graph <- function(nodes, schema) {
  nodes <- normalize_dpsir_nodes(nodes)
  nodes <- apply_schema_visual_mapping(nodes, schema)
  nodes
}

prepare_edges_for_graph <- function(edges) {
  if (is.null(edges) || nrow(edges) == 0) {
    edges <- create_empty_graph_edges()
  }

  edges <- normalize_dpsir_edges(edges)

  if (!"weight" %in% names(edges)) {
    edges$weight <- if (nrow(edges) == 0) numeric() else 1
  }

  if (!"confidence" %in% names(edges)) {
    edges$confidence <- if (nrow(edges) == 0) numeric() else 1
  }

  if (!"arrows" %in% names(edges)) {
    edges$arrows <- if (nrow(edges) == 0) character() else "to"
  }

  if (!"width" %in% names(edges)) {
    edges$width <- if (nrow(edges) == 0) {
      numeric()
    } else {
      pmax(as.numeric(edges$weight), 1)
    }
  }

  edges
}

build_igraph <- function(
    nodes,
    edges = NULL,
    schema = get_default_dpsir_schema(),
    verbose = FALSE
) {
  validate_graph_inputs(nodes, edges, schema)

  nodes <- prepare_nodes_for_graph(nodes, schema)
  edges <- prepare_edges_for_graph(edges)

  if (verbose) {
    message("Building DPSIR graph with ", nrow(nodes), " nodes and ", nrow(edges), " edges.")
  }

  g <- graph_from_data_frame(
    d = edges,
    vertices = nodes,
    directed = TRUE
  )

  graph_attr(g, "network_type") <- "DPSIR"
  graph_attr(g, "directed") <- TRUE
  graph_attr(g, "created_at") <- Sys.time()

  g
}

graph_to_nodes <- function(g) {
  stopifnot(inherits(g, "igraph"))
  nodes <- igraph::as_data_frame(g, what = "vertices")
  names(nodes)[names(nodes) == "name"] <- "id"
  nodes
}

graph_to_edges <- function(g) {
  stopifnot(inherits(g, "igraph"))
  igraph::as_data_frame(g, what = "edges")
}

# =====================================================
# MAPEAMENTO VISUAL (SCHEMA-DRIVEN)
# =====================================================

apply_schema_visual_mapping <- function(nodes, schema, use_shapes = TRUE) {
  validate_required_fields(nodes, "dpsir_category", "Nodes table")
  validate_dpsir_categories(nodes, schema)

  colors <- schema_colors(schema)
  shapes <- schema_shapes(schema)

  nodes$group <- nodes$dpsir_category
  nodes$color <- unname(colors[nodes$dpsir_category])
  nodes$shape <- if (isTRUE(use_shapes)) {
    unname(shapes[nodes$dpsir_category])
  } else {
    "dot"
  }

  nodes
}

# =====================================================
# LAYOUT EM CAMADAS (POSICAO X FIXA POR NIVEL)
# =====================================================

compute_layered_layout <- function(nodes, schema, x_spacing = 200, y_spacing = 80) {
  validate_schema(schema)

  categories <- schema_categories(schema)
  order_index <- setNames(seq_along(categories), categories)

  category_rank <- unname(order_index[nodes$dpsir_category])
  x <- category_rank * x_spacing

  y <- ave(seq_len(nrow(nodes)), category_rank, FUN = function(idx) {
    n <- length(idx)
    (seq_len(n) - (n + 1) / 2) * y_spacing
  })

  data.frame(id = nodes$id, x = x, y = y, stringsAsFactors = FALSE)
}

# =====================================================
# TOOLTIPS
# =====================================================

build_node_tooltip <- function(nodes) {
  glue::glue(
    "<b>{nodes$label}</b><br>",
    "Category: {nodes$dpsir_category}<br>",
    "Subsystem: {ifelse(is.na(nodes$subsystem) | nodes$subsystem == '', '-', nodes$subsystem)}<br>",
    "Uncertainty: {ifelse(is.na(nodes$uncertainty) | nodes$uncertainty == '', '-', nodes$uncertainty)}<br>",
    "Controllability: {ifelse(is.na(nodes$controllability) | nodes$controllability == '', '-', nodes$controllability)}<br>",
    "Temporal scale: {ifelse(is.na(nodes$temporal_scale) | nodes$temporal_scale == '', '-', nodes$temporal_scale)}"
  )
}

build_edge_tooltip <- function(edges) {
  glue::glue(
    "{edges$from} &rarr; {edges$to}<br>",
    "Weight: {ifelse(is.na(edges$weight), '-', edges$weight)}<br>",
    "Confidence: {ifelse(is.na(edges$confidence), '-', edges$confidence)}<br>",
    "Interaction: {ifelse(is.na(edges$interaction_type) | edges$interaction_type == '', '-', edges$interaction_type)}<br>",
    "Evidence: {ifelse(is.na(edges$evidence_type) | edges$evidence_type == '', '-', edges$evidence_type)}<br>",
    "Threshold: {ifelse(is.na(edges$threshold), '-', edges$threshold)}"
  )
}

# =====================================================
# BUILD NETWORK VISUAL
# =====================================================

get_interaction_type_colors <- function() {
  c(
    positive = "#d62728",
    negative = "#2ca02c"
  )
}

build_edge_legend <- function(confidence_threshold = 0.5) {
  colors <- get_interaction_type_colors()

  legend <- data.frame(
    label = names(colors),
    color = unname(colors),
    arrows = "to",
    dashes = FALSE,
    stringsAsFactors = FALSE
  )

  rbind(
    legend,
    data.frame(
      label = paste0("Low confidence (< ", confidence_threshold, ")"),
      color = "#848484",
      arrows = "to",
      dashes = TRUE,
      stringsAsFactors = FALSE
    )
  )
}

rescale_safe <- function(x, to) {
  x <- as.numeric(x)

  if (length(unique(x)) <= 1) {
    return(rep(mean(to), length(x)))
  }

  scales::rescale(x, to = to)
}

# =====================================================
# SHARED HELPERS (used by build_network_visual and
# build_community_visual)
# =====================================================

size_nodes_by_degree <- function(nodes, graph, node_size_mode = "all", node_size_weighted = FALSE) {
  if (vcount(graph) > 0) {
    deg <- compute_degree(graph, mode = node_size_mode, weighted = node_size_weighted)

    nodes$edge_count <- if (length(deg) > 0) {
      deg[match(nodes$id, names(deg))]
    } else {
      0
    }
  } else {
    nodes$edge_count <- 0
  }

  nodes$edge_count[is.na(nodes$edge_count)] <- 0
  nodes$size <- rescale_safe(nodes$edge_count, to = c(15, 45))
  nodes
}

border_by_uncertainty <- function(nodes) {
  uncertainty_border <- c(low = 1, medium = 2.5, high = 4)
  nodes$borderWidth <- unname(uncertainty_border[nodes$uncertainty])
  nodes$borderWidth[is.na(nodes$borderWidth)] <- 2
  nodes
}

style_edges_for_visual <- function(edges, edge_width_by = "weight", confidence_threshold = 0.5) {
  if (nrow(edges) == 0) {
    return(edges)
  }

  edges$arrows <- "to"

  edges$width <- switch(
    edge_width_by,
    weight = rescale_safe(edges$weight, to = c(1, 8)),
    confidence = rescale_safe(edges$confidence, to = c(1, 8)),
    rep(2, nrow(edges))
  )

  edges$dashes <- !is.na(edges$confidence) & edges$confidence < confidence_threshold

  interaction_colors <- get_interaction_type_colors()
  edges$color <- unname(interaction_colors[edges$interaction_type])
  edges$color[is.na(edges$color)] <- "#848484"

  edges$title <- build_edge_tooltip(edges)

  edges
}

# =====================================================
# PATHWAY HIGHLIGHT (grey out everything outside the set)
# =====================================================

apply_highlight <- function(nodes, edges, highlighted_nodes) {
  if (is.null(highlighted_nodes) || length(highlighted_nodes) == 0) {
    return(list(nodes = nodes, edges = edges))
  }

  is_highlighted_node <- nodes$id %in% highlighted_nodes
  nodes$color[!is_highlighted_node] <- "#dddddd"
  nodes$borderWidth <- ifelse(is_highlighted_node, pmax(nodes$borderWidth, 3), 1)

  if (nrow(edges) > 0) {
    is_highlighted_edge <- edges$from %in% highlighted_nodes & edges$to %in% highlighted_nodes
    edges$color[!is_highlighted_edge] <- "#e8e8e8"
    edges$width <- ifelse(is_highlighted_edge, edges$width * 1.5, pmin(edges$width, 1))
  }

  list(nodes = nodes, edges = edges)
}

build_network_visual <- function(
    nodes,
    edges,
    graph,
    schema,
    use_dpsir_shapes = TRUE,
    node_size_mode = "all",
    node_size_weighted = FALSE,
    edge_width_by = "weight",
    confidence_threshold = 0.5,
    x_spacing = 200,
    y_spacing = 80,
    avoid_overlap = 0.5,
    node_font_size = 14,
    legend_font_size = 14,
    highlighted_nodes = NULL
) {
  req(nodes)

  if (is.null(edges) || !is.data.frame(edges)) {
    edges <- data.frame(
      id = character(),
      from = character(),
      to = character(),
      width = numeric(),
      dashes = logical(),
      arrows = character(),
      stringsAsFactors = FALSE
    )
  }

  nodes$id <- trimws(as.character(nodes$id))
  nodes <- apply_schema_visual_mapping(nodes, schema, use_shapes = use_dpsir_shapes)

  edges$from <- trimws(as.character(edges$from))
  edges$to <- trimws(as.character(edges$to))

  valid_nodes <- nodes$id
  edges <- edges[edges$from %in% valid_nodes & edges$to %in% valid_nodes, ]

  # ===================================================
  # LAYERED LAYOUT (fixed X per category, free Y)
  # ===================================================

  layout <- compute_layered_layout(nodes, schema, x_spacing = x_spacing, y_spacing = y_spacing)
  nodes <- merge(nodes, layout, by = "id", sort = FALSE)
  nodes$`fixed.x` <- TRUE
  nodes$`fixed.y` <- FALSE

  # ===================================================
  # NODE SIZE (degree, optionally weighted by edge strength)
  # ===================================================

  nodes <- size_nodes_by_degree(nodes, graph, node_size_mode, node_size_weighted)

  # ===================================================
  # UNCERTAINTY -> BORDER WIDTH
  # ===================================================

  nodes <- border_by_uncertainty(nodes)

  # ===================================================
  # NODE TOOLTIP AND LABEL FONT SIZE
  # ===================================================

  nodes$title <- build_node_tooltip(nodes)
  nodes$`font.size` <- node_font_size

  # ===================================================
  # EDGES: DIRECTION ARROW, WIDTH, DASH BY CONFIDENCE,
  # COLOR BY INTERACTION TYPE
  # ===================================================

  edges <- style_edges_for_visual(edges, edge_width_by, confidence_threshold)

  # ===================================================
  # PATHWAY HIGHLIGHT (optional)
  # ===================================================

  highlighted <- apply_highlight(nodes, edges, highlighted_nodes)
  nodes <- highlighted$nodes
  edges <- highlighted$edges

  # ===================================================
  # LEGEND AND RENDER
  # ===================================================

  legend_nodes <- build_dpsir_legend(schema)
  legend_nodes$`font.size` <- legend_font_size

  legend_edges <- build_edge_legend(confidence_threshold)
  legend_edges$`font.size` <- legend_font_size

  visNetwork(
    nodes,
    edges,
    width = "100%",
    height = "900px"
  ) %>%
    visNodes(
      shadow = TRUE
    ) %>%
    visEdges(
      smooth = FALSE
    ) %>%
    visPhysics(
      solver = "forceAtlas2Based",
      stabilization = TRUE,
      forceAtlas2Based = list(avoidOverlap = avoid_overlap)
    ) %>%
    visLayout(
      randomSeed = 123
    ) %>%
    visInteraction(
      navigationButtons = TRUE,
      keyboard = TRUE,
      multiselect = TRUE
    ) %>%
    visExport(
      type = "png",
      name = "iDPSIR_network"
    ) %>%
    visOptions(
      highlightNearest = list(
        enabled = TRUE,
        hover = TRUE
      ),
      selectedBy = "group"
    ) %>%
    visLegend(
      useGroups = FALSE,
      addNodes = legend_nodes,
      addEdges = legend_edges,
      position = "right",
      main = "DPSIR"
    )
}

# =====================================================
# COMMUNITY VISUAL (grouped/colored by community membership
# instead of DPSIR category, same layered positions so it
# can be visually compared with the main graph)
# =====================================================

build_community_legend <- function(membership) {
  communities <- sort(unique(membership))
  palette <- scales::hue_pal()(length(communities))

  data.frame(
    label = paste("Community", communities),
    color = palette,
    shape = "dot",
    stringsAsFactors = FALSE
  )
}

build_community_visual <- function(
    nodes,
    edges,
    graph,
    schema,
    membership,
    node_size_mode = "all",
    node_size_weighted = FALSE,
    edge_width_by = "weight",
    confidence_threshold = 0.5,
    x_spacing = 200,
    y_spacing = 80,
    avoid_overlap = 0.5,
    node_font_size = 14,
    legend_font_size = 14
) {
  req(nodes)

  if (is.null(edges) || !is.data.frame(edges)) {
    edges <- data.frame(
      id = character(),
      from = character(),
      to = character(),
      width = numeric(),
      dashes = logical(),
      arrows = character(),
      stringsAsFactors = FALSE
    )
  }

  nodes$id <- trimws(as.character(nodes$id))
  edges$from <- trimws(as.character(edges$from))
  edges$to <- trimws(as.character(edges$to))

  valid_nodes <- nodes$id
  edges <- edges[edges$from %in% valid_nodes & edges$to %in% valid_nodes, ]

  # ===================================================
  # COLOR/GROUP BY COMMUNITY (same layered X/Y as the main graph)
  # ===================================================

  community_labels <- setNames(paste("Community", unname(membership)), names(membership))
  nodes$group <- unname(community_labels[nodes$id])

  legend_nodes <- build_community_legend(membership)
  community_colors <- setNames(legend_nodes$color, legend_nodes$label)
  nodes$color <- unname(community_colors[nodes$group])
  nodes$shape <- "dot"

  layout <- compute_layered_layout(nodes, schema, x_spacing = x_spacing, y_spacing = y_spacing)
  nodes <- merge(nodes, layout, by = "id", sort = FALSE)
  nodes$`fixed.x` <- TRUE
  nodes$`fixed.y` <- FALSE

  nodes <- size_nodes_by_degree(nodes, graph, node_size_mode, node_size_weighted)
  nodes <- border_by_uncertainty(nodes)

  nodes$title <- build_node_tooltip(nodes)
  nodes$`font.size` <- node_font_size

  edges <- style_edges_for_visual(edges, edge_width_by, confidence_threshold)

  legend_nodes$`font.size` <- legend_font_size
  legend_edges <- build_edge_legend(confidence_threshold)
  legend_edges$`font.size` <- legend_font_size

  visNetwork(
    nodes,
    edges,
    width = "100%",
    height = "900px"
  ) %>%
    visNodes(
      shadow = TRUE
    ) %>%
    visEdges(
      smooth = FALSE
    ) %>%
    visPhysics(
      solver = "forceAtlas2Based",
      stabilization = TRUE,
      forceAtlas2Based = list(avoidOverlap = avoid_overlap)
    ) %>%
    visLayout(
      randomSeed = 123
    ) %>%
    visInteraction(
      navigationButtons = TRUE,
      keyboard = TRUE,
      multiselect = TRUE
    ) %>%
    visExport(
      type = "png",
      name = "iDPSIR_communities"
    ) %>%
    visOptions(
      highlightNearest = list(
        enabled = TRUE,
        hover = TRUE
      ),
      selectedBy = "group"
    ) %>%
    visLegend(
      useGroups = FALSE,
      addNodes = legend_nodes,
      addEdges = legend_edges,
      position = "right",
      main = "Community"
    )
}

# =====================================================
# SANITIZE EDGES
# =====================================================

sanitize_edges <- function(edges, nodes) {
  if (is.null(edges) || nrow(edges) == 0) {
    return(
      data.frame(
        id = character(),
        from = character(),
        to = character(),
        width = numeric(),
        dashes = logical(),
        arrows = character(),
        stringsAsFactors = FALSE
      )
    )
  }

  nodes$id <- trimws(as.character(nodes$id))
  edges$from <- trimws(as.character(edges$from))
  edges$to <- trimws(as.character(edges$to))

  edges <- edges[!is.na(edges$from) & !is.na(edges$to), ]
  edges <- edges[edges$from %in% nodes$id & edges$to %in% nodes$id, ]

  if (!"id" %in% names(edges)) {
    edges$id <- paste0("edge_", seq_len(nrow(edges)))
  }

  if (!"width" %in% names(edges)) {
    edges$width <- 1
  }

  if (!"dashes" %in% names(edges)) {
    edges$dashes <- FALSE
  }

  if (!"arrows" %in% names(edges)) {
    edges$arrows <- "to"
  }

  edges$id <- as.character(edges$id)
  edges$width <- as.numeric(edges$width)
  edges$dashes <- as.logical(edges$dashes)
  edges$arrows <- as.character(edges$arrows)

  edges <- unique(edges)
  edges
}
