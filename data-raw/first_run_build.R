# =====================================================
# "First run" versions of the published examples - build script
# =====================================================
#
# The same network (factors, links and signs) with every other setting left
# at the app's default: every edge "moderate" (0.45), self-regulation 0.5,
# no growth, initial levels or thresholds, every Impact ecological with
# v = 1, and the temporal settings of a new project. The pressure and
# response scenario is the same as in the full example, so the two can be
# compared side by side - what a first-time user gets from the structure
# alone, and what the parameterization changes (tutorial, "First run").
#
# Writes docs/example_mangi_default.idpsir.json and
# docs/example_gnanapragasam_default.idpsir.json.
# Run from the repository root, after the examples' own build scripts:
#   Rscript data-raw/first_run_build.R

setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")

strip_to_defaults <- function(src, dest, title) {
  sp <- read_savepoint(src)
  keep_n <- intersect(c("id", "label", "dpsir_category", "subsystem", "descriptor"), names(sp$nodes))
  keep_e <- intersect(c("from", "to", "interaction_type", "evidence_type", "reference"), names(sp$edges))
  ss <- sp$scenario_state
  out <- build_savepoint(
    sp$schema,
    normalize_dpsir_nodes(sp$nodes[, keep_n], sp$schema), normalize_dpsir_edges(sp$edges[, keep_e]),
    metadata = list(project_name = title, author = "iDPSIR examples",
                    notes = paste("Same network as", basename(src), "with every setting left at the app's default.")),
    scenario_state = ss[c("response_active", "response_strengths", "pressure_active", "pressure_strengths")])
  write_savepoint(out, dest)
}

strip_to_defaults("docs/example_mangi.idpsir.json", "docs/example_mangi_default.idpsir.json",
                  "Example: Kenyan reef fisheries - first run (defaults only)")
strip_to_defaults("docs/example_gnanapragasam.idpsir.json", "docs/example_gnanapragasam_default.idpsir.json",
                  "Example: Sri Lanka fisheries - first run (defaults only)")
