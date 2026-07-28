# Auto-sourced by testthat before running tests in this directory (files
# named "helper*" are testthat's standard convention for shared setup).
# Deliberately does NOT source global.R: that also library()s shiny/bs4Dash/
# DT/etc. and runs the missing-package auto-install check, none of which the
# numeric core under test here depends on.
#
# testthat runs helper/test files with the working directory set to
# tests/testthat/ itself (confirmed empirically, not assumed) - hence "../../"
# to reach the repo root from here, the same convention used for reading
# docs/example_fisheries.idpsir.json in the test files themselves.

library(igraph)

source("../../R/schema.R")
source("../../R/validate.R")
source("../../R/graph.R")
source("../../R/metrics.R")
source("../../R/loop_analysis.R")
source("../../R/reach.R")
source("../../R/io.R")
