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
    include_reproducibility = FALSE
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
  }

  if (length(selected_scenario_names) > 0 && length(saved_scenarios) > 0) {
    scenario_results <- lapply(selected_scenario_names, function(scenario_name) saved_scenarios[[scenario_name]]$result)
    names(scenario_results) <- selected_scenario_names

    baseline_result <- list(equilibrium = setNames(rep(0, vcount(graph)), V(graph)$name))
    comparison_df <- compare_scenario_effects(graph, c(list(Baseline = baseline_result), scenario_results))
    comparison_df$id <- NULL

    # Baseline's press is all-zero, so its equilibrium is exactly 0 no
    # matter how edge weights are resampled - agreement is trivially 100%
    # everywhere, computed directly rather than re-running simulations.
    baseline_sign_conf <- data.frame(
      id = V(graph)$name,
      node = if (!is.null(V(graph)$label)) V(graph)$label else V(graph)$name,
      category = if (!is.null(V(graph)$dpsir_category)) V(graph)$dpsir_category else "",
      agreement_pct = 100,
      stringsAsFactors = FALSE
    )
    scenario_sign_conf <- lapply(selected_scenario_names, function(scenario_name) saved_scenarios[[scenario_name]]$sign_confidence)
    names(scenario_sign_conf) <- selected_scenario_names
    sign_conf_df <- compare_scenario_sign_confidence(graph, c(list(Baseline = baseline_sign_conf), scenario_sign_conf))
    sign_conf_df$id <- NULL

    summary_df <- do.call(rbind, lapply(selected_scenario_names, function(scenario_name) {
      sc <- saved_scenarios[[scenario_name]]
      effect_df <- summarize_scenario_effect(graph, sc$result)
      counts <- table(factor(effect_df$direction, levels = c("Improves", "Worsens", "Stable")))
      data.frame(
        Scenario = scenario_name,
        Improves = as.integer(counts[["Improves"]]),
        Worsens = as.integer(counts[["Worsens"]]),
        Stable = as.integer(counts[["Stable"]]),
        stringsAsFactors = FALSE
      )
    }))

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

    scenario_items <- lapply(selected_scenario_names, function(scenario_name) {
      sc <- saved_scenarios[[scenario_name]]
      responses_text <- paste(
        sprintf("%s at %d%%", sc$active, round(sc$strengths[sc$active])),
        collapse = ", "
      )
      tags$li(tags$strong(scenario_name), ": ", responses_text)
    })

    sections <- c(sections, list(
      tags$h2("Scenarios compared"),
      tags$p("Baseline: no response applied."),
      tags$ul(scenario_items),
      tags$h3("Equilibrium effect per factor"),
      report_html_table(comparison_df),
      caption_tag(
        "Table", next_table_n(),
        "Equilibrium effect of each scenario on every node, computed via loop analysis (press perturbation, -A^-1 x press) relative to the baseline (no response applied)."
      ),
      tags$h3("Sign confidence per factor"),
      report_html_table(sign_conf_df),
      caption_tag(
        "Table", next_table_n(),
        "Percentage of 100 resampled simulations (varying each edge's weight within a range set by its confidence) that agreed with the equilibrium effect's direction shown above - low values flag a prediction that a more confident estimate of the network could easily flip."
      ),
      tags$h3("Reach per scenario"),
      report_html_table(reach_df),
      caption_tag(
        "Table", next_table_n(),
        "How many factors - and how many Impacts out of the total in the network - each scenario's active response(s) can influence via some causal path. Pure graph traversal, defined even when the equilibrium effect above is not."
      ),
      tags$h3("Summary per scenario"),
      report_html_table(summary_df),
      caption_tag("Table", next_table_n(), "Count of nodes whose equilibrium effect improves, worsens, or stays stable under each scenario.")
    ))

    sensitivity_sections <- lapply(selected_scenario_names, function(scenario_name) {
      sc <- saved_scenarios[[scenario_name]]
      top <- utils::head(sc$sensitivity[order(-sc$sensitivity$influence), c("link", "weight", "confidence", "influence")], 5)
      names(top) <- c("Link", "Weight", "Confidence", "Influence")

      tagList(
        tags$h4(scenario_name),
        report_html_table(top),
        caption_tag(
          "Table", next_table_n(),
          sprintf(
            "For \"%s\", the edges whose weight - if bumped up 10%% - would move its equilibrium effect the most, ranked highest first. Worth double-checking these estimates first if you're unsure about them.",
            scenario_name
          )
        )
      )
    })

    sections <- c(sections, list(
      tags$h3("Which edges matter most (top 5 per scenario)"),
      tagList(sensitivity_sections)
    ))
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
        "Sign confidence and robustness-to-uncertainty figures above resample every edge's weight ",
        tags$code("n_simulations = 100"), " times within a range set by its confidence and ",
        tags$code("spread = 0.5"), ", using a fixed random seed (", tags$code("seed = 42"), ") so that",
        " regenerating this report from the same savepoint reproduces the exact same numbers.",
        " Edge sensitivity ranks each edge by a one-at-a-time ", tags$code("+10%"),
        " weight bump (", tags$code("relative_change = 0.1"), "), which involves no random sampling",
        " and is already fully deterministic."
      )
    ))
  }

  tagList(sections)
}
