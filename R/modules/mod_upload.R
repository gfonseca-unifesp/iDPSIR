upload_ui <- function(id) {
  ns <- NS(id)

  tagList(
    fileInput(
      ns("nodes_file"),
      "Upload Nodes CSV",
      accept = ".csv"
    ),
    fileInput(
      ns("edges_file"),
      "Optional Edge Table",
      accept = ".csv"
    ),
    tags$hr(),
    helpText(
      "Edges can be created interactively inside INA."
    )
  )
}

upload_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    nodes <- reactive({
      req(input$nodes_file)

      fread(input$nodes_file$datapath)
    })

    edges <- reactive({
      if (is.null(input$edges_file)) {
        return(
          data.frame(
            id = character(),
            from = character(),
            to = character(),
            weight = numeric(),
            width = numeric(),
            dashes = logical(),
            arrows = character(),
            stringsAsFactors = FALSE
          )
        )
      }

      fread(
        input$edges_file$datapath
      )
    })

    return(list(
      nodes = nodes,
      edges = edges
    ))
  })
}
