# =====================================================
# Manuscript v7 - data tables (Revisao 3, E8)
# =====================================================
#
# Tables 3-6 of manuscrito_v7/MANUSCRIPT_full_7.md and the "Data needs"
# table of each case (step 5), computed through the app's engine from the
# savepoints in docs/ and the analyses in analysis/ (the simulated networks
# are read from analysis/sim_networks/out, never rerun). Tables 1 and 2 are
# qualitative (tool search, workflow guide) and are not generated.
#
# Run from the repository root:
#   Rscript data-raw/manuscript_tables.R [out_dir]     (default manuscrito_v7/tables)
# Writes one CSV per table and prints them, so they can be checked against
# the text.

manuscript_tables <- function(root = ".") {
  tabs <- list()
  lab <- function(g, id) .interp_label(g, id)

  # ---- Table 3: port, priority as responses are added ----
  port <- ms_load("example_port", root)
  sv <- port$sp$saved_scenarios
  t3 <- do.call(rbind, lapply(1:3, function(k) {
    d <- sv[[k]]
    sc <- ms_scenario(port, d$active, d$strengths, d$pressure_active, d$pressure_strengths)
    s <- sc$sufficiency_df
    w <- s$worsening > 1e-9
    pr <- sc$prioritization
    pr <- pr[!is.na(pr$priority) & pr$priority > 0, , drop = FALSE]
    pr <- pr[order(-pr$priority), , drop = FALSE]
    data.frame(responses_applied = d$name,
               impacts_neutralized = sprintf("%d of %d", sum(s$neutralized & w), sum(w)),
               top_priority = if (nrow(pr)) lab(port$g, pr$id[1]) else "none",
               top_priority_value = if (nrow(pr)) round(pr$priority[1], 2) else NA,
               second_priority = if (nrow(pr) > 1) lab(port$g, pr$id[2]) else "",
               second_priority_value = if (nrow(pr) > 1) round(pr$priority[2], 2) else NA,
               stringsAsFactors = FALSE)
  }))
  tabs$table3_port_priority <- t3

  # ---- Table 4: Kenya, strength needed to neutralize ----
  mangi <- ms_load("example_mangi", root)
  mangi0 <- ms_load("example_mangi_default", root)
  cell <- function(s, id) {
    r <- s[s$id == id, ]
    if (r$worsening <= 1e-9) return("not worsened")
    if (r$neutralized) return("neutralized")
    if (r$mitigation > 1e-9) return("worsened by the response")
    if (is.na(r$strength_to_neutralize)) return("not reachable")
    sprintf("x%s", trimws(formatC(r$strength_to_neutralize, format = "fg", digits = 3, flag = "#")))
  }
  sv <- mangi$sp$saved_scenarios
  rows <- lapply(seq_along(sv), function(k) {
    d <- sv[[k]]
    s <- sufficiency(mangi$g, mangi$pv(d$pressure_strengths[d$pressure_active]), mangi$pv(d$strengths[d$active]))
    data.frame(response_scenario = d$name, catch_per_fisher = cell(s, "I1"), livelihoods = cell(s, "I2"),
               conflicts = cell(s, "I3"), stringsAsFactors = FALSE)
  })
  d1 <- sv[[1]]
  s0 <- sufficiency(mangi0$g, mangi0$pv(d1$pressure_strengths[d1$pressure_active]), mangi0$pv(d1$strengths[d1$active]))
  rows[[length(rows) + 1]] <- data.frame(response_scenario = "First run (defaults), scenario 1", catch_per_fisher = cell(s0, "I1"),
                                         livelihoods = cell(s0, "I2"), conflicts = cell(s0, "I3"), stringsAsFactors = FALSE)
  tabs$table4_kenya_strength_needed <- do.call(rbind, rows)

  # ---- Table 5: Sri Lanka, tests against observed effort ----
  vt <- utils::read.csv(file.path(root, "analysis/validation_srilanka/out/variant_test.csv"), stringsAsFactors = FALSE)
  m <- utils::read.csv(file.path(root, "analysis/validation_srilanka/out/metrics.csv"), stringsAsFactors = FALSE)
  t5 <- data.frame(
    network = c("Aid -> fleet (published)", "Persistence of 2014", "Trend 2006-2014", "Without aid -> fleet",
                "Rival: fleet growth and demand fitted instead"),
    fitted_parameters = c(vt$k[vt$model == "aid"], NA, NA, vt$k[vt$model == "no_aid"], vt$k[vt$model == "rival"]),
    rmse_2006_2021 = round(c(vt$rmse_2006_2021[vt$model == "aid"], NA, NA, vt$rmse_2006_2021[vt$model == "no_aid"],
                             vt$rmse_2006_2021[vt$model == "rival"])),
    delta_aic = round(c(vt$delta_aic[vt$model == "aid"], NA, NA, vt$delta_aic[vt$model == "no_aid"], vt$delta_aic[vt$model == "rival"]), 1),
    rmse_2015_2021_calibrated_2006_2014 = round(c(m$rmse[1], m$rmse[2], m$rmse[3], vt$rmse_test_2015_2021[vt$model == "no_aid"],
                                                  vt$rmse_test_2015_2021[vt$model == "rival"])),
    stringsAsFactors = FALSE)
  tabs$table5_srilanka_tests <- t5

  # ---- Table 6: simulated networks (read from out/) ----
  rates <- utils::read.csv(file.path(root, "analysis/sim_networks/out/change_rates.csv"), stringsAsFactors = FALSE)
  hyp <- utils::read.csv(file.path(root, "analysis/sim_networks/out/hypotheses.csv"), stringsAsFactors = FALSE)
  what <- c("C0->C1" = "Link strengths (bare structure -> drawn strengths)", "C1->C2" = "State thresholds",
            "C2->C2t" = "Static -> temporal reading", "C2t->C3" = "Growth trends", "C0->C3" = "All of the above")
  t6a <- data.frame(what_is_added = unname(what[rates$pair]), pair = rates$pair, n = rates$n,
                    verdicts_that_change_pct = round(100 * rates$rate, 1), ci_low = round(100 * rates$lo, 1),
                    ci_high = round(100 * rates$hi, 1), stringsAsFactors = FALSE)
  tabs$table6a_simulated_change_rates <- t6a
  tabs$table6b_simulated_hypotheses <- data.frame(hypothesis = hyp$hypothesis, statistic = hyp$statistic,
                                                  estimate = round(hyp$estimate, 3), ci_low = round(hyp$lo, 3),
                                                  ci_high = round(hyp$hi, 3), result = hyp$result, stringsAsFactors = FALSE)

  # ---- Data needs of each case (step 5) ----
  dn_port <- data_needs(port$g, list(p_D = port$pv(sv_p <- port$sp$saved_scenarios[[2]]$pressure_strengths),
                                     press = port$pv(port$sp$saved_scenarios[[2]]$strengths)))
  d <- mangi$sp$saved_scenarios[[1]]
  dn_mangi <- data_needs(mangi$g, list(p_D = mangi$pv(d$pressure_strengths[d$pressure_active]), press = mangi$pv(d$strengths[d$active])))
  sl0 <- ms_load("example_gnanapragasam_default", root)
  ss0 <- sl0$sp$scenario_state
  dn_sl <- data_needs(sl0$g, list(p_D = sl0$pv(ss0$pressure_strengths), press = sl0$pv(ss0$response_strengths)), temporal = TRUE)
  tabs$data_needs_port_scenario2 <- dn_port
  tabs$data_needs_kenya_scenario1 <- dn_mangi
  tabs$data_needs_srilanka_first_run <- dn_sl
  tabs
}

# Text checks: the numbers Tables 3-6 of the v7 manuscript print.
manuscript_tables_check <- function(tabs) {
  chk <- list()
  ok <- function(name, cond) chk[[name]] <<- isTRUE(cond)
  t3 <- tabs$table3_port_priority
  ok("T3 s1: 0 of 4, seafood 0.90, fauna 0.52", t3$impacts_neutralized[1] == "0 of 4" && t3$top_priority_value[1] == 0.90 && t3$second_priority_value[1] == 0.52)
  ok("T3 s2: 0 of 4, fauna 0.43", t3$impacts_neutralized[2] == "0 of 4" && t3$top_priority_value[2] == 0.43)
  ok("T3 s3: 4 of 4, none", t3$impacts_neutralized[3] == "4 of 4" && t3$top_priority[3] == "none")
  t4 <- tabs$table4_kenya_strength_needed
  ok("T4 row 1: x1.18 x1.19 x12.4", identical(unname(unlist(t4[1, 2:4])), c("x1.18", "x1.19", "x12.4")))
  ok("T4 row 2: x3.94 x3.97 x41.3 (text: x3.9 x4.0 x41)", identical(unname(unlist(t4[2, 2:4])), c("x3.94", "x3.97", "x41.3")))
  ok("T4 row 3: x1.20 x1.37 neutralized", identical(unname(unlist(t4[3, 2:4])), c("x1.20", "x1.37", "neutralized")))
  ok("T4 row 4: all neutralized", all(unlist(t4[4, 2:4]) == "neutralized"))
  ok("T4 first run: x1.25, as catch, worsened by the response", identical(unname(unlist(t4[5, 2:4])), c("x1.25", "x1.25", "worsened by the response")))
  t5 <- tabs$table5_srilanka_tests
  ok("T5: 658 / 6152 / 2472; dAIC 67.5 / 42.4; 559 632 5737 6871 10867",
     identical(t5$rmse_2006_2021[c(1, 4, 5)], c(658, 6152, 2472)) && identical(t5$delta_aic[c(4, 5)], c(67.5, 42.4)) &&
       identical(t5$rmse_2015_2021_calibrated_2006_2014, c(559, 632, 5737, 6871, 10867)))
  t6 <- tabs$table6a_simulated_change_rates
  ok("T6: 15.9 18.9 17.8 4.3 22.8", identical(t6$verdicts_that_change_pct, c(15.9, 18.9, 17.8, 4.3, 22.8)))
  data.frame(check = names(chk), ok = unlist(chk), row.names = NULL)
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  out_dir <- if (length(args) >= 1) args[1] else "manuscrito_v7/tables"
  setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
  suppressMessages({ library(shiny); source("R/modules/mod_responses.R") })
  source("data-raw/manuscript_build.R")
  tabs <- manuscript_tables()
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  for (nm in names(tabs)) utils::write.csv(tabs[[nm]], file.path(out_dir, paste0(nm, ".csv")), row.names = FALSE)
  for (nm in names(tabs)) { cat("\n==", nm, "\n"); print(tabs[[nm]], right = FALSE) }
  cat("\n== checks against the v7 text\n"); print(manuscript_tables_check(tabs), right = FALSE)
  message(sprintf("Written: %d tables in %s", length(tabs), out_dir))
}
