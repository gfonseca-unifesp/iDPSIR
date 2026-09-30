# =====================================================
# Mangi et al. (2007) reef fisheries example - build script
# =====================================================
#
# Source: Mangi, S.C., Roberts, C.M., Rodwell, L.D. (2007). Reef fisheries
# management in Kenya: preliminary approach using the driver-pressure-
# state-impacts-response (DPSIR) scheme of indicators. Ocean & Coastal
# Management 50, 463-480. doi:10.1016/j.ocecoaman.2006.10.003
#
# Structure = the indicators of the article's Table 1 and sections 3.1-3.6,
# simplified by one rule (DPSIR is for monitoring and management, not for
# portraying every interaction): two indicators in a cause-effect chain are
# not both monitored.
#   - "Number of fishers" and "excessive exploitation" (3.2.1/3.2.2) are one
#     chain -> one Pressure, general fishing effort.
#   - The sea urchin release (3.3.3) is a chain fish predators -> urchins ->
#     reef. The indicator worth monitoring is the urchin density; fishing of
#     the urchin's predator (red-lined triggerfish, Balistapus undulatus) is
#     a Pressure of its own, parallel to general fishing effort.
# Responses: the three the article describes as existing in 2007 (3.5) and
# three it recommends (section 6), marked in their descriptors. Barriers to
# change (3.6: poor enforcement, low compliance) are not nodes: they lower
# how much of a response actually acts - the "as enforced" scenarios.
#
# The article gives no link strengths ("a 10% rise in coastal population
# does not correspond to a 10% rise in fishing pressure", section 6): every
# edge is a class, "strong" only where the text describes a main or
# dramatic effect. The one number used as a parameter is the coastal
# population growth, 3.7% per year (2.5 million in 1999; 3.1.1) - one
# window = one year. The classes also respect standardized coefficients: the
# squared strengths arriving at a factor add up to less than 1 (the Review
# step checks it), so where two causes compete the article's emphasis decides
# which one is strong. No Impact -> Response links: which Impact calls for
# which response is what the prioritization shows.
#
# Writes data/mangi2007_nodes.csv, data/mangi2007_edges.csv and
# docs/example_mangi.idpsir.json (with saved scenarios). The "first run"
# version with every setting at the default comes from
# data-raw/first_run_build.R.
# Run from the repository root:  Rscript data-raw/mangi2007_build.R

sec <- function(s) paste0("Mangi et al. 2007, section ", s, " (doi:10.1016/j.ocecoaman.2006.10.003)")

nodes <- data.frame(
  id = c("D1","D2","D3","D4","D5","D6", "P1","P2","P3","P4", "S1","S2","S3", "I1","I2","I3",
         "R1","R2","R3","R4","R5","R6"),
  label = c("Coastal population","Poverty","Unemployment","Tourism employment","Traditional fishing customs","Sea warming",
            "General fishing effort","Triggerfish fishing","Destructive gear use","Thermal stress (bleaching)",
            "Fish abundance","Live coral cover","Sea urchin density",
            "Declining catch per fisher","Livelihood benefits compromised","Exclusion and conflicts",
            "No-take marine parks","Gear restrictions","Education and awareness",
            "Tourism-based alternative livelihoods","Co-management with access rights","Gear exchange with credit"),
  dpsir_category = c(rep("Driver",6), rep("Pressure",4), rep("State",3), rep("Impact",3), rep("Response",6)),
  subsystem = c(rep("Society",5), "Climate", rep("Fishery",3), "Climate", rep("Reef",3),
                "Fishery","Human welfare","Human welfare", rep("Management",6)),
  # Drivers, Pressures and Responses are levels set by the scenario (1 =
  # no memory), as in the port example; the rest keep the app default.
  self_regulation = c(rep(1,10), rep(0.5,3), rep(0.5,3), rep(1,6)),
  growth_rate = c(0.037, rep(0, 21)),
  reference_value = c(2.5, rep(NA, 21)),
  endpoint_class = c(rep(NA,13), "service","welfare","welfare", rep(NA,6)),
  value_v = c(rep(NA,13), 1, 1, 1, rep(NA,6)),
  stringsAsFactors = FALSE)
nodes$descriptor <- c(
  "Coastal population, million (2.5 in 1999), growing 3.7% per year (3.1.1).",
  "Share of the population below the poverty line (42%, 3.1.4).",
  "Unemployment rate (40% in 2001, 3.1.2).",
  "Jobs in coastal tourism; when tourism fell (1997-98) boat operators turned to fishing (3.1.5).",
  "Customary rules (taboos, elders) that regulate where and how to fish; their decay leads young fishers to non-traditional gears (3.1.3).",
  "Rising sea surface temperature (external variability; +1.5 C in the 1998 event, 3.3.4).",
  "Number of fishers per km2 and the catch they take (3.2.1-3.2.2); the trend in total catch is the alternative indicator.",
  "Fishing of the urchin's predators, e.g. the red-lined triggerfish Balistapus undulatus (3.3.3).",
  "Frequency of use of beach seines and spear guns (3.2.3).",
  "Coral bleaching episodes driven by warm-water anomalies (3.3.4).",
  "Fish biomass, kg/ha (3.3.1).",
  "Percentage of live hard coral and reef complexity; fished reefs have half the cover of unfished ones (3.3.2).",
  "Density of grazing and rock-boring urchins (no./m2), released when their predators are fished; they erode the reef and compete with fish (3.3.3).",
  "Catch per unit effort, kg per fisher (3-4 kg/day, 3.4.1).",
  "Share of household income and food that depends on the reef (3.4.2).",
  "Fishers excluded and number of conflicts among reef users (3.4.3).",
  "Existing in 2007: four marine parks with no extraction (3.5.1). Also excludes fishers.",
  "Existing in 2007: Fisheries Act gear and mesh rules, reserves with gear restrictions; beach seines banned but still used (3.5.1).",
  "Existing in 2007: awareness campaigns and meetings with fishers (3.5.2).",
  "Recommended (section 6): develop tourism and other income around parks to remove fishers from the reef.",
  "Recommended (section 6): licences, exclusive access rights and collaborative (ICZM) management with local fishers.",
  "Recommended (section 6): credit to buy authorized gear and compensation for gear declared illegal.")

mk <- function(f, t, cls, sg, s) data.frame(from = f, to = t, strength_class = cls, interaction_type = sg,
                                          evidence_type = "literature", reference = sec(s), stringsAsFactors = FALSE)
edges <- rbind(
  # Drivers -> Pressures
  mk("D1","P1","strong","positive","3.1.1"), mk("D2","P1","weak","positive","3.2.1"),
  mk("D3","P1","moderate","positive","3.1.2"), mk("D4","P1","weak","negative","3.1.5"),
  mk("D1","P2","moderate","positive","3.2.2"), mk("D2","P2","moderate","positive","3.2.2"),
  mk("D1","P3","weak","positive","3.1.1"), mk("D2","P3","strong","positive","5"),
  mk("D5","P3","moderate","negative","3.1.3"), mk("D6","P4","strong","positive","3.3.4"),
  # Pressures -> States
  mk("P1","S1","strong","negative","3.3.1"), mk("P3","S1","moderate","negative","3.2.3"),
  mk("P3","S2","strong","negative","3.3.2"), mk("P4","S2","moderate","negative","3.3.4"),
  mk("P2","S3","strong","positive","3.3.3"),
  # States -> Impacts (the urchin's effect on fish and reef reaches the
  # Impacts directly: no State -> State links)
  mk("S1","I1","strong","negative","3.4.1"), mk("S2","I1","moderate","negative","3.3.2"),
  mk("S3","I1","weak","positive","3.3.3"),
  mk("S1","I2","moderate","negative","3.4.2"), mk("S2","I2","moderate","negative","3.4.2"),
  mk("S3","I2","moderate","positive","3.3.3"),
  mk("S1","I3","moderate","negative","3.4.3"),
  # Responses
  mk("R1","P1","moderate","negative","3.5.1"), mk("R1","P2","moderate","negative","3.5.1"),
  mk("R1","P3","moderate","negative","3.5.1"), mk("R1","I3","moderate","positive","3.4.3"),
  mk("R2","P3","strong","negative","3.5.1"), mk("R3","P3","moderate","negative","3.5.2"),
  mk("R4","D4","strong","positive","6"), mk("R4","D3","moderate","negative","6"),
  mk("R5","P1","moderate","negative","6"), mk("R5","I3","moderate","negative","3.5.2"),
  mk("R6","P3","strong","negative","6"))
stopifnot(!anyDuplicated(paste(edges$from, edges$to)))

if (sys.nframe() == 0) {
  setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
  utils::write.csv(nodes, "data/mangi2007_nodes.csv", row.names = FALSE, na = "")
  utils::write.csv(edges, "data/mangi2007_edges.csv", row.names = FALSE, na = "")
  imp <- import_matrices("data/mangi2007_nodes.csv", "data/mangi2007_edges.csv")

  temporal <- list(
    temporal_mode_pressure = "permanent", temporal_mode_response = "permanent", temporal_stop_rule = "fixed",
    temporal_windows = 30, temporal_max_windows = 50, temporal_tol_rel = 5, baseline_without_response = FALSE,
    temporal_gate_mode = "state_level", temporal_trends_outside = TRUE, temporal_continue_after = 0)
  pressure <- list(pressure_active = c("D1", "D2", "D3", "D6"),
                   pressure_strengths = c(D1 = 100, D2 = 100, D3 = 100, D6 = 100))
  scenario <- function(name, strengths) c(
    list(name = name, active = names(strengths), strengths = strengths, n_simulations = 300L), pressure, temporal)
  existing_written <- c(R1 = 100, R2 = 100, R3 = 100)
  existing_enforced <- c(R1 = 30, R2 = 30, R3 = 30)
  recommended <- c(R4 = 100, R5 = 100, R6 = 100)
  saved <- list(
    scenario("1. Existing measures, as written", existing_written),
    scenario("2. Existing measures, as enforced (30%)", existing_enforced),
    scenario("3. + Recommended measures", c(existing_enforced, recommended)),
    scenario("4. All measures, fully complied", c(existing_written, recommended)))
  names(saved) <- vapply(saved, `[[`, "", "name")
  state <- c(list(response_active = names(existing_written), response_strengths = existing_written), pressure, temporal)
  sp <- build_savepoint(
    get_default_dpsir_schema(), imp$nodes, imp$edges,
    metadata = list(project_name = "Example: Kenyan reef fisheries (Mangi et al. 2007)",
                    author = "iDPSIR examples",
                    notes = "Structure from Mangi et al. 2007 (Table 1, sections 3-6). One window = one year. Strengths are classes; the only parameter from the article is the 3.7%/yr population growth."),
    scenario_state = state, saved_scenarios = saved)
  write_savepoint(sp, "docs/example_mangi.idpsir.json")

  # Figures for the tutorial: the network, and the temporal chart of
  # scenario 4 (all measures fully complied), the app's own chart.
  g <- build_igraph(imp$nodes, imp$edges, get_default_dpsir_schema())
  cols <- setNames(sp$schema$color, sp$schema$name)
  cat_order <- sp$schema$name
  cats <- V(g)$dpsir_category
  x <- match(cats, cat_order)
  y <- ave(seq_along(cats), cats, FUN = function(i) seq_along(i) - (length(i) + 1) / 2)
  render_plot_png(function() {
    par(mar = c(0.5, 0.5, 2, 0.5))
    plot(g, layout = cbind(x * 3, -y * 1.4), vertex.shape = "circle", vertex.color = cols[cats], vertex.size = 8,
         vertex.label = V(g)$label, vertex.label.cex = 0.7, vertex.label.dist = 1.6, vertex.label.color = "black",
         vertex.label.degree = pi / 2, edge.color = unname(get_interaction_type_colors()[E(g)$interaction_type]),
         edge.arrow.size = 0.35, edge.width = 1 + 2.5 * E(g)$weight, edge.curved = 0.12,
         main = "Kenyan reef fisheries (Mangi et al. 2007)")
    legend("bottomleft", legend = cat_order, pt.bg = cols[cat_order], pch = 21, pt.cex = 1.6, bty = "n", cex = 0.8)
    legend("bottomright", legend = c("positive (increases)", "negative (decreases)"),
           col = get_interaction_type_colors()[c("positive", "negative")], lwd = 2, bty = "n", cex = 0.8)
  }, "docs/example_mangi_network.png", width = 1600, height = 1100)

  sc <- saved[[4]]
  tr <- simulate_temporal_pair(g, build_press_vector(g, sc$pressure_active, sc$pressure_strengths / 100),
                               build_press_vector(g, sc$active, sc$strengths / 100), windows = 30, stop_rule = "fixed")
  tb <- format_temporal_table(g, tr)
  render_plot_png(function() plot_temporal_storyboard(tb, reinforcing_warning = isTRUE(tr$stability$unbounded)),
                  "docs/example_mangi_temporal_4.png", width = 1300, height = 800)
  message("Written: data/mangi2007_{nodes,edges}.csv, docs/example_mangi.idpsir.json and figures.")

}
