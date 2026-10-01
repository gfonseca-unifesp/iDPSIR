# data-raw/manuscript_figures.R: the six figures of manuscript v7 in print
# resolution. The outputs live in manuscrito_v8/fig_hr/ (not versioned), so
# the test is skipped where they do not exist (CI, a fresh clone).

fig_dir <- "../../manuscrito_v8/fig_hr"
fig_stems <- c("fig1_workflow", "fig2_architecture", "fig3_port", "fig4_kenya", "fig5_srilanka", "fig6_simulated")

png_size <- function(path) {
  con <- file(path, "rb"); on.exit(close(con))
  h <- readBin(con, "raw", 24)
  be <- function(b) sum(as.integer(b) * 256^(3:0))
  c(width = be(h[17:20]), height = be(h[21:24]))
}

test_that("manuscript figures: PNG, TIFF and PDF at 190 mm and 600 dpi", {
  skip_if_not(dir.exists(fig_dir), "manuscript figures not generated here")
  expected_px <- round(190 / 25.4 * 600)   # 4488
  for (s in fig_stems) {
    f <- file.path(fig_dir, paste0(s, c(".png", ".tif", ".pdf")))
    expect_true(all(file.exists(f)), info = s)
    expect_equal(png_size(f[1])[["width"]], expected_px, tolerance = 2, info = s)
    tif <- readBin(f[2], "raw", 4)
    expect_true(identical(tif, as.raw(c(0x49, 0x49, 0x2a, 0x00))) || identical(tif, as.raw(c(0x4d, 0x4d, 0x00, 0x2a))), info = s)
    if (requireNamespace("magick", quietly = TRUE)) {
      info <- magick::image_info(magick::image_read(f[2]))
      expect_equal(info$width, expected_px, tolerance = 2, info = s)
    }
    # The PDF opens: header, and the end-of-file marker within the last bytes.
    expect_identical(readChar(f[3], 5, useBytes = TRUE), "%PDF-", info = s)
    sz <- file.size(f[3])
    con <- file(f[3], "rb"); seek(con, max(0, sz - 64)); tail <- readBin(con, "raw", 64); close(con)
    tail <- rawToChar(tail[tail != as.raw(0)])
    expect_true(grepl("%%EOF", tail, fixed = TRUE, useBytes = TRUE), info = s)
  }
})
