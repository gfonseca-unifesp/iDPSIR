ina_ui <- function() {
  dashboardPage(
    title = "iDPSIR",
    header = dashboardHeader(
      title = dashboardBrand(
        title = "iDPSIR",
        color = "primary"
      ),
      rightUi = tags$li(
        class = "nav-item dropdown",
        tags$a(
          class = "nav-link",
          href = "tutorial/tutorial.html",
          target = "_blank",
          title = "Getting-started tutorial",
          icon("circle-question"),
          " Help"
        )
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
