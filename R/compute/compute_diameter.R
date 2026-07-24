compute_diameter <- function(g) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NA)
  }

  diameter(
    g,
    directed = TRUE
  )
}
