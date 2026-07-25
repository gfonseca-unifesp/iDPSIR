# =====================================================
# MOD_REPORT - REPORT TAB (last tab in Explore)
# =====================================================
#
# Lets the user assemble one self-contained HTML report from whatever was
# explored in the app: any number of saved graph snapshots (images), general
# metrics, centralities, DPSIR descriptors, and any subset of saved
# scenarios. Nothing here recomputes anything the other tabs don't already
# compute - this module just lets the user pick what goes into the file.
#
# Graph snapshots are captured client-side with html2canvas (already loaded
# by visNetwork's visExport() on the Graph widget, so no extra dependency)
# and sent back to the server as a data URL via a custom message handler -
# this avoids adding a headless-rendering package (webshot2/phantomjs) just
# to get PNGs into an HTML file, same reasoning that kept the report off
# rmarkdown/pandoc in Marco D.
#
# The capture itself is triggered from the Graph tab's own "Save current
# view" button (see mod_graph.R), not from here: html2canvas (and
# vis-network's own <canvas>) both collapse to 0x0 once their tab is
# display:none, so a click on THIS tab could never see a visible Graph pane.
# Since the button lives on the Graph tab itself, the element is always
# visible at capture time - no tab-switch listener or artificial delay
# needed. This module only registers the shared message handler that
# performs the capture; mod_graph.R sends the request and stores the
# result under a user-chosen name, and graph_snapshots (passed in below)
# is that named list.

mod_report_ui <- function(id) {
  ns <- NS(id)

  box(
    width = 12,
    title = "Report",
    status = "primary",
    solidHeader = TRUE,

    tags$script(HTML(
      "if (!window.idpsirCaptureHandlerRegistered) {
        window.idpsirCaptureHandlerRegistered = true;
        Shiny.addCustomMessageHandler('idpsir_capture_element', function(msg) {
          var el = document.getElementById(msg.elementId);
          if (!el || typeof html2canvas === 'undefined') return;
          html2canvas(el, {
            onrendered: function(canvas) {
              if (canvas.width > 0 && canvas.height > 0) {
                Shiny.setInputValue(msg.inputId, canvas.toDataURL('image/png'), {priority: 'event'});
              }
            }
          });
        });
      }"
    )),

    p("Choose what to include, then download one self-contained HTML report."),

    fluidRow(
      column(
        width = 4,
        h5("Sections"),
        checkboxInput(ns("include_general"), "General metrics", value = TRUE),
        checkboxInput(ns("include_centralities"), "Centralities", value = FALSE),
        checkboxInput(ns("include_descriptors"), "DPSIR descriptors", value = FALSE)
      ),
      column(
        width = 4,
        h5("Graph images"),
        p("Select saved snapshots to include (save one from the Graph tab's \"Save current view\" button)."),
        DTOutput(ns("graph_snapshots_table"))
      ),
      column(
        width = 4,
        h5("Scenarios"),
        p("Select saved scenarios to include (baseline - no response applied - is added automatically)."),
        DTOutput(ns("scenarios_table"))
      )
    ),

    tags$hr(),
    downloadButton(ns("download_report"), "Download report (HTML)", icon = icon("file-arrow-down"), class = "btn-success")
  )
}

mod_report_server <- function(id, schema, nodes, edges, graph, saved_scenarios, graph_snapshots) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    output$graph_snapshots_table <- renderDT({
      snaps <- graph_snapshots()

      if (length(snaps) == 0) {
        return(datatable(
          data.frame(Name = character(), stringsAsFactors = FALSE),
          rownames = FALSE,
          options = list(dom = "t")
        ))
      }

      datatable(
        data.frame(Name = names(snaps), stringsAsFactors = FALSE),
        selection = "multiple", rownames = FALSE, options = list(dom = "t", pageLength = 10)
      )
    })

    output$scenarios_table <- renderDT({
      saved <- saved_scenarios()

      if (length(saved) == 0) {
        return(datatable(
          data.frame(Name = character(), Responses = character(), stringsAsFactors = FALSE),
          rownames = FALSE,
          options = list(dom = "t")
        ))
      }

      df <- do.call(rbind, lapply(names(saved), function(scenario_name) {
        sc <- saved[[scenario_name]]
        data.frame(
          Name = scenario_name,
          Responses = paste(sc$active, collapse = ", "),
          stringsAsFactors = FALSE
        )
      }))

      datatable(df, selection = "multiple", rownames = FALSE, options = list(dom = "t", pageLength = 10))
    })

    output$download_report <- downloadHandler(
      filename = function() paste0("idpsir_report_", Sys.Date(), ".html"),
      content = function(file) {
        snaps <- graph_snapshots()
        snap_sel <- input$graph_snapshots_table_rows_selected
        selected_snapshot_names <- if (length(snap_sel) > 0) names(snaps)[snap_sel] else character()

        saved <- saved_scenarios()
        sel <- input$scenarios_table_rows_selected
        selected_scenario_names <- if (length(sel) > 0) names(saved)[sel] else character()

        page <- build_full_report_html(
          schema = schema(),
          graph = graph(),
          graph_snapshots = snaps,
          selected_snapshot_names = selected_snapshot_names,
          include_general = isTRUE(input$include_general),
          include_centralities = isTRUE(input$include_centralities),
          include_descriptors = isTRUE(input$include_descriptors),
          saved_scenarios = saved,
          selected_scenario_names = selected_scenario_names
        )

        htmltools::save_html(page, file)
      }
    )
  })
}
