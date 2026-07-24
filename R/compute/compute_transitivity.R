compute_transitivity <- function(g) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NA)
  }

  transitivity(
    g,
    type = "global"
  )
}
