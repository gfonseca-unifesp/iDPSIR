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
# instalar pacotes (uma vez)
install.packages(c(
  "shiny","bs4Dash","visNetwork","igraph","DT","dplyr",
  "data.table","htmlwidgets","shinyWidgets","glue","purrr","scales","jsonlite"
))
shiny::runApp()          # sobe o app
```

`jsonlite` é usado só via `jsonlite::` (nunca `library(jsonlite)`) porque ele
mascara `shiny::validate()` quando anexado — cuidado se for usar em outro lugar.

Checagem rápida de sintaxe sem subir o app:
`Rscript -e 'invisible(lapply(list.files("R", "\\.R$", recursive=TRUE, full.names=TRUE), parse))'`

**Sempre teste rodando o app** após mudanças em módulos — erros de Shiny só aparecem em runtime.

## Estrutura

- `app.R` → chama `ina_ui()` / `ina_server()`.
- `global.R` → pacotes, opções e `source()` de todos os fontes (ordem importa).
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
  (`build_savepoint`/`write_savepoint`/`read_savepoint`, com checagem de `format_version`).
- `R/pathways.R` → análise de caminhos causais schema-aware (`find_dpsir_paths`,
  `compute_critical_pathways`, `score_pathway`), adaptado de `R/dpsir/core_dpsir_pathways.R`.
- `R/core/core_ui_components.R` → toggles/inputs compartilhados (usados no painel de métricas).
- `R/dpsir/core_dpsir_pathways.R` → versão original (categorias fixas), mantida no disco
  mas **não sourceada**; superada por `R/pathways.R`.
- `R/dpsir/core_dpsir_responses.R` → lógica de simulação de respostas, **preservada mas
  não sourceada**; reservada para a Fase 3 (`apply_response`, cenários).
- `R/modules/mod_data.R` → editor por formulário (passos Início/Modelo/Nós/Arestas/Revisar
  do wizard); estado em `reactiveValues`, não-reativo até "Construir/Reconstruir grafo".
- `R/modules/mod_graph.R` → painel de exploração do grafo (filtros de subsistema/escala
  temporal, paleta de exibição, layout em camadas, tabela de nós com seleção cruzada
  grafo↔tabela). Destaque de caminhos causais vive aqui também, como dropdown "Highlight
  pathway" (From/To categoria + seleção do caminho, mesmo padrão de "Select by group" /
  "Node size based on") — não é uma aba separada, para não forçar o usuário a trocar de
  aba e voltar toda vez que quiser ver o destaque no grafo.
- `R/modules/mod_communities.R` → aba de comunidades (Louvain/Walktrap/Infomap/Label
  Propagation) desenhada com `build_community_visual` (com arestas, ao contrário da
  versão pré-Fase-1).
- `R/modules/mod_metrics.R` → painel único de métricas (Gerais / Centralidades / Descritores DPSIR).
- `R/modules/mod_wizard.R` → casca do wizard (passo atual, Voltar/Avançar com validação,
  download do savepoint disponível em qualquer passo); o passo Explorar é um
  `tabsetPanel` (Graph/Communities/Metrics).
- `R/ui_main.R`, `R/server_main.R` → UI e server principais (chamam só `mod_wizard_*`).
- `data/` → CSVs de exemplo.

Ao adicionar/remover um arquivo em `R/`, atualize os `source()` em `global.R`.

## Modelo de dados

**Nós:** `id`, `label`, `dpsir_category`, `subsystem`, `uncertainty` (low/medium/high),
`controllability` (low/medium/high), `temporal_scale` (short/medium/long).
**Arestas:** `from`, `to`, `weight`, `confidence` (0–1), `interaction_type`, `evidence_type`.
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

## Próximo

Retomar matriz de conexões livre e aninhamento hierárquico de níveis (Fase 2,
itens restantes) quando desenhados, ou avançar para a Fase 3 (cenários de resposta,
`apply_response`, `R/dpsir/core_dpsir_responses.R`).

## Princípios

Minimalista e incremental. Vocabulário controlado e validação por construção.
Reprodutibilidade (adicionar `renv`). Testar rodando o app a cada mudança de módulo.
