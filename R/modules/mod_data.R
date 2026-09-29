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
    uncertainty = numeric(),
    controllability = numeric(),
    self_regulation = numeric(),
    growth_rate = numeric(),
    growth_cap = numeric(),
    reference_value = numeric(),
    sd = numeric(),
    threshold_level = numeric(),
    threshold_direction = character(),
    descriptor = character(),
    endpoint_class = character(),
    value_v = numeric(),
    stringsAsFactors = FALSE
  )
}

create_empty_edges_table <- function() {
  data.frame(
    from = character(),
    to = character(),
    weight = numeric(),
    weight_low = numeric(),
    weight_high = numeric(),
    strength_class = character(),
    weight_source = character(),
    confidence = numeric(),
    interaction_type = character(),
    evidence_type = character(),
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

# Any of the 5 step renders below can throw for reasons this app doesn't
# control - e.g. a different bs4Dash/shiny/fontawesome version on the
# user's machine than the one this was last tested against (global.R only
# checks packages are PRESENT, never pins a version - see CLAUDE.md,
# "app nao abre uniforme em todos os computadores"). Shiny's default
# failure mode for a broken renderUI is a single thin gray line of text
# sitting right where the step content should be, easy to miss entirely
# next to the Back/Save/Next buttons that keep rendering fine below it -
# a user can genuinely perceive that as "the step is just blank". Wrapping
# every step in this instead surfaces one large, unmissable alert with the
# exact R error message, so a report like "the Start step shows nothing"
# turns into an actionable one-liner instead of an unreproducible mystery.
render_step_error <- function(e) {
  tags$div(
    class = "alert alert-danger",
    tags$strong("This step could not be displayed."),
    tags$p(conditionMessage(e)),
    tags$p(
      class = "text-muted", style = "font-size: 12px;",
      "This usually means an R package on this computer is a different version than the app expects. ",
      "Reloading the page is unlikely to fix it on its own - please copy the exact message above when reporting this."
    )
  )
}

mod_data_server <- function(id, seed = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      schema = if (is.null(seed)) get_default_dpsir_schema() else seed$schema,
      nodes = if (is.null(seed)) create_empty_nodes_table() else seed$nodes,
      edges = if (is.null(seed)) create_empty_edges_table() else seed$edges,
      positions = NULL,
      scenario_state = NULL,
      # Revisao 1 (guia externo sobre o relatorio como material
      # suplementar): provenance header do relatorio precisa do nome/autor/
      # notas do savepoint carregado e do nome do arquivo em si - nenhum dos
      # dois tinha um lugar pra viver depois de carregado (`metadata` de um
      # savepoint restaurado so' alimentava a notificacao transiente do
      # Start). NULL em qualquer modo sem um unico arquivo de origem (New
      # project/Import CSV/Combine savepoints) - o cabecalho so' preenche o
      # que existir.
      metadata = NULL,
      savepoint_filename = NULL,
      loaded = !is.null(seed),
      start_message = "",
      start_blocking = character(),
      start_warnings = character(),
      graph = NULL,
      graph_message = "",
      # Revisao 2, item 0.2: incremented on every successful Start action
      # (new/import/savepoint/merge) - the other modules watch it and clear
      # their own per-project state (saved scenarios, snapshots, ...), which
      # otherwise leaked from project A into project B's report.
      epoch = 0,
      # Revisao 2, item 0.3: incremented each time a graph is built on top of
      # a network that changed since the previous build (rv$graph was NULL).
      # Saved scenarios hold press vectors and results computed on the old
      # network, so mod_responses clears them when this moves.
      graph_version = 0
    )

    editing_node_id <- reactiveVal(NULL)
    editing_edge_index <- reactiveVal(NULL)

    # =================================================
    # STEP 1: START
    # =================================================

    # Each of the four starting modes is rendered as a uniform card (icon,
    # title, one-line description, optional file input(s), button pinned to
    # the same baseline via the "flex: 1" spacer) instead of a bare button
    # next to three columns with file inputs above them - the mismatch made
    # "New project" look unfinished next to the other three.
    start_card <- function(icon_name, title, description, inputs = NULL, button) {
      tags$div(
        style = "height: 100%; display: flex; flex-direction: column; border: 1px solid #dee2e6; border-radius: 4px; padding: 14px;",
        icon(icon_name, style = "font-size: 20px; color: #6c757d;"),
        tags$p(title, style = "font-weight: 600; margin: 10px 0 4px;"),
        tags$p(description, style = "font-size: 12.5px; color: #6c757d; margin: 0 0 8px;"),
        inputs,
        tags$div(style = "flex: 1;"),
        button
      )
    }

    output$start_step <- renderUI({
      tryCatch({
      box(
        width = 12,
        title = "Start",
        status = "primary",
        solidHeader = TRUE,

        p("Choose how to start the project."),

        fluidRow(
          column(
            width = 3,
            start_card(
              "file", "New project",
              "Start from a blank network and add nodes and edges by hand.",
              button = actionButton(ns("start_new"), "New project", icon = icon("file"), class = "btn-primary", width = "100%")
            )
          ),
          column(
            width = 3,
            start_card(
              "upload", "Import CSV files",
              "Already have nodes and edges in spreadsheets? Upload them.",
              inputs = tagList(
                fileInput(ns("import_nodes_file"), "Nodes (CSV)", accept = ".csv"),
                fileInput(ns("import_edges_file"), "Edges (CSV, optional)", accept = ".csv"),
                checkboxInput(ns("import_convert_legacy"), "Convert from older relative weights", value = FALSE)
              ),
              button = actionButton(ns("start_import"), "Import matrices", icon = icon("upload"), width = "100%")
            )
          ),
          column(
            width = 3,
            start_card(
              "folder-open", "Load savepoint",
              "Resume a project you saved earlier as a .idpsir.json file.",
              inputs = fileInput(ns("savepoint_file"), ".idpsir.json file", accept = ".json"),
              button = actionButton(ns("start_savepoint"), "Load savepoint", icon = icon("folder-open"), width = "100%")
            )
          ),
          column(
            width = 3,
            start_card(
              "object-group", "Combine savepoints",
              "Merge two or more saved projects into one network.",
              inputs = fileInput(ns("merge_files"), ".idpsir.json files (2+)", accept = ".json", multiple = TRUE),
              button = actionButton(ns("start_merge"), "Combine savepoints", icon = icon("object-group"), width = "100%")
            )
          )
        ),

        if (nzchar(rv$start_message)) {
          tags$div(
            class = if (length(rv$start_blocking) > 0) "alert alert-danger" else "alert alert-info",
            style = "margin-top: 10px;",
            rv$start_message
          )
        },
        if (length(rv$start_blocking) > 0) {
          tags$div(
            class = "alert alert-danger", style = "margin-top: -4px;",
            tags$strong("What needs fixing:"),
            tags$ul(lapply(rv$start_blocking, tags$li))
          )
        },
        if (length(rv$start_warnings) > 0) {
          tags$div(
            class = "alert alert-warning", style = "margin-top: -4px;",
            tags$strong("Imported, but note:"),
            tags$ul(lapply(rv$start_warnings, tags$li))
          )
        }
      )
      }, error = render_step_error)
    })
    # Step 1 is the only step that is ALREADY visible the instant the page
    # connects - it never transitions from hidden to shown the way steps
    # 2-6 do on a real "Next" click. Shiny's suspendWhenHidden (default
    # TRUE) only computes an output once the client reports a hidden ->
    # visible transition for it; an output that starts visible has no such
    # transition to report, and on some client/timing combinations the
    # very first visibility report race-loses against the server's first
    # reactive flush, leaving the output suspended forever with no error -
    # matches a live debug session where every module server finished
    # initializing (logged) but "start_step: render begin" never printed
    # at all. Forcing it to always compute sidesteps that race entirely.
    outputOptions(output, "start_step", suspendWhenHidden = FALSE)

    observeEvent(input$start_new, {
      rv$schema <- get_default_dpsir_schema()
      rv$nodes <- create_empty_nodes_table()
      rv$edges <- create_empty_edges_table()
      rv$positions <- NULL
      rv$scenario_state <- NULL
      rv$metadata <- NULL
      rv$savepoint_filename <- NULL
      rv$graph <- NULL
      rv$start_blocking <- character()
      rv$start_warnings <- character()
      rv$loaded <- TRUE
      rv$epoch <- rv$epoch + 1
      rv$start_message <- "New project started with the default DPSIR schema."
    })

    observeEvent(input$start_import, {
      req(input$import_nodes_file)

      rv$start_blocking <- character()
      rv$start_warnings <- character()

      tryCatch(
        {
          edges_path <- if (is.null(input$import_edges_file)) NULL else input$import_edges_file$datapath

          nodes_raw <- data.table::fread(input$import_nodes_file$datapath)
          edges_raw <- if (is.null(edges_path)) NULL else data.table::fread(edges_path)

          # Preflight runs on the RAW columns/values, before
          # normalize_dpsir_nodes()/normalize_dpsir_edges() silently fill in
          # defaults for anything missing - a spreadsheet with a renamed
          # column, an out-of-vocabulary value, or a non-numeric weight would
          # otherwise be accepted as-is (or fail much later with a confusing
          # graph-building error) instead of being caught right here.
          preflight <- preflight_import(nodes_raw, edges_raw, get_default_dpsir_schema())

          if (length(preflight$blocking) > 0) {
            rv$start_blocking <- preflight$blocking
            rv$start_message <- "Import blocked: the file(s) don't match the expected format."
            return(invisible(NULL))
          }

          imported <- import_matrices(
            input$import_nodes_file$datapath, edges_path,
            convert_legacy = isTRUE(input$import_convert_legacy)
          )

          validate_dpsir_nodes(imported$nodes, get_default_dpsir_schema())

          rv$schema <- get_default_dpsir_schema()
          rv$nodes <- imported$nodes
          rv$edges <- imported$edges
          rv$positions <- NULL
          rv$scenario_state <- NULL
          rv$metadata <- NULL
          rv$savepoint_filename <- NULL
          rv$graph <- NULL
          rv$loaded <- TRUE
          rv$epoch <- rv$epoch + 1
          rv$start_warnings <- c(
            if (isTRUE(input$import_convert_legacy)) preflight$warnings[!grepl("is above 1 - unusual", preflight$warnings)] else preflight$warnings,
            legacy_conversion_notes(imported$conversion)
          )
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

      rv$start_blocking <- character()
      rv$start_warnings <- character()

      tryCatch(
        {
          restored <- read_savepoint(input$savepoint_file$datapath)

          rv$schema <- restored$schema
          rv$nodes <- restored$nodes
          rv$edges <- restored$edges
          rv$positions <- restored$positions
          rv$scenario_state <- restored$scenario_state
          rv$metadata <- restored$metadata
          rv$savepoint_filename <- input$savepoint_file$name
          rv$start_warnings <- restored$warnings
          rv$graph <- NULL
          rv$loaded <- TRUE
          rv$epoch <- rv$epoch + 1
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

      rv$start_blocking <- character()
      rv$start_warnings <- character()

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
          rv$scenario_state <- NULL
          rv$metadata <- NULL
          rv$savepoint_filename <- NULL
          rv$graph <- NULL
          rv$loaded <- TRUE
          rv$epoch <- rv$epoch + 1

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

      tryCatch({
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
      }, error = render_step_error)
    })
    outputOptions(output, "model_step", suspendWhenHidden = FALSE)

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

      tryCatch({
      box(
        width = 12,
        title = "Nodes",
        status = "primary",
        solidHeader = TRUE,

        actionButton(ns("add_node"), "Add", icon = icon("plus")),
        actionButton(ns("edit_node"), "Edit selected", icon = icon("pen")),
        actionButton(ns("remove_node"), "Remove selected", icon = icon("trash")),
        # Revisao 2, item B2: swing weights for the value of service/welfare Impacts.
        actionButton(ns("elicit_values"), "Elicit values (swing weights)", icon = icon("scale-balanced")),

        tags$hr(),
        DTOutput(ns("nodes_table"))
      )
      }, error = render_step_error)
    })
    outputOptions(output, "nodes_step", suspendWhenHidden = FALSE)

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
        subsystem = "", uncertainty = 0.5, controllability = 0.5,
        self_regulation = DEFAULT_SELF_REGULATION, growth_rate = 0, growth_cap = NA_real_, reference_value = NA_real_,
        sd = NA_real_, threshold_level = NA_real_, threshold_direction = "auto", descriptor = "",
        endpoint_class = "ecological", value_v = 1
      )
      # Revisao 2, item 2.6: panels follow the level's role, not its name.
      role_condition <- function(role) {
        cats <- categories_with_role(role, rv$schema)
        if (length(cats) == 0) return("false")
        paste(sprintf("input['%s'] == '%s'", ns("nm_category"), gsub("'", "\\'", cats)), collapse = " || ")
      }
      impact_panel <- role_condition("impact")
      state_panel <- role_condition("state")
      num_or_na <- function(x) if (is.null(x) || length(x) == 0 || is.na(x)) NA else x
      value_panel <- sprintf("(%s) && input['%s'] != 'ecological'", impact_panel, ns("nm_endpoint_class"))

      modalDialog(
        title = if (is.null(defaults)) "Add node" else "Edit node",
        textInput(ns("nm_id"), "ID", value = d$id),
        textInput(ns("nm_label"), "Label", value = d$label),
        selectInput(ns("nm_category"), "DPSIR category", choices = schema_categories(rv$schema), selected = d$dpsir_category),
        textInput(ns("nm_subsystem"), "Subsystem", value = d$subsystem),
        numericInput(
          ns("nm_uncertainty"), "Uncertainty (0-1)",
          value = d$uncertainty %||% 0.5, min = 0, max = 1, step = 0.1
        ),
        numericInput(
          ns("nm_controllability"), "Controllability (0-1)",
          value = d$controllability %||% 0.5, min = 0, max = 1, step = 0.1
        ),
        numericInput(
          ns("nm_self_regulation"), "Self-regulation (0-1)",
          value = d$self_regulation %||% DEFAULT_SELF_REGULATION, min = 0, max = 1, step = 0.05
        ),
        tags$p(
          class = "text-muted", style = "font-size: 12px;",
          "Share of this factor's deviation that fades by itself each window: 0 = accumulates like a stock",
          "(nothing recovers), 1 = no memory (reflects only what arrives in the window). Default 0.5."
        ),
        # Revisao 2, item A8: guide (Anexo X4 of the roadmap).
        tags$table(
          class = "table table-sm", style = "font-size: 11.5px; margin-bottom: 8px;",
          tags$thead(tags$tr(tags$th("Self-regulation"), tags$th("Half-life"), tags$th("Build-up at equilibrium"), tags$th("Typical of"))),
          tags$tbody(
            tags$tr(tags$td("0.05"), tags$td("13.5 windows"), tags$td("20x"), tags$td("contaminant in sediment")),
            tags$tr(tags$td("0.10"), tags$td("6.6 windows"), tags$td("10x"), tags$td("reef recovery, long-lived species")),
            tags$tr(tags$td("0.30"), tags$td("1.9 windows"), tags$td("3x"), tags$td("short-cycle fish stock")),
            tags$tr(tags$td("0.50 (default)"), tags$td("1 window"), tags$td("2x"), tags$td("water quality that renews quickly")),
            tags$tr(tags$td("1"), tags$td("-"), tags$td("1x"), tags$td("monthly income, catch in the window"))
          )
        ),
        fluidRow(
          column(6, numericInput(
            ns("nm_growth_rate"), "Growth rate per window (optional)",
            value = d$growth_rate %||% 0, step = 0.01
          )),
          column(6, numericInput(
            ns("nm_growth_cap"), "Growth ceiling (optional, own units)",
            value = num_or_na(d$growth_cap), min = 0, step = 1
          ))
        ),
        tags$p(
          class = "text-muted", style = "font-size: 12px;",
          "Leave at 0 for most factors. Only used by the Scenarios tab's discrete-window",
          "simulation: how this factor's base level moves by itself each window (e.g. population",
          "growth, a rising consumption trend), in both the baseline and the scenario, whether or not",
          "the factor is in the scenario. Self-regulation is different: it is how a deviation caused",
          "by the network fades. The ceiling stops the base level at that value (e.g. a licence cap",
          "on the fleet); it needs the initial level."
        ),
        # Revisao 2, item C0 (D23): measurement layer, in the factor's own units.
        tags$h6("Measurement (optional)", style = "margin-top: 10px;"),
        fluidRow(
          column(6, numericInput(ns("nm_reference_value"), "Initial level (reference value)", value = num_or_na(d$reference_value), min = 0, step = 0.5)),
          column(6, numericInput(ns("nm_sd"), "Typical variation (SD)", value = num_or_na(d$sd), min = 0, step = 0.1))
        ),
        numericInput(ns("nm_cv"), "...or typical variation as CV (% of the initial level)", value = NA, min = 0, step = 1),
        tags$p(
          class = "text-muted", style = "font-size: 12px;",
          "Leave blank unless you want results in this factor's own units or a threshold on it. The model works in",
          "standard deviations: the typical variation converts real units into the model's units and back."
        ),
        conditionalPanel(
          condition = state_panel,
          fluidRow(
            column(6, numericInput(ns("nm_threshold_level"), "Threshold level (State only)", value = num_or_na(d$threshold_level), step = 0.5)),
            column(6, selectInput(ns("nm_threshold_direction"), "Direction",
                                  choices = c("From the level (below = falling, above = rising)" = "auto", "Either direction" = "both"),
                                  selected = if (is.null(d$threshold_direction) || is.na(d$threshold_direction)) "auto" else d$threshold_direction))
          ),
          tags$p(
            class = "text-muted", style = "font-size: 12px;",
            "Activation threshold, in this factor's own units: the State only passes its effect on (all its outgoing",
            "links together) once it crosses this level - e.g. a fish stock collapse point below the initial level, or a",
            "legal limit for a contaminant above it. Needs the initial level and, ideally, the typical variation."
          )
        ),
        # Revisao 2, item B1: only for Impact factors (specification V1).
        conditionalPanel(
          condition = impact_panel,
          selectInput(
            ns("nm_endpoint_class"), "Endpoint class (Impact)",
            choices = c("Ecological" = "ecological", "Ecosystem service" = "service", "Human welfare" = "welfare"),
            selected = if (is.null(d$endpoint_class) || is.na(d$endpoint_class)) "ecological" else d$endpoint_class
          ),
          conditionalPanel(
            condition = value_panel,
            numericInput(ns("nm_value_v"), "Social value v (0-1)",
                         value = if (is.null(d$value_v) || is.na(d$value_v)) 1 else d$value_v, min = 0, max = 1, step = 0.05)
          ),
          tags$p(
            class = "text-muted", style = "font-size: 12px;",
            "Used to prioritize Impacts. An ecological endpoint always has value 1; for a service or welfare",
            "endpoint, v says how much it matters (\"Elicit values\" on the Nodes step helps set it)."
          )
        ),
        textAreaInput(
          ns("nm_descriptor"), "Descriptor (optional)",
          value = d$descriptor %||% "", rows = 2,
          placeholder = "A short, plain-language description of what this factor represents"
        ),
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_node"), "Save", class = "btn-primary")
        )
      )
    }

    # Revisao 2, item B2 (specification V1): swing weights. The user rates,
    # for each service/welfare Impact, how much it matters to take it from
    # its worst to its best level - 100 for the most important, 0-100 for the
    # others; the app stores the rating / 100 as value_v.
    swing_ids <- reactive({
      n <- normalize_dpsir_nodes(rv$nodes, rv$schema)
      n$id[roles_of(n$dpsir_category, rv$schema) %in% "impact" & n$endpoint_class %in% c("service", "welfare")]
    })

    observeEvent(input$elicit_values, {
      ids <- swing_ids()
      if (length(ids) == 0) {
        showNotification("No service or welfare Impacts yet - set an Impact's endpoint class first (Edit selected).", type = "warning")
        return()
      }
      n <- normalize_dpsir_nodes(rv$nodes, rv$schema)
      rows <- lapply(ids, function(id) {
        i <- match(id, n$id)
        numericInput(ns(paste0("swing_", i)), n$label[i], value = round(100 * (n$value_v[i] %||% 1)), min = 0, max = 100, step = 5)
      })
      showModal(modalDialog(
        title = "Elicit values (swing weights)",
        tags$p(
          "Imagine each Impact below moving from its worst to its best plausible level. Give 100 to the move",
          "that matters most, and 0-100 to each of the others in proportion. The value v stored is your rating / 100."
        ),
        rows,
        footer = tagList(modalButton("Cancel"), actionButton(ns("confirm_swing"), "Save values", class = "btn-primary"))
      ))
    })

    observeEvent(input$confirm_swing, {
      ids <- swing_ids()
      n <- rv$nodes
      for (id in ids) {
        i <- match(id, n$id)
        val <- suppressWarnings(as.numeric(input[[paste0("swing_", match(id, normalize_dpsir_nodes(rv$nodes, rv$schema)$id))]]))
        if (is.na(val) || val < 0 || val > 100) {
          showNotification("Each rating must be between 0 and 100.", type = "error")
          return()
        }
        n$value_v[i] <- val / 100
      }
      rv$nodes <- normalize_dpsir_nodes(n, rv$schema)
      removeModal()
      showNotification("Values saved.", type = "message")
    })

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

      self_regulation <- input$nm_self_regulation
      if (is.na(self_regulation) || self_regulation < 0 || self_regulation > 1) {
        showNotification("Self-regulation must be between 0 and 1.", type = "error")
        return()
      }

      value_v <- input$nm_value_v %||% 1
      is_impact_cat <- identical(roles_of(input$nm_category, rv$schema), "impact")
      if (is_impact_cat && !identical(input$nm_endpoint_class, "ecological") &&
          (is.na(value_v) || value_v < 0 || value_v > 1)) {
        showNotification("The social value v must be between 0 and 1.", type = "error")
        return()
      }
      if (identical(input$nm_endpoint_class, "ecological")) value_v <- 1

      # Revisao 2, item C0: measurement layer.
      num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else suppressWarnings(as.numeric(x))
      reference_value <- num(input$nm_reference_value)
      if (!is.na(reference_value) && reference_value <= 0) {
        showNotification("The initial level must be greater than 0 (or left blank).", type = "error")
        return()
      }
      sd_value <- num(input$nm_sd)
      cv <- num(input$nm_cv)
      if (is.na(sd_value) && !is.na(cv)) {
        if (is.na(reference_value)) {
          showNotification("A CV needs the initial level (reference value) to be converted.", type = "error")
          return()
        }
        sd_value <- cv / 100 * reference_value
      }
      if (!is.na(sd_value) && sd_value <= 0) {
        showNotification("The typical variation must be greater than 0 (or left blank).", type = "error")
        return()
      }
      growth_rate <- num(input$nm_growth_rate)
      if (is.na(growth_rate)) growth_rate <- 0
      if (growth_rate <= -1) {
        showNotification("The growth rate must be greater than -1 (the base level would change sign).", type = "error")
        return()
      }
      if (growth_rate > 0.5) {
        showNotification("A growth rate above 0.5 per window is unusual - check the window length.", type = "warning")
      }
      growth_cap <- num(input$nm_growth_cap)
      if (!is.na(growth_cap) && growth_cap <= 0) {
        showNotification("The growth ceiling must be greater than 0 (or left blank).", type = "error")
        return()
      }
      threshold_level <- if (identical(roles_of(input$nm_category, rv$schema), "state")) num(input$nm_threshold_level) else NA_real_
      if (!is.na(threshold_level) && is.na(reference_value)) {
        showNotification("A threshold level needs the initial level (reference value).", type = "error")
        return()
      }

      new_row <- data.frame(
        id = new_id,
        label = input$nm_label,
        dpsir_category = input$nm_category,
        subsystem = input$nm_subsystem,
        uncertainty = input$nm_uncertainty,
        controllability = input$nm_controllability,
        self_regulation = self_regulation,
        growth_rate = growth_rate,
        growth_cap = growth_cap,
        reference_value = reference_value,
        sd = sd_value,
        threshold_level = threshold_level,
        threshold_direction = if (is.na(threshold_level)) NA_character_ else (input$nm_threshold_direction %||% "auto"),
        descriptor = trimws(input$nm_descriptor %||% ""),
        endpoint_class = if (is_impact_cat) input$nm_endpoint_class %||% "ecological" else NA_character_,
        value_v = if (is_impact_cat) value_v else NA_real_,
        stringsAsFactors = FALSE
      )

      if (is.null(existing_id)) {
        rv$nodes <- normalize_dpsir_nodes(dplyr::bind_rows(rv$nodes, new_row), rv$schema)
      } else {
        idx <- which(rv$nodes$id == existing_id)
        # Assign by name, not position: rv$nodes may have its columns in a
        # different order than new_row (e.g. a savepoint whose optional
        # columns were appended in a different sequence by
        # normalize_dpsir_nodes()) - a positional `rv$nodes[idx, ] <- new_row`
        # would silently shift values into the wrong column when the order
        # differs, even though the column names/counts match (same bug class
        # already found and fixed for the now-dropped temporal_scale column).
        rv$nodes[idx, names(new_row)] <- new_row

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

      tryCatch({
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
      }, error = render_step_error)
    })
    outputOptions(output, "edges_step", suspendWhenHidden = FALSE)

    output$edges_table <- renderDT({
      datatable(
        rv$edges,
        selection = "single",
        rownames = FALSE,
        options = list(pageLength = 10, scrollX = TRUE)
      )
    })

    # Revisao 2, item 1.2: an edge's strength is entered as a class (Weak /
    # Moderate / Strong - the default for users without data) or as a value:
    # beta directly, or r^2 as a shortcut (|beta| = sqrt(r^2)), optionally
    # with n (the band then comes from the standard error) or an explicit
    # band. Substitute groups and priorities follow Anexo X6 of the roadmap.
    edge_modal <- function(defaults = NULL) {
      node_choices <- setNames(rv$nodes$id, paste0(rv$nodes$id, " - ", rv$nodes$label))

      d <- defaults %||% list(
        from = if (length(node_choices) > 0) node_choices[1] else "",
        to = if (length(node_choices) > 0) node_choices[1] else "",
        weight = NA_real_, weight_low = NA_real_, weight_high = NA_real_,
        strength_class = DEFAULT_STRENGTH_CLASS, weight_source = "class",
        interaction_type = get_interaction_types()[1],
        evidence_type = get_evidence_types()[1],
        reference = ""
      )
      mode <- if (identical(d$weight_source, "class") || identical(d$weight_source, "default")) {
        d$strength_class %||% DEFAULT_STRENGTH_CLASS
      } else {
        "value"
      }
      value_panel <- sprintf("input['%s'] == 'value'", ns("em_strength_mode"))
      cls <- strength_classes()

      modalDialog(
        title = if (is.null(defaults)) "Add edge" else "Edit edge",
        selectInput(ns("em_from"), "From", choices = node_choices, selected = d$from),
        selectInput(ns("em_to"), "To", choices = node_choices, selected = d$to),
        selectInput(ns("em_interaction"), "Sign (interaction type)", choices = get_interaction_types(), selected = d$interaction_type),
        selectInput(
          ns("em_strength_mode"), "Strength",
          choices = c(setNames(cls$class, sprintf("%s (%.2f, range %.2f-%.2f)", cls$label, cls$value, cls$low, cls$high)),
                      "I have a value" = "value"),
          selected = mode
        ),
        tags$p(
          class = "text-muted", style = "font-size: 12px;",
          "Strength = how many standard deviations the target changes when this factor changes by one.",
          "No data? Pick a class - Moderate is the default. The class range is the uncertainty used in the confidence readings."
        ),
        conditionalPanel(
          condition = value_panel,
          numericInput(ns("em_beta"), "Strength (beta, > 0)", value = if (identical(mode, "value")) d$weight else NA, min = 0, step = 0.05),
          tags$p(class = "text-muted", style = "font-size: 12px;", "Or, instead of beta:"),
          fluidRow(
            column(6, numericInput(ns("em_r2"), "r squared (0-1)", value = NA, min = 0, max = 1, step = 0.05)),
            column(6, numericInput(ns("em_n"), "n (sample size, optional)", value = NA, min = 3, step = 1))
          ),
          tags$p(class = "text-muted", style = "font-size: 12px;", "Uncertainty range (optional - otherwise from r squared and n, or from the class of the value):"),
          fluidRow(
            column(6, numericInput(ns("em_low"), "Lowest plausible", value = if (identical(mode, "value")) d$weight_low else NA, min = 0, step = 0.05)),
            column(6, numericInput(ns("em_high"), "Highest plausible", value = if (identical(mode, "value")) d$weight_high else NA, min = 0, step = 0.05))
          )
        ),
        selectInput(ns("em_evidence"), "Evidence type", choices = get_evidence_types(), selected = d$evidence_type),
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
      mode <- input$em_strength_mode %||% DEFAULT_STRENGTH_CLASS
      num <- function(x) if (is.null(x) || length(x) == 0) NA_real_ else suppressWarnings(as.numeric(x))

      weight <- NA_real_
      low <- NA_real_
      high <- NA_real_
      strength_class <- NA_character_
      weight_source <- "class"

      if (identical(mode, "value")) {
        beta <- num(input$em_beta)
        r2 <- num(input$em_r2)
        n <- num(input$em_n)
        low <- num(input$em_low)
        high <- num(input$em_high)

        if (!is.na(r2) && (r2 <= 0 || r2 > 1)) {
          showNotification("r squared must be above 0 and at most 1.", type = "error")
          return()
        }
        if (!is.na(beta)) {
          weight <- beta
          if (!is.na(r2)) showNotification("Both beta and r squared were given - beta was used.", type = "message")
        } else if (!is.na(r2)) {
          weight <- beta_from_r2(r2)
        } else {
          showNotification("Enter a strength (beta) or an r squared, or pick a class.", type = "error")
          return()
        }
        if (weight <= 0) {
          showNotification("Strength must be greater than zero.", type = "error")
          return()
        }
        if (is.na(low) && is.na(high) && !is.na(r2) && !is.na(n)) {
          if (n <= 2) {
            showNotification("n must be at least 3.", type = "error")
            return()
          }
          band <- band_from_r2_n(r2, n)
          low <- min(band[["low"]], weight)
          high <- max(band[["high"]], weight)
        } else if (xor(is.na(low), is.na(high))) {
          showNotification("Give both ends of the uncertainty range, or neither.", type = "error")
          return()
        } else if (!is.na(low) && (low > weight || high < weight || low < 0)) {
          showNotification("The uncertainty range must contain the strength.", type = "error")
          return()
        }
        if (weight > 1) {
          showNotification("A strength above 1 is unusual for a standardized coefficient - check the value.", type = "warning")
        }
        weight_source <- "given"
      } else {
        strength_class <- mode
      }

      new_row <- data.frame(
        from = input$em_from,
        to = input$em_to,
        weight = weight,
        weight_low = low,
        weight_high = high,
        strength_class = strength_class,
        weight_source = weight_source,
        interaction_type = input$em_interaction,
        evidence_type = input$em_evidence,
        reference = trimws(input$em_reference %||% ""),
        stringsAsFactors = FALSE
      )
      # Fills the class value/band and the derived fields for this row.
      new_row <- normalize_dpsir_edges(new_row)

      idx <- editing_edge_index()

      if (is.null(idx)) {
        rv$edges <- normalize_dpsir_edges(dplyr::bind_rows(rv$edges, new_row))
      } else {
        # Assign by name, not position - see the matching comment on the
        # node edit above (real column-order bug found live in Fase 5).
        rv$edges[idx, names(new_row)] <- new_row
      }

      removeModal()
    })

    # =================================================
    # STEP 5: REVIEW AND BUILD
    # =================================================

    output$review_step <- renderUI({
      req(rv$loaded)

      tryCatch({
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
      }, error = render_step_error)
    })
    outputOptions(output, "review_step", suspendWhenHidden = FALSE)

    output$validation_summary <- renderUI({
      messages <- character()

      node_check <- tryCatch({ validate_dpsir_nodes(rv$nodes, rv$schema); NULL }, error = function(e) conditionMessage(e))
      if (!is.null(node_check)) messages <- c(messages, node_check)

      if (is.null(node_check) && nrow(rv$edges) > 0) {
        edge_check <- tryCatch({ validate_dpsir_edges(rv$nodes, rv$edges, rv$schema); NULL }, error = function(e) conditionMessage(e))
        if (!is.null(edge_check)) messages <- c(messages, edge_check)
      }

      # Revisao 2, Fase 1: informational notes about edge strengths - how
      # many edges rely on a class or default value, which ones need review
      # after a conversion, and nodes whose incoming betas explain > 100%.
      notes <- character()
      if (length(messages) == 0 && nrow(rv$edges) > 0) {
        e <- normalize_dpsir_edges(rv$edges)
        n_assumed <- sum(e$weight_source %in% c("class", "default"))
        if (n_assumed > 0) {
          notes <- c(notes, sprintf(
            "%d of %d edges use a strength class or the default ('moderate', 0.45) instead of a value - results are qualitative for those links.",
            n_assumed, nrow(e)
          ))
        }
        review <- e$weight_source == "converted" & e$weight > 1
        if (any(review)) {
          notes <- c(notes, sprintf(
            "Review the strength of these converted edges (above 1): %s.",
            paste(sprintf("%s -> %s", e$from[review], e$to[review]), collapse = ", ")
          ))
        }
        notes <- c(notes, explained_variance_warnings(normalize_dpsir_nodes(rv$nodes, rv$schema), e))
      }
      if (length(messages) == 0) notes <- c(notes, self_regulation_warnings(normalize_dpsir_nodes(rv$nodes, rv$schema)), growth_warnings(normalize_dpsir_nodes(rv$nodes, rv$schema)))
      if (length(messages) == 0) {
        notes <- c(notes, tryCatch(
          threshold_warnings(build_igraph(rv$nodes, rv$edges, rv$schema)),
          error = function(e) character()
        ))
      }

      tagList(
        if (length(messages) == 0) {
          tags$div(class = "alert alert-success", "Everything is valid. Ready to build the graph.")
        } else {
          tags$div(
            class = "alert alert-warning",
            tags$strong("Issues: "),
            tags$ul(lapply(messages, tags$li))
          )
        },
        if (length(notes) > 0) {
          tags$div(class = "alert alert-info", tags$ul(lapply(notes, tags$li)))
        }
      )
    })

    # Revisao 2, item 0.1: the Graph tab draws nodes()/edges() live, but
    # Metrics/Scenarios/Report all read graph(), frozen at the last "Build" -
    # removing a node after building left them still counting it. Any edit
    # to the network now drops the built graph, so step 5's Next guard (and
    # Explore) require a rebuild. Start actions already set rv$graph to NULL
    # themselves in the same flush, so the `!is.null()` check keeps this from
    # overwriting their own message.
    observeEvent(list(rv$nodes, rv$edges, rv$schema), {
      if (!is.null(rv$graph)) {
        rv$graph <- NULL
        rv$graph_message <- "The network changed since the graph was built - rebuild it in step 5 (Review and build)."
      }
    }, ignoreInit = TRUE)

    observeEvent(input$build_graph, {
      tryCatch(
        {
          was_stale <- is.null(rv$graph)
          built <- build_igraph(rv$nodes, rv$edges, rv$schema)
          # Revisao 2, item 1.3: the total effect only exists when rho(B) < 1.
          check_effect_matrix(built)
          rv$graph <- built
          if (was_stale) rv$graph_version <- rv$graph_version + 1
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
      scenario_state = reactive(rv$scenario_state),
      metadata = reactive(rv$metadata),
      savepoint_filename = reactive(rv$savepoint_filename),
      graph = reactive(rv$graph),
      loaded = reactive(rv$loaded),
      epoch = reactive(rv$epoch),
      graph_version = reactive(rv$graph_version)
    )
  })
}
