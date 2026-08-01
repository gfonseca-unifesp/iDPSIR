# CLAUDE.md — iDPSIR

Contexto para assistentes de código trabalhando neste repositório.

## O que é

App **R/Shiny** para construir e analisar redes causais no modelo **DPSIR**
(Driver–Pressure–State–Impact–Response), voltado à **gestão ambiental**.
Objetivo: app científico, minimalista e de evolução incremental.

O plano completo (decisões, arquitetura-alvo, roadmap) está em **`PLANO_iDPSIR.md`** —
leia-o antes de implementar. Este arquivo é o resumo operacional.

## Como rodar e testar

```r
shiny::runApp()          # sobe o app
```

`global.R` verifica no início (`required_packages`/`missing_packages`) se os pacotes
necessários já estão instalados e instala automaticamente os que faltarem (ajustando
`options(repos=...)` para CRAN se nenhum mirror estiver configurado) antes de dar
`library()` neles — não é mais preciso rodar `install.packages()` manualmente antes,
inclusive para quem sobe o app via `shiny::runGitHub("iDPSIR", "gfonseca-unifesp", "main")`
sem ter instalado nada antes.

`jsonlite` é usado só via `jsonlite::` (nunca `library(jsonlite)`) porque ele
mascara `shiny::validate()` quando anexado — cuidado se for usar em outro lugar.

Checagem rápida de sintaxe sem subir o app:
`Rscript -e 'invisible(lapply(list.files("R", "\\.R$", recursive=TRUE, full.names=TRUE), parse))'`

**Sempre teste rodando o app** após mudanças em módulos — erros de Shiny só aparecem em runtime.

## Estrutura

- `app.R` → chama `ina_ui()` / `ina_server()`.
- `global.R` → auto-instala pacotes faltantes, pacotes, opções e `source()` de todos
  os fontes (ordem importa).
- `R/schema.R` → esquema DPSIR configurável (níveis, conexões derivadas da ordem, paletas,
  vocabulários controlados de nós/arestas, legenda). Item 9.1 do
  `ROADMAP_FASE9_iDPSIR.md`: `get_self_regulation_levels() <- c("none","low","medium","high")`,
  mesmo padrão de `get_uncertainty_levels()`/`get_controllability_levels()`.
- `R/validate.R` → validação de nós/arestas contra o schema. `normalize_dpsir_nodes()`
  ganhou o mesmo tratamento opcional-com-default já usado em `threshold`/`reference`
  (edges): `self_regulation` ausente vira `"none"` — sem validação de vocabulário
  contra a lista (mesma lógica leniente de `uncertainty`/`controllability`, que
  também nunca foram validados, só restringidos pelo dropdown do formulário).
- `R/graph.R` → `build_igraph`, mapeamento visual por schema, layout em camadas
  (`compute_layered_layout`) ou circular (`compute_circular_layout`, todos os nós
  igualmente espaçados num anel — `compute_graph_layout` despacha entre os dois por
  `layout_mode`), com sobreposição opcional de posições arrastadas manualmente
  (`apply_manual_positions`, ver Fase 5 fast-follow "layout do grafo" no Estado
  atual). `build_network_visual` (tooltips com `reference` da aresta quando
  presente — ver item 7.3 do roadmap de publicação no Estado atual —, espessura
  por weight, tracejado por confidence, legendas de nó/aresta opcionais via
  `show_node_legend`/`show_edge_legend`), `sanitize_edges`.
- `R/metrics.R` → centralidades (grau, intermediação, proximidade, pagerank, eigenvector —
  com opção `weighted`; betweenness/closeness convertem weight→distância via `1/weight`),
  métricas gerais (densidade, diâmetro, transitividade, modularidade, componentes) e
  descritores DPSIR (`compute_dpsir_descriptors`: contagem por categoria, matriz de
  transições, Impactos sem Resposta, Pressões não cobertas, médias de incerteza/controlabilidade).
- `R/io.R` → importar matrizes CSV (`import_matrices`) e savepoint `.idpsir.json`
  (`build_savepoint`/`write_savepoint`/`read_savepoint`, com checagem de `format_version`;
  `merge_savepoints`, ver Fase 4 abaixo). Revisão 1, Fase 3: `build_savepoint()`
  ganhou `scenario_state` opcional (default `NULL`) — o cenário de
  pressão/resposta configurado na aba Scenarios (ver `mod_responses.R`
  abaixo), pra sobreviver a salvar/recarregar o savepoint, mesmo padrão
  aditivo já usado por `positions` (Fase 5). Guardado como **linhas**
  `data.frame(id, strength)` para pressão e resposta separadamente, não como
  vetor nomeado — `jsonlite::write_json(auto_unbox=TRUE)` desmancha
  silenciosamente um vetor nomeado de tamanho 1 num escalar solto (perdendo
  o nome/id inteiro), confirmado ao vivo; um data.frame de linhas nunca sofre
  esse "unboxing" não importa o número de linhas, o mesmo motivo que já fez
  `positions` usar linhas em vez de vetores x/y nomeados. `read_savepoint()`
  devolve `scenario_state` de volta no formato "vetor nomeado" que
  `mod_responses.R` espera (`response_active`/`response_strengths`/
  `pressure_active`/`pressure_strengths`/`effect_horizon`) — a conversão
  savepoint-JSON-amigável vs. R-amigável fica só dentro de `io.R`, nenhum
  outro arquivo precisa saber dela. `NULL` em `scenario_state` (savepoint
  sem cenário nenhum, ou salvo antes desta revisão) serializa como `"{}"`,
  não `"null"` — `read_savepoint()` usa o mesmo guard duplo
  `is.null(...) || length(...) == 0` que `positions` já usava por esse
  motivo exato.
- `R/pathways.R` → análise de caminhos causais schema-aware (`find_dpsir_paths`,
  `compute_critical_pathways`, `score_pathway`), adaptado de `R/dpsir/core_dpsir_pathways.R`.
- `R/core/core_ui_components.R` → toggles/inputs compartilhados (usados no painel de métricas).
- `R/dpsir/core_dpsir_pathways.R` → versão original (categorias fixas), mantida no disco
  mas **não sourceada**; superada por `R/pathways.R`.
- `R/dpsir/core_dpsir_responses.R` → versão original de onde `R/responses.R` foi
  adaptada, mantida no disco mas **não sourceada**.
- `R/responses.R` → `get_feedback_categories`/`find_response_targets` continuam em
  uso (identificam nós de Resposta). `apply_response`, `compute_node_impact_score`,
  `summarize_response_impact`, `compare_states`, `compare_multiple_states` foram o
  motor da aba Scenarios até a Fase 5 Marco B — mantidas no arquivo mas não mais
  chamadas por nenhum módulo, substituídas por `R/loop_analysis.R` abaixo.
- `R/reach.R` → item 9.2 do `ROADMAP_FASE9_iDPSIR.md`: `response_reach(g, active_ids)`
  (até onde a influência de uma resposta chega na cadeia DPSIR — travessia pura do
  grafo direcionado a partir do que a resposta afeta diretamente, sem nenhuma álgebra
  linear; sempre calculável, ao contrário do efeito de equilíbrio de
  `loop_analysis.R`, que depende da rede se assentar) e `count_impacts_in_graph(g)`
  (denominador pro "Y de N Impactos" — deliberadamente fora de `response_reach()`,
  que fica só sobre o que uma resposta específica alcança).
- `R/loop_analysis.R` → análise de loop / matriz comunitária (Levins 1974).
  Marco A: `build_interaction_matrix(g)` (matriz `A[i,j]` = efeito de `j` sobre `i`,
  sinal de `interaction_type`/magnitude de `weight`), `check_stability(A)`
  (autovalores, `stable`/`eigenvalues`/`max_real_part`), `press_perturbation(A, press)`
  (efeito de um passo `A %*% press` e de equilíbrio `-A^-1 %*% press`; matriz
  singular retorna `NA` com aviso em vez de erro). Marco B, motor da aba Scenarios:
  `build_press_vector(g, active_ids, strengths)` (ativar uma resposta a uma dada
  força vira uma entrada não-zero no vetor de press — combinar respostas é só somar
  mais entradas, sem o encadeamento manual do `apply_response` antigo),
  `summarize_scenario_effect(g, result)` (Improves/Worsens/Stable por nó a partir do
  efeito de equilíbrio, com fallback pro efeito imediato quando a matriz é singular),
  `summarize_scenario_network_effect(result)` (nós afetados + magnitude total,
  imediato vs equilíbrio — substitui as métricas de topologia do `compare_states`
  antigo, que não fazem mais sentido já que o grafo não muda mais, só o estado),
  `compare_scenario_effects(g, scenario_results)` (efeito de equilíbrio de N cenários
  lado a lado, substitui `compare_multiple_states`). Marco C:
  `simulate_trajectory(A, press, steps, step_size = 0.5)` (integra dx/dt = A·x + press
  por Euler implícito a partir de x=0 — incondicionalmente estável para
  Re(autovalor) < 0, então converge pro mesmo equilíbrio de `press_perturbation`
  quando a rede é estável, e diverge quando não é; matriz `I - step_size·A`
  degenerada retorna matriz de `NA` com aviso, mesmo padrão de `press_perturbation`).
  Marco D: `robustness_check(g, press, n_simulations, spread = 0.5)` — o `confidence`
  de cada aresta vira uma faixa de variação de peso (alta confiança = pouca
  variação, baixa = muita), roda N simulações reamostrando os pesos e mede em
  quantas o sinal do efeito em cada nó bateu com o resultado original (equilíbrio,
  ou imediato quando a matriz é singular) — dá um uso real ao `confidence`, que até
  aqui só controlava o tracejado no grafo. Sem dependência nova
  (`eigen()`/`solve()`/`runif()` do R base). Fast-follow pós-Fase 5:
  `find_neutralization_step(A, press, node, target_fraction=0.9, max_steps=500,
  step_size=0.5)` reaproveita `simulate_trajectory()` pra achar o primeiro passo em
  que o efeito num nó atinge 90% do seu efeito de equilíbrio projetado — e
  `summarize_neutralization(g, press)`, o mesmo resumido por nó de categoria
  "Impact" (motor da tabela "When will Impacts be neutralized?" em
  `mod_responses.R`). Deliberadamente **não** exige `check_stability(A)$stable`
  — ver a nota dentro do próprio arquivo: como o schema proíbe aresta de um nó
  pra ele mesmo, a diagonal de `A` é sempre zero, `trace(A)` (= soma dos
  autovalores) é sempre zero, e `check_stability` por isso nunca retorna `TRUE`
  pra nenhuma rede construída pelo app — gatear nisso deixaria a função morta na
  prática. "Neutralizado" aqui é *rise time* (primeiro cruzamento de 90% do
  projetado), não *settling time* (ficar lá depois) — mesma ressalva de
  "estimativa direcional, não garantia" já usada pro número de equilíbrio.
  Fast-follow "threshold não-linear" (versão mínima do item 2b pós-Fase 5, ver
  Estado atual): `build_threshold_matrix(g)` extrai o `threshold` opcional de
  cada aresta (`R/validate.R`) numa matriz `Th[to,from]` no mesmo formato de
  `A`. `simulate_trajectory_thresholded(A, press, Th, steps, step_size)`
  reaproveita o loop de `simulate_trajectory()`, mas a cada passo zera
  temporariamente `A_eff[to,from]` para toda aresta com threshold definido
  cujo nó de origem ainda não ultrapassou (em módulo) esse valor no estado
  simulado — a aresta "liga" no primeiro passo em que ultrapassa, e continua
  ligada dali em diante (não desliga se o estado recuar). `simulate_trajectory()`
  virou um atalho de uma linha pra essa função com `Th = NULL` (testado
  batendo número por número contra o comportamento anterior — nenhuma
  mudança pra quem não usa threshold). `check_stability`/`press_perturbation`/
  `robustness_check`/`find_neutralization_step` continuam ignorando threshold
  de propósito — descrevem só o regime linear; só a trajetória ganha o
  gatilho. Roadmap item 7.1 ("determinância de sinal", vocabulário de
  Dambacher et al.): `sign_determinacy(g, press, n_simulations=100, spread=0.5)`
  é um alias fino de `robustness_check()` — mesma reamostragem de peso por
  `confidence`, só com o nome alinhado à literatura, sem virar um segundo
  método independente pra validar contra o primeiro (a rota analítica via
  permanente da matriz é combinatorialmente inviável — ver nota no próprio
  arquivo). `compare_scenario_sign_confidence(g, scenario_sign_confidence)`
  é o equivalente de `compare_scenario_effects()` pra confiança de sinal em
  vez de efeito de equilíbrio, usado tanto na comparação em tela quanto na
  seção "Scenarios compared" do relatório. Roadmap item 7.2 ("qual aresta
  importa mais"): `global_sensitivity(g, press, relative_change=0.1,
  target_ids=NULL)` — one-at-a-time (OAT): aumenta o peso de UMA aresta por
  vez em 10%, recalcula o efeito de equilíbrio pro mesmo `press`, e mede
  quanto ele mudou (soma dos módulos das diferenças) — reaproveita
  `press_perturbation()` direto, sem simulação nova e sem pacote novo
  (`barplot()` do R base no gráfico, mesma razão que manteve a trajetória em
  `matplot()` em vez de `ggplot2` no Marco C). Roadmap item 6.4
  (reprodutibilidade): `robustness_check()`/`sign_determinacy()` ganharam
  `seed=42` (`set.seed(seed)` logo antes do loop de reamostragem) — antes,
  aplicar o mesmo cenário duas vezes (ou gerar o relatório duas vezes a
  partir do mesmo savepoint) dava um "Sign confidence" ligeiramente
  diferente a cada vez, só pelo sorteio dos pesos; com a semente fixa a
  mesma chamada sempre devolve o mesmo resultado, não importa o estado do
  RNG antes de chamar. `global_sensitivity()` não precisou de mudança — já
  é determinístico (OAT sem amostragem aleatória). Fase 9 item 9.1
  ("auto-regulação por fator"): `self_regulation_magnitudes()` (mapeamento
  fixo `none=0, low=-0.5, medium=-1, high=-2`, deliberadamente não exposto
  ao usuário — faixa escolhida pra competir de verdade com o peso típico
  das arestas do app, ver `data/`/`docs/example_fisheries.idpsir.json`) e
  `self_regulation_diagonal(g)` (lê `V(g)$self_regulation`, com fallback
  pra `"none"` se o atributo nem existir — grafos antigos/savepoints sem o
  campo continuam batendo byte a byte com o comportamento de antes).
  `build_interaction_matrix()` deixou de ter retorno antecipado em
  `ecount(g)==0` — a diagonal precisa ser preenchida mesmo sem arestas, já
  que auto-regulação é atributo de nó, não de aresta (o schema continua
  proibindo aresta de um nó pra ele mesmo, intocado). Fase 9 item 9.1.4
  ("sensibilidade à auto-regulação"): `self_regulation_sensitivity()`,
  literalmente a mesma reamostragem de `robustness_check()` só que
  perturbando a magnitude da auto-regulação de cada nó (multiplicador
  contínuo, não salto discreto entre níveis — decisão tomada antes de
  implementar, pra não inventar um segundo tipo de aleatoriedade só pra
  este item) em vez do peso das arestas; um nó "none" tem magnitude 0, e
  0×qualquer-coisa continua 0, então fica corretamente fora da perturbação
  sem nenhum caso especial no código.
- `R/sufficiency.R` → Revisão 1 (`manuscrito/REVISAO_1_...md`, avaliada e
  fasada em `.claude/plans/`): motor de **suficiência de resposta**, o novo
  motor principal da aba Scenarios, substituindo `press_perturbation()`
  como leitura primária (essa e as demais funções do regime dinâmico —
  `check_stability`, `simulate_trajectory*`, `find_neutralization_step`,
  `summarize_neutralization`, `self_regulation_*` — continuam definidas em
  `loop_analysis.R` mas deixam de ser chamadas, mesmo padrão de código
  superado já usado o projeto inteiro). `build_signed_matrix(g)` reaproveita
  `build_interaction_matrix()` e zera a diagonal — isso sozinho já resolve
  "ignorar `self_regulation` de savepoint antigo" sem nenhum código
  condicional: mesmo que o atributo ainda exista no grafo, a diagonal
  preenchida por ele é descartada de qualquer forma. `spectral_radius(W)`
  usa `Mod(eigen(W)$values)` (módulo, não parte real — autovalor complexo é
  rotina em rede com ciclo). `propagate(W, p, c=0.5)` calcula
  `Φ(p) = (I - λW)⁻¹p - p` com `λ = c/ρ(W)` — como `λ·ρ(W) = c < 1` sempre,
  a matriz nunca é singular pra nenhuma rede, eliminando de vez tanto a
  exigência de estabilidade quanto a inversão de sinal que motivaram a
  revisão (ver "Estado atual" abaixo pro caso real que provou isso).
  Fase 9: bug real corrigido — `ρ(W) = 0` acontece tanto pra `W`
  genuinamente vazio quanto pra `W` nilpotente (qualquer rede acíclica,
  sem ciclo nenhum — os autovalores de um DAG são sempre zero), e o código
  tratava os dois casos como "nada a propagar", zerando um efeito real e
  bem definido em toda rede sem ciclo. `all(W==0)` continua zerando;
  `ρ(W)==0` com `W` não-vazio agora usa `λ <- c` direto (sem dividir por
  `ρ`, já que `(I-λW)` é invertível pra qualquer `λ` quando `W` é
  nilpotente) — ver "Estado atual" pra rede real (Gnanapragasam) e teste
  de regressão que provaram o bug antes de corrigir.
  `sufficiency(g, p_D, p_R, c)` — piora/mitigação/líquido/neutralizado/força
  necessária por Impacto (`strength_to_neutralize` é uma razão
  adimensional sobre `p_R`, não um valor absoluto — a tela multiplica pela
  força planejada de uma resposta única na hora de exibir, já que somar
  respostas combinadas não teria uma "força planejada" única pra
  multiplicar). `sufficiency_confidence()` reaproveita a mesma reamostragem
  de `robustness_check()`. `sufficiency_reach_over_c()` varre uma grade de
  `c` e sinaliza veredito de fronteira. Revisão 1, Fase 3:
  `format_sufficiency_table()`/`format_reach_over_c_table()` — formatação de
  exibição compartilhada entre os renderers em tela de `mod_responses.R` e a
  seção "Response sufficiency" do relatório (`R/report.R`), pra um número
  nunca poder divergir entre tela e relatório exportado (mesmo raciocínio já
  usado por `R/scenario_plots.R` pros gráficos de trajetória/sensibilidade).
- `R/temporal.R` → Revisão 1, Fase 4: motor **temporal opcional de janelas
  discretas** — descoberto necessário numa conversa longa com o usuário
  revisando `manuscrito/gnanapragasam_2026.pdf` (Gnanapragasam et al. 2026,
  Marine Policy): a leitura estática de `sufficiency()` responde "a
  resposta cobre a piora?" num único instante, mas o artigo mostra
  auxílios pós-desastre (respostas a um Impacto de perda de renda) que,
  janelas depois, viram eles mesmos uma força de pressão nova — um efeito
  indireto invisível numa leitura de instante único. Deliberadamente
  **opcional e aditivo**: não exige nenhum dado a mais do usuário pra quem
  só quer a leitura estática, e não busca convergência/equilíbrio (ao
  contrário do motor antigo) — roda um número fixo de janelas e reporta o
  que aconteceu em cada uma, sem perguntar se a rede "se assenta".

  Equação por nó $i$, por janela $t$:
  $x_i(t{+}1) = x_i(t) + \text{growth\_rate}_i \cdot x_i(t) + \sum_j
  \text{gate}_{ji}(t)\cdot W[i,j]\cdot x_j(t) + p_i(t)$ — `W =
  build_interaction_matrix(g)` (`R/loop_analysis.R`, já inclui a
  autorregulação na diagonal desde a Fase 9), então **não há termo
  separado de autorregulação aqui**: somar de novo contaria o mesmo
  efeito duas vezes. `growth_rate` é deliberadamente um termo à parte —
  tendência exógena do próprio nó (crescimento populacional, tendência de
  consumo), independente da estrutura do grafo, ao contrário da
  autorregulação (que é sobre como o nó reage ao próprio desvio) e das
  arestas (sobre como um nó reage a outro nó). `build_growth_rate_vector(g)`/
  `build_reference_values(g)` leem `growth_rate`/`reference_value` (nós)
  tolerantemente — a coluna ainda não existe no schema (chega só na Fase
  5), então devolvem 0/1 pra todo mundo, comportamento idêntico ao de
  hoje, mesmo padrão NULL-safe já usado por `self_regulation_diagonal()`.
  `apply_threshold_gate()` reaproveita a mesma técnica vetorizada de
  `simulate_trajectory_thresholded()` (replicar o estado da origem por
  coluna, comparar contra a matriz de threshold), só que a comparação é
  relativa ao `reference_value` da origem, não absoluta — e como
  `reference_value` default é 1, o motor já nasce "pronto pra relativo"
  sem mudança nenhuma quando a Fase 5 adicionar a coluna de verdade.
  `simulate_temporal_pair(g, p_D, p_R, windows, mode_D, mode_R)` roda duas
  rodadas lado a lado — baseline (só `p_D`) e cenário (`p_D+p_R` juntos,
  **nunca** separados e somados depois: o threshold-gating quebra a
  linearidade que a decomposição `worsening+mitigation` da leitura
  estática depende) — cada perturbação podendo ser impulso (ativa só na
  janela 1) ou permanente (ativa toda janela). `format_temporal_table()`
  gera Impacto = $\max(0, x_i(t))$ por janela nas duas rodadas, com
  veredito (Neutralized/Partial/Failure-worsened) comparando as duas.

  **Achado real, testado antes de aceitar o design da Fase 5 (não
  assumido)**: reaproveitar as magnitudes do autorregulação antigo
  (`self_regulation_magnitudes()`, none=0/low=-0,5/medium=-1/high=-2)
  direto nesta equação de diferença discreta **oscila em vez de decair**.
  $x(t{+}1) = (1+sr)\cdot x(t)$ só decai suavemente quando $|1+sr|<1$; com
  $sr=-2$ ("high"), $(1+sr)=-1$ exatamente — o estado flip-flopa de sinal
  pra sempre na mesma magnitude, nunca decaindo rumo a zero (confirmado
  rodando um impulso de -1 num nó com autorregulação "high": vira
  -1,1,-1,1,-1,... eternamente). As magnitudes antigas foram calibradas
  pro Euler *implícito* do motor antigo (`solve(I - step_size*A)`), não
  pra uma diferença *explícita* direta — reforça, com número real e não
  só preferência de UX, por que a Fase 5 precisa mesmo trocar
  autorregulação pra uma fração contínua em $[0,1)$ aplicada como
  `x(t+1) -= self_regulation*x(t)` (sempre negativada internamente), o
  que garante decaimento geométrico limpo em vez de oscilação.

  Testado via `scratchpad/test_temporal.R`/`test_temporal2.R` (standalone,
  antes de virar teste permanente) contra uma rede de 5 nós construída à
  mão (D1→P1→S1→I1, R1→S1 mitiga, R1→D1 fecha o ciclo "resposta vira nova
  pressão", o mesmo padrão de fixture já usado no Marco A/D da Fase 5 pra
  provar uma propriedade matemática específica em vez de depender de rede
  de exemplo externa): com resposta em modo permanente, o benefício
  relativo da resposta sobre o Impacto erode de neutralização total
  (janela 2) pra mitigação só parcial (janela 8, razão cenário/baseline
  subindo de 0 pra 0,6) — o "resposta virando nova pressão" reproduzido
  numericamente, não só narrado. `tests/testthat/test-temporal.R` novo (21
  assertivas, incluindo o achado da oscilação acima como teste de
  regressão formal) — suíte completa limpa. App inalterado, zero mudança
  de tela ainda (mesmo padrão da Fase 1 da suficiência estática).
- `R/scenario_plots.R` → fast-follow "gráficos editáveis/baixáveis" (pedido do
  usuário ao revisar a aba Scenarios): `draw_trajectory_plot()`/
  `draw_sensitivity_plot()`, funções puras de desenho (base R
  `matplot()`/`barplot()`, sem nenhuma dependência de Shiny/reativo) — a
  mesma chamada produz o gráfico em tela (`mod_responses.R`'s
  `renderPlot()`), o arquivo baixado (`downloadHandler()`) e a figura
  embutida no relatório (`report.R`), em vez de três implementações que
  pudessem divergir. `render_plot_png()`/`render_plot_svg()` escrevem num
  arquivo via `grDevices::png()`/`grDevices::svg()`; `plot_to_data_uri()`
  (usado só por `report.R`) renderiza num arquivo temporário e devolve um
  data URI base64 via `jsonlite::base64_enc()` — sem pacote novo, já que
  `jsonlite` já é dependência do app (usado com prefixo explícito em
  `io.R` pelo mesmo motivo de sempre: mascarar `shiny::validate()` se
  anexado).
- `R/report.R` → montagem do relatório HTML autocontido (`build_full_report_html`,
  `report_html_table`, `format_report_cell`, `matrix_to_report_df`), usado só por
  `mod_report.R`. Seções (imagens de grafo salvas/métricas gerais/centralidades/
  descritores/referências/cenários) são todas opcionais via flags — nenhuma é
  recomputada aqui,
  só reaproveita as funções de `R/metrics.R`/`R/responses.R` já usadas nas outras
  abas. `graph_snapshots`/`selected_snapshot_names` viram uma seção "Network graph"
  com um `<h3>` + `<img>` por snapshot selecionado, não uma imagem única. Cada
  figura e tabela do relatório ganha uma legenda numerada sequencialmente
  ("Figure N"/"Table N", contadores fechados sobre `build_full_report_html`) — ver
  "Legendas e parametrização no relatório" no Estado atual. `centrality_params`
  (novo argumento, default `list(directed=TRUE, normalized=TRUE, weighted=FALSE)`
  igual ao de `compute_all_metrics()`) é repassado direto pra `compute_all_metrics()`
  na seção de Centralidades — antes o relatório sempre usava esses defaults
  hardcoded, ignorando o que o usuário tivesse configurado na aba Metrics.
  Item 7.3 do roadmap de publicação: seção opcional "References", uma tabela
  Link ("De -> Para" usando os rótulos dos nós) x Reference, uma linha por
  aresta que tiver `reference` preenchido — omitida por completo se nenhuma
  aresta tiver (ver Estado atual). Item 6.4 do roadmap ("sessionInfo +
  parametrização"): seção opcional "Reproducibility" no fim do relatório —
  versão do R (`R.version.string`) + tabela de versões de cada pacote em
  `required_packages` (reaproveitado direto de `global.R`, sem duplicar a
  lista — `utils::packageVersion()` por pacote, com fallback "not
  installed" se algum não estiver presente) e um parágrafo fixo com os
  parâmetros das análises estocásticas (`n_simulations=100`, `spread=0.5`,
  `seed=42` pra confiança de sinal/robustez; `relative_change=0.1` pra
  sensibilidade — os mesmos defaults usados de fato em `mod_responses.R`,
  não números inventados pro texto). Item 9.2 do `ROADMAP_FASE9_iDPSIR.md`:
  seção "Reach per scenario" na comparação de cenários (`response_reach()`,
  `R/reach.R`), tabela Scenario × Factors reached × Impacts reached — sempre
  calculável, mesmo quando o efeito de equilíbrio não é. Fast-follow
  "gráficos editáveis/baixáveis": novas seções "How the effect evolves over
  time" e "Which edges matter most" ganharam a figura de verdade (não só a
  tabela que "Which edges matter most" já tinha) via
  `plot_to_data_uri()`/`draw_trajectory_plot()`/`draw_sensitivity_plot()`
  (`R/scenario_plots.R`) — uma imagem por cenário selecionado, cada uma com
  sua própria legenda numerada. Trajetória recalculada a partir de
  `sc$trajectory_steps` (capturado no momento de "Save this scenario", ver
  `mod_responses.R` abaixo) — não precisa de um slider ao vivo pra existir
  no relatório.

  **Revisão 1, Fase 3**: nova seção "Response sufficiency", uma subseção por
  cenário salvo selecionado, inserida **antes** de "Scenarios compared"
  (agora rotulada "(older, equilibrium-based reading)", mesmo texto de aviso
  já usado em `mod_responses.R`) — mesma ordem da UI, onde a leitura nova
  também vem antes da antiga. Reaproveita `format_sufficiency_table()`/
  `format_reach_over_c_table()` (novos, `R/sufficiency.R` — ver abaixo) pras
  duas tabelas cuja formatação tinha lógica própria; a matriz de confiança
  (`sc$sufficiency_confidence_matrix`) já vem pronta de `R/sufficiency.R`
  sem formatação extra. Cada subseção mostra o cenário de pressão/resposta
  em texto (`"D1 at 100%, D3 at 100%"` etc.) e o valor de `c` usado, seguido
  das 3 tabelas com legenda numerada própria — nenhuma seção nova depende de
  checkbox novo em `mod_report.R`, reaproveita a mesma seleção de cenários
  que já alimenta "Scenarios compared".
- `R/modules/mod_data.R` → editor por formulário (passos Início/Modelo/Nós/Arestas/Revisar
  do wizard); estado em `reactiveValues`, não-reativo até "Construir/Reconstruir grafo".
  Formulário de aresta tem um campo opcional "Threshold" (em branco na maioria das
  arestas) — ver Fase 5 fast-follow "threshold não-linear" no Estado atual — e um
  campo opcional "Reference" (texto livre, DOI/URL/citação) — ver item 7.3 do
  roadmap de publicação no Estado atual.
  `rv$positions` (campo do savepoint que existia desde a Fase 1 mas nunca tinha
  nada escrevendo nele) ganhou um setter (`set_positions`) exposto no retorno do
  módulo, pra `mod_graph.R` gravar as posições arrastadas manualmente — ver
  Fase 5 fast-follow "layout do grafo". Passo Início redesenhado: os 4 modos
  de começar (New project/Import CSV/Load savepoint/Combine savepoints) viram
  cards uniformes via `start_card()` (ícone + título + descrição de uma linha
  + input(s) de arquivo quando houver + botão sempre na mesma base, via
  espaçador `flex: 1` dentro de uma coluna flex de altura 100% — o Bootstrap
  4 do bs4Dash já estica as colunas de um `fluidRow` pra mesma altura por
  padrão, então basta isso pros 4 botões alinharem na mesma linha) — antes
  "New project" era só um botão solto ao lado de 3 colunas com inputs de
  arquivo acima, o que deixava a coluna "New project" com aparência
  inacabada/desalinhada. Mockup revisado com o usuário antes de implementar.
  Fase 9 item 9.1: formulário de nó ganhou `selectInput` "Self-regulation"
  (`get_self_regulation_levels()`, default `"none"`, mesmo padrão de
  Uncertainty/Controllability) com um texto de ajuda em linguagem simples
  (sem "diagonal"/"autovalor" — regra de linguagem do roadmap: termos
  matemáticos só nos comentários de código, nunca na tela) explicando o
  conceito com exemplos concretos (habitat que se recupera, driver
  controlado por algo fora do modelo). `create_empty_nodes_table()` ganhou
  a coluna correspondente.
- `R/modules/mod_graph.R` → painel de exploração do grafo. Controles em caixas
  colapsáveis (`bs4Dash::box(collapsible = TRUE)`) empilhadas numa coluna à esquerda,
  agrupadas por tema (Display, Node & edge emphasis, Layout & spacing, Pathway
  highlight, Communities, Nodes), com o grafo + legenda ocupando a coluna maior à
  direita (Fase 4.2 — ver abaixo). Destaque de caminhos causais vive aqui também, como
  dropdown "Highlight pathway" (From/To categoria + seleção do caminho, mesmo padrão de
  "Select by group" / "Node size based on") — não é uma aba separada, para não forçar o
  usuário a trocar de aba e voltar toda vez que quiser ver o destaque no grafo.
  Comunidades (Louvain/Walktrap/Infomap/Label Propagation, `build_community_visual`)
  também não é mais aba separada — é uma opção "Color nodes by: DPSIR category |
  Community" do mesmo grafo, reaproveitando os mesmos filtros/espaçamento já
  configurados (ver Fase 4.2). Abaixo do grafo, "Save current view for report"
  captura um snapshot nomeado da tela atual (qualquer combinação de paleta/cor/
  filtro/destaque) para a aba Report — ver seção de captura de imagem abaixo. A
  caixa "Nodes" tem um botão "Clear selection" que desfaz tanto a seleção da
  tabela quanto o destaque no grafo (`visUnselectAll()`), já que nenhuma das duas
  direções da sincronização cruzada tabela↔grafo limpava a seleção sozinha. Cada
  snapshot guarda `list(image=, caption=)` em vez de só o dataURL: `caption` é
  montada em `build_snapshot_caption()` a partir dos `input$...` ativos no momento
  do clique (layout ativo, cor/paleta ou comunidade+algoritmo, filtros de
  subsistema/temporal, base do tamanho do nó, base da espessura da aresta +
  limiar de confiança, e o caminho destacado se houver um selecionado) — vira
  a legenda da figura na aba Report. Fast-follow "layout do grafo": dropdown
  "Layout" (Layered by category / Circular) na caixa Display; arrastar um nó
  o fixa no lugar (`fixed.x`/`fixed.y`, ver `R/graph.R`) e a posição é enviada
  ao servidor via evento `dragEnd` do vis.js, guardada em `positions`/
  `set_positions` (passados de `mod_data.R`, ver abaixo) — sobrevive a trocas
  de filtro/cor e a salvar/recarregar o savepoint, não só ao render atual.
  Botão "Reset dragged positions" limpa todas as posições manuais de uma vez.
  Checkboxes "Show category/community legend"/"Show edge-type legend" na
  caixa Display escondem a legenda por completo quando ambos desligados.
- `R/modules/mod_metrics.R` → painel único de métricas (Gerais / Centralidades / Descritores DPSIR).
  `mod_metrics_server` retorna `centrality_params` (reactive com `directed`/
  `normalized`/`weighted`, os mesmos toggles usados na tabela em tela) para a aba
  Report reaproveitar — ver Fase 5, seção "Legendas e parametrização no relatório".
- `R/modules/mod_responses.R` → aba "Scenarios": ativar respostas (nós de categoria
  feedback) com força 0-100%, aplicar cenário combinado, salvar e comparar múltiplos
  cenários lado a lado (comparação rápida em tela — a exportação em si vive em
  `mod_report.R`, ver abaixo). Motor desde a Fase 5 Marco B é `R/loop_analysis.R`:
  ativar uma resposta vira uma entrada no vetor de press, `interaction_matrix`/
  `network_stability` são `reactive`s computados uma vez por grafo (não mudam entre
  cenários) e reaproveitados a cada "Apply scenario". Aviso de estabilidade em
  linguagem simples acima das tabelas de resultado (nada de autovalor cru na tela).
  "Effect on the network" mostra nós afetados/magnitude total (imediato vs
  equilíbrio) em vez de nodes/edges/density do motor antigo, já que o grafo em si
  não muda mais, só o estado. "Effect on each factor" mantém a mesma UI de sempre
  (Improves/Worsens/Stable visível; `id`/imediato/equilíbrio ocultos mas presentes
  no export CSV/Excel). Marco C: disclosure opcional "Show how the effect evolves
  over time" (desligada por padrão), com slider "Number of steps" e um
  `plotOutput` via `matplot()` (base R, sem `ggplot2`) plotando
  `simulate_trajectory()` — uma linha por fator, cores de `scales::hue_pal()`
  (pacote já usado no app). Útil principalmente quando a rede é instável: a
  tabela de equilíbrio vira só uma estimativa direcional nesse caso, mas a
  trajetória continua rodando pra qualquer número de passos e mostra a
  divergência visualmente. Marco D: disclosure opcional "Show robustness to
  uncertainty" (desligada por padrão), com slider "Number of simulations" e uma
  tabela (Factor/Category/Effect/Agreement %) de `robustness_check()`, ordenada
  do menos confiável pro mais confiável — deixa explícito quando o resultado
  mostrado é robusto a quão incerto o usuário disse que cada aresta é, vs. um
  empate delicado que qualquer variação de peso derruba. Fast-follow pós-Fase 5:
  tabela "When will Impacts be neutralized?" (`summarize_neutralization()`),
  logo abaixo de "Effect on each factor" — quantos passos até o efeito da
  Resposta em cada nó de categoria Impacto atingir 90% do seu efeito de
  equilíbrio projetado; oculta por completo quando a rede não tem nenhum nó
  Impacto. Fast-follow "threshold não-linear": o gráfico de trajetória passa a
  chamar `simulate_trajectory_thresholded()` com a `threshold_matrix()`
  (reactive, `build_threshold_matrix(graph())`) da rede — se nenhuma aresta
  tiver threshold definido (`Th` todo `NA`), o resultado é idêntico a antes;
  um `threshold_note` aparece acima do gráfico só quando pelo menos uma aresta
  tem threshold, avisando que as tabelas de equilíbrio/robustez acima não
  refletem esse gatilho. Roadmap item 7.1: "Effect on each factor" ganha uma
  coluna "Sign confidence (%)" sempre visível (não escondida atrás do
  disclosure opcional) — calculada via `sign_determinacy()` a N=100 fixo em
  todo "Apply scenario", não só quando o usuário abre "Show robustness to
  uncertainty" (que continua existindo, agora só como a versão configurável/
  aprofundada, reaproveitando o mesmo `sign_determinacy()`). A comparação de
  múltiplos cenários salvos ganhou uma tabela "Sign confidence per factor"
  (`compare_scenario_sign_confidence()`) ao lado da de efeito de equilíbrio;
  o baseline (sem resposta) tem confiança 100% computada direto (press
  zero ⇒ equilíbrio zero não importa como os pesos sejam reamostrados),
  sem gastar simulação à toa. Roadmap item 7.2: disclosure opcional "Show
  which edges matter most", com gráfico de barras horizontal (`barplot()`
  base R) + tabela ordenada de `global_sensitivity()` — calculado de forma
  eager em "Apply scenario" (igual `sign_confidence`) pra sobreviver em
  cenários salvos e entrar no relatório. `ROADMAP_FASE9_iDPSIR.md` item 9.2
  ("alcance de uma resposta"): seção "Reach" logo abaixo de "Effect on the
  network" — "N factors reached, including Y of Z Impacts" mais uma tabela
  dos fatores alcançados (`response_reach()`, `R/reach.R`), deliberadamente
  posicionada ao lado do aviso de estabilidade em vez de escondida atrás
  dele: alcance é travessia pura do grafo, não depende da rede se assentar,
  então continua definido mesmo quando o efeito de equilíbrio não está.
  Calculado de forma eager em "Apply scenario" (mesmo padrão de
  `sign_confidence`/`sensitivity`), e a comparação de cenários ganhou uma
  tabela "Reach per scenario" ao lado das demais (baseline sempre 0, já
  que nenhuma resposta ativa não alcança nada). Item 9.1.4: nota em
  linguagem simples ao lado do aviso de estabilidade (`self_regulation_note`,
  escondida por completo se nenhum nó tiver auto-regulação — a maioria dos
  savepoints existentes) avisando que o resultado assume a auto-regulação
  configurada; quarto disclosure opcional "Show sensitivity to
  self-regulation" (também escondido nas mesmas condições), tabela
  Factor/Category/Effect/Agreement % de `self_regulation_sensitivity()` —
  calculado sob demanda (igual "Show robustness to uncertainty", não eager
  como `sign_confidence`), já que é um diagnóstico de aprofundamento, não
  um número de primeira linha. Fast-follow "gráficos editáveis/baixáveis"
  (pedido do usuário ao revisar a aba): os gráficos de trajetória e de
  sensibilidade de arestas eram `renderPlot()` estáticos sem botão de
  download nem presença no relatório — diferente do grafo de rede, que já
  tinha todo um pipeline de captura via `html2canvas` porque é um widget
  JS vivo, esses dois já eram gráficos base R (`matplot()`/`barplot()`)
  desenhados no servidor, então dá pra reescrever direto num arquivo com
  um `downloadHandler()` comum, sem captura nenhuma do navegador. Lógica
  de desenho movida pra `R/scenario_plots.R` (`draw_trajectory_plot()`/
  `draw_sensitivity_plot()`), reaproveitada por três lugares: o gráfico em
  tela, os botões "Download PNG"/"Download SVG" (novos, um par por
  gráfico) e a figura embutida no relatório (ver `R/report.R` acima) — a
  mesma chamada de função em todos, nunca três desenhos que pudessem
  divergir. Sensibilidade ganhou um slider "Number of edges shown" (min 3,
  max 20, default 10) — antes o gráfico não tinha nenhuma configuração,
  sempre fixo em top-10; trajetória já tinha "Number of steps". Ao salvar
  um cenário (`observeEvent(input$save_scenario)`), o valor atual de
  `input$trajectory_steps` é gravado em `sc$trajectory_steps` (padrão 20
  se nunca tocado) — sem isso o relatório não teria como redesenhar a
  trajetória de um cenário salvo, já que o slider é um input único e
  global, não por cenário.

  **Revisão 1, Fase 2 — leitura de suficiência adicionada ao lado da leitura
  antiga (nada removido ainda, ver `R/sufficiency.R` acima).** Novo painel
  "Pressure scenario" (espelha exatamente o padrão já existente do painel
  de Resposta: um checkbox + slider 0-100% por nó Driver/Pressure,
  `pressure_nodes`/`output$pressure_controls`) logo acima do painel
  "Response scenario" (renomeado de "Responses" pra deixar claro que agora
  são dois cenários independentes, não um só). Slider único novo "How far
  to trace the effect" (`effect_horizon`, 0.2-0.8, default 0.5) mapeia o
  `c` de `propagate()` — rótulo escolhido de propósito pra não colidir com
  "Reach" (`response_reach()`), um recurso diferente e já existente na
  mesma aba (alcance topológico, não tem nada a ver com o parâmetro `c`).
  "Apply scenario" agora também constrói `p_D` (`build_press_vector()`
  sobre os inputs do painel de pressão) e chama `sufficiency()`/
  `sufficiency_reach_over_c()`/`build_confidence_matrix()` (helper novo,
  não-reativo, no topo do arquivo — avalia cada Resposta da rede sozinha,
  **sempre a 100%** de força, contra o mesmo `p_D`, nunca a força que o
  slider daquela resposta happens to show) — as três tabelas da Seção 4 da
  revisão ("Is the response enough?", "How confident is that, response by
  response?", "Does it hold up across how far the effect is traced?"),
  guardadas em `current_scenario()` ao lado (não no lugar) de tudo que já
  existia. A seção antiga foi apenas rotulada "Effect on each factor
  (older, equilibrium-based reading)" com uma nota "Being replaced by the
  sufficiency reading above - kept here for now while it's validated" —
  continua calculando e mostrando exatamente o que já mostrava.

  **Dois bugs reais, encontrados só ao testar ao vivo no navegador contra a
  rede de Mangi** (nenhum dos dois existia nos 29 testes standalone da
  Fase 1, porque nenhum deles exercitava o caminho UI→DT):
  - A tabela "Does it hold up..." (`reach_over_c_table`) sempre mostrava
    "No matching records found", apesar dos cabeçalhos das colunas
    aparecerem corretos. Depurado lendo a API do DataTables direto no
    console do navegador (`dt.ajax.json()`), não assumido: o R real por
    trás do JSON server-side retornava `"Error in if (!searchable[j]) next:
    argumento tem comprimento zero"` — a última coluna da tabela (`flips`)
    tinha o nome `""` (string vazia, escolhido pra não repetir "Verdict"
    ao lado de "Borderline"/""), e o pacote DT quebra internamente ao
    tentar casar esse nome vazio na lógica de busca por coluna, mesmo com
    a busca desligada (`dom = "t"`). Corrigido dando um nome de verdade
    ("Verdict") à coluna — `datatable()` não aceita nome de coluna vazio
    de forma confiável nesta versão do pacote.
  - A tabela "How confident is that..." mostrava números plausíveis mas
    **diferentes** dos já verificados na Fase 1 (ex.: Gear restrictions
    no Recife saindo 80% em vez dos 100% esperados) — não um erro, uma
    escolha de design equivocada: `build_confidence_matrix()` original
    avaliava cada Resposta na força **atual do seu próprio slider**
    (`strengths_pct`), inclusive pras Respostas inativas, cujo slider fica
    parado no default de 50% até o usuário tocar nele. Isso tornava a
    comparação enganosa — uma Resposta tecnicamente tão eficaz quanto
    outra parecia mais fraca só por ninguém ter arrastado o slider dela
    ainda. Corrigido fixando a força em 100% pra toda Resposta nesta
    tabela especificamente (`build_press_vector(g, rid, setNames(1, rid))`,
    parâmetro `strengths_pct` removido da assinatura) — o que também é o
    que a Fase 1 já tinha verificado contra a Tabela 2 da própria revisão
    e contra `test-sufficiency.R`, então esse ajuste alinhou o comporta-
    mento da UI ao que já estava provado correto, não o contrário.

  Testado ponta a ponta rodando o app de verdade contra a rede de Mangi
  (`data/mangi2007_*.csv`, importada via CSV — savepoint de exemplo ainda
  não existe, isso é Fase 5): pressão D1+D3 a 100%, resposta R1 a 100%,
  `c=0.5` (default) — as três tabelas novas batem número por número com
  a Fase 1 (`worsening`/`mitigation`/`net` de 0.11/-0.166/-0.056 em Catch
  decline, 0.03/-0.093/-0.063 no Recife, 0.05/-0.102/-0.053 em Food
  insecurity, todos "Yes"/"Strength needed" 66%/32%/49%; confiança R1=100
  nos três Impactos, R2/R3/R5=100 só no Recife; nenhuma linha "Borderline"
  na tabela de `c`, todos "Yes" nos 5 valores de `c` testados). A seção
  antiga (equilíbrio/estabilidade/Reach/robustez/"When will Impacts be
  neutralized") continua funcionando sem nenhuma regressão nos números já
  documentados nas fases anteriores — prova de que a Fase 2 foi
  genuinamente aditiva. Sem erros no console do navegador nem do servidor
  em nenhum passo, depois de corrigidos os dois achados acima. Suíte
  `testthat` (91 assertivas) e checagem de sintaxe re-rodadas depois do
  fix, ambas limpas.

  **Revisão 1, Fase 3 — persistência do cenário no savepoint.** Novo
  parâmetro `restore_state` em `mod_responses_server()` (a `scenario_state`
  restaurada de um savepoint, `NULL` em qualquer outro modo de início —
  exposta por `mod_data.R`/passada por `mod_wizard.R`, mesmo padrão já
  usado por `positions`). Lido só na hora de desenhar os controles
  (`output$pressure_controls`/`output$response_controls`/
  `output$effect_horizon_ui`, este último convertido de `sliderInput`
  estático pra `uiOutput` só pra poder receber um valor inicial vindo do
  savepoint) — nunca escrito de volta, então editar manualmente depois de
  carregar nunca é revertido por este mecanismo. Nova reactive
  `current_scenario_state` (lida direto de `input$...`, não de
  `current_scenario()`) devolvida no retorno do módulo — captura o que
  estiver configurado na tela **no momento de baixar o savepoint**, esteja
  ou não com "Apply scenario" já clicado.

  **Bug real, encontrado só ao testar o carregamento de um savepoint com
  cenário salvo (não aparecia em nenhum teste standalone nem nos 91 do
  Fase 1/2, porque nenhum deles restaurava savepoint com nó *parcialmente*
  ativo)**: a app quebrava com "índice fora de limites" ao entrar na aba
  Scenarios depois de carregar um savepoint que só tinha D1/D3/R1 ativos —
  qualquer outro nó (D2, D4, R2...) travava o painel inteiro. Causa: a
  primeira versão de `restored_strength()` usava `strengths[[node_id]]`
  pra buscar a força salva de cada nó — `strengths` é um **vetor atômico**
  nomeado (não uma lista), e `[[` num vetor atômico **lança erro** pra um
  nome ausente (`"subscript out of bounds"`), ao contrário de uma lista,
  onde `[[` devolve `NULL` silenciosamente. Corrigido checando
  `node_id %in% names(strengths)` explicitamente antes de indexar, sem
  depender do comportamento de `[[` variar por tipo. Verificado carregando
  de volta o savepoint de teste (D1/D3 a 100%, R1 a 100%, `c=0.5`): os
  nós ausentes do cenário salvo (D2, D4, R2-R5) aparecem corretamente
  desmarcados a 50% (o default), os presentes exatamente na força salva,
  e aplicar o cenário restaurado reproduz número por número o já
  verificado na Fase 2 (0.11/-0.166/-0.056/66% em Catch decline, etc.) —
  sem erro no console do servidor.
- `R/modules/mod_report.R` → aba "Report" (última do Explorar): checkboxes para
  métricas gerais/centralidades/descritores DPSIR/referências de aresta/item 6.4
  ("Reproducibility info"), seleção múltipla de imagens de
  grafo salvas (`mod_graph.R`'s "Save current view for report") e seleção múltipla
  de cenários salvos (baseline sempre incluído) — mesmo padrão de tabela com
  `selection = "multiple"` para as duas. Um único botão "Download report (HTML)"
  gera tudo via `build_full_report_html`. Registra o handler JS compartilhado de
  captura (`idpsir_capture_element`/`html2canvas`), mas quem dispara a captura é
  `mod_graph.R`, não este módulo — ver seção de captura de imagem abaixo. A captura
  redimensiona o container temporariamente (~2.5x), esconde os controles do próprio
  vis-network (navegação, "Select by group", "Export as png") e corta para o
  conteúdo real antes de restaurar o tamanho original — ver "Qualidade das figuras
  do relatório" no Estado atual.
- `R/modules/mod_wizard.R` → casca do wizard (passo atual, Voltar/Avançar com validação,
  download do savepoint disponível em qualquer passo, Next oculto no último passo — ver
  Fase 4.3); o passo Explorar é um `tabsetPanel` (Graph/Scenarios/Metrics/Report). Não
  participa mais da captura de imagem do grafo (ver seção abaixo) — só encaminha o
  `graph_snapshots` retornado por `mod_graph_server` para `mod_report_server`.
- `R/modules/mod_communities.R` → versão anterior da aba de comunidades (widget
  `visNetwork` separado, sem os filtros/espaçamento do Graph), mantida no disco mas
  **não sourceada** desde a Fase 4.2 — superada por `mod_graph.R`.
- `R/ui_main.R`, `R/server_main.R` → UI e server principais (chamam só `mod_wizard_*`).
  `ui_main.R` tem um link "Help" no `dashboardHeader(rightUi=...)`, abrindo
  `docs/tutorial.html` (servido pelo `addResourcePath("tutorial", "docs")` em
  `global.R`) numa aba nova — ver Estado atual.
- `data/` → CSVs de exemplo. `mangi2007_nodes.csv`/`mangi2007_edges.csv`
  (novos, Revisão 1) — rede real e citada (Mangi et al. 2007), promovida de
  `manuscrito/` (mesmos dados, coluna `self_regulation` removida dos nós —
  não existe mais no novo motor) — fixture principal de teste do novo
  motor de suficiência, ver `R/sufficiency.R` acima. Revisão 1, Fase 9:
  `gnanapragasam2026_nodes.csv`/`_edges.csv` — rede de 13 nós adaptada de
  Gnanapragasam et al. 2026 (Marine Policy), gera
  `docs/example_gnanapragasam.idpsir.json` e substitui a rede de pescas
  (5 nós) como exemplo principal do tutorial — ver "Estado atual".
- `tests/testthat.R`, `tests/testthat/*.R` → testes automatizados do núcleo
  numérico (item 6.3 do roadmap de publicação) — ver Estado atual.
- `.github/workflows/shinylive.yml` → CI que publica uma build WebAssembly do
  app (roda no navegador, sem servidor) no GitHub Pages a cada push em
  `main` — item 8.1 do roadmap de publicação, ver Estado atual.

Ao adicionar/remover um arquivo em `R/`, atualize os `source()` em `global.R`.

## Modelo de dados

**Nós:** `id`, `label`, `dpsir_category`, `subsystem`, `uncertainty` (low/medium/high),
`controllability` (low/medium/high), `temporal_scale` (short/medium/long).
**Arestas:** `from`, `to`, `weight`, `confidence` (0–1), `interaction_type`
(`positive`/`negative` — sinal do efeito causal, usado tanto na cor da aresta quanto,
futuramente, como sinal direto da matriz de interação da Fase 5), `evidence_type`,
`threshold` (opcional, `NA` por padrão — ver Fase 5 fast-follow "threshold
não-linear" abaixo; só usado pelo gráfico de trajetória em `mod_responses.R`),
`reference` (opcional, `""` por padrão — texto livre/DOI/URL citando a evidência
por trás da aresta, ver item 7.3 do roadmap de publicação abaixo).
**Conexões DPSIR (padrão):** D→P, P→S, S→I, I→R, R→{D,P,S,I}.

## Estado atual

**Fase 0 concluída** (commit de baseline): removido código morto, `global.R` enxuto,
bugs corrigidos, README e `.gitignore`.

**Fase 1 concluída**: esquema DPSIR configurável (`schema.R`), validação/grafo/métricas
migrados e schema-driven, savepoint `.idpsir.json` funcional, editor por formulário
(nós/arestas via modal, não-reativo), wizard completo (Início→Modelo→Nós→Arestas→
Revisar→Explorar) com guardas de validação entre passos, painel de grafo em camadas
com filtros, painel único de métricas (Gerais/Centralidades/Descritores DPSIR).
Testado ponta a ponta rodando o app (fluxo completo: novo projeto → nós/arestas por
formulário → construir grafo → explorar → salvar savepoint).

Removido do MVP (conforme decisão do PLANO seção 3): abas separadas de Centrality,
Communities, Pathways, Responses. A lógica de pathways/responses foi preservada em
`R/dpsir/` mas não é sourceada — reservada para as Fases 2/3.

**Polimento pós-Fase 1**: toda a UI (labels, botões, mensagens, notificações) está em
inglês — comentários de código e docs (`CLAUDE.md`, `PLANO_iDPSIR.md`) seguem em
português. O painel de grafo (`mod_graph.R`) ganhou controles de exibição: tamanho do
nó por grau (total/entrada/saída, com opção ponderada por weight), espessura da aresta
por weight/confidence/fixa, limiar de tracejado por confiança, e espaçamento
horizontal/vertical + "avoid overlap" configuráveis para evitar grafos ilegíveis.
Corrigido bug em que as arestas não tinham seta de direção (`edges$arrows` nunca era
setado em `build_network_visual`) nem espessura visual (`edges$width` nunca era
calculado). Adicionada legenda de arestas (`build_edge_legend`, cores por
`interaction_type` + indicação de baixa confiança) ao lado da legenda de categorias.

**Bug real encontrado e corrigido durante o teste em runtime:** `compute_diameter`
usava o atributo `weight` da aresta como distância automaticamente (comportamento
padrão do igraph), inflando o diâmetro. Corrigido com `weights = NA` para diâmetro
topológico (hop count). O mesmo cuidado já tinha sido aplicado a betweenness/closeness.

**Fase 2 (parcial) concluída, na branch `fase-2`** (ver PLANO seção 8): dos 6 itens da
Fase 2, os 4 de ganho claro e baixo risco foram feitos — destaque de caminhos causais
no grafo (`highlighted_nodes` em `build_network_visual`, grafo/edges fora do caminho
ficam cinza), seleção cruzada grafo↔tabela (clique no nó seleciona a linha na tabela e
vice-versa, `mod_graph.R`) e comunidades redesenhadas com arestas (`mod_communities.R`
+ `build_community_visual`, corrigindo o bug da versão antiga que só mostrava pontos
coloridos sem conexões). Testado ponta a ponta rodando o app.

Pathways **não é uma aba separada**: a primeira versão colocava a análise de caminhos
numa aba própria, mas isso obrigava o usuário a selecionar o caminho lá e voltar para a
aba Graph para ver o destaque — pouco intuitivo. Reajustado a pedido do usuário: os
controles (From/To categoria + dropdown "Highlight pathway", com o score no label)
ficam dentro da própria aba Graph, no mesmo padrão de "Select by group"/"Node size
based on". `R/modules/mod_pathways.R` foi removido; a lógica (`R/pathways.R`) passou a
ser usada diretamente por `mod_graph.R`.

**Dois bugs reais encontrados e corrigidos durante o teste em runtime** (nenhum dos
dois aparecia em teste estático, só ao clicar de verdade na UI):
- `dataTableProxy(session$ns("nodes_table"))` estava com namespace duplicado — o
  pacote DT já aplica `session$ns()` internamente ao outputId quando chamado dentro de
  um module, então passar o id já qualificado apontava para um elemento inexistente e
  a seleção grafo→tabela nunca chegava a mudar a tabela. Corrigido para
  `dataTableProxy("nodes_table")` (sem `session$ns()` manual). `visNetworkProxy`, ao
  contrário, precisa do `session$ns()` explícito — os dois pacotes têm convenções
  diferentes, vale conferir sempre que usar proxies de htmlwidgets dentro de módulos.
- A trava anti-loop `suppress_graph_sync` nunca era consumida (porque
  `visNetworkProxy() %>% visSelectNodes()` não reemite o evento `select` do vis.js),
  então ficava presa em `TRUE` e engolia o próximo clique real no grafo. Removida —
  só a direção tabela→grafo precisa de trava (`suppress_table_sync`), porque
  `selectRows()` sim reaciona `input$..._rows_selected`.

Matriz de conexões livre e aninhamento hierárquico de níveis ficam de fora por ora —
mudam a arquitetura do schema e serão discutidos numa conversa própria antes de
planejar (ver plano em `.claude/` ou pedir para reabrir a discussão).

**Fase 3 concluída, na branch `fase-3`** (cenários de resposta e relatório exportável,
ver PLANO seção 8 e restrição do usuário: gestores não são especialistas em DPSIR/grafos,
então a aba evita jargão de grafo na tela). Novos arquivos:
- `R/responses.R` — adaptado de `R/dpsir/core_dpsir_responses.R` (que continua
  preservado no disco, não sourceado), mais `find_response_targets` restaurada (vivia
  no `core_dpsir_pathways.R` antigo e tinha ficado faltando desde a Fase 2).
  `get_feedback_categories(schema)` generaliza a categoria "Response" fixa para
  qualquer categoria com `role == "feedback"`. `compare_multiple_states` generaliza
  `compare_states` para N grafos nomeados (baseline + cenários lado a lado).
- `R/modules/mod_responses.R` — aba "Scenarios": uma linha (checkbox + slider 0-100%)
  por nó de categoria feedback existente na rede; "Apply scenario" encadeia
  `apply_response` para cada resposta marcada sobre o mesmo grafo (combinação de
  respostas é só um loop). Mostra "Effect on the network" (`compare_states`) e "Effect
  on each factor" (`summarize_response_impact`, com Improves/Worsens/Stable em
  linguagem simples — os scores numéricos ficam ocultos por padrão via `columnDefs
  visible=FALSE` mas continuam no export CSV/Excel). Cenários salvos ficam em
  `reactiveValues` só na sessão (não entram no savepoint ainda). Selecionar 2+
  cenários salvos habilita "Compare selected scenarios" (baseline sempre incluído
  automaticamente) — comparação rápida só em tela, exportação em HTML vive na aba
  Report (ver abaixo).

Testado ponta a ponta rodando o app: rede de 6 nós (D1/P1/S1/I1/R1/R2) com R1 e R2 como
Response, dois cenários salvos (R1 a 60%; R1+R2 a 60%/80%), comparação mostrando
`total_edge_weight` caindo corretamente (9→6.6→5.0) — sem erros no console do
servidor em nenhum passo.

`R/dpsir/core_dpsir_pathways.R` e `R/dpsir/core_dpsir_responses.R` continuam no disco,
não sourceados — foram só a base de onde `R/pathways.R` e `R/responses.R` foram
adaptados; podem ser removidos numa limpeza futura se não houver mais uso previsto.

**Relatório redesenhado como aba própria "Report"** (última do Explorar), a pedido do
usuário: a primeira versão do relatório (Fase 3 original) vivia dentro da aba Scenarios
e só cobria comparação de cenários — achado "muito simples" e pouco informativo. Agora
`R/report.R` (`build_full_report_html`) + `R/modules/mod_report.R` deixam o usuário
escolher, via checkboxes, quais seções entram no HTML final: grafo (imagem), métricas
gerais, centralidades, descritores DPSIR, e seleção múltipla de cenários salvos
(baseline sempre incluído automaticamente). Continua sem rmarkdown/pandoc (mesma razão
da Fase 3: `rmarkdown::pandoc_available()` é `FALSE` nesta máquina) — HTML montado com
`htmltools::tagList`/`save_html()`, `report_html_table` arredondando números a 2 casas
(inteiros sem `.00` via `format_report_cell`, ajustado depois do teste ter mostrado
"2.00" em contagens de nós/arestas — pouco legível). Comunidades (imagem + tabela de
membership) ficou de fora deste primeiro corte por decisão do usuário — fica como
próximo passo natural, reaproveitando a mesma mecânica de captura de imagem abaixo.

**Bug real de captura de imagem, encontrado e corrigido só ao testar em runtime** (não
aparecia em teste estático): a ideia inicial era capturar o grafo com `html2canvas`
(já carregado pelo `visExport()` do widget, sem dependência nova) no momento em que o
usuário marca "Include network graph" — mas isso é feito *na aba Report*, e nesse
momento a aba Graph está com `display:none`. `html2canvas` sobre um elemento oculto
(e o próprio `<canvas>` do vis-network, verificado diretamente via
`network.canvas.frame.canvas`) sempre retornava `width=0, height=0` →
`toDataURL()` virava `"data:,"`, uma imagem inválida, mas que passava sem erro pelo
`is.null()` do lado R (silenciosamente quebrado). Corrigido invertendo quem dispara a
captura: `mod_wizard_server` (que tem acesso a `input$current_step` e ao
`tabsetPanel(id=...)` da aba Explorar) dispara a captura sempre que a aba Graph fica
de fato visível — ao chegar no passo Explorar (Graph é a aba padrão) e sempre que o
usuário volta pra ela — enviando o resultado direto pro input da aba Report via
`session$sendCustomMessage`. O handler em `mod_report.R` só registra o listener e
descarta capturas de tamanho zero (`canvas.width > 0 && canvas.height > 0`), então uma
tentativa falha (ex.: primeiro carregamento antes do layout assentar) não sobrescreve
uma captura boa anterior. A legenda do grafo é um `vis.Network` separado (visível no
grep de `visNetwork.js`: `document.getElementById("legend"+el.id).network`), então a
imagem capturada inclui a legenda porque `html2canvas` rasteriza a div inteira do
widget (não só o canvas principal) — mantido assim de propósito.

Este mecanismo de auto-captura ao trocar de aba foi **substituído** na Fase 4
(seção "Múltiplos snapshots do grafo para o relatório" abaixo) por uma captura
manual e nomeada, disparada por um botão dentro da própria aba Graph — mais
simples (o elemento já está visível quando o botão é clicado, sem precisar do
listener de troca de aba nem do timeout) e permite salvar mais de uma vista.

**Fase 4 concluída, na branch `fase-4`** (ver PLANO seção 8, itens 4.1-4.3):

- **4.1 — Combinar savepoints.** `schemas_equivalent()` novo em `R/schema.R` (compara
  nome/ordem/papel de feedback dos níveis, ignorando cor/forma que são cosméticas) e
  `merge_savepoints()` novo em `R/io.R`: só combina savepoints com schema equivalente
  (mensagem clara se não forem); ids de nó duplicados entre savepoints ganham prefixo
  automático do nome do arquivo de origem (ex.: `water__D1`) — só quando há colisão de
  fato, ids únicos ficam como estavam; arestas são concatenadas e passam por `unique()`.
  Nova opção "Combine savepoints" no passo Início (`mod_data.R`), aceita 2+ arquivos
  `.idpsir.json` via `fileInput(multiple = TRUE)`. Testado standalone (schemas
  incompatíveis são rejeitados; colisão de id resolvida; grafo resultante válida e
  constrói normalmente) e ponta a ponta no app (duas redes de 3-4 nós cada, combinadas
  em 7 nós/5 arestas, wizard completo até Explorar sem erros).
- **4.2 — Aba Graph reorganizada.** Motivo: os controles de exibição ficavam empilhados
  acima do grafo (cinco `fluidRow`s antes do widget aparecer), empurrando pra baixo o
  que importa na aba. Agora os controles vivem em caixas colapsáveis
  (`bs4Dash::box(collapsible = TRUE)`) numa coluna estreita à esquerda, agrupadas por
  tema; o grafo + legenda ocupam a coluna maior à direita. `mod_communities.R` foi
  absorvido: Communities deixou de ser aba/widget separado e virou uma opção
  "Color nodes by: DPSIR category | Community" do mesmo grafo, chamando
  `build_community_visual` com os mesmos `filtered_nodes()`/`filtered_edges()`/
  `filtered_graph()` e os mesmos controles de espaçamento/tamanho/espessura já usados
  pela cor por categoria — elimina a divergência que existia entre os dois widgets
  antes (cada um podia estar configurado de um jeito diferente). O `tabsetPanel` do
  Explorar caiu de 5 para 4 abas (Graph/Scenarios/Metrics/Report). Testado no app: as
  duas subredes da Fase 4.1 aparecem corretamente coloridas por categoria e por
  comunidade (Louvain detectou as duas subredes desconectadas como duas comunidades),
  filtro de subsistema funciona nos dois modos, sem erros no console do servidor.
- **4.3 — Botão Next oculto no último passo.** No passo Explorar (o último), Next não
  levava a lugar nenhum mas continuava visível e clicável. Agora só aparece enquanto
  `current_step < 6` (`conditionalPanel` em `mod_wizard.R`); Back e "Save savepoint"
  continuam disponíveis em qualquer passo.
- **Auto-instalação de pacotes em `global.R`.** Motivo: `shiny::runGitHub()` é o
  caminho mais simples para um gestor sem experiência em R abrir o app, mas até aqui
  exigia rodar `install.packages(...)` manualmente antes — um passo a mais fácil de
  esquecer ou errar. Agora `global.R` checa `required_packages` via
  `requireNamespace()` antes de qualquer `library()`, instala só os que faltarem
  (ajustando `options(repos=...)` para o CRAN público se nenhum mirror estiver
  configurado, evitando o erro "trying to use CRAN without setting a mirror" em
  sessões não interativas) e só então carrega tudo. Testado rodando o app localmente
  (todos os pacotes já instalados, então `missing_packages` fica vazio e o app sobe
  normalmente sem nenhum erro no console).
- **Clear selection nos Nodes e múltiplos snapshots do grafo para o relatório**,
  ambos apontados pelo usuário ao revisar a `fase-4` antes do merge:
  - A sincronização cruzada tabela↔grafo (Fase 2) nunca tinha um caminho para
    *desfazer* uma seleção feita pela tabela: `visSelectNodes()` destaca o nó no
    grafo, mas nada limpava esse destaque depois, já que o DT não dispara evento
    algum quando uma linha já selecionada é clicada de novo. Adicionado botão
    "Clear selection" na caixa "Nodes" (`mod_graph.R`) que chama
    `selectRows(proxy, NULL)` na tabela e `visUnselectAll()` no grafo.
  - A captura de imagem do grafo para a aba Report (Fase 3) guardava só a última
    vista automaticamente, sem nome, sem possibilidade de comparar duas
    configurações diferentes no mesmo relatório. Substituída por captura manual
    e nomeada: "Save current view for report", abaixo do próprio grafo em
    `mod_graph.R`, dispara o mesmo `html2canvas` via `session$sendCustomMessage`
    (handler compartilhado, registrado em `mod_report.R`) e guarda o resultado
    numa lista nomeada (`reactiveValues`, mesmo padrão de `saved_scenarios` em
    `mod_responses.R`) — o usuário pode salvar quantas vistas quiser (ex.: "By
    category", "By community", "Fisheries pathway") e escolher quais entram no
    relatório. `mod_graph_server` agora retorna essa lista
    (`graph_snapshots = reactive(...)`), encaminhada por `mod_wizard_server` para
    `mod_report_server`; `build_full_report_html` ganhou
    `graph_snapshots`/`selected_snapshot_names` no lugar de `graph_image` único,
    gerando um `<h3>` + `<img>` por snapshot selecionado. Como o botão de captura
    agora vive na própria aba Graph (sempre visível quando clicado), o mecanismo
    de `mod_wizard_server` que disparava a captura ao trocar de aba (Fase 3) foi
    removido — não é mais necessário. Testado ponta a ponta rodando o app: savepoint
    de 4 nós carregado, dois snapshots salvos ("Snapshot 1"/"Snapshot 2"), ambos
    aparecendo na tabela de seleção múltipla da aba Report, relatório baixado
    contendo as duas seções com `<img>` válidas (`data:image/png;base64,...`, não
    vazias); seleção de nó via tabela destacando o grafo e "Clear selection"
    desfazendo a seleção da tabela corretamente — sem erros no console do servidor
    em nenhum passo.
- **Vocabulário de `interaction_type` simplificado para `positive`/`negative`**,
  a pedido do usuário, preparando o terreno pra Fase 5. Motivo: o vocabulário
  antigo (`increases`/`reduces`/`triggers`/`mitigates`/`improves`) já colapsava
  visualmente em duas cores (vermelho para increases/triggers, verde para
  reduces/mitigates/improves — ver `get_interaction_type_colors()` em `graph.R`),
  mas como texto livre exigiria uma tabela de mapeamento texto→sinal só pra
  alimentar a matriz de interação `A[i,j]` da Fase 5 (seção 8 do PLANO). Reduzido
  direto ao sinal (`positive` = a aresta aumenta o alvo, `negative` = diminui/
  mitiga), sem ambiguidade e sem depender de interpretação de sinônimo.
  `get_interaction_types()` (`schema.R`) e `get_interaction_type_colors()`
  (`graph.R`) atualizados; `data/sample_edges.csv` remapeado (increases/triggers
  → positive, reduces/mitigates → negative). `mod_data.R` já lia o vocabulário
  dinamicamente via `get_interaction_types()`, então o formulário de aresta não
  precisou de nenhuma mudança. `validate.R` nunca validou os valores de
  `interaction_type` contra a lista (só o formulário restringia via dropdown),
  então CSVs importados com valores antigos não geram erro — ficam sem cor
  reconhecida no grafo (cinza) até serem corrigidos.

**Fase 5 em andamento (Marcos A e B concluídos, ver PLANO seção 8).** `R/loop_analysis.R`
novo, sourceado em `global.R`: `build_interaction_matrix()`, `check_stability()`,
`press_perturbation()` — descritos no bullet de `R/loop_analysis.R` acima. Testado
standalone (`scratchpad/test_loop_analysis.R`) contra o exemplo clássico de Levins/
Puccia (cadeia trófica Recurso→Consumidor→Predador, só o Recurso com autorregulação):
a matriz construída bate exatamente com a matriz do livro-texto, `check_stability`
reconhece a cadeia como estável (autovalores com parte real negativa), e uma
perturbação sustentada (`press`) no Predador reproduz a cascata trófica clássica em
sinal — Predador sobe, Consumidor desce, Recurso sobe — tanto no efeito de um passo
quanto no de equilíbrio. Casos de borda também testados: matriz singular retorna
`NA` com aviso (não erro), grafo sem arestas retorna matriz zero. Testado também
contra um grafo DPSIR real construído via `build_igraph()` (`data/sample_*.csv`,
10 nós/16 arestas): células da matriz batem com peso/sinal esperado, e essa rede de
exemplo (desenhada só pra demonstrar funcionalidades, não pra ser realista) é
corretamente identificada como **instável** — mostra que `check_stability` não
assume estabilidade por padrão, como o PLANO pede.

**Fase 5 Marco B concluído:** `mod_responses.R` revisado pra computar a partir de
`R/loop_analysis.R` em vez de `apply_response()` — descrito no bullet de
`mod_responses.R` acima. `R/report.R`/`mod_report.R` também precisaram mudar em
cadeia, já que cenários salvos deixaram de guardar um grafo modificado (`sc$graph`)
e passaram a guardar o resultado de `press_perturbation` (`sc$result`); a seção
"Scenarios compared" do relatório trocou `compare_multiple_states`/
`summarize_response_impact` por `compare_scenario_effects`/`summarize_scenario_effect`
e o título da tabela de "Effect on the network" (métricas de topologia que não
existem mais) para "Equilibrium effect per factor" (efeito por nó, o que o método
de loop realmente calcula).

**Bug real de `DT::formatRound`, encontrado só ao testar em runtime** (não aparecia
em teste estático nem nos testes standalone de `R/loop_analysis.R`): passar
`colnames = c("Immediate" = "immediate", ...)` pro `datatable()` e depois chamar
`formatRound(columns = c("immediate", "equilibrium"), ...)` (nomes originais do
data.frame) quebrava com "You specified the columns: immediate, equilibrium, but the
column names of the data are Metric, Immediate, Equilibrium" — nesta versão do
pacote DT, `formatRound()` casa contra o nome de exibição pós-`colnames`, não contra
o nome original da coluna. Corrigido renomeando o data.frame diretamente
(`names(df) <- c("Metric", "Immediate", "Equilibrium")`) antes de `datatable()`, sem
usar o parâmetro `colnames=` — o mesmo padrão que o código anterior (Fase 3) já usava
e nunca tinha esse problema porque nunca combinava `colnames=` com `formatRound()` no
mesmo output.

Testado ponta a ponta rodando o app: rede cíclica de 5 nós (D1→P1→S1→I1→R1→D1, um
único loop com 2 arestas negativas — portanto um loop de feedback líquido positivo,
matematicamente instável) carregada via savepoint. `check_stability` corretamente
identifica a rede como instável e o aviso em linguagem simples aparece antes das
tabelas. Ativar R1 a 50% produz um efeito imediato só em D1 (o único alvo direto de
R1) mas um efeito de **equilíbrio** só em I1 (Public health risk) — resultado
verificado independentemente calculando `A`, `A %*% press` e `-solve(A) %*% press`
à mão em R fora do app: bate exatamente, incluindo os autovalores complexos que
confirmam a instabilidade. Dois cenários salvos (R1 a 50%/80%) comparados lado a
lado mostram o efeito de equilíbrio escalando proporcionalmente (-0.5 → -0.8) e a
contagem Improves/Worsens/Stable batendo entre a view individual e a comparação.
Relatório HTML gerado com as duas seções (métricas gerais + cenários comparados),
os valores -0.5/-0.8 confirmados presentes no HTML baixado. Sem erros no console do
servidor em nenhum passo, após corrigir o bug do `formatRound` acima.

**Fase 5 Marco C concluído.** `simulate_trajectory()` adicionada a
`R/loop_analysis.R`, integrada em `mod_responses.R` como disclosure opcional —
descritos nos bullets de `R/loop_analysis.R`/`mod_responses.R` acima.

**Decisão de design que mudou de rumo ao testar:** a leitura mais literal do PLANO
("A mesma matriz A aplicada repetidamente: A, A², A³...") vira Euler **explícito**
com passo=1 aplicado direto ao vetor de press — implementada primeiro, mas
descartada ao testar contra o exemplo da cadeia trófica estável (Marco A): a
trajetória **divergia** (magnitude 1→2→3→4→6→7→11→...→89 em 15 passos) mesmo numa
rede que `check_stability()` corretamente identifica como estável, porque Euler
explícito tem uma região de estabilidade numérica minúscula perto do eixo
imaginário — e autovalores complexos são comuns justamente em matrizes com ciclos,
o caso central desta fase. Isso teria contradito o próprio aviso de estabilidade
mostrado acima da tabela, gerando desconfiança no app. Substituída por Euler
**implícito** (`solve(diag(n) - step_size*A)` a cada passo), que é
incondicionalmente estável para Re(autovalor) < 0 — testado com `step_size` 0.5 e
5 no mesmo exemplo estável, convergindo pro `-A^-1*press` exato em ambos os casos, e
divergindo (crescimento >10× entre o passo 20 e o 60) no exemplo do ciclo instável.
`step_size` default ajustado de 1 para 0.5 depois de um segundo achado: com
`step_size=1` exatamente, o ciclo de 5 nós com todos os pesos=1 batia numa
singularidade algébrica exata (`I - A` com autovalor 0), disparando o aviso de
"trajetória não pôde ser computada" logo no primeiro teste — um coincidência
comum o bastante (pesos uniformes, ciclos com autovalor exatamente 1) pra não
deixar como default.

Testado standalone (`R` fora do app) contra os dois exemplos já usados nos Marcos
A/B, e ponta a ponta no app: rede cíclica de 5 nós, checkbox "Show how the effect
evolves over time" ligado, gráfico via `matplot()` renderizado sem erro mostrando
as curvas divergindo (consistente com o aviso de instabilidade já mostrado),
slider "Number of steps" reagindo corretamente a mudanças. Sem erros no console do
servidor em nenhum passo.

**Fase 5 Marco D concluído — Fase 5 completa (Marcos A-D).**
`robustness_check()` adicionada a `R/loop_analysis.R`, integrada em
`mod_responses.R` como disclosure opcional — descritos nos bullets acima.

Achado durante os testes: a rede de exemplo da cadeia trófica (Marcos A/B) se
mostrou **sign-determinada** — variar o peso das arestas em até ±90%
(`spread = 0.9`) nunca muda o sinal do efeito de equilíbrio em nenhum nó, mesmo com
confiança mínima em todas as arestas. Não é um bug: é uma propriedade matemática
conhecida de certas estruturas de loop simples (cadeias/loops únicos), a base
teórica de boa parte da própria análise de Levins — o sinal do resultado às vezes
é determinado só pela topologia (quais arestas são positivas/negativas), não pela
magnitude. Pra testar de verdade o caso onde o sinal genuinamente depende da
magnitude, foi preciso um segundo exemplo construído à mão: dois caminhos de sinal
oposto convergindo no mesmo nó (uma aresta direta negativa competindo com um
caminho indireto positivo de dois saltos) com auto-regulação em cada nó pra manter
a matriz invertível. Nos pesos originais (todos 1) os dois caminhos se cancelam
exatamente (efeito de equilíbrio = 0, "Stable") — um empate no fio da navalha onde
*qualquer* perturbação deveria derrubar a classificação. Confirmado: 0% de
concordância nesse nó em 300 simulações, contra 100% nos outros dois nós
(não-ambíguos). Verificado também que o percentual fica na mesma faixa entre
N=50 e N=1000 (sem oscilação selvagem, como o PLANO pede — "vendo o percentual
estabilizar conforme aumenta N").

Testado ponta a ponta no app: rede cíclica de 5 nós, resposta ativada, checkbox
"Show robustness to uncertainty" ligado, tabela renderizada sem erro (100% de
concordância pros 5 fatores nessa rede específica — plausível, não um caso de
empate delicado como o exemplo construído a mão), slider "Number of simulations"
reagindo corretamente a mudanças (testado de 100 pra 20). Sem erros no console do
servidor em nenhum passo.

**Qualidade das figuras do relatório melhorada**, a pedido do usuário ao revisar o
report gerado (legenda cortada, grafo descentralizado, baixa resolução — objetivo:
"figuras de alta qualidade para publicação"). Investigado diretamente no DOM/JS ao
vivo, não por suposição — três causas reais, três fixes:

- **Baixa resolução:** `html2canvas.toString()` inspecionado diretamente confirma que
  a versão empacotada pelo `visExport()` do visNetwork é anterior à 1.0 e não tem a
  opção `scale` (testado: passar `scale: 3` não mudava nada no canvas resultante).
  Como o próprio `<canvas>` do vis-network redesenha nítido em qualquer tamanho CSS
  que o container receber (testado: aumentar o container em 2.5x fez o canvas
  interno crescer 2.5x de verdade, não só esticar borrado), a captura agora
  redimensiona o container temporariamente (~2.5x), pede pro `vis.Network` (acessado
  via `HTMLWidgets.find(...)`, expõe `.network`/`.legend`) refazer `setSize()` +
  `redraw()` + `fit()` nesse tamanho maior, captura, e só então restaura o tamanho
  original.
- **Legenda cortada:** a legenda é um segundo `vis.Network` independente, posicionado
  `position="right"` dentro do mesmo container — medido ao vivo, sua borda direita
  fica exatamente rente à largura do container (~0px de folga), e o conteúdo real
  também vaza ~15px abaixo da altura declarada. `html2canvas` só renderiza a caixa
  que o elemento declara, cortando esse vazamento silenciosamente. Corrigido medindo
  o bounding box real de todos os descendentes (grafo + legenda, no tamanho já
  aumentado) e passando isso como `width`/`height` explícitos pro `html2canvas`.
- **Grafo descentralizado:** se o usuário tivesse arrastado/dado zoom antes de
  salvar, essa posição é o que ficava gravado. Corrigido chamando `.fit()` nos dois
  `vis.Network` (grafo e legenda) depois do redimensionamento, antes de capturar.

Mais dois ajustes, descobertos só ao olhar a imagem capturada de verdade (não visíveis
por inspeção de DOM): os próprios controles do vis-network (setas de navegação,
dropdown "Select by group", botão "Export as png") ficam presos aos cantos do
container — ao aumentar o container em 2.5x, isso empurra esses controles pra bem
longe do diagrama, inflando a "caixa combinada" medida acima e enchendo a imagem de
espaço morto. Escondidos (`display:none`) só durante a captura, restaurados depois.
E `cropToContent()`, que escaneia o canvas capturado pelo bounding box real de pixels
não-brancos e corta a margem morta ao redor.

**Uma tentativa revertida:** também tentei colapsar o espaço horizontal *entre* o
diagrama e a legenda (as duas ainda ficam bem afastadas mesmo depois do corte, já
que `position="right"` da legenda é relativo à largura do container, independente de
quão largo o diagrama em si seja) — procurando a maior faixa de colunas totalmente
em branco e encurtando-a. Descartado ao testar: as próprias setas/linhas da legenda
("positive"/"negative") são majoritariamente em branco no meio, só com conteúdo nas
pontas, então a busca por "maior faixa em branco" cortava no meio dessas linhas em
vez do espaço entre diagrama e legenda, corrompendo visualmente a legenda. Não valia
a pena a fragilidade extra por uma reclamação secundária, já que as três nomeadas
pelo usuário (legenda cortada, resolução, centralização) já estavam resolvidas sem
esse passo.

Testado ponta a ponta rodando o app de verdade (não só lendo código): savepoint de
10 nós/16 arestas, "Save current view for report" clicado, captura interceptada e
baixada como arquivo real (não só inspecionada via `canvas.toDataURL()` em memória)
— confirmado visualmente: resolução saltou de ~760x800 para ~1890x2000 (2.5x),
legenda completa e visível (categorias DPSIR + tipos de aresta + "Low confidence"),
grafo centralizado, controles de navegação/seleção do vis-network ausentes da
imagem final. Sem erros no console do servidor em nenhum passo.

**Legendas e parametrização no relatório**, segundo pedido do usuário feito na
mesma conversa do item acima ("é importante incluir as legendas das figuras e
das tabelas... e descrever eventuais parametrizações feitas"). Duas mudanças:

- **Numeração e legenda de toda figura/tabela**: `build_full_report_html`
  (`R/report.R`) ganhou contadores fechados (`next_figure_n()`/`next_table_n()`)
  e um `caption_tag()` que imprime um `<p class="report-caption">` logo abaixo
  de cada tabela/imagem ("Figure 1.", "Table 1.", "Table 2."...) — numeração
  sequencial pelo relatório inteiro, não reiniciada por seção. A legenda da
  figura do grafo vem de `mod_graph.R` (ver abaixo); as legendas das tabelas são
  texto fixo descrevendo o que a tabela mostra (a mesma explicação para
  qualquer rede, já que a tabela em si não muda de estrutura).
- **Parametrização descrita e de fato usada**: ao investigar onde descrever a
  parametrização da aba Centralities, foi encontrado um bug real (não só uma
  lacuna): `R/report.R` chamava `compute_all_metrics(graph)` **sem nenhum
  parâmetro**, sempre usando os defaults da própria função
  (`directed=TRUE, normalized=TRUE, weighted=FALSE`) — só que o toggle
  `ina_toggle_directed()` usado na aba Metrics (`R/core/core_ui_components.R`)
  tem `value=FALSE` (Undirected) como default, **diferente** do default de
  `compute_all_metrics()`. Ou seja, o relatório já divergia silenciosamente da
  tabela que o usuário via em tela, mesmo sem o usuário mexer em nada. Corrigido
  expondo os três toggles (`directed`/`normalized`/`weighted`) como
  `centrality_params` retornado por `mod_metrics_server`, encaminhado por
  `mod_wizard_server` até `mod_report_server` e passado tanto para
  `compute_all_metrics()` (corrige o valor) quanto para o texto da legenda
  ("Computed with: undirected graph, normalized scores, weighted by edge
  weight..." — corrige a descrição). Verificado ao vivo: alternar "Weighted"
  pra ligado na aba Metrics e gerar o relatório em seguida produz os mesmos
  números na tabela de Centralidades do relatório e da tela (confirmado
  comparando `betweenness=0.17`/`closeness=0.67` idênticos nos dois lugares).
- A legenda de cada figura de grafo (`mod_graph.R`'s `build_snapshot_caption()`)
  é montada a partir dos `input$...` de exibição ativos no momento do clique em
  "Save current view for report": cor por categoria+paleta ou por comunidade+
  algoritmo, filtros de subsistema/temporal (ou "no filters applied"), base do
  tamanho do nó, base da espessura da aresta + limiar de confiança, e o caminho
  destacado se `path_highlight` não for "none". Parâmetros puramente cosméticos
  (espaçamento, tamanho de fonte) ficaram de fora — não mudam o que a figura
  *significa*, só como ela é desenhada.

Testado ponta a ponta rodando o app de verdade: savepoint de 5 nós em ciclo
(D1→P1→S1→I1→R1→D1) carregado via injeção de arquivo no `<input type=file>`
(o upload real via diálogo do SO não é acessível neste ambiente de teste),
grafo construído, um snapshot salvo, um cenário (R1 a 50%) aplicado e salvo, e
na aba Metrics o toggle "Weighted" ligado (ficando `directed=FALSE,
weighted=TRUE` — diferente do default antigo do relatório) antes de gerar o
relatório com todas as seções + o snapshot + o cenário selecionados. HTML
baixado (via `fetch()` direto na URL do `downloadHandler`, já que a seleção de
linha das tabelas DT não reage a cliques sintéticos simples neste ambiente —
contornado setando `input$..._rows_selected` diretamente via
`Shiny.setInputValue`, que é o mesmo valor que a UI real produziria) e
inspecionado: "Figure 1." com a legenda de exibição correta, "Table 1."
a "Table 8." numeradas em sequência por todo o relatório, "Table 2." (Centralidades)
descrevendo e usando exatamente "undirected graph, normalized scores, weighted
by edge weight" — confirmado que os números batem com os mostrados na aba
Metrics. Sem erros no console do servidor em nenhum passo.

**Exemplo didático no tutorial (item 1 da lista pós-Fase 5)**, com savepoint em
`docs/`. `docs/example_fisheries.idpsir.json` — gerado via `build_savepoint()`/
`write_savepoint()` num script standalone (não por edição manual de JSON, pra
garantir que passa por `validate_schema`/`validate_dpsir_nodes`/
`validate_dpsir_edges` de verdade antes de ir pro disco) — é uma rede de 5 nós
em ciclo fechado (D1 Coastal tourism growth → P1 Overfishing → S1 Fish stock
decline → I1 Fisher income loss → R1 Fishing quota policy → D1), com as duas
arestas que fecham o ciclo (I1→R1 e R1→D1) deliberadamente com confiança baixa
(0.6/0.4) por representarem a parte mais especulativa da história (pressão
política reagindo à perda de renda; uma campanha de conscientização amenizando
a demanda turística). Fechar o ciclo até o Driver foi uma escolha deliberada, não
estética: uma primeira tentativa com a Resposta mitigando só a Pressão (mais
"realista" no sentido de que Respostas normalmente não voltam até o Driver)
deixa D1 sem nenhuma aresta de entrada, e um nó sem entrada zera uma linha
inteira de `A` — o que gera exatamente o autovalor zero que torna a matriz
singular (confirmado rodando: `check_stability` retorna instável com um
autovalor exatamente `0+0i`, e `press_perturbation` cai no fallback de
"equilíbrio indefinido" documentado no Marco A/B). Como o schema só permite
Resposta linkar de volta pra categorias anteriores (nenhuma outra categoria
pode), fechar o ciclo até o Driver é a única forma de dar a **todo** nó pelo
menos uma entrada e assim ter uma matriz não-singular de verdade pra demonstrar
o efeito de equilíbrio — por isso a rede final usa R1→D1, não R1→P1.

Testado com a rede final (script standalone com `build_interaction_matrix`/
`check_stability`/`press_perturbation`/`simulate_trajectory`/
`robustness_check`, todos chamados de verdade, não simulados): matriz não-
singular, mas **instável** (autovalores com parte real positiva) — mesmo
padrão já documentado no Marco A/B/D: como o schema proíbe autoloops,
`trace(A)=0` sempre, então `check_stability` nunca retorna `TRUE` pra uma rede
com um ciclo genuíno. Ativar R1 a 70% produz efeito imediato só em D1 (único
alvo direto de R1) e efeito de equilíbrio só em I1 — o imediato e o equilíbrio
caem em nós completamente diferentes, o que virou o exemplo central da seção
"Applying the response" do tutorial. A trajetória diverge (instável, como
esperado) e o robustness check dá 100% de concordância em todos os nós mesmo
com 100 simulações reamostrando as duas arestas de confiança baixa — mostrando
que "a direção do efeito é confiável" e "o sistema vai de fato estabilizar" são
perguntas independentes, a distinção central que o tutorial tenta ensinar.

Verificado ponta a ponta rodando o app de verdade (não só o script standalone):
o JSON gerado foi injetado no `<input type=file>` real do wizard (mesmo truque
de `DataTransfer` já usado nesta sessão) e carregado via "Load savepoint",
avançado por todos os passos do wizard até Explorar, grafo construído sem erro
de validação ("Everything is valid"), nós/arestas na tela batendo exatamente com
o JSON gerado, e o cenário aplicado a 70% na aba Scenarios reproduzindo os
mesmos números do script standalone (`Total effect magnitude`: imediato 0.35,
equilíbrio 0.47) — incluindo o aviso de instabilidade em linguagem simples, a
tabela de robustez (100% em todos os fatores) e o toggle de trajetória, todos
sem erro no console do servidor.

`docs/tutorial.html`: nova seção "4 · Worked example" (TOC renumerado 4→6)
entre "Explore tabs" e "Saving your work", com link relativo para o savepoint
(`example_fisheries.idpsir.json`, mesma pasta) e um passo a passo usando os
números reais verificados acima — não números inventados. Também corrigida a
descrição da aba Scenarios em "3 · Explore tabs", que ainda descrevia o motor
antigo pré-Fase 5 ("overall network effect: edges, total weight, density,
before/after") — desatualizada desde o Marco B; agora descreve "Effect on the
network" (nós afetados + magnitude, imediato vs equilíbrio, aviso de
estabilidade) e os dois disclosures opcionais dos Marcos C/D (trajetória,
robustez), que não apareciam no tutorial antes.

**Item 2a concluído: "quantos passos até neutralizar um Impacto".**
`find_neutralization_step()`/`summarize_neutralization()` (`R/loop_analysis.R`) e
a tabela "When will Impacts be neutralized?" (`mod_responses.R`) — descritos nos
bullets acima.

**Decisão de design que mudou de rumo ao testar** (mesmo padrão de rigor das
descobertas anteriores da Fase 5): a primeira versão gateava o resultado em
`check_stability(A)$stable` — só reportar um número de passos quando a rede
fosse "estável", devolvendo `NA`/"Network not stable" caso contrário, por
analogia direta com o aviso já usado em `press_perturbation()`. Testado contra
três redes diferentes (`docs/example_fisheries.idpsir.json`, uma cadeia trófica
acíclica, e uma reconstrução dela com Resposta fechando o loop) — **nenhuma**
das três chegou a `Stable: TRUE`. Isso não foi falta de sorte: é a mesma prova
já registrada na avaliação da Fase 5 (schema proíbe aresta de nó pra ele mesmo
→ diagonal de `A` sempre zero → `trace(A)` = soma dos autovalores sempre zero
→ `check_stability` matematicamente incapaz de retornar `TRUE` pra qualquer
grafo que este app possa construir, com ou sem ciclo). Gatear nisso teria
deixado a função **morta na prática** — nunca mostraria um número de passos
pra ninguém, só o aviso, tornando o item inteiro inútil. Corrigido soltando a
exigência de estabilidade global: "neutralizado" passou a significar apenas o
primeiro cruzamento de 90% do efeito de equilíbrio já projetado (rise time),
não que o efeito **permanece** lá depois (settling time) — a mesma ressalva de
"estimativa direcional, não garantia" que já vale pro próprio número de
equilíbrio, só que aplicada ao passo. Na prática isso é o que torna o recurso
útil mesmo em redes com ciclo: o exemplo de pescas atinge 90% do efeito
projetado em I1 (Fisher income loss) já no passo 2 — bem antes da trajetória
de fato divergir (visível só a partir do passo ~10 no gráfico de trajetória) —
então o número tem valor prático mesmo sabendo que a rede nunca "assenta" de
verdade no sentido estrito.

Testado com `docs/example_fisheries.idpsir.json` (script standalone e
depois na app rodando): `summarize_neutralization()` reporta corretamente
"Fisher income loss, equilíbrio -0.467, 2 passos, Reaches 90%..." — batendo
exatamente entre o script e a tela (mesmo `press` a 70%, mesmo resultado).
Testado também o caminho negativo (rede construída à mão em que a trajetória
diverge sem nunca cruzar 90% do projetado, por oscilar em vez de convergir
suavemente): retorna corretamente "Not reached within 500 steps" em vez de um
falso positivo. Ponta a ponta na app: savepoint de pescas carregado, grafo
construído, R1 a 70% aplicado — tabela "When will Impacts be neutralized?"
aparece logo abaixo de "Effect on each factor", sem erro no console do
servidor em nenhum passo.

**Item 2b concluído — versão mínima, escopo deliberadamente reduzido.** O
pedido original (modelagem não-linear de threshold na relação Estado→Impacto)
tinha sido classificado como mudança arquitetural maior, a ser discutida à
parte antes de planejar — o que foi feito: em conversa com o usuário, o escopo
foi reduzido a "o usuário escolhe indicar ou não um threshold por aresta"
(campo opcional, a maioria das arestas fica sem), evitando reconstruir o motor
inteiro em torno de não-linearidade. `threshold` (`R/validate.R`,
`R/modules/mod_data.R`'s formulário de aresta, `R/loop_analysis.R`'s
`build_threshold_matrix`/`simulate_trajectory_thresholded`) — descritos nos
bullets acima.

Decisão de design chave, definida antes de implementar (não descoberta ao
testar, diferente das anteriores): o "valor de State que aciona o Impacto" não
podia ser um nível absoluto, porque o motor inteiro só modela **desvio**
causado por uma Resposta (não existe um "baseline" de Driver/Pressão sendo
simulado, só a Resposta entra como `press`). Então o threshold é sobre o quanto
o **cenário simulado** precisa deslocar o nó de origem (em módulo) antes da
aresta ligar — uma simplificação deliberada, documentada como tal no tutorial
e no formulário de aresta, não vendida como um nível ambiental absoluto.
Consequência direta dessa decisão: `check_stability`/`press_perturbation`/
`robustness_check`/`find_neutralization_step` continuam ignorando threshold de
propósito (descrevem só o regime linear/de pequena perturbação); só a
trajetória passo-a-passo, que já simula o cenário se desenrolando no tempo,
ganha o gatilho não-linear — um aviso (`threshold_note`) aparece acima do
gráfico quando isso se aplica, deixando explícito que as tabelas de
equilíbrio/robustez acima não refletem o threshold.

Testado: (1) regressão — `simulate_trajectory()` chamado sem threshold produz
resultado idêntico (`all.equal` `TRUE`) ao comportamento de antes desta
mudança, confirmando que virar um atalho pra
`simulate_trajectory_thresholded(..., Th = NULL)` não alterou nada pra quem já
usava a função; (2) com um threshold de teste na aresta S1→I1 do exemplo de
pescas, I1 fica em zero enquanto `|S1| < threshold`, e passa a reagir
normalmente assim que `|S1|` cruza esse valor — confirmado também o caso
degenerado (threshold gigante, nunca cruzado: I1 fica em zero por toda a
trajetória, nenhum erro). Ponta a ponta na app rodando de verdade: savepoint
de pescas carregado, aresta S1→I1 editada pelo formulário (`Threshold
(optional)` = 0.05, campo em branco funcionando para as outras 4 arestas sem
gerar erro de validação — "Everything is valid"), grafo reconstruído, cenário
aplicado a 70%, gráfico de trajetória habilitado — nota "This network has one
or more edges with a threshold set..." aparece corretamente acima do gráfico,
sem erro no console do servidor em nenhum passo.

**Merge pra `main` + push pro GitHub**, e verificação pré-release. `fase-5`
foi mesclada em `main` via fast-forward (sem conflitos, nenhum commit
divergente) e enviada pro GitHub. Testado de verdade rodando
`shiny::runGitHub("iDPSIR", "gfonseca-unifesp", ref="main")` — download real
do zip do GitHub, não uma cópia local — e repetindo o fluxo do exemplo de
pescas até a aba Scenarios: todos os números bateram exatamente com os já
verificados localmente (aviso de instabilidade, tabelas de efeito, "When will
Impacts be neutralized?", nota de threshold), sem erro no console do
servidor.

README revisado contra esse estado atual e encontrado desatualizado de um
jeito real, não só incompleto: ainda descrevia `R/responses.R`/`apply_response`
como o motor de cenários (superado desde o Marco B por `R/loop_analysis.R`),
não mencionava `R/loop_analysis.R` na árvore de arquivos nem `docs/`
(tutorial + savepoint de exemplo), e a seção Scenarios do Workflow não
mencionava nada da Fase 5 (estabilidade, equilíbrio, trajetória, robustez,
neutralização). Reescrito (intro, árvore, formato de dados, Workflow) pra
refletir o estado atual, com link pro tutorial logo no topo.

**Limpeza pré-release + tutorial acessível de dentro do app.** Dois arquivos
órfãos na raiz do repo, encontrados numa varredura de arquivos não versionados
em `R/`/`data/`/`docs/`, removidos: `iDPSIR_rationale.txt` (esboço de árvore
de arquivos de antes da Fase 0, não bate em nada com a estrutura atual —
`mod_network.R`, `compute/`, `data_models/` etc. nunca existiram na versão
schema-driven) e `quick_start.R` (`install.packages('shiny')` sozinho,
contradizendo o próprio README, que já documenta auto-instalação completa).

Tutorial passou a ser acessível de dentro do app rodando, não só no GitHub:
`global.R` ganhou `shiny::addResourcePath("tutorial", "docs")` (serve
`docs/tutorial.html` — o mesmo arquivo do GitHub, sem duplicar conteúdo nem
reconciliar o CSS próprio do tutorial com o tema do bs4Dash) e `R/ui_main.R`
ganhou um link "Help" em `dashboardHeader(rightUi=...)`, abrindo
`tutorial/tutorial.html` numa aba nova.

**Bug real de bs4Dash, encontrado só ao testar em runtime** (não em checagem
de sintaxe): a primeira versão do link usava só `class = "nav-item"` no
`tags$li` — `bs4Dash::dashboardHeader()` chama `tagAssert(rightUi, type =
"li", class = "dropdown")` internamente, exigindo literalmente a classe
`"dropdown"` no elemento (`bs4Dash:::tagAssert` confirmado lendo o código-fonte
do pacote: `strsplit` na classe + checagem de igualdade exata de token, não
prefixo/substring), e quebrava a inicialização do app inteiro com "Missing
required class" antes mesmo de servir a primeira página. Corrigido pra
`class = "nav-item dropdown"` — como o link não usa `data-toggle="dropdown"`
no `<a>`, o comportamento continua sendo um link normal, só satisfaz a
asserção do pacote. Testado rodando o app de verdade: link "Help" aparece no
canto superior direito, `fetch()` em `/tutorial/tutorial.html` retorna 200
com o conteúdo real do tutorial (título e seção "Worked example" presentes),
clique no link navega pra essa URL com o título certo carregado — sem erro no
console do servidor.

**Gaps de release ainda em aberto, não resolvidos** (levantados numa
varredura mas fora do pedido explícito do usuário até agora): sem `LICENSE`
no repo (relevante pra uso público, já que o README convida
`shiny::runGitHub()`); sem `renv.lock`/`tests/` (já sinalizado no próprio
README como "ainda planejado").

**Fast-follow "layout do grafo"**, a pedido do usuário ao revisar o app antes
do release: o exemplo de pescas (5 nós, 1 por categoria) sempre desenhava
como uma linha reta — não é um bug de renderização, é consequência direta de
`compute_layered_layout` (X fixo por categoria, Y só se espalha *dentro* de
uma categoria — com 1 nó por categoria, Y=0 pra todo mundo). Pra um ciclo de
feedback (o assunto central da Fase 5), isso é ruim: a aresta que fecha o
loop precisa arquear por cima do diagrama inteiro em vez de parecer um loop.
Segundo problema relatado, causa diferente: arrastar um nó não "grudava" —
`nodes$fixed.y` era sempre `FALSE`, então o solver de física (`avoidOverlap`)
continuava reposicionando o nó verticalmente mesmo depois do usuário soltar o
mouse. Um terceiro achado, não relatado mas descoberto ao investigar o
segundo: o campo `positions` do savepoint (existe desde a Fase 1) nunca teve
nada escrevendo nele — mesmo sem a física brigando, um rebuild ou reload
esqueceria qualquer arranjo manual de qualquer forma.

Três correções, mantendo `check_stability`/`press_perturbation`/etc.
intocados (mudança é só visual): (1) `compute_circular_layout` nova em
`R/graph.R` — todos os nós igualmente espaçados num anel, raio cresce com o
número de nós, ignorando categoria; dropdown "Layout" na caixa Display
alterna entre "Layered by category" e "Circular". (2) `fixed.y` passou a ser
`TRUE` para nós arrastados manualmente (`nodes$id %in% manually_placed`) e
para *todos* os nós em modo circular (um anel geométrico preciso não deveria
ser perturbado por física) — nós não-arrastados em modo layered continuam
com Y livre, então "Avoid node overlap" não quebrou pra quem não arrasta
nada. (3) Evento `dragEnd` do vis.js (`visEvents()`, mesmo padrão do `select`
já existente) envia a posição final pro servidor, que grava em
`mod_data.R`'s `rv$positions` via um setter novo (`set_positions`) — o campo
do savepoint finalmente ganhou um escritor. Botão "Reset dragged positions"
limpa tudo de uma vez (`set_positions(NULL)`).

**Bug real, encontrado só ao testar em runtime** (não em checagem de
sintaxe, nem óbvio por leitura de código): a primeira versão do parser do
lado do servidor assumia que `input$node_drag` chegaria como um data.frame
(pra 2+ nós arrastados) ou uma lista aninhada (pra 1 nó) — quebrou
imediatamente com "$ operator is invalid for atomic vectors" assim que
testado de verdade. Depurado com `message(str(...))` no log do servidor: a
deserialização de JSON do Shiny achata um array de objetos `{id,x,y}` num
único **vetor nomeado com nomes repetidos** (`c(id=,x=,y=,id=,x=,y=,...)`),
tanto pra 1 nó quanto pra vários — nem data.frame, nem lista de listas.
Corrigido lendo por nome (`payload[names(payload)=="id"]`, etc.) em vez de
por posição/estrutura, o que funciona igual pra 1 ou N nós arrastados de
uma vez (drag múltiplo, com `multiselect=TRUE` já ligado em `visInteraction`).

Também aproveitado: `show_node_legend`/`show_edge_legend` (checkboxes na
caixa Display) tornam `visLegend()` inteiramente condicional em
`build_network_visual`/`build_community_visual` — com os dois desligados, a
chamada nem roda, sem `<div>` de legenda vazio sobrando.

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado, layout circular confirmado formando um anel de verdade (`getPositions()`
via JS batendo com a fórmula — raio=200, ângulos em incrementos de 72°);
arrastar D1 (via `Shiny.setInputValue` simulando o evento `dragEnd`, já que
um drag de mouse de verdade não é viável neste ambiente de teste) prende o
nó exatamente na posição solta enquanto os outros nós continuam reagindo à
física normalmente; "Reset dragged positions" devolve D1 à posição
calculada; savepoint baixado contém `"positions":[{"id":"D1","x":500,"y":-300}]`
de verdade (não mais sempre vazio); savepoint recarregado (via `fetch()` do
link de download, reinjetado como upload) reconstrói o grafo com D1 já na
posição salva, sem precisar arrastar de novo. Legendas somem e voltam
corretamente ao alternar os checkboxes (confirmado inspecionando o `<div>`
`legend<containerId>` diretamente no DOM, não só o objeto do widget). Sem
erro no console do servidor em nenhum passo, depois de corrigido o parser.

**Bug real pós-lançamento: nó arrastado travava depois do primeiro drag,
não aceitava mais mudanças.** Reportado pelo usuário já em uso, bem depois
do fast-follow acima ter sido dado como testado — porque aquele teste só
simulava o evento `dragEnd` UMA vez (`Shiny.setInputValue`), nunca um
SEGUNDO drag no mesmo nó, que é exatamente onde o bug aparece. Investigado
lendo o código-fonte minificado do `vis-network.js` que o pacote
`visNetwork` empacota (não assumido por documentação ou memória — greppado
direto): `onDragStart` tira uma "foto" do `fixed.x`/`fixed.y` de cada nó
selecionado no **início** de cada gesto de arrastar
(`xFixed:r.options.fixed.x,yFixed:r.options.fixed.y`) e só deixa `onDrag`
atualizar aquele eixo se a foto disser `false`; `onDragEnd` restaura os
valores originais **na instância de rede em memória**. Isso funciona bem
dentro de uma única sessão do widget — mas nosso código pinava um nó
arrastado gravando `fixed.y = TRUE` no **próximo re-render completo**
(`renderVisNetwork` reconstrói um `vis.Network` novo do zero a cada
`positions()` mudar), e esse novo widget nasce com `fixed.y = TRUE` já
"de fábrica" pro nó que foi arrastado — não há "instância anterior" pra
restaurar nada. Resultado: no segundo drag desse nó, `onDragStart` tira a
foto e vê `yFixed = TRUE`, e `onDrag` nunca mais atualiza a posição —
o nó trava, exatamente o relato do usuário.

Corrigido trocando o mecanismo de pino: `fixed.y` volta a ser **sempre
`FALSE`** (então todo drag, não só o primeiro, é respeitado), e quem
impede o nó de derivar sob a física entre um drag e outro passa a ser
`physics = FALSE` nesse nó específico — opção que o `onDragStart`/`onDrag`
do vis-network **nunca consulta** pra decidir se move o nó, então não tem
como travar o drag por essa via. `fixed.x` continua sempre `TRUE` (não
mudou; nunca foi a parte quebrada, e nós nunca puderam ser arrastados
horizontalmente mesmo antes deste bug — mantém o nó na coluna da
categoria DPSIR, comportamento intencional). Modo circular, que antes
pinava todo nó com `fixed.x=TRUE,fixed.y=TRUE` desde o primeiro render
(ou seja, **nenhum** nó nunca foi arrastável em modo circular, um segundo
bug latente que ninguém tinha reportado ainda), passou a usar
`physics=FALSE` em todo nó pelo mesmo motivo — mantém o anel preciso e
libera o drag ao mesmo tempo.

Verificado sem depender de um drag de mouse real (o ambiente de teste
não tem o Browser pane com renderização de tela disponível nesta sessão,
então nem `computer{action:"screenshot"}` nem eventos DOM sintéticos
`PointerEvent`/`MouseEvent` disparam o reconhecimento de gesto do
Hammer.js que o vis-network usa por baixo): em vez disso, cada ciclo
completo "arrastar → salvar posição no servidor → re-render" foi
disparado via `Shiny.setInputValue('...node_drag', [{id,x,y}], ...)`
(o mesmo payload em array que o handler `dragEnd` real envia — usar um
objeto solto em vez de array reproduziu de propósito o erro antigo "$
operator is invalid for atomic vectors", confirmando que o parser só
aceita o formato real), e o estado resultante do nó foi lido direto do
widget (`network.body.data.nodes.get('D1')`) depois de cada ciclo: após
o primeiro drag, `fixed:{x:true,y:false}, physics:false` (antes do fix
teria sido `fixed:{x:true,y:true}`, o estado comprovadamente travado);
repetido um segundo drag no mesmo nó — posição atualiza normalmente,
mesmo `fixed`/`physics` corretos; "Reset dragged positions" devolve o nó
a `physics:true` e à posição calculada do layout. Sem erro no console do
servidor em nenhum ciclo. Suíte `testthat` completa re-rodada (sem
mudança de contagem — o fix é só de `R/graph.R`/visual, fora do núcleo
numérico coberto pelos testes) e checagem de sintaxe de todos os arquivos
`R/`, ambas limpas.

**Roadmap de publicação (`ROADMAP_MELHORIAS_iDPSIR.md`) — rumo a submissão
JOSS/SoftwareX.** O usuário trouxe um roadmap externo (Fases 6-11, escrito
para ser executado incrementalmente) e confirmou: alvo é submissão real, não
só "deixar robusto". Avaliação feita antes de aceitar o roadmap ao pé da
letra — três ajustes técnicos registrados:
- **Item 7.1 (determinância de sinal)** como escrito sugere computar via
  "permanente" da matriz — isso é combinatorialmente inviável (Ryser: O(2ⁿ·n)),
  trava em redes de ~20+ nós. `robustness_check()` (Marco D da Fase 5) já
  implementa a via de simulação equivalente (reamostra pesos por confidence,
  mede concordância de sinal) — 7.1 na prática é "formalizar/renomear no
  vocabulário de Dambacher" o que já existe, não construir do zero.
- **Item 6.2 (renv)** tem uma tensão não endereçada no roadmap: `renv` supõe
  uma biblioteca por projeto persistente, mas `shiny::runGitHub()` baixa pra
  um diretório temporário a cada execução — as duas coisas não se compõem de
  graça, precisa de desenho explícito antes de implementar.
- **Item 8.1 (shinylive)** é o item de maior incerteza técnica do roadmap
  inteiro, apesar de listado como gating: o próprio roadmap pede pra
  "validar bs4Dash" — bs4Dash carrega um tema AdminLTE3 completo com
  dependências JS reais, compatibilidade com WASM é desconhecida até testar.
  Recomendado um spike isolado antes de tratar como gate garantido.

Ordem combinada com o usuário: **7.3 → 6.3 → 6.1** (6.1 fica por último —
falta a lista completa de coautores pro `CITATION.cff`).

**Item 7.3 concluído: referência/DOI por aresta.** Campo opcional `reference`
(texto livre — DOI, URL, ou citação simples — deliberadamente **sem** validação
de formato, mesma lógica de `evidence_type` e dos demais campos de texto livre
do app) seguindo exatamente o mesmo padrão já estabelecido pelo `threshold`
(fast-follow "threshold não-linear" acima): `R/validate.R`'s
`normalize_dpsir_edges()` garante a coluna sempre presente (default `""`,
não `NA`, pra casar com o padrão de `nzchar()`/`== ''` já usado em
`interaction_type`/`evidence_type`); `R/modules/mod_data.R`'s formulário de
aresta ganhou um `textInput` "Reference (optional)"; `R/graph.R`'s
`build_edge_tooltip()` mostra a referência no hover; `R/report.R`'s
`build_full_report_html()` ganhou `include_references` e uma seção
"References" (tabela Link × Reference, uma linha por aresta com referência
preenchida, omitida por completo se nenhuma aresta tiver) — `R/modules/mod_report.R`
ganhou o checkbox correspondente. `data/sample_edges.csv` e
`docs/example_fisheries.idpsir.json` ganharam a coluna (a maioria das arestas
em branco; a aresta P1→S1 do exemplo de pescas, a mais monitorada da rede,
ganhou uma citação ilustrativa — marcada explicitamente como "not a real
source" pra não ser confundida com literatura de verdade).

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado (com a referência já no JSON), tabela de Arestas mostrando a coluna
`reference` corretamente, grafo construído sem erro, tooltip da aresta P1→S1
mostrando a citação completa (confirmado lendo `network.body.data.edges` via
JS, não só inspeção visual), checkbox "Edge references" na aba Report
marcado, relatório baixado contendo `<h2>References</h2>` com a tabela
Link/Reference correta e numerada em sequência com as demais tabelas
("Table 2." nesse teste) — sem erro no console do servidor em nenhum passo.

**Item 6.3 concluído: testes `testthat` do núcleo numérico.** `tests/testthat.R`
(runner) + `tests/testthat/helper-setup.R` + quatro arquivos de teste
(`test-loop_analysis.R`, `test-metrics.R`, `test-io.R`, `test-validate.R`),
77 expectativas, todas passando. Como o app ainda não é um pacote R instalável
(item 6.1, adiado), `helper-setup.R` **não** faz `source("global.R")` — isso
puxaria `library(shiny)`/`bs4Dash`/`DT`/etc. e rodaria o auto-install de
pacotes à toa, já que os testes só exercitam `schema.R`/`validate.R`/`graph.R`/
`metrics.R`/`loop_analysis.R`/`io.R`, nenhum dos quais precisa de UI. Só
`library(igraph)` + os seis `source()` relevantes.

**Achado real ao rodar pela primeira vez, não assumido**: `testthat::test_dir()`
executa cada `helper-*.R`/`test-*.R` com o *working directory* setado pra
dentro de `tests/testthat/` (não o diretório de onde `test_dir()` foi chamado)
— confirmado empiricamente depois que `source("R/schema.R")` falhou com
"arquivo não encontrado" mesmo rodando o runner da raiz do repo. Corrigido
usando `"../../R/..."` em vez de `"R/..."` tanto no helper quanto nos
`read_savepoint("../../docs/example_fisheries.idpsir.json")` dos testes que
usam o exemplo de pescas como fixture.

**Achado real de quebra**, também só ao rodar de verdade (não em checagem de
sintaxe): `as.undirected()` está deprecated desde igraph 2.1.0 (substituído
por `as_undirected()`) — surgiu como *warning* rodando os testes de
`compute_all_metrics(directed=FALSE)`, não algo que eu tivesse ido procurar.
Corrigido nos dois arquivos **sourceados** que ainda usavam a forma antiga
(`R/metrics.R`, `R/modules/mod_graph.R`); `R/modules/mod_communities.R` (não
sourceado desde a Fase 4.2) foi deixado como estava — não vale a pena manter
código morto atualizado. Testado ponta a ponta rodando o app de verdade
depois da troca: "Color nodes by: Community" no savepoint de pescas continua
detectando comunidades e colorindo o grafo sem erro (Louvain sobre o grafo
não-direcionado via `as_undirected()`), confirmado lendo os grupos de cada
nó diretamente do widget vis.js via JS.

Dois exemplos numéricos usados como fixture, ambos verificados antes de virar
teste permanente (nunca a partir de suposição): (1) a cadeia trófica clássica
de 3 espécies (Recurso→Consumidor→Predador, só o Recurso com autorregulação)
— construída como matriz `A` direto, contornando `build_igraph()`/o schema de
propósito, já que o schema proíbe o autoloop que essa autorregulação exige;
autovalores/imediato/equilíbrio conferidos com `eigen()`/álgebra manual antes
de virar `expect_equal()`; (2) `docs/example_fisheries.idpsir.json`, cujos
números (imediato -0.35 em D1, equilíbrio -0.4667 em I1, 2 passos até 90%,
100% de concordância na robustez) já tinham sido verificados de forma
independente múltiplas vezes nesta sessão antes desta rodada de testes —
reaproveitados como regressão, não recalculados de olho fechado.

**Item 7.1 concluído: determinância de sinal.** `sign_determinacy()` e
`compare_scenario_sign_confidence()` (`R/loop_analysis.R`), coluna "Sign
confidence (%)" em "Effect on each factor", tabela "Sign confidence per
factor" na comparação de cenários (em tela e no relatório) — descritos nos
bullets acima. Como já avaliado antes de aceitar o item do roadmap ao pé da
letra (ver "Priorização geral" acima): a rota analítica via permanente da
matriz foi descartada de propósito (combinatorialmente inviável), e
`robustness_check()` do Marco D já era, na prática, a implementação numérica
certa — 7.1 formalizou/expôs isso como resultado de primeira classe (sempre
visível, não só atrás do disclosure opcional) em vez de construir um segundo
método.

Decisão de design: a confiança de sinal passou a ser calculada
automaticamente em todo "Apply scenario" (N=100 fixo), não só quando o
usuário abre "Show robustness to uncertainty" — o disclosure continua
existindo, agora reposicionado como a versão configurável/aprofundada
(ajustar N, ver a tabela ordenada por confiabilidade) que reaproveita a
mesma função. Testado que `sign_determinacy()` bate número por número com
`robustness_check()` sob a mesma seed (é literalmente o mesmo código, só com
nome alinhado à literatura de Dambacher) — não é uma segunda implementação
correndo o risco de divergir da primeira.

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado, cenário a 70% aplicado — coluna "Sign confidence (%)" mostrando
100% pra todos os 5 fatores (bate com o já verificado via `robustness_check`
nesta mesma rede em testes anteriores desta sessão); dois cenários salvos
(70% e 40%) comparados — tabela "Sign confidence per factor" aparece com
Baseline/Scenario 1/Scenario 2, todos 100% (baseline calculado direto, sem
rodar simulação, já que press=0 sempre dá equilíbrio=0 não importa a
reamostragem); relatório gerado com os dois cenários selecionados contém a
seção "Sign confidence per factor" com os mesmos números — sem erro no
console do servidor em nenhum passo.

**Item 7.2 concluído: sensibilidade/ranking de arestas.** `global_sensitivity()`
(`R/loop_analysis.R`) e o disclosure "Show which edges matter most" (gráfico
de barras + tabela em `mod_responses.R`) — descritos nos bullets acima. Rota
one-at-a-time (OAT): aumenta o peso de uma aresta por vez em 10%, recalcula
o efeito de equilíbrio pro mesmo `press`, mede quanto mudou (soma dos módulos
das diferenças) e ordena do maior pro menor — reaproveita `press_perturbation()`
direto, sem simulação nova. Mantida a mesma decisão de não adicionar `ggplot2`
já tomada no Marco C (trajetória via `matplot()`): o gráfico usa `barplot()`
do R base.

**Achado ao testar, não um bug:** a primeira rede testada
(`docs/example_fisheries.idpsir.json`) mostrou só **uma** aresta com
influência não-zero (I1→R1), as outras 4 todas exatamente zero. Verificado
por que antes de assumir que fosse um bug: a sensibilidade de
`-A⁻¹·press` a perturbar `A[i,j]` é proporcional ao efeito de equilíbrio
*já existente no nó de origem* dessa aresta — e no ciclo único de 5 nós do
exemplo de pescas, só I1 termina com equilíbrio não-zero (efeito de R1 a
70% cai só em I1, já documentado no item 2a acima), então só a aresta que
sai de I1 pode ter influência alguma; as outras 4, saindo de nós com
equilíbrio zero, não têm o que amplificar. Confirmado independentemente com
uma segunda rede construída à mão (cadeia trófica Recurso→Consumidor→
Predador, onde todo nó tem equilíbrio não-zero) mostrando as 5 arestas com
influência positiva, ordenadas corretamente. Testado também contra
`data/sample_nodes.csv`/`sample_edges.csv` (rede de 10 nós já documentada
como tendo matriz singular, ver Fase 5 Marco A): `global_sensitivity()`
recorre ao mesmo fallback de `press_perturbation()` (efeito imediato em vez
de equilíbrio quando a matriz é singular), mostrando só as 3 arestas que
saem diretamente de R1 (únicas alcançáveis pelo efeito imediato de um
passo) — comportamento correto herdado do fallback já existente, sem
código extra.

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado, R1 a 70% aplicado, checkbox "Show which edges matter most"
ligado — gráfico de barras mostrando só I1→R1 com barra visível, as outras
4 arestas em zero (batendo com o script standalone); tabela ordenada
mostrando os mesmos números (`Influence` arredondado a 3 casas). Entra
também no relatório: seção "Which edges matter most (top 5 per scenario)"
com uma tabela por cenário selecionado, cada uma com sua própria legenda
numerada (corrigido de um primeiro rascunho que usava uma legenda só
compartilhada entre todos os cenários — quebrava o padrão de "toda
tabela/figura tem sua própria legenda numerada" já estabelecido no item de
legendas/parametrização acima). Sem erro no console do servidor em nenhum
passo.

**Item 6.4 concluído: `sessionInfo` + parametrização/semente no relatório.**
Duas mudanças, ambas em `R/loop_analysis.R`/`R/report.R`/`R/modules/mod_report.R`
— descritas nos bullets acima:
- **Semente fixa nas reamostragens.** `robustness_check()`/`sign_determinacy()`
  ganharam `seed=42` (default), com `set.seed(seed)` logo antes do loop que
  sorteia os multiplicadores de peso. Sem isso, "Sign confidence" e a tabela
  de robustez mudavam ligeiramente a cada "Apply scenario" — mesmo cenário,
  mesmo grafo, número diferente só pelo sorteio — o que contradiz a própria
  ideia de um relatório reprodutível (o critério "pronto quando" do roadmap
  é literal: "rodar de novo com a mesma semente reproduz números idênticos").
  `global_sensitivity()` não precisou de nada — já é 100% determinístico (OAT
  sem amostragem).
- **Seção "Reproducibility" no relatório**, opcional (checkbox "Reproducibility
  info", desligado por padrão, mesmo padrão dos outros opcionais). Duas
  partes: "Session info" (versão do R + tabela de versões de cada pacote em
  `required_packages`, reaproveitado direto de `global.R` em vez de duplicar
  a lista — cada versão via `utils::packageVersion()`, com fallback "not
  installed" se um pacote faltar) e "Analysis parameters" (texto fixo citando
  os defaults realmente usados em `mod_responses.R`: `n_simulations=100`,
  `spread=0.5`, `seed=42` pra confiança de sinal/robustez, `relative_change=0.1`
  pra sensibilidade — não números inventados pro texto, os mesmos already
  hardcoded nas chamadas do módulo).

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado, R1 a 70% aplicado (mesmos números já verificados: imediato 0.35,
equilíbrio 0.4667, 100% sign confidence, 2 passos até neutralizar — nenhuma
regressão do fix de semente), cenário salvo, checkbox "Reproducibility info"
marcado via `Shiny.setInputValue` (seleção de linha de tabela não reage a
clique sintético neste ambiente, mesmo contorno já usado em testes
anteriores desta sessão) e relatório baixado via `fetch()` direto na URL do
`downloadHandler`: seção "Reproducibility" presente com "R version 4.3.2"
(a versão de fato instalada nesta máquina), tabela com as 13 versões de
`required_packages` (shiny 1.10.0, bs4Dash 2.3.5, igraph 2.1.4, etc.),
numerada em sequência com as demais tabelas ("Table 6." nesse teste), e o
parágrafo de parâmetros citando exatamente `n_simulations = 100`,
`spread = 0.5`, `seed = 42`, `relative_change = 0.1`. Seções anteriores
("Sign confidence per factor", "Which edges matter most", "Equilibrium
effect per factor") confirmadas presentes no mesmo HTML, sem regressão.
Novo teste de regressão em `test-loop_analysis.R` (`robustness_check` com a
semente default chamado duas vezes, cada uma precedida de um
`set.seed()` externo diferente — 999 e depois 1 — confirmando
`expect_identical()` entre as duas chamadas, provando que o resultado
independe do estado do RNG antes de chamar). Suíte completa rodada de novo
(43 assertivas em `loop_analysis` agora, uma a mais que antes; nenhuma
falha) e checagem de sintaxe de todos os arquivos `R/`, sem erro no console
do servidor em nenhum passo.

**Item 8.1 — spike concluído, CI implementado, na branch `fase-8-shinylive`.**
Antes de aceitar 8.1 como "pronto pra fazer" (a maior incerteza técnica do
roadmap, ver "Priorização geral" acima — bs4Dash carrega um tema AdminLTE3
completo, compatibilidade com WASM era desconhecida), foi feito um spike
isolado em vez de partir direto pra CI:

1. Checado se as 13 dependências de `required_packages` têm binário WASM no
   repositório do webR (`https://repo.r-wasm.org/bin/emscripten/contrib/4.4/PACKAGES`)
   — todas têm, incluindo `bs4Dash` (2.3.4).
2. `shinylive::export(appdir=".", destdir=...)` rodado de verdade sobre o
   repo local, servido com `httpuv::runStaticServer()`, e testado no
   navegador (não só "abriu a página"): savepoint de pescas carregado via
   injeção de arquivo no `<input type=file>` **dentro do iframe** que o
   shinylive usa pra rodar o app (mesmo truque de `DataTransfer` já usado
   nesta sessão, só que atravessando `iframe.contentWindow`/`contentDocument`
   em vez do documento principal), wizard percorrido até Explore, grafo
   construído ("Graph built successfully" — confirma que `igraph`/`validate.R`
   funcionam dentro do WASM), e o cenário R1 a 70% aplicado — os números
   batem exatamente com os já verificados no app nativo (imediato 0.35,
   equilíbrio 0.4667, 100% sign confidence, aviso de instabilidade). Ou seja,
   não é só "a UI carrega": `eigen()`/`solve()` do R base (o núcleo de
   `loop_analysis.R`) produzem resultado numericamente idêntico rodando em
   WebAssembly no navegador.

**Achado real, encontrado só ao inspecionar o export gerado (não documentado
em lugar nenhum do pacote `shinylive`):** `shinylive::export(appdir=".")`
não tem exclusão no estilo `.gitignore` — ele empacota **tudo** que está no
diretório apontado por `appdir`, sem filtrar por extensão nem por relevância
pro app rodar. Rodando a partir da raiz do repo, isso varreu `tests/`,
`ROADMAP_MELHORIAS_iDPSIR.md`, `PLANO_iDPSIR.md`, `CLAUDE.md` — e até um
savepoint de teste solto (não versionado) que estava na raiz do repo local —
pra dentro da árvore de arquivos "do app" que a demo pública exibe/serve
(confirmado via `grep` nos nomes de arquivo dentro do `app.json` gerado).
Nada disso quebra o app, mas é ruído sem propósito numa demo pública — o
workflow por isso **não** exporta a raiz do repo direto: `Stage app files`
copia só `app.R`, `global.R`, `R/`, `data/`, `docs/` pra um diretório `_app/`
temporário antes de chamar `shinylive::export()` nele, o mesmo conjunto de
arquivos que `shiny::runApp()`/`runGitHub()` já usam de fato. Reexportado e
retestado no navegador com esse conjunto reduzido: `app.json` resultante só
lista os arquivos esperados (confirmado via o mesmo `grep`), e o app
carrega/funciona identicamente ao teste anterior (mesmo savepoint de pescas,
mesmo cenário, mesmos números).

`.github/workflows/shinylive.yml` (novo): dois jobs — `build` (checkout,
`r-lib/actions/setup-r@v2` com `r-version: "release"`, instala `shinylive`,
copia os arquivos do app pra `_app/`, exporta pra `_site/`, sobe como
artifact de Pages) e `deploy` (`actions/deploy-pages@v4`), gatilho em push
pra `main` mais `workflow_dispatch` manual — mesmo padrão de dois-jobs
recomendado pela própria documentação de `actions/deploy-pages`. YAML
validado com `yaml::read_yaml()` (a chave `on:` aparece como `TRUE` no
objeto R por causa da coerção booleana do YAML 1.1 — uma peculiaridade
conhecida do parser do pacote `yaml`, não um erro real do arquivo; o parser
do GitHub Actions interpreta `on:` normalmente). README ganhou um badge
"Try it live" no topo e um parágrafo em "How to run" explicando o
compromisso (sem instalar nada, mas primeiro carregamento mais lento —
R e os pacotes baixam pro navegador).

**Decisão de escopo, confirmada com o usuário antes de implementar:** não
foi adicionado um botão "Load demo network" de carregamento automático no
passo Start — o exemplo de pescas já está embutido no export (dentro de
`docs/`) e carregável via "Load savepoint" já existente, o que já satisfaz
o critério "pronto quando" do roadmap ("com o exemplo de pesca carregável,
linkada no README"); um atalho dedicado ficaria fora do escopo do item 8.1.

**Deploy real confirmado — item 8.1 completo.** `fase-8-shinylive` foi
mesclada em `main` (fast-forward) e enviada pro GitHub; o usuário habilitou
Pages (Settings → Pages → Source: GitHub Actions) e confirmou que o workflow
rodou com sucesso. Verificado também deste lado com `curl -o /dev/null -w
"%{http_code}"` contra `https://gfonseca-unifesp.github.io/iDPSIR/`: `200`.
O badge "Try it live" no README aponta pra essa URL e já resolve de
verdade — item 8.1 do roadmap está pronto ponta a ponta, não só validado
localmente.

**Passo Início redesenhado (fora do roadmap de publicação, pedido direto do
usuário ao revisar a UI).** Os 4 cards descritos no bullet de `mod_data.R`
acima — mockup mostrado ao usuário antes de implementar (`start_card()` com
ícone/título/descrição/input(s)/botão numa base comum). Testado ponta a
ponta rodando o app de verdade: os 4 cards renderizam com a mesma altura e
os botões alinhados na mesma linha de base (confirmado por screenshot);
"New project" clicado (via `Shiny.setInputValue`/clique direto no DOM — o
`ref` de um `read_page` desatualizado após a mudança de layout apontava pro
elemento errado numa primeira tentativa, corrigido clicando o elemento por
`id` diretamente) mostra a mensagem de confirmação normalmente abaixo dos
cards; avançar pro passo Model funciona sem erro. Sem erro no console do
servidor em nenhum passo.

**Fase 9 iniciada, na branch `fase-9-auto-regulacao`** (roadmap externo
trazido pelo usuário, `ROADMAP_FASE9_iDPSIR.md`, avaliado antes de aceitar —
rastreado item por item contra o código real de `schema.R`/`validate.R`/
`graph.R`/`io.R`/`mod_data.R`/`loop_analysis.R`, sem nenhum bloqueio técnico
encontrado). Dois itens: **9.1** (auto-regulação por fator, atributo de nó
que desbloqueia efeito de longo prazo/estabilidade — hoje `check_stability()`
nunca pode retornar `TRUE` pra nenhuma rede construída pelo app, porque o
schema proíbe self-loop e por isso a diagonal de `A` é sempre zero) e
**9.2** (alcance de uma resposta, medida puramente topológica, sempre
calculável independente do efeito de longo prazo). Ordem combinada com o
usuário: **9.2 primeiro** (independente, mais simples, não mexe no núcleo
numérico), depois 9.1, tutorial/README por último.

**Item 9.2 concluído: alcance de uma resposta.** `response_reach(g,
active_ids)` (`R/reach.R`, novo arquivo — deliberadamente separado de
`loop_analysis.R`, já que é travessia pura de grafo direcionado via
`igraph::subcomponent(mode="out")`, sem nenhuma álgebra linear envolvida):
parte dos alvos diretos das respostas ativas (`neighbors(g, id,
mode="out")`, não do(s) próprio(s) nó(s) de resposta) e coleta tudo
alcançável a partir daí, excluindo as próprias respostas ativas do
resultado (uma resposta "alcançar a si mesma" via um loop de feedback não é
um fator novo atingido). `count_impacts_in_graph(g)` fica fora dessa
função de propósito — é o denominador do "Y de N Impactos", uma
propriedade da rede inteira, não do que uma resposta específica alcança.

Verificado com quatro casos antes de virar teste permanente (nunca por
suposição, script em `scratchpad/test_reach.R`): (1) o exemplo de pescas
(ciclo fechado de 5 nós) — R1 alcança os outros 4 nós inteiros (o loop
inteiro menos ele mesmo), demonstrando que num ciclo único uma resposta
tende a alcançar quase tudo; (2) uma rede em árvore construída à mão com
duas respostas — uma perto da raiz (age sobre a Pressão, alcança 3 fatores)
e uma de fim-de-cadeia (age direto no Impacto, alcança só 1) — a
comparação raiz-vs-fim-de-cadeia que motiva o item; (3) nenhuma resposta
ativa e (4) uma resposta sem nenhuma aresta de saída — ambos retornam
resultado vazio sem erro.

Interface: seção "Reach" na aba Scenarios, logo abaixo de "Effect on the
network" e explicitamente **ao lado** do aviso de estabilidade (não atrás
dele) — o texto deixa claro que alcance vale mesmo quando o efeito de
equilíbrio não está definido. Calculado de forma eager em "Apply scenario"
(mesmo padrão de `sign_confidence`/`sensitivity` dos itens 7.1/7.2), então
sobrevive em cenários salvos e entra tanto na comparação em tela quanto no
relatório. Tabela "Reach per scenario" na comparação usa baseline fixo em
zero (nenhuma resposta ativa não alcança nada, sem precisar chamar
`response_reach()` com uma lista vazia — embora a função já trate esse
caso corretamente também, testado explicitamente).

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado, R1 a 70% aplicado — "Reach" mostra "4 factors reached, including
1 of 1 Impact" com a tabela listando D1/P1/S1/I1 por categoria, batendo
exatamente com o script standalone; dois cenários salvos (R1 a 70%/40%,
mesmo alcance nos dois já que alcance não depende da força, só de quais
respostas estão ativas — confirmado que isso é o comportamento correto, não
um bug) comparados mostrando "Reach per scenario" com Baseline=0/Scenario
1=4/Scenario 2=4; relatório gerado com os dois cenários contém "Reach per
scenario" numerada em sequência com as demais tabelas ("Table 4" nesse
teste) com os mesmos números. Nenhuma seção anterior (Sign confidence,
Which edges matter most, Equilibrium effect) regrediu. Sem erro no console
do servidor em nenhum passo. Suíte `testthat` ganhou `tests/testthat/test-reach.R`
(6 testes novos, 15 assertivas) — suíte completa roda limpa.

**Item 9.1 concluído: auto-regulação por fator.** Os quatro sub-passos do
roadmap (9.1.1 atributo/vocabulário, 9.1.2 uso no cálculo, 9.1.3 interface
de edição/persistência, 9.1.4 nota condicional + sensibilidade) — descritos
nos bullets de `schema.R`/`validate.R`/`loop_analysis.R`/`mod_data.R`/
`mod_responses.R` acima. Esse item resolve uma limitação estrutural
documentada repetidamente ao longo de toda a Fase 5: como o schema proíbe
aresta de um nó pra ele mesmo, a diagonal de `A` era **sempre** zero pra
qualquer rede construída pelo app, e por isso `trace(A)` (soma dos
autovalores) também era sempre zero — o que torna `check_stability()`
matematicamente incapaz de retornar `TRUE`, não importa a rede. Auto-
regulação, sendo atributo de **nó** (não aresta), preenche a diagonal sem
reabrir essa proibição.

**Verificação decisiva, não assumida**: rodando o exemplo de pescas (ciclo
de 5 nós, sempre instável até agora) com todos os nós marcados
`self_regulation="high"`, `check_stability()` retornou `TRUE` — a
**primeira vez em todo o projeto** que essa mensagem aparece. Autovalores
todos com parte real negativa (`-3.62, -2.50, -2.50, -0.69, -0.69`), e
`press_perturbation()` devolveu um efeito de equilíbrio **totalmente
definido** (sem `NA`) pros 5 nós — antes disso, todo cenário nessa rede só
tinha o efeito imediato como confiável. Testado também: (a) baseline sem
auto-regulação continua idêntico byte a byte ao comportamento anterior
(retrocompatibilidade — savepoints antigos sem a coluna carregam com
`"none"`, sem mudar nenhum número já verificado nesta sessão); (b) níveis
mistos (`low/none/medium/none/none`) preenchem a diagonal corretamente mas
não necessariamente estabilizam a rede — nem toda combinação estabiliza,
comportamento correto, não um bug.

`self_regulation_sensitivity()` testado contra o mesmo exemplo com todos os
nós em "high": 100% de concordância de sinal em todos os 5 fatores variando
a magnitude da auto-regulação em ±50% — a rede se mostrou **determinada em
sinal** também pra essa perturbação (mesmo padrão de achado já documentado
pra `robustness_check()` no Marco D da Fase 5: nem toda rede tem um
resultado delicado o bastante pra ser derrubado por variação de magnitude,
isso é uma propriedade real da topologia, não falta de teste). Um segundo
caso sanidade — rede sem nenhuma auto-regulação — dá 100% trivialmente
(magnitude sempre zero, `A_sim` idêntica a `A_base` em toda simulação, sem
variação nenhuma pra testar), confirmando que a função não quebra nesse
caso degenerado.

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado, os 5 nós editados um a um pelo formulário (via
`el.selectize.setValue('high')` — descoberto que o `<select>` nativo por
trás de um `selectInput` do Shiny só expõe a opção **atualmente
selecionada** como filho DOM quando `selectize=TRUE` (o padrão), não a
lista inteira; confirmado que isso já era assim pro `nm_uncertainty`
pré-existente também, não é bug novo — só corrigi a forma de setar o valor
via JS pra usar a API do selectize em vez de mexer no `<select>` bruto),
grafo reconstruído, cenário R1 a 70% aplicado: aviso de estabilidade mudou
de "not stable" (vermelho) pra **"stable" (verde)**, "Nodes affected" foi
de 1.00→2.00 imediato e 1.00→**5.00** de equilíbrio, a nota de auto-
regulação apareceu corretamente acima das tabelas, e "Show sensitivity to
self-regulation" apareceu na lista de disclosures (ausente antes de marcar
qualquer nó) mostrando a tabela com 100% em todos os fatores — todos os
números batendo exatamente com o script standalone. Recarregado o mesmo
savepoint de pescas **sem** auto-regulação (arquivo em disco não
modificado por este teste): nota e disclosure corretamente ausentes,
aviso volta a "not stable", nenhuma regressão nos números já verificados
(0.35/0.47/100%/8 passos). Sem erro no console do servidor em nenhum
passo. Suíte `testthat` ganhou 7 testes novos entre `test-loop_analysis.R`
(diagonal de auto-regulação, retrocompatibilidade, estabilização/equilíbrio
definido no exemplo de pescas, sensibilidade — incluindo teste de
reprodutibilidade com semente fixa, mesmo padrão do item 6.4) — suíte
completa roda limpa.

**Fast-follow "gráficos editáveis/baixáveis" concluído** (fora do roadmap
de publicação/Fase 9, pedido direto do usuário ao revisar a aba
Scenarios: os gráficos de trajetória e de sensibilidade de arestas não
tinham como ser baixados, configurados além do que já existia, nem
apareciam no relatório). Descrito nos bullets de `R/scenario_plots.R`
(novo arquivo)/`R/report.R`/`R/modules/mod_responses.R` acima.

**Achado que simplificou a implementação, não assumido de antemão**:
diferente do grafo de rede (um widget `vis.Network` vivo em JS, que
precisou de todo um pipeline `html2canvas` pra virar imagem), os dois
gráficos aqui já eram `matplot()`/`barplot()` — desenhos base R renderizados
no **servidor**, não no navegador. Isso significa que um `downloadHandler()`
comum do Shiny (abrir um dispositivo gráfico, redesenhar, fechar) já
resolve o download sozinho, sem captura nenhuma do lado do navegador — bem
mais simples que o mecanismo do grafo. A mesma lógica de desenho
(`draw_trajectory_plot()`/`draw_sensitivity_plot()`, movida pra
`R/scenario_plots.R`) é reaproveitada por três chamadores: o `renderPlot()`
em tela, os `downloadHandler()`s de PNG/SVG, e `plot_to_data_uri()` do
relatório — nunca reimplementada três vezes.

Testado ponta a ponta rodando o app de verdade: savepoint de pescas
carregado, R1 a 70% aplicado, ambos os disclosures abertos — botões
"Download PNG"/"Download SVG" aparecem nos dois gráficos, e o slider
"Number of edges shown" (novo) aparece só no de sensibilidade. Os 4
downloads buscados via `fetch()` direto na URL do `downloadHandler`:
`content-type` correto em todos (`image/png`/`image/svg+xml`) e tamanho
não-zero, confirmando arquivo de verdade gerado, não um placeholder vazio.
Mudar "Number of edges shown" de 10 pra 3 e rebaixar o PNG de novo mudou o
tamanho do arquivo (5656→5061 bytes), confirmando que o controle realmente
afeta o que é desenhado/baixado, não só a tela. Cenário salvo e relatório
gerado com ele selecionado: seções novas "How the effect evolves over
time" e "Which edges matter most" aparecem com imagem `<img>` de verdade
(inspecionada como base64 PNG válido, não vazio) mais a legenda numerada —
numeração sequencial confirmada varrendo o HTML inteiro por
`<strong>Figure N.</strong>`/`<strong>Table N.</strong>`: Table 1-5, Figure 1
(trajetória), Figure 2 (sensibilidade), Table 6 (tabela de sensibilidade
que já existia) — Figuras e Tabelas intercaladas na ordem certa do
documento, não contadores separados. Sem erro no console do servidor em
nenhum passo.

**Itens 9.3/9.4 concluídos: tutorial e README.** Fecha a Fase 9 inteira
(9.1, 9.2, 9.3, 9.4 — a ordem 9.2→9.1→9.3/9.4 combinada com o usuário no
início da fase).

**Achado real ao revisar, não ignorado**: o callout de aviso já existente em
`docs/tutorial.html` ("Applying the response") dizia, em texto fixo, que "the
underlying math structurally can't produce a strict 'yes, stable' verdict for
a genuine loop" — verdade **antes** do item 9.1, mas **falsa** depois dele
(a própria seção nova provava o contrário duas seções abaixo, mostrando
`check_stability()` retornando `TRUE`). Corrigido pra "by default... without
that [self-regulation], the math can't produce a 'yes, stable' verdict" —
sem isso o tutorial teria uma contradição interna entre dois parágrafos a
poucas telas de distância.

`README.md`: `self_regulation` documentado em Data format (mesmo estilo dos
demais atributos), árvore de arquivos ganhou `R/reach.R`/`R/scenario_plots.R`/
`ROADMAP_FASE9_iDPSIR.md`, e o bullet de Scenarios em Workflow passou a citar
que o efeito de equilíbrio/estabilidade é **condicional** à auto-regulação
configurada (com a sensibilidade correspondente), o alcance (sempre
calculável, independente disso), e que os gráficos de trajetória/sensibilidade
agora têm download PNG/SVG e entram no relatório.

`docs/tutorial.html`: nova sequência dentro do "Worked example" existente
(mesmo savepoint de pescas já usado, sem introduzir uma segunda rede) —
"Unlocking a genuine long-term effect: self-regulation" (marcar auto-
regulação "high" nos 5 fatores, ver o aviso virar "stable", "Nodes affected"
ir de 1.00/1.00 pra 2.00/**5.00**, neutralização de I1 em -0.121/8 passos —
todos números já verificados nesta sessão, não inventados pro texto);
"How much do you trust that? Sensitivity to self-regulation" (100% de
concordância nos 5 fatores, mesmo já verificado); "Reach: the one thing that
never needed any of this" (4 fatores/1 de 1 Impacto, sem mudança nenhuma
antes/depois da auto-regulação — prova visual de que é independente).
Comparação raiz-vs-fim-de-cadeia (pedida explicitamente pelo roadmap)
**não** exigiu modificar o exemplo de pescas (que só tem uma Resposta,
insuficiente pra comparar duas posições): uma tabela ilustrativa separada
com números já testados em `test-reach.R` (resposta perto da raiz alcança 3
fatores; resposta de fim-de-cadeia alcança 1) cobre o conceito sem pedir
pro leitor construir nada. Seção "Reach" e "Show sensitivity to
self-regulation" também adicionadas à lista de controles da aba Scenarios em
"3 · Explore tabs" (que ainda não os mencionava); campo `self_regulation`
adicionado às duas tabelas de campos de Nós (formato CSV de importação e a
descrição do formulário do passo 3); "Sign confidence"/"Edge sensitivity" no
Quick glossary ganharam vizinhos "Self-regulation"/"Reach".

Verificado carregando o arquivo renderizado de verdade no navegador
(`file://`, não só lendo o HTML) e extraindo o texto visível da página
inteira: nenhuma seção quebrada, nenhum HTML malformado, fluxo de leitura
coerente do início ao fim — incluindo a checagem específica de que o
callout corrigido não contradiz mais a seção de auto-regulação logo abaixo.

**Revisão 1 iniciada, na branch `fase-10-suficiencia`** (documento externo
trazido pelo usuário, avaliado tecnicamente antes de aceitar — a prova
`λ·ρ(W) = c < 1 ⟹ (I - λW)` nunca singular foi conferida à mão antes de
implementar, não só copiada do documento) — planejada com `EnterPlanMode`
em 6 fases aditivas (motor → UI nova ao lado da antiga → relatório/
persistência → corte do motor antigo → exemplo Mangi/tutorial/README →
fechamento), pra nunca deixar o app quebrado no meio do caminho. Plano
salvo em `.claude/plans/wondrous-cuddling-eclipse.md`.

**Achado decisivo antes mesmo de implementar**: o usuário já tinha rodado a
rede de Mangi et al. 2007 pelo motor antigo (pasta `manuscrito/`, não
versionada) e exportado um relatório real
(`manuscrito/idpsir_report_2026-07-28_GF.html`) — nele, o Cenário 2 (Gear
restrictions a 100%) mostra equilíbrio **+0,81** ("worsening") em "Reef
ecosystem degradation", quando restringir petrechos deveria intuitivamente
*reduzir* a pressão sobre o recife. Uma inversão de sinal real, reproduzível,
não hipotética — a mesma rede virou o fixture de validação principal do
motor novo (`manuscrito/mangi2007_*.csv`, promovida pra `data/` sem a coluna
`self_regulation`).

**Fase 1 concluída: motor matemático (`R/sufficiency.R`), 100% aditivo —
zero mudança visível no app.** `build_signed_matrix`, `spectral_radius`,
`propagate`, `sufficiency`, `sufficiency_confidence`,
`sufficiency_reach_over_c` — descritos no bullet de `R/sufficiency.R` acima.

**Verificação, não suposição**: script standalone
(`scratchpad/test_sufficiency.R`) rodado contra a rede de Mangi real:
(1) o caso do bug — `sufficiency()` pra Gear restrictions (R2) sozinho dá
mitigação **-0,069** em Reef ecosystem degradation (I2) — sinal correto,
nega diretamente o +0,81 do motor antigo; (2) o exemplo completo da própria
revisão (Seção 4, Tabela 1 — pressão D1+D3, resposta R1/AMP) bateu quase
exatamente com os números computados aqui: Catch decline
0,1096/-0,1660/-0,0564/Sim/0,660 (revisão: 0,110/-0,166/-0,056/Sim/0,66),
Reef degradation 0,0301/-0,0929/-0,0629/Sim/0,324 (revisão:
0,030/-0,093/-0,063/Sim/0,32), Food insecurity 0,0496/-0,1023/-0,0527/Sim/
0,485 (revisão: 0,050/-0,102/-0,053/Sim/0,49) — uma implementação
independente, escrita só a partir da formalização da Seção 2, reproduzindo
os números que a própria revisão apresenta como exemplo — confiança alta de
que a implementação bate com a intenção do autor; (3) `propagate()` nunca
retorna `NA`, testado inclusive contra `data/sample_nodes.csv`/
`sample_edges.csv`, já documentado desde a Fase 5 Marco A como produzindo
matriz singular pro motor antigo; (4) réplica da Tabela 2 (confiança por
Resposta × Impacto): R1→100/100/100, R2/R3/R5→0/100/0, R4→0/~20/0 — bate
com o padrão da revisão (R4 "frágil" no recife, R1 única resposta ampla),
a pequena diferença no percentual exato de R4 (20% vs 23% da revisão) é
esperada — reamostragem estocástica com N=300, sem a revisão especificar a
semente usada pro seu próprio número.

`tests/testthat/test-sufficiency.R` novo — 12 testes/29 assertivas,
incluindo o teste de regressão do bug real (R2→Reef com mitigação negativa),
batida numérica contra a Tabela 1 da revisão (tolerância 1e-3 nos valores,
1e-2 na força-pra-neutralizar), reprodutibilidade com semente fixa (mesmo
padrão do item 6.4), e caso de borda (grafo sem nó Impacto). Suíte completa
(`Rscript tests/testthat.R`) roda limpa. Checagem de sintaxe de todos os
`R/` limpa. App não testado no navegador nesta fase de propósito — nada
mudou na UI ainda, é exatamente o que a Fase 1 promete.

## Próximo

Fase 5 está completa (Marcos A-D). Todos os 4 itens da lista pós-Fase 5 (1:
exemplo didático, 2a: passos até neutralizar, 2b: threshold opcional por
aresta, 3: qualidade das figuras, 4: legendas/parametrização) estão feitos.
`main` sincronizada com o GitHub, README atualizado, tutorial acessível de
dentro do app, layout circular + posições manuais persistentes + legendas
opcionais no Graph.

**Trabalhando agora no roadmap de publicação** (`ROADMAP_MELHORIAS_iDPSIR.md`),
ordem combinada com o usuário:
- [x] **7.3** — referência/DOI por aresta (concluído, ver acima).
- [x] **6.3** — testes `testthat` do núcleo numérico (concluído, ver acima).
- [x] **7.1** — determinância de sinal (concluído, ver acima).
- [x] **7.2** — sensibilidade/ranking de arestas (concluído, ver acima; ficou
  sem `ggplot2` no fim, `barplot()` do R base bastou).
- [x] **6.4** — `sessionInfo` + parametrização/semente no relatório
  (concluído, ver acima).
- [x] **8.1** — demo online via shinylive (concluído, ver acima — mesclada
  em `main`, Pages habilitado pelo usuário, deploy confirmado ao vivo em
  `https://gfonseca-unifesp.github.io/iDPSIR/`). Decidido junto com o
  usuário adiar 6.2 (renv) e fazer 8.1 primeiro, já que era a maior
  incerteza técnica do roadmap — validada com o spike antes de implementar.
- [ ] **6.1** — LICENSE (MIT, já confirmado)/CITATION.cff/DESCRIPTION — por
  último, aguardando lista de coautores do usuário.
- [ ] **6.2** — `renv` (pin de versões) — único item restante do roadmap
  além do 6.1. A tensão renv-vs-`runGitHub()` (renv supõe biblioteca
  persistente por projeto; `runGitHub()` baixa pra um diretório temporário
  a cada execução) segue sem resolver — precisa de uma decisão de desenho
  antes de implementar (ver opções levantadas com o usuário: renv só pra
  dev local, ou `global.R` detectando e usando `renv::restore()` quando um
  `renv.lock` existir).

**Fase 9 concluída e mesclada em `main`** (`ROADMAP_FASE9_iDPSIR.md`, branch
`fase-9-auto-regulacao`, fast-forward sem conflitos, `git push` confirmado),
ordem combinada com o usuário:
- [x] **9.2** — alcance de uma resposta (concluído, ver acima).
- [x] **9.1** — auto-regulação por fator (concluído, ver acima — os quatro
  sub-passos 9.1.1-9.1.4 num único commit; verificação decisiva: exemplo de
  pescas com auto-regulação alta em todos os nós vira a primeira rede
  **estável** de todo o projeto, com efeito de equilíbrio totalmente
  definido).
- [x] **9.3**/**9.4** — tutorial e README (concluído, ver acima).

Fora do roadmap: fast-follow "gráficos editáveis/baixáveis" (download
PNG/SVG + figuras no relatório pros gráficos de trajetória/sensibilidade,
ver acima) também concluído nesta branch, mesclado junto.

Checagem de sintaxe + suíte `testthat` completa (91 assertivas) re-rodadas
em `main` depois do merge, ambas limpas, antes do push.

**Revisão 1, Fase 3 concluída: relatório + persistência do cenário no
savepoint.** `format_sufficiency_table()`/`format_reach_over_c_table()`
(`R/sufficiency.R`), seção "Response sufficiency" no relatório
(`R/report.R`), `scenario_state` no savepoint (`R/io.R`,
`mod_responses.R`, `mod_data.R`, `mod_wizard.R`) — descritos nos bullets
acima.

**Bug real de `[[` em vetor atômico, encontrado só ao testar o
carregamento de um savepoint com cenário parcialmente ativo** (nenhum dos
29 testes de suficiência nem os 19 de io.R exercitava esse caminho, porque
nenhum deles restaurava um savepoint dentro do app de verdade e depois
navegava até a aba Scenarios): a app quebrava com "índice fora de limites"
assim que a aba Scenarios era aberta após carregar um savepoint salvo com
D1/D3/R1 ativos — descrito em detalhe no bullet de `mod_responses.R`
acima. Corrigido trocando `strengths[[node_id]]` por um check explícito
`node_id %in% names(strengths)` antes de indexar.

Testado ponta a ponta rodando o app de verdade contra a rede de Mangi: (1)
cenário D1+D3 (pressão) + R1 (resposta) a 100%, `c=0.5`, aplicado e salvo;
relatório gerado com esse cenário selecionado contém a seção "Response
sufficiency" com as 3 tabelas batendo número por número com a tela
("Table 2"/"Table 3"/"Table 4" nesse teste, incluindo o texto "Pressure:
D1 at 100%, D3 at 100%" / "Response: R1 at 100%" / "How far the effect was
traced (c): 0.5"), e a seção antiga "Scenarios compared (older,
equilibrium-based reading)" logo em seguida, sem nenhuma regressão. (2)
Savepoint baixado nesse estado inspecionado diretamente via `fetch()`:
`scenario_state` presente com `pressure: [{id:"D1",strength:100},
{id:"D3",strength:100}]`, `response: [{id:"R1",strength:100}]`,
`effect_horizon: 0.5` — confirmando que o formato de linhas evita o
"unboxing" que um vetor nomeado de tamanho 1 sofreria. (3) Esse savepoint
recarregado do zero (nova sessão, sem nenhum estado prévio): depois do
bug acima corrigido, a aba Scenarios abre sem erro, D1/D3/R1 aparecem
corretamente marcados a 100% e os demais nós desmarcados a 50% (o
default), `effect_horizon` volta a 0.5, e "Apply scenario" reproduz
exatamente os mesmos números já verificados — prova de que o round-trip
completo (tela → savepoint → JSON → disco → recarregar → tela) preserva o
cenário configurado. Sem erros no console do navegador nem do servidor em
nenhum passo, depois do fix. Suíte `testthat` ganhou um teste de
round-trip de `scenario_state` em `test-io.R` e dois testes das novas
funções de formatação em `test-sufficiency.R` (98 assertivas no total);
checagem de sintaxe limpa.

**Revisão 1, segunda onda — motor temporal de janelas discretas.** Depois
da Fase 3, uma conversa longa com o usuário (trazendo
`manuscrito/gnanapragasam_2026.pdf`, Gnanapragasam et al. 2026, Marine
Policy) abriu um escopo maior do que o plano original de 6 fases previa —
plano reescrito em `.claude/plans/wondrous-cuddling-eclipse.md` (a seção
"Histórico" no fim do arquivo preserva o plano original das Fases 1-3, já
executado). Decisões-chave dessa conversa: (1) State não deve carregar
sinal no nome/rótulo — é variável neutra medida, sinal vem das arestas
("Coral degradation" no exemplo do Mangi é na verdade um Impacto
disfarçado de Estado, motivando trocar a rede de exemplo); (2)
autorregulação vira fração contínua $[0,1)$ em vez de categórico
none/low/medium/high, e **não** é removida do schema (reverte decisão
anterior) — é reaproveitada pelo motor temporal novo; (3) dois atributos
novos em Nós — `growth_rate` (tendência exógena própria do nó) e
`reference_value` (escala de referência, torna `threshold` relativo em
vez de absoluto); (4) `threshold` (aresta) passa a ser fração 0-1 do
`reference_value` da origem, restrito a arestas com origem State; (5)
`temporal_scale` aposentado (nunca entrou em cálculo nenhum, fica
redundante com `growth_rate`/autorregulação agora numéricos);
`uncertainty`/`controllability` ficam categóricos por ora. Rede de
exemplo troca de Mangi et al. 2007 pra Gnanapragasam et al. 2026 — mostra
um auxílio (Resposta a um Impacto de perda de renda) que, janelas depois,
vira ele mesmo uma força de pressão nova (mais barcos entregues como
auxílio → mais esforço de pesca), o efeito indireto que motivou todo o
motor temporal.

- [x] **Fase 1** — motor matemático (`R/sufficiency.R`), aditivo, zero
  mudança visível (concluído, ver acima).
- [x] **Fase 2** — UI nova ("Pressure scenario" + controle de alcance + as
  3 tabelas da Seção 4) ao lado da UI antiga, sem remover nada ainda
  (concluído, ver acima — dois bugs reais de DT/design corrigidos ao
  testar ao vivo contra a rede de Mangi).
- [x] **Fase 3** — relatório (3 tabelas novas) + persistência dos dois
  cenários + `c` no savepoint (concluído, ver acima — um bug real de `[[`
  em vetor atômico corrigido ao testar o carregamento de um savepoint com
  cenário salvo).
- [x] **Fase 4** — motor temporal (`R/temporal.R`, ver acima) — concluído,
  aditivo, zero mudança de tela ainda. Achado real testado antes de aceitar
  o design da Fase 5: reaproveitar as magnitudes antigas de autorregulação
  (-0,5/-1/-2) na equação de diferença discreta nova **oscila em vez de
  decair** (confirmado rodando um impulso com autorregulação "high": vira
  -1,1,-1,1,... eternamente) — motivo real, não só preferência de UX, pra
  Fase 5 converter autorregulação pra fração contínua $[0,1)$. 21
  assertivas novas em `tests/testthat/test-temporal.R`, suíte completa
  (147 assertivas) e checagem de sintaxe limpas.
- [x] **Fase 5 concluída** — schema/dados: `growth_rate`/`reference_value`
  opcionais em Nós (`R/schema.R`, `R/validate.R`'s `normalize_dpsir_nodes()`,
  `R/modules/mod_data.R`'s formulário + `create_empty_nodes_table()`);
  `threshold` (aresta) vira fração 0-1 restrita a arestas com origem State
  (validado em `confirm_edge`, `mod_data.R`); autorregulação vira
  `numericInput` 0-1 (era `selectInput` none/low/medium/high),
  `self_regulation_magnitudes()` removida de `R/loop_analysis.R`;
  `temporal_scale` **removido** (não só ignorado) de
  `normalize_dpsir_nodes()`, do schema (`get_temporal_scales()` removida) e
  do formulário/CSV.

  **Dois bugs reais de corrupção de coluna, encontrados só ao testar ao
  vivo** (nenhum dos dois em checagem de sintaxe nem na suíte `testthat` —
  nenhum teste exercitava "editar um nó/aresta já carregado de um
  savepoint antigo cujas colunas opcionais foram preenchidas em ordem
  diferente da que o formulário usa hoje"):
  - **Nós**: carregar `docs/example_fisheries.idpsir.json` (savepoint
    anterior à Fase 5 — sem `self_regulation`, com `temporal_scale`) e
    editar um nó existente corrompia toda coluna a partir de `subsystem`:
    o valor novo de `self_regulation` ia parar na posição de
    `temporal_scale`, `growth_rate` na de `self_regulation`, e
    `reference_value` acabava mostrando o próprio `id` do nó (reciclagem
    do R). Causa: `rv$nodes[idx, ] <- new_row` (`mod_data.R`) faz
    atribuição **posicional** quando o número de colunas de `rv$nodes`
    (10, ainda com `temporal_scale`) difere do `new_row` reconstruído pelo
    formulário (9, sem `temporal_scale`). Corrigido na raiz:
    `normalize_dpsir_nodes()` agora **remove** a coluna
    (`nodes$temporal_scale <- NULL`), não só a ignora — garante que
    `rv$nodes` sempre tem exatamente o mesmo conjunto de colunas que o
    formulário produz, não importa a origem dos dados.
  - **Arestas**: mesmo padrão de bug, causa diferente. Editar a aresta
    S1→I1 desse mesmo savepoint antigo (que tem `reference` mas não
    `threshold`) e definir um Threshold fazia o valor aparecer na coluna
    **reference** da tabela, com `threshold` ficando em branco — não um
    problema de contagem de colunas (ambas existem), mas de **ordem**:
    `create_empty_edges_table()`/`confirm_edge`'s `new_row` constroem
    `threshold` antes de `reference`, mas como o savepoint antigo não tinha
    `threshold`, `normalize_dpsir_edges()` (`R/validate.R`) o adiciona **por
    último** (`edges$threshold <- ...`, depois que `reference` já existia)
    — resultando em `rv$edges` com a ordem `[...,reference,threshold]`,
    oposta à de `new_row`. `rv$edges[idx, ] <- new_row` (mesma linha de
    código, mesmo padrão de bug do lado de nós) atribuiu posicionalmente,
    trocando os dois valores. Corrigido na origem do problema (a
    atribuição em si, não a ordem das colunas — mais robusto a qualquer
    ordem futura): `rv$nodes[idx, names(new_row)] <- new_row` e
    `rv$edges[idx, names(new_row)] <- new_row` — atribuição por **nome**,
    correta não importa a ordem das colunas em `rv$nodes`/`rv$edges`,
    contanto que os nomes existam (garantido por `normalize_dpsir_nodes()`/
    `normalize_dpsir_edges()`).

  Verificado ao vivo rodando o app de verdade contra
  `docs/example_fisheries.idpsir.json` (savepoint pré-Fase-5, sem
  `self_regulation`, com `temporal_scale`): (1) tabela de Nós mostra
  corretamente as colunas `self_regulation`/`growth_rate`/`reference_value`
  (defaults 0/0/1) e nenhuma `temporal_scale`; (2) editar S1 (Self-regulation
  0.4, Growth rate 0.02, Reference value 50) grava exatamente nesses campos,
  com D1/P1/I1/R1 inalterados (0/0/1) — confirma o fix da corrupção de nós;
  (3) tabela de Arestas mostra `threshold` como última coluna; (4) tentar
  definir um Threshold na aresta D1→P1 (origem Driver) é rejeitado com
  "Threshold can only be set when \"From\" is a State factor.", sem alterar
  a linha; (5) definir Threshold=0.3 na aresta S1→I1 (origem State) salva
  corretamente **na coluna threshold**, com `reference` permanecendo em
  branco — confirma o fix da corrupção de arestas; (6) passo Review mostra
  "Everything is valid", grafo constrói com sucesso; (7) aba Graph não
  mostra mais o dropdown "Temporal scale" (só "Subsystem" como filtro).
  Sem erro no console do servidor em nenhum passo, depois dos dois fixes.
  Suíte `testthat` ganhou 5 testes novos em `test-validate.R` (defaults,
  passthrough numérico, mapeamento legado categórico→numérico,
  `reference_value=0`→1, remoção de `temporal_scale`) e 2 testes em
  `test-loop_analysis.R` foram ajustados pra usar valores numéricos crus
  em vez das strings categóricas antigas (170 assertivas no total); suíte
  completa e checagem de sintaxe limpas.
- [x] **Fase 6 concluída** — UI da leitura temporal na aba Scenarios
  (`R/modules/mod_responses.R`), quinto disclosure opcional na mesma lista
  de "Show how the effect evolves over time"/"Show robustness to
  uncertainty"/etc.: nº de janelas (slider 2-15, default 5), seletor
  impulso/permanente independente pra pressão (default "Ongoing/permanent")
  e resposta (default "One-time/impulse") — mesmos defaults de
  `simulate_temporal_pair()`. Reaproveita `sc$p_D`/`sc$press` já
  computados em "Apply scenario" (mesmos vetores usados pela leitura
  estática), então o cenário testado é sempre o mesmo configurado nos
  painéis Pressure/Response acima, nunca um terceiro cenário paralelo.
  `temporal_result` é uma `reactive` só computada quando o disclosure está
  aberto (`req(isTRUE(input$show_temporal))`), compartilhada pela tabela e
  pela prancha — a simulação roda uma vez só, nunca duas.

  **Indicador de progresso**: `simulate_temporal_pair()` (`R/temporal.R`)
  ganhou um parâmetro opcional `on_step(t, windows)`, chamado a cada janela
  do loop — default `NULL` (no-op), preservando a função pura/testável sem
  Shiny. `mod_responses.R` embrulha a chamada em `withProgress()` e passa
  `on_step = function(t, total) incProgress(1/total, detail = sprintf(...))`
  — "Window X of N" aparece enquanto simula, sem acoplar `R/temporal.R` a
  `shiny`. Novo teste em `test-temporal.R` confirma o callback é chamado
  exatamente `windows` vezes com `(t, windows)` corretos, e que ele é
  puramente um efeito colateral (não muda o resultado da simulação).

  **Prancha de grafos por janela**: `draw_temporal_storyboard()`
  (`R/scenario_plots.R`, mesmo arquivo/filosofia dos gráficos de
  trajetória/sensibilidade — base R, sem pacote novo) desenha um painel
  por janela via `igraph::plot.igraph()`, todos com o **mesmo layout**
  (`compute_graph_layout()`, `R/graph.R` — o mesmo helper que a aba Graph
  usa, computado uma vez só via uma `reactive` própria,
  `temporal_layout()`) — só cor/tamanho do nó variam entre painéis (escala
  divergente vermelho/azul por sinal de $x_i(t)$, tamanho por
  magnitude), deliberadamente **não** rotulada como "bom/ruim" (isso
  depende do que cada fator significa) — só "aumentou"/"diminuiu a partir
  de zero". Ganhou os mesmos botões "Download PNG"/"Download SVG" que os
  outros dois gráficos da aba (`plot_download_row()`), preparando o
  terreno pra Fase 7 incluir a prancha no relatório.

  **Bug real, encontrado só ao testar ao vivo** (nenhum teste standalone
  exercitava desenhar o grafo de verdade com `igraph::plot.igraph()` —
  todos os testes de `R/temporal.R` até aqui só verificavam os números,
  nunca a prancha): a prancha quebrava com **"Bad vertex shape(s):
  triangle, dot, diamond, star"**. Causa: `prepare_nodes_for_graph()`
  (`R/graph.R`) já preenche um atributo de vértice `shape` no grafo
  principal (`apply_schema_visual_mapping()`, vocabulário do widget
  `vis.Network` — `square`/`triangle`/`dot`/`diamond`/`star`) pra colorir o
  grafo interativo da aba Graph; `igraph::plot.igraph()` lê automaticamente
  qualquer atributo de vértice chamado `shape` como o parâmetro
  `vertex.shape`, e nenhum desses nomes é uma forma válida de
  `plot.igraph` (que só aceita `circle`/`square`/`csquare`/etc. do próprio
  igraph). Corrigido passando `vertex.shape = "circle"` explicitamente em
  `draw_temporal_storyboard()` — um argumento explícito sempre tem
  prioridade sobre o atributo de mesmo nome no grafo.

  **Segundo bug real, encontrado revisando o código antes de testar** (não
  ao vivo — pego relendo `mod_responses.R` antes de começar a Fase 6):
  `has_self_regulation()` ainda comparava `sr != "none"` — sobrevivência da
  Fase 5, que converteu `self_regulation` de categórico (`"none"`/...) pra
  numérico (`0` por padrão). Comparar um vetor numérico contra a string
  `"none"` sempre coage pra caractere e sempre dá `TRUE` (`"0" != "none"`),
  então essa reactive ficou **permanentemente `TRUE`** pra qualquer rede,
  mesmo uma sem nenhuma auto-regulação configurada — mostrando a nota e o
  disclosure "Show sensitivity to self-regulation" sempre, incondicionalmente.
  Corrigido pra `any(as.numeric(sr) > 0)`. Verificado ao vivo: a rede de
  pescas (todos os nós com `self_regulation=0`, nunca tocados no
  formulário desde a Fase 5) já não mostra mais a nota nem o disclosure —
  o comportamento correto, ausente desde que a Fase 5 introduziu a
  conversão numérica e só agora corrigido.

  Testado ponta a ponta rodando o app de verdade contra
  `docs/example_fisheries.idpsir.json`: Overfishing (pressão) + Fishing
  quota policy (resposta) ativados, "Apply scenario" clicado — nota/
  disclosure de auto-regulação corretamente ausentes (fix acima
  confirmado); "Show temporal simulation" aberto, tabela "How each Impact
  changes, window by window" mostra os valores esperados por janela
  (incluindo o "Impact_i(t) = max(0, x_i(t))" já documentado em
  `format_temporal_table()` cortando os mergulhos negativos da rede —
  documentadamente instável — de volta a zero, não um bug novo); prancha
  renderiza sem erro (confirmado decodificando o PNG retornado num
  `<canvas>` via JS e contando pixels não-brancos — 1.48% do total,
  provando conteúdo real, não uma imagem em branco, já que o
  `computer{action:"screenshot"}` deste ambiente devolveu uma captura em
  branco por um motivo de timing alheio ao app, não confiável aqui);
  subir "Number of windows" pra 12 recomputa a tabela (13 janelas) e a
  prancha (13 painéis) sem erro; mudar o modo da pressão pra "impulse" via
  `Shiny.setInputValue` muda os números da tabela corretamente (prova que
  o seletor está de fato conectado à simulação). Download PNG (`fetch()`
  direto na URL do `downloadHandler`: `content-type: image/png`, 200,
  12.8 KB) e SVG (118 KB, começa com `<svg`) ambos confirmados. Sem erro
  no console do navegador nem do servidor em nenhum passo, depois dos dois
  fixes. Suíte `testthat` ganhou 1 teste novo em `test-temporal.R` (26
  assertivas no total) e a suíte completa + checagem de sintaxe seguem
  limpas.
- [x] **Fase 7 concluída** — relatório. Duas mudanças em
  `R/report.R`/`R/modules/mod_report.R`:
  - **Seleção de gráficos de cenário** (ponto operacional (b) da Revisão
    1): nova caixa "Scenario charts" na aba Report, com 3 checkboxes —
    "How the effect evolves over time" (trajetória, default ligado — mesmo
    comportamento de sempre, que nunca teve como ser desligado até agora),
    "Which edges matter most" (sensibilidade, default ligado, mesmo
    motivo) e "Temporal simulation (discrete windows)" (novo, default
    **desligado** — mesma convenção "opt-in" de todo disclosure novo desta
    revisão). `build_full_report_html()` ganhou
    `include_trajectory_chart`/`include_sensitivity_chart`/
    `include_temporal_section` (todos com o mesmo default da UI), cada um
    envolvendo o bloco de seção correspondente num `if (isTRUE(...))` —
    nenhuma mudança de comportamento pra quem não mexer nos checkboxes
    novos (os dois primeiros continuam ligados por padrão).
  - **Seção "Temporal simulation (discrete windows)"**: uma subseção por
    cenário selecionado, com a tabela "How each Impact changes, window by
    window" (mesma `format_temporal_table()` da tela) e a prancha de
    grafos (`draw_temporal_storyboard()`, `R/scenario_plots.R`, via
    `plot_to_data_uri()` — mesmo padrão já usado pelos gráficos de
    trajetória/sensibilidade). Reaproveita `sc$p_D`/`sc$press` já
    guardados no cenário salvo — não guarda o histórico completo
    (janelas × nós) no objeto do cenário, só os 3 novos campos que faltam
    pra reproduzi-lo: `sc$temporal_windows`/`sc$temporal_mode_pressure`/
    `sc$temporal_mode_response`, capturados em "Save this scenario"
    (`mod_responses.R`) com o mesmo padrão já usado por
    `sc$trajectory_steps` — configurado na tela vira o que é salvo, sem
    precisar guardar o resultado inteiro. O layout da prancha
    (`compute_graph_layout(graph_to_nodes(graph), schema)`) é calculado
    uma vez só, fora do loop por cenário — todo painel de toda prancha de
    todo cenário selecionado compartilha as mesmas posições de nó.

  Testado ponta a ponta rodando o app de verdade contra
  `docs/example_fisheries.idpsir.json`: Overfishing (pressão) + Fishing
  quota policy (resposta) aplicados e salvos como "Scenario 1"; na aba
  Report, "Scenario 1" selecionado e "Temporal simulation" ligado — HTML
  baixado (via `fetch()` direto na URL do `downloadHandler`, mesmo truque
  de sempre) contém a seção "Temporal simulation (discrete windows)", a
  tabela com as colunas Impact/Window/Baseline/Scenario/Verdict, e uma
  imagem `<img>` real (~11,7 KB de base64, decodificada com sucesso) —
  junto com "How the effect evolves over time"/"Which edges matter most"
  (ambos ligados por padrão) e todas as seções pré-existentes
  ("Response sufficiency"/"Scenarios compared"), sem regressão. Desligar
  os checkboxes de trajetória e sensibilidade e gerar de novo: as duas
  seções desaparecem do HTML (confirmado via busca de texto), a seção
  temporal continua presente, contagem de "Figure" caiu de 3 pra 1 e de
  "Table" de 10 pra 9 — prova de que os 3 toggles de fato controlam o
  conteúdo, não só existem na tela. Sem erro no console do navegador nem
  do servidor em nenhum passo. Sem teste `testthat` novo (este arquivo
  não tem suíte dedicada — verificado só via app real, mesmo padrão já
  usado pras fases anteriores do relatório); suíte completa (171
  assertivas) e checagem de sintaxe seguem limpas.
- [x] **Fase 8 concluída** — corte do motor antigo. Removido da tela
  (`R/modules/mod_responses.R`) e do relatório (`R/report.R`,
  `R/modules/mod_report.R`) tudo que dependia de `press_perturbation()`/
  `check_stability()`: o aviso de estabilidade, "Effect on the network",
  "Effect on each factor" (Improves/Worsens/Stable + Sign confidence),
  "When will Impacts be neutralized?", os disclosures "Show how the effect
  evolves over time" (gráfico de trajetória), "Show robustness to
  uncertainty", "Show which edges matter most" e "Show sensitivity to
  self-regulation", a nota de auto-regulação, e a seção de relatório
  "Scenarios compared (older, equilibrium-based reading)" inteira
  (Equilibrium effect/Sign confidence/Summary per scenario). **Mantido**:
  `self_regulation_diagonal()`/`build_interaction_matrix()`/
  `build_threshold_matrix()` (`R/loop_analysis.R`) — reaproveitadas pelo
  motor temporal (Fase 4-7) — e **Reach** (`response_reach()`, `R/reach.R`),
  travessia pura de grafo, nunca dependeu de `press_perturbation()`.
  Relocado pra sua própria seção (`reach_section` na tela, `h2("Reach")`
  no relatório) em vez de ficar dentro do bloco antigo removido. As
  funções em si (`press_perturbation()`, `check_stability()`,
  `simulate_trajectory_thresholded()`, `robustness_check()`,
  `sign_determinacy()`, `self_regulation_sensitivity()`,
  `global_sensitivity()`, `summarize_scenario_effect()`,
  `summarize_scenario_network_effect()`, `compare_scenario_effects()`,
  `compare_scenario_sign_confidence()`, `find_neutralization_step()`,
  `summarize_neutralization()`) continuam definidas em
  `R/loop_analysis.R` e cobertas por `tests/testthat/test-loop_analysis.R`
  — só páram de ser chamadas pela UI/relatório, mesmo padrão já usado
  pra `apply_response()` (`R/responses.R`).

  Duas adaptações não pedidas explicitamente pelo roadmap, mas necessárias
  pra não deixar funcionalidade existente quebrada: a coluna "Summary" da
  tabela "Saved scenarios" (antes `"%d improve, %d worsen, %d stable"`,
  calculada a partir do `sc$result` removido) virou
  `scenario_sufficiency_summary()` — `"%d of %d Impacts neutralized"` a
  partir de `sc$sufficiency_df$neutralized` (a leitura nova, já calculada
  em "Apply scenario"). "Compare selected scenarios" perdeu as 3 tabelas
  antigas (Equilibrium effect/Sign confidence/Summary per scenario) e
  ficou só com "Reach per scenario" — deliberadamente **não** foi
  inventada uma tabela de comparação de suficiência entre cenários pra
  substituir as removidas (cada cenário salvo pode ter sido aplicado com
  um `p_D` de pressão diferente, então não existe uma linha "Baseline"
  única e correta pra essa comparação, ao contrário de Reach, que nunca
  depende de pressão) — escopo deliberadamente contido ao que o roadmap
  pediu (cortar o motor antigo), não uma feature nova.

  Cabeçalho de `mod_responses.R` reescrito do zero pra refletir o estado
  atual (duas leituras — suficiência e temporal — mais Reach independente),
  em vez de descrever features que não existem mais na tela.

  Testado ponta a ponta rodando o app de verdade contra
  `docs/example_fisheries.idpsir.json`: aba Scenarios não mostra mais
  nenhum vestígio do motor antigo antes ou depois de "Apply scenario"
  (sem aviso de estabilidade, sem "Effect on each factor", sem
  disclosures de trajetória/robustez/sensibilidade/auto-regulação);
  "Reach" aparece como seção própria logo abaixo da suficiência,
  mostrando "4 factors reached, including 1 of 1 Impact" como antes;
  disclosure temporal continua funcionando (tabela + prancha, sem
  regressão nos números já verificados na Fase 6); "Save this scenario"
  grava "Scenario 1 | R1 | 0 of 1 Impacts neutralized" na tabela de
  cenários salvos (bate com "Neutralizes? No" da tabela de suficiência);
  "Compare selected scenarios" (Baseline + Scenario 1) mostra só "Reach
  per scenario" (Baseline 0, Scenario 1 4 factors/1 of 1 Impact), sem as
  3 tabelas antigas. Relatório gerado com o cenário selecionado e
  "Include temporal simulation" ligado contém "Response sufficiency",
  "Reach" e "Temporal simulation (discrete windows)", e **não** contém
  "Scenarios compared"/"Equilibrium effect per factor"/"Sign confidence
  per factor"/"Which edges matter most"/"How the effect evolves over
  time" (confirmado varrendo o HTML por essas strings) — 1 Figure (só a
  prancha temporal) e 6 Tables, contra as 3 Figures/10 Tables de antes do
  corte. Sem erro no console do navegador nem do servidor em nenhum
  passo. Suíte `testthat` completa (171 assertivas, nenhuma mudança —
  `R/loop_analysis.R` em si não foi tocado) e checagem de sintaxe seguem
  limpas.
- [x] **Fase 9 concluída** — exemplo Gnanapragasam et al. 2026 (Marine
  Policy), substituindo o de pescas (5 nós) como exemplo principal do
  tutorial. `data/gnanapragasam2026_nodes.csv`/`_edges.csv` (13 nós: D1
  crescimento populacional, D2 crescimento da demanda por pescado, D3
  número de pescadores/embarcações, P1 esforço de pesca, S1 estoque de
  peixe/CPUE, S2 motorização da frota, I1-I5 Impactos — queda de captura,
  perda de renda, conflito com pescadores indianos, declínio da pesca
  tradicional, perda de cultura tradicional —, R1 auxílio pós-tsunami, R2
  auxílio pós-guerra) + `docs/example_gnanapragasam.idpsir.json` (gerado
  via `build_savepoint()`/`write_savepoint()` de verdade, não editado à
  mão, mesmo padrão do exemplo anterior).

  **Dois conflitos reais entre o plano e as regras do schema, encontrados
  só ao tentar validar a rede** (nenhum dos dois óbvio de antemão — o
  plano original desenhou a rede em conversa, antes desta fase realmente
  tentar construí-la): `schema_allowed_connections()` só permite cada
  categoria avançar para o **próximo** nível (nunca pular, nunca
  permanecer no mesmo) — duas arestas do desenho original violavam isso.
  (1) `D3→I3` (Driver→Impact, pulando Pressure e State) — corrigida para
  `S1→I3` (State→Impact, um passo válido): narrativamente melhor também,
  já que é a **escassez do estoque** que empurra pescadores pra águas
  disputadas, não o número de embarcações diretamente. (2) `I4→I5`
  (Impact→Impact, mesmo nível) — corrigida removendo o encadeamento e
  ligando `S2→I5` diretamente (motorização da frota causa tanto o
  declínio da pesca tradicional quanto a perda de cultura, cada um
  direto, sem depender um do outro). Nenhuma mudança na história
  pretendida (resposta virando nova pressão via `R→D3→P1→S1→Impactos`,
  mais o ramo `R→S2→Impactos` sem loop) — só a forma de conectar dois
  nós específicos.

  **Bug real e mais sério: `sufficiency()`/`propagate()` (`R/sufficiency.R`,
  motor principal desde a Fase 1) retornava zero pra QUALQUER rede
  acíclica, não só pra uma rede sem aresta nenhuma.** Descoberto ao rodar
  a leitura de suficiência estática nesta rede pela primeira vez: tanto
  `worsening` quanto `mitigation` saíam **zero para todos os 5 Impactos**,
  mesmo com pressão e resposta ativas — porque, seguindo o próprio plano
  ("`I2→R1`/`I2→R2` não entram como aresta simulada"), esta rede não tem
  **nenhum** ciclo (nenhuma aresta de Impacto de volta pra Resposta), e
  `propagate()` tratava `rho(W) == 0` (o caso de uma matriz nilpotente —
  sempre verdadeiro pra qualquer DAG, já que os autovalores de uma matriz
  sem ciclo são sempre exatamente zero) do mesmo jeito que tratava `W`
  genuinamente vazio (sem aresta nenhuma) — um curto-circuito que
  descartava um efeito real e bem definido pra toda rede acíclica.
  Confirmado matematicamente antes de corrigir: `(I - lambda*W)` é
  invertível pra **qualquer** lambda quando `W` é nilpotente (autovalores
  todos exatamente 1 nesse caso, não dependem de lambda), então a série de
  Neumann `lambda*W*p + lambda²*W²*p + ...` só termina mais cedo (no
  comprimento do maior caminho do DAG) — nunca precisa da garantia
  `lambda*rho(W) = c < 1` que motivou a fórmula original. Verificado à mão
  contra uma cadeia A→B→C de 3 nós construída à parte
  (`scratchpad/verify_propagate_fix.R`) antes de corrigir: com `c=0.5`, o
  efeito esperado é A=0/B=0,5/C=0,25 — o código antigo devolvia zero nos
  três. Corrigido separando os dois casos explicitamente: `all(W==0)`
  (matriz genuinamente vazia) continua retornando zero; `rho(W)==0` com
  `W` não-vazio agora usa `lambda <- c` diretamente em vez de `c/rho`
  (indefinido). Novo teste de regressão em `test-sufficiency.R` (a mesma
  cadeia A→B→C, valores exatos) — suíte completa (192 assertivas) segue
  limpa, nenhuma rede cíclica já testada (Mangi, pescas) muda de
  comportamento, já que a correção só altera o ramo antes inatingível
  para elas.

  Com a correção, a rede de Gnanapragasam mostra exatamente o efeito
  pretendido: `mitigation` sai **positivo** (não negativo) pros 5
  Impactos quando só a resposta (R1+R2) é ativada — a resposta não só
  falha em ajudar, ela ativamente piora tudo, já que seu único caminho
  causal no modelo passa pela mesma pressão que causou o dano. Verificado
  com um cenário combinado (pressão D1+D2 a 100%, resposta R1+R2 a 100%,
  `c=0,5`): net positivo e "Neutralizes? No" nos 5 Impactos; confiança de
  neutralização 0% pra R1 e R2 avaliadas sozinhas (300 simulações);
  "Does it hold up" mostra "No" em todo `c` de 0,2 a 0,8, nenhum
  Borderline; Reach = 9 fatores incluindo 5 de 5 Impactos (idêntico pra
  R1/R2 sozinhas ou combinadas, já que ambas atingem exatamente os mesmos
  dois nós). Simulação temporal (pressão permanente D1+D2, resposta
  impulso R1+R2, 10 janelas): todos os 5 Impactos mostram a coluna
  cenário sempre maior que a baseline, com a diferença crescendo a cada
  janela (D3 quase não se auto-regula, então o impulso vira ratchet em
  vez de esmaecer); Declínio da pesca tradicional e Perda de cultura
  tradicional mostram baseline **exatamente zero em toda janela** — esses
  dois Impactos só existem por causa da resposta, nada na pressão os
  alcança.

  **Segundo bug real, encontrado só ao testar a própria tabela temporal
  ao vivo com esta rede de 5 Impactos** (nenhum teste anterior — inclusive
  o da Fase 6/7 — usava mais de 1 Impacto, então nunca exercitava esta
  combinação): a tabela "How each Impact changes, window by window"
  (`mod_responses.R`) usava `dom = "t"` (sem controles de paginação) com
  `pageLength = 15` — como o número de linhas é `janelas × Impactos`
  (genuinamente sem limite, ao contrário de toda outra tabela do app, que
  sempre cabe numa tela), com 5 Impactos isso preenche uma página inteira
  em só 3 janelas (0, 1, 2) — qualquer janela além da 2ª ficava **
  permanentemente inacessível na tela**, sem nenhum controle pra passar de
  página. Confirmado que o cálculo em si estava correto (checando as
  dimensões do PNG da prancha, que usa a mesma contagem de janelas e não
  depende do DataTables) antes de procurar o bug na tabela. Corrigido
  trocando `dom = "t"` para `dom = "tp"` (adiciona Previous/Next, mesmo
  padrão já usado nas tabelas de Nodes/Edges do wizard). Verificado ao
  vivo: com 10 janelas, a tabela agora mostra 4 páginas (Previous1234Next)
  e navegar até elas expõe as janelas 5 e 10 corretamente — os números
  batem exatamente com o script standalone (ex.: Catch decline
  janela 10: baseline 1744,91 / cenário 4594,08).

  **`docs/tutorial.html` e `README.md` reescritos** — não só trocar o
  savepoint linkado, mas toda a narrativa que descrevia o motor antigo
  (equilíbrio/estabilidade/sign confidence/robustez/sensibilidade a
  auto-regulação/trajetória), removido na Fase 8. Tutorial: tabelas de
  campos de Nós/Arestas atualizadas (sem `temporal_scale`, `self_regulation`
  numérico, `growth_rate`/`reference_value` novos, `threshold` relativo e
  restrito a State); seção da aba Scenarios reescrita do zero pra
  descrever a UI atual (dois painéis de cenário, suficiência, Reach,
  disclosure temporal); seção "Worked example" inteira reescrita com a
  história de Gnanapragasam e os números acima, todos verificados ao vivo
  rodando o app de verdade (não só o script standalone) antes de
  escrever; glossário atualizado (remove Sign confidence/Edge sensitivity,
  adiciona Sufficiency/Neutralized/Temporal simulation, Self-regulation
  redescrito). README: parágrafo de abertura, árvore de arquivos
  (`sufficiency.R`/`temporal.R` descritos, `loop_analysis.R` marcado como
  "definido mas não mais chamado"), seção Data format (`self_regulation`
  numérico, `growth_rate`/`reference_value`, `threshold` relativo),
  Workflow (Scenarios reescrito pra suficiência + temporal + Reach).
  `docs/example_fisheries.idpsir.json` **não foi removido** — continua
  sendo fixture real de `tests/testthat/test-loop_analysis.R`/
  `test-reach.R`/`test-metrics.R` (`read_savepoint()` direto), só parou
  de ser o exemplo linkado no tutorial.

  Testado ponta a ponta rodando o app de verdade contra o savepoint
  gerado: carregado via injeção de arquivo, "Everything is valid" nos 13
  nós/13 arestas (confirma o fix dos dois conflitos de schema), grafo
  construído, cenário aplicado reproduzindo **exatamente** os números
  documentados acima (incluindo após reiniciar o servidor pra pegar o fix
  do `propagate()`) — nenhuma discrepância entre o script standalone e a
  tela. Página do tutorial renderizada de verdade (`/tutorial/tutorial.html`,
  não só o arquivo cru): link de download do savepoint responde 200 com
  `content-type: application/json`; seção "Worked example" com 6 `<h3>`,
  4 tabelas, 3 callouts, sem HTML malformado; glossário com os termos
  corretos. Sem erro no console do navegador nem do servidor em nenhum
  passo, depois dos dois fixes. Suíte `testthat` completa (192 assertivas)
  e checagem de sintaxe seguem limpas.
- [x] **Fase 10 concluída — Revisão 1 completa (Fases 1-10).** Verificação
  final: suíte `testthat` completa (192 assertivas) e checagem de sintaxe
  de todos os arquivos `R/`, ambas limpas, rodadas de novo do zero nesta
  fase (não reaproveitando o resultado das fases anteriores). Passagem
  completa no navegador com o app rodando de verdade: (1) retrocompatibilidade
  — `docs/example_fisheries.idpsir.json` (savepoint anterior à Fase 5, sem
  `self_regulation`, ainda com `temporal_scale` gravado) carregado do
  zero, avançado até Nodes (colunas corretas: sem `temporal_scale`,
  `self_regulation`/`growth_rate`/`reference_value` default 0/0/1) e
  construído sem erro — confirma que a normalização tolerante
  (`normalize_dpsir_nodes()`) continua funcionando pra savepoint bem
  antigo; (2) rede de Gnanapragasam (Fase 9) do zero: carregada,
  construída, cenário (pressão D1+D2 + resposta R1+R2 a 100%) aplicado
  reproduzindo os mesmos números já documentados na Fase 9, disclosure
  temporal aberto com 10 janelas (paginação `Previous1234Next` confirmada
  funcionando — fix da Fase 9), cenário salvo mostrando "0 of 5 Impacts
  neutralized" (a nova coluna Summary baseada em suficiência); (3)
  relatório completo gerado com **todas** as seções ligadas (general
  metrics, centralities, descriptors, references, reproducibility,
  response sufficiency, reach, temporal simulation) — confirmado por
  busca de texto que as 8 seções esperadas estão presentes e que nenhum
  vestígio do motor antigo (`Scenarios compared`/`Equilibrium effect per
  factor`) aparece, 13 tabelas + 1 figura (a prancha temporal), versão do
  R mencionada na seção de reprodutibilidade. Sem erro no console do
  navegador nem do servidor em nenhum passo de toda a passagem.

  Com isso, a Revisão 1 (suficiência de resposta + motor temporal de
  janelas discretas + corte do motor de equilíbrio antigo + exemplo
  Gnanapragasam) está **completa e mesclável** — 10 fases, cada uma
  testada ao vivo e commitada separadamente nesta branch
  (`fase-10-suficiencia`), pronta pra revisão do usuário antes de
  push/merge em `main`.

**Redesenho do exemplo Gnanapragasam (R1/R2→I2 direto + `growth_rate` em
D3), substituindo o desenho da Fase 9 (R1/R2→D3).** Revisando o artigo
mais de perto com o usuário: o auxílio pós-tsunami/pós-guerra (R1/R2) foi
desenhado pelo próprio artigo pra compensar diretamente **Fisher income
loss** (I2) — não pra aumentar a frota. A aresta R1/R2→D3 usada até aqui
simplificava demais um efeito que o artigo trata como indireto. Testado
antes de aceitar o redesenho (scripts standalone em `scratchpad/`, nunca
assumido): removendo R1/R2→D3 e adicionando R1/R2→I2 (negative), o Driver
"Number of fishers and boats" (D3) fica parado em 0 pra sempre no motor
temporal — `growth_rate` é multiplicativo sobre o desvio **já existente**
(`x(t+1) = x(t) + growth_rate*x(t) + ...`), não cria desvio a partir de
repouso zero. Corrigido dando a D3 uma pequena semente própria via o
cenário de pressão (D3 a 30%, em paralelo a D1/D2) — representando "esse
crescimento está de fato acontecendo, por razões que o artigo não
define", exatamente o que `growth_rate` foi desenhado pra expressar.

Com D3 semeado, a leitura temporal reproduz a "erosão sem reversão"
pedida pelo usuário: R1+R2 neutralizam Fisher income loss no início
(janelas 0-3), mas a mitigação relativa erode de ~34% de corte (janela 5,
34.3 vs. baseline 52.3) pra <1% (janela 15, 8150.0 vs. 8212.9) conforme o
crescimento independente de D3 domina — nunca reverte pra "pior que sem
resposta" (testado em varredura de `growth_rate`∈{0.03,0.05,0.08,0.12} ×
semente∈{0.3,0.5,0.8} até 60 janelas, sempre assintótico, nunca cruza).
Achado que corrigiu uma primeira leitura errada do usuário (confirmado
por ele: "sim vc tem razao me expressei mal"): só **Fisher income loss**
é de fato afetado pela resposta nesta rede — Catch decline/Conflict with
Indian fishermen ficam **idênticos** entre baseline e cenário em toda
janela (fora do alcance da resposta, `response_reach()` confirma: 4
fatores alcançados, 3 de 5 Impactos — S2/I2/I4/I5, nunca I1/I3);
Traditional fishing decline/Loss of traditional culture são genuinamente
piorados pelo canal lateral da resposta (R1/R2→S2, fleet motorization),
com baseline exatamente zero em toda janela.

`data/gnanapragasam2026_edges.csv` (R1/R2→D3 removidas, R1/R2→I2
adicionadas), `data/gnanapragasam2026_nodes.csv` (D3 `growth_rate` 0→0.03)
editados; `docs/example_gnanapragasam.idpsir.json` regenerado via script
(`build_savepoint()`/`write_savepoint()` de verdade, não editado à mão) —
ganhou também `scenario_state` pré-configurado (pressão D1+D2 a 100%,
resposta R1+R2 a 100%, `effect_horizon=0.5`; D3 fica de fora do savepoint
de propósito — é um passo extra guiado só na seção temporal do tutorial,
não faz parte do cenário "de largada"), o que a versão anterior do
savepoint nunca tinha. `docs/tutorial.html` (seção "Worked example"
inteira reescrita: nova tabela de arestas, nova tabela de suficiência,
tabela de confiança por resposta [Post-tsunami 25.7% vs. Post-war 72% em
Fisher income loss — as duas respostas discordam], tabela reach-over-c
com "Borderline" em c=0.8, seção Reach reescrita pra mostrar as duas
rotas da mesma resposta [direta em I2, indireta via S2→I4/I5] em vez de
uma tabela hipotética, tabela temporal com as 4 assinaturas de
comportamento) e `README.md` (parágrafo do exemplo) atualizados com os
números verificados nesta sessão.

Verificado ponta a ponta rodando o app de verdade: savepoint carregado,
"Everything is valid" nos 13 nós/13 arestas, cenário pré-configurado
aplicado reproduzindo exatamente a Tabela 1 do tutorial (Catch decline
1.5/0/1.5/No; Fisher income loss 1.125/-2.25/-1.125/Yes x0.50; Conflict
0.75/0/0.75/No; Traditional decline 0/1.25/1.25/No; Loss of culture
0/0.938/0.938/No), confiança 26%/72%, reach "4 factors reached, including
3 of 5 Impacts"; relatório HTML gerado com a seção temporal incluída (1
figura, 6 tabelas) contendo os mesmos números. Suíte `testthat` e
checagem de sintaxe seguem limpas.

**Correções de UI apontadas pelo usuário ao revisar o app** (`R/graph.R`,
`R/modules/mod_graph.R`, `R/scenario_plots.R`, `R/modules/mod_responses.R`):

- **Arrastar nó só se movia no eixo Y, nunca em X.** `fixed.x` estava
  fixo em `TRUE` (tanto em `build_network_visual` quanto em
  `build_community_visual`) desde sempre — travava X pra manter a coluna
  por categoria no layout em camadas, mas pelo mesmo motivo já documentado
  pro fix de Y (vis-network tira uma "foto" de `fixed.x`/`fixed.y` no
  início de cada gesto de arrastar), travava X em **todo** drag, não só
  physics. Corrigido pro mesmo padrão já usado em Y: `fixed.x` sempre
  `FALSE`, `physics=FALSE` é quem de fato imobiliza um nó arrastado/
  circular entre um drag e outro. Trade-off aceito conscientemente: nós
  não-arrastados em modo layered agora têm X tecnicamente livre pro
  solver de física, não travado por `fixed.x=TRUE` — na prática o
  `x_spacing` de 200px entre categorias e a repulsão do forceAtlas2Based
  mantêm as colunas coerentes (confirmado ao vivo, sem distorção
  visível). Verificado lendo o node do widget: `fixed:{x:false,y:false}`
  num nó nunca arrastado, e a posição arrastada (`x=500,y=-300`)
  persistindo corretamente após o drag.
- **Nó arrastado em modo layered não voltava pro anel ao trocar pra
  circular.** `apply_manual_positions()` sobrepunha a posição arrastada
  em cima do layout computado **sem checar `layout_mode`** — em modo
  circular, isso arrancava o nó do anel. Corrigido pulando
  `apply_manual_positions()` inteiramente quando `layout_mode ==
  "circular"` (nos dois construtores de visual, grafo e comunidades) — a
  posição continua guardada em `positions`/savepoint, só não é reaplicada
  nesse modo. Verificado ao vivo: nó arrastado pra `(500,-300)` em modo
  layered, alternado pra circular — os 13 nós (incluindo o arrastado)
  ficam todos a ~413px do centro (raio uniforme, confirmado via
  `network.getPositions()`); voltando pra layered, a posição arrastada
  reaparece exatamente onde foi deixada.
- **"Highlight pathway" parecia travado em "None".** Investigado a fundo
  (inclusive um susto real: `Rscript -e` com string multi-linha via este
  Bash tool nesta máquina Windows segfaultava em qualquer chamada de
  `all_simple_paths()` — reproduzido isoladamente, mas confirmado ser um
  artefato do `-e` inline, não um bug do igraph: o mesmo código rodando de
  um arquivo `.R` funciona perfeitamente). Com isso descartado, o reativo
  (`path_candidates`/`observeEvent`) provou estar **correto**: testado ao
  vivo trocando "Pathway to category" pra "Impact", o servidor computou e
  enviou 9 candidatos corretamente — o valor só não aparecia no `<select>`
  bruto porque o widget é `selectize.js`, que mantém sua própria lista
  interna (`el.selectize.options`) sem espelhar de volta pro DOM
  (inspecionar `el.options` sozinho, como fiz primeiro, é enganoso).
  Abrindo o dropdown de verdade, os 9 caminhos apareciam e o destaque no
  grafo funcionava. A causa real do "parece travado" pro usuário: o par
  de categoria padrão (Driver→Response) genuinamente não tem nenhum
  caminho nesta rede (nenhuma aresta entra num nó de Resposta) —
  `nrow(candidates)==0` correto, mas sem nenhuma explicação na tela.
  Corrigido não a lógica (que já funcionava), mas a UX: `output$path_status`
  novo mostra "No pathway found from any X to any Y in this network." só
  quando a lista de candidatos está vazia — verificado ao vivo aparecendo/
  desaparecendo corretamente ao trocar a categoria.
- **Legenda/tamanho de rótulo e escala de cor na prancha temporal
  ("storyboard").** `draw_temporal_storyboard()` (`R/scenario_plots.R`)
  ganhou `label_cex` (antes fixo em 0.65) — novo slider "Label size"
  (0.3-1.5) em `mod_responses.R`, encadeado no `renderPlot()` e nos dois
  `downloadHandler()`s (PNG/SVG), mesmo padrão de compartilhamento de
  função já usado pelos outros gráficos da aba. Uma coluna extra
  (`graphics::layout()` no lugar de `par(mfrow=...)`, já que agora precisa
  de uma célula com formato diferente das demais) mostra uma barra de
  gradiente vermelho-branco-azul com eixo rotulado (`-max_abs`/`0`/
  `max_abs`) e "increased"/"decreased" nas pontas — a legenda de cor que
  antes só existia como texto de ajuda acima do gráfico. Verificado
  renderizando standalone (PNG de teste, barra e rótulos legíveis, sem
  sobreposição) e ao vivo na app: imagem real (128 KB) presente no DOM,
  aumentar o slider pra 1.4 visivelmente aumenta os rótulos dos nós no
  screenshot, download PNG responde 200/`image/png`. Relatório
  (`R/report.R`) usa o `label_cex` padrão (0.65) — não fica configurável
  por cenário salvo, mesmo escopo mínimo já usado pelos demais parâmetros
  só-de-tela desta aba.

Suíte `testthat` completa e checagem de sintaxe re-rodadas depois de
todas essas mudanças, ambas limpas. Passagem completa no navegador
cobrindo o redesenho da rede + os 3 fixes + as 2 features do storyboard,
sem erro no console do navegador nem do servidor em nenhum passo.

**Segunda rodada no exemplo Gnanapragasam: canal lateral da resposta
removido, e a rede ganha suporte gráfico direto no tutorial.** Pedido do
usuário testando variações da rede ao vivo (ver sessão): desligar
`R1→S2`/`R2→S2` (o aid deixa de ter QUALQUER ligação com a frota
motorizada) e ligar três arestas novas — `Fishing effort→Fleet
motorization` (positive, 1.5/0.6), `Fleet motorization→Catch decline`
(positive, 1.5/0.5) e `Fleet motorization→Conflict with Indian
fishermen` (positive, 1/0.5) — pra ver o efeito. Testado primeiro num
script standalone antes de aceitar como oficial (mesmo padrão de toda
mudança de rede nesta revisão): a suficiência estática de **Fisher
income loss** não muda em nada (`-1.125` líquido, `Yes x0.50`) — seu
único caminho causal continua intocado — mas **Catch decline** e
**Conflict with Indian fishermen** pioram bem mais (1.5→2.344,
0.75→1.313: `Fleet motorization` virou uma segunda rota pra esses dois
Impactos, empilhada em cima da rota via `Fish stock` que já existia), e
**Traditional fishing decline**/**Loss of traditional culture** passam a
ter *worsening* não-zero (1.125/0.844) em vez de zero — deixaram de ser
efeito colateral exclusivo da resposta e passaram a ser movidos pela
mesma cadeia de pressão que tudo mais.

A mudança mais forte é no **Reach**: caiu de "4 factors reached,
including 3 of 5 Impacts" pra **"1 factor reached, including 1 of 5
Impacts"** — sem nenhuma ligação lateral, a resposta só consegue
influenciar Fisher income loss, nunca mais nada, independente de força
ou do quanto "how far to trace the effect" for esticado. Confiança de
sinal muda ligeiramente (Post-tsunami 25.7%→20.7%, Post-war 72%→68.3%)
mesmo o caminho pra I2 sendo idêntico — esperado, não bug: `ρ(W)`
(usado no `λ=c/ρ(W)` de `propagate()`) é uma propriedade **global** da
matriz, então adicionar arestas em outro ramo desloca ligeiramente a
escala usada em toda reamostragem, inclusive na de I2 (mesmo raciocínio
já documentado pro item 6.4 sobre semente fixa × ordem das arestas —
aqui é ordem das arestas × valor da confiança, não da semente).

`data/gnanapragasam2026_edges.csv` editado (3 arestas trocadas por 3
novas, mesma contagem de 14), `docs/example_gnanapragasam.idpsir.json`
regenerado (mesmo `scenario_state` de antes — D1+D2 pressão/R1+R2
resposta a 100%, `effect_horizon=0.5`; D3 continua de fora do savepoint
de propósito, é um passo guiado só na seção temporal).

**Suporte gráfico no tutorial**, pedido explícito do usuário ("acredito
que seja interessante acrescentar um suporte gráfico da rede e da
evolução da rede"): duas imagens estáticas novas, geradas por script
(não a partir do pipeline `html2canvas` do navegador, que exige o app
rodando) — `docs/example_gnanapragasam_network.png` (diagrama da rede
via `igraph::plot.igraph()`, nós coloridos por categoria DPSIR via
`schema_colors()`, arestas coloridas por `interaction_type` via
`get_interaction_type_colors()` já existente em `R/graph.R`, legenda de
categoria + legenda de efeito) e
`docs/example_gnanapragasam_storyboard.png` (a prancha temporal de
verdade — `draw_temporal_storyboard()`, `R/scenario_plots.R`, reaproveitada
tal qual, mesmo cenário do tutorial: D1+D2+D3@30% permanente, R1+R2
impulso, 15 janelas — "isso é exatamente o que o app mostra", não uma
segunda implementação). `vertex.shape="circle"` em ambas as imagens pelo
mesmo motivo já documentado em `draw_temporal_storyboard()`: os nomes de
forma do schema (square/triangle/dot/diamond/star, vocabulário do
vis.js) não são formas válidas de `igraph::plot.igraph()`. Nova classe
CSS `.figure`/`figcaption` em `docs/tutorial.html` (não existia nenhum
estilo de imagem no tutorial até agora), seguindo o mesmo padrão visual
de `.table-wrap`/`.code-card` já usado no resto da página.

Seção "Worked example" reescrita por completo com os números da rede
nova: tabela de arestas, tabela de suficiência, tabela de confiança
(20.7%/68.3%), seção Reach (1 de 5, não mais 4/3-de-5), tabela temporal
completa (todas as 5 linhas agora batendo — 4 delas idênticas
baseline=cenário em toda janela, só Fisher income loss diverge). Uma
afirmação nova no texto ("Catch decline já se move na janela 4, mais
rápido do que se a rota do estoque de peixe carregasse o efeito
sozinha") foi **verificada antes de publicar**, não assumida: script
comparando a rede com e sem a aresta `Fleet motorization→Catch decline`
confirma que sem ela Catch decline fica em zero até a janela 4 (só
começa na 5), com ela começa na própria janela 4 — a alegação bate.
`README.md` (parágrafo do exemplo) atualizado no mesmo sentido.

Verificado ponta a ponta rodando o app de verdade com o savepoint
regenerado: "Everything is valid" nos 13 nós/14 arestas, cenário
pré-configurado reproduzindo exatamente a Tabela 1 do tutorial
(2.344/1.125/1.313/1.125/0.844 de worsening, só Fisher income loss com
mitigação), confiança 21%/68% (arredondado na tela, bate com
20.7%/68.3%), Reach mostrando "1 factor reached, including 1 of 5
Impacts" com só Fisher income loss na tabela. Simulação temporal com D3
a 30% e 15 janelas reproduzindo janela por janela os números do
tutorial (janela 15: 22.009,949/12.858,203/14.765,826/11.074,369 idênticos
baseline=cenário; Fisher income loss 8.212,935→8.149,935); storyboard
renderizando na tela batendo visualmente com a imagem estática do
tutorial. Relatório gerado com a seção temporal incluída, sem erro.
Suíte `testthat` e checagem de sintaxe seguem limpas (nenhum teste
depende dos pesos exatos deste exemplo). Sem erro no console do
navegador nem do servidor em nenhum passo.

**Terceira rodada de polimento, 8 pontos levantados pelo usuário revisando o
app.** Todos aditivos/de UI, sem tocar no núcleo numérico exceto o item 2
abaixo (que é uma relocação de atributo, não uma mudança de fórmula).

1. **Callout "illustrative" movido pro início do Worked example**
   (`docs/tutorial.html`) — antes ficava no fim da seção inteira, só depois
   de todas as tabelas/figuras; agora aparece logo após o card de download,
   antes de "The story", pra quem só lê o topo já saber que os números são
   uma interpretação do autor, não do artigo.

2. **Threshold movido de aresta pra nó (`activation_threshold`).** Decisão
   confirmada com o usuário antes de implementar: um único threshold por
   State, disparando **todas** as suas arestas de saída juntas — não mais
   um gatilho independente por aresta individual. Faz mais sentido
   conceitualmente (é uma propriedade da variável de estado, não de um link
   causal específico) e casa com o padrão real de uso (nesta sessão, cada
   State só tinha threshold numa de suas arestas de qualquer forma).
   `R/validate.R`: `normalize_dpsir_nodes()` ganha `activation_threshold`
   (default `NA`, mesmo padrão opcional de `growth_rate`/`reference_value`);
   `normalize_dpsir_edges()` **remove** `threshold` (não só ignora — mesmo
   motivo já documentado pra `temporal_scale`: evita corrupção de coluna
   por atribuição posicional se `rv$edges` e o formulário tiverem contagens
   de coluna diferentes). `R/loop_analysis.R`'s `build_threshold_matrix()`
   reescrita pra ler `V(g)$activation_threshold` em vez de `E(g)$threshold`
   — itera as arestas do grafo mas busca o valor no nó de origem, então
   toda aresta saindo do mesmo State pega o mesmo gatilho. `R/graph.R`:
   `create_empty_graph_edges()` perde a coluna; `build_edge_tooltip()`
   perde "Threshold", `build_node_tooltip()` ganha "Activation threshold".
   `mod_data.R`: formulário de aresta perde o campo inteiro; formulário de
   nó ganha `numericInput` "Activation threshold (optional, 0-1, State
   factors only)" com a mesma validação que a aresta tinha antes (0-1, só
   permitido se a categoria for State), agora checada contra a categoria do
   próprio nó em vez da categoria do "From" de uma aresta.

   **Achado real, descoberto só ao migrar o exemplo Gnanapragasam**: como
   S1 (Fish stock) tem 3 arestas de saída (→I1, →I2, →I3) mas só a aresta
   →I1 tinha threshold antes, mover pro nó significa que **todas as três**
   passam a esperar o mesmo gatilho agora — um comportamento genuinamente
   diferente, não só uma relocação de onde o dado mora. Testado antes de
   aceitar como correto: script comparando `propagate()` (usa
   `build_signed_matrix()`, nunca lê threshold) confirma a leitura estática
   de suficiência **não muda nada** (threshold só afeta a simulação
   temporal, como já documentado); a tabela temporal mudou só pra Fisher
   income loss (I2: janela5 41.06/23.06, antes 52.3/34.3) e Conflict with
   Indian fishermen (I3: janela5 55.39, antes 62.9) — Catch decline (I1)
   ficou **idêntico** (já era a única aresta com threshold antes). Um
   segundo achado, ao depurar por que I1 "furava" o gatilho antes da hora
   enquanto I2 não: I1 e I3 têm uma **segunda** rota de entrada sem
   threshold nenhum (via S2/Fleet motorization, adicionada na sessão
   anterior), então já se moviam a partir da janela 4 só por essa rota,
   mesmo com a rota-S1 ainda desligada (confirmado rodando com/sem a
   aresta S2→I1: sem ela, I1 fica em zero até a janela 4 igual I2) — Fisher
   income loss não tem essa segunda rota, então é a única que realmente
   fica visivelmente "presa" esperando o threshold de S1 abrir na janela 5.
   Isso virou o novo texto de "A threshold worth knowing about" no
   tutorial, mais rico que a versão anterior (que só falava de uma aresta).
   `data/gnanapragasam2026_nodes.csv` (S1 ganha `activation_threshold=0.15`)/
   `_edges.csv` (coluna `threshold` removida), savepoint e as duas imagens
   estáticas regeneradas. Números de suficiência estática, confiança e
   reach **inalterados** (confirmado byte a byte contra os já verificados).
   Testes: os 2 testes de threshold em `test-validate.R` viraram testes de
   `activation_threshold` em nós (mais um par novo pra edges sem a coluna);
   `test-temporal.R`'s teste de gating passou a setar
   `V(g)[V(g)$name=="S1"]$activation_threshold <- 2` em vez de `E(g)$threshold`
   — mesmo resultado exato (a fixture de teste só tinha 1 aresta saindo de
   S1 mesmo, então não expõe a diferença de "gatilha todas juntas").

3. **Slider "?" sem função removido do cabeçalho.** Investigado ao vivo, não
   assumido: o cabeçalho tinha 3 elementos além do link "Help" — confirmado
   inspecionando o DOM que são `#help_switch` (toggle "modo de ajuda" que o
   bs4Dash injeta sozinho), `#theme_switch` (toggle claro/escuro) e um botão
   de control-sidebar já `display:none`. Clicar em `#help_switch` produz
   **zero mudança no DOM** (confirmado comparando `innerHTML.length` antes/
   depois) — nunca teve efeito porque este app nunca usa o parâmetro
   `help=` de `bs4Dash::box()`. `#theme_switch` **é** funcional (confirmado
   clicando: adiciona a classe `dark-mode` no `<body>`) — mantido.
   `bs4Dash::dashboardPage(help=FALSE)`/`dashboardHeader()` não têm um
   parâmetro que desliga só esse switch especificamente (os dois elementos
   são sempre renderizados, `help=`/`dark=` só parecem controlar o estado
   inicial do toggle, não se ele existe) — corrigido escondendo via um
   `tags$script` inline (`$('#help_switch').closest('.custom-control').hide()`)
   colocado em `dashboardBody()`, **não** em `rightUi` — `dashboardHeader()`
   valida (`tagAssert`) que todo tag de nível superior em `rightUi` é um
   `<li class="dropdown">` (o mesmo bug já documentado quando o link "Help"
   foi adicionado), e um `<script>` solto ali quebraria o app inteiro no
   startup.

4. **Coluna "Descriptor" opcional em Nós.** Texto livre, sem validação de
   formato (mesmo padrão de `reference` nas arestas) — pro usuário
   documentar em uma frase o que um fator representa, útil pra quem lê a
   rede depois sem ter participado da modelagem. `R/validate.R`
   (`normalize_dpsir_nodes()`, default `""`), `mod_data.R`
   (`create_empty_nodes_table()`, `textAreaInput` no formulário, `new_row`),
   `R/graph.R`'s `build_node_tooltip()` mostra em itálico logo abaixo do
   label **só quando preenchido** (`ifelse` vetorizado, mesmo truque já
   usado pros outros campos opcionais do tooltip) — não polui o tooltip de
   nós sem descrição.

5. **Cores de aresta trocadas: positivo=verde, negativo=vermelho** (antes
   era o oposto). Mudança de uma linha em `get_interaction_type_colors()`
   (`R/graph.R`) — como toda cor de aresta (grafo, legenda, e as duas
   figuras estáticas do tutorial) já vinha dessa única função, a troca se
   propaga sozinha sem precisar tocar em mais nada. As duas imagens do
   tutorial (`docs/example_gnanapragasam_network.png`/
   `_storyboard.png`) regeneradas pelo mesmo script de sempre — a primeira
   pela cor, a segunda pelos números corrigidos do item 2.

6. **Tabela "All Driver-to-Impact pathways" em Descriptors.** Nova
   subseção na aba Metrics → DPSIR descriptors (e espelhada no relatório,
   dentro do bloco `include_descriptors` já existente) listando **todo**
   caminho causal simples de Driver a Impact na rede, não só o par
   escolhido no dropdown "Highlight pathway" da aba Graph. Reaproveita
   `find_dpsir_paths()`/`compute_critical_pathways()` (`R/pathways.R`) já
   existentes via uma função nova, `compute_all_driver_impact_pathways(g,
   schema, max_paths=500)` — `max_paths` é um limite **documentado**, não
   "sem limite algum": uma rede densa poderia ter uma quantidade
   combinatorialmente grande de caminhos simples, e um teto explícito com
   aviso na tela (`$truncated`) é melhor que travar o app tentando listar
   todos. Testado na rede de Gnanapragasam: 21 caminhos, nenhum truncamento
   (bem abaixo do teto), ordenados por score, batendo entre tela e
   relatório (`D3 -> P1 -> S1 -> I1`, score 5.20, no topo dos dois).

7. **Indicador de progresso em "Apply scenario".** Único ponto de cômputo
   pesado sem nenhum feedback visual até agora: `build_confidence_matrix()`
   roda 300 simulações **por resposta existente na rede** (não só as
   ativas), perceptível numa rede maior — o disclosure de simulação
   temporal já tinha `withProgress()`/`incProgress()` desde a Fase 6, esse
   era o único buraco. Envolvido o corpo do `observeEvent(input$apply_scenario)`
   inteiro num `withProgress()` com 4 incrementos grosseiros (Reach →
   Sufficiency → Confidence → Done), não granular por simulação — checado
   antes que fosse necessário: `sufficiency()`/`sufficiency_reach_over_c()`/
   `response_reach()` são todos rápidos (poucos `propagate()`/travessia de
   grafo, sem amostragem), só `build_confidence_matrix()` justifica um
   indicador. Verificado que `shiny::withProgress(expr, ..., env=parent.frame())`
   avalia no frame do chamador (lido o código-fonte do pacote, não
   assumido) — as atribuições `reach <-`/`suff_df <-`/etc. dentro do bloco
   continuam visíveis depois dele, sem precisar reestruturar o retorno.

8. **Aba Scenarios reorganizada em caixas colapsáveis.** Era uma coluna
   única e longa (Pressure/Response/Resultados/Temporal/Salvos tudo
   empilhado); reorganizada em `bs4Dash::box(collapsible=TRUE)` por tópico
   — mesmo padrão já usado pela aba Graph — "Pressure scenario"/"Response
   scenario"/"Results" abertos por padrão (fluxo principal), "Temporal
   simulation"/"Saved scenarios" fechados por padrão (avançado/secundário).
   Como todo conteúdo já vinha de `uiOutput()`s renderizados no servidor,
   a reorganização foi só de onde os placeholders ficam na UI estática —
   zero mudança de lógica server-side, exceto um ponto: "Save this
   scenario" vivia dentro do mesmo `renderUI` do disclosure temporal
   (`temporal_and_save_section`) só por conveniência de código, não por
   relação lógica — colocá-lo dentro da caixa "Temporal simulation" (fechada
   por padrão) o esconderia de quem nunca abre esse disclosure. Separado
   num `output$save_scenario_section` próprio, movido pra dentro da caixa
   "Results" (onde faz mais sentido - salva o que "Results" está
   mostrando), mantendo a mesma guarda `req(current_scenario())`.

Verificado ponta a ponta rodando o app de verdade contra o savepoint
regenerado do Gnanapragasam: header sem o switch morto (`#help_switch`
oculto, `#theme_switch` funcional, confirmado programaticamente via
`closest('.custom-control').offsetParent`); tabela de Nós mostrando as
colunas `activation_threshold`/`descriptor` na posição certa; editar S1
(descriptor preenchido) e salvar preserva `activation_threshold=0.15`
intacto (sem a corrupção de coluna já vista em bugs anteriores desta
revisão); tentar setar `activation_threshold` num nó Driver (D1) rejeitado
corretamente, linha inalterada; formulário de aresta sem campo de
threshold algum; cores da aresta confirmadas via
`network.body.data.edges.get()` (`positive: "#2ca02c"`, `negative:
"#d62728"`); Metrics → DPSIR descriptors mostrando "All Driver-to-Impact
pathways" com 21 linhas; Scenarios com as 5 caixas colapsáveis, "Apply
scenario" reproduzindo exatamente os números já verificados (2.344/1.125/
1.313/1.125/0.844 de worsening, confiança 21%/68%, Reach "1 factor... 1 of
5 Impacts"), "Save this scenario" visível dentro de "Results" sem precisar
abrir "Temporal simulation"; relatório com "Descriptors" ligado contendo a
mesma tabela de pathways, mesmos números da tela. Sem erro no console do
navegador nem do servidor em nenhum passo. Suíte `testthat` completa e
checagem de sintaxe seguem limpas.

(Achado colateral, não um bug do app: `fetch()` sem `{cache:'no-store'}`
no console do navegador devolvia uma versão em cache do savepoint mais
antiga que a recém-regenerada, mostrando `activation_threshold` ausente
pra S1 — resolvido só no lado do script de teste, comparando headers
`last-modified`; não afeta o app real, que nunca faz fetch client-side
desse arquivo fora do `fileInput` de upload.)

**README + dados de exemplo alinhados ao schema atual.** Um documento de
instruções externo (`INSTRUCOES_README_iDPSIR.md`, trazido pelo usuário)
apontou que `data/sample_nodes.csv` e `data/mangi2007_nodes.csv` ainda
usavam o cabeçalho de nó **antigo** (com `temporal_scale`, sem
`self_regulation`/`growth_rate`/`reference_value`/`activation_threshold`),
enquanto o README já documentava o schema novo desde a rodada anterior —
o app carrega os dois formatos sem erro (retrocompatibilidade), mas a
inconsistência entre o que o README descreve e o que os CSVs de exemplo
de fato têm era real. Migrados os dois pro cabeçalho atual (mesmo do
`gnanapragasam2026_nodes.csv`): `temporal_scale` removido,
`self_regulation`/`growth_rate` = 0 e `reference_value` = 1 em todos os
nós de `sample_nodes.csv`; em `mangi2007_nodes.csv`, os quatro Estados
que se recuperam naturalmente ganharam `self_regulation` não-zero (S1
Coral degradation e S2 Fish stock decline = 0,3; S3 Loss of large
high-trophic fish e S4 Biodiversity decline = 0,2, os demais em 0) —
valor deliberadamente pequeno o bastante pra não mudar a leitura
estática de suficiência (que zera a diagonal de qualquer forma via
`build_signed_matrix()`), só dar amortecimento real pra quem ligar a
simulação temporal opcional nessa rede. `docs/example_fisheries.idpsir.json`
**não foi tocado** — continua de propósito no formato antigo, é a
fixture que prova retrocompatibilidade em `test-loop_analysis.R`/
`test-reach.R`/`test-metrics.R`.

Três ajustes de texto no README, todos dentro do escopo pontual pedido
(o documento foi explícito: "não reescrever" as seções já atualizadas na
Revisão 1): (1) citação completa de Gnanapragasam et al. 2026 (autores,
título, revista, volume, página) no lugar do "Gnanapragasam et al. 2026
(Marine Policy)" abreviado, na seção Data format; (2) uma frase nova no
bullet de Scenarios deixando explícito que a leitura de suficiência
**ignora `self_regulation` de propósito** — só a simulação temporal
opcional usa esse atributo (e `growth_rate`) — o Data format já dizia
isso pro campo em si, faltava repetir no contexto de Scenarios pra quem
lê só essa seção não achar que auto-regulação muda o veredito principal;
(3) uma nota de que a simulação temporal é uma integração explícita de
**horizonte curto**, não um forecast calibrado — em redes sem
`self_regulation`/`growth_rate` ajustados pra amortecer, os valores
crescem rápido janela a janela (comportamento já documentado e aceito
em várias fases anteriores), então o recurso serve pra ler *direção* de
um efeito indireto retardado, não magnitude absoluta. O texto das
arestas do exemplo Gnanapragasam (`R1/R2→I2`: "compensating lost fishing
income, not fleet size") foi conferido contra a ressalva do documento —
o artigo de fato atribui ao auxílio uma contribuição indireta ao aumento
do esforço de pesca, mas o texto da aresta não afirma nenhum número que
o artigo não dê, só descreve o alvo direto documentado (renda) — mantido
como estava.

Verificado ao vivo rodando o app de verdade (não só lendo os CSVs): os
dois arquivos migrados importados via "Import CSV files" (injeção de
arquivo, `sample_nodes.csv`+`sample_edges.csv` primeiro — "Matrices
imported: 10 nodes, 16 edges", sem aviso — depois `mangi2007_nodes.csv`+
`mangi2007_edges.csv` — "18 nodes, 31 edges", sem aviso), tabela de Nós
mostrando as colunas corretas nos dois casos (`self_regulation`/
`growth_rate`/`reference_value`/`activation_threshold`/`descriptor`,
sem `temporal_scale`), valores de auto-regulação de Mangi conferidos
linha a linha (S1/S2=0,3, S3/S4=0,2, demais=0), "Everything is valid" e
"Graph built successfully" pra rede de Mangi (18 nós/31 arestas). Sem
erro no console do servidor em nenhum passo. Suíte `testthat` completa e
checagem de sintaxe seguem limpas (nenhum teste do núcleo numérico lê
`self_regulation`/`growth_rate`/`temporal_scale` desses dois arquivos
especificamente, só `mangi2007_*.csv` como fixture de suficiência, que
ignora esses campos por design).

**"Example networks" — os três exemplos, lado a lado, no tutorial e no
README.** Pedido do usuário ao perceber que o app já acumulava três
savepoints de exemplo (`example_fisheries`, e agora `mangi2007_*.csv`
migrado e `example_gnanapragasam`) sem nenhum lugar que os apresentasse
juntos, explicasse a diferença entre eles, ou linkasse pras tabelas CSV
por trás de cada um.

- **`docs/example_mangi.idpsir.json` (novo)** — não existia savepoint
  nenhum pra Mangi até agora, só os CSVs migrados na rodada anterior.
  Gerado via `build_savepoint()`/`write_savepoint()` (mesmo script
  padrão, nunca editado à mão), com `scenario_state` pré-configurado
  reproduzindo o cenário exato que capturou o bug real de inversão de
  sinal do motor antigo (documentado à exaustão em fases anteriores):
  pressão D1 (crescimento populacional) + D3 (demanda de mercado) a
  100%, resposta R2 (Gear restrictions) a 100%. **Verificado antes de
  publicar**: `sufficiency()` sobre esse cenário dá Reef ecosystem
  degradation com worsening 0,03 / mitigation **-0,069** / net -0,039 /
  Yes (44%) — o sinal correto, contra o +0,81 (piora) que o motor antigo
  reportava pra essa mesma rede — a mesma verificação já feita quando
  `R/sufficiency.R` foi construído (Fase 1 da Revisão 1), agora com um
  savepoint de verdade em vez de só um script standalone.
- **`docs/tutorial.html`** ganha uma seção nova "Example networks" (novo
  item 4 do sumário, empurrando Worked example/Saving/Glossary pra
  5/6/7), com uma subseção por rede — Fisheries (5 nós, ciclo fechado
  único, sem CSV por trás, só existe como savepoint — o ponto de partida
  mais simples pra se orientar no wizard antes de qualquer complexidade),
  Mangi et al. 2007 (18 nós/31 arestas, rede publicada de verdade, a
  história do bug real contada de forma didática — citação completa da
  revista incluída), e Gnanapragasam et al. 2026 (resumo/teaser de 1
  parágrafo + link pra seção "Worked example" logo abaixo, que continua
  sendo o mergulho fundo já existente — não duplicado aqui). Cada rede
  tem seu próprio `.code-cluster` de download: savepoint sempre, mais as
  duas tabelas CSV (`data/mangi2007_*.csv`/`gnanapragasam2026_*.csv`) pra
  Mangi e Gnanapragasam, que têm CSV por trás — Fisheries não, porque
  nunca teve (só foi gerada como savepoint desde a Fase 5 original).
- **`R/global.R`** ganha `shiny::addResourcePath("data", "data")`,
  espelhando o `addResourcePath("tutorial", "docs")` já existente —
  **achado real ao testar, não assumido**: os links novos pras tabelas
  CSV usam caminho relativo `../data/arquivo.csv` a partir de
  `docs/tutorial.html`, que resolve certinho quando o arquivo é aberto
  cru (GitHub, `file://`) mas quebra dentro do app rodando de verdade —
  lá o tutorial é servido em `/tutorial/tutorial.html`, então
  `../data/...` vira `/data/...`, uma rota que não existia até este
  commit. Sem o resource path novo, os links de CSV dariam 404 pra
  qualquer usuário abrindo o tutorial pelo link "Help" de dentro do app
  (o caminho mais comum, não o raro) — confirmado reproduzindo o 404
  antes do fix e o 200 depois, via `fetch()` direto nas duas URLs.
- **`README.md`** ganha uma seção "## Example networks" própria (antes
  só existia um parágrafo mencionando só o Gnanapragasam), uma entrada
  por rede com o mesmo resumo do tutorial + link pra seção completa
  (`docs/tutorial.html#examples`) pra quem quiser os números; a árvore de
  arquivos (`docs/` na seção Structure) e o parágrafo de abertura
  atualizados pra mencionar as três redes, não só uma.
- **Achado de layout, corrigido só ao testar visualmente** (não ao ler o
  HTML): os dois `.code-cluster`s novos com 2 cards (savepoint + CSVs)
  renderizaram um EM CIMA do outro em vez de lado a lado — a classe CSS
  que ativa o layout em grade de 2 colunas é `.code-cluster.two`
  (`@media (min-width: 760px) { .code-cluster.two { grid-template-columns:
  ... } }`, já definida no `<style>` desde a Fase 5 original, usada até
  agora só implicitamente porque todo `.code-cluster` anterior tinha um
  card só). Esqueci de adicionar a classe `two` nos dois clusters novos
  de 2 cards; corrigido depois de medir `getBoundingClientRect()` dos
  cards ao vivo no navegador (mesma largura e mesmo `top`, confirmando
  lado a lado, em vez de larguras iguais à do cluster inteiro e `top`s
  diferentes, que era o sintoma do bug).

Testado ponta a ponta rodando o app de verdade: savepoint de Mangi
carregado via injeção de arquivo, "Everything is valid"/"Graph built
successfully" pros 18 nós/31 arestas, cenário pré-configurado (D1+D3
pressão, R2 resposta) já vindo marcado ao entrar em Scenarios, "Apply
scenario" reproduzindo exatamente os números documentados acima
(incluindo a tabela de confiança — Gear restrictions 0%/100%/0% e Reach
"14 factors reached, including 3 of 3 Impacts"); os dois `fetch()` de
`/data/mangi2007_nodes.csv` e `/data/gnanapragasam2026_edges.csv`
confirmados 200 depois do fix de `addResourcePath`; layout dos cards
lado a lado confirmado via medição de bounding box depois do fix da
classe `two`. Sem erro no console do servidor em nenhum passo. Suíte
`testthat` completa e checagem de sintaxe seguem limpas (nenhuma mudança
tocou `R/` fora de `global.R`, que não tem teste dedicado).

**Rede de Mangi corrigida: Estados neutros + citação certa.** Documento
externo (`INSTRU~2.MD`, trazido pelo usuário, junto com `mangi2007_nodes.csv`/
`mangi2007_edges.csv` já corrigidos) apontou duas coisas reais: (1) os
quatro Estados da rede estavam nomeados como o problema em si (`Coral
degradation`, `Fish stock decline`, `Loss of large high-trophic fish`,
`Biodiversity decline`) em vez de como a variável neutra que medem — o
mesmo anti-padrão já registrado como lição aprendida na Fase 9
("'Coral degradation' no exemplo do Mangi é na verdade um Impacto
disfarçado de Estado"), nunca de fato corrigido nesta rede até agora;
(2) a citação completa do artigo no tutorial tinha o terceiro autor
errado (`Rawlinson, N.J.F.` em vez de `Rodwell, L.D.`, confirmado contra
o DOI `10.1016/j.ocecoaman.2006.10.003` que já vinha em toda `reference`
de aresta desde a Fase 9 mas nunca tinha sido usado pra checar o nome).

Renomear os quatro Estados pra `Coral cover`, `Fish stock`, `Large
high-trophic fish`, `Biodiversity` inverte o sinal de duas famílias de
aresta: `Pressure→State` (agora `negative` — mais esforço de pesca
*reduz* o estoque, em vez de "aumentar o declínio") e `State→Impact`
(agora também `negative` — mais estoque *reduz* a queda de captura);
`Response→State` vira `positive` (mais AMP *aumenta* estoque/cobertura).
**Verificado antes de aceitar, não assumido**: como as duas inversões
(`Pressure→State` e `State→Impact`) ficam no mesmo caminho causal, elas
se cancelam algebricamente — `sufficiency()` nos três Impactos dá
exatamente os mesmos números de antes (Reef ecosystem degradation com
R2/Gear restrictions: mitigação -0,069/44%, idêntico byte a byte ao já
verificado com os nomes antigos) — só os valores intermediários de
Estado mudam de sinal (conferido: estoque -0,204, biodiversidade -0,141
sob a mesma pressão D1+D3, ambos corretamente negativos — o Estado
"cai" sob pressão, como o nome neutro exige).

Convenção registrada como padrão dos exemplos, não só corrigida na rede
de Mangi: nova nota no tutorial (dentro da própria seção "Example
networks", logo abaixo do parágrafo do Mangi — o lugar onde a convenção
é demonstrada de verdade, não um aviso solto) e no README (parágrafo
novo em Data format, ao lado da tabela de campos de Nó) explicando que
Estado deve ser nomeado como medida neutra (`Fish stock`, não `Fish
stock decline`) porque o juízo de valor pertence à aresta
(`interaction_type`), não ao nome do nó — nomear pelo problema associado
embute um sinal presumido que pode divergir silenciosamente das arestas
de verdade. Glossário do tutorial (entrada "State") ganhou a mesma nota,
resumida, com link de volta pro exemplo do Mangi.

Testado ponta a ponta rodando o app de verdade: CSVs corrigidos
carregados via "Import CSV files", "Everything is valid" nos 18 nós/31
arestas sem nenhum aviso; savepoint `docs/example_mangi.idpsir.json`
regenerado a partir dos novos CSVs (mesmo `scenario_state` de antes,
D1+D3 pressão/R2 resposta) e recarregado — trocando a resposta pra R1
(AMP) na tela, "Apply scenario" reproduz **exatamente** o critério
"pronto quando" do documento: R1 neutraliza os três Impactos (Yes/Yes/Yes,
força 66%/32%/49% — bate com "força ~0,3–0,66" das notas), confiança
100%/100%/100% pra R1 nos três Impactos, R4 é a única resposta frágil no
recife (20%, bate com "~23%" das notas — mesma ordem de grandeza), Reach
mostra os nomes de Estado neutros corretos na tabela (`Fish stock`,
`Coral cover`, etc.). Sem erro no console do servidor em nenhum passo.
Suíte `testthat` completa (mesma contagem de antes — os testes de
`test-sufficiency.R` usam Mangi como fixture mas não dependem do nome
do Estado, só dos IDs `S1`-`S4`) e checagem de sintaxe seguem limpas.

**Preflight de validação na importação de CSV** (item 3 do mesmo documento
externo). Motivo: `import_matrices()` (`R/io.R`) sempre chamou
`normalize_dpsir_nodes()`/`normalize_dpsir_edges()`, que preenchem
default **silenciosamente** pra qualquer coluna ausente/renomeada — uma
planilha fora do formato esperado podia ser aceita sem o usuário
perceber, com resultado errado descoberto só bem depois (na aba
Explorar, ou nunca). `R/validate.R` ganha `preflight_import_nodes()`/
`preflight_import_edges()`/`preflight_import()`, chamadas em
`mod_data.R`'s `observeEvent(input$start_import, ...)` **antes** de
`import_matrices()` — rodam sobre as colunas/valores **brutos** do CSV
(antes de qualquer normalização), separando dois tipos de achado:
- **Bloqueante** (`blocking`, impede a importação): coluna obrigatória
  ausente/renomeada (`id`/`label`/`dpsir_category` nos nós,
  `from`/`to` nas arestas); valor fora do vocabulário
  (`dpsir_category`, `interaction_type`, `uncertainty`/`controllability`);
  fora de faixa (`self_regulation` fora de [0,1), `weight` ≤ 0,
  `confidence` fora de [0,1], `activation_threshold` fora de [0,1] ou
  presente num nó que não é State); tipo errado (peso/confiança/
  self_regulation/activation_threshold não-numérico). Toda mensagem
  aponta arquivo, coluna e **linha** (numerada como uma planilha real
  veria — cabeçalho é a linha 1).
- **Aviso** (`warnings`, não bloqueia): coluna desconhecida/obsoleta no
  arquivo (`temporal_scale`, um typo, etc.) — ignorada; coluna
  opcional conhecida ausente — cada linha assume o default (ex.:
  "self_regulation ausente, assume 0 pra todo nó").

`get_known_dpsir_node_fields()`/`get_known_dpsir_edge_fields()` novas
(lista fechada de colunas reconhecidas, usada só pra decidir "desconhecida
vs. conhecida-mas-ausente" — `get_required_dpsir_node_fields()`/
`get_required_dpsir_edge_fields()` já existentes continuam sendo a
sublista que bloqueia se faltar). `mod_data.R` ganha `rv$start_blocking`/
`rv$start_warnings` (resetados no início de todo handler de Start, não só
Import, pra uma mensagem de uma tentativa anterior não sobreviver ao
trocar de modo) e a UI do passo Start ganha duas caixas condicionais
abaixo da mensagem curta de sempre: `alert-danger` com a lista de
bloqueios (import não acontece) ou `alert-warning` com a lista de avisos
(import aconteceu normalmente, só sinalizando o que foi assumido).

**Bug real, encontrado só ao testar contra um valor `NA` de verdade, não
assumido**: a primeira versão detectava "célula em branco" checando
`nzchar(trimws(as.character(valor)))` — mas `as.character(NA)` produz a
string literal `"NA"` em R, que É `nzchar`-verdadeira, então uma célula
genuinamente vazia (`activation_threshold` ausente pra um nó Driver, o
caso mais comum de todos) era lida como "o usuário digitou o texto NA" e
bloqueada como "not a number", derrubando até o próprio CSV de exemplo
usado no teste. Corrigido com um helper único (`.pf_is_blank(x)`) que
checa `is.na(x)` no valor **original** (antes de virar string) em vez do
texto stringificado, usado consistentemente nos 7 campos verificados —
o mesmo tipo de cuidado com `NA`/`nzchar` já registrado como lição
aprendida na Fase 3 da Revisão 1 (`strengths[[node_id]]` em vetor
atômico), agora numa forma diferente do mesmo erro de categoria.

Testado com 10 casos via script standalone antes de escrever os testes
permanentes (tabela válida incluindo um `NA` real numa coluna numérica
opcional; coluna obrigatória ausente; `dpsir_category`/`uncertainty` fora
do vocabulário; `activation_threshold` num nó não-State;
`self_regulation` fora de faixa e não-numérico, separados; coluna
desconhecida + coluna opcional ausente juntas; arestas com
`interaction_type`/`weight`/`confidence` inválidos; aresta com coluna
obrigatória ausente; `preflight_import()` combinando os dois). Todos os
10 batendo, viraram 8 testes permanentes em `tests/testthat/test-validate.R`
(16 assertivas novas, suíte de `validate` foi de 33 pra 49 dots). Testado
também ao vivo rodando o app de verdade: (1) CSV com `dpsir_category`
inválido — bloqueado, alerta vermelho com a linha certa, nada importado;
(2) `data/sample_nodes.csv`/`sample_edges.csv` (já no schema atual) —
importa limpo, só um aviso real (`descriptor` de fato não existe nesses
CSVs, correto); (3) CSV mínimo (só `id`/`label`/`dpsir_category`) —
importa normalmente com os 5 avisos esperados, um por coluna opcional
ausente. Sem erro no console do servidor em nenhum dos três casos. Suíte
completa e checagem de sintaxe seguem limpas.

Trilha operacional separada (independente, registrada no plano, encaixa
quando quiser): layout circular não parece um círculo (suspeita de
container retangular esticando a proporção, não confirmada ao vivo ainda —
diferente do bug de posição arrastada não voltar ao anel, já corrigido
acima), reordenar níveis do schema (`mod_data.R`'s "Add level" não tem
edição nem tratamento de colisão pra um nível já existente). Nenhuma
dessas foi endereçada ainda — ficam registradas pra quando o usuário
quiser retomá-las.

Pedido pelo usuário mas ainda não definido: "estrela"/"rosa" como layouts
adicionais — precisa de uma conversa pra fixar o que cada termo significa
antes de implementar (ver discussão registrada na sessão).

Retomar matriz de conexões livre e aninhamento hierárquico de níveis (Fase 2, itens
restantes) quando desenhados. Considerar incluir cenários salvos no savepoint (hoje
só duram a sessão) se isso vier a ser pedido. Relatório: adicionar seção de
Comunidades (imagem + tabela) como fast-follow, reaproveitando a mecânica de
captura já existente.

## Princípios

Minimalista e incremental. Vocabulário controlado e validação por construção.
Reprodutibilidade (adicionar `renv`). Testar rodando o app a cada mudança de módulo.
