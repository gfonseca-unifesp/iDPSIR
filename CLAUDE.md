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
- `R/interpretation.R` — leitura em linguagem simples de um cenário (`interpret_scenario()`),
  comparação entre cenários e gráfico de cobertura; usado pela aba Interpretation
  (`mod_interpretation_ui()`, saídas em `mod_responses_server()`) e pelo relatório.
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
  (Scenarios e Interpretation; `compute_scenario()`; "cenário mostrado" único,
  `shown_source()`, com seletores sincronizados em Results, Temporal e Interpretation),
  `mod_metrics.R`, `mod_report.R`.
- `data/` — exemplos (Mangi 2007, Gnanapragasam 2026 com parâmetros e esforço observado,
  porto didático `port_*`, `sample_*`); `data-raw/` — scripts que geram os exemplos (Sri
  Lanka, Mangi, porto, versões "first run") e suas figuras;
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
| 30/09 (Mangi) | Exemplo do Mangi refeito a partir do artigo (Tabela 1, seções 3–6): não se monitoram dois indicadores em cadeia causal (sem Estado→Estado; ouriço com pressão própria, pesca de peixe-porco); arestas por classe (o artigo não dá forças), soma dos β² que chegam a cada fator < 1; único parâmetro: crescimento populacional de 3,7%/ano. Versões "first run" (só defaults) de Mangi e Sri Lanka para comparação no tutorial (`data-raw/first_run_build.R`). A rede antiga ficou em `tests/testthat/fixtures/mangi2007_v1_*`. |
| 30/09 (auditoria) | Tolerância de neutralização vale para o rótulo e para a parada "até neutralizar" (0 = só zero). "Add level" com papel (D/P/S/I/R ou personalizado, p.ex. sub-driver) e posição; papéis padrão escritos no schema; remover nível sem fatores. Tracejado das arestas segue a confiança derivada da faixa (legenda explica). |
| 30/09 | `uncertainty`/`controllability` removidos (não entravam em cálculo). Papéis vêm do schema. Paleta Okabe-Ito padrão. Exemplo do Sri Lanka parametrizado pelo artigo (limiar = B_MSY; B_lim nunca é cruzado). Cenários salvos entram no savepoint (definição; recalculados ao carregar). |

## Estado

**Revisão 3 em andamento** (`ROADMAP_REVISAO3_iDPSIR.md`, branch `revisao3`; decisões E-a/E-b
registradas no roadmap).
- **E1:** premissas declaradas: unidades em DP; leitura estática = equilíbrio temporal com s = 1
  (`static_equivalent_windows()`, `temporal_equilibrium()`, `test-equivalence.R`); redação
  convergência × estabilidade; `self_regulation_sensitivity()` com coluna na tabela de
  suficiência.
- **E2:** validação do Sri Lanka em `analysis/validation_srilanka/`. Calibração 2006–2021
  reproduz o build (0,342/0,089; R² 0,93). Fora da amostra (ajuste 2006–2014, previsão
  2015–2021): RMSE 559 mil kW-dia, viés +351, NSE −0,48. Melhor que persistência de 2014
  (632) e tendência linear (5.737); banda de 90% cobre todos os anos (larga, ±1.300). **Leitura
  honesta:** 2015–2021 é um platô, então o teste diz pouco sobre o efeito do auxílio; em
  origem móvel o modelo vence a persistência a partir de 2014, empata em 2013 e perde em 2012
  (com só três anos pós-guerra, esse auxílio sai superestimado, 0,21 contra 0,12). No texto:
  "consistente fora da amostra e melhor que referências ingênuas", não "validado".
- **E5.1–E5.2:** pré-registro (`analysis/sim_networks/PREREGISTRO.md`, commitado antes de
  qualquer execução; inclui a condição C2t para separar crescimento da troca estática →
  temporal) e gerador (`generate.R`, testado em `tests/testthat/test-sim-generator.R`).
- **E3:** lista única de tipos de evidência (+ literature, regression, calibration,
  definition); incerteza estrutural por aresta (`edge_absence_probability()`: 0,2
  expert/política/branco, 0,1 literatura/observação, 0 definição/regressão/calibração ou força
  estimada). Os sorteios de β são feitos antes das ausências (matriz), então
  `structural = FALSE` reproduz os números antigos. Pode subir a confiança (uma ligação da
  pressão também some). Variante do Sri Lanka sem auxílio → frota
  (`example_gnanapragasam_noaidfleet`): alcance do auxílio 1/5, estoque nunca abaixo de
  B_MSY, esforço RMSE 6.152 (NSE −4,9) contra 658 — os dados sustentam a hipótese.
- **E4:** forma aditiva opcional; justificativa do produto (perda esperada evitável);
  `priority_robustness()` (v ± 20%, produto × soma) → coluna "Rank stability", nota e
  mensagem na Interpretation quando o topo é instável (< 80%).

Revisão 2 executada até a Fase 4 (branches `revisao2-fase0` … `revisao2-fase4`; ver o
roadmap). Coautora: Marcela Bergo Davanso (`CITATION.cff`, `LICENSE`, `DESCRIPTION`; UNIFESP). Pendências conhecidas: PDF da especificação de relevância a atualizar (seções 4 e
7.4, V5 com eficácia = cobertura); mesclar as branches da Revisão 2 em `main`.
