# =====================================================
# BUILD NETWORK VISUAL
# =====================================================

build_network_visual <- function(
    nodes,
    edges,
    graph,
    ns,
    edge_weight = 1,
    edge_style = "FALSE",
    color_palette = "default",
    use_dpsir_shapes = TRUE,
    node_size_metric = "total"
) {
  
  # ===================================================
  # GET DATA
  # ===================================================
  
  # ===================================================
  # SAFETY CHECKS
  # ===================================================
  
  req(nodes)
  
  # -----------------------------------------------
  # EMPTY EDGES
  # -----------------------------------------------
  
  if (
    is.null(edges) ||
    !is.data.frame(edges)
  ) {
    
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
  
  # ===================================================
  # NORMALIZE TYPES
  # ===================================================
  
  nodes$id <- trimws(
    as.character(nodes$id)
  )

  nodes <- apply_dpsir_visual_mapping(
    nodes,
    palette = color_palette,
    use_shapes = use_dpsir_shapes
  )
  
  edges$from <- trimws(
    as.character(edges$from)
  )
  
  edges$to <- trimws(
    as.character(edges$to)
  )
  
  # ===================================================
  # REMOVE INVALID EDGES
  # ===================================================
  
  valid_nodes <- nodes$id
  
  edges <- edges[
    edges$from %in% valid_nodes &
      edges$to %in% valid_nodes,
  ]
  
  # ===================================================
  # COMPUTE NODE SIZE METRIC
  # ===================================================
  
  if (vcount(graph) > 0) {
    degree_mode <- switch(
      node_size_metric,
      incoming = "in",
      outgoing = "out",
      total = "all",
      "all"
    )
    
    deg <- compute_degree(graph, mode = degree_mode)
    
    if (length(deg) > 0) {
      
      nodes$edge_count <- deg[
        match(nodes$id, names(deg))
      ]
      
    } else {
      
      nodes$edge_count <- 0
      
    }
    
  } else {
    
    nodes$edge_count <- 0
    
  }
  
  # -----------------------------------------------
  # REPLACE NA DEGREE
  # -----------------------------------------------
  
  nodes$edge_count[
    is.na(nodes$edge_count)
  ] <- 0
  
  # ===================================================
  # NODE SIZE
  # ===================================================
  
  if (
    length(unique(nodes$edge_count)) == 1
  ) {
    
    nodes$size <- 25
    
  } else {
    
    nodes$size <- scales::rescale(
      nodes$edge_count,
      to = c(15, 45)
    )
    
  }
  
  # ===================================================
  # BUILD VISNETWORK
  # ===================================================
  
  legend_nodes <- build_dpsir_legend(
    palette = color_palette,
    use_shapes = use_dpsir_shapes
  )
  
  visNetwork(
    nodes,
    edges,
    width = "100%",
    height = "900px"
  ) %>%
    
    visNodes(
      borderWidth = 2,
      shadow = TRUE
    ) %>%
    
    visEdges(
      smooth = FALSE
    ) %>%
    
    visPhysics(
      solver = "forceAtlas2Based",
      stabilization = TRUE
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
      name = "INA_network"
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
      position = "right",
      main = "DPSIR"
    )
}

# =====================================================
# SANITIZE EDGES
# =====================================================

sanitize_edges <- function(edges, nodes){
  
  # ===================================================
  # EMPTY EDGE CASE
  # ===================================================
  
  if (
    is.null(edges) ||
    nrow(edges) == 0
  ) {
    
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
  
  # ===================================================
  # NORMALIZE NODE IDS
  # ===================================================
  
  nodes$id <- trimws(
    as.character(nodes$id)
  )
  
  # ===================================================
  # NORMALIZE EDGES
  # ===================================================
  
  edges$from <- trimws(
    as.character(edges$from)
  )
  
  edges$to <- trimws(
    as.character(edges$to)
  )
  
  # ===================================================
  # REMOVE NA
  # ===================================================
  
  edges <- edges[
    !is.na(edges$from) &
      !is.na(edges$to),
  ]
  
  # ===================================================
  # REMOVE INVALID EDGES
  # ===================================================
  
  edges <- edges[
    edges$from %in% nodes$id &
      edges$to %in% nodes$id,
  ]
  
  # ===================================================
  # REQUIRED COLUMNS
  # ===================================================
  
  if (!"id" %in% names(edges)) {
    
    edges$id <- paste0(
      "edge_",
      seq_len(nrow(edges))
    )
    
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
  
  # ===================================================
  # FORCE TYPES
  # ===================================================
  
  edges$id <- as.character(edges$id)
  
  edges$width <- as.numeric(edges$width)
  
  edges$dashes <- as.logical(edges$dashes)
  
  edges$arrows <- as.character(edges$arrows)
  
  # ===================================================
  # REMOVE DUPLICATES
  # ===================================================
  
  edges <- unique(edges)
  
  edges
}
