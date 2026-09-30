# Revisao 3: global strength and confidence of a network (Metrics tab).

test_that("network_strength_confidence tells a parameterized network from a default one", {
  load_g <- function(f) {
    sp <- read_savepoint(file.path("../../docs", paste0(f, ".idpsir.json")))
    build_igraph(sp$nodes, sp$edges, sp$schema)
  }
  par <- network_strength_confidence(load_g("example_gnanapragasam"))
  def <- network_strength_confidence(load_g("example_gnanapragasam_default"))
  val <- function(r, m) r$summary$Value[r$summary$Measure == m]
  expect_equal(val(def, "Links by class (weak / moderate / strong)"), "0 / 20 / 0")
  expect_equal(val(def, "Strength from data / typed in / class / default"), "0% / 0% / 0% / 100%")
  expect_match(val(par, "Strength from data / typed in / class / default"), "^30% / ")
  expect_equal(val(par, "States with a threshold"), "1 of 2")
  # Without loops and with bands that keep their sign, every sign is determinate.
  expect_equal(val(par, "Driver -> Impact effects with a determinate sign"), "100%")
  # Same answer twice (fixed seed).
  expect_identical(par, network_strength_confidence(load_g("example_gnanapragasam")))
  bt <- par$by_transition
  expect_equal(sum(bt$Links), igraph::ecount(load_g("example_gnanapragasam")))
  expect_false(is.unsorted(-bt$`Assumed strength (%)`))
})

test_that("edge_strength_origin separates data, typed, class and default", {
  nodes <- normalize_dpsir_nodes(data.frame(id = c("D1", "P1", "S1"), label = c("d", "p", "s"),
                      dpsir_category = c("Driver", "Pressure", "State"), stringsAsFactors = FALSE))
  edges <- normalize_dpsir_edges(data.frame(from = c("D1", "P1"), to = c("P1", "S1"), interaction_type = "positive",
                      weight = c(0.5, NA), strength_class = c(NA, "weak"),
                      evidence_type = c("regression", "literature"), stringsAsFactors = FALSE))
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())
  expect_equal(edge_strength_origin(g), c("estimated", "class"))
})
