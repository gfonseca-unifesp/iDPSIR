# =====================================================
# TEST RUNNER (standalone, not a package yet - see
# ROADMAP_MELHORIAS_iDPSIR.md item 6.1, still pending)
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
# exercise (schema/validate/graph/metrics/loop_analysis/io), not the whole
# app (global.R would also pull in shiny/bs4Dash/DT/etc. and trigger the
# auto-install path, none of which the numeric core needs to be tested).

testthat::test_dir("tests/testthat", reporter = "summary")
