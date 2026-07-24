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
