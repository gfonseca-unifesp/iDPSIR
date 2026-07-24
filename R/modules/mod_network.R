# =====================================================
# UI
# =====================================================

network_ui <- function(id){
  
  ns <- NS(id)
  
  fluidPage(
    
    fluidRow(
      
      # =================================================
      # LEFT PANEL
      # =================================================
      
      column(
        width = 3,
        
        # -----------------------------------------------
        # DATA IMPORT
        # -----------------------------------------------
        
        box(
          width = 12,
          title = "Data Upload",
          status = "primary",
          solidHeader = TRUE,
          collapsible = TRUE,
          
          upload_ui(ns("upload"))
        ),
        
        # -----------------------------------------------
        # EXPORT
        # -----------------------------------------------
        
        box(
          width = 12,
          title = "Export",
          status = "success",
          solidHeader = TRUE,
          collapsible = TRUE,
          
          downloadButton(
            ns("download_edges"),
            "Download Edge Table"
          ),
          
          br(),
          br(),
          
          downloadButton(
            ns("download_nodes"),
            "Download Node Table"
          )
        )
      ),
      
      # =================================================
      # NETWORK PANEL
      # =================================================
      
      column(
        width = 9,
        
        tabsetPanel(
          type = "tabs",
          
          tabPanel(
            "Table Editor",
            tabsetPanel(
              type = "tabs",
              
              tabPanel(
                "1. Nodes",
                fluidRow(
                  column(
                    width = 12,
                    box(
                      width = 12,
                      title = "Node Setup",
                      status = "primary",
                      solidHeader = TRUE,
                      
                      actionButton(
                        ns("add_node_row"),
                        "Add Node",
                        icon = icon("plus")
                      ),
                      
                      actionButton(
                        ns("remove_empty_nodes"),
                        "Remove Empty Rows",
                        icon = icon("trash")
                      ),
                      
                      actionButton(
                        ns("validate_nodes_step"),
                        "Validate Nodes",
                        icon = icon("check")
                      ),
                      
                      actionButton(
                        ns("render_nodes_graph_step"),
                        "Render Graph with Nodes",
                        icon = icon("play")
                      ),
                      
                      uiOutput(ns("editor_status")),
                      
                      DTOutput(ns("nodes_editor"))
                    )
                  )
                )
              ),
              
              tabPanel(
                "2. Render Graph",
                box(
                  width = 12,
                  title = "Preview with Nodes Only",
                  status = "warning",
                  solidHeader = TRUE,
                  
                  visNetworkOutput(ns("graph_nodes_preview"), height = "700px")
                )
              ),
              
              tabPanel(
                "3. Edges",
                fluidRow(
                  column(
                    width = 12,
                    box(
                      width = 12,
                      title = "Edge Setup",
                      status = "success",
                      solidHeader = TRUE,
                      
                      actionButton(
                        ns("add_edge_row"),
                        "Add Edge",
                        icon = icon("plus")
                      ),
                      
                      actionButton(
                        ns("remove_empty_edges"),
                        "Remove Empty Rows",
                        icon = icon("trash")
                      ),
                      
                      actionButton(
                        ns("validate_edges_step"),
                        "Validate Edges",
                        icon = icon("check")
                      ),
                      
                      actionButton(
                        ns("render_graph_step"),
                        "Render Final Graph",
                        icon = icon("play")
                      ),
                      
                      actionButton(
                        ns("clear_editor"),
                        "Clear Editor",
                        icon = icon("trash")
                      ),
                      
                      DTOutput(ns("edges_editor"))
                    )
                  )
                )
              ),
              
              tabPanel(
                "4. Final Graph",
                box(
                  width = 12,
                  title = "Final Network Preview",
                  status = "primary",
                  solidHeader = TRUE,
                  
                  selectInput(
                    ns("color_palette"),
                    "Color Palette",
                    choices = get_dpsir_palette_choices(),
                    selected = "default"
                  ),
                  
                  checkboxInput(
                    ns("use_dpsir_shapes"),
                    "Use DPSIR symbols",
                    value = TRUE
                  ),
                  
                  radioButtons(
                    ns("node_size_metric"),
                    "Node Size",
                    choices = c(
                      "Total edges" = "total",
                      "Incoming edges" = "incoming",
                      "Outgoing edges" = "outgoing"
                    ),
                    selected = "total"
                  ),
                  
                  visNetworkOutput(ns("graph_final_preview"), height = "700px")
                )
              )
            )
          )
        )
      )
    )
  )
}


# =====================================================
# SERVER
# =====================================================

network_server <- function(id){
  
  moduleServer(id, function(input, output, session){
    
    ns <- session$ns
    
    # =================================================
    # IMPORT MODULE
    # =================================================
    
    upload <- upload_server("upload")
    
    # =================================================
    # GRAPH STATE
    # =================================================
    
    graph_state <- reactiveValues(
      nodes = NULL,
      edges = NULL,
      render_graph = FALSE,
      render_nodes_graph = FALSE,
      validation_message = ""
    )
    
    create_empty_nodes_table <- function() {
      data.frame(
        id = character(),
        label = character(),
        dpsir_category = character(),
        subsystem = character(),
        uncertainty = character(),
        controllability = character(),
        temporal_scale = character(),
        stringsAsFactors = FALSE
      )
    }
    
    create_empty_edges_table <- function() {
      data.frame(
        from = character(),
        to = character(),
        weight = numeric(),
        confidence = numeric(),
        interaction_type = character(),
        evidence_type = character(),
        stringsAsFactors = FALSE
      )
    }
    
    safe_nodes_table <- function(nodes) {
      if (is.null(nodes) || !is.data.frame(nodes)) {
        return(create_empty_nodes_table())
      }
      normalize_nodes_table(nodes)
    }
    
    safe_edges_table <- function(edges) {
      if (is.null(edges) || !is.data.frame(edges)) {
        return(create_empty_edges_table())
      }
      normalize_edges_table(edges)
    }
    
    normalize_nodes_table <- function(nodes) {
      if (is.null(nodes) || !is.data.frame(nodes)) {
        return(create_empty_nodes_table())
      }
      
      nodes <- as.data.frame(nodes, stringsAsFactors = FALSE)
      nodes <- nodes[, !is.na(names(nodes)), drop = FALSE]
      expected_cols <- names(create_empty_nodes_table())
      
      for (col in expected_cols) {
        if (!(col %in% names(nodes))) {
          nodes[[col]] <- if (col %in% c("weight", "confidence")) {
            numeric()
          } else {
            character()
          }
        }
      }
      
      nodes <- nodes[, expected_cols, drop = FALSE]
      
      nodes$id <- trimws(as.character(nodes$id))
      nodes$label <- as.character(nodes$label)
      nodes$dpsir_category <- trimws(as.character(nodes$dpsir_category))
      nodes$subsystem <- as.character(nodes$subsystem)
      nodes$uncertainty <- as.character(nodes$uncertainty)
      nodes$controllability <- as.character(nodes$controllability)
      nodes$temporal_scale <- as.character(nodes$temporal_scale)
      
      nodes <- nodes[, expected_cols, drop = FALSE]
      nodes
    }
    
    normalize_edges_table <- function(edges) {
      if (is.null(edges) || !is.data.frame(edges)) {
        return(create_empty_edges_table())
      }
      
      edges <- as.data.frame(edges, stringsAsFactors = FALSE)
      expected_cols <- names(create_empty_edges_table())
      
      for (col in expected_cols) {
        if (!(col %in% names(edges))) {
          edges[[col]] <- if (col %in% c("weight", "confidence")) {
            numeric()
          } else {
            character()
          }
        }
      }
      
      edges <- edges[, expected_cols, drop = FALSE]
      
      edges$from <- trimws(as.character(edges$from))
      edges$to <- trimws(as.character(edges$to))
      edges$weight <- suppressWarnings(as.numeric(edges$weight))
      edges$confidence <- suppressWarnings(as.numeric(edges$confidence))
      edges$interaction_type <- as.character(edges$interaction_type)
      edges$evidence_type <- as.character(edges$evidence_type)
      
      edges
    }
    
    # =================================================
    # LOAD NODES
    # =================================================
    
    observeEvent(upload$nodes(), {
      
      nodes <- safe_nodes_table(upload$nodes())
      
      tryCatch(
        {
          validate_nodes(nodes)
          graph_state$validation_message <- "Nodes are valid. Proceed to edges."
          graph_state$render_graph <- FALSE
          graph_state$render_nodes_graph <- FALSE
          nodes$id <- as.character(nodes$id)
          graph_state$nodes <- nodes
        },
        error = function(e) {
          graph_state$validation_message <- conditionMessage(e)
          graph_state$render_graph <- FALSE
          graph_state$render_nodes_graph <- FALSE
        }
      )
      
    })
    
    # =================================================
    # LOAD EDGES
    # =================================================
    
    observeEvent(upload$edges(), {
      
      req(graph_state$nodes)
      
      edges <- safe_edges_table(upload$edges())
      
      tryCatch(
        {
          validate_edges(edges)
          graph_state$validation_message <- "Edges are valid. You can now render the graph."
          graph_state$render_graph <- FALSE
          graph_state$render_nodes_graph <- FALSE
          graph_state$edges <- sanitize_edges(
            edges,
            graph_state$nodes
          )
        },
        error = function(e) {
          graph_state$validation_message <- conditionMessage(e)
          graph_state$render_graph <- FALSE
          graph_state$render_nodes_graph <- FALSE
        }
      )
      
    })
    
    # =================================================
    # BUILD IGRAPH
    # =================================================
    graph_obj <- reactive({
      
      if (is.null(graph_state$nodes) || !is.data.frame(graph_state$nodes)) {
        return(NULL)
      }
      
      if (nrow(graph_state$nodes) == 0) {
        return(NULL)
      }
      
      nodes <- graph_state$nodes
      edges <- graph_state$edges
      
      tryCatch(
        {
          build_igraph(nodes, edges)
        },
        error = function(e) {
          NULL
        }
      )
      
    })
    
    # =================================================
    # NETWORK RENDER
    # =================================================

    output$graph_nodes_preview <- renderVisNetwork({
      
      req(
        graph_state$render_nodes_graph,
        !is.null(graph_obj())
      )
      
      build_network_visual(
        nodes = graph_state$nodes,
        edges = graph_state$edges,
        graph = graph_obj(),
        ns = ns,
        color_palette = input$color_palette,
        use_dpsir_shapes = input$use_dpsir_shapes,
        node_size_metric = input$node_size_metric
      )
      
    })
    
    output$graph_final_preview <- renderVisNetwork({
      
      req(
        graph_state$render_graph,
        !is.null(graph_obj())
      )
      
      build_network_visual(
        nodes = graph_state$nodes,
        edges = graph_state$edges,
        graph = graph_obj(),
        ns = ns,
        color_palette = input$color_palette,
        use_dpsir_shapes = input$use_dpsir_shapes,
        node_size_metric = input$node_size_metric
      )
      
    })
    
    output$editor_status <- renderUI({
      
      nodes_df <- safe_nodes_table(graph_state$nodes)
      edges_df <- safe_edges_table(graph_state$edges)
      
      status_text <- character()
      
      if (nrow(nodes_df) == 0) {
        step_label <- "Step 1"
        step_color <- "warning"
        status_text <- c(
          status_text,
          "Step 1: add at least one node before moving to edges."
        )
      } else if (any(nodes_df$id == "" | nodes_df$label == "" | nodes_df$dpsir_category == "")) {
        step_label <- "Step 1"
        step_color <- "warning"
        status_text <- c(
          status_text,
          "Step 1: complete id, label, and DPSIR category for every node."
        )
      } else if (nrow(edges_df) == 0) {
        step_label <- "Step 2"
        step_color <- "info"
        status_text <- c(
          status_text,
          "Step 2: edges are optional, but you can add them now if needed."
        )
      } else if (any(edges_df$from == "" | edges_df$to == "")) {
        step_label <- "Step 2"
        step_color <- "info"
        status_text <- c(
          status_text,
          "Step 2: every edge needs a valid source and target."
        )
      } else {
        step_label <- "Step 3"
        step_color <- "success"
        status_text <- c(
          status_text,
          "Step 3: the tables look ready. Click Render Graph to preview the network."
        )
      }
      
      if (nzchar(graph_state$validation_message)) {
        message_text <- graph_state$validation_message
      } else {
        message_text <- paste(status_text, collapse = " ")
      }
      
      tags$div(
        class = paste0("alert alert-", step_color),
        style = "padding: 10px; margin-top: 8px;",
        tags$strong(paste0(step_label, ": ")),
        message_text
      )
    })
    
    output$nodes_editor <- renderDT({
      
      nodes_df <- safe_nodes_table(graph_state$nodes)
      
      datatable(
        nodes_df,
        editable = TRUE,
        rownames = FALSE,
        options = list(
          pageLength = 10,
          dom = 't'
        )
      )
    })
    
    output$edges_editor <- renderDT({
      
      edges_df <- safe_edges_table(graph_state$edges)
      
      datatable(
        edges_df,
        editable = TRUE,
        rownames = FALSE,
        options = list(
          pageLength = 10,
          dom = 't'
        )
      )
    })
    
    observeEvent(input$nodes_editor_cell_edit, {
      
      info <- input$nodes_editor_cell_edit
      
      nodes_df <- safe_nodes_table(graph_state$nodes)
      
      if (
        info$row < 0 ||
        info$row >= nrow(nodes_df) ||
        info$col < 0 ||
        info$col >= ncol(nodes_df)
      ) {
        return()
      }
      
      col_name <- names(nodes_df)[info$col + 1]
      nodes_df[info$row + 1, col_name] <- info$value
      
      graph_state$nodes <- safe_nodes_table(nodes_df)
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
      graph_state$validation_message <- ""
      
      if (!is.null(graph_state$edges) && is.data.frame(graph_state$edges)) {
        graph_state$edges <- sanitize_edges(
          graph_state$edges,
          graph_state$nodes
        )
      }
    })
    
    observeEvent(input$edges_editor_cell_edit, {
      
      info <- input$edges_editor_cell_edit
      
      edges_df <- safe_edges_table(graph_state$edges)
      
      if (
        info$row < 0 ||
        info$row >= nrow(edges_df) ||
        info$col < 0 ||
        info$col >= ncol(edges_df)
      ) {
        return()
      }
      
      col_name <- names(edges_df)[info$col + 1]
      edges_df[info$row + 1, col_name] <- info$value
      
      graph_state$edges <- safe_edges_table(edges_df)
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
      graph_state$validation_message <- ""
      
      if (!is.null(graph_state$nodes) && is.data.frame(graph_state$nodes)) {
        graph_state$edges <- sanitize_edges(
          graph_state$edges,
          graph_state$nodes
        )
      }
    })
    
    observeEvent(input$add_node_row, {
      
      current_nodes <- safe_nodes_table(graph_state$nodes)
      
      new_row <- data.frame(
        id = "",
        label = "",
        dpsir_category = "Driver",
        subsystem = "",
        uncertainty = "",
        controllability = "",
        temporal_scale = "",
        stringsAsFactors = FALSE
      )
      
      graph_state$nodes <- as.data.frame(
        rbind(
          current_nodes,
          new_row,
          stringsAsFactors = FALSE,
          make.row.names = FALSE
        ),
        stringsAsFactors = FALSE
      )
      graph_state$nodes <- safe_nodes_table(graph_state$nodes)
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
      graph_state$validation_message <- ""
      
      if (!is.null(graph_state$edges) && is.data.frame(graph_state$edges)) {
        graph_state$edges <- sanitize_edges(
          graph_state$edges,
          graph_state$nodes
        )
      }
      
      replaceData(
        dataTableProxy(ns("nodes_editor")),
        graph_state$nodes,
        resetPaging = FALSE,
        rownames = FALSE
      )
    })
    
    observeEvent(input$remove_empty_nodes, {
      nodes_df <- safe_nodes_table(graph_state$nodes)
      nodes_df <- nodes_df[
        !(nodes_df$id == "" &
            nodes_df$label == "" &
            nodes_df$dpsir_category == "" &
            nodes_df$subsystem == "" &
            nodes_df$uncertainty == "" &
            nodes_df$controllability == "" &
            nodes_df$temporal_scale == ""),
      ]
      
      graph_state$nodes <- safe_nodes_table(nodes_df)
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
      graph_state$validation_message <- ""
      
      if (!is.null(graph_state$edges) && is.data.frame(graph_state$edges)) {
        graph_state$edges <- sanitize_edges(
          graph_state$edges,
          graph_state$nodes
        )
      }
      
      replaceData(
        dataTableProxy(ns("nodes_editor")),
        graph_state$nodes,
        resetPaging = FALSE,
        rownames = FALSE
      )
    })
    
    observeEvent(input$add_edge_row, {
      
      current_edges <- safe_edges_table(graph_state$edges)
      
      new_row <- data.frame(
        from = "",
        to = "",
        weight = 1,
        confidence = 1,
        interaction_type = "",
        evidence_type = "",
        stringsAsFactors = FALSE
      )
      
      graph_state$edges <- as.data.frame(
        rbind(
          current_edges,
          new_row,
          stringsAsFactors = FALSE,
          make.row.names = FALSE
        ),
        stringsAsFactors = FALSE
      )
      graph_state$edges <- safe_edges_table(graph_state$edges)
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
      graph_state$validation_message <- ""
      
      if (!is.null(graph_state$nodes) && is.data.frame(graph_state$nodes)) {
        graph_state$edges <- sanitize_edges(
          graph_state$edges,
          graph_state$nodes
        )
      }
      
      replaceData(
        dataTableProxy(ns("edges_editor")),
        graph_state$edges,
        resetPaging = FALSE,
        rownames = FALSE
      )
    })
    
    observeEvent(input$remove_empty_edges, {
      edges_df <- safe_edges_table(graph_state$edges)
      edges_df <- edges_df[
        !(edges_df$from == "" &
            edges_df$to == "" &
            edges_df$interaction_type == "" &
            edges_df$evidence_type == ""),
      ]
      
      graph_state$edges <- safe_edges_table(edges_df)
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
      graph_state$validation_message <- ""
      
      if (!is.null(graph_state$nodes) && is.data.frame(graph_state$nodes)) {
        graph_state$edges <- sanitize_edges(
          graph_state$edges,
          graph_state$nodes
        )
      }
      
      replaceData(
        dataTableProxy(ns("edges_editor")),
        graph_state$edges,
        resetPaging = FALSE,
        rownames = FALSE
      )
    })
    
    observeEvent(input$validate_nodes_step, {
      
      nodes_df <- safe_nodes_table(graph_state$nodes)
      
      tryCatch(
        {
          validate_nodes(nodes_df)
          graph_state$validation_message <- "Nodes are valid. You can now work on edges."
        },
        error = function(e) {
          graph_state$validation_message <- conditionMessage(e)
        }
      )
      
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
    })
    
    observeEvent(input$render_nodes_graph_step, {
      
      nodes_df <- safe_nodes_table(graph_state$nodes)
      
      tryCatch(
        {
          validate_nodes(nodes_df)
          graph_state$render_nodes_graph <- TRUE
          graph_state$validation_message <- "Nodes preview is ready."
        },
        error = function(e) {
          graph_state$render_nodes_graph <- FALSE
          graph_state$validation_message <- conditionMessage(e)
        }
      )
      
      graph_state$render_graph <- FALSE
    })
    
    observeEvent(input$validate_edges_step, {
      
      nodes_df <- safe_nodes_table(graph_state$nodes)
      edges_df <- safe_edges_table(graph_state$edges)
      
      tryCatch(
        {
          if (nrow(edges_df) == 0) {
            graph_state$validation_message <- "No edges were added yet. You can still render the graph with nodes only."
          } else {
            validate_dpsir_edges(nodes_df, edges_df)
            graph_state$validation_message <- "Edges are valid. Click Render Final Graph to preview the network."
          }
        },
        error = function(e) {
          graph_state$validation_message <- conditionMessage(e)
        }
      )
      
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
    })
    
    observeEvent(input$render_graph_step, {
      
      nodes_df <- safe_nodes_table(graph_state$nodes)
      edges_df <- safe_edges_table(graph_state$edges)
      
      tryCatch(
        {
          validate_nodes(nodes_df)
          
          if (nrow(edges_df) > 0) {
            validate_dpsir_edges(nodes_df, edges_df)
          }
          
          graph_state$render_graph <- TRUE
          graph_state$render_nodes_graph <- FALSE
          graph_state$validation_message <- "Final graph is ready to be rendered."
        },
        error = function(e) {
          graph_state$render_graph <- FALSE
          graph_state$render_nodes_graph <- FALSE
          graph_state$validation_message <- conditionMessage(e)
        }
      )
    })
    
    observeEvent(input$clear_editor, {
      
      graph_state$nodes <- create_empty_nodes_table()
      graph_state$edges <- create_empty_edges_table()
      graph_state$render_graph <- FALSE
      graph_state$render_nodes_graph <- FALSE
      graph_state$validation_message <- ""
      
      replaceData(
        dataTableProxy(ns("nodes_editor")),
        graph_state$nodes,
        resetPaging = FALSE,
        rownames = FALSE
      )
      
      replaceData(
        dataTableProxy(ns("edges_editor")),
        graph_state$edges,
        resetPaging = FALSE,
        rownames = FALSE
      )
    })
    
    # =================================================
    # DOWNLOAD EDGE TABLE
    # =================================================
    
    output$download_edges <- downloadHandler(
      
      filename = function() {
        
        paste0(
          "INA_edges_",
          Sys.Date(),
          ".csv"
        )
        
      },
      
      content = function(file) {
        
        write.csv(
          graph_state$edges,
          file,
          row.names = FALSE
        )
        
      }
    )
    
    # =================================================
    # DOWNLOAD NODE TABLE
    # =================================================
    
    output$download_nodes <- downloadHandler(
      
      filename = function() {
        
        paste0(
          "INA_nodes_",
          Sys.Date(),
          ".csv"
        )
        
      },
      
      content = function(file) {
        
        write.csv(
          graph_state$nodes,
          file,
          row.names = FALSE
        )
        
      }
    )
    
    # =================================================
    # RETURN
    # =================================================
    
    return(
      
      list(
        
        graph = graph_obj,
        
        nodes = reactive({
          graph_state$nodes
        }),
        
        edges = reactive({
          graph_state$edges
        })
        
      )
    )
  })
}
