# =====================================================
# MOD_RESPONSES - SCENARIOS TAB
# =====================================================
#
# Lets a non-technical user build a "scenario" by turning on one or more
# Response nodes (feedback-role categories) at a chosen implementation
# strength, then see the before/after effect in plain language. No graph
# jargon on screen: "Effect on each factor" shows Improves/Worsens/Stable,
# not raw scores (those stay available, just hidden by default and still
# in the CSV/Excel export).

mod_responses_ui <- function(id) {
  ns <- NS(id)

  box(
    width = 12,
    title = "Scenarios",
    status = "primary",
    solidHeader = TRUE,

    p("Turn on the responses you want to test, set how strongly each is implemented, then apply the scenario to see its effect."),

    uiOutput(ns("response_controls")),

    tags$hr(),
    fluidRow(
      column(width = 6, textInput(ns("scenario_name"), "Scenario name", value = "Scenario 1")),
      column(width = 6, br(), actionButton(ns("apply_scenario"), "Apply scenario", icon = icon("play"), class = "btn-success", width = "100%"))
    ),

    uiOutput(ns("scenario_result")),

    tags$hr(),
    h5("Saved scenarios"),
    p("Save a scenario, then select two or more (the baseline - no response applied - is always included) to compare them side by side."),
    DTOutput(ns("saved_scenarios_table")),
    actionButton(ns("compare_scenarios"), "Compare selected scenarios", icon = icon("balance-scale")),
    uiOutput(ns("comparison_result"))
  )
}

mod_responses_server <- function(id, schema, nodes, edges, graph) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    response_nodes <- reactive({
      req(nodes(), schema())
      feedback_categories <- get_feedback_categories(schema())
      n <- nodes()
      n[n$dpsir_category %in% feedback_categories, , drop = FALSE]
    })

    output$response_controls <- renderUI({
      req(graph())
      rn <- response_nodes()

      if (nrow(rn) == 0) {
        return(tags$div(
          class = "alert alert-warning",
          "No Response nodes in this network yet. Add one in the Nodes step to build scenarios."
        ))
      }

      rows <- lapply(seq_len(nrow(rn)), function(i) {
        node_id <- rn$id[i]
        fluidRow(
          column(width = 6, checkboxInput(ns(paste0("active_", node_id)), rn$label[i], value = FALSE)),
          column(width = 6, sliderInput(ns(paste0("strength_", node_id)), NULL, min = 0, max = 100, value = 50, step = 5, post = "%"))
        )
      })

      tagList(rows)
    })

    current_scenario <- reactiveVal(NULL)

    observeEvent(input$apply_scenario, {
      req(graph())

      rn <- response_nodes()
      active_ids <- rn$id[vapply(rn$id, function(node_id) isTRUE(input[[paste0("active_", node_id)]]), logical(1))]

      if (length(active_ids) == 0) {
        showNotification("Select at least one response to apply.", type = "warning")
        return()
      }

      scenario_graph <- graph()
      strengths <- setNames(numeric(length(active_ids)), active_ids)

      for (node_id in active_ids) {
        strength_pct <- input[[paste0("strength_", node_id)]]
        strengths[[node_id]] <- strength_pct
        scenario_graph <- apply_response(scenario_graph, schema(), response_id = node_id, strength = strength_pct / 100)
      }

      current_scenario(list(
        name = input$scenario_name,
        active = active_ids,
        strengths = strengths,
        graph = scenario_graph
      ))
    })

    output$scenario_result <- renderUI({
      req(current_scenario())

      tagList(
        h5("Effect on the network"),
        DTOutput(ns("network_effect_table")),
        h5("Effect on each factor"),
        DTOutput(ns("factor_effect_table")),
        tags$hr(),
        actionButton(ns("save_scenario"), "Save this scenario", icon = icon("save"), class = "btn-outline-primary")
      )
    })

    output$network_effect_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      df <- compare_states(graph(), sc$graph)
      names(df) <- c("Metric", "Before", "After")

      datatable(df, rownames = FALSE, options = list(dom = "t")) %>%
        formatRound(columns = c("Before", "After"), digits = 2)
    })

    output$factor_effect_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      df <- summarize_response_impact(graph(), sc$graph)
      df <- df[, c("node", "category", "direction", "id", "before_score", "after_score", "delta")]

      datatable(
        df,
        rownames = FALSE,
        extensions = "Buttons",
        colnames = c("Factor", "Category", "Effect", "ID", "Before score", "After score", "Delta"),
        options = list(
          dom = "Bfrtip",
          buttons = c("csv", "excel"),
          columnDefs = list(list(visible = FALSE, targets = c(3, 4, 5, 6))),
          pageLength = 10,
          scrollX = TRUE
        )
      ) %>%
        formatRound(columns = c("before_score", "after_score", "delta"), digits = 2)
    })

    # =================================================
    # SAVE AND COMPARE SCENARIOS
    # =================================================

    saved_scenarios <- reactiveValues(list = list())
    scenario_counter <- reactiveVal(1)

    scenario_direction_counts <- function(sc) {
      impact <- summarize_response_impact(graph(), sc$graph)
      table(factor(impact$direction, levels = c("Improves", "Worsens", "Stable")))
    }

    observeEvent(input$save_scenario, {
      sc <- current_scenario()
      req(sc)

      saved <- saved_scenarios$list
      saved[[sc$name]] <- sc
      saved_scenarios$list <- saved

      scenario_counter(scenario_counter() + 1)
      updateTextInput(session, "scenario_name", value = paste("Scenario", scenario_counter()))
      showNotification(paste0("Scenario '", sc$name, "' saved."), type = "message")
    })

    output$saved_scenarios_table <- renderDT({
      saved <- saved_scenarios$list

      if (length(saved) == 0) {
        return(datatable(
          data.frame(Name = character(), Responses = character(), Summary = character(), stringsAsFactors = FALSE),
          rownames = FALSE,
          options = list(dom = "t")
        ))
      }

      df <- do.call(rbind, lapply(names(saved), function(scenario_name) {
        sc <- saved[[scenario_name]]
        counts <- scenario_direction_counts(sc)
        data.frame(
          Name = scenario_name,
          Responses = paste(sc$active, collapse = ", "),
          Summary = sprintf("%d improve, %d worsen, %d stable", counts[["Improves"]], counts[["Worsens"]], counts[["Stable"]]),
          stringsAsFactors = FALSE
        )
      }))

      datatable(df, selection = "multiple", rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })

    comparison_selection <- reactiveVal(NULL)

    observeEvent(input$compare_scenarios, {
      sel <- input$saved_scenarios_table_rows_selected

      if (is.null(sel) || length(sel) == 0) {
        showNotification("Select at least one saved scenario to compare.", type = "warning")
        return()
      }

      comparison_selection(sel)
    })

    selected_scenario_names <- reactive({
      sel <- comparison_selection()
      req(sel)
      names(saved_scenarios$list)[sel]
    })

    output$comparison_result <- renderUI({
      req(comparison_selection())

      tagList(
        tags$hr(),
        h5("Scenario comparison"),
        DTOutput(ns("comparison_table")),
        h5("Summary per scenario"),
        DTOutput(ns("comparison_summary_table"))
      )
    })

    output$comparison_table <- renderDT({
      names_sel <- selected_scenario_names()
      saved <- saved_scenarios$list

      scenario_graphs <- lapply(names_sel, function(scenario_name) saved[[scenario_name]]$graph)
      names(scenario_graphs) <- names_sel

      df <- compare_multiple_states(graph(), scenario_graphs)
      numeric_cols <- setdiff(names(df), "metric")

      datatable(df, rownames = FALSE, colnames = c("Metric" = "metric"), options = list(dom = "t")) %>%
        formatRound(columns = numeric_cols, digits = 2)
    })

    output$comparison_summary_table <- renderDT({
      names_sel <- selected_scenario_names()
      saved <- saved_scenarios$list

      rows <- lapply(names_sel, function(scenario_name) {
        counts <- scenario_direction_counts(saved[[scenario_name]])
        data.frame(
          Scenario = scenario_name,
          Improves = as.integer(counts[["Improves"]]),
          Worsens = as.integer(counts[["Worsens"]]),
          Stable = as.integer(counts[["Stable"]]),
          stringsAsFactors = FALSE
        )
      })

      datatable(do.call(rbind, rows), rownames = FALSE, options = list(dom = "t"))
    })

    list(
      current_scenario = current_scenario,
      response_nodes = response_nodes,
      saved_scenarios = reactive(saved_scenarios$list)
    )
  })
}
