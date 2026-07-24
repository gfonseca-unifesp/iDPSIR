compute_density <- function(g) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NA)
  }

  edge_density(g)
}
