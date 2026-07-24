ina_ui <- function() {
  dashboardPage(
    title = "iDPSIR",
    header = dashboardHeader(
      title = dashboardBrand(
        title = "iDPSIR",
        color = "primary"
      )
    ),
    sidebar = dashboardSidebar(
      sidebarMenu(
        id = "main_sidebar",
        menuItem(
          "Network",
          tabName = "network",
          icon = icon("diagram-project")
        ),
        menuItem(
          "Pathways",
          tabName = "pathways",
          icon = icon("route")
        ),
        menuItem(
          "Responses",
          tabName = "responses",
          icon = icon("play")
        ),
        menuItem(
          "Metrics",
          tabName = "metrics",
          icon = icon("table")
        ),
        menuItem(
          "Centrality",
          tabName = "centrality",
          icon = icon("bullseye")
        ),
        menuItem(
          "Communities",
          tabName = "communities",
          icon = icon("people-group")
        )
      )
    ),
    body = dashboardBody(
      tabItems(
        tabItem(
          tabName = "network",
          network_ui("network")
        ),
        tabItem(
          tabName = "pathways",
          pathways_ui("pathways")
        ),
        tabItem(
          tabName = "responses",
          responses_ui("responses")
        ),
        tabItem(
          tabName = "metrics",
          metrics_ui("metrics")
        ),
        tabItem(
          tabName = "centrality",
          centrality_ui("centrality")
        ),
        tabItem(
          tabName = "communities",
          communities_ui("communities")
        )
      )
    )
  )
}
