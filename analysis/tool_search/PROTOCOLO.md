# Tool search protocol — Table 1 of the manuscript (Revisão 3, E7)

**Goal:** a documented, repeatable search for openly available tools that model causal networks
in social–ecological systems, so that the manuscript can state what exists and what does not
("we found no openly available tool that ...", Supplement S5), with a source for every cell of
Table 1.

## 1. Inclusion criteria

- **Included:** a tool that is *available* (code, installable software or a working web
  application) and models causal networks (signed or weighted directed graphs, fuzzy cognitive
  maps, Bayesian networks, system-dynamics diagrams, DPSIR/DAPSI(W)R(M) chains) for
  environmental or social–ecological problems, **or** a published method that assesses the
  sufficiency or effectiveness of management measures on a DPSIR-type chain (even without
  released software - marked as such).
- **Excluded:** frameworks with no computational reading (conceptual DPSIR only is kept as one
  reference row); general network-visualization software; tools with no documentation of the
  method.

## 2. Sources and search strings

| Source | Status | Search |
|---|---|---|
| Web (general search engine) | **done, 2026-09-30** | the combinations below, one family per query |
| GitHub, CRAN, r-universe | **done, 2026-09-30** | package names and "qualitative network", "loop analysis", "fuzzy cognitive", "Bayesian network shiny" |
| Web of Science Core Collection | **to run by the authors** (institutional access) | string A |
| Scopus | **to run by the authors** | string A |
| Google Scholar (first 200 results) | **to run by the authors** | string B |
| *Environmental Modelling & Software*, *Methods in Ecology and Evolution*, *SoftwareX*, *Ecological Informatics* (software/application notes) | **to run by the authors** | string B in each journal |

**String A (WoS/Scopus, title-abstract-keywords):**
`(DPSIR OR "DAPSI(W)R(M)" OR "driver-pressure-state" OR "causal network" OR "qualitative network model*" OR "loop analysis" OR "fuzzy cognitive map*" OR "Bayesian belief network*" OR "system dynamics") AND (software OR tool OR application OR package OR "decision support") AND (environment* OR ecosystem* OR "social-ecological" OR marine OR coastal OR fisher*)`

**String B (Scholar / journals):**
`("DPSIR" OR "qualitative network" OR "loop analysis" OR "fuzzy cognitive map") ("R package" OR "Shiny" OR "web application" OR "software") ("management" OR "sufficiency" OR "effectiveness of measures")`

**Record for each database:** date, exact string, number of hits, number screened by title and
abstract, number read in full, number included - a PRISMA-style flow in Supplement S5.

## 3. What each cell of Table 1 means (coding rules)

| Column | Coded as | Rule |
|---|---|---|
| Method | text | the computation the tool performs, in the authors' terms |
| DPSIR-structured | Yes / Possible / Structure only / No | Yes = categories and allowed links enforced; Possible = the user can impose them |
| Feedback loops | Yes / Yes if stable / No / Not represented | whether cycles can be analysed |
| Response sufficiency | Yes / Sign only / Scenario comparison / No | Yes = reports whether a measure offsets a pressure's effect on a target |
| Uncertainty / sign robustness | text | what is resampled or scored, and how |
| Evidence-traceable | Yes / Partial / No | a reference or evidence field per link |
| Reproducible output | text | what can be saved and re-run |
| Interface / target user | text | code, GUI, web; intended user |
| Availability | URL, license, last version or update checked | "not released" when only the paper exists |

Every cell carries a source (paper, documentation or repository) in `tabela_ferramentas.csv`.

## 4. Results so far (web, GitHub, CRAN — 2026-09-30)

See `tabela_ferramentas.csv` (one row per tool, a source per cell). Findings that change the
manuscript's Table 1 and text:

1. **Response sufficiency is not unique to iDPSIR.** Two recent works assess whether measures
   are sufficient on a DPSIR-type chain:
   - Ahtiainen et al. — *Quantifying effectiveness and sufficiency of measures - An
     application of the DPSIR framework for the marine environment*, Marine Policy,
     doi:10.1016/j.marpol.2024.106480 (online Nov 2024; the manuscript cites it as 2025 -
     confirm the volume year). Expert-, literature- and model-based data; probability of
     reaching each target; no released software found.
   - Bryhn et al. (2026) — *Mind the GAP: a model to inform coastal and marine management and
     policy about gaps to environmental targets*, Ocean & Coastal Management (pii
     S096456912600150X). Expert elicitation of the potential and current effectiveness of
     measures against environmental quality standards; implementation gaps. **New row.**
   The novelty claim should therefore be: *the first openly available, no-install tool that
   reads sufficiency by propagating effects through a signed causal network, with per-link
   evidence and uncertainty* - not "the first sufficiency assessment".
2. **QPress has Shiny widgets** (`impact.barplot.shiny`) and evaluates press scenarios,
   including management presses, against validation criteria, as the proportion of simulations
   with each sign. Table 1: interface "R package with Shiny widgets"; response sufficiency
   "Sign of change under a management press" (not magnitude, not neutralization).
3. **Fuzzy cognitive mapping now has Monte Carlo uncertainty** (In-Cognitive, SoftwareX 2023,
   web application, open source). The FCM row's "no determinacy test" should be qualified.
4. **Web tools exist for neighbouring methods:** DAGitty (causal DAGs, browser), shinyBN
   (Bayesian networks, Shiny, online), Insight Maker (system dynamics, browser). None is
   DPSIR-structured or reads response sufficiency.
5. **To read in full before submission:** Ramos-Quintana et al. (2018), *Quantitative-qualitative
   assessments of environmental causal networks to support the DPSIR framework in the
   decision-making process*, Environmental Impact Assessment Review 69, 42–60,
   doi:10.1016/j.eiar.2017.11.004 - closest in aim (DPSIR + causal networks + decisions);
   whether it released software decides whether it is a row of Table 1 or a citation in the
   Introduction.

## 5. Still to do

- Run strings A and B in WoS, Scopus, Scholar and the four journals; fill the flow counts.
- Read in full: Bryhn et al. 2026, Ramos-Quintana et al. 2018, Ahtiainen et al. (volume/year).
- Revise Table 1 with the rows and cells above; add Supplement S5 (this protocol, the flow and
  `tabela_ferramentas.csv`).
