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
through every step and includes a worked example with a downloadable savepoint
([`docs/example_gnanapragasam.idpsir.json`](docs/example_gnanapragasam.idpsir.json)).
The same tutorial is one click away from inside the running app too, via the "Help"
link in the top-right corner.

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
trophic-chain matrix, the real Mangi et al. 2007 fisheries network, and a small
five-node network kept in `docs/example_fisheries.idpsir.json` as a test fixture -
not the tutorial's own worked example, see Data format below). Run it from the
project root:

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
│   ├── sufficiency.R          # primary Scenarios reading: a discounted, short-path-dominated propagated effect (always well-defined, no stability requirement) - worsening (pressure) vs. mitigation (response) vs. net, per Impact, plus a confidence check (edge-weight resampling) and sensitivity to how far the effect is traced
│   ├── temporal.R             # optional discrete-time-window simulation: runs the pressure/response scenario forward window by window (no equilibrium assumption), showing whether a response's benefit holds up or erodes over time
│   ├── responses.R            # get_feedback_categories/find_response_targets (still used); apply_response and the older scenario-comparison helpers are kept but no longer called, superseded by sufficiency.R/temporal.R
│   ├── reach.R                # response_reach(): how far a response's influence travels through the network - pure graph traversal, independent of both readings above
│   ├── scenario_plots.R       # shared trajectory/edge-sensitivity/temporal-storyboard chart drawing, reused on screen, in PNG/SVG downloads, and in the report
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
├── docs/                      # getting-started tutorial (tutorial.html) and a worked-example savepoint (example_gnanapragasam.idpsir.json)
├── tests/
│   ├── testthat.R             # test runner: Rscript tests/testthat.R
│   └── testthat/               # tests for the scientific core (loop_analysis, sufficiency, temporal, reach, metrics, io, validate)
├── PLANO_iDPSIR.md            # restructuring plan and roadmap (in Portuguese)
├── ROADMAP_MELHORIAS_iDPSIR.md # roadmap towards a JOSS/SoftwareX submission (in Portuguese)
├── ROADMAP_FASE9_iDPSIR.md    # roadmap for self-regulation and response reach (in Portuguese)
└── README.md
```

## Data format

**Nodes** (`data/sample_nodes.csv`): `id`, `label`, `dpsir_category` (Driver, Pressure,
State, Impact, Response), `subsystem`, `uncertainty` (low/medium/high),
`controllability` (low/medium/high), `self_regulation` (optional, a number in [0, 1),
default 0 — the fraction of a factor's simulated deviation that reverts each time
window, e.g. a fish stock that partially replenishes; only used by the optional
temporal simulation, see Scenarios below), `growth_rate` (optional, default 0 — a
factor's own exogenous trend per time window, e.g. population growth, independent of
any edge), `reference_value` (optional, default 1 — the scale a factor's simulated
change is measured against when an outgoing edge has a `threshold`, see below).

**Edges** (`data/sample_edges.csv`): `from`, `to`, `weight`, `confidence` (0-1),
`interaction_type` (positive/negative), `evidence_type`, `threshold` (optional,
blank for most edges; a fraction 0-1 of the source factor's `reference_value` it
must move before this edge switches on — only allowed when the source is a State
factor), `reference` (optional DOI/URL/citation backing the link, listed in the
report if included).

**Default DPSIR connections:** Driver→Pressure, Pressure→State, State→Impact,
Impact→Response, and Response→{Driver, Pressure, State, Impact}. The schema is
configurable, so this order and vocabulary can be adjusted per project.

A larger, annotated example — an artisanal-fisheries network adapted from
Gnanapragasam et al. 2026 (Marine Policy), where a well-intentioned response ends up
becoming a new pressure on the very system it was meant to help — is at
[`docs/example_gnanapragasam.idpsir.json`](docs/example_gnanapragasam.idpsir.json);
load it from the wizard's Start step (Load savepoint) or see the
[tutorial](docs/tutorial.html) for a full walkthrough.

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
  plus a confidence check (% of simulations, resampling edge weights within their
  confidence range, that agree on the neutralization verdict) and a check for whether
  the verdict holds up across how far the effect is traced. Unlike the network's own
  math, this reading never requires a "stable" network and never inverts a
  prediction's sign. **Reach** always shows how many factors — and how many Impacts —
  a response's influence can touch through some causal path, independent of the
  reading above. An optional **temporal simulation** disclosure (`R/temporal.R`) runs
  the same two scenarios forward window by window instead of reading a single instant
  — useful when a response might, windows later, become a new pressure itself — with a
  configurable number of windows, an impulse/permanent mode for each scenario, a table
  of how each Impact changes window by window, a progress indicator while it computes,
  and a "storyboard" plotting the network's state per window (downloadable as PNG/SVG,
  and included as a figure in the report if selected). Save a scenario and compare
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
  self-contained downloadable HTML report.

A savepoint (`.idpsir.json`) can be downloaded from any step and reloaded later to
resume a project.

## Roadmap

The full evolution plan (configurable DPSIR schema, wizard interface, savepoint,
attribute usage, and development phases) is in [`PLANO_iDPSIR.md`](PLANO_iDPSIR.md)
(in Portuguese).

> Reproducibility: adding `renv` to pin package versions is still planned.
