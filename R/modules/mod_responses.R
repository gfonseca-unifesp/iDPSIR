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
#
# Fase 5 Marco D: an optional, off-by-default "Show robustness to
# uncertainty" disclosure runs robustness_check() - the `confidence` the
# user already fills in on each edge becomes a plausible variation range
# for its weight, resampled N times, checking how often each factor's
# direction held. Finally gives `confidence` a real use beyond dashing an
# edge on the graph.
#
# Fast-follow (post-Fase 5): "Effect on each factor" says an Impact will
# improve, but not when - a "When will Impacts be neutralized?" table
# (summarize_neutralization(), R/loop_analysis.R) reuses simulate_trajectory()
# to report how many steps until the response's effect on each Impact node
# first reaches 90% of its equilibrium value. Deliberately does NOT require
# the network to be stable (see R/loop_analysis.R for why that would make
# this dead code in practice for any network built by the app) - it's the
# same directional-estimate caveat as the equilibrium number itself, not a
# guarantee of settling. Hidden entirely when there's no Impact node in the
# built graph.
#
# Fast-follow (post-Fase 5): optional per-edge `threshold` (set in the Edges
# form, R/modules/mod_data.R) makes the trajectory chart nonlinear - an edge
# with a threshold contributes nothing until the source factor's simulated
# change (in this scenario) crosses that value, then behaves as usual. Only
# the trajectory chart uses it (`simulate_trajectory_thresholded()`); the
# equilibrium/robustness/neutralization numbers above stay exactly as before
# (the linear, small-perturbation regime) - a small `threshold_note` warns
# when this divergence between the chart and the tables above applies.
#
# Roadmap item 7.1 ("sign determinacy", Dambacher et al. framing): every
# prediction in "Effect on each factor" now carries a "Sign confidence (%)"
# column, computed via sign_determinacy() (R/loop_analysis.R - a thin,
# literature-named alias for the same robustness_check() resampling used
# below) at a fixed N=100 every time a scenario is applied, not hidden
# behind the optional disclosure. "Show robustness to uncertainty" stays as
# the deeper-dive version, with an adjustable simulation count, for
# double-checking a borderline result.
#
# Roadmap item 7.2 ("which edge matters most"): a "Show which edges matter
# most (optional)" disclosure plots global_sensitivity() (R/loop_analysis.R)
# - a horizontal bar chart (base R barplot(), no ggplot2, same reasoning as
# the trajectory chart) ranking edges by how much bumping their weight up
# 10% (one at a time) would move this scenario's equilibrium effect.
# Computed eagerly in "Apply scenario" (like sign_confidence above) so a
# saved scenario carries its own ranking into the report, not just on screen.
#
# Fase 9 item 9.2 ("response reach"): a "Reach" section, right under "Effect
# on the network", shows how many factors - and how many Impacts out of the
# total - the active response(s) can influence via SOME causal path
# (response_reach(), R/reach.R). Pure directed-graph traversal, no matrix
# involved - deliberately placed next to (not gated by) the stability
# warning, since reach stays defined even when the equilibrium effect above
# it doesn't. Computed eagerly in "Apply scenario", same as sign_confidence/
# sensitivity, so saved scenarios carry it into the comparison table/report.

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

    # Optional per-edge threshold (see R/loop_analysis.R) - only used by the
    # trajectory chart below. All-NA (the common case: no edge has one set)
    # behaves identically to not passing it at all.
    threshold_matrix <- reactive({
      req(graph())
      build_threshold_matrix(graph())
    })

    has_thresholds <- reactive({
      any(!is.na(threshold_matrix()))
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
      sign_confidence <- suppressWarnings(sign_determinacy(graph(), press, n_simulations = 100))
      sensitivity <- suppressWarnings(global_sensitivity(graph(), press))
      reach <- response_reach(graph(), active_ids)

      current_scenario(list(
        name = input$scenario_name,
        active = active_ids,
        strengths = strengths,
        press = press,
        result = result,
        sign_confidence = sign_confidence,
        sensitivity = sensitivity,
        reach = reach
      ))
    })

    output$scenario_result <- renderUI({
      req(current_scenario())

      tagList(
        uiOutput(ns("stability_note")),
        h5("Effect on the network"),
        DTOutput(ns("network_effect_table")),
        h5("Reach"),
        p(
          class = "text-muted",
          "How far this response's influence travels through the DPSIR chain - always",
          "calculable, regardless of the stability warning above (which only applies to",
          "the equilibrium effect)."
        ),
        uiOutput(ns("reach_summary")),
        DTOutput(ns("reach_table")),
        h5("Effect on each factor"),
        DTOutput(ns("factor_effect_table")),
        uiOutput(ns("neutralization_section")),
        tags$hr(),
        checkboxInput(ns("show_trajectory"), "Show how the effect evolves over time (optional)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("show_trajectory")),
          sliderInput(ns("trajectory_steps"), "Number of steps", min = 5, max = 60, value = 20, step = 5),
          uiOutput(ns("threshold_note")),
          plotOutput(ns("trajectory_plot"), height = "320px")
        ),
        tags$hr(),
        checkboxInput(ns("show_robustness"), "Show robustness to uncertainty (optional)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("show_robustness")),
          sliderInput(ns("robustness_simulations"), "Number of simulations", min = 20, max = 500, value = 100, step = 20),
          p(
            class = "text-muted",
            "The \"Sign confidence (%)\" column above already runs this check at 100",
            "simulations. Each edge's weight is randomly varied within a range based on",
            "its confidence (high confidence = little variation, low = a lot); use this",
            "to try a different number of simulations, or see the full table sorted",
            "from least to most reliable."
          ),
          DTOutput(ns("robustness_table"))
        ),
        tags$hr(),
        checkboxInput(ns("show_sensitivity"), "Show which edges matter most (optional)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("show_sensitivity")),
          p(
            class = "text-muted",
            "Bumps each edge's weight up by 10%, one at a time, and measures how much",
            "this scenario's overall equilibrium effect moves - the edges at the top",
            "are the ones most worth double-checking your weight estimate for."
          ),
          plotOutput(ns("sensitivity_plot"), height = "320px"),
          DTOutput(ns("sensitivity_table"))
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

    output$threshold_note <- renderUI({
      req(isTRUE(has_thresholds()))

      tags$p(
        class = "text-muted",
        icon("bolt"),
        " This network has one or more edges with a threshold set: their effect only",
        "switches on once the source factor's simulated change crosses that value -",
        "the equilibrium/robustness figures above don't account for this, only the",
        "chart below does."
      )
    })

    output$trajectory_plot <- renderPlot({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_trajectory))

      traj <- simulate_trajectory_thresholded(
        interaction_matrix(), sc$press, Th = threshold_matrix(), steps = input$trajectory_steps
      )

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

    output$robustness_table <- renderDT({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_robustness))

      robustness_df <- sign_determinacy(graph(), sc$press, n_simulations = input$robustness_simulations)
      effect_df <- summarize_scenario_effect(graph(), sc$result)

      robustness_df$direction <- effect_df$direction[match(robustness_df$id, effect_df$id)]
      robustness_df <- robustness_df[order(robustness_df$agreement_pct), ]
      robustness_df <- robustness_df[, c("node", "category", "direction", "agreement_pct")]
      names(robustness_df) <- c("Factor", "Category", "Effect", "Agreement (%)")

      datatable(robustness_df, rownames = FALSE, options = list(dom = "t", pageLength = 10)) %>%
        formatRound(columns = "Agreement (%)", digits = 0)
    })

    output$sensitivity_plot <- renderPlot({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_sensitivity))

      sens <- sc$sensitivity
      if (all(sens$influence < 1e-9)) {
        plot.new()
        text(0.5, 0.5, "No single edge's weight noticeably changes this scenario's effect.")
        return(invisible())
      }

      top <- head(sens[order(sens$influence), ], 10) # ascending so barplot draws highest on top
      barplot(
        top$influence, names.arg = top$link, horiz = TRUE, las = 1,
        col = "#4E79A7", border = NA, cex.names = 0.8,
        xlab = "Change in total equilibrium effect (+10% weight)",
        main = "Which edges matter most for this scenario"
      )
    })

    output$sensitivity_table <- renderDT({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_sensitivity))

      df <- sc$sensitivity[, c("link", "weight", "confidence", "influence")]
      names(df) <- c("Link", "Weight", "Confidence", "Influence")

      datatable(df, rownames = FALSE, options = list(dom = "t", pageLength = 10)) %>%
        formatRound(columns = c("Influence"), digits = 3)
    })

    output$network_effect_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      df <- summarize_scenario_network_effect(sc$result)
      names(df) <- c("Metric", "Immediate", "Equilibrium")

      datatable(df, rownames = FALSE, options = list(dom = "t")) %>%
        formatRound(columns = c("Immediate", "Equilibrium"), digits = 2)
    })

    # Roadmap Fase 9 item 9.2: "reach" is pure graph traversal from what the
    # active response(s) directly act on (R/reach.R) - always defined, unlike
    # the equilibrium effect above, which depends on the network settling.
    output$reach_summary <- renderUI({
      sc <- current_scenario()
      req(sc)

      if (sc$reach$total == 0) {
        return(tags$p("This response doesn't reach any other factor in the network."))
      }

      total_impacts <- count_impacts_in_graph(graph())
      reached_impacts_row <- sc$reach$by_category[sc$reach$by_category$category == "Impact", "count"]
      reached_impacts <- if (length(reached_impacts_row) == 0) 0 else reached_impacts_row

      tags$p(
        tags$strong(sprintf("%d factor%s reached", sc$reach$total, if (sc$reach$total == 1) "" else "s")),
        sprintf(", including %d of %d Impact%s.", reached_impacts, total_impacts, if (total_impacts == 1) "" else "s")
      )
    })

    output$reach_table <- renderDT({
      sc <- current_scenario()
      req(sc, sc$reach$total > 0)

      g <- graph()
      idx <- match(sc$reach$reached_ids, V(g)$name)
      df <- data.frame(
        Factor = V(g)$label[idx],
        Category = V(g)$dpsir_category[idx],
        stringsAsFactors = FALSE
      )

      datatable(df, rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })

    # Fase 5 fast-follow: not just "does this response help", but "how long
    # until it actually neutralizes the Impact" - the question that
    # motivated the request. Hidden entirely when the network has no Impact
    # nodes, instead of showing an empty table.
    neutralization_df <- reactive({
      sc <- current_scenario()
      req(sc)
      summarize_neutralization(graph(), sc$press)
    })

    output$neutralization_section <- renderUI({
      req(nrow(neutralization_df()) > 0)

      tagList(
        h5("When will Impacts be neutralized?"),
        p(
          class = "text-muted",
          "How many steps of \"Show how the effect evolves over time\" (below) it takes",
          "for this response's effect on each Impact to first reach 90% of the equilibrium",
          "effect shown above - treat this the same way as that equilibrium number: a",
          "projection of where things are headed, not a guarantee the effect stays there",
          "(check the trajectory chart if the stability warning above is showing)."
        ),
        DTOutput(ns("neutralization_table"))
      )
    })

    output$neutralization_table <- renderDT({
      df <- neutralization_df()[, c("node", "equilibrium_effect", "steps_to_neutralize", "note")]
      names(df) <- c("Impact", "Equilibrium effect", "Steps to 90%", "Note")

      datatable(df, rownames = FALSE, options = list(dom = "t")) %>%
        formatRound(columns = "Equilibrium effect", digits = 3)
    })

    output$factor_effect_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      df <- summarize_scenario_effect(graph(), sc$result)
      df$sign_confidence <- sc$sign_confidence$agreement_pct[match(df$id, sc$sign_confidence$id)]
      df <- df[, c("node", "category", "direction", "sign_confidence", "id", "immediate", "equilibrium")]
      names(df) <- c("Factor", "Category", "Effect", "Sign confidence (%)", "ID", "Immediate", "Equilibrium")

      datatable(
        df,
        rownames = FALSE,
        extensions = "Buttons",
        options = list(
          dom = "Bfrtip",
          buttons = c("csv", "excel"),
          columnDefs = list(list(visible = FALSE, targets = c(4, 5, 6))),
          pageLength = 10,
          scrollX = TRUE
        )
      ) %>%
        formatRound(columns = "Sign confidence (%)", digits = 0) %>%
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
        h5("Sign confidence per factor"),
        p(
          class = "text-muted",
          "How often each scenario's predicted direction held up across 100 simulations",
          "that resampled every edge's weight within a range set by its confidence."
        ),
        DTOutput(ns("comparison_sign_confidence_table")),
        h5("Reach per scenario"),
        DTOutput(ns("comparison_reach_table")),
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

    output$comparison_sign_confidence_table <- renderDT({
      names_sel <- selected_scenario_names()
      saved <- saved_scenarios$list

      scenario_sign_conf <- lapply(names_sel, function(scenario_name) saved[[scenario_name]]$sign_confidence)
      names(scenario_sign_conf) <- names_sel

      # Baseline's press is all-zero, so its equilibrium is exactly 0
      # regardless of how edge weights are resampled (-A^-1 * 0 = 0 for any
      # invertible A) - agreement is trivially 100% everywhere, computed
      # directly instead of wastefully re-running simulations to confirm it.
      baseline_sign_conf <- data.frame(
        id = V(graph())$name,
        node = if (!is.null(V(graph())$label)) V(graph())$label else V(graph())$name,
        category = if (!is.null(V(graph())$dpsir_category)) V(graph())$dpsir_category else "",
        agreement_pct = 100,
        stringsAsFactors = FALSE
      )
      scenario_sign_conf <- c(list(Baseline = baseline_sign_conf), scenario_sign_conf)

      df <- compare_scenario_sign_confidence(graph(), scenario_sign_conf)
      df$id <- NULL
      numeric_cols <- setdiff(names(df), c("node", "category"))
      names(df)[names(df) == "node"] <- "Factor"
      names(df)[names(df) == "category"] <- "Category"

      datatable(df, rownames = FALSE, options = list(dom = "t")) %>%
        formatRound(columns = numeric_cols, digits = 0)
    })

    output$comparison_reach_table <- renderDT({
      names_sel <- selected_scenario_names()
      saved <- saved_scenarios$list
      total_impacts <- count_impacts_in_graph(graph())

      reach_row <- function(scenario_name, reach) {
        reached_impacts_row <- reach$by_category[reach$by_category$category == "Impact", "count"]
        reached_impacts <- if (length(reached_impacts_row) == 0) 0L else reached_impacts_row
        data.frame(
          Scenario = scenario_name,
          `Factors reached` = reach$total,
          `Impacts reached` = sprintf("%d of %d", reached_impacts, total_impacts),
          check.names = FALSE,
          stringsAsFactors = FALSE
        )
      }

      # Baseline activates no response, so its reach is trivially empty -
      # computed directly instead of calling response_reach() with no ids.
      baseline_row <- reach_row("Baseline", list(total = 0L, by_category = data.frame(category = character(), count = integer())))
      scenario_rows <- lapply(names_sel, function(scenario_name) reach_row(scenario_name, saved[[scenario_name]]$reach))

      datatable(do.call(rbind, c(list(baseline_row), scenario_rows)), rownames = FALSE, options = list(dom = "t"))
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
