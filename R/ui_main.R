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
      # bs4Dash auto-injects a "help mode" toggle switch (the "?" icon next to
      # the dark-mode switch) alongside the header - confirmed live that
      # clicking it produces zero DOM change, since this app never sets a
      # help attribute on any bs4Dash::box(). The dark-mode switch right next
      # to it (#theme_switch) IS functional (toggles the dashboard skin) and
      # stays. No bs4Dash param disables just the help switch, so it's hidden
      # client-side instead of left as dead UI. Placed in the body, not
      # rightUi, because dashboardHeader() asserts every top-level rightUi tag
      # is an <li class="dropdown"> (see the "Help" link above, which needed
      # that exact class to pass) - a <script> tag there would fail the same
      # assertion and break the whole app at startup.
      tags$script(HTML(
        "$(function() { $('#help_switch').closest('.custom-control').hide(); });"
      )),
      fluidPage(
        mod_wizard_ui("wizard")
      )
    )
  )
}
