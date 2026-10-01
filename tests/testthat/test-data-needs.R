# R/data_needs.R: the ranked "what to measure or look up first" table
# (step 5 of the workflow), checked on the example networks.

dn_load <- function(f) {
  sp <- read_savepoint(file.path("../../docs", paste0(f, ".idpsir.json")))
  list(sp = sp, g = build_igraph(sp$nodes, sp$edges, sp$schema))
}
dn_scenario <- function(x, k = 0) {
  ids <- V(x$g)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  if (k == 0) {
    ss <- x$sp$scenario_state
    return(list(p_D = pv(ss$pressure_strengths), press = pv(ss$response_strengths)))
  }
  d <- x$sp$saved_scenarios[[k]]
  list(p_D = pv(d$pressure_strengths[d$pressure_active]), press = pv(d$strengths[d$active]))
}

test_that("data needs: port - tight links, the States without threshold, the order", {
  port <- dn_load("example_port")
  # Scenario 1 (best practices only) has no tight verdict; scenario 2 (+ runoff
  # treatment) does, and its tight links are the ones the Revisao 3 report cites.
  s1 <- data_needs(port$g, dn_scenario(port, 1))
  expect_false("link_tight" %in% s1$type)
  expect_setequal(s1$item[s1$type == "threshold_missing"], c("Water turbidity", "Dissolved Zn in water", "Dissolved Cu in water"))
  s2 <- data_needs(port$g, dn_scenario(port, 2))
  tight <- s2$item[s2$type == "link_tight"]
  expect_true("Cargo terminal (land site) -> Surface runoff" %in% tight)
  expect_true("Runoff treatment system -> Surface runoff" %in% tight)
  # Order: tight links and missing thresholds alternate, then the other blocks.
  expect_equal(s2$type[1:4], c("link_tight", "threshold_missing", "link_tight", "threshold_missing"))
  blocks <- c(link_tight = 1, threshold_missing = 1, threshold_unanchored = 2, link_assumed_reaching = 3,
              response_strength = 4, growth_missing = 5)
  expect_false(is.unsorted(blocks[s2$type]))
  expect_equal(s2$priority_rank, seq_len(nrow(s2)))
  # A link listed as tight is not listed again as assumed.
  expect_length(intersect(tight, s2$item[s2$type == "link_assumed_reaching"]), 0)
})

test_that("data needs: Mangi - tight links and the strength actually applied", {
  m <- dn_load("example_mangi")
  s1 <- data_needs(m$g, dn_scenario(m, 1))
  tight <- s1$item[s1$type == "link_tight"]
  expect_true("General fishing effort -> Fish abundance" %in% tight)
  expect_true("Poverty -> Destructive gear use" %in% tight)
  s2 <- data_needs(m$g, dn_scenario(m, 2))
  rs <- s2[s2$type == "response_strength", ]
  expect_gt(nrow(rs), 0)
  expect_true(all(grepl("Set at 30%", rs$why)))
})

test_that("data needs: Sri Lanka - the stock has its threshold; calibrated links are never assumed", {
  sl <- dn_load("example_gnanapragasam")
  for (sc in list(NULL, dn_scenario(sl, 0))) {
    d <- data_needs(sl$g, sc, temporal = TRUE)
    expect_false("Fish stock (biomass)" %in% d$item[d$type == "threshold_missing"])
    links <- d[d$type %in% c("link_tight", "link_assumed_reaching"), ]
    expect_false(any(grepl("aid .* -> Fleet capacity", links$item)))
    expect_true(all(links$current_source %in% c("class", "default")) || nrow(links) == 0)
  }
  # Growth only when the temporal reading is on.
  expect_false("growth_missing" %in% data_needs(sl$g, dn_scenario(sl, 0), temporal = FALSE)$type)
})

test_that("data needs: in a first-run network every listed link is 'default'", {
  m0 <- dn_load("example_mangi_default")
  # The first-run links keep the article's reference (it documents the
  # structure); without it, every assumed link on a path is listed.
  edges <- m0$sp$edges; edges$reference <- ""
  g0 <- build_igraph(m0$sp$nodes, edges, m0$sp$schema)
  d <- data_needs(g0, NULL)
  links <- d[d$type == "link_assumed_reaching", ]
  expect_gt(nrow(links), 0)
  expect_true(all(links$current_source == "default"))
})

test_that("data needs: without a scenario only structural items, with a note", {
  port <- dn_load("example_port")
  d <- data_needs(port$g, NULL)
  expect_true(all(d$type %in% c("threshold_missing", "threshold_unanchored", "link_assumed_reaching")))
  expect_true(all(is.na(d$effect)))
  expect_match(attr(d, "note"), "No scenario applied")
  expect_equal(nrow(data_needs(port$g, list(p_D = NULL))), nrow(d))
})

test_that("data needs: the exported CSV has the columns of the specification", {
  m <- dn_load("example_mangi")
  d <- data_needs(m$g, dn_scenario(m, 1))
  f <- tempfile(fileext = ".csv")
  utils::write.csv(d, f, row.names = FALSE)
  back <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_equal(names(back), DATA_NEEDS_COLUMNS)
  expect_equal(nrow(back), nrow(d))
})
