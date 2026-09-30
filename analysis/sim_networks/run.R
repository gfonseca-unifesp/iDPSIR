# =====================================================
# Simulated DPSIR networks - conditions (Revisao 3, E5.3)
# =====================================================
#
# Implements section 3 of PREREGISTRO.md: for each network (seed 1000 + i)
# the same scenario is read in C0 (raw), C1 (strengths), C2 (+ thresholds,
# static), C2t (+ thresholds, temporal), C3 (+ growth, temporal) and C4
# (confidence with structural uncertainty), for R strength draws
# (seed 100000 * i + r). One row per network x draw x condition x Impact.
#
# Everything goes through the app's engine: sufficiency(),
# impact_prioritization(), sufficiency_confidence(), simulate_temporal_pair(),
# format_temporal_table(), interpret_scenario(). Sourced after
# tests/testthat/helper-setup.R and generate.R (see run_all.R).

SIM_T <- 20            # temporal verdict window
SIM_TOL_REL <- 0.05    # temporal "Neutralized (relative)" tolerance

verdict3 <- function(status) {
  ifelse(status == "neutralized", "neutralized",
         ifelse(status %in% c("not_affected", "improved"), "not_affected", "not_neutralized"))
}

# Network properties (section 4), on the raw structure.
network_properties <- function(net, g0, rho0) {
  cat_of <- setNames(net$nodes$dpsir_category, net$nodes$id)
  n <- nrow(net$nodes)
  d_ids <- net$nodes$id[cat_of == "Driver"]
  i_ids <- net$nodes$id[cat_of == "Impact"]
  dist <- igraph::distances(g0, v = d_ids, to = i_ids, mode = "out", weights = NA)
  cyc <- tryCatch(length(igraph::simple_cycles(g0, mode = "out")$vertices), error = function(e) NA_integer_)
  reach <- response_reach(g0, names(net$response))
  data.frame(
    network = net$seed, n_nodes = n, n_edges = nrow(net$edges), density = nrow(net$edges) / (n * (n - 1)),
    q = net$q, has_cycle = !igraph::is_dag(g0), n_cycles = cyc,
    mean_path_DI = mean(dist[is.finite(dist)]), rho_raw = rho0,
    share_reached = reach$impacts / length(i_ids),
    n_thresholds = sum(!is.na(net$nodes$threshold_level)), n_growing = sum(net$nodes$growth_rate != 0),
    n_impacts = length(i_ids), n_responses_active = length(net$response),
    stringsAsFactors = FALSE
  )
}

# Static reading of one condition: sufficiency, 5- and 3-level verdicts,
# priority and rank.
static_rows <- function(g, net, n_rho, structural = FALSE) {
  ids <- igraph::V(g)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  pD <- pv(net$pressure); pR <- pv(net$response)
  s <- sufficiency(g, pD, pR)
  pr <- impact_prioritization(g, pD, s, n_simulations = n_rho, structural = structural)
  it <- interpret_scenario(g, list(sufficiency_df = s, prioritization = pr))$impacts
  k <- match(s$id, it$id); kp <- match(s$id, pr$id)
  rank <- rank(-ifelse(pr$affected & !is.na(pr$priority), pr$priority, -Inf), ties.method = "min")[kp]
  data.frame(impact = s$id, worsening = s$worsening, mitigation = s$mitigation, net = s$net,
             strength_needed = s$strength_to_neutralize, verdict5 = it$status[k], verdict3 = verdict3(it$status[k]),
             priority = pr$priority[kp], rank = ifelse(pr$affected[kp], rank, NA_integer_),
             stringsAsFactors = FALSE)
}

# Temporal reading at window SIM_T (C2t, C3).
temporal_rows <- function(g, net) {
  ids <- igraph::V(g)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  tr <- simulate_temporal_pair(g, pv(net$pressure), pv(net$response), windows = SIM_T, stop_rule = "fixed",
                               mode_D = "permanent", mode_R = "permanent", tol_rel = SIM_TOL_REL)
  tt <- format_temporal_table(g, tr, tol_rel = SIM_TOL_REL)
  tt <- tt[tt$window == SIM_T, , drop = FALSE]
  v3 <- ifelse(tt$verdict %in% c("Neutralized", "Neutralized (relative)", "Improved beyond neutral"), "neutralized",
               ifelse(tt$verdict == "Not affected", "not_affected", "not_neutralized"))
  data.frame(impact = tt$id, worsening = tt$baseline_impact, mitigation = tt$net_impact - tt$baseline_impact,
             net = tt$net_impact, strength_needed = NA_real_, verdict5 = tt$verdict, verdict3 = v3,
             priority = NA_real_, rank = NA_integer_, diverges = isTRUE(tr$stability$unbounded),
             stringsAsFactors = FALSE)
}

# Every condition for one network. Returns list(results, network, counts).
run_network <- function(i, R = 20, n_rho = 100, n_conf = 100, spec = sim_spec_default()) {
  net <- generate_dpsir_network(1000 + i, spec)
  g0 <- sim_graph(net$nodes, raw_edges(net), keep = character())
  rho0 <- spectral_radius(effect_matrix(g0))
  props <- network_properties(net, g0, rho0)
  counts <- data.frame(network = net$seed, raw_excluded = rho0 >= 1 - 1e-9, draws_rejected = 0L, temporal_diverged = 0L)
  if (counts$raw_excluded) return(list(results = NULL, network = props, counts = counts))
  tag <- function(df, cond, r, rho_B, mode) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    if (!"diverges" %in% names(df)) df$diverges <- FALSE
    cbind(data.frame(network = net$seed, draw = r, condition = cond, draw_mode = mode, rho_B = rho_B,
                     stringsAsFactors = FALSE), df)
  }
  out <- list(tag(static_rows(g0, net, n_rho), "C0", 0L, rho0, "raw"))
  for (r in seq_len(R)) {
    e <- draw_strength_edges(net, 100000 * i + r, spec)
    if (is.null(e)) { counts$draws_rejected <- counts$draws_rejected + 1L; next }
    mode <- attr(e, "mode")
    g1 <- sim_graph(net$nodes, e, keep = character())
    g2 <- sim_graph(net$nodes, e, keep = "thresholds")
    g3 <- sim_graph(net$nodes, e, keep = c("thresholds", "growth"))
    rho_B <- spectral_radius(effect_matrix(g1))
    out <- c(out, list(
      tag(static_rows(g1, net, n_rho), "C1", r, rho_B, mode),
      tag(static_rows(g2, net, n_rho), "C2", r, rho_B, mode)
    ))
    t2 <- temporal_rows(g2, net); t3 <- temporal_rows(g3, net)
    counts$temporal_diverged <- counts$temporal_diverged + as.integer(any(t2$diverges)) + as.integer(any(t3$diverges))
    out <- c(out, list(tag(t2, "C2t", r, rho_B, mode), tag(t3, "C3", r, rho_B, mode)))
    # C4 (secondary): confidence of the planned scenario, with and without
    # structural uncertainty, on the C1 reading.
    ids <- igraph::V(g1)$name
    pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
    c_f <- sufficiency_confidence(g1, pv(net$pressure), pv(net$response), n_simulations = n_conf)
    c_t <- sufficiency_confidence(g1, pv(net$pressure), pv(net$response), n_simulations = n_conf, structural = TRUE)
    c4 <- data.frame(impact = c_f$id, worsening = NA_real_, mitigation = NA_real_, net = NA_real_, strength_needed = NA_real_,
                     verdict5 = NA_character_, verdict3 = NA_character_, priority = NA_real_, rank = NA_integer_,
                     confidence = c_f$neutralized_pct, confidence_structural = c_t$neutralized_pct[match(c_f$id, c_t$id)],
                     stringsAsFactors = FALSE)
    out <- c(out, list(tag(c4, "C4", r, rho_B, mode)))
  }
  res <- do.call(rbind, lapply(out, function(d) {
    if (is.null(d)) return(NULL)
    for (k in c("confidence", "confidence_structural")) if (!k %in% names(d)) d[[k]] <- NA_real_
    d
  }))
  list(results = res, network = props, counts = counts)
}

# Runs networks `ids` (in parallel when workers > 1) and writes the outputs.
run_experiment <- function(ids, R = 20, n_rho = 100, n_conf = 100, workers = 1, out_dir = "analysis/sim_networks/out",
                           root = ".") {
  f <- function(i) tryCatch(run_network(i, R, n_rho, n_conf),
                            error = function(e) list(results = NULL, network = NULL,
                                                     counts = data.frame(network = 1000 + i, raw_excluded = NA, draws_rejected = NA,
                                                                         temporal_diverged = NA, error = conditionMessage(e))))
  if (workers > 1) {
    # Each worker loads the app's engine and these scripts itself (parallel,
    # PSOCK clusters work the same on Windows and elsewhere); seeds are
    # per network, so the result does not depend on the number of workers.
    cl <- parallel::makeCluster(workers)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    root_abs <- normalizePath(root)
    parallel::clusterExport(cl, "root_abs", envir = environment())
    parallel::clusterEvalQ(cl, {
      setwd(file.path(root_abs, "tests/testthat"))
      suppressMessages(suppressWarnings(source("helper-setup.R")))
      setwd(root_abs)
      source("analysis/sim_networks/generate.R")
      source("analysis/sim_networks/run.R")
      NULL
    })
    res <- parallel::parLapply(cl, ids, function(i, R, n_rho, n_conf) {
      tryCatch(run_network(i, R, n_rho, n_conf),
               error = function(e) list(results = NULL, network = NULL,
                                        counts = data.frame(network = 1000 + i, raw_excluded = NA, draws_rejected = NA,
                                                            temporal_diverged = NA, error = conditionMessage(e))))
    }, R = R, n_rho = n_rho, n_conf = n_conf)
  } else {
    res <- lapply(ids, f)
  }
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  bind <- function(key) {
    parts <- lapply(res, `[[`, key)
    parts <- Filter(Negate(is.null), parts)
    cols <- unique(unlist(lapply(parts, names)))
    do.call(rbind, lapply(parts, function(d) { d[setdiff(cols, names(d))] <- NA; d[cols] }))
  }
  results <- bind("results"); networks <- bind("network"); counts <- bind("counts")
  utils::write.csv(results, gzfile(file.path(out_dir, "results.csv.gz")), row.names = FALSE)
  utils::write.csv(networks, file.path(out_dir, "networks.csv"), row.names = FALSE)
  utils::write.csv(counts, file.path(out_dir, "counts.csv"), row.names = FALSE)
  invisible(list(results = results, networks = networks, counts = counts))
}
