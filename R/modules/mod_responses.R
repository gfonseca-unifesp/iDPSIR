# =====================================================
# MOD_RESPONSES - SCENARIOS TAB
# =====================================================
#
# Lets a non-technical user build a "scenario" by turning on one or more
# Response nodes (feedback-role categories) at a chosen implementation
# strength, then see the effect in plain language.
#
# Two readings, both driven by the same Pressure/Response scenario inputs:
# - Sufficiency (R/sufficiency.R, Revisao 1 Fase 1-3): the primary reading.
#   A static, discounted propagated effect - always well-defined, never
#   requires the network to be "stable" - answering "does the response's
#   mitigation cover the pressure's worsening on each Impact?" plus how
#   confident that verdict is and whether it holds across how far the
#   effect is traced.
# - Temporal simulation (R/temporal.R, Revisao 1 Fase 4-7): an optional
#   disclosure that runs the same two scenarios forward window by window
#   (discrete time steps, no convergence/equilibrium assumption), showing a
#   table of how each Impact changes over time and a "storyboard" of the
#   network's state per window.
#
# Reach (response_reach(), R/reach.R, Fase 9 item 9.2): how many factors - and
# how many Impacts out of the total - the active response(s) can influence
# via SOME causal path. Pure directed-graph traversal, no matrix involved,
# independent of both readings above - computed eagerly in "Apply scenario"
# so saved scenarios carry it into the comparison table/report.
#
# Revisao 1, Fase 8 ("corte do motor antigo"): this tab used to show a SECOND,
# older reading first ("Effect on each factor (older, equilibrium-based
# reading)") built on loop analysis (R/loop_analysis.R): press_perturbation()
# (-A^-1 x press, requiring network "stability" that no network this app can
# build ever has - the schema forbids a node acting on itself, so the
# interaction matrix's diagonal/trace/eigenvalue-sum is always zero), plus
# everything derived from it - a linear trajectory chart, robustness-to-
# uncertainty and sensitivity-to-self-regulation disclosures, sign
# confidence, and a "which edges matter most" ranking. That whole reading is
# cut here, superseded by sufficiency (which fixed exactly this fragility -
# see R/sufficiency.R's header for the real inverted-sign bug that motivated
# it) and temporal simulation. The underlying functions in
# R/loop_analysis.R (press_perturbation(), check_stability(),
# simulate_trajectory_thresholded(), robustness_check(), sign_determinacy(),
# self_regulation_sensitivity(), global_sensitivity(), etc.) are left defined
# and still covered by tests/testthat/test-loop_analysis.R - only the calls
# from this file (and R/report.R) are removed, the same "superseded code
# stays on disk, just stops being called" pattern already used throughout
# this project (e.g. R/responses.R's apply_response()).
plot_download_row <- function(ns, prefix) {
  fluidRow(
    column(6, downloadButton(ns(paste0("download_", prefix, "_png")), "Download PNG", class = "btn-sm")),
    column(6, downloadButton(ns(paste0("download_", prefix, "_svg")), "Download SVG", class = "btn-sm"))
  )
}

# Revisao 1, Table 2: every Response node in the network evaluated ALONE at
# FULL strength (100%) - regardless of whether its checkbox is active, and
# regardless of whatever % its own slider happens to show - against the
# same pressure scenario. Fixed at 100% deliberately, not each response's
# current slider value: an untouched slider defaults to 50%, which would
# make an inactive response look artificially weaker than an equally
# capable one the user happened to check and drag to 100% - fixing the
# strength makes this a clean "if this were fully applied on its own"
# comparison, matching the review's own Table 2 and the values already
# verified in tests/testthat/test-sufficiency.R (also computed at 100%).
# Pure function (no Shiny reactives), so it's independently testable and
# reusable from R/report.R later (Fase 3).
build_confidence_matrix <- function(g, p_D, response_nodes_df, c, n_simulations = 300, spread = 0.5, seed = 42) {
  if (nrow(response_nodes_df) == 0) {
    return(data.frame(Response = character(), stringsAsFactors = FALSE))
  }

  per_response <- lapply(seq_len(nrow(response_nodes_df)), function(i) {
    rid <- response_nodes_df$id[i]
    p_r <- build_press_vector(g, rid, setNames(1, rid))
    sufficiency_confidence(g, p_D, p_r, c = c, n_simulations = n_simulations, spread = spread, seed = seed)
  })

  if (nrow(per_response[[1]]) == 0) {
    return(data.frame(Response = response_nodes_df$label, stringsAsFactors = FALSE))
  }

  impact_labels <- per_response[[1]]$node
  mat <- do.call(rbind, lapply(per_response, function(sc) sc$neutralized_pct))
  colnames(mat) <- impact_labels

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  cbind(Response = response_nodes_df$label, df, stringsAsFactors = FALSE)
}

mod_responses_ui <- function(id) {
  ns <- NS(id)

  box(
    width = 12,
    title = "Scenarios",
    status = "primary",
    solidHeader = TRUE,

    # Revisao 1, Fase 2: two independent "pushes" the user builds - a
    # pressure scenario (what's getting worse) and a response scenario
    # (what's being done about it) - read by the sufficiency reading below.
    p("Build two scenarios: what's pushing the system to get worse, and how you're responding to it. Then see whether the response is enough."),

    h5("Pressure scenario"),
    p(class = "text-muted", "Optional. Turn on the Drivers/Pressures you expect to worsen, and how strongly."),
    uiOutput(ns("pressure_controls")),

    tags$hr(),
    h5("Response scenario"),
    p(class = "text-muted", "Turn on the responses you want to test, and how strongly each is implemented."),
    uiOutput(ns("response_controls")),

    tags$hr(),
    uiOutput(ns("effect_horizon_ui")),
    p(
      class = "text-muted",
      "Lower values focus almost entirely on short, direct causal chains; higher values let longer, indirect chains",
      "contribute more. \"Sensitivity to this setting\" below shows whether your conclusions change across this range."
    ),

    fluidRow(
      column(width = 6, textInput(ns("scenario_name"), "Scenario name", value = "Scenario 1")),
      column(width = 6, br(), actionButton(ns("apply_scenario"), "Apply scenario", icon = icon("play"), class = "btn-success", width = "100%"))
    ),

    uiOutput(ns("sufficiency_result")),
    uiOutput(ns("reach_section")),
    uiOutput(ns("temporal_and_save_section")),

    tags$hr(),
    h5("Saved scenarios"),
    p("Save a scenario, then select two or more (the baseline - no response applied - is always included) to compare them side by side."),
    DTOutput(ns("saved_scenarios_table")),
    actionButton(ns("compare_scenarios"), "Compare selected scenarios", icon = icon("balance-scale")),
    uiOutput(ns("comparison_result"))
  )
}

mod_responses_server <- function(id, schema, nodes, edges, graph, restore_state = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Revisao 1, Fase 3: `restore_state` is the scenario_state loaded from a
    # savepoint (NULL for New project/Import CSV/Combine savepoints - see
    # mod_data.R's rv$scenario_state, same reset-on-Start/restore-on-Load
    # pattern already used for graph node positions). Only ever read here,
    # to seed the *initial* value of a checkbox/slider when it's (re)drawn -
    # never written back into it, so a user's later manual changes are never
    # silently reverted by this module.
    restored <- function() if (is.null(restore_state)) NULL else restore_state()
    # `strengths` is a named atomic numeric vector (from read_savepoint()),
    # not a list - `[[` on an atomic vector throws "subscript out of
    # bounds" for a name that isn't present (unlike a list, where it
    # returns NULL), confirmed live: restoring a savepoint whose scenario
    # only activated some nodes crashed both control panels with exactly
    # that error the moment a not-yet-active node's strength was looked
    # up. `%in% names(...)` guards it explicitly instead of relying on
    # `[[`'s list-like behavior.
    restored_strength <- function(strengths, node_id) {
      if (is.null(strengths) || !(node_id %in% names(strengths))) {
        return(50)
      }
      val <- strengths[[node_id]]
      if (is.na(val)) 50 else val
    }

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

      rs <- restored()

      rows <- lapply(seq_len(nrow(rn)), function(i) {
        node_id <- rn$id[i]
        is_active <- !is.null(rs) && node_id %in% rs$response_active
        fluidRow(
          column(width = 6, checkboxInput(ns(paste0("active_", node_id)), rn$label[i], value = is_active)),
          column(width = 6, sliderInput(
            ns(paste0("strength_", node_id)), NULL, min = 0, max = 100, step = 5, post = "%",
            value = if (is.null(rs)) 50 else restored_strength(rs$response_strengths, node_id)
          ))
        )
      })

      tagList(rows)
    })

    # Revisao 1: the "pressure" side of the two pushes - Drivers/Pressures
    # the user expects to worsen. "Driver"/"Pressure" are literal category
    # names here, same as "Impact" is already hardcoded in a few places in
    # this codebase (e.g. R/sufficiency.R, R/metrics.R) rather than
    # generalized through the schema's role system.
    pressure_nodes <- reactive({
      req(nodes())
      n <- nodes()
      n[n$dpsir_category %in% c("Driver", "Pressure"), , drop = FALSE]
    })

    output$pressure_controls <- renderUI({
      req(graph())
      pn <- pressure_nodes()

      if (nrow(pn) == 0) {
        return(tags$div(
          class = "alert alert-warning",
          "No Driver or Pressure nodes in this network yet."
        ))
      }

      rs <- restored()

      rows <- lapply(seq_len(nrow(pn)), function(i) {
        node_id <- pn$id[i]
        is_active <- !is.null(rs) && node_id %in% rs$pressure_active
        fluidRow(
          column(width = 6, checkboxInput(ns(paste0("pressure_active_", node_id)), pn$label[i], value = is_active)),
          column(width = 6, sliderInput(
            ns(paste0("pressure_strength_", node_id)), NULL, min = 0, max = 100, step = 5, post = "%",
            value = if (is.null(rs)) 50 else restored_strength(rs$pressure_strengths, node_id)
          ))
        )
      })

      tagList(rows)
    })

    output$effect_horizon_ui <- renderUI({
      req(graph())
      rs <- restored()
      sliderInput(
        ns("effect_horizon"), "How far to trace the effect",
        min = 0.2, max = 0.8, step = 0.05,
        value = if (is.null(rs) || is.null(rs$effect_horizon)) 0.5 else rs$effect_horizon
      )
    })

    # =================================================
    # APPLY SCENARIO
    # =================================================

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
      reach <- response_reach(graph(), active_ids)

      # Revisao 1, Fase 2: the sufficiency reading. Pressure is optional -
      # an inactive pressure scenario is just an all-zero press vector,
      # which sufficiency() handles the same as any other (worsening = 0
      # everywhere, so "neutralized" trivially holds wherever the response
      # helps at all).
      pn <- pressure_nodes()
      pressure_active_ids <- pn$id[vapply(pn$id, function(node_id) isTRUE(input[[paste0("pressure_active_", node_id)]]), logical(1))]
      pressure_strengths <- setNames(numeric(length(pressure_active_ids)), pressure_active_ids)
      for (node_id in pressure_active_ids) {
        pressure_strengths[[node_id]] <- input[[paste0("pressure_strength_", node_id)]]
      }
      p_D <- build_press_vector(graph(), pressure_active_ids, pressure_strengths / 100)
      c_value <- input$effect_horizon

      suff_df <- sufficiency(graph(), p_D, press, c = c_value)
      suff_reach_over_c <- sufficiency_reach_over_c(graph(), p_D, press)

      suff_confidence_matrix <- build_confidence_matrix(graph(), p_D, rn, c = c_value)

      current_scenario(list(
        name = input$scenario_name,
        active = active_ids,
        strengths = strengths,
        press = press,
        reach = reach,
        pressure_active = pressure_active_ids,
        pressure_strengths = pressure_strengths,
        p_D = p_D,
        effect_horizon = c_value,
        sufficiency_df = suff_df,
        sufficiency_confidence_matrix = suff_confidence_matrix,
        sufficiency_reach_over_c = suff_reach_over_c
      ))
    })

    # =================================================
    # SUFFICIENCY MODEL (Revisao 1, Fase 2)
    # =================================================

    output$sufficiency_result <- renderUI({
      req(current_scenario())

      tagList(
        h5("Is the response enough? (sufficiency)"),
        p(
          class = "text-muted",
          "For each Impact: how much the pressure scenario worsens it, how much the response scenario mitigates it,",
          "and whether the mitigation is enough to neutralize the worsening."
        ),
        DTOutput(ns("sufficiency_table")),
        h5("How confident is that, response by response?"),
        p(
          class = "text-muted",
          "Every response in the network, evaluated alone at the strength set above, against the same pressure",
          "scenario: % of simulations - resampling every edge's weight within a range set by its confidence - in",
          "which that response alone neutralizes each Impact."
        ),
        DTOutput(ns("confidence_matrix_table")),
        h5("Does it hold up across how far the effect is traced?"),
        p(
          class = "text-muted",
          "Recomputes the neutralization verdict at different settings of \"How far to trace the effect\" -",
          "an Impact marked borderline has a verdict that changes somewhere in that range."
        ),
        DTOutput(ns("reach_over_c_table"))
      )
    })

    output$sufficiency_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      display <- format_sufficiency_table(sc$sufficiency_df, sc$active, sc$strengths)
      datatable(display, rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })

    output$confidence_matrix_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      df <- sc$sufficiency_confidence_matrix
      numeric_cols <- setdiff(names(df), "Response")

      dt <- datatable(df, rownames = FALSE, options = list(dom = "t", pageLength = 10))
      if (length(numeric_cols) > 0) {
        dt <- dt %>% formatRound(columns = numeric_cols, digits = 0)
      }
      dt
    })

    output$reach_over_c_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      display <- format_reach_over_c_table(sc$sufficiency_reach_over_c)
      datatable(display, rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })

    # Roadmap Fase 9 item 9.2: "reach" is pure graph traversal from what the
    # active response(s) directly act on (R/reach.R) - always defined,
    # independent of both readings above (sufficiency/temporal).
    output$reach_section <- renderUI({
      req(current_scenario())

      tagList(
        h5("Reach"),
        p(
          class = "text-muted",
          "How far this response's influence travels through the DPSIR chain - pure graph traversal,",
          "independent of the sufficiency reading above."
        ),
        uiOutput(ns("reach_summary")),
        DTOutput(ns("reach_table"))
      )
    })

    output$temporal_and_save_section <- renderUI({
      req(current_scenario())

      tagList(
        tags$hr(),
        checkboxInput(ns("show_temporal"), "Show temporal simulation across discrete time windows (optional)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("show_temporal")),
          p(
            class = "text-muted",
            "Runs the pressure and response scenarios forward window by window instead of reading a single instant -",
            "useful when a response might, windows later, become a new pressure itself (e.g. aid that grows the fleet,",
            "which later increases fishing effort)."
          ),
          fluidRow(
            column(4, sliderInput(ns("temporal_windows"), "Number of windows", min = 2, max = 15, value = 5, step = 1)),
            column(4, selectInput(
              ns("temporal_mode_pressure"), "Pressure scenario",
              choices = c("Ongoing (permanent)" = "permanent", "One-time (impulse)" = "impulse"),
              selected = "permanent"
            )),
            column(4, selectInput(
              ns("temporal_mode_response"), "Response scenario",
              choices = c("One-time (impulse)" = "impulse", "Ongoing (permanent)" = "permanent"),
              selected = "impulse"
            ))
          ),
          h5("How each Impact changes, window by window"),
          DTOutput(ns("temporal_table")),
          h5("Network storyboard"),
          p(
            class = "text-muted",
            "Same layout in every panel - only color and size change. Redder = increased from zero in this scenario,",
            "bluer = decreased; bigger = larger change. Watch how the pattern spreads or fades across windows."
          ),
          plotOutput(ns("temporal_storyboard"), height = "600px"),
          plot_download_row(ns, "temporal_storyboard")
        ),
        tags$hr(),
        actionButton(ns("save_scenario"), "Save this scenario", icon = icon("save"), class = "btn-outline-primary")
      )
    })

    # =================================================
    # TEMPORAL ENGINE (Revisao 1, Fase 6)
    # =================================================
    #
    # Shared by the table and the storyboard below, so both read the exact
    # same simulation for the current live inputs (windows/mode selectors),
    # not two separate runs that could disagree. Gated by
    # req(isTRUE(input$show_temporal)) so it doesn't run at all while the
    # disclosure is collapsed. withProgress()/incProgress() (plain shiny,
    # no new dependency) gives the user a "Window X of N" readout while it
    # runs - simulate_temporal_pair() itself (R/temporal.R) stays a pure,
    # Shiny-free function; the progress bar is wired in only through the
    # optional `on_step` callback it exposes for exactly this purpose.
    temporal_result <- reactive({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_temporal))

      windows <- input$temporal_windows

      withProgress(message = "Simulating temporal windows", value = 0, {
        simulate_temporal_pair(
          graph(), sc$p_D, sc$press, windows = windows,
          mode_D = input$temporal_mode_pressure, mode_R = input$temporal_mode_response,
          on_step = function(t, total) {
            incProgress(1 / total, detail = sprintf("Window %d of %d", t, total))
          }
        )
      })
    })

    output$temporal_table <- renderDT({
      tr <- temporal_result()
      req(tr)

      df <- format_temporal_table(graph(), tr)
      if (nrow(df) == 0) {
        return(datatable(
          data.frame(Note = "No Impact factors in this network yet."),
          rownames = FALSE, options = list(dom = "t")
        ))
      }

      df$id <- NULL
      names(df) <- c("Impact", "Window", "Baseline", "Scenario", "Verdict")

      datatable(df, rownames = FALSE, options = list(dom = "t", pageLength = 15)) %>%
        formatRound(columns = c("Baseline", "Scenario"), digits = 3)
    })

    # A fixed layout, computed once per network (same helper the Graph tab
    # uses) - only node color/size vary between storyboard panels, so the
    # network appears to hold still while the state "plays" across it.
    temporal_layout <- reactive({
      req(graph())
      compute_graph_layout(nodes(), schema())
    })

    output$temporal_storyboard <- renderPlot({
      tr <- temporal_result()
      req(tr)
      draw_temporal_storyboard(graph(), temporal_layout(), tr$scenario)
    })

    output$download_temporal_storyboard_png <- downloadHandler(
      filename = function() paste0("temporal_storyboard_", Sys.Date(), ".png"),
      content = function(file) {
        tr <- temporal_result()
        req(tr)
        n_panels <- nrow(tr$scenario)
        ncol_grid <- ceiling(sqrt(n_panels))
        nrow_grid <- ceiling(n_panels / ncol_grid)
        render_plot_png(
          function() draw_temporal_storyboard(graph(), temporal_layout(), tr$scenario),
          file, width = 260 * ncol_grid, height = 260 * nrow_grid
        )
      }
    )

    output$download_temporal_storyboard_svg <- downloadHandler(
      filename = function() paste0("temporal_storyboard_", Sys.Date(), ".svg"),
      content = function(file) {
        tr <- temporal_result()
        req(tr)
        n_panels <- nrow(tr$scenario)
        ncol_grid <- ceiling(sqrt(n_panels))
        nrow_grid <- ceiling(n_panels / ncol_grid)
        render_plot_svg(
          function() draw_temporal_storyboard(graph(), temporal_layout(), tr$scenario),
          file, width = 2.7 * ncol_grid, height = 2.7 * nrow_grid
        )
      }
    )

    # Roadmap Fase 9 item 9.2: "reach" is pure graph traversal from what the
    # active response(s) directly act on (R/reach.R).
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

    # =================================================
    # SAVE AND COMPARE SCENARIOS
    # =================================================

    saved_scenarios <- reactiveValues(list = list())
    scenario_counter <- reactiveVal(1)

    # Revisao 1, Fase 8: replaces the old Improves/Worsens/Stable summary
    # (scenario_direction_counts(), built from the now-removed equilibrium
    # reading) with a one-liner from the sufficiency reading instead - "how
    # many of this network's Impacts does this scenario's response
    # neutralize", the primary reading's own headline number.
    scenario_sufficiency_summary <- function(sc) {
      df <- sc$sufficiency_df
      if (is.null(df) || nrow(df) == 0) {
        return("No Impact factors")
      }
      sprintf("%d of %d Impacts neutralized", sum(df$neutralized), nrow(df))
    }

    observeEvent(input$save_scenario, {
      sc <- current_scenario()
      req(sc)

      # Revisao 1, Fase 7: the temporal disclosure's own settings, captured
      # at save time (not apply time) - the report (R/report.R) re-simulates
      # from sc$p_D/sc$press rather than storing the whole windows x nodes
      # history, so it needs to know how many windows and which
      # impulse/permanent mode to use.
      sc$temporal_windows <- input$temporal_windows %||% 5
      sc$temporal_mode_pressure <- input$temporal_mode_pressure %||% "permanent"
      sc$temporal_mode_response <- input$temporal_mode_response %||% "impulse"

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
        data.frame(
          Name = scenario_name,
          Responses = paste(sc$active, collapse = ", "),
          Summary = scenario_sufficiency_summary(sc),
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
        h5("Reach per scenario"),
        p(
          class = "text-muted",
          "How far each selected scenario's active response(s) can influence via some causal path."
        ),
        DTOutput(ns("comparison_reach_table"))
      )
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

    # Revisao 1, Fase 3: the *live* scenario builder state - read straight
    # off the current inputs, not off current_scenario() (which only
    # updates on "Apply scenario") - so a savepoint captures whatever the
    # user has configured on screen right now, applied or not. Read by
    # mod_wizard.R's download handler; never written to by this module.
    current_scenario_state <- reactive({
      rn <- response_nodes()
      pn <- pressure_nodes()

      response_active <- rn$id[vapply(rn$id, function(id) isTRUE(input[[paste0("active_", id)]]), logical(1))]
      response_strengths <- setNames(
        vapply(response_active, function(id) input[[paste0("strength_", id)]] %||% 50, numeric(1)),
        response_active
      )

      pressure_active <- pn$id[vapply(pn$id, function(id) isTRUE(input[[paste0("pressure_active_", id)]]), logical(1))]
      pressure_strengths <- setNames(
        vapply(pressure_active, function(id) input[[paste0("pressure_strength_", id)]] %||% 50, numeric(1)),
        pressure_active
      )

      list(
        response_active = response_active,
        response_strengths = response_strengths,
        pressure_active = pressure_active,
        pressure_strengths = pressure_strengths,
        effect_horizon = input$effect_horizon %||% 0.5
      )
    })

    list(
      current_scenario = current_scenario,
      response_nodes = response_nodes,
      saved_scenarios = reactive(saved_scenarios$list),
      scenario_state = current_scenario_state
    )
  })
}
