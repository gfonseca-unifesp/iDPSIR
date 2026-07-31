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
#
# Fase 9 item 9.1.4 ("self-regulation is a modeling assumption"): a note
# next to the stability warning, hidden unless at least one node has
# self-regulation set, reminding the user that the equilibrium/stability
# result rests on that choice. A fourth optional disclosure, "Show
# sensitivity to self-regulation" (also hidden unless the network uses the
# feature at all), reuses the robustness-check pattern but perturbs each
# self-regulated factor's own strength instead of edge weights
# (self_regulation_sensitivity(), R/loop_analysis.R) - computed on demand
# (like "robustness to uncertainty", not eagerly like sign_confidence),
# since it's a deeper-dive diagnostic, not a headline number.
#
# Charts editability/download fast-follow (user request after reviewing the
# tab): the trajectory and edge-sensitivity charts were static renderPlot()
# images with no way to download them or configure them beyond what was
# already there, and never appeared in the report at all - unlike the
# network graph, which has its own capture-to-report pipeline. Both charts
# are already plain base-R plots (matplot()/barplot()) drawn server-side,
# so - unlike the graph, which is a live JS widget needing html2canvas -
# they can be redrawn straight to a file with a standard Shiny
# downloadHandler(), no browser-side capture needed. Drawing code moved to
# R/scenario_plots.R (draw_trajectory_plot()/draw_sensitivity_plot()) so
# the on-screen plot, the PNG/SVG download, and the report's embedded
# image are all the exact same function call, not three implementations
# that could drift apart. "Number of edges shown" is new (sensitivity
# previously had zero configuration at all, fixed at top-10); trajectory's
# "Number of steps" already existed.
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
    # (what's being done about it) - shown side by side with the
    # sufficiency reading below. Deliberately additive: the older
    # equilibrium-based reading (further down, unchanged) stays fully
    # functional alongside this while the new engine is validated.
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

    tags$hr(),
    h5("Effect on each factor (older, equilibrium-based reading)"),
    p(class = "text-muted", "Being replaced by the sufficiency reading above - kept here for now while it's validated."),
    uiOutput(ns("scenario_result")),

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

    # Roadmap Fase 9 item 9.1.4: whether the equilibrium/stability results
    # below rest on a self-regulation assumption at all - drives both the
    # conditional note and whether the sensitivity-to-self-regulation
    # disclosure is shown (hidden entirely when nobody's using the feature).
    has_self_regulation <- reactive({
      req(graph())
      sr <- V(graph())$self_regulation
      # Revisao 1, Fase 5: self_regulation stopped being categorical
      # ("none"/"low"/...) and became numeric (0 by default) - comparing a
      # numeric vector against the string "none" coerces to character and is
      # always TRUE, which silently pinned this reactive to TRUE for every
      # network (even one where nobody touched self-regulation at all) until
      # caught here. `> 0` is the real "is anyone using it" check now.
      !is.null(sr) && any(suppressWarnings(as.numeric(sr)) > 0, na.rm = TRUE)
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

      # Revisao 1, Fase 2: the new sufficiency reading, computed alongside
      # (not instead of) everything above. Pressure is optional - an
      # inactive pressure scenario is just an all-zero press vector, which
      # sufficiency() handles the same as any other (worsening = 0
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
        result = result,
        sign_confidence = sign_confidence,
        sensitivity = sensitivity,
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

    output$scenario_result <- renderUI({
      req(current_scenario())

      tagList(
        uiOutput(ns("stability_note")),
        uiOutput(ns("self_regulation_note")),
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
          plotOutput(ns("trajectory_plot"), height = "320px"),
          plot_download_row(ns, "trajectory")
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
          sliderInput(ns("sensitivity_top_n"), "Number of edges shown", min = 3, max = 20, value = 10, step = 1),
          plotOutput(ns("sensitivity_plot"), height = "320px"),
          plot_download_row(ns, "sensitivity"),
          DTOutput(ns("sensitivity_table"))
        ),
        uiOutput(ns("self_regulation_sensitivity_section")),
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

    # Roadmap Fase 9 item 9.1.4: self-regulation is a modeling assumption,
    # not an observed edge property - shown regardless of whether the
    # network came out stable or not, since either way the result rests on
    # the self-regulation levels the user chose. Hidden entirely when no
    # node has any (today's default, and the common case until the feature
    # is actually used).
    output$self_regulation_note <- renderUI({
      req(isTRUE(has_self_regulation()))

      tags$p(
        class = "text-muted",
        icon("circle-info"),
        " This result assumes the self-regulation you set for the factors (Nodes step).",
        "See how much it depends on that choice in \"Show sensitivity to self-regulation\" below."
      )
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

    # Shared by the on-screen plot and both download handlers, so all three
    # always show/export the exact same trajectory for the current live
    # inputs (steps slider), not just the drawing code.
    current_trajectory <- function(steps) {
      sc <- current_scenario()
      req(sc)
      traj <- simulate_trajectory_thresholded(
        interaction_matrix(), sc$press, Th = threshold_matrix(), steps = steps
      )
      labels <- V(graph())$label[match(colnames(traj), V(graph())$name)]
      list(traj = traj, labels = labels)
    }

    output$trajectory_plot <- renderPlot({
      req(isTRUE(input$show_trajectory))
      tr <- current_trajectory(input$trajectory_steps)
      draw_trajectory_plot(tr$traj, tr$labels)
    })

    output$download_trajectory_png <- downloadHandler(
      filename = function() paste0("trajectory_", Sys.Date(), ".png"),
      content = function(file) {
        tr <- current_trajectory(input$trajectory_steps)
        render_plot_png(function() draw_trajectory_plot(tr$traj, tr$labels), file)
      }
    )

    output$download_trajectory_svg <- downloadHandler(
      filename = function() paste0("trajectory_", Sys.Date(), ".svg"),
      content = function(file) {
        tr <- current_trajectory(input$trajectory_steps)
        render_plot_svg(function() draw_trajectory_plot(tr$traj, tr$labels), file)
      }
    )

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
      draw_sensitivity_plot(sc$sensitivity, top_n = input$sensitivity_top_n)
    })

    output$download_sensitivity_png <- downloadHandler(
      filename = function() paste0("edge_sensitivity_", Sys.Date(), ".png"),
      content = function(file) {
        sc <- current_scenario()
        req(sc)
        render_plot_png(function() draw_sensitivity_plot(sc$sensitivity, top_n = input$sensitivity_top_n), file)
      }
    )

    output$download_sensitivity_svg <- downloadHandler(
      filename = function() paste0("edge_sensitivity_", Sys.Date(), ".svg"),
      content = function(file) {
        sc <- current_scenario()
        req(sc)
        render_plot_svg(function() draw_sensitivity_plot(sc$sensitivity, top_n = input$sensitivity_top_n), file)
      }
    )

    output$sensitivity_table <- renderDT({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_sensitivity))

      df <- sc$sensitivity[, c("link", "weight", "confidence", "influence")]
      names(df) <- c("Link", "Weight", "Confidence", "Influence")

      datatable(df, rownames = FALSE, options = list(dom = "t", pageLength = 10)) %>%
        formatRound(columns = c("Influence"), digits = 3)
    })

    output$self_regulation_sensitivity_section <- renderUI({
      req(isTRUE(has_self_regulation()))

      tagList(
        tags$hr(),
        checkboxInput(ns("show_self_regulation_sensitivity"), "Show sensitivity to self-regulation (optional)", value = FALSE),
        conditionalPanel(
          condition = sprintf("input['%s']", ns("show_self_regulation_sensitivity")),
          p(
            class = "text-muted",
            "Nudges each self-regulated factor's strength up or down (not the edges - that's",
            "\"robustness to uncertainty\" above) and measures how often the predicted",
            "direction holds - a low percentage means the result depends heavily on the",
            "self-regulation you assumed for that factor, not just on the network's links."
          ),
          DTOutput(ns("self_regulation_sensitivity_table"))
        )
      )
    })

    output$self_regulation_sensitivity_table <- renderDT({
      sc <- current_scenario()
      req(sc, isTRUE(input$show_self_regulation_sensitivity))

      sens_df <- suppressWarnings(self_regulation_sensitivity(graph(), sc$press, n_simulations = 100))
      effect_df <- summarize_scenario_effect(graph(), sc$result)

      sens_df$direction <- effect_df$direction[match(sens_df$id, effect_df$id)]
      sens_df <- sens_df[order(sens_df$agreement_pct), ]
      sens_df <- sens_df[, c("node", "category", "direction", "agreement_pct")]
      names(sens_df) <- c("Factor", "Category", "Effect", "Agreement (%)")

      datatable(sens_df, rownames = FALSE, options = list(dom = "t", pageLength = 10)) %>%
        formatRound(columns = "Agreement (%)", digits = 0)
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

      # Captured at save time (not apply time, when the trajectory slider
      # may not exist yet on a first-ever "Apply scenario") so the report
      # can redraw the same trajectory later without needing a live slider -
      # same "what you configured is what gets saved" pattern already used
      # for the response strengths themselves.
      sc$trajectory_steps <- input$trajectory_steps %||% 20

      # Revisao 1, Fase 7: same reasoning, for the temporal disclosure's own
      # settings - the report (R/report.R) re-simulates from sc$p_D/sc$press
      # rather than storing the whole windows x nodes history, so it needs
      # to know how many windows and which impulse/permanent mode to use.
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
