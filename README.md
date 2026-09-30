# iDPSIR

[![Try it live](https://img.shields.io/badge/Try_it_live-online_demo-2ea44f)](https://gfonseca-unifesp.github.io/iDPSIR/)

**R/Shiny** app for building and analyzing causal networks under the **DPSIR** model
(Driver–Pressure–State–Impact–Response), aimed at environmental management. A guided
wizard walks non-technical users through building the network (form-based editor or
CSV import), exploring it with a layered DPSIR-aware visualization, running community
detection, testing response scenarios two ways — a static **sufficiency** reading
(does a planned response's mitigation cover a pressure's worsening on each Impact,
and how confident is that verdict) and an optional **temporal simulation** across
discrete time windows (does the response's effect hold up over time, or does it
eventually become a new pressure itself) — and exporting a self-contained HTML
report, all without requiring familiarity with graph theory.

New to iDPSIR? See the [getting-started tutorial](docs/tutorial.html) — it walks
through every step and includes three downloadable example networks, from a
five-node orientation loop to a full worked example (see
[Example networks](#example-networks) below). The same tutorial is one click away
from inside the running app too, via the "Help" link in the top-right corner.

## How to run

No R installation at all? **[Try it live](https://gfonseca-unifesp.github.io/iDPSIR/)**
runs the same app entirely in your browser via WebAssembly ([shinylive](https://shinylive.io/)),
no server involved — the first load takes a bit longer while R and its packages
download into the browser, everything after that is instant. Good for a quick look;
for real work, install R locally (below) so nothing depends on your connection.

Requires R (>= 4.1). Missing packages are installed automatically on first run — no
manual `install.packages()` step needed. From the project root:

```r
shiny::runApp()
```

Or, without cloning the repo:

```r
shiny::runGitHub("iDPSIR", "gfonseca-unifesp", "main")
```

## Testing

The scientific core (`R/structural.R`, `R/sufficiency.R`, `R/temporal.R`, `R/triggers.R`, `R/relevance.R`, `R/pathways.R`,
`R/reach.R`, `R/metrics.R`, `R/io.R`, `R/validate.R`) has an automated `testthat`
suite, checked against hand-verified numeric examples (the roadmap's reference cases for
growth and State triggers, the real Mangi et al. 2007 and Gnanapragasam et al. 2026 networks, the reference
values of a small Pressure -> State -> Impact chain for the temporal simulation, and
older-format savepoints kept in `tests/testthat/fixtures/` to check that files from
earlier versions still load with the same results). Run it from the project root:

```r
testthat::test_dir("tests/testthat")
```

or from a shell:

```bash
Rscript tests/testthat.R
```

Requires the `testthat` package (not a runtime dependency of the app itself, so it's
not auto-installed by `global.R` — install it with `install.packages("testthat")` if
missing).

The suite runs on every push and pull request (GitHub Actions); the online demo is
rebuilt from `main` only after it passes. `DESCRIPTION` lists the app's dependencies and
`renv.lock` pins the versions used in development and CI (`renv::restore()` recreates
them); running the app never requires renv — `global.R` still installs whatever is
missing.

## Structure

```
iDPSIR/
├── app.R                     # entry point
├── global.R                  # auto-installs missing packages, then loads them; source() of every file (order matters)
├── R/
│   ├── schema.R              # configurable DPSIR schema (levels, order, palettes, vocabularies)
│   ├── validate.R             # node/edge validation against the schema
│   ├── graph.R                # igraph builder, layered layout, network/community visuals
│   ├── metrics.R              # centralities, general metrics, strength & confidence, DPSIR descriptors
│   ├── pathways.R             # causal pathways that follow the DPSIR order; effect = product of signed strengths (with band)
│   ├── loop_analysis.R        # interaction matrix (signed strengths, self-regulation on the diagonal) and the push vector, used by the temporal engine
│   ├── structural.R           # edge strengths as standardized path coefficients (beta): Weak/Moderate/Strong classes, uncertainty bands, r-squared shortcuts, the rho(B) < 1 check, conversion of older files
│   ├── sufficiency.R          # primary Scenarios reading: the path-analysis total effect of each push (product of betas along each causal path) - worsening (pressure) vs. mitigation (response) vs. net, per Impact, plus a confidence check (every beta resampled within its uncertainty band)
│   ├── temporal.R             # optional discrete-time-window simulation: runs the pressure/response scenario forward window by window, until the response neutralizes the Impact or for a fixed number of windows
│   ├── responses.R            # get_feedback_categories(): the Response levels of a schema
│   ├── reach.R                # response_reach(): how far a response's influence travels through the network - pure graph traversal, independent of both readings above
│   ├── scenario_plots.R       # per-Impact temporal line chart and prioritization chart, shared by the screen, PNG/SVG downloads and the report
│   ├── report.R               # self-contained HTML report builder
│   ├── io.R                   # CSV matrix import, .idpsir.json savepoint read/write, merge_savepoints()
│   ├── core/                  # shared UI components
│   ├── modules/                # Shiny modules
│   │   ├── mod_data.R          # wizard steps: Start/Model/Nodes/Edges/Review (form-based editor)
│   │   ├── mod_graph.R         # Graph tab: filters, display options, pathway highlighting, category/community coloring, save snapshots for the report
│   │   ├── mod_responses.R     # Scenarios tab: build a pressure scenario and a response scenario, apply the sufficiency reading (with an optional temporal-simulation disclosure), reach, save/compare scenarios
│   │   ├── mod_report.R        # Report tab: pick metrics sections + saved graph snapshots + saved scenarios (+ optional temporal simulation), download the HTML report (numbered figure/table captions, parametrization described)
│   │   ├── mod_metrics.R       # Metrics tab: general / strength & confidence / centralities / DPSIR descriptors
│   │   └── mod_wizard.R        # wizard shell tying every step/tab together
│   ├── ui_main.R               # top-level UI (ina_ui)
│   └── server_main.R           # top-level server (ina_server)
├── data/                      # example data (sample_nodes.csv, sample_edges.csv, mangi2007_*.csv, gnanapragasam2026_*.csv incl. parameters and observed effort)
├── data-raw/                  # scripts that build the Sri Lanka, Mangi and port examples, and their first-run versions
├── docs/                      # getting-started tutorial (tutorial.html) and the example savepoints (example_fisheries/mangi/gnanapragasam/port.idpsir.json and the *_default first-run versions, see Example networks below)
├── legacy/                    # code no longer used by the app (equilibrium engine, older scenario/plot code), kept for reference - not sourced
├── tests/
│   ├── testthat.R             # test runner: Rscript tests/testthat.R
│   └── testthat/               # tests for the scientific core (sufficiency, temporal, triggers, growth, relevance, pathways, reach, metrics, io, validate, graph, report); fixtures/ holds older-format savepoints
├── DESCRIPTION / renv.lock    # dependencies (project, not a package) and pinned versions for development/CI
├── LICENSE, CITATION.cff
└── README.md
```

## Data format

**Nodes** (`data/sample_nodes.csv`): `id`, `label`, `dpsir_category` (Driver, Pressure,
State, Impact, Response), `subsystem` (optional grouping, used to filter the graph),
`self_regulation` (optional, a number in [0, 1],
default 0.5 — the share of a factor's deviation that fades by itself each time window;
only used by the optional temporal simulation, see [Self-regulation](#self-regulation)
below), `growth_rate` (optional, default 0, greater than −1 — how the factor's
base level moves by itself per time window, e.g. population growth, independent of any
edge; only used by the temporal simulation), `growth_cap` (optional — the level, in
the factor's own units, where that growth stops, e.g. a licence cap), `reference_value` (optional — the factor's initial level in its own units),
`sd` (optional — its typical variation, a standard deviation in the same units; the
node form also accepts a coefficient of variation), `threshold_level` (optional, State
only, blank for most — the level in the factor's own units at which ALL of its outgoing
edges switch on together; see [State triggers](#state-triggers)),
`threshold_direction` (optional: `auto`, the default, reads the direction from the
initial level; `both` counts a move of that size either way), `descriptor` (optional
free-text description of what the factor represents — documentation only, not read by
any calculation), `endpoint_class` (Impact only, optional: `ecological` — the default —,
`service` or `welfare`) and `value_v` (Impact only, optional, 0–1: the social value of a
service/welfare Impact, set by hand or with "Elicit values (swing weights)" on the Nodes
step; always 1 for an ecological Impact). `interaction_type` also accepts the vocabulary
of the relevance specification (increases/triggers/improves/sustains → positive,
reduces/mitigates/decreases → negative).

Older files may carry `uncertainty` and `controllability` columns: they were removed
because they never entered any calculation (the uncertainty that matters is each edge's
strength band), and are ignored on load with a note.

**Edges** (`data/sample_edges.csv`): `from`, `to`, `interaction_type` (positive/negative
— required: the sign has no default), `weight` (the edge's **strength** as a
standardized path coefficient beta: how many standard deviations the target moves when
the source moves by one), `weight_low`/`weight_high` (optional uncertainty band of the
strength), `strength_class` (optional: `weak`, `moderate`, `strong`), `evidence_type`,
`reference` (optional DOI/URL/citation backing the link, listed in the report if
included).

**What you need to enter.** Only the structure (nodes with their category, edges) and
the sign of each edge are required — everything else has a default, and the network
runs with them (results are then qualitative; the Review step and the report say how
many edges rely on a default). Fields in the same group replace each other — fill in
one:

| Group | Fill in one of (priority order) | Default |
|---|---|---|
| Strength of an edge | beta directly > r-squared (the form converts it: \|beta\| = sqrt(r²)) > class | Moderate |
| Uncertainty of an edge | `weight_low`/`weight_high` > r-squared plus sample size n (band from the standard error) > band of the class | band of the class |

| Class | Strength used | Uncertainty band |
|---|---|---|
| Weak | 0.15 | 0 – 0.3 |
| Moderate (default) | 0.45 | 0.3 – 0.6 |
| Strong | 0.80 | 0.6 – 1.0 |

The effect of a scenario is the product of the strengths along each causal path,
summed over paths, so a response far from an Impact is naturally attenuated. The
network is blocked at "Build" if its feedback loops would amplify without bound
(spectral radius of the strength matrix at or above 1); the message names the edges on
the loop. **Older files** (savepoints and CSVs from before standardized strengths) are
converted on load (tick "Convert from older relative weights" for a CSV) so that their
static results stay exactly the same; the Start step reports the conversion.

**Default DPSIR connections:** Driver→Pressure, Pressure→State, State→Impact,
Impact→Response, and Response→{Driver, Pressure, State, Impact}. The schema is
configurable, so this order and vocabulary can be adjusted per project.

**Modeling convention — State nodes are neutral measurements**, e.g. `Fish stock`,
`Coral cover`, not `Fish stock decline`/`Coral degradation`. The direction (is more of
it good or bad) belongs on the edges (`interaction_type`), not baked into the node's
name — naming a State after the problem it's usually associated with quietly assumes
a sign that can drift out of sync with the actual edges. All the example networks
follow this (with one documented, internally-consistent exception in the
Gnanapragasam network). The app never checks this for you — see the tutorial's
[Modeling convention](docs/tutorial.html#conventions) section for the full sign table,
the golden rule that keeps a node's edges consistent, and how to read the temporal
simulation's Verdict once your signs are in place.

### Self-regulation

`self_regulation` (0–1, default 0.5) is the share of a factor's deviation that fades by
itself each window, independently of the network: 0 = nothing fades and everything
that arrives accumulates (a stock with no replenishment, a persistent contaminant);
0.3 = 30% of the deviation fades each window (a population rebuilding, a habitat
regenerating); 1 = no memory, the factor only reflects what arrives in the current
window.

Each window: *new value = (1 − self_regulation) × previous value + what arrives through
the edges + the push*.

Example — fishing effort (P) → fish stock (S) → catch decline (I), with strengths 0.7
and 0.6 (both negative) and a pressure of 1 standard deviation:

| Case | Window 2 | 4 | 8 | 12 |
|---|---|---|---|---|
| Ongoing pressure, self-regulation 0 everywhere — fish stock | −0.70 | −4.20 | −19.6 | −46.2 |
| Ongoing pressure, stock recovers 30% per window — fish stock | −0.70 | −1.53 | −2.14 | −2.29 (settles at −0.7 ÷ 0.3 = −2.33) |
| Ongoing pressure, self-regulation 1 everywhere — fish stock | −0.70 | −0.70 | −0.70 | −0.70 (same as the static reading) |
| One-off pressure, stock recovers 30% per window — fish stock | −0.70 | −0.34 | −0.08 | −0.02 (back to normal) |

Under a constant load, a factor settles at *load ÷ self-regulation*: a contaminant with
self-regulation 0.05 accumulates up to 20 times what arrives each window, which is how
a small per-window pressure can still cross a threshold through accumulation.

| Self-regulation | Half-life of recovery | Build-up at equilibrium (1 ÷ self-regulation) | Typical of |
|---|---|---|---|
| 0.05 | 13.5 windows | 20× | contaminant in sediment |
| 0.10 | 6.6 windows | 10× | reef recovery, long-lived species |
| 0.30 | 1.9 windows | 3× | short-cycle fish stock |
| 0.50 (default) | 1 window | 2× | water quality that renews quickly |
| 1 | — | 1× | monthly income, catch in the window |

### State triggers

A State with a threshold passes its effect on only once it crosses that level — a
collapse point, for example a fish stock falling below 85 t. The model works in
standard deviations: the threshold becomes *z = (threshold level − initial level) /
typical variation* (1 for either when blank), and the trigger is open when the State's
deviation has crossed *z* in its direction. It is used by both readings:

- **Sufficiency (static)** — the State's deviation under the scenario decides the gate,
  and the Scenarios tab shows a *State triggers* table: open or closed under the
  pressure alone and with the response, and whether the response closes it. An Impact
  held back by a closed trigger is reported as neutralized by the trigger, and *Reach*
  also reports what the scenario actually reaches, not crossing closed triggers.
- **Temporal simulation** — checked every window, by the *accumulated* State level
  (default) or by the *load* arriving in each window (or both, to compare). A weak but
  steady pressure may never trigger by load and still trigger by accumulation — so the
  two readings can disagree, as in the Gnanapragasam example, where the stock's trigger
  (B_MSY) stays closed in a single instant and opens by accumulation in 2012 (window 8).

Pushes are shares of one standard deviation (100% = 1 SD, up to 500%); a factor with a
typical variation also takes its push in its own units. Older files with an
`activation_threshold` fraction *f* are converted on load to a threshold level
*reference × (1 − f)* in either direction, which reproduces the old rule |x| ≥ f·reference.

## Example networks

Three ready-to-load networks, from smallest to most complete — see the tutorial's
[Example networks](docs/tutorial.html#examples) section for a full, numbers-backed
explanation of each; the short version:

- **Fisheries** — 5 nodes, a single closed feedback loop (Driver → Pressure → State →
  Impact → Response → back to Driver). No underlying CSV, just a savepoint; the
  simplest way to get oriented with the wizard and the Graph/Scenarios tabs before
  anything else adds complexity.
  [`docs/example_fisheries.idpsir.json`](docs/example_fisheries.idpsir.json).
- **Mangi et al. 2007** — 22 factors, 33 links, built from the indicator scheme of a
  published coral-reef-fisheries paper (*Ocean & Coastal Management*, 50(5-6), 463-480);
  every link cites the article's section. Simplified for monitoring: no two indicators
  in a cause-effect chain (the urchin release is one State, sea urchin density, fed by
  its own Pressure, triggerfish fishing). Links are classes (the article gives no
  strengths); the one parameter is the 3.7%/yr population growth. Four saved scenarios:
  the 2007 measures as written and as enforced, plus the recommended ones, and all of
  them fully complied — the only one that neutralizes every Impact, for about twenty years
  before population growth overtakes it.
  [`docs/example_mangi.idpsir.json`](docs/example_mangi.idpsir.json) or
  [`data/mangi2007_nodes.csv`](data/mangi2007_nodes.csv) /
  [`data/mangi2007_edges.csv`](data/mangi2007_edges.csv); built by
  [`data-raw/mangi2007_build.R`](data-raw/mangi2007_build.R).
- **Gnanapragasam et al. 2026** — 17 nodes, 20 edges, Sri Lanka's small-scale fisheries
  (*Marine Policy*, 189, 107095), one window per year from 2004, parametrized from the
  paper's own data (see [below](#sri-lanka-example-how-it-was-parametrized)).
  Post-disaster aid (2005–2012) restores fishers' income and, through the boats it
  buys, drives effort up and the stock below B_MSY in 2012; the paper's effort quota
  (25% cut, from 2022) brings it back by 2030. The app's main worked example — full
  walkthrough in the tutorial.
  [`docs/example_gnanapragasam.idpsir.json`](docs/example_gnanapragasam.idpsir.json)
  (scenario 2005–2030 pre-configured) or the underlying
  [`data/gnanapragasam2026_nodes.csv`](data/gnanapragasam2026_nodes.csv) /
  [`data/gnanapragasam2026_edges.csv`](data/gnanapragasam2026_edges.csv).

- **Port operations (didactic)** — 15 nodes, 20 edges, one window per season. Dredging
  clouds the water (fauna behaviour, primary production) while the cargo terminal's
  runoff carries metals (seafood contamination, CONAMA water-quality class). The Impacts
  weigh differently (class and value v), and the **Impact prioritization** points to one
  response at a time: runoff treatment first (seafood contamination has the top
  priority), then a work window for the dredging campaign — which the temporal
  simulation shows is needed only during the campaign, while the runoff treatment must
  start early because the biota accumulates metals. Comes with four saved scenarios.
  [`docs/example_port.idpsir.json`](docs/example_port.idpsir.json) or
  [`data/port_nodes.csv`](data/port_nodes.csv) / [`data/port_edges.csv`](data/port_edges.csv);
  built by [`data-raw/port_build.R`](data-raw/port_build.R).

Load any of them from the wizard's Start step (Load savepoint), or via CSV import for
the three that have plain tables.

**Causal-assumption variant.** `docs/example_gnanapragasam_noaidfleet.idpsir.json` is the Sri Lanka example without
the two "aid → fleet capacity" links (built by
[`data-raw/gnanapragasam2026_variant_build.R`](data-raw/gnanapragasam2026_variant_build.R)):
the aid then reaches only fisher income loss, the stock never falls below B_MSY, and
the simulated effort misses the observed one (RMSE 6,152 against 658) - the data support
the assumption that the aid enlarged the fleet.

**First run (defaults only).** `docs/example_mangi_default.idpsir.json` and
`docs/example_gnanapragasam_default.idpsir.json` hold the same networks with every setting
at the app's default (every link moderate, self-regulation 0.5, no growth or thresholds),
built by [`data-raw/first_run_build.R`](data-raw/first_run_build.R). Compared with the full
examples they show what the structure alone decides and what the parametrization changes:
for Mangi the verdicts and the priority agree (only the growth adds a deadline); for Sri Lanka the
defaults give the optimistic answer and the article's parameters reverse it (tutorial,
"First run").

### Sri Lanka example: how it was parametrized

One window is one year; window 0 is 2004, the last year before the post-tsunami aid, so
the reference values are 2004 levels. Every value below is either taken from the paper,
derived from it, calibrated against it, or — where marked — from outside it. The tables
are built by [`data-raw/gnanapragasam2026_build.R`](data-raw/gnanapragasam2026_build.R),
which also writes the savepoint; [`data-raw/gnanapragasam2026_figures.R`](data-raw/gnanapragasam2026_figures.R)
draws the figures.

- **Fishing effort** was digitized exactly from the paper's Fig. 4 (a vector figure):
  [`data/gnanapragasam2026_effort_observed.csv`](data/gnanapragasam2026_effort_observed.csv),
  7,181 thousand kW-days in 1990 to 16,531 in 2021. Its SD over that series (4,877) is
  the model unit of effort, fleet capacity and the quota — the same sample the paper's
  standardized relationships were estimated on.
- **Fish stock** comes from the paper's Gordon-Schaefer model: B_MSY = 1.5 × H_MSY =
  345 kt, so K = 690 kt and, at equilibrium, B(E) = K(1 − E/30,924), which reproduces
  the paper's Table 4. Its threshold is B_MSY itself (falling): the usual limit
  reference point, half of B_MSY (a management convention, not in the paper), was tried
  first and is never crossed at realistic levels, so the stock would never reach its
  Impacts.
- **The two aid strengths** were fitted to the observed effort, 2006–2021
  (R² = 0.93 within the fitted years; fit rewritten in
  [`analysis/validation_srilanka/calibrate.R`](analysis/validation_srilanka/calibrate.R)).
- **Self-regulation**: in the temporal simulation a link passes its strength every
  window, and a factor with self-regulation *s* settles at strength ÷ *s*. States whose
  strengths come from an equilibrium (the Schaefer stock, the motorized share) keep
  *s* = 1 so the static and temporal readings agree; the fleet, whose boats persist,
  keeps 0.02.

**Two different checks.** *Consistency with the paper's bioeconomic model* - the app's
replay against that model's outputs - and *validation against data* - the observed effort
out of sample. For the second, the aid strengths were fitted on 2006-2014 and effort was
predicted for 2015-2021 ([`analysis/validation_srilanka/validate.R`](analysis/validation_srilanka/validate.R)):
RMSE 559 thousand kW-days (bias +351), lower than holding the 2014 value (632) or the
2006-2014 linear trend (5,737); the 90% band from the strengths' uncertainty covers every
year. 2015-2021 is a plateau, though, so the test says little about the aid's effect;
with a rolling origin the model beats holding the last value from 2014 on, ties in 2013
and loses in 2012 (fitted with only three post-war years, that aid is over-estimated).

Consistency with the bioeconomic model: the stock falls below B_MSY in 2012 (the
paper: catch passes H_MSY in 2012) and is at 307 kt in 2021 (≈ 321 kt); with the 25%
quota from 2022, effort reaches 12,470 thousand kW-days in 2030 (E_MEY = 12,287) and
the stock 406 kt (413 kt in Table 4).

![Effort and fish stock, observed and simulated](docs/example_gnanapragasam_validation.png)

**Parameters and sources** (`data/gnanapragasam2026_parameters.csv`):

| item | value | source |
|---|---|---|
| Window length | 1 year | Annual statistics (article, 1990-2021) |
| Window 0 | 2004 | Last year before the post-tsunami aid |
| Effort SD (P1, D3, R3 units) | 4877 thousand kW-days | SD of the 1990-2021 series digitized from Fig. 4 (vector figure) |
| Effort in 2004 (reference, P1 and D3) | 8328 thousand kW-days | Fig. 4 (digitized) |
| Fishing effort -> Fish stock (beta) | -0.825 | sqrt(R2 = 0.68), CPUE vs effort (section 3.3); sign: more effort, less stock |
| Fishing effort -> Fish stock (band) | 0.622 - 1.027 | 95% interval of beta from R2 and n = 32 years |
| Carrying capacity K | 690 kt | 2 x B_MSY; B_MSY = 1.5 x H_MSY (section 3.5.1, Table 3) |
| Intrinsic growth r | 1.33 per year | 4 x H_MSY / K (Gordon-Schaefer) |
| Fish stock in 2004 (reference) | 504.4 kt | Equilibrium K (1 - E / E_max) at the 2004 effort; reproduces Table 4 |
| Fish stock SD | 108.9 kt | (K / E_max) x effort SD |
| Fish stock self-regulation | 1 | Biomass taken at its Schaefer equilibrium each year (r = 1.33/yr: recovery rate r B / K about 0.72/yr); sr = 1 keeps the temporal equilibrium equal to B(E) |
| Fish stock threshold (B_MSY) | 345.2 kt (falling) | B_MSY = 1.5 x H_MSY (article). B_lim = 0.5 B_MSY (convention) was tested and is never crossed |
| Coastal population growth | 0.8% per year | External (national statistics), not in the article |
| Coastal population in 2004 | 19.4 million | External (national statistics), not in the article |
| Per-capita demand growth | 2.3% per year | Consumption doubled over three decades (section 3.1, Fig. 5) |
| Per-capita demand ceiling | 31 kg per person | Peak of 31 kg in 2016 (section 3.1) |
| Per-capita demand in 2004 | 23.5 kg per person | 31 kg discounted at 2.3%/yr back to 2004 |
| Fleet capacity growth | 1% per year | Effort trend 1990-2004 (Fig. 4), before the aid |
| Fleet capacity self-regulation | 0.02 | Boats persist; effort stayed on a plateau after the aid (Fig. 4) |
| Post-tsunami aid -> Fleet capacity | 0.34 | Fitted with the post-war aid by least squares to Fig. 4, 2006-2021 (R2 = 0.93; a common value fits worse, R2 = 0.84) |
| Post-war aid -> Fleet capacity | 0.08 | Fitted with the post-tsunami aid (same fit) |
| Aid periods | 2005-2009 (windows 1-5); 2010-2012 (windows 6-8) | Section 3.1 and Fig. 6 |
| Fleet capacity -> Fishing effort | 0.85 (band 0.75 - 0.95) | Effort = boat power x fishing days (section 2.2.1): capacity sets effort; kept below 0.9 so the three drivers of effort explain at most 100% of its variation |
| Fleet motorization in 2004 / SD | 40% / 15.5 points | Fleet split 60:40 non-motorized before 2004, 60:40 motorized now (section 3.4); SD calibrated to that rise |
| Effort-based quota -> Fishing effort | 1 (definitional) | The quota cuts effort directly, in effort units |
| Quota size | 5% of 2021 effort = 827; 25% = 4,133 thousand kW-days | Table 4 (5% = MSY, 25% = MEY) |
| Flow factors' self-regulation | 1 (no memory) | Effort, demand, catch and income are flows, not stocks |
| Other edge strengths | classes weak 0.15 / moderate 0.45 / strong 0.80 | Qualitative links (section 3, Table 2) |

**Nodes** (`data/gnanapragasam2026_nodes.csv`, main columns):

| id | label | category | self_regulation | growth_rate | growth_cap | reference_value | sd | threshold_level |
|---|---|---|---|---|---|---|---|---|
| D1 | Coastal population | Driver | 0.50 | 0.008 |  |   19.4 |  |  |
| D2 | Per-capita fish demand | Driver | 1.00 | 0.023 | 31 |   23.5 |  |  |
| D3 | Fleet capacity (boats x power) | Driver | 0.02 | 0.01 |  | 8328.0 | 4877.0 |  |
| D4 | Indian trawler incursions | Driver | 1.00 |  |  |  |  |  |
| P1 | Fishing effort | Pressure | 1.00 |  |  | 8328.0 | 4877.0 |  |
| P2 | Illegal bottom trawling | Pressure | 1.00 |  |  |  |  |  |
| S1 | Fish stock (biomass) | State | 1.00 |  |  |  504.4 |  108.9 | 345.2 |
| S2 | Fleet motorization (% motorized) | State | 1.00 |  |  |   40.0 |   15.5 |  |
| I1 | Catch decline | Impact | 1.00 |  |  |  |  |  |
| I2 | Fisher income loss | Impact | 1.00 |  |  |  |  |  |
| I3 | Conflict with Indian fishermen | Impact | 0.50 |  |  |  |  |  |
| I4 | Traditional fishing decline | Impact | 0.50 |  |  |  |  |  |
| I5 | Loss of traditional fishing culture | Impact | 0.30 |  |  |  |  |  |
| R1 | Post-tsunami aid (2005-2009) | Response | 1.00 |  |  |  |  |  |
| R2 | Post-war aid (2010-2012) | Response | 1.00 |  |  |  |  |  |
| R3 | Effort-based quota | Response | 1.00 |  |  |  | 4877.0 |  |
| R4 | Combating poaching | Response | 1.00 |  |  |  |  |  |

**Edges** (`data/gnanapragasam2026_edges.csv`):

| link | sign | strength | band | source |
|---|---|---|---|---|
| Coastal population → Fishing effort | positive | weak |  | class |
| Per-capita fish demand → Fishing effort | positive | moderate |  | class |
| Fleet capacity (boats x power) → Fishing effort | positive | 0.850 | 0.75 – 0.95 | given |
| Indian trawler incursions → Illegal bottom trawling | positive | strong |  | class |
| Fishing effort → Fish stock (biomass) | negative | 0.825 | 0.622 – 1.027 | r2 |
| Fishing effort → Fleet motorization (% motorized) | positive | 0.750 |  | calibrated |
| Illegal bottom trawling → Fish stock (biomass) | negative | moderate |  | class |
| Fish stock (biomass) → Catch decline | negative | strong |  | class |
| Fish stock (biomass) → Fisher income loss | negative | moderate |  | class |
| Fish stock (biomass) → Conflict with Indian fishermen | negative | moderate |  | class |
| Fleet motorization (% motorized) → Catch decline | positive | moderate |  | class |
| Fleet motorization (% motorized) → Conflict with Indian fishermen | positive | weak |  | class |
| Fleet motorization (% motorized) → Traditional fishing decline | positive | strong |  | class |
| Fleet motorization (% motorized) → Loss of traditional fishing culture | positive | moderate |  | class |
| Post-tsunami aid (2005-2009) → Fleet capacity (boats x power) | positive | 0.345 |  | calibrated |
| Post-tsunami aid (2005-2009) → Fisher income loss | negative | moderate |  | class |
| Post-war aid (2010-2012) → Fleet capacity (boats x power) | positive | 0.085 |  | calibrated |
| Post-war aid (2010-2012) → Fisher income loss | negative | moderate |  | class |
| Effort-based quota → Fishing effort | negative | 1.000 | 0.9 – 1 | given |
| Combating poaching → Indian trawler incursions | negative | moderate |  | class |


## Workflow

The wizard has six steps: **Start** (new project, CSV import, load a `.idpsir.json`
savepoint, or combine two or more savepoints into one) → **Model** (schema/palette,
advanced) → **Nodes** → **Edges** → **Review and build** → **Explore**, which itself
has four tabs:

- **Graph** — layered (by DPSIR category) or circular layout, filters, node/edge
  emphasis, spacing controls, and pathway highlighting (chains that follow the DPSIR
  order, ranked by their effect: the product of the signed strengths along the chain, the
  path's indirect effect in path analysis). "Color nodes by" switches
  between DPSIR category and detected community (Louvain/Walktrap/Infomap/Label
  Propagation, redrawn with edges, not bare colored dots) without leaving the tab.
  Dragging a node pins it in place (persisted in the savepoint, "Reset dragged
  positions" clears it); category/community and edge-type legends can each be
  toggled off. Any view can be saved as a named snapshot to include in the report.
- **Scenarios** — build two independent "pushes": a **pressure scenario** (which
  Drivers/Pressures are worsening, and how strongly) and a **response scenario**
  (which Responses are active, and how strongly). Applying them runs the primary,
  **sufficiency** reading (`R/sufficiency.R`; the path-sum expansion converges when the
  effect matrix's spectral radius is below 1, checked when the graph is built): for each Impact, how
  much the pressure scenario worsens it, how much the response scenario mitigates (or
  worsens) it, and whether that mitigation is enough to neutralize the worsening (an
  Impact the pressure does not reach is reported as **Not affected**, not neutralized;
  all in standard deviations of each factor, 100% = a push of 1 SD; a last column says
  whether the verdict holds for self-regulation 0.25–1, the reading itself being the
  temporal equilibrium with self-regulation 1) —
  plus a confidence check (% of simulations, resampling every edge's strength within
  its uncertainty band, in which the verdict holds; one row for the scenario as set with
  the sliders, one per response alone at 100%) and an **Impact prioritization**:
  relevance = value v × importance D (the pressure's total effect on that Impact,
  relative to the most affected one — with standardized strengths this is the Levins
  equilibrium of the relevance specification) × reliability (share of simulations in
  which that effect keeps its sign), and priority = relevance × gap (the share of the
  worsening the response leaves uncovered), with a bar chart, a CSV download and a
  report section, and a **Rank stability** column (share of 500 variations - values v
  changed by up to 20%, product or weighted-sum index - in which each Impact keeps its
  rank). **Include structural uncertainty** also drops links from the resampled draws,
  more often the weaker their evidence (0.2 expert/policy/blank, 0.1 literature or
  observations, 0 for definitions, regressions, calibrations and strengths estimated
  from data). The sufficiency reading above is deliberately static and ignores
  a node's `self_regulation` on purpose — that attribute (and `growth_rate`) only
  feeds the optional temporal simulation below, never the primary verdict. **Reach**
  always shows how many factors — and how many Impacts — a response's influence can
  touch through some causal path, independent of the reading above. An optional
  **temporal simulation** disclosure (`R/temporal.R`) runs the same two scenarios
  forward window by window instead of reading a single instant — useful when a
  response might, windows later, become a new pressure itself. **Scenario to
  simulate** picks the scenario applied above or any saved one (with its own temporal
  settings), to revisit its tables and charts without re-applying it. Pressure and response
  each run as **"Added every window"** (default: the push is applied again every
  window), **"Applied once and held"** (window 1 only; the level it creates fades
  only through self-regulation) or **"For a number of windows"** (a start window and a
  duration per factor, e.g. an aid programme that ran five years). A factor's
  `growth_rate` moves its base level by itself in both runs — even when it is not in
  the scenario (on by default) — optionally up to its `growth_cap`; growth and
  self-regulation are separate (self-regulation fades the deviation the network causes,
  growth moves the base level), and an **Edge intensity by window** table (CSV) shows
  what each link out of a growing factor or a thresholded State passes on. The simulation runs **until the response neutralizes
  the Impact** (default, up to 50 windows, editable: it stops at the first window in
  which every Impact the response reaches, and that is worsened in either run, is at
  or below zero or within the tolerance below — or reports "Not neutralized within N windows"), or for a
  **fixed number of windows**; **Continue after neutralizing** keeps running N more
  windows, since with a growing trend a neutralization may not last. A table shows how each Impact changes window by window
  (the stop window highlighted), with a "Neutralized (relative)" label when the net
  value is within a tolerance of the baseline (default 5%) — "until neutralized"
  also stops there (tolerance 0 = only zero counts). An option runs the baseline
  **without any response** (ignoring Impact → Response links). A chart shows one panel
  per Impact, dashed baseline vs. solid Net, points colored by that window's Verdict,
  the neutralized zone (Net ≤ 0) shaded and the stop window marked (downloadable as
  PNG/SVG, and included in the report if selected). The key message: *what makes an
  Impact converge is the chain's self-regulation; the response mode decides the
  effort; the stop criterion says in which window the problem was solved.* It's an
  explicit short-horizon integration, not a calibrated forecast — read it for the
  *direction* of an indirect, delayed effect, not for the absolute magnitude. Save a scenario and compare
  multiple saved scenarios' reach side by side; saved scenarios are kept in the savepoint
  (their settings) and recomputed when it is loaded. The temporal simulation runs on
  **Run simulation**, and the number of resamples behind the confidence readings is
  selectable (100 or 300, the maximum, since the app computes in a single process; an
  estimate of how long "Apply scenario" will take, measured on the network and the
  computer, is shown next to it). The older equilibrium-based reading
  (loop analysis / Levins 1974 — stability check, immediate vs. equilibrium effect,
  step-by-step trajectory, robustness and self-regulation-sensitivity checks, edge
  ranking) was removed: it required a stability condition no network built by this
  app's schema can ever meet, and could silently invert a prediction's sign. Its code
  is kept in `legacy/` for reference.
- **Interpretation** — a plain-language reading of the Scenarios results for the applied
  or any saved scenario: how many worsened Impacts are neutralized, one sentence per
  Impact in priority order (neutralized, % of the worsening covered and how much
  stronger the response would have to be, not covered, worsened by the response),
  key messages (the Impact to act on first, side effects, fragile verdicts, tight verdicts with the links worth checking), a coverage
  chart and every scenario side by side. The same scenario is shown in the Scenarios
  results, the temporal simulation and this tab (one selector in each, kept in sync);
  the report opens its scenario part with the same reading.
- **Metrics** — general network metrics; **strength and confidence** of the network as
  a whole (link classes, explained variance, loop amplification, Driver-to-Impact total
  effects; where the strengths came from, band widths, evidence and references, expected
  absent links, sign and interval of the total effects under the link bands - also by
  transition, least founded first); centralities; and DPSIR descriptors (gaps such as
  Impacts without a Response, or Pressures not covered by one).
- **Report** — pick which sections (saved graph snapshots, metrics, centralities,
  descriptors, edge references, saved scenarios, reproducibility info — R/package
  versions and the parameters used in the stochastic analyses) go into one
  self-contained downloadable HTML report. Every report opens the same way regardless
  of what's checked: a "Report summary" (network name/author/savepoint file, plus each
  selected scenario's pressure/response definition) and a "How to read these
  results" legend (sign convention, what "neutralized" means, the Verdict color key) —
  then the decision-relevant sections (Response sufficiency, Reach, Temporal
  simulation, References) in that order, with the descriptive material (graph image,
  general metrics, centralities, DPSIR descriptors) demoted to a "Network
  characterization (appendix)" section at the end. Scenarios are always listed in
  ascending order regardless of the order they were selected in.

A savepoint (`.idpsir.json`) can be downloaded from any step and reloaded later to
resume a project.

## License and citation

MIT (see [`LICENSE`](LICENSE)). To cite iDPSIR, use [`CITATION.cff`](CITATION.cff)
(GitHub shows it under "Cite this repository").
