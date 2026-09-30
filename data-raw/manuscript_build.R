# =====================================================
# Manuscript - every number, table and figure from the published savepoints
# =====================================================
#
# Revisao 3, E8 (item A-2 of ROADMAP_MANUSCRITO_iDPSIR.md). One place that
# computes what the manuscript cites, from the savepoints in docs/ and the
# analyses in analysis/, through the app's own engine:
#   - the port, Mangi and Sri Lanka cases (parametrized and first run),
#   - the sensitivity to self-regulation (E1.4),
#   - the out-of-sample validation and the causal-assumption variant (E2, E3.2),
#   - the confidence with and without structural uncertainty (E3.1),
#   - the robustness of the priority order (E4.2),
#   - the simulated networks (E5), read from analysis/sim_networks/out when present.
#
# manuscript_numbers() returns a named list of scalars; the test
# tests/testthat/test-manuscript-numbers.R compares it with the frozen values
# in tests/testthat/fixtures/manuscript_numbers.json, so a change of the engine
# that alters a cited number fails the suite.
#
# Run from the repository root:  Rscript data-raw/manuscript_build.R [out_dir]
# Writes out_dir/numeros.json (default out_dir: manuscrito_v5/build, which is
# not versioned) and refreshes the frozen fixture when called with --freeze.
# Tables and figures are added once the manuscript's list of them is fixed
# (they already exist per case in data-raw/*_build.R and analysis/*/).

ms_load <- function(name, root = ".") {
  sp <- read_savepoint(file.path(root, "docs", paste0(name, ".idpsir.json")))
  g <- build_igraph(sp$nodes, sp$edges, sp$schema)
  ids <- igraph::V(g)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  list(sp = sp, g = g, pv = pv)
}

ms_scenario <- function(x, active, strengths, pressure_active, pressure_strengths, n = 300, structural = FALSE) {
  rn <- data.frame(id = igraph::V(x$g)$name[has_role(x$g, "feedback")], label = igraph::V(x$g)$label[has_role(x$g, "feedback")])
  compute_scenario(x$g, rn, "s", active, strengths, pressure_active, pressure_strengths, n_simulations = n, structural = structural)
}

ms_temporal <- function(x, sc, windows, schedule = NULL, mode = "permanent") {
  simulate_temporal_pair(x$g, x$pv(sc$pressure_strengths), x$pv(sc$strengths), windows = windows, stop_rule = "fixed",
                         mode_D = mode, mode_R = mode, schedule = schedule)
}

manuscript_numbers <- function(root = ".", with_sim = TRUE) {
  num <- list()
  put <- function(key, value) num[[key]] <<- unname(value)

  # ---- Port (didactic) ----
  port <- ms_load("example_port", root)
  sv <- port$sp$saved_scenarios
  for (k in 1:3) {
    d <- sv[[k]]
    sc <- ms_scenario(port, d$active, d$strengths, d$pressure_active, d$pressure_strengths)
    pr <- sc$prioritization
    top <- pr[order(-ifelse(is.na(pr$priority), -Inf, pr$priority)), ]
    put(sprintf("port.s%d.neutralized", k), sum(sc$sufficiency_df$neutralized & sc$sufficiency_df$worsening > 1e-9))
    put(sprintf("port.s%d.top_priority", k), top$priority[1])
    put(sprintf("port.s%d.top_id", k), if (isTRUE(top$priority[1] > 0)) top$id[1] else "none")
    if (k == 1) {
      put("port.s1.second_priority", top$priority[2])
      put("port.s1.primary_production_priority", pr$priority[pr$id == "I4"])
      put("port.s1.rank_top_stable", attr(sc$priority_robustness, "top_stable"))
      put("port.s1.rank_tau", attr(sc$priority_robustness, "kendall_tau"))
      put("port.s1.fauna_keeps_rank", sc$priority_robustness$keeps_rank[sc$priority_robustness$id == "I1"])
      sct <- ms_scenario(port, d$active, d$strengths, d$pressure_active, d$pressure_strengths, structural = TRUE)
      cm <- sc$sufficiency_confidence_matrix; cmt <- sct$sufficiency_confidence_matrix
      put("port.s1.conf_fauna", cm[1, "Behavioral alterations of fauna"])
      put("port.s1.conf_fauna_structural", cmt[1, "Behavioral alterations of fauna"])
      sens <- self_regulation_sensitivity(port$g, sc$p_D, sc$press)
      put("port.s1.sr_depends_n", sum(sens$depends_on_s))
    }
  }
  for (k in 3:4) {
    d <- sv[[k]]
    tr <- simulate_temporal_pair(port$g, port$pv(d$pressure_strengths), port$pv(d$strengths), windows = 12, stop_rule = "fixed",
                                 mode_D = "window", mode_R = "window", schedule = d$temporal_schedule)
    put(sprintf("port.s%d.fauna_peak_net", k), max(tr$scenario[, "I1"]))
    put(sprintf("port.s%d.fauna_peak_baseline", k), max(tr$baseline[, "I1"]))
    put(sprintf("port.s%d.seafood_w12", k), tr$scenario[13, "I2"])
  }

  # ---- Mangi et al. 2007 ----
  mangi <- ms_load("example_mangi", root)
  mangi0 <- ms_load("example_mangi_default", root)
  sv <- mangi$sp$saved_scenarios
  for (k in seq_along(sv)) {
    d <- sv[[k]]
    sc <- ms_scenario(mangi, d$active, d$strengths, d$pressure_active, d$pressure_strengths)
    s <- sc$sufficiency_df
    put(sprintf("mangi.s%d.neutralized", k), sum(s$neutralized & s$worsening > 1e-9))
    for (id in c("I1", "I2", "I3")) put(sprintf("mangi.s%d.%s.x_needed", k, id), s$strength_to_neutralize[s$id == id])
    if (k == 1) {
      for (id in c("I1", "I2", "I3")) {
        put(sprintf("mangi.s1.%s.worsening", id), s$worsening[s$id == id])
        put(sprintf("mangi.s1.%s.net", id), s$net[s$id == id])
      }
      pr <- sc$prioritization
      put("mangi.s1.top_id", pr$id[which.max(ifelse(is.na(pr$priority), -Inf, pr$priority))])
      put("mangi.s1.top_priority", max(pr$priority, na.rm = TRUE))
      put("mangi.s1.parks_alone_conflict_mitigation",
          sufficiency(mangi$g, sc$p_D, mangi$pv(c(R1 = 100)))$mitigation[s$id == "I3"])
      sct <- ms_scenario(mangi, d$active, d$strengths, d$pressure_active, d$pressure_strengths, structural = TRUE)
      put("mangi.s1.conf_catch", sc$sufficiency_confidence_matrix[1, "Declining catch per fisher"])
      put("mangi.s1.conf_catch_structural", sct$sufficiency_confidence_matrix[1, "Declining catch per fisher"])
      # First run.
      sc0 <- ms_scenario(mangi0, d$active, d$strengths, d$pressure_active, d$pressure_strengths)
      s0 <- sc0$sufficiency_df
      for (id in c("I1", "I3")) {
        put(sprintf("mangi.first.%s.worsening", id), s0$worsening[s0$id == id])
        put(sprintf("mangi.first.%s.net", id), s0$net[s0$id == id])
      }
      pr0 <- sc0$prioritization
      put("mangi.first.top_id", pr0$id[which.max(ifelse(is.na(pr0$priority), -Inf, pr0$priority))])
      put("mangi.first.top_priority", max(pr0$priority, na.rm = TRUE))
    }
    if (k == 4) {
      tr <- ms_temporal(mangi, d, 40)
      first_pos <- function(col) { w <- which(tr$scenario[-(1:5), col] > 1e-9)[1]; if (is.na(w)) NA else w + 4 }
      put("mangi.s4.return_year_conflicts", first_pos("I3"))
      put("mangi.s4.return_year_catch", first_pos("I1"))
      tr0 <- ms_temporal(mangi0, d, 40)
      put("mangi.first.s4.ever_returns", any(tr0$scenario[-(1:5), c("I1", "I2", "I3")] > 1e-9))
    }
  }

  # ---- Sri Lanka (Gnanapragasam et al. 2026) ----
  sl <- ms_load("example_gnanapragasam", root)
  ss <- sl$sp$scenario_state
  tr <- simulate_temporal_pair(sl$g, sl$pv(ss$pressure_strengths), sl$pv(ss$response_strengths), windows = ss$temporal_windows,
                               stop_rule = "fixed", mode_D = ss$temporal_mode_pressure, mode_R = ss$temporal_mode_response,
                               schedule = ss$temporal_schedule)
  n <- sl$sp$nodes
  lev <- function(id, w) n$reference_value[n$id == id] + n$sd[n$id == id] * tr$scenario[w + 1, id]
  put("sl.stock_2021", lev("S1", 17)); put("sl.stock_2030", lev("S1", 26)); put("sl.effort_2030", lev("P1", 26))
  bmsy <- n$threshold_level[n$id == "S1"]
  stock <- n$reference_value[n$id == "S1"] + n$sd[n$id == "S1"] * tr$scenario[, "S1"]
  put("sl.year_below_bmsy", 2004 + which(stock < bmsy)[1] - 1)
  tt <- format_temporal_table(sl$g, tr)
  put("sl.w26_worse_than_no_response", sum(tt$window == 26 & tt$verdict == "Failure/worsened"))
  s_static <- sufficiency(sl$g, sl$pv(ss$pressure_strengths), sl$pv(ss$response_strengths))
  put("sl.static_worsened", sum(s_static$worsening > 1e-9))
  sl0 <- ms_load("example_gnanapragasam_default", root)
  ss0 <- sl0$sp$scenario_state
  s0 <- sufficiency(sl0$g, sl0$pv(ss0$pressure_strengths), sl0$pv(ss0$response_strengths))
  put("sl.first.neutralized", sum(s0$neutralized & s0$worsening > 1e-9))
  tr0 <- simulate_temporal_pair(sl0$g, sl0$pv(ss0$pressure_strengths), sl0$pv(ss0$response_strengths), stop_rule = "until_neutralized",
                                max_windows = 50, tol_rel = 0.05)
  put("sl.first.neutralized_at", tr0$neutralized_at)
  slv <- ms_load("example_gnanapragasam_noaidfleet", root)
  put("sl.aid_reach_impacts", response_reach(sl$g, c("R1", "R2"))$impacts)
  put("sl.variant.aid_reach_impacts", response_reach(slv$g, c("R1", "R2"))$impacts)

  # ---- Validation (E2) ----
  source(file.path(root, "analysis/validation_srilanka/calibrate.R"), local = TRUE)
  source(file.path(root, "analysis/validation_srilanka/validate.R"), local = TRUE)
  v <- run_validation(root, n_band = 500)
  m <- v$metrics
  put("val.rmse", m$rmse[1]); put("val.bias", m$bias[1]); put("val.nse", m$nse[1])
  put("val.rmse_persistence", m$rmse[2]); put("val.rmse_trend", m$rmse[3]); put("val.band_coverage", m$band_coverage_90[1])
  r <- v$rolling
  put("val.rolling2012.rmse", r$rmse[r$origin == 2012]); put("val.rolling2012.rmse_persistence", r$rmse_persistence[r$origin == 2012])
  d <- load_srilanka(root)
  full <- calibrate_aid(d, 2006:2021)
  put("val.full.beta_R1", full$beta[["R1"]]); put("val.full.beta_R2", full$beta[["R2"]]); put("val.full.nse", full$stats[["nse"]])

  # ---- Simulated networks (E5), when the outputs exist ----
  hyp <- file.path(root, "analysis/sim_networks/out/hypotheses.csv")
  if (with_sim && file.exists(hyp)) {
    h <- utils::read.csv(hyp, stringsAsFactors = FALSE)
    for (i in seq_len(nrow(h))) {
      key <- gsub("[^A-Za-z0-9]+", "_", h$hypothesis[i])
      put(sprintf("sim.%s.estimate", key), h$estimate[i]); put(sprintf("sim.%s.result", key), h$result[i])
    }
  }
  num
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  freeze <- "--freeze" %in% args
  args <- setdiff(args, "--freeze")
  out_dir <- if (length(args) >= 1) args[1] else "manuscrito_v5/build"
  setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
  suppressMessages({ library(shiny); source("R/modules/mod_responses.R") })
  num <- manuscript_numbers()
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(num, file.path(out_dir, "numeros.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
  if (freeze) {
    jsonlite::write_json(num, "tests/testthat/fixtures/manuscript_numbers.json", auto_unbox = TRUE, digits = NA, pretty = TRUE)
    message("Frozen: tests/testthat/fixtures/manuscript_numbers.json")
  }
  message(sprintf("Written: %s/numeros.json (%d numbers)", out_dir, length(num)))
}
