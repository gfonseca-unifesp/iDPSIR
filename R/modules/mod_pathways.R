pathways_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    fluidRow(
      box(
        width = 12,
        title = "DPSIR Pathway Analysis",
        status = "primary",
        solidHeader = TRUE,
        collapsible = TRUE,
        fluidRow(
          column(
            width = 4,
            selectInput(
              ns("from_category"),
              "From",
              choices = get_valid_dpsir_categories(),
              selected = "Driver"
            )
          ),
          column(
            width = 4,
            selectInput(
              ns("to_category"),
              "To",
              choices = get_valid_dpsir_categories(),
              selected = "Impact"
            )
          ),
          column(
            width = 4,
            numericInput(
              ns("top_n"),
              "Top pathways",
              value = 10,
              min = 1,
              max = 100,
              step = 1
            )
          )
        ),
        hr(),
        DTOutput(ns("pathways_table")),
        hr(),
        DTOutput(ns("response_targets_table"))
      )
    )
  )
}

pathways_server <- function(id, graph) {
  moduleServer(id, function(input, output, session) {
    pathways <- reactive({
      req(graph())

      find_dpsir_paths(
        graph(),
        from_category = input$from_category,
        to_category = input$to_category,
        max_paths = 500
      )
    })

    critical_pathways <- reactive({
      req(graph())

      compute_critical_pathways(
        graph(),
        paths = pathways(),
        top_n = input$top_n
      )
    })

    output$pathways_table <- renderDT({
      datatable(
        critical_pathways(),
        options = list(pageLength = 10, scrollX = TRUE),
        rownames = FALSE
      )
    })

    output$response_targets_table <- renderDT({
      req(graph())

      datatable(
        find_response_targets(graph()),
        options = list(pageLength = 10, scrollX = TRUE),
        rownames = FALSE
      )
    })

    list(
      pathways = pathways,
      critical_pathways = critical_pathways
    )
  })
}
