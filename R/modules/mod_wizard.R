# =====================================================
# MOD_WIZARD - WIZARD SHELL (Start/Model/Nodes/Edges/Review/Explore)
# =====================================================
#
# Orquestra os passos guiados (mod_data) e o painel leve de exploracao
# (mod_graph + mod_metrics). O passo atual vive num numericInput oculto para
# que os conditionalPanel funcionem no cliente; savepoint fica disponivel em
# qualquer passo.

WIZARD_STEP_LABELS <- c("Start", "Model", "Nodes", "Edges", "Review and build", "Explore")

mod_wizard_ui <- function(id) {
  ns <- NS(id)

  step_condition <- function(n) paste0("input['", ns("current_step"), "'] == ", n)

  tagList(
    tags$div(
      style = "display: none;",
      numericInput(ns("current_step"), NULL, value = 1)
    ),

    uiOutput(ns("progress_ui")),

    conditionalPanel(condition = step_condition(1), uiOutput(ns("data-start_step"))),
    conditionalPanel(condition = step_condition(2), uiOutput(ns("data-model_step"))),
    conditionalPanel(condition = step_condition(3), uiOutput(ns("data-nodes_step"))),
    conditionalPanel(condition = step_condition(4), uiOutput(ns("data-edges_step"))),
    conditionalPanel(condition = step_condition(5), uiOutput(ns("data-review_step"))),
    conditionalPanel(
      condition = step_condition(6),
      tabsetPanel(
        id = ns("explore_tabs"),
        tabPanel("Graph", mod_graph_ui(ns("graph"))),
        tabPanel("Communities", mod_communities_ui(ns("communities"))),
        tabPanel("Scenarios", mod_responses_ui(ns("responses"))),
        tabPanel("Metrics", mod_metrics_ui(ns("metrics"))),
        tabPanel("Report", mod_report_ui(ns("report")))
      )
    ),

    tags$hr(),
    fluidRow(
      column(width = 3, actionButton(ns("prev_step"), "Back", icon = icon("arrow-left"), width = "100%")),
      column(width = 6, downloadButton(ns("download_savepoint"), "Save savepoint (.idpsir.json)", width = "100%")),
      column(width = 3, actionButton(ns("next_step"), "Next", icon = icon("arrow-right"), width = "100%", class = "btn-primary"))
    )
  )
}

mod_wizard_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    data <- mod_data_server("data")
    mod_graph_server("graph", data$schema, data$nodes, data$edges, data$graph)
    mod_communities_server("communities", data$schema, data$nodes, data$edges, data$graph)
    responses <- mod_responses_server("responses", data$schema, data$nodes, data$edges, data$graph)
    mod_metrics_server("metrics", data$schema, data$graph)
    mod_report_server("report", data$schema, data$nodes, data$edges, data$graph, responses$saved_scenarios)

    # =================================================
    # GRAPH IMAGE CAPTURE (for the Report tab)
    # =================================================
    #
    # html2canvas (and vis-network's own <canvas>) both collapse to 0x0 once
    # their tab is display:none, so capturing on-demand from the Report tab
    # never works - the Graph pane has to actually be visible at capture
    # time. Trigger it here instead, whenever the Graph pane becomes visible:
    # once when Explore is first reached (Graph is its default tab, so no
    # tab-switch event fires for that initial view) and again every time the
    # user switches back to the Graph tab.

    request_graph_capture <- function() {
      session$sendCustomMessage(
        "idpsir_capture_element",
        list(elementId = paste0(ns("graph"), "-network"), inputId = paste0(ns("report"), "-captured_graph_image"))
      )
    }

    observeEvent(input$current_step, {
      if (identical(input$current_step, 6)) request_graph_capture()
    })

    observeEvent(input$explore_tabs, {
      if (identical(input$explore_tabs, "Graph")) request_graph_capture()
    })

    output$progress_ui <- renderUI({
      req(input$current_step)

      tags$div(
        class = "alert alert-secondary",
        tags$strong(paste0(
          "Step ", input$current_step, " of ", length(WIZARD_STEP_LABELS),
          ": ", WIZARD_STEP_LABELS[input$current_step]
        ))
      )
    })

    observeEvent(input$prev_step, {
      updateNumericInput(session, "current_step", value = max(input$current_step - 1, 1))
    })

    observeEvent(input$next_step, {
      current <- input$current_step
      block_reason <- NULL

      if (current == 1 && !isTRUE(data$loaded())) {
        block_reason <- "Choose how to start (new project, import matrices, or savepoint) before continuing."
      } else if (current == 3 && nrow(data$nodes()) == 0) {
        block_reason <- "Add at least one node before continuing."
      } else if (current == 5 && is.null(data$graph())) {
        block_reason <- "Build the graph (the 'Build/Rebuild graph' button) before going to Explore."
      }

      if (is.null(block_reason)) {
        updateNumericInput(session, "current_step", value = min(current + 1, length(WIZARD_STEP_LABELS)))
      } else {
        showNotification(block_reason, type = "warning")
      }
    })

    output$download_savepoint <- downloadHandler(
      filename = function() paste0("project_", Sys.Date(), ".idpsir.json"),
      content = function(file) {
        savepoint <- build_savepoint(
          schema = data$schema(),
          nodes = data$nodes(),
          edges = data$edges(),
          positions = data$positions()
        )
        write_savepoint(savepoint, file)
      }
    )
  })
}
