# =====================================================
# Sri Lanka example - is "aid -> fleet capacity" supported by the data?
# =====================================================
#
# Revisao 3, E3.2, done fairly. Dropping the two aid -> fleet links removes
# the only two fitted parameters, so the variant fits worse by construction.
# Comparisons that do not favour the model with more parameters:
#   (a) AIC / AICc / BIC from the residual sum of squares, 2006-2021;
#   (b) out of sample: every model fitted on 2006-2014, tested on 2015-2021;
#   (c) a rival with the same number of free parameters: no aid -> fleet, but
#       the rise in effort explained by the fleet's own growth (growth_rate of
#       D3) and by demand -> effort (beta D2 -> P1), both fitted.
# The models are defined in vn_example_srilanka() and compared by
# vn_compare() (analysis/templates/validate_network.R).
#
#   Rscript analysis/validation_srilanka/variant_test.R   (from the repository root)

if (!exists("simulate_temporal_pair")) {
  old <- setwd("tests/testthat"); suppressMessages(source("helper-setup.R")); setwd(old)
}
if (!exists("vn_load")) {
  for (vn_path in c("analysis/templates/validate_network.R", "../../analysis/templates/validate_network.R")) {
    if (file.exists(vn_path)) { source(vn_path, local = TRUE); break }
  }
}

run_variant_test <- function(root = ".", out_dir = "analysis/validation_srilanka/out") {
  ex <- vn_example_srilanka(root)
  out <- vn_compare(ex$models, ex$all_years, ex$fit_years, ex$test_years)
  names(out)[names(out) == "rmse_all"] <- "rmse_2006_2021"
  names(out)[names(out) == "rmse_test"] <- "rmse_test_2015_2021"
  names(out)[names(out) == "params_all"] <- "params_2006_2021"
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(out, file.path(out_dir, "variant_test.csv"), row.names = FALSE)
  out
}

if (sys.nframe() == 0) print(run_variant_test(), digits = 4)
