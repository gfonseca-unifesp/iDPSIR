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
    default = c("#1f77b4", "#d62728", "#2ca02c", "#ff7f0e", "#9467bd"),
    colorblind = c("#0072B2", "#D55E00", "#009E73", "#E69F00", "#CC79A7"),
    muted = c("#4E79A7", "#E15759", "#59A14F", "#F28E2B", "#B07AA1"),
    high_contrast = c("#0050A4", "#B00020", "#00843D", "#C75B12", "#6A1B9A")
  )
}

get_dpsir_palette_choices <- function() {
  c(
    "Default" = "default",
    "Colorblind safe" = "colorblind",
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

get_uncertainty_levels <- function() c("low", "medium", "high")

get_controllability_levels <- function() c("low", "medium", "high")

get_temporal_scales <- function() c("short", "medium", "long")

get_interaction_types <- function() {
  c("increases", "reduces", "triggers", "mitigates", "improves")
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
