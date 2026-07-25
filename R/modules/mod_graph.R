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

mod_graph_ui <- function(id) {
  ns <- NS(id)

  fluidRow(
    column(
      width = 4,

      box(
        width = 12, title = "Display", status = "primary", solidHeader = TRUE, collapsible = TRUE,
        selectInput(ns("palette"), "Color palette", choices = get_dpsir_palette_choices()),
        checkboxInput(ns("use_shapes"), "Use DPSIR shapes", value = TRUE),
        selectInput(ns("subsystem_filter"), "Subsystem", choices = "All"),
        selectInput(ns("temporal_filter"), "Temporal scale", choices = "All")
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
        sliderInput(ns("legend_font_size"), "Legend font size", min = 8, max = 40, value = 14, step = 1)
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
        DTOutput(ns("nodes_table"))
      )
    ),

    column(
      width = 8,
      box(
        width = 12, title = "Graph", status = "primary", solidHeader = TRUE,
        visNetworkOutput(ns("network"), height = "800px")
      )
    )
  )
}

mod_graph_server <- function(id, schema, nodes, edges, graph) {
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
          legend_font_size = input$legend_font_size
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
          highlighted_nodes = highlighted_nodes()
        )
      }

      widget %>%
        visEvents(select = sprintf(
          "function(properties) { Shiny.setInputValue('%s', properties.nodes, {priority: 'event'}); }",
          session$ns("node_click")
        ))
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
  })
}
