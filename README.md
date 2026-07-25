# iDPSIR

**R/Shiny** app for building and analyzing causal networks under the **DPSIR** model
(Driver–Pressure–State–Impact–Response), aimed at environmental management. A guided
wizard walks non-technical users through building the network (form-based editor or
CSV import), exploring it with a layered DPSIR-aware visualization, running community
detection, simulating response scenarios, and exporting a self-contained HTML report —
all without requiring familiarity with graph theory.

## How to run

Requires R (>= 4.1). Missing packages are installed automatically on first run — no
manual `install.packages()` step needed. From the project root:

```r
shiny::runApp()
```

Or, without cloning the repo:

```r
shiny::runGitHub("iDPSIR", "gfonseca-unifesp", "main")
```

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
│   ├── responses.R            # response simulation (apply_response, scenario comparison)
│   ├── report.R               # self-contained HTML report builder
│   ├── io.R                   # CSV matrix import, .idpsir.json savepoint read/write, merge_savepoints()
│   ├── core/                  # shared UI components
│   ├── dpsir/                 # earlier, non-schema-aware versions kept for reference (not sourced)
│   ├── modules/                # Shiny modules
│   │   ├── mod_data.R          # wizard steps: Start/Model/Nodes/Edges/Review (form-based editor)
│   │   ├── mod_graph.R         # Graph tab: filters, display options, pathway highlighting, category/community coloring, save snapshots for the report
│   │   ├── mod_communities.R   # earlier standalone Communities tab, kept for reference (not sourced; superseded by mod_graph.R's "Color nodes by")
│   │   ├── mod_responses.R     # Scenarios tab: build/apply/save/compare response scenarios
│   │   ├── mod_report.R        # Report tab: pick metrics sections + saved graph snapshots + saved scenarios, download the HTML report
│   │   ├── mod_metrics.R       # Metrics tab: general / centralities / DPSIR descriptors
│   │   └── mod_wizard.R        # wizard shell tying every step/tab together
│   ├── ui_main.R               # top-level UI (ina_ui)
│   └── server_main.R           # top-level server (ina_server)
├── data/                      # example data (sample_nodes.csv, sample_edges.csv)
├── PLANO_iDPSIR.md            # restructuring plan and roadmap (in Portuguese)
└── README.md
```

## Data format

**Nodes** (`data/sample_nodes.csv`): `id`, `label`, `dpsir_category` (Driver, Pressure,
State, Impact, Response), `subsystem`, `uncertainty` (low/medium/high),
`controllability` (low/medium/high), `temporal_scale` (short/medium/long).

**Edges** (`data/sample_edges.csv`): `from`, `to`, `weight`, `confidence` (0-1),
`interaction_type` (positive/negative), `evidence_type`.

**Default DPSIR connections:** Driver→Pressure, Pressure→State, State→Impact,
Impact→Response, and Response→{Driver, Pressure, State, Impact}. The schema is
configurable, so this order and vocabulary can be adjusted per project.

## Workflow

The wizard has six steps: **Start** (new project, CSV import, load a `.idpsir.json`
savepoint, or combine two or more savepoints into one) → **Model** (schema/palette,
advanced) → **Nodes** → **Edges** → **Review and build** → **Explore**, which itself
has four tabs:

- **Graph** — layered DPSIR visualization with filters, node/edge emphasis, spacing
  controls, and pathway highlighting. "Color nodes by" switches between DPSIR
  category and detected community (Louvain/Walktrap/Infomap/Label Propagation,
  redrawn with edges, not bare colored dots) without leaving the tab. Any view can
  be saved as a named snapshot to include in the report.
- **Scenarios** — turn on Response nodes at a given implementation strength, apply a
  combined scenario, save it, and compare multiple saved scenarios side by side.
- **Metrics** — general network metrics, centralities, and DPSIR descriptors (gaps
  such as Impacts without a Response, or Pressures not covered by one).
- **Report** — pick which sections (saved graph snapshots, metrics, centralities,
  descriptors, saved scenarios) go into one self-contained downloadable HTML report.

A savepoint (`.idpsir.json`) can be downloaded from any step and reloaded later to
resume a project.

## Roadmap

The full evolution plan (configurable DPSIR schema, wizard interface, savepoint,
attribute usage, and development phases) is in [`PLANO_iDPSIR.md`](PLANO_iDPSIR.md)
(in Portuguese).

> Reproducibility: adding `renv` to pin package versions is still planned.
