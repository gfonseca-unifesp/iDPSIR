# =====================================================
# RESPONSE REACH (topological, roadmap Fase 9 item 9.2)
# =====================================================
#
# "How far does a response's influence travel through the DPSIR chain" -
# pure directed-graph reachability from what the response(s) directly act
# on, no linear algebra involved (unlike R/loop_analysis.R). Deliberately
# independent of build_interaction_matrix()/press_perturbation(): the
# equilibrium effect there is only defined when the network settles (see
# R/loop_analysis.R's notes on self-regulation, roadmap item 9.1), but
# reach is always computable - a response that acts on a Driver can be
# shown to reach the Impacts downstream even on a network with no defined
# long-term effect at all.

response_reach <- function(g, active_ids) {
  stopifnot(inherits(g, "igraph"))

  empty_result <- list(
    reached_ids = character(),
    total = 0L,
    by_category = data.frame(category = character(), count = integer(), stringsAsFactors = FALSE)
  )

  active_ids <- intersect(active_ids, V(g)$name)
  if (length(active_ids) == 0) {
    return(empty_result)
  }

  # What the response(s) directly act on - the starting point for reach,
  # not the response node itself (a response "reaching" itself isn't a
  # meaningful result).
  direct_targets <- unique(unlist(lapply(active_ids, function(id) {
    neighbors(g, id, mode = "out")$name
  })))

  if (length(direct_targets) == 0) {
    return(empty_result)
  }

  # Everything downstream of each direct target, forward along directed
  # edges - subcomponent(mode="out") already includes the starting node
  # itself, so the union naturally includes direct_targets too.
  reached <- unique(unlist(lapply(direct_targets, function(id) {
    V(g)$name[subcomponent(g, id, mode = "out")]
  })))

  # A response reaching back to itself (or another active response) via a
  # feedback loop isn't a new factor reached - excluded from the count.
  reached <- setdiff(reached, active_ids)

  categories <- V(g)$dpsir_category[match(reached, V(g)$name)]
  by_category <- as.data.frame(table(category = categories), stringsAsFactors = FALSE)
  names(by_category) <- c("category", "count")
  by_category$count <- as.integer(by_category$count)

  list(
    reached_ids = reached,
    total = length(reached),
    by_category = by_category
  )
}

# "Y of N Impacts" needs the denominator (how many Impact nodes exist in
# the built graph at all, reached or not) - kept separate from
# response_reach() so that function stays about what a specific set of
# responses reaches, not the whole network's shape.
count_impacts_in_graph <- function(g) {
  stopifnot(inherits(g, "igraph"))
  sum(V(g)$dpsir_category == "Impact")
}
