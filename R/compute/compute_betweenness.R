compute_betweenness <- function(g, directed = TRUE, normalized = TRUE) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NULL)
  }

  betweenness(
    g,
    directed = directed,
    normalized = normalized
  )
}
