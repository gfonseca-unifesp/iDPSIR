# =====================================================
# HTML REPORT (no rmarkdown/pandoc - this machine does not have pandoc,
# so the report is assembled directly with htmltools, which needs no
# external binary. save_html() always wraps its input in its own
# <html>/<head>/<body> - passing a plain tagList (not a hand-built
# tags$html(...)) is what keeps the output valid, confirmed by testing.)
# =====================================================

REPORT_CSS <- "
  body { font-family: -apple-system, 'Segoe UI', Arial, sans-serif; margin: 40px; color: #222; }
  h1 { color: #1f77b4; }
  h2 { color: #444; margin-top: 32px; }
  h3 { color: #555; margin-top: 20px; }
  table.report-table { border-collapse: collapse; margin: 12px 0; }
  table.report-table th, table.report-table td { border: 1px solid #ccc; padding: 6px 14px; text-align: left; }
  table.report-table th { background: #f0f0f0; }
  .meta { color: #666; font-size: 0.9em; }
  .report-graph-image { max-width: 100%; border: 1px solid #ccc; margin: 12px 0; }
  .report-caption { color: #555; font-size: 0.9em; margin: 4px 0 20px 0; max-width: 700px; }
  .report-warning { background: #fff3cd; border: 1px solid #ffe69c; color: #664d03; padding: 8px 14px; max-width: 700px; }
"

format_report_cell <- function(cell) {
  if (!is.numeric(cell)) return(as.character(cell))
  if (!is.na(cell) && abs(cell - round(cell)) < 1e-9) return(format(round(cell)))
  format(round(cell, 2), nsmall = 2)
}

report_html_table <- function(df) {
  header <- tags$tr(lapply(names(df), tags$th))
  body_rows <- lapply(seq_len(nrow(df)), function(i) {
    tags$tr(lapply(df[i, ], function(cell) tags$td(format_report_cell(cell))))
  })
  tags$table(class = "report-table", tags$thead(header), tags$tbody(body_rows))
}

# transition_matrix comes back from compute_dpsir_descriptors() as a plain
# matrix with row names as the "from" category - report_html_table() only
# reads names(df), so the row label would otherwise be silently dropped.
matrix_to_report_df <- function(mat) {
  df <- as.data.frame.matrix(mat)
  cbind(From = rownames(df), df, stringsAsFactors = FALSE)
}

build_full_report_html <- function(
    schema,
    graph,
    graph_snapshots = list(),
    selected_snapshot_names = character(),
    include_general = TRUE,
    include_centralities = FALSE,
    centrality_params = list(directed = TRUE, normalized = TRUE, weighted = FALSE),
    include_descriptors = FALSE,
    include_references = FALSE,
    saved_scenarios = list(),
    selected_scenario_names = character(),
    include_reproducibility = FALSE,
    include_temporal_section = FALSE,
    include_interpretation = TRUE,
    metadata = NULL,
    savepoint_filename = NULL
) {
  # Sequential "Figure N"/"Table N" numbering across the whole report, plus
  # a caption paragraph under each - both requested so the report reads like
  # a document meant for publication, not just a dump of on-screen widgets.
  fig_counter <- 0
  tab_counter <- 0
  next_figure_n <- function() { fig_counter <<- fig_counter + 1; fig_counter }
  next_table_n <- function() { tab_counter <<- tab_counter + 1; tab_counter }
  caption_tag <- function(prefix, n, text) {
    tags$p(class = "report-caption", tags$strong(paste0(prefix, " ", n, ". ")), text)
  }

  # Recaps one scenario's pressure/response as text - used both by the
  # provenance header's "Scenario definitions" table below and by
  # "Response sufficiency"'s own per-scenario line further down, so the two
  # can never describe the same scenario two different ways.
  # Audit: factor labels, not ids, in the scenario definitions.
  lab <- function(ids) {
    l <- V(graph)$label[match(ids, V(graph)$name)]
    ifelse(is.na(l) | !nzchar(l), ids, l)
  }
  scenario_definition_text <- function(sc) {
    pressure_text <- if (length(sc$pressure_active) == 0) {
      "none (no pressure scenario)"
    } else {
      paste(sprintf("%s at %d%%", lab(sc$pressure_active), round(sc$pressure_strengths[sc$pressure_active])), collapse = ", ")
    }
    response_text <- if (length(sc$active) == 0) "none" else
      paste(sprintf("%s at %d%%", lab(sc$active), round(sc$strengths[sc$active])), collapse = ", ")
    list(pressure = pressure_text, response = response_text)
  }

  sections <- list(
    tags$h1("iDPSIR - Report"),
    tags$style(HTML(REPORT_CSS)),
    tags$p(class = "meta", paste("Generated on", format(Sys.time(), "%Y-%m-%d %H:%M")))
  )

  # C.1 Provenance header (guia externo sobre o relatorio como material
  # suplementar) - sempre presente (nao atras de checkbox algum: e' barato
  # de montar e o objetivo e' todo relatorio abrir com isso, nao importa
  # quais secoes de analise o usuario tenha escolhido), logo apos o
  # cabecalho, antes de qualquer analise. `metadata` (project_name/author/
  # created_at/updated_at/notes, ja existem em todo savepoint - R/io.R)
  # e `savepoint_filename` (nome do arquivo original, capturado so' no
  # momento de "Load savepoint" - NULL em New project/Import CSV/Combine
  # savepoints, onde nao ha um unico arquivo de origem) sao opcionais -
  # o cabecalho so' mostra o que existir. Nao inventa um numero de versao
  # do app (nao existe ainda - item 6.1 do roadmap de publicacao segue em
  # aberto): aponta pra "Reproducibility" (fim do relatorio) pra isso.
  meta_rows <- list()
  if (!is.null(metadata)) {
    if (!is.null(metadata$project_name) && nzchar(metadata$project_name)) {
      meta_rows <- c(meta_rows, list(tags$p(tags$strong("Network: "), metadata$project_name)))
    }
    if (!is.null(metadata$author) && nzchar(metadata$author)) {
      meta_rows <- c(meta_rows, list(tags$p(tags$strong("Author: "), metadata$author)))
    }
    if (!is.null(metadata$notes) && nzchar(metadata$notes)) {
      meta_rows <- c(meta_rows, list(tags$p(tags$strong("Notes: "), metadata$notes)))
    }
    if (!is.null(metadata$created_at) && nzchar(metadata$created_at)) {
      meta_rows <- c(meta_rows, list(tags$p(
        tags$strong("Savepoint created: "), metadata$created_at,
        " - last updated: ", metadata$updated_at %||% metadata$created_at
      )))
    }
  }
  if (!is.null(savepoint_filename) && nzchar(savepoint_filename)) {
    meta_rows <- c(meta_rows, list(tags$p(tags$strong("Savepoint file: "), savepoint_filename)))
  }

  scenario_def_rows <- if (length(selected_scenario_names) > 0 && length(saved_scenarios) > 0) {
    do.call(rbind, lapply(selected_scenario_names, function(scenario_name) {
      d <- scenario_definition_text(saved_scenarios[[scenario_name]])
      data.frame(Scenario = scenario_name, Pressure = d$pressure, Response = d$response, stringsAsFactors = FALSE)
    }))
  } else {
    NULL
  }

  sections <- c(sections, list(tags$h2("Report summary")), meta_rows)
  if (!is.null(scenario_def_rows)) {
    sections <- c(sections, list(
      report_html_table(scenario_def_rows),
      caption_tag(
        "Table", next_table_n(),
        "Definition of each selected scenario: which Drivers/Pressures are pushed (and how strongly), and which Responses are applied (and how strongly). Edge strengths are standardized path coefficients (beta); the effect of a scenario is their product along each causal path, summed over paths."
      )
    ))
  }
  sections <- c(sections, list(
    tags$p(
      class = "meta",
      "See \"Reproducibility\" at the end of this report for the R/package versions and the random seed/",
      "simulation count behind every resampling-based number above."
    ),
    # Revisao 2, Fase 4 (checklist, D18): how many strengths are not data.
    {
      src <- igraph::E(graph)$weight_source
      if (is.null(src)) NULL else tags$p(class = "meta", sprintf(
        "Edge strengths: %d of %d from a class or the default (qualitative), %d converted from an older file, %d given.",
        sum(src %in% c("class", "default")), length(src), sum(src %in% "converted"),
        sum(!src %in% c("class", "default", "converted"))
      ))
    }
  ))

  # C.2 Interpretation legend - always shown, once, right after the header.
  # This (not a second sign-convention explanation buried in a caption
  # somewhere) is what prevents the baseline-vs-zero misreading that
  # motivated replacing the old node-panel storyboard (see
  # R/scenario_plots.R's plot_temporal_storyboard()).
  sections <- c(sections, list(
    tags$h2("How to read these results"),
    tags$div(
      class = "report-warning",
      tags$p(
        tags$strong("Sign convention: "), "+ means the Impact worsens, − means it improves. An Impact is ",
        tags$strong("neutralized"), " when its net effect is ", tags$strong("≤ 0"),
        " (the shaded zone in the temporal figures below) - being merely below the baseline means the response helps, not that the Impact is neutralized."
      ),
      tags$p(
        tags$strong("Per-window Verdict colors: "),
        tags$span(style = "color: #1b8a3a; font-weight: bold;", "green"), " = improved/neutralized (≤ 0), ",
        tags$span(style = "color: #5cb85c; font-weight: bold;", "light green"), " = neutralized (relative): still above 0 but within the chosen tolerance of the baseline, ",
        tags$span(style = "color: #e0a100; font-weight: bold;", "amber"), " = partial (helped but still > 0), ",
        tags$span(style = "color: #c0392b; font-weight: bold;", "red"), " = failure (at or above baseline)."
      )
    )
  ))

  # C.3: results-first section order for a supplement - Response
  # sufficiency (primary reading) -> Reach + Temporal simulation ->
  # References -> Network characterization (appendix, demoted from where
  # it used to open the report) -> Reproducibility (stays last, it's about
  # the report itself, not the network).

  # Revisao 2 (30/09): plain-language interpretation (R/interpretation.R),
  # the same reading as the Interpretation tab - first, so the report opens
  # with what the numbers mean, then the detailed tables below.
  if (isTRUE(include_interpretation) && length(selected_scenario_names) > 0 && length(saved_scenarios) > 0) {
    chosen <- saved_scenarios[intersect(selected_scenario_names, names(saved_scenarios))]
    chosen <- Filter(function(sc) !is.null(sc$sufficiency_df), chosen)
    if (length(chosen) > 0) {
      interp_sections <- lapply(names(chosen), function(scenario_name) {
        sc <- chosen[[scenario_name]]
        it <- interpret_scenario(graph, sc)
        imp <- it$impacts
        n_plot <- sum(imp$worsening > 1e-9 | abs(imp$mitigation) > 1e-9)
        def <- scenario_definition_text(sc)
        tagList(
          tags$h4(scenario_name),
          tags$p(tags$strong("Pressure: "), def$pressure, tags$br(), tags$strong("Response: "), def$response),
          tags$p(tags$strong(it$headline)),
          if (length(it$messages) > 0) tags$ul(lapply(it$messages, tags$li)),
          tags$ol(lapply(seq_len(nrow(imp)), function(k) tags$li(tags$strong(imp$node[k]), ": ", imp$text[k]))),
          tags$img(src = plot_to_data_uri(function() draw_sufficiency_plot(imp), width = 900, height = 140 + 60 * max(1, n_plot)),
                   style = "max-width: 100%;"),
          caption_tag("Figure", next_figure_n(), sprintf(
            "For \"%s\": the pressure's worsening of each Impact (red; dark red = added by the response itself), what the response offsets (green) and the net effect (diamond; at or left of zero = neutralized). Impacts in priority order, top first.",
            scenario_name))
        )
      })
      cmp <- compare_scenario_interpretations(graph, chosen)
      sections <- c(sections, list(
        tags$h2("Interpretation"),
        tags$p(
          "A plain-language reading of each selected scenario: whether the response is enough for each Impact,",
          "in priority order, and what to watch. The tables in the next section hold the numbers behind it."
        ),
        tagList(interp_sections),
        if (nrow(cmp) > 0) tagList(
          tags$h3("Scenarios side by side"),
          report_html_table(cmp),
          caption_tag("Table", next_table_n(),
            "Each selected scenario against its own pressure scenario: for each Impact, whether the response neutralizes it, the share of the worsening it covers, or whether it worsens it; and the Impact to act on first.")
        )
      ))
    }
  }

  # Revisao 1, Fase 3: the sufficiency reading (R/sufficiency.R), one
  # subsection per selected scenario - the primary reading, matching the
  # on-screen ordering in mod_responses.R. format_sufficiency_table() is
  # the exact same function the Scenarios
  # tab uses for its own table, so a number here can never drift from what
  # the user saw live.
  if (length(selected_scenario_names) > 0 && length(saved_scenarios) > 0) {
    sufficiency_scenario_sections <- lapply(selected_scenario_names, function(scenario_name) {
      sc <- saved_scenarios[[scenario_name]]
      # A scenario saved before Fase 2 (same session only, since saved
      # scenarios aren't persisted to the savepoint) has no sufficiency_df -
      # skip it rather than error, same defensive style as the rest of
      # this file's optional sections.
      if (is.null(sc$sufficiency_df)) {
        return(NULL)
      }

      scenario_def <- scenario_definition_text(sc)

      suff_table <- format_sufficiency_table(sc$sufficiency_df, sc$active, sc$strengths)

      tagList(
        tags$h4(scenario_name),
        tags$p(
          tags$strong("Pressure: "), scenario_def$pressure, tags$br(),
          tags$strong("Response: "), scenario_def$response
        ),
        report_html_table(suff_table),
        caption_tag(
          "Table", next_table_n(),
          sprintf(
            "For \"%s\": how much the pressure scenario worsens each Impact, how much the response scenario mitigates it, and whether that mitigation is enough to neutralize the worsening.",
            scenario_name
          )
        ),
        report_html_table(format_confidence_matrix(sc$sufficiency_confidence_matrix)),
        {
          m <- sc$sufficiency_confidence_matrix
          note <- skipped_draws_note(attr(m, "skipped"), attr(m, "n_simulations") %||% sc$n_simulations)
          if (!is.null(note)) tags$p(class = "report-warning", note)
        },
        caption_tag(
          "Table", next_table_n(),
          sprintf(
            "For \"%s\"'s pressure scenario: every response in the network evaluated alone at full strength (\"neutralization confidence\") - percentage of simulations (resampling each edge's strength within its uncertainty range) in which that response alone neutralizes each Impact.",
            scenario_name
          )
        ),
        # Revisao 2, item C4: State triggers.
        if (!is.null(sc$gates_pressure) && nrow(sc$gates_pressure) > 0) {
          tagList(
            tags$h5("State triggers"),
            report_html_table(format_triggers_table(graph, sc$gates_pressure, sc$gates_net)),
            caption_tag("Table", next_table_n(), sprintf(
              "For \"%s\": each State with a threshold - its deviation (in standard deviations) under the pressure scenario alone and with the response, and whether its trigger is open (it passes its effect on) before and after the response.",
              scenario_name
            ))
          )
        },
        # Revisao 2, item B7: Impact prioritization.
        if (!is.null(sc$prioritization) && nrow(sc$prioritization) > 0) {
          tagList(
            tags$h5("Impact prioritization"),
            report_html_table(format_prioritization_table(sc$prioritization)),
            caption_tag(
              "Table", next_table_n(),
              sprintf("For \"%s\": relevance of each Impact (value v x importance D x reliability) and priority (relevance x the share of the worsening the response leaves uncovered). %s", scenario_name, PRIORITIZATION_METHOD_NOTE)
            ),
            tags$img(src = plot_to_data_uri(function() draw_prioritization_plot(sc$prioritization), width = 800, height = 380), style = "max-width: 100%;"),
            caption_tag("Figure", next_figure_n(), sprintf("For \"%s\": relevance (bars) and priority (markers) of each worsened Impact.", scenario_name))
          )
        }
      )
    })
    sufficiency_scenario_sections <- Filter(Negate(is.null), sufficiency_scenario_sections)

    if (length(sufficiency_scenario_sections) > 0) {
      sections <- c(sections, list(
        tags$h2("Response sufficiency"),
        tags$p(
          "For each selected scenario: whether the response is strong enough to neutralize the pressure's",
          "worsening on each Impact, how confident that verdict is, and which Impact to prioritize."
        ),
        tagList(sufficiency_scenario_sections)
      ))
    }
  }

  # Revisao 1, Fase 8: the old equilibrium-based reading (press_perturbation/
  # check_stability and everything derived from it - sign confidence,
  # global edge sensitivity, the linear trajectory chart) is cut from the
  # report here, superseded by "Response sufficiency" (Fase 1-3) and
  # "Temporal simulation" (Fase 4-7) above/below. Reach is the one part of
  # the old "Scenarios compared" section kept - response_reach() is pure
  # graph traversal, never depended on press_perturbation, and stays exactly
  # as useful as before. The underlying functions (press_perturbation(),
  # check_stability(), simulate_trajectory_thresholded(), etc., R/loop_analysis.R)
  # are left defined and still covered by tests/testthat/test-loop_analysis.R -
  # only the calls from here and mod_responses.R are removed, same
  # "superseded code stays on disk, just stops being called" pattern already
  # used throughout this project (e.g. R/responses.R's apply_response()).
  if (length(selected_scenario_names) > 0 && length(saved_scenarios) > 0) {
    total_impacts <- count_impacts_in_graph(graph)
    reach_row <- function(scenario_name, reach, eff = NULL) {
      reached_impacts_row <- reach$impacts
      reached_impacts <- if (length(reached_impacts_row) == 0) 0L else reached_impacts_row
      # Audit: the screen also says what the scenario reaches with its
      # closed triggers (item C5); the report now does too.
      in_scenario <- if (!is.null(eff) && length(eff$closed) > 0 && eff$total < reach$total) {
        sprintf("%d (trigger closed: %s)", eff$total, paste(eff$closed_labels, collapse = ", "))
      } else as.character(reach$total)
      data.frame(
        Scenario = scenario_name,
        `Factors reached` = reach$total,
        `Impacts reached` = sprintf("%d of %d", reached_impacts, total_impacts),
        `Reached in this scenario` = in_scenario,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
    baseline_reach_row <- reach_row("Baseline", list(total = 0L, by_category = data.frame(category = character(), count = integer())), NULL)
    reach_df <- do.call(rbind, c(
      list(baseline_reach_row),
      lapply(selected_scenario_names, function(scenario_name) reach_row(scenario_name, saved_scenarios[[scenario_name]]$reach, saved_scenarios[[scenario_name]]$reach_effective))
    ))

    sections <- c(sections, list(
      tags$h2("Reach"),
      tags$p("How far each scenario's active response(s) can influence via some causal path - pure graph traversal, independent of the sufficiency reading above."),
      report_html_table(reach_df),
      caption_tag(
        "Table", next_table_n(),
        "How many factors - and how many Impacts out of the total in the network - each scenario's active response(s) can influence via some causal path."
      )
    ))

    # Revisao 1, Fase 7 (guia externo sobre o relatorio como material
    # suplementar, revisado depois): secao de simulacao temporal - um
    # grafico de linha por Impacto (plot_temporal_storyboard(), R/scenario_plots.R)
    # + uma tabela janela-a-janela por cenario selecionado. Re-simula a
    # partir de sc$p_D/sc$press/sc$temporal_* (capturados em "Save this
    # scenario" - R/modules/mod_responses.R) em vez de guardar o historico
    # inteiro (janelas x nos) no objeto do cenario, mesmo padrao "recompute
    # a partir da config guardada" ja usado pelo grafico de trajetoria
    # acima. O grafico de linha nao precisa de layout/posicoes do grafo
    # (e' so' valor x janela) - `layout_settings`/`positions`, usados so'
    # pelo storyboard de paineis-de-rede antigo, saem da assinatura desta
    # funcao junto com ele.
    if (isTRUE(include_temporal_section)) {
      temporal_sections <- lapply(selected_scenario_names, function(scenario_name) {
        sc <- saved_scenarios[[scenario_name]]
        tr <- simulate_temporal_pair(
          graph, sc$p_D, sc$press,
          windows = max(1, sc$temporal_windows %||% 5),
          mode_D = sc$temporal_mode_pressure %||% "permanent",
          mode_R = sc$temporal_mode_response %||% "permanent",
          # Revisao 2, item A5.
          stop_rule = sc$temporal_stop_rule %||% "until_neutralized",
          max_windows = max(1, sc$temporal_max_windows %||% 50),
          baseline_without_response = isTRUE(sc$baseline_without_response),
          gate_mode = if (identical(sc$temporal_gate_mode, "load")) "load" else "state_level",
          # Revisao 2, Fase D.
          schedule = sc$temporal_schedule,
          trends_outside = !isFALSE(sc$temporal_trends_outside),
          continue_after = sc$temporal_continue_after %||% 0,
          # Audit: the report used the default tolerance, not the saved one.
          tol_rel = max(0, sc$temporal_tol_rel %||% 5) / 100
        )

        stability_note <- temporal_stability_note(tr$stability)
        note_tag <- if (!is.null(stability_note)) tags$p(class = "report-warning", stability_note) else NULL

        # Computado uma unica vez - alimenta tanto o grafico (colunas
        # node/baseline_impact/net_impact/verdict, como
        # format_temporal_table() as devolve) quanto a tabela em HTML
        # (renomeadas pra exibicao logo abaixo).
        raw_df <- format_temporal_table(graph, tr, tol_rel = tr$tol_rel)

        table_tag <- if (nrow(raw_df) == 0) {
          tags$p("No Impact factors in this network yet.")
        } else {
          table_df <- raw_df
          table_df$id <- NULL
          # "Net" (not "Scenario") - same vocabulary as the sufficiency
          # table's Worsening/Mitigation/Net columns, see the rename note
          # above format_temporal_table() in R/temporal.R.
          names(table_df) <- c("Impact", "Window", "Baseline", "Net", "Verdict")
          tagList(
            report_html_table(table_df),
            caption_tag(
              "Table", next_table_n(),
              sprintf(
                "For \"%s\": how each Impact factor changes window by window, comparing a baseline run (pressure only) against the net run (pressure and response together) over %d discrete windows.",
                scenario_name, tr$windows
              )
            )
          )
        }

        img_uri <- plot_to_data_uri(
          function() plot_temporal_storyboard(raw_df, reinforcing_warning = isTRUE(tr$stability$unbounded), neutralized_at = tr$neutralized_at),
          width = 900, height = 700
        )

        # Revisao 2, items A2/C0/C3: how the run ended, the trigger criterion
        # and the levels in the factors' own units.
        stop_tag <- tagList(
          if (!is.null(temporal_stop_note(tr))) tags$p(temporal_stop_note(tr)),
          lapply(tr$schedule_notes, function(n) tags$p(class = "report-warning", n))
        )
        # Revisao 2, Fase 4 (checklist): the settings behind the run.
        mode_text <- function(m) switch(m %||% "permanent",
          permanent = "added every window", impulse = "applied once and held", window = "for a set number of windows", m)
        sched <- sc$temporal_schedule
        if (is.data.frame(sched) && nrow(sched) > 0) {
          windowed <- c(if (identical(sc$temporal_mode_pressure, "window")) sc$pressure_active,
                        if (identical(sc$temporal_mode_response, "window")) sc$active)
          sched <- sched[sched$id %in% windowed, , drop = FALSE]
        }
        sched_text <- if (is.data.frame(sched) && nrow(sched) > 0) {
          labs <- V(graph)$label[match(sched$id, V(graph)$name)]
          paste0(" Periods: ", paste(sprintf("%s windows %d-%d", labs, as.integer(sched$start), as.integer(sched$start + sched$duration - 1)), collapse = "; "), ".")
        } else ""
        settings_tag <- tags$p(sprintf(
          "Settings: pressure %s; response %s; %s; neutralization tolerance %s%% of the baseline (labels and stop); growth trends %s.%s",
          mode_text(sc$temporal_mode_pressure), mode_text(sc$temporal_mode_response),
          if (identical(sc$temporal_stop_rule, "fixed")) sprintf("%d windows", as.integer(sc$temporal_windows %||% 5))
          else sprintf("until neutralized (up to %d windows)", as.integer(sc$temporal_max_windows %||% 50)),
          sc$temporal_tol_rel %||% 5,
          if (isFALSE(sc$temporal_trends_outside)) "only for factors in the scenario" else "applied to every factor",
          sched_text
        ))
        gate_tag <- if (nrow(tr$thresholds) > 0) {
          tags$p(sprintf("Trigger criterion: %s.%s", if (identical(tr$gate_mode, "load")) "load arriving at the State in each window" else "accumulated State level",
                         # Audit: "Compare both" is a screen-only view; the report runs the level criterion.
                         if (identical(sc$temporal_gate_mode, "compare")) " (\"Compare both\" was selected on screen; the report shows the level criterion - switch to \"load\" and save again to report the other.)" else ""))
        } else NULL
        level_df <- temporal_level_table(graph, tr)
        level_tag <- if (nrow(level_df) > 0) {
          tagList(
            report_html_table(level_df),
            caption_tag("Table", next_table_n(), sprintf(
              "For \"%s\": level of each factor with an initial value, in its own units, at the last window (initial level + typical variation x deviation), without and with the response.",
              scenario_name
            ))
          )
        } else NULL

        # Revisao 2, item D3: edge intensity by window.
        int_df <- edge_intensity_table(graph, tr)
        int_tag <- if (nrow(int_df) > 0) {
          tagList(
            report_html_table(int_df),
            caption_tag("Table", next_table_n(), sprintf(
              "For \"%s\": what each edge leaving a growing factor or a thresholded State passes on per window (strength x source level, deviation + growth trend), in the scenario run.",
              scenario_name
            ))
          )
        } else NULL

        tagList(
          tags$h4(scenario_name),
          note_tag,
          settings_tag,
          stop_tag,
          gate_tag,
          table_tag,
          level_tag,
          int_tag,
          tags$img(class = "report-graph-image", src = img_uri),
          caption_tag(
            "Figure", next_figure_n(),
            sprintf(
              "For \"%s\": one panel per Impact - dashed line is the baseline (pressure only), solid line is Net (pressure and response together), points colored by that window's Verdict, shaded band is the neutralized zone (Net ≤ 0).",
              scenario_name
            )
          )
        )
      })

      sections <- c(sections, list(
        tags$h2("Temporal simulation (discrete windows)"),
        tags$p(
          "Runs the pressure and response scenarios forward window by window instead of reading a single instant -",
          "useful when a response might, windows later, become a new pressure itself."
        ),
        tagList(temporal_sections)
      ))
    }
  }

  if (isTRUE(include_references)) {
    edges_df <- graph_to_edges(graph)

    if (!is.null(edges_df$reference) && any(nzchar(edges_df$reference))) {
      node_labels <- setNames(V(graph)$label, V(graph)$name)
      ref_rows <- edges_df[nzchar(edges_df$reference), ]

      ref_df <- data.frame(
        Link = paste0(unname(node_labels[ref_rows$from]), " -> ", unname(node_labels[ref_rows$to])),
        Reference = ref_rows$reference,
        stringsAsFactors = FALSE
      )

      sections <- c(sections, list(
        tags$h2("References"),
        report_html_table(ref_df),
        caption_tag(
          "Table", next_table_n(),
          "Sources cited for each edge that has one, letting a reader trace a prediction back to the evidence it's based on."
        )
      ))
    }
  }

  # C.3: "Network characterization (appendix)" - the network graph image,
  # general metrics, centralities and DPSIR descriptors used to open the
  # report (descriptive-first); demoted here for a supplement, where the
  # decision outputs above (sufficiency/reach/temporal) are what a reader
  # wants first. Nothing here is recomputed differently - same functions,
  # same flags, just moved and demoted from h2 to h3 under one shared
  # appendix heading.
  appendix_sections <- list()

  if (length(selected_snapshot_names) > 0 && length(graph_snapshots) > 0) {
    snapshot_sections <- lapply(selected_snapshot_names, function(snapshot_name) {
      snap <- graph_snapshots[[snapshot_name]]
      tagList(
        tags$h4(snapshot_name),
        tags$img(class = "report-graph-image", src = snap$image),
        caption_tag("Figure", next_figure_n(), snap$caption)
      )
    })

    appendix_sections <- c(appendix_sections, list(tags$h3("Network graph")), snapshot_sections)
  }

  if (isTRUE(include_general)) {
    appendix_sections <- c(appendix_sections, list(
      tags$h3("General metrics"),
      report_html_table(compute_general_metrics(graph)),
      caption_tag(
        "Table", next_table_n(),
        "Network-level metrics (density, diameter, transitivity, modularity, number of connected components) computed over the full built graph."
      )
    ))
  }

  if (isTRUE(include_centralities)) {
    params_text <- sprintf(
      "Computed with: %s, %s, %s.",
      if (isTRUE(centrality_params$directed)) "directed graph" else "undirected graph",
      if (isTRUE(centrality_params$normalized)) "normalized scores" else "raw (non-normalized) scores",
      if (isTRUE(centrality_params$weighted)) "weighted by edge weight (link strength)" else "unweighted (topology only)"
    )

    appendix_sections <- c(appendix_sections, list(
      tags$h3("Centralities"),
      report_html_table(compute_all_metrics(
        graph,
        directed = isTRUE(centrality_params$directed),
        normalized = isTRUE(centrality_params$normalized),
        weighted = isTRUE(centrality_params$weighted)
      )),
      caption_tag(
        "Table", next_table_n(),
        paste("Node centrality measures (degree, betweenness, closeness, PageRank, eigenvector centrality).", params_text)
      )
    ))
  }

  if (isTRUE(include_descriptors)) {
    d <- compute_dpsir_descriptors(graph, schema)

    appendix_sections <- c(appendix_sections, list(
      tags$h3("DPSIR descriptors"),
      tags$h4("Nodes by category"),
      report_html_table(d$count_by_category),
      caption_tag("Table", next_table_n(), "Number of nodes per DPSIR category in the built graph."),
      tags$h4("Transitions (edges by source -> target category)"),
      report_html_table(d$transitions),
      caption_tag("Table", next_table_n(), "Number of edges observed between each pair of DPSIR categories (source -> target)."),
      tags$h4("Category x category matrix"),
      report_html_table(matrix_to_report_df(d$transition_matrix)),
      caption_tag("Table", next_table_n(), "Same edge counts as the transitions table above, arranged as a source (row) x target (column) matrix."),
      tags$p(
        tags$strong("Impacts without Response: "),
        if (length(d$impacts_without_response) == 0) "none" else paste(d$impacts_without_response, collapse = ", ")
      ),
      tags$p(
        tags$strong("Pressures not covered by Response: "),
        if (length(d$pressures_without_response) == 0) "none" else paste(d$pressures_without_response, collapse = ", ")
      )
    ))

    dp <- compute_all_driver_impact_pathways(graph, schema)
    if (isTRUE(dp$available)) {
      truncated_note <- if (isTRUE(dp$truncated)) {
        sprintf(" Showing the first %d pathways found - this network may have more.", nrow(dp$table))
      } else {
        ""
      }

      pathways_df <- format_pathways_table(dp$table)

      appendix_sections <- c(appendix_sections, list(
        tags$h4("All Driver-to-Impact pathways"),
        report_html_table(pathways_df),
        caption_tag(
          "Table", next_table_n(),
          paste0(PATHWAYS_CAPTION, truncated_note)
        )
      ))
    }
  }

  if (length(appendix_sections) > 0) {
    sections <- c(sections, list(tags$h2("Network characterization (appendix)")), appendix_sections)
  }

  if (isTRUE(include_reproducibility)) {
    pkgs <- if (exists("required_packages", inherits = TRUE)) required_packages else character()
    version_df <- data.frame(
      Package = pkgs,
      Version = vapply(
        pkgs,
        function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) "not installed"),
        character(1)
      ),
      stringsAsFactors = FALSE
    )

    sections <- c(sections, list(
      tags$h2("Reproducibility"),
      tags$h3("Session info"),
      tags$p(R.version.string),
      report_html_table(version_df),
      caption_tag("Table", next_table_n(), "R and package versions used to generate this report."),
      tags$h3("Analysis parameters"),
      tags$p(
        "\"How confident is that, response by response?\" resamples every edge's strength (beta) ",
        tags$code(sprintf("n_simulations = %s", {
          sims <- unique(vapply(saved_scenarios[intersect(selected_scenario_names, names(saved_scenarios))],
                                function(sc) as.character(sc$n_simulations %||% 300), character(1)))
          if (length(sims) == 0) "300" else paste(sims, collapse = "/")
        })),
        " times (as set when each scenario was applied), uniformly within its uncertainty range, ",
        "using a fixed random seed (", tags$code("seed = 42"), ") so that",
        " regenerating this report from the same savepoint reproduces the exact same numbers."
      )
    ))
  }

  tagList(sections)
}
