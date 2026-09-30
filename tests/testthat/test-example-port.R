# The port example (data-raw/port_build.R) must keep telling its story:
# relevance, not only the size of the worsening, orders the Impacts, and
# each response has its period.

port_graph <- function() {
  imp <- import_matrices("../../data/port_nodes.csv", "../../data/port_edges.csv")
  build_igraph(imp$nodes, imp$edges, get_default_dpsir_schema())
}
push <- function(g, v) { p <- setNames(rep(0, vcount(g)), V(g)$name); p[names(v)] <- v; p }

test_that("port example: the prioritization points to one response at a time", {
  g <- port_graph()
  pD <- push(g, c(D1 = 1, D2 = 1, D3 = 1))
  top <- function(resp) {
    s <- sufficiency(g, pD, push(g, setNames(rep(1, length(resp)), resp)))
    pr <- impact_prioritization(g, pD, s)
    pr$id[which.max(pr$priority)]
  }
  expect_equal(top("R5"), "I2")                 # seafood contamination -> runoff treatment
  expect_equal(top(c("R5", "R1")), "I1")        # fauna behaviour -> work window
  s3 <- sufficiency(g, pD, push(g, c(R5 = 1, R1 = 1, R4 = 1)))
  expect_true(all(s3$neutralized))
  # Same worsening, lower relevance: primary production is never on top.
  pr1 <- impact_prioritization(g, pD, sufficiency(g, pD, push(g, c(R5 = 1))))
  expect_lt(pr1$priority[pr1$id == "I4"], pr1$priority[pr1$id == "I1"])
})

test_that("port example: the work window is needed only during dredging, runoff treatment must start early", {
  g <- port_graph()
  pD <- push(g, c(D1 = 1, D2 = 1, D3 = 1))
  pR <- push(g, c(R1 = 1, R4 = 1, R5 = 1))
  drivers <- data.frame(id = c("D1", "D2", "D3"), start = c(3, 1, 1), duration = c(3, 12, 12))
  run <- function(r1_start, r1_dur) simulate_temporal_pair(
    g, pD, pR, windows = 12, stop_rule = "fixed", mode_D = "window", mode_R = "window",
    schedule = rbind(drivers, data.frame(id = c("R1", "R4", "R5"), start = c(r1_start, 3, 1), duration = c(r1_dur, 3, 12)))
  )
  early <- run(1, 12)
  late <- run(6, 7)
  expect_gt(max(early$baseline[, "I1"]), 1.5)
  expect_lt(max(early$scenario[, "I1"]), 0.35)
  expect_lt(max(early$scenario[, "I2"]), 0.5)
  expect_gt(late$scenario[13, "I2"], 10)
})
