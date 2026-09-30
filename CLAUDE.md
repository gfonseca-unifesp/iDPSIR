# CLAUDE.md — iDPSIR

Resumo operacional para assistentes de código. O histórico detalhado (fases, bugs
achados ao vivo, decisões que mudaram de rumo) está em **`docs/CHANGELOG.md`**; o
roadmap em vigor é **`ROADMAP_REVISAO2_iDPSIR.md`**. Documentação para o usuário:
`README.md` e `docs/tutorial.html`.

## O que é

App **R/Shiny** para construir e analisar redes causais **DPSIR**
(Driver–Pressure–State–Impact–Response) em gestão ambiental. Científico, minimalista,
evolução incremental. UI em inglês; comentários e docs internos em português.

## Como rodar e testar

```r
shiny::runApp()                               # sobe o app
testthat::test_dir("tests/testthat")          # ou: Rscript tests/testthat.R
```

- `global.R` instala os pacotes que faltarem (`required_packages`) e dá `source()` em
  tudo (a ordem importa). Ao adicionar/remover um arquivo em `R/`, atualize os
  `source()` de `global.R` e de `tests/testthat/helper-setup.R`.
- `jsonlite` só com prefixo (`jsonlite::`): anexado, mascara `shiny::validate()`.
- **Sempre teste rodando o app** após mudar módulos — erros de Shiny só aparecem em
  runtime. Nesta máquina: R 4.5.1 (`C:/Program Files/R/R-4.5.1/bin/Rscript.exe`).
- `DESCRIPTION` lista as dependências (projeto, não pacote); `renv.lock` só para
  desenvolvimento/CI (sem `.Rprofile`: `runGitHub()` continua com o auto-install).
- CI (`.github/workflows/shinylive.yml`): testes em todo push/PR; export shinylive e
  deploy no Pages só a partir de `main` (R 4.5.1, shinylive 0.5.0 fixos).

## Estrutura

- `R/schema.R` — schema configurável (níveis, ordem, paletas; Okabe-Ito padrão) e
  **papéis** (`schema_roles()`, `roles_of()`, `has_role()`): o motor nunca compara nomes
  de categoria, só papéis driver/pressure/state/impact/feedback.
- `R/validate.R` — preflight de importação (bloqueios e avisos com linha) e
  normalização de nós/arestas (defaults, legado).
- `R/structural.R` — aresta = β padronizado com faixa; classes weak/moderate/strong
  (0,15/0,45/0,80); `effect_matrix()`, checagem ρ(B) < 1, conversão de arquivos antigos,
  avisos do Review.
- `R/sufficiency.R` — leitura estática: efeito total (I − B)⁻¹p − p; piora, mitigação,
  líquido, "Not affected"; confiança por reamostragem da faixa; `with_local_seed()`.
- `R/triggers.R` — gatilhos de Estado (limiar em unidade real, z, direção), leitura
  estática e temporal, alcance efetivo, tabela de níveis.
- `R/relevance.R` — importância D, confiabilidade ρ, lacuna e prioridade dos Impactos.
- `R/temporal.R` — simulação por janelas: dev(t+1) = (1 − sr)·dev + B·x + p,
  x = dev + tendência; modos permanent/impulse/window; parada "até neutralizar";
  intensidade das arestas.
- `R/loop_analysis.R` — só `build_interaction_matrix()`, `self_regulation_diagonal()`,
  `build_press_vector()` (o motor de equilíbrio antigo está em `legacy/`).
- `R/pathways.R` — caminhos pela ordem do schema; efeito = produto dos β com sinal.
- `R/reach.R`, `R/metrics.R`, `R/responses.R` (`get_feedback_categories()`),
  `R/graph.R` (grafo, layouts, visual), `R/scenario_plots.R` (gráfico temporal e de
  prioridade), `R/report.R` (relatório HTML), `R/io.R` (CSV, savepoint com cenário e
  cenários salvos).
- `R/modules/` — `mod_wizard.R` (passos num tabset oculto controlado pelo servidor),
  `mod_data.R` (Start/Model/Nodes/Edges/Review), `mod_graph.R`, `mod_responses.R`
  (Scenarios; `compute_scenario()`), `mod_metrics.R`, `mod_report.R`.
- `data/` — exemplos (Mangi 2007, Gnanapragasam 2026 com parâmetros e esforço observado,
  `sample_*`); `data-raw/` — scripts que geram o exemplo do Sri Lanka e suas figuras;
  `docs/` — tutorial, savepoints de exemplo, figuras; `legacy/` — código fora de uso;
  `tests/testthat/` — suíte (fixtures de formatos antigos em `fixtures/`).

## Modelo de dados

**Nós:** `id`, `label`, `dpsir_category`, `subsystem`, `self_regulation` [0,1] (padrão
0,5), `growth_rate` (> −1), `growth_cap`, `reference_value` (> 0), `sd` (> 0),
`threshold_level` e `threshold_direction` (só State), `endpoint_class`/`value_v` (só
Impact), `descriptor`. **Arestas:** `from`, `to`, `interaction_type` (positive/negative,
obrigatório), `weight` (β), `weight_low`/`weight_high`, `strength_class`,
`weight_source`, `evidence_type`, `reference`; `confidence` é derivada da faixa (só
visual). Colunas antigas (`uncertainty`, `controllability`, `temporal_scale`,
`activation_threshold`, `threshold` em aresta) são convertidas ou descartadas com aviso.
**Conexões:** D→P, P→S, S→I, I→R, R→{D,P,S,I}.

## Lições que valem para qualquer mudança

- `renderUI` que lê inputs que ele mesmo cria: `isolate()`, senão redesenha a cada mudança.
- Outputs escondidos ficam suspensos; o passo inicial e as saídas do Start usam
  `suspendWhenHidden = FALSE`. A aba Explore é montada só no passo 6 — atualizações
  enviadas antes disso se perdem (preencher com `observe` que lê o próprio input).
- `debounce()` devolve `NULL` no primeiro render: dê default.
- Atribuir linha de data.frame **por nome** (`df[idx, names(new_row)] <- new_row`).
- `jsonlite::write_json(auto_unbox = TRUE)` desmancha vetor nomeado de tamanho 1: salvar
  como linhas (`id`, `strength`); `digits = NA` para precisão total.
- DT: seleção de linha não reage a clique sintético (teste com
  `Shiny.setInputValue(..._rows_selected)`); `formatRound()` casa com o nome exibido.
- `visNetworkProxy()` precisa de `session$ns()`; `dataTableProxy()` não.
- `igraph::plot()` lê o atributo `shape` do vértice: passe `vertex.shape` explícito.
- Um fator com autorregulação s se assenta em β/s no temporal: Estados calibrados por
  equilíbrio usam s = 1.

## Decisões da Revisão 2 (não reabrir)

| # | Decisão |
|---|---|
| D1 | Pressão e resposta têm modo próprio: `permanent`, `impulse` ou `window` (início e duração por fator, Fase D). "Até neutralizar" é critério de parada da simulação, não modo. |
| D2 | Padrões: pressão e resposta `permanent`; duração "até neutralizar", máximo 50 janelas. |
| D4 | Ciclos só existem via Resposta (I→R); sem Resposta, a cadeia tem no máximo D→P→S→I. |
| D6 | Relevância v1.0: `endpoint_class`, valor v (swing weights), D max-normalizado, ρ multiplicativo. |
| D7/D8 | Gatilho do Estado: desvio com sinal (D/P recortados ≥ 0), binário — liga/desliga todas as arestas de saída. |
| D9/D10/D24 | Crescimento no nó, como tendência do nível de base (igual nas duas rodadas, também fora do cenário); autorregulação só no desvio; x = desvio + tendência. Teto opcional (`growth_cap`). |
| D11 | Gatilho temporal por desvio acumulado (padrão) ou carga na janela; comparação disponível. |
| D12 | Alcance topológico e efetivo (sem atravessar gatilho fechado), lado a lado. |
| D13/D19/D22 | Só o modo estrutural (sem o fator c); arquivos antigos convertidos (β = λ·w) com aviso; exemplos no modo estrutural. |
| D14 | Importância D pela propagação do app (= Levins padronizado). |
| D15 | Eficácia = cobertura (força do slider); a faixa de β entra só na incerteza. |
| D17/D18/D21 | Aresta = β padronizado com faixa; r² só atalho; classes 0,15/0,45/0,80; sinal sem padrão; confiança antiga vira faixa. |
| D20 | Persistência do desvio = 1 − `self_regulation`; padrão 0,5. |
| D23 | Camada de medida: referência, DP/CV, limiar em unidade real (z), força > 100% ou em unidades. |
| 30/09 | `uncertainty`/`controllability` removidos (não entravam em cálculo). Papéis vêm do schema. Paleta Okabe-Ito padrão. Exemplo do Sri Lanka parametrizado pelo artigo (limiar = B_MSY; B_lim nunca é cruzado). Cenários salvos entram no savepoint (definição; recalculados ao carregar). |

## Estado

Revisão 2 executada até a Fase 4 (branches `revisao2-fase0` … `revisao2-fase4`; ver o
roadmap). Pendências conhecidas: lista de coautores para `CITATION.cff`/`LICENSE`
(hoje só o autor principal); PDF da especificação de relevância a atualizar (seções 4 e
7.4, V5 com eficácia = cobertura); mesclar as branches da Revisão 2 em `main`.
