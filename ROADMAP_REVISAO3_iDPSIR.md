# Roadmap — Revisão 3: fundamentos do método, validação, redes simuladas e usabilidade

**Objetivo:** atacar os pontos da revisão pré-submissão (`manuscrito_v5/REVISAO_top-journal_v5.md`) que dependem de trabalho no app ou de análises novas, antes de reescrever as Seções 2–4 do manuscrito. Ao final, o manuscrito deve se apoiar em:

1. premissas do motor declaradas e coerentes entre a leitura estática e a temporal (ponto 3 da revisão);
2. validação do Sri Lanka **fora da amostra** (ponto 2);
3. incerteza estrutural na confiança (ponto 5);
4. um índice de prioridade justificado e testado quanto à sensibilidade (ponto 7);
5. **um experimento com redes DPSIR simuladas** que transforma "estrutura primeiro, parâmetros depois" num resultado geral (ponto 4);
6. **um teste de usabilidade** com usuários reais (ponto 8);
7. um protocolo documentado de busca de ferramentas para a Tabela 1 (ponto 6);
8. o script único de números e figuras (A-2 do `ROADMAP_MANUSCRITO_iDPSIR.md`), agora incluindo 2–6.

**Como usar com o Claude Code:**
- Leia antes o `CLAUDE.md`, o `README.md`, o `ROADMAP_MANUSCRITO_iDPSIR.md` e a revisão em `manuscrito_v5/`.
- Cada item traz *motivação*, *o que fazer*, *arquivos*, *testes* e **Pronto quando**. Cada item é uma unidade de trabalho (um commit ou PR).
- Rode `Rscript tests/testthat.R` a cada item e **suba o app** quando mexer em módulo Shiny.
- Trabalhe numa branch nova a partir de `revisao2-exemplo-porto` (ex.: `revisao3`), ou de `main` se a Revisão 2 já tiver sido mesclada (A-1).

**Onde fica o código de análise:**
- As análises novas (Fases E2, E5, E6 e E7) ficam em `analysis/`, fora do app.
- O workflow copia o app para `_app` antes do `shinylive::export()`, que empacota tudo o que estiver lá. Confira que `analysis/` **não** entra nessa cópia.
- Pacotes usados só nas análises (ex.: `ranger`, `future.apply`) vão para `Suggests` no `DESCRIPTION`, nunca para o `global.R`.

---

## Decisões tomadas (30/09/2026) e correções ao plano

- **E-a:** opção (c) — manter as duas leituras, provar a equivalência com s = 1 e medir a sensibilidade.
- **E-b:** calibrar os auxílios em 2006–2014 e testar em 2015–2021, com validação de origem móvel como robustez.
- **E-d / E6 (30/09, decisão do autor): o teste de usabilidade sai do plano.** Tudo no app e no
  manuscrito vem da literatura ou de resultados hipotéticos; não haverá coleta com participantes,
  portanto nada depende de CEP. As Fases E6.1–E6.3 não serão feitas, e o manuscrito não reivindica
  usabilidade medida.
- **Branch:** `revisao3`, a partir de `revisao2-exemplo-porto`. O manuscrito (`manuscrito_v5/`, `MANUSCRIPT_*.docx`) fica fora do git.

Correções feitas ao conferir o plano contra o código:
1. **E2.1:** `calibrate_aid()` não existe no build do Sri Lanka, que só guarda os valores ajustados (0,345 e 0,085). O ajuste por mínimos quadrados é reescrito em `analysis/validation_srilanka/calibrate.R` e conferido contra o R² = 0,93 documentado.
2. **E3.1:** os tipos de evidência citados (`expert`, `literature`, `regression`, `calibration`, `definition`) não são os do app (`observational`, `monitoring`, `expert_assessment`…); os exemplos usam `literature`, `literature_review` etc. A probabilidade de ausência passa a se basear na **origem da força** (`weight_source`: class/default > given/r2/calibrated) combinada com o tipo de evidência, e a lista de tipos é unificada antes.
3. **E1.4:** numa rede sem ciclos o líquido **não** é igual para todo s. Com S = s·I, (sI − B)⁻¹ = Σ Bᵏ/sᵏ⁺¹, então caminhos de comprimento diferente mudam de peso relativo. O teste verifica esse escalonamento.
4. **E1.2 / E1.4:** o equilíbrio (S − B)⁻¹p só é atingido pela simulação se ρ((I − S) + B) < 1. As funções detectam e declaram o caso divergente, em vez de devolver um número.
5. **E8:** os valores congelados do teste ficam num arquivo versionado (`tests/testthat/fixtures/manuscript_numbers.json`); `manuscrito_v5/build/` só recebe as saídas.
6. **E1.3:** a redação antiga está só no cabeçalho de `R/structural.R`.

## Decisões a confirmar antes de começar

| # | Decisão | Recomendação |
|---|---|---|
| E-a | **Autorregulação estática × temporal.** A leitura estática usa (I − B)⁻¹, que equivale a autorregulação 1 em todo nó. O estado de equilíbrio do temporal é dev* = (S − B)⁻¹p, com S = diag(s) e s = 0,5 por padrão. Os dois só coincidem quando s = 1. | **(c) Manter os dois, provar a equivalência quando s = 1 e medir a sensibilidade.** Não mudar o default agora. Documentar que a leitura estática é a de *um instante* (efeito total da path analysis) e a temporal mostra o acúmulo. A análise de sensibilidade (E1.4) diz se algum veredito depende disso. Alternativas: (a) a leitura estática passar a usar S; (b) o default temporal virar s = 1. As duas mudam números já publicados no tutorial. |
| E-b | **Janela de calibração do Sri Lanka** | Calibrar os auxílios em **2006–2014** e testar em **2015–2021**. Como robustez, fazer também uma validação com origem móvel (calibra até o ano *k* e prevê *k*+1…2021, para *k* = 2012…2016). |
| E-c | **Revista-alvo** | Define se as Fases E5 e E6 entram no artigo principal ou num segundo artigo. Recomendação: fazer as duas agora (são o que eleva o artigo) e decidir o destino com os resultados em mão. |
| E-d | **Ética no teste de usabilidade** | Consultar o CEP da UNIFESP **antes** de recrutar. A Resolução CNS 510/2016 trata de pesquisas em ciências humanas e sociais e dispensa alguns casos (p.ex. pesquisa de opinião com participantes não identificados). Confirmar com o CEP se o estudo se enquadra, e preparar o TCLE de qualquer forma. |
| E-e | **Quem é o "usuário não especialista" do teste** | Dois grupos de 6 a 8 pessoas: (1) gestores ou analistas ambientais (órgãos, consultorias, comitês); (2) estudantes de pós-graduação sem experiência em modelagem de redes. |
| E-f | **Hipóteses do experimento de redes simuladas** | Registrar H1–H5 (E5.1) em `analysis/sim_networks/PREREGISTRO.md`, com commit **antes** de rodar. Deixa claro que as hipóteses não foram ajustadas aos resultados. |

---

## Fase E1 — Premissas do motor declaradas e coerentes (ponto 3)

### E1.1 — Como a força vira o vetor p
**Motivação:** o manuscrito não diz em que unidade a pressão e a resposta se comparam. No código, `p = força% / 100` em desvios-padrão do nó (`mod_responses.R:72–73`; `build_press_vector()`). Quando o usuário informa unidades, a conversão é unidades / DP (`effective_strength()`). "Neutralizado" (líquido ≤ 0) compara efeitos em DP do Impacto.
**O que fazer:**
- Documentar isso no cabeçalho de `R/sufficiency.R` e no tutorial.
- Criar a função `press_units_note(g, p)` que devolve, por nó ativo, a força em DP e em unidades reais, quando houver `sd`. Mostrar essa nota no relatório.
**Testes:** em `test-sufficiency.R`, 100% equivale a p = 1, e 5 unidades com DP = 10 equivalem a p = 0,5.
**Pronto quando:** o relatório de cada cenário mostra a força de cada nó em DP e, quando aplicável, em unidades.

### E1.2 — Equivalência entre a leitura estática e a temporal
**Motivação:** decisão E-a.
**O que fazer:**
- Criar `static_equivalent_windows(g, p, s)`. Ela roda `simulate_temporal_pair()` sem crescimento e sem gatilho, com a autorregulação de todos os nós forçada a `s`, até convergir (|Δ| < 1e-9 ou 2000 janelas), e devolve o equilíbrio de cada Impacto.
- Documentar em `temporal.R` que o equilíbrio é (S − B)⁻¹p. Com S = I, esse equilíbrio é igual ao efeito total mais o push, porque (I − B)⁻¹p = Φ(p) + p.
**Testes (novo `test-equivalence.R`):**
- Em Mangi, Porto e Sri Lanka, sem gatilho nem crescimento, o equilíbrio temporal com s = 1 é igual a `propagate()` + p, com tolerância de 1e-6.
- Com s = 0,5, o equilíbrio é igual a solve(0,5·I − B, p).
**Pronto quando:** os testes passam e o cabeçalho de `sufficiency.R` cita a equivalência.

### E1.3 — Convergência × estabilidade: corrigir a redação
**O que fazer:**
- Em `sufficiency.R`, `structural.R`, README e tutorial, trocar "defined when ρ(B) < 1" por "the path-sum expansion converges when ρ(B) < 1; (I − B) is then invertible".
- Acrescentar que isso implica que −(I − B), a matriz de Levins com autorregulação 1, é estável, mas que a recíproca não vale.
- Checar a mensagem de erro de `propagate()`: está correta e não precisa mudar.
**Pronto quando:** `grep -rn "well defined whenever" R/ docs/` não encontra mais a redação antiga.

### E1.4 — Sensibilidade dos vereditos à autorregulação
**O que fazer:**
- Criar `self_regulation_sensitivity(g, p_D, p_R, s_grid = c(0.25, 0.5, 0.75, 1))` em `R/sufficiency.R`.
- Para cada `s`, calcular piora, mitigação e líquido no equilíbrio (S − B)⁻¹p, para Φ com S uniforme e também para S como configurado nos nós.
- Devolver o veredito de cada Impacto por `s` e a marca `depends_on_s` (o veredito muda na grade).
- Mostrar o resultado como uma linha extra na tabela de suficiência ("Holds for self-regulation 0.25–1: yes/no") e no relatório.
**Testes:** numa rede com ciclo I→R→P, o veredito muda com `s`, e o teste verifica que `depends_on_s` detecta essa mudança. Numa DAG, o líquido é igual para todo `s` quando só se lê o efeito do push, e o teste documenta esse caso.
**Pronto quando:** os três exemplos informam se algum veredito depende de `s`. O resultado vai para a tabela de números do manuscrito (E8).

---

## Fase E2 — Validação do Sri Lanka fora da amostra (ponto 2)

**Situação atual:** em `data-raw/gnanapragasam2026_build.R`, os betas dos auxílios (R1→D3, R2→D3) são ajustados por mínimos quadrados ao esforço observado de **2006–2021** (R² = 0,93). A janela 0 é 2004. Os outros "acertos" (B_MSY em 2012, 307 kt, E_MEY) comparam o app com saídas do modelo bioeconômico do artigo. É consistência entre modelos, não validação com dados.

### E2.1 — Separar calibração e teste
**O que fazer:**
- Criar `analysis/validation_srilanka/validate.R`, reaproveitando `calibrate_aid()` do build (extrair a função para `analysis/validation_srilanka/calibrate.R` ou para um `R/` interno, sem duplicar código).
- Calibrar em 2006–2014 e prever 2015–2021 com os betas congelados.
- Métricas fora da amostra: R², RMSE, viés médio, NSE (Nash–Sutcliffe) e erro no ano de pico ou platô.
- Comparar com duas referências ingênuas: persistência (esforço de 2014 constante) e tendência linear de 2006–2014. O modelo precisa superar as duas para que "validated" se sustente.
- Fazer a validação com origem móvel (E-b) e reportar as métricas por origem.
**Saídas:**
- `analysis/validation_srilanka/out/metrics.csv`;
- `analysis/validation_srilanka/out/fig_validation.png` e `.svg`, com observado, ajuste em 2006–2014 e previsão em 2015–2021 com banda.
**Pronto quando:** as métricas estão geradas e registradas no `CLAUDE.md`, com um parágrafo honesto do resultado, bom ou ruim.

### E2.2 — Incerteza da previsão
**O que fazer:** propagar a faixa dos betas calibrados (erro-padrão do ajuste) e das demais arestas, reamostradas como em `sufficiency_confidence()`, para obter uma banda de 90% da previsão de 2015–2021. Reportar a cobertura: a fração dos anos observados que cai dentro da banda.

### E2.3 — Separar as duas comparações no texto e no tutorial
**O que fazer:**
- No tutorial e no build, rotular como **"consistência com o modelo bioeconômico"** as comparações com as saídas do artigo (B_MSY, estoque, E_MEY).
- Rotular como **"validação"** só a comparação fora da amostra com o esforço observado.
**Testes:** `test-example-gnanapragasam` (criar, se não existir) fixa as métricas de E2.1 com tolerância de 1e-3.
**Pronto quando:** o manuscrito pode dizer "calibrated on 2006–2014 and tested on 2015–2021 (R² = …)" com o número saindo do script.

---

## Fase E3 — Incerteza estrutural (ponto 5)

### E3.1 — Presença/ausência de arestas na reamostragem
**Motivação:** a literatura citada (Crozier et al., 2025; Tam et al., 2025) mostra que a estrutura pesa mais que a magnitude.
**O que fazer:** em `sufficiency_confidence()` e `prediction_reliability()`, acrescentar o argumento `structural = FALSE`. Com `TRUE`, cada aresta fica ausente no sorteio com probabilidade `p_absent`:
- `evidence_type = expert` ou sem referência: 0,2;
- `literature`: 0,1;
- `regression`, `calibration` ou `definition`: 0.

Os valores ficam num `data.frame` configurável (`structural_absence_defaults()`). Sorteios com ρ(B) ≥ 1 continuam descartados e declarados.
**UI:** checkbox "Include structural uncertainty (links with weaker evidence may be absent)" ao lado do número de simulações. Gravar no `scenario_state`.
**Testes:** com todas as arestas `definition`, o resultado é idêntico a `structural = FALSE`. Com uma única aresta crítica `expert`, a confiança cai para cerca de 80%.

### E3.2 — Variante do Sri Lanka sem auxílio → frota (A-3)
**O que fazer:** criar `data-raw/gnanapragasam2026_variant_build.R`, que gera `docs/example_gnanapragasam_noaidfleet.idpsir.json`. Na variante, o alcance cai e a reversão desaparece. Reportar como teste de hipótese causal e como exemplo de incerteza estrutural.
**Pronto quando:** as duas opções aparecem na tela, no relatório e no script E8.

---

## Fase E4 — Índice de prioridade: justificativa e sensibilidade (ponto 7)

### E4.1 — Forma aditiva como alternativa
**O que fazer:**
- Em `impact_prioritization()`, acrescentar `aggregation = c("multiplicative", "additive")`.
- Forma aditiva: relevância = w_v·v + w_D·D + w_ρ·ρ, com pesos iguais por padrão; prioridade = relevância × gap.
- Justificar o produto no cabeçalho de `relevance.R`: prioridade como perda esperada evitável (valor × tamanho × probabilidade de o sinal estar certo × fração não coberta). Um zero anula de propósito: um Impacto não afetado não tem prioridade.
**Testes:** as duas formas dão a mesma ordem quando v, D e ρ são iguais entre Impactos.

### E4.2 — Robustez da ordem de prioridade
**O que fazer:** criar `priority_robustness(g, p_D, suff_df, n = 500, seed = 42)`.
- Perturbar v em ±20%, uniforme e truncado em [0, 1].
- Alternar entre a forma multiplicativa e a aditiva.
- Reportar: a frequência com que cada Impacto fica em 1º lugar e o tau de Kendall médio contra a ordem-base.
- Mostrar em "Impact prioritization" como uma coluna "Rank stability".
**Pronto quando:** o Porto e Mangi têm a estabilidade da ordem reportada no relatório e em E8.

### E4.3 — Depositar a especificação de relevância
**O que fazer:** atualizar o PDF (A-5) e depositá-lo no Zenodo junto com o release (A-1), para que o artigo possa citá-lo.

---

## Fase E5 — Experimento com redes DPSIR simuladas (ponto 4)

**Pergunta:** em redes DPSIR plausíveis, com que frequência o veredito de suficiência e a prioridade dos Impactos mudam entre a rede crua (só estrutura e sinais) e a rede parametrizada? Quais parâmetros e quais propriedades da rede explicam as mudanças?

**Estrutura de pastas:** `analysis/sim_networks/` com `PREREGISTRO.md`, `generate.R`, `run.R`, `analyze.R`, `out/` e `README.md`. Tudo chama o núcleo do app (`R/structural.R`, `sufficiency.R`, `relevance.R`, `triggers.R`, `temporal.R`) via `source()`, **sem reimplementar o motor**.

### E5.1 — Pré-registro
Escrever e commitar **antes** de rodar:

**Hipóteses:**
- **H1:** a fração de vereditos que mudam entre a rede crua e a parametrizada é moderada (< 30%) quando só as forças das arestas variam.
- **H2:** limiares de Estado e crescimento aumentam essa fração mais do que as forças das arestas (a ordem "limiares e crescimento primeiro" do manuscrito).
- **H3:** redes com laços I→R→P mudam mais vereditos que redes acíclicas.
- **H4:** Impactos perto da neutralização na rede crua (|líquido| / piora < 0,2) concentram as mudanças.
- **H5:** a ordem de prioridade é mais estável que os vereditos (tau de Kendall > 0,7).

**Desfechos primários:**
- mudança de veredito por Impacto (neutralized / partial / not neutralized / worsened / not affected);
- mudança do Impacto de maior prioridade;
- tau de Kendall da ordem de prioridade.

**Análise pré-definida:** proporções com IC 95% (bootstrap por rede), regressão logística de "mudou" contra as propriedades da rede (efeitos aleatórios por rede, `glmer`) e floresta aleatória (`ranger`) com importância por permutação.

### E5.2 — Gerador de redes DPSIR (`generate.R`)
**O que fazer:** `generate_dpsir_network(seed, spec)`, que devolve `nodes` e `edges` no formato do app.
- **Tamanho por nível:** sorteado de distribuições ancoradas nos exemplos e na literatura. D ∈ 2–5, P ∈ 2–6, S ∈ 2–6, I ∈ 2–6, R ∈ 1–5, de 10 a 25 nós no total.
- **Arestas:** só as permitidas por `schema_allowed_connections()`. A densidade de cada par de níveis é sorteada em [0,15; 0,5]. Garantir que todo Impacto seja alcançável por algum Driver e que toda Resposta tenha pelo menos um alvo. **Sem Estado → Estado** (regra de simplificação).
- **Sinais:** pela convenção da Tabela 3 do manuscrito. Uma fração de 10–20% de exceções coerentes por nó (orientação invertida do Estado) testa a robustez.
- **Laços:** com probabilidade q ∈ {0; 0,3; 0,6}, criar arestas I→R que fecham ciclos I→R→P/D.
- **Forças (rede parametrizada):** β sorteado de uma mistura de classes weak/moderate/strong, ou contínuo em (0; 0,9). Reescalar para Σβ² < 1 por nó alvo e **rejeitar** redes com ρ(B) ≥ 1, registrando a taxa de rejeição.
- **Limiares:** com probabilidade 0,3 por Estado, um `threshold_level` em z ∈ [0,2; 1,5] com direção coerente.
- **Crescimento:** com probabilidade 0,3 por Driver, g ∈ [0,01; 0,05] por janela, com teto opcional.
- **Valores v:** Impactos com `endpoint_class` sorteada e v ∈ [0,2; 1] para service/welfare.
- **Cenários:** pressão com todos os Drivers a 100%. Resposta com um subconjunto aleatório de Respostas, com força em [25%; 150%].

**Testes (`analysis/sim_networks/tests/test-generator.R`):**
- toda rede gerada passa em `validate_*()` e `check_effect_matrix()`;
- a mesma semente produz a mesma rede;
- não há aresta proibida pelo esquema.

### E5.3 — Condições comparadas (`run.R`)
Para cada rede, avaliar o mesmo cenário em cinco condições:

| Condição | Forças | Limiares | Crescimento | Leitura |
|---|---|---|---|---|
| C0 crua | todas "moderate" (0,45), igual ao `first_run_build.R` | não | não | estática |
| C1 forças | β sorteados | não | não | estática |
| C2 + limiares | β sorteados | sim | não | estática com gatilho |
| C3 + crescimento | β sorteados | sim | sim | temporal, veredito na janela T = 20 |
| C4 incerteza | C1 + `sufficiency_confidence()` e `structural = TRUE` (E3) | — | — | confiança |

- Registrar por Impacto: piora, mitigação, líquido, veredito, força necessária, prioridade e ordem.
- Registrar por rede: n de nós, densidade, n de ciclos, comprimento médio dos caminhos D→I, ρ(B), fração de Impactos alcançados pelas respostas e n de Estados com limiar.
- **Tamanho:** 1000 redes × 20 sorteios de β, ou seja 20.000 avaliações por condição. Estimar o tempo com 50 redes antes e ajustar. Paralelizar com `future.apply`, com semente por rede (`seed = 1000 + i`).
- **Saída:** `out/results.parquet`, ou `.csv.gz` se não houver `arrow`.

### E5.4 — Comparação com a leitura só de sinais (opcional, recomendado)
Para as redes estáveis no sentido de Levins, calcular a previsão de sinal de −A⁻¹ com pesos aleatórios, à maneira do QPress (fração de sorteios com o mesmo sinal). Comparar a determinação de sinal com a confiabilidade ρ do iDPSIR. Isso conecta o experimento a Reum et al. (2020) e responde a um revisor da comunidade de modelos qualitativos. Implementar com o núcleo do app; não depender do pacote QPress.

### E5.5 — Análise e figuras (`analyze.R`)
**Figuras:**
- **(a)** Taxa de mudança de veredito C0→C1, C1→C2 e C2→C3, com IC 95%.
- **(b)** Taxa de mudança contra a distância à neutralização na rede crua (H4).
- **(c)** Importância das propriedades da rede (floresta aleatória).
- **(d)** Estabilidade da prioridade (tau de Kendall).

**Tabela:** coeficientes da regressão logística.

**Resumo em texto:** `out/summary.md`, com H1–H5 marcadas como confirmada, refutada ou inconclusiva.

**Pronto quando:** o pipeline roda de ponta a ponta com um comando (`Rscript analysis/sim_networks/run_all.R`), é reprodutível pela semente e gera figuras e tabela prontas para o manuscrito (nova §4.4 ou seção própria).

---

## Fase E6 — Teste de usabilidade (ponto 8)

O Claude Code prepara os materiais, a instrumentação e a análise. **A coleta é feita pelos autores**, depois da consulta ao CEP (E-d).

### E6.1 — Protocolo e materiais (`analysis/usability/`)
- `PROTOCOLO.md`:
  - objetivo e desenho: sessão individual de 60 min, remota ou presencial, com observador;
  - critérios de inclusão;
  - n = 12–16 (E-e);
  - roteiro do moderador e tratamento dos dados, que são anonimizados.
- `TCLE.md`: termo de consentimento, adaptado ao modelo do CEP da UNIFESP.
- `tarefas.md`: tarefas cronometradas, usando uma rede nova e não um dos exemplos, para não favorecer quem leu o tutorial.
  - **T1:** a partir de uma descrição curta (um problema costeiro com 8 fatores), construir a rede no assistente.
  - **T2:** montar o cenário de pressão e o de resposta e ler se cada Impacto é neutralizado.
  - **T3:** responder a três perguntas de decisão pela aba Interpretation, por exemplo "qual Impacto priorizar?" e "com que força a resposta X basta?".
  - **T4:** salvar o savepoint, reabrir e gerar o relatório.
- `questionario.md`:
  - **SUS**, System Usability Scale, 10 itens (Brooke, 1996), em versão em português **validada**; o Claude Code deve localizar a referência da tradução e registrá-la;
  - 3 perguntas de compreensão do resultado, com gabarito;
  - 3 perguntas abertas;
  - perfil do participante (formação, experiência com DPSIR e com modelagem).

### E6.2 — Modo de estudo no app (instrumentação local)
**O que fazer:**
- Com `?study=1` na URL, o app registra só no navegador: timestamps de entrada e saída de cada passo do assistente, erros de validação mostrados, cliques em "Build" e "Apply scenario", e tempo até o primeiro resultado.
- Ao final, um botão "Download session log (JSON)". O participante envia o arquivo ao pesquisador **por decisão própria**.
- Nada é enviado a servidor e nada é gravado sem o modo ligado.
**Arquivos:** `R/modules/mod_wizard.R` (observadores), um módulo pequeno `mod_study.R` e `www/study.js`, se necessário.
**Testes:** sem `?study=1` nada muda e nenhum input novo aparece. Com o modo ligado, o JSON tem os campos esperados.
**Pronto quando:** o log é gerado no app local e na demo shinylive.

### E6.3 — Análise (`analysis/usability/analyze.R`)
- Calcular o escore SUS (0–100) por participante e por grupo, com média, IC e comparação com o benchmark de 68.
- Calcular por tarefa: taxa de sucesso, tempo e erros.
- Calcular o acerto das perguntas de compreensão, que é o dado mais forte para "interpretable by non-specialists".
- Codificar as respostas abertas por tema.
- Saída: tabela e figura para o manuscrito, e `out/summary.md`.

**Pronto quando:** protocolo, TCLE, tarefas, questionário, modo de estudo e script de análise estão prontos, com um piloto interno (1 ou 2 pessoas do laboratório) e ajustes feitos.

---

## Fase E7 — Protocolo de busca de ferramentas (ponto 6)

**O que fazer:** criar `analysis/tool_search/PROTOCOLO.md` e `tabela_ferramentas.csv`.
- **Fontes:** Web of Science, Scopus, Google Scholar, CRAN task views, GitHub e as revistas *Environmental Modelling & Software* e *Methods in Ecology and Evolution*.
- **Termos:** combinações de DPSIR, DAPSI(W)R(M), causal network, qualitative network, loop analysis, fuzzy cognitive, Bayesian network, decision support, Shiny, software e tool.
- **Critério de inclusão:** ferramenta **disponível** (código ou aplicativo) que modela redes causais em sistemas socioecológicos.
- Registrar a data da busca.
- Para cada ferramenta, preencher as 9 colunas da Tabela 1 **com a fonte de cada célula**. Incluir QPress, LoopAnalyst, Mental Modeler, Netica ou GeNIe, shinyBN, DAGitty, Ecopath with Ecosim, Vensim ou Stella (DPSIR + dinâmica de sistemas) e a ferramenta do modelo de medidas do Báltico (Ahtiainen et al., 2025), se estiver disponível.
- Corrigir as células da Tabela 1 que a busca contradisser. Revisar a linha do QPress em "Response sufficiency", já que o QPress avalia cenários de manejo como press.

**Pronto quando:** a tabela tem fonte para cada célula e o manuscrito pode dizer "we found no openly available tool that… (search protocol in Supplement S5)".

---

## Fase E8 — Script único de números e figuras (A-2 ampliado)

**O que fazer:** criar `data-raw/manuscript_build.R`, que gera tudo o que o manuscrito cita:
- casos Porto, Mangi e Sri Lanka, crus e parametrizados;
- sensibilidade a `s` (E1.4);
- validação fora da amostra (E2);
- confiança com e sem incerteza estrutural (E3);
- robustez da prioridade (E4.2);
- resultados das redes simuladas (lendo `analysis/sim_networks/out`, sem rodar de novo);
- resultados de usabilidade (lendo `analysis/usability/out`).

Saídas em `manuscrito_v5/build/`: um CSV por tabela, PNG a 300 dpi e SVG por figura, e `numeros.json` com cada número citado no texto.

**Teste:** `tests/testthat/test-manuscript-numbers.R` compara `numeros.json` com os valores congelados. Uma mudança no motor que altere um número citado quebra o teste.
**Pronto quando:** um comando regenera tudo e o teste passa.

---

## Fase E9 — Depois do código: manuscrito (fora do Claude Code ou com a skill de docx)

Na ordem:
1. Reescrever as Seções 2–4 (M3–M5) com os números de E8, incluindo:
   - uma **§3 com o modelo formal**: equações, premissas, mapeamento força → p, equivalência com Levins e convergência × estabilidade;
   - uma **seção nova de redes simuladas**;
   - o **teste de usabilidade**.
2. Ajustar o Resumo e a Discussão aos resultados reais (H1–H5, SUS, validação).
3. Acrescentar Code/Data availability, Acknowledgements, Funding, Competing interests, CRediT e a **declaração de uso de IA** (rascunho na revisão).
4. Release v1.0.0 com DOI no Zenodo (A-1) e material suplementar S1–S5.
5. Rodar de novo a `/top-journal-review` na versão 6.

---

## Ordem sugerida e dependências

1. **E1** (1–2 dias). Premissas; muda comentários, testes e duas funções novas.
2. **E2** (1–2 dias). Independente de E1; pode rodar em paralelo.
3. **E5.1–E5.2** (2 dias). Pré-registro e gerador. Commitar o pré-registro antes de E5.3.
4. **E3 e E4** (2 dias). Precisam estar prontos antes de E5.3, que usa `structural = TRUE` e a prioridade.
5. **E5.3–E5.5** (3–5 dias, mais tempo de máquina).
6. **E6.1–E6.2** (2 dias). Em paralelo com E5; a coleta depende do CEP e pode levar semanas, então começar a consulta **já**.
7. **E7** (1 dia). Pode ser feito a qualquer momento.
8. **E8** (1–2 dias). Depois de tudo o que gera números.
9. **E9.**

## Checklist final

- [ ] `Rscript tests/testthat.R` passa, incluindo `test-equivalence.R` e `test-manuscript-numbers.R`.
- [ ] O app sobe localmente e na demo shinylive, e `analysis/` não entra no bundle.
- [ ] `analysis/sim_networks/PREREGISTRO.md` foi commitado antes de `out/results.*`; conferir as datas no git.
- [ ] A validação fora da amostra está registrada e o texto usa "validated" só se o modelo superar as duas referências ingênuas.
- [ ] Protocolo de usabilidade aprovado ou dispensado pelo CEP, com o parecer arquivado.
- [ ] Cada célula da Tabela 1 tem fonte (E7).
- [ ] As decisões E-a a E-f estão registradas no `CLAUDE.md`.
