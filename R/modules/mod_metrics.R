metrics_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    DTOutput(ns("metrics_table")),
    hr(),
    DTOutput(ns("top_nodes_table"))
  )
}

metrics_server <- function(id, graph) {
  moduleServer(id, function(input, output, session) {
    output$metrics_table <- renderDT({
      g <- graph()
      validate(need(!is.null(g) && vcount(g) > 0, "Construa o grafo para ver as métricas."))

      metrics <- compute_all_metrics(g)

      datatable(
        metrics,
        extensions = "Buttons",
        options = list(
          dom = "Bfrtip",
          buttons = c("csv", "excel")
        )
      )
    })

    output$top_nodes_table <- renderDT({
      g <- graph()
      validate(need(!is.null(g) && vcount(g) > 0, "Construa o grafo para ver as métricas."))

      metrics <- compute_all_metrics(g)
      top_nodes <- metrics[order(
        -metrics$degree,
        -metrics$pagerank
      ), ]

      datatable(
        head(top_nodes, 10),
        options = list(
          pageLength = 10,
          scrollX = TRUE
        ),
        rownames = FALSE
      )
    })
  })
}
