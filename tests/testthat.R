# =====================================================
# TEST RUNNER (standalone - the app is a Shiny project, not an installed
# package; DESCRIPTION only lists its dependencies)
# =====================================================
#
# Run from the repo root:
#   Rscript tests/testthat.R
# or from an R session already at the repo root:
#   testthat::test_dir("tests/testthat")
#
# tests/testthat/helper-setup.R is sourced automatically by testthat before
# any test-*.R file runs (standard testthat convention for files named
# "helper*") - it loads igraph and source()s just the core files these tests
# exercise (the numeric core, io, report), not the whole
# app (global.R would also pull in shiny/bs4Dash/DT/etc. and trigger the
# auto-install path, none of which the numeric core needs to be tested).

testthat::test_dir("tests/testthat", reporter = "summary")
