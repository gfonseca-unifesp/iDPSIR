communities_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    fluidRow(
      box(
        width = 12,
        title = "Community Detection",
        status = "primary",
        solidHeader = TRUE,
        collapsible = TRUE,
        fluidRow(
          column(
            width = 4,
            selectInput(
              ns("algorithm"),
              "Community Algorithm",
              choices = c(
                "Louvain",
                "Walktrap",
                "Infomap",
                "Label Propagation"
              ),
              selected = "Louvain"
            )
          ),
          column(
            width = 4,
            ina_toggle_directed(
              ns("directed")
            )
          )
        ),
        hr(),
        plotlyOutput(
          ns("community_plot"),
          height = "700px"
        ),
        hr(),
        DTOutput(
          ns("community_table")
        )
      )
    )
  )
}

communities_server <- function(id, graph) {
  moduleServer(id, function(input, output, session) {
    # ============================================
    # GRAPH PREPARATION
    # ============================================

    graph_ready <- reactive({
      req(graph())

      g <- graph()

      validate(
        need(vcount(g) > 0, "Graph is empty.")
      )

      if (input$directed) {
        g
      } else {
        as.undirected(g)
      }
    })

    # ============================================
    # LAYOUT CACHE
    # ============================================

    layout_coords <- reactive({
      set.seed(123)

      layout_with_fr(
        graph_ready()
      )
    })

    # ============================================
    # COMMUNITY DETECTION
    # ============================================

    community_result <- reactive({
      g <- graph_ready()

      # Louvain e Label Propagation não são definidos para grafos direcionados;
      # convertidos para não-direcionado para evitar erro quando "Directed" está ativo.
      switch(input$algorithm,
        "Louvain" = cluster_louvain(as.undirected(g)),
        "Walktrap" = cluster_walktrap(g),
        "Infomap" = cluster_infomap(g),
        "Label Propagation" = cluster_label_prop(as.undirected(g))
      )
    })

    # ============================================
    # COMMUNITY TABLE
    # ============================================

    community_table <- reactive({
      
      g <- graph_ready()
      
      comm <- community_result()
      
      node_labels <- vertex_attr(
        g,
        "label"
      )
      
      if(is.null(node_labels)){
        node_labels <- V(g)$name
      }
      
      tibble(
        
        id = V(g)$name,
        
        node = node_labels,
        
        community = membership(comm)
      )
    })

    # ============================================
    # COMMUNITY PLOT
    # ============================================

    output$community_plot <- renderPlotly({
      g <- graph_ready()

      coords <- layout_coords()

      comm <- community_result()

      df_nodes <- data.frame(
        
        x = coords[, 1],
        y = coords[, 2],
        
        node = if(
          is.null(vertex_attr(g, "label"))
        ){
          V(g)$name
        } else {
          vertex_attr(g, "label")
        },
        
        community = as.factor(
          membership(comm)
        )
      )
      

      plot_ly(
        data = df_nodes,
        x = ~x,
        y = ~y,
        type = "scatter",
        mode = "markers+text",
        color = ~community,
        text = ~node,
        textposition = "top center",
        hoverinfo = "text"
      )
    })

    # ============================================
    # TABLE
    # ============================================

    output$community_table <- renderDT({
      datatable(
        community_table(),
        extensions = "Buttons",
        options = list(
          dom = "Bfrtip",
          buttons = c(
            "csv",
            "excel"
          ),
          pageLength = 20,
          scrollX = TRUE
        )
      )
    })

    # ============================================
    # RETURN
    # ============================================

    return(
      list(
        communities = community_result,
        membership = community_table
      )
    )
  })
}
