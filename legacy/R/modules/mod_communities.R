# =====================================================
# MOD_COMMUNITIES - COMMUNITY DETECTION TAB (drawn with edges)
# =====================================================
#
# Fixes the pre-Fase-1 version, which plotted community membership as bare
# colored dots with no edges - making the grouping visually unverifiable.
# Reuses the same layered layout as the main graph (compute_layered_layout)
# so the two views are visually comparable.

mod_communities_ui <- function(id) {
  ns <- NS(id)

  box(
    width = 12,
    title = "Communities",
    status = "primary",
    solidHeader = TRUE,

    fluidRow(
      column(
        width = 4,
        selectInput(
          ns("algorithm"), "Algorithm",
          choices = c("Louvain", "Walktrap", "Infomap", "Label Propagation"),
          selected = "Louvain"
        )
      )
    ),

    visNetworkOutput(ns("network"), height = "700px"),
    tags$hr(),
    DTOutput(ns("membership_table"))
  )
}

mod_communities_server <- function(id, schema, nodes, edges, graph) {
  moduleServer(id, function(input, output, session) {
    community_result <- reactive({
      req(graph())
      g <- graph()

      # Louvain and Label Propagation are undefined for directed graphs;
      # converted to undirected to avoid an error.
      switch(
        input$algorithm,
        "Louvain" = cluster_louvain(as.undirected(g)),
        "Walktrap" = cluster_walktrap(g),
        "Infomap" = cluster_infomap(g),
        "Label Propagation" = cluster_label_prop(as.undirected(g))
      )
    })

    membership_vector <- reactive({
      membership(community_result())
    })

    output$network <- renderVisNetwork({
      req(graph())

      build_community_visual(
        nodes = nodes(),
        edges = edges(),
        graph = graph(),
        schema = schema(),
        membership = membership_vector()
      )
    })

    output$membership_table <- renderDT({
      req(graph())

      mem <- membership_vector()
      n <- nodes()

      df <- data.frame(
        id = names(mem),
        label = n$label[match(names(mem), n$id)],
        community = as.integer(mem),
        stringsAsFactors = FALSE
      )

      datatable(df, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
    })
  })
}
