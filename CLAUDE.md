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
- `R/figure_export.R` — `export_figure()` (PNG/TIFF com dpi, PDF/SVG; largura em mm; fonte em pt),
  rede estática para impressão (`draw_network_static()`), botão/diálogo "Download figure…"
  (`figure_export_button()`, `register_figure_export()`, com pré-visualização PNG no diálogo) em toda
  figura do app; a rede segue a aba Graph (paleta, filtro, formas DPSIR, tracejado por confiança,
  cores por comunidade, destaque do caminho ou do nó selecionado; layout "screen" = camadas com o
  espaçamento e os nós arrastados; opções em `network_view()`) e
  substitui o "Export as png" do visNetwork (html2canvas agora vem de `html2canvas_dependency()`,
  `R/graph.R`, para o "Save current view for report"); usado também por
  `data-raw/manuscript_figures.R`. Relatório: qualidade 96/300 dpi e rede estática.
- `R/data_needs.R` — `data_needs()`: tabela ordenada do que medir ou buscar primeiro (passo 5 do
  manuscrito v7): ligações dos vereditos apertados e Estados sem limiar intercalados, limiar sem
  referência/DP, ligações assumidas sem referência no caminho, força aplicada das respostas,
  crescimento (só com o temporal ligado). Aba Interpretation (CSV) e relatório.
- `R/interpretation.R` — leitura em linguagem simples de um cenário (`interpret_scenario()`),
  comparação entre cenários e gráfico de cobertura; usado pela aba Interpretation
  (`mod_interpretation_ui()`, saídas em `mod_responses_server()`) e pelo relatório.
- `R/temporal.R` — simulação por janelas: dev(t+1) = (1 − sr)·dev + B·x + p,
  x = dev + tendência; modos permanent/impulse/window; parada "até neutralizar";
  intensidade das arestas.
- `R/loop_analysis.R` — só `build_interaction_matrix()`, `self_regulation_diagonal()`,
  `build_press_vector()` (o motor de equilíbrio antigo está em `legacy/`).
- `R/pathways.R` — caminhos pela ordem do schema; efeito = produto dos β com sinal.
- `R/reach.R`, `R/metrics.R` (inclui `network_strength_confidence()`: força e confiança
  globais, aba Metrics e relatório), `R/responses.R` (`get_feedback_categories()`),
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
  `structural = FALSE` reproduz os números antigos. **Sorteio em que a pressão deixa de piorar
  o Impacto (ligação ausente no caminho) não conta como neutralizado**: vai para
  `not_worsened_pct`, com nota na tela, no relatório e na Interpretation (antes inflava a
  confiança: fauna do porto 0% → 29%, que eram todos "não piorado"; agora 0% e 29% não piorado).
  A confiança ainda pode subir de verdade quando some uma de várias ligações da pressão e a
  piora diminui (Mangi, rendimento 11% → 29%, com a pressão piorando em 100% dos sorteios).
  Variante do Sri Lanka sem auxílio → frota (`example_gnanapragasam_noaidfleet`): alcance do
  auxílio 1/5, estoque nunca abaixo de B_MSY, esforço RMSE 6.152 contra 658. Como a variante
  perde os dois betas ajustados, a comparação justa está em
  `analysis/validation_srilanka/variant_test.R`: ΔAIC 67 (sem auxílio, nada ajustado) e 42 (rival
  com 2 parâmetros: crescimento da frota e demanda → esforço, que bate no limite β = 1,5); fora da
  amostra 2015–2021, RMSE 559 contra 6.871 e 10.867 — os dados sustentam a hipótese.
- **E5.3–E5.5 (redes simuladas, 1000 × 20):** H1 confirmada (forças mudam 15,9% dos
  vereditos); H2 refutada (limiares 18,9%, mas crescimento só 4,3% — move linha de base e
  cenário juntos); H3 refutada (ciclos mudam *menos*, OR 0,79); H4 confirmada (perto da
  neutralização, OR 5,4); H5 refutada (τ médio 0,64; topo da prioridade muda em 35%).
  Trocar a leitura estática → temporal muda 17,8%. **Consequência para o texto:** a ordem
  "limiares e crescimento primeiro" do tutorial/manuscrito não se sustenta — limiares e
  forças importam parecido, crescimento pouco para o veredito; e a prioridade é mais
  sensível à parametrização que o veredito. Resultados em `analysis/sim_networks/out/`.
- **E7 (busca de ferramentas):** `analysis/tool_search/` (protocolo + tabela com fonte por
  célula). Web/GitHub/CRAN feitos; WoS/Scopus/Scholar ficam com os autores. Achados: suficiência
  **não** é exclusiva do iDPSIR (Ahtiainen et al., Marine Policy; Bryhn et al. 2026 "Mind the
  GAP") — a novidade é a leitura por propagação numa rede causal, aberta e sem instalação; QPress
  tem widgets Shiny; FCM já tem incerteza Monte Carlo (In-Cognitive 2023); ler Ramos-Quintana
  et al. 2018.
- **S7 / passo 6 fora do app:** `analysis/templates/validate_network.R` (template genérico:
  `vn_load`, `vn_calibrate`, `vn_validate`, `vn_compare`, `vn_plot_validation`); os scripts de
  `analysis/validation_srilanka/` são só a configuração do caso (mesmos números, conferidos por
  `test-validation-template.R` contra `manuscript_numbers.json`). `vn_compare` acrescenta AICc e a
  autocorrelação lag-1 dos resíduos (publicada 0,15; alternativas 0,75–0,76).
- **Figuras do manuscrito v8:** `data-raw/manuscript_figures.R` grava em `manuscrito_v8/fig_hr/`;
  redes das Figs. 3a–5a em layout circular com ligações por tipo de linha (`MS_NET_LAYOUT`,
  `MS_NET_EDGES`); Fig. 6 com texto maior (`par(cex = 1)` depois do `mfrow`).
- **E6 (teste de usabilidade): fora do plano** por decisão do autor — não há coleta com
  participantes, nada depende de CEP.
- **E4:** forma aditiva opcional; justificativa do produto (perda esperada evitável);
  `priority_robustness()` (v ± 20%, produto × soma) → coluna "Rank stability", nota e
  mensagem na Interpretation quando o topo é instável (< 80%).

Revisão 2 executada até a Fase 4 (branches `revisao2-fase0` … `revisao2-fase4`; ver o
roadmap). Coautora: Marcela Bergo Davanso (`CITATION.cff`, `LICENSE`, `DESCRIPTION`; UNIFESP). Pendências conhecidas: PDF da especificação de relevância a atualizar (seções 4 e
7.4, V5 com eficácia = cobertura); mesclar as branches da Revisão 2 em `main`.
