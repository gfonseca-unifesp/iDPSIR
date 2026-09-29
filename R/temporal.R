# =====================================================
# TEMPORAL ENGINE - DISCRETE WINDOWS (Revisao 1, Fase 4)
# =====================================================
#
# A leitura estatica (R/sufficiency.R) responde "a resposta cobre a
# piora?" num unico instante. Revisando o artigo do Gnanapragasam et al.
# 2026 com o usuario, ficou claro que tempo importa de verdade pro DPSIR:
# uma resposta a um Impacto (auxilio pos-tsunami/pos-guerra a perda de
# renda) pode, JANELAS DEPOIS, se tornar ela mesma uma forca de pressao
# nova (mais barcos entregues como auxilio -> mais esforco de pesca) - um
# efeito indireto invisivel numa leitura de um so instante.
#
# Este motor e deliberadamente OPCIONAL e aditivo a sufficiency() - nao
# exige nenhum dado a mais do usuario pra continuar usando a leitura
# estatica. Tambem nao busca convergencia/equilibrio (ao contrario do
# motor antigo, R/loop_analysis.R): roda um numero fixo de janelas
# discretas e reporta o que aconteceu em cada uma, sem perguntar se a
# rede "se assenta" - e exatamente essa pergunta (estabilidade) que
# tornava o motor antigo fragil (toda rede que este app constroi tem
# trace(A)=0, nunca e estavel no sentido de autovalor).
#
# Equacao de atualizacao por no i, por janela discreta t:
#
#   x_i(t+1) = x_i(t) + growth_rate_i * x_i(t) + sum_j gate_ji(t) * (lambda*W)[i,j] * x_j(t) + p_i(t)
#
# `lambda*W` (nao o W bruto de build_interaction_matrix()) - ver o
# comentario dentro de simulate_temporal_pair() pra por que: sem esse
# fator de contracao, uma rede cujo raio espectral de W passe de 1
# (comum com poucos ciclos de feedback e pesos moderados - confirmado
# ~4 na rede do Mangi) faz esta recursao explicita divergir
# geometricamente a cada janela, um artefato numerico da discretizacao,
# nao um dinamismo real da rede.
#
# W = build_interaction_matrix(g) (R/loop_analysis.R) - ja inclui a
# auto-regulacao na diagonal (Fase 9), entao NAO ha um termo separado de
# self_regulation aqui: somar de novo seria contar duas vezes o mesmo
# efeito. growth_rate e um termo a parte de proposito - e uma tendencia
# EXOGENA do proprio no (crescimento populacional, tendencia de consumo),
# independente da estrutura do grafo, ao contrario da auto-regulacao (que
# e sobre como o no reage ao proprio desvio) e das arestas (que sao sobre
# como um no reage a OUTRO no).
#
# gate_ji(t) = 1 sempre que a aresta j->i nao tem threshold definido;
# caso contrario, 1 sse |x_j(t)| / reference_value_j >= threshold(j->i).
# `threshold` e `reference_value` sao lidos tal qual estao guardados no
# grafo - nenhuma normalizacao extra acontece aqui. Antes da Fase 5 (que
# adiciona a coluna `reference_value` nos Nos), build_reference_values()
# devolve 1 pra todo mundo, entao a divisao e um no-op e o threshold se
# comporta como magnitude absoluta, exatamente como hoje - o motor ja
# nasce "pronto pra relativo" sem precisar de mudanca nenhuma quando a
# Fase 5 adicionar a coluna de verdade.
#
# p_i(t): forca externa (pressao + resposta), impulso (so no passo 1) ou
# permanente (todo passo) - ver simulate_temporal_pair() abaixo. Pressao e
# resposta sao simuladas JUNTAS na mesma rodada (nunca separadas e somadas
# depois): a decomposicao aditiva worsening+mitigation da leitura estatica
# depende de propagate() ser linear, e o threshold-gating aqui quebra essa
# linearidade de proposito (e o proprio ponto do mecanismo). Por isso
# comparamos duas RODADAS completas - baseline (so p_D) e cenario
# (p_D+p_R) - em vez de tentar decompor uma unica rodada combinada.
#
# Achado real, testado antes de decidir a Fase 5 (nao assumido):
# reaproveitar as magnitudes categoricas que self_regulation tinha ANTES
# da Fase 5 (none=0, low=-0.5, medium=-1, high=-2 - eram
# self_regulation_magnitudes(), R/loop_analysis.R, removida pela propria
# Fase 5 por causa exatamente deste achado) direto nesta equacao de
# diferenca discreta OSCILA em vez de decair.
# x(t+1) = x(t) + sr*x(t) = (1+sr)*x(t) so decai suavemente quando
# |1+sr| < 1; com sr=-2 (o "high" antigo), (1+sr) = -1 exatamente - o
# estado flip-flopa de sinal pra sempre com a MESMA magnitude, nem cresce
# nem encolhe (confirmado rodando scratchpad/test_temporal2.R: impulso de
# -1 em S1 com self_regulation="high" vira -1,1,-1,1,-1,... eternamente,
# nao decai rumo a 0). As magnitudes antigas foram calibradas pro Euler
# IMPLICITO do motor antigo (solve(I - step_size*A)), nao pra uma diferenca
# EXPLICITA direta - reforca por que a Fase 5 precisa mesmo trocar
# self_regulation pra uma fracao continua em [0,1) aplicada como
# `x(t+1) -= self_regulation * x(t)` (sempre negativado internamente na
# diagonal por build_interaction_matrix()), nao um capricho de UX: e o que
# garante decaimento geometrico limpo (`x(t+1) = (1-self_regulation)*x(t)`)
# em vez de oscilacao.

# Taxa de crescimento propria do no - tendencia exogena, independente das
# arestas (Revisao 1 Fase 5 adiciona a coluna `growth_rate` em Nos; leitura
# tolerante aqui, mesmo padrao NULL-safe de self_regulation_diagonal() em
# R/loop_analysis.R, entao este motor ja funciona antes dessa coluna
# existir - devolve 0 pra todo mundo, comportamento constante de hoje).
build_growth_rate_vector <- function(g) {
  node_names <- V(g)$name
  gr <- V(g)$growth_rate
  if (is.null(gr)) {
    return(setNames(rep(0, length(node_names)), node_names))
  }
  values <- suppressWarnings(as.numeric(gr))
  values[is.na(values)] <- 0
  setNames(values, node_names)
}

# Valor de referencia por no - a escala em que `threshold` (aresta) passa
# a ser expresso como fracao 0-1 (Revisao 1 Fase 5 adiciona a coluna
# `reference_value` em Nos; default 1 - antes dessa coluna existir, ou
# quando em branco, threshold se comporta como magnitude absoluta,
# igual ao motor antigo faz hoje).
build_reference_values <- function(g) {
  node_names <- V(g)$name
  rv <- V(g)$reference_value
  if (is.null(rv)) {
    return(setNames(rep(1, length(node_names)), node_names))
  }
  values <- suppressWarnings(as.numeric(rv))
  values[is.na(values) | values == 0] <- 1
  setNames(values, node_names)
}

# Aplica o gatilho de threshold a W pro estado atual x - mesma convencao
# de matriz (linha=to, coluna=from) e mesma tecnica vetorizada (replicar
# o estado de origem por coluna, comparar contra a matriz de threshold)
# ja usada por simulate_trajectory_thresholded() (R/loop_analysis.R), so
# que aqui a comparacao e relativa ao reference_value da origem, nao
# absoluta.
apply_threshold_gate <- function(W, x, threshold_matrix, reference_values) {
  n <- nrow(W)

  if (is.null(threshold_matrix) || !any(!is.na(threshold_matrix))) {
    return(W)
  }

  relative_state <- abs(x) / reference_values
  state_by_column <- matrix(relative_state, nrow = n, ncol = n, byrow = TRUE)
  below_threshold <- !is.na(threshold_matrix) & state_by_column < threshold_matrix

  W_eff <- W
  W_eff[below_threshold] <- 0
  W_eff
}

# Um passo discreto da equacao no topo do arquivo. `W` aqui e o interaction
# matrix JA CONTRAIDO (ver `contraction_c` em simulate_temporal_pair() logo
# abaixo) - nao o W bruto de build_interaction_matrix().
# Revisao 2, item C3: the State gates come from R/triggers.R (threshold as a
# level with a direction, D23; criterion "state_level" or "load", D11).
# Returns the new state and which gates were open in this window.
temporal_step <- function(x, W, growth_rate, th, g, gate_mode, p) {
  gated <- temporal_gate_matrix(W, x, th, g, gate_mode)
  list(x = x + growth_rate * x + as.numeric(gated$W %*% x) + p, open = gated$open)
}

# Runs two rounds side by side - baseline (p_D only) and scenario
# (p_D + p_R) - window by window, each push either "impulse" (window 1 only)
# or "permanent" (every window). Returns the full history (window x node)
# of both rounds, starting from x = 0 at window 0.
#
# Revisao 2, Fase A (decisions D1/D2 revised on 29/09):
# - mode_R defaults to "permanent", like mode_D.
# - stop_rule: "until_neutralized" (default) runs until the response
#   neutralizes the Impacts it reaches, up to max_windows (default 50);
#   "fixed" runs exactly `windows`. Passing `windows` without `stop_rule`
#   keeps the older fixed-length behaviour (existing callers and tests).
#   The stop criterion is ABSOLUTE (net <= tol_abs, i.e. reached or crossed
#   zero), never the relative tolerance of the table (see
#   format_temporal_table()): when the baseline grows faster than the
#   scenario, |net| can drop below 5% of the baseline while the Impact is
#   still getting worse. Only Impacts reached by the active responses AND
#   already worsened in the baseline in that window count - so the run does
#   not stop before the problem has even arrived through the chain.
# - baseline_without_response: the baseline round ignores every edge
#   arriving at a Response node (Impact -> Response links), so it is a true
#   "no response at all" baseline. Off by default (older behaviour).
# - Item 2.5: no more stability_cap rescaling. Edge strengths are
#   standardized coefficients (data, Fase 1), not free to be shrunk; the
#   warning for a loop that outgrows its self-regulation stays.
#
# `on_step(t, windows)` (Revisao 1, Fase 6) is an optional progress
# callback, so this engine stays Shiny-free.
simulate_temporal_pair <- function(g, p_D, p_R, windows = 5,
                                    mode_D = c("permanent", "impulse"),
                                    mode_R = c("permanent", "impulse"),
                                    stop_rule = c("until_neutralized", "fixed"),
                                    max_windows = 50,
                                    tol_abs = 1e-9,
                                    baseline_without_response = FALSE,
                                    gate_mode = c("state_level", "load"),
                                    growth_rate = NULL,
                                    on_step = NULL) {
  stopifnot(inherits(g, "igraph"))
  if (missing(stop_rule) && !missing(windows)) stop_rule <- "fixed"
  mode_D <- match.arg(mode_D)
  mode_R <- match.arg(mode_R)
  stop_rule <- match.arg(stop_rule)
  gate_mode <- match.arg(gate_mode)
  n_windows <- if (stop_rule == "fixed") windows else max_windows
  stopifnot(n_windows >= 1)

  W <- build_interaction_matrix(g)
  node_names <- rownames(W)
  n <- nrow(W)

  # Warning only (item 2.5): some mode of (I + W) amplifies every window -
  # a reinforcing loop stronger than the configured self-regulation.
  # Eigenvalue exactly 1 (a node without self-regulation holding its value)
  # is the documented "ratchet", not flagged.
  rho_W <- spectral_radius(W)
  rho_topology <- spectral_radius(diag(n) + W)
  stability <- list(rho_W = rho_W, lambda = 1, unbounded = rho_topology > 1 + 1e-6)

  W_baseline <- W
  if (isTRUE(baseline_without_response)) {
    categories <- V(g)$dpsir_category
    response_ids <- node_names[!is.null(categories) & categories %in% get_feedback_categories_safe(g)]
    W_baseline[response_ids, ] <- 0
    W_baseline[cbind(match(response_ids, node_names), match(response_ids, node_names))] <- diag(W)[match(response_ids, node_names)]
  }

  if (is.null(growth_rate)) growth_rate <- build_growth_rate_vector(g)
  th <- state_thresholds(g)

  # Revisao 2, item 0.3: align by name (R/sufficiency.R), never by position.
  p_D <- unname(align_press_vector(p_D, node_names, "pressure scenario"))
  p_R <- unname(align_press_vector(p_R, node_names, "response scenario"))

  # Impacts that count for the stop criterion: reached by the active
  # response(s).
  categories <- V(g)$dpsir_category
  impact_ids <- node_names[!is.null(categories) & categories == "Impact"]
  active_responses <- node_names[p_R != 0]
  reached_impacts <- intersect(response_reach(g, active_responses)$reached_ids, impact_ids)

  x_baseline <- setNames(rep(0, n), node_names)
  x_scenario <- setNames(rep(0, n), node_names)
  hist_baseline <- matrix(0, nrow = n_windows + 1, ncol = n, dimnames = list(NULL, node_names))
  hist_scenario <- matrix(0, nrow = n_windows + 1, ncol = n, dimnames = list(NULL, node_names))

  neutralized_at <- NA_integer_
  ran <- n_windows
  gates_baseline <- matrix(NA, nrow = n_windows, ncol = nrow(th), dimnames = list(NULL, th$id))
  gates_scenario <- gates_baseline

  for (t in seq_len(n_windows)) {
    p_D_t <- if (mode_D == "impulse" && t > 1) rep(0, n) else p_D
    p_R_t <- if (mode_R == "impulse" && t > 1) rep(0, n) else p_R

    step_b <- temporal_step(x_baseline, W_baseline, growth_rate, th, g, gate_mode, p_D_t)
    step_s <- temporal_step(x_scenario, W, growth_rate, th, g, gate_mode, p_D_t + p_R_t)
    x_baseline <- setNames(step_b$x, node_names)
    x_scenario <- setNames(step_s$x, node_names)
    if (nrow(th) > 0) {
      gates_baseline[t, ] <- step_b$open
      gates_scenario[t, ] <- step_s$open
    }

    hist_baseline[t + 1, ] <- x_baseline
    hist_scenario[t + 1, ] <- x_scenario

    if (!is.null(on_step)) on_step(t, n_windows)

    if (is.na(neutralized_at) && length(reached_impacts) > 0) {
      considered <- reached_impacts[x_baseline[reached_impacts] > tol_abs]
      if (length(considered) > 0 && all(x_scenario[considered] <= tol_abs)) {
        neutralized_at <- t
        if (stop_rule == "until_neutralized") {
          ran <- t
          break
        }
      }
    }
  }

  list(
    baseline = hist_baseline[seq_len(ran + 1), , drop = FALSE],
    scenario = hist_scenario[seq_len(ran + 1), , drop = FALSE],
    windows = ran,
    stop_rule = stop_rule,
    max_windows = if (stop_rule == "until_neutralized") max_windows else NA_integer_,
    neutralized_at = neutralized_at,
    reached_impacts = reached_impacts,
    gate_mode = gate_mode,
    thresholds = th,
    gates_baseline = gates_baseline[seq_len(ran), , drop = FALSE],
    gates_scenario = gates_scenario[seq_len(ran), , drop = FALSE],
    stability = stability
  )
}

# Feedback (Response) categories of the graph's own schema when it carries
# one; the default DPSIR "Response" otherwise.
get_feedback_categories_safe <- function(g) {
  sch <- tryCatch(get_default_dpsir_schema(), error = function(e) NULL)
  if (is.null(sch)) return("Response")
  tryCatch(get_feedback_categories(sch), error = function(e) "Response")
}

# Plain-language line about how the run ended (until_neutralized) - shared
# by the Scenarios tab and the report.
temporal_stop_note <- function(tr) {
  if (!identical(tr$stop_rule, "until_neutralized")) {
    if (is.na(tr$neutralized_at)) return(NULL)
    return(sprintf("The response neutralizes the Impacts it reaches at window %d.", tr$neutralized_at))
  }
  if (length(tr$reached_impacts) == 0) {
    return(sprintf("The active response(s) reach no Impact, so there is nothing to neutralize - ran all %d windows.", tr$max_windows))
  }
  if (is.na(tr$neutralized_at)) {
    return(sprintf("Not neutralized within %d windows.", tr$max_windows))
  }
  sprintf("Neutralized at window %d: every Impact the response reaches is at or below zero.", tr$neutralized_at)
}

# Plain-language note for temporal_result$stability - NULL when the network
# is fine (nothing to say), a warning string when the topology's own
# reinforcing loop outgrows what stability_cap/self_regulation can offset
# (see the comment inside simulate_temporal_pair() above). Kept separate
# from the table/storyboard renderers so both R/modules/mod_responses.R and
# R/report.R show the exact same wording without duplicating it.
temporal_stability_note <- function(stability) {
  if (is.null(stability) || !isTRUE(stability$unbounded)) return(NULL)
  paste(
    "This network has a reinforcing feedback loop that its configured self-regulation doesn't fully offset -",
    "factor values will keep growing window after window instead of settling down. Treat this simulation as a",
    "directional signal (is the response still helping relative to no response, at each window?), not as a",
    "forecast that converges to a final number."
  )
}

# Uma linha por Impacto x janela: Impact_i(t) = x_i(t) (valor bruto, com
# sinal) nas duas rodadas, e o veredito dessa janela (total/parcial/falha)
# comparando as duas - a generalizacao pra multiplas janelas do criterio
# de sucesso da leitura estatica (neutralized = net <= threshold).
#
# Bug real corrigido, confirmado contra um relatorio gerado de verdade
# (rede do Mangi): uma versao anterior mostrava `max(0, x_i(t))` em vez do
# valor bruto, e classificava "Neutralized" sempre que esse valor
# flor-a-zero desse zero. Numa rede que estava DIVERGINDO (ver o fix de
# `contraction_c` em simulate_temporal_pair() acima), x oscila de sinal a
# cada poucas janelas sem nunca de fato se aproximar de zero em modulo -
# flor-a-zero escondia essa oscilacao toda vez que x calhava de estar
# negativo naquela janela especifica, entao a tabela mostrava "Scenario:
# 0.000, Neutralized" em toda janela, uma ilusao de sucesso permanente
# construida em cima do mesmo artefato numerico. Mostra o valor bruto (com
# sinal) nas duas rodadas.
#
# Segundo bug real, corrigido numa revisao posterior (avaliacao de um plano
# trazido pelo usuario, verificado antes de aceitar - ver CLAUDE.md): a
# correcao acima ainda julgava o veredito pelo MODULO do valor bruto
# (`abs(s) < abs(b)` => "Partial", senao "Failure/worsened"), ignorando o
# SINAL - um cenario que ultrapassa zero pra o lado bom (ex.: baseline=10,
# scenario=-50, sob a convencao "Impacto = problema, positivo = pior"
# documentada no tutorial) tinha `abs(-50)=50 >= abs(10)=10`, caindo em
# "Failure/worsened" quando na verdade e o oposto: a resposta nao so
# neutralizou como foi ALEM, deixando o fator melhor que o cenario sem
# pressao nenhuma. Corrigido julgando pelo SINAL, nao pelo modulo: um valor
# negativo (alem do threshold de ruido numerico) e sempre uma melhora sobre
# o neutro, nunca uma piora, nao importa quao grande em modulo.
#
# Coluna renomeada de `scenario_impact` pra `net_impact` (guia externo
# trazido pelo usuario sobre o relatorio como material suplementar,
# CLAUDE.md): a mesma grandeza (pressao+resposta combinadas) ja se chama
# `Net` na tabela de suficiencia (`format_sufficiency_table()`,
# R/sufficiency.R) - "Scenario" nesta tabela era um nome diferente pra a
# mesma coisa, incoerencia de vocabulario entre as duas leituras.
# `baseline_impact` nao muda de nome (so a coluna pressao+resposta e'
# renomeada). O historico de matrizes cru em simulate_temporal_pair()
# (`list(baseline=, scenario=)`) fica como esta de proposito - nao e' uma
# "coluna" exposta ao usuario, e' o array interno consumido em ~10 lugares
# (storyboard antigo, downloads, relatorio); renomear so a saida desta
# funcao ja resolve a incoerencia de vocabulario com risco bem menor.
# Revisao 2, item A3: `tol_rel` (default 5% of the baseline) labels a net
# value that is small relative to the baseline as "Neutralized (relative)" -
# but only while |net| is not growing from the previous window, because a
# baseline that grows faster than the scenario makes that ratio fall even
# while the Impact keeps getting worse. The absolute rules stay as they were.
format_temporal_table <- function(g, temporal_result, threshold = 1e-9, tol_rel = 0.05) {
  categories <- V(g)$dpsir_category
  is_impact <- !is.null(categories) & categories == "Impact"
  impact_ids <- V(g)$name[is_impact]

  empty <- data.frame(
    id = character(), node = character(), window = integer(),
    baseline_impact = numeric(), net_impact = numeric(),
    verdict = character(), stringsAsFactors = FALSE
  )
  if (length(impact_ids) == 0) {
    return(empty)
  }

  impact_labels <- if (!is.null(V(g)$label)) V(g)$label[is_impact] else impact_ids
  windows <- temporal_result$windows

  baseline_impact <- temporal_result$baseline[, impact_ids, drop = FALSE]
  scenario_impact <- temporal_result$scenario[, impact_ids, drop = FALSE]

  rows <- lapply(seq_len(windows + 1) - 1, function(t) {
    b <- baseline_impact[t + 1, ]
    s <- scenario_impact[t + 1, ]
    s_prev <- if (t == 0) s else scenario_impact[t, ]
    not_growing <- abs(s) <= abs(s_prev) + threshold
    relative_ok <- tol_rel > 0 & s > threshold & abs(s) <= tol_rel * abs(b) & not_growing

    verdict <- ifelse(
      abs(s) <= threshold, "Neutralized",
      ifelse(
        s < -threshold, "Improved beyond neutral",
        ifelse(
          relative_ok, "Neutralized (relative)",
          ifelse(s >= b - threshold, "Failure/worsened", "Partial")
        )
      )
    )

    data.frame(
      id = impact_ids, node = impact_labels, window = t,
      baseline_impact = unname(b), net_impact = unname(s),
      verdict = verdict, stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}
