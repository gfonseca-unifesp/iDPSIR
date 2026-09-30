# =====================================================
# Gnanapragasam et al. 2026 example network - build script
# =====================================================
#
# Gnanapragasam, K., Ratnasiri, S., Fleming, C. (2026). Sustainable
# small-scale fisheries development: Integrating bioeconomic and DPSIR models
# for policy insights. Marine Policy 189, 107095.
# https://doi.org/10.1016/j.marpol.2026.107095 (CC BY 4.0)
#
# Writes, from the parameter table below:
#   data/gnanapragasam2026_nodes.csv
#   data/gnanapragasam2026_edges.csv
#   data/gnanapragasam2026_parameters.csv   (every value and its source)
#   data/gnanapragasam2026_effort_observed.csv (Fig. 4, digitized)
#
# Run from the repository root:  Rscript data-raw/gnanapragasam2026_build.R
#
# Conventions (see the README section "Sri Lanka example: how it was
# parametrized"):
# - One window = one year. Window 0 = 2004 (before the tsunami aid); the
#   reference values are 2004 levels, so window 1 = 2005 ... window 17 = 2021.
# - The model works in standard deviations (SD). Effort's SD is the SD of the
#   1990-2021 series (Fig. 4), the same sample the article's standardized
#   relationships were estimated on.
# - Fish stock (biomass) values come from the article's Gordon-Schaefer
#   model: B_MSY = 1.5 x H_MSY = 345 kt, so K = 690 kt and, at equilibrium,
#   B(E) = K (1 - E / E_max) with E_max = 2 x E_MSY = 30,924 thousand kW-days
#   (this reproduces Table 4: 5% cut -> 339.6 kt). Hence
#   SD_B = (K / E_max) x SD_E and the intrinsic rate r = 4 H_MSY / K = 1.33/yr.
# - The stock threshold is B_MSY = 345 kt (article): below it the stock is
#   overfished and its effects on catch, income and conflict switch on. The
#   usual limit reference point B_lim = 0.5 B_MSY = 172.5 kt (a management
#   convention, not in the article) was tried first: it is never crossed at
#   realistic levels, so the stock would never reach its Impacts.
# - In the temporal engine an edge passes beta per window and a node with
#   self-regulation sr settles at beta / sr times the static effect. States
#   whose relationships are equilibria (Schaefer biomass, % motorized) keep
#   sr = 1, so the temporal and static readings agree; stocks that genuinely
#   accumulate (the fleet, whose boats persist) keep a low sr.

effort_obs <- data.frame(
  year = 1990:2021,
  total_effort_kwdays_1000 = c(
    7181, 7353, 6493, 6263, 6550, 6378, 6263, 6321, 5919, 6493, 6550, 6435, 6665, 7984, 8328, 2764,
    10106, 11024, 11024, 12516, 13720, 16588, 16703, 16703, 17334, 17277, 17506, 16130, 17334, 16818, 16703, 16531
  )
)

# Derived quantities -----------------------------------------------------
H_MSY <- 230.113            # kt (Table 3)
E_MSY <- 15462              # thousand kW-days (Table 3)
B_MSY <- 1.5 * H_MSY        # kt (article, section 3.5.1)
K <- 2 * B_MSY
E_max <- 2 * E_MSY
r_int <- 4 * H_MSY / K
sd_E <- sd(effort_obs$total_effort_kwdays_1000)
E_2004 <- effort_obs$total_effort_kwdays_1000[effort_obs$year == 2004]
B_eq <- function(E) K * (1 - E / E_max)
sd_B <- K / E_max * sd_E
B_2004 <- B_eq(E_2004)
B_mid <- B_eq(mean(effort_obs$total_effort_kwdays_1000[effort_obs$year >= 2004]))
sr_stock <- 1 - exp(-r_int * B_mid / K)   # discrete-year recovery at the 2004-2021 mean level
B_lim <- 0.5 * B_MSY

# Calibrated aid strengths, fitted by least squares to the observed effort
# 2006-2021 (analysis/validation_srilanka/calibrate.R, calibrate_aid(); that
# fit gives 0.342 and 0.089, R2 = 0.93); values fixed here, rounded, so the
# build is deterministic. The out-of-sample test (fit 2006-2014, predict
# 2015-2021) is analysis/validation_srilanka/validate.R.
BETA_R1_D3 <- 0.345
BETA_R2_D3 <- 0.085

nodes <- data.frame(
  id = c("D1", "D2", "D3", "D4", "P1", "P2", "S1", "S2", "I1", "I2", "I3", "I4", "I5", "R1", "R2", "R3", "R4"),
  label = c(
    "Coastal population", "Per-capita fish demand", "Fleet capacity (boats x power)", "Indian trawler incursions",
    "Fishing effort", "Illegal bottom trawling", "Fish stock (biomass)", "Fleet motorization (% motorized)",
    "Catch decline", "Fisher income loss", "Conflict with Indian fishermen", "Traditional fishing decline",
    "Loss of traditional fishing culture",
    "Post-tsunami aid (2005-2009)", "Post-war aid (2010-2012)", "Effort-based quota", "Combating poaching"
  ),
  dpsir_category = c("Driver", "Driver", "Driver", "Driver", "Pressure", "Pressure", "State", "State",
                     "Impact", "Impact", "Impact", "Impact", "Impact", "Response", "Response", "Response", "Response"),
  subsystem = "Sri Lanka small-scale fisheries",
  self_regulation = c(0.5, 1, 0.02, 1, 1, 1, 1, 1, 1, 1, 0.5, 0.5, 0.3, 1, 1, 1, 1),
  growth_rate = c(0.008, 0.023, 0.01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
  growth_cap = c(NA, 31, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA),
  reference_value = c(19.4, round(31 / 2^(12 / 30), 1), E_2004, NA, E_2004, NA, round(B_2004, 1), 40, NA, NA, NA, NA, NA, NA, NA, NA, NA),
  sd = c(NA, NA, round(sd_E), NA, round(sd_E), NA, round(sd_B, 1), 15.5, NA, NA, NA, NA, NA, NA, NA, round(sd_E), NA),
  threshold_level = c(NA, NA, NA, NA, NA, NA, round(B_MSY, 1), NA, NA, NA, NA, NA, NA, NA, NA, NA, NA),
  threshold_direction = c(NA, NA, NA, NA, NA, NA, "auto", NA, NA, NA, NA, NA, NA, NA, NA, NA, NA),
  endpoint_class = c(rep(NA, 8), "service", "welfare", "welfare", "welfare", "welfare", rep(NA, 4)),
  value_v = c(rep(NA, 8), 1, 1, 0.6, 0.5, 0.5, rep(NA, 4)),
  descriptor = c(
    "Population of Sri Lanka, millions (base-level trend only).",
    "Fish consumption per person, kg/yr; doubled in three decades and peaked at 31 kg in 2016.",
    "Fishing capacity of the fleet, in the same units as effort (thousand kW-days/yr).",
    "Transboundary incursions by Indian bottom trawlers (qualitative in the article).",
    "Standardized fishing effort, thousand kW-days/yr (Fig. 4).",
    "Fishing pressure from illegal (mostly Indian) bottom trawling.",
    "Fish biomass, kt; Gordon-Schaefer equilibrium with the article's MSY benchmarks.",
    "Share of motorized boats in the fleet, %; 40% before the tsunami, 60% now.",
    "Loss of catch (in 2021 the catch equals pre-tsunami levels with twice the effort).",
    "Loss of fishers' income.",
    "Conflicts with Indian fishers (arrests, lost fishing grounds).",
    "Decline of the non-motorized traditional fleet.",
    "Erosion of traditional practices and local ecological knowledge.",
    "Boats and gear given to rebuild livelihoods after the 2004 tsunami (article: +23% boats by 2008).",
    "Second wave of boats and gear after the end of the civil war in 2009.",
    "Effort-based quota: 5% (MSY) to 25% (MEY) cut, via buybacks or fishing-free days (Table 4).",
    "Joint patrols, surveillance and penalties against illegal trawling."
  ),
  stringsAsFactors = FALSE
)

ref_article <- "Gnanapragasam et al. 2026, Marine Policy 189:107095"
r2_band <- band_from_r2 <- function(r2, n) {
  b <- sqrt(r2); se <- sqrt((1 - r2) / (n - 2)); round(c(max(0, b - 1.96 * se), b + 1.96 * se), 3)
}
b_cpue <- r2_band(0.68, 32)

edges <- data.frame(
  from = c("D1", "D2", "D3", "D4", "P1", "P1", "P2", "S1", "S1", "S1", "S2", "S2", "S2", "S2",
           "R1", "R1", "R2", "R2", "R3", "R4"),
  to   = c("P1", "P1", "P1", "P2", "S1", "S2", "S1", "I1", "I2", "I3", "I1", "I3", "I4", "I5",
           "D3", "I2", "D3", "I2", "P1", "D4"),
  weight = c(NA, NA, 0.85, NA, round(sqrt(0.68), 3), 0.75, NA, NA, NA, NA, NA, NA, NA, NA,
             BETA_R1_D3, NA, BETA_R2_D3, NA, 1, NA),
  weight_low = c(NA, NA, 0.75, NA, b_cpue[1], NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, 0.9, NA),
  weight_high = c(NA, NA, 0.95, NA, b_cpue[2], NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, 1.0, NA),
  strength_class = c("weak", "moderate", NA, "strong", NA, NA, "moderate", "strong", "moderate", "moderate",
                     "moderate", "weak", "strong", "moderate", NA, "moderate", NA, "moderate", NA, "moderate"),
  weight_source = c("class", "class", "given", "class", "r2", "calibrated", "class", "class", "class", "class",
                    "class", "class", "class", "class", "calibrated", "class", "calibrated", "class", "given", "class"),
  interaction_type = c("positive", "positive", "positive", "positive", "negative", "positive", "negative",
                       "negative", "negative", "negative", "positive", "positive", "positive", "positive",
                       "positive", "negative", "positive", "negative", "negative", "negative"),
  evidence_type = c("literature", "literature", "definition", "literature", "regression", "calibration", "literature",
                    "expert_assessment", "expert_assessment", "literature", "literature", "expert_assessment",
                    "literature", "literature", "calibration", "literature", "calibration", "literature",
                    "definition", "literature"),
  reference = ref_article,
  stringsAsFactors = FALSE
)

params <- data.frame(
  item = c(
    "Window length", "Window 0",
    "Effort SD (P1, D3, R3 units)", "Effort in 2004 (reference, P1 and D3)",
    "Fishing effort -> Fish stock (beta)", "Fishing effort -> Fish stock (band)",
    "Carrying capacity K", "Intrinsic growth r", "Fish stock in 2004 (reference)", "Fish stock SD",
    "Fish stock self-regulation", "Fish stock threshold (B_MSY)",
    "Coastal population growth", "Coastal population in 2004",
    "Per-capita demand growth", "Per-capita demand ceiling", "Per-capita demand in 2004",
    "Fleet capacity growth", "Fleet capacity self-regulation",
    "Post-tsunami aid -> Fleet capacity", "Post-war aid -> Fleet capacity",
    "Aid periods", "Fleet capacity -> Fishing effort",
    "Fleet motorization in 2004 / SD", "Effort-based quota -> Fishing effort",
    "Quota size", "Flow factors' self-regulation", "Other edge strengths"
  ),
  value = c(
    "1 year", "2004",
    sprintf("%.0f thousand kW-days", sd_E), sprintf("%.0f thousand kW-days", E_2004),
    sprintf("-%.3f", sqrt(0.68)), sprintf("%.3f - %.3f", b_cpue[1], b_cpue[2]),
    sprintf("%.0f kt", K), sprintf("%.2f per year", r_int), sprintf("%.1f kt", B_2004), sprintf("%.1f kt", sd_B),
    "1", sprintf("%.1f kt (falling)", B_MSY),
    "0.8% per year", "19.4 million",
    "2.3% per year", "31 kg per person", sprintf("%.1f kg per person", 31 / 2^(12 / 30)),
    "1% per year", "0.02",
    sprintf("%.2f", BETA_R1_D3), sprintf("%.2f", BETA_R2_D3),
    "2005-2009 (windows 1-5); 2010-2012 (windows 6-8)", "0.85 (band 0.75 - 0.95)",
    "40% / 15.5 points", "1 (definitional)",
    "5% of 2021 effort = 827; 25% = 4,133 thousand kW-days", "1 (no memory)", "classes weak 0.15 / moderate 0.45 / strong 0.80"
  ),
  source = c(
    "Annual statistics (article, 1990-2021)", "Last year before the post-tsunami aid",
    "SD of the 1990-2021 series digitized from Fig. 4 (vector figure)", "Fig. 4 (digitized)",
    "sqrt(R2 = 0.68), CPUE vs effort (section 3.3); sign: more effort, less stock", "95% interval of beta from R2 and n = 32 years",
    "2 x B_MSY; B_MSY = 1.5 x H_MSY (section 3.5.1, Table 3)", "4 x H_MSY / K (Gordon-Schaefer)",
    "Equilibrium K (1 - E / E_max) at the 2004 effort; reproduces Table 4", "(K / E_max) x effort SD",
    sprintf("Biomass taken at its Schaefer equilibrium each year (r = %.2f/yr: recovery rate r B / K about %.2f/yr); sr = 1 keeps the temporal equilibrium equal to B(E)", r_int, r_int * B_mid / K),
    "B_MSY = 1.5 x H_MSY (article). B_lim = 0.5 B_MSY (convention) was tested and is never crossed",
    "External (national statistics), not in the article", "External (national statistics), not in the article",
    "Consumption doubled over three decades (section 3.1, Fig. 5)", "Peak of 31 kg in 2016 (section 3.1)",
    "31 kg discounted at 2.3%/yr back to 2004",
    "Effort trend 1990-2004 (Fig. 4), before the aid", "Boats persist; effort stayed on a plateau after the aid (Fig. 4)",
    "Fitted with the post-war aid by least squares to Fig. 4, 2006-2021 (R2 = 0.93; a common value fits worse, R2 = 0.84)", "Fitted with the post-tsunami aid (same fit)",
    "Section 3.1 and Fig. 6", "Effort = boat power x fishing days (section 2.2.1): capacity sets effort; kept below 0.9 so the three drivers of effort explain at most 100% of its variation",
    "Fleet split 60:40 non-motorized before 2004, 60:40 motorized now (section 3.4); SD calibrated to that rise",
    "The quota cuts effort directly, in effort units", "Table 4 (5% = MSY, 25% = MEY)",
    "Effort, demand, catch and income are flows, not stocks", "Qualitative links (section 3, Table 2)"
  ),
  stringsAsFactors = FALSE
)

if (sys.nframe() == 0) {
  utils::write.csv(nodes, "data/gnanapragasam2026_nodes.csv", row.names = FALSE, na = "")
  utils::write.csv(edges, "data/gnanapragasam2026_edges.csv", row.names = FALSE, na = "")
  utils::write.csv(params, "data/gnanapragasam2026_parameters.csv", row.names = FALSE)
  utils::write.csv(effort_obs, "data/gnanapragasam2026_effort_observed.csv", row.names = FALSE)
  message("Written: data/gnanapragasam2026_{nodes,edges,parameters,effort_observed}.csv")
}

# Savepoint with the preset scenario (needs the app's R/ sources; run from the
# repository root after the CSVs above):
#   pressure  - Indian trawler incursions, every window;
#   responses - post-tsunami aid (windows 1-5), post-war aid (6-8), and from
#               2022 (window 18, 13 windows) the effort quota at 85% of one
#               effort SD (= 4,145 thousand kW-days, about 25% of 2021
#               effort, the MEY cut) plus combating poaching;
#   26 windows (2005-2030).
build_example_savepoint <- function(path = "docs/example_gnanapragasam.idpsir.json") {
  imp <- import_matrices("data/gnanapragasam2026_nodes.csv", "data/gnanapragasam2026_edges.csv", convert_legacy = FALSE)
  scenario_state <- list(
    pressure_active = "D4", pressure_strengths = c(D4 = 100),
    response_active = c("R1", "R2", "R3", "R4"),
    response_strengths = c(R1 = 100, R2 = 100, R3 = 85, R4 = 100),
    temporal_mode_pressure = "permanent", temporal_mode_response = "window",
    temporal_stop_rule = "fixed", temporal_windows = 26, temporal_max_windows = 50,
    temporal_tol_rel = 5, baseline_without_response = FALSE, temporal_gate_mode = "state_level",
    temporal_trends_outside = TRUE, temporal_continue_after = 0,
    temporal_schedule = data.frame(id = c("R1", "R2", "R3", "R4"), start = c(1, 6, 18, 18), duration = c(5, 3, 13, 13))
  )
  sp <- build_savepoint(
    get_default_dpsir_schema(), imp$nodes, imp$edges,
    metadata = list(
      project_name = "Example: Sri Lanka small-scale fisheries (Gnanapragasam et al. 2026)",
      author = "iDPSIR examples",
      notes = "Window = 1 year, window 0 = 2004. Parameters and sources: data/gnanapragasam2026_parameters.csv."
    ),
    scenario_state = scenario_state
  )
  write_savepoint(sp, path)
  invisible(path)
}
