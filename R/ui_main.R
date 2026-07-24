ina_ui <- function() {
  dashboardPage(
    title = "iDPSIR",
    header = dashboardHeader(
      title = dashboardBrand(
        title = "iDPSIR",
        color = "primary"
      )
    ),
    sidebar = dashboardSidebar(disable = TRUE),
    body = dashboardBody(
      fluidPage(
        mod_wizard_ui("wizard")
      )
    )
  )
}
