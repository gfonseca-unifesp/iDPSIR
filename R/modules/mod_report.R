# =====================================================
# MOD_REPORT - REPORT TAB (last tab in Explore)
# =====================================================
#
# Lets the user assemble one self-contained HTML report from whatever was
# explored in the app: the network graph (captured as an image), general
# metrics, centralities, DPSIR descriptors, and any subset of saved
# scenarios. Nothing here recomputes anything the other tabs don't already
# compute - this module just lets the user pick what goes into the file.
#
# The graph image is captured client-side with html2canvas (already loaded
# by visNetwork's visExport() on the Graph widget, so no extra dependency)
# and sent back to the server as a data URL via a custom message handler -
# this avoids adding a headless-rendering package (webshot2/phantomjs) just
# to get one PNG into an HTML file, same reasoning that kept the report off
# rmarkdown/pandoc in Marco D.
#
# The capture request itself is NOT triggered from here: html2canvas (and
# vis-network's own <canvas>) both collapse to 0x0 once their tab is
# display:none, so a checkbox click on THIS tab can never see a visible
# Graph pane. mod_wizard_server triggers the capture whenever the Graph tab
# actually becomes visible and sends the result straight to
# captured_graph_image below - this module only registers the message
# handler that performs the capture and displays/uses whatever was last
# received.

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
          // A short delay lets the tab finish becoming visible (layout reflow)
          // before html2canvas measures it - capturing immediately on
          // shown.bs.tab can still see zero size.
          setTimeout(function() {
            var el = document.getElementById(msg.elementId);
            if (!el || typeof html2canvas === 'undefined') return;
            html2canvas(el, {
              onrendered: function(canvas) {
                if (canvas.width > 0 && canvas.height > 0) {
                  Shiny.setInputValue(msg.inputId, canvas.toDataURL('image/png'), {priority: 'event'});
                }
              }
            });
          }, 400);
        });
      }"
    )),

    p("Choose what to include, then download one self-contained HTML report."),

    fluidRow(
      column(
        width = 6,
        h5("Sections"),
        checkboxInput(ns("include_graph"), "Network graph (image, as currently shown in the Graph tab)", value = FALSE),
        uiOutput(ns("graph_capture_status")),
        tags$hr(),
        checkboxInput(ns("include_general"), "General metrics", value = TRUE),
        checkboxInput(ns("include_centralities"), "Centralities", value = FALSE),
        checkboxInput(ns("include_descriptors"), "DPSIR descriptors", value = FALSE)
      ),
      column(
        width = 6,
        h5("Scenarios"),
        p("Select saved scenarios to include (baseline - no response applied - is added automatically)."),
        DTOutput(ns("scenarios_table"))
      )
    ),

    tags$hr(),
    downloadButton(ns("download_report"), "Download report (HTML)", icon = icon("file-arrow-down"), class = "btn-success")
  )
}

mod_report_server <- function(id, schema, nodes, edges, graph, saved_scenarios) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    graph_image <- reactiveVal(NULL)

    observeEvent(input$captured_graph_image, {
      graph_image(input$captured_graph_image)
    })

    output$graph_capture_status <- renderUI({
      req(isTRUE(input$include_graph))
      img <- graph_image()

      if (is.null(img)) {
        tags$p(
          class = "text-muted",
          icon("triangle-exclamation"),
          " Not captured yet - open the Graph tab once this session, then come back here."
        )
      } else {
        tagList(
          tags$p(icon("check"), " Graph image captured."),
          tags$img(src = img, style = "max-width: 220px; border: 1px solid #ccc;")
        )
      }
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
        saved <- saved_scenarios()
        sel <- input$scenarios_table_rows_selected
        selected_names <- if (length(sel) > 0) names(saved)[sel] else character()

        page <- build_full_report_html(
          schema = schema(),
          graph = graph(),
          include_graph_image = isTRUE(input$include_graph),
          graph_image = graph_image(),
          include_general = isTRUE(input$include_general),
          include_centralities = isTRUE(input$include_centralities),
          include_descriptors = isTRUE(input$include_descriptors),
          saved_scenarios = saved,
          selected_scenario_names = selected_names
        )

        htmltools::save_html(page, file)
      }
    )
  })
}
