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
#   The path-analysis total effect of each push (products of the edges'
#   standardized strengths beta along each path; Revisao 2, Fase 1) -
#   answering "does the response's mitigation cover the pressure's
#   worsening on each Impact?" plus how confident that verdict is when every
#   beta is resampled within its uncertainty range.
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
build_confidence_matrix <- function(g, p_D, response_nodes_df, n_simulations = 300, seed = 42, planned = NULL) {
  if (nrow(response_nodes_df) == 0) {
    return(data.frame(Response = character(), stringsAsFactors = FALSE))
  }

  per_response <- lapply(seq_len(nrow(response_nodes_df)), function(i) {
    rid <- response_nodes_df$id[i]
    p_r <- build_press_vector(g, rid, setNames(1, rid))
    sufficiency_confidence(g, p_D, p_r, n_simulations = n_simulations, seed = seed)
  })

  if (nrow(per_response[[1]]) == 0) {
    return(data.frame(Response = response_nodes_df$label, stringsAsFactors = FALSE))
  }

  impact_labels <- per_response[[1]]$node
  mat <- do.call(rbind, lapply(per_response, function(sc) sc$neutralized_pct))
  colnames(mat) <- impact_labels

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  out <- cbind(Response = response_nodes_df$label, df, stringsAsFactors = FALSE)
  # Revisao 2, item 2.2: the rows above test each response alone at 100%;
  # this row resamples the scenario actually set (the sliders), i.e. the
  # confidence of the verdict shown in the sufficiency table.
  if (!is.null(planned) && any(planned != 0)) {
    pl <- sufficiency_confidence(g, p_D, planned, n_simulations = n_simulations, seed = seed)
    row <- as.data.frame(t(pl$neutralized_pct), stringsAsFactors = FALSE)
    names(row) <- impact_labels
    out <- rbind(cbind(Response = "Planned scenario (as set)", row, stringsAsFactors = FALSE), out)
  }
  out
}

mod_responses_ui <- function(id) {
  ns <- NS(id)

  tagList(
    # Revisao 1, Fase 2: two independent "pushes" the user builds - a
    # pressure scenario (what's getting worse) and a response scenario
    # (what's being done about it) - read by the sufficiency reading below.
    # Second round of Revisao 1: split into collapsible boxes (same pattern
    # already used by the Graph tab's left column) instead of one long
    # single-box column - easier to scan/collapse a section you're not
    # currently using than to scroll past it.
    p("Build two scenarios: what's pushing the system to get worse, and how you're responding to it. Then see whether the response is enough."),

    box(
      width = 12, title = "Pressure scenario", status = "primary", solidHeader = TRUE,
      collapsible = TRUE,
      p(class = "text-muted", "Optional. Turn on the Drivers/Pressures you expect to worsen, and how strongly."),
      uiOutput(ns("pressure_controls"))
    ),

    box(
      width = 12, title = "Response scenario", status = "primary", solidHeader = TRUE,
      collapsible = TRUE,
      p(class = "text-muted", "Turn on the responses you want to test, and how strongly each is implemented."),
      uiOutput(ns("response_controls")),
      tags$hr(),
      fluidRow(
        column(width = 6, textInput(ns("scenario_name"), "Scenario name", value = "Scenario 1")),
        column(width = 6, br(), actionButton(ns("apply_scenario"), "Apply scenario", icon = icon("play"), class = "btn-success", width = "100%"))
      )
    ),

    box(
      width = 12, title = "Results", status = "primary", solidHeader = TRUE,
      collapsible = TRUE,
      uiOutput(ns("sufficiency_result")),
      uiOutput(ns("reach_section")),
      tags$hr(),
      uiOutput(ns("save_scenario_section"))
    ),

    box(
      width = 12, title = "Temporal simulation", status = "primary", solidHeader = TRUE,
      collapsible = TRUE, collapsed = TRUE,
      uiOutput(ns("temporal_and_save_section"))
    ),

    box(
      width = 12, title = "Saved scenarios", status = "primary", solidHeader = TRUE,
      collapsible = TRUE, collapsed = TRUE,
      p("Save a scenario, then select two or more (the baseline - no response applied - is always included) to compare them side by side."),
      DTOutput(ns("saved_scenarios_table")),
      actionButton(ns("compare_scenarios"), "Compare selected scenarios", icon = icon("balance-scale")),
      uiOutput(ns("comparison_result"))
    )
  )
}

mod_responses_server <- function(id, schema, nodes, edges, graph, restore_state = NULL,
                                 epoch = NULL, graph_version = NULL) {
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
    # Revisao 2, item 0.4: what the scenario controls are (re)drawn with -
    # the last state the user had on screen when there is one (so a rebuild
    # after editing the network does not reset their scenario), else the
    # restored savepoint state. isolate() so moving a slider never
    # re-renders the whole panel.
    seed_state <- function() isolate(last_live_state()) %||% restored()
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

    # Revisao 2, item C0 (group F of Anexo X6): a push is a share of one
    # standard deviation (100% = 1 SD); it may go above 100%, or be given in
    # the factor's own units when it has a typical variation (SD).
    strength_control <- function(active_id, strength_id, units_id, label, active, value, sd) {
      has_sd <- !is.null(sd) && !is.na(sd)
      fluidRow(
        column(width = 6, checkboxInput(ns(active_id), label, value = active)),
        column(width = if (has_sd) 4 else 6, sliderInput(ns(strength_id), NULL, min = 0, max = 500, step = 5, post = "%", value = value)),
        if (has_sd) column(width = 2, numericInput(ns(units_id), "or, in units", value = NA, step = sd / 10))
      )
    }
    # The strength used: the units field (converted with the SD) when filled,
    # else the slider.
    effective_strength <- function(strength_id, units_id, sd) {
      units <- input[[units_id]]
      if (!is.null(units) && length(units) == 1 && !is.na(units) && !is.null(sd) && !is.na(sd)) {
        return(100 * units / sd)
      }
      input[[strength_id]] %||% 50
    }
    node_sd <- function(id) {
      n <- nodes()
      if (!"sd" %in% names(n)) return(NA_real_)
      suppressWarnings(as.numeric(n$sd[match(id, n$id)]))
    }

    response_nodes <- reactive({
      req(nodes(), schema())
      feedback_categories <- get_feedback_categories(schema())
      n <- nodes()
      n[n$dpsir_category %in% feedback_categories, , drop = FALSE]
    })

    # Revisao 2, item 0.4: the scenario controls only exist once the
    # Scenarios tab has actually been drawn for the CURRENT graph (Explore is
    # built lazily, and hidden outputs are suspended). Until then, input$active_*
    # is either missing or left over from a previous project with the same
    # ids - so current_scenario_state() falls back to the restored savepoint
    # state instead of saving an empty (or stale) scenario. Reset at a higher
    # priority than the outputs, so a re-render in the same flush wins.
    controls_live <- reactiveVal(FALSE)
    observeEvent(graph(), controls_live(FALSE), ignoreNULL = FALSE, priority = 100)

    output$response_controls <- renderUI({
      req(graph())
      rn <- response_nodes()
      controls_live(TRUE)

      if (nrow(rn) == 0) {
        return(tags$div(
          class = "alert alert-warning",
          "No Response nodes in this network yet. Add one in the Nodes step to build scenarios."
        ))
      }

      rs <- seed_state()

      rows <- lapply(seq_len(nrow(rn)), function(i) {
        node_id <- rn$id[i]
        is_active <- !is.null(rs) && node_id %in% rs$response_active
        strength_control(
          paste0("active_", node_id), paste0("strength_", node_id), paste0("units_", node_id),
          rn$label[i], is_active,
          if (is.null(rs)) 50 else restored_strength(rs$response_strengths, node_id),
          node_sd(node_id)
        )
      })

      tagList(rows)
    })

    # Revisao 1: the "pressure" side of the two pushes - Drivers/Pressures
    # the user expects to worsen. Revisao 2, item 2.6: by role, so renamed
    # levels keep working.
    pressure_nodes <- reactive({
      req(nodes(), schema())
      n <- nodes()
      n[roles_of(n$dpsir_category, schema()) %in% c("driver", "pressure"), , drop = FALSE]
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

      rs <- seed_state()

      rows <- lapply(seq_len(nrow(pn)), function(i) {
        node_id <- pn$id[i]
        is_active <- !is.null(rs) && node_id %in% rs$pressure_active
        strength_control(
          paste0("pressure_active_", node_id), paste0("pressure_strength_", node_id), paste0("pressure_units_", node_id),
          pn$label[i], is_active,
          if (is.null(rs)) 50 else restored_strength(rs$pressure_strengths, node_id),
          node_sd(node_id)
        )
      })

      tagList(rows)
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
        strengths[[node_id]] <- effective_strength(paste0("strength_", node_id), paste0("units_", node_id), node_sd(node_id))
      }

      press <- build_press_vector(graph(), active_ids, strengths / 100)

      # Revisao 1, Fase 2: the sufficiency reading. Pressure is optional -
      # an inactive pressure scenario is just an all-zero press vector,
      # which sufficiency() handles the same as any other (worsening = 0
      # everywhere, so "neutralized" trivially holds wherever the response
      # helps at all).
      pn <- pressure_nodes()
      pressure_active_ids <- pn$id[vapply(pn$id, function(node_id) isTRUE(input[[paste0("pressure_active_", node_id)]]), logical(1))]
      pressure_strengths <- setNames(numeric(length(pressure_active_ids)), pressure_active_ids)
      for (node_id in pressure_active_ids) {
        pressure_strengths[[node_id]] <- effective_strength(paste0("pressure_strength_", node_id), paste0("pressure_units_", node_id), node_sd(node_id))
      }
      p_D <- build_press_vector(graph(), pressure_active_ids, pressure_strengths / 100)

      # Segunda rodada da Revisao 1: withProgress em torno do calculo -
      # build_confidence_matrix() sozinho roda 300 simulacoes POR resposta
      # existente na rede (nao so as ativas), perceptivel numa rede maior;
      # sem isso o clique em "Apply scenario" nao dava nenhum feedback
      # visual ate a tela inteira atualizar de uma vez, parecendo travado.
      # Revisao 2, item 0.5: an error in an observer ends the whole Shiny
      # session (the app greys out and every tab stops responding). Catch
      # it here, keep the previous results on screen and tell the user.
      ok <- tryCatch({
        withProgress(message = "Computing scenario results", value = 0, {
          incProgress(0.1, detail = "Reach")
          reach <- response_reach(graph(), active_ids)

          incProgress(0.2, detail = "Sufficiency")
          suff_df <- sufficiency(graph(), p_D, press)

          incProgress(0.3, detail = "Confidence (resampling edge strengths)")
          suff_confidence_matrix <- build_confidence_matrix(graph(), p_D, rn, planned = press)

          # Revisao 2, items C4/C5: State triggers (pressure only vs. with the
          # response) and the reach that the closed triggers leave.
          gates_pressure <- state_gates(graph(), p_D)
          gates_net <- state_gates(graph(), p_D + press)
          reach_effective <- effective_response_reach(graph(), active_ids, gates_net$id[!gates_net$open])

          # Revisao 2, item B7: relevance and priority of each Impact.
          incProgress(0.1, detail = "Impact prioritization")
          prioritization <- impact_prioritization(graph(), p_D, suff_df)
          incProgress(0.4, detail = "Done")
        })
        TRUE
      }, error = function(e) {
        showNotification(paste("Could not apply the scenario:", conditionMessage(e)), type = "error", duration = NULL)
        FALSE
      })
      if (!ok) return()

      current_scenario(list(
        name = input$scenario_name,
        active = active_ids,
        strengths = strengths,
        press = press,
        reach = reach,
        pressure_active = pressure_active_ids,
        pressure_strengths = pressure_strengths,
        p_D = p_D,
        sufficiency_df = suff_df,
        sufficiency_confidence_matrix = suff_confidence_matrix,
        prioritization = prioritization,
        gates_pressure = gates_pressure,
        gates_net = gates_net,
        reach_effective = reach_effective
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
          "scenario: % of simulations - resampling every edge's strength within its uncertainty range - in",
          "which that response alone neutralizes each Impact."
        ),
        DTOutput(ns("confidence_matrix_table")),
        uiOutput(ns("triggers_section")),
        # Revisao 2, item B7.
        h5("Impact prioritization"),
        p(
          class = "text-muted",
          "Which Impact to act on first. Relevance = value v x importance D (how much the pressure moves it,",
          "relative to the most affected Impact) x reliability (how often that prediction keeps its sign).",
          "Priority = relevance x gap (the share of the worsening the response leaves uncovered)."
        ),
        DTOutput(ns("prioritization_table")),
        plotOutput(ns("prioritization_plot"), height = "320px"),
        downloadButton(ns("download_prioritization_csv"), "Download CSV", class = "btn-sm"),
        tags$p(class = "text-muted", style = "font-size: 12px; margin-top: 6px;", PRIORITIZATION_METHOD_NOTE),
        uiOutput(ns("prioritization_note"))
      )
    })

    output$sufficiency_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      display <- format_sufficiency_table(sc$sufficiency_df, sc$active, sc$strengths)
      datatable(display, rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })

    output$prioritization_table <- renderDT({
      sc <- current_scenario()
      req(sc, sc$prioritization)
      datatable(format_prioritization_table(sc$prioritization), rownames = FALSE, options = list(dom = "t", pageLength = 20))
    })

    output$prioritization_plot <- renderPlot({
      sc <- current_scenario()
      req(sc, sc$prioritization)
      draw_prioritization_plot(sc$prioritization)
    })

    output$prioritization_note <- renderUI({
      sc <- current_scenario()
      req(sc, sc$prioritization)
      if (isTRUE(attr(sc$prioritization, "all_zero"))) {
        div(class = "alert alert-warning", "The pressure scenario does not move any Impact, so importance D is 0 everywhere.")
      }
    })

    output$download_prioritization_csv <- downloadHandler(
      filename = function() paste0("impact_prioritization_", Sys.Date(), ".csv"),
      content = function(file) {
        sc <- current_scenario()
        req(sc, sc$prioritization)
        utils::write.csv(format_prioritization_table(sc$prioritization), file, row.names = FALSE)
      }
    )

    output$confidence_matrix_table <- renderDT({
      sc <- current_scenario()
      req(sc)

      datatable(format_confidence_matrix(sc$sufficiency_confidence_matrix), rownames = FALSE, options = list(dom = "t", pageLength = 20))
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

    # Revisao 2, Fase A: the temporal settings as one list - live inputs when
    # the controls exist, else the restored/last state (item 0.4), else the
    # defaults (D2: permanent / permanent / until neutralized, 50 windows).
    temporal_defaults <- list(
      temporal_mode_pressure = "permanent", temporal_mode_response = "permanent",
      temporal_stop_rule = "until_neutralized", temporal_max_windows = 50,
      temporal_windows = 5, temporal_tol_rel = 5, baseline_without_response = FALSE,
      temporal_gate_mode = "state_level",
      # Revisao 2, Fase D.
      temporal_trends_outside = TRUE, temporal_continue_after = 0
    )
    present <- function(v) !is.null(v) && length(v) == 1 && !is.na(v)
    temporal_setting <- function(name, state = NULL) {
      if (present(input[[name]])) return(input[[name]])
      if (present(state[[name]])) return(state[[name]])
      temporal_defaults[[name]]
    }
    temporal_settings <- function(state = NULL) {
      out <- setNames(lapply(names(temporal_defaults), temporal_setting, state = state), names(temporal_defaults))
      out$temporal_schedule <- temporal_schedule(state)
      out
    }

    # Revisao 2, Fase D: "For a number of windows" - start and duration per
    # pushed factor (live inputs when present, else the saved schedule).
    schedule_ids <- function() {
      sc <- current_scenario()
      if (is.null(sc)) return(character())
      ids <- c(names(sc$p_D)[sc$p_D != 0], names(sc$press)[sc$press != 0])
      unique(ids[!is.na(ids)])
    }
    temporal_schedule <- function(state = NULL) {
      saved <- state$temporal_schedule
      if (is.null(saved) || !is.data.frame(saved)) {
        saved <- data.frame(id = character(), start = numeric(), duration = numeric(), stringsAsFactors = FALSE)
      }
      ids <- union(isolate(schedule_ids()), saved$id)
      if (length(ids) == 0) return(saved)
      rows <- lapply(ids, function(id) {
        s_in <- input[[paste0("sched_start_", id)]]
        d_in <- input[[paste0("sched_dur_", id)]]
        k <- match(id, saved$id)
        data.frame(
          id = id,
          start = if (present(s_in)) s_in else if (!is.na(k)) saved$start[k] else 1,
          duration = if (present(d_in)) d_in else if (!is.na(k)) saved$duration[k] else 1,
          stringsAsFactors = FALSE
        )
      })
      do.call(rbind, rows)
    }

    mode_help <- c(
      permanent = "The push is added again every window, so its effect keeps building up. Use for an ongoing pressure or a management effort that keeps being applied. A response can overshoot and push the Impact below zero.",
      impulse = "The push is applied in window 1 only; the level it creates stays in the system (it fades only if that factor has self-regulation). Use for a one-off event or measure.",
      window = "The push is added in every window of a period you set per factor (start and duration below), then stops - e.g. an aid programme that ran for five years."
    )
    output$mode_help_pressure <- renderUI(helpText(mode_help[[input$temporal_mode_pressure %||% "permanent"]]))
    output$mode_help_response <- renderUI(helpText(mode_help[[input$temporal_mode_response %||% "permanent"]]))

    output$temporal_and_save_section <- renderUI({
      req(current_scenario())
      # isolate(): reading the temporal inputs here must not make this whole
      # section re-render (and untick "Show temporal simulation") every time
      # one of them changes - they are only used as starting values.
      ts <- isolate(temporal_settings(seed_state()))
      mode_choices <- c("Added every window (default)" = "permanent", "Applied once and held" = "impulse",
                        "For a number of windows" = "window")
      has_growth <- any(build_growth_rate_vector(graph()) != 0)

      tagList(
        checkboxInput(ns("show_temporal"), "Show temporal simulation across discrete time windows (optional)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("show_temporal")),
          p(
            class = "text-muted",
            "Runs the pressure and response scenarios forward window by window instead of reading a single instant -",
            "useful when a response might, windows later, become a new pressure itself (e.g. aid that grows the fleet,",
            "which later increases fishing effort)."
          ),
          # Revisao 2, items A1-A4.
          fluidRow(
            column(6,
              selectInput(ns("temporal_mode_pressure"), "Pressure", choices = mode_choices, selected = ts$temporal_mode_pressure),
              uiOutput(ns("mode_help_pressure"))
            ),
            column(6,
              selectInput(ns("temporal_mode_response"), "Response", choices = mode_choices, selected = ts$temporal_mode_response),
              uiOutput(ns("mode_help_response"))
            )
          ),
          conditionalPanel(
            condition = sprintf("input['%s'] == 'window' || input['%s'] == 'window'", ns("temporal_mode_pressure"), ns("temporal_mode_response")),
            uiOutput(ns("schedule_controls"))
          ),
          # Revisao 2, Fase D (D10).
          if (has_growth) {
            tagList(
              checkboxInput(
                ns("temporal_trends_outside"), "Apply growth trends even to factors outside the pressure scenario",
                value = !isFALSE(ts$temporal_trends_outside)
              ),
              helpText(
                "A factor with a growth rate moves its base level by itself every window, in the baseline and in the",
                "scenario alike - so the difference between them does not depend on growth unless a threshold is crossed."
              )
            )
          },
          fluidRow(
            column(6,
              selectInput(
                ns("temporal_stop_rule"), "Simulation length",
                choices = c("Until the response neutralizes the Impact (default)" = "until_neutralized",
                            "Fixed number of windows" = "fixed"),
                selected = ts$temporal_stop_rule
              ),
              conditionalPanel(
                condition = sprintf("input['%s'] == 'until_neutralized'", ns("temporal_stop_rule")),
                numericInput(ns("temporal_max_windows"), "Maximum windows", value = ts$temporal_max_windows, min = 1, max = 200, step = 1),
                # Revisao 2, item D4: with a growing trend, neutralizing may be temporary.
                numericInput(ns("temporal_continue_after"), "Continue after neutralizing (windows)", value = ts$temporal_continue_after %||% 0, min = 0, max = 100, step = 1)
              ),
              conditionalPanel(
                condition = sprintf("input['%s'] == 'fixed'", ns("temporal_stop_rule")),
                numericInput(ns("temporal_windows"), "Windows", value = ts$temporal_windows, min = 1, max = 200, step = 1)
              )
            ),
            column(6,
              numericInput(ns("temporal_tol_rel"), "Neutralization tolerance (% of baseline)", value = ts$temporal_tol_rel, min = 0, max = 50, step = 1),
              helpText("Only labels the table ('Neutralized (relative)'); the run stops only when the Impact reaches zero."),
              checkboxInput(ns("baseline_without_response"), "Baseline without any response (ignore Impact -> Response links)", value = isTRUE(ts$baseline_without_response))
            )
          ),
          # Revisao 2, item C3 (D11, P1): only shown when some State has a threshold.
          if (has_state_thresholds(graph())) {
            tagList(
              selectInput(
                ns("temporal_gate_mode"), "Trigger criterion",
                choices = c("Accumulated State level (default)" = "state_level",
                            "Load arriving at the State" = "load",
                            "Compare both" = "compare"),
                selected = ts$temporal_gate_mode
              ),
              helpText(
                "Load = did what arrives in this window pass the limit? Accumulated = has the State already deviated",
                "beyond the critical point, adding up every window? A weak but steady pressure may never trigger by load,",
                "and still trigger by accumulation."
              )
            )
          },
          uiOutput(ns("temporal_stop_note")),
          uiOutput(ns("temporal_stability_note")),
          uiOutput(ns("temporal_growth_note")),
          uiOutput(ns("temporal_gates_section")),
          uiOutput(ns("temporal_levels_section")),
          uiOutput(ns("temporal_intensity_section")),
          h5("How each Impact changes, window by window"),
          DTOutput(ns("temporal_table")),
          h5("How each Impact changes over time"),
          p(
            class = "text-muted",
            "One panel per Impact. The dashed grey line is the baseline (pressure only); the solid line is Net",
            "(pressure and response together), with each point colored by that window's Verdict. The shaded",
            "band is the neutralized zone (Net ≤ 0) - a Net point resting in that band means neutralized,",
            "not merely \"below the baseline\"."
          ),
          plotOutput(ns("temporal_chart"), height = "600px"),
          plot_download_row(ns, "temporal_chart")
        )
      )
    })

    # Split out of temporal_and_save_section (second round of Revisao 1):
    # "Save this scenario" isn't specific to the temporal disclosure, it
    # saves whatever's in current_scenario() - now shown in the "Results"
    # box instead of being buried inside the (collapsed-by-default)
    # "Temporal simulation" box, so it stays easy to find.
    output$save_scenario_section <- renderUI({
      req(current_scenario())
      actionButton(ns("save_scenario"), "Save this scenario", icon = icon("save"), class = "btn-outline-primary")
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
    output$schedule_controls <- renderUI({
      sc <- current_scenario()
      req(sc)
      # Only the groups set to "For a number of windows".
      ids <- c(
        if (identical(input$temporal_mode_pressure, "window")) names(sc$p_D)[sc$p_D != 0],
        if (identical(input$temporal_mode_response, "window")) names(sc$press)[sc$press != 0]
      )
      req(length(ids) > 0)
      sched <- isolate(temporal_schedule(seed_state()))
      labs <- nodes()$label[match(ids, nodes()$id)]
      tagList(
        tags$h6("Period of each push (for a number of windows)"),
        lapply(seq_along(ids), function(i) {
          k <- match(ids[i], sched$id)
          fluidRow(
            column(6, tags$p(style = "margin-top: 30px;", labs[i])),
            column(3, numericInput(ns(paste0("sched_start_", ids[i])), "Start window", value = if (is.na(k)) 1 else sched$start[k], min = 1, step = 1)),
            column(3, numericInput(ns(paste0("sched_dur_", ids[i])), "Windows", value = if (is.na(k)) 1 else sched$duration[k], min = 1, step = 1))
          )
        })
      )
    })

    # Revisao 2, item D3: which factors carry a growth trend.
    output$temporal_growth_note <- renderUI({
      gr <- build_growth_rate_vector(graph())
      gr <- gr[gr != 0]
      req(length(gr) > 0)
      labs <- V(graph())$label[match(names(gr), V(graph())$name)]
      tags$p(class = "text-muted", sprintf("Factors with a growth trend: %s.", paste(sprintf("%s (%+.1f%%/window)", labs, 100 * gr), collapse = ", ")))
    })

    intensity_table <- reactive({
      tr <- temporal_result()
      req(tr, ncol(tr$edge_intensity) > 0)
      edge_intensity_table(graph(), tr)
    })
    output$temporal_intensity_section <- renderUI({
      tr <- temporal_result()
      req(tr, ncol(tr$edge_intensity) > 0)
      tagList(
        h5("Edge intensity by window"),
        p(class = "text-muted",
          "What each edge leaving a growing factor or a thresholded State passes on in each window: strength x the",
          "source's level (deviation + trend), in the scenario run. A closed trigger passes nothing."),
        DTOutput(ns("temporal_intensity_table")),
        downloadButton(ns("download_intensity_csv"), "Download CSV", class = "btn-sm")
      )
    })
    output$temporal_intensity_table <- renderDT({
      datatable(intensity_table(), rownames = FALSE, options = list(dom = "tp", pageLength = 10, scrollX = TRUE))
    })
    output$download_intensity_csv <- downloadHandler(
      filename = function() paste0("edge_intensity_", Sys.Date(), ".csv"),
      content = function(file) utils::write.csv(intensity_table(), file, row.names = FALSE)
    )

    temporal_result <- reactive({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_temporal))

      ts <- temporal_settings()

      # Revisao 2, item 0.5: report the failure instead of leaving the
      # table/chart blank with Shiny's terse grey error text.
      tryCatch(
        withProgress(message = "Simulating temporal windows", value = 0, {
          simulate_temporal_pair(
            graph(), sc$p_D, sc$press,
            windows = max(1, ts$temporal_windows %||% 5),
            mode_D = ts$temporal_mode_pressure, mode_R = ts$temporal_mode_response,
            stop_rule = ts$temporal_stop_rule,
            max_windows = max(1, ts$temporal_max_windows %||% 50),
            baseline_without_response = isTRUE(ts$baseline_without_response),
            gate_mode = if (identical(ts$temporal_gate_mode, "load")) "load" else "state_level",
            schedule = ts$temporal_schedule,
            trends_outside = !isFALSE(ts$temporal_trends_outside),
            continue_after = ts$temporal_continue_after %||% 0,
            on_step = function(t, total) {
              incProgress(1 / total, detail = sprintf("Window %d of %d", t, total))
            }
          )
        }),
        error = function(e) {
          showNotification(paste("The temporal simulation failed:", conditionMessage(e)), type = "error", duration = NULL)
          req(FALSE)
        }
      )
    })

    # Revisao 2, item C3: the same run with the other criterion, for
    # "Compare both".
    temporal_result_load <- reactive({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_temporal), identical(input$temporal_gate_mode, "compare"))
      ts <- temporal_settings()
      simulate_temporal_pair(
        graph(), sc$p_D, sc$press,
        windows = max(1, ts$temporal_windows %||% 5),
        mode_D = ts$temporal_mode_pressure, mode_R = ts$temporal_mode_response,
        stop_rule = ts$temporal_stop_rule, max_windows = max(1, ts$temporal_max_windows %||% 50),
        baseline_without_response = isTRUE(ts$baseline_without_response), gate_mode = "load",
        schedule = ts$temporal_schedule, trends_outside = !isFALSE(ts$temporal_trends_outside),
        continue_after = ts$temporal_continue_after %||% 0
      )
    })

    output$temporal_gates_section <- renderUI({
      tr <- temporal_result()
      req(tr, nrow(tr$thresholds) > 0)
      compare <- identical(input$temporal_gate_mode, "compare")
      tagList(
        h5("State triggers, window by window"),
        p(class = "text-muted", if (compare) {
          "Open/closed in the scenario run, by accumulated level and by load; windows where they disagree are marked."
        } else {
          "Open/closed in the scenario run (pressure and response together)."
        }),
        DTOutput(ns("temporal_gates_table")),
        if (compare) uiOutput(ns("temporal_compare_note"))
      )
    })

    output$temporal_gates_table <- renderDT({
      tr <- temporal_result()
      req(tr, nrow(tr$thresholds) > 0)
      labs <- V(graph())$label[match(tr$thresholds$id, V(graph())$name)]
      df <- data.frame(Window = seq_len(nrow(tr$gates_scenario)), check.names = FALSE)
      for (k in seq_along(labs)) df[[labs[k]]] <- ifelse(tr$gates_scenario[, k], "open", "closed")
      if (identical(input$temporal_gate_mode, "compare")) {
        trl <- temporal_result_load()
        n <- min(nrow(df), nrow(trl$gates_scenario))
        for (k in seq_along(labs)) {
          col <- paste0(labs[k], " (load)")
          df[[col]] <- NA_character_
          df[[col]][seq_len(n)] <- ifelse(trl$gates_scenario[seq_len(n), k], "open", "closed")
        }
      }
      datatable(df, rownames = FALSE, options = list(dom = "tp", pageLength = 10))
    })

    output$temporal_compare_note <- renderUI({
      tr <- temporal_result(); trl <- temporal_result_load()
      n <- min(nrow(tr$gates_scenario), nrow(trl$gates_scenario))
      differ <- which(rowSums(tr$gates_scenario[seq_len(n), , drop = FALSE] != trl$gates_scenario[seq_len(n), , drop = FALSE]) > 0)
      tags$p(
        if (length(differ) == 0) "The two criteria agree in every window." else sprintf("The criteria disagree in window(s) %s.", paste(differ, collapse = ", ")),
        tags$br(),
        sprintf("By load: %s", temporal_stop_note(trl) %||% "")
      )
    })

    # Revisao 2, item C0: levels in the factor's own units for factors with
    # an initial level (reference value).
    output$temporal_levels_section <- renderUI({
      tr <- temporal_result()
      req(tr)
      df <- temporal_level_table(graph(), tr)
      req(nrow(df) > 0)
      warn <- temporal_extrapolation_note(graph(), tr)
      tagList(
        h5("Change relative to initial values"),
        p(class = "text-muted", "Level = initial level + typical variation x deviation, at the last window shown."),
        DTOutput(ns("temporal_levels_table")),
        if (!is.null(warn)) div(class = "alert alert-warning", warn)
      )
    })

    output$temporal_levels_table <- renderDT({
      tr <- temporal_result()
      req(tr)
      datatable(temporal_level_table(graph(), tr), rownames = FALSE, options = list(dom = "t", pageLength = 20))
    })

    output$temporal_stop_note <- renderUI({
      tr <- temporal_result()
      req(tr)
      note <- temporal_stop_note(tr)
      req(note)
      div(class = if (is.na(tr$neutralized_at)) "alert alert-secondary" else "alert alert-success", role = "status", note)
    })

    temporal_tol <- function() max(0, (input$temporal_tol_rel %||% 5)) / 100

    output$temporal_stability_note <- renderUI({
      tr <- temporal_result()
      req(tr)
      note <- temporal_stability_note(tr$stability)
      req(note)
      div(class = "alert alert-warning", role = "alert", note)
    })

    output$temporal_table <- renderDT({
      tr <- temporal_result()
      req(tr)

      df <- format_temporal_table(graph(), tr, tol_rel = temporal_tol())
      if (nrow(df) == 0) {
        return(datatable(
          data.frame(Note = "No Impact factors in this network yet."),
          rownames = FALSE, options = list(dom = "t")
        ))
      }

      df$id <- NULL
      # "Net" (not "Scenario") - same vocabulary as the sufficiency table's
      # Worsening/Mitigation/Net columns, see the rename note above
      # format_temporal_table() in R/temporal.R.
      names(df) <- c("Impact", "Window", "Baseline", "Net", "Verdict")

      # Real bug, found live testing the Gnanapragasam example (Fase 9, 5
      # Impact nodes): row count here is windows x Impacts, genuinely
      # unbounded (up to 15 windows), unlike every other table in this app
      # that uses dom = "t" (no pagination UI) because it's always small
      # enough to fit on one screen. Without "p" (pagination controls), DT
      # still silently caps rendering at pageLength rows with no way to see
      # the rest - confirmed live: with 5 Impacts, pageLength = 15 hid every
      # window past window 2, even though the simulation itself (checked via
      # the storyboard's own panel count) had correctly computed all of them.
      dt <- datatable(df, rownames = FALSE, options = list(dom = "tp", pageLength = 15)) %>%
        formatRound(columns = c("Baseline", "Net"), digits = 3)
      # Revisao 2, item A2: highlight the window in which the run stopped.
      if (!is.na(tr$neutralized_at)) {
        dt <- dt %>% formatStyle("Window", target = "row",
                                 backgroundColor = styleEqual(tr$neutralized_at, "#e7f4ea"))
      }
      dt
    })

    # Revisao 1 (guia externo sobre o relatorio como material
    # suplementar): substitui o storyboard de paineis-de-rede por um
    # grafico de linha por Impacto (plot_temporal_storyboard(), novo em
    # R/scenario_plots.R) - ver o motivo real (nao so' estetico) no
    # cabecalho daquela funcao. Nao precisa mais de layout/posicoes do
    # grafo (o grafico e' so' valor x janela, sem rede desenhada), entao
    # `temporal_layout`/`layout_settings`/`positions` (que so' existiam
    # pra alimentar o storyboard antigo) saem daqui e do restante da
    # cadeia (mod_graph.R's retorno, mod_wizard.R, R/report.R,
    # mod_report.R) - nenhum outro consumidor os usava.
    temporal_chart_df <- reactive({
      tr <- temporal_result()
      req(tr)
      format_temporal_table(graph(), tr, tol_rel = temporal_tol())
    })

    output$temporal_chart <- renderPlot({
      tr <- temporal_result()
      req(tr)
      plot_temporal_storyboard(temporal_chart_df(), reinforcing_warning = isTRUE(tr$stability$unbounded), neutralized_at = tr$neutralized_at)
    })

    output$download_temporal_chart_png <- downloadHandler(
      filename = function() paste0("temporal_chart_", Sys.Date(), ".png"),
      content = function(file) {
        tr <- temporal_result()
        req(tr)
        render_plot_png(
          function() plot_temporal_storyboard(temporal_chart_df(), reinforcing_warning = isTRUE(tr$stability$unbounded), neutralized_at = tr$neutralized_at),
          file, width = 900, height = 700
        )
      }
    )

    output$download_temporal_chart_svg <- downloadHandler(
      filename = function() paste0("temporal_chart_", Sys.Date(), ".svg"),
      content = function(file) {
        tr <- temporal_result()
        req(tr)
        render_plot_svg(
          function() plot_temporal_storyboard(temporal_chart_df(), reinforcing_warning = isTRUE(tr$stability$unbounded), neutralized_at = tr$neutralized_at),
          file, width = 9.4, height = 7.3
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
      reached_impacts_row <- sc$reach$impacts
      reached_impacts <- if (length(reached_impacts_row) == 0) 0 else reached_impacts_row

      eff <- sc$reach_effective
      tagList(
        tags$p(
          tags$strong(sprintf("%d factor%s reachable in the network", sc$reach$total, if (sc$reach$total == 1) "" else "s")),
          sprintf(", including %d of %d Impact%s.", reached_impacts, total_impacts, if (total_impacts == 1) "" else "s")
        ),
        # Revisao 2, item C5 (D12): what this scenario actually reaches, not
        # crossing States whose trigger is closed.
        if (!is.null(eff) && length(eff$closed) > 0 && eff$total < sc$reach$total) {
          tags$p(sprintf(
            "In this scenario: %d reached - the trigger of %s is closed, so nothing passes beyond it.",
            eff$total, paste(eff$closed_labels, collapse = ", ")
          ))
        }
      )
    })

    # Revisao 2, item C4: State triggers table.
    output$triggers_section <- renderUI({
      sc <- current_scenario()
      req(sc, !is.null(sc$gates_pressure), nrow(sc$gates_pressure) > 0)
      tagList(
        h5("State triggers"),
        p(
          class = "text-muted",
          "A State with a threshold passes its effect on only once its deviation crosses the threshold. Deviations",
          "are in standard deviations (the model's units); the threshold is shown in the factor's own units and in SD."
        ),
        DTOutput(ns("triggers_table")),
        if (isTRUE(attr(sc$gates_net, "unstable")) || isTRUE(attr(sc$gates_pressure, "unstable"))) {
          div(class = "alert alert-warning", "A trigger switches on and off with the feedback loop and never settles - it was treated as open.")
        }
      )
    })

    output$triggers_table <- renderDT({
      sc <- current_scenario()
      req(sc, nrow(sc$gates_pressure) > 0)
      datatable(format_triggers_table(graph(), sc$gates_pressure, sc$gates_net), rownames = FALSE, options = list(dom = "t"))
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
      # Revisao 2, item A5: every temporal setting, so the report re-runs
      # the same simulation.
      sc <- utils::modifyList(sc, isolate(temporal_settings(seed_state())))

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

    # Revisao 2, item 0.2: a new project (any Start action - see
    # mod_data.R's rv$epoch) must not inherit the previous project's
    # applied/saved scenarios, comparison selection or name counter.
    reset_scenario_state <- function() {
      current_scenario(NULL)
      saved_scenarios$list <- list()
      comparison_selection(NULL)
      scenario_counter(1)
      updateTextInput(session, "scenario_name", value = "Scenario 1")
    }

    if (!is.null(epoch)) {
      observeEvent(epoch(), reset_scenario_state(), ignoreInit = TRUE)
    }

    # Revisao 2, item 0.3: saved scenarios store press vectors and results
    # computed on the network as it was when they were saved. Once the
    # network changes and the graph is rebuilt (mod_data.R's graph_version),
    # those results no longer describe this network - clear them rather
    # than let the report mix old and new numbers.
    if (!is.null(graph_version)) {
      observeEvent(graph_version(), {
        n_saved <- length(saved_scenarios$list)
        current_scenario(NULL)
        saved_scenarios$list <- list()
        comparison_selection(NULL)
        if (n_saved > 0) {
          showNotification(
            sprintf("The network changed and was rebuilt: %d saved scenario(s) were cleared. Apply and save them again.", n_saved),
            type = "warning", duration = 10
          )
        }
      }, ignoreInit = TRUE)
    }

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
        reached_impacts_row <- reach$impacts
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
    live_state_from_inputs <- function() {
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

      c(
        list(
          response_active = response_active,
          response_strengths = response_strengths,
          pressure_active = pressure_active,
          pressure_strengths = pressure_strengths
        ),
        # Revisao 2, item A5.
        temporal_settings(isolate(restored()))
      )
    }

    # Revisao 2, item 0.4: the last state read from live controls survives
    # the controls going stale (network edited, graph invalidated) - so a
    # user who configured a scenario, went back to fix a label and saved
    # keeps what they configured, not the older savepoint's scenario.
    last_live_state <- reactiveVal(NULL)
    observe({
      req(isTRUE(controls_live()))
      last_live_state(live_state_from_inputs())
    })
    if (!is.null(epoch)) {
      observeEvent(epoch(), last_live_state(NULL), ignoreInit = TRUE, priority = 100)
    }

    # Keeps only factors that still exist in the network, so a fallback
    # state never saves ids of nodes removed since it was captured.
    keep_existing_ids <- function(st) {
      if (is.null(st)) return(NULL)
      ids <- nodes()$id
      st$response_active <- intersect(st$response_active, ids)
      st$response_strengths <- st$response_strengths[names(st$response_strengths) %in% ids]
      st$pressure_active <- intersect(st$pressure_active, ids)
      st$pressure_strengths <- st$pressure_strengths[names(st$pressure_strengths) %in% ids]
      st
    }

    # Revisao 1, Fase 3 / Revisao 2, item 0.4: the scenario state saved into
    # the savepoint. Live controls when they exist for the current graph;
    # otherwise the last live state, and failing that the restored one.
    current_scenario_state <- reactive({
      if (isTRUE(controls_live())) {
        return(live_state_from_inputs())
      }
      keep_existing_ids(last_live_state() %||% restored())
    })

    list(
      current_scenario = current_scenario,
      response_nodes = response_nodes,
      saved_scenarios = reactive(saved_scenarios$list),
      scenario_state = current_scenario_state
    )
  })
}
