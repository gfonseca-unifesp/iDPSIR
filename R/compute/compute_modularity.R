compute_modularity <- function(g) {
  communities <- compute_communities(g)

  if (
    is.null(communities)
  ) {
    return(NA)
  }

  modularity(communities)
}
