# =====================================================
# VALIDACAO - NOS E ARESTAS (SCHEMA-DRIVEN)
# =====================================================

get_required_dpsir_node_fields <- function() {
  c("id", "label", "dpsir_category")
}

get_required_dpsir_edge_fields <- function() {
  c("from", "to")
}

normalize_dpsir_nodes <- function(nodes) {
  nodes <- as.data.frame(nodes, stringsAsFactors = FALSE)
  nodes$id <- trimws(as.character(nodes$id))
  nodes$label <- as.character(nodes$label)
  nodes$dpsir_category <- trimws(as.character(nodes$dpsir_category))

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
