# =====================================================
# INA - CENTRALITY MODULE
# Professional Scientific Version
# =====================================================

# =====================================================
# UI
# =====================================================

centrality_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    fluidRow(
      box(
        width = 12,
        title = "Centrality Analysis",
        status = "primary",
        solidHeader = TRUE,
        collapsible = TRUE,

        # =========================================
        # METRIC SELECTION
        # =========================================

        fluidRow(
          column(
            width = 6,
            checkboxGroupInput(
              ns("metrics"),
              "Centrality Metrics",
              choices = c(
                "Degree" = "degree",
                "Betweenness" = "betweenness",
                "Closeness" = "closeness",
                "Eigenvector" = "eigenvector",
                "PageRank" = "pagerank"
              ),
              selected = c(
                "degree",
                "betweenness",
                "pagerank"
              )
            )
          ),
          column(
            width = 3,
            ina_toggle_directed(
              ns("directed")
            )
          ),
          column(
            width = 3,
            ina_toggle_normalized(
              ns("normalized")
            )
          )
        ),
        hr(),

        # =========================================
        # CENTRALITY TABLE
        # =========================================

        DTOutput(
          ns("centrality_table")
        )
      )
    )
  )
}

# =====================================================
# SERVER
# =====================================================

centrality_server <- function(id, graph) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # =================================================
    # CENTRALITY COMPUTATION
    # =================================================

    centralities <- reactive({
      req(graph())

      g <- graph()

      validate(
        need(
          vcount(g) > 0,
          "Graph contains no nodes."
        )
      )

      # =============================================
      # DIRECTED OPTION
      # =============================================

      if (isTRUE(input$directed)) {
        g_analysis <- g
      } else {
        g_analysis <- as.undirected(g)
      }

      # =============================================
      # INITIAL DATAFRAME
      # =============================================

      node_labels <- vertex_attr(
        g_analysis,
        "label"
      )
      
      if(is.null(node_labels)){
        node_labels <- V(g_analysis)$name
      }
      
      result <- data.frame(
        
        id = V(g_analysis)$name,
        
        node = node_labels,
        
        stringsAsFactors = FALSE
      )

      # =============================================
      # DEGREE
      # =============================================

      if ("degree" %in% input$metrics) {
        result$degree <- round(
          compute_degree(
            g_analysis
          ),
          4
        )
      }

      # =============================================
      # BETWEENNESS
      # =============================================

      if ("betweenness" %in% input$metrics) {
        result$betweenness <- round(
          compute_betweenness(
            g_analysis,
            normalized = input$normalized
          ),
          4
        )
      }

      # =============================================
      # CLOSENESS
      # =============================================

      if ("closeness" %in% input$metrics) {
        result$closeness <- round(
          compute_closeness(
            g_analysis,
            normalized = input$normalized
          ),
          4
        )
      }

      # =============================================
      # EIGENVECTOR
      # =============================================

      if ("eigenvector" %in% input$metrics) {
        result$eigenvector <- round(
          compute_eigenvector(
            g_analysis
          ),
          4
        )
      }

      # =============================================
      # PAGERANK
      # =============================================

      if ("pagerank" %in% input$metrics) {
        result$pagerank <- round(
          compute_pagerank(
            g_analysis
          ),
          6
        )
      }

      # =============================================
      # METADATA
      # =============================================

      result$directed <- input$directed

      result$normalized <- input$normalized

      result
    })

    # =================================================
    # TABLE RENDER
    # =================================================

    output$centrality_table <- renderDT({
      
      df <- centralities()
      
      numeric_cols <- names(df)[
        sapply(df, is.numeric)
      ]
      
      table <- datatable(
        df,
        extensions = c(
          "Buttons",
          "Scroller"
        ),
        filter = "top",
        options = list(
          dom = "Bfrtip",
          buttons = c(
            "csv",
            "excel"
          ),
          pageLength = 20,
          scrollX = TRUE,
          deferRender = TRUE,
          scroller = TRUE
        ),
        rownames = FALSE
      )
      
      if(length(numeric_cols) > 0){
        
        table <- table %>%
          formatRound(
            columns = numeric_cols,
            digits = 4
          )
        
      }
      
      table
    })
    # =================================================
    # RETURN
    # =================================================

    return(
      list(
        centralities = centralities
      )
    )
  })
}
