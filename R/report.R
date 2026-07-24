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
    include_graph_image = FALSE,
    graph_image = NULL,
    include_general = TRUE,
    include_centralities = FALSE,
    include_descriptors = FALSE,
    saved_scenarios = list(),
    selected_scenario_names = character()
) {
  sections <- list(
    tags$h1("iDPSIR - Report"),
    tags$style(HTML(REPORT_CSS)),
    tags$p(class = "meta", paste("Generated on", format(Sys.time(), "%Y-%m-%d %H:%M")))
  )

  if (isTRUE(include_graph_image) && !is.null(graph_image)) {
    sections <- c(sections, list(
      tags$h2("Network graph"),
      tags$img(class = "report-graph-image", src = graph_image)
    ))
  }

  if (isTRUE(include_general)) {
    sections <- c(sections, list(
      tags$h2("General metrics"),
      report_html_table(compute_general_metrics(graph))
    ))
  }

  if (isTRUE(include_centralities)) {
    sections <- c(sections, list(
      tags$h2("Centralities"),
      report_html_table(compute_all_metrics(graph))
    ))
  }

  if (isTRUE(include_descriptors)) {
    d <- compute_dpsir_descriptors(graph, schema)

    sections <- c(sections, list(
      tags$h2("DPSIR descriptors"),
      tags$h3("Nodes by category"),
      report_html_table(d$count_by_category),
      tags$h3("Transitions (edges by source -> target category)"),
      report_html_table(d$transitions),
      tags$h3("Category x category matrix"),
      report_html_table(matrix_to_report_df(d$transition_matrix)),
      tags$p(
        tags$strong("Impacts without Response: "),
        if (length(d$impacts_without_response) == 0) "none" else paste(d$impacts_without_response, collapse = ", ")
      ),
      tags$p(
        tags$strong("Pressures not covered by Response: "),
        if (length(d$pressures_without_response) == 0) "none" else paste(d$pressures_without_response, collapse = ", ")
      ),
      tags$h3("Average uncertainty/controllability by category (1=low, 2=medium, 3=high)"),
      report_html_table(d$averages_by_category)
    ))
  }

  if (length(selected_scenario_names) > 0 && length(saved_scenarios) > 0) {
    scenario_graphs <- lapply(selected_scenario_names, function(scenario_name) saved_scenarios[[scenario_name]]$graph)
    names(scenario_graphs) <- selected_scenario_names

    comparison_df <- compare_multiple_states(graph, scenario_graphs)
    names(comparison_df)[1] <- "Metric"

    summary_df <- do.call(rbind, lapply(selected_scenario_names, function(scenario_name) {
      sc <- saved_scenarios[[scenario_name]]
      impact <- summarize_response_impact(graph, sc$graph)
      counts <- table(factor(impact$direction, levels = c("Improves", "Worsens", "Stable")))
      data.frame(
        Scenario = scenario_name,
        Improves = as.integer(counts[["Improves"]]),
        Worsens = as.integer(counts[["Worsens"]]),
        Stable = as.integer(counts[["Stable"]]),
        stringsAsFactors = FALSE
      )
    }))

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
      tags$h3("Effect on the network"),
      report_html_table(comparison_df),
      tags$h3("Summary per scenario"),
      report_html_table(summary_df)
    ))
  }

  tagList(sections)
}
