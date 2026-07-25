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

# Trajetoria passo a passo: simula a resposta ao longo do tempo integrando
# a mesma dinamica continua que da o equilibrio (dx/dt = A*x + press,
# equilibrio em -A^-1*press), comecando de x=0, via Euler implicito.
#
# Euler implicito foi escolhido depois de testar (e descartar) a leitura
# mais literal de "A aplicada repetidamente" (A, A^2, A^3... direto sobre
# o press): isso equivale a Euler EXPLICITO com passo=1, que diverge por
# artefato numerico mesmo em redes que check_stability() corretamente
# identifica como estaveis, sempre que os autovalores de A tem parte
# imaginaria grande (a regiao de estabilidade do Euler explicito e muito
# estreita perto do eixo imaginario - comum justamente em matrizes com
# ciclos, o caso central da Fase 5). Euler implicito e incondicionalmente
# estavel para Re(autovalor) < 0: converge para o mesmo equilibrio de
# press_perturbation() sempre que a rede for estavel, e diverge quando nao
# for, sem exigir escolher um passo pequeno o suficiente - testado nos
# mesmos dois exemplos usados no Marco A/B (cadeia trofica estavel converge
# exatamente pro -A^-1*press already calculado; ciclo instavel diverge). O
# tamanho do passo fica fixo internamente; "Number of steps" e o unico
# controle exposto ao usuario.
simulate_trajectory <- function(A, press, steps = 10, step_size = 0.5) {
  stopifnot(is.matrix(A), nrow(A) == ncol(A))
  stopifnot(length(press) == nrow(A))
  stopifnot(steps >= 1)

  node_names <- rownames(A)
  press <- as.numeric(press)
  n <- length(node_names)

  trajectory <- matrix(NA_real_, nrow = steps, ncol = n, dimnames = list(NULL, node_names))

  update_matrix <- tryCatch(
    solve(diag(n) - step_size * A),
    error = function(e) NULL
  )

  if (is.null(update_matrix)) {
    warning("Trajectory could not be computed for this network (degenerate structure).", call. = FALSE)
    return(trajectory)
  }

  state <- rep(0, n)
  for (step in seq_len(steps)) {
    state <- as.numeric(update_matrix %*% (state + step_size * press))
    trajectory[step, ] <- state
  }

  trajectory
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

# Direcao (Improves/Worsens/Stable) por no, a partir do efeito de
# equilibrio - "Improves" = a resposta reduz o valor do fator (mesma
# convencao ja usada por apply_response: uma Resposta existe para mitigar
# Driver/Pressure/State/Impact, entao reduzir e o resultado desejado). Se a
# matriz for singular (equilibrio indefinido, ver press_perturbation), cai
# de volta pro efeito imediato para aquele no.
summarize_scenario_effect <- function(g, result, threshold = 1e-9) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  equilibrium <- result$equilibrium[node_names]
  immediate <- result$immediate[node_names]

  effect <- equilibrium
  na_equilibrium <- is.na(effect)
  effect[na_equilibrium] <- immediate[na_equilibrium]

  direction <- ifelse(
    is.na(effect) | abs(effect) < threshold,
    "Stable",
    ifelse(effect < 0, "Improves", "Worsens")
  )

  out <- data.frame(
    id = node_names,
    node = if (!is.null(V(g)$label)) V(g)$label else node_names,
    category = if (!is.null(V(g)$dpsir_category)) V(g)$dpsir_category else rep("", length(node_names)),
    immediate = unname(immediate),
    equilibrium = unname(equilibrium),
    direction = direction,
    stringsAsFactors = FALSE
  )

  out[order(-abs(effect)), ]
}

# Resumo em nivel de rede (nao ha mais metricas de topologia
# antes/depois - o grafo nao muda, so o estado dinamico - entao mostra
# quantos nos foram afetados e a magnitude total do efeito, em vez de
# nodes/edges/density como o compare_states() antigo).
summarize_scenario_network_effect <- function(result, threshold = 1e-9) {
  immediate <- result$immediate
  equilibrium <- result$equilibrium
  equilibrium_defined <- !all(is.na(equilibrium))

  data.frame(
    metric = c("Nodes affected", "Total effect magnitude"),
    immediate = c(
      sum(abs(immediate) >= threshold),
      sum(abs(immediate))
    ),
    equilibrium = c(
      if (equilibrium_defined) sum(abs(equilibrium) >= threshold, na.rm = TRUE) else NA_real_,
      if (equilibrium_defined) sum(abs(equilibrium), na.rm = TRUE) else NA_real_
    ),
    stringsAsFactors = FALSE
  )
}

# Efeito de equilibrio de N cenarios lado a lado (uma linha por no, uma
# coluna por cenario) - substitui compare_multiple_states().
compare_scenario_effects <- function(g, scenario_results) {
  stopifnot(inherits(g, "igraph"), is.list(scenario_results), length(scenario_results) >= 1)

  node_names <- V(g)$name

  df <- data.frame(
    id = node_names,
    node = if (!is.null(V(g)$label)) V(g)$label else node_names,
    category = if (!is.null(V(g)$dpsir_category)) V(g)$dpsir_category else rep("", length(node_names)),
    stringsAsFactors = FALSE
  )

  for (scenario_name in names(scenario_results)) {
    df[[scenario_name]] <- unname(scenario_results[[scenario_name]]$equilibrium[node_names])
  }

  df
}
