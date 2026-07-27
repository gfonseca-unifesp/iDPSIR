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
  vocabulários controlados de nós/arestas, legenda).
- `R/validate.R` → validação de nós/arestas contra o schema.
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
  seção "Scenarios compared" do relatório.
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
  aresta tiver (ver Estado atual).
- `R/modules/mod_data.R` → editor por formulário (passos Início/Modelo/Nós/Arestas/Revisar
  do wizard); estado em `reactiveValues`, não-reativo até "Construir/Reconstruir grafo".
  Formulário de aresta tem um campo opcional "Threshold" (em branco na maioria das
  arestas) — ver Fase 5 fast-follow "threshold não-linear" no Estado atual — e um
  campo opcional "Reference" (texto livre, DOI/URL/citação) — ver item 7.3 do
  roadmap de publicação no Estado atual.
  `rv$positions` (campo do savepoint que existia desde a Fase 1 mas nunca tinha
  nada escrevendo nele) ganhou um setter (`set_positions`) exposto no retorno do
  módulo, pra `mod_graph.R` gravar as posições arrastadas manualmente — ver
  Fase 5 fast-follow "layout do grafo".
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
  sem gastar simulação à toa.
- `R/modules/mod_report.R` → aba "Report" (última do Explorar): checkboxes para
  métricas gerais/centralidades/descritores DPSIR/referências de aresta, seleção
  múltipla de imagens de
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
- `data/` → CSVs de exemplo.
- `tests/testthat.R`, `tests/testthat/*.R` → testes automatizados do núcleo
  numérico (item 6.3 do roadmap de publicação) — ver Estado atual.

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
- [ ] **6.1** — LICENSE (MIT, já confirmado)/CITATION.cff/DESCRIPTION — por
  último, aguardando lista de coautores do usuário.
- Ordem combinada pro que resta: **7.2 (sensibilidade/ranking de arestas) →
  6.4 (sessionInfo + seed no relatório) → 6.2 (renv) → 8.1 (shinylive)** — 6.2
  fica depois de 7.2/6.4 de propósito, pra só travar a lista de dependências
  quando não houver mais trabalho pela frente que possa adicionar um pacote
  novo (7.2 cogita `ggplot2` pro gráfico tornado, ainda não é dependência do
  app hoje). 8.1 continua com a ressalva de fazer um spike de bs4Dash em
  WASM antes de tratar como gate garantido.

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
