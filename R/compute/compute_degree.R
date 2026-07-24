compute_degree <- function(g, mode = "all") {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NULL)
  }

  degree(
    g,
    mode = mode
  )
}
