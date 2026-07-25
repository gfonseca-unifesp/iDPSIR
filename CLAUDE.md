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
  (`compute_layered_layout`), `build_network_visual` (tooltips, espessura por weight,
  tracejado por confidence), `sanitize_edges`.
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
- `R/responses.R` → simulação de respostas schema-aware (`get_feedback_categories`,
  `find_response_targets`, `apply_response`, `compute_node_impact_score`,
  `summarize_response_impact`, `compare_states`, `compare_multiple_states`).
  Motor da aba Scenarios até a Fase 5 Marco B — ver `R/loop_analysis.R` abaixo.
- `R/loop_analysis.R` → análise de loop / matriz comunitária (Levins 1974), Fase 5
  Marco A: `build_interaction_matrix(g)` (matriz `A[i,j]` = efeito de `j` sobre `i`,
  sinal de `interaction_type`/magnitude de `weight`), `check_stability(A)`
  (autovalores, `stable`/`eigenvalues`/`max_real_part`), `press_perturbation(A, press)`
  (efeito de um passo `A %*% press` e de equilíbrio `-A^-1 %*% press`; matriz
  singular retorna `NA` com aviso em vez de erro). Sem dependência nova
  (`eigen()`/`solve()` do R base). Ainda não usada por nenhum módulo — `mod_responses.R`
  passa a chamar isso no Marco B, substituindo `apply_response` como motor principal.
- `R/report.R` → montagem do relatório HTML autocontido (`build_full_report_html`,
  `report_html_table`, `format_report_cell`, `matrix_to_report_df`), usado só por
  `mod_report.R`. Seções (imagens de grafo salvas/métricas gerais/centralidades/
  descritores/cenários) são todas opcionais via flags — nenhuma é recomputada aqui,
  só reaproveita as funções de `R/metrics.R`/`R/responses.R` já usadas nas outras
  abas. `graph_snapshots`/`selected_snapshot_names` viram uma seção "Network graph"
  com um `<h3>` + `<img>` por snapshot selecionado, não uma imagem única.
- `R/modules/mod_data.R` → editor por formulário (passos Início/Modelo/Nós/Arestas/Revisar
  do wizard); estado em `reactiveValues`, não-reativo até "Construir/Reconstruir grafo".
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
  direções da sincronização cruzada tabela↔grafo limpava a seleção sozinha.
- `R/modules/mod_metrics.R` → painel único de métricas (Gerais / Centralidades / Descritores DPSIR).
- `R/modules/mod_responses.R` → aba "Scenarios": ativar respostas (nós de categoria
  feedback) com força 0-100%, aplicar cenário combinado, salvar e comparar múltiplos
  cenários lado a lado (comparação rápida em tela — a exportação em si vive em
  `mod_report.R`, ver abaixo).
- `R/modules/mod_report.R` → aba "Report" (última do Explorar): checkboxes para
  métricas gerais/centralidades/descritores DPSIR, seleção múltipla de imagens de
  grafo salvas (`mod_graph.R`'s "Save current view for report") e seleção múltipla
  de cenários salvos (baseline sempre incluído) — mesmo padrão de tabela com
  `selection = "multiple"` para as duas. Um único botão "Download report (HTML)"
  gera tudo via `build_full_report_html`. Registra o handler JS compartilhado de
  captura (`idpsir_capture_element`/`html2canvas`), mas quem dispara a captura é
  `mod_graph.R`, não este módulo — ver seção de captura de imagem abaixo.
- `R/modules/mod_wizard.R` → casca do wizard (passo atual, Voltar/Avançar com validação,
  download do savepoint disponível em qualquer passo, Next oculto no último passo — ver
  Fase 4.3); o passo Explorar é um `tabsetPanel` (Graph/Scenarios/Metrics/Report). Não
  participa mais da captura de imagem do grafo (ver seção abaixo) — só encaminha o
  `graph_snapshots` retornado por `mod_graph_server` para `mod_report_server`.
- `R/modules/mod_communities.R` → versão anterior da aba de comunidades (widget
  `visNetwork` separado, sem os filtros/espaçamento do Graph), mantida no disco mas
  **não sourceada** desde a Fase 4.2 — superada por `mod_graph.R`.
- `R/ui_main.R`, `R/server_main.R` → UI e server principais (chamam só `mod_wizard_*`).
- `data/` → CSVs de exemplo.

Ao adicionar/remover um arquivo em `R/`, atualize os `source()` em `global.R`.

## Modelo de dados

**Nós:** `id`, `label`, `dpsir_category`, `subsystem`, `uncertainty` (low/medium/high),
`controllability` (low/medium/high), `temporal_scale` (short/medium/long).
**Arestas:** `from`, `to`, `weight`, `confidence` (0–1), `interaction_type`
(`positive`/`negative` — sinal do efeito causal, usado tanto na cor da aresta quanto,
futuramente, como sinal direto da matriz de interação da Fase 5), `evidence_type`.
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

**Fase 5 iniciada (Marco A concluído, ver PLANO seção 8).** `R/loop_analysis.R`
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

## Próximo

Fase 5 Marco B é o próximo passo: revisar `mod_responses.R` pra computar a partir de
`R/loop_analysis.R` em vez de `apply_response()` — tabela de efeito (imediato +
equilíbrio) e aviso de estabilidade, mesma interface (tabelas "Effect on the
network"/"Effect on each factor", linguagem Improves/Worsens/Stable) que a aba
Scenarios já usa hoje. Depois, Marco C (trajetória com número de passos ajustável) e
Marco D (robustez via confidence). Retomar matriz de conexões livre e aninhamento
hierárquico de níveis (Fase 2, itens restantes) quando desenhados. Considerar incluir
cenários salvos no savepoint (hoje só duram a sessão) se isso vier a ser pedido.
Relatório: adicionar seção de Comunidades (imagem + tabela) como fast-follow,
reaproveitando a mecânica de captura já existente.

## Princípios

Minimalista e incremental. Vocabulário controlado e validação por construção.
Reprodutibilidade (adicionar `renv`). Testar rodando o app a cada mudança de módulo.
