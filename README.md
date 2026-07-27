# iDPSIR

[![Try it live](https://img.shields.io/badge/Try_it_live-online_demo-2ea44f)](https://gfonseca-unifesp.github.io/iDPSIR/)

**R/Shiny** app for building and analyzing causal networks under the **DPSIR** model
(Driver–Pressure–State–Impact–Response), aimed at environmental management. A guided
wizard walks non-technical users through building the network (form-based editor or
CSV import), exploring it with a layered DPSIR-aware visualization, running community
detection, simulating response scenarios through loop analysis (Levins 1974) — signed
interaction matrix, stability check, immediate vs. equilibrium effect, step-by-step
trajectory, and a robustness check against edge-confidence uncertainty — and exporting
a self-contained HTML report, all without requiring familiarity with graph theory.

New to iDPSIR? See the [getting-started tutorial](docs/tutorial.html) — it walks
through every step and includes a worked example with a downloadable savepoint
([`docs/example_fisheries.idpsir.json`](docs/example_fisheries.idpsir.json)). The
same tutorial is one click away from inside the running app too, via the "Help"
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

The scientific core (`R/loop_analysis.R`, `R/metrics.R`, `R/io.R`, `R/validate.R`) has
an automated `testthat` suite, checked against hand-verified numeric examples (a
classic stable trophic-chain matrix and the fisheries worked example). Run it from the
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
│   ├── loop_analysis.R        # loop analysis (Levins 1974): interaction matrix, stability, press perturbation, step-by-step trajectory (with an optional per-edge nonlinear threshold), robustness check, steps-to-neutralize-an-Impact
│   ├── responses.R            # get_feedback_categories/find_response_targets (still used); apply_response and the older scenario-comparison helpers are kept but no longer called, superseded by loop_analysis.R
│   ├── report.R               # self-contained HTML report builder
│   ├── io.R                   # CSV matrix import, .idpsir.json savepoint read/write, merge_savepoints()
│   ├── core/                  # shared UI components
│   ├── dpsir/                 # earlier, non-schema-aware versions kept for reference (not sourced)
│   ├── modules/                # Shiny modules
│   │   ├── mod_data.R          # wizard steps: Start/Model/Nodes/Edges/Review (form-based editor)
│   │   ├── mod_graph.R         # Graph tab: filters, display options, pathway highlighting, category/community coloring, save snapshots for the report
│   │   ├── mod_communities.R   # earlier standalone Communities tab, kept for reference (not sourced; superseded by mod_graph.R's "Color nodes by")
│   │   ├── mod_responses.R     # Scenarios tab: activate responses and run loop analysis (stability check, immediate vs. equilibrium effect, step-by-step trajectory, robustness check, steps to neutralize an Impact), save/compare scenarios
│   │   ├── mod_report.R        # Report tab: pick metrics sections + saved graph snapshots + saved scenarios, download the HTML report (numbered figure/table captions, parametrization described)
│   │   ├── mod_metrics.R       # Metrics tab: general / centralities / DPSIR descriptors
│   │   └── mod_wizard.R        # wizard shell tying every step/tab together
│   ├── ui_main.R               # top-level UI (ina_ui)
│   └── server_main.R           # top-level server (ina_server)
├── data/                      # example data (sample_nodes.csv, sample_edges.csv)
├── docs/                      # getting-started tutorial (tutorial.html) and a worked-example savepoint (example_fisheries.idpsir.json)
├── tests/
│   ├── testthat.R             # test runner: Rscript tests/testthat.R
│   └── testthat/               # tests for the scientific core (loop_analysis, metrics, io, validate)
├── PLANO_iDPSIR.md            # restructuring plan and roadmap (in Portuguese)
├── ROADMAP_MELHORIAS_iDPSIR.md # roadmap towards a JOSS/SoftwareX submission (in Portuguese)
└── README.md
```

## Data format

**Nodes** (`data/sample_nodes.csv`): `id`, `label`, `dpsir_category` (Driver, Pressure,
State, Impact, Response), `subsystem`, `uncertainty` (low/medium/high),
`controllability` (low/medium/high), `temporal_scale` (short/medium/long).

**Edges** (`data/sample_edges.csv`): `from`, `to`, `weight`, `confidence` (0-1),
`interaction_type` (positive/negative), `evidence_type`, `threshold` (optional,
blank for most edges — see Scenarios below), `reference` (optional DOI/URL/citation
backing the link, listed in the report if included).

**Default DPSIR connections:** Driver→Pressure, Pressure→State, State→Impact,
Impact→Response, and Response→{Driver, Pressure, State, Impact}. The schema is
configurable, so this order and vocabulary can be adjusted per project.

A larger, annotated example — a five-node feedback loop with a worked scenario —
is at [`docs/example_fisheries.idpsir.json`](docs/example_fisheries.idpsir.json);
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
- **Scenarios** — turn on Response nodes at a given implementation strength and apply
  a combined scenario. Runs on loop analysis (Levins 1974): the signed, weighted graph
  becomes a community matrix, and activating a response is a sustained perturbation
  propagated through it, including any feedback loop. Shows the immediate (one-step)
  and equilibrium (full feedback) effect on every factor with a sign confidence score
  (% of simulations, resampling edge weights within their confidence range, that agree
  on the predicted direction), a plain-language stability warning when the network's
  feedback loops aren't stable, how many steps it takes for the effect to reach 90% of
  its projected value on each Impact ("when will this be neutralized"), an optional
  step-by-step trajectory chart (respecting any per-edge nonlinear `threshold` set in
  the Edges step), an optional robustness check against how confident each edge's
  weight is, and an optional ranking of which edges' weight most affects the result
  ("which edges matter most"). Save a scenario and compare multiple saved scenarios
  side by side.
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
