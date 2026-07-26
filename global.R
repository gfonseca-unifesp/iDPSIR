# =========================
# iDPSIR - GLOBAL CONFIG
# =========================

# =========================
# AUTO-INSTALL DEPENDENCIES
# =========================
# Garante que quem roda via shiny::runGitHub() (sem ter rodado install.packages
# manualmente antes) tenha os pacotes necessarios instalados automaticamente na
# primeira execucao, em vez de falhar com "there is no package called ...".

required_packages <- c(
  "shiny", "bs4Dash", "visNetwork", "igraph", "DT", "dplyr",
  "data.table", "htmlwidgets", "shinyWidgets", "glue", "purrr", "scales", "jsonlite"
)

missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_packages) > 0) {
  if (is.null(getOption("repos")) || identical(getOption("repos")[["CRAN"]], "@CRAN@")) {
    options(repos = c(CRAN = "https://cloud.r-project.org"))
  }
  message("iDPSIR: installing missing packages: ", paste(missing_packages, collapse = ", "))
  install.packages(missing_packages)
}

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

# Serves docs/ (tutorial.html + the example savepoint) under /tutorial/... so
# the running app can link straight to the same file used on GitHub, instead
# of duplicating its content into a Shiny tab.
shiny::addResourcePath("tutorial", "docs")

# =========================
# NUCLEO (schema, validacao, grafo, metricas, io)
# =========================

source("R/schema.R")
source("R/validate.R")
source("R/graph.R")
source("R/metrics.R")
source("R/pathways.R")
source("R/responses.R")
source("R/loop_analysis.R")
source("R/report.R")
source("R/io.R")

source("R/core/core_ui_components.R")

# =========================
# MODULOS
# =========================

source("R/modules/mod_data.R")
source("R/modules/mod_graph.R")
source("R/modules/mod_metrics.R")
source("R/modules/mod_responses.R")
source("R/modules/mod_report.R")
source("R/modules/mod_wizard.R")

# =========================
# MAIN APP
# =========================

source("R/ui_main.R")
source("R/server_main.R")
