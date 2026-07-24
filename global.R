# =========================
# iDPSIR - GLOBAL CONFIG
# =========================

# =========================
# LIBRARIES
# =========================

library(shiny)
library(bs4Dash)
library(visNetwork)
library(igraph)
library(tidygraph)
library(ggraph)
library(DT)
library(dplyr)
library(data.table)
library(htmlwidgets)
library(colourpicker)
library(shinyWidgets)
library(plotly)
library(glue)
library(purrr)
library(scales)

# =========================
# GLOBAL OPTIONS
# =========================

options(
  shiny.maxRequestSize = 100 * 1024^2
)

# =========================
# DPSIR LAYER
# =========================

source("R/dpsir/core_dpsir_validation.R")
source("R/dpsir/core_dpsir_mapping.R")
source("R/dpsir/core_dpsir_pathways.R")
source("R/dpsir/core_dpsir_responses.R")

# =========================
# GRAPH ENGINE
# =========================

source("R/core/graph/core_graph_validation.R")
source("R/core/graph/core_graph_builder.R")
source("R/core/graph/core_graph_visualization.R")
source("R/core/core_ui_components.R")

# =========================
# COMPUTE LAYER
# =========================

source("R/compute/compute_degree.R")
source("R/compute/compute_betweenness.R")
source("R/compute/compute_closeness.R")
source("R/compute/compute_pagerank.R")
source("R/compute/compute_eigenvector.R")
source("R/compute/compute_density.R")
source("R/compute/compute_diameter.R")
source("R/compute/compute_transitivity.R")
source("R/compute/compute_communities.R")
source("R/compute/compute_modularity.R")
source("R/compute/compute_all_metrics.R")

# =========================
# MODULES
# =========================

source("R/modules/mod_upload.R")
source("R/modules/mod_network.R")
source("R/modules/mod_metrics.R")
source("R/modules/mod_centrality.R")
source("R/modules/mod_communities.R")
source("R/modules/mod_pathways.R")
source("R/modules/mod_responses.R")

# =========================
# MAIN APP
# =========================

source("R/ui_main.R")
source("R/server_main.R")
