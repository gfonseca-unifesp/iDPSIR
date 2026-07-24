source("global.R")

ui <- ina_ui()

server <- function(input, output, session) {
  ina_server(input, output, session)
}

shinyApp(ui, server)
