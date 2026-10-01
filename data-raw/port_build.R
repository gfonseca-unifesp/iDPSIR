# =====================================================
# Port operations example - build script
# =====================================================
#
# A didactic network (adapted from a port environmental impact assessment
# table): two groups of Impacts with different relevance, each covered by a
# different response, one of which is only needed for part of the time.
#   - turbidity group: dredging and ship traffic -> sediment resuspension ->
#     turbidity -> fauna behaviour, primary production (recovers quickly);
#   - metals group: cargo terminal -> surface runoff -> dissolved Zn/Cu ->
#     biota (seafood) contamination, CONAMA water-quality class (persists,
#     bioaccumulates).
# One window = one season; the maintenance dredging campaign runs in
# windows 3-5. Strengths are classes (qualitative). Impact -> Response links
# of the original table were left out: which Impact calls for which response
# is what the prioritization shows.
#
# Writes data/port_nodes.csv, data/port_edges.csv and
# docs/example_port.idpsir.json (with four saved scenarios).
# Run from the repository root:  Rscript data-raw/port_build.R

nodes <- data.frame(
  id = c("D1","D2","D3","P1","P2","S1","S2","S3","I1","I2","I3","I4","R1","R4","R5"),
  label = c("Maintenance dredging","Cargo terminal (land site)","Vessel traffic and operation",
            "Surface runoff","Sediment resuspension","Water turbidity","Dissolved Zn in water","Dissolved Cu in water",
            "Behavioral alterations of fauna","Biota contamination (seafood)","Water quality loss (CONAMA classes)","Loss of primary production",
            "Runoff treatment system","Environmental work window","Best practices adoption"),
  dpsir_category = c(rep("Driver",3), rep("Pressure",2), rep("State",3), rep("Impact",4), rep("Response",3)),
  subsystem = c("Port operation","Port operation","Port operation","Water","Water","Water","Water","Water",
                "Ecosystem","Human welfare","Human welfare","Ecosystem service","Management","Management","Management"),
  self_regulation = c(1,1,1, 1,1, 0.7,0.2,0.2, 0.8,0.1,0.5,0.5, 1,1,1),
  endpoint_class = c(rep(NA,8), "ecological","welfare","welfare","service", rep(NA,3)),
  value_v = c(rep(NA,8), 1, 1, 0.6, 0.4, rep(NA,3)),
  stringsAsFactors = FALSE)
nodes$descriptor <- c(
  "Periodic dredging campaigns to keep the access channel navigable.",
  "Cargo terminal and industrial plant on land; its paved area drains to the bay.",
  "Ship traffic and berthing operations in the port.",
  "Rainwater runoff from the terminal, carrying metals.",
  "Fine sediment put back in suspension by dredging and ship propellers.",
  "Water turbidity (clears within weeks once resuspension stops).",
  "Dissolved zinc in the water column (persists; slow to clear).",
  "Dissolved copper in the water column (persists; slow to clear).",
  "Changes in fish and invertebrate behaviour under turbid water (reversible).",
  "Metal accumulation in fish and shellfish eaten by people (bioaccumulates; slow to reverse).",
  "Loss of the water-quality class set by CONAMA Resolution 357 (legal compliance).",
  "Loss of phytoplankton primary production when turbidity blocks light.",
  "Collection and treatment of the terminal's runoff before it reaches the bay.",
  "Dredging restricted to the environmentally least sensitive period.",
  "General good practices (dredging methods, speed limits, housekeeping).")
mk <- function(f, t, cls, sg) data.frame(from = f, to = t, strength_class = cls, interaction_type = sg, stringsAsFactors = FALSE)
edges <- rbind(
  mk("D1","P2","strong","positive"), mk("D3","P2","moderate","positive"), mk("D2","P1","strong","positive"),
  mk("P1","S1","weak","positive"), mk("P1","S2","strong","positive"), mk("P1","S3","strong","positive"),
  mk("P2","S1","strong","positive"), mk("P2","S2","weak","positive"), mk("P2","S3","weak","positive"),
  mk("S1","I1","strong","positive"), mk("S1","I4","strong","positive"), mk("S1","I3","weak","positive"),
  mk("S2","I2","moderate","positive"), mk("S2","I3","moderate","positive"),
  mk("S3","I2","strong","positive"), mk("S3","I3","moderate","positive"),
  mk("R1","P1","strong","negative"), mk("R4","P2","strong","negative"),
  mk("R5","D1","moderate","negative"), mk("R5","D3","moderate","negative"))
edges$evidence_type <- "expert_assessment"; edges$reference <- ""
edges$reference[edges$from %in% c("D1","D2","D3")] <- "EIA"

if (sys.nframe() == 0) {
  setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
  utils::write.csv(nodes, "data/port_nodes.csv", row.names = FALSE, na = "")
  utils::write.csv(edges, "data/port_edges.csv", row.names = FALSE, na = "")
  imp <- import_matrices("data/port_nodes.csv", "data/port_edges.csv")

  temporal <- function(sched_R) list(
    temporal_mode_pressure = "window", temporal_mode_response = "window", temporal_stop_rule = "fixed",
    temporal_windows = 12, temporal_max_windows = 50, temporal_tol_rel = 5, baseline_without_response = FALSE,
    temporal_gate_mode = "state_level", temporal_trends_outside = TRUE, temporal_continue_after = 0,
    temporal_schedule = rbind(data.frame(id = c("D1", "D2", "D3"), start = c(3, 1, 1), duration = c(3, 12, 12)), sched_R))
  pressure <- list(pressure_active = c("D1", "D2", "D3"), pressure_strengths = c(D1 = 100, D2 = 100, D3 = 100))
  scenario <- function(name, resp, sched_R) c(
    list(name = name, active = resp, strengths = setNames(rep(100, length(resp)), resp), n_simulations = 300L),
    pressure, temporal(sched_R))
  saved <- list(
    scenario("1. Best practices only", "R5", data.frame(id = "R5", start = 1, duration = 12)),
    scenario("2. + Runoff treatment", c("R5", "R1"), data.frame(id = c("R5", "R1"), start = c(1, 1), duration = c(12, 12))),
    scenario("3. + Work window during dredging", c("R5", "R1", "R4"),
             data.frame(id = c("R5", "R1", "R4"), start = c(1, 1, 3), duration = c(12, 12, 3))),
    scenario("4. Runoff treatment starts late", c("R5", "R1", "R4"),
             data.frame(id = c("R5", "R1", "R4"), start = c(1, 6, 3), duration = c(12, 7, 3)))
  )
  names(saved) <- vapply(saved, `[[`, "", "name")
  state <- c(list(response_active = "R5", response_strengths = c(R5 = 100)), pressure,
             temporal(data.frame(id = "R5", start = 1, duration = 12)))
  sp <- build_savepoint(
    get_default_dpsir_schema(), imp$nodes, imp$edges,
    metadata = list(project_name = "Example: port operations - which response, and when?",
                    author = "iDPSIR examples",
                    notes = "Didactic example. One window = one season; maintenance dredging campaign in windows 3-5."),
    scenario_state = state, saved_scenarios = saved
  )
  write_savepoint(sp, "docs/example_port.idpsir.json")

  # Figures for the tutorial: the network and the temporal chart of
  # scenarios 3 and 4 (the app's own chart).
  g <- build_igraph(imp$nodes, imp$edges, get_default_dpsir_schema())
  cols <- setNames(sp$schema$color, sp$schema$name)
  cat_order <- sp$schema$name
  cats <- V(g)$dpsir_category
  x <- match(cats, cat_order)
  y <- ave(seq_along(cats), cats, FUN = function(i) seq_along(i) - (length(i) + 1) / 2)
  render_plot_png(function() {
    par(mar = c(0.5, 0.5, 2, 0.5))
    plot(g, layout = cbind(x * 3, -y * 1.6), vertex.shape = "circle", vertex.color = cols[cats], vertex.size = 10,
         vertex.label = V(g)$label, vertex.label.cex = 0.75, vertex.label.dist = 1.7, vertex.label.color = "black",
         vertex.label.degree = pi / 2, edge.color = unname(get_interaction_type_colors()[E(g)$interaction_type]),
         edge.arrow.size = 0.4, edge.width = 1 + 2.5 * E(g)$weight, edge.curved = 0.12,
         main = "Port operations: turbidity and metals groups")
    legend("bottomleft", legend = cat_order, pt.bg = cols[cat_order], pch = 21, pt.cex = 1.6, bty = "n", cex = 0.8)
    legend("bottomright", legend = c("positive (increases)", "negative (decreases)"),
           col = get_interaction_type_colors()[c("positive", "negative")], lwd = 2, bty = "n", cex = 0.8)
  }, "docs/example_port_network.png", width = 1500, height = 950)

  ids <- V(g)$name
  push <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  for (k in 3:4) {
    sc <- saved[[k]]
    tr <- simulate_temporal_pair(g, push(sc$pressure_strengths), push(sc$strengths), windows = 12, stop_rule = "fixed",
                                 mode_D = "window", mode_R = "window", schedule = sc$temporal_schedule)
    tb <- format_temporal_table(g, tr)
    render_plot_png(function() plot_temporal_storyboard(tb, reinforcing_warning = isTRUE(tr$stability$unbounded)),
                    sprintf("docs/example_port_temporal_%d.png", k), width = 1300, height = 800)
  }
  message("Written: data/port_{nodes,edges}.csv, docs/example_port.idpsir.json and figures.")
}
