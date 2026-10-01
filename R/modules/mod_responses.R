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
# Revisao 3: the app computes in a single process, so the confidence
# readings are capped at 300 simulations (the simulated-network experiment
# of the manuscript uses more, in parallel, outside the app).
APP_MAX_SIMULATIONS <- 300L
APP_SIMULATION_CHOICES <- c(100L, 300L)

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
# Revisao 2, item 3.13: everything "Apply scenario" computes, as one
# function - also used to rebuild the saved scenarios of a savepoint.
# Strengths are in % (as on the sliders).
compute_scenario <- function(g, response_nodes_df, name, active_ids, strengths,
                             pressure_active_ids, pressure_strengths, n_simulations = 300, structural = FALSE,
                             progress = function(amount, detail) invisible(NULL)) {
  press <- build_press_vector(g, active_ids, strengths / 100)
  p_D <- build_press_vector(g, pressure_active_ids, pressure_strengths / 100)
  progress(0.1, "Reach")
  reach <- response_reach(g, active_ids)
  progress(0.2, "Sufficiency")
  suff_df <- sufficiency(g, p_D, press)
  progress(0.3, "Confidence (resampling edge strengths)")
  conf <- build_confidence_matrix(g, p_D, response_nodes_df, n_simulations = n_simulations, planned = press, structural = structural)
  # Revisao 2, items C4/C5: State triggers and the reach they leave.
  gates_pressure <- state_gates(g, p_D)
  gates_net <- state_gates(g, p_D + press)
  reach_effective <- effective_response_reach(g, active_ids, gates_net$id[!gates_net$open])
  # Revisao 3, E1.4: does each verdict hold for other self-regulation?
  sr_sensitivity <- tryCatch(self_regulation_sensitivity(g, p_D, press), error = function(e) NULL)
  # Revisao 2, item B7: relevance and priority of each Impact.
  progress(0.1, "Impact prioritization")
  prioritization <- impact_prioritization(g, p_D, suff_df, n_simulations = n_simulations, structural = structural)
  # Revisao 3, E4.2: how stable the priority order is.
  priority_rob <- tryCatch(priority_robustness(prioritization), error = function(e) NULL)
  progress(0.3, "Done")
  list(
    name = name, active = active_ids, strengths = strengths, press = press, reach = reach,
    pressure_active = pressure_active_ids, pressure_strengths = pressure_strengths, p_D = p_D,
    sufficiency_df = suff_df, sufficiency_confidence_matrix = conf, n_simulations = n_simulations,
    structural_uncertainty = isTRUE(structural), priority_robustness = priority_rob,
    prioritization = prioritization, gates_pressure = gates_pressure, gates_net = gates_net,
    reach_effective = reach_effective, sr_sensitivity = sr_sensitivity
  )
}

# Revisao 2, item 3.12: a node id may contain spaces or symbols that are not
# valid in an input id - inputs use this safe, stable key (the id in hex).
input_key <- function(id) {
  vapply(as.character(id), function(x) paste0("k", paste(sprintf("%02x", as.integer(charToRaw(enc2utf8(x)))), collapse = "")), character(1), USE.NAMES = FALSE)
}

build_confidence_matrix <- function(g, p_D, response_nodes_df, n_simulations = 300, seed = 42, planned = NULL, structural = FALSE) {
  if (nrow(response_nodes_df) == 0) {
    return(data.frame(Response = character(), stringsAsFactors = FALSE))
  }

  per_response <- lapply(seq_len(nrow(response_nodes_df)), function(i) {
    rid <- response_nodes_df$id[i]
    p_r <- build_press_vector(g, rid, setNames(1, rid))
    sufficiency_confidence(g, p_D, p_r, n_simulations = n_simulations, seed = seed, structural = structural)
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
    pl <- sufficiency_confidence(g, p_D, planned, n_simulations = n_simulations, seed = seed, structural = structural)
    row <- as.data.frame(t(pl$neutralized_pct), stringsAsFactors = FALSE)
    names(row) <- impact_labels
    out <- rbind(cbind(Response = "Planned scenario (as set)", row, stringsAsFactors = FALSE), out)
    per_response <- c(per_response, list(pl))
    attr(out, "not_worsened") <- setNames(pl$not_worsened_pct, impact_labels)
  }
  if (is.null(attr(out, "not_worsened"))) {
    # No scenario set: the largest share over the responses alone (the
    # pressure part of each draw is the same for all of them).
    attr(out, "not_worsened") <- setNames(apply(do.call(rbind, lapply(per_response, function(sc) sc$not_worsened_pct)), 2, max), impact_labels)
  }
  attr(out, "skipped") <- max(vapply(per_response, function(x) as.numeric(attr(x, "skipped") %||% 0), numeric(1)))
  attr(out, "n_simulations") <- n_simulations
  attr(out, "structural") <- isTRUE(structural)
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
        column(width = 4, textInput(ns("scenario_name"), "Scenario name", value = "Scenario 1")),
        # Revisao 2, item 3.4: fewer simulations = faster (e.g. in the
        # browser-only demo), more = steadier percentages.
        column(width = 4,
          selectInput(ns("n_simulations"), "Simulations (confidence)", choices = APP_SIMULATION_CHOICES, selected = APP_MAX_SIMULATIONS),
          # Revisao 3, E3.1.
          checkboxInput(ns("structural_uncertainty"), "Include structural uncertainty (links with weaker evidence may be absent)", value = FALSE),
          uiOutput(ns("apply_time_note"))
        ),
        column(width = 4, br(), actionButton(ns("apply_scenario"), "Apply scenario", icon = icon("play"), class = "btn-success", width = "100%"))
      )
    ),

    box(
      width = 12, title = "Results", status = "primary", solidHeader = TRUE,
      collapsible = TRUE,
      uiOutput(ns("results_source_ui")),
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

# Revisao 2 (30/09): the Interpretation tab. Its outputs live in
# mod_responses_server() (same namespace: the wizard calls this with the
# Scenarios module's id), so it shares the scenarios and the shown scenario.
mod_interpretation_ui <- function(id) {
  ns <- NS(id)
  tagList(
    p("A plain-language reading of whether the response is enough and which Impact to act on first, for any",
      "applied or saved scenario - and every scenario side by side."),
    box(
      width = 12, title = "Scenario", status = "primary", solidHeader = TRUE, collapsible = TRUE,
      uiOutput(ns("interp_source_ui")),
      uiOutput(ns("interp_empty"))
    ),
    box(
      width = 12, title = "Reading", status = "primary", solidHeader = TRUE, collapsible = TRUE,
      uiOutput(ns("interp_body"))
    ),
    # Revisao 3 (manuscript v7, step 5): one ranked list of what to measure
    # or look up first (R/data_needs.R).
    box(
      width = 12, title = "Data needs — what to measure or look up first", status = "primary", solidHeader = TRUE, collapsible = TRUE,
      uiOutput(ns("data_needs_ui"))
    ),
    box(
      width = 12, title = "All scenarios side by side", status = "primary", solidHeader = TRUE, collapsible = TRUE,
      uiOutput(ns("interp_compare_ui"))
    )
  )
}

mod_responses_server <- function(id, schema, nodes, edges, graph, restore_state = NULL,
                                 epoch = NULL, graph_version = NULL, restore_saved = NULL) {
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
          paste0("active_", input_key(node_id)), paste0("strength_", input_key(node_id)), paste0("units_", input_key(node_id)),
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
          paste0("pressure_active_", input_key(node_id)), paste0("pressure_strength_", input_key(node_id)), paste0("pressure_units_", input_key(node_id)),
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

    # Revisao 3: how long "Apply scenario" will take, measured on this
    # network and this computer (the browser-only demo is much slower than
    # a local R). One resample = new strengths, effect matrix, spectral
    # radius and total effect; Apply runs n_simulations of them for the
    # scenario as set, for each response alone and for the reliability of
    # the prioritization.
    resample_seconds <- reactive({
      g <- graph()
      req(g)
      ids <- V(g)$name
      p <- setNames(as.numeric(has_role(g, "driver") | has_role(g, "pressure")), ids)
      w <- E(g)$weight
      n <- 20
      t <- system.time(for (k in seq_len(n)) {
        gg <- g
        E(gg)$weight <- w * stats::runif(length(w), 0.9, 1.1)
        B <- effect_matrix(gg)
        if (spectral_radius(B) < 1) propagate(B, p)
      })[["elapsed"]]
      max(t / n, 1e-4)
    })
    apply_seconds <- reactive({
      n_sim <- as.integer(input$n_simulations %||% APP_MAX_SIMULATIONS)
      n_resp <- nrow(response_nodes())
      # x1.3 for the triggers, the prioritization and the display.
      n_sim * (n_resp + 2) * resample_seconds() * 1.3
    })
    fmt_seconds <- function(s) if (s < 60) sprintf("%.0f s", max(1, s)) else sprintf("%.1f min", s / 60)
    output$apply_time_note <- renderUI({
      s <- apply_seconds()
      n_sim <- as.integer(input$n_simulations %||% APP_MAX_SIMULATIONS)
      txt <- sprintf("Apply scenario resamples the network %s times (%d simulations x %d readings): about %s on this computer.",
                     format(n_sim * (nrow(response_nodes()) + 2), big.mark = ","), n_sim, nrow(response_nodes()) + 2, fmt_seconds(s))
      if (s > 10) {
        div(class = "alert alert-warning", style = "padding:6px 10px; font-size:13px;",
            txt, if (n_sim > 100) " 100 simulations is about three times faster; 300 gives steadier percentages.")
      } else {
        helpText(txt)
      }
    })

    observeEvent(input$apply_scenario, {
      req(graph())
      est <- tryCatch(isolate(apply_seconds()), error = function(e) 0)
      if (est > 5) {
        showNotification(sprintf("Computing the scenario - about %s with these settings. The progress bar shows how far it is.", fmt_seconds(est)),
                         type = "message", duration = min(30, ceiling(est)))
      }

      rn <- response_nodes()
      active_ids <- rn$id[vapply(rn$id, function(node_id) isTRUE(input[[paste0("active_", input_key(node_id))]]), logical(1))]

      if (length(active_ids) == 0) {
        showNotification("Select at least one response to apply.", type = "warning")
        return()
      }

      strengths <- setNames(numeric(length(active_ids)), active_ids)
      for (node_id in active_ids) {
        strengths[[node_id]] <- effective_strength(paste0("strength_", input_key(node_id)), paste0("units_", input_key(node_id)), node_sd(node_id))
      }

      # Revisao 1, Fase 2: the sufficiency reading. Pressure is optional -
      # an inactive pressure scenario is just an all-zero press vector,
      # which sufficiency() handles the same as any other (worsening = 0
      # everywhere, so "neutralized" trivially holds wherever the response
      # helps at all).
      pn <- pressure_nodes()
      pressure_active_ids <- pn$id[vapply(pn$id, function(node_id) isTRUE(input[[paste0("pressure_active_", input_key(node_id))]]), logical(1))]
      pressure_strengths <- setNames(numeric(length(pressure_active_ids)), pressure_active_ids)
      for (node_id in pressure_active_ids) {
        pressure_strengths[[node_id]] <- effective_strength(paste0("pressure_strength_", input_key(node_id)), paste0("pressure_units_", input_key(node_id)), node_sd(node_id))
      }
      # Segunda rodada da Revisao 1: withProgress em torno do calculo -
      # build_confidence_matrix() sozinho roda 300 simulacoes POR resposta
      # existente na rede (nao so as ativas), perceptivel numa rede maior;
      # sem isso o clique em "Apply scenario" nao dava nenhum feedback
      # visual ate a tela inteira atualizar de uma vez, parecendo travado.
      # Revisao 2, item 0.5: an error in an observer ends the whole Shiny
      # session (the app greys out and every tab stops responding). Catch
      # it here, keep the previous results on screen and tell the user.
      sc <- tryCatch({
        withProgress(message = "Computing scenario results", value = 0, {
          compute_scenario(
            graph(), rn, input$scenario_name, active_ids, strengths,
            pressure_active_ids, pressure_strengths,
            n_simulations = as.integer(input$n_simulations %||% 300),
            structural = isTRUE(input$structural_uncertainty),
            progress = function(amount, detail) incProgress(amount, detail = detail)
          )
        })
      }, error = function(e) {
        showNotification(paste("Could not apply the scenario:", conditionMessage(e)), type = "error", duration = NULL)
        NULL
      })
      if (is.null(sc)) return()

      current_scenario(sc)
    })

    # =================================================
    # SUFFICIENCY MODEL (Revisao 1, Fase 2)
    # =================================================

    output$sufficiency_result <- renderUI({
      req(shown_scenario())

      tagList(
        h5("Is the response enough? (sufficiency)"),
        p(
          class = "text-muted",
          "For each Impact: how much the pressure scenario worsens it, how much the response scenario mitigates it,",
          "and whether the mitigation is enough to neutralize the worsening."
        ),
        DTOutput(ns("sufficiency_table")),
        uiOutput(ns("sr_sensitivity_note")),
        h5("How confident is that, response by response?"),
        p(
          class = "text-muted",
          "First row: the scenario as set above. Then every response in the network, evaluated alone at 100%,",
          "against the same pressure scenario: % of simulations - resampling every edge's strength within its",
          "uncertainty range - in which it neutralizes each Impact."
        ),
        DTOutput(ns("confidence_matrix_table")),
        uiOutput(ns("confidence_skipped_note")),
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
        figure_export_button(ns, "prioritization"),
        # Revisao 3, E4.2.
        plotOutput(ns("rank_stability_plot"), height = "300px"),
        figure_export_button(ns, "rank_stability"),
        downloadButton(ns("download_prioritization_csv"), "Download CSV", class = "btn-sm"),
        tags$p(class = "text-muted", style = "font-size: 12px; margin-top: 6px;", PRIORITIZATION_METHOD_NOTE),
        uiOutput(ns("prioritization_note"))
      )
    })

    # Revisao 3, E1.1/E1.4.
    output$sr_sensitivity_note <- renderUI({
      sc <- shown_scenario()
      req(sc)
      sens <- sc$sr_sensitivity
      tagList(
        helpText(
          "Strengths are pushes in standard deviations of each factor (100% = 1 SD); worsening, mitigation and net",
          "are in SD of each Impact.",
          if (!is.null(sens) && nrow(sens) > 0) paste(
            "The last column repeats the verdict with every factor's self-regulation set to 0.25, 0.5, 0.75 and 1",
            "(the reading above equals 1): \"yes\" means the verdict does not depend on it.",
            attr(sens, "note") %||% "")
        )
      )
    })

    output$sufficiency_table <- renderDT({
      sc <- shown_scenario()
      req(sc)

      display <- format_sufficiency_table(sc$sufficiency_df, sc$active, sc$strengths, sc$sr_sensitivity)
      datatable(display, rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })

    output$prioritization_table <- renderDT({
      sc <- shown_scenario()
      req(sc, sc$prioritization)
      datatable(format_prioritization_table(sc$prioritization, sc$priority_robustness), rownames = FALSE, options = list(dom = "t", pageLength = 20))
    })

    output$prioritization_plot <- renderPlot({
      sc <- shown_scenario()
      req(sc, sc$prioritization)
      draw_prioritization_plot(sc$prioritization)
    })

    output$rank_stability_plot <- renderPlot({
      sc <- shown_scenario()
      req(sc, sc$priority_robustness)
      draw_rank_stability_plot(sc$priority_robustness)
    })

    # Revisao 3: every chart downloads in the format, size, resolution and
    # font the user picks (R/figure_export.R).
    n_impacts_shown <- function() {
      sc <- shown_scenario()
      if (is.null(sc) || is.null(sc$prioritization)) 4 else max(1, nrow(sc$prioritization))
    }
    register_figure_export(input, output, session, "prioritization", filename = "prioritization",
      draw = function() draw_prioritization_plot(shown_scenario()$prioritization),
      height = function(w, font) w * 0.475)
    register_figure_export(input, output, session, "rank_stability", filename = "rank_stability",
      draw = function() draw_rank_stability_plot(shown_scenario()$priority_robustness),
      height = function(w, font) w * max(0.3, 0.12 + 0.075 * n_impacts_shown()))
    register_figure_export(input, output, session, "interp_priority", filename = "prioritization",
      draw = function() draw_prioritization_plot(shown_scenario()$prioritization),
      height = function(w, font) w * 0.475)
    register_figure_export(input, output, session, "interp_rank", filename = "rank_stability",
      draw = function() draw_rank_stability_plot(shown_scenario()$priority_robustness),
      height = function(w, font) w * max(0.3, 0.12 + 0.075 * n_impacts_shown()))
    register_figure_export(input, output, session, "interp_coverage", filename = "coverage",
      draw = function() draw_sufficiency_plot(shown_interpretation()$impacts),
      height = function(w, font) {
        imp <- shown_interpretation()$impacts
        n <- max(1, sum(imp$worsening > 1e-9 | abs(imp$mitigation) > 1e-9))
        w * (140 + 60 * n) / 900
      })
    register_figure_export(input, output, session, "temporal_chart", filename = "temporal_chart",
      draw = function() {
        tr <- temporal_result()
        plot_temporal_storyboard(temporal_chart_df(), reinforcing_warning = isTRUE(tr$stability$unbounded), neutralized_at = tr$neutralized_at)
      },
      height = function(w, font) {
        n <- max(1, length(unique(temporal_chart_df()$node)))
        nc <- ceiling(sqrt(n)); nr <- ceiling(n / nc)
        w / nc * 0.8 * nr + 14
      })

    output$prioritization_note <- renderUI({
      sc <- shown_scenario()
      req(sc, sc$prioritization)
      tagList(
        if (isTRUE(attr(sc$prioritization, "all_zero"))) {
          div(class = "alert alert-warning", "The pressure scenario does not move any Impact, so importance D is 0 everywhere.")
        },
        priority_robustness_note(sc$priority_robustness, helpText)
      )
    })

    output$download_prioritization_csv <- downloadHandler(
      filename = function() paste0("impact_prioritization_", Sys.Date(), ".csv"),
      content = function(file) {
        sc <- shown_scenario()
        req(sc, sc$prioritization)
        utils::write.csv(format_prioritization_table(sc$prioritization, sc$priority_robustness), file, row.names = FALSE)
      }
    )

    output$confidence_skipped_note <- renderUI({
      sc <- shown_scenario()
      req(sc)
      m <- sc$sufficiency_confidence_matrix
      note <- skipped_draws_note(attr(m, "skipped"), attr(m, "n_simulations") %||% sc$n_simulations)
      nw <- not_worsened_note(attr(m, "not_worsened"))
      if (is.null(note) && is.null(nw)) return(NULL)
      tagList(if (!is.null(note)) div(class = "alert alert-warning", note),
              if (!is.null(nw)) div(class = "alert alert-info", nw))
    })

    output$confidence_matrix_table <- renderDT({
      sc <- shown_scenario()
      req(sc)

      datatable(format_confidence_matrix(sc$sufficiency_confidence_matrix), rownames = FALSE, options = list(dom = "t", pageLength = 20))
    })

    # Roadmap Fase 9 item 9.2: "reach" is pure graph traversal from what the
    # active response(s) directly act on (R/reach.R) - always defined,
    # independent of both readings above (sufficiency/temporal).
    output$reach_section <- renderUI({
      req(shown_scenario())

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
      sc <- temporal_scenario()
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
        s_in <- input[[paste0("sched_start_", input_key(id))]]
        d_in <- input[[paste0("sched_dur_", input_key(id))]]
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

    # The temporal box is available once a scenario is applied OR saved
    # scenarios exist (e.g. restored from a savepoint). A reactiveVal only
    # invalidates when its value changes, so saving another scenario does
    # not redraw the section (and untick "Show temporal simulation").
    temporal_available <- reactiveVal(FALSE)
    observe({
      v <- !is.null(current_scenario()) || length(saved_scenarios$list) > 0
      if (!identical(v, isolate(temporal_available()))) temporal_available(v)
    })

    output$temporal_and_save_section <- renderUI({
      req(temporal_available())
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
          uiOutput(ns("temporal_source_ui")),
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
                helpText("Stops at the first window in which every Impact the response reaches - and that is worsened with or without the response - is at or below zero, or within the tolerance of its baseline."),
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
              helpText("An Impact whose net value is at or below this share of its baseline counts as 'Neutralized (relative)' in the table, and 'Until neutralized' stops there too. 0 = only zero counts. Takes effect on the next Run simulation."),
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
          actionButton(ns("run_temporal"), "Run simulation", icon = icon("play"), class = "btn-primary"),
          helpText("Change the settings above, then run. The results below keep the last run until you run again."),
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
          figure_export_button(ns, "temporal_chart")
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
      if (!is.null(shown_name())) {
        return(helpText(sprintf("Showing the saved scenario \"%s\". Choose \"Current scenario\" above to save the one applied.", shown_name())))
      }
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
      sc <- temporal_scenario()
      req(sc)
      # Only the groups set to "For a number of windows".
      ids <- c(
        if (identical(input$temporal_mode_pressure, "window")) names(sc$p_D)[sc$p_D != 0],
        if (identical(input$temporal_mode_response, "window")) names(sc$press)[sc$press != 0]
      )
      req(length(ids) > 0)
      # A saved scenario brings its own periods.
      sched <- if (!is.null(temporal_source_name()) && is.data.frame(sc$temporal_schedule)) sc$temporal_schedule
               else isolate(temporal_schedule(seed_state()))
      labs <- nodes()$label[match(ids, nodes()$id)]
      tagList(
        tags$h6("Period of each push (for a number of windows)"),
        lapply(seq_along(ids), function(i) {
          k <- match(ids[i], sched$id)
          fluidRow(
            column(6, tags$p(style = "margin-top: 30px;", labs[i])),
            column(3, numericInput(ns(paste0("sched_start_", input_key(ids[i]))), "Start window", value = if (is.na(k)) 1 else sched$start[k], min = 1, step = 1)),
            column(3, numericInput(ns(paste0("sched_dur_", input_key(ids[i]))), "Windows", value = if (is.na(k)) 1 else sched$duration[k], min = 1, step = 1))
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

    last_run_settings <- reactiveVal(NULL)
    observeEvent(current_scenario(), last_run_settings(NULL))

    # "Scenario shown" - one value for Results, Temporal simulation and the
    # Interpretation tab: the scenario applied above ("current") or any saved
    # scenario, to revisit its results without re-applying it. Each place has
    # its own selector; all three stay in sync with shown_source().
    shown_source <- reactiveVal("__current__")
    source_choices <- reactive({
      saved <- names(saved_scenarios$list)
      c(if (!is.null(current_scenario())) c("Current scenario (applied)" = "__current__"), setNames(saved, saved))
    })
    # Keep it valid (a saved scenario was cleared, or only saved ones exist).
    observe({
      ch <- source_choices()
      if (length(ch) > 0 && !isolate(shown_source()) %in% ch) shown_source(unname(ch[[1]]))
    })
    shown_name <- reactive({
      src <- shown_source()
      if (identical(src, "__current__") || !src %in% names(saved_scenarios$list)) NULL else src
    })
    shown_scenario <- reactive({
      n <- shown_name()
      if (is.null(n)) current_scenario() else saved_scenarios$list[[n]]
    })
    temporal_source_name <- shown_name
    temporal_scenario <- shown_scenario
    source_selector_ids <- c(results_source = "Scenario shown", temporal_source = "Scenario to simulate",
                             interp_source = "Scenario to interpret")
    for (sid in names(source_selector_ids)) local({
      sid <- sid
      output[[paste0(sid, "_ui")]] <- renderUI({
        ch <- source_choices()
        req(length(ch) > 0)
        tagList(
          selectInput(ns(sid), source_selector_ids[[sid]], choices = ch, selected = isolate(shown_source()), width = "100%"),
          uiOutput(ns(paste0(sid, "_note")))
        )
      })
      output[[paste0(sid, "_note")]] <- renderUI({
        sc <- shown_scenario()
        req(sc)
        lab <- function(ids) { l <- nodes()$label[match(ids, nodes()$id)]; ifelse(is.na(l), ids, l) }
        txt <- function(ids, st) if (length(ids) == 0) "none" else paste(sprintf("%s at %d%%", lab(ids), round(st[ids])), collapse = ", ")
        helpText(sprintf("Pressure: %s. Response: %s.", txt(sc$pressure_active, sc$pressure_strengths), txt(sc$active, sc$strengths)))
      })
      observeEvent(input[[sid]], {
        if (!identical(input[[sid]], shown_source())) shown_source(input[[sid]])
      })
    })
    observeEvent(shown_source(), {
      for (sid in names(source_selector_ids)) {
        if (!is.null(input[[sid]]) && !identical(input[[sid]], shown_source())) updateSelectInput(session, sid, selected = shown_source())
      }
    })
    # Applying a new scenario shows it everywhere.
    observeEvent(current_scenario(), shown_source("__current__"), ignoreInit = TRUE)

    # The settings a source runs with the first time it is selected: a saved
    # scenario's own; for "current", what was on screen before leaving it.
    current_stash <- reactiveVal(NULL)
    last_run_source <- reactiveVal("__current__")
    settings_of_saved <- function(sc) {
      out <- lapply(names(temporal_defaults), function(k) if (present(sc[[k]])) sc[[k]] else temporal_defaults[[k]])
      out <- setNames(out, names(temporal_defaults))
      out$temporal_schedule <- sc$temporal_schedule
      out
    }
    apply_settings_to_controls <- function(ts) {
      updateSelectInput(session, "temporal_mode_pressure", selected = ts$temporal_mode_pressure)
      updateSelectInput(session, "temporal_mode_response", selected = ts$temporal_mode_response)
      updateSelectInput(session, "temporal_stop_rule", selected = ts$temporal_stop_rule)
      updateNumericInput(session, "temporal_max_windows", value = ts$temporal_max_windows)
      updateNumericInput(session, "temporal_windows", value = ts$temporal_windows)
      updateNumericInput(session, "temporal_continue_after", value = ts$temporal_continue_after %||% 0)
      updateNumericInput(session, "temporal_tol_rel", value = ts$temporal_tol_rel)
      updateCheckboxInput(session, "baseline_without_response", value = isTRUE(ts$baseline_without_response))
      updateCheckboxInput(session, "temporal_trends_outside", value = !isFALSE(ts$temporal_trends_outside))
      if (!is.null(input$temporal_gate_mode)) updateSelectInput(session, "temporal_gate_mode", selected = ts$temporal_gate_mode)
    }

    temporal_result <- reactive({
      sc <- temporal_scenario()
      req(sc, isTRUE(input$show_temporal))

      src <- shown_source()
      if (!identical(src, last_run_source())) {
        # First run after switching scenario: its own settings, not the
        # controls (their update reaches the server only after this run).
        if (identical(last_run_source(), "__current__")) current_stash(temporal_settings())
        ts <- if (identical(src, "__current__")) current_stash() %||% temporal_settings() else settings_of_saved(sc)
        apply_settings_to_controls(ts)
        last_run_source(src)
      } else {
        ts <- temporal_settings()
      }

      # Revisao 2, item 0.5: report the failure instead of leaving the
      # table/chart blank with Shiny's terse grey error text.
      tr <- tryCatch(
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
            tol_rel = max(0, ts$temporal_tol_rel %||% 5) / 100,
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
      # Audit: the settings of THIS run - the table labels, the "load"
      # comparison run and "Save this scenario" use them, not whatever is on
      # screen now (possibly edited but never run).
      tr$settings <- ts
      tr$p_D <- sc$p_D
      tr$press <- sc$press
      tr$scenario_name <- if (identical(src, "__current__")) NULL else src
      # "Save this scenario" saves the applied scenario with the settings of
      # its own last run - not of a saved scenario revisited here.
      if (identical(src, "__current__")) last_run_settings(ts)
      tr
    }) %>%
      # Revisao 2, item 3.3: runs on "Run simulation" (and when the
      # disclosure is opened, a new scenario is applied or another scenario
      # is chosen), not on every change of a setting.
      bindEvent(input$run_temporal, input$show_temporal, current_scenario(), shown_source())

    # Revisao 2, item C3: the same run with the other criterion, for
    # "Compare both".
    temporal_result_load <- reactive({
      req(isTRUE(input$show_temporal), identical(input$temporal_gate_mode, "compare"))
      tr <- temporal_result()
      ts <- tr$settings
      simulate_temporal_pair(
        graph(), tr$p_D, tr$press,
        windows = max(1, ts$temporal_windows %||% 5),
        mode_D = ts$temporal_mode_pressure, mode_R = ts$temporal_mode_response,
        stop_rule = ts$temporal_stop_rule, max_windows = max(1, ts$temporal_max_windows %||% 50),
        baseline_without_response = isTRUE(ts$baseline_without_response), gate_mode = "load",
        schedule = ts$temporal_schedule, trends_outside = !isFALSE(ts$temporal_trends_outside),
        continue_after = ts$temporal_continue_after %||% 0,
        tol_rel = max(0, ts$temporal_tol_rel %||% 5) / 100
      )
    }) %>%
      # Audit: follows the main run (same settings), not every input change.
      bindEvent(temporal_result(), input$temporal_gate_mode)

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
      tagList(
        if (!is.null(note)) div(class = if (is.na(tr$neutralized_at)) "alert alert-secondary" else "alert alert-success", role = "status", note),
        if (length(tr$schedule_notes) > 0) div(class = "alert alert-warning", lapply(tr$schedule_notes, tags$p))
      )
    })


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

      df <- format_temporal_table(graph(), tr, tol_rel = tr$tol_rel)
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
      format_temporal_table(graph(), tr, tol_rel = tr$tol_rel)
    })

    output$temporal_chart <- renderPlot({
      tr <- temporal_result()
      req(tr)
      plot_temporal_storyboard(temporal_chart_df(), reinforcing_warning = isTRUE(tr$stability$unbounded), neutralized_at = tr$neutralized_at)
    })



    # Roadmap Fase 9 item 9.2: "reach" is pure graph traversal from what the
    # active response(s) directly act on (R/reach.R).
    output$reach_summary <- renderUI({
      sc <- shown_scenario()
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
      sc <- shown_scenario()
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
      sc <- shown_scenario()
      req(sc, nrow(sc$gates_pressure) > 0)
      datatable(format_triggers_table(graph(), sc$gates_pressure, sc$gates_net), rownames = FALSE, options = list(dom = "t"))
    })

    output$reach_table <- renderDT({
      sc <- shown_scenario()
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
    # INTERPRETATION TAB (mod_interpretation_ui)
    # =================================================
    #
    # A plain-language reading of the shown scenario (R/interpretation.R) and
    # every scenario side by side. Same functions as the report.
    shown_interpretation <- reactive({
      sc <- shown_scenario()
      req(sc, graph())
      interpret_scenario(graph(), sc)
    })
    all_scenarios_for_comparison <- reactive({
      out <- saved_scenarios$list
      if (!is.null(current_scenario())) out <- c(list("Current scenario (applied)" = current_scenario()), out)
      out
    })
    interp_status_style <- c(
      neutralized = "background:#e7f4ea; border-left:4px solid #1b8a3a;",
      partial = "background:#fff6e0; border-left:4px solid #e0a100;",
      not_covered = "background:#fdecea; border-left:4px solid #c0392b;",
      worsened_by_response = "background:#fdecea; border-left:4px solid #c0392b;",
      improved = "background:#f4f6f8; border-left:4px solid #7a8793;",
      not_affected = "background:#f4f6f8; border-left:4px solid #7a8793;"
    )
    interp_status_label <- c(
      neutralized = "Neutralized", partial = "Partly covered", not_covered = "Not covered",
      worsened_by_response = "Worsened by the response", improved = "Improved", not_affected = "Not affected"
    )
    output$interp_empty <- renderUI({
      if (length(source_choices()) == 0) {
        div(class = "alert alert-secondary", "Apply a scenario (or load a savepoint with saved scenarios) in the Scenarios tab first.")
      }
    })
    output$interp_body <- renderUI({
      it <- shown_interpretation()
      imp <- it$impacts
      req(nrow(imp) > 0)
      n_plot <- sum(imp$worsening > 1e-9 | abs(imp$mitigation) > 1e-9)
      tagList(
        h4(it$headline),
        if (length(it$messages) > 0) tags$ul(lapply(it$messages, tags$li)),
        h5("Impact by impact, in priority order"),
        lapply(seq_len(nrow(imp)), function(k) {
          r <- imp[k, ]
          div(style = paste("padding:8px 12px; margin-bottom:8px; border-radius:4px;", interp_status_style[[r$status]]),
              tags$strong(paste0(if (!is.na(r$rank)) paste0(r$rank, ". ") else "", r$node)),
              tags$span(style = "margin-left:8px; font-size:12px; color:#555;",
                        paste0(interp_status_label[[r$status]],
                               if (!is.na(r$priority)) sprintf(" | priority %.2f", r$priority) else "")),
              tags$p(style = "margin:4px 0 0 0;", r$text))
        }),
        h5("How much of the worsening the response covers"),
        p(class = "text-muted",
          "Red: the pressure's worsening of each Impact (dark red, when present: worsening added by the response",
          "itself). Green: what the response offsets, from the worsening back to the net. Diamond: the net effect - green when",
          "at or below zero; the shaded side of zero is the neutralized zone, where the green bar ends when the response goes beyond neutral."),
        plotOutput(ns("interp_coverage_plot"), height = paste0(140 + 60 * max(1, n_plot), "px")),
        figure_export_button(ns, "interp_coverage"),
        h5("Relevance and priority"),
        p(class = "text-muted", "Bars: how much each Impact matters (value v x importance D x reliability). Diamonds: priority,",
          "the relevance times the share of the worsening left uncovered - the Impact to act on first has the largest."),
        plotOutput(ns("interp_priority_plot"), height = "320px"),
        figure_export_button(ns, "interp_priority"),
        h5("How stable is that order?"),
        p(class = "text-muted", "Each bar: in what share of 500 variations (values v changed by up to 20%, index as a product or a sum)",
          "the Impact ended 1st, 2nd, 3rd... The tick marks its rank above. One colour = a stable rank; two = a near tie."),
        plotOutput(ns("interp_rank_plot"), height = "300px"),
        figure_export_button(ns, "interp_rank"),
        tags$p(class = "text-muted", style = "font-size: 12px; margin-top: 6px;", PRIORITIZATION_METHOD_NOTE)
      )
    })
    output$interp_coverage_plot <- renderPlot(draw_sufficiency_plot(shown_interpretation()$impacts))
    output$interp_rank_plot <- renderPlot({
      sc <- shown_scenario()
      req(sc, sc$priority_robustness)
      draw_rank_stability_plot(sc$priority_robustness)
    })
    output$interp_priority_plot <- renderPlot({
      sc <- shown_scenario()
      req(sc, sc$prioritization)
      draw_prioritization_plot(sc$prioritization)
    })
    data_needs_df <- reactive({
      req(graph())
      sc <- shown_scenario()
      data_needs(graph(), sc, temporal = isTRUE(input$show_temporal))
    })
    output$data_needs_ui <- renderUI({
      d <- data_needs_df()
      tagList(
        p(DATA_NEEDS_INTRO),
        if (!is.null(attr(d, "note"))) div(class = "alert alert-secondary", attr(d, "note")),
        if (nrow(d) == 0) helpText("Nothing to add: every State that matters has a threshold and every link on a path has a value or a reference.")
        else tagList(DTOutput(ns("data_needs_table")),
                     downloadButton(ns("download_data_needs_csv"), "Download CSV", class = "btn-sm"))
      )
    })
    output$data_needs_table <- renderDT({
      datatable(format_data_needs(data_needs_df()), rownames = FALSE,
                options = list(pageLength = 15, scrollX = TRUE, dom = "tip"))
    })
    output$download_data_needs_csv <- downloadHandler(
      filename = function() paste0("data_needs_", Sys.Date(), ".csv"),
      content = function(file) utils::write.csv(data_needs_df(), file, row.names = FALSE)
    )
    interp_comparison_df <- reactive({
      req(graph())
      compare_scenario_interpretations(graph(), all_scenarios_for_comparison())
    })
    output$interp_compare_ui <- renderUI({
      df <- interp_comparison_df()
      if (nrow(df) == 0) return(helpText("Apply or save scenarios to compare them here."))
      tagList(
        p(class = "text-muted",
          "Every scenario against its own pressure scenario: for each Impact, whether the response neutralizes it,",
          "what share of the worsening it covers, or whether it worsens it; and the Impact to act on first."),
        DTOutput(ns("interp_compare_table")),
        downloadButton(ns("download_interp_compare_csv"), "Download CSV", class = "btn-sm")
      )
    })
    output$interp_compare_table <- renderDT({
      datatable(interp_comparison_df(), rownames = FALSE, options = list(dom = "t", pageLength = 50, scrollX = TRUE))
    })
    output$download_interp_compare_csv <- downloadHandler(
      filename = function() paste0("scenario_comparison_", Sys.Date(), ".csv"),
      content = function(file) utils::write.csv(interp_comparison_df(), file, row.names = FALSE)
    )

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
      # Audit: prefer the settings of the last run of this scenario, so the
      # report reproduces what was seen; else what is on screen.
      sc <- utils::modifyList(sc, isolate(last_run_settings()) %||% isolate(temporal_settings(seed_state())))

      # Revisao 2, item 3.9: ask before overwriting a saved scenario.
      if (sc$name %in% names(saved_scenarios$list)) {
        pending_scenario(sc)
        showModal(modalDialog(
          title = "Overwrite scenario",
          sprintf("A scenario named '%s' is already saved. Replace it?", sc$name),
          footer = tagList(modalButton("Cancel"), actionButton(ns("confirm_overwrite_scenario"), "Replace", class = "btn-danger"))
        ))
        return()
      }
      store_scenario(sc)
    })

    pending_scenario <- reactiveVal(NULL)
    store_scenario <- function(sc) {
      saved <- saved_scenarios$list
      saved[[sc$name]] <- sc
      saved_scenarios$list <- saved

      scenario_counter(scenario_counter() + 1)
      updateTextInput(session, "scenario_name", value = paste("Scenario", scenario_counter()))
      showNotification(paste0("Scenario '", sc$name, "' saved."), type = "message")
    }
    observeEvent(input$confirm_overwrite_scenario, {
      sc <- pending_scenario()
      req(sc)
      store_scenario(sc)
      pending_scenario(NULL)
      removeModal()
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

    # Revisao 2, item 3.13: a savepoint's saved scenarios are rebuilt once
    # the loaded network's graph is built (after the clearing below).
    pending_saved <- reactiveVal(NULL)
    if (!is.null(epoch)) {
      observeEvent(epoch(), {
        reset_scenario_state()
        pending_saved(if (is.null(restore_saved)) NULL else restore_saved())
      }, ignoreInit = TRUE)
    }
    restore_saved_scenarios <- function() {
      defs <- pending_saved()
      if (is.null(defs) || length(defs) == 0 || is.null(graph())) return()
      pending_saved(NULL)
      rn <- response_nodes()
      rebuilt <- list()
      withProgress(message = "Rebuilding saved scenarios", value = 0, {
        for (d in defs) {
          incProgress(1 / length(defs), detail = d$name)
          sc <- tryCatch(
            compute_scenario(graph(), rn, d$name, d$active, d$strengths, d$pressure_active, d$pressure_strengths,
                             n_simulations = min(as.integer(d$n_simulations %||% 300), APP_MAX_SIMULATIONS),
                             structural = isTRUE(d$structural_uncertainty)),
            error = function(e) NULL
          )
          if (is.null(sc)) next
          temporal <- d[setdiff(names(d), c("name", "active", "strengths", "pressure_active", "pressure_strengths", "n_simulations", "structural_uncertainty"))]
          rebuilt[[d$name]] <- utils::modifyList(sc, temporal)
        }
      })
      saved_scenarios$list <- rebuilt
      scenario_counter(length(rebuilt) + 1)
      updateTextInput(session, "scenario_name", value = paste("Scenario", length(rebuilt) + 1))
      if (length(rebuilt) > 0) {
        showNotification(sprintf("%d saved scenario(s) restored from the savepoint.", length(rebuilt)), type = "message")
      }
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
      observeEvent(graph_version(), restore_saved_scenarios(), ignoreInit = TRUE, priority = -10)
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
        h5("Sufficiency per scenario"),
        p(class = "text-muted", "For each Impact: neutralized, the share of the worsening covered, or worsened by the response (see the Interpretation tab)."),
        DTOutput(ns("comparison_sufficiency_table")),
        h5("Reach per scenario"),
        p(
          class = "text-muted",
          "How far each selected scenario's active response(s) can influence via some causal path."
        ),
        DTOutput(ns("comparison_reach_table"))
      )
    })

    output$comparison_sufficiency_table <- renderDT({
      saved <- saved_scenarios$list[selected_scenario_names()]
      datatable(compare_scenario_interpretations(graph(), saved), rownames = FALSE, options = list(dom = "t", scrollX = TRUE))
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

      response_active <- rn$id[vapply(rn$id, function(id) isTRUE(input[[paste0("active_", input_key(id))]]), logical(1))]
      response_strengths <- setNames(
        # Audit: the strength actually used (the "in units" field when filled).
        vapply(response_active, function(id) effective_strength(paste0("strength_", input_key(id)), paste0("units_", input_key(id)), node_sd(id)), numeric(1)),
        response_active
      )

      pressure_active <- pn$id[vapply(pn$id, function(id) isTRUE(input[[paste0("pressure_active_", input_key(id))]]), logical(1))]
      pressure_strengths <- setNames(
        vapply(pressure_active, function(id) effective_strength(paste0("pressure_strength_", input_key(id)), paste0("pressure_units_", input_key(id)), node_sd(id)), numeric(1)),
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
        temporal_settings(isolate(restored())),
        # Audit: saved with the scenario, like the temporal settings.
        list(n_simulations = as.integer(input$n_simulations %||% isolate(restored())$n_simulations %||% 300),
             structural_uncertainty = isTRUE(input$structural_uncertainty %||% isolate(restored())$structural_uncertainty))
      )
    }

    # Restores "Simulations (confidence)" from a loaded savepoint.
    observe({
      rs <- restored()
      n <- rs$n_simulations
      if (!is.null(n) && !is.na(suppressWarnings(as.integer(n)))) {
        # An older savepoint may say 1000; the app now caps at 300.
        updateSelectInput(session, "n_simulations", selected = as.character(min(as.integer(n), APP_MAX_SIMULATIONS)))
      }
      if (!is.null(rs$structural_uncertainty)) updateCheckboxInput(session, "structural_uncertainty", value = isTRUE(rs$structural_uncertainty))
    })

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
