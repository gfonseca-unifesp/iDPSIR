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
#   x_i(t+1) = x_i(t) + growth_rate_i * x_i(t) + sum_j gate_ji(t) * W[i,j] * x_j(t) + p_i(t)
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
# reaproveitar as magnitudes do self_regulation ANTIGO (none=0, low=-0.5,
# medium=-1, high=-2 - ver self_regulation_magnitudes(), R/loop_analysis.R)
# direto nesta equacao de diferenca discreta OSCILA em vez de decair.
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

# Um passo discreto da equacao no topo do arquivo.
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
simulate_temporal_pair <- function(g, p_D, p_R, windows = 5,
                                    mode_D = c("permanent", "impulse"),
                                    mode_R = c("impulse", "permanent"),
                                    growth_rate = NULL,
                                    threshold_matrix = NULL,
                                    reference_values = NULL) {
  stopifnot(inherits(g, "igraph"))
  stopifnot(windows >= 1)
  mode_D <- match.arg(mode_D)
  mode_R <- match.arg(mode_R)

  W <- build_interaction_matrix(g)
  node_names <- rownames(W)
  n <- nrow(W)

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
  }

  list(baseline = hist_baseline, scenario = hist_scenario, windows = windows)
}

# Uma linha por Impacto x janela: Impact_i(t) = max(0, x_i(t)) nas duas
# rodadas, e o veredito dessa janela (total/parcial/falha) comparando as
# duas - a generalizacao pra multiplas janelas do criterio de sucesso da
# leitura estatica (neutralized = net <= threshold).
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

  # pmax() takes dim/attributes from its FIRST argument (documented R
  # behavior) - the matrix must come first, or a single-Impact-node network
  # silently degrades from a matrix to a plain vector here.
  baseline_impact <- pmax(temporal_result$baseline[, impact_ids, drop = FALSE], 0)
  scenario_impact <- pmax(temporal_result$scenario[, impact_ids, drop = FALSE], 0)

  rows <- lapply(seq_len(windows + 1) - 1, function(t) {
    b <- baseline_impact[t + 1, ]
    s <- scenario_impact[t + 1, ]

    verdict <- ifelse(
      s <= threshold, "Neutralized",
      ifelse(s < b - threshold, "Partial", "Failure/worsened")
    )

    data.frame(
      id = impact_ids, node = impact_labels, window = t,
      baseline_impact = unname(b), scenario_impact = unname(s),
      verdict = verdict, stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}
