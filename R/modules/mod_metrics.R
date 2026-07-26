# =====================================================
# MOD_METRICS - SINGLE METRICS PANEL
# General + Centralities + DPSIR descriptors
# =====================================================

mod_metrics_ui <- function(id) {
  ns <- NS(id)

  box(
    width = 12,
    title = "Metrics",
    status = "primary",
    solidHeader = TRUE,

    tabsetPanel(
      tabPanel(
        "General",
        DTOutput(ns("general_table"))
      ),
      tabPanel(
        "Centralities",
        fluidRow(
          column(width = 4, ina_toggle_directed(ns("directed"))),
          column(width = 4, ina_toggle_normalized(ns("normalized"))),
          column(width = 4, checkboxInput(ns("weighted"), "Weighted by edge weight (link strength)", value = FALSE))
        ),
        DTOutput(ns("centrality_table"))
      ),
      tabPanel(
        "DPSIR descriptors",
        h4("Nodes by category"),
        DTOutput(ns("count_table")),
        h4("Transitions (edges by source -> target category)"),
        DTOutput(ns("transitions_table")),
        h4("Category x category matrix"),
        DTOutput(ns("matrix_table")),
        uiOutput(ns("gaps_summary")),
        h4("Average uncertainty/controllability by category (1=low, 2=medium, 3=high)"),
        DTOutput(ns("averages_table"))
      )
    )
  )
}

mod_metrics_server <- function(id, schema, graph) {
  moduleServer(id, function(input, output, session) {
    output$general_table <- renderDT({
      req(graph())

      datatable(
        compute_general_metrics(graph()),
        rownames = FALSE,
        options = list(dom = "t")
      )
    })

    output$centrality_table <- renderDT({
      req(graph())

      df <- compute_all_metrics(
        graph(),
        directed = input$directed,
        normalized = input$normalized,
        weighted = input$weighted
      )

      numeric_cols <- names(df)[sapply(df, is.numeric)]

      table <- datatable(
        df,
        extensions = "Buttons",
        options = list(
          dom = "Bfrtip",
          buttons = c("csv", "excel"),
          pageLength = 20,
          scrollX = TRUE
        ),
        rownames = FALSE
      )

      if (length(numeric_cols) > 0) {
        table <- table %>% formatRound(columns = numeric_cols, digits = 4)
      }

      table
    })

    descriptors <- reactive({
      req(graph())
      compute_dpsir_descriptors(graph(), schema())
    })

    output$count_table <- renderDT({
      datatable(descriptors()$count_by_category, rownames = FALSE, options = list(dom = "t"))
    })

    output$transitions_table <- renderDT({
      datatable(descriptors()$transitions, rownames = FALSE, options = list(dom = "t"))
    })

    output$matrix_table <- renderDT({
      datatable(as.data.frame.matrix(descriptors()$transition_matrix), options = list(dom = "t"))
    })

    output$averages_table <- renderDT({
      datatable(
        descriptors()$averages_by_category,
        rownames = FALSE,
        options = list(dom = "t")
      ) %>%
        formatRound(columns = c("avg_uncertainty", "avg_controllability"), digits = 2)
    })

    output$gaps_summary <- renderUI({
      d <- descriptors()

      tagList(
        tags$p(
          tags$strong("Impacts without Response: "),
          if (length(d$impacts_without_response) == 0) "none" else paste(d$impacts_without_response, collapse = ", ")
        ),
        tags$p(
          tags$strong("Pressures not covered by Response: "),
          if (length(d$pressures_without_response) == 0) "none" else paste(d$pressures_without_response, collapse = ", ")
        )
      )
    })

    # Exposed so the Report tab's Centralities table can use the same
    # directed/normalized/weighted choice the user configured here, instead
    # of silently falling back to compute_all_metrics()'s own defaults.
    list(
      centrality_params = reactive(list(
        directed = isTRUE(input$directed),
        normalized = isTRUE(input$normalized),
        weighted = isTRUE(input$weighted)
      ))
    )
  })
}
