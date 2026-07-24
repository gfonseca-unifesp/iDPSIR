compute_eigenvector <- function(g) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NULL)
  }

  eigen_centrality(g)$vector
}
