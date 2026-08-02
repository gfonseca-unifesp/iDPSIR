# =====================================================
# VALIDACAO - NOS E ARESTAS (SCHEMA-DRIVEN)
# =====================================================

get_required_dpsir_node_fields <- function() {
  c("id", "label", "dpsir_category")
}

get_required_dpsir_edge_fields <- function() {
  c("from", "to")
}

get_known_dpsir_node_fields <- function() {
  c(
    "id", "label", "dpsir_category", "subsystem", "uncertainty", "controllability",
    "self_regulation", "growth_rate", "reference_value", "activation_threshold", "descriptor"
  )
}

get_known_dpsir_edge_fields <- function() {
  c("from", "to", "weight", "confidence", "interaction_type", "evidence_type", "reference")
}

# =====================================================
# IMPORT PREFLIGHT (CSV format/vocabulary check, run at import time -
# before normalize_dpsir_nodes()/normalize_dpsir_edges() silently apply
# defaults for anything missing, so a mis-shaped spreadsheet gets caught
# right where it was uploaded instead of surfacing as a confusing error,
# or worse, an accepted-but-wrong network, several steps later).
#
# Returns list(blocking = character(), warnings = character()) - blocking
# messages mean the file should NOT be imported as-is (missing/renamed
# required column, out-of-vocabulary value, non-numeric where a number is
# expected); warnings are informational only (unknown column ignored, or
# optional column absent so every row got the same default) and don't
# stop the import. Row numbers count the header as row 1, matching what a
# spreadsheet program shows.
# =====================================================

# A cell is "blank" if it's genuinely missing (NA - what an empty CSV cell
# parses to) or an empty/whitespace-only string - never based on its
# stringified form, which would turn a real NA into the text "NA" and
# misread a blank cell as "the user typed the word NA" (confirmed as a real
# bug while testing this: `as.character(NA)` %in% a values vector is a
# false positive for "has a value").
.pf_is_blank <- function(x) {
  is.na(x) | trimws(as.character(x)) == ""
}

preflight_import_nodes <- function(nodes_raw, schema = get_default_dpsir_schema()) {
  nodes_raw <- as.data.frame(nodes_raw, stringsAsFactors = FALSE)
  blocking <- character()
  warn <- character()

  present <- names(nodes_raw)
  missing_required <- setdiff(get_required_dpsir_node_fields(), present)
  if (length(missing_required) > 0) {
    blocking <- c(blocking, sprintf(
      "Nodes file: missing required column '%s'.", missing_required
    ))
  }

  unknown_cols <- setdiff(present, get_known_dpsir_node_fields())
  if (length(unknown_cols) > 0) {
    warn <- c(warn, sprintf(
      "Nodes file: column '%s' is not a recognized field and was ignored.", unknown_cols
    ))
  }

  optional_defaults <- c(
    uncertainty = "0.5", controllability = "0.5",
    self_regulation = "0", growth_rate = "0", reference_value = "1",
    activation_threshold = "blank (no threshold)", descriptor = "blank"
  )
  missing_optional <- setdiff(names(optional_defaults), present)
  if (length(missing_optional) > 0) {
    warn <- c(warn, sprintf(
      "Nodes file: column '%s' is missing - every node defaults to %s.",
      missing_optional, optional_defaults[missing_optional]
    ))
  }

  if (length(missing_required) == 0 && nrow(nodes_raw) > 0) {
    valid_categories <- schema_categories(schema)
    category_vals <- trimws(as.character(nodes_raw$dpsir_category))
    bad <- which(!.pf_is_blank(nodes_raw$dpsir_category) & !category_vals %in% valid_categories)
    if (length(bad) > 0) {
      blocking <- c(blocking, sprintf(
        "Nodes file, row %d: dpsir_category '%s' is not one of %s.",
        bad + 1, category_vals[bad], paste(valid_categories, collapse = ", ")
      ))
    }
  }

  if (nrow(nodes_raw) > 0) {
    for (field in c("uncertainty", "controllability")) {
      if (field %in% present) {
        raw <- nodes_raw[[field]]
        legacy_levels <- c("low", "medium", "high") # pre-Revisao-1 vocabulary, still accepted
        raw_chr <- trimws(as.character(raw))
        blank <- .pf_is_blank(raw)
        is_legacy <- raw_chr %in% legacy_levels
        numeric_vals <- suppressWarnings(as.numeric(raw))
        bad_type <- which(!blank & !is_legacy & is.na(numeric_vals))
        if (length(bad_type) > 0) {
          blocking <- c(blocking, sprintf(
            "Nodes file, row %d: %s '%s' is not a number.",
            bad_type + 1, field, raw_chr[bad_type]
          ))
        }
        bad_range <- which(!blank & !is_legacy & !is.na(numeric_vals) & (numeric_vals < 0 | numeric_vals > 1))
        if (length(bad_range) > 0) {
          blocking <- c(blocking, sprintf(
            "Nodes file, row %d: %s %s is outside the valid range [0, 1].",
            bad_range + 1, field, numeric_vals[bad_range]
          ))
        }
      }
    }

    if ("self_regulation" %in% present) {
      raw <- nodes_raw$self_regulation
      legacy_levels <- c("none", "low", "medium", "high") # pre-Revisao-1 vocabulary, still accepted
      raw_chr <- trimws(as.character(raw))
      blank <- .pf_is_blank(raw)
      is_legacy <- raw_chr %in% legacy_levels
      numeric_vals <- suppressWarnings(as.numeric(raw))
      bad_type <- which(!blank & !is_legacy & is.na(numeric_vals))
      if (length(bad_type) > 0) {
        blocking <- c(blocking, sprintf(
          "Nodes file, row %d: self_regulation '%s' is not a number.",
          bad_type + 1, raw_chr[bad_type]
        ))
      }
      bad_range <- which(!blank & !is_legacy & !is.na(numeric_vals) & (numeric_vals < 0 | numeric_vals >= 1))
      if (length(bad_range) > 0) {
        blocking <- c(blocking, sprintf(
          "Nodes file, row %d: self_regulation %s is outside the valid range [0, 1).",
          bad_range + 1, numeric_vals[bad_range]
        ))
      }
    }

    if ("activation_threshold" %in% present) {
      raw <- nodes_raw$activation_threshold
      raw_chr <- trimws(as.character(raw))
      blank <- .pf_is_blank(raw)
      numeric_vals <- suppressWarnings(as.numeric(raw))
      bad_type <- which(!blank & is.na(numeric_vals))
      if (length(bad_type) > 0) {
        blocking <- c(blocking, sprintf(
          "Nodes file, row %d: activation_threshold '%s' is not a number.",
          bad_type + 1, raw_chr[bad_type]
        ))
      }
      has_value <- !blank & !is.na(numeric_vals)
      is_state <- if ("dpsir_category" %in% present) {
        trimws(as.character(nodes_raw$dpsir_category)) == "State"
      } else {
        rep(TRUE, nrow(nodes_raw))
      }
      bad_category <- which(has_value & !is_state)
      if (length(bad_category) > 0) {
        blocking <- c(blocking, sprintf(
          "Nodes file, row %d: activation_threshold is set but this node is not a State factor.",
          bad_category + 1
        ))
      }
      bad_range <- which(has_value & (numeric_vals < 0 | numeric_vals > 1))
      if (length(bad_range) > 0) {
        blocking <- c(blocking, sprintf(
          "Nodes file, row %d: activation_threshold %s is outside the valid range [0, 1].",
          bad_range + 1, numeric_vals[bad_range]
        ))
      }
    }
  }

  list(blocking = blocking, warnings = warn)
}

preflight_import_edges <- function(edges_raw) {
  edges_raw <- as.data.frame(edges_raw, stringsAsFactors = FALSE)
  blocking <- character()
  warn <- character()

  if (nrow(edges_raw) == 0) {
    return(list(blocking = blocking, warnings = warn))
  }

  present <- names(edges_raw)
  missing_required <- setdiff(get_required_dpsir_edge_fields(), present)
  if (length(missing_required) > 0) {
    blocking <- c(blocking, sprintf(
      "Edges file: missing required column '%s'.", missing_required
    ))
  }

  unknown_cols <- setdiff(present, get_known_dpsir_edge_fields())
  if (length(unknown_cols) > 0) {
    warn <- c(warn, sprintf(
      "Edges file: column '%s' is not a recognized field and was ignored.", unknown_cols
    ))
  }

  optional_defaults <- c(
    weight = "1", confidence = "1", interaction_type = "an uncolored/undashed edge",
    evidence_type = "blank", reference = "blank"
  )
  missing_optional <- setdiff(names(optional_defaults), present)
  if (length(missing_optional) > 0) {
    warn <- c(warn, sprintf(
      "Edges file: column '%s' is missing - every edge defaults to %s.",
      missing_optional, optional_defaults[missing_optional]
    ))
  }

  if (length(missing_required) == 0) {
    if ("interaction_type" %in% present) {
      raw <- edges_raw$interaction_type
      vals <- trimws(as.character(raw))
      bad <- which(!.pf_is_blank(raw) & !vals %in% c("positive", "negative"))
      if (length(bad) > 0) {
        blocking <- c(blocking, sprintf(
          "Edges file, row %d: interaction_type '%s' must be positive or negative.",
          bad + 1, vals[bad]
        ))
      }
    }

    if ("weight" %in% present) {
      raw <- edges_raw$weight
      raw_chr <- trimws(as.character(raw))
      blank <- .pf_is_blank(raw)
      numeric_vals <- suppressWarnings(as.numeric(raw))
      bad_type <- which(!blank & is.na(numeric_vals))
      if (length(bad_type) > 0) {
        blocking <- c(blocking, sprintf(
          "Edges file, row %d: weight '%s' is not a number.", bad_type + 1, raw_chr[bad_type]
        ))
      }
      bad_range <- which(!blank & !is.na(numeric_vals) & numeric_vals <= 0)
      if (length(bad_range) > 0) {
        blocking <- c(blocking, sprintf(
          "Edges file, row %d: weight %s must be greater than 0.", bad_range + 1, numeric_vals[bad_range]
        ))
      }
    }

    if ("confidence" %in% present) {
      raw <- edges_raw$confidence
      raw_chr <- trimws(as.character(raw))
      blank <- .pf_is_blank(raw)
      numeric_vals <- suppressWarnings(as.numeric(raw))
      bad_type <- which(!blank & is.na(numeric_vals))
      if (length(bad_type) > 0) {
        blocking <- c(blocking, sprintf(
          "Edges file, row %d: confidence '%s' is not a number.", bad_type + 1, raw_chr[bad_type]
        ))
      }
      bad_range <- which(!blank & !is.na(numeric_vals) & (numeric_vals < 0 | numeric_vals > 1))
      if (length(bad_range) > 0) {
        blocking <- c(blocking, sprintf(
          "Edges file, row %d: confidence %s is outside the valid range [0, 1].", bad_range + 1, numeric_vals[bad_range]
        ))
      }
    }
  }

  list(blocking = blocking, warnings = warn)
}

preflight_import <- function(nodes_raw, edges_raw = NULL, schema = get_default_dpsir_schema()) {
  nodes_result <- preflight_import_nodes(nodes_raw, schema)
  edges_result <- if (is.null(edges_raw)) {
    list(blocking = character(), warnings = character())
  } else {
    preflight_import_edges(edges_raw)
  }

  list(
    blocking = c(nodes_result$blocking, edges_result$blocking),
    warnings = c(nodes_result$warnings, edges_result$warnings)
  )
}

normalize_dpsir_nodes <- function(nodes) {
  nodes <- as.data.frame(nodes, stringsAsFactors = FALSE)
  nodes$id <- trimws(as.character(nodes$id))
  nodes$label <- as.character(nodes$label)
  nodes$dpsir_category <- trimws(as.character(nodes$dpsir_category))

  # uncertainty/controllability deixaram de ser um vocabulario categorico
  # (low/medium/high) e viraram uma fracao continua em [0,1] - nunca
  # entraram em nenhum calculo (so leitura: borda do no, tooltip, media
  # por categoria), entao a mudanca e so de representacao, sem nenhuma
  # equacao pra reavaliar (diferente de self_regulation, ver abaixo, que
  # precisou virar numerico especificamente pra ser usado no motor
  # temporal). 0.5 e o default tanto pra coluna ausente quanto pra valor
  # em branco - "moderado/nao informado", o mesmo papel que "medium" jogava
  # no vocabulario antigo, sem favorecer nem alta nem baixa incerteza por
  # omissao. Um savepoint/CSV de antes desta mudanca ainda pode trazer as
  # strings antigas - mapeadas aqui pra nao quebrar ao carregar, mesmo
  # padrao de legado ja usado por self_regulation logo abaixo.
  for (field in c("uncertainty", "controllability")) {
    if (!field %in% names(nodes)) {
      nodes[[field]] <- 0.5
    } else {
      raw <- nodes[[field]]
      legacy_levels <- c(low = 0.2, medium = 0.5, high = 0.8)
      is_legacy_string <- as.character(raw) %in% names(legacy_levels)
      numeric_values <- suppressWarnings(as.numeric(raw))
      numeric_values[is_legacy_string] <- legacy_levels[as.character(raw)[is_legacy_string]]
      numeric_values[is.na(numeric_values)] <- 0.5
      nodes[[field]] <- numeric_values
    }
  }

  # Revisao 1, Fase 5: self_regulation deixou de ser um vocabulario
  # categorico (none/low/medium/high) e virou uma fracao continua em
  # [0,1) - ver R/temporal.R pro motivo real testado (as magnitudes
  # categoricas antigas oscilam em vez de decair na equacao de diferenca
  # discreta do motor temporal). Missing entirely e o caso normal (default
  # 0, mesmo comportamento de sempre) - ver R/loop_analysis.R's
  # self_regulation_diagonal(). Um savepoint/CSV de antes desta mudanca
  # ainda pode trazer as strings antigas - mapeadas aqui pra um valor
  # numerico so pra nao quebrar ao carregar, nao e o caminho principal.
  if (!"self_regulation" %in% names(nodes)) {
    nodes$self_regulation <- 0
  } else {
    raw <- nodes$self_regulation
    legacy_levels <- c(none = 0, low = 0.2, medium = 0.4, high = 0.6)
    is_legacy_string <- as.character(raw) %in% names(legacy_levels)
    numeric_values <- suppressWarnings(as.numeric(raw))
    numeric_values[is_legacy_string] <- legacy_levels[as.character(raw)[is_legacy_string]]
    numeric_values[is.na(numeric_values)] <- 0
    nodes$self_regulation <- numeric_values
  }

  # Revisao 1, Fase 5: tendencia exogena propria do no (crescimento
  # populacional, tendencia de consumo), independente das arestas - ver
  # R/temporal.R. Opcional, default 0 (constante, comportamento de hoje).
  if (!"growth_rate" %in% names(nodes)) {
    nodes$growth_rate <- 0
  } else {
    nodes$growth_rate <- suppressWarnings(as.numeric(nodes$growth_rate))
    nodes$growth_rate[is.na(nodes$growth_rate)] <- 0
  }

  # Revisao 1, Fase 5: escala de referencia do no, usada so pra tornar
  # `threshold` (aresta) relativo em vez de absoluto - ver R/temporal.R.
  # Opcional, default 1 (threshold se comporta como magnitude absoluta,
  # igual a antes desta coluna existir).
  if (!"reference_value" %in% names(nodes)) {
    nodes$reference_value <- 1
  } else {
    nodes$reference_value <- suppressWarnings(as.numeric(nodes$reference_value))
    nodes$reference_value[is.na(nodes$reference_value) | nodes$reference_value == 0] <- 1
  }

  # Descricao livre e opcional do no (uma frase explicando o que o fator
  # representa) - pedido do usuario pra documentar a rede pra um leitor
  # que nao participou da modelagem. Mesmo padrao ja usado por outros
  # campos de texto livre (reference nas arestas): default "", nunca NA,
  # sem validacao de formato.
  if (!"descriptor" %in% names(nodes)) {
    nodes$descriptor <- ""
  } else {
    nodes$descriptor[is.na(nodes$descriptor)] <- ""
    nodes$descriptor <- trimws(as.character(nodes$descriptor))
  }

  # Segunda rodada da Revisao 1: threshold deixou de ser atributo de
  # ARESTA e virou atributo de NO (renomeado `activation_threshold`) - um
  # unico gatilho por State, disparando TODAS as suas arestas de saida
  # juntas, em vez de um gatilho independente por aresta individual (ver
  # R/loop_analysis.R's build_threshold_matrix()). Mesmo padrao opcional
  # de sempre: ausente/NA e o caso normal ("sempre ligado", comportamento
  # de hoje), so significativo pra um no de categoria State - validado no
  # formulario (mod_data.R), nao aqui.
  if (!"activation_threshold" %in% names(nodes)) {
    nodes$activation_threshold <- NA_real_
  } else {
    nodes$activation_threshold <- suppressWarnings(as.numeric(nodes$activation_threshold))
  }

  # `temporal_scale` foi aposentado (ver R/schema.R) - removida aqui, nao
  # so ignorada, se um savepoint/CSV antigo ainda trouxer a coluna.
  #
  # Bug real, encontrado so ao testar ao vivo (carregar um savepoint
  # antigo com `temporal_scale`, editar um no existente): deixar a coluna
  # "so ignorada" (sem remover) fazia `rv$nodes` (carregado, com
  # `temporal_scale`) e o `new_row` reconstruido pelo formulario (sem
  # `temporal_scale`, ja que o formulario nao pergunta mais por ela) terem
  # um NUMERO DIFERENTE de colunas - `rv$nodes[idx, ] <- new_row`
  # (mod_data.R) faz a atribuicao POSICIONALMENTE quando as colunas nao
  # batem, nao por nome, deslocando every valor uma posicao a partir de
  # onde a coluna faltante ficaria (self_regulation acabava gravado na
  # posicao de temporal_scale, growth_rate na de self_regulation, etc, e
  # reference_value virava o proprio id do no por causa da reciclagem).
  # Remover a coluna aqui garante que `rv$nodes` sempre tem exatamente o
  # mesmo conjunto de colunas que o formulario produz, nao importa se os
  # dados de origem (savepoint/CSV) tinham `temporal_scale` ou nao.
  nodes$temporal_scale <- NULL

  nodes
}

normalize_dpsir_edges <- function(edges) {
  edges <- as.data.frame(edges, stringsAsFactors = FALSE)

  if (nrow(edges) == 0) {
    return(edges)
  }

  edges$from <- trimws(as.character(edges$from))
  edges$to <- trimws(as.character(edges$to))

  if ("weight" %in% names(edges)) {
    edges$weight <- as.numeric(edges$weight)
  }

  if ("confidence" %in% names(edges)) {
    edges$confidence <- as.numeric(edges$confidence)
  }

  # `threshold` foi movido de aresta pra no (ver normalize_dpsir_nodes()'s
  # `activation_threshold`) - removida aqui, nao so ignorada, pelo mesmo
  # motivo real ja documentado pra `temporal_scale`: manter `rv$edges`
  # sempre com o mesmo conjunto de colunas que o formulario produz (que
  # nao pergunta mais por isso), evitando o bug de atribuicao posicional
  # `rv$edges[idx, ] <- new_row` deslocar valores pra coluna errada.
  edges$threshold <- NULL

  # Optional free-text citation for the edge (DOI, URL, or a plain reference
  # like "Smith et al. 2020") - deliberately not format-validated, the same
  # way evidence_type's sibling free-text fields aren't. Defaults to "" so
  # older savepoints/CSVs without the column keep working unchanged.
  if (!"reference" %in% names(edges)) {
    edges$reference <- ""
  } else {
    edges$reference[is.na(edges$reference)] <- ""
    edges$reference <- trimws(as.character(edges$reference))
  }

  edges
}

validate_required_fields <- function(data, required_fields, object_name) {
  missing_fields <- setdiff(required_fields, names(data))

  if (length(missing_fields) > 0) {
    stop(
      paste(
        object_name,
        "is missing required fields:",
        paste(missing_fields, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_categories <- function(nodes, schema) {
  valid_categories <- schema_categories(schema)

  invalid <- is.na(nodes$dpsir_category) |
    !nodes$dpsir_category %in% valid_categories

  if (any(invalid)) {
    stop(
      paste(
        "Invalid DPSIR categories:",
        paste(unique(nodes$dpsir_category[invalid]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_unique_node_ids <- function(nodes) {
  duplicated_ids <- unique(nodes$id[duplicated(nodes$id)])

  if (length(duplicated_ids) > 0) {
    stop(
      paste("Duplicated node ids:", paste(duplicated_ids, collapse = ", ")),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_nodes <- function(nodes, schema = get_default_dpsir_schema()) {
  validate_required_fields(
    nodes,
    get_required_dpsir_node_fields(),
    "Nodes table"
  )

  nodes <- normalize_dpsir_nodes(nodes)

  validate_unique_node_ids(nodes)
  validate_dpsir_categories(nodes, schema)

  invisible(TRUE)
}

validate_edge_node_existence <- function(nodes, edges) {
  invalid_from <- !edges$from %in% nodes$id
  invalid_to <- !edges$to %in% nodes$id

  if (any(invalid_from)) {
    stop(
      paste(
        "Edges contain invalid 'from' node ids:",
        paste(unique(edges$from[invalid_from]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (any(invalid_to)) {
    stop(
      paste(
        "Edges contain invalid 'to' node ids:",
        paste(unique(edges$to[invalid_to]), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_edge_logic <- function(nodes, edges, schema) {
  allowed_connections <- schema_allowed_connections(schema)
  node_categories <- setNames(nodes$dpsir_category, nodes$id)
  invalid_edges <- character()

  for (i in seq_len(nrow(edges))) {
    from_id <- edges$from[i]
    to_id <- edges$to[i]

    from_category <- unname(node_categories[from_id])
    to_category <- unname(node_categories[to_id])
    allowed_targets <- allowed_connections[[from_category]]

    if (is.null(allowed_targets) || !to_category %in% allowed_targets) {
      invalid_edges <- c(
        invalid_edges,
        paste0(
          from_id,
          " (",
          from_category,
          ") -> ",
          to_id,
          " (",
          to_category,
          ")"
        )
      )
    }
  }

  if (length(invalid_edges) > 0) {
    stop(
      paste(
        "Invalid DPSIR edge connections:",
        paste(invalid_edges, collapse = "; ")
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_dpsir_edges <- function(nodes, edges, schema = get_default_dpsir_schema()) {
  validate_required_fields(
    edges,
    get_required_dpsir_edge_fields(),
    "Edges table"
  )

  nodes <- normalize_dpsir_nodes(nodes)
  edges <- normalize_dpsir_edges(edges)

  if (nrow(edges) == 0) {
    return(invisible(TRUE))
  }

  validate_edge_node_existence(nodes, edges)
  validate_dpsir_edge_logic(nodes, edges, schema)

  invisible(TRUE)
}

is_valid_dpsir_network <- function(nodes, edges = NULL, schema = get_default_dpsir_schema()) {
  tryCatch(
    {
      validate_dpsir_nodes(nodes, schema)

      if (!is.null(edges)) {
        validate_dpsir_edges(nodes, edges, schema)
      }

      TRUE
    },
    error = function(e) {
      FALSE
    }
  )
}

# =====================================================
# VALIDACAO DE ENTRADA DO GRAFO
# =====================================================

validate_nodes <- function(nodes, schema = get_default_dpsir_schema()) {
  if (is.null(nodes) || !is.data.frame(nodes)) {
    stop("Nodes must be a data.frame.", call. = FALSE)
  }

  validate_dpsir_nodes(nodes, schema)
  invisible(TRUE)
}

validate_edges <- function(edges) {
  if (is.null(edges)) {
    return(invisible(TRUE))
  }

  if (!is.data.frame(edges)) {
    stop("Edges must be a data.frame.", call. = FALSE)
  }

  validate_required_fields(
    edges,
    get_required_dpsir_edge_fields(),
    "Edges table"
  )

  invisible(TRUE)
}

validate_graph_inputs <- function(nodes, edges = NULL, schema = get_default_dpsir_schema()) {
  validate_nodes(nodes, schema)

  if (!is.null(edges)) {
    validate_edges(edges)
    validate_dpsir_edges(nodes, edges, schema)
  }

  invisible(TRUE)
}
