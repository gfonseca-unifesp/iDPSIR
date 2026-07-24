# =====================================================
# MOD_GRAPH - GRAPH EXPLORATION PANEL (layered layout)
# =====================================================
#
# Lightweight panel (not a wizard step): receives schema/nodes/edges/graph
# from mod_data and applies filters (subsystem, temporal scale) + display
# options (palette, node/edge emphasis, spacing), without altering the
# saved project state.

mod_graph_ui <- function(id) {
  ns <- NS(id)

  box(
    width = 12,
    title = "Graph",
    status = "primary",
    solidHeader = TRUE,

    fluidRow(
      column(width = 3, selectInput(ns("palette"), "Color palette", choices = get_dpsir_palette_choices())),
      column(width = 3, checkboxInput(ns("use_shapes"), "Use DPSIR shapes", value = TRUE)),
      column(width = 3, selectInput(ns("subsystem_filter"), "Subsystem", choices = "All")),
      column(width = 3, selectInput(ns("temporal_filter"), "Temporal scale", choices = "All"))
    ),

    tags$hr(),
    fluidRow(
      column(
        width = 3,
        selectInput(
          ns("node_size_mode"), "Node size based on",
          choices = c("Total degree" = "all", "Incoming edges" = "in", "Outgoing edges" = "out")
        )
      ),
      column(width = 3, checkboxInput(ns("node_size_weighted"), "Size by edge weight (strength)", value = FALSE)),
      column(
        width = 3,
        selectInput(
          ns("edge_width_by"), "Edge width based on",
          choices = c("Edge weight" = "weight", "Confidence" = "confidence", "Fixed" = "fixed")
        )
      ),
      column(width = 3, sliderInput(ns("confidence_threshold"), "Dash edges below confidence", min = 0, max = 1, value = 0.5, step = 0.05))
    ),

    tags$hr(),
    fluidRow(
      column(width = 4, sliderInput(ns("x_spacing"), "Horizontal spacing between categories", min = 100, max = 500, value = 200, step = 25)),
      column(width = 4, sliderInput(ns("y_spacing"), "Vertical spacing between nodes", min = 30, max = 250, value = 80, step = 10)),
      column(width = 4, sliderInput(ns("avoid_overlap"), "Avoid node overlap", min = 0, max = 1, value = 0.5, step = 0.1))
    ),

    tags$hr(),
    fluidRow(
      column(width = 6, sliderInput(ns("node_font_size"), "Graph label font size", min = 8, max = 40, value = 14, step = 1)),
      column(width = 6, sliderInput(ns("legend_font_size"), "Legend font size", min = 8, max = 40, value = 14, step = 1))
    ),

    visNetworkOutput(ns("network"), height = "700px")
  )
}

mod_graph_server <- function(id, schema, nodes, edges, graph) {
  moduleServer(id, function(input, output, session) {
    observeEvent(nodes(), {
      n <- nodes()

      subsystems <- sort(unique(n$subsystem[nzchar(n$subsystem)]))
      updateSelectInput(session, "subsystem_filter", choices = c("All", subsystems), selected = "All")

      temporals <- sort(unique(n$temporal_scale[nzchar(n$temporal_scale)]))
      updateSelectInput(session, "temporal_filter", choices = c("All", temporals), selected = "All")
    })

    filtered_nodes <- reactive({
      n <- nodes()

      if (!is.null(input$subsystem_filter) && input$subsystem_filter != "All") {
        n <- n[n$subsystem == input$subsystem_filter, ]
      }

      if (!is.null(input$temporal_filter) && input$temporal_filter != "All") {
        n <- n[n$temporal_scale == input$temporal_filter, ]
      }

      n
    })

    filtered_edges <- reactive({
      n <- filtered_nodes()
      e <- edges()
      e[e$from %in% n$id & e$to %in% n$id, ]
    })

    filtered_graph <- reactive({
      n <- filtered_nodes()
      if (nrow(n) == 0) return(NULL)

      tryCatch(
        build_igraph(n, filtered_edges(), schema()),
        error = function(e) NULL
      )
    })

    output$network <- renderVisNetwork({
      req(graph())
      req(filtered_graph())

      display_schema <- apply_schema_palette(schema(), input$palette)

      build_network_visual(
        nodes = filtered_nodes(),
        edges = filtered_edges(),
        graph = filtered_graph(),
        schema = display_schema,
        use_dpsir_shapes = input$use_shapes,
        node_size_mode = input$node_size_mode,
        node_size_weighted = input$node_size_weighted,
        edge_width_by = input$edge_width_by,
        confidence_threshold = input$confidence_threshold,
        x_spacing = input$x_spacing,
        y_spacing = input$y_spacing,
        avoid_overlap = input$avoid_overlap,
        node_font_size = input$node_font_size,
        legend_font_size = input$legend_font_size
      )
    })
  })
}
