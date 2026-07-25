# =====================================================
# LOOP ANALYSIS (community matrix / press perturbation)
# =====================================================
#
# Analise de loop de Levins (1974) / Dambacher, Puccia et al. - o metodo
# classico de ecologia para grafos direcionados com sinal e ciclos, a mesma
# estrutura que o loop Response -> {Driver,Pressure,State,Impact} cria no
# DPSIR. Cada aresta vira uma entrada da matriz de interacao A[i,j] (efeito
# de j sobre i): sinal de `interaction_type` (positive/negative), magnitude
# de `weight` - os mesmos dois atributos que o usuario ja preenche hoje.
# Zero dependencia nova, so `solve()`/`eigen()` do R base.
#
# Marco A da Fase 5 (ver PLANO_iDPSIR.md secao 8): matematica pura, sem UI.
# `mod_responses.R` passa a computar a partir daqui nos marcos seguintes;
# `apply_response()` (R/responses.R) fica preservada no disco mas deixa de
# ser o motor principal da aba Scenarios.

build_interaction_matrix <- function(g) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  n <- length(node_names)
  A <- matrix(0, nrow = n, ncol = n, dimnames = list(node_names, node_names))

  if (ecount(g) == 0) {
    return(A)
  }

  edge_ends <- ends(g, E(g), names = TRUE)
  weight <- E(g)$weight
  sign <- ifelse(E(g)$interaction_type == "negative", -1, 1)

  for (k in seq_len(nrow(edge_ends))) {
    from_node <- edge_ends[k, 1]
    to_node <- edge_ends[k, 2]
    A[to_node, from_node] <- A[to_node, from_node] + sign[k] * weight[k]
  }

  A
}

check_stability <- function(A) {
  stopifnot(is.matrix(A), nrow(A) == ncol(A))

  eigenvalues <- eigen(A, only.values = TRUE)$values
  real_parts <- Re(eigenvalues)

  list(
    stable = all(real_parts < 0),
    eigenvalues = eigenvalues,
    max_real_part = max(real_parts)
  )
}

# Perturbacao sustentada (press) sobre um ou mais nos: `press` e um vetor
# numerico nomeado ou na mesma ordem de rownames(A), com o tamanho/sinal da
# perturbacao em cada no (0 para os nos nao perturbados). Retorna tanto o
# efeito de um unico passo (`A` aplicado uma vez) quanto o de equilibrio
# (`-A^-1`, contabilizando todos os loops diretos e indiretos).
press_perturbation <- function(A, press) {
  stopifnot(is.matrix(A), nrow(A) == ncol(A))
  stopifnot(length(press) == nrow(A))

  node_names <- rownames(A)
  press <- as.numeric(press)

  immediate <- as.numeric(A %*% press)
  names(immediate) <- node_names

  equilibrium <- tryCatch(
    {
      eq <- as.numeric(-solve(A) %*% press)
      names(eq) <- node_names
      eq
    },
    error = function(e) {
      warning("Interaction matrix is singular; equilibrium response is undefined.", call. = FALSE)
      setNames(rep(NA_real_, length(node_names)), node_names)
    }
  )

  list(immediate = immediate, equilibrium = equilibrium)
}
