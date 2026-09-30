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

# Revisao 1, Fase 5: self_regulation deixou de ser um vocabulario
# categorico (none/low/medium/high, com uma tabela fixa de magnitudes) e
# virou uma fracao continua em [0,1) digitada direto pelo usuario -
# "fracao do desvio que reverte por janela". Sempre negativada aqui pra
# virar a magnitude de decaimento na diagonal (0,4 digitado vira -0,4 na
# diagonal: x(t+1) = x(t) - 0,4*x(t) = 0,6*x(t), decaimento geometrico
# limpo) - ver R/temporal.R pro motivo real testado (as magnitudes fixas
# antigas, calibradas pro Euler implicito do motor de equilibrio, oscilam
# em vez de decair na equacao de diferenca discreta do motor temporal
# novo). Per-node self-regulation como um vetor nomeado simples -
# compartilhado por build_interaction_matrix() e pela rotina de
# sensibilidade-a-auto-regulacao (item 9.1.4), os dois leem o mesmo valor.
self_regulation_diagonal <- function(g) {
  node_names <- V(g)$name
  self_reg <- V(g)$self_regulation
  if (is.null(self_reg)) {
    return(setNames(rep(0, length(node_names)), node_names))
  }
  values <- suppressWarnings(as.numeric(self_reg))
  values[is.na(values)] <- 0
  setNames(-values, node_names)
}

build_interaction_matrix <- function(g) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  n <- length(node_names)
  A <- matrix(0, nrow = n, ncol = n, dimnames = list(node_names, node_names))

  if (ecount(g) > 0) {
    edge_ends <- ends(g, E(g), names = TRUE)
    weight <- E(g)$weight
    sign <- ifelse(E(g)$interaction_type == "negative", -1, 1)

    for (k in seq_len(nrow(edge_ends))) {
      from_node <- edge_ends[k, 1]
      to_node <- edge_ends[k, 2]
      A[to_node, from_node] <- A[to_node, from_node] + sign[k] * weight[k]
    }
  }

  # Self-regulation is a node attribute, not an edge - applied to the
  # diagonal regardless of edge count, so it works even on a graph with no
  # edges at all (unlike the loop above, which used to be the only thing
  # this function did, hence the early return this replaces).
  diag(A) <- diag(A) + self_regulation_diagonal(g)

  A
}

# =====================================================
# SCENARIOS (Marco B: mod_responses.R computa a partir daqui)
# =====================================================
#
# Ativar uma resposta a uma dada forca vira uma perturbacao sustentada
# (press) sobre o proprio no da Resposta - o efeito se propaga pelas
# arestas com sinal/peso ja preenchidos, contabilizando o loop de feedback
# completo via press_perturbation(). Combinar respostas e so somar mais de
# um no no mesmo vetor de press, em vez do encadeamento manual que
# apply_response() (R/responses.R) fazia.

build_press_vector <- function(g, active_ids, strengths) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  press <- setNames(rep(0, length(node_names)), node_names)
  press[active_ids] <- strengths[active_ids]
  press
}
