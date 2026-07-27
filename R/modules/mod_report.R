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
#
# Three fixes to the capture itself, found by inspecting the live DOM and
# testing each fix's actual effect (not guessed):
#
# 1. LOW RESOLUTION: html2canvas's modern `scale` option does nothing here -
#    confirmed by inspecting `html2canvas.toString()` directly: the version
#    visNetwork's visExport() bundles predates v1.0 and has no such option
#    (captures always come out at plain CSS pixel size, ~760x800). Since
#    vis-network's own <canvas> DOES redraw sharp at whatever CSS size its
#    container is given (confirmed: resizing the container 2.5x made the
#    canvas's actual pixel buffer grow 2.5x, not just stretch blurrily),
#    the fix is to temporarily enlarge the container itself, tell both
#    vis.Network instances (main graph + legend) to resize/redraw at that
#    larger size, capture, then restore the original size.
# 2. LEGEND CUT OFF: the legend is a *second*, separate vis.Network instance
#    rendered with position:absolute inside the same container - measured
#    live, its right edge sits flush against the container's own width with
#    ~0px to spare, and the container's true content also overflows ~15px
#    past its declared height. html2canvas only renders an element's own
#    declared box by default, silently cropping that overflow. Fixed by
#    measuring the *real* combined bounding box of every descendant (network
#    canvas + legend, at the enlarged size) and passing that as an explicit
#    width/height to html2canvas, with a small margin.
# 3. OFF-CENTER GRAPH: if the user had panned/zoomed before capturing, that
#    pan is what gets captured. Fixed by calling both vis.Network instances'
#    own `.fit()` (accessed via `HTMLWidgets.find()`, confirmed live to
#    expose `.network`/`.legend`) after resizing, with a short delay for the
#    resize/fit to settle before measuring and capturing.
#
# A fourth, cosmetic fix piggybacks on the same capture: the widget's own
# aspect ratio (a wide, short DPSIR layout inside a fixed-height container)
# leaves a lot of blank space below the graph once captured at full
# container size - `cropToContent()` scans the rendered canvas for its
# actual non-blank bounding box (network + legend, wherever they ended up)
# and crops to that plus a small margin, so the saved figure is framed
# tightly instead of floating in a mostly-empty page. (A further attempt to
# also collapse the horizontal gap between the diagram and the legend -
# they're two independent vis.Network instances, so that gap isn't just
# outer margin - was tried and reverted: the legend's own arrow/line
# glyphs are mostly blank space with content only at their ends, so a
# naive "widest blank column run" search cut through the middle of those
# lines instead of the intended gap. Not worth the added fragility for a
# secondary complaint when the three the user actually named - clipped
# legend, low resolution, off-center graph - are already fixed above.)

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

          var widget = (typeof HTMLWidgets !== 'undefined') ? HTMLWidgets.find('#' + msg.elementId) : null;
          var upscale = 2.5;
          var origWidth = el.style.width;
          var origHeight = el.style.height;
          var origRect = el.getBoundingClientRect();
          var bigWidth = Math.round(origRect.width * upscale);
          var bigHeight = Math.round(origRect.height * upscale);

          // vis-network's own UI chrome (zoom/pan arrows, the 'Select by
          // group' dropdowns, the 'Export as png' button) is pinned to the
          // container's corners - at the enlarged capture size those
          // corners are far from the actual diagram, which pins
          // cropToContent()'s bounding box to the full container and
          // defeats the crop. Hidden for the duration of the capture only.
          var toHide = ['nodeSelect' + msg.elementId, 'selectedBy' + msg.elementId, 'download' + msg.elementId]
            .map(function(id) { return document.getElementById(id); })
            .filter(function(e) { return !!e; });
          var navEls = el.querySelectorAll('.vis-navigation');
          for (var n = 0; n < navEls.length; n++) toHide.push(navEls[n]);
          var hiddenState = toHide.map(function(e) { return {el: e, prevDisplay: e.style.display}; });
          hiddenState.forEach(function(h) { h.el.style.display = 'none'; });

          function restoreHidden() {
            hiddenState.forEach(function(h) { h.el.style.display = h.prevDisplay; });
          }

          function resizeTo(w, h) {
            el.style.width = w + 'px';
            el.style.height = h + 'px';
            if (widget && widget.network && widget.network.setSize) widget.network.setSize(w + 'px', (h - 40) + 'px');
            if (widget && widget.network && widget.network.redraw) widget.network.redraw();
            if (widget && widget.network && widget.network.fit) widget.network.fit();
            if (widget && widget.legend && widget.legend.redraw) widget.legend.redraw();
            if (widget && widget.legend && widget.legend.fit) widget.legend.fit();
          }

          function cropToContent(canvas, padding) {
            var ctx = canvas.getContext('2d');
            var w = canvas.width, h = canvas.height;
            var data = ctx.getImageData(0, 0, w, h).data;
            var minX = w, minY = h, maxX = 0, maxY = 0, found = false;
            for (var y = 0; y < h; y++) {
              for (var x = 0; x < w; x++) {
                var idx = (y * w + x) * 4;
                var isBlank = data[idx + 3] < 10 || (data[idx] > 250 && data[idx + 1] > 250 && data[idx + 2] > 250);
                if (!isBlank) {
                  found = true;
                  if (x < minX) minX = x;
                  if (x > maxX) maxX = x;
                  if (y < minY) minY = y;
                  if (y > maxY) maxY = y;
                }
              }
            }
            if (!found) return canvas;
            minX = Math.max(0, minX - padding);
            minY = Math.max(0, minY - padding);
            maxX = Math.min(w - 1, maxX + padding);
            maxY = Math.min(h - 1, maxY + padding);
            var cropW = maxX - minX + 1, cropH = maxY - minY + 1;
            var cropped = document.createElement('canvas');
            cropped.width = cropW;
            cropped.height = cropH;
            cropped.getContext('2d').drawImage(canvas, minX, minY, cropW, cropH, 0, 0, cropW, cropH);
            return cropped;
          }

          resizeTo(bigWidth, bigHeight);

          setTimeout(function() {
            var rect = el.getBoundingClientRect();
            var maxRight = rect.width;
            var maxBottom = rect.height;
            var descendants = el.querySelectorAll('*');
            for (var i = 0; i < descendants.length; i++) {
              var r = descendants[i].getBoundingClientRect();
              if (r.width === 0 && r.height === 0) continue;
              maxRight = Math.max(maxRight, r.right - rect.left);
              maxBottom = Math.max(maxBottom, r.bottom - rect.top);
            }

            html2canvas(el, {
              width: Math.ceil(maxRight) + 6,
              height: Math.ceil(maxBottom) + 6
            }).then(function(canvas) {
              if (canvas.width > 0 && canvas.height > 0) {
                var finalCanvas = cropToContent(canvas, 40);
                Shiny.setInputValue(msg.inputId, finalCanvas.toDataURL('image/png'), {priority: 'event'});
              }
              restoreHidden();
              resizeTo(origRect.width, origRect.height);
              el.style.width = origWidth;
              el.style.height = origHeight;
            }).catch(function() {
              restoreHidden();
              resizeTo(origRect.width, origRect.height);
              el.style.width = origWidth;
              el.style.height = origHeight;
            });
          }, 250);
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
        checkboxInput(ns("include_descriptors"), "DPSIR descriptors", value = FALSE),
        checkboxInput(ns("include_references"), "Edge references", value = FALSE)
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

mod_report_server <- function(id, schema, nodes, edges, graph, saved_scenarios, graph_snapshots, centrality_params) {
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
          centrality_params = centrality_params(),
          include_descriptors = isTRUE(input$include_descriptors),
          include_references = isTRUE(input$include_references),
          saved_scenarios = saved,
          selected_scenario_names = selected_scenario_names
        )

        htmltools::save_html(page, file)
      }
    )
  })
}
