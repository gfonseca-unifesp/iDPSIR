compute_all_metrics <- function(g) {
  
  node_labels <- vertex_attr(
    g,
    "label"
  )
  
  if(is.null(node_labels)){
    node_labels <- V(g)$name
  }
  
  data.frame(
    
    id = V(g)$name,
    
    node = node_labels,
    
    degree = compute_degree(g),
    
    betweenness = compute_betweenness(g),
    
    closeness = compute_closeness(g),
    
    pagerank = compute_pagerank(g),
    
    eigenvector = compute_eigenvector(g),
    
    stringsAsFactors = FALSE
  )
}