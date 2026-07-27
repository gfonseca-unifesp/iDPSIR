# Roadmap de melhorias — iDPSIR (rumo à publicação)

**Objetivo:** elevar o iDPSIR de protótipo funcional a ferramenta científica publicável e
adotável, cobrindo três eixos: **aceitação** (revisores / credibilidade científica),
**interface** (usabilidade para gestores não-técnicos) e **utilização** (adoção e
distribuição). Este documento continua o `PLANO_iDPSIR.md` (que foi até a Fase 5) e é
escrito para ser executado incrementalmente com o Claude Code.

**Como usar com o Claude Code:** cada item traz *motivação*, *o que fazer*, *arquivos a
tocar*, *pacotes novos*, *esforço*, *impacto na aceitação* e um critério **Pronto quando**.
Trate cada item como uma unidade de trabalho (um commit ou uma PR). As fases são
independentes o suficiente para serem feitas fora de ordem, com as dependências
explicitadas onde existem.

**Estado atual (já pronto, não refazer):** wizard + editor por formulário; import CSV;
savepoint `.idpsir.json` e combinação de savepoints; grafo em camadas com comunidades,
realce de caminho e snapshots; métricas com export CSV/Excel (DT Buttons); análise de loop
(Levins 1974) com estabilidade, efeito imediato/equilíbrio, trajetória, "passos até
neutralizar" e robustez por `confidence`; relatório HTML; tutorial estático (`docs/tutorial.html`).

---

## Priorização geral (esforço × impacto)

Legenda de esforço: **P** (horas) · **M** (1–3 dias) · **G** (semana+).
"Gating" = recomendado concluir **antes** de submeter o artigo.

| # | Melhoria | Eixo | Esforço | Impacto aceitação | Gating? |
|---|---|---|---|---|---|
| 6.1 | LICENSE + CITATION.cff + DESCRIPTION | Aceitação | P | Alto | Sim |
| 6.2 | `renv` (pin de versões) | Aceitação | P | Alto | Sim |
| 6.3 | Testes `testthat` do núcleo numérico | Aceitação | M | Alto | Sim |
| 6.4 | `sessionInfo` + parametrização no relatório | Aceitação | P | Médio | Sim |
| 6.5 | Export do relatório em PDF | Interface | M | Médio | Não |
| 7.1 | Determinância de sinal (Dambacher) | Aceitação | M | **Alto** | Sim |
| 7.2 | Sensibilidade global / ranking de arestas | Aceitação | M | Alto | Sim |
| 7.3 | Referência/DOI por aresta | Aceitação | M | **Alto** | Sim |
| 8.1 | Demo online (shinylive) + badge "Try it live" | Utilização | M | **Alto** | Sim |
| 8.2 | Dockerfile + empacotamento como pacote R | Utilização | M | Médio | Não |
| 9.1 | Tour guiado (`rintrojs`) | Interface | M | Médio | Não |
| 9.2 | Ajuda contextual (tooltips/popovers) | Interface | M | Médio | Não |
| 9.3 | Busca e foco de nó (ego-network) | Interface | M | Baixo | Não |
| 9.4 | Paletas seguras para daltônicos por padrão | Interface | P | Médio | Não |
| 9.5 | Desfazer/refazer no editor | Interface | M | Baixo | Não |
| 9.6 | Export do grafo em PNG/SVG alta resolução | Utilização | P | Médio | Não |
| 10.1 | Toggle único EN/PT (i18n) | Utilização | G | Médio | Não |
| 11.1 | Galeria de exemplos multi-domínio | Utilização | M | Médio | Não |

**Mínimo para submeter (SoftwareX / JOSS):** 6.1, 6.2, 6.3, 6.4, 7.1, 7.2, 7.3, 8.1 + um
**estudo de caso com dados reais**. O restante entra como "trabalho futuro" sem travar a
submissão.

---

## Fase 6 — Fundação para publicação e reprodutibilidade

### 6.1 — LICENSE, CITATION.cff e DESCRIPTION
**Motivação:** requisito prático de JOSS/SoftwareX e o que torna o app citável e reutilizável.
**O que fazer:** escolher uma licença OSI (ex.: MIT ou GPL-3); criar `CITATION.cff` (autor,
título, versão, DOI a preencher depois via Zenodo); criar `DESCRIPTION` (metadados do
"pacote", dependências, autor/ORCID) e, opcionalmente, `codemeta.json`.
**Arquivos:** `LICENSE` (novo), `CITATION.cff` (novo), `DESCRIPTION` (novo), menção no `README.md`.
**Pacotes:** nenhum (opcional `cffr` para gerar/validar o CITATION.cff).
**Esforço:** P · **Impacto:** Alto.
**Pronto quando:** o repositório tem licença explícita, um `CITATION.cff` válido e um
`DESCRIPTION` que lista todas as dependências usadas em `global.R`.

### 6.2 — `renv` (pin de versões)
**Motivação:** o próprio README admite que o `renv` está pendente; sem ele, a alegação de
reprodutibilidade não se sustenta na revisão.
**O que fazer:** inicializar `renv`, capturar `renv.lock` com as versões atuais, ajustar
`global.R` para (se `renv` presente) restaurar em vez de auto-instalar; documentar o fluxo
no README. Manter o auto-install como *fallback* quando não houver `renv`.
**Arquivos:** `renv.lock` (novo), `renv/` (novo), `global.R`, `.gitignore`, `README.md`.
**Pacotes:** `renv`.
**Dependência:** faça antes de 8.1/8.2 (o lock alimenta shinylive/Docker).
**Pronto quando:** um clone novo roda com `renv::restore()` e reproduz o mesmo ambiente;
`renv.lock` versionado no git.

### 6.3 — Testes `testthat` do núcleo numérico
**Motivação:** JOSS/EMS cobram testes; o coração científico (`loop_analysis.R`) precisa de
verificação automática — inclusive dos casos-limite já documentados nos comentários.
**O que fazer:** criar `tests/testthat/` com testes para: `build_interaction_matrix`
(sinal/peso corretos), `press_perturbation` (imediato vs. equilíbrio; matriz singular →
NA), `simulate_trajectory` (convergência ao `-A⁻¹·press` em rede estável; divergência em
instável), `robustness_check` (concordância = 100% quando `confidence = 1`),
`find_neutralization_step` e `summarize_neutralization`. Fixar exemplos numéricos
conferidos à mão (a cadeia trófica e o ciclo instável citados nos comentários).
**Arquivos:** `tests/testthat.R` (novo), `tests/testthat/test-loop_analysis.R` (novo),
`tests/testthat/test-metrics.R`, `tests/testthat/test-io.R`, `tests/testthat/test-validate.R`.
**Pacotes:** `testthat`.
**Esforço:** M · **Impacto:** Alto.
**Pronto quando:** `testthat::test_dir("tests/testthat")` passa; o núcleo de loop tem
cobertura dos caminhos felizes e dos casos-limite (singular, acíclico, instável).

### 6.4 — `sessionInfo` e parametrização no relatório
**Motivação:** um relatório reprodutível deve registrar versões e todos os parâmetros usados.
**O que fazer:** anexar ao relatório HTML uma seção com `sessionInfo()`/versões de pacotes,
data/hora, e os parâmetros de cada análise (força das respostas, nº de passos, `spread` da
robustez, semente aleatória). Fixar `set.seed()` nas reamostragens para reprodutibilidade.
**Arquivos:** `R/report.R`, `R/modules/mod_report.R`, `R/loop_analysis.R` (semente).
**Esforço:** P · **Impacto:** Médio. **Pronto quando:** o relatório traz versões, timestamp
e todos os parâmetros; rodar de novo com a mesma semente reproduz números idênticos.

### 6.5 — Export do relatório em PDF
**Motivação:** gestores e revistas frequentemente querem PDF, não só HTML.
**O que fazer:** oferecer "Download PDF" ao lado do HTML. Rota recomendada: `pagedown`
(Chrome headless) ou `webshot2`; documentar a dependência de Chrome/Chromium. Alternativa
sem dependência: CSS de impressão + orientação ao usuário ("Imprimir → Salvar como PDF").
**Arquivos:** `R/report.R`, `R/modules/mod_report.R`.
**Pacotes:** `pagedown` **ou** `webshot2` (avaliar peso vs. shinylive — ver 8.1).
**Esforço:** M · **Impacto:** Médio. **Pronto quando:** o usuário baixa um PDF fiel ao HTML,
ou há um caminho de impressão documentado que produz PDF limpo.

---

## Fase 7 — Rigor científico da análise de loop

### 7.1 — Determinância de sinal (padrão Dambacher)
**Motivação:** **a adição de maior peso teórico.** O estado da arte em modelagem qualitativa
por loop não reporta só o *sinal* do efeito, mas a *confiabilidade* desse sinal (matriz de
predições ponderada / adjunta). Conecta o app diretamente à literatura (Dambacher, Puccia &
Levins) e blinda contra o revisor especialista.
**O que fazer:** a partir da matriz de interação `A`, computar a matriz de efeitos de
pressão via adjunta (`-adj(A)`), a **matriz de feedback absoluto** (via permanente ou via
simulação de sinais), e a **razão de ponderação** = |efeito líquido| / (efeitos totais),
como índice de determinância de sinal (0–1). Exibir na aba Scenarios uma tabela por fator:
efeito, sinal e "confiança do sinal (%)". Reaproveitar a infraestrutura de reamostragem já
existente em `robustness_check` como implementação numérica da determinância.
**Arquivos:** `R/loop_analysis.R` (novas funções: `weighted_predictions_matrix`,
`sign_determinacy`), `R/modules/mod_responses.R` (exibição), `R/report.R` (seção),
`tests/testthat/test-loop_analysis.R`.
**Esforço:** M · **Impacto:** **Alto**. **Pronto quando:** cada predição de efeito vem
acompanhada de um índice de determinância de sinal (0–100%), validado contra um exemplo
pequeno calculado à mão e coerente com `robustness_check`.

### 7.2 — Sensibilidade global / ranking de arestas influentes
**Motivação:** complementa a robustez por `confidence` respondendo "qual ligação mais
importa medir melhor" — informação de alto valor para gestão.
**O que fazer:** variar sistematicamente os pesos (todos, ou um a um), medir a mudança no
efeito de equilíbrio dos fatores-alvo e **ranquear as arestas por influência** (gráfico
tornado / tabela ordenada). Pode ser one-at-a-time (OAT) ou global (amostragem). Reusar o
laço de reamostragem de `robustness_check`, agora atribuindo a variância do resultado a cada
aresta.
**Arquivos:** `R/loop_analysis.R` (nova `global_sensitivity`), `R/modules/mod_responses.R`
(UI + gráfico tornado), `R/report.R`.
**Pacotes:** nenhum novo (base + `ggplot2`/`visNetwork` já disponíveis; se usar barras,
`ggplot2`). **Esforço:** M · **Impacto:** Alto. **Pronto quando:** para um cenário dado, o
app lista/plota as arestas ordenadas por influência sobre os fatores-alvo.

### 7.3 — Referência / DOI por aresta (evidência rastreável)
**Motivação:** a crítica clássica ao DPSIR qualitativo é "isso é só opinião". `evidence_type`
já existe como categoria; falta a citação em si. Adicionar referência por aresta transforma
a rede em modelo rastreável à literatura — **defesa direta contra o revisor cético.**
**O que fazer:** acrescentar campo opcional `reference` (texto livre / DOI / URL) à aresta;
validar formato leve (opcional); persistir no savepoint; mostrar no tooltip da aresta e numa
**seção de referências** do relatório (lista consolidada). Adicionar a coluna ao
`sample_edges.csv` e ao exemplo de pesca.
**Arquivos:** `R/schema.R` (atributo de aresta), `R/validate.R` (validação opcional),
`R/io.R` (savepoint carrega o campo), `R/modules/mod_data.R` (input no formulário de aresta),
`R/graph.R` (tooltip), `R/report.R` (seção de referências), `data/sample_edges.csv`,
`docs/example_fisheries.idpsir.json`.
**Esforço:** M · **Impacto:** **Alto**. **Pronto quando:** cada aresta pode receber uma
referência, que aparece no tooltip e numa lista de referências do relatório, e sobrevive ao
salvar/recarregar savepoint.

---

## Fase 8 — Distribuição e demo

### 8.1 — Demo online sem instalar R (shinylive)
**Motivação:** **provável item de maior impacto na revisão.** Hoje o revisor precisa clonar
e rodar `runApp()`. Um link "rode no navegador" remove esse atrito e serve também aos
gestores. `shinylive` roda o app em WebAssembly, sem servidor, com link estático permanente.
**O que fazer:** exportar o app com `shinylive`; publicar via GitHub Pages (workflow de CI);
adicionar badge/botão **"Try it live"** no README. **Atenção:** sob shinylive não há
instalação em tempo de execução — o auto-install de `global.R` não funciona; as dependências
precisam ser resolvidas no build. Verificar quais pacotes têm build WASM (a maioria do stack
— shiny, igraph, visNetwork, DT, jsonlite — funciona; validar bs4Dash e qualquer coisa que
dependa de Chrome, como export PDF de 6.5, que **não** roda em WASM e deve ficar só na versão
local).
**Arquivos:** `.github/workflows/shinylive.yml` (novo), `README.md` (badge), ajustes
condicionais em `global.R`.
**Pacotes:** `shinylive`. **Dependência:** 6.2 (renv/lista de deps estável). **Esforço:** M ·
**Impacto:** **Alto**. **Pronto quando:** há uma URL pública que abre o app no navegador, com
o exemplo de pesca carregável, linkada no README.

### 8.2 — Dockerfile + empacotamento como pacote R
**Motivação:** instalação estável e reprodutível para quem for rodar localmente/servidor;
casa com o `renv`.
**O que fazer:** `Dockerfile` (imagem rocker/shiny + `renv::restore()`); opcionalmente
reestruturar como pacote R instalável (`R/` já modular; adicionar `NAMESPACE`, mover `app.R`
para `inst/`), com função `run_app()`. Documentar `docker run`.
**Arquivos:** `Dockerfile` (novo), `.dockerignore` (novo), `NAMESPACE` (se empacotar),
`README.md`. **Dependência:** 6.2. **Esforço:** M · **Impacto:** Médio. **Pronto quando:**
`docker build`/`docker run` sobe o app; (se empacotado) `devtools::install()` + `run_app()`
funciona.

---

## Fase 9 — Interface e acessibilidade

### 9.1 — Tour guiado interativo
**Motivação:** o público é não-técnico; um tour reduz a curva além do tutorial estático.
**O que fazer:** `rintrojs` com passos destacando wizard, abas Graph/Scenarios/Metrics/Report;
botão "Fazer tour" no cabeçalho; disparar automaticamente na primeira visita.
**Arquivos:** `R/ui_main.R`, `R/modules/mod_wizard.R`, `R/server_main.R`.
**Pacotes:** `rintrojs`. **Esforço:** M · **Impacto:** Médio. **Pronto quando:** um tour de
poucos passos cobre o fluxo principal e pode ser reiniciado a qualquer momento.

### 9.2 — Ajuda contextual (tooltips/popovers)
**Motivação:** o motor é sofisticado (estabilidade, equilíbrio, neutralização, determinância);
a UI precisa traduzir esses termos para o gestor.
**O que fazer:** ícones "?" com popover/tooltip explicando cada termo técnico e cada
parâmetro (força da resposta, nº de passos, spread da robustez). Texto curto, em linguagem
simples.
**Arquivos:** `R/modules/mod_responses.R`, `R/modules/mod_metrics.R`, `R/modules/mod_graph.R`,
`R/core/core_ui_components.R` (helper reutilizável). **Pacotes:** `bs4Dash`/`shinyBS` (ou
`tippy`). **Dependência:** coordenar com 10.1 (ver nota de i18n). **Esforço:** M ·
**Impacto:** Médio. **Pronto quando:** todo termo técnico e parâmetro tem ajuda contextual
acessível sem sair da tela.

### 9.3 — Busca e foco de nó (ego-network)
**Motivação:** o layout em camadas satura em redes grandes.
**O que fazer:** campo de busca por rótulo que centraliza/realça o nó; opção "focar" que
mostra só a vizinhança (ego-network) a N passos. Reusar `highlighted_nodes` de
`build_network_visual`.
**Arquivos:** `R/modules/mod_graph.R`, `R/graph.R`. **Esforço:** M · **Impacto:** Baixo.
**Pronto quando:** buscar um nó o realça e é possível isolar sua vizinhança.

### 9.4 — Paletas seguras para daltônicos por padrão
**Motivação:** acessibilidade cada vez mais cobrada por revisores; baixo custo.
**O que fazer:** incluir Okabe-Ito e/ou viridis nas paletas e torná-las o padrão; garantir
contraste também no export.
**Arquivos:** `R/schema.R` (`get_dpsir_palette_choices`/paletas), `R/graph.R`. **Esforço:** P
· **Impacto:** Médio. **Pronto quando:** a paleta padrão é color-blind-safe e as opções
antigas seguem disponíveis.

### 9.5 — Desfazer/refazer no editor por formulário
**Motivação:** conforto na edição de muitos atributos; reduz medo de errar.
**O que fazer:** pilha de estados em `reactiveValues` (nós/arestas) com botões Undo/Redo.
**Arquivos:** `R/modules/mod_data.R`. **Esforço:** M · **Impacto:** Baixo. **Pronto quando:**
uma edição de nó/aresta pode ser desfeita e refeita sem reconstruir manualmente.

### 9.6 — Export do grafo em PNG/SVG de alta resolução
**Motivação:** gestores querem a figura para slides/laudos; hoje ela só entra no relatório.
**O que fazer:** botão de export do `visNetwork` atual (usar `visExport`, ou `htmlwidgets` +
`webshot2` para alta resolução). Respeitar a nota do 8.1: `webshot2` depende de Chrome e não
roda em shinylive — manter export nativo do visNetwork como caminho universal.
**Arquivos:** `R/modules/mod_graph.R`, `R/graph.R`. **Pacotes:** (opcional) `webshot2`.
**Esforço:** P · **Impacto:** Médio. **Pronto quando:** o grafo visível pode ser baixado como
imagem utilizável em documento.

---

## Fase 10 — Internacionalização EN/PT (toggle único)

### 10.1 — Botão único English/Português (sem versão paralela)
**Restrição do projeto (importante):** **não** manter duas versões do app. Deve ser **um só
app** com um **toggle único EN/PT** que troca os textos ao vivo, sem recarregar e sem
duplicar código ou telas.
**O que fazer:** adotar `shiny.i18n`; extrair todas as strings visíveis ao usuário para um
dicionário de tradução (`translation.json` com chaves EN→PT); envolver cada string com
`i18n$t(...)`; adicionar um único controle no cabeçalho (radio/switch EN|PT) que chama
`i18n$set_translation_language()` e atualiza a UI reativamente. Traduzir também mensagens de
validação, rótulos de tabelas, legendas do grafo, textos de ajuda (9.2) e o relatório
(idioma escolhido no momento da exportação).
**Arquivos:** `inst/i18n/translation.json` (ou `translations/`), `R/ui_main.R` (controle de
idioma), `R/server_main.R` (objeto i18n reativo), **todos** os `R/modules/*.R` (envolver
strings), `R/validate.R` (mensagens), `R/report.R` (relatório localizado).
**Pacotes:** `shiny.i18n`.
**Dependência e ordem recomendada:** fazer **depois** das mudanças de UI que ainda vão mexer
em texto (9.1, 9.2, 7.1–7.3), para não envolver strings que serão reescritas. O framework
i18n pode ser instalado antes; a passagem de "envolver todas as strings" é o último passo,
feita de uma vez.
**Esforço:** G (é o item mais trabalhoso, por tocar todas as strings) · **Impacto:** Médio
(amplia adoção lusófona; diferencial regional). **Pronto quando:** um único botão alterna
EN↔PT ao vivo, cobrindo UI, mensagens, legendas, ajuda e relatório, com um só código-base e
nenhuma tela duplicada.

---

## Fase 11 — Adoção e conteúdo

### 11.1 — Galeria de exemplos multi-domínio
**Motivação:** hoje só há o exemplo de pesca; múltiplos domínios mostram generalidade e
reduzem a barreira de entrada.
**O que fazer:** adicionar 2–3 savepoints prontos de domínios distintos (ex.: qualidade da
água, uso do solo, além da pesca) em `docs/`; no passo **Início** do wizard, um dropdown
"Carregar exemplo" que lista a galeria. Documentar cada exemplo no tutorial.
**Arquivos:** `docs/example_*.idpsir.json` (novos), `R/modules/mod_data.R` (dropdown de
exemplos no passo Início), `docs/tutorial.html`. **Esforço:** M · **Impacto:** Médio.
**Pronto quando:** o usuário carrega qualquer exemplo da galeria em um clique, a partir do
passo Início.

---

## Mapa para o artigo (o que é gating × trabalho futuro)

**Gating (fazer antes de submeter):** 6.1, 6.2, 6.3, 6.4 (fundação/reprodutibilidade);
7.1, 7.2, 7.3 (rigor da análise de loop e evidência rastreável); 8.1 (demo online). Some-se
a isso o item que **não é de software** e é o maior gargalo: **um estudo de caso com dados
reais** demonstrando insight de gestão não-óbvio, mais uma **validação cruzada** das saídas
contra `QPress`/`LoopAnalyst` num caso comum.

**Trabalho futuro (pode entrar no texto sem travar a submissão):** 6.5, 8.2, 9.1–9.6, 10.1,
11.1.

**Enquadramento da contribuição (para não vender como "método novo"):** *"primeira
ferramenta que operacionaliza a análise de loop qualitativa (Levins) dentro da estrutura
DPSIR, com predições acompanhadas de determinância de sinal e evidência rastreável, num
fluxo reprodutível e acessível a gestores sem formação em teoria de grafos."*

**Revistas-alvo:** SoftwareX ou Journal of Open Source Software (mais rápidos; JOSS exige os
testes de 6.3); Environmental Modelling & Software (alvo de maior prestígio); Ecological
Informatics / MethodsX (alternativas).

---

## Checklist de submissão

- [ ] LICENSE, CITATION.cff, DESCRIPTION (6.1)
- [ ] `renv.lock` versionado e restore funcionando (6.2)
- [ ] Testes passando, cobrindo o núcleo de loop (6.3)
- [ ] Relatório com sessionInfo, parâmetros e semente fixa (6.4)
- [ ] Determinância de sinal em cada predição (7.1)
- [ ] Sensibilidade global / ranking de arestas (7.2)
- [ ] Referência/DOI por aresta, no tooltip e no relatório (7.3)
- [ ] Demo online público linkado no README (8.1)
- [ ] Estudo de caso com dados reais escrito
- [ ] Validação cruzada contra QPress/LoopAnalyst
- [ ] DOI do software (Zenodo) preenchido no CITATION.cff
- [ ] Manuscrito no template da revista-alvo
