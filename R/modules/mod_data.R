# =====================================================
# MOD_DATA - FORM-BASED EDITOR (Start/Model/Nodes/Edges/Review steps)
# =====================================================
#
# Estado acumulado em reactiveValues; nao-reativo por design: nada dispara a
# reconstrucao do grafo ate o usuario clicar em "Build/Rebuild graph"
# no passo Review.

# =====================================================
# TABELAS VAZIAS
# =====================================================

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
    threshold = numeric(),
    reference = character(),
    stringsAsFactors = FALSE
  )
}

# =====================================================
# UI
# =====================================================

mod_data_ui <- function(id) {
  ns <- NS(id)

  tagList(
    uiOutput(ns("start_step")),
    uiOutput(ns("model_step")),
    uiOutput(ns("nodes_step")),
    uiOutput(ns("edges_step")),
    uiOutput(ns("review_step"))
  )
}

# =====================================================
# SERVER
# =====================================================

mod_data_server <- function(id, seed = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      schema = if (is.null(seed)) get_default_dpsir_schema() else seed$schema,
      nodes = if (is.null(seed)) create_empty_nodes_table() else seed$nodes,
      edges = if (is.null(seed)) create_empty_edges_table() else seed$edges,
      positions = NULL,
      loaded = !is.null(seed),
      start_message = "",
      graph = NULL,
      graph_message = ""
    )

    editing_node_id <- reactiveVal(NULL)
    editing_edge_index <- reactiveVal(NULL)

    # =================================================
    # STEP 1: START
    # =================================================

    output$start_step <- renderUI({
      box(
        width = 12,
        title = "Start",
        status = "primary",
        solidHeader = TRUE,

        p("Choose how to start the project."),

        fluidRow(
          column(
            width = 3,
            actionButton(ns("start_new"), "New project", icon = icon("file"), class = "btn-primary", width = "100%")
          ),
          column(
            width = 3,
            fileInput(ns("import_nodes_file"), "Import nodes (CSV)", accept = ".csv"),
            fileInput(ns("import_edges_file"), "Import edges (CSV, optional)", accept = ".csv"),
            actionButton(ns("start_import"), "Import matrices", icon = icon("upload"), width = "100%")
          ),
          column(
            width = 3,
            fileInput(ns("savepoint_file"), "Load savepoint (.idpsir.json)", accept = ".json"),
            actionButton(ns("start_savepoint"), "Load savepoint", icon = icon("folder-open"), width = "100%")
          ),
          column(
            width = 3,
            fileInput(ns("merge_files"), "Combine savepoints (2+ .idpsir.json)", accept = ".json", multiple = TRUE),
            actionButton(ns("start_merge"), "Combine savepoints", icon = icon("object-group"), width = "100%")
          )
        ),

        if (nzchar(rv$start_message)) {
          tags$div(class = "alert alert-info", style = "margin-top: 10px;", rv$start_message)
        }
      )
    })

    observeEvent(input$start_new, {
      rv$schema <- get_default_dpsir_schema()
      rv$nodes <- create_empty_nodes_table()
      rv$edges <- create_empty_edges_table()
      rv$positions <- NULL
      rv$graph <- NULL
      rv$loaded <- TRUE
      rv$start_message <- "New project started with the default DPSIR schema."
    })

    observeEvent(input$start_import, {
      req(input$import_nodes_file)

      tryCatch(
        {
          edges_path <- if (is.null(input$import_edges_file)) NULL else input$import_edges_file$datapath
          imported <- import_matrices(input$import_nodes_file$datapath, edges_path)

          validate_dpsir_nodes(imported$nodes, get_default_dpsir_schema())

          rv$schema <- get_default_dpsir_schema()
          rv$nodes <- imported$nodes
          rv$edges <- imported$edges
          rv$positions <- NULL
          rv$graph <- NULL
          rv$loaded <- TRUE
          rv$start_message <- paste0(
            "Matrices imported: ", nrow(imported$nodes), " nodes, ",
            nrow(imported$edges), " edges."
          )
        },
        error = function(e) {
          rv$start_message <- paste("Import error:", conditionMessage(e))
        }
      )
    })

    observeEvent(input$start_savepoint, {
      req(input$savepoint_file)

      tryCatch(
        {
          restored <- read_savepoint(input$savepoint_file$datapath)

          rv$schema <- restored$schema
          rv$nodes <- restored$nodes
          rv$edges <- restored$edges
          rv$positions <- restored$positions
          rv$graph <- NULL
          rv$loaded <- TRUE
          rv$start_message <- paste0(
            "Savepoint loaded: '", restored$metadata$project_name %||% "Untitled",
            "' (last updated ", restored$metadata$updated_at %||% "?", ")."
          )
        },
        error = function(e) {
          rv$start_message <- paste("Error loading savepoint:", conditionMessage(e))
        }
      )
    })

    observeEvent(input$start_merge, {
      files <- input$merge_files

      if (is.null(files) || nrow(files) < 2) {
        rv$start_message <- "Select at least two savepoint files to combine."
        return()
      }

      tryCatch(
        {
          savepoints <- lapply(files$datapath, read_savepoint)
          source_names <- sub("(\\.idpsir)?\\.json$", "", files$name, ignore.case = TRUE)
          merged <- merge_savepoints(savepoints, source_names)

          rv$schema <- merged$schema
          rv$nodes <- merged$nodes
          rv$edges <- merged$edges
          rv$positions <- NULL
          rv$graph <- NULL
          rv$loaded <- TRUE

          rename_note <- if (length(merged$renamed_ids) > 0) {
            paste0(" IDs renamed to avoid collisions: ", paste(merged$renamed_ids, collapse = ", "), ".")
          } else {
            ""
          }

          rv$start_message <- paste0(
            "Combined ", length(savepoints), " savepoints: ", nrow(merged$nodes), " nodes, ",
            nrow(merged$edges), " edges.", rename_note
          )
        },
        error = function(e) {
          rv$start_message <- paste("Error combining savepoints:", conditionMessage(e))
        }
      )
    })

    # =================================================
    # STEP 2: MODEL
    # =================================================

    output$model_step <- renderUI({
      req(rv$loaded)

      box(
        width = 12,
        title = "Model",
        status = "primary",
        solidHeader = TRUE,

        p("The default DPSIR schema is already selected. Advanced (optional): adjust the palette or add levels."),

        fluidRow(
          column(
            width = 4,
            selectInput(ns("model_palette"), "Color palette", choices = get_dpsir_palette_choices(), selected = "default")
          ),
          column(
            width = 4,
            br(),
            actionButton(ns("apply_palette"), "Apply palette", icon = icon("palette"))
          ),
          column(
            width = 4,
            br(),
            actionButton(ns("add_level"), "Add level", icon = icon("plus"))
          )
        ),

        DTOutput(ns("schema_table"))
      )
    })

    output$schema_table <- renderDT({
      req(rv$schema)

      display <- rv$schema[order(rv$schema$order), ]
      display$role <- ifelse(is.na(display$role), "-", display$role)

      datatable(
        display,
        selection = "single",
        rownames = FALSE,
        options = list(pageLength = 10, dom = "t")
      )
    })

    observeEvent(input$apply_palette, {
      rv$schema <- apply_schema_palette(rv$schema, input$model_palette)
    })

    observeEvent(input$add_level, {
      showModal(modalDialog(
        title = "Add schema level",
        textInput(ns("lvl_name"), "Level name"),
        numericInput(ns("lvl_order"), "Position (order)", value = max(rv$schema$order) + 1, step = 1),
        selectInput(ns("lvl_shape"), "Shape", choices = get_dpsir_shape_cycle()),
        checkboxInput(ns("lvl_feedback"), "Feedback level (can connect back)", value = FALSE),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_add_level"), "Add", class = "btn-primary")
        )
      ))
    })

    observeEvent(input$confirm_add_level, {
      name <- trimws(input$lvl_name)

      if (!nzchar(name) || name %in% rv$schema$name) {
        showNotification("Invalid or already existing level name.", type = "error")
        return()
      }

      new_row <- data.frame(
        name = name,
        order = input$lvl_order,
        color = "#777777",
        shape = input$lvl_shape,
        role = if (isTRUE(input$lvl_feedback)) "feedback" else NA_character_,
        stringsAsFactors = FALSE
      )

      rv$schema <- rbind(rv$schema, new_row)
      removeModal()
    })

    # =================================================
    # STEP 3: NODES
    # =================================================

    output$nodes_step <- renderUI({
      req(rv$loaded)

      box(
        width = 12,
        title = "Nodes",
        status = "primary",
        solidHeader = TRUE,

        actionButton(ns("add_node"), "Add", icon = icon("plus")),
        actionButton(ns("edit_node"), "Edit selected", icon = icon("pen")),
        actionButton(ns("remove_node"), "Remove selected", icon = icon("trash")),

        tags$hr(),
        DTOutput(ns("nodes_table"))
      )
    })

    output$nodes_table <- renderDT({
      datatable(
        rv$nodes,
        selection = "single",
        rownames = FALSE,
        options = list(pageLength = 10, scrollX = TRUE)
      )
    })

    node_modal <- function(defaults = NULL) {
      d <- defaults %||% list(
        id = "", label = "", dpsir_category = schema_categories(rv$schema)[1],
        subsystem = "", uncertainty = get_uncertainty_levels()[1],
        controllability = get_controllability_levels()[1],
        temporal_scale = get_temporal_scales()[1]
      )

      modalDialog(
        title = if (is.null(defaults)) "Add node" else "Edit node",
        textInput(ns("nm_id"), "ID", value = d$id),
        textInput(ns("nm_label"), "Label", value = d$label),
        selectInput(ns("nm_category"), "DPSIR category", choices = schema_categories(rv$schema), selected = d$dpsir_category),
        textInput(ns("nm_subsystem"), "Subsystem", value = d$subsystem),
        selectInput(ns("nm_uncertainty"), "Uncertainty", choices = get_uncertainty_levels(), selected = d$uncertainty),
        selectInput(ns("nm_controllability"), "Controllability", choices = get_controllability_levels(), selected = d$controllability),
        selectInput(ns("nm_temporal"), "Temporal scale", choices = get_temporal_scales(), selected = d$temporal_scale),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_node"), "Save", class = "btn-primary")
        )
      )
    }

    observeEvent(input$add_node, {
      editing_node_id(NULL)
      showModal(node_modal())
    })

    observeEvent(input$edit_node, {
      sel <- input$nodes_table_rows_selected
      if (is.null(sel)) {
        showNotification("Select a node in the table.", type = "warning")
        return()
      }

      row <- rv$nodes[sel, ]
      editing_node_id(row$id)
      showModal(node_modal(defaults = as.list(row)))
    })

    observeEvent(input$remove_node, {
      sel <- input$nodes_table_rows_selected
      if (is.null(sel)) {
        showNotification("Select a node in the table.", type = "warning")
        return()
      }

      removed_id <- rv$nodes$id[sel]
      rv$nodes <- rv$nodes[-sel, ]
      rv$edges <- rv$edges[rv$edges$from != removed_id & rv$edges$to != removed_id, ]
    })

    observeEvent(input$confirm_node, {
      new_id <- trimws(input$nm_id)

      if (!nzchar(new_id)) {
        showNotification("The node ID cannot be empty.", type = "error")
        return()
      }

      existing_id <- editing_node_id()
      id_conflict <- new_id %in% rv$nodes$id && !identical(new_id, existing_id)

      if (id_conflict) {
        showNotification("A node with this ID already exists.", type = "error")
        return()
      }

      new_row <- data.frame(
        id = new_id,
        label = input$nm_label,
        dpsir_category = input$nm_category,
        subsystem = input$nm_subsystem,
        uncertainty = input$nm_uncertainty,
        controllability = input$nm_controllability,
        temporal_scale = input$nm_temporal,
        stringsAsFactors = FALSE
      )

      if (is.null(existing_id)) {
        rv$nodes <- rbind(rv$nodes, new_row)
      } else {
        idx <- which(rv$nodes$id == existing_id)
        rv$nodes[idx, ] <- new_row

        if (!identical(existing_id, new_id)) {
          rv$edges$from[rv$edges$from == existing_id] <- new_id
          rv$edges$to[rv$edges$to == existing_id] <- new_id
        }
      }

      removeModal()
    })

    # =================================================
    # STEP 4: EDGES
    # =================================================

    output$edges_step <- renderUI({
      req(rv$loaded)

      box(
        width = 12,
        title = "Edges",
        status = "primary",
        solidHeader = TRUE,

        actionButton(ns("add_edge"), "Add", icon = icon("plus")),
        actionButton(ns("edit_edge"), "Edit selected", icon = icon("pen")),
        actionButton(ns("remove_edge"), "Remove selected", icon = icon("trash")),

        tags$hr(),
        DTOutput(ns("edges_table"))
      )
    })

    output$edges_table <- renderDT({
      datatable(
        rv$edges,
        selection = "single",
        rownames = FALSE,
        options = list(pageLength = 10, scrollX = TRUE)
      )
    })

    edge_modal <- function(defaults = NULL) {
      node_choices <- setNames(rv$nodes$id, paste0(rv$nodes$id, " - ", rv$nodes$label))

      d <- defaults %||% list(
        from = if (length(node_choices) > 0) node_choices[1] else "",
        to = if (length(node_choices) > 0) node_choices[1] else "",
        weight = 1, confidence = 1,
        interaction_type = get_interaction_types()[1],
        evidence_type = get_evidence_types()[1],
        threshold = NA_real_,
        reference = ""
      )

      modalDialog(
        title = if (is.null(defaults)) "Add edge" else "Edit edge",
        selectInput(ns("em_from"), "From", choices = node_choices, selected = d$from),
        selectInput(ns("em_to"), "To", choices = node_choices, selected = d$to),
        numericInput(ns("em_weight"), "Weight (> 0)", value = d$weight, min = 0.01, step = 0.5),
        numericInput(ns("em_confidence"), "Confidence (0-1)", value = d$confidence, min = 0, max = 1, step = 0.05),
        selectInput(ns("em_interaction"), "Interaction type", choices = get_interaction_types(), selected = d$interaction_type),
        selectInput(ns("em_evidence"), "Evidence type", choices = get_evidence_types(), selected = d$evidence_type),
        numericInput(ns("em_threshold"), "Threshold (optional)", value = d$threshold, min = 0, step = 0.5),
        tags$p(
          class = "text-muted", style = "font-size: 13px;",
          "Leave blank for most edges. Only used by the Scenarios tab's trajectory",
          "chart: how much the source factor has to change (in this scenario) before",
          "this edge switches on, instead of always contributing proportionally."
        ),
        textInput(ns("em_reference"), "Reference (optional)", value = d$reference, placeholder = "DOI, URL, or citation"),
        tags$p(
          class = "text-muted", style = "font-size: 13px;",
          "The evidence this link is based on - shown on hover and listed in the",
          "report, so a reader can trace any prediction back to its source."
        ),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_edge"), "Save", class = "btn-primary")
        )
      )
    }

    observeEvent(input$add_edge, {
      if (nrow(rv$nodes) == 0) {
        showNotification("Add nodes before creating edges.", type = "warning")
        return()
      }

      editing_edge_index(NULL)
      showModal(edge_modal())
    })

    observeEvent(input$edit_edge, {
      sel <- input$edges_table_rows_selected
      if (is.null(sel)) {
        showNotification("Select an edge in the table.", type = "warning")
        return()
      }

      row <- rv$edges[sel, ]
      editing_edge_index(sel)
      showModal(edge_modal(defaults = as.list(row)))
    })

    observeEvent(input$remove_edge, {
      sel <- input$edges_table_rows_selected
      if (is.null(sel)) {
        showNotification("Select an edge in the table.", type = "warning")
        return()
      }

      rv$edges <- rv$edges[-sel, ]
    })

    observeEvent(input$confirm_edge, {
      if (is.na(input$em_weight) || input$em_weight <= 0) {
        showNotification("Weight must be greater than zero.", type = "error")
        return()
      }

      if (is.na(input$em_confidence) || input$em_confidence < 0 || input$em_confidence > 1) {
        showNotification("Confidence must be between 0 and 1.", type = "error")
        return()
      }

      threshold <- input$em_threshold
      if (!is.null(threshold) && !is.na(threshold) && threshold < 0) {
        showNotification("Threshold, if set, must be zero or greater.", type = "error")
        return()
      }

      new_row <- data.frame(
        from = input$em_from,
        to = input$em_to,
        weight = input$em_weight,
        confidence = input$em_confidence,
        interaction_type = input$em_interaction,
        evidence_type = input$em_evidence,
        threshold = if (is.null(threshold)) NA_real_ else threshold,
        reference = trimws(input$em_reference %||% ""),
        stringsAsFactors = FALSE
      )

      idx <- editing_edge_index()

      if (is.null(idx)) {
        rv$edges <- rbind(rv$edges, new_row)
      } else {
        rv$edges[idx, ] <- new_row
      }

      removeModal()
    })

    # =================================================
    # STEP 5: REVIEW AND BUILD
    # =================================================

    output$review_step <- renderUI({
      req(rv$loaded)

      box(
        width = 12,
        title = "Review and build",
        status = "success",
        solidHeader = TRUE,

        tags$p(paste0(nrow(rv$nodes), " nodes, ", nrow(rv$edges), " edges.")),

        uiOutput(ns("validation_summary")),

        tags$hr(),
        actionButton(ns("build_graph"), "Build/Rebuild graph", icon = icon("play"), class = "btn-success"),

        if (nzchar(rv$graph_message)) {
          tags$div(class = "alert alert-info", style = "margin-top: 10px;", rv$graph_message)
        }
      )
    })

    output$validation_summary <- renderUI({
      messages <- character()

      node_check <- tryCatch({ validate_dpsir_nodes(rv$nodes, rv$schema); NULL }, error = function(e) conditionMessage(e))
      if (!is.null(node_check)) messages <- c(messages, node_check)

      if (is.null(node_check) && nrow(rv$edges) > 0) {
        edge_check <- tryCatch({ validate_dpsir_edges(rv$nodes, rv$edges, rv$schema); NULL }, error = function(e) conditionMessage(e))
        if (!is.null(edge_check)) messages <- c(messages, edge_check)
      }

      if (length(messages) == 0) {
        tags$div(class = "alert alert-success", "Everything is valid. Ready to build the graph.")
      } else {
        tags$div(
          class = "alert alert-warning",
          tags$strong("Issues: "),
          tags$ul(lapply(messages, tags$li))
        )
      }
    })

    observeEvent(input$build_graph, {
      tryCatch(
        {
          rv$graph <- build_igraph(rv$nodes, rv$edges, rv$schema)
          rv$graph_message <- "Graph built successfully."
        },
        error = function(e) {
          rv$graph <- NULL
          rv$graph_message <- paste("Error building the graph:", conditionMessage(e))
        }
      )
    })

    # =================================================
    # RETURN
    # =================================================

    list(
      schema = reactive(rv$schema),
      nodes = reactive(rv$nodes),
      edges = reactive(rv$edges),
      positions = reactive(rv$positions),
      set_positions = function(pos) { rv$positions <- pos },
      graph = reactive(rv$graph),
      loaded = reactive(rv$loaded)
    )
  })
}
