# Plano de Reestruturação — iDPSIR

**Objetivo:** transformar o iDPSIR num app científico minimalista para análise de redes DPSIR, facilmente aplicável à gestão ambiental, construído de forma incremental a partir de um núcleo enxuto e confiável.

**Princípios:**

- **Minimalista primeiro.** O MVP entrega só os 3 pilares (tabelas, grafo, métricas) + edição robusta. Nada além disso.
- **Incremental.** Cada fase é utilizável por si só; a complexidade (caminhos, comunidades, cenários) vem depois, sobre uma base estável.
- **Qualidade de dados por construção.** Vocabulários controlados e validação impedem que erros de digitação quebrem o modelo silenciosamente.
- **Reprodutível.** Um gestor deve conseguir salvar um estudo de caso, reabrir e chegar ao mesmo resultado.

---

## 1. Diagnóstico atual (resumo)

| Pilar | Situação | Lacuna principal |
|---|---|---|
| 1. Tabelas de entrada | Parcial | Existe DT editável, mas não há **vista de leitura** limpa; edição e visualização estão misturadas. |
| 2. Grafo DPSIR | Bom, mas incompleto | Cor/forma/legenda OK; falta **layout em camadas** que torne legível a cadeia D→P→S→I→R. |
| 3. Métricas | Fraco | Centralidades OK; estatísticas gerais (densidade, diâmetro, transitividade, modularidade) **calculadas mas nunca exibidas**; **descritores aplicados ao DPSIR inexistentes**. |
| Edição | Frágil | Célula-a-célula em texto livre; sem vocabulário controlado; desconfortável para os 7 atributos por nó. |

**Código morto / duplicado detectado:**

- `R/data_models/` inteiro (7 arquivos) **não é carregado** pelo `global.R`; duplica funções de `dpsir/`.
- `core/graph/core_graph_centrality.R` e `core_graph_metrics.R` duplicam a camada `compute/` (densidade, diâmetro, transitividade, modularidade definidas **duas vezes**).
- `output$graph` em `mod_network.R` não tem `visNetworkOutput` correspondente.

**Bugs a corrigir:**

- `metrics_server` chama `compute_all_metrics(graph())` sem `req(graph())` → erro antes de carregar dados.
- Communities com toggle *Directed* + *Louvain*/*Label Propagation* → erro (algoritmos só valem para grafo não-direcionado).
- `compute_all_metrics` roda closeness/eigenvector sempre direcionado → NaN e avisos silenciosos.

---

## 2. Decisões de arquitetura

1. **Edição por formulário + seleção.** A tabela vira *visão de leitura + seleção*; um painel/modal edita cada nó/aresta com campos controlados (`selectInput` para categoria e vocabulários). O grafo cria topologia e seleciona; o formulário edita atributos.
2. **Não-reativo por design.** Edições acumulam no estado; nada re-renderiza até o botão **"Reconstruir grafo"**. A validação roda nesse momento, com feedback claro.
3. **Esquema DPSIR configurável (dados, não constantes).** Os níveis do modelo (nome, ordem, cor, forma e regras de conexão) são *dados*, definidos pelo usuário no início a partir do template DPSIR padrão. `R/schema.R` guarda o template e a lógica; validação, visual e layout leem esse config. Permite sub-níveis e níveis intermediários **sem tocar em código**.
4. **Savepoint como recurso central.** Projetos levam dias; o app salva/carrega um *savepoint* que captura o estado completo (modelo + nós + arestas + posições + metadados) num único arquivo portátil e compartilhável. A inicialização aceita **dois caminhos**: pelas matrizes (CSV) ou por um savepoint. Detalhado na seção 7.
5. **Interface em wizard.** A construção do projeto é guiada passo a passo, com poucas informações por tela e padrões pré-preenchidos, para decisões fáceis. Detalhado na seção 5.

---

## 3. Estrutura de pastas proposta (minimalista)

Consolida os muitos arquivos "uma função por arquivo" em módulos coesos.

```
iDPSIR/
├── app.R
├── global.R
├── README.md
├── renv.lock                 # Fase 0
├── R/
│   ├── schema.R              # categorias, vocabulários, conexões permitidas
│   ├── validate.R           # validação de nós, arestas e lógica DPSIR
│   ├── graph.R              # build_igraph + layout DPSIR + visual (visNetwork)
│   ├── metrics.R            # métricas gerais + centralidades + descritores DPSIR
│   ├── io.R                 # savepoint (salvar/carregar), importar matrizes, export
│   └── modules/
│       ├── mod_data.R       # upload + tabela de leitura + editor por formulário
│       ├── mod_graph.R      # visualização do grafo
│       └── mod_metrics.R    # painel de métricas
├── data/
│   ├── sample_nodes.csv
│   └── sample_edges.csv
└── docs/
    └── PLANO_iDPSIR.md
```

Some, no MVP: `dpsir/`, `compute/` (10 arquivos), `core/graph/` (10 arquivos), `data_models/` (7 arquivos), `mod_pathways`, `mod_responses`, `mod_communities`. O conteúdo aproveitável migra para os 5 arquivos de `R/` acima; o resto é removido ou guardado para fases futuras.

---

## 4. Modelo de dados e esquema configurável

**Modelo (configuração do usuário).** O esquema deixa de ser fixo. É uma **lista ordenada de níveis**, definida no início a partir do template DPSIR padrão:

| Campo do nível | Descrição |
|---|---|
| `name` | nome do nível (ex.: Driver, Sub-driver, Pressure…) |
| `order` | posição na cadeia causal (1, 2, 3…) |
| `color` / `shape` | atribuídos automaticamente, editáveis |
| `role` | opcional; marca níveis de **feedback** (o papel que hoje é do Response) |

As **conexões permitidas são derivadas da ordem**: cada nível conecta ao próximo, e níveis de `role = feedback` podem voltar para trás. Assim, inserir um "Sub-driver" ou um nível entre Pressure e State é só adicionar um item na lista — cor, forma, validação e layout se ajustam sozinhos. O template padrão reproduz o DPSIR canônico (D→P→S→I→R, com R como feedback). Matriz de conexões livre e aninhamento hierárquico ficam para fases posteriores.

**Nós**

| Campo | Tipo | Valores |
|---|---|---|
| `id` | texto | único, obrigatório |
| `label` | texto | livre |
| `dpsir_category` | fechado | um dos níveis do modelo (padrão: Driver…Response) |
| `subsystem` | texto | livre |
| `uncertainty` | fechado | low, medium, high |
| `controllability` | fechado | low, medium, high |
| `temporal_scale` | fechado | short, medium, long |

**Arestas**

| Campo | Tipo | Valores |
|---|---|---|
| `from`, `to` | fechado | ids de nós existentes |
| `weight` | numérico | > 0 |
| `confidence` | numérico | 0–1 |
| `interaction_type` | fechado | increases, reduces, triggers, mitigates, improves |
| `evidence_type` | fechado | observational, monitoring, expert_assessment, ... |

**Conexões permitidas:** derivadas do modelo — cada nível → o próximo na ordem, mais os níveis de feedback voltando para trás. No template DPSIR padrão isso equivale a D→P, P→S, S→I, I→R e R→{D,P,S,I}.

---

## 5. Interface em wizard e edição por formulário

**Princípio de UX:** a construção do projeto é um **wizard passo a passo** — cada tela mostra poucas informações e pede uma decisão simples, com padrões já preenchidos e botões Voltar/Avançar. Reduz a carga cognitiva no ponto mais difícil (a edição) e guia usuários não técnicos.

**Passos do wizard:**

1. **Início** — como começar: *Novo projeto*, *Importar matrizes (CSV)* ou *Carregar savepoint*. (uma decisão)
2. **Modelo** — confirmar o esquema. Padrão DPSIR já selecionado ("Usar DPSIR padrão"); avançado, opcional: adicionar/renomear/reordenar níveis.
3. **Nós** — adicionar/editar um nó por vez via formulário (poucos campos, dropdowns com padrões). Tabela ao lado como visão geral.
4. **Arestas** — opcional; adicionar ligações com `from`/`to` por seleção e atributos. Pode pular.
5. **Revisar e construir** — resumo da validação + botão **Construir grafo**, com mensagens claras do que falta.
6. **Explorar** — abre o espaço de análise (grafo + métricas).

**Regras do wizard:**

- Indicador de progresso ("Passo X de N"); sempre Voltar/Avançar.
- Padrões sensatos pré-selecionados (DPSIR, categoria default, weight=1…).
- Validação nas transições, com feedback amigável.
- **Salvar savepoint disponível a qualquer momento** — inclusive no meio do wizard — para não perder dias de trabalho.
- Após construído, pode-se reentrar em qualquer passo para editar; a análise (grafo/métricas) é um painel leve, com poucos controles — não um wizard.

### 5.1 Edição por formulário (núcleo dos passos 3 e 4)

- **Tabela de leitura** (DT não-editável) mostra todos os atributos e serve para **selecionar** uma linha.
- Botões: **Adicionar**, **Editar selecionado**, **Remover selecionado** — para nós e para arestas.
- **Modal de edição** com todos os campos como inputs próprios: dropdowns para categoria e vocabulários; `from`/`to` como dropdown dos nós existentes; numéricos para weight/confidence.
- Estado acumulado em `reactiveValues`; **"Reconstruir grafo"** aplica tudo de uma vez e dispara a validação.
- Feedback de validação claro (o que está inválido e por quê).
- (Fase 2) Clicar num nó do grafo seleciona a linha correspondente na tabela.

Isso resolve os dois problemas centrais: conforto com muitos atributos por nó e integridade dos vocabulários (que protege a validação DPSIR e a pontuação de impacto).

---

## 6. Os 3 pilares no MVP

**Pilar 1 — Dados (`mod_data`):** upload CSV (nós/arestas), tabela de leitura, editor por formulário, salvar/abrir projeto, botão reconstruir.

**Pilar 2 — Grafo (`mod_graph`):** **layout em camadas por categoria** (posição horizontal fixa por D/P/S/I/R, tolerante a ciclos R→…), cor e forma por categoria, legenda, largura da aresta por `weight`, tracejado para baixa `confidence`.

**Pilar 3 — Métricas (`mod_metrics`):** um painel único com três blocos, do geral ao aplicado:

- *Gerais do grafo:* nº de nós, arestas, densidade, diâmetro, transitividade, modularidade, nº de componentes.
- *Centralidades por nó:* degree, betweenness, closeness, eigenvector, pagerank (com toggles direcionado/normalizado).
- *Descritores DPSIR:* contagem de nós por categoria; contagem de arestas por transição; matriz categoria×categoria; **Impactos sem Resposta** e **Pressões não cobertas por Respostas** (lacunas de gestão); grau/centralidade médios por categoria.

Todos com export (CSV/Excel).

### 6.1 Aproveitamento dos atributos (Pilares 2 e 3)

Diagnóstico: hoje só `id`, `label` e `dpsir_category` são usados no grafo, e as métricas ignoram quase todos os atributos. O plano passa a **explorar cada atributo** — no grafo (Pilar 2) e nas métricas (Pilar 3):

| Atributo | No grafo (Pilar 2) | Nas métricas (Pilar 3) |
|---|---|---|
| `dpsir_category` | cor, forma, grupo e **camada do layout** | contagem por categoria, matriz de transições, descritores DPSIR |
| `label` | rótulo do nó | identificação nas tabelas |
| `subsystem` | **filtro** e agrupamento visual | recortes das métricas por subsistema |
| `uncertainty` | borda/opacidade do nó | incerteza média por categoria; destaque de nós críticos de alta incerteza |
| `controllability` | realce/ícone do nó | controlabilidade média; identificação de **alavancas de gestão** |
| `temporal_scale` | filtro/faceta temporal | recorte temporal das métricas |
| `weight` (aresta) | **espessura da aresta** | centralidades ponderadas pela força do elo |
| `confidence` (aresta) | transparência / tracejado | ponderação por confiança; perfil de confiança da rede |
| `interaction_type` (aresta) | cor/rótulo da aresta (increases, reduces…) | balanço de interações (reforço × mitigação) |
| `evidence_type` (aresta) | tooltip da aresta | perfil de qualidade da evidência |

**Correção necessária:** o `igraph` interpreta `weight` como *distância* em intermediação/proximidade — semântica invertida para "força do elo". Nas centralidades ponderadas, converter (ex.: distância = 1/força) para que elos mais fortes aproximem, não afastem.

Tooltips (`title`) nos nós e arestas passam a listar todos os atributos ao passar o mouse — sem poluir o desenho.

---

## 7. Savepoint e inicialização do projeto

Como a construção de um grafo pode levar dias, o **savepoint** (ponto de salvamento) é um recurso central: permite salvar, retomar e **compartilhar** um projeto para edição futura, sem perda de contexto.

**Conteúdo do savepoint (estado completo):**

- Modelo/esquema: níveis (nome, ordem, cor, forma, papel) e regras de conexão.
- Nós e arestas: todas as tabelas com todos os atributos.
- Posições dos nós, se o usuário organizou o grafo manualmente.
- Metadados: nome do projeto, autor, datas de criação/edição, descrição/notas e **versão do formato** (compatibilidade futura).

**Formato:** um único arquivo **JSON** (`.idpsir.json`) — portátil, legível, versionável no git e independente de linguagem (importante caso o app evolua). O `.rds` fica como alternativa rápida em R; opcionalmente, um pacote `.zip` com `nodes.csv` + `edges.csv` + `model.json` para inspecionar as partes.

**Dois caminhos de inicialização:**

1. **Pelas matrizes** — importar `nodes.csv` (+ `edges.csv` opcional) e definir/confirmar o modelo. Bom para partir de dados tabulares já existentes.
2. **Pelo savepoint** — carregar o `.idpsir.json` e restaurar tudo (modelo + tabelas + posições + metadados) exatamente como estava.

**Robustez:**

- Ao carregar, o savepoint é validado contra o esquema declarado; versões antigas são migradas quando possível, com erro claro se incompatível.
- Salvar não depende de reconstruir o grafo — pode-se salvar a qualquer momento, mesmo com edição em andamento.
- **Autosave/recuperação (recomendado):** como uma sessão Shiny pode cair, um autosave periódico para arquivo local, com opção de recuperar o último estado ao reabrir, protege dias de trabalho. Núcleo = savepoint manual (Fase 1); autosave = incremento (Fase 1.5/2).

---

## 8. Roadmap incremental

### Fase 0 — Limpeza e fundação
Remover código morto (`data_models/`, `core_graph_*` duplicados, `output$graph`); consolidar em `schema.R`, `validate.R`, `graph.R`, `metrics.R`, `io.R`; corrigir `req()` no Metrics e o bug Directed+Louvain; adicionar `README.md`, `renv.lock` e mover exemplos para `data/`.
**Pronto quando:** o app roda com os dados de exemplo, sem código morto e sem duplicação de definições.

### Fase 1 — MVP dos 3 pilares
Configuração do modelo (níveis em cadeia ordenada, partindo do DPSIR padrão); `mod_data` **em wizard** (editor por formulário; savepoint salvar/carregar; importar matrizes); `mod_graph` (layout por camadas segundo a ordem dos níveis + peso/confiança); `mod_metrics` (painel geral + centralidades + descritores DPSIR).
**Pronto quando:** dá para definir o modelo, montar do zero uma rede válida, visualizá-la de forma legível e extrair as métricas.

### Fase 2 — Análise causal e modelos avançados
Destaque de caminhos no grafo (`highlight_pathway`, já existente); aba de pathways enxuta; comunidades corrigidas (com arestas desenhadas); seleção cruzada grafo↔tabela; **matriz de conexões livre** e **aninhamento hierárquico** de níveis (para modelos não-lineares).

### Fase 3 — Cenários e respostas
Simulação de resposta (`apply_response`, reaproveitada), comparação de cenários e relatório exportável.

### Fase 4 — Combinar savepoints (múltiplas redes compatíveis)
**Motivação:** redes DPSIR de subsistemas montadas em separado (ex.: pesca e qualidade
da água), depois combinadas numa visão integrada.

**Decisões de design:**
- Só savepoints com o **mesmo schema** (mesmos níveis, na mesma ordem, mesmos papéis)
  podem ser combinados — schemas diferentes são bloqueados com mensagem clara;
  reconciliar dois schemas distintos fica fora de escopo.
- IDs de nó duplicados entre savepoints são prefixados automaticamente pelo nome do
  savepoint de origem (ex.: `pesca__P1`, `agua__P1`) para garantir unicidade — evita
  misturar silenciosamente dois nós diferentes que por acaso têm o mesmo id.
- Arestas são apenas concatenadas, sem tentar deduplicar/mediar pesos automaticamente;
  duplicatas exatas caem no `unique()` que `sanitize_edges` já aplica.
- Sem tela nova de "resolução de conflitos": o resultado da combinação entra direto no
  passo **Nós** do wizard, já populado — revisão/renomeação/remoção usa o editor por
  formulário que já existe, sem interface nova para aprender.

**Onde entra na UI:** nova opção no passo Início, ao lado de Novo projeto / Importar
matrizes / Carregar savepoint: **"Combinar savepoints"**, aceita 2+ arquivos
`.idpsir.json`.

**Arquivos:** `merge_savepoints()` novo em `R/io.R`; ajuste em `mod_data.R` para a nova
opção do passo Início.

**Pronto quando:** dois savepoints válidos e compatíveis resultam numa única rede
editável, com nós/arestas combinados e ids únicos, seguindo o mesmo fluxo de revisão
já usado no resto do wizard.

### Fase 5 — Loop de feedback como motor de Scenarios
**Motivação:** o diferencial do DPSIR é o loop Response → {Driver, Pressure, State,
Impact}, mas hoje o app só mostra o efeito de uma resposta como uma comparação única
"antes/depois" (`apply_response`, Fase 3) — o loop nunca é observado "rodando" de
fato, e o cálculo de hoje ignora o peso da própria aresta da Resposta (só usa pra
achar os alvos, não pra medir o efeito). Modelagem estatística contra dados reais
(path analysis defasada, SEM) foi avaliada (seção 11) e **fica fora do escopo deste
app por ora** — decisão consciente, não pendência: exige um tipo de dado
(observações ao longo do tempo) que o iDPSIR não tem, e o risco de complexidade para
o público-alvo é real. Pode voltar a ser considerada depois, inclusive como uma
ferramenta separada.

**Método escolhido:** **análise de loop / matriz comunitária** (Levins 1974;
Dambacher, Puccia e outros) — o método clássico de ecologia justamente para grafos
direcionados com sinal e ciclos, o mesmo tipo de estrutura que o Response cria no
DPSIR. Cada aresta vira uma entrada da matriz de interação `A[i,j]` (efeito de j
sobre i), com sinal dado por `interaction_type` e magnitude por `weight` — os mesmos
dois atributos que o usuário já preenche hoje, agora usados também na Resposta, não
só pra achar os alvos.

**Decisão de consolidação (não é aditivo — revisa a Fase 3):** em vez de manter o
`apply_response()` de hoje ao lado de um método novo, a análise de loop **substitui**
o motor de cálculo da aba Scenarios. Manter os dois geraria dois números diferentes
pra mesma pergunta ("qual o efeito desta resposta?"), sem um jeito principiado de
saber qual confiar — e o método de loop é estritamente mais rigoroso (usa o peso da
aresta da Resposta, que o método antigo descarta). A interface que o usuário já
conhece **não muda**: mesmas tabelas ("Effect on the network" / "Effect on each
factor"), mesma linguagem Improves/Worsens/Stable, mesmo fluxo de Salvar/Comparar
cenários — só os números por trás ficam mais corretos. Combinar respostas também
fica mais simples nesse método (somar as pressões no mesmo vetor, em vez do
encadeamento manual de `apply_response()` hoje).

**Camadas opcionais, dentro da mesma aba (nada de aba nova):**
- **Efeito imediato × efeito de equilíbrio.** Perturbação de pressão sustentada:
  calcular tanto o efeito de um passo (`A` aplicado uma vez) quanto o de equilíbrio
  (`-A⁻¹`, contabilizando todos os loops diretos e indiretos) — mostrado como um
  detalhe expansível na tabela ("Right away: +2%. Once it settles: +8%"), não como
  uma segunda tabela concorrente.
- **Trajetória com número de passos ajustável** (disclosure opcional, desligado por
  padrão). A mesma matriz `A` aplicada repetidamente (`A`, `A²`, `A³`...) mostra o
  sistema convergindo — com um controle "Number of steps" que o usuário ajusta.
  Também é a saída que continua funcionando quando o sistema é instável (potência
  finita de matriz sempre existe, mesmo quando o equilíbrio infinito não).
- **Robustez via confidence** (disclosure opcional, desligado por padrão). O
  `confidence` que o usuário já preenche em cada aresta vira uma faixa de variação
  plausível no peso (alta confiança = pouca variação; baixa = muita); rodando N
  simulações com pesos perturbados dentro dessa faixa, mostra o percentual de vezes
  em que o sinal do resultado se manteve — com um controle "Number of simulations"
  que o próprio usuário ajusta, vendo o percentual estabilizar conforme aumenta N.
  Dá um uso real ao `confidence`, que hoje só controla o tracejado no grafo.
- **Checagem de estabilidade.** Nem todo grafo desenhado pelo usuário é "estável" no
  sentido do método (autovalores de `A` com parte real negativa); a função detecta
  isso e avisa em linguagem simples, sem mostrar autovalor bruto na tela.

**Por que essa escolha:** zero dependência nova (`solve()`/`eigen()` do R base;
gráfico de trajetória via `matplot()`, sem precisar de `ggplot2`), é o método já
estabelecido na literatura para exatamente este tipo de estrutura, e não exige
nenhum dado observado — só o grafo qualitativo que o usuário já constrói hoje.

**Arquivos:**
- `R/loop_analysis.R` novo — `build_interaction_matrix()`, `check_stability()`,
  `press_perturbation()`, `simulate_trajectory()`, `robustness_check()`.
- `mod_responses.R` revisado para computar a partir desse motor; `apply_response()`
  deixa de ser o principal (fica preservado no disco, não sourceado — mesmo
  tratamento já dado a `R/dpsir/`).

**Marcos:**
- **A** — matemática pura (`R/loop_analysis.R`), testada standalone contra um
  exemplo conhecido de loop analysis.
- **B** — Scenarios revisado: tabela de efeito (imediato + equilíbrio) e aviso de
  estabilidade, substituindo o motor antigo.
- **C** — trajetória com número de passos ajustável.
- **D** — robustez via confidence, com número de simulações ajustável.

**Pronto quando:** aplicar uma resposta com força X mostra, para cada nó da rede, o
efeito de equilíbrio considerando o loop de feedback completo — não só o efeito
direto de um passo, como hoje — usando as mesmas tabelas e a mesma linguagem que a
aba Scenarios já usa.

---

## 9. Pontos de atenção

- **Layout DPSIR com ciclos.** A regra permite R→{D,P,S,I}, então o grafo tem ciclos — um layout hierárquico puro falha. Solução: fixar a posição horizontal por categoria (D…R) e distribuir verticalmente; tolera ciclos e mantém a leitura da cadeia.
- **Escopo do editor.** É a maior parte do esforço da Fase 1; convém prototipar só nós primeiro, depois arestas.
- **Compatibilidade igraph.** Alguns algoritmos exigem grafo não-direcionado; centralizar essa lógica em `graph.R`.
- **Reprodutibilidade.** `renv` e datasets versionados desde a Fase 0, para não acumular dívida.
- **Perda de trabalho.** Projetos de dias exigem savepoint frequente e, idealmente, autosave/recuperação de sessão; o formato deve carregar sua versão para não invalidar arquivos antigos quando o app evoluir.

---

## 10. Controle de versão (Git/GitHub)

Decisão: **mover o projeto para fora do OneDrive** e versionar com Git, publicando em `github.com/gfonseca-unifesp`. Motivo: OneDrive sincronizando a pasta `.git` pode corromper o repositório; e o Git dá histórico, reprodutibilidade e o caminho de distribuição via `runGitHub`.

**Passos (você executa a movimentação e a autenticação; eu preparo o resto):**

1. Mover a pasta para um diretório de desenvolvimento fora do OneDrive, ex.: `C:\Users\fonse\Projetos\iDPSIR`.
2. Reconectar essa nova pasta aqui, para eu retomar o acesso.
3. Eu inicializo o repositório, com `.gitignore` (R/RStudio) e `README.md`, e organizo os commits por fase. *(O `.gitignore` já foi criado na pasta atual e vai junto na movimentação.)*
4. Você autentica no GitHub (GitHub Desktop, ou `gh auth login`) e cria o repositório remoto `iDPSIR`.
5. `git remote add origin` + `git push` — eu forneço os comandos exatos; o `push` é feito por você (a credencial é sua).

Enquanto o projeto estiver no OneDrive, evito operações Git na pasta para não gerar conflitos de sincronização.

---

## 11. Fase 5 — avaliação técnica (path analysis / SEM) e decisão de escopo

**O que já existe hoje:** `R/pathways.R` já faz "path analysis" no sentido
topológico — encontra e pontua caminhos causais no grafo (`find_dpsir_paths`,
`score_pathway`), mas a pontuação usa só peso/confiança que o usuário digitou
manualmente. Não há nenhuma estimativa estatística a partir de dados reais.

**O que "path analysis" no sentido clássico (Wright) e SEM significam:** tratar cada
nó como uma variável com valores observados (numéricos), e as arestas como
coeficientes de regressão padronizados, estimados a partir dos dados — não mais
atribuídos por julgamento. SEM generaliza isso permitindo variáveis latentes e testes
de ajuste do modelo inteiro (χ², CFI, RMSEA).

**Três obstáculos reais, nessa ordem de importância:**

1. **Ciclos de feedback não se encaixam no método padrão.** O DPSIR permite
   Response → {Driver, Pressure, State, Impact}, ou seja, o grafo tem ciclos por
   construção — é o próprio ponto do modelo. Path analysis clássica e SEM recursivo
   assumem grafo acíclico; ciclos exigem equações simultâneas ou dados em
   painel/série temporal defasada (efeito de R em t sobre D em t+1), um desenho de
   pesquisa bem mais exigente do que o que o app pede hoje. Não dá para simplesmente
   jogar o grafo inteiro num `lavaan::sem()` e esperar que funcione.
2. **Dado observado é um tipo de dado novo, que o app não tem.** Hoje um nó tem só
   atributos qualitativos (`uncertainty`, `controllability`, `temporal_scale`).
   Ajustar qualquer modelo estatístico exige uma tabela nó × observação (várias
   medições/períodos por nó) — um formato de dado, uma tela de importação e uma
   validação (tamanho de amostra mínimo, nomes de coluna batendo com os ids dos nós)
   que não existem em nenhuma fase anterior.
3. **Risco de complexidade para o público-alvo.** O princípio já seguido em todo o
   app ("gestores não são especialistas em DPSIR nem em teoria de grafos") esbarra
   direto em SEM: mesmo um ajuste bem-sucedido produz números (χ², CFI, RMSEA,
   índices de modificação) que exigem treinamento estatístico para interpretar — e
   um ajuste malsucedido (modelo não identificado, não convergiu) é ainda mais
   difícil de explicar sem jargão. Amostras pequenas ou irregulares, comuns em
   monitoramento ambiental real, tornam isso um risco frequente, não uma exceção.

**Decisão de escopo (confirmada com o usuário):** modelagem estatística contra dados
reais — defasada (cross-lagged/VAR) ou SEM não-recursivo — fica **fora do escopo do
iDPSIR por ora**. Não é uma sub-fase futura dentro deste app; é um outro tipo de
ferramenta (exige um tipo de dado que o iDPSIR não coleta, uma tela de importação
própria, e carrega o risco de complexidade do item 3 acima). Se um dia fizer sentido,
é mais provável que valha a pena como um **app separado** — que poderia inclusive
*consumir* um savepoint `.idpsir.json` como ponto de partida (a estrutura do modelo
já viria pronta) — do que como uma aba a mais dentro deste.

**O que fica dentro do escopo:** a Fase 5 tal como descrita na seção 8 — análise de
loop / matriz comunitária (Levins 1974) **substituindo** o motor de cálculo da aba
Scenarios, não coexistindo com ele. Diferente de SEM, esse método foi desenhado
justamente para grafos com ciclo, não exige nenhum dado observado (só o grafo
qualitativo que o usuário já constrói), e não introduz nenhuma dependência nova
(`solve()`/`eigen()` do R base). É o jeito de honrar o loop de feedback do Response —
o diferencial do DPSIR — sem esbarrar em nenhum dos três obstáculos listados acima, e
sem deixar dois métodos concorrentes confundindo a mesma pergunta.
