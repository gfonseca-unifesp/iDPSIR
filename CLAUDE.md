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
- `R/core/core_ui_components.R` → toggles/inputs compartilhados (usados no painel de métricas).
- `R/dpsir/core_dpsir_pathways.R`, `core_dpsir_responses.R` → lógica de pathways/respostas
  **preservada mas não sourceada** em `global.R`; reservada para reuso nas Fases 2/3.
- `R/modules/mod_data.R` → editor por formulário (passos Início/Modelo/Nós/Arestas/Revisar
  do wizard); estado em `reactiveValues`, não-reativo até "Construir/Reconstruir grafo".
- `R/modules/mod_graph.R` → painel leve de exploração do grafo (filtros de subsistema/escala
  temporal, paleta de exibição, layout em camadas).
- `R/modules/mod_metrics.R` → painel único de métricas (Gerais / Centralidades / Descritores DPSIR).
- `R/modules/mod_wizard.R` → casca do wizard (passo atual, Voltar/Avançar com validação,
  download do savepoint disponível em qualquer passo).
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

## Próximo: Fase 2 (ver PLANO seção 8)

Destaque de caminhos no grafo, aba de pathways enxuta, comunidades corrigidas (com
arestas desenhadas), seleção cruzada grafo↔tabela, matriz de conexões livre e
aninhamento hierárquico de níveis.

## Princípios

Minimalista e incremental. Vocabulário controlado e validação por construção.
Reprodutibilidade (adicionar `renv`). Testar rodando o app a cada mudança de módulo.
