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
  simulate_trajectory_thresholded(A, press, Th = NULL, steps = steps, step_size = step_size)
}

# Extrai o `activation_threshold` de cada no (opcional, ver R/validate.R)
# numa matriz no mesmo formato de A (Th[to, from]) - NA onde o no de
# origem nao tem threshold definido, valor numerico onde tem. Passada pra
# simulate_trajectory_thresholded() como o "gatilho" que liga/desliga
# cada aresta durante a simulacao.
#
# Segunda rodada da Revisao 1: threshold deixou de ser escolhido aresta a
# aresta e virou um unico valor por no de origem - toda aresta que sai de
# um no com `activation_threshold` definido é gatilhada pelo MESMO
# valor (o desvio simulado desse no de origem), nao mais uma aresta
# individual podendo esperar um gatilho e a aresta-irma do mesmo State
# ficando sempre ligada. Simplifica o modelo mental ("a partir de X% de
# desvio, esse fator passa a afetar tudo que ele alimenta") e casa com o
# proprio motivo do threshold existir: e uma propriedade da variavel de
# estado (um ponto de virada ecologico), nao de um link causal especifico.
build_threshold_matrix <- function(g) {
  stopifnot(inherits(g, "igraph"))

  node_names <- V(g)$name
  n <- length(node_names)
  Th <- matrix(NA_real_, nrow = n, ncol = n, dimnames = list(node_names, node_names))

  if (ecount(g) == 0 || is.null(V(g)$activation_threshold)) {
    return(Th)
  }

  node_threshold <- suppressWarnings(as.numeric(V(g)$activation_threshold))
  names(node_threshold) <- node_names

  edge_ends <- ends(g, E(g), names = TRUE)

  for (k in seq_len(nrow(edge_ends))) {
    from_node <- edge_ends[k, 1]
    to_node <- edge_ends[k, 2]
    th <- node_threshold[[from_node]]
    if (is.na(th)) next
    Th[to_node, from_node] <- th
  }

  Th
}

# Mesma trajetoria de simulate_trajectory(), com um "gatilho" opcional por
# aresta: se `Th[to, from]` nao for NA, essa aresta so contribui pro no de
# destino a partir do passo em que |estado do no de origem| ultrapassa esse
# valor - antes disso, contribui zero, como se a aresta nao existisse ainda.
# Arestas sem threshold (`Th` = NA, o padrao) continuam ligadas o tempo
# todo, exatamente como antes - por isso simulate_trajectory() acima e so um
# atalho pra esta funcao com `Th = NULL` (testado batendo numero por numero
# contra a versao anterior a essa mudanca, sem thresholds nenhuma rede muda).
#
# O "State value that triggers the Impact" que motivou o pedido do usuario
# nao e um nivel absoluto (o motor inteiro so modela DESVIO causado por uma
# Resposta, nunca o nivel absoluto de nada - nao ha um "baseline" de
# Driver/Pressure sendo simulado, so a Resposta entra como `press`). Entao o
# threshold aqui e sobre o quanto o CENARIO SIMULADO precisa deslocar o no de
# origem (em modulo) antes da aresta ligar - uma simplificacao deliberada,
# nao um nivel ambiental absoluto independente do cenario. Documentado assim
# no tutorial/CLAUDE.md pra nao vender a funcionalidade como mais do que e.
#
# check_stability()/press_perturbation()/robustness_check() continuam
# ignorando threshold de proposito - eles descrevem o regime linear/de
# pequena perturbacao (a mesma matriz A de sempre); so a trajetoria
# passo-a-passo, que ja simula o cenario se desenrolando no tempo, ganha o
# gatilho no-linear.
simulate_trajectory_thresholded <- function(A, press, Th = NULL, steps = 10, step_size = 0.5) {
  stopifnot(is.matrix(A), nrow(A) == ncol(A))
  stopifnot(length(press) == nrow(A))
  stopifnot(steps >= 1)

  node_names <- rownames(A)
  press <- as.numeric(press)
  n <- length(node_names)

  has_threshold <- !is.null(Th) && any(!is.na(Th))
  if (has_threshold) {
    stopifnot(is.matrix(Th), all(dim(Th) == dim(A)))
  }

  trajectory <- matrix(NA_real_, nrow = steps, ncol = n, dimnames = list(NULL, node_names))
  state <- rep(0, n)

  for (step in seq_len(steps)) {
    A_eff <- A

    if (has_threshold) {
      # coluna j = estado (em modulo) do no "from" dessa coluna, replicado
      # em todas as linhas - compara cada A[to,from] contra Th[to,from].
      state_by_column <- matrix(abs(state), nrow = n, ncol = n, byrow = TRUE)
      below_threshold <- !is.na(Th) & state_by_column < Th
      A_eff[below_threshold] <- 0
    }

    update_matrix <- tryCatch(
      solve(diag(n) - step_size * A_eff),
      error = function(e) NULL
    )

    if (is.null(update_matrix)) {
      warning("Trajectory could not be computed for this network (degenerate structure).", call. = FALSE)
      trajectory[step:steps, ] <- NA_real_
      break
    }

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

# +1/0/-1 por entrada, com uma faixa "efetivamente zero" em torno de 0 -
# mesma logica de classificacao usada em summarize_scenario_effect(), so
# que aqui devolve o sinal em vez do rotulo Improves/Worsens/Stable.
classify_effect_sign <- function(x, threshold = 1e-9) {
  ifelse(is.na(x), NA_integer_, ifelse(abs(x) < threshold, 0L, ifelse(x < 0, -1L, 1L)))
}

# Marco D: robustez do sinal do efeito a variacoes no peso das arestas,
# proporcionais a incerteza que o usuario ja registrou em cada uma
# (`confidence`) - alta confianca = pouca variacao, baixa = muita, faixa
# de +-`spread` no peso quando confidence=0 e nenhuma quando confidence=1.
# Roda `n_simulations` reamostragens e mede em quantas delas o sinal do
# efeito em cada no bateu com o resultado original (equilibrio, ou
# imediato quando a matriz e singular) - da um uso real ao `confidence`,
# que ate aqui so controlava o tracejado no grafo. `press` fica fixo (a
# mesma resposta/forca do cenario) - so os pesos das arestas variam.
#
# Roadmap item 6.4: `seed` fixo por padrao (`set.seed(seed)` logo antes de
# reamostrar) - sem isso, aplicar o mesmo cenario duas vezes (ou gerar o
# relatorio duas vezes a partir do mesmo savepoint) dava um "Sign confidence"
# ligeiramente diferente a cada vez, so por causa do sorteio dos pesos, o
# que contradiz a propria ideia de um relatorio reprodutivel. Com a semente
# fixa, a mesma chamada (mesmo grafo/press/n_simulations/spread/seed) sempre
# devolve exatamente o mesmo resultado, independente do estado do RNG antes
# de chamar.
robustness_check <- function(g, press, n_simulations = 100, spread = 0.5, threshold = 1e-9, seed = 42) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(n_simulations >= 1)

  node_names <- V(g)$name

  baseline_result <- suppressWarnings(press_perturbation(build_interaction_matrix(g), press))
  baseline_effect <- baseline_result$equilibrium
  used_immediate <- all(is.na(baseline_effect))
  if (used_immediate) baseline_effect <- baseline_result$immediate
  baseline_sign <- classify_effect_sign(baseline_effect, threshold)

  confidence <- E(g)$confidence
  confidence[is.na(confidence)] <- 0.5
  base_weight <- E(g)$weight
  variation <- (1 - confidence) * spread

  matches <- matrix(0L, nrow = n_simulations, ncol = length(node_names), dimnames = list(NULL, node_names))
  g_sim <- g
  any_singular <- used_immediate

  set.seed(seed)
  for (sim in seq_len(n_simulations)) {
    multiplier <- runif(length(base_weight), 1 - variation, 1 + variation)
    E(g_sim)$weight <- base_weight * multiplier

    result_sim <- suppressWarnings(press_perturbation(build_interaction_matrix(g_sim), press))
    effect_sim <- result_sim$equilibrium

    if (all(is.na(effect_sim))) {
      any_singular <- TRUE
      effect_sim <- result_sim$immediate
    }

    matches[sim, ] <- as.integer(classify_effect_sign(effect_sim, threshold) == baseline_sign)
  }

  if (any_singular) {
    warning("Some simulations used the immediate effect instead of equilibrium (singular interaction matrix).", call. = FALSE)
  }

  data.frame(
    id = node_names,
    node = if (!is.null(V(g)$label)) V(g)$label else node_names,
    category = if (!is.null(V(g)$dpsir_category)) V(g)$dpsir_category else rep("", length(node_names)),
    agreement_pct = unname(colMeans(matches)[node_names]) * 100,
    stringsAsFactors = FALSE
  )
}

# =====================================================
# SENSITIVITY TO SELF-REGULATION (roadmap Fase 9 item 9.1.4)
# =====================================================
#
# Same resampling philosophy as robustness_check() above (Marco D, Fase 5) -
# but perturbs each node's self-regulation MAGNITUDE instead of each edge's
# weight, and leaves edge weights untouched entirely (that uncertainty is
# what robustness_check()/sign_determinacy() already cover; this is
# specifically about how much the result depends on the self-regulation
# assumption). Continuous magnitude resampling (`magnitude * runif(1-spread,
# 1+spread)`), not discrete jumps between none/low/medium/high levels -
# keeps this consistent with the one resampling mechanism already used
# everywhere else in this file, rather than inventing a second kind of
# randomness. A node marked "none" has magnitude 0, and 0 times anything is
# still 0, so it's correctly excluded from the perturbation with no
# special-casing needed.
self_regulation_sensitivity <- function(g, press, n_simulations = 100, spread = 0.5, threshold = 1e-9, seed = 42) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(n_simulations >= 1)

  node_names <- V(g)$name
  base_diag <- self_regulation_diagonal(g)

  A_base <- build_interaction_matrix(g)
  baseline_result <- suppressWarnings(press_perturbation(A_base, press))
  baseline_effect <- baseline_result$equilibrium
  used_immediate <- all(is.na(baseline_effect))
  if (used_immediate) baseline_effect <- baseline_result$immediate
  baseline_sign <- classify_effect_sign(baseline_effect, threshold)

  matches <- matrix(0L, nrow = n_simulations, ncol = length(node_names), dimnames = list(NULL, node_names))
  A_sim <- A_base
  any_singular <- used_immediate

  set.seed(seed)
  for (sim in seq_len(n_simulations)) {
    multiplier <- runif(length(base_diag), 1 - spread, 1 + spread)
    diag(A_sim) <- base_diag * multiplier

    result_sim <- suppressWarnings(press_perturbation(A_sim, press))
    effect_sim <- result_sim$equilibrium

    if (all(is.na(effect_sim))) {
      any_singular <- TRUE
      effect_sim <- result_sim$immediate
    }

    matches[sim, ] <- as.integer(classify_effect_sign(effect_sim, threshold) == baseline_sign)
  }

  if (any_singular) {
    warning("Some simulations used the immediate effect instead of equilibrium (singular interaction matrix).", call. = FALSE)
  }

  data.frame(
    id = node_names,
    node = if (!is.null(V(g)$label)) V(g)$label else node_names,
    category = if (!is.null(V(g)$dpsir_category)) V(g)$dpsir_category else rep("", length(node_names)),
    agreement_pct = unname(colMeans(matches)[node_names]) * 100,
    stringsAsFactors = FALSE
  )
}

# =====================================================
# SIGN DETERMINACY (roadmap item 7.1 - Dambacher et al. framing)
# =====================================================
#
# The literature's "sign determinacy" asks exactly the question
# robustness_check() (Marco D) already answers numerically: if the network's
# edge weights are uncertain, how often does a prediction's SIGN survive
# that uncertainty? The classic route (Dambacher, Puccia & Levins) computes
# this analytically via the interaction matrix's adjoint/permanent - but a
# matrix permanent is combinatorially expensive (Ryser's formula:
# O(2^n * n)) and becomes infeasible past a couple dozen nodes, squarely
# within reach of a real DPSIR network. robustness_check()'s resampling
# approach already IS a practical numerical implementation of the same
# concept, so `sign_determinacy()` is a thin, literature-aligned name for
# it - not a second, independent method to cross-check against.
sign_determinacy <- function(g, press, n_simulations = 100, spread = 0.5, threshold = 1e-9, seed = 42) {
  robustness_check(g, press, n_simulations = n_simulations, spread = spread, threshold = threshold, seed = seed)
}

# Sign confidence (%) de N cenarios lado a lado - mesma forma de
# compare_scenario_effects(), so que com agreement_pct no lugar do efeito de
# equilibrio. Usado na comparacao em tela e na secao "Scenarios compared"
# do relatorio.
compare_scenario_sign_confidence <- function(g, scenario_sign_confidence) {
  stopifnot(inherits(g, "igraph"), is.list(scenario_sign_confidence), length(scenario_sign_confidence) >= 1)

  node_names <- V(g)$name

  df <- data.frame(
    id = node_names,
    node = if (!is.null(V(g)$label)) V(g)$label else node_names,
    category = if (!is.null(V(g)$dpsir_category)) V(g)$dpsir_category else rep("", length(node_names)),
    stringsAsFactors = FALSE
  )

  for (scenario_name in names(scenario_sign_confidence)) {
    sc_df <- scenario_sign_confidence[[scenario_name]]
    df[[scenario_name]] <- sc_df$agreement_pct[match(node_names, sc_df$id)]
  }

  df
}

# =====================================================
# NEUTRALIZATION STEP (fast-follow pos-Fase 5)
# =====================================================
#
# Fase 5 diz QUANTO uma Resposta desloca cada fator (immediate/equilibrium),
# mas nao diz QUANDO - o gestor quer saber em quantos passos um Impacto sera
# de fato neutralizado, nao so que ele "vai melhorar" eventualmente.
# Reaproveita simulate_trajectory() ja existente: "neutralizado" = a
# trajetoria do no atinge pela primeira vez `target_fraction` (default 90%)
# do seu efeito de equilibrio projetado - "rise time" de controle classico,
# nao "settling time" (nao exige que a trajetoria PERMANECA la depois).
#
# Essa distincao nao e cosmetica: gatear isso em check_stability()$stable
# (como uma primeira versao fazia) deixaria a funcao morta na pratica. O
# schema proibe aresta de um no pra ele mesmo, entao a diagonal de A e
# sempre zero, logo trace(A) = soma dos autovalores = 0 sempre, pra
# QUALQUER rede construida pelo app - o que torna check_stability()
# matematicamente incapaz de retornar TRUE nunca (mesmo achado ja
# documentado na avaliacao da Fase 5: uma rede sem nenhum ciclo tem todos os
# autovalores exatamente zero, "nao estavel" por ser marginal, nao por
# divergir; uma rede com ciclo tem autovalores positivos e negativos se
# cancelando). Testado: nem uma cadeia trofica acíclica (sem ciclo) nem uma
# reconstruida com Resposta fechando o loop chegam a "Stable: TRUE". Por
# isso "quantos passos ate neutralizar" usa o mesmo
# equilibrio projetado que a tabela "Effect on each factor" ja mostra (uma
# estimativa direcional, nao garantida) em vez de exigir uma condicao que
# nunca ocorre - a mesma ressalva de "trate como direcao, nao promessa" so
# que aplicada ao numero de passos.
find_neutralization_step <- function(A, press, node, target_fraction = 0.9, max_steps = 500, step_size = 0.5) {
  stopifnot(is.matrix(A), nrow(A) == ncol(A))
  stopifnot(length(press) == nrow(A))
  stopifnot(node %in% rownames(A))
  stopifnot(target_fraction > 0, target_fraction <= 1)

  equilibrium <- suppressWarnings(press_perturbation(A, press)$equilibrium[[node]])
  if (is.na(equilibrium) || abs(equilibrium) < 1e-9) {
    return(NA_integer_)
  }

  trajectory <- simulate_trajectory(A, press, steps = max_steps, step_size = step_size)[, node]
  target_value <- equilibrium * target_fraction

  reached <- if (equilibrium > 0) which(trajectory >= target_value) else which(trajectory <= target_value)
  if (length(reached) == 0) NA_integer_ else min(reached)
}

# Mesma pergunta, resumida por no de categoria Impacto - "estamos de fato
# livrando o sistema de impactos" e nao so "reduzindo a pressao", a
# distincao que motivou o pedido. Uma linha por no de categoria "Impact" na
# rede (categoria hardcoded, mesmo padrao ja usado em
# compute_dpsir_descriptors() pra impacts_without_response); `note` explica
# em texto por que o passo ficou indefinido quando for o caso, em vez de um
# NA cru na tela.
summarize_neutralization <- function(g, press, target_fraction = 0.9, max_steps = 500, step_size = 0.5) {
  stopifnot(inherits(g, "igraph"))

  impact_idx <- which(V(g)$dpsir_category == "Impact")
  if (length(impact_idx) == 0) {
    return(data.frame(
      id = character(), node = character(),
      equilibrium_effect = numeric(), steps_to_neutralize = integer(),
      note = character(), stringsAsFactors = FALSE
    ))
  }

  impact_ids <- V(g)$name[impact_idx]
  impact_labels <- if (!is.null(V(g)$label)) V(g)$label[impact_idx] else impact_ids

  A <- build_interaction_matrix(g)
  equilibrium <- suppressWarnings(press_perturbation(A, press)$equilibrium)
  pct_label <- sprintf("%d%%", round(target_fraction * 100))

  rows <- lapply(seq_along(impact_ids), function(i) {
    id <- impact_ids[i]
    label <- impact_labels[i]
    eq <- equilibrium[[id]]

    if (is.na(eq)) {
      return(data.frame(
        id = id, node = label, equilibrium_effect = NA_real_, steps_to_neutralize = NA_integer_,
        note = "This factor's long-run effect is undefined for this network.", stringsAsFactors = FALSE
      ))
    }

    if (abs(eq) < 1e-9) {
      return(data.frame(
        id = id, node = label, equilibrium_effect = eq, steps_to_neutralize = NA_integer_,
        note = "This response has no long-run effect on this factor.", stringsAsFactors = FALSE
      ))
    }

    step <- find_neutralization_step(A, press, id, target_fraction, max_steps, step_size)
    note <- if (is.na(step)) {
      sprintf("Not reached within %d steps.", max_steps)
    } else {
      sprintf("Reaches %s of its projected effect.", pct_label)
    }

    data.frame(
      id = id, node = label, equilibrium_effect = eq, steps_to_neutralize = step,
      note = note, stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

# =====================================================
# EDGE SENSITIVITY (roadmap item 7.2)
# =====================================================
#
# sign_determinacy() answers "how much can I trust this prediction's
# direction, given how uncertain each edge is". This answers a different,
# complementary question: "if I had estimated ONE edge's weight a bit
# differently, how much would my conclusion have changed" - i.e. which
# edge is most worth double-checking. One-at-a-time (OAT): bump a single
# edge's weight up by `relative_change` (10% by default), recompute the
# equilibrium effect for the same press, and measure how much it moved
# (summed absolute difference across `target_ids`, default every node) -
# reuses press_perturbation() directly, no new resampling/simulation loop
# and no new package (deliberately plain base R, same reasoning that kept
# the trajectory chart on matplot() instead of adding ggplot2 in Marco C).
global_sensitivity <- function(g, press, relative_change = 0.1, target_ids = NULL) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(ecount(g) > 0)

  node_names <- V(g)$name
  if (is.null(target_ids)) target_ids <- node_names

  baseline <- suppressWarnings(press_perturbation(build_interaction_matrix(g), press))
  baseline_effect <- baseline$equilibrium
  if (all(is.na(baseline_effect))) baseline_effect <- baseline$immediate

  edge_ends <- ends(g, E(g), names = TRUE)
  base_weight <- E(g)$weight
  node_labels <- if (!is.null(V(g)$label)) setNames(V(g)$label, node_names) else setNames(node_names, node_names)

  influence <- numeric(ecount(g))
  g_sim <- g

  for (k in seq_len(ecount(g))) {
    E(g_sim)$weight <- base_weight
    E(g_sim)$weight[k] <- base_weight[k] * (1 + relative_change)

    result_sim <- suppressWarnings(press_perturbation(build_interaction_matrix(g_sim), press))
    effect_sim <- result_sim$equilibrium
    if (all(is.na(effect_sim))) effect_sim <- result_sim$immediate

    influence[k] <- sum(abs(effect_sim[target_ids] - baseline_effect[target_ids]))
  }

  out <- data.frame(
    from = edge_ends[, 1],
    to = edge_ends[, 2],
    link = paste0(unname(node_labels[edge_ends[, 1]]), " -> ", unname(node_labels[edge_ends[, 2]])),
    weight = base_weight,
    confidence = E(g)$confidence,
    influence = influence,
    stringsAsFactors = FALSE
  )

  out[order(-out$influence), ]
}
