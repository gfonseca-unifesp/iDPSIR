# R/interpretation.R: the plain-language reading shown in the Interpretation
# tab and in the report. Checked on the Mangi example, whose story is known
# (tests/testthat/test-example-mangi.R).

interp_graph <- function() {
  sp <- read_savepoint("../../docs/example_mangi.idpsir.json")
  build_igraph(sp$nodes, sp$edges, sp$schema)
}
interp_scenario <- function(g, resp) {
  pv <- function(v) { p <- setNames(rep(0, vcount(g)), V(g)$name); p[names(v)] <- v; p }
  pD <- pv(c(D1 = 1, D2 = 1, D3 = 1, D6 = 1))
  pR <- pv(resp)
  s <- sufficiency(g, pD, pR)
  conf <- sufficiency_confidence(g, pD, pR, n_simulations = 100)
  cm <- as.data.frame(t(conf$neutralized_pct)); names(cm) <- conf$node
  cm <- cbind(Response = "Planned scenario (as set)", cm)
  list(sufficiency_df = s, prioritization = impact_prioritization(g, pD, s, n_simulations = 100),
       sufficiency_confidence_matrix = cm, active = names(resp), strengths = resp * 100, p_D = pD, press = pR)
}

test_that("interpretation: statuses, order and headline follow the sufficiency numbers", {
  g <- interp_graph()
  it <- interpret_scenario(g, interp_scenario(g, c(R1 = 1, R2 = 1, R3 = 1)))
  expect_equal(it$headline, "The response scenario neutralizes 0 of 3 worsened Impacts.")
  expect_true(all(it$impacts$status == "partial"))
  # Priority order: rank 1 has the largest priority.
  expect_equal(it$impacts$rank, 1:3)
  expect_true(all(diff(it$impacts$priority) <= 0))
  expect_match(it$messages[1], paste0("^Act first on ", it$impacts$node[1]))
  expect_match(it$impacts$text[it$impacts$id == "I1"], "offsets 85% of the worsening")

  full <- interpret_scenario(g, interp_scenario(g, c(R1 = 1, R2 = 1, R3 = 1, R4 = 1, R5 = 1, R6 = 1)))
  expect_equal(full$headline, "The response scenario neutralizes all 3 worsened Impacts.")
  expect_true(all(full$impacts$status == "neutralized"))
})

test_that("interpretation: a response that worsens an Impact is flagged", {
  g <- interp_graph()
  # Marine parks alone raise the conflicts (they exclude fishers).
  it <- interpret_scenario(g, interp_scenario(g, c(R1 = 1)))
  row <- it$impacts[it$impacts$id == "I3", ]
  expect_equal(row$status, "worsened_by_response")
  expect_true(any(grepl("itself worsens: Exclusion and conflicts", it$messages)))
})

test_that("interpretation: comparison has one row per scenario and one column per Impact", {
  g <- interp_graph()
  scs <- list(A = interp_scenario(g, c(R1 = 1, R2 = 1, R3 = 1)),
              B = interp_scenario(g, c(R1 = 1, R2 = 1, R3 = 1, R4 = 1, R5 = 1, R6 = 1)))
  cmp <- compare_scenario_interpretations(g, scs)
  expect_equal(cmp$Scenario, c("A", "B"))
  expect_equal(cmp$Neutralized, c("0 of 3", "3 of 3"))
  expect_equal(unname(unlist(cmp[2, c("Declining catch per fisher", "Livelihood benefits compromised", "Exclusion and conflicts")])), rep("Neutralized", 3))
  expect_match(cmp[1, "Declining catch per fisher"], "% covered$")
  expect_equal(cmp[["Top priority left"]][2], "-")
})

test_that("interpretation: tight verdicts name the links on the paths to the Impact", {
  g <- interp_graph()
  sc <- interp_scenario(g, c(R1 = 1, R2 = 1, R3 = 1))
  it <- interpret_scenario(g, sc)$impacts
  expected <- it$worsening > 1e-9 & abs(it$net) < INTERPRETATION_TIGHT * it$worsening
  expect_equal(it$tight, expected)
  # Force one: shrink the net of the first worsened Impact.
  sc$sufficiency_df$net[sc$sufficiency_df$id == "I1"] <- 0.05 * sc$sufficiency_df$worsening[sc$sufficiency_df$id == "I1"]
  out <- interpret_scenario(g, sc)
  row <- out$impacts[out$impacts$id == "I1", ]
  expect_true(row$tight)
  expect_match(row$text, "Tight verdict")
  expect_match(row$text, "links involved: ")
  expect_true(any(grepl("^Tight verdicts", out$messages)))
  # The links: source reached from a pushed factor, target reaching I1.
  lk <- tight_verdict_links(g, "I1", c("D1", "R1"))
  expect_gt(nrow(lk), 0)
  reach_I1 <- is.finite(igraph::distances(g, v = lk$to, to = "I1", mode = "out")[, 1])
  expect_true(all(reach_I1))
  expect_equal(nrow(tight_verdict_links(g, "I1", character())), 0)
  # With the pushes, the links come ordered by how much they move the net.
  lk2 <- tight_verdict_links(g, "I1", c("D1", "R1"), sc$p_D, sc$press)
  expect_false(is.unsorted(rev(lk2$influence[!is.na(lk2$influence)])))
  expect_gt(max(lk2$influence, na.rm = TRUE), 0)
})
