ina_server <- function(input, output, session) {
  network <- network_server("network")

  metrics_server("metrics", network$graph)
  centrality_server("centrality", network$graph)
  communities_server("communities", network$graph)
  pathways_server("pathways", network$graph)
  responses_server("responses", network$graph)
}
