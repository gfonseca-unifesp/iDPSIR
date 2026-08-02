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
    include_temporal_section = FALSE
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

  sections <- list(
    tags$h1("iDPSIR - Report"),
    tags$style(HTML(REPORT_CSS)),
    tags$p(class = "meta", paste("Generated on", format(Sys.time(), "%Y-%m-%d %H:%M")))
  )

  if (length(selected_snapshot_names) > 0 && length(graph_snapshots) > 0) {
    snapshot_sections <- lapply(selected_snapshot_names, function(snapshot_name) {
      snap <- graph_snapshots[[snapshot_name]]
      tagList(
        tags$h3(snapshot_name),
        tags$img(class = "report-graph-image", src = snap$image),
        caption_tag("Figure", next_figure_n(), snap$caption)
      )
    })

    sections <- c(sections, list(tags$h2("Network graph")), snapshot_sections)
  }

  if (isTRUE(include_general)) {
    sections <- c(sections, list(
      tags$h2("General metrics"),
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

    sections <- c(sections, list(
      tags$h2("Centralities"),
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

    sections <- c(sections, list(
      tags$h2("DPSIR descriptors"),
      tags$h3("Nodes by category"),
      report_html_table(d$count_by_category),
      caption_tag("Table", next_table_n(), "Number of nodes per DPSIR category in the built graph."),
      tags$h3("Transitions (edges by source -> target category)"),
      report_html_table(d$transitions),
      caption_tag("Table", next_table_n(), "Number of edges observed between each pair of DPSIR categories (source -> target)."),
      tags$h3("Category x category matrix"),
      report_html_table(matrix_to_report_df(d$transition_matrix)),
      caption_tag("Table", next_table_n(), "Same edge counts as the transitions table above, arranged as a source (row) x target (column) matrix."),
      tags$p(
        tags$strong("Impacts without Response: "),
        if (length(d$impacts_without_response) == 0) "none" else paste(d$impacts_without_response, collapse = ", ")
      ),
      tags$p(
        tags$strong("Pressures not covered by Response: "),
        if (length(d$pressures_without_response) == 0) "none" else paste(d$pressures_without_response, collapse = ", ")
      ),
      tags$h3("Average uncertainty/controllability by category (1=low, 2=medium, 3=high)"),
      report_html_table(d$averages_by_category),
      caption_tag("Table", next_table_n(), "Mean uncertainty and controllability score per DPSIR category, coded as 1 (low), 2 (medium), 3 (high).")
    ))

    dp <- compute_all_driver_impact_pathways(graph, schema)
    if (isTRUE(dp$available)) {
      truncated_note <- if (isTRUE(dp$truncated)) {
        sprintf(" Showing the first %d pathways found - this network may have more.", nrow(dp$table))
      } else {
        ""
      }

      pathways_df <- dp$table[, c("nodes", "length", "score")]
      names(pathways_df) <- c("Pathway", "Length (nodes)", "Score")

      sections <- c(sections, list(
        tags$h3("All Driver-to-Impact pathways"),
        report_html_table(pathways_df),
        caption_tag(
          "Table", next_table_n(),
          paste0(
            "Every simple causal chain from a Driver to an Impact in this network, ranked by score ",
            "(mean edge weight x mean confidence x number of links).", truncated_note
          )
        )
      ))
    }
  }

  # Revisao 1, Fase 3: the sufficiency reading (R/sufficiency.R), one
  # subsection per selected scenario - the primary reading, matching the
  # on-screen ordering in mod_responses.R. format_sufficiency_table()/
  # format_reach_over_c_table() are the exact same functions the Scenarios
  # tab uses for its own tables, so a number here can never drift from what
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

      pressure_text <- if (length(sc$pressure_active) == 0) {
        "none (no pressure scenario)"
      } else {
        paste(sprintf("%s at %d%%", sc$pressure_active, round(sc$pressure_strengths[sc$pressure_active])), collapse = ", ")
      }
      response_text <- paste(sprintf("%s at %d%%", sc$active, round(sc$strengths[sc$active])), collapse = ", ")

      suff_table <- format_sufficiency_table(sc$sufficiency_df, sc$active, sc$strengths)
      reach_table <- format_reach_over_c_table(sc$sufficiency_reach_over_c)

      tagList(
        tags$h4(scenario_name),
        tags$p(
          tags$strong("Pressure: "), pressure_text, tags$br(),
          tags$strong("Response: "), response_text, tags$br(),
          tags$strong("How far the effect was traced (c): "), sc$effect_horizon %||% 0.5
        ),
        report_html_table(suff_table),
        caption_tag(
          "Table", next_table_n(),
          sprintf(
            "For \"%s\": how much the pressure scenario worsens each Impact, how much the response scenario mitigates it, and whether that mitigation is enough to neutralize the worsening.",
            scenario_name
          )
        ),
        report_html_table(sc$sufficiency_confidence_matrix),
        caption_tag(
          "Table", next_table_n(),
          sprintf(
            "For \"%s\"'s pressure scenario: every response in the network evaluated alone at full strength - percentage of simulations (resampling each edge's weight within a range set by its confidence) in which that response alone neutralizes each Impact.",
            scenario_name
          )
        ),
        report_html_table(reach_table),
        caption_tag(
          "Table", next_table_n(),
          sprintf(
            "For \"%s\": whether the neutralization verdict for each Impact holds up across different settings of how far the effect is traced (c) - a scenario marked Borderline has a verdict that flips somewhere in that range.",
            scenario_name
          )
        )
      )
    })
    sufficiency_scenario_sections <- Filter(Negate(is.null), sufficiency_scenario_sections)

    if (length(sufficiency_scenario_sections) > 0) {
      sections <- c(sections, list(
        tags$h2("Response sufficiency"),
        tags$p(
          "For each selected scenario: whether the response is strong enough to neutralize the pressure's",
          "worsening on each Impact, how confident that verdict is, and whether it holds up across different reach settings."
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
    baseline_reach_row <- reach_row("Baseline", list(total = 0L, by_category = data.frame(category = character(), count = integer())))
    reach_df <- do.call(rbind, c(
      list(baseline_reach_row),
      lapply(selected_scenario_names, function(scenario_name) reach_row(scenario_name, saved_scenarios[[scenario_name]]$reach))
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

    # Revisao 1, Fase 7: temporal simulation section - one storyboard + one
    # window-by-window table per selected scenario. Re-simulates from
    # sc$p_D/sc$press/sc$temporal_* (captured at "Save this scenario" time,
    # R/modules/mod_responses.R) rather than storing the whole windows x
    # nodes history in the scenario object, same "recompute from stored
    # config" pattern already used for the trajectory chart above. The
    # layout is computed once (not per scenario) - every panel of every
    # scenario's storyboard shares the same node positions as the Graph tab.
    if (isTRUE(include_temporal_section)) {
      temporal_layout <- compute_graph_layout(graph_to_nodes(graph), schema)

      temporal_sections <- lapply(selected_scenario_names, function(scenario_name) {
        sc <- saved_scenarios[[scenario_name]]
        tr <- simulate_temporal_pair(
          graph, sc$p_D, sc$press,
          windows = sc$temporal_windows %||% 5,
          mode_D = sc$temporal_mode_pressure %||% "permanent",
          mode_R = sc$temporal_mode_response %||% "impulse"
        )

        stability_note <- temporal_stability_note(tr$stability)
        note_tag <- if (!is.null(stability_note)) tags$p(class = "report-warning", stability_note) else NULL

        table_df <- format_temporal_table(graph, tr)
        table_tag <- if (nrow(table_df) == 0) {
          tags$p("No Impact factors in this network yet.")
        } else {
          table_df$id <- NULL
          names(table_df) <- c("Impact", "Window", "Baseline", "Scenario", "Verdict")
          tagList(
            report_html_table(table_df),
            caption_tag(
              "Table", next_table_n(),
              sprintf(
                "For \"%s\": how each Impact factor changes window by window, comparing a baseline run (pressure only) against the scenario run (pressure and response together) over %d discrete windows.",
                scenario_name, tr$windows
              )
            )
          )
        }

        img_uri <- plot_to_data_uri(
          function() draw_temporal_storyboard(graph, temporal_layout, tr$scenario),
          width = 900, height = 900
        )

        tagList(
          tags$h4(scenario_name),
          note_tag,
          table_tag,
          tags$img(class = "report-graph-image", src = img_uri),
          caption_tag(
            "Figure", next_figure_n(),
            sprintf(
              "For \"%s\": one panel per discrete time window (same layout throughout) - node color shows whether that factor increased (redder) or decreased (bluer) from zero in this scenario, size shows how large the change is.",
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
        "\"How confident is that, response by response?\" resamples every edge's weight ",
        tags$code("n_simulations = 300"), " times within a range set by its confidence and ",
        tags$code("spread = 0.5"), ", using a fixed random seed (", tags$code("seed = 42"), ") so that",
        " regenerating this report from the same savepoint reproduces the exact same numbers."
      )
    ))
  }

  tagList(sections)
}
