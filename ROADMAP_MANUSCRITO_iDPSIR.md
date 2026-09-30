# Roadmap — Manuscrito iDPSIR após a Revisão 2

**Objetivo:** alinhar o manuscrito (`MANUSCRIPT_full_4.docx`, "iDPSIR: an interactive app to
construct and analyze DPSIR causal networks", Fonseca & Davanso) ao app como está na branch
`revisao2-exemplo-porto` (commit `136e2f5`), antes de mesclar em `main` e submeter.

**Diagnóstico em uma frase:** o manuscrito descreve o motor da Revisão 1 — pesos relativos com
"confiança", fator de alcance *c* com λ = c/ρ(W), sensibilidade ao alcance, atributos
`uncertainty`/`controllability`/`activation_threshold` — e três exemplos (pescas mínimo, Mangi
com 18 nós, Sri Lanka com 13 nós) que **não existem mais nessa forma**. O motor atual é outro
(β padronizado, efeito total da análise de caminhos, gatilhos, relevância/prioridade, simulação
temporal com modos e crescimento) e os exemplos foram refeitos a partir dos artigos. Quase todas
as seções 2–5 e todas as tabelas/figuras de resultados precisam ser reescritas; a introdução e a
discussão mudam em pontos específicos.

Convenções: **[M]** = mudança no manuscrito; **[A]** = trabalho no app/repositório necessário
para o manuscrito. Os números citados vêm das execuções desta sessão e servem de guia; os
definitivos devem sair do script de M0.2.

---

## Decisões a confirmar antes de escrever

| # | Decisão | Recomendação |
|---|---|---|
| M-a | O exemplo mínimo de pescas (5 nós) sai do artigo? | **Sim.** Foi feito no modo de pesos antigo, hoje é só fixture de compatibilidade. O porto assume o papel de exemplo didático, com uma mensagem mais útil (priorizar respostas e o período de cada uma). |
| M-b | Ordem dos casos | **Porto → Mangi → Sri Lanka**, em complexidade crescente: (1) estrutura + relevância/prioridade + períodos; (2) rede publicada + cumprimento + crescimento; (3) parametrização completa + validação contra dados + gatilho por acúmulo. |
| M-c | A comparação "rede crua × parametrizada" entra como? | **Um parágrafo em cada caso** (Mangi e Sri Lanka) **mais uma tabela-síntese** (§4.4) e um parágrafo na Discussão. É a mensagem mais forte para quem usa pela primeira vez: no Mangi a estrutura decide; no Sri Lanka os parâmetros invertem a resposta. |
| M-d | Manter o contraste do Sri Lanka "auxílio desacoplado × acoplado à frota" (Tabela 6 atual)? | **Opcional.** A rede atual já é a acoplada (auxílio → capacidade da frota, calibrado com o esforço observado). O contraste vira um teste de hipótese causal numa variante sem as ligações auxílio → frota (ver A-3). É um bom argumento, mas pode ficar para o material suplementar. |
| M-e | Revista-alvo e extensão | Define quanto dos Métodos vai para o suplemento. Com três casos e o novo bloco de relevância, o texto cresce: considerar mover as equações do temporal e da relevância para um Apêndice. |
| M-f | Fonte do exemplo do porto | O app diz "adaptado de uma tabela de avaliação de impacto ambiental portuária". **É preciso a referência** (EIA/RIMA, relatório) ou declarar como exemplo hipotético construído pelos autores. |

---

## Fase M0 — Pré-requisitos no app e no repositório [A]

- **A-1. Mesclar e publicar.**
  - Mesclar as branches da Revisão 2 em `main`.
  - Conferir a demo shinylive no Pages; os arquivos novos são `R/interpretation.R`, `R/relevance.R`, `R/triggers.R`, `R/structural.R` e os savepoints novos.
  - Criar o release `v1.0.0` com DOI (Zenodo) e atualizar `CITATION.cff` e `DESCRIPTION`.
  - O manuscrito cita a versão e o DOI em "Software availability".
- **A-2. Script único de números e figuras do artigo** (`data-raw/manuscript_build.R`).
  - Parte dos savepoints publicados e gera cada tabela (CSV) e figura (PNG 300 dpi + SVG) do texto.
  - Um teste (`test-manuscript-numbers.R`) fixa os números citados, para o artigo nunca divergir do app.
  - Hoje os números estão espalhados entre o tutorial e os testes dos exemplos.
- **A-3. (Se M-d)** Variante do Sri Lanka sem auxílio → frota, para o teste da hipótese causal, gerada em `data-raw/`.
- **A-4. Material suplementar:**
  - os savepoints (`example_port`, `example_mangi`, `example_mangi_default`, `example_gnanapragasam`, `example_gnanapragasam_default`);
  - o relatório HTML de cada cenário usado no texto;
  - `gnanapragasam2026_parameters.csv` e `_effort_observed.csv`;
  - os scripts `data-raw/`.
- **A-5.** Atualizar o PDF da especificação de relevância (seções 4 e 7.4, V5 com eficácia = cobertura), que o manuscrito passa a citar.
- **A-6.** Resolver M-f (fonte do porto) e registrar no `descriptor` e no tutorial.

---

## Fase M1 — Título, resumo e palavras-chave [M]

- **Resumo — trocar:**
  - "discounted sum of paths / well-defined for any network" → **efeito total de uma rede de coeficientes de caminho padronizados (β)**, (I − B)⁻¹p − p, definido quando ρ(B) < 1 (o app verifica);
  - "resampling each edge within its stated confidence" → **reamostragem de cada β dentro da sua faixa de incerteza**.
- **Resumo — acrescentar:**
  - **relevância e prioridade dos Impactos** (valor, importância, confiabilidade, lacuna);
  - a **simulação temporal** com modos de pressão/resposta, crescimento e gatilhos de Estado;
  - a **leitura interpretativa** (aba Interpretation, relatório).
- **Resumo — casos:** "porto (didático), recife do Quênia (Mangi 2007, refeito dos indicadores do artigo), pesca do Sri Lanka (parametrizada e validada contra 32 anos de esforço)", mais a comparação rede crua × parametrizada.
- **Palavras-chave:** acrescentar *path analysis*, *prioritization*; considerar retirar *loop analysis*, que deixou de ser o motor.

---

## Fase M2 — Introdução [M]

- **§1–2:** sem mudança de fundo.
- **§3 (análise de loops):** manter a crítica (estabilidade, inversão de sinal) e acrescentar a ponte: o iDPSIR adota a **análise de caminhos** (Wright 1921; Grace 2006; Shipley 2016). Hoje essa ponte está só na Discussão; ela é a base do motor e deve aparecer já na Introdução.
- **Tabela 1, linha do iDPSIR:**
  - Method: "static sufficiency on standardized path coefficients + reach + relevance/priority + optional temporal";
  - Uncertainty: "neutralization confidence and prediction reliability (β band resampling)";
  - remover "reach-sensitivity".
- **§4 (apresentação do iDPSIR):**
  - reescrever o modelo;
  - trocar "equivalent to loop analysis restricted to its convergent regime" por **efeitos totais de path analysis**, lembrando que, com coeficientes padronizados, o efeito total coincide com a leitura de Levins (D14);
  - acrescentar priorização e interpretação.
- **§5 (casos):** nova ordem e novas mensagens (M-b).

---

## Fase M3 — Descrição do software (§2) [M]

- **2.1 Visão geral.**
  - Núcleo atual: `structural.R`, `sufficiency.R`, `triggers.R`, `relevance.R`, `temporal.R`, `interpretation.R`, `reach.R`, `pathways.R`, `metrics.R`, `graph.R`, `io.R`, `validate.R`.
  - Módulos: `mod_data`, `mod_graph`, `mod_responses` (Scenarios e Interpretation), `mod_metrics`, `mod_report`, `mod_wizard`.
  - Código fora de uso em `legacy/`.
  - Dependências segundo o `DESCRIPTION`: shiny, bs4Dash, visNetwork, igraph, DT, dplyr, data.table, htmlwidgets, shinyWidgets, glue, purrr, scales, jsonlite, htmltools. `data.table` é usado na importação; `shinyWidgets` não aparece com prefixo no código, então confirmar se ainda é necessário antes de citar.
- **2.2 Fluxo guiado.**
  - Seis passos, ainda válido.
  - **Model:** papéis dos níveis (D/P/S/I/R ou personalizado, p.ex. sub-driver), inserir na posição e remover nível vazio.
  - **Nodes:** campos condicionais (limiar só em Estado; classe/valor e *swing weights* só em Impacto).
  - **Edges:** classe ou valor β, faixa, atalho r²/n.
  - **Review:** checa ρ(B) < 1 (bloqueia) e soma de β² que chegam a um fator (avisa).
  - **Explore:** **cinco abas**.
- **Figura 1:** redesenhar (cinco abas; núcleo com os arquivos novos; savepoint com cenários salvos).
- **2.3 Modelo de dados — Tabela 2 reescrita:**
  - Esquema: níveis, ordem, **papel**.
  - Nó:
    - `category`, `subsystem`, `descriptor`;
    - `self_regulation` [0,1] (padrão 0,5);
    - `growth_rate` e `growth_cap`;
    - `reference_value` e `sd` (camada de medida);
    - `threshold_level` e `threshold_direction` (Estado);
    - `endpoint_class` e `value_v` (Impacto).
  - Aresta:
    - `interaction_type` (obrigatório);
    - `weight` (β), `weight_low`/`weight_high`, `strength_class` (weak/moderate/strong = 0,15/0,45/0,80);
    - `evidence_type`, `reference`.
  - **Retirar:** `uncertainty`, `controllability`, `activation_threshold`, `confidence`. A confiança passa a ser derivada da faixa e é só visual.
  - Mencionar a conversão automática de arquivos antigos (β = λ·w, D13/D19).
- **2.3, novo parágrafo — regra de simplificação para monitoramento** (decisão do autor, exemplo do Mangi): o DPSIR serve para monitorar e gerir, não para retratar todas as interações.
  - Dois indicadores em cadeia causal não são ambos monitorados.
  - Por isso não há ligação Estado → Estado.
  - Quando um mecanismo passa por outro Estado, ele vira uma pressão paralela ligada ao Estado a monitorar (a pesca do peixe-porco → densidade de ouriço).
- **2.4 Ambiente de análise:**
  - Graph, **Scenarios**:
    - pressão/resposta com força em % ou unidades;
    - suficiência, confiança por resposta, gatilhos, prioridade, alcance topológico e efetivo;
    - temporal; cenários salvos.
  - **Interpretation:** leitura em texto, gráfico de cobertura, comparação de cenários.
  - Metrics, Report.
  - **Cenário mostrado único**, com seletores sincronizados.
- **2.5 Reprodutibilidade:**
  - o savepoint guarda também os **cenários salvos** (definições, recalculados ao carregar) e as configurações temporais;
  - CI com testes em todo push;
  - `renv.lock`;
  - semente local fixa (`with_local_seed`);
  - `CITATION.cff`; DOI do release.

---

## Fase M4 — Métodos (§3) [M]

- **3.1 Representação.**
  - Grafo assinado; **aresta = coeficiente de caminho padronizado β** com faixa de incerteza.
  - Classes como padrão qualitativo; r²/n como atalho (β = √r², faixa do erro-padrão).
  - Convenção de sinais e Tabela 3: manter, conferindo a linha R → I (−).
  - Manter a nota sobre a orientação do Estado. O exemplo da exceção muda: no Sri Lanka atual, *Fleet motorization* continua orientado "mais é pior".
- **3.2 Suficiência — reescrever as equações:**
  - B = matriz de efeitos diretos (β com sinal), sem diagonal;
  - efeito total Φ(p) = (I − B)⁻¹p − p = Σₖ≥₁ Bᵏp, definido se **ρ(B) < 1**;
  - com coeficientes padronizados e Σβ² < 1 por fator isso é o caso usual, e o app bloqueia se não for;
  - duas pressões superpostas: piora, mitigação, líquido, neutralizado (≤ 0);
  - força necessária em forma fechada, por linearidade;
  - com gatilho, por bissecção até ×10⁴;
  - **"Not affected"** quando a pressão não alcança o Impacto;
  - **retirar c, λ e toda a §3.2.2 (sensibilidade ao alcance)**, que não existe mais.
- **3.2.1 Confiança de neutralização:**
  - cada β é sorteado uniformemente na sua faixa (N = 300 padrão, 100/1000 opcionais, semente 42);
  - sorteios com ρ(B) ≥ 1 são descartados e declarados; todos descartados = "not computable";
  - acrescentar a **linha do cenário planejado** e as linhas de cada resposta sozinha a 100%.
- **3.3 (nova) Gatilhos de Estado:**
  - limiar em unidade real → z = (nível − referência)/DP;
  - portão binário: todas as arestas de saída ligam/desligam juntas (D7/D8);
  - leitura estática iterada em ciclos;
  - neutralização "por fechamento do gatilho";
  - alcance efetivo (não atravessa gatilho fechado).
- **3.4 (nova) Relevância e prioridade dos Impactos**, pela especificação v1.0 (citar o PDF de A-5):
  - `endpoint_class` e valor v, com *swing weights* para *service/welfare*;
  - importância D (efeito total normalizado pelo máximo, = Levins padronizado);
  - confiabilidade ρ (preservação do sinal na reamostragem);
  - relevância = v·D·ρ; lacuna = max(0, net)/piora; prioridade = relevância × lacuna.
- **3.5 Alcance:** topológico e efetivo, lado a lado (D12).
- **3.6 Simulação temporal — reescrever a eq. (9):**
  - dev(t+1) = (1 − s)·dev(t) + B·x(t) + p(t), com x = dev + tendência;
  - tendência de crescimento no nível de base, igual nas duas rodadas, com teto opcional;
  - modos **permanent / impulse / window** (início e duração por fator);
  - parada "até neutralizar" com tolerância relativa (padrão 5%; 0 = só zero) e "continuar N janelas";
  - critério do gatilho: nível acumulado (padrão) × carga da janela;
  - camada de medida (níveis em unidade real, janela em que o limiar é cruzado);
  - intensidade das arestas por janela;
  - autorregulação: um fator se assenta em β/s;
  - aviso de laço de reforço;
  - **retirar** o `stability_cap` e o `activation_threshold` como descritos.
- **3.7 (nova) Leitura interpretativa:** regras de status por Impacto (neutralizado, parcial com % coberto e força necessária, não coberto, piorado pela resposta, não afetado), limiares de "frágil" (20–80%) e "confiável" (≥ 80%), mensagens-chave. Deixar claro que são regras de apresentação, não modelo.
- **3.8 Implementação e reprodutibilidade:** era a 3.5; atualizar como em 2.5.

---

## Fase M5 — Resultados (§4), reestruturados [M]

Para cada caso: estrutura e fontes → cenários → suficiência e prioridade (aba Interpretation) → temporal → **rede crua × parametrizada**. Todas as figuras e tabelas saem de A-2.

### 4.1 Porto (didático): priorizar respostas e o período de cada uma
- **Rede:** 15 nós, 20 ligações, janela = estação; dois grupos de Impactos (turbidez e metais), valores v por *swing weights*.
- **Sequência de priorização:**
  - só boas práticas → prioridade: contaminação do pescado (0,90), depois fauna (0,52);
  - com o tratamento de escoamento → fauna (0,43);
  - com a janela ambiental → nenhum.
- **Mensagem:** a produção primária piora tanto quanto a fauna, mas fica por último (0,21) porque pesa menos (v = 0,4).
- **Temporal:**
  - a janela ambiental só durante a dragagem basta (pico de 0,29 contra 1,55 sem resposta);
  - o tratamento que começa tarde deixa a contaminação em ~10 (≈ 0,1 quando começa cedo).
- **Figuras:** rede; prioridade (passos 1–3); temporal dos cenários 3 e 4.

### 4.2 Recife do Quênia (Mangi et al. 2007): cumprimento e crescimento
- **Rede refeita dos indicadores do artigo** (Tabela 1, §3–6): 22 fatores, 33 ligações, cada uma citando a seção do artigo.
  - Regra de simplificação: esforço de pesca geral; pesca do peixe-porco → ouriço; sem Estado → Estado.
  - Classes com Σβ² < 1 por fator; único parâmetro: crescimento populacional de 3,7%/ano.
  - Respostas existentes em 2007 e recomendadas; barreiras como força da resposta.
- **Substitui a rede de 18 nós:** a Tabela 5 e as Figuras 3–4 atuais saem.
- **Cenários (pressão: população, pobreza, desemprego, aquecimento):**
  - existentes como escritas → 0 de 3 (captura ×1,18; meios de vida ×1,19; conflitos ×12);
  - como cumpridas a 30% → 0 de 3;
  - + recomendadas → 1 de 3 (conflitos);
  - todas cumpridas → 3 de 3.
  - Mensagem: **o que falta é cumprimento, não a escolha das medidas**; os parques sozinhos pioram os conflitos (efeito colateral); o aquecimento fica fora de qualquer alcance.
- **Temporal (30 anos):** tudo cumprido neutraliza por ~20 anos; conflitos voltam no ano 21, captura no 27, pelo crescimento populacional.
- **Rede crua × parametrizada:** vereditos e prioridade coincidem (conflitos no topo); os parâmetros mudam tamanhos (captura e meios de vida indistinguíveis na rede crua; nela as medidas pioram os conflitos) e dão o prazo (sem crescimento, neutraliza para sempre).
- **Tabelas/figuras:** rede; cenários × Impactos (tabela da aba Interpretation); cobertura; temporal do cenário 4; comparação crua × parametrizada.

### 4.3 Pesca do Sri Lanka (Gnanapragasam et al. 2026): o auxílio que virou pressão
- **Rede:** 17 fatores, 20 ligações, janela = ano desde 2004, parametrizada do artigo:
  - esforço digitalizado da Fig. 4;
  - estoque de Gordon-Schaefer com limiar B_MSY;
  - auxílios calibrados contra o esforço observado (R² = 0,93);
  - crescimento de população, demanda (com teto) e frota;
  - cota de esforço de 25%.
- **Substitui a rede de 13 nós:** a Tabela 6 e as Figuras 5–6 atuais saem ou viram o teste de M-d.
- **Validação contra o artigo:**
  - o estoque cai abaixo de B_MSY em 2012;
  - 307 kt em 2021 (≈ 321);
  - com a cota, esforço de 12.470 em 2030 (E_MEY = 12.287) e estoque de 406 kt (413).
- **História:**
  - renda: melhor que neutro em 2012, pior que sem auxílio em 2021, neutralizada em 2030 com cota + combate à pesca ilegal;
  - gatilho aberto por **acúmulo** (a leitura estática não vê piora nenhuma);
  - a cota mínima de 5% não basta.
- **Rede crua × parametrizada — a conclusão se inverte:**
  - a rede crua dá "Fisher income loss neutralizado; neutralizado na janela 4";
  - a parametrizada dá "nada piora num instante; 4 de 5 Impactos terminam piores que sem auxílio".
- **(M-d) Teste da hipótese causal:** sem as ligações auxílio → frota, o alcance cai e a reversão desaparece.

> **Tabela 1 (Revisão 3, E7):** ver `analysis/tool_search/` — acrescentar a linha de Bryhn et
> al. (2026, "Mind the GAP"), qualificar QPress (widgets Shiny; suficiência só de sinal) e FCM
> (In-Cognitive tem incerteza Monte Carlo), e reformular a novidade: não "a primeira avaliação
> de suficiência", mas "a primeira ferramenta aberta, sem instalação, que lê suficiência
> propagando efeitos numa rede causal com evidência e incerteza por ligação".
> **Ramos-Quintana et al. (2018)** (lido): precursor mais próximo — rede causal DPSIR com
> tendências combinadas por produto ao longo do caminho e soma entre caminhos (como o efeito
> total do iDPSIR), um único estado global com regiões de risco fuzzy e ações de gestão com
> pesos ordinais (1/2). Sem software, sem ciclos, sem incerteza reamostrada, sem leitura por
> Impacto: citar na Introdução e entrar na Tabela 1 como método sem software.

> **Aviso de veredito apertado (Revisão 3, após E5/H4):** a Interpretação e o relatório
> marcam o Impacto piorado cujo saldo fica a menos de 20% da piora e listam as 5 ligações
> que mais movem esse saldo (β + 10%), indicando as de força assumida (classe ou padrão).
> Citar na seção de interpretação como consequência direta de H4.

### 4.4 (nova) O que a parametrização acrescenta

> **Atualização (Revisão 3, E5):** o experimento com 1000 redes simuladas contradiz parte
> da ordem abaixo. Forças mudam 15,9% dos vereditos, limiares 18,9%, crescimento só 4,3%
> (ele move a linha de base e o cenário juntos), e trocar a leitura estática pela temporal
> muda 17,8%. A prioridade é **mais** sensível que o veredito (τ = 0,64; topo muda em 35%).
> Reescrever a mensagem: "comece pela estrutura; parametrize forças e limiares onde há
> evidência — eles mudam vereditos na mesma medida —, confira a prioridade com a
> estabilidade do rank; o crescimento importa para o *quando*, raramente para o veredito".
> O mesmo vale para o tutorial ("First run") e o README.
- Tabela-síntese dos dois casos (veredito, prioridade e resultado temporal, cru × parametrizado).
- Mensagem: **comece pela estrutura e pelos sinais**; depois parametrize na ordem de retorno:
  1. limiares e crescimento (podem inverter um veredito);
  2. classes onde a evidência diz "principal" ou "secundário" (mudam tamanhos e às vezes prioridades);
  3. por último, as configurações temporais.
- Compare sempre com a rede crua.

---

## Fase M6 — Discussão (§5) [M]

- **5.1 Ganhos:**
  - O 2º ganho (padronização) fica mais forte: a aresta **já é** um coeficiente de caminho, então a ponte com SEM/SCM deixa de ser analogia e vira continuidade (a rede pode ser estimada com dados sem mudar de objeto).
  - O 4º ganho ganha a priorização e a leitura interpretativa.
  - Casos citados: porto (prioridade e período), Quênia (cumprimento e prazo do crescimento), Sri Lanka (efeito indireto contraproducente, validado contra dados).
- **5.1, novo parágrafo — "estrutura primeiro, parâmetros depois"** (M-c): o que a rede crua já decide e o que só aparece com parâmetros.
- **5.2 Aplicabilidade:** citar os níveis personalizados (sub-drivers) e o porto como caso fora da pesca.
- **5.3 Limitações — reescrever:**
  - **retirar** a limitação do fator de alcance;
  - **acrescentar:**
    - linearidade e aditividade dos efeitos;
    - requisito ρ(B) < 1;
    - classes como padrão qualitativo;
    - gatilho binário;
    - simulação temporal explícita (sem equilíbrio) cuja leitura depende da autorregulação escolhida;
    - relevância dependente dos valores v elicitados;
    - limiares da leitura interpretativa convencionais;
    - a regra de simplificação (sem Estado → Estado) como escolha deliberada.
  - **Manter:** convenção de orientação, dependência da qualidade da rede.

---

## Fase M7 — Conclusões [M]
- Reescrever em torno de três frases:
  1. suficiência e prioridade num motor de path analysis;
  2. leitura temporal com modos, crescimento e gatilhos, validada num caso real;
  3. o fluxo "estrutura → parâmetros" como prática recomendada.
- Manter a ponte para a etapa orientada a dados.

---

## Fase M8 — Referências, suplementos e revisão final [M]

- **Referências:**
  - completar **Gnanapragasam, Ratnasiri & Fleming (2026), Marine Policy 189, 107095** (hoje é um marcador);
  - acrescentar a especificação de relevância (A-5), a referência de *swing weights* e a de Gordon-Schaefer usadas no Sri Lanka;
  - acrescentar a referência do porto (M-f);
  - Dzoga et al. (2020) só se citado.
- **Software availability:** URL do repositório, demo, versão, DOI (A-1), licença MIT, requisitos (R ≥ 4.1 no `DESCRIPTION`; testado em 4.5.1).
- **Suplementos (A-4):** S1 savepoints e relatórios; S2 confiança por resposta de cada caso; S3 parâmetros do Sri Lanka; S4 scripts.
- **Problemas já presentes no texto:**
  - falta a Tabela 4 (numeração 1, 2, 3, 5, 6);
  - "Figure 3b" (deveria ser 4b);
  - "netwrok";
  - "Neutralised"/"neutralized" misturados;
  - "Sup S2"/"Sup2";
  - referência do Gnanapragasam incompleta;
  - as equações (1)–(9) estão como objetos que não aparecem no texto extraído: reescrever todas no editor de equações.
- **Checklist final:** cada número do texto sai de A-2 e é verificado pelo teste; nomes de abas e botões batem com o app; a Figura 1 bate com os arquivos; o savepoint de cada figura está no suplemento.

---

## Anexo — o que o manuscrito diz × o que o app faz hoje

| Manuscrito (versão 4) | App atual (`136e2f5`) |
|---|---|
| Peso > 0 + confiança 0–1 | β padronizado + faixa; classes 0,15/0,45/0,80; confiança derivada, só visual |
| Φ = (I − λW)⁻¹p − p, λ = c/ρ(W) | Φ = (I − B)⁻¹p − p, sem *c*; exige ρ(B) < 1 (checado) |
| Sensibilidade ao alcance (grade de *c*, "borderline") | Removida |
| `uncertainty`, `controllability` | Removidos |
| `activation_threshold` (0–1) | `threshold_level` em unidade real + direção; z com referência/DP; portão binário, estático e temporal |
| Sem relevância | Relevância e prioridade (v, D, ρ, lacuna) |
| Eq. temporal com gate, crescimento e autorregulação | dev + tendência, modos, parada com tolerância, critério do gatilho, intensidade, níveis em unidades |
| Quatro abas no Explore | Cinco abas (+ Interpretation); cenário mostrado único |
| Savepoint: rede + cenário + layout | + cenários salvos, configurações temporais, nº de simulações |
| Pescas mínimo, Mangi 18 nós, Sri Lanka 13 nós | Porto, Mangi 22 nós (refeito do artigo), Sri Lanka 17 nós (calibrado); versões "first run" |
