# =====================================================
# SCHEMA - DPSIR CONFIGURAVEL
# =====================================================
#
# Um "schema" e um data.frame de niveis (name, order, color, shape, role).
# `role = "feedback"` marca niveis que, alem de conectar ao proximo nivel na
# ordem, tambem podem conectar de volta a qualquer nivel anterior (o papel
# que o Response tem no DPSIR canonico). As conexoes permitidas e o layout em
# camadas sao sempre derivados dessa tabela, nunca fixados em codigo.

# =====================================================
# PALETAS DE COR E FORMAS
# =====================================================

get_dpsir_color_palettes <- function() {
  list(
    # Revisao 2, item 3.11: Okabe-Ito (colorblind safe) is the default.
    default = c("#0072B2", "#D55E00", "#009E73", "#E69F00", "#CC79A7"),
    classic = c("#1f77b4", "#d62728", "#2ca02c", "#ff7f0e", "#9467bd"),
    muted = c("#4E79A7", "#E15759", "#59A14F", "#F28E2B", "#B07AA1"),
    high_contrast = c("#0050A4", "#B00020", "#00843D", "#C75B12", "#6A1B9A")
  )
}

get_dpsir_palette_choices <- function() {
  c(
    "Okabe-Ito, colorblind safe (default)" = "default",
    "Classic" = "classic",
    "Muted" = "muted",
    "High contrast" = "high_contrast"
  )
}

get_dpsir_shape_cycle <- function() {
  c("square", "triangle", "dot", "diamond", "star", "hexagon", "box", "ellipse")
}

recycle_to_length <- function(values, n) {
  rep(values, length.out = n)
}

# =====================================================
# SCHEMA PADRAO (TEMPLATE DPSIR)
# =====================================================

get_default_dpsir_schema <- function(palette = "default") {
  names <- c("Driver", "Pressure", "State", "Impact", "Response")
  n <- length(names)

  palettes <- get_dpsir_color_palettes()
  if (!palette %in% names(palettes)) {
    stop("Unknown DPSIR color palette.", call. = FALSE)
  }

  data.frame(
    name = names,
    order = seq_len(n),
    color = recycle_to_length(palettes[[palette]], n),
    shape = recycle_to_length(get_dpsir_shape_cycle(), n),
    role = c(rep(NA_character_, n - 1), "feedback"),
    stringsAsFactors = FALSE
  )
}

# =====================================================
# APLICAR PALETA A UM SCHEMA EXISTENTE
# =====================================================

apply_schema_palette <- function(schema, palette = "default") {
  palettes <- get_dpsir_color_palettes()
  if (!palette %in% names(palettes)) {
    stop("Unknown DPSIR color palette.", call. = FALSE)
  }

  schema <- schema[order(schema$order), ]
  schema$color <- recycle_to_length(palettes[[palette]], nrow(schema))
  schema
}

# =====================================================
# VALIDACAO DO SCHEMA
# =====================================================

validate_schema <- function(schema) {
  if (is.null(schema) || !is.data.frame(schema)) {
    stop("Schema must be a data.frame.", call. = FALSE)
  }

  required_cols <- c("name", "order", "color", "shape", "role")
  missing_cols <- setdiff(required_cols, names(schema))
  if (length(missing_cols) > 0) {
    stop(
      paste("Schema is missing columns:", paste(missing_cols, collapse = ", ")),
      call. = FALSE
    )
  }

  if (nrow(schema) == 0) {
    stop("Schema must have at least one level.", call. = FALSE)
  }

  if (any(is.na(schema$name) | trimws(schema$name) == "")) {
    stop("Every schema level needs a non-empty name.", call. = FALSE)
  }

  if (any(duplicated(schema$name))) {
    stop("Schema level names must be unique.", call. = FALSE)
  }

  if (any(is.na(schema$order)) || any(duplicated(schema$order))) {
    stop("Schema level 'order' must be unique and non-missing.", call. = FALSE)
  }

  invisible(TRUE)
}

# =====================================================
# CATEGORIAS ORDENADAS
# =====================================================

schema_categories <- function(schema) {
  validate_schema(schema)
  schema$name[order(schema$order)]
}

# =====================================================
# COMPATIBILIDADE ENTRE SCHEMAS (usado ao combinar savepoints)
# =====================================================
#
# Dois schemas sao compativeis se tem os mesmos niveis, na mesma ordem,
# com os mesmos papeis de feedback - cor e forma sao cosmeticos e nao
# entram na comparacao.

schemas_equivalent <- function(schema_a, schema_b) {
  validate_schema(schema_a)
  validate_schema(schema_b)

  categories_a <- schema_categories(schema_a)
  categories_b <- schema_categories(schema_b)

  if (!identical(categories_a, categories_b)) {
    return(FALSE)
  }

  roles_a <- schema_a$role[match(categories_a, schema_a$name)]
  roles_b <- schema_b$role[match(categories_b, schema_b$name)]

  identical(roles_a, roles_b)
}

# =====================================================
# CONEXOES PERMITIDAS (DERIVADAS DA ORDEM)
# =====================================================

schema_allowed_connections <- function(schema) {
  validate_schema(schema)

  schema <- schema[order(schema$order), ]
  connections <- list()

  for (i in seq_len(nrow(schema))) {
    current_order <- schema$order[i]
    current_name <- schema$name[i]

    next_level <- schema$name[schema$order == current_order + 1]
    targets <- next_level

    if (!is.na(schema$role[i]) && schema$role[i] == "feedback") {
      previous_levels <- schema$name[schema$order < current_order]
      targets <- union(targets, previous_levels)
    }

    connections[[current_name]] <- targets
  }

  connections
}

# =====================================================
# CORES E FORMAS POR CATEGORIA
# =====================================================

schema_colors <- function(schema) {
  validate_schema(schema)
  setNames(schema$color, schema$name)
}

schema_shapes <- function(schema) {
  validate_schema(schema)
  setNames(schema$shape, schema$name)
}

# =====================================================
# VOCABULARIOS CONTROLADOS (NOS E ARESTAS)
# =====================================================

# `uncertainty`/`controllability` (nos) deixaram de ser um vocabulario
# categorico (low/medium/high) e viraram uma fracao continua em [0,1] -
# mesmo padrao ja adotado por `self_regulation` na Fase 5, embora estes
# dois nunca tenham entrado em nenhum calculo (so leitura/exibicao: borda
# do no no grafo, tooltip, media por categoria em Descriptors/relatorio) -
# get_uncertainty_levels()/get_controllability_levels() removidas, o
# formulario (mod_data.R) usa numericInput(0-1) no lugar do selectInput.

# `temporal_scale` (short/medium/long) foi aposentado na Revisao 1: nunca
# entrava em nenhum calculo (so decorativo desde a Fase 1) e ficou
# redundante/contraditorio com `growth_rate`/auto-regulacao (agora
# numericos, ver R/temporal.R) respondendo a mesma pergunta - "muda rapido
# ou devagar" - de forma quantitativa. get_temporal_scales() removida;
# normalize_dpsir_nodes() (R/validate.R) continua lendo tolerantemente um
# savepoint/CSV antigo que ainda tenha a coluna, so ignorada.
#
# `self_regulation` (Fase 9) deixou de ser um vocabulario controlado
# (none/low/medium/high) - vira uma fracao continua em [0,1) digitada
# diretamente (ver formulario de no em mod_data.R e
# self_regulation_diagonal(), R/loop_analysis.R). get_self_regulation_levels()
# removida junto.

get_interaction_types <- function() {
  c("positive", "negative")
}

get_evidence_types <- function() {
  c(
    "observational",
    "monitoring",
    "expert_assessment",
    "remote_sensing",
    "epidemiological",
    "policy_document",
    "management_plan"
  )
}

# =====================================================
# LEGENDA (usada pelo grafo)
# =====================================================

build_dpsir_legend <- function(schema) {
  validate_schema(schema)
  schema <- schema[order(schema$order), ]

  data.frame(
    label = schema$name,
    color = schema$color,
    shape = schema$shape,
    stringsAsFactors = FALSE
  )
}

# =====================================================
# ROLES (Revisao 2, item 2.6)
# =====================================================
#
# The engine needs to know which level plays which part (driver, pressure,
# state, impact, feedback), not what the level is called - renaming
# "Impact" to "Outcome" on the Model step must not empty the tables. A
# level's role comes from the schema's `role` column when it holds one of
# these names; otherwise it is inferred from the order: `feedback` levels
# keep their role; among the others, the first is the driver, the last the
# impact, the second the pressure and the second-to-last the state (for the
# default DPSIR order this gives exactly D, P, S, I, R).
DPSIR_ROLES <- c("driver", "pressure", "state", "impact", "feedback")

schema_roles <- function(schema = get_default_dpsir_schema()) {
  s <- schema[order(schema$order), , drop = FALSE]
  given <- tolower(trimws(as.character(s$role)))
  given[is.na(given)] <- ""
  roles <- ifelse(given %in% DPSIR_ROLES, given, NA_character_)
  chain <- which(is.na(roles) | roles != "feedback")
  free <- chain[is.na(roles[chain])]
  n <- length(chain)
  infer <- rep(NA_character_, n)
  if (n >= 1) infer[1] <- "driver"
  if (n >= 2) infer[n] <- "impact"
  if (n >= 3) infer[2] <- "pressure"
  if (n >= 4) infer[n - 1] <- "state"
  for (k in seq_along(chain)) {
    i <- chain[k]
    if (i %in% free && !is.na(infer[k]) && !infer[k] %in% roles) roles[i] <- infer[k]
  }
  setNames(roles, s$name)
}

# Role of each category name (NA for a category the schema does not have).
roles_of <- function(categories, schema = get_default_dpsir_schema()) {
  unname(schema_roles(schema)[as.character(categories)])
}

# Category names that play `role` in the schema.
categories_with_role <- function(role, schema = get_default_dpsir_schema()) {
  r <- schema_roles(schema)
  names(r)[!is.na(r) & r %in% role]
}

# Role of every node of a graph: the vertex attribute set by build_igraph()
# from the graph's own schema, or - for a graph built without it - the role
# of its category name in the default schema.
node_roles <- function(g) {
  r <- igraph::vertex_attr(g, "dpsir_role")
  if (!is.null(r)) return(as.character(r))
  cats <- igraph::vertex_attr(g, "dpsir_category")
  if (is.null(cats)) return(rep(NA_character_, igraph::vcount(g)))
  roles_of(cats)
}

has_role <- function(g, role) {
  r <- node_roles(g)
  !is.na(r) & r %in% role
}
