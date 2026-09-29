# Protótipos numéricos — iDPSIR Revisão 2

Scripts em Python (só `numpy`) que reproduzem o motor do iDPSIR e serviram para tomar as decisões do `ROADMAP_REVISAO2_iDPSIR.md` (raiz do repositório). **Não fazem parte do app.** Servem ao Claude Code como referência para escrever os testes `testthat` em R. Cada teste em R deve reproduzir os números abaixo (tolerância 1e-6, salvo indicação).

As portas seguem o código de `main` no commit `201d131`:
- `propagate()`, `sufficiency()` e `build_signed_matrix()` de `R/sufficiency.R`. A matriz é `A[to, from]`, `λ = c` sem ciclo e `c/ρ` com ciclo, e o resultado é `Φ = (I − λW)⁻¹p − p`.
- `simulate_temporal_pair()` e `temporal_step()` de `R/temporal.R`. O passo é `x(t+1) = x + λW·x + p`, com `λ = min(1, 0.9/ρ)` e autorregulação na diagonal.

Rodar: `python3 <script>.py`

**Conferência em R (29/09/2026):** `confere_em_R.R` roda os mesmos casos contra o motor R real (`Rscript prototipos_revisao2/confere_em_R.R`, a partir da raiz do repositório). Todos os valores da tabela abaixo bateram. O protótipo de `until_neutralized` foi recalculado com a regra "não desligar antes de o problema chegar" (ver a A6 do roadmap).

| Script | Roadmap | O que mostra | Valores de referência |
|---|---|---|---|
| `teste_psir.py` | contexto (D3) | Cadeia P→E→I com resposta R→P na leitura estática atual. Com ciclo fraco (I→R peso 0,001), o veredito se inverte. | Cadeia simples, pesos 1, c = 0,5: piora +0,25; mitigação −0,125; força necessária 200% |
| `variante.py` | contexto (D3, não adotado) | Variante λ = min(1, c/ρ) na leitura estática. **Decisão D3: não mudar λ.** | — |
| `alvos.py` | contexto (D3) | Resposta ligada à Pressão, ao Estado ou ao Impacto, na leitura estática e na temporal. Mostra o atraso da resposta na Pressão. | Estática, c = 0,5: força 200% / 100% / 50% |
| `persistencia.py` | Fase A (A2, A6), D16 | Impulso, permanente, retroalimentação I→R, autorregulação e protótipo de `until_neutralized` | Ver a tabela A6 do roadmap: impulso I = 6 / 36 / 406 nas janelas 5 / 10 / 30; permanente I = −14 na janela 8 |
| `amortecido.py` | Fase A (A3, A6) | Autorregulação 0,3 em P, E e I faz o impulso convergir para a neutralização | Janela 30: I = 0,0267 contra baseline 36,9588 |
| `gatilho.py` | Fase C (C1, C2, C6), D7–D8 | Gatilho do Estado pela carga das Pressões (limiar 0,4) | P1 + P2 a 100%: carga 0,60, piora 0,120; com R→P1 peso 0,8: carga 0,36, líquido 0; P1 + P2 a 70%: 0,084 |
| `q7.py` | Fase C (C3), D11 | Critério do gatilho na simulação temporal: carga × nível acumulado | P1 sozinha 0,3, impulso: por carga nunca abre; por nível abre na janela 4 |
| `crescimento.py` | Fase D (D1, D2, D5), D9–D10 | `growth_rate` no nó × na aresta × os dois (dupla contagem) × tendência exógena | g = 0,10, w = 0,5, impulso: 0,50 / 0,55 / 0,605 (razão 1,10, nunca 1,21); tendência sem push: 0,05 / 0,105 / 0,1655 |
| `d_levins_vs_propagate.py` | Fase B (B3), D14 | Importância D pelo equilíbrio de Levins (PDF v1.0, seção 4) × pela propagação do app. **A ordem dos Impactos se inverte.** | Levins: D(I1) = 1,00, D(I2) = 0,86. Propagação com c = 0,5: D(I1) = 0,55, D(I2) = 1,00 |

Observações:
- `variante.py` e `amortecido.py` reaproveitam funções de `teste_psir.py` e `persistencia.py` (via `exec`). Mantenha os scripts juntos na mesma pasta.
- Os números vieram da porta em Python e foram confirmados no R por `confere_em_R.R`. Se uma mudança no motor alterar algum deles, investigar antes de atualizar o valor esperado.
- Os valores de `until_neutralized` em `persistencia.py` são **sem** a regra "não desligar antes de o problema chegar". Os valores válidos estão na A6 do roadmap e em `confere_em_R.R`.
- Pesos de 1 nos exemplos didáticos (`teste_psir.py`, `alvos.py`, `persistencia.py`) são anteriores à decisão D13 (escala 0–1). Servem para testar o motor, não como exemplos para o usuário.
