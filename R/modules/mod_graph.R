# =====================================================
# MOD_GRAPH - GRAPH EXPLORATION PANEL (layered layout)
# =====================================================
#
# Lightweight panel (not a wizard step): receives schema/nodes/edges/graph
# from mod_data and applies filters (subsystem, temporal scale) + display
# options (palette, node/edge emphasis, spacing), without altering the
# saved project state. Pathway highlighting lives here too (not a separate
# tab): a "Highlight pathway" dropdown, same pattern as "Select by group" /
# "Node size based on", so picking a pathway updates this same graph
# instead of sending the user to another tab and back. The nodes table
# below the network is kept in sync with graph clicks in both directions.
#
# Controls live in collapsible boxes stacked in a left column (Fase 4.2),
# grouped by theme, so they no longer push the graph itself below the fold;
# the graph + legend take up the wider right column. Communities is no
# longer a separate tab with its own, independently-configured widget - it's
# now a "Color nodes by" option on this same graph, sharing every filter and
# display setting already set here (subsystem/temporal filters, spacing,
# node/edge emphasis), which is what keeps the two views from ever
# disagreeing with each other the way the old separate tab could.
#
# "Save current view for report" below the graph captures a named snapshot
# of whatever is on screen (any palette/coloring/filter/highlight combo) for
# later inclusion in the Report tab - see the comment above graph_snapshots
# below for why this replaced the old auto-capture-on-tab-switch mechanism.
#
# Layout: "Layered by category" (fixed X per DPSIR category, the original
# default) draws a small feedback-loop network as a straight row with one
# long arc closing the loop - readable for D->P->S->I->R flow, poor for
# reading a cycle as a cycle. "Circular" (R/graph.R's compute_circular_layout)
# places every node evenly around a ring regardless of category, so a loop's
# closing edge is just another chord instead of a diagram-spanning arc.
# Dragging a node pins it (fixed.x/fixed.y in graph.R) so it stops drifting
# back under the physics solver - previously only X was locked, so any
# manual rearrangement kept getting nudged by the "avoid overlap" solver
# the moment you let go. Dragged positions are kept in mod_data.R's
# `positions` (a savepoint field that already existed but had nothing
# writing to it) via `positions`/`set_positions` passed in below, so they
# survive filter/color changes and a savepoint save/reload, not just the
# current render.

mod_graph_ui <- function(id) {
  ns <- NS(id)

  fluidRow(
    column(
      width = 4,

      box(
        width = 12, title = "Display", status = "primary", solidHeader = TRUE, collapsible = TRUE,
        selectInput(
          ns("layout_mode"), "Layout",
          choices = c("Layered by category" = "layered", "Circular" = "circular")
        ),
        selectInput(ns("palette"), "Color palette", choices = get_dpsir_palette_choices()),
        checkboxInput(ns("use_shapes"), "Use DPSIR shapes", value = TRUE),
        selectInput(ns("subsystem_filter"), "Subsystem", choices = "All"),
        selectInput(ns("temporal_filter"), "Temporal scale", choices = "All"),
        checkboxInput(ns("show_node_legend"), "Show category/community legend", value = TRUE),
        checkboxInput(ns("show_edge_legend"), "Show edge-type legend", value = TRUE)
      ),

      box(
        width = 12, title = "Node & edge emphasis", status = "primary", solidHeader = TRUE, collapsible = TRUE,
        selectInput(
          ns("node_size_mode"), "Node size based on",
          choices = c("Total degree" = "all", "Incoming edges" = "in", "Outgoing edges" = "out")
        ),
        checkboxInput(ns("node_size_weighted"), "Size by edge weight (strength)", value = FALSE),
        selectInput(
          ns("edge_width_by"), "Edge width based on",
          choices = c("Edge weight" = "weight", "Confidence" = "confidence", "Fixed" = "fixed")
        ),
        sliderInput(ns("confidence_threshold"), "Dash edges below confidence", min = 0, max = 1, value = 0.5, step = 0.05)
      ),

      box(
        width = 12, title = "Layout & spacing", status = "primary", solidHeader = TRUE,
        collapsible = TRUE, collapsed = TRUE,
        sliderInput(ns("x_spacing"), "Horizontal spacing between categories", min = 100, max = 500, value = 200, step = 25),
        sliderInput(ns("y_spacing"), "Vertical spacing between nodes", min = 30, max = 250, value = 80, step = 10),
        sliderInput(ns("avoid_overlap"), "Avoid node overlap", min = 0, max = 1, value = 0.5, step = 0.1),
        sliderInput(ns("node_font_size"), "Graph label font size", min = 8, max = 40, value = 14, step = 1),
        sliderInput(ns("legend_font_size"), "Legend font size", min = 8, max = 40, value = 14, step = 1),
        tags$hr(),
        p(
          class = "text-muted", style = "font-size: 13px;",
          "Drag a node to pin it in place - it stops following the layout above",
          "until you reset it."
        ),
        actionButton(ns("reset_positions"), "Reset dragged positions", icon = icon("rotate-left"), class = "btn-outline-secondary btn-sm")
      ),

      box(
        width = 12, title = "Pathway highlight", status = "primary", solidHeader = TRUE,
        collapsible = TRUE, collapsed = TRUE,
        selectInput(ns("path_from_category"), "Pathway from category", choices = character()),
        selectInput(ns("path_to_category"), "Pathway to category", choices = character()),
        selectInput(ns("path_highlight"), "Highlight pathway", choices = c("None" = "none"), width = "100%")
      ),

      box(
        width = 12, title = "Communities", status = "primary", solidHeader = TRUE,
        collapsible = TRUE, collapsed = TRUE,
        selectInput(ns("color_by"), "Color nodes by", choices = c("DPSIR category" = "category", "Community" = "community")),
        conditionalPanel(
          condition = sprintf("input['%s'] == 'community'", ns("color_by")),
          selectInput(
            ns("community_algorithm"), "Algorithm",
            choices = c("Louvain", "Walktrap", "Infomap", "Label Propagation")
          ),
          DTOutput(ns("membership_table"))
        )
      ),

      box(
        width = 12, title = "Nodes", status = "primary", solidHeader = TRUE,
        collapsible = TRUE, collapsed = TRUE,
        p("Click a node in the graph to select it here, or select a row to focus it in the graph."),
        actionButton(ns("clear_selection"), "Clear selection", icon = icon("eraser"), class = "btn-outline-secondary btn-sm"),
        DTOutput(ns("nodes_table"))
      )
    ),

    column(
      width = 8,
      box(
        width = 12, title = "Graph", status = "primary", solidHeader = TRUE,
        visNetworkOutput(ns("network"), height = "800px"),
        tags$hr(),
        fluidRow(
          column(width = 6, textInput(ns("snapshot_name"), NULL, value = "Snapshot 1", placeholder = "Snapshot name")),
          column(width = 6, actionButton(ns("save_snapshot"), "Save current view for report", icon = icon("camera"), class = "btn-outline-primary", width = "100%"))
        ),
        uiOutput(ns("snapshot_status"))
      )
    )
  )
}

mod_graph_server <- function(id, schema, nodes, edges, graph, positions, set_positions) {
  moduleServer(id, function(input, output, session) {
    observeEvent(nodes(), {
      n <- nodes()

      subsystems <- sort(unique(n$subsystem[nzchar(n$subsystem)]))
      updateSelectInput(session, "subsystem_filter", choices = c("All", subsystems), selected = "All")

      temporals <- sort(unique(n$temporal_scale[nzchar(n$temporal_scale)]))
      updateSelectInput(session, "temporal_filter", choices = c("All", temporals), selected = "All")
    })

    # =================================================
    # PATHWAY HIGHLIGHT (dropdown, same pattern as the other display options)
    # =================================================

    observeEvent(schema(), {
      categories <- schema_categories(schema())
      updateSelectInput(session, "path_from_category", choices = categories, selected = categories[1])
      updateSelectInput(session, "path_to_category", choices = categories, selected = categories[length(categories)])
    })

    path_candidates <- reactive({
      req(graph(), input$path_from_category, input$path_to_category)

      paths <- find_dpsir_paths(graph(), input$path_from_category, input$path_to_category, schema = schema())
      compute_critical_pathways(graph(), paths, top_n = 10)
    })

    observeEvent(path_candidates(), {
      candidates <- path_candidates()

      if (nrow(candidates) == 0) {
        updateSelectInput(session, "path_highlight", choices = c("None" = "none"), selected = "none")
        return()
      }

      choices <- setNames(
        as.character(seq_len(nrow(candidates))),
        sprintf("%s (score %.2f)", candidates$nodes, candidates$score)
      )
      updateSelectInput(session, "path_highlight", choices = c("None" = "none", choices), selected = "none")
    })

    highlighted_nodes <- reactive({
      sel <- input$path_highlight

      if (is.null(sel) || sel == "none") {
        return(NULL)
      }

      row <- path_candidates()[as.integer(sel), ]
      trimws(strsplit(row$nodes, " -> ", fixed = TRUE)[[1]])
    })

    filtered_nodes <- reactive({
      n <- nodes()

      if (!is.null(input$subsystem_filter) && input$subsystem_filter != "All") {
        n <- n[n$subsystem == input$subsystem_filter, ]
      }

      if (!is.null(input$temporal_filter) && input$temporal_filter != "All") {
        n <- n[n$temporal_scale == input$temporal_filter, ]
      }

      n
    })

    filtered_edges <- reactive({
      n <- filtered_nodes()
      e <- edges()
      e[e$from %in% n$id & e$to %in% n$id, ]
    })

    filtered_graph <- reactive({
      n <- filtered_nodes()
      if (nrow(n) == 0) return(NULL)

      tryCatch(
        build_igraph(n, filtered_edges(), schema()),
        error = function(e) NULL
      )
    })

    # =================================================
    # COMMUNITIES (a coloring mode of this same graph, not a separate widget -
    # shares filtered_nodes()/filtered_edges()/filtered_graph() and every
    # display control above, so it can never show something inconsistent
    # with what's configured in Display / Node & edge emphasis / Layout.
    # =================================================

    community_result <- reactive({
      req(identical(input$color_by, "community"), filtered_graph())
      g <- filtered_graph()

      # Louvain and Label Propagation are undefined for directed graphs;
      # converted to undirected to avoid an error.
      switch(
        input$community_algorithm,
        "Louvain" = cluster_louvain(as.undirected(g)),
        "Walktrap" = cluster_walktrap(g),
        "Infomap" = cluster_infomap(g),
        "Label Propagation" = cluster_label_prop(as.undirected(g))
      )
    })

    membership_vector <- reactive({
      req(community_result())
      membership(community_result())
    })

    output$network <- renderVisNetwork({
      req(graph())
      req(filtered_graph())

      display_schema <- apply_schema_palette(schema(), input$palette)

      widget <- if (identical(input$color_by, "community")) {
        build_community_visual(
          nodes = filtered_nodes(),
          edges = filtered_edges(),
          graph = filtered_graph(),
          schema = display_schema,
          membership = membership_vector(),
          node_size_mode = input$node_size_mode,
          node_size_weighted = input$node_size_weighted,
          edge_width_by = input$edge_width_by,
          confidence_threshold = input$confidence_threshold,
          x_spacing = input$x_spacing,
          y_spacing = input$y_spacing,
          avoid_overlap = input$avoid_overlap,
          node_font_size = input$node_font_size,
          legend_font_size = input$legend_font_size,
          layout_mode = input$layout_mode,
          manual_positions = positions(),
          show_node_legend = input$show_node_legend,
          show_edge_legend = input$show_edge_legend
        )
      } else {
        build_network_visual(
          nodes = filtered_nodes(),
          edges = filtered_edges(),
          graph = filtered_graph(),
          schema = display_schema,
          use_dpsir_shapes = input$use_shapes,
          node_size_mode = input$node_size_mode,
          node_size_weighted = input$node_size_weighted,
          edge_width_by = input$edge_width_by,
          confidence_threshold = input$confidence_threshold,
          x_spacing = input$x_spacing,
          y_spacing = input$y_spacing,
          avoid_overlap = input$avoid_overlap,
          node_font_size = input$node_font_size,
          legend_font_size = input$legend_font_size,
          highlighted_nodes = highlighted_nodes(),
          layout_mode = input$layout_mode,
          manual_positions = positions(),
          show_node_legend = input$show_node_legend,
          show_edge_legend = input$show_edge_legend
        )
      }

      widget %>%
        visEvents(
          select = sprintf(
            "function(properties) { Shiny.setInputValue('%s', properties.nodes, {priority: 'event'}); }",
            session$ns("node_click")
          ),
          dragEnd = sprintf(
            "function(properties) {
              if (properties.nodes.length === 0) return;
              var pos = this.getPositions(properties.nodes);
              var payload = properties.nodes.map(function(id) { return {id: id, x: pos[id].x, y: pos[id].y}; });
              Shiny.setInputValue('%s', payload, {priority: 'event'});
            }",
            session$ns("node_drag")
          )
        )
    })

    output$membership_table <- renderDT({
      req(identical(input$color_by, "community"))

      mem <- membership_vector()
      n <- filtered_nodes()

      df <- data.frame(
        id = names(mem),
        label = n$label[match(names(mem), n$id)],
        community = as.integer(mem),
        stringsAsFactors = FALSE
      )

      datatable(df, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE, dom = "t"))
    })

    # =================================================
    # MANUAL NODE POSITIONS (dragging pins a node in place -
    # see fixed.x/fixed.y in graph.R for why this stopped nodes
    # drifting back under the physics solver). Persisted through
    # mod_data.R's `positions` savepoint field, which existed
    # already but had nothing writing to it until now.
    # =================================================

    observeEvent(input$node_drag, {
      payload <- input$node_drag

      # Confirmed empirically (not assumed): Shiny's default JSON
      # deserialization flattens an array of {id,x,y} objects into one
      # repeating named vector (id,x,y,id,x,y,...), not a data.frame or a
      # list of lists - true for both a single dragged node and several.
      dragged <- if (is.data.frame(payload)) {
        payload
      } else if (is.atomic(payload)) {
        nm <- names(payload)
        data.frame(
          id = as.character(payload[nm == "id"]),
          x = as.numeric(payload[nm == "x"]),
          y = as.numeric(payload[nm == "y"]),
          stringsAsFactors = FALSE
        )
      } else {
        do.call(rbind, lapply(payload, function(p) {
          data.frame(id = as.character(p$id), x = as.numeric(p$x), y = as.numeric(p$y), stringsAsFactors = FALSE)
        }))
      }

      current <- positions()
      if (is.null(current)) {
        current <- data.frame(id = character(), x = numeric(), y = numeric(), stringsAsFactors = FALSE)
      }

      current <- current[!current$id %in% dragged$id, ]
      set_positions(rbind(current, dragged))
    })

    observeEvent(input$reset_positions, {
      set_positions(NULL)
    })

    # =================================================
    # CROSS-SELECTION: GRAPH <-> NODES TABLE
    # =================================================

    output$nodes_table <- renderDT({
      datatable(
        filtered_nodes()[, c("id", "label", "dpsir_category", "subsystem")],
        selection = "single",
        rownames = FALSE,
        options = list(pageLength = 10, scrollX = TRUE)
      )
    })

    # Only the table -> graph direction needs a reentrancy guard: selectRows()
    # re-triggers nodes_table_rows_selected, which would otherwise call
    # visSelectNodes() again. visNetworkProxy's visSelectNodes() does NOT
    # re-emit vis.js's "select" event, so the graph -> table direction has
    # no feedback loop to guard against.
    suppress_table_sync <- reactiveVal(FALSE)

    observeEvent(input$node_click, {
      ids <- input$node_click
      proxy <- dataTableProxy("nodes_table")

      if (length(ids) == 0) {
        selectRows(proxy, NULL)
        return()
      }

      idx <- match(ids[1], filtered_nodes()$id)
      if (!is.na(idx)) {
        suppress_table_sync(TRUE)
        selectRows(proxy, idx)
      }
    })

    observeEvent(input$nodes_table_rows_selected, {
      if (isTRUE(suppress_table_sync())) {
        suppress_table_sync(FALSE)
        return()
      }

      sel <- input$nodes_table_rows_selected
      if (is.null(sel)) return()

      node_id <- filtered_nodes()$id[sel]
      visNetworkProxy(session$ns("network")) %>% visSelectNodes(id = node_id)
    })

    observeEvent(input$clear_selection, {
      selectRows(dataTableProxy("nodes_table"), NULL)
      visNetworkProxy(session$ns("network")) %>% visUnselectAll()
    })

    # =================================================
    # SAVE CURRENT VIEW FOR THE REPORT
    # =================================================
    #
    # A named snapshot of exactly what's on screen right now (whatever
    # palette/coloring/filters/highlight are active), captured client-side
    # with html2canvas via the shared message handler registered in
    # mod_report.R. Captured on demand by this button - not automatically
    # whenever the tab is opened - so the user decides what's worth keeping,
    # and can build up several named views (e.g. "By category", "By
    # community", "Fisheries pathway") to pick from later in the Report tab.

    graph_snapshots <- reactiveValues(list = list())
    snapshot_counter <- reactiveVal(1)
    pending_snapshot_name <- reactiveVal(NULL)
    pending_snapshot_caption <- reactiveVal(NULL)

    # Describes exactly which display/filter/highlight choices produced this
    # view, so the Report tab can caption the figure instead of showing a
    # bare image - the same choices affect what's visually meaningful, not
    # cosmetic-only settings like spacing/font size.
    build_snapshot_caption <- function() {
      layout_desc <- paste0("layout: ", c(layered = "layered by category", circular = "circular")[[input$layout_mode]])

      color_desc <- if (identical(input$color_by, "community")) {
        paste0("nodes colored by community (", input$community_algorithm, " algorithm)")
      } else {
        paste0("nodes colored by DPSIR category (", input$palette, " palette)")
      }

      filters <- character()
      if (!is.null(input$subsystem_filter) && input$subsystem_filter != "All") {
        filters <- c(filters, paste0("subsystem = ", input$subsystem_filter))
      }
      if (!is.null(input$temporal_filter) && input$temporal_filter != "All") {
        filters <- c(filters, paste0("temporal scale = ", input$temporal_filter))
      }
      filter_desc <- if (length(filters) > 0) paste0("filtered by ", paste(filters, collapse = ", ")) else "no filters applied"

      size_labels <- c(all = "total degree", "in" = "incoming edges", "out" = "outgoing edges")
      size_desc <- paste0(
        "node size by ", size_labels[[input$node_size_mode]],
        if (isTRUE(input$node_size_weighted)) " (weighted by edge weight)" else ""
      )

      edge_labels <- c(weight = "edge weight", confidence = "confidence", fixed = "fixed width")
      edge_desc <- sprintf(
        "edge width by %s, dashed below confidence %.2f",
        edge_labels[[input$edge_width_by]], input$confidence_threshold
      )

      parts <- c(layout_desc, color_desc, filter_desc, size_desc, edge_desc)

      if (!is.null(input$path_highlight) && input$path_highlight != "none") {
        candidates <- path_candidates()
        idx <- as.integer(input$path_highlight)
        if (!is.na(idx) && idx <= nrow(candidates)) {
          parts <- c(parts, paste0("highlighted pathway: ", candidates$nodes[idx]))
        }
      }

      paste0(paste(parts, collapse = "; "), ".")
    }

    observeEvent(input$save_snapshot, {
      name <- trimws(input$snapshot_name)

      if (!nzchar(name)) {
        showNotification("Enter a name for this snapshot before saving.", type = "warning")
        return()
      }

      pending_snapshot_name(name)
      pending_snapshot_caption(build_snapshot_caption())
      session$sendCustomMessage(
        "idpsir_capture_element",
        list(elementId = session$ns("network"), inputId = session$ns("snapshot_capture_result"))
      )
    })

    observeEvent(input$snapshot_capture_result, {
      name <- pending_snapshot_name()
      req(name)

      saved <- graph_snapshots$list
      saved[[name]] <- list(image = input$snapshot_capture_result, caption = pending_snapshot_caption())
      graph_snapshots$list <- saved

      snapshot_counter(snapshot_counter() + 1)
      updateTextInput(session, "snapshot_name", value = paste("Snapshot", snapshot_counter()))
      showNotification(paste0("Snapshot '", name, "' saved for the report."), type = "message")
    })

    output$snapshot_status <- renderUI({
      saved <- graph_snapshots$list

      if (length(saved) == 0) {
        return(tags$p(class = "text-muted", "No snapshots saved yet."))
      }

      tags$p(
        class = "text-muted",
        paste0(
          length(saved), " snapshot(s) saved: ", paste(names(saved), collapse = ", "),
          ". Choose which to include on the Report tab."
        )
      )
    })

    list(
      graph_snapshots = reactive(graph_snapshots$list)
    )
  })
}
