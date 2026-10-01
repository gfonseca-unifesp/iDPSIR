# =====================================================
# Sri Lanka example - variant without "aid -> fleet capacity" (Revisao 3, E3.2)
# =====================================================
#
# The published example assumes that the post-tsunami and post-war aid also
# enlarged the fleet (R1 -> D3 and R2 -> D3, strengths calibrated on the
# observed effort). This variant drops those two links and keeps everything
# else - network, parameters and scenario - so the two savepoints test one
# causal assumption: does the aid become a pressure?
#
# Writes docs/example_gnanapragasam_noaidfleet.idpsir.json.
# Run from the repository root, after gnanapragasam2026_build.R:
#   Rscript data-raw/gnanapragasam2026_variant_build.R

setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")

sp <- read_savepoint("docs/example_gnanapragasam.idpsir.json")
edges <- sp$edges[!(sp$edges$from %in% c("R1", "R2") & sp$edges$to == "D3"), , drop = FALSE]
stopifnot(nrow(edges) == nrow(sp$edges) - 2)
out <- build_savepoint(
  sp$schema, sp$nodes, edges,
  metadata = list(
    project_name = "Example: Sri Lanka small-scale fisheries - variant without aid -> fleet",
    author = "iDPSIR examples",
    notes = "Same as example_gnanapragasam.idpsir.json without the links post-tsunami aid -> fleet capacity and post-war aid -> fleet capacity (causal-assumption test)."
  ),
  scenario_state = sp$scenario_state
)
write_savepoint(out, "docs/example_gnanapragasam_noaidfleet.idpsir.json")
message("Written: docs/example_gnanapragasam_noaidfleet.idpsir.json")
