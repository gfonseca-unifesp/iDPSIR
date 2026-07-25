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
#
# Fase 5 Marco B: the engine underneath is loop analysis (R/loop_analysis.R),
# not apply_response() (R/responses.R, preserved but no longer called).
# Activating a response at a given strength is a sustained "press"
# perturbation on that response node; press_perturbation() propagates it
# through the whole signed, weighted graph - including the feedback loop -
# and returns both the one-step (immediate) and full-loop (equilibrium)
# effect on every node. Combining responses is just summing more than one
# node into the same press vector. The interface below is unchanged from
# before Marco B (same tables, same Improves/Worsens/Stable language) -
# only the numbers behind it are now correct.
#
# Fase 5 Marco C: an optional, off-by-default "Show how the effect evolves
# over time" disclosure plots simulate_trajectory() (base R matplot(), no
# ggplot2) - useful even when the network is unstable (the equilibrium
# table above is only a directional estimate then), since the trajectory
# still runs for any finite number of steps and visibly diverges instead.

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

    # =================================================
    # LOOP ANALYSIS ENGINE
    # =================================================
    #
    # The interaction matrix and its stability only depend on the built
    # graph (weights/signs), not on which response is being tested - built
    # once per graph and reused across every "Apply scenario" click.

    interaction_matrix <- reactive({
      req(graph())
      build_interaction_matrix(graph())
    })

    network_stability <- reactive({
      req(interaction_matrix())
      check_stability(interaction_matrix())
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

      strengths <- setNames(numeric(length(active_ids)), active_ids)
      for (node_id in active_ids) {
        strengths[[node_id]] <- input[[paste0("strength_", node_id)]]
      }

      press <- build_press_vector(graph(), active_ids, strengths / 100)
      result <- press_perturbation(interaction_matrix(), press)

      current_scenario(list(
        name = input$scenario_name,
        active = active_ids,
        strengths = strengths,
        press = press,
        result = result
      ))
    })

    output$scenario_result <- renderUI({
      req(current_scenario())

      tagList(
        uiOutput(ns("stability_note")),
        h5("Effect on the network"),
        DTOutput(ns("network_effect_table")),
        h5("Effect on each factor"),
        DTOutput(ns("factor_effect_table")),
        tags$hr(),
        checkboxInput(ns("show_trajectory"), "Show how the effect evolves over time (optional)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("show_trajectory")),
          sliderInput(ns("trajectory_steps"), "Number of steps", min = 5, max = 60, value = 20, step = 5),
          plotOutput(ns("trajectory_plot"), height = "320px")
        ),
        tags$hr(),
        actionButton(ns("save_scenario"), "Save this scenario", icon = icon("save"), class = "btn-outline-primary")
      )
    })

    output$stability_note <- renderUI({
      req(network_stability())
      stab <- network_stability()

      if (isTRUE(stab$stable)) {
        tags$div(
          class = "alert alert-success",
          icon("check"),
          " This network's feedback loops are stable: the equilibrium effect below is where the system settles over time."
        )
      } else {
        tags$div(
          class = "alert alert-warning",
          icon("triangle-exclamation"),
          " This network's feedback loops are not stable: treat the equilibrium effect below as a directional estimate, not a guaranteed outcome. The immediate (one-step) effect is still reliable."
        )
      }
    })

    output$trajectory_plot <- renderPlot({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_trajectory))

      traj <- simulate_trajectory(interaction_matrix(), sc$press, steps = input$trajectory_steps)

      if (all(is.na(traj))) {
        plot.new()
        text(0.5, 0.5, "Trajectory could not be computed for this network.")
        return(invisible())
      }

      node_ids <- colnames(traj)
      labels <- V(graph())$label[match(node_ids, V(graph())$name)]
      colors <- scales::hue_pal()(ncol(traj))

      matplot(
        seq_len(nrow(traj)), traj, type = "l", lty = 1, lwd = 2, col = colors,
        xlab = "Steps", ylab = "Effect on each factor",
        main = "How the effect changes as the response takes hold"
      )
      abline(h = 0, col = "grey70", lty = 2)
      legend("topright", legend = labels, col = colors, lty = 1, lwd = 2, cex = 0.8, bty = "n")
    })

    output$network_effect_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      df <- summarize_scenario_network_effect(sc$result)
      names(df) <- c("Metric", "Immediate", "Equilibrium")

      datatable(df, rownames = FALSE, options = list(dom = "t")) %>%
        formatRound(columns = c("Immediate", "Equilibrium"), digits = 2)
    })

    output$factor_effect_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      df <- summarize_scenario_effect(graph(), sc$result)
      df <- df[, c("node", "category", "direction", "id", "immediate", "equilibrium")]
      names(df) <- c("Factor", "Category", "Effect", "ID", "Immediate", "Equilibrium")

      datatable(
        df,
        rownames = FALSE,
        extensions = "Buttons",
        options = list(
          dom = "Bfrtip",
          buttons = c("csv", "excel"),
          columnDefs = list(list(visible = FALSE, targets = c(3, 4, 5))),
          pageLength = 10,
          scrollX = TRUE
        )
      ) %>%
        formatRound(columns = c("Immediate", "Equilibrium"), digits = 3)
    })

    # =================================================
    # SAVE AND COMPARE SCENARIOS
    # =================================================

    saved_scenarios <- reactiveValues(list = list())
    scenario_counter <- reactiveVal(1)

    scenario_direction_counts <- function(sc) {
      effect_df <- summarize_scenario_effect(graph(), sc$result)
      table(factor(effect_df$direction, levels = c("Improves", "Worsens", "Stable")))
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

      scenario_results <- lapply(names_sel, function(scenario_name) saved[[scenario_name]]$result)
      names(scenario_results) <- names_sel

      baseline_result <- list(equilibrium = setNames(rep(0, vcount(graph())), V(graph())$name))
      scenario_results <- c(list(Baseline = baseline_result), scenario_results)

      df <- compare_scenario_effects(graph(), scenario_results)
      df$id <- NULL
      numeric_cols <- setdiff(names(df), c("node", "category"))
      names(df)[names(df) == "node"] <- "Factor"
      names(df)[names(df) == "category"] <- "Category"

      datatable(df, rownames = FALSE, options = list(dom = "t")) %>%
        formatRound(columns = numeric_cols, digits = 3)
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
