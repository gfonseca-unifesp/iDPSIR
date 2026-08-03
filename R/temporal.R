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
temporal_step <- function(x, W, growth_rate, threshold_matrix, reference_values, p) {
  gated_W <- apply_threshold_gate(W, x, threshold_matrix, reference_values)
  x + growth_rate * x + as.numeric(gated_W %*% x) + p
}

# Roda duas rodadas lado a lado - baseline (so p_D) e cenario (p_D+p_R) -
# por `windows` janelas discretas, cada perturbacao podendo ser "impulse"
# (ativa so na janela 1) ou "permanent" (ativa em toda janela). Devolve o
# historico completo (janela x no) das duas rodadas, comecando de x=0 na
# janela 0 - quem quiser so os nos de Impacto ou so a ultima janela filtra
# depois (ver format_temporal_table() abaixo).
#
# `on_step`, opcional (Revisao 1, Fase 6): callback chamado a cada janela
# como `on_step(t, windows)`, ANTES de qualquer dependencia de Shiny entrar
# neste arquivo - este motor continua puro/testavel sem shiny carregado.
# mod_responses.R passa uma funcao que chama shiny::incProgress() aqui, pra
# a UI mostrar "Simulando janela X de N" em vez de parecer travada - default
# NULL (no-op), comportamento identico a antes desta mudanca.
simulate_temporal_pair <- function(g, p_D, p_R, windows = 5,
                                    mode_D = c("permanent", "impulse"),
                                    mode_R = c("impulse", "permanent"),
                                    growth_rate = NULL,
                                    threshold_matrix = NULL,
                                    reference_values = NULL,
                                    stability_cap = 0.9,
                                    on_step = NULL) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(windows >= 1)
  stopifnot(stability_cap > 0, stability_cap < 1)
  mode_D <- match.arg(mode_D)
  mode_R <- match.arg(mode_R)

  W <- build_interaction_matrix(g)
  node_names <- rownames(W)
  n <- nrow(W)

  # Real bug, confirmed against a generated report (rede do Mangi): the raw
  # interaction matrix's spectral radius can be well above 1 (rho(W)~4 for
  # Mangi's own network) - since each window's update is x + growth*x +
  # W%*%x + p, an UNSCALED W with rho(W)>1 makes the propagated term
  # amplify every single window (roughly rho(W)-fold), independent of
  # growth_rate or self_regulation, which is baked into W's diagonal and
  # gets swamped by the same unscaled off-diagonal terms it's supposed to
  # counteract. That's not a modeled dynamic, it's the discrete recursion
  # blowing up numerically - confirmed by hand: Mangi's Impacts grew ~5x
  # per window, matching rho(W)~4 almost exactly.
  #
  # Deliberately NOT the static reading's "always normalize to a fixed c"
  # (R/sufficiency.R's propagate()) - that would rescale even networks that
  # are already perfectly well-behaved (Gnanapragasam's own W has
  # rho(W)=0.35, comfortably < 1, confirmed by hand before choosing this
  # design), which would have meant re-deriving every already-verified
  # number in the tutorial's worked example for no reason other than
  # matching the static engine's habit. Instead this ONLY intervenes when
  # the network would actually diverge: `lambda = min(1, stability_cap /
  # rho(W))` when rho(W) > 0, so a network with rho(W) <= stability_cap is
  # left completely untouched (lambda=1, identical to before this fix),
  # and only a genuinely unstable one gets scaled down - by just enough to
  # cap the per-window gain at `stability_cap` (< 1, so it now decays
  # instead of exploding), never further. `stability_cap` is a fixed
  # numerical-safety margin, not a user-facing modeling choice like the
  # static reading's "how far to trace the effect" (effect_horizon) -
  # deliberately NOT reusing that slider here, since conflating "how far
  # an effect should be trusted to propagate" (a modeling question) with
  # "how much to dampen so the numbers don't blow up" (a stability
  # question) would let a user's effect_horizon choice silently change
  # whether their network diverges, which has nothing to do with what
  # that slider is supposed to mean. A genuinely nilpotent W (rho(W)=0 -
  # every network without a feedback cycle, e.g. a pure Driver-to-Impact
  # chain) can't blow up exponentially through W alone regardless of
  # scaling (its powers are exactly zero past a finite point, so
  # (I+W)^t grows only polynomially in t, not geometrically) - left at
  # lambda=1 too, nothing to fix there.
  rho_W <- spectral_radius(W)
  lambda <- if (rho_W > 0) min(1, stability_cap / rho_W) else 1

  # Even after the cap above, a network can still be genuinely unbounded:
  # for any eigenvalue mu of W with Re(mu) > 0 (a true reinforcing loop -
  # confirmed present in the Mangi network, dominant eigenvalue
  # 2.6+3.1i), no positive lambda can bring |1+lambda*mu| below 1 - that's
  # not a step-size artifact, it's the network's own topology outrunning
  # its configured self_regulation. rho(I + lambda*W) detects this
  # directly (spectral_radius() already handles complex eigenvalues via
  # Mod(), same as everywhere else in this app). Deliberately checks W's
  # contribution ALONE, excluding growth_rate: growth_rate is an already-
  # documented, intentional exogenous trend (population growth, etc.) that
  # legitimately compounds on its own and would make this check fire for
  # almost any network with growth_rate>0 - noise, not signal, since that
  # growth isn't the "hidden feedback loop" this warning is meant to catch.
  #
  # Threshold is STRICTLY > 1 (with a small numeric tolerance), not >= 1 -
  # a real distinction, not a rounding nicety. Any node without
  # self_regulation (an Impact, most Drivers/Pressures) contributes an
  # eigenvalue of exactly 0 to W, which lands M's eigenvalue at EXACTLY 1 -
  # that's the already-documented, expected "ratchet, no natural recovery"
  # behavior (see the self_regulation=0 test in test-temporal.R: an
  # impulse just holds steady forever, it doesn't grow). >= 1 flagged that
  # constantly (confirmed: it fired on the plain 5-node test fixture with
  # NO feedback cycle at all, and even on the self_regulation=2 fixture,
  # which decays on the node that has it and merely holds steady - never
  # grows - on the rest) - noise on nearly every network, not signal.
  # > 1 fires only when some mode of M genuinely amplifies each window,
  # confirmed against Mangi (1.72, correctly flagged) and Gnanapragasam
  # (exactly 1.00, correctly NOT flagged - its own growth is entirely
  # growth_rate-driven and already explained in the tutorial, not a
  # topology loop).
  rho_topology <- spectral_radius(diag(n) + lambda * W)
  stability <- list(rho_W = rho_W, lambda = lambda, unbounded = rho_topology > 1 + 1e-6)

  W <- lambda * W

  if (is.null(growth_rate)) growth_rate <- build_growth_rate_vector(g)
  if (is.null(reference_values)) reference_values <- build_reference_values(g)
  if (is.null(threshold_matrix)) threshold_matrix <- build_threshold_matrix(g)

  p_D <- as.numeric(p_D)
  p_R <- as.numeric(p_R)

  x_baseline <- setNames(rep(0, n), node_names)
  x_scenario <- setNames(rep(0, n), node_names)

  hist_baseline <- matrix(0, nrow = windows + 1, ncol = n, dimnames = list(NULL, node_names))
  hist_scenario <- matrix(0, nrow = windows + 1, ncol = n, dimnames = list(NULL, node_names))

  for (t in seq_len(windows)) {
    p_D_t <- if (mode_D == "impulse" && t > 1) rep(0, n) else p_D
    p_R_t <- if (mode_R == "impulse" && t > 1) rep(0, n) else p_R

    x_baseline <- temporal_step(x_baseline, W, growth_rate, threshold_matrix, reference_values, p_D_t)
    x_scenario <- temporal_step(x_scenario, W, growth_rate, threshold_matrix, reference_values, p_D_t + p_R_t)

    hist_baseline[t + 1, ] <- x_baseline
    hist_scenario[t + 1, ] <- x_scenario

    if (!is.null(on_step)) on_step(t, windows)
  }

  list(baseline = hist_baseline, scenario = hist_scenario, windows = windows, stability = stability)
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
format_temporal_table <- function(g, temporal_result, threshold = 1e-9) {
  categories <- V(g)$dpsir_category
  is_impact <- !is.null(categories) & categories == "Impact"
  impact_ids <- V(g)$name[is_impact]

  empty <- data.frame(
    id = character(), node = character(), window = integer(),
    baseline_impact = numeric(), scenario_impact = numeric(),
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

    verdict <- ifelse(
      abs(s) <= threshold, "Neutralized",
      ifelse(
        s < -threshold, "Improved beyond neutral",
        ifelse(s >= b - threshold, "Failure/worsened", "Partial")
      )
    )

    data.frame(
      id = impact_ids, node = impact_labels, window = t,
      baseline_impact = unname(b), scenario_impact = unname(s),
      verdict = verdict, stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}
