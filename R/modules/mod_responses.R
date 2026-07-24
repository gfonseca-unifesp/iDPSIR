responses_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    fluidRow(
      box(
        width = 12,
        title = "DPSIR Response Simulation",
        status = "primary",
        solidHeader = TRUE,
        collapsible = TRUE,
        fluidRow(
          column(
            width = 4,
            selectInput(
              ns("response_id"),
              "Response node",
              choices = character()
            )
          ),
          column(
            width = 3,
            selectInput(
              ns("mode"),
              "Mode",
              choices = c("Mitigate" = "mitigate", "Amplify" = "amplify"),
              selected = "mitigate"
            )
          ),
          column(
            width = 3,
            sliderInput(
              ns("strength"),
              "Strength",
              min = 0,
              max = 1,
              value = 0.25,
              step = 0.05
            )
          ),
          column(
            width = 2,
            br(),
            actionButton(
              ns("apply"),
              "Apply",
              icon = icon("play"),
              width = "100%",
              class = "btn-primary"
            )
          )
        ),
        hr(),
        uiOutput(ns("scenario_summary")),
        hr(),
        DTOutput(ns("comparison_table")),
        hr(),
        DTOutput(ns("impact_table"))
      )
    )
  )
}

responses_server <- function(id, graph) {
  moduleServer(id, function(input, output, session) {
    simulated_graph <- reactiveVal(NULL)

    observe({
      req(graph())

      g <- graph()
      response_ids <- V(g)$name[V(g)$dpsir_category == "Response"]
      response_labels <- V(g)$label[V(g)$dpsir_category == "Response"]

      if (length(response_ids) == 0) {
        updateSelectInput(session, "response_id", choices = character())
        return()
      }

      choices <- setNames(response_ids, response_labels)
      updateSelectInput(session, "response_id", choices = choices)
    })

    observeEvent(input$apply, {
      req(graph(), input$response_id)

      simulated_graph(
        apply_response(
          graph(),
          response_id = input$response_id,
          strength = input$strength,
          mode = input$mode
        )
      )
    })

    output$scenario_summary <- renderUI({
      req(graph())

      before <- graph()
      after <- simulated_graph()
      if (is.null(after)) {
        after <- before
      }

      comparison <- compare_states(before, after)
      impact <- summarize_response_impact(before, after)
      positive_change <- sum(impact$delta < 0, na.rm = TRUE)
      negative_change <- sum(impact$delta > 0, na.rm = TRUE)

      summary_text <- paste0(
        "Scenario effect: ",
        if (positive_change > negative_change) {
          "most nodes improve after the response."
        } else if (negative_change > positive_change) {
          "several nodes worsen after the response."
        } else {
          "the response produces mixed effects."
        }
      )

      tags$div(
        class = "alert alert-info",
        style = "padding: 10px; margin-bottom: 10px;",
        tags$strong("Scenario summary: "),
        summary_text,
        tags$br(),
        tags$small(
          paste0(
            "Total edge weight changed from ",
            round(comparison$before[comparison$metric == "total_edge_weight"], 2),
            " to ",
            round(comparison$after[comparison$metric == "total_edge_weight"], 2),
            "."
          )
        )
      )
    })

    output$comparison_table <- renderDT({
      req(graph())

      after <- simulated_graph()

      if (is.null(after)) {
        after <- graph()
      }

      datatable(
        compare_states(graph(), after),
        options = list(pageLength = 10, scrollX = TRUE),
        rownames = FALSE
      )
    })

    output$impact_table <- renderDT({
      req(graph())

      after <- simulated_graph()
      if (is.null(after)) {
        after <- graph()
      }

      datatable(
        summarize_response_impact(graph(), after),
        options = list(pageLength = 10, scrollX = TRUE),
        rownames = FALSE
      )
    })

    list(
      simulated_graph = simulated_graph
    )
  })
}
