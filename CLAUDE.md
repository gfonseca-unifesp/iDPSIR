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
  "shiny","bs4Dash","visNetwork","igraph","tidygraph","ggraph","DT","dplyr",
  "data.table","htmlwidgets","colourpicker","shinyWidgets","plotly","glue","purrr","scales"
))
shiny::runApp()          # sobe o app
```

Checagem rápida de sintaxe sem subir o app:
`Rscript -e 'invisible(lapply(list.files("R", "\\.R$", recursive=TRUE, full.names=TRUE), parse))'`

**Sempre teste rodando o app** após mudanças em módulos — erros de Shiny só aparecem em runtime.

## Estrutura

- `app.R` → chama `ina_ui()` / `ina_server()`.
- `global.R` → pacotes, opções e `source()` de todos os fontes (ordem importa).
- `R/dpsir/` → regras do modelo DPSIR (validação, mapeamento visual, caminhos, respostas).
- `R/core/graph/` → motor do grafo: `builder` (build_igraph), `validation`, `visualization` (build_network_visual, sanitize_edges).
- `R/core/core_ui_components.R` → toggles/inputs compartilhados.
- `R/compute/` → métricas (grau, intermediação, proximidade, pagerank, eigenvector, densidade, diâmetro, transitividade, modularidade, comunidades).
- `R/modules/` → módulos Shiny: `mod_network` (edição+grafo), `mod_metrics`, `mod_centrality`, `mod_communities`, `mod_pathways`, `mod_responses`, `mod_upload`.
- `R/ui_main.R`, `R/server_main.R` → UI e server principais.
- `data/` → CSVs de exemplo.

Ao adicionar/remover um arquivo em `R/`, atualize os `source()` em `global.R`.

## Modelo de dados

**Nós:** `id`, `label`, `dpsir_category`, `subsystem`, `uncertainty` (low/medium/high),
`controllability` (low/medium/high), `temporal_scale` (short/medium/long).
**Arestas:** `from`, `to`, `weight`, `confidence` (0–1), `interaction_type`, `evidence_type`.
**Conexões DPSIR (padrão):** D→P, P→S, S→I, I→R, R→{D,P,S,I}.

## Estado atual

**Fase 0 concluída** (commit de baseline): removido código morto (`data_models/`,
`core_graph_*` não usados), `global.R` enxuto, bugs corrigidos
(`mod_metrics` com guarda de grafo vazio; `mod_communities` com Louvain/Label
Propagation em grafo não-direcionado), `output$graph` órfão removido, README e `.gitignore`.

## Próximo: Fase 1 (ver PLANO seções 4–7)

- **Esquema DPSIR configurável desde já**: categorias como *dados* (lista ordenada de níveis
  com nome/ordem/cor/forma/papel), conexões derivadas da ordem + nível de feedback.
  Padrão = DPSIR. Permite sub-níveis/intermediários sem mexer em código.
- **Interface em wizard** (passo a passo, poucas decisões por tela): Início → Modelo → Nós →
  Arestas → Revisar/Construir → Explorar. Análise (grafo/métricas) é painel leve, não wizard.
- **Editor por formulário + seleção** (um nó/aresta por vez, dropdowns com vocabulário controlado).
  Não-reativo: aplica no botão "Construir/Reconstruir grafo".
- **Savepoint** (`.idpsir.json`): estado completo (modelo + tabelas + posições + metadados),
  portátil e compartilhável; inicialização por matrizes CSV **ou** por savepoint.
- **Aproveitar todos os atributos** no grafo (espessura por weight, tracejado por confidence,
  tooltips) e nas métricas (descritores DPSIR: por categoria, matriz de transições, Impactos
  sem Resposta etc.). Corrigir semântica de `weight` (distância vs. força) nas centralidades.

## Princípios

Minimalista e incremental. Vocabulário controlado e validação por construção.
Reprodutibilidade (adicionar `renv`). Testar rodando o app a cada mudança de módulo.
