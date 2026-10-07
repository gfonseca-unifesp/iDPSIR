# =====================================================
# Manuscript v8 - supplementary tables S1 (port), S2 (Kenya), S3 (Sri Lanka)
# =====================================================
#
# For each case, from the savepoints in docs/ through the app's own code:
#   factors   - level, self-regulation, growth, reference level and SD,
#               threshold, Impact class and value;
#   links     - sign, class, beta, band, where the strength comes from,
#               evidence type and reference (for Kenya, the section of the
#               article);
#   scenarios - every pushed factor with its strength, mode and schedule;
#   data needs- the ranked table of step 5 (R/data_needs.R).
# S3 adds the parameter table with sources (data/gnanapragasam2026_parameters.csv).
#
# Run from the repository root:
#   Rscript data-raw/manuscript_supplement.R [out_dir]   (default manuscrito_v8/supplement)
# Writes one CSV per table and one Markdown file per supplement, ready to
# paste into the manuscript's supplementary material. The CSVs of factors
# (S*_factors.csv) and links (S*_links.csv) use the app's import format -
# the same columns as data/*_nodes.csv and data/*_edges.csv - so they load
# with Start -> Import CSV files; the Markdown tables are the readable
# version of the same content.

# The app's import columns, in this order (R/validate.R).
SUP_APP_NODE_COLS <- c("id", "label", "dpsir_category", "subsystem", "self_regulation", "growth_rate", "growth_cap",
                       "reference_value", "sd", "threshold_level", "threshold_direction", "endpoint_class", "value_v", "descriptor")
SUP_APP_EDGE_COLS <- c("from", "to", "interaction_type", "strength_class", "weight", "weight_low", "weight_high",
                       "weight_source", "evidence_type", "reference")

# Factors in the import format: every column the app knows, blank where the
# savepoint has nothing.
sup_app_nodes <- function(x) {
  n <- x$sp$nodes
  out <- as.data.frame(lapply(SUP_APP_NODE_COLS, function(k) if (k %in% names(n)) n[[k]] else NA), stringsAsFactors = FALSE)
  names(out) <- SUP_APP_NODE_COLS
  imp <- out$dpsir_category == "Impact"
  out$endpoint_class[!imp] <- NA; out$value_v[!imp] <- NA
  out$threshold_direction[is.na(out$threshold_level)] <- NA
  out
}

# Links in the import format: a strength that comes from a class or the
# default is written as the class only (weight and band blank), so the app
# derives them exactly as in the savepoint; an entered, r2 or calibrated
# strength is written with its weight, band and source.
sup_app_edges <- function(x) {
  e <- x$sp$edges
  out <- as.data.frame(lapply(SUP_APP_EDGE_COLS, function(k) if (k %in% names(e)) e[[k]] else NA), stringsAsFactors = FALSE)
  names(out) <- SUP_APP_EDGE_COLS
  derived <- out$weight_source %in% c("class", "default")
  out$weight[derived] <- NA; out$weight_low[derived] <- NA; out$weight_high[derived] <- NA
  out
}

sup_load <- function(name, root = ".") {
  sp <- read_savepoint(file.path(root, "docs", paste0(name, ".idpsir.json")))
  list(sp = sp, g = build_igraph(sp$nodes, sp$edges, sp$schema))
}

sup_num <- function(x, digits = 3) ifelse(is.na(x), "", trimws(formatC(x, format = "fg", digits = digits)))

sup_factors <- function(x) {
  n <- x$sp$nodes
  col <- function(k) if (k %in% names(n)) n[[k]] else rep(NA, nrow(n))
  thr <- col("threshold_level")
  imp <- n$dpsir_category == "Impact"
  data.frame(
    id = n$id, factor = n$label, level = n$dpsir_category,
    subsystem = ifelse(is.na(col("subsystem")), "", col("subsystem")),
    self_regulation = sup_num(as.numeric(col("self_regulation"))),
    growth_rate = ifelse(is.na(col("growth_rate")) | as.numeric(col("growth_rate")) == 0, "", sup_num(as.numeric(col("growth_rate")))),
    growth_cap = sup_num(as.numeric(col("growth_cap"))),
    reference_value = sup_num(as.numeric(col("reference_value")), 4),
    sd = sup_num(as.numeric(col("sd")), 4),
    threshold = ifelse(is.na(thr), "", paste0(sup_num(as.numeric(thr), 4), " (", ifelse(is.na(col("threshold_direction")), "auto", col("threshold_direction")), ")")),
    impact_class = ifelse(imp, ifelse(is.na(col("endpoint_class")), "ecological", col("endpoint_class")), ""),
    value_v = ifelse(imp, sup_num(ifelse(is.na(as.numeric(col("value_v"))), 1, as.numeric(col("value_v")))), ""),
    description = ifelse(is.na(col("descriptor")), "", col("descriptor")),
    stringsAsFactors = FALSE)
}

sup_links <- function(x, section = FALSE) {
  e <- x$sp$edges
  lab <- setNames(x$sp$nodes$label, x$sp$nodes$id)
  ref <- ifelse(is.na(e$reference), "", as.character(e$reference))
  out <- data.frame(
    from = unname(lab[e$from]), to = unname(lab[e$to]),
    sign = ifelse(e$interaction_type == "negative", "-", "+"),
    class = ifelse(is.na(e$strength_class), "", e$strength_class),
    beta = sup_num(as.numeric(e$weight)),
    band = paste0(sup_num(as.numeric(e$weight_low)), "-", sup_num(as.numeric(e$weight_high))),
    strength_from = c(class = "class", default = "default", given = "entered", r2 = "r2 (with n)",
                      calibrated = "calibrated", converted = "converted")[as.character(e$weight_source)],
    evidence = ifelse(is.na(e$evidence_type), "", e$evidence_type),
    reference = ref, stringsAsFactors = FALSE)
  if (section) {
    out$section <- ifelse(grepl("section", ref), sub(".*section ([0-9.]+).*", "\\1", ref), "")
    out$reference <- sub(", section [0-9.]+", "", ref)
  }
  out
}

# Every pushed factor of a scenario with its strength, mode and schedule.
# Modes: permanent = added every window; impulse = once; window = from
# `start` for `duration` windows.
sup_scenario_rows <- function(x, sc, scenario_name, n_windows) {
  lab <- setNames(x$sp$nodes$label, x$sp$nodes$id)
  sched <- sc$temporal_schedule
  mode_of <- function(role) sc[[paste0("temporal_mode_", role)]] %||% "permanent"
  one <- function(ids, strengths, role) {
    if (length(ids) == 0) return(NULL)
    md <- mode_of(role)
    st <- du <- rep("", length(ids))
    if (identical(md, "window") && !is.null(sched)) {
      k <- match(ids, sched$id)
      st <- ifelse(is.na(k), "", as.character(sched$start[k]))
      du <- ifelse(is.na(k), "", as.character(sched$duration[k]))
    } else if (identical(md, "permanent")) {
      st <- rep("1", length(ids)); du <- rep(sprintf("all (%s)", n_windows), length(ids))
    } else if (identical(md, "impulse")) {
      st <- rep("1", length(ids)); du <- rep("once", length(ids))
    }
    data.frame(scenario = scenario_name, role = role, factor = unname(lab[ids]), strength_pct = as.numeric(strengths[ids]),
               mode = c(permanent = "every window", impulse = "once", window = "for a period")[[md]],
               start = st, duration = du, stringsAsFactors = FALSE)
  }
  rbind(one(sc$pressure_active, sc$pressure_strengths, "pressure"), one(sc$active, sc$strengths, "response"))
}

sup_scenarios <- function(x, n_windows) {
  sv <- x$sp$saved_scenarios
  if (length(sv) == 0) {
    ss <- x$sp$scenario_state
    sc <- list(pressure_active = ss$pressure_active, pressure_strengths = ss$pressure_strengths,
               active = ss$response_active, strengths = ss$response_strengths,
               temporal_mode_pressure = ss$temporal_mode_pressure, temporal_mode_response = ss$temporal_mode_response,
               temporal_schedule = ss$temporal_schedule)
    return(sup_scenario_rows(x, sc, "Published scenario, 2005-2030", n_windows))
  }
  do.call(rbind, lapply(sv, function(sc) sup_scenario_rows(x, sc, sc$name, n_windows)))
}

sup_data_needs <- function(x, sc, temporal = FALSE) {
  ids <- igraph::V(x$g)$name
  pv <- function(v) { p <- setNames(rep(0, length(ids)), ids); p[names(v)] <- v / 100; p }
  dn <- data_needs(x$g, list(p_D = pv(sc$pressure_strengths[sc$pressure_active %||% names(sc$pressure_strengths)]),
                             press = pv(sc$strengths %||% sc$response_strengths)), temporal = temporal)
  format_data_needs(dn)
}

# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------
sup_md_table <- function(df, caption) {
  esc <- function(v) gsub("\\|", "\\\\|", ifelse(is.na(v), "", as.character(v)))
  head <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  body <- apply(df, 1, function(r) paste0("| ", paste(esc(r), collapse = " | "), " |"))
  c(paste0("**", caption, "**"), "", head, sep, body, "")
}

sup_rename <- function(df, map) { names(df) <- ifelse(names(df) %in% names(map), map[names(df)], names(df)); df }
SUP_FACTOR_NAMES <- c(id = "Id", factor = "Factor", level = "DPSIR level", subsystem = "Subsystem", self_regulation = "Self-regulation",
                      growth_rate = "Growth rate", growth_cap = "Growth cap", reference_value = "Reference level", sd = "SD",
                      threshold = "Threshold (direction)", impact_class = "Impact class", value_v = "Value v", description = "Description")
SUP_LINK_NAMES <- c(from = "From", to = "To", sign = "Sign", class = "Class", beta = "Strength (beta)", band = "Band",
                    strength_from = "Strength from", evidence = "Evidence type", reference = "Reference", section = "Article section")
SUP_SCEN_NAMES <- c(scenario = "Scenario", role = "Push", factor = "Factor", strength_pct = "Strength (%)", mode = "Mode",
                    start = "Start (window)", duration = "Duration (windows)")

# The savepoints of each case, copied into the supplement as S<k>_<name>:
# loading one (Start -> Load savepoint) brings the network with its sources,
# saved scenarios and temporal settings, and recomputes every result.
SUP_SAVEPOINTS <- list(
  S1 = c("example_port"),
  S2 = c("example_mangi", "example_mangi_default"),
  S3 = c("example_gnanapragasam", "example_gnanapragasam_default", "example_gnanapragasam_noaidfleet")
)

manuscript_supplement <- function(root = ".", out_dir = "manuscrito_v8/supplement") {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  for (k in names(SUP_SAVEPOINTS)) for (nm in SUP_SAVEPOINTS[[k]]) {
    file.copy(file.path(root, "docs", paste0(nm, ".idpsir.json")), file.path(out_dir, sprintf("%s_%s.idpsir.json", k, nm)),
              overwrite = TRUE)
  }
  w <- function(df, f) utils::write.csv(df, file.path(out_dir, f), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  # Factors and links go out in the app's import format; the readable
  # versions are the Markdown tables.
  w_case <- function(tabs, x, prefix) {
    for (k in names(tabs)) {
      df <- switch(k, factors = sup_app_nodes(x), links = sup_app_edges(x), tabs[[k]])
      w(df, sprintf("%s_%s.csv", prefix, k))
    }
  }

  # ---- S1, port ----
  port <- sup_load("example_port", root)
  s1 <- list(factors = sup_factors(port), links = sup_links(port), scenarios = sup_scenarios(port, 12),
             data_needs = sup_data_needs(port, port$sp$saved_scenarios[[2]]))
  w_case(s1, port, "S1_port")
  md <- c("# Supplementary Material S1. Port (hypothetical case, Section 5.1)", "",
          "Savepoint: `S1_example_port.idpsir.json` (in the repository, `docs/example_port.idpsir.json`, built by `data-raw/port_build.R`): load it with Start -> Load savepoint to get the network and the four scenarios. Network only, as CSV: `S1_port_factors.csv` and `S1_port_links.csv` (Start -> Import CSV files). One window = one season; 12 windows. All strengths are classes (weak 0.15, moderate 0.45, strong 0.80), with the class band.", "",
          sup_md_table(sup_rename(s1$factors, SUP_FACTOR_NAMES), "Table S1.1. Factors."),
          sup_md_table(sup_rename(s1$links, SUP_LINK_NAMES), "Table S1.2. Links."),
          sup_md_table(sup_rename(s1$scenarios, SUP_SCEN_NAMES), "Table S1.3. The four scenarios and the schedule of each factor (windows = seasons; the dredging campaign is windows 3-5)."),
          sup_md_table(s1$data_needs, "Table S1.4. Data needs, scenario 2 (+ runoff treatment), static reading."))
  writeLines(md, file.path(out_dir, "S1_port.md"), useBytes = TRUE)

  # ---- S2, Kenya ----
  ken <- sup_load("example_mangi", root)
  s2 <- list(factors = sup_factors(ken), links = sup_links(ken, section = TRUE), scenarios = sup_scenarios(ken, 30),
             data_needs = sup_data_needs(ken, ken$sp$saved_scenarios[[1]]))
  s2$links <- s2$links[, c("from", "to", "sign", "class", "beta", "band", "strength_from", "evidence", "section", "reference")]
  w_case(s2, ken, "S2_kenya")
  md <- c("# Supplementary Material S2. Kenyan reef fishery, rebuilt from Mangi et al. (2007) (Section 5.2)", "",
          "Savepoints: `S2_example_mangi.idpsir.json` (in the repository, `docs/example_mangi.idpsir.json`, built by `data-raw/mangi2007_build.R`) and its first-run version `S2_example_mangi_default.idpsir.json` (`data-raw/first_run_build.R`): load them with Start -> Load savepoint. Network only, as CSV: `S2_kenya_factors.csv` and `S2_kenya_links.csv` (Start -> Import CSV files). One window = one year. The article gives no link strengths: every strength is a class. The only number taken from the article is the coastal population growth of 3.7% per year. Each link cites the section of Mangi et al. (2007), doi:10.1016/j.ocecoaman.2006.10.003.", "",
          sup_md_table(sup_rename(s2$factors, SUP_FACTOR_NAMES), "Table S2.1. Factors."),
          sup_md_table(sup_rename(s2$links, SUP_LINK_NAMES), "Table S2.2. Links, with the section of the article each comes from."),
          sup_md_table(sup_rename(s2$scenarios, SUP_SCEN_NAMES), "Table S2.3. The four scenarios (every push acts in every window; the temporal reading of scenario 4 runs 30 years)."),
          sup_md_table(s2$data_needs, "Table S2.4. Data needs, scenario 1 (existing measures, as written), static reading."))
  writeLines(md, file.path(out_dir, "S2_kenya.md"), useBytes = TRUE)

  # ---- S3, Sri Lanka ----
  sl <- sup_load("example_gnanapragasam", root)
  sl0 <- sup_load("example_gnanapragasam_default", root)
  par <- utils::read.csv(file.path(root, "data/gnanapragasam2026_parameters.csv"), stringsAsFactors = FALSE)
  ss0 <- sl0$sp$scenario_state
  s3 <- list(parameters = par, factors = sup_factors(sl), links = sup_links(sl), schedule = sup_scenarios(sl, 26),
             data_needs = sup_data_needs(sl0, list(pressure_active = ss0$pressure_active, pressure_strengths = ss0$pressure_strengths,
                                                   strengths = ss0$response_strengths), temporal = TRUE))
  w_case(s3, sl, "S3_srilanka")
  md <- c("# Supplementary Material S3. Sri Lankan small-scale fishery, parameterized from Gnanapragasam et al. (2026) (Section 5.3)", "",
          "Savepoints (Start -> Load savepoint): `S3_example_gnanapragasam.idpsir.json` (published network and scenario, 2005-2030; in the repository `docs/example_gnanapragasam.idpsir.json`, built by `data-raw/gnanapragasam2026_build.R`), `S3_example_gnanapragasam_default.idpsir.json` (first run) and `S3_example_gnanapragasam_noaidfleet.idpsir.json` (variant without aid -> fleet). Network only, as CSV: `S3_srilanka_factors.csv` and `S3_srilanka_links.csv` (Start -> Import CSV files). One window = one year; window 0 = 2004. Observed effort: `data/gnanapragasam2026_effort_observed.csv`. The fit of the two aid strengths, the out-of-sample test and the comparison of networks are described in Supplement S7.", "",
          sup_md_table(sup_rename(s3$parameters, c(item = "Item", value = "Value", source = "Source")), "Table S3.1. Parameters and sources."),
          sup_md_table(sup_rename(s3$factors, SUP_FACTOR_NAMES), "Table S3.2. Factors."),
          sup_md_table(sup_rename(s3$links, SUP_LINK_NAMES), "Table S3.3. Links and the source of each strength."),
          sup_md_table(sup_rename(s3$schedule, SUP_SCEN_NAMES), "Table S3.4. Scenario: the pressure and the schedule of the aid programmes, the effort quota and the fight against illegal trawling (window 1 = 2005)."),
          sup_md_table(s3$data_needs, "Table S3.5. Data needs of the first run (every setting at its default), temporal reading on."))
  writeLines(md, file.path(out_dir, "S3_srilanka.md"), useBytes = TRUE)
  invisible(list(S1 = s1, S2 = s2, S3 = s3))
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  out_dir <- if (length(args) >= 1) args[1] else "manuscrito_v8/supplement"
  setwd("tests/testthat"); suppressMessages(suppressWarnings(source("helper-setup.R"))); setwd("../..")
  r <- manuscript_supplement(out_dir = out_dir)
  for (s in names(r)) for (k in names(r[[s]])) message(sprintf("%s %s: %d rows", s, k, nrow(r[[s]][[k]])))
}
