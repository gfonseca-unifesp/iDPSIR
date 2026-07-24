ina_toggle_directed <- function(id) {
  prettyToggle(
    inputId = id,
    label_on = "Directed",
    label_off = "Undirected",
    value = FALSE,
    status_on = "primary",
    status_off = "warning"
  )
}

ina_toggle_normalized <- function(id) {
  prettyToggle(
    inputId = id,
    label_on = "Normalized",
    label_off = "Raw Values",
    value = TRUE,
    status_on = "success",
    status_off = "default",
    fill = TRUE,
    bigger = TRUE
  )
}
