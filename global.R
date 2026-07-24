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
library(DT)
library(dplyr)
library(data.table)
library(htmlwidgets)
library(shinyWidgets)
library(glue)
library(purrr)
library(scales)

# jsonlite fica sem library() de proposito: ele mascara shiny::validate()
# quando anexado. io.R usa sempre jsonlite:: com prefixo explicito.

# =========================
# GLOBAL OPTIONS
# =========================

options(
  shiny.maxRequestSize = 100 * 1024^2
)

# =========================
# NUCLEO (schema, validacao, grafo, metricas, io)
# =========================

source("R/schema.R")
source("R/validate.R")
source("R/graph.R")
source("R/metrics.R")
source("R/io.R")

source("R/core/core_ui_components.R")

# =========================
# MODULOS
# =========================

source("R/modules/mod_data.R")
source("R/modules/mod_graph.R")
source("R/modules/mod_metrics.R")
source("R/modules/mod_wizard.R")

# =========================
# MAIN APP
# =========================

source("R/ui_main.R")
source("R/server_main.R")
