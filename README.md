# iDPSIR

**R/Shiny** app for building and analyzing causal networks under the **DPSIR** model
(Driver–Pressure–State–Impact–Response), aimed at environmental management. A guided
wizard walks non-technical users through building the network (form-based editor or
CSV import), exploring it with a layered DPSIR-aware visualization, running community
detection, simulating response scenarios, and exporting a self-contained HTML report —
all without requiring familiarity with graph theory.

## How to run

Requires R (>= 4.1). Install the packages and run the app from the project root:

```r
install.packages(c(
  "shiny", "bs4Dash", "visNetwork", "igraph", "DT", "dplyr",
  "data.table", "htmlwidgets", "shinyWidgets", "glue", "purrr", "scales", "jsonlite"
))

shiny::runApp()
```

## Structure

```
iDPSIR/
├── app.R                     # entry point
├── global.R                  # packages, options and source() of every file (order matters)
├── R/
│   ├── schema.R              # configurable DPSIR schema (levels, order, palettes, vocabularies)
│   ├── validate.R             # node/edge validation against the schema
│   ├── graph.R                # igraph builder, layered layout, network/community visuals
│   ├── metrics.R              # centralities, general metrics, DPSIR descriptors
│   ├── pathways.R             # schema-aware causal pathway analysis
│   ├── responses.R            # response simulation (apply_response, scenario comparison)
│   ├── report.R               # self-contained HTML report builder
│   ├── io.R                   # CSV matrix import and .idpsir.json savepoint read/write
│   ├── core/                  # shared UI components
│   ├── dpsir/                 # earlier, non-schema-aware versions kept for reference (not sourced)
│   ├── modules/                # Shiny modules
│   │   ├── mod_data.R          # wizard steps: Start/Model/Nodes/Edges/Review (form-based editor)
│   │   ├── mod_graph.R         # Graph tab: filters, display options, pathway highlighting
│   │   ├── mod_communities.R   # Communities tab (Louvain/Walktrap/Infomap/Label Propagation)
│   │   ├── mod_responses.R     # Scenarios tab: build/apply/save/compare response scenarios
│   │   ├── mod_report.R        # Report tab: pick sections, download the HTML report
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

The wizard has six steps: **Start** (new project, CSV import, or load a `.idpsir.json`
savepoint) → **Model** (schema/palette, advanced) → **Nodes** → **Edges** → **Review
and build** → **Explore**, which itself has five tabs:

- **Graph** — layered DPSIR visualization with filters, node/edge emphasis, spacing
  controls, and pathway highlighting.
- **Communities** — community detection redrawn with edges (not bare colored dots).
- **Scenarios** — turn on Response nodes at a given implementation strength, apply a
  combined scenario, save it, and compare multiple saved scenarios side by side.
- **Metrics** — general network metrics, centralities, and DPSIR descriptors (gaps
  such as Impacts without a Response, or Pressures not covered by one).
- **Report** — pick which sections (graph image, metrics, centralities, descriptors,
  saved scenarios) go into one self-contained downloadable HTML report.

A savepoint (`.idpsir.json`) can be downloaded from any step and reloaded later to
resume a project.

## Roadmap

The full evolution plan (configurable DPSIR schema, wizard interface, savepoint,
attribute usage, and development phases) is in [`PLANO_iDPSIR.md`](PLANO_iDPSIR.md)
(in Portuguese).

> Reproducibility: adding `renv` to pin package versions is still planned.
