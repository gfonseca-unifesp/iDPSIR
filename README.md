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

The scientific core (`R/loop_analysis.R`, `R/sufficiency.R`, `R/temporal.R`,
`R/reach.R`, `R/metrics.R`, `R/io.R`, `R/validate.R`) has an automated `testthat`
suite, checked against hand-verified numeric examples (a classic stable
trophic-chain matrix, the real Mangi et al. 2007 fisheries network, the reference
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

## Structure

```
iDPSIR/
├── app.R                     # entry point
├── global.R                  # auto-installs missing packages, then loads them; source() of every file (order matters)
├── R/
│   ├── schema.R              # configurable DPSIR schema (levels, order, palettes, vocabularies)
│   ├── validate.R             # node/edge validation against the schema
│   ├── graph.R                # igraph builder, layered layout, network/community visuals
│   ├── metrics.R              # centralities, general metrics, DPSIR descriptors
│   ├── pathways.R             # schema-aware causal pathway analysis
│   ├── loop_analysis.R        # loop analysis (Levins 1974): interaction matrix (incl. optional per-node self-regulation, reused by the temporal engine below) and the older equilibrium reading (press perturbation, stability check, trajectory, robustness, edge/self-regulation sensitivity) - kept defined and tested, but no longer called from the UI/report, superseded by sufficiency.R and temporal.R
│   ├── structural.R           # edge strengths as standardized path coefficients (beta): Weak/Moderate/Strong classes, uncertainty bands, r-squared shortcuts, the rho(B) < 1 check, conversion of older files
│   ├── sufficiency.R          # primary Scenarios reading: the path-analysis total effect of each push (product of betas along each causal path) - worsening (pressure) vs. mitigation (response) vs. net, per Impact, plus a confidence check (every beta resampled within its uncertainty band)
│   ├── temporal.R             # optional discrete-time-window simulation: runs the pressure/response scenario forward window by window, until the response neutralizes the Impact or for a fixed number of windows
│   ├── responses.R            # get_feedback_categories/find_response_targets (still used); apply_response and the older scenario-comparison helpers are kept but no longer called, superseded by sufficiency.R/temporal.R
│   ├── reach.R                # response_reach(): how far a response's influence travels through the network - pure graph traversal, independent of both readings above
│   ├── scenario_plots.R       # shared trajectory/edge-sensitivity/per-Impact temporal line chart drawing, reused on screen, in PNG/SVG downloads, and in the report
│   ├── report.R               # self-contained HTML report builder
│   ├── io.R                   # CSV matrix import, .idpsir.json savepoint read/write, merge_savepoints()
│   ├── core/                  # shared UI components
│   ├── dpsir/                 # earlier, non-schema-aware versions kept for reference (not sourced)
│   ├── modules/                # Shiny modules
│   │   ├── mod_data.R          # wizard steps: Start/Model/Nodes/Edges/Review (form-based editor)
│   │   ├── mod_graph.R         # Graph tab: filters, display options, pathway highlighting, category/community coloring, save snapshots for the report
│   │   ├── mod_communities.R   # earlier standalone Communities tab, kept for reference (not sourced; superseded by mod_graph.R's "Color nodes by")
│   │   ├── mod_responses.R     # Scenarios tab: build a pressure scenario and a response scenario, apply the sufficiency reading (with an optional temporal-simulation disclosure), reach, save/compare scenarios
│   │   ├── mod_report.R        # Report tab: pick metrics sections + saved graph snapshots + saved scenarios (+ optional temporal simulation), download the HTML report (numbered figure/table captions, parametrization described)
│   │   ├── mod_metrics.R       # Metrics tab: general / centralities / DPSIR descriptors
│   │   └── mod_wizard.R        # wizard shell tying every step/tab together
│   ├── ui_main.R               # top-level UI (ina_ui)
│   └── server_main.R           # top-level server (ina_server)
├── data/                      # example data (sample_nodes.csv, sample_edges.csv, mangi2007_*.csv, gnanapragasam2026_*.csv)
├── docs/                      # getting-started tutorial (tutorial.html) and three example savepoints (example_fisheries/mangi/gnanapragasam.idpsir.json, see Example networks below)
├── tests/
│   ├── testthat.R             # test runner: Rscript tests/testthat.R
│   └── testthat/               # tests for the scientific core (loop_analysis, sufficiency, temporal, reach, metrics, io, validate, graph); fixtures/ holds older-format savepoints
└── README.md
```

## Data format

**Nodes** (`data/sample_nodes.csv`): `id`, `label`, `dpsir_category` (Driver, Pressure,
State, Impact, Response), `subsystem`, `uncertainty` (optional, a number in [0, 1],
default 0.5 — how confident you are this node is described correctly; thickens the
node's border on the graph, not read by any calculation), `controllability` (optional,
a number in [0, 1], default 0.5 — how much a manager can influence this factor
directly, not read by any calculation), `self_regulation` (optional, a number in [0, 1],
default 0.5 — the share of a factor's deviation that fades by itself each time window;
only used by the optional temporal simulation, see [Self-regulation](#self-regulation)
below), `growth_rate` (optional, default 0 — a
factor's own exogenous trend per time window, e.g. population growth, independent of
any edge), `reference_value` (optional, default 1 — the scale a factor's simulated
change is measured against when it has an `activation_threshold` set),
`activation_threshold` (optional, blank for most factors; a fraction 0-1 of the
factor's own `reference_value` it has to move before ALL of its outgoing edges switch
on together — only allowed when the factor is State), `descriptor` (optional
free-text description of what the factor represents — documentation only, not read by
any calculation).

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
a sign that can drift out of sync with the actual edges. All three example networks
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

## Example networks

Three ready-to-load networks, from smallest to most complete — see the tutorial's
[Example networks](docs/tutorial.html#examples) section for a full, numbers-backed
explanation of each; the short version:

- **Fisheries** — 5 nodes, a single closed feedback loop (Driver → Pressure → State →
  Impact → Response → back to Driver). No underlying CSV, just a savepoint; the
  simplest way to get oriented with the wizard and the Graph/Scenarios tabs before
  anything else adds complexity.
  [`docs/example_fisheries.idpsir.json`](docs/example_fisheries.idpsir.json).
- **Mangi et al. 2007** — 18 nodes, 31 edges, a real published coral-reef-fisheries
  DPSIR network (*Ocean & Coastal Management*, 50(5-6), 463-480). This is the network
  that caught a real bug during development: the app's older equilibrium-based
  reading (removed since) showed a gear-restriction response making reef degradation
  *worse* — wrong sign. The current sufficiency reading gets it right (see the
  tutorial for the exact numbers).
  [`docs/example_mangi.idpsir.json`](docs/example_mangi.idpsir.json) (pressure/response
  pre-configured) or the underlying
  [`data/mangi2007_nodes.csv`](data/mangi2007_nodes.csv) /
  [`data/mangi2007_edges.csv`](data/mangi2007_edges.csv).
- **Gnanapragasam et al. 2026** — 13 nodes, 14 edges, an artisanal-fisheries network
  (*Marine Policy*, 189, 107095) where a response that directly and sufficiently
  neutralizes its one intended Impact still erodes over time against an independent
  driver trend it can't touch, while the other four Impacts sit entirely outside what
  the response can ever reach. The app's main worked example — full walkthrough in the
  tutorial, illustrated with a network diagram and a per-Impact temporal line chart.
  [`docs/example_gnanapragasam.idpsir.json`](docs/example_gnanapragasam.idpsir.json)
  (pressure/response pre-configured) or the underlying
  [`data/gnanapragasam2026_nodes.csv`](data/gnanapragasam2026_nodes.csv) /
  [`data/gnanapragasam2026_edges.csv`](data/gnanapragasam2026_edges.csv).

Load any of them from the wizard's Start step (Load savepoint), or via CSV import for
the two that have plain tables.

## Workflow

The wizard has six steps: **Start** (new project, CSV import, load a `.idpsir.json`
savepoint, or combine two or more savepoints into one) → **Model** (schema/palette,
advanced) → **Nodes** → **Edges** → **Review and build** → **Explore**, which itself
has four tabs:

- **Graph** — layered (by DPSIR category) or circular layout, filters, node/edge
  emphasis, spacing controls, and pathway highlighting. "Color nodes by" switches
  between DPSIR category and detected community (Louvain/Walktrap/Infomap/Label
  Propagation, redrawn with edges, not bare colored dots) without leaving the tab.
  Dragging a node pins it in place (persisted in the savepoint, "Reset dragged
  positions" clears it); category/community and edge-type legends can each be
  toggled off. Any view can be saved as a named snapshot to include in the report.
- **Scenarios** — build two independent "pushes": a **pressure scenario** (which
  Drivers/Pressures are worsening, and how strongly) and a **response scenario**
  (which Responses are active, and how strongly). Applying them runs the primary,
  always-well-defined **sufficiency** reading (`R/sufficiency.R`): for each Impact, how
  much the pressure scenario worsens it, how much the response scenario mitigates (or
  worsens) it, and whether that mitigation is enough to neutralize the worsening —
  plus a confidence check (% of simulations, resampling every edge's strength within
  its uncertainty band, in which the verdict holds). The sufficiency reading above is deliberately static and ignores
  a node's `self_regulation` on purpose — that attribute (and `growth_rate`) only
  feeds the optional temporal simulation below, never the primary verdict. **Reach**
  always shows how many factors — and how many Impacts — a response's influence can
  touch through some causal path, independent of the reading above. An optional
  **temporal simulation** disclosure (`R/temporal.R`) runs the same two scenarios
  forward window by window instead of reading a single instant — useful when a
  response might, windows later, become a new pressure itself. Pressure and response
  each run as **"Added every window"** (default: the push is applied again every
  window) or **"Applied once and held"** (window 1 only; the level it creates fades
  only through self-regulation). The simulation runs **until the response neutralizes
  the Impact** (default, up to 50 windows, editable: it stops at the first window in
  which every Impact the response reaches, and that the pressure has already worsened,
  is at or below zero — or reports "Not neutralized within N windows"), or for a
  **fixed number of windows**. A table shows how each Impact changes window by window
  (the stop window highlighted), with a "Neutralized (relative)" label when the net
  value is within a tolerance of the baseline (default 5%) and not growing — the
  tolerance only labels the table, it never stops the run. An option runs the baseline
  **without any response** (ignoring Impact → Response links). A chart shows one panel
  per Impact, dashed baseline vs. solid Net, points colored by that window's Verdict,
  the neutralized zone (Net ≤ 0) shaded and the stop window marked (downloadable as
  PNG/SVG, and included in the report if selected). The key message: *what makes an
  Impact converge is the chain's self-regulation; the response mode decides the
  effort; the stop criterion says in which window the problem was solved.* It's an
  explicit short-horizon integration, not a calibrated forecast — read it for the
  *direction* of an indirect, delayed effect, not for the absolute magnitude. Save a scenario and compare
  multiple saved scenarios' reach side by side. The older equilibrium-based reading
  (loop analysis / Levins 1974 — stability check, immediate vs. equilibrium effect,
  step-by-step trajectory, robustness and self-regulation-sensitivity checks, edge
  ranking) is no longer shown in the UI or report — see `R/loop_analysis.R`'s header
  for why (it required a stability condition no network built by this app's schema
  can ever meet, and could silently invert a prediction's sign) — but its functions
  stay defined and tested for reference.
- **Metrics** — general network metrics, centralities, and DPSIR descriptors (gaps
  such as Impacts without a Response, or Pressures not covered by one).
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
