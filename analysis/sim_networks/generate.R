# =====================================================
# Simulated DPSIR networks - generator (Revisao 3, E5.2)
# =====================================================
#
# Implements section 2 and the parameter draws of section 3 of PREREGISTRO.md.
# Everything is returned in the app's own formats (nodes/edges data.frames
# that pass normalize_dpsir_*() and build_igraph()), so the conditions in
# run.R go through the app's engine unchanged.
#
# Sourced after the app's R/ core (tests/testthat/helper-setup.R).

SIM_LEVELS <- c(Driver = "D", Pressure = "P", State = "S", Impact = "I", Response = "R")

# Default sign of each allowed level pair (manuscript Table 3), for a
# natural-condition State. A harm-oriented State flips the pairs that touch it.
SIM_SIGNS <- c("D>P" = 1, "P>S" = -1, "S>I" = -1, "I>R" = 1, "R>D" = -1, "R>P" = -1, "R>S" = 1, "R>I" = -1)

sim_spec_default <- function() {
  list(
    size = list(D = 2:5, P = 2:6, S = 2:6, I = 2:6, R = 1:5), total = c(10, 25),
    density = c(0.15, 0.5), q_loops = c(0, 0.3, 0.6), harm_share = c(0.10, 0.20),
    p_threshold = 0.3, z = c(0.2, 1.5), p_growth = 0.3, growth = c(0.01, 0.05), p_cap = 0.5, cap = c(0.2, 1),
    p_response = 0.5, response_strength = c(25, 150),
    beta_continuous = c(0.05, 0.9), band_continuous = 0.3, max_sum_beta2 = 0.95, max_redraws = 5
  )
}

.draw_int <- function(v) if (length(v) == 1) v else sample(v, 1)

# One network: structure, signs, per-network parameters (thresholds, growth,
# Impact values) and the scenario. Deterministic in `seed`.
generate_dpsir_network <- function(seed, spec = sim_spec_default()) {
  with_local_seed(seed, {
    repeat {
      n <- vapply(spec$size, .draw_int, numeric(1))
      if (sum(n) >= spec$total[1] && sum(n) <= spec$total[2]) break
    }
    ids <- unlist(lapply(names(n), function(l) paste0(l, seq_len(n[[l]]))))
    lvl <- sub("[0-9]+$", "", ids)
    cat_of <- setNames(names(SIM_LEVELS), SIM_LEVELS)[lvl]

    pairs <- list(c("D", "P"), c("P", "S"), c("S", "I"), c("R", "D"), c("R", "P"), c("R", "S"), c("R", "I"))
    edges <- do.call(rbind, lapply(pairs, function(pr) {
      from <- ids[lvl == pr[1]]; to <- ids[lvl == pr[2]]
      d <- stats::runif(1, spec$density[1], spec$density[2])
      grid <- expand.grid(from = from, to = to, stringsAsFactors = FALSE)
      grid[stats::runif(nrow(grid)) < d, , drop = FALSE]
    }))
    add <- function(e, from, to) rbind(e, data.frame(from = from, to = to, stringsAsFactors = FALSE))
    pick <- function(v) v[sample.int(length(v), 1)]
    # Repairs: reachability from the Drivers down to every Impact, and every
    # Response acts on something.
    for (tgt in c("P", "S", "I")) {
      src <- c(P = "D", S = "P", I = "S")[[tgt]]
      for (x in ids[lvl == tgt]) if (!any(edges$to == x & substr(edges$from, 1, 1) == src)) edges <- add(edges, pick(ids[lvl == src]), x)
    }
    for (r in ids[lvl == "R"]) if (!any(edges$from == r)) edges <- add(edges, r, pick(ids[lvl %in% c("D", "P", "S", "I")]))
    # Feedback loops through I -> R only.
    q <- spec$q_loops[sample.int(length(spec$q_loops), 1)]
    for (r in ids[lvl == "R"]) if (stats::runif(1) < q) edges <- add(edges, pick(ids[lvl == "I"]), r)
    edges <- unique(edges)

    # Signs, with harm-oriented States flipping every edge that touches them.
    f <- stats::runif(1, spec$harm_share[1], spec$harm_share[2])
    harm <- ids[lvl == "S"][stats::runif(sum(lvl == "S")) < f]
    key <- paste0(substr(edges$from, 1, 1), ">", substr(edges$to, 1, 1))
    sgn <- SIM_SIGNS[key] * ifelse(edges$from %in% harm | edges$to %in% harm, -1, 1)
    edges$interaction_type <- ifelse(sgn > 0, "positive", "negative")

    # Per-network parameters.
    states <- ids[lvl == "S"]
    thr <- setNames(rep(NA_real_, length(ids)), ids)
    for (s in states) if (stats::runif(1) < spec$p_threshold) {
      z <- stats::runif(1, spec$z[1], spec$z[2])
      # Reference 1 and sd 1 (engine units): level = 1 + z, in the direction
      # the pressure moves the State.
      thr[s] <- 1 + if (s %in% harm) z else -z
    }
    growth <- setNames(rep(0, length(ids)), ids)
    cap <- setNames(rep(NA_real_, length(ids)), ids)
    for (dd in ids[lvl == "D"]) if (stats::runif(1) < spec$p_growth) {
      growth[dd] <- stats::runif(1, spec$growth[1], spec$growth[2])
      if (stats::runif(1) < spec$p_cap) cap[dd] <- 1 + stats::runif(1, spec$cap[1], spec$cap[2])
    }
    impacts <- ids[lvl == "I"]
    ec <- setNames(rep(NA_character_, length(ids)), ids)
    vv <- setNames(rep(NA_real_, length(ids)), ids)
    ec[impacts] <- sample(c("ecological", "service", "welfare"), length(impacts), replace = TRUE)
    vv[impacts] <- ifelse(ec[impacts] == "ecological", 1, stats::runif(length(impacts), 0.2, 1))

    # Scenario.
    resp <- ids[lvl == "R"]
    on <- resp[stats::runif(length(resp)) < spec$p_response]
    if (length(on) == 0) on <- pick(resp)
    strengths <- setNames(stats::runif(length(on), spec$response_strength[1], spec$response_strength[2]), on)

    nodes <- data.frame(
      id = ids, label = ids, dpsir_category = unname(cat_of), subsystem = "",
      self_regulation = ifelse(lvl %in% c("D", "P", "R"), 1, 0.5),
      growth_rate = unname(growth), growth_cap = unname(cap),
      threshold_level = unname(thr), threshold_direction = "auto",
      endpoint_class = unname(ec), value_v = unname(vv),
      stringsAsFactors = FALSE
    )
    list(seed = seed, q = q, harm = harm, nodes = nodes, edges = edges[, c("from", "to", "interaction_type")],
         pressure = setNames(rep(100, sum(lvl == "D")), ids[lvl == "D"]), response = strengths)
  })
}

# Edges of the raw network (C0): every edge "moderate", as first_run_build.R.
raw_edges <- function(net) {
  e <- net$edges
  e$strength_class <- "moderate"
  e
}

# Edges of one strength draw (C1-C4). Returns NULL when every redraw gives
# rho(B) >= 1 (counted as rejected in run.R).
draw_strength_edges <- function(net, seed, spec = sim_spec_default()) {
  e <- net$edges
  resp_from <- net$nodes$dpsir_category[match(e$from, net$nodes$id)] == "Response"
  with_local_seed(seed, {
    for (attempt in seq_len(spec$max_redraws)) {
      mode <- if (stats::runif(1) < 0.5) "classes" else "continuous"
      if (mode == "classes") {
        cls <- strength_classes()
        k <- sample.int(3, nrow(e), replace = TRUE)
        beta <- cls$value[k]; lo <- cls$low[k]; hi <- cls$high[k]
      } else {
        beta <- stats::runif(nrow(e), spec$beta_continuous[1], spec$beta_continuous[2])
        lo <- pmax(0, beta * (1 - spec$band_continuous)); hi <- beta * (1 + spec$band_continuous)
      }
      # Explained-variance rule, on the edges that do not leave a Response.
      for (tgt in unique(e$to)) {
        k <- which(e$to == tgt & !resp_from)
        ss <- sum(beta[k]^2)
        if (ss > spec$max_sum_beta2) {
          f <- sqrt(spec$max_sum_beta2 / ss)
          beta[k] <- beta[k] * f; lo[k] <- lo[k] * f; hi[k] <- hi[k] * f
        }
      }
      out <- e
      out$weight <- beta; out$weight_low <- pmin(lo, beta); out$weight_high <- pmax(hi, beta)
      g <- sim_graph(net$nodes, out)
      if (spectral_radius(effect_matrix(g)) < 1 - 1e-9) {
        attr(out, "mode") <- mode
        attr(out, "attempts") <- attempt
        return(out)
      }
    }
    NULL
  })
}

# igraph of a simulated network through the app's normalization.
sim_graph <- function(nodes, edges, keep = c("thresholds", "growth")) {
  n <- nodes
  if (!"thresholds" %in% keep) n$threshold_level <- NA_real_
  if (!"growth" %in% keep) { n$growth_rate <- 0; n$growth_cap <- NA_real_ }
  schema <- get_default_dpsir_schema()
  build_igraph(normalize_dpsir_nodes(n, schema), normalize_dpsir_edges(edges), schema)
}
