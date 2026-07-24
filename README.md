# iDPSIR

Aplicativo **R/Shiny** para construção e análise de redes causais no modelo **DPSIR** (Driver–Pressure–State–Impact–Response), voltado à gestão ambiental. Permite montar a rede (por upload de tabelas ou edição interativa), visualizá-la segundo a estrutura DPSIR e calcular métricas de rede — das mais gerais às aplicadas ao DPSIR.

## Como rodar

Requer R (≥ 4.1). Instale os pacotes e execute o app na raiz do projeto:

```r
install.packages(c(
  "shiny", "bs4Dash", "visNetwork", "igraph", "tidygraph", "ggraph",
  "DT", "dplyr", "data.table", "htmlwidgets", "colourpicker",
  "shinyWidgets", "plotly", "glue", "purrr", "scales"
))

shiny::runApp()
```

## Estrutura

```
iDPSIR/
├── app.R                     # ponto de entrada
├── global.R                  # pacotes, opções e carregamento dos fontes
├── R/
│   ├── dpsir/                # regras do modelo DPSIR (validação, mapeamento, caminhos, respostas)
│   ├── core/graph/           # motor do grafo (builder, validação, visualização)
│   ├── core/                 # componentes de UI compartilhados
│   ├── compute/              # métricas (grau, intermediação, pagerank, etc.)
│   ├── modules/              # módulos Shiny (network, metrics, centrality, communities, pathways, responses, upload)
│   ├── ui_main.R             # UI principal
│   └── server_main.R         # server principal
├── data/                     # dados de exemplo (sample_nodes.csv, sample_edges.csv)
├── PLANO_iDPSIR.md           # plano de reestruturação e roadmap
└── README.md
```

## Formato dos dados

**Nós** (`data/sample_nodes.csv`): `id`, `label`, `dpsir_category` (Driver, Pressure, State, Impact, Response), `subsystem`, `uncertainty` (low/medium/high), `controllability` (low/medium/high), `temporal_scale` (short/medium/long).

**Arestas** (`data/sample_edges.csv`): `from`, `to`, `weight`, `confidence` (0–1), `interaction_type`, `evidence_type`.

**Conexões DPSIR permitidas:** Driver→Pressure, Pressure→State, State→Impact, Impact→Response e Response→{Driver, Pressure, State, Impact}.

## Roadmap

O plano de evolução (esquema DPSIR configurável, interface em wizard, savepoint, aproveitamento de atributos e fases de desenvolvimento) está em [`PLANO_iDPSIR.md`](PLANO_iDPSIR.md).

> Reprodutibilidade: adicionar `renv` para fixar as versões dos pacotes (previsto na Fase 0/1).
