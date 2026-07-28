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
  `merge_savepoints`, ver Fase 4 abaixo).
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
  `sufficiency(g, p_D, p_R, c)` — piora/mitigação/líquido/neutralizado/força
  necessária por Impacto (`strength_to_neutralize` é uma razão
  adimensional sobre `p_R`, não um valor absoluto — a tela multiplica pela
  força planejada de uma resposta única na hora de exibir, já que somar
  respostas combinadas não teria uma "força planejada" única pra
  multiplicar). `sufficiency_confidence()` reaproveita a mesma reamostragem
  de `robustness_check()`. `sufficiency_reach_over_c()` varre uma grade de
  `c` e sinaliza veredito de fronteira.
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
  motor de suficiência, ver `R/sufficiency.R` acima.
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

**Revisão 1 em andamento — modelo de suficiência de resposta, na branch
`fase-10-suficiencia`** (documento externo trazido pelo usuário, plano de
6 fases em `.claude/plans/wondrous-cuddling-eclipse.md`, ver "Estado atual"
acima pro achado que motivou a revisão — inversão de sinal real na rede de
Mangi et al. 2007 sob o motor antigo). Substitui `press_perturbation()`
(equilíbrio dinâmico, exige estabilidade) por `propagate()`
(`R/sufficiency.R`, efeito propagado e descontado, sempre bem definido) como
leitura principal da aba Scenarios:
- [x] **Fase 1** — motor matemático (`R/sufficiency.R`), aditivo, zero
  mudança visível (concluído, ver acima).
- [ ] **Fase 2** — UI nova ("Pressure scenario" + controle de alcance + as
  3 tabelas da Seção 4) ao lado da UI antiga, sem remover nada ainda.
- [ ] **Fase 3** — relatório (3 tabelas novas) + persistência dos dois
  cenários + `c` no savepoint.
- [ ] **Fase 4** — corte: remove UI/relatório do motor antigo, renomeia
  `mod_responses.R`→`mod_scenarios.R`, remove `self_regulation` de
  `schema.R`/`validate.R`/`mod_data.R`.
- [ ] **Fase 5** — promove exemplo de Mangi a `docs/`, reescreve tutorial e
  README pra "os dois empurrões", decide o que fazer com testes órfãos.
- [ ] **Fase 6** — verificação final, `CLAUDE.md`, commit/push/merge.

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
