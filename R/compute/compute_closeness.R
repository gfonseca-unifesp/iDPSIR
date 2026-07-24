compute_closeness <- function(g, mode = "all", normalized = TRUE) {
  if (
    is.null(g) ||
      vcount(g) == 0
  ) {
    return(NULL)
  }

  closeness(
    g,
    mode = mode,
    normalized = normalized
  )
}
