# Revisao 3, E8: every number the manuscript cites comes from
# data-raw/manuscript_build.R. A change of the engine that alters one of them
# fails here; if the change is intended, refresh the fixture with
#   Rscript data-raw/manuscript_build.R manuscrito_v5/build --freeze
# and update the manuscript.

source("../../data-raw/manuscript_build.R")
suppressMessages(source("../../R/modules/mod_responses.R"))

test_that("the numbers cited in the manuscript are unchanged", {
  frozen <- jsonlite::read_json("fixtures/manuscript_numbers.json", simplifyVector = TRUE)
  now <- manuscript_numbers("../..", with_sim = TRUE)
  expect_setequal(names(now), names(frozen))
  for (k in names(frozen)) {
    if (is.numeric(frozen[[k]])) expect_equal(now[[k]], frozen[[k]], tolerance = 1e-6, info = k)
    else expect_identical(as.character(now[[k]]), as.character(frozen[[k]]), info = k)
  }
})
