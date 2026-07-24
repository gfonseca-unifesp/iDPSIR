compute_pagerank <- function(g) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NULL)
  }

  page_rank(g)$vector
}
