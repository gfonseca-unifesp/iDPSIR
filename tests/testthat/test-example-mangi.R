# The Mangi et al. 2007 example (data-raw/mangi2007_build.R) must keep
# telling its story: the existing measures fall short, mostly because of
# compliance; the recommended ones cover the conflicts; all measures fully
# complied neutralize every Impact; warming is out of every response's reach;
# and the "first run" (defaults only) reaches a different priority.

mangi_graph <- function(path = "../../docs/example_mangi.idpsir.json") {
  sp <- read_savepoint(path)
  build_igraph(sp$nodes, sp$edges, sp$schema)
}
push <- function(g, v) { p <- setNames(rep(0, vcount(g)), V(g)$name); p[names(v)] <- v; p }
pressure <- c(D1 = 1, D2 = 1, D3 = 1, D6 = 1)

test_that("Mangi example: no State -> State link, every edge a class, cited to a section", {
  sp <- read_savepoint("../../docs/example_mangi.idpsir.json")
  cat_of <- setNames(sp$nodes$dpsir_category, sp$nodes$id)
  expect_false(any(cat_of[sp$edges$from] == "State" & cat_of[sp$edges$to] == "State"))
  expect_true(all(sp$edges$weight_source == "class"))
  expect_true(all(grepl("^Mangi et al. 2007, section", sp$edges$reference)))
  expect_equal(sp$nodes$growth_rate[sp$nodes$id == "D1"], 0.037)
  expect_length(sp$saved_scenarios, 4)
})

test_that("Mangi example: compliance, not the choice of measures, is the gap", {
  g <- mangi_graph()
  pD <- push(g, pressure)
  suff <- function(r) sufficiency(g, pD, push(g, r))
  written <- suff(c(R1 = 1, R2 = 1, R3 = 1))
  enforced <- suff(c(R1 = 0.3, R2 = 0.3, R3 = 0.3))
  expect_false(any(written$neutralized))
  expect_true(all(enforced$net > written$net))
  plus <- suff(c(R1 = 0.3, R2 = 0.3, R3 = 0.3, R4 = 1, R5 = 1, R6 = 1))
  expect_equal(plus$neutralized, c(FALSE, FALSE, TRUE))   # only the conflicts
  expect_true(all(suff(c(R1 = 1, R2 = 1, R3 = 1, R4 = 1, R5 = 1, R6 = 1))$neutralized))
  # Marine parks alone raise the conflicts (they exclude fishers).
  expect_gt(suff(c(R1 = 1))$mitigation[3], 0)
})

test_that("Mangi example: warming worsens the reef Impacts and no response reaches it", {
  g <- mangi_graph()
  w <- sufficiency(g, push(g, c(D6 = 1)), push(g, c(R1 = 1)))$worsening
  expect_gt(w[1], 0)
  reach <- response_reach(g, c("R1", "R2", "R3", "R4", "R5", "R6"))
  expect_true(length(reach$reached_ids) > 0)
  expect_false(any(c("D6", "P4") %in% reach$reached_ids))
})

test_that("Mangi example: the first run agrees on the verdicts; only growth ends the full-compliance scenario", {
  run <- function(path, resp, windows = 40) {
    g <- mangi_graph(path)
    pD <- push(g, pressure)
    list(g = g, pD = pD, s = sufficiency(g, pD, push(g, resp)),
         tr = simulate_temporal_pair(g, pD, push(g, resp), windows = windows, stop_rule = "fixed"))
  }
  existing <- c(R1 = 1, R2 = 1, R3 = 1)
  full <- c(existing, R4 = 1, R5 = 1, R6 = 1)
  p1 <- run("../../docs/example_mangi.idpsir.json", existing)
  d1 <- run("../../docs/example_mangi_default.idpsir.json", existing)
  expect_equal(p1$s$neutralized, d1$s$neutralized)
  top <- function(r) { pr <- impact_prioritization(r$g, r$pD, r$s); pr$id[which.max(pr$priority)] }
  expect_equal(top(p1), "I3")
  expect_equal(top(d1), "I3")
  # With the defaults the existing measures make the conflicts worse.
  expect_gt(d1$s$mitigation[3], 0)
  expect_lt(p1$s$mitigation[3], 0)
  # Full compliance: the 3.7% growth overtakes it after about 20 years; with
  # the defaults (no growth) it holds for good.
  p4 <- run("../../docs/example_mangi.idpsir.json", full)$tr
  d4 <- run("../../docs/example_mangi_default.idpsir.json", full)$tr
  crosses <- function(tr) which(tr$scenario[-(1:5), "I3"] > 1e-9)[1] + 4
  expect_true(crosses(p4) >= 18 && crosses(p4) <= 25)
  expect_true(all(d4$scenario[-(1:5), c("I1", "I2", "I3")] <= 1e-9))
})
