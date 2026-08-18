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
    # Explore's tabsetPanel (mod_graph_ui/mod_responses_ui/mod_metrics_ui/
    # mod_report_ui combined) is a LOT of DOM/JS up front - a visNetwork
    # widget, ~12 collapsible bs4Dash boxes, a dozen+ selectize dropdowns,
    # sliders. Embedding it here directly (as before) means every fresh
    # page load ships and initializes all of that immediately, even though
    # step 1 (Start) is the only thing visible - conditionalPanel only
    # hides it with CSS display:none, it's still fully in the DOM. On a
    # user report of the Start step rendering blank with zero error
    # anywhere (not even Shiny's own client-side error text - see
    # CLAUDE.md, "app nao abre uniforme em todos os computadores"), that
    # much upfront JS widget initialization is a real, testable risk
    # factor for exactly this kind of silent client-side failure - so
    # Explore is now built server-side via uiOutput/renderUI, the first
    # time (and only the first time) the user actually reaches step 6.
    conditionalPanel(condition = step_condition(6), uiOutput(ns("explore_ui"))),

    tags$hr(),
    fluidRow(
      column(width = 3, actionButton(ns("prev_step"), "Back", icon = icon("arrow-left"), width = "100%")),
      column(width = 6, downloadButton(ns("download_savepoint"), "Save savepoint (.idpsir.json)", width = "100%")),
      column(
        width = 3,
        # Next has nowhere left to go once Explore (the last step) is reached,
        # so it stops being rendered there instead of sitting around inert.
        conditionalPanel(
          condition = paste0("input['", ns("current_step"), "'] < ", length(WIZARD_STEP_LABELS)),
          actionButton(ns("next_step"), "Next", icon = icon("arrow-right"), width = "100%", class = "btn-primary")
        )
      )
    )
  )
}

mod_wizard_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    message("[iDPSIR debug] mod_wizard_server: session init begin")
    data <- mod_data_server("data")
    message("[iDPSIR debug] mod_wizard_server: mod_data_server done")
    graph_result <- mod_graph_server("graph", data$schema, data$nodes, data$edges, data$graph, data$positions, data$set_positions)
    message("[iDPSIR debug] mod_wizard_server: mod_graph_server done")
    responses <- mod_responses_server(
      "responses", data$schema, data$nodes, data$edges, data$graph, data$scenario_state
    )
    message("[iDPSIR debug] mod_wizard_server: mod_responses_server done")
    metrics_result <- mod_metrics_server("metrics", data$schema, data$graph)
    message("[iDPSIR debug] mod_wizard_server: mod_metrics_server done")
    mod_report_server(
      "report", data$schema, data$nodes, data$edges, data$graph,
      responses$saved_scenarios, graph_result$graph_snapshots, metrics_result$centrality_params,
      metadata = data$metadata, savepoint_filename = data$savepoint_filename
    )
    message("[iDPSIR debug] mod_wizard_server: mod_report_server done, session init complete")

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

    # Build Explore's tabsetPanel once, the first time step 6 is reached,
    # and never again - explore_built() only ever flips FALSE -> TRUE, so
    # re-visiting step 6 later does not re-invalidate/rebuild output$explore_ui
    # (which would otherwise wipe graph zoom/selection, entered scenario
    # sliders, etc. every time the user steps away and back).
    explore_built <- reactiveVal(FALSE)

    observeEvent(input$current_step, {
      if (identical(input$current_step, length(WIZARD_STEP_LABELS)) && !isTRUE(explore_built())) {
        explore_built(TRUE)
      }
    }, ignoreInit = TRUE)

    output$explore_ui <- renderUI({
      req(explore_built())

      tabsetPanel(
        id = ns("explore_tabs"),
        tabPanel("Graph", mod_graph_ui(ns("graph"))),
        tabPanel("Scenarios", mod_responses_ui(ns("responses"))),
        tabPanel("Metrics", mod_metrics_ui(ns("metrics"))),
        tabPanel("Report", mod_report_ui(ns("report")))
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
          positions = data$positions(),
          scenario_state = responses$scenario_state()
        )
        write_savepoint(savepoint, file)
      }
    )
  })
}
