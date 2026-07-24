compute_communities <- function(g) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NULL)
  }

  cluster_louvain(
    as.undirected(g)
  )
}
