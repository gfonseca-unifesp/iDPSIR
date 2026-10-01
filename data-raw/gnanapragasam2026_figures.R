# Figures of the Sri Lanka example for the tutorial and the README.
# Run from the repository root after gnanapragasam2026_build.R:
#   Rscript data-raw/gnanapragasam2026_figures.R
# Writes docs/example_gnanapragasam_{network,temporal_chart,validation}.png.

setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")

sp <- read_savepoint("docs/example_gnanapragasam.idpsir.json")
g <- build_igraph(sp$nodes, sp$edges, sp$schema)
ss <- sp$scenario_state
pv <- function(v) { p <- setNames(rep(0, vcount(g)), V(g)$name); p[names(v)] <- v / 100; p }
p_D <- pv(ss$pressure_strengths)
p_R <- pv(ss$response_strengths)
tr <- simulate_temporal_pair(
  g, p_D, p_R, windows = ss$temporal_windows, stop_rule = "fixed",
  mode_D = ss$temporal_mode_pressure, mode_R = ss$temporal_mode_response, schedule = ss$temporal_schedule
)
ref <- setNames(sp$nodes$reference_value, sp$nodes$id)
sdv <- setNames(sp$nodes$sd, sp$nodes$id)
years <- 2004 + seq_len(nrow(tr$scenario)) - 1

# 1. Network --------------------------------------------------------------
cat_order <- c("Driver", "Pressure", "State", "Impact", "Response")
cats <- V(g)$dpsir_category
cols <- setNames(sp$schema$color, sp$schema$name)
x <- match(cats, cat_order)
y <- ave(seq_along(cats), cats, FUN = function(i) seq_along(i) - (length(i) + 1) / 2)
lay <- cbind(x * 3, -y * 1.4)
edge_col <- unname(get_interaction_type_colors()[E(g)$interaction_type])
render_plot_png(function() {
  par(mar = c(0.5, 0.5, 2, 0.5))
  plot(g, layout = lay, vertex.shape = "circle", vertex.color = cols[cats], vertex.size = 9,
       vertex.label = V(g)$label, vertex.label.cex = 0.72, vertex.label.dist = 1.6, vertex.label.color = "black",
       vertex.label.degree = pi / 2, edge.color = edge_col, edge.arrow.size = 0.4, edge.width = 1 + 2.5 * E(g)$weight,
       edge.curved = 0.15, rescale = TRUE, main = "Sri Lanka small-scale fisheries (Gnanapragasam et al. 2026)")
  legend("bottomleft", legend = cat_order, pt.bg = cols[cat_order], pch = 21, pt.cex = 1.6, bty = "n", cex = 0.8)
  legend("bottomright", legend = c("positive (increases)", "negative (decreases)"),
         col = get_interaction_type_colors()[c("positive", "negative")], lwd = 2, bty = "n", cex = 0.8)
}, "docs/example_gnanapragasam_network.png", width = 1500, height = 1000)

# 2. Temporal chart (the app's own chart) ----------------------------------
tb <- format_temporal_table(g, tr)
render_plot_png(function() plot_temporal_storyboard(tb, reinforcing_warning = isTRUE(tr$stability$unbounded), neutralized_at = tr$neutralized_at),
                "docs/example_gnanapragasam_temporal_chart.png", width = 1300, height = 900)

# 3. Validation: effort (observed vs simulated) and fish stock -------------
obs <- read.csv("data/gnanapragasam2026_effort_observed.csv")
effort_s <- ref["P1"] + sdv["P1"] * tr$scenario[, "P1"]
effort_b <- ref["P1"] + sdv["P1"] * tr$baseline[, "P1"]
stock_s <- ref["S1"] + sdv["S1"] * tr$scenario[, "S1"]
stock_b <- ref["S1"] + sdv["S1"] * tr$baseline[, "S1"]
render_plot_png(function() {
  par(mfrow = c(1, 2), mar = c(4.2, 4.5, 3, 1))
  plot(obs$year, obs$total_effort_kwdays_1000, type = "b", pch = 16, col = "grey30", xlim = range(c(obs$year, years)),
       ylim = c(0, 19000), xlab = "Year", ylab = "Fishing effort (thousand kW-days)", main = "Fishing effort")
  lines(years, effort_s, col = "#1f77b4", lwd = 2.5)
  lines(years, effort_b, col = "#1f77b4", lwd = 1.5, lty = 2)
  abline(h = 15462, col = "#d62728", lty = 3); text(1991, 15462, "E_MSY", pos = 3, cex = 0.75, col = "#d62728")
  abline(h = 12287, col = "#2ca02c", lty = 3); text(1991, 12287, "E_MEY", pos = 3, cex = 0.75, col = "#2ca02c")
  rect(2004.5, -1000, 2009.5, 20000, col = adjustcolor("orange", 0.12), border = NA)
  rect(2009.5, -1000, 2012.5, 20000, col = adjustcolor("purple", 0.10), border = NA)
  rect(2021.5, -1000, 2030.5, 20000, col = adjustcolor("#2ca02c", 0.08), border = NA)
  legend("bottomright", legend = c("Observed (Fig. 4)", "Simulated", "Simulated, no response", "Aid 2005-09 / 2010-12", "Quota + anti-poaching from 2022"),
         col = c("grey30", "#1f77b4", "#1f77b4", adjustcolor("orange", 0.5), adjustcolor("#2ca02c", 0.4)),
         lty = c(1, 1, 2, NA, NA), pch = c(16, NA, NA, 15, 15), lwd = c(1, 2.5, 1.5, NA, NA), pt.cex = c(1, 1, 1, 2, 2), bty = "n", cex = 0.72)
  plot(years, stock_s, type = "l", lwd = 2.5, col = "#1f77b4", ylim = c(250, 520), xlab = "Year", ylab = "Fish stock (kt)", main = "Fish stock (biomass)")
  lines(years, stock_b, lwd = 1.5, lty = 2, col = "#1f77b4")
  abline(h = 345.2, col = "#d62728", lty = 3); text(2009, 345.2, "B_MSY (threshold)", pos = 3, cex = 0.75, col = "#d62728")
  points(2021, 321, pch = 4, cex = 1.4, lwd = 2); text(2021, 321, "article, 2021", pos = 1, cex = 0.7)
  points(2030, 413, pch = 4, cex = 1.4, lwd = 2); text(2030, 413, "article, 25% cut", pos = 2, cex = 0.7)
}, "docs/example_gnanapragasam_validation.png", width = 1500, height = 650)
cat("Figures written.\n")
