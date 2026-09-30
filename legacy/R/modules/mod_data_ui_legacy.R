# LEGACY - moved out of the app in Revisao 2, Fase 4 (30/09/2026).
# Not sourced by global.R. Kept for reference; originally in R/modules/mod_data.R.


# =====================================================
# UI
# =====================================================

mod_data_ui <- function(id) {
  ns <- NS(id)

  tagList(
    uiOutput(ns("start_step")),
    uiOutput(ns("model_step")),
    uiOutput(ns("nodes_step")),
    uiOutput(ns("edges_step")),
    uiOutput(ns("review_step"))
  )
}

