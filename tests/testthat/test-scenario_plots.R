# =====================================================
# TESTS - R/scenario_plots.R's plot_temporal_storyboard() (Revisao 1: guia
# externo sobre o relatorio como material suplementar, CLAUDE.md)
# =====================================================
#
# O contrato central desta funcao: a cor de cada ponto "Net" vem DIRETO da
# coluna `verdict` que format_temporal_table() (R/temporal.R) ja calculou -
# nunca um novo teste de sinal recomputado aqui. Os testes abaixo verificam
# essa propriedade (todo veredito emitido bate com uma chave da paleta, e
# as cores implicam exatamente o que a legenda promete: verde <=> net <= 0,
# nunca o contrario) contra as tres redes de exemplo do app - sem fixar
# numeros esperados dessas redes (isso ja e' feito em outros arquivos de
# teste), so' a propriedade estrutural cor<->veredito<->sinal.

temporal_df_for <- function(g, p_D, p_R, windows = 6) {
  tr <- simulate_temporal_pair(g, p_D, p_R, windows = windows, mode_D = "permanent", mode_R = "impulse")
  format_temporal_table(g, tr)
}

test_that("every verdict format_temporal_table() emits has a defined color in idpsir_verdict_palette", {
  sp <- read_savepoint("../../docs/example_fisheries.idpsir.json")
  g <- build_igraph(sp$nodes, sp$edges, sp$schema)
  p_R <- build_press_vector(g, active_ids = "R1", strengths = c(R1 = 0.7))
  df <- temporal_df_for(g, build_press_vector(g, active_ids = character(0), strengths = numeric(0)), p_R)

  expect_true(nrow(df) > 0)
  expect_true(all(df$verdict %in% names(idpsir_verdict_palette)))
  expect_false(any(is.na(idpsir_verdict_palette[df$verdict])))
})

test_that("green-mapped verdicts (Neutralized/Improved beyond neutral) only occur when net_impact <= 0, never for a worse-than-baseline row - Mangi fixture", {
  nodes <- data.table::fread("../../data/mangi2007_nodes.csv", data.table = FALSE)
  edges <- data.table::fread("../../data/mangi2007_edges.csv", data.table = FALSE)
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())

  p_D <- build_press_vector(g, active_ids = c("D1", "D3"), strengths = c(D1 = 1, D3 = 1))
  p_R <- build_press_vector(g, active_ids = "R2", strengths = c(R2 = 1))
  df <- temporal_df_for(g, p_D, p_R)

  green_verdicts <- c("Neutralized", "Improved beyond neutral")
  is_green <- df$verdict %in% green_verdicts
  is_red <- df$verdict == "Failure/worsened"

  # Green implies net <= 0 (within the same numeric noise threshold
  # format_temporal_table() itself uses) - the shaded "neutralized zone"
  # in the figure and the legend's "green = <= 0" promise both depend on
  # this holding exactly, not approximately.
  expect_true(all(df$net_impact[is_green] <= 1e-9 + 1e-6))
  # Red (Failure/worsened) implies net >= baseline (never negative, since
  # format_temporal_table() only assigns it when net_impact >= baseline).
  expect_true(all(df$net_impact[is_red] >= df$baseline_impact[is_red] - 1e-6))
  # No verdict string outside the palette's vocabulary leaked through.
  expect_true(all(df$verdict %in% names(idpsir_verdict_palette)))
})

test_that("green-mapped verdicts only occur when net_impact <= 0 - Gnanapragasam fixture (5 Impacts, mixed verdicts across windows)", {
  nodes <- data.table::fread("../../data/gnanapragasam2026_nodes.csv", data.table = FALSE)
  edges <- data.table::fread("../../data/gnanapragasam2026_edges.csv", data.table = FALSE)
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())

  p_D <- build_press_vector(g, active_ids = c("D1", "D2"), strengths = c(D1 = 1, D2 = 1))
  p_R <- build_press_vector(g, active_ids = c("R1", "R2"), strengths = c(R1 = 1, R2 = 1))
  df <- temporal_df_for(g, p_D, p_R, windows = 10)

  is_green <- df$verdict %in% c("Neutralized", "Improved beyond neutral")
  expect_true(any(is_green)) # this fixture is documented to have Fisher income loss dip negative
  expect_true(all(df$net_impact[is_green] <= 1e-9 + 1e-6))
  expect_true(all(df$verdict %in% names(idpsir_verdict_palette)))
})

test_that("plot_temporal_storyboard() draws without error for a single-Impact network", {
  g <- graph_from_data_frame(
    data.frame(from = "S1", to = "I1", weight = 1, confidence = 0.8, interaction_type = "negative", stringsAsFactors = FALSE),
    vertices = data.frame(id = c("S1", "I1"), label = c("S1", "I1"), dpsir_category = c("State", "Impact"), stringsAsFactors = FALSE),
    directed = TRUE
  )
  p_R <- build_press_vector(g, active_ids = "S1", strengths = c(S1 = 1))
  df <- temporal_df_for(g, build_press_vector(g, active_ids = character(0), strengths = numeric(0)), p_R, windows = 4)

  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  expect_no_error(render_plot_png(function() plot_temporal_storyboard(df), tmp, width = 600, height = 500))
  expect_true(file.exists(tmp) && file.info(tmp)$size > 0)
})

test_that("plot_temporal_storyboard() draws without error for a multi-Impact network and a reinforcing_warning caption", {
  nodes <- data.table::fread("../../data/gnanapragasam2026_nodes.csv", data.table = FALSE)
  edges <- data.table::fread("../../data/gnanapragasam2026_edges.csv", data.table = FALSE)
  g <- build_igraph(nodes, edges, get_default_dpsir_schema())

  p_D <- build_press_vector(g, active_ids = c("D1", "D2"), strengths = c(D1 = 1, D2 = 1))
  p_R <- build_press_vector(g, active_ids = c("R1", "R2"), strengths = c(R1 = 1, R2 = 1))
  df <- temporal_df_for(g, p_D, p_R, windows = 8)

  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  expect_no_error(render_plot_png(function() plot_temporal_storyboard(df, reinforcing_warning = TRUE), tmp, width = 1200, height = 800))
  expect_true(file.exists(tmp) && file.info(tmp)$size > 0)
})

test_that("plot_temporal_storyboard() draws a placeholder, not an error, when the graph has no Impact nodes", {
  empty_df <- data.frame(
    id = character(), node = character(), window = integer(),
    baseline_impact = numeric(), net_impact = numeric(), verdict = character(),
    stringsAsFactors = FALSE
  )
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  expect_no_error(render_plot_png(function() plot_temporal_storyboard(empty_df), tmp, width = 400, height = 300))
})
