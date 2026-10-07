# data-raw/manuscript_supplement.R: tables S1-S3 of the paper, from the
# savepoints. Written to a temporary folder here.

source("../../data-raw/manuscript_supplement.R")

test_that("supplement tables: every factor, link and scheduled push of the three cases", {
  out <- file.path(tempdir(), "supp_test")
  r <- manuscript_supplement(root = "../..", out_dir = out)
  expect_equal(nrow(r$S1$factors), 15); expect_equal(nrow(r$S1$links), 20)
  expect_equal(nrow(r$S2$factors), 22); expect_equal(nrow(r$S2$links), 33)
  expect_equal(nrow(r$S3$factors), 17); expect_equal(nrow(r$S3$links), 20)
  # Every Kenyan link cites a section of the article.
  expect_true(all(grepl("^[0-9.]+$", r$S2$links$section)))
  # Port, scenario 4: the runoff treatment starts in season 6 for 7 seasons.
  s4 <- r$S1$scenarios[r$S1$scenarios$scenario == "4. Runoff treatment starts late" & r$S1$scenarios$factor == "Runoff treatment system", ]
  expect_equal(c(s4$start, s4$duration), c("6", "7"))
  # Sri Lanka: the aid periods and the quota at 85%.
  sch <- r$S3$schedule
  expect_equal(sch$start[sch$factor == "Post-war aid (2010-2012)"], "6")
  expect_equal(sch$strength_pct[sch$factor == "Effort-based quota"], 85)
  # Data needs: the first-run stock threshold comes first (Sri Lanka).
  expect_equal(r$S3$data_needs$Item[1], "Fish stock (biomass)")
  expect_true(all(file.exists(file.path(out, c("S1_port.md", "S2_kenya.md", "S3_srilanka.md")))))
  # The savepoints of each case are copied next to the tables, and load.
  sps <- c("S1_example_port", "S2_example_mangi", "S2_example_mangi_default", "S3_example_gnanapragasam",
           "S3_example_gnanapragasam_default", "S3_example_gnanapragasam_noaidfleet")
  for (f in sps) expect_true(file.exists(file.path(out, paste0(f, ".idpsir.json"))), info = f)
  expect_length(read_savepoint(file.path(out, "S1_example_port.idpsir.json"))$saved_scenarios, 4)
})
